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
