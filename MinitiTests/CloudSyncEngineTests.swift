import Foundation
import SwiftData
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// A server in memory with the same rules as `/api/sync/*`: revision CAS, tombstones, the
/// trim guard, external-id uniqueness, a change feed with a retained window.
/// Holds named transport calls until released, so a test can act while a request is in flight.
final class CallGate: @unchecked Sendable {
    var holdNames: Set<String> = []
    private(set) var held = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait(_ name: String) async {
        guard holdNames.contains(name) else { return }
        held += 1
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        let waiting = waiters
        waiters = []
        held = 0
        holdNames = []
        waiting.forEach { $0.resume() }
    }
}

final class FakeCloudTransport: CloudSyncTransport, @unchecked Sendable {
    let gate = CallGate()

    struct Row {
        var revision: Int
        var deleted: Bool
        var updatedAt: Date
        var transcriptRevision: Int
        var document: [String: Any]
    }

    var rows: [UUID: Row] = [:]
    var changes: [(seq: Int, id: UUID)] = []
    var seq = 0
    var oldestRetainedSeq = 1
    var calls: [String] = []
    var respectsTaskCancellation = false
    var cancelNext = false
    var failNext: CloudSyncError?
    var failStatus: CloudSyncError?
    var failManifest: CloudSyncError?
    var omitBatchRows = false
    var omittedBatchIDs: Set<UUID> = []
    var tooLargeTitles: Set<String> = []
    var tier = "pro"
    var accountCloud: (enabled: Bool?, version: Int) = (nil, 0)
    /// Runs after a put is accepted and before the result is returned (simulates the user
    /// acting while an upload is in flight).
    var onPut: ((UUID) -> Void)?

    func setAccountCloud(enabled: Bool) async throws -> Int {
        calls.append("setAccountCloud:\(enabled)")
        try throwIfArmed()
        accountCloud = (enabled, accountCloud.version + 1)
        return accountCloud.version
    }

    private func throwIfArmed() throws {
        if respectsTaskCancellation { try Task.checkCancellation() }
        if cancelNext { cancelNext = false; throw CancellationError() }
        if let error = failNext { failNext = nil; throw error }
    }

    private func record(_ id: UUID) -> Int { seq += 1; changes.append((seq, id)); return seq }

    func seed(_ document: [String: Any], updatedAt: Date, transcriptRevision: Int = 0) -> UUID {
        let id = UUID(uuidString: document["id"] as! String)!
        rows[id] = Row(revision: 1, deleted: false, updatedAt: updatedAt, transcriptRevision: transcriptRevision, document: document)
        _ = record(id)
        return id
    }

    private func state(_ id: UUID, _ row: Row) -> CloudMeetingState {
        CloudMeetingState(id: id, revision: row.revision, deleted: row.deleted, updatedAt: row.updatedAt, document: row.deleted ? nil : row.document)
    }

    func manifest() async throws -> CloudManifest {
        calls.append("manifest"); await gate.wait("manifest"); try throwIfArmed()
        if let failManifest { throw failManifest }
        return CloudManifest(entries: rows.map { CloudManifestEntry(id: $0.key, revision: $0.value.revision, updatedAt: $0.value.updatedAt, deleted: $0.value.deleted) }, latestSeq: seq)
    }

    func changes(since: Int, limit: Int) async throws -> CloudChangesPage {
        calls.append("changes:\(since)"); await gate.wait("changes"); try throwIfArmed()
        if since == 0 || since < oldestRetainedSeq - 1 { throw CloudSyncError.cursorExpired }
        let page = changes.filter { $0.seq > since }.prefix(limit + 1)
        let hasMore = page.count > limit
        let slice = Array(page.prefix(limit))
        var last: [UUID: Int] = [:]
        for c in slice { last[c.id] = c.seq }
        let out = last.compactMap { id, s -> CloudChange? in
            guard let row = rows[id] else { return nil }
            return CloudChange(seq: s, id: id, revision: row.revision, deleted: row.deleted, updatedAt: row.updatedAt, document: row.deleted ? nil : row.document)
        }.sorted { $0.seq < $1.seq }
        return CloudChangesPage(changes: out, nextSince: slice.last?.seq ?? since, hasMore: hasMore, latestSeq: seq)
    }

    func fetchMeeting(id: UUID) async throws -> CloudMeetingState? {
        calls.append("get"); try throwIfArmed()
        return rows[id].map { state(id, $0) }
    }

    func fetchMeetings(ids: [UUID]) async throws -> [CloudMeetingState] {
        calls.append("batch:\(ids.count)"); await gate.wait("batch"); try throwIfArmed()
        return omitBatchRows ? [] : ids.filter { !omittedBatchIDs.contains($0) }.compactMap { id in rows[id].map { state(id, $0) } }
    }

    func putMeeting(id: UUID, baseRevision: Int, document data: Data, restoreDeleted: Bool = false) async throws -> CloudPutResult {
        calls.append("put"); await gate.wait("put"); try throwIfArmed()
        let document = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if tier != "pro" { throw CloudSyncError.proRequired }
        if let title = document["title"] as? String, tooLargeTitles.contains(title) { return .tooLarge }
        let updatedAt = MeetingSyncDocument.date(document["updated_at"]) ?? Date()
        let transcriptRevision = (document["transcript_revision"] as? NSNumber)?.intValue ?? 0
        if let source = document["external_source"] as? String, let external = document["external_id"] as? String {
            for (otherID, other) in rows where otherID != id && !other.deleted && (other.document["external_source"] as? String) == source && (other.document["external_id"] as? String) == external {
                return .externalDuplicate(existing: state(otherID, other))
            }
        }
        if let existing = rows[id] {
            if existing.revision != baseRevision || (existing.deleted && !restoreDeleted) || existing.transcriptRevision > transcriptRevision {
                return .conflict(state(id, existing))
            }
            let row = Row(revision: existing.revision + 1, deleted: false, updatedAt: updatedAt, transcriptRevision: transcriptRevision, document: document)
            rows[id] = row
            _ = record(id)
            onPut?(id)
            return .ok(revision: row.revision)
        }
        rows[id] = Row(revision: 1, deleted: false, updatedAt: updatedAt, transcriptRevision: transcriptRevision, document: document)
        _ = record(id)
        onPut?(id)
        return .ok(revision: 1)
    }

    func deleteMeeting(id: UUID, baseRevision: Int) async throws -> CloudDeleteResult {
        calls.append("delete"); await gate.wait("delete"); try throwIfArmed()
        guard var row = rows[id] else { return .ok(revision: 0) }
        if row.deleted { return .ok(revision: row.revision) }
        if row.revision != baseRevision { return .conflict(state(id, row)) }
        row.revision += 1; row.deleted = true; row.updatedAt = Date(); row.document = [:]
        rows[id] = row
        _ = record(id)
        return .ok(revision: row.revision)
    }

    func status() async throws -> CloudStatus {
        calls.append("status"); await gate.wait("status"); try throwIfArmed()
        if let failStatus { throw failStatus }
        let live = rows.values.filter { !$0.deleted }
        return CloudStatus(tier: tier, syncAllowed: tier == "pro", bytes: live.count * 1000, meetingCount: live.count, latestSeq: seq, email: nil, connectedApps: 0, tokens: 0)
    }

    func deleteCloudCopy() async throws {
        calls.append("deleteCloudCopy"); try throwIfArmed()
        rows = [:]; changes = []
    }

    func remoteDelete(_ id: UUID) {
        guard var row = rows[id] else { return }
        row.revision += 1; row.deleted = true; row.updatedAt = Date(); row.document = [:]
        rows[id] = row
        _ = record(id)
    }

    func remoteEdit(_ id: UUID, updatedAt: Date, _ change: (inout [String: Any]) -> Void) {
        guard var row = rows[id] else { return }
        change(&row.document)
        row.document["updated_at"] = MeetingSyncDocument.formatter.string(from: updatedAt)
        row.revision += 1; row.updatedAt = updatedAt
        if let r = (row.document["transcript_revision"] as? NSNumber)?.intValue { row.transcriptRevision = r }
        rows[id] = row
        _ = record(id)
    }
}

@MainActor
final class TestCloudHost: CloudSyncHost {
    let container: ModelContainer
    let context: ModelContext
    var pause: CloudSyncPause?
    var liveMeetingID: UUID?
    var allowSelectedUpload = false
    var cloudUploadProtectedMeetingID: UUID? { allowSelectedUpload ? nil : liveMeetingID }
    var fetchFails = false
    var commitFails = false
    var cloudAccountID: String? = "acct_test"
    var deleted: Set<UUID> = []
    var inserted: [UUID] = []
    var changedCount = 0
    var changedMeetingIDs: [UUID] = []
    var tierChanges: [Bool] = []
    var fetchedMeetingRows = 0

    init() throws {
        container = try TestSupport.makeInMemoryContainer()
        context = ModelContext(container)
    }

    var cloudModelContext: ModelContext? { context }
    var cloudPauseReason: CloudSyncPause? { pause }
    func isMeetingDeleted(_ id: UUID) -> Bool { deleted.contains(id) }
    func cloudRemoveLocally(_ meeting: Meeting) { deleted.insert(meeting.id); context.delete(meeting) }
    func cloudCommit(_ mutate: @escaping () -> Void) -> Bool { mutate(); if commitFails { return false }; do { try context.save(); return true } catch { return false } }
    func cloudFetchMeetings(_ descriptor: FetchDescriptor<Meeting>) -> [Meeting]? {
        guard !fetchFails, let rows = try? context.fetch(descriptor) else { return nil }
        fetchedMeetingRows += rows.count
        return rows
    }
    func cloudFetchTombstones() -> [MeetingTombstone]? { try? context.fetch(FetchDescriptor<MeetingTombstone>()) }
    func cloudDidInsertMeetings(_ meetings: [Meeting]) { inserted += meetings.map(\.id) }
    func cloudDidChangeMeetings(_ updated: [Meeting]) { changedCount += 1; changedMeetingIDs += updated.map(\.id) }
    func cloudTierChanged(isPro: Bool) { tierChanges.append(isPro) }

    /// What the app does on a user delete: bookkeeping, tombstone when the cloud knows, delete.
    func userDelete(_ meeting: Meeting) {
        deleted.insert(meeting.id)
        if meeting.cloudRevision > 0 { context.insert(MeetingTombstone(id: meeting.id, cloudRevision: meeting.cloudRevision)) }
        context.delete(meeting)
        try? context.save()
    }

    func meeting(_ id: UUID) -> Meeting? {
        (try? context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })))?.first
    }

    func allMeetings() -> [Meeting] { (try? context.fetch(FetchDescriptor<Meeting>())) ?? [] }
}

@MainActor
final class CloudSyncEngineTests: XCTestCase {
    private var host: TestCloudHost!
    private var transport: FakeCloudTransport!
    private var engine: CloudSyncEngine!
    private var clock = Date(timeIntervalSince1970: 1_790_100_000)

    override func setUp() async throws {
        host = try TestCloudHost()
        transport = FakeCloudTransport()
        engine = CloudSyncEngine()
        engine.host = host
        engine.transport = transport
        engine.defaults = UserDefaults(suiteName: "CloudSyncEngineTests-\(UUID().uuidString)")!
        engine.sleep = { _ in }
        engine.now = { [unowned self] in self.clock }
    }

    @discardableResult
    private func finished(_ title: String, start: TimeInterval = 1_790_000_000, segments: Int = 2, excluded: Bool = false) -> Meeting {
        let meeting = Meeting(title: title, startTime: Date(timeIntervalSince1970: start), endTime: Date(timeIntervalSince1970: start + 600))
        for i in 0..<segments { meeting.segments.append(TranscriptSegment(text: "\(title) line \(i)", speaker: i % 2, timestamp: Double(i), isFinal: true)) }
        meeting.syncExcluded = excluded
        host.context.insert(meeting)
        try? host.context.save()
        return meeting
    }

