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
final class FakeCloudTransport: CloudSyncTransport, @unchecked Sendable {
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
    var failNext: CloudSyncError?
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
        calls.append("manifest"); try throwIfArmed()
        return CloudManifest(entries: rows.map { CloudManifestEntry(id: $0.key, revision: $0.value.revision, updatedAt: $0.value.updatedAt, deleted: $0.value.deleted) }, latestSeq: seq)
    }

    func changes(since: Int, limit: Int) async throws -> CloudChangesPage {
        calls.append("changes:\(since)"); try throwIfArmed()
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
        calls.append("batch:\(ids.count)"); try throwIfArmed()
        return ids.compactMap { id in rows[id].map { state(id, $0) } }
    }

    func putMeeting(id: UUID, baseRevision: Int, document data: Data) async throws -> CloudPutResult {
        calls.append("put"); try throwIfArmed()
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
            if existing.revision != baseRevision || existing.deleted || existing.transcriptRevision > transcriptRevision {
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
        calls.append("delete"); try throwIfArmed()
        guard var row = rows[id] else { return .ok(revision: 0) }
        if row.deleted { return .ok(revision: row.revision) }
        if row.revision != baseRevision { return .conflict(state(id, row)) }
        row.revision += 1; row.deleted = true; row.updatedAt = Date(); row.document = [:]
        rows[id] = row
        _ = record(id)
        return .ok(revision: row.revision)
    }

    func status() async throws -> CloudStatus {
        calls.append("status"); try throwIfArmed()
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
    var cloudAccountID: String? = "acct_test"
    var deleted: Set<UUID> = []
    var inserted: [UUID] = []
    var changedCount = 0
    var tierChanges: [Bool] = []

    init() throws {
        container = try TestSupport.makeInMemoryContainer()
        context = ModelContext(container)
    }

    var cloudModelContext: ModelContext? { context }
    var cloudPauseReason: CloudSyncPause? { pause }
    func isMeetingDeleted(_ id: UUID) -> Bool { deleted.contains(id) }
    func cloudRemoveLocally(_ meeting: Meeting) { deleted.insert(meeting.id); context.delete(meeting) }
    func cloudCommit(_ mutate: @escaping () -> Void) -> Bool { mutate(); do { try context.save(); return true } catch { return false } }
    func cloudFetchMeetings(_ descriptor: FetchDescriptor<Meeting>) -> [Meeting]? { try? context.fetch(descriptor) }
    func cloudFetchTombstones() -> [MeetingTombstone]? { try? context.fetch(FetchDescriptor<MeetingTombstone>()) }
    func cloudDidInsertMeetings(_ meetings: [Meeting]) { inserted += meetings.map(\.id) }
    func cloudDidChangeMeetings(_ updated: [Meeting]) { changedCount += 1 }
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

    // MARK: Push

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
        transport.oldestRetainedSeq = transport.seq + 10
        await tick()
        XCTAssertNotNil(host.meeting(remoteID))
        XCTAssertEqual(a.cloudRevision, 1)
        XCTAssertTrue(transport.calls.filter { $0 == "manifest" }.count >= 2)
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
}


// MARK: - AppState wiring

@MainActor
final class CloudSyncAppStateTests: XCTestCase {
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

        // A user delete of a never-synced meeting leaves a tombstone only while the switch is on.
        let fresh = Meeting(title: "Never uploaded", startTime: Date(), endTime: Date())
        context.insert(fresh)
        try context.save()
        state.noteMeetingDeleted(fresh)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MeetingTombstone>()).count, 2)
        state.cloudSyncEnabled = false
    }
}
