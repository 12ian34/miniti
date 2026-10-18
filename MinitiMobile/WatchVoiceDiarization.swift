import AVFoundation
import FluidAudio
import Foundation

/// Watch recordings diarised on the phone (voice prints slice 3): run the on-device speaker
/// model over the joined file, give Deepgram's words the local speaker labels, and name the
/// speakers from the stored voice prints. Skipped when the on-device diarizer is off, not
/// loaded, or busy with a live meeting; the Deepgram labels then stand.
@MainActor
enum WatchVoiceDiarization {
    struct Outcome {
        var segments: [WatchTranscriptionClient.TranscriptSegmentDraft]
        var speakerNames: [String: String] = [:]
        var speakerEmails: [String: String] = [:]
        var selfSpeakerIDs: Set<Int> = []
    }

    static func relabel(fileURL: URL, result: WatchTranscriptionClient.Result, appState: AppState) async -> Outcome? {
        let diarization = appState.onDeviceDiarization
        guard appState.onDeviceSpeakerSeparationEnabled, diarization.isReady, diarization.activeTimeline == nil else { return nil }
        guard result.segments.contains(where: { !$0.words.isEmpty }) else { return nil }
        let samples: [Float]
        do {
            samples = try AudioConverter(sampleRate: 16_000).resampleAudioFile(fileURL)
        } catch {
            DebugLogger.shared.log(.audio, "Watch diarization: could not decode audio: \(error.localizedDescription)")
            return nil
        }
        guard !samples.isEmpty else { return nil }
        let collector = appState.makeVoicePrintCollector()
        guard let timeline = diarization.beginSession(sources: [.microphone], collector: collector) else { return nil }
        let chunk = 16_000
        var offset = 0
        var first = true
        while offset < samples.count {
            let end = min(samples.count, offset + chunk)
            diarization.ingest(samples: Array(samples[offset..<end]), source: .microphone)
            if first { timeline.markSocketStart(); first = false }
            offset = end
            // Keep the main actor responsive for a long file.
            if offset % (chunk * 30) == 0 { await Task.yield() }
        }
        await diarization.endSessionAndWait()
        if let collector { await collector.finish() }

        // Words to local speakers, splitting an utterance where the local label changes.
        var segments: [WatchTranscriptionClient.TranscriptSegmentDraft] = []
        var labelled = 0
        for segment in result.segments {
            var runs: [(slot: Int, words: [WatchTranscriptionClient.WordTiming])] = []
            var lastKnown = segment.speaker
            for word in segment.words {
                let slot = timeline.lookup(source: .microphone, socketStart: word.start, socketEnd: word.end)?.providerSpeaker ?? lastKnown
                lastKnown = slot
                if let last = runs.indices.last, runs[last].slot == slot {
                    runs[last].words.append(word)
                } else {
                    runs.append((slot, [word]))
                }
            }
            if runs.isEmpty {
                segments.append(segment)
                continue
            }
            labelled += 1
            for run in runs {
                segments.append(WatchTranscriptionClient.TranscriptSegmentDraft(
                    text: run.words.map(\.word).joined(separator: " "), speaker: run.slot,
                    timestamp: run.words[0].start, confidence: segment.confidence, words: run.words
                ))
            }
        }
        var outcome = Outcome(segments: segments)

        // Names from prints.
        if let collector, appState.voicePrintsWanted {
            let prints = appState.voicePrints.prints.filter { ($0.isSelf && appState.voicePrintSelfEnabled) || (!$0.isSelf && appState.voicePrintOthersEnabled) }
            let voices = collector.snapshot().filter { $0.source == .microphone }
            let candidates = voices.map { VoicePrintMatcher.Candidate(speakerID: $0.slot, vector: $0.vector, speechSeconds: $0.speechSeconds) }
            for match in VoicePrintMatcher.assign(candidates: candidates, prints: prints) where match.isConfident {
                if match.print.isSelf {
                    outcome.selfSpeakerIDs.insert(match.speakerID)
                } else {
                    outcome.speakerNames[String(match.speakerID)] = match.print.displayName
                    if let email = match.print.email { outcome.speakerEmails[String(match.speakerID)] = email }
                }
                if let voice = voices.first(where: { $0.slot == match.speakerID }), voice.speechSeconds >= VoicePrintMatcher.learnMinimumSeconds {
                    appState.voicePrints.merge(key: match.print.key, displayName: match.print.displayName, email: match.print.email,
                                               vector: voice.vector, speechSeconds: voice.speechSeconds)
                }
            }
        }
        DebugLogger.shared.log(.audio, "Watch diarization: \(labelled) of \(result.segments.count) utterances relabelled, \(outcome.speakerNames.count) named, self=\(outcome.selfSpeakerIDs.sorted())")
        return outcome
    }
}