    private func remoteDocument(_ id: UUID = UUID(), title: String, updatedAt: Date) -> [String: Any] {
        [
            "schema_version": 1, "id": id.uuidString.lowercased(), "title": title,
            "start_time": "2026-09-20T09:00:00.000Z", "end_time": "2026-09-20T09:30:00.000Z",
            "updated_at": MeetingSyncDocument.formatter.string(from: updatedAt), "language": "en", "transcript_revision": 0,
            "segments": [["id": UUID().uuidString.lowercased(), "speaker": 0, "text": "From the other device", "start": 0.0, "final": true, "confidence": 1.0]],
            "speaker_names": ["0": "Remote"], "summary": "Remote summary", "action_items": ["Call back"], "notes": "", "pinned": false,
        ]
    }

    private func tick() async { clock = clock.addingTimeInterval(10); await settle(); await engine.sync(reason: "test") }

    /// A refreshPause that opens the gates kicks an async pass; wait for it before asserting.
    private func settle() async {
        // A kicked pass starts on a later main-actor turn: give it a moment to begin, then wait.
        try? await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<400 where engine.isRunning { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testBusySyncRetriesQuietlyAndPreservesTheEdit() async throws {
        let meeting = finished("Pending folder edit")
        var waits: [TimeInterval] = []
        engine.sleep = { waits.append($0) }
        transport.failNext = .busy(retryAfter: 2)
        await engine.sync(reason: "change")
        XCTAssertEqual(waits, [2])
        XCTAssertNotNil(transport.rows[meeting.id])
        XCTAssertFalse(engine.log.contains { $0.kind == .error })
        XCTAssertNil(engine.lastError)
    }

    func testPersistentBusyHasBoundedRetriesAndKeepsLocalWorkForNextPoll() async throws {
        let meeting = finished("Keep this edit")
        var waits = 0
        engine.sleep = { _ in waits += 1 }
        transport.failManifest = .busy(retryAfter: 2)
        await engine.sync(reason: "change")
        XCTAssertEqual(waits, 2)
        XCTAssertFalse(engine.isRunning)
        XCTAssertFalse(engine.log.contains { $0.kind == .error })
        XCTAssertNil(engine.lastError)
        transport.failManifest = nil
        await engine.sync(reason: "poll")
        XCTAssertNotNil(transport.rows[meeting.id])
    }

    // MARK: 3.6.0 automatic completion and truthful status

    func testStoppedSelectedMeetingUploadsOnLifecycleChangeWithoutOpeningSettings() async throws {
        let meeting = finished("Stopped and visible")
        host.liveMeetingID = meeting.id
        await engine.sync(reason: "poll")
        XCTAssertNil(transport.rows[meeting.id])
        XCTAssertEqual(engine.protectedMeetingCount, 1)
        host.allowSelectedUpload = true
        engine.noteLifecycleChange()
        await settle()
        XCTAssertEqual(transport.rows[meeting.id]?.document["title"] as? String, meeting.title)
        XCTAssertEqual(engine.status?.meetingCount, 1)
        XCTAssertEqual(engine.pendingUploadCount, 0)
        XCTAssertEqual(host.liveMeetingID, meeting.id)
    }

    func testAutomaticChangesRefreshCountWithoutManualSyncAndNoopPollUsesFreshness() async throws {
        await engine.sync(reason: "poll")
        XCTAssertEqual(engine.status?.meetingCount, 0)
        let meeting = finished("Automatic")
        engine.noteLocalChange()
        await settle()
        XCTAssertEqual(engine.status?.meetingCount, 1)
        let count = transport.calls.filter { $0 == "status" }.count
        await engine.sync(reason: "poll")
        XCTAssertEqual(transport.calls.filter { $0 == "status" }.count, count)
        clock = clock.addingTimeInterval(CloudSyncEngine.statusFreshness)
        XCTAssertTrue(engine.statusIsStale)
        await engine.sync(reason: "poll")
        XCTAssertFalse(engine.statusIsStale)
        XCTAssertEqual(transport.calls.filter { $0 == "status" }.count, count + 1)
        host.userDelete(meeting)
        engine.noteLocalChange()
        await settle()
        XCTAssertEqual(engine.status?.meetingCount, 0)
        XCTAssertEqual(engine.pendingRemovalCount, 0)
    }

    func testFailedCountRefreshRetainsAcceptedUploadAndMarksCountLastKnown() async throws {
        await engine.sync(reason: "poll")
        let checked = engine.statusFetchedAt
        transport.failStatus = .offline
        let meeting = finished("Saved remotely")
        await engine.sync(reason: "change")
        XCTAssertEqual(meeting.cloudRevision, 1)
        XCTAssertEqual(meeting.syncFingerprint, MeetingSyncDocument.fingerprint(of: meeting))
        XCTAssertEqual(engine.status?.meetingCount, 0)
        XCTAssertEqual(engine.statusFetchedAt, checked)
        XCTAssertTrue(engine.statusRefreshFailed)
        XCTAssertTrue(engine.statusIsStale)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.pendingUploadCount, 0)
        transport.failStatus = nil
        await engine.sync(reason: "poll")
        XCTAssertEqual(engine.status?.meetingCount, 1)
        XCTAssertFalse(engine.statusRefreshFailed)
    }

    func testFailedLocalScanOrSaveDoesNotUploadOrClaimFreshCheck() async throws {
        let meeting = finished("Uncommitted scan")
        host.fetchFails = true
        await engine.sync(reason: "change")
        XCTAssertNil(engine.lastSyncedAt)
        XCTAssertTrue(engine.scanFailed)
        XCTAssertFalse(transport.calls.contains("put"))
        host.fetchFails = false
        host.commitFails = true
        await engine.sync(reason: "change")
        XCTAssertNil(engine.lastSyncedAt)
        XCTAssertFalse(transport.calls.contains("put"))
        host.commitFails = false
        await engine.sync(reason: "poll")
        XCTAssertEqual(transport.rows[meeting.id]?.revision, 1)
        XCTAssertFalse(engine.scanFailed)
    }

    func testResumeDuringUploadNeverCertifiesNewerTranscriptOrAppliesConflict() async throws {
        let meeting = finished("Before resume")
        transport.gate.holdNames = ["put"]
        let task = Task { await self.engine.sync(reason: "change") }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        host.liveMeetingID = meeting.id
        meeting.endTime = nil
        meeting.segments.append(TranscriptSegment(text: "New speech", speaker: 0, timestamp: 601, isFinal: true))
        try host.context.save()
        transport.gate.release()
        await task.value
        XCTAssertEqual(meeting.segments.last?.text, "New speech")
        XCTAssertNil(meeting.endTime)
        XCTAssertNotEqual(meeting.syncFingerprint, MeetingSyncDocument.fingerprint(of: meeting))
        XCTAssertEqual(transport.calls.filter { $0 == "put" }.count, 1)
        XCTAssertEqual(engine.protectedMeetingCount, 1)
    }

    func testEditDuringAcceptedUploadSchedulesSuccessorAndKeepsLatestContent() async throws {
        let meeting = finished("First revision")
        transport.onPut = { [unowned self] id in
            self.transport.onPut = nil
            meeting.title = "Second revision"
            try? self.host.context.save()
            self.engine.noteLocalChange()
        }
        await engine.sync(reason: "change")
        await settle()
        XCTAssertEqual(transport.rows[meeting.id]?.document["title"] as? String, "Second revision")
        XCTAssertEqual(meeting.syncFingerprint, MeetingSyncDocument.fingerprint(of: meeting))
        XCTAssertEqual(engine.pendingUploadCount, 0)
        XCTAssertEqual(engine.status?.meetingCount, 1)
    }

    func testSelectedStoppedMeetingKeepsLocalStateWhenRemoteConflictArrives() async throws {
        let meeting = finished("Visible local")
        host.liveMeetingID = meeting.id
        host.allowSelectedUpload = true
        _ = transport.seed(remoteDocument(meeting.id, title: "Remote", updatedAt: clock.addingTimeInterval(100)), updatedAt: clock.addingTimeInterval(100))
        await engine.sync(reason: "change")
        XCTAssertEqual(meeting.title, "Visible local")
        XCTAssertEqual(engine.pendingUploadCount, 1)
        XCTAssertEqual(engine.idleLabel, "Changes waiting to sync")
        host.liveMeetingID = nil
        engine.noteLifecycleChange()
        await settle()
        XCTAssertEqual(meeting.title, "Remote")
        XCTAssertEqual(engine.pendingUploadCount, 0)
    }

    func testACommitDuringPullKeepsNewerLocalEditsAndRerunsAutomatically() async throws {
        let meeting = finished("Before pull")
        await engine.sync(reason: "change")
        transport.remoteEdit(meeting.id, updatedAt: clock.addingTimeInterval(1)) { $0["title"] = "Remote edit" }
        transport.gate.holdNames = ["changes"]
        let task = Task { await self.engine.sync(reason: "poll") }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        clock = clock.addingTimeInterval(20)
        meeting.title = "Local edited during pull"
        try host.context.save()
        engine.noteLocalChange()
        transport.gate.release()
        await task.value
        await settle()
        XCTAssertEqual(meeting.title, "Local edited during pull")
        XCTAssertEqual(transport.rows[meeting.id]?.document["title"] as? String, meeting.title)
        XCTAssertEqual(engine.pendingUploadCount, 0)
    }

    func testCommittedEditDeferralDoesNotStampSuccessBeforeItsFailedRerun() async throws {
        let meeting = finished("Before held pull")
        await engine.sync(reason: "change")
        let previousCheck = engine.lastSyncedAt
        let statusCalls = transport.calls.filter { $0 == "status" }.count
        transport.gate.holdNames = ["changes"]
        let task = Task { await self.engine.sync(reason: "poll") }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        clock = clock.addingTimeInterval(20)
        meeting.title = "Saved during pull"
        try host.context.save()
        engine.noteLocalChange()
        transport.failManifest = .offline
        transport.gate.release()
        await task.value
        await settle()
        XCTAssertEqual(engine.phase, .paused(.offline))
        XCTAssertEqual(engine.lastSyncedAt, previousCheck)
        XCTAssertEqual(transport.calls.filter { $0 == "status" }.count, statusCalls)
        XCTAssertEqual(meeting.title, "Saved during pull")
        transport.failManifest = nil
        await engine.sync(reason: "poll")
        XCTAssertEqual(transport.rows[meeting.id]?.document["title"] as? String, meeting.title)
        XCTAssertGreaterThan(try XCTUnwrap(engine.lastSyncedAt), try XCTUnwrap(previousCheck))
    }

    func testFailedPulledCommitDoesNotAdvanceCursorAndRetriesDurability() async throws {
        await engine.sync(reason: "poll")
        let cursorKey = CloudSyncEngine.cursorKey("acct_test")
        let before = engine.defaults.integer(forKey: cursorKey)
        // Ensure a change strictly beyond the initial cursor.
        _ = transport.seed(remoteDocument(title: "First", updatedAt: clock), updatedAt: clock)
        let remote = transport.seed(remoteDocument(title: "Second", updatedAt: clock), updatedAt: clock)
        transport.gate.holdNames = ["changes"]
        let task = Task { await self.engine.sync(reason: "poll") }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        host.commitFails = true
        transport.gate.release()
        await task.value
        XCTAssertEqual(engine.defaults.integer(forKey: cursorKey), before)
        XCTAssertTrue(engine.scanFailed)
        host.commitFails = false
        await engine.sync(reason: "poll")
        XCTAssertNotNil(host.meeting(remote))
        XCTAssertGreaterThan(engine.defaults.integer(forKey: cursorKey), before)
        XCTAssertFalse(engine.scanFailed)
    }

    func testChangesBeyondTheFivePassCapAreNotDropped() async throws {
        let meeting = finished("Revision 0")
        var changes = 0
        transport.onPut = { [unowned self] _ in
            guard changes < 6 else { self.transport.onPut = nil; return }
            changes += 1
            meeting.title = "Revision \(changes)"
            try? self.host.context.save()
            self.engine.noteLocalChange()
        }
        await engine.sync(reason: "change")
        await settle()
        XCTAssertEqual(changes, 6)
        XCTAssertEqual(transport.rows[meeting.id]?.document["title"] as? String, "Revision 6")
        XCTAssertEqual(meeting.syncFingerprint, MeetingSyncDocument.fingerprint(of: meeting))
        XCTAssertEqual(engine.pendingUploadCount, 0)
    }

    func testFailedLifecycleReconcileRetainsSkippedIncomingChangesForNextPoll() async throws {
        let meeting = finished("Before remote change")
        await engine.sync(reason: "change")
        host.liveMeetingID = meeting.id
        host.allowSelectedUpload = true
        transport.remoteEdit(meeting.id, updatedAt: clock.addingTimeInterval(10)) { $0["title"] = "Remote while selected" }
        await engine.sync(reason: "poll")
        XCTAssertEqual(meeting.title, "Before remote change")
        let skippedCursor = engine.defaults.integer(forKey: CloudSyncEngine.cursorKey("acct_test"))
        XCTAssertEqual(skippedCursor, transport.seq)

        host.liveMeetingID = nil
        transport.failNext = .offline
        engine.noteLifecycleChange()
        await settle()
        XCTAssertEqual(engine.phase, .paused(.offline))
        XCTAssertEqual(meeting.title, "Before remote change")
        let manifests = transport.calls.filter { $0 == "manifest" }.count
        await engine.sync(reason: "poll")
        XCTAssertEqual(transport.calls.filter { $0 == "manifest" }.count, manifests + 1)
        XCTAssertEqual(meeting.title, "Remote while selected")
    }

    func testUnsavedEditDuringHeldPullCannotBeOverwrittenBeforeItsSaveNotification() async throws {
        let meeting = finished("Before pull")
        await engine.sync(reason: "change")
        transport.remoteEdit(meeting.id, updatedAt: clock.addingTimeInterval(10)) { $0["title"] = "Remote edit" }
        let cursorKey = CloudSyncEngine.cursorKey("acct_test")
        let previousCursor = engine.defaults.integer(forKey: cursorKey)
        let previousCheck = engine.lastSyncedAt
        let statusCalls = transport.calls.filter { $0 == "status" }.count
        transport.gate.holdNames = ["changes"]
        let task = Task { await self.engine.sync(reason: "poll") }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        clock = clock.addingTimeInterval(20)
        meeting.title = "Unsaved local edit"
        XCTAssertTrue(host.context.hasChanges)
        // Deliberately no context.save or noteLocalChange: this is the UI-to-save window.
        transport.gate.release()
        await task.value
        XCTAssertEqual(meeting.title, "Unsaved local edit")
        XCTAssertEqual(engine.defaults.integer(forKey: cursorKey), previousCursor)
        XCTAssertTrue(engine.waitingForLocalEdits)
        XCTAssertEqual(engine.idleLabel, "Waiting for local edits to save")
        XCTAssertEqual(engine.lastSyncedAt, previousCheck)
        XCTAssertEqual(transport.calls.filter { $0 == "status" }.count, statusCalls)
        await engine.sync(reason: "poll")
        XCTAssertFalse(engine.waitingForLocalEdits)
        XCTAssertEqual(meeting.title, "Unsaved local edit")
        XCTAssertEqual(transport.rows[meeting.id]?.document["title"] as? String, "Unsaved local edit")
        XCTAssertEqual(engine.pendingUploadCount, 0)
    }

    func testUnsavedEditsDuringManifestAndBatchDoNotClaimCompletedChecks() async throws {
        let meeting = finished("Saved before check")
        await engine.sync(reason: "change")
        for heldCall in ["manifest", "batch"] {
            clock = clock.addingTimeInterval(20)
            transport.remoteEdit(meeting.id, updatedAt: clock) { $0["notes"] = "remote notes" }
            engine.resetBookkeepingCursorOnly()
            let completedAt = engine.lastSyncedAt
            let statusCalls = transport.calls.filter { $0 == "status" }.count
            transport.gate.holdNames = [heldCall]
            let checking = Task { await self.engine.sync(reason: "poll") }
            try await TestSupport.waitUntil { self.transport.gate.held == 1 }
            clock = clock.addingTimeInterval(20)
            meeting.notes = "unsaved during " + heldCall
            transport.gate.release()
            await checking.value
            XCTAssertTrue(engine.waitingForLocalEdits, heldCall)
            XCTAssertEqual(engine.lastSyncedAt, completedAt, heldCall)
            XCTAssertEqual(transport.calls.filter { $0 == "status" }.count, statusCalls, heldCall)
            XCTAssertEqual(meeting.notes, "unsaved during " + heldCall)
            await engine.sync(reason: "poll")
            XCTAssertFalse(engine.waitingForLocalEdits, heldCall)
            XCTAssertEqual(transport.rows[meeting.id]?.document["notes"] as? String, "unsaved during " + heldCall)
        }
    }

    func testStopLifecycleCoalescesChecksAndOnlyReconcilesSkippedIncomingRows() async throws {
        let meeting = finished("Recording")
        host.liveMeetingID = meeting.id
        _ = transport.seed(remoteDocument(title: "Other device", updatedAt: clock), updatedAt: clock)
        await engine.sync(reason: "poll")
        transport.calls = []
        host.allowSelectedUpload = true
        engine.noteLifecycleChange()
        engine.noteLifecycleChange()
        engine.noteLifecycleChange()
        await settle()
        XCTAssertEqual(transport.calls.filter { $0 == "put" }.count, 1)
        XCTAssertEqual(transport.calls.filter { $0 == "manifest" }.count, 0, "stop eligibility does not require a manifest")
        XCTAssertEqual(transport.calls.filter { $0 == "status" }.count, 1, "accepted upload refreshes count once")
        XCTAssertNil(engine.pendingChangesCaption)
        transport.calls = []
        engine.noteLifecycleChange() // final AI completion with no incoming change skipped
        await settle()
        XCTAssertTrue(transport.calls.isEmpty)

        transport.remoteEdit(meeting.id, updatedAt: clock.addingTimeInterval(30)) { $0["title"] = "Remote while selected" }
        await engine.sync(reason: "poll")
        XCTAssertEqual(meeting.title, "Recording")
        transport.calls = []
        host.liveMeetingID = nil
        engine.noteLifecycleChange()
        engine.noteLifecycleChange()
        await settle()
        XCTAssertEqual(meeting.title, "Remote while selected")
        XCTAssertEqual(transport.calls.filter { $0 == "manifest" }.count, 1, "release retries the skipped row once")
        XCTAssertEqual(transport.calls.filter { $0 == "status" }.count, 0, "unchanged manifest does not re-fetch a fresh count")
    }

    func testCredentialInvalidationPreservesReconcileForProtectedIncomingChanges() async throws {
        let meeting = finished("Before repair")
        await engine.sync(reason: "change")
        host.liveMeetingID = meeting.id
        host.allowSelectedUpload = true
        transport.remoteEdit(meeting.id, updatedAt: clock.addingTimeInterval(20)) { $0["title"] = "Remote before repair" }
        await engine.sync(reason: "poll")
        XCTAssertEqual(meeting.title, "Before repair")
        let cursor = engine.defaults.integer(forKey: CloudSyncEngine.cursorKey("acct_test"))
        engine.invalidatePasses(reason: "same-account credential replacement")
        XCTAssertEqual(engine.defaults.integer(forKey: CloudSyncEngine.cursorKey("acct_test")), cursor)
        host.liveMeetingID = nil
        engine.noteLifecycleChange()
        await engine.sync(reason: "poll")
        XCTAssertEqual(meeting.title, "Remote before repair")
    }

    func testProtectedRowMissingFromManifestReuploadsAfterSelectionReleases() async throws {
        let meeting = finished("Keep local copy")
        await engine.sync(reason: "change")
        host.liveMeetingID = meeting.id
        host.allowSelectedUpload = true
        transport.rows = [:] // server purged the cloud copy, retaining its sequence watermark
        engine.resetBookkeepingCursorOnly()
        await engine.sync(reason: "poll")
        XCTAssertGreaterThan(meeting.cloudRevision, 0, "protected row is not repointed during reconciliation")
        XCTAssertNil(transport.rows[meeting.id])
        host.liveMeetingID = nil
        engine.noteLifecycleChange()
        await settle()
        XCTAssertEqual(transport.rows[meeting.id]?.document["title"] as? String, "Keep local copy")
        XCTAssertEqual(meeting.syncFingerprint, MeetingSyncDocument.fingerprint(of: meeting))
    }

    func testPendingCaptionOmitsZeroOperations() async throws {
        let meeting = finished("Waiting to upload")
        transport.gate.holdNames = ["put"]
        let uploading = Task { await self.engine.sync(reason: "change") }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        XCTAssertEqual(engine.pendingChangesCaption, "This device: 1 upload waiting.")
        transport.gate.release()
        await uploading.value
        host.userDelete(meeting)
        transport.gate.holdNames = ["delete"]
        let deleting = Task { await self.engine.sync(reason: "change") }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        XCTAssertEqual(engine.pendingChangesCaption, "This device: 1 removal waiting.")
        transport.gate.release()
        await deleting.value
        XCTAssertNil(engine.pendingChangesCaption)
    }

    // MARK: Push

    func testExclusionDuringTheFirstUploadKeepsLocalContentAndDeletesTheAcceptedCopy() async throws {
        let meeting = finished("Keep here")
        let id = meeting.id
        transport.gate.holdNames = ["put"]
        let syncing = Task { await engine.sync(reason: "test") }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        XCTAssertTrue(engine.isUploading(id))
        XCTAssertEqual(meeting.cloudRevision, 0)
        meeting.syncExcluded = true
        try host.context.save()
        transport.gate.release()
        await syncing.value
        XCTAssertFalse(engine.isUploading(id))
        await settle()
        XCTAssertTrue(meeting.syncExcluded)
        XCTAssertEqual(host.meeting(id)?.title, "Keep here")
        XCTAssertEqual(meeting.cloudRevision, 0)
        XCTAssertNil(meeting.syncFingerprint)
        XCTAssertTrue(transport.rows[id]?.deleted == true)
        XCTAssertEqual(transport.calls.filter { $0 == "put" }.count, 1)
        XCTAssertTrue(try host.context.fetch(FetchDescriptor<MeetingTombstone>()).isEmpty)
    }

    func testAnExcludedMeetingSurvivesRemoteChangesAndDeletionDuringReconcile() async throws {
        let meeting = finished("Keep local title", excluded: true)
        _ = transport.seed(remoteDocument(meeting.id, title: "Do not apply", updatedAt: clock), updatedAt: clock)
        await tick()
        XCTAssertEqual(host.meeting(meeting.id)?.title, "Keep local title")
        XCTAssertTrue(meeting.syncExcluded)
        XCTAssertTrue(transport.rows[meeting.id]?.deleted == true)
        XCTAssertFalse(transport.calls.contains("put"))
        await tick()
        XCTAssertNotNil(host.meeting(meeting.id), "the cloud deletion must not delete the excluded local original")
    }

    func testAQueuedUploadIsSkippedWhenExcludedDuringAnEarlierUpload() async throws {
        _ = finished("First")
        let second = finished("Second", start: 1_790_000_700)
        transport.onPut = { _ in second.syncExcluded = true }
        await tick()
        XCTAssertNil(transport.rows[second.id])
        XCTAssertTrue(second.syncExcluded)
    }

    func testAnExplicitPutOnCloudRestoresTheExcludedOriginalButOrdinarySyncDoesNot() async throws {
        let meeting = finished("Original")
        await tick()
        meeting.syncExcluded = true
        host.context.insert(MeetingTombstone(id: meeting.id, cloudRevision: meeting.cloudRevision))
        meeting.cloudRevision = 0
        meeting.syncFingerprint = nil
        try host.context.save()
        await tick()
        XCTAssertTrue(transport.rows[meeting.id]?.deleted == true)
        XCTAssertNotNil(host.meeting(meeting.id))
        meeting.syncExcluded = false
        meeting.cloudRestoreRequested = true
        meeting.syncStateRaw = "pending_folder_refresh"
        try host.context.save()
        engine.noteLocalChange()
        await tick()
        XCTAssertFalse(transport.rows[meeting.id]?.deleted ?? true)
        XCTAssertEqual(host.meeting(meeting.id)?.title, "Original")
        XCTAssertFalse(meeting.cloudRestoreRequested)
        XCTAssertNil(meeting.syncStateRaw)
        XCTAssertEqual(meeting.cloudRevision, 3)
    }

    func testUndoCloudExclusionBeforeSyncPreservesBothCopies() async throws {
        let meeting = finished("Restored before removal")
        await tick()
        let state = AppState()
        state.modelContext = host.context
        state.cloudSyncEnabled = false
        XCTAssertTrue(state.setMeetingExcludedFromCloud(meeting, excluded: true))
        XCTAssertEqual(host.cloudFetchTombstones()?.count, 1)
        XCTAssertTrue(state.setMeetingExcludedFromCloud(meeting, excluded: false))
        XCTAssertTrue(host.cloudFetchTombstones()?.isEmpty == true)
        engine.noteLocalChange()
        transport.calls.removeAll()
        await tick()
        await tick()
        XCTAssertNotNil(host.meeting(meeting.id))
        XCTAssertFalse(transport.rows[meeting.id]?.deleted ?? true)
        XCTAssertFalse(transport.calls.contains("delete"))
        XCTAssertFalse(meeting.cloudRestoreRequested)
    }

    func testStaleCloudOnlyRemovalCannotDeleteARestoredLocalMeeting() async throws {
        let meeting = finished("Restored on older app")
        await tick()
        host.context.insert(MeetingTombstone(id: meeting.id, cloudRevision: meeting.cloudRevision))
        meeting.cloudRestoreRequested = true
        meeting.syncFingerprint = nil
        try host.context.save()
        engine.noteLocalChange()
        transport.calls.removeAll()
        await tick()
        await tick()
        XCTAssertNotNil(host.meeting(meeting.id))
        XCTAssertFalse(transport.rows[meeting.id]?.deleted ?? true)
        XCTAssertFalse(transport.calls.contains("delete"))
        XCTAssertTrue(host.cloudFetchTombstones()?.isEmpty == true)
    }

    func testThousandMeetingFolderUpgradeUsesBoundedLocalFetches() async throws {
        let count = 1_000
        for index in 0..<count {
            let meeting = finished("Upgrade \(index)", start: 1_790_000_000 + Double(index), segments: 0)
            let document = MeetingSyncDocument.encode(meeting, segments: [])
            _ = transport.seed(document, updatedAt: meeting.updatedAt ?? clock)
            meeting.cloudRevision = 1
            meeting.syncFingerprint = MeetingSyncDocument.fingerprint(of: meeting)
            meeting.syncedContentFingerprint = nil
            meeting.syncedFolderFingerprint = nil
            MeetingSyncDocument.promoteLegacyFolderFields(meeting)
        }
        try host.context.save()
        host.fetchedMeetingRows = 0
        let start = Date()
        await tick()
        let elapsed = Date().timeIntervalSince(start)
        print("FOLDER_UPGRADE_PROFILE: \(count) meetings, \(host.fetchedMeetingRows) fetched rows, \(elapsed)s")
        XCTAssertLessThan(host.fetchedMeetingRows, count * 30, "Single-ID lookups must not fetch the full history per row")
        XCTAssertEqual(host.allMeetings().count, count)
        XCTAssertEqual(engine.pendingFolderRefreshCount, 0)
        XCTAssertTrue(host.allMeetings().allSatisfy { $0.syncedFolderFingerprint != nil })
    }

    func testFirstSyncUploadsFinishedMeetingsOnly() async throws {
        let a = finished("Alpha")
        let b = finished("Beta", start: 1_790_000_700)
        let excluded = finished("Private", excluded: true)
        let live = Meeting(title: "Live", startTime: Date())
        host.context.insert(live)
        let stopped = finished("Stopped but open")
        host.liveMeetingID = stopped.id
        try host.context.save()

        await tick()

        XCTAssertEqual(Set(transport.rows.keys), [a.id, b.id])
        XCTAssertEqual(a.cloudRevision, 1)
        XCTAssertEqual(b.cloudRevision, 1)
        XCTAssertNotNil(a.syncedAt)
        XCTAssertNotNil(a.syncFingerprint)
        XCTAssertEqual(a.syncFingerprint, a.localFingerprint)
        XCTAssertEqual(excluded.cloudRevision, 0)
        XCTAssertEqual(live.cloudRevision, 0)
        XCTAssertEqual(stopped.cloudRevision, 0)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNotNil(engine.lastSyncedAt)
        XCTAssertEqual(transport.rows[a.id]?.document["title"] as? String, "Alpha")
        XCTAssertEqual((transport.rows[a.id]?.document["segments"] as? [[String: Any]])?.count, 2)
        XCTAssertTrue(transport.calls.first == "manifest", "a fresh device reconciles before pushing")
        // Nothing dirty: the next pass makes no put.
        let puts = transport.calls.filter { $0 == "put" }.count
        await tick()
        XCTAssertEqual(transport.calls.filter { $0 == "put" }.count, puts)
    }

    func testLocalEditIsPushedAgainstTheCloudRevision() async throws {
        let a = finished("Alpha")
        await tick()
        a.title = "Alpha renamed"
        a.isPinned = true
        try host.context.save()
        await tick()
        XCTAssertEqual(transport.rows[a.id]?.revision, 2)
        XCTAssertEqual(transport.rows[a.id]?.document["title"] as? String, "Alpha renamed")
        XCTAssertEqual(a.cloudRevision, 2)
        XCTAssertEqual(a.updatedAt, clock, "the engine stamps the edit when it notices it")
    }

    func testLegacyMeetingKeepsItsOwnTimestampOnFirstObservation() async throws {
        let a = finished("Old")
        a.insightsUpdatedAt = Date(timeIntervalSince1970: 1_790_005_000)
        try host.context.save()
        await tick()
        XCTAssertEqual(a.updatedAt, Date(timeIntervalSince1970: 1_790_005_000))
    }

    func testFolderOnlyEditPreservesUnseenRemoteNotes() async throws {
        let meeting = finished("Customer call")
        await tick()
        transport.remoteEdit(meeting.id, updatedAt: clock.addingTimeInterval(5)) {
            $0["notes"] = "Notes edited on the older client"
        }
        MeetingSyncDocument.prepareFolderEdit(meeting)
        let folder = UUID()
        meeting.folderID = folder; meeting.folderManual = true
        try host.context.save()
        clock = clock.addingTimeInterval(60)
        await engine.sync(reason: "test")
        XCTAssertEqual(meeting.notes, "Notes edited on the older client")
        XCTAssertEqual(meeting.folderID, folder)
        XCTAssertEqual(transport.rows[meeting.id]?.document["notes"] as? String, meeting.notes)
        XCTAssertEqual(transport.rows[meeting.id]?.document["folder_id"] as? String, folder.uuidString.lowercased())
    }

    func testFolderOnlyEditsPreserveRemoteNotesBeyondPushBatchAndDuringReconcile() async throws {
        let meetings = (0...CloudSyncEngine.pushBatch).map { finished("Bulk \($0)", segments: 0) }
        await tick()
        for reconcile in [false, true] {
            for meeting in meetings {
                transport.remoteEdit(meeting.id, updatedAt: clock.addingTimeInterval(5)) {
                    $0["notes"] = "Unseen remote edit \(reconcile)"
                }
                MeetingSyncDocument.prepareFolderEdit(meeting)
                meeting.folderID = UUID(); meeting.folderManual = true
            }
            try host.context.save()
            clock = clock.addingTimeInterval(60)
            if reconcile {
                // Fresh engine has no feed cursor, so it must reconcile before pushing.
                engine = CloudSyncEngine(); engine.host = host; engine.transport = transport
                engine.defaults = UserDefaults(suiteName: "FolderReconcile-\(UUID())")!
                engine.sleep = { _ in }; engine.now = { [unowned self] in self.clock }
            }
            await engine.sync(reason: "test")
            for meeting in meetings {
                XCTAssertEqual(meeting.notes, "Unseen remote edit \(reconcile)")
                XCTAssertEqual(transport.rows[meeting.id]?.document["notes"] as? String, meeting.notes)
                XCTAssertEqual(transport.rows[meeting.id]?.document["folder_id"] as? String, meeting.folderID?.uuidString.lowercased())
            }
        }
    }

    func testContentEditsPreserveRemoteFolderMovesAcrossPushPullAndReconcile() async throws {
        let meetings = (0...CloudSyncEngine.pushBatch).map { finished("Call \($0)", segments: 0) }
        await tick()
        for reconcile in [false, true] {
            let folder = UUID()
            for meeting in meetings {
                transport.remoteEdit(meeting.id, updatedAt: clock.addingTimeInterval(5)) {
                    $0["folder_id"] = folder.uuidString.lowercased()
                    $0["folder_manual"] = true
                }
                meeting.notes = "Local notes \(reconcile)"
            }
            try host.context.save()
            clock = clock.addingTimeInterval(60)
            if reconcile { engine.resetBookkeepingCursorOnly() }
            await engine.sync(reason: "test")
            for meeting in meetings {
                XCTAssertEqual(meeting.folderID, folder)
                XCTAssertEqual(meeting.notes, "Local notes \(reconcile)")
                XCTAssertEqual(transport.rows[meeting.id]?.document["notes"] as? String, meeting.notes)
                XCTAssertEqual(transport.rows[meeting.id]?.document["folder_id"] as? String, folder.uuidString.lowercased())
            }
        }
    }

    func testUpgradeFetchesSameRevisionFolderBeforeUploadingLocalNotes() async throws {
        for dirtyBeforeUpgrade in [false, true] {
          for hasLegacyExtras in [false, true] {
            let meeting = finished("Old client", segments: 0)
            await tick()
            let remoteFolder = UUID(), staleFolder = UUID()
            // The server accepted old-client notes but ignored its echoed stale folder.
            transport.rows[meeting.id]?.document["folder_id"] = remoteFolder.uuidString.lowercased()
            transport.rows[meeting.id]?.document["folder_manual"] = true
            meeting.folderID = nil; meeting.folderManual = nil
            meeting.syncExtraJSON = hasLegacyExtras ? "{\"folder_id\":\"\(staleFolder.uuidString)\",\"folder_manual\":true}" : nil
            meeting.syncedContentFingerprint = nil; meeting.syncedFolderFingerprint = nil
            meeting.syncFingerprint = MeetingSyncDocument.fingerprint(of: meeting)
            meeting.localFingerprint = meeting.syncFingerprint
            if dirtyBeforeUpgrade { meeting.notes = "Local edit" }
            MeetingSyncDocument.promoteLegacyFolderFields(meeting)
            XCTAssertEqual(meeting.syncStateRaw, "pending_folder_refresh")
            meeting.notes = "Local edit"
            try host.context.save()
            await tick()
            XCTAssertEqual(meeting.folderID, remoteFolder)
            XCTAssertEqual(meeting.notes, "Local edit")
            XCTAssertEqual(transport.rows[meeting.id]?.document["folder_id"] as? String, remoteFolder.uuidString.lowercased())
            XCTAssertEqual(transport.rows[meeting.id]?.document["notes"] as? String, "Local edit")
            XCTAssertNil(meeting.syncStateRaw)
          }
        }
    }

    func testUnavailableUpgradeFolderFetchIsTruthfulBoundedAndManuallyRetryable() async throws {
        let meeting = finished("Legacy without folder", segments: 0)
        await tick()
        meeting.syncedContentFingerprint = nil; meeting.syncedFolderFingerprint = nil
        MeetingSyncDocument.promoteLegacyFolderFields(meeting)
        meeting.notes = "Retain local work"
        try host.context.save()
        transport.omitBatchRows = true
        await tick()
        XCTAssertEqual(engine.pendingFolderRefreshCount, 1)
        XCTAssertTrue(engine.skippedMeetingIDs.isEmpty)
        XCTAssertNil(engine.lastError)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.folderRefreshIssueTitles, [meeting.title])
        let count = transport.calls.filter { $0 == "manifest" || $0.hasPrefix("batch:") }.count
        await engine.sync(reason: "poll")
        await engine.sync(reason: "foreground")
        XCTAssertEqual(transport.calls.filter { $0 == "manifest" || $0.hasPrefix("batch:") }.count, count, "Activation cannot reset a row's backoff")
        XCTAssertEqual(meeting.notes, "Retain local work")
        let remoteFolder = UUID()
        transport.rows[meeting.id]?.document["folder_id"] = remoteFolder.uuidString.lowercased()
        transport.omitBatchRows = false
        await engine.sync(reason: "manual")
        XCTAssertEqual(meeting.folderID, remoteFolder)
        XCTAssertEqual(meeting.notes, "Retain local work")
        XCTAssertNil(meeting.syncStateRaw)
        XCTAssertEqual(engine.pendingFolderRefreshCount, 0)
    }

