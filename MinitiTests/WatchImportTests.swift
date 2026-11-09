import AVFoundation
import SwiftData
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
        service?.sessionDeactivated()
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

    func testPaidPartsSurviveCancellationAndBYOKOnlyPaysForRemainingParts() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let parts = (0..<3).map { (url: root.appendingPathComponent("part-\($0).m4a"), offset: Double($0 * 60)) }
        var uploads = 0
        let one = WatchTranscriptionClient.Result(segments: [.init(text: "words", speaker: 0, timestamp: 0, confidence: 1, words: [])], duration: 60)
        let first = Task {
            try await WatchTranscriptionClient.transcribeParts(parts, language: "en", credential: .init(scheme: "Bearer", token: "managed"),
                cacheDirectory: root, managedSessionID: "original-session", managedOwner: "original-account", upload: { _ in
                    uploads += 1
                    if uploads == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                    return one
                })
        }
        do { _ = try await first.value; XCTFail("expected cancellation before part three") } catch is CancellationError { }
        XCTAssertEqual(uploads, 2)
        let resumed = try await WatchTranscriptionClient.transcribeParts(parts, language: "en", credential: .init(scheme: "Token", token: "byok"),
            cacheDirectory: root, upload: { _ in uploads += 1; return one })
        XCTAssertEqual(uploads, 3, "Paid parts must not upload again")
        XCTAssertEqual(resumed.segments.map(\.timestamp), [0, 60, 120])
        let receipts = try WatchTranscriptionClient.transcriptionReceipts(in: root)
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts["original-session"]?.minutes, 2, "BYOK's final minute is not managed usage")
        XCTAssertEqual(receipts["original-session"]?.owner, "original-account")
    }

    func testFullPaidResultIsSavedBeforeCancellationIsObserved() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = root.appendingPathComponent("paid-transcription-full.json")
        let one = WatchTranscriptionClient.Result(segments: [.init(text: "saved", speaker: 0, timestamp: 0, confidence: 1, words: [])], duration: 45)
        let first = Task {
            try await WatchTranscriptionClient.transcribeCached(fileURL: root.appendingPathComponent("input.m4a"), cacheURL: cache,
                language: "en", credential: .init(scheme: "Bearer", token: "managed"), managedSessionID: "session", managedOwner: "owner", upload: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }; return one
                })
        }
        _ = try await first.value
        let cached = try await WatchTranscriptionClient.transcribeCached(fileURL: root.appendingPathComponent("input.m4a"), cacheURL: cache,
            language: "en", credential: .init(scheme: "Token", token: "byok"), managedSessionID: nil, managedOwner: nil,
            upload: { _ in XCTFail("must reuse the paid result"); return one })
        XCTAssertEqual(cached.duration, 45)
        XCTAssertEqual(try WatchTranscriptionClient.transcriptionReceipts(in: root)["session"]?.minutes, 0.75)
    }

    func testSilentPaidResponseIsCheckpointedDespiteCancellation() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = root.appendingPathComponent("paid-transcription-full.json")
        let task = Task {
            try await WatchTranscriptionClient.transcribeCached(fileURL: root.appendingPathComponent("missing-audio.m4a"), cacheURL: cache,
                language: "en", credential: .init(scheme: "Bearer", token: "managed"), managedSessionID: "silent", managedOwner: "owner", upload: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return try WatchTranscriptionClient.parse(Data(#"{"metadata":{"duration":30},"results":{"utterances":[]}}"#.utf8), allowEmpty: true)
                })
        }
        let result = try await task.value
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertEqual(result.duration, 30)
        XCTAssertEqual(try WatchTranscriptionClient.transcriptionReceipts(in: root)["silent"]?.minutes, 0.5)
    }

    func testFullCheckpointFinishesImportWithoutRejoiningOrRequestingCredentials() async throws {
        try await withCleanConsent {
            StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
            let state = try stubbedState(session: TestSupport.stubbedSession())
            state.setThirdPartyAIConsent(true); state.privateModeEnabled = false
            state.appModeRaw = AppMode.byok.rawValue
            state.deepgramApiKey = ""; state.openaiApiKey = ""
            let (id, _) = try dropOnePartRecording() // Deliberately unreadable audio.
            let checkpoint = WatchTranscriptionClient.Checkpoint(result: .init(segments: [
                .init(text: "Already received speech", speaker: 0, timestamp: 0, confidence: 1, words: [])
            ], duration: 30), managedSessionID: nil, managedOwner: nil)
            try JSONEncoder().encode(checkpoint).write(to: service.directory(for: id).appendingPathComponent("paid-transcription-full.json"))
            StubURLProtocol.handler = { _ in XCTFail("No provider or new grant is needed"); return (503, Data()) }
            service.appState = state; service.kick()
            try await TestSupport.waitUntil(timeout: 15) { self.service.jobs.first?.status == .done }
            let meeting = try XCTUnwrap(state.fetchMeetings(.historyLoad)?.first { $0.externalID == id.uuidString })
            XCTAssertEqual(meeting.segments.first?.text, "Already received speech")
            XCTAssertEqual(grantRequests(), 0)
        }
    }

    func testActualWorkerCancellationResumesRemainingPartsWithBYOKAndOriginalBilling() async throws {
        try await withCleanConsent {
            StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
            let state = try stubbedState(session: TestSupport.stubbedSession())
            state.setThirdPartyAIConsent(true); state.privateModeEnabled = false
            let owner = try XCTUnwrap(state.clientAuthManager.status.accountID)
            let id = UUID(), started = Date()
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            var manifestParts: [WatchRecordingSegment] = []
            for index in 0..<3 {
                let transfer = WatchSegmentTransfer(recordingID: id, index: index, offset: Double(index), duration: 1, startedAt: started, language: "en", isManifest: false)
                let url = drop(transfer, contents: Data())
                try {
                    let file = try AVAudioFile(forWriting: url, settings: WatchRecorder_settingsForTests(), commonFormat: .pcmFormatFloat32, interleaved: false)
                    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
                    buffer.frameLength = 16_000; try file.write(from: buffer)
                }()
                service.noteArrival(transfer, at: url)
                manifestParts.append(.init(index: index, offset: Double(index), duration: 1, byteCount: 1, filename: url.lastPathComponent))
            }
            let manifest = WatchRecordingManifest(id: id, protocolVersion: 1, startedAt: started, endedAt: started.addingTimeInterval(3), language: "en", state: .stopped, segments: manifestParts)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let transfer = WatchSegmentTransfer(recordingID: id, index: -1, offset: 0, duration: 3, startedAt: started, language: "en", isManifest: true)
            service.noteArrival(transfer, at: drop(transfer, contents: try encoder.encode(manifest)))
            let one = WatchTranscriptionClient.Result(segments: [.init(text: "Retained words", speaker: 0, timestamp: 0, confidence: 1, words: [])], duration: 1)
            try JSONEncoder().encode(WatchTranscriptionClient.Checkpoint(result: one, managedSessionID: "first-session", managedOwner: owner))
                .write(to: service.directory(for: id).appendingPathComponent("paid-transcription-part-0.json"))
            StubURLProtocol.handler = { request in
                if request.url?.path.hasSuffix("/session/prerecorded") == true {
                    return (200, Data(#"{"access_token":"dg-test","token_type":"Bearer","expires_in":600,"expires_at":"2099-01-01T00:00:00Z","session_id":"second-session"}"#.utf8))
                }
                return (503, Data())
            }
            var uploads: [String] = []
            service.transcriptionUpload = { url in
                uploads.append(url.lastPathComponent)
                self.service.sessionDeactivated()
                // Backgrounding alone retains the OS grace period. Simulate its
                // expiry while the successful provider response is arriving.
                withUnsafeCurrentTask { $0?.cancel() }
                return one
            }
            service.appState = state; service.kick()
            try await TestSupport.waitUntil(timeout: 15) { !self.service.isRunning && uploads.count == 1 }
            XCTAssertEqual(service.jobs.first?.status, .queued)
            XCTAssertTrue(FileManager.default.fileExists(atPath: service.directory(for: id).appendingPathComponent("paid-transcription-part-1.json").path))
            state.appModeRaw = AppMode.byok.rawValue; state.deepgramApiKey = "test-byok"; state.openaiApiKey = ""
            service.transcriptionUpload = { url in uploads.append(url.lastPathComponent); return one }
            service.sessionActivated()
            try await TestSupport.waitUntil(timeout: 15) { self.service.jobs.first?.status == .done }
            XCTAssertEqual(uploads, ["segment-001.m4a", "segment-002.m4a"])
            XCTAssertEqual(grantRequests(), 1)
            let pending = state.managedSessionJournal.pending
            XCTAssertEqual(pending.first { $0.sessionId == "first-session" }?.durationMinutes, 1.0 / 60)
            XCTAssertEqual(pending.first { $0.sessionId == "second-session" }?.durationMinutes, 1.0 / 60)
            XCTAssertEqual(pending.count, 2, "BYOK's remaining part incurs no managed report")
            XCTAssertEqual(state.fetchMeetings(.historyLoad)?.first?.segments.count, 3)
        }
    }

    func testCompletePartCacheSettlesOnlyItsReceiptsAndNeedsNoNewGrant() async throws {
        try await withCleanConsent {
            StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
            let state = try stubbedState(session: TestSupport.stubbedSession())
            state.setThirdPartyAIConsent(true); state.privateModeEnabled = false
            state.appModeRaw = AppMode.byok.rawValue
            state.deepgramApiKey = ""; state.openaiApiKey = ""
            let (id, _) = try dropOnePartRecording()
            let owner = try XCTUnwrap(state.clientAuthManager.status.accountID)
            let checkpoint = WatchTranscriptionClient.Checkpoint(result: .init(segments: [
                .init(text: "Cached part", speaker: 0, timestamp: 0, confidence: 1, words: [])
            ], duration: 30), managedSessionID: "paid-original", managedOwner: owner)
            try JSONEncoder().encode(checkpoint).write(to: service.directory(for: id).appendingPathComponent("paid-transcription-part-0.json"))
            // Reproduce death after opening another session, before final cache write.
            try rewriteJob(id) { job in
                job.managedOwner = owner; job.managedSessionID = "unused-retry"
                job.usesTranscriptionReceipts = nil // pre-155 private job with receipt checkpoints
            }
            StubURLProtocol.handler = { request in
                if request.url?.path.hasSuffix("/session/prerecorded") == true { XCTFail("Complete parts must not request credentials") }
                return (503, Data())
            }
            service.appState = state; service.kick()
            try await TestSupport.waitUntil(timeout: 15) { self.service.jobs.first?.status == .done }
            XCTAssertEqual(grantRequests(), 0)
            let reports = state.managedSessionJournal.pending
            XCTAssertEqual(reports.first { $0.sessionId == "paid-original" }?.durationMinutes, 0.5)
            XCTAssertEqual(reports.first { $0.sessionId == "unused-retry" }?.durationMinutes, 0)
            XCTAssertEqual(state.fetchMeetings(.historyLoad)?.first?.segments.first?.text, "Cached part")
        }
    }

    func testSilentCompletePartCacheNeverRequestsQuotaOnRetry() async throws {
        try await withCleanConsent {
            StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
            let state = try stubbedState(session: TestSupport.stubbedSession())
            state.setThirdPartyAIConsent(true); state.privateModeEnabled = false
            let (id, _) = try dropOnePartRecording()
            let checkpoint = WatchTranscriptionClient.Checkpoint(result: .init(segments: [], duration: 30), managedSessionID: nil, managedOwner: nil)
            try JSONEncoder().encode(checkpoint).write(to: service.directory(for: id).appendingPathComponent("paid-transcription-part-0.json"))
            StubURLProtocol.handler = { request in
                if request.url?.path.hasSuffix("/session/prerecorded") == true { XCTFail("Silent cached work needs no quota") }
                return (402, Data())
            }
            service.appState = state; service.kick()
            try await TestSupport.waitUntil { self.service.jobs.first?.status == .failed && !self.service.isRunning }
            XCTAssertEqual(service.jobs.first?.message, "No speech was found in the recording")
            service.retry(id)
            try await TestSupport.waitUntil { self.service.jobs.first?.status == .failed && !self.service.isRunning }
            XCTAssertEqual(grantRequests(), 0)
        }
    }

    func testDismissRetainsReceiptsUntilOriginalOwnerUsageIsDurable() async throws {
        StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
        let state = try stubbedState(session: TestSupport.stubbedSession())
        let (id, audio) = try dropOnePartRecording()
        let checkpoint = WatchTranscriptionClient.Checkpoint(result: .init(segments: [], duration: 30), managedSessionID: "dismissed-paid", managedOwner: "original-owner")
        let cache = service.directory(for: id).appendingPathComponent("paid-transcription-part-0.json")
        try JSONEncoder().encode(checkpoint).write(to: cache)
        try rewriteJob(id) { $0.status = .failed }
        service.dismiss(id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        service = WatchImportService(root: root)
        service.appState = state; service.sessionActivated()
        try await TestSupport.waitUntil { !FileManager.default.fileExists(atPath: cache.path) }
        XCTAssertEqual(service.jobs.first?.status, .dismissed)
        let report = try XCTUnwrap(state.managedSessionJournal.pending.first { $0.sessionId == "dismissed-paid" })
        XCTAssertEqual(report.accountID, "original-owner")
        XCTAssertEqual(report.durationMinutes, 0.5)
    }

    func testDismissedCorruptCheckpointIsRetainedOnlyForUsageDeliveryWindow() async throws {
        let state = try stubbedState(session: TestSupport.stubbedSession())
        let (id, _) = try dropOnePartRecording()
        let directory = service.directory(for: id)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("paid-transcription-full.json"))
        try rewriteJob(id) { $0.status = .failed }
        service.dismiss(id)
        service.appState = state; service.sessionActivated()
        await Task.yield()
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        service.now = { Date().addingTimeInterval(31 * 86_400) }
        service.sessionActivated()
        try await TestSupport.waitUntil { !FileManager.default.fileExists(atPath: directory.path) }
        XCTAssertTrue(state.managedSessionJournal.pending.isEmpty, "Never invent minutes from a corrupt receipt")
    }

    private func rewriteJob(_ id: UUID, change: (inout WatchImportJob) -> Void) throws {
        var rows = service.jobs
        let index = try XCTUnwrap(rows.firstIndex { $0.id == id })
        change(&rows[index])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(rows).write(to: root.appendingPathComponent("ledger.json"))
        service = WatchImportService(root: root)
        service.sendReceipt = { [weak self] in self?.receipts.append($0) }
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

    func testFailedLedgerWriteRetainsAudioAndDoesNotAcknowledgeTransfer() throws {
        let transfer = WatchSegmentTransfer(recordingID: UUID(), index: 0, offset: 0, duration: 1, startedAt: Date(), language: "en", isManifest: false)
        let file = drop(transfer, contents: Data([1]))
        service.ledgerWriter = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        service.noteArrival(transfer, at: file)
        XCTAssertTrue(receipts.isEmpty)
        XCTAssertEqual(service.jobs.first?.status, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(WatchImportService(root: root).jobs.isEmpty)
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

    // MARK: Permission (narrowed R2, 2026-10-27)

    private let consentKeys = ["acceptedTermsVersion", "declinedTermsVersion", "hasAcceptedTerms"]
    /// Kept for the test's lifetime: a temporary container tears its context down under the worker.
    private var container: ModelContainer?

    private func withCleanConsent(_ body: () async throws -> Void) async rethrows {
        let defaults = UserDefaults.standard
        let saved = consentKeys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        consentKeys.forEach { defaults.removeObject(forKey: $0) }
        try await body()
    }

    /// An enrolled managed `AppState` with an in-memory store whose network goes through the stub.
    private func stubbedState(session: URLSession) throws -> AppState {
        let manager = TestSupport.enrolledAuthManager(session: session)
        let state = AppState()
        state.appModeRaw = AppMode.managed.rawValue
        state.clientAuthManager = manager
        state.minitiAPIService = MinitiAPIService(session: session, auth: manager)
        state.refreshClientAuthStatus()
        let container = try TestSupport.makeInMemoryContainer()
        self.container = container
        state.modelContext = container.mainContext
        return state
    }

    /// One 30 s recording: its segment file and the manifest, which makes the job runnable.
    private func dropOnePartRecording() throws -> (id: UUID, segment: URL) {
        let id = UUID()
        let started = Date()
        let seg0 = WatchSegmentTransfer(recordingID: id, index: 0, offset: 0, duration: 30, startedAt: started, language: "en", isManifest: false)
        let url = drop(seg0, contents: Data([1]))
        service.noteArrival(seg0, at: url)
        let manifest = WatchRecordingManifest(
            id: id, protocolVersion: 1, startedAt: started, endedAt: started.addingTimeInterval(30), language: "en", state: .stopped,
            segments: [WatchRecordingSegment(index: 0, offset: 0, duration: 30, byteCount: 1, filename: "segment-000.m4a")]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestTransfer = WatchSegmentTransfer(recordingID: id, index: -1, offset: 0, duration: 30, startedAt: started, language: "en", isManifest: true)
        service.noteArrival(manifestTransfer, at: drop(manifestTransfer, contents: try encoder.encode(manifest)))
        return (id, url)
    }

    private func grantRequests() -> Int {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/session/prerecorded") == true }.count
    }

    func testSavedWatchTranscriptWithFailedSummaryCompletesWithoutAnotherImportAttempt() async throws {
        try await withCleanConsent {
            StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
            let state = try stubbedState(session: TestSupport.stubbedSession())
            state.setThirdPartyAIConsent(true)
            state.privateModeEnabled = false
            StubURLProtocol.handler = { _ in (503, Data(#"{"error":"unavailable"}"#.utf8)) }
            service.appState = state
            let (id, _) = try dropOnePartRecording()
            let meeting = Meeting(title: "Saved Watch transcript", endTime: Date(), segments: [
                TranscriptSegment(text: "Saved speech", speaker: 0, timestamp: 0, isFinal: true, confidence: 1)
            ])
            meeting.externalSource = WatchImportService.sourceIdentifier
            meeting.externalID = id.uuidString
            state.modelContext?.insert(meeting); try state.modelContext?.save()
            try await TestSupport.waitUntil(timeout: 15) { self.service.jobs.first?.status == .done }
            XCTAssertNil(meeting.summaryText)
            XCTAssertTrue(service.jobs.first?.message?.contains("Recording saved") == true)
            let completion = meeting.webhookCompletion?.id
            let requests = StubURLProtocol.requests.count
            try await TestSupport.waitUntil { !self.service.isRunning }
            service.kick()
            XCTAssertFalse(service.isRunning, "A done job cannot schedule another worker")
            XCTAssertEqual(StubURLProtocol.requests.count, requests)
            XCTAssertEqual(meeting.webhookCompletion?.id, completion)
            XCTAssertEqual(service.jobs.first?.status, .done)
        }
    }

    func testSavedImportWithoutAnAIKeyCompletesWithoutRetryingInsightsOrWebhooks() async throws {
        try await withCleanConsent {
            StubURLProtocol.reset(); defer { StubURLProtocol.reset() }
            let state = try stubbedState(session: TestSupport.stubbedSession())
            state.setThirdPartyAIConsent(true)
            let oldMode = state.appModeRaw, oldKey = state.openaiApiKey
            defer { state.appModeRaw = oldMode; state.openaiApiKey = oldKey }
            state.appModeRaw = AppMode.byok.rawValue
            state.openaiApiKey = ""
            service.appState = state
            let (id, _) = try dropOnePartRecording()
            let meeting = Meeting(title: "Saved Watch transcript", endTime: Date(), segments: [
                TranscriptSegment(text: "Saved speech", speaker: 0, timestamp: 0, isFinal: true, confidence: 1)
            ])
            meeting.externalSource = WatchImportService.sourceIdentifier
            meeting.externalID = id.uuidString
            state.modelContext?.insert(meeting); try state.modelContext?.save()
            try await TestSupport.waitUntil { self.service.jobs.first?.status == .done }
            XCTAssertTrue(StubURLProtocol.requests.isEmpty)
            XCTAssertNil(meeting.summaryText)
            service.kick()
            XCTAssertEqual(service.jobs.first?.status, .done)
            XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        }
    }

    func testArrivalWithoutPermissionKeepsTheJobAndAudioAndResumesOnceWhenGranted() async throws {
        try await withCleanConsent {
            StubURLProtocol.reset()
            defer { StubURLProtocol.reset() }
            let session = TestSupport.stubbedSession()
            let state = try stubbedState(session: session)
            state.setThirdPartyAIConsent(false)
            service.appState = state
            StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }

            let (_, segment) = try dropOnePartRecording()
            try await TestSupport.waitUntil { self.service.jobs.first?.status == .waitingForPermission }
            XCTAssertTrue(FileManager.default.fileExists(atPath: segment.path), "the audio is kept")
            XCTAssertEqual(grantRequests(), 0, "no grant, no upload, no insights without permission")
            XCTAssertEqual(service.jobs.first?.message, "Needs permission for Deepgram and OpenAI. Allow it in Settings, Privacy.")

            // Kicks without permission change nothing: no retry loop.
            service.kick()
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertEqual(service.jobs.first?.status, .waitingForPermission)
            XCTAssertEqual(grantRequests(), 0)

            // A terminal refusal isolates permission behavior. Transient failures have
            // separate scheduler regressions and retain their retry deadline.
            StubURLProtocol.handler = { request in
                request.url?.path.hasSuffix("/session/prerecorded") == true ? (400, Data(#"{"error":"invalid_request"}"#.utf8)) : (200, Data("{}".utf8))
            }
            state.setThirdPartyAIConsent(true)
            service.kick()
            try await TestSupport.waitUntil { self.service.jobs.first?.status == .failed }
            XCTAssertEqual(grantRequests(), 1, "resumed once")
            XCTAssertTrue(FileManager.default.fileExists(atPath: segment.path))
        }
    }

    func testWithdrawalWhileTheGrantIsInFlightPreventsTheUpload() async throws {
        try await withCleanConsent {
            StubURLProtocol.reset()
            defer { StubURLProtocol.reset() }
            let session = TestSupport.stubbedSession()
            let state = try stubbedState(session: session)
            state.setThirdPartyAIConsent(true)
            service.appState = state
            let grant = #"{"access_token":"dg-token","token_type":"Bearer","expires_in":600,"expires_at":"2099-01-01T00:00:00Z","session_id":"s1"}"#
            StubURLProtocol.handler = { request in
                request.url?.path.hasSuffix("/session/prerecorded") == true ? (200, Data(grant.utf8)) : (200, Data("{}".utf8))
            }
            StubURLProtocol.delay = 0.3

            let (_, segment) = try dropOnePartRecording()
            try await TestSupport.waitUntil { self.grantRequests() == 1 }
            StubURLProtocol.delay = 0
            // Withdrawn while the grant answer is on its way: the grant may finish, the upload may not start.
            state.setThirdPartyAIConsent(false)
            try await TestSupport.waitUntil { self.service.jobs.first?.status == .waitingForPermission }
            XCTAssertNil(service.jobs.first?.meetingID, "nothing was transcribed")
            XCTAssertTrue(FileManager.default.fileExists(atPath: segment.path))
            XCTAssertEqual(grantRequests(), 1)
        }
    }

    func testEachSeparatePartUploadChecksPermissionFirst() async throws {
        // Review 2026-10-27: after a failed join, every part is its own upload.
        @MainActor final class Checks { var count = 0 }
        let checks = Checks()
        let parts = [(url: URL(fileURLWithPath: "/tmp/p0.m4a"), offset: 0.0), (url: URL(fileURLWithPath: "/tmp/p1.m4a"), offset: 300.0)]
        do {
            _ = try await WatchTranscriptionClient.transcribeParts(parts, language: "en", credential: .init(scheme: "Token", token: "x"), mayContinue: { checks.count += 1; return false })
            XCTFail("expected permissionWithdrawn")
        } catch WatchTranscriptionClient.Failure.permissionWithdrawn {
            XCTAssertEqual(checks.count, 1, "checked before the first upload, which therefore never left")
        }
    }

    func testStitchRequiresEveryPartAndNeverReplacesACompleteFileOnFailureOrCancellation() async throws {
        let dir = root.appendingPathComponent("stitch")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let good = dir.appendingPathComponent("good.m4a")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        // Scoped so the file header is finalised before anything reads it.
        try {
            let file = try AVAudioFile(forWriting: good, settings: WatchRecorder_settingsForTests(), commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
            buffer.frameLength = 16_000
            try file.write(from: buffer)
        }()
        let fixtureSeconds = try await AVURLAsset(url: good).load(.duration).seconds
        XCTAssertGreaterThan(fixtureSeconds, 0.5, "fixture must be readable")
        let bad = dir.appendingPathComponent("bad.m4a")
        try Data(repeating: 0, count: 2_000).write(to: bad)
        let output = dir.appendingPathComponent("joined.m4a")
        try await WatchTranscriptionClient.stitch([good], into: output)
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: good))
        do {
            try await WatchTranscriptionClient.stitch([good, bad], into: output)
            XCTFail("An unreadable later part must not publish a partial success")
        } catch {
        }
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: good))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await WatchTranscriptionClient.stitch([good], into: output)
        }
        do { try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: good))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix("join-") })
    }

    func testUnreadableManifestFailsTheJob() {
        let id = UUID()
        let t = WatchSegmentTransfer(recordingID: id, index: -1, offset: 0, duration: 1, startedAt: Date(), language: "en", isManifest: true)
        service.noteArrival(t, at: drop(t, contents: Data("nope".utf8)))
        XCTAssertEqual(service.jobs[0].status, .failed)
    }

    func testTransientRetryLadderIsDurableAndStopsAtEight() throws {
        let date = Date()
        var job = WatchImportJob(id: UUID(), startedAt: date, language: "en", status: .queued, message: nil,
            receivedIndexes: [0], expectedIndexes: [0], durationSeconds: 30, meetingID: nil, updatedAt: date)
        let delays: [TimeInterval] = [5, 15, 60, 300, 300, 300, 300]
        for delay in delays {
            job.deferTransient(now: date)
            XCTAssertEqual(job.nextEligibleAt, date.addingTimeInterval(delay))
            XCTAssertFalse(WatchImportService.eligible(job, now: date, permitted: true, minutesRemaining: 500))
            XCTAssertTrue(WatchImportService.eligible(job, now: date.addingTimeInterval(delay), permitted: true, minutesRemaining: 500))
        }
        job.deferTransient(now: date)
        XCTAssertEqual(job.status, .failed)
        XCTAssertEqual(job.attemptCount, 8)
        XCTAssertNil(job.nextEligibleAt)
        let decoded = try JSONDecoder().decode(WatchImportJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(decoded, job)
        job.status = .waitingForMinutes; job.quotaSnapshot = 0
        XCTAssertFalse(WatchImportService.eligible(job, now: date, permitted: true, minutesRemaining: 0))
        XCTAssertTrue(WatchImportService.eligible(job, now: date, permitted: true, minutesRemaining: 20))
        job.status = .waitingForPermission
        XCTAssertFalse(WatchImportService.eligible(job, now: date, permitted: false, minutesRemaining: 20))
    }

    func testBackgroundArrivalAndConnectionActivationKeepAudioUntilForeground() async throws {
        try await withCleanConsent {
            let state = try stubbedState(session: TestSupport.stubbedSession())
            service.appState = state
            service.sessionDeactivated()
            var started: [UUID] = []
            service.performJob = { started.append($0.id); self.service.sessionDeactivated() }
            let recording = try dropOnePartRecording()
            service.connectionActivated()
            service.kick()
            XCTAssertFalse(service.isRunning)
            XCTAssertTrue(started.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: recording.segment.path))
            service.sessionActivated()
            try await TestSupport.waitUntil { started.count == 1 }
            XCTAssertEqual(started, [recording.id])
        }
    }

    func testWorkerDoesNotSpinAfterOfflineGrantAndMovesToNextJob() async throws {
        try await withCleanConsent {
            StubURLProtocol.reset()
            defer { StubURLProtocol.reset(); service.sessionDeactivated() }
            let state = try stubbedState(session: TestSupport.stubbedSession())
            state.setThirdPartyAIConsent(true)
            service.appState = state
            StubURLProtocol.handler = { _ in (503, Data(#"{"error":"unavailable"}"#.utf8)) }
            let first = try dropOnePartRecording()
            let second = try dropOnePartRecording()
            try await TestSupport.waitUntil { self.service.jobs.count == 2 && self.service.jobs.allSatisfy { $0.attemptCount == 1 } }
            XCTAssertEqual(grantRequests(), 2)
            for _ in 0..<20 { service.kick() }
            await Task.yield()
            XCTAssertEqual(grantRequests(), 2)
            XCTAssertTrue(FileManager.default.fileExists(atPath: first.segment.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: second.segment.path))
            let restored = WatchImportService(root: root)
            XCTAssertTrue(restored.jobs.allSatisfy { $0.attemptCount == 1 && $0.nextEligibleAt != nil })
        }
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
        try FileManager.default.copyItem(at: parts[0], to: output)
        let incompleteReusable = try await WatchTranscriptionClient.canReuseJoinedAudio(output, parts: parts)
        XCTAssertFalse(incompleteReusable, "A previous first-part-only join must be rebuilt")
        try await WatchTranscriptionClient.stitch(parts, into: output)
        let completeReusable = try await WatchTranscriptionClient.canReuseJoinedAudio(output, parts: parts)
        XCTAssertTrue(completeReusable)
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
