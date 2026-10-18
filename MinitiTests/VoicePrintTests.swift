import XCTest
#if os(iOS)
@testable import MinitiMobile
#else
@testable import miniti
#endif

@MainActor
final class VoicePrintTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("voiceprints-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func unit(_ i: Int, dims: Int = 4) -> [Float] {
        var v = [Float](repeating: 0, count: dims); v[i] = 1; return v
    }

    func testStoreRoundTripMergeCapAndDelete() {
        let store = VoicePrintStore(root: root)
        store.merge(key: VoicePrint.selfKey, displayName: "You", email: nil, vector: unit(0), speechSeconds: 30)
        store.merge(key: "sam@acme.com", displayName: "Sam", email: "sam@acme.com", vector: unit(1), speechSeconds: 40)
        XCTAssertEqual(store.selfPrint?.meetings, 1)
        XCTAssertEqual(store.others.map(\.key), ["sam@acme.com"])

        // Merging moves the print towards the new vector, more so while history is short.
        store.merge(key: "sam@acme.com", displayName: "Sam Jones", email: "sam@acme.com", vector: unit(2), speechSeconds: 20)
        let sam = store.print(for: "sam@acme.com")!
        XCTAssertEqual(sam.meetings, 2)
        XCTAssertEqual(sam.speechSeconds, 60)
        XCTAssertEqual(sam.displayName, "Sam Jones")
        XCTAssertEqual(sam.vector[1], sam.vector[2], accuracy: 0.001)
        XCTAssertEqual(sqrt(sam.vector.reduce(0) { $0 + $1 * $1 }), 1, accuracy: 0.001, "stays unit length")

        let reloaded = VoicePrintStore(root: root)
        XCTAssertEqual(reloaded.prints.count, 2)
        reloaded.removeAll(keepSelf: true)
        XCTAssertEqual(reloaded.prints.map(\.key), [VoicePrint.selfKey])
        XCTAssertEqual(VoicePrintStore(root: root).prints.count, 1)
        reloaded.remove(key: VoicePrint.selfKey)
        XCTAssertTrue(VoicePrintStore(root: root).prints.isEmpty)
    }

    func testMatcherIsOneToOneSelfFirstAndHonoursThresholds() {
        let now = Date()
        func print(_ key: String, _ v: [Float]) -> VoicePrint {
            VoicePrint(key: key, displayName: key, email: key == "self" ? nil : key, vector: v, meetings: 1, speechSeconds: 60, createdAt: now, updatedAt: now)
        }
        let me = print(VoicePrint.selfKey, unit(0))
        let sam = print("sam@acme.com", unit(1))
        let near = VoicePrint.normalised([0.8, 0.6, 0, 0])   // 0.8 to me, 0.6 to sam
        let candidates = [
            VoicePrintMatcher.Candidate(speakerID: 1000, vector: near, speechSeconds: 30),
            VoicePrintMatcher.Candidate(speakerID: 1001, vector: VoicePrint.normalised([0.3, 0.95, 0, 0]), speechSeconds: 30),
            VoicePrintMatcher.Candidate(speakerID: 1002, vector: VoicePrint.normalised([0, 0.5, 0.87, 0]), speechSeconds: 30),
            VoicePrintMatcher.Candidate(speakerID: 1003, vector: unit(0), speechSeconds: 5),
        ]
        let matches = VoicePrintMatcher.assign(candidates: candidates, prints: [sam, me])
        let byID = Dictionary(uniqueKeysWithValues: matches.map { ($0.speakerID, $0) })
        XCTAssertEqual(byID[1000]?.print.key, VoicePrint.selfKey, "self settles first even though 1000 also resembles sam")
        XCTAssertTrue(byID[1000]!.isConfident)
        XCTAssertEqual(byID[1001]?.print.key, "sam@acme.com")
        XCTAssertTrue(byID[1001]!.isConfident)
        XCTAssertNil(byID[1002], "0.5 to sam, but sam is taken and nothing else is above the confirm band")
        XCTAssertNil(byID[1003], "too little speech")

        let weak = VoicePrintMatcher.assign(candidates: [VoicePrintMatcher.Candidate(speakerID: 7, vector: VoicePrint.normalised([0.5, 0.87, 0, 0]), speechSeconds: 30)], prints: [sam])
        XCTAssertEqual(weak.count, 1)
        XCTAssertTrue(weak[0].isConfident, "0.87 to sam is a confident match")
        let suggestion = VoicePrintMatcher.assign(candidates: [VoicePrintMatcher.Candidate(speakerID: 8, vector: VoicePrint.normalised([0.87, 0.5, 0, 0]), speechSeconds: 30)], prints: [sam])
        XCTAssertEqual(suggestion.count, 1)
        XCTAssertFalse(suggestion[0].isConfident)
        XCTAssertEqual(suggestion[0].similarity, 0.5, accuracy: 0.01)
    }

    func testCollectorWindowsOnlyExclusiveSpeechAndAveragesPerSlot() async {
        let rate = Int(OnDeviceSpeakerTimeline.sampleRate)
        let collector = VoicePrintCollector { samples in
            // Fake embedder: the window's mean amplitude goes into dimension 0, the rest zero.
            let mean = samples.reduce(0, +) / Float(samples.count)
            return [mean, 1, 0, 0]
        }
        // 20 s of audio: slot 0 at amplitude 0.5 for the first 10 s, slot 1 at 0.25 after.
        let audio = [Float](repeating: 0.5, count: rate * 10) + [Float](repeating: 0.25, count: rate * 10)
        collector.noteAudio(source: .microphone, samples: audio)
        var dominant = [UInt8](repeating: 0, count: 1000) + [UInt8](repeating: 1, count: 1000)
        var exclusive = [Bool](repeating: true, count: 2000)
        // Two seconds of overlap in the middle must not be used.
        for i in 900..<1100 { exclusive[i] = false }
        dominant[1999] = OnDeviceSpeakerTimeline.silence
        collector.noteFrames(source: .microphone, startFrame: 0, dominant: dominant, exclusive: exclusive)
        await collector.finish()
        let voices = collector.snapshot().sorted { $0.slot < $1.slot }
        XCTAssertEqual(voices.map(\.slot), [0, 1])
        XCTAssertEqual(voices[0].speechSeconds, 9, accuracy: 0.02, "6 s window plus a 3 s tail; the overlap second is out")
        XCTAssertEqual(voices[1].speechSeconds, 6, accuracy: 0.02, "one window; the 2.99 s tail is under the 3 s minimum and dropped")
        XCTAssertEqual(voices[0].vector[0] / voices[0].vector[1], 0.5, accuracy: 0.01)
        XCTAssertEqual(voices[1].vector[0] / voices[1].vector[1], 0.25, accuracy: 0.01)
    }

    func testTimelineReportsExclusivityAndFrameOffsets() {
        let timeline = OnDeviceSpeakerTimeline(sources: [.microphone])
        var seen: [(Int, [UInt8], [Bool])] = []
        timeline.onFrames = { _, start, frames, exclusive in seen.append((start, frames, exclusive)) }
        // 3 frames, 2 slots: only slot 0; both; silence.
        timeline.append(source: .microphone, probabilities: [0.9, 0.1, 0.7, 0.8, 0.2, 0.3], frameCount: 3, numSpeakers: 2)
        timeline.append(source: .microphone, probabilities: [0.1, 0.9], frameCount: 1, numSpeakers: 2)
        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(seen[0].0, 0)
        XCTAssertEqual(seen[0].1, [0, 1, OnDeviceSpeakerTimeline.silence])
        XCTAssertEqual(seen[0].2, [true, false, false])
        XCTAssertEqual(seen[1].0, 3)
        XCTAssertEqual(seen[1].1, [1])
    }

    func testStableProviderMapOnlyCoversOnDeviceSources() {
        var state = SpeakerIdentityState()
        state.beginConnection(preservingIdentities: false)
        state.setStableProviderSources([.microphone])
        let a = state.appSpeakerID(source: .microphone, providerID: 0)
        let b = state.appSpeakerID(source: .microphone, providerID: 1)
        _ = state.appSpeakerID(source: .system, providerID: 0)
        let map = state.stableProviderMap()
        XCTAssertEqual(map[.microphone]?[0], a)
        XCTAssertEqual(map[.microphone]?[1], b)
        XCTAssertNil(map[.system])
    }

    func testPrintsNeverReachTheCloudDocumentOrExports() throws {
        XCTAssertFalse(MeetingSyncDocument.knownKeys.contains { $0.lowercased().contains("voice") })
        let meeting = Meeting(title: "Budget", startTime: Date(), endTime: Date().addingTimeInterval(60),
                              segments: [TranscriptSegment(text: "Hello", speaker: 0, timestamp: 0, isFinal: true)])
        meeting.speakerNames = ["0": "Sam"]
        let doc = try JSONSerialization.data(withJSONObject: MeetingSyncDocument.encode(meeting, segments: meeting.segments))
        XCTAssertFalse(String(decoding: doc, as: UTF8.self).lowercased().contains("voice"))
        let payload = try JSONEncoder().encode(WebhookService.payloadFromMeeting(meeting))
        XCTAssertFalse(String(decoding: payload, as: UTF8.self).lowercased().contains("voice"))
        XCTAssertFalse(meeting.fullMeetingAsMarkdown().lowercased().contains("voice print"))
    }
}