    func testUnreadableUpgradeRowDoesNotBlockHealthySyncAndStopsAutomaticRetries() async throws {
        let held = finished("Unreadable")
        let healthy = finished("Healthy")
        let incoming = finished("Incoming")
        await tick()
        held.syncedContentFingerprint = nil; held.syncedFolderFingerprint = nil
        MeetingSyncDocument.promoteLegacyFolderFields(held)
        held.notes = "Held edit"
        healthy.notes = "First independent edit"
        try host.context.save()
        let savedEnd = transport.rows[held.id]?.document["end_time"]
        transport.rows[held.id]?.document["end_time"] = nil
        transport.remoteEdit(incoming.id, updatedAt: clock.addingTimeInterval(5)) { $0["notes"] = "Still downloads" }
        await tick()
        XCTAssertEqual(transport.rows[healthy.id]?.document["notes"] as? String, "First independent edit")
        XCTAssertEqual(held.syncStateRaw, "pending_folder_refresh")
        XCTAssertEqual(incoming.notes, "Still downloads")
        XCTAssertEqual(engine.phase, .idle)
        for _ in 0..<2 {
            clock = clock.addingTimeInterval(301)
            await engine.sync(reason: "poll")
        }
        let attempts = transport.calls.filter { $0.hasPrefix("batch:") }.count
        XCTAssertEqual(attempts, 3)
        clock = clock.addingTimeInterval(1000)
        healthy.notes = "Still uploads"
        try host.context.save()
        await engine.sync(reason: "foreground")
        XCTAssertEqual(transport.calls.filter { $0.hasPrefix("batch:") }.count, attempts)
        XCTAssertEqual(transport.rows[healthy.id]?.document["notes"] as? String, "Still uploads")
        transport.rows[held.id]?.document["end_time"] = savedEnd
        await engine.sync(reason: "manual")
        XCTAssertNil(held.syncStateRaw)
        XCTAssertEqual(transport.rows[held.id]?.document["notes"] as? String, "Held edit")
        XCTAssertTrue(engine.folderRefreshIssueTitles.isEmpty)
    }

