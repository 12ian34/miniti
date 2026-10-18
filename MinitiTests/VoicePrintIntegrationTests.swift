import FluidAudio
import XCTest
#if os(iOS)
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// The real on-device diarizer and the real CAM++ model over a real meeting, end to end through
/// the collector. Runs only when `MINITI_AMI_WAV` points at a 16 kHz mono recording (the AMI
/// ES2004a headset mix from scripts/diarization-poc/data), because it loads two Core ML models
/// and takes a minute: `TEST_RUNNER_MINITI_AMI_WAV=/path/to.wav fastlane mac test`.
@MainActor
final class VoicePrintIntegrationTests: XCTestCase {
    func testRealDiarizerAndEmbedderRecogniseSpeakersAcrossHalves() async throws {
        guard let path = ProcessInfo.processInfo.environment["MINITI_AMI_WAV"], FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("set MINITI_AMI_WAV to run the voice print integration test")
        }
        try XCTSkipUnless(OnDeviceDiarizationService.isHardwareSupported)
        let samples = try AudioConverter(sampleRate: 16_000).resampleAudioFile(URL(fileURLWithPath: path))
        let rate = Int(OnDeviceSpeakerTimeline.sampleRate)
        XCTAssertGreaterThan(samples.count, rate * 960, "need at least 16 minutes of audio")

        let diarization = OnDeviceDiarizationService()
        diarization.prepare(sources: [.microphone])
        for _ in 0..<600 where !diarization.isReady {
            if case .failed(let m) = diarization.status { XCTFail("diarizer failed: \(m)"); return }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertTrue(diarization.isReady, "diarizer did not load in time")
        let embedder = try await CampPlusEmbedder.load()
        let embed: @Sendable ([Float]) async throws -> [Float] = { try await embedder.embed(audio: $0) }

        func run(from start: Int, seconds: Int) async -> [VoicePrintCollector.SlotVoice] {
            let collector = VoicePrintCollector(embed: embed)
            let timeline = diarization.beginSession(sources: [.microphone], collector: collector)!
            var offset = start * rate
            let end = min(samples.count, (start + seconds) * rate)
            var first = true
            while offset < end {
                let next = min(end, offset + rate)
                diarization.ingest(samples: Array(samples[offset..<next]), source: .microphone)
                if first { timeline.markSocketStart(); first = false }
                offset = next
            }
            await diarization.endSessionAndWait()
            await collector.finish()
            let mature = timeline.matureSlots(source: .microphone)
            print("voiceprint integration: \(start)s+\(seconds)s mature slots \(mature); processed \(Int(timeline.processedSeconds(source: .microphone))) s; \(collector.diagnostics)")
            return collector.snapshot()
        }

        let t0 = Date()
        let firstHalf = await run(from: 0, seconds: 480)
        let secondHalf = await run(from: 480, seconds: 480)
        print("voiceprint integration: two passes in \(Int(Date().timeIntervalSince(t0))) s")

        let enrolled = firstHalf.filter { $0.speechSeconds >= VoicePrintMatcher.learnMinimumSeconds }
        XCTAssertGreaterThanOrEqual(enrolled.count, 2, "expected at least two speakers with 20 s of own speech in the first eight minutes")
        XCTAssertLessThanOrEqual(firstHalf.count, 6, "far too many slots: \(firstHalf.map { ($0.slot, Int($0.speechSeconds)) })")
        let now = Date()
        let prints = enrolled.map {
            VoicePrint(key: "slot-\($0.slot)", displayName: "Speaker \($0.slot)", email: nil, vector: $0.vector,
                       meetings: 1, speechSeconds: $0.speechSeconds, createdAt: now, updatedAt: now)
        }
        let candidates = secondHalf.map { VoicePrintMatcher.Candidate(speakerID: $0.slot, vector: $0.vector, speechSeconds: $0.speechSeconds) }
        let matches = VoicePrintMatcher.assign(candidates: candidates, prints: prints)
        for m in matches { print("voiceprint integration: second-half slot \(m.speakerID) (\(Int(candidates.first { $0.speakerID == m.speakerID }!.speechSeconds)) s) -> \(m.print.key) \(String(format: "%.2f", m.similarity)) \(m.isConfident ? "confident" : "suggest")") }
        XCTAssertGreaterThanOrEqual(matches.filter(\.isConfident).count, 2, "expected at least two speakers recognised across halves: \(matches.map { ($0.speakerID, $0.print.key, $0.similarity) })")
        XCTAssertEqual(Set(matches.map(\.print.key)).count, matches.count, "one print per speaker")
    }
}
