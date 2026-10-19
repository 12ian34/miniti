import AVFoundation
import XCTest
#if os(iOS)
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class WatchRecordingProtocolTests: XCTestCase {
    func testSegmentTransferRoundTrip() {
        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let transfer = WatchSegmentTransfer(recordingID: id, index: 3, offset: 900, duration: 300, startedAt: started, language: "de", isManifest: false)
        let decoded = WatchSegmentTransfer(dictionary: transfer.dictionary)
        XCTAssertEqual(decoded, transfer)
    }

    func testUnknownProtocolVersionIsRefused() {
        var dict = WatchSegmentTransfer(recordingID: UUID(), index: 0, offset: 0, duration: 1, startedAt: Date(), language: "en", isManifest: true).dictionary
        dict["protocol"] = WatchRecordingProtocol.version + 1
        XCTAssertNil(WatchSegmentTransfer(dictionary: dict))
        XCTAssertNil(WatchSegmentTransfer(dictionary: nil))
    }

    func testReceiptRoundTrip() {
        let receipt = WatchReceipt(recordingID: UUID(), receivedIndexes: [0, 2], status: .waitingForMinutes, message: "later")
        XCTAssertEqual(WatchReceipt(dictionary: receipt.dictionary), receipt)
        XCTAssertNil(WatchReceipt(dictionary: ["recording_id": "x"]))
    }

    func testManifestJSONRoundTrip() throws {
        let manifest = WatchRecordingManifest(
            id: UUID(), protocolVersion: 1, startedAt: Date(timeIntervalSince1970: 1_800_000_000), endedAt: nil,
            language: "en", state: .stopped,
            segments: [WatchRecordingSegment(index: 0, offset: 0, duration: 300, byteCount: 1, filename: "segment-000.m4a", delivered: true),
                       WatchRecordingSegment(index: 1, offset: 300, duration: 12.5, byteCount: 1, filename: "segment-001.m4a")]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(WatchRecordingManifest.self, from: try encoder.encode(manifest))
        XCTAssertEqual(back, manifest)
        XCTAssertEqual(back.duration, 312.5)
    }
}

#if os(iOS)
@MainActor
final class WatchImportTests: XCTestCase {
    private var root: URL!
    private var service: WatchImportService!
    private var receipts: [WatchReceipt] = []

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("watch-import-\(UUID().uuidString)")
        service = WatchImportService(root: root)
        receipts = []
        service.sendReceipt = { [weak self] in self?.receipts.append($0) }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func drop(_ transfer: WatchSegmentTransfer, contents: Data) -> URL {
        let dir = service.directory(for: transfer.recordingID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(transfer.isManifest ? "manifest.json" : String(format: "segment-%03d.m4a", transfer.index))
        try? contents.write(to: url)
        return url
    }

    func testDuplicateDeliveryAndManifestCompleteTheJobOnce() throws {
        let id = UUID()
        let started = Date()
        let seg0 = WatchSegmentTransfer(recordingID: id, index: 0, offset: 0, duration: 300, startedAt: started, language: "en", isManifest: false)
        let seg1 = WatchSegmentTransfer(recordingID: id, index: 1, offset: 300, duration: 20, startedAt: started, language: "en", isManifest: false)
        service.noteArrival(seg0, at: drop(seg0, contents: Data([1])))
        service.noteArrival(seg0, at: drop(seg0, contents: Data([1])))
        XCTAssertEqual(service.jobs.count, 1)
        XCTAssertEqual(service.jobs[0].receivedIndexes, [0])
        XCTAssertEqual(service.jobs[0].status, .receiving)

        let manifest = WatchRecordingManifest(
            id: id, protocolVersion: 1, startedAt: started, endedAt: started.addingTimeInterval(320), language: "fr", state: .stopped,
            segments: [WatchRecordingSegment(index: 0, offset: 0, duration: 300, byteCount: 1, filename: "segment-000.m4a"),
                       WatchRecordingSegment(index: 1, offset: 300, duration: 20, byteCount: 1, filename: "segment-001.m4a")]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestTransfer = WatchSegmentTransfer(recordingID: id, index: -1, offset: 0, duration: 320, startedAt: started, language: "fr", isManifest: true)
        service.noteArrival(manifestTransfer, at: drop(manifestTransfer, contents: try encoder.encode(manifest)))
        XCTAssertEqual(service.jobs[0].status, .receiving, "one file still missing")
        XCTAssertEqual(service.jobs[0].expectedIndexes, [0, 1])
        XCTAssertEqual(service.jobs[0].language, "fr")

        service.noteArrival(seg1, at: drop(seg1, contents: Data([1])))
        XCTAssertEqual(service.jobs[0].status, .queued)
        XCTAssertEqual(receipts.last?.status, .received)
        XCTAssertEqual(receipts.last?.receivedIndexes, [0, 1])

        // The ledger survives a relaunch.
        let reloaded = WatchImportService(root: root)
        XCTAssertEqual(reloaded.jobs.map(\.id), [id])
        XCTAssertEqual(reloaded.jobs[0].status, .queued)
    }

    func testTransferMetadataSurvivesPropertyListSerialisation() throws {
        let transfer = WatchSegmentTransfer(recordingID: UUID(), index: 2, offset: 600, duration: 300, startedAt: Date(timeIntervalSince1970: 1_800_000_000), language: "en", isManifest: false)
        let data = try PropertyListSerialization.data(fromPropertyList: transfer.dictionary, format: .binary, options: 0)
        let back = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(WatchSegmentTransfer(dictionary: back), transfer)
        let receipt = WatchReceipt(recordingID: UUID(), receivedIndexes: [0, 1], status: .ready)
        let rdata = try PropertyListSerialization.data(fromPropertyList: receipt.dictionary, format: .binary, options: 0)
        XCTAssertEqual(WatchReceipt(dictionary: try XCTUnwrap(PropertyListSerialization.propertyList(from: rdata, format: nil) as? [String: Any])), receipt)
    }

    func testResentManifestKeepsAFailedJobFailedAndTellsTheWatch() throws {
        let id = UUID()
        let started = Date()
        let bad = WatchSegmentTransfer(recordingID: id, index: -1, offset: 0, duration: 1, startedAt: started, language: "en", isManifest: true)
        service.noteArrival(bad, at: drop(bad, contents: Data("nope".utf8)))
        XCTAssertEqual(service.jobs[0].status, .failed)
        XCTAssertEqual(receipts.last?.status, .failed)
        // A segment arriving later does not revive it.
        let seg = WatchSegmentTransfer(recordingID: id, index: 0, offset: 0, duration: 1, startedAt: started, language: "en", isManifest: false)
        service.noteArrival(seg, at: drop(seg, contents: Data([1])))
        XCTAssertEqual(service.jobs[0].status, .failed)
        XCTAssertEqual(receipts.last?.status, .failed)
        XCTAssertEqual(receipts.last?.receivedIndexes, [0])
    }

    func testDismissLeavesATombstoneThatAnswersReady() throws {
        let id = UUID()
        let started = Date()
        let bad = WatchSegmentTransfer(recordingID: id, index: -1, offset: 0, duration: 1, startedAt: started, language: "en", isManifest: true)
        service.noteArrival(bad, at: drop(bad, contents: Data("nope".utf8)))
        service.dismiss(id)
        XCTAssertEqual(service.jobs[0].status, .dismissed)
        XCTAssertTrue(service.activeJobs.isEmpty)
        XCTAssertEqual(receipts.last?.status, .ready)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.directory(for: id).path))
        // The watch resends: still no job revived, still told ready, file dropped.
        let seg = WatchSegmentTransfer(recordingID: id, index: 0, offset: 0, duration: 1, startedAt: started, language: "en", isManifest: false)
        let url = drop(seg, contents: Data([1]))
        service.noteArrival(seg, at: url)
        XCTAssertEqual(service.jobs.count, 1)
        XCTAssertEqual(service.jobs[0].status, .dismissed)
        XCTAssertEqual(receipts.last?.status, .ready)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        // Survives a relaunch.
        XCTAssertEqual(WatchImportService(root: root).jobs[0].status, .dismissed)
    }

    func testRetryRequeuesOnlyCompleteJobs() throws {
        let id = UUID()
        let started = Date()
        let bad = WatchSegmentTransfer(recordingID: id, index: -1, offset: 0, duration: 1, startedAt: started, language: "en", isManifest: true)
        service.noteArrival(bad, at: drop(bad, contents: Data("nope".utf8)))
        service.retry(id)
        XCTAssertEqual(service.jobs[0].status, .receiving, "no manifest yet, so it waits for files")
        XCTAssertTrue(service.jobs[0].isRemovable)
    }

    func testStitchSkipsUnreadablePartsAndCopiesASingleGoodOne() async throws {
        let dir = root.appendingPathComponent("stitch")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let good = dir.appendingPathComponent("good.caf")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        // Scoped so the file header is finalised before anything reads it.
        try {
            let file = try AVAudioFile(forWriting: good, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
            buffer.frameLength = 16_000
            try file.write(from: buffer)
        }()
        let fixtureSeconds = try await AVURLAsset(url: good).load(.duration).seconds
        XCTAssertGreaterThan(fixtureSeconds, 0.5, "fixture must be readable")
        let bad = dir.appendingPathComponent("bad.m4a")
        try Data(repeating: 0, count: 2_000).write(to: bad)
        let output = dir.appendingPathComponent("joined.m4a")
        try await WatchTranscriptionClient.stitch([bad, good], into: output)
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: good))
        do {
            try await WatchTranscriptionClient.stitch([bad], into: output)
            XCTFail("expected unreadable")
        } catch WatchTranscriptionClient.Failure.unreadable {
        }
    }

    func testUnreadableManifestFailsTheJob() {
        let id = UUID()
        let t = WatchSegmentTransfer(recordingID: id, index: -1, offset: 0, duration: 1, startedAt: Date(), language: "en", isManifest: true)
        service.noteArrival(t, at: drop(t, contents: Data("nope".utf8)))
        XCTAssertEqual(service.jobs[0].status, .failed)
    }

    func testDeepgramUtterancesBecomeSegments() throws {
        let json = """
        {"metadata":{"duration":61.2},"results":{"channels":[{"alternatives":[{"transcript":"x"}]}],
         "utterances":[{"start":0.5,"end":3.0,"confidence":0.98,"transcript":" Hello there. ","speaker":0},
                       {"start":3.2,"end":5.0,"confidence":0.9,"transcript":"","speaker":1},
                       {"start":5.1,"end":9.0,"confidence":0.95,"transcript":"Hi.","speaker":1}]}}
        """
        let result = try WatchTranscriptionClient.parse(Data(json.utf8))
        XCTAssertEqual(result.duration, 61.2)
        XCTAssertEqual(result.segments.map(\.text), ["Hello there.", "Hi."])
        XCTAssertEqual(result.segments.map(\.speaker), [0, 1])
        XCTAssertEqual(result.segments[1].timestamp, 5.1)

        let job = WatchImportJob(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_800_000_000), language: "en", status: .queued, message: nil,
                                 receivedIndexes: [0], expectedIndexes: [0], durationSeconds: 60, meetingID: nil, updatedAt: Date())
        let meeting = WatchImportService.makeMeeting(job: job, result: result)
        XCTAssertEqual(meeting.externalSource, "watch")
        XCTAssertEqual(meeting.externalID, job.id.uuidString)
        XCTAssertEqual(meeting.provenanceDisplayName, "Apple Watch")
        XCTAssertEqual(meeting.segments.count, 2)
        XCTAssertEqual(meeting.endTime, job.startedAt.addingTimeInterval(61.2))
    }

    func testStitchJoinsSeveralRealAACFilesIntoOneReadableFile() async throws {
        // The 3.1.0 bug: a passthrough export over more than one AAC file fails with -11838.
        let dir = root.appendingPathComponent("aac")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        var parts: [URL] = []
        for i in 0..<3 {
            let url = dir.appendingPathComponent("segment-00\(i).m4a")
            try {
                let file = try AVAudioFile(forWriting: url, settings: WatchRecorder_settingsForTests(), commonFormat: .pcmFormatFloat32, interleaved: false)
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000))
                buffer.frameLength = 32_000
                let data = buffer.floatChannelData![0]
                for n in 0..<32_000 { data[n] = sinf(Float(n) * 0.05 * Float(i + 1)) * 0.3 }
                try file.write(from: buffer)
            }()
            parts.append(url)
        }
        let output = dir.appendingPathComponent("joined.m4a")
        try await WatchTranscriptionClient.stitch(parts, into: output)
        let seconds = try await AVURLAsset(url: output).load(.duration).seconds
        XCTAssertEqual(seconds, 6, accuracy: 0.3, "three two-second parts")
        XCTAssertGreaterThan(try XCTUnwrap(FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int), 1_000)
    }

    func testEmptyTranscriptIsAnError() {
        let json = #"{"metadata":{"duration":4},"results":{"utterances":[]}}"#
        XCTAssertThrowsError(try WatchTranscriptionClient.parse(Data(json.utf8)))
    }

    func testListenURLCarriesDiarizationAndUtterances() {
        let url = WatchTranscriptionClient.listenURL(language: "de").absoluteString
        XCTAssertTrue(url.contains("model=nova-3"))
        XCTAssertTrue(url.contains("language=de"))
        XCTAssertTrue(url.contains("diarize=true"))
        XCTAssertTrue(url.contains("utterances=true"))
    }
}
#endif


#if os(iOS)
/// The watch recorder's AAC settings, mirrored here because the watch target is not linked into the tests.
func WatchRecorder_settingsForTests() -> [String: Any] {
    [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: WatchRecordingProtocol.sampleRate,
     AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: WatchRecordingProtocol.bitRate, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
}
#endif