    func testUpgradeFolderBookkeepingDoesNotNotifyMarkdownContentChanges() async throws {
        let meeting = finished("Existing export")
        await tick()
        meeting.syncedContentFingerprint = nil; meeting.syncedFolderFingerprint = nil
        MeetingSyncDocument.promoteLegacyFolderFields(meeting)
        try host.context.save()
        let folder = UUID()
        transport.rows[meeting.id]?.document["folder_id"] = folder.uuidString.lowercased()
        host.changedMeetingIDs = []
        await tick()
        XCTAssertEqual(meeting.folderID, folder)
        XCTAssertFalse(host.changedMeetingIDs.contains(meeting.id), "No export callback for a folder-only or baseline-only refresh")
        transport.remoteEdit(meeting.id, updatedAt: clock.addingTimeInterval(5)) { $0["notes"] = "Actual remote content edit" }
        await tick()
        XCTAssertTrue(host.changedMeetingIDs.contains(meeting.id), "Real content edits still refresh the export")
    }

    func testExplicitRestoreStillReadsUnknownRemoteFolderBeforeUploading() async throws {
        let meeting = finished("Restore pending folder")
        await tick()
        meeting.syncedContentFingerprint = nil; meeting.syncedFolderFingerprint = nil
        MeetingSyncDocument.promoteLegacyFolderFields(meeting)
        let folder = UUID()
        transport.rows[meeting.id]?.document["folder_id"] = folder.uuidString.lowercased()
        meeting.cloudRevision = 0; meeting.cloudRestoreRequested = true
        meeting.syncFingerprint = nil; meeting.notes = "Explicit local copy"
        try host.context.save()
        await tick()
        XCTAssertEqual(meeting.folderID, folder)
        XCTAssertEqual(transport.rows[meeting.id]?.document["folder_id"] as? String, folder.uuidString.lowercased())
        XCTAssertEqual(transport.rows[meeting.id]?.document["notes"] as? String, "Explicit local copy")
    }

