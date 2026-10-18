import Foundation

/// A print that resembles a live speaker but not confidently enough to apply on its own.
struct VoicePrintSuggestion: Equatable, Sendable {
    let printKey: String
    let displayName: String
    let email: String?
    let similarity: Float
}

/// Voice prints (3.2.0): recognise the person using miniti and remembered attendees by voice
/// across meetings. Everything runs on the on-device diarizer's slots; Deepgram's diarizer gives
/// no embeddings, so with it in charge nothing here fires. See docs/voice-prints-plan.md.
extension AppState {
    /// Either print setting on, and the on-device diarizer selected.
    var voicePrintsWanted: Bool {
        (voicePrintSelfEnabled || voicePrintOthersEnabled) && onDeviceSpeakerSeparationEnabled
    }

    /// Load or drop the embedding model to match the settings. Called at launch and on change.
    func refreshVoicePrintAvailability() {
        guard !ScreenshotMode.isActive else { return }
        if voicePrintsWanted {
            voicePrintEmbedder.prepare()
        } else {
            voicePrintEmbedder.unload()
        }
    }

    /// A collector for the session about to start, or nil when prints are off or the model is not loaded.
    func makeVoicePrintCollector() -> VoicePrintCollector? {
        guard voicePrintsWanted, let embed = voicePrintEmbedder.embedFunction() else { return nil }
        return VoicePrintCollector(embed: embed)
    }

    /// Slot voices of the live session translated to app speaker ids.
    private func liveVoiceCandidates() -> [VoicePrintMatcher.Candidate] {
        guard let collector = onDeviceDiarization.activeCollector, let map = deepgramService?.onDeviceSpeakerMap else { return [] }
        return collector.snapshot().compactMap { voice in
            guard let appID = map[voice.source]?[voice.slot] else { return nil }
            return VoicePrintMatcher.Candidate(speakerID: appID, vector: voice.vector, speechSeconds: voice.speechSeconds)
        }
    }

    /// Compare the live speakers with the stored prints. Cheap; throttled to every 15 s.
    func voicePrintMatchTick(now: Date = Date()) {
        guard voicePrintsWanted, isRecording, onDeviceDiarization.activeCollector != nil else { return }
        if let last = lastVoicePrintMatchAt, now.timeIntervalSince(last) < 15 { return }
        lastVoicePrintMatchAt = now
        let prints = voicePrints.prints.filter { ($0.isSelf && voicePrintSelfEnabled) || (!$0.isSelf && voicePrintOthersEnabled) }
        guard !prints.isEmpty else { return }
        let matches = VoicePrintMatcher.assign(candidates: liveVoiceCandidates(), prints: prints)
        for match in matches {
            let key = String(match.speakerID)
            if match.isConfident {
                applyVoicePrintMatch(match)
            } else if !livePrintMatchedIDs.contains(key), !liveSpeakerOverrides.contains(key) {
                let suggestion = VoicePrintSuggestion(printKey: match.print.key, displayName: match.print.isSelf ? "You" : match.print.displayName,
                                                      email: match.print.email, similarity: match.similarity)
                if livePrintSuggestions[key] != suggestion {
                    livePrintSuggestions[key] = suggestion
                    DebugLogger.shared.log(.app, "Voice print suggestion: id=\(key) \(suggestion.displayName) \(String(format: "%.2f", match.similarity))")
                }
            }
        }
    }

    private func applyVoicePrintMatch(_ match: VoicePrintMatcher.Match) {
        let key = String(match.speakerID)
        guard !liveSpeakerOverrides.contains(key) else { return }
        livePrintSuggestions.removeValue(forKey: key)
        if match.print.isSelf {
            if !effectiveLiveSelfSpeakerIDs.contains(match.speakerID) || liveSelfSpeakerIDs.isEmpty {
                setLiveSelfSpeaker(id: match.speakerID, isSelf: true)
                DebugLogger.shared.log(.app, "Voice print: id=\(key) is you (\(String(format: "%.2f", match.similarity)))")
            }
        } else if liveSpeakerNames[key] != match.print.displayName {
            var names = liveSpeakerNames
            names[key] = match.print.displayName
            liveSpeakerNames = names
            if let meeting = currentMeeting {
                meeting.speakerNames = names
                if let email = match.print.email {
                    var emails = meeting.speakerEmails
                    emails[key] = email
                    meeting.speakerEmails = emails
                }
                saveCurrentMeetingIfNeeded()
            }
            DebugLogger.shared.log(.app, "Voice print: id=\(key) is \(match.print.displayName) (\(String(format: "%.2f", match.similarity)))")
        }
        livePrintMatchedIDs.insert(key)
    }

    /// The person confirmed a suggestion from the rename sheet.
    func confirmVoicePrintSuggestion(speakerID: Int) {
        let key = String(speakerID)
        guard let suggestion = livePrintSuggestions[key], let print = voicePrints.print(for: suggestion.printKey) else { return }
        applyVoicePrintMatch(VoicePrintMatcher.Match(speakerID: speakerID, print: print, similarity: VoicePrintMatcher.matchThreshold))
    }

    func dismissVoicePrintSuggestion(speakerID: Int) {
        livePrintSuggestions.removeValue(forKey: String(speakerID))
    }

    /// Capture what this meeting taught us. Call before the diarization session ends; the
    /// collector finishes its tail off the main actor and the merge happens after.
    func learnVoicePrintsAtMeetingEnd() {
        guard voicePrintsWanted, let collector = onDeviceDiarization.activeCollector, let map = deepgramService?.onDeviceSpeakerMap else { return }
        let selfIDs = effectiveLiveSelfSpeakerIDs
        let names = liveSpeakerNames
        let overrides = liveSpeakerOverrides
        let emails = currentMeeting?.resolvedSpeakerEmails ?? [:]
        let selfOn = voicePrintSelfEnabled
        let othersOn = voicePrintOthersEnabled
        let store = voicePrints
        Task { @MainActor in
            await collector.finish()
            var learnt: [String] = []
            for voice in collector.snapshot() where voice.speechSeconds >= VoicePrintMatcher.learnMinimumSeconds {
                guard let appID = map[voice.source]?[voice.slot] else { continue }
                let key = String(appID)
                if selfOn, selfIDs.contains(appID) {
                    store.merge(key: VoicePrint.selfKey, displayName: "You", email: nil, vector: voice.vector, speechSeconds: voice.speechSeconds)
                    learnt.append("you")
                } else if othersOn, let email = emails[key], let name = names[key] ?? (overrides.contains(key) ? names[key] : nil) {
                    store.merge(key: email, displayName: name, email: email, vector: voice.vector, speechSeconds: voice.speechSeconds)
                    learnt.append(email)
                }
            }
            if !learnt.isEmpty {
                DebugLogger.shared.log(.app, "Voice prints learnt: \(learnt.joined(separator: ", "))")
            }
        }
    }

    func resetLiveVoicePrintState() {
        livePrintMatchedIDs = []
        livePrintSuggestions = [:]
        lastVoicePrintMatchAt = nil
    }
}