    func testDeleteDuringPendingFolderRestoreKeepsExplicitLocalCopy() async throws {
        let meeting = finished("Restore during delete")
        await tick()
        meeting.syncedContentFingerprint = nil; meeting.syncedFolderFingerprint = nil
        MeetingSyncDocument.promoteLegacyFolderFields(meeting)
        meeting.cloudRestoreRequested = true; meeting.cloudRevision = 0
        meeting.syncFingerprint = nil; meeting.notes = "Keep this local copy"
        try host.context.save()
        transport.gate.holdNames = ["batch"]
        let task = Task { await self.engine.sync(reason: "manual") }
        try await TestSupport.waitUntil { self.transport.gate.held > 0 }
        transport.remoteDelete(meeting.id)
        transport.gate.release()
        await task.value
        XCTAssertFalse(host.deleted.contains(meeting.id))
        XCTAssertEqual(transport.rows[meeting.id]?.deleted, false)
        XCTAssertEqual(transport.rows[meeting.id]?.document["notes"] as? String, "Keep this local copy")
    }

    func testUndoneFolderEditCannotOverrideLaterRemoteMove() async throws {
        let meeting = finished("Undo")
        await tick()
        MeetingSyncDocument.prepareFolderEdit(meeting)
        meeting.folderID = UUID()
        meeting.folderID = nil
        XCTAssertFalse(MeetingSyncDocument.hasOnlyPendingFolderEdit(meeting))
        try host.context.save()
        let remoteFolder = UUID()
        transport.remoteEdit(meeting.id, updatedAt: clock.addingTimeInterval(5)) {
            $0["folder_id"] = remoteFolder.uuidString.lowercased()
            $0["folder_manual"] = true
        }
        await tick()
        XCTAssertEqual(meeting.folderID, remoteFolder, "calls: \(transport.calls), engine: \(engine.log.map(\.detail)), revision: \(meeting.cloudRevision)")
        XCTAssertNil(meeting.folderEditContentFingerprint)
    }

    func testConflictRemoteNewerReplacesLocalAndLocalNewerWins() async throws {
        let a = finished("Alpha")
        await tick()
        // Another device renames after us: remote wins.
        transport.remoteEdit(a.id, updatedAt: clock.addingTimeInterval(100)) { $0["title"] = "Remote title" }
        a.title = "Local title"
        try host.context.save()
        clock = clock.addingTimeInterval(10)   // local stamp is older than the remote edit
        await engine.sync(reason: "test")
        XCTAssertEqual(a.title, "Remote title")
        XCTAssertEqual(a.cloudRevision, transport.rows[a.id]?.revision)
        XCTAssertEqual(host.changedCount > 0, true)

        // Now the local edit is newer than the remote one: local wins after a retry.
        transport.remoteEdit(a.id, updatedAt: clock.addingTimeInterval(5)) { $0["title"] = "Remote again" }
        clock = clock.addingTimeInterval(60)
        a.title = "Local wins"
        try host.context.save()
        await engine.sync(reason: "test")
        XCTAssertEqual(transport.rows[a.id]?.document["title"] as? String, "Local wins")
        XCTAssertEqual(a.cloudRevision, transport.rows[a.id]?.revision)
    }

    func testAMeetingsOwnStampEchoedByTheCloudIsNotANewerEdit() async throws {
        // 2026-10-21: a device that lost its sync bookkeeping (or lagged behind a wave of pushes)
        // compared its microsecond stamp with the cloud's millisecond echo of that same stamp,
        // called every meeting "newer", and re-uploaded the whole library as conflicts.
        let a = finished("Alpha")
        await tick()
        let stamp = clock.addingTimeInterval(100)
        transport.remoteEdit(a.id, updatedAt: stamp) { _ in }      // same content, newer revision
        let remoteRevision = try XCTUnwrap(transport.rows[a.id]?.revision)
        a.updatedAt = stamp.addingTimeInterval(0.0004)             // our copy of that stamp, 0.4 ms "later"
        a.syncFingerprint = nil                                    // looks dirty
        try host.context.save()
        engine.clearLog()
        await engine.sync(reason: "test")
        XCTAssertFalse(engine.log.contains { $0.kind == .conflict }, "\(engine.log.map(\.detail))")
        XCTAssertEqual(transport.rows[a.id]?.revision, remoteRevision, "nothing was pushed")
        XCTAssertEqual(a.cloudRevision, remoteRevision)
        XCTAssertEqual(a.syncFingerprint, MeetingSyncDocument.fingerprint(of: a), "the cloud copy was taken as synced")
        // A real later edit still wins.
        XCTAssertTrue(CloudSyncEngine.isNewer(stamp.addingTimeInterval(0.002), than: stamp))
        XCTAssertFalse(CloudSyncEngine.isNewer(stamp.addingTimeInterval(0.0009), than: stamp))
        XCTAssertEqual(CloudSyncEngine.stamp(Date(timeIntervalSince1970: 1_790_000_000.1234)).timeIntervalSince1970, 1_790_000_000.123, accuracy: 0.0000001)
    }

    func testTrimGuardNeverLetsAStaleTranscriptReplaceTheServer() async throws {
        let a = finished("Alpha", segments: 3)
        await tick()
        // The other device trimmed to one segment.
        transport.remoteEdit(a.id, updatedAt: clock.addingTimeInterval(100)) {
            $0["transcript_revision"] = 3
            $0["segments"] = [["speaker": 0, "text": "only one", "start": 0.0]]
        }
        // We rename locally with the old transcript, and even with a newer stamp.
        clock = clock.addingTimeInterval(500)
        a.title = "Renamed on stale transcript"
        try host.context.save()
        await engine.sync(reason: "test")
        XCTAssertEqual(a.segments.count, 1, "the server's trimmed transcript was applied locally")
        XCTAssertEqual(a.transcriptRevision, 3)
        XCTAssertEqual(a.title, "Renamed on stale transcript", "the local rename survives the merge")
        XCTAssertEqual(transport.rows[a.id]?.transcriptRevision, 3)
        XCTAssertEqual(transport.rows[a.id]?.document["title"] as? String, "Renamed on stale transcript", "and is pushed with the merged transcript")
        XCTAssertEqual(a.cloudRevision, transport.rows[a.id]?.revision)
    }

    func testTooLargeIsSkippedUntilTheMeetingChanges() async throws {
        let a = finished("huge")
        transport.tooLargeTitles = ["huge"]
        await tick()
        XCTAssertEqual(a.syncStateRaw, "skipped_too_large")
        XCTAssertTrue(engine.skippedMeetingIDs.contains(a.id))
        let puts = transport.calls.filter { $0 == "put" }.count
        await tick()
        XCTAssertEqual(transport.calls.filter { $0 == "put" }.count, puts, "not retried while unchanged")
        a.title = "small now"
        try host.context.save()
        await tick()
        XCTAssertNil(a.syncStateRaw)
        XCTAssertEqual(a.cloudRevision, 1)
        XCTAssertFalse(engine.skippedMeetingIDs.contains(a.id))
    }

    func testExternalDuplicateIsReplacedByTheExistingCloudMeeting() async throws {
        let existingID = transport.seed(remoteDocument(title: "Imported on the Mac", updatedAt: clock).merging(["external_source": "granola", "external_id": "csv-1"]) { $1 }, updatedAt: clock)
        let local = finished("Imported on the phone")
        local.externalSource = "granola"
        local.externalID = "csv-1"
        try host.context.save()
        await tick()
        XCTAssertNil(host.meeting(local.id))
        XCTAssertEqual(host.meeting(existingID)?.title, "Imported on the Mac")
        XCTAssertEqual(host.allMeetings().count, 1)
    }

    // MARK: Pull

    func testPullInsertsRemoteMeetingsAndIgnoresOurOwnEcho() async throws {
        let a = finished("Alpha")
        await tick()
        let remoteID = transport.seed(remoteDocument(title: "From the phone", updatedAt: clock), updatedAt: clock)
        await tick()
        let pulled = try XCTUnwrap(host.meeting(remoteID))
        XCTAssertEqual(pulled.title, "From the phone")
        XCTAssertEqual(pulled.summaryText, "Remote summary")
        XCTAssertEqual(pulled.segments.count, 1)
        XCTAssertEqual(pulled.cloudRevision, 1)
        XCTAssertEqual(pulled.syncFingerprint, MeetingSyncDocument.fingerprint(of: pulled))
        XCTAssertEqual(host.inserted, [remoteID])
        XCTAssertEqual(host.allMeetings().count, 2)
        XCTAssertEqual(a.cloudRevision, 1)
        await tick()
        XCTAssertEqual(host.allMeetings().count, 2, "no duplicates on later pulls")
        XCTAssertEqual(host.inserted.count, 1)
    }

    func testRemoteDeleteRemovesTheLocalCopyAndLocalDeleteSendsATombstone() async throws {
        let a = finished("Alpha")
        let b = finished("Beta", start: 1_790_000_700)
        await tick()
        transport.remoteDelete(a.id)
        await tick()
        XCTAssertNil(host.meeting(a.id))
        XCTAssertTrue(host.deleted.contains(a.id))

        host.userDelete(b)
        XCTAssertEqual(host.cloudFetchTombstones()?.count, 1)
        await tick()
        XCTAssertEqual(transport.rows[b.id]?.deleted, true)
        XCTAssertEqual(host.cloudFetchTombstones()?.count, 0)
    }

    func testLocalDeleteStillWinsWhenAnotherDeviceEditedAfterwards() async throws {
        let a = finished("Alpha")
        await tick()
        transport.remoteEdit(a.id, updatedAt: clock.addingTimeInterval(100)) { $0["title"] = "Edited elsewhere" }
        host.userDelete(a)
        await tick()
        XCTAssertEqual(transport.rows[a.id]?.deleted, true)
        XCTAssertEqual(host.cloudFetchTombstones()?.count, 0)
    }

    func testRemoteUpdateLeavesANewerDirtyLocalEditAloneAndPushesIt() async throws {
        let a = finished("Alpha")
        await tick()
        transport.remoteEdit(a.id, updatedAt: clock.addingTimeInterval(5)) { $0["title"] = "Remote" }
        clock = clock.addingTimeInterval(60)
        a.title = "Local newer"
        try host.context.save()
        await engine.sync(reason: "test")
        XCTAssertEqual(a.title, "Local newer")
        XCTAssertEqual(transport.rows[a.id]?.document["title"] as? String, "Local newer")
    }

    func testExpiredCursorFallsBackToTheManifest() async throws {
        let a = finished("Alpha")
        await tick()
        let remoteID = transport.seed(remoteDocument(title: "Added while away", updatedAt: clock), updatedAt: clock)
        transport.oldestRetainedSeq = transport.seq + 1
        await tick()
        XCTAssertNotNil(host.meeting(remoteID))
        XCTAssertEqual(a.cloudRevision, 1)
        XCTAssertTrue(transport.calls.filter { $0 == "manifest" }.count >= 2)
    }

    func testRepeatedCursorExpiryStopsImmediateRetriesAndRecoversOnLaterPoll() async throws {
        _ = finished("Saved")
        await engine.sync(reason: "change")
        let checkedAt = engine.lastSyncedAt
        transport.calls = []
        // Simulate a temporarily inconsistent server watermark: even the newly fetched
        // manifest cursor is too old for the retained feed.
        transport.oldestRetainedSeq = transport.seq + 10
        await engine.sync(reason: "poll")
        await settle()
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(transport.calls.filter { $0.hasPrefix("changes:") }.count, 2)
        XCTAssertEqual(transport.calls.filter { $0 == "manifest" }.count, 1)
        XCTAssertEqual(transport.calls.filter { $0 == "status" }.count, 0)
        XCTAssertEqual(engine.lastSyncedAt, checkedAt)
        if case .failed = engine.phase {} else { XCTFail("repeated expiry must remain visibly unfinished") }
        let callsAfterFailure = transport.calls.count
        await settle()
        XCTAssertEqual(transport.calls.count, callsAfterFailure, "no self-scheduled debounce loop after repeated expiry")
        transport.oldestRetainedSeq = 1
        clock = clock.addingTimeInterval(60)
        await engine.sync(reason: "poll")
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertGreaterThan(try XCTUnwrap(engine.lastSyncedAt), try XCTUnwrap(checkedAt))
        XCTAssertEqual(transport.calls.filter { $0 == "manifest" }.count, 2, "required reconciliation survives until the next trigger")
    }

    func testReconcileReuploadsMeetingsTheCloudForgotInsteadOfDeleting() async throws {
        let a = finished("Alpha")
        await tick()
        transport.rows = [:]
        transport.changes = []
        transport.seq = 0
        engine.resetBookkeepingCursorOnly()
        await tick()
        XCTAssertNotNil(host.meeting(a.id))
        XCTAssertEqual(transport.rows[a.id]?.document["title"] as? String, "Alpha")
    }

    func testReconcileAppliesNewerRemoteAndKeepsNewerLocal() async throws {
        let a = finished("Alpha")
        let b = finished("Beta", start: 1_790_000_700)
        await tick()
        transport.remoteEdit(a.id, updatedAt: clock.addingTimeInterval(100)) { $0["title"] = "Alpha from the cloud" }
        transport.remoteEdit(b.id, updatedAt: clock.addingTimeInterval(5)) { $0["title"] = "Beta from the cloud" }
        clock = clock.addingTimeInterval(60)
        b.title = "Beta local newer"
        try host.context.save()
        engine.resetBookkeepingCursorOnly()
        await engine.sync(reason: "test")
        XCTAssertEqual(a.title, "Alpha from the cloud")
        XCTAssertEqual(b.title, "Beta local newer")
        XCTAssertEqual(transport.rows[b.id]?.document["title"] as? String, "Beta local newer")
    }

    // MARK: Gates

    func testPausedMakesNoCalls() async throws {
        finished("Alpha")
        host.pause = .privateMode
        await tick()
        XCTAssertTrue(transport.calls.isEmpty)
        XCTAssertEqual(engine.phase, .paused(.privateMode))
        host.pause = nil
        engine.refreshPause()
        XCTAssertEqual(engine.phase, .idle)
    }

    func testProRequiredPausesAndTellsTheHost() async throws {
        finished("Alpha")
        transport.tier = "free"
        await tick()
        XCTAssertEqual(engine.phase, .paused(.notPro))
        XCTAssertEqual(host.tierChanges, [false])
    }

    func testOfflineAndRevokedAreReportedNotFatal() async throws {
        finished("Alpha")
        transport.failNext = .offline
        await tick()
        XCTAssertEqual(engine.phase, .paused(.offline))
        await tick()
        XCTAssertEqual(engine.phase, .idle)
        transport.failNext = .server(code: "http_401", status: 401)
        await tick()
        if case .failed = engine.phase {} else { XCTFail("a transient 401 is reported, not sticky: \(engine.phase)") }
        await tick()
        XCTAssertEqual(engine.phase, .idle)
        transport.failNext = .revoked
        await tick()
        XCTAssertEqual(engine.phase, .paused(.deviceRemoved))
        await tick()
        XCTAssertEqual(engine.phase, .paused(.deviceRemoved), "stays paused until bookkeeping is reset")
        engine.resetBookkeeping()
        await settle()
        transport.failNext = .notEnrolled
        await tick()
        XCTAssertEqual(engine.phase, .paused(.notEnrolled))
    }

    func testResetBookkeepingForgetsTheCloudButKeepsMeetings() async throws {
        let a = finished("Alpha")
        host.userDelete(finished("Gone", start: 1_790_000_700))
        await tick()
        XCTAssertEqual(a.cloudRevision, 1)
        host.pause = .notEnrolled   // signed out: the reset must not kick a pass
        engine.resetBookkeeping()
        XCTAssertEqual(a.cloudRevision, 0)
        XCTAssertNil(a.syncFingerprint)
        XCTAssertEqual(host.cloudFetchTombstones()?.count, 0)
        XCTAssertNotNil(host.meeting(a.id))
        XCTAssertEqual(engine.phase, .paused(.notEnrolled))
        host.pause = nil
        engine.refreshPause()   // gates open again: kicks a pass on its own
        await settle()
        XCTAssertEqual(a.cloudRevision, transport.rows[a.id]?.revision, "re-attached to whatever the cloud holds now")
        XCTAssertEqual(transport.rows[a.id]?.revision, 1, "identical content is re-attached through the manifest, not uploaded again")
        XCTAssertNotNil(a.syncFingerprint)
    }

    func testNewSaveDoesNotCancelAnUploadStartedByTheDebounce() async throws {
        let meeting = finished("Before edit")
        transport.respectsTaskCancellation = true
        transport.gate.holdNames = ["put"]
        defer { transport.gate.release() }
        engine.noteLocalChange()
        try await TestSupport.waitUntil { self.transport.gate.held > 0 }
        meeting.title = "After edit"
        try host.context.save()
        engine.noteLocalChange()
        // Let the replacement debounce request its pass while the first upload is held.
        try await Task.sleep(nanoseconds: 30_000_000)
        transport.gate.release()
        await settle()
        XCTAssertEqual(transport.rows[meeting.id]?.document["title"] as? String, "After edit")
        XCTAssertNil(engine.lastError)
        XCTAssertFalse(engine.log.contains { $0.kind == .error }, "a local edit must not cancel the preceding upload")
    }

    func testCancelledRequestRemainsPendingWithoutReportingFailureOrSuccess() async throws {
        let meeting = finished("Retry automatically")
        transport.cancelNext = true
        await engine.sync(reason: "test")
        XCTAssertNil(engine.lastSyncedAt)
        XCTAssertNil(engine.lastError)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertFalse(engine.log.contains { $0.kind == .error })
        await engine.sync(reason: "poll")
        XCTAssertNotNil(transport.rows[meeting.id])
        XCTAssertNotNil(engine.lastSyncedAt)
    }

    func testCancelledStatusReadDoesNotPublishACompletedCheck() async throws {
        finished("Uploaded")
        transport.respectsTaskCancellation = true
        transport.gate.holdNames = ["status"]
        defer { transport.gate.release() }
        let checking = Task { await self.engine.sync(reason: "test", refreshStatus: true) }
        try await TestSupport.waitUntil { self.transport.gate.held > 0 }
        checking.cancel()
        transport.gate.release()
        await checking.value
        XCTAssertNil(engine.lastSyncedAt)
        XCTAssertNil(engine.statusFetchedAt)
        XCTAssertNil(engine.lastError)
        XCTAssertEqual(engine.phase, .idle)
        await engine.sync(reason: "poll", refreshStatus: true)
        XCTAssertNotNil(engine.statusFetchedAt)
    }

    func testNoteLocalChangeDebouncesIntoOneSync() async throws {
        finished("Alpha")
        engine.noteLocalChange()
        engine.noteLocalChange()
        engine.noteLocalChange()
        try await Task.sleep(nanoseconds: 50_000_000)
        while case .pushing = engine.phase { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(transport.calls.filter { $0 == "manifest" }.count, 1)
    }
}

extension CloudSyncEngineTests {
    func testDeleteDuringTheFirstUploadLeavesATombstoneSoTheCloudCopyGoesToo() async throws {
        let a = finished("Alpha")
        let host = self.host!
        transport.onPut = { [weak transport] id in
            // The user deletes the meeting while its PUT is on the wire (cloudRevision still 0).
            if let meeting = host.meeting(id) { host.userDelete(meeting) }
            transport?.onPut = nil
        }
        await tick()
        XCTAssertNil(host.meeting(a.id))
        XCTAssertEqual(transport.rows[a.id]?.deleted, true, "the copy uploaded during the delete is tombstoned on the next pass")
        XCTAssertEqual(host.cloudFetchTombstones()?.count, 0)
    }

    func testThePollOnlyScansAfterACommitAndEveryFifthTime() async throws {
        let a = finished("Alpha")
        await engine.sync(reason: "launch")
        let puts = transport.calls.filter { $0 == "put" }.count
        a.title = "Changed without a commit notice"
        try host.context.save()
        await engine.sync(reason: "poll")
        XCTAssertEqual(transport.calls.filter { $0 == "put" }.count, puts, "a plain poll pulls without fingerprinting")
        engine.noteLocalChange()
        try await Task.sleep(nanoseconds: 30_000_000)
        while case .pushing = engine.phase { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(transport.rows[a.id]?.document["title"] as? String, "Changed without a commit notice")
        a.title = "Changed again"
        try host.context.save()
        for _ in 0..<4 { await engine.sync(reason: "poll") }
        XCTAssertNotEqual(transport.rows[a.id]?.document["title"] as? String, "Changed again")
        await engine.sync(reason: "poll")
        XCTAssertEqual(transport.rows[a.id]?.document["title"] as? String, "Changed again", "the fifth poll runs a full scan")
    }

    func testPrivateModeMidBacklogStopsTheRemainingUploads() async throws {
        for i in 0..<5 { finished("Meeting \(i)", start: 1_790_000_000 + Double(i) * 1000) }
        let host = self.host!
        transport.onPut = { [weak transport] _ in
            host.pause = .privateMode
            transport?.onPut = nil
        }
        await tick()
        XCTAssertEqual(transport.rows.count, 1, "nothing else leaves the device once private mode is on")
        XCTAssertEqual(engine.phase, .paused(.privateMode))
    }

    func testDocumentsWithoutAnEndTimeAreIgnored() async throws {
        var doc = remoteDocument(title: "Still recording elsewhere", updatedAt: clock)
        doc["end_time"] = NSNull()
        let id = transport.seed(doc, updatedAt: clock)
        await tick()
        XCTAssertNil(host.meeting(id))
    }

    // MARK: Pass authority (R3, 2026-10-27)

    private func cursor(for account: String) -> Int { engine.defaults.integer(forKey: CloudSyncEngine.cursorKey(account)) }

    func testAnAccountSwitchDuringAPullDiscardsTheOldAccountsAnswer() async throws {
        _ = transport.seed(remoteDocument(title: "A1", updatedAt: clock), updatedAt: clock)
        await tick()
        XCTAssertEqual(host.allMeetings().map(\.title), ["A1"])
        let cursorA = cursor(for: "acct_test")
        XCTAssertGreaterThan(cursorA, 0)

        // A second meeting appears on A; its pull is held while the device switches to B.
        _ = transport.seed(remoteDocument(title: "A2", updatedAt: clock), updatedAt: clock)
        transport.gate.holdNames = ["changes"]
        let syncing = Task { await engine.sync(reason: "test") }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        let transportB = FakeCloudTransport()
        host.cloudAccountID = "acct_b"
        engine.transport = transportB
        engine.resetBookkeeping()
        transport.gate.release()
        await syncing.value
        await settle()

        XCTAssertFalse(host.allMeetings().contains { $0.title == "A2" }, "A's page must not land under B")
        XCTAssertEqual(cursor(for: "acct_test"), cursorA, "A's cursor is not advanced by a stale pass")
        XCTAssertEqual(transportB.calls.first, "manifest", "B's own reconciliation ran after the stale pass left")
        XCTAssertGreaterThan(cursor(for: "acct_b"), 0, "B's cursor comes from B's manifest")
        if case .failed = engine.phase { XCTFail("a superseded pass is not a failure") }
        if case .paused = engine.phase { XCTFail("nor a pause") }
    }

    func testAStaleErrorAfterAToBToADoesNotPauseOrMarkTheDevice() async throws {
        _ = transport.seed(remoteDocument(title: "A1", updatedAt: clock), updatedAt: clock)
        await tick()
        for stale in [CloudSyncError.proRequired, .revoked] {
            transport.gate.holdNames = ["changes"]
            transport.failNext = stale
            let syncing = Task { await engine.sync(reason: "test") }
            try await TestSupport.waitUntil { self.transport.gate.held == 1 }
            // A to B and back to A while A's first request is outstanding.
            let transportB = FakeCloudTransport()
            host.cloudAccountID = "acct_b"; engine.transport = transportB; engine.resetBookkeeping()
            host.cloudAccountID = "acct_test"; engine.transport = transport; engine.resetBookkeeping()
            transport.gate.release()
            await syncing.value
            await settle()
            if case .paused(let reason) = engine.phase { XCTFail("the stale \(stale) paused the current account: \(reason)") }
            XCTAssertTrue(host.tierChanges.isEmpty, "no tier verdict from a stale answer")
            XCTAssertEqual(engine.phase, .idle)
        }
    }

    func testACredentialReplacementDuringAnUploadDoesNotMarkTheMeetingSyncedFromTheStaleAnswer() async throws {
        let meeting = finished("Local")
        transport.gate.holdNames = ["put"]
        let syncing = Task { await engine.sync(reason: "test") }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        // Same account, new credential (a key repair or a reauthentication): the pass loses its authority.
        engine.invalidatePasses(reason: "credential changed")
        transport.gate.release()
        transport.gate.holdNames = ["manifest"]
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        XCTAssertEqual(meeting.cloudRevision, 0, "old upload receipt must not commit before the replacement authority checks the server")
        XCTAssertNil(meeting.syncFingerprint)
        XCTAssertNil(engine.lastSyncedAt)
        XCTAssertFalse(engine.log.contains { $0.kind == .uploaded }, "the stale .ok was not applied as an upload")

        transport.gate.release()
        transport.gate.holdNames = ["batch"]
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        XCTAssertEqual(meeting.cloudRevision, 0, "even the new manifest must fetch the actual server document before confirming it")
        XCTAssertNil(meeting.syncFingerprint)
        transport.gate.release()
        await syncing.value
        await settle()

        XCTAssertEqual(transport.calls.filter { $0 == "put" }.count, 1, "a new-authority read can confirm the previously accepted server write without writing it twice")
        XCTAssertEqual(transport.calls.filter { $0 == "manifest" }.count, 2, "initial manifest plus replacement-authority reconciliation")
        XCTAssertEqual(transport.calls.filter { $0.hasPrefix("batch:") }.count, 1)
        XCTAssertEqual(meeting.cloudRevision, 1, "settled only after fetching the cloud document under replacement authority")
        XCTAssertEqual(meeting.syncFingerprint, MeetingSyncDocument.fingerprint(of: meeting))
    }

    func testAStaleStatusAnswerIsNotKept() async throws {
        _ = transport.seed(remoteDocument(title: "A1", updatedAt: clock), updatedAt: clock)
        await tick()
        transport.gate.holdNames = ["status"]
        let syncing = Task { await engine.sync(reason: "test", refreshStatus: true) }
        try await TestSupport.waitUntil { self.transport.gate.held == 1 }
        let transportB = FakeCloudTransport()
        _ = transportB.seed(remoteDocument(title: "B1", updatedAt: clock), updatedAt: clock)
        _ = transportB.seed(remoteDocument(title: "B2", updatedAt: clock), updatedAt: clock)
        host.cloudAccountID = "acct_b"; engine.transport = transportB; engine.resetBookkeeping()
        transport.gate.release()
        await syncing.value
        await settle()
        // B holds its two meetings plus A1, which the reset made local and B's pass uploaded.
        XCTAssertEqual(engine.status?.meetingCount, 3, "the status shown is B's own, never A's stale answer")
    }
}


// MARK: - AppState wiring

@MainActor
final class CloudSyncAppStateTests: XCTestCase {
    func testSelectedFinishedMeetingHasDifferentUploadAndIncomingProtection() throws {
        let state = AppState()
        let meeting = Meeting(title: "Stopped", startTime: Date(), endTime: Date())
        state.currentMeeting = meeting
        state.isRecording = false
        state.isStartingMeeting = false
        state.isResumingRecording = false
        XCTAssertNil(state.cloudUploadProtectedMeetingID)
        XCTAssertTrue(state.cloudProtectsIncoming(meeting.id))
        for phase in 0..<3 {
            state.isRecording = phase == 0
            state.isStartingMeeting = phase == 1
            state.isResumingRecording = phase == 2
            XCTAssertEqual(state.cloudUploadProtectedMeetingID, meeting.id)
        }
        state.isRecording = false
        state.isStartingMeeting = false
        state.isResumingRecording = false
        state.currentMeeting = nil
        XCTAssertFalse(state.cloudProtectsIncoming(meeting.id))
    }

    func testTitleRulesAreLiteralAndPrivateModeWins() {
        let rules = ["  ", " therapy ", "[private]"]
        XCTAssertEqual(CloudExclusionPolicy.matchingRule(title: "THERAPY appointment", rules: rules), "therapy")
        XCTAssertNil(CloudExclusionPolicy.matchingRule(title: "private sale", rules: rules))
        XCTAssertNil(CloudExclusionPolicy.matchingRule(title: nil, rules: rules))
        XCTAssertTrue(CloudExclusionPolicy.excluded(privateMode: true, title: nil, rules: []))
        XCTAssertFalse(CloudExclusionPolicy.excluded(privateMode: false, title: nil, rules: rules))
    }

    func testRuleEditorTrimsRejectsDuplicatesAndShowsWhySaveIsUnavailable() {
        let key = "cloud.exclusionTitleRules"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        let state = AppState()
        state.cloudExclusionRules = []
        XCTAssertNotNil(CloudRuleValidation.problem("  ", existing: []))
        XCTAssertTrue(state.addCloudExclusionRule("  Therapy  "))
        XCTAssertEqual(state.cloudExclusionRules, ["Therapy"])
        XCTAssertFalse(state.addCloudExclusionRule("therapy"))
        XCTAssertEqual(CloudRuleValidation.problem("therapy", existing: state.cloudExclusionRules), "That rule already exists.")
        XCTAssertFalse(state.addCloudExclusionRule(String(repeating: "x", count: 121)))
        XCTAssertNotNil(CloudRuleValidation.problem("new", existing: (0..<30).map(String.init)))
    }

    func testToolbarTogglePersistsAndOverridesLateRulesWithoutChangingOtherMeetings() throws {
        let keys = ["privateMode", "cloud.exclusionTitleRules", "cloudSyncEnabled"]
        let previous = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer { for (key, value) in previous { UserDefaults.standard.set(value, forKey: key) } }
        let container = try TestSupport.makeInMemoryContainer()
        let state = AppState()
        state.modelContext = container.mainContext
        state.privateModeEnabled = false
        state.cloudSyncEnabled = false
        state.cloudExclusionRules = ["therapy"]
        let meeting = Meeting(title: "Current")
        let ordinary = Meeting(title: "Other")
        container.mainContext.insert(meeting); container.mainContext.insert(ordinary)
        state.currentMeeting = meeting
        state.isRecording = true
        state.toggleMeetingCloudStorage(meeting)
        XCTAssertTrue(meeting.syncExcluded)
        XCTAssertFalse(ordinary.syncExcluded)
        XCTAssertEqual(state.meetingCloudFeedback?.message, "This meeting won't be synced to your cloud.")
        state.toggleMeetingCloudStorage(meeting)
        XCTAssertFalse(meeting.syncExcluded)
        XCTAssertTrue(meeting.cloudRestoreRequested)
        XCTAssertEqual(state.meetingCloudFeedback?.message, MeetingCloudPrivacyPresentation.uploadStatus(pause: .off))
        state.selectedCalendarEvent = try JSONDecoder().decode(MinitiAPIService.CalendarEvent.self,
            from: Data(#"{"id":"therapy-test","title":"Therapy session","start":"2026-10-29T09:00:00Z","end":"2026-10-29T09:30:00Z","attendees":[]}"#.utf8))
        XCTAssertFalse(meeting.syncExcluded, "The explicit toolbar choice wins over a late calendar rule")
        state.privateModeEnabled = true
        meeting.syncExcluded = true
        state.toggleMeetingCloudStorage(meeting)
        XCTAssertTrue(meeting.syncExcluded, "A running private recording cannot be opted into cloud")
        state.isRecording = false; state.currentMeeting = nil
    }

    func testSavedToolbarToggleQueuesDeletionAndNeverClaimsItAlreadyFinished() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let state = AppState()
        state.modelContext = container.mainContext
        let meeting = Meeting(title: "Saved", startTime: Date(), endTime: Date())
        meeting.cloudRevision = 3
        container.mainContext.insert(meeting)
        state.toggleMeetingCloudStorage(meeting)
        XCTAssertTrue(meeting.syncExcluded)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<MeetingTombstone>()).first?.cloudRevision, 3)
        XCTAssertTrue(state.meetingCloudFeedback?.message.contains("removal is pending") == true)
        state.toggleMeetingCloudStorage(meeting)
        XCTAssertFalse(meeting.syncExcluded)
        XCTAssertTrue(meeting.cloudRestoreRequested)
    }

    func testRulesLatchBeforeCaptureAndLateAssociationOnlyAddsExclusionWithoutAnOverride() throws {
        let keys = ["appMode", "deepgramApiKey", "hasAcceptedTerms", "acceptedTermsVersion", "declinedTermsVersion", "privateMode", "cloud.exclusionTitleRules"]
        let previous = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer { for (key, value) in previous { UserDefaults.standard.set(value, forKey: key) } }
        let state = AppState()
        state.appMode = .byok; state.deepgramApiKey = "test-only-no-transport"
        state.audioCaptureService = nil; state.deepgramService = nil
        state.privateModeEnabled = false; state.cloudExclusionRules = ["therapy"]
        let event = try JSONDecoder().decode(MinitiAPIService.CalendarEvent.self,
            from: Data(#"{"id":"therapy-test","title":"Therapy session","start":"2026-10-29T09:00:00Z","end":"2026-10-29T09:30:00Z","attendees":[]}"#.utf8))
        state.hasAcceptedTerms = true
        XCTAssertTrue(state.startMeetingFromEvent(event))
        XCTAssertTrue(try XCTUnwrap(state.currentMeeting).syncExcluded, "Rule applies before capture or first save")
        state.currentMeeting = nil
        state.isStartingMeeting = false // Finish the prior synthetic, capture-less start.
        XCTAssertTrue(state.startNewMeeting())
        XCTAssertFalse(try XCTUnwrap(state.currentMeeting).syncExcluded)
        state.isRecording = true; state.selectedCalendarEvent = event
        XCTAssertTrue(try XCTUnwrap(state.currentMeeting).syncExcluded)
        state.cloudExclusionRules = []; state.selectedCalendarEvent = nil
        XCTAssertTrue(try XCTUnwrap(state.currentMeeting).syncExcluded)
        state.isRecording = false; state.isStartingMeeting = false; state.currentMeeting = nil
    }

    func testPrivateModeSnapshotsTheSwitchAndPausesTheEngine() throws {
        let defaults = UserDefaults(suiteName: "CloudSyncAppStateTests-\(UUID().uuidString)")!
        let state = AppState()
        state.cloudSyncEnabled = true
        state.setPrivateMode(true, defaults: defaults)
        if state.privateModeAvailable {
            XCTAssertFalse(state.cloudSyncEnabled)
            XCTAssertEqual(state.cloudPauseReason, .off)
            state.setPrivateMode(false, defaults: defaults)
            XCTAssertTrue(state.cloudSyncEnabled, "the switch comes back with the other nine settings")
        } else {
            XCTAssertTrue(state.cloudSyncEnabled, "private mode is unavailable here, so nothing changes")
        }
        state.cloudSyncEnabled = false
    }

    func testAccountCloudSwitchDecisions() {
        typealias A = AppState.CloudAccountFlagAction
        func decide(local: Bool, pending: Bool? = nil, server: Bool?, version: Int = 1, applied: Int = 0, pro: Bool = true, privateMode: Bool = false) -> A {
            AppState.cloudAccountFlagAction(localOn: local, pending: pending, serverEnabled: server, serverVersion: version, appliedVersion: applied, isPro: pro, privateMode: privateMode)
        }
        // A choice the account has not confirmed wins over everything, including a newer server value.
        XCTAssertEqual(decide(local: true, pending: true, server: false, version: 9), .push(true))
        XCTAssertEqual(decide(local: false, pending: false, server: true, version: 9), .push(false))
        // Account never set (before 3.3.0, or new): an "on" device teaches it, an "off" device stays quiet.
        XCTAssertEqual(decide(local: true, server: nil, version: 0), .push(true))
        XCTAssertEqual(decide(local: false, server: nil, version: 0), .none)
        // Nothing new since the last applied version.
        XCTAssertEqual(decide(local: false, server: true, version: 3, applied: 3), .none)
        XCTAssertEqual(decide(local: true, server: false, version: 2, applied: 5), .none)
        // Another device flipped it: follow. Off always applies; on waits for Pro and the end of private mode.
        XCTAssertEqual(decide(local: true, server: false, version: 4, applied: 3), .follow(false))
        XCTAssertEqual(decide(local: false, server: true, version: 4, applied: 3), .follow(true))
        XCTAssertEqual(decide(local: false, server: true, version: 4, applied: 3, pro: false), .none, "not Pro: wait, version stays unapplied")
        XCTAssertEqual(decide(local: false, server: true, version: 4, applied: 3, privateMode: true), .none, "private mode: wait")
        XCTAssertEqual(decide(local: true, server: false, version: 4, applied: 3, privateMode: true), .follow(false), "off applies even under private mode")
        // Same state, newer version: just remember it.
        XCTAssertEqual(decide(local: true, server: true, version: 4, applied: 3), .acknowledge)
        XCTAssertEqual(decide(local: false, server: false, version: 4, applied: 3), .acknowledge)
    }

    func testPauseReasonOrderAndKeepOffTheCloud() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let state = AppState()
        state.modelContext = context
        state.cloudSyncEnabled = false
        XCTAssertEqual(state.cloudPauseReason, .off)
        state.cloudSyncEnabled = true
        state.appMode = .byok
        XCTAssertEqual(state.cloudPauseReason, .notManaged)
        state.appMode = .managed
        // The test host shares the Mac's own Keychain, so it may be enrolled; either way the gate
        // after mode is enrollment, then tier, and never nil without Pro.
        XCTAssertTrue([.notEnrolled, .notPro].contains(state.cloudPauseReason), "\(String(describing: state.cloudPauseReason))")

        let meeting = Meeting(title: "Synced once", startTime: Date(), endTime: Date())
        meeting.cloudRevision = 3
        meeting.syncFingerprint = "abc"
        context.insert(meeting)
        try context.save()
        state.setMeetingExcludedFromCloud(meeting, excluded: true)
        XCTAssertTrue(meeting.syncExcluded)
        XCTAssertEqual(meeting.cloudRevision, 0)
        XCTAssertNil(meeting.syncFingerprint)
        let tombstones = try context.fetch(FetchDescriptor<MeetingTombstone>())
        XCTAssertEqual(tombstones.map(\.id), [meeting.id], "the cloud copy is removed through a tombstone")
        XCTAssertEqual(tombstones.first?.cloudRevision, 3)
        state.setMeetingExcludedFromCloud(meeting, excluded: false)
        XCTAssertFalse(meeting.syncExcluded)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MeetingTombstone>()).isEmpty)

        // A user delete of a never-synced meeting leaves a tombstone only while the switch is on.
        let fresh = Meeting(title: "Never uploaded", startTime: Date(), endTime: Date())
        context.insert(fresh)
        try context.save()
        state.noteMeetingDeleted(fresh)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MeetingTombstone>()).count, 1)
        state.cloudSyncEnabled = false
    }
}


@MainActor
final class CloudPrivacyAvailabilityTests: XCTestCase {
    func testFinishedNeverSyncedMeetingDoesNotInventARemovalWhileCloudIsOffOrBYOK() throws {
        let previous = UserDefaults.standard.object(forKey: "appMode")
        let cloudBefore = UserDefaults.standard.object(forKey: "cloudSyncEnabled")
        defer {
            UserDefaults.standard.set(previous, forKey: "appMode")
            UserDefaults.standard.set(cloudBefore, forKey: "cloudSyncEnabled")
        }
        let container = try TestSupport.makeInMemoryContainer()
        let state = AppState(); state.modelContext = container.mainContext
        let meeting = Meeting(title: "Never on cloud", startTime: Date(), endTime: Date())
        container.mainContext.insert(meeting); try container.mainContext.save()
        for mode in [AppMode.managed, .byok] {
            state.appMode = mode; state.cloudSyncEnabled = false
            state.toggleMeetingCloudStorage(meeting)
            XCTAssertTrue(meeting.syncExcluded)
            XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<MeetingTombstone>()).isEmpty)
            XCTAssertEqual(state.meetingCloudFeedback?.message, "This meeting won't be synced to your cloud.")
            state.toggleMeetingCloudStorage(meeting)
            XCTAssertFalse(meeting.syncExcluded)
            XCTAssertEqual(state.meetingCloudFeedback?.message, MeetingCloudPrivacyPresentation.uploadStatus(pause: .off))
        }
    }

    func testRemovalCopyExplainsAutomaticRetryAndSettingsThatNeedAction() {
        XCTAssertEqual(MeetingCloudPrivacyPresentation.removalStatus(pause: nil, retrying: false), "Removing the cloud copy automatically. This meeting stays on this device.")
        XCTAssertTrue(MeetingCloudPrivacyPresentation.removalStatus(pause: nil, retrying: true).contains("automatically"))
        XCTAssertTrue(MeetingCloudPrivacyPresentation.removalStatus(pause: .offline, retrying: false).contains("automatically"))
        XCTAssertTrue(MeetingCloudPrivacyPresentation.removalStatus(pause: .off, retrying: false).contains("Turn on cloud sync"))
        XCTAssertTrue(MeetingCloudPrivacyPresentation.removalStatus(pause: .notEnrolled, retrying: false).contains("Sign in"))
        XCTAssertTrue(MeetingCloudPrivacyPresentation.removalStatus(pause: .privateMode, retrying: false).contains("when private mode is off"))
    }

    func testRemovalProtectionSurvivesCloudBeingDisabledDuringAnUpload() {
        XCTAssertFalse(MeetingCloudPrivacyPresentation.needsRemoval(knownCopy: false, uploadInFlight: false, canSync: false, finished: true))
        XCTAssertTrue(MeetingCloudPrivacyPresentation.needsRemoval(knownCopy: false, uploadInFlight: true, canSync: false, finished: true))
        XCTAssertTrue(MeetingCloudPrivacyPresentation.needsRemoval(knownCopy: true, uploadInFlight: false, canSync: false, finished: true))
        XCTAssertEqual(MeetingCloudPrivacyPresentation.uploadStatus(pause: .notManaged), "This meeting can sync with a managed Pro account.")
        XCTAssertEqual(MeetingCloudPrivacyPresentation.uploadStatus(pause: .notPro), "This meeting can sync when this account has Pro.")
        XCTAssertEqual(MeetingCloudPrivacyPresentation.uploadStatus(pause: nil), "Waiting to put on the cloud")
    }
}
