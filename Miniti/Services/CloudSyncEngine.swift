import Foundation
import SwiftData

/// Why the engine is not syncing right now. Shown in Settings → Cloud.
enum CloudSyncPause: Equatable {
    case off
    case notManaged
    case notEnrolled
    case privateMode
    case notPro
    case offline
    case unavailable
    case notAvailableYet
    case deviceRemoved

    var label: String {
        switch self {
        case .off: return "Off"
        case .notManaged: return "Cloud needs the managed plan"
        case .notEnrolled: return "No account on this device"
        case .privateMode: return "Paused while private mode is on"
        case .notPro: return "Cloud needs Pro"
        case .offline: return "Waiting for a connection"
        case .unavailable: return "Cloud is not available right now"
        case .notAvailableYet: return "Cloud is not available for this account yet"
        case .deviceRemoved: return "This device was removed from the account"
        }
    }
}

/// What the engine needs from the app. `AppState` conforms in `AppState+CloudSync.swift`;
/// tests conform with an in-memory container and a fake transport.
@MainActor
protocol CloudSyncHost: AnyObject {
    var cloudModelContext: ModelContext? { get }
    /// Nil when syncing is allowed, else why it is paused.
    var cloudPauseReason: CloudSyncPause? { get }
    /// The live or just-stopped meeting: never read, written, or deleted by the engine.
    var liveMeetingID: UUID? { get }
    var cloudAccountID: String? { get }
    func isMeetingDeleted(_ id: UUID) -> Bool
    /// Remove a meeting the cloud already deleted (or replaced): the app's delete bookkeeping
    /// without a tombstone, then `context.delete`. Called inside a `cloudCommit` block.
    func cloudRemoveLocally(_ meeting: Meeting)
    /// Run `mutate` then save through the app's persistence policy.
    func cloudCommit(_ mutate: @escaping () -> Void) -> Bool
    func cloudFetchMeetings(_ descriptor: FetchDescriptor<Meeting>) -> [Meeting]?
    func cloudFetchTombstones() -> [MeetingTombstone]?
    /// Meetings that arrived from another device were inserted (History reload, auto-export).
    func cloudDidInsertMeetings(_ meetings: [Meeting])
    /// Existing meetings changed or were deleted from the cloud (History reload).
    func cloudDidChangeMeetings()
    /// The server said the account is not Pro (or is again).
    func cloudTierChanged(isPro: Bool)
}

/// Keeps finished, non-excluded meetings equal to the account's cloud copy (3.0.0).
///
/// Dirty detection is a fingerprint over every synced field except the transcript text
/// (`MeetingSyncDocument.fingerprint`), compared with the fingerprint the cloud last saw, so
/// no write path in the app has to stamp anything. Pushes are one `PUT` per meeting with the
/// server revision as the base; conflicts resolve last-writer-wins on `updated_at`, with the
/// server's tombstones and trim guard always winning. Pulls walk the change feed from a
/// per-account cursor; a cursor the server no longer retains falls back to a manifest
/// reconcile. Nothing here reads the live recording, and every model access happens on the
/// main actor between awaits with a deleted-id check first.
@MainActor
final class CloudSyncEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case reconciling
        case pushing(done: Int, total: Int)
        case pulling
        case paused(CloudSyncPause)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .paused(.off)
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var status: CloudStatus?
    @Published private(set) var skippedMeetingIDs: Set<UUID> = []
    @Published private(set) var lastError: String?

    weak var host: CloudSyncHost?
    var transport: CloudSyncTransport?
    /// Injectable for tests.
    var now: () -> Date = Date.init
    var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    var defaults: UserDefaults = .standard

    static let pushDebounce: TimeInterval = 5
    static let pollInterval: TimeInterval = 60
    static let pushBatch = 200
    static let pullPageSize = 50
    static let reconcileBatch = 50

    private var running = false
    private var rerunRequested = false
    private var needsReconcile = false
    private var debounceTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var deviceRemoved = false
    /// A commit happened since the last fingerprint scan. The 60 s poll only pulls unless
    /// this is set; a full scan still runs every fifth poll as a safety net.
    private var pendingScan = true
    private var pollsSinceScan = 0
    static let fullScanEveryPolls = 5

    // MARK: Lifecycle

    /// Start polling. Safe to call again.
    func start() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sync(reason: "poll") }
        }
        pendingScan = true
        refreshPause()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Re-evaluate the pause reason after a setting, mode, tier or account change.
    func refreshPause() {
        // Signing out clears the "removed" verdict; the next account starts clean.
        if host?.cloudPauseReason == .notEnrolled { deviceRemoved = false }
        if let reason = effectivePause() {
            phase = .paused(reason)
        } else if case .paused = phase {
            phase = .idle
            // Gates just opened (switch, tier, enrollment): do not wait for the poll.
            kick(reason: "resumed")
        }
    }

    /// Every loop checks this between awaits so private mode or the switch stops a pass
    /// mid-backlog instead of finishing up to 200 uploads.
    private var stillAllowed: Bool { effectivePause() == nil }

    private func effectivePause() -> CloudSyncPause? {
        if deviceRemoved { return .deviceRemoved }
        return host?.cloudPauseReason
    }

    /// Something committed locally: push soon.
    func noteLocalChange() {
        pendingScan = true
        guard effectivePause() == nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await self.sleep(Self.pushDebounce)
            guard !Task.isCancelled else { return }
            await self.sync(reason: "change")
        }
    }

    /// App became active, the switch was turned on, or the user pressed Sync now.
    func kick(reason: String) {
        pendingScan = true
        Task { await sync(reason: reason, refreshStatus: true) }
    }

    /// Forget every cloud relationship on this device (sign out, move to another account,
    /// account deleted). Local meetings stay; they upload to whatever account comes next.
    func resetBookkeeping() {
        guard let host, let context = host.cloudModelContext else { return }
        let meetings = host.cloudFetchMeetings(FetchDescriptor<Meeting>()) ?? []
        let tombstones = host.cloudFetchTombstones() ?? []
        _ = host.cloudCommit {
            for meeting in meetings {
                meeting.cloudRevision = 0
                meeting.syncFingerprint = nil
                meeting.syncedAt = nil
                meeting.syncStateRaw = nil
            }
            for tombstone in tombstones { context.delete(tombstone) }
        }
        if let account = host.cloudAccountID { defaults.removeObject(forKey: Self.cursorKey(account)) }
        deviceRemoved = false
        skippedMeetingIDs = []
        status = nil
        lastSyncedAt = nil
        needsReconcile = true
        refreshPause()
    }

    /// Tests: whether a pass is in flight.
    var isRunning: Bool { running }

    /// Tests: force the next pass through the manifest without touching meetings.
    func resetBookkeepingCursorOnly() {
        cursor = 0
        needsReconcile = true
    }

    // MARK: Cursor

    static func cursorKey(_ account: String) -> String { "cloudSync.cursor.\(account)" }

    private var cursor: Int {
        get {
            guard let account = host?.cloudAccountID else { return 0 }
            return defaults.integer(forKey: Self.cursorKey(account))
        }
        set {
            guard let account = host?.cloudAccountID else { return }
            defaults.set(newValue, forKey: Self.cursorKey(account))
        }
    }

    // MARK: Sync

    /// One pass: scan and push, send tombstones, pull. Single flight; a request during a run
    /// queues one more run.
    func sync(reason: String, refreshStatus: Bool = false) async {
        if running {
            rerunRequested = true
            return
        }
        running = true
        var passes = 0
        repeat {
            rerunRequested = false
            passes += 1
            await pass(reason: passes == 1 ? reason : "rerun", refreshStatus: refreshStatus)
        } while rerunRequested && passes < 5
        running = false
    }

    private func pass(reason: String, refreshStatus: Bool) async {
        guard let host, let transport, host.cloudModelContext != nil else { return }
        if let reason = effectivePause() {
            phase = .paused(reason)
            return
        }
        lastError = nil
        do {
            // Stamp local edits before anything compares timestamps with the cloud. The poll
            // skips the scan when nothing committed since the last one.
            let shouldScan = pendingScan || reason != "poll" || pollsSinceScan + 1 >= Self.fullScanEveryPolls || cursor == 0 || needsReconcile
            if shouldScan {
                _ = scan(host: host)
                pendingScan = false
                pollsSinceScan = 0
            } else {
                pollsSinceScan += 1
            }
            if cursor == 0 || needsReconcile {
                phase = .reconciling
                try await reconcile(host: host, transport: transport)
                needsReconcile = false
            }
            if shouldScan { try await push(host: host, transport: transport) }
            try await pushTombstones(host: host, transport: transport)
            guard stillAllowed else { refreshPause(); return }
            phase = .pulling
            try await pull(host: host, transport: transport)
            if refreshStatus || status == nil {
                status = try await transport.status()
            }
            lastSyncedAt = now()
            phase = .idle
            DebugLogger.shared.log(.app, "Cloud sync done reason=\(reason)")
        } catch let error as CloudSyncError {
            handle(error)
        } catch {
            phase = .failed("Sync failed")
            lastError = String(describing: type(of: error))
            DebugLogger.shared.log(.app, "Cloud sync FAILED: \(type(of: error))", level: .warning)
        }
    }

    private func handle(_ error: CloudSyncError) {
        switch error {
        case .cursorExpired:
            needsReconcile = true
            cursor = 0
            rerunRequested = true
        case .proRequired:
            phase = .paused(.notPro)
            host?.cloudTierChanged(isPro: false)
        case .unavailable:
            phase = .paused(.unavailable)
        case .notAvailableYet:
            phase = .paused(.notAvailableYet)
        case .requiresManaged:
            phase = .paused(.notManaged)
        case .offline:
            phase = .paused(.offline)
        case .notEnrolled:
            phase = .paused(.notEnrolled)
        case .revoked:
            deviceRemoved = true
            phase = .paused(.deviceRemoved)
        case .rateLimited:
            phase = .failed("Too many requests, trying again later")
        case .server(let code, _):
            phase = .failed("Sync failed (\(code))")
            lastError = code
        }
        DebugLogger.shared.log(.app, "Cloud sync paused: \(error)", level: .warning)
    }

    // MARK: Scan

    private func finishedMeetings(_ host: CloudSyncHost) -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.endTime != nil && $0.syncExcluded == false })
        return host.cloudFetchMeetings(descriptor) ?? []
    }

    /// Update `localFingerprint` and `updatedAt` for every meeting whose content moved since
    /// the last look, and return the ones the cloud does not have yet.
    private func scan(host: CloudSyncHost) -> [Meeting] {
        let live = host.liveMeetingID
        var changed: [(Meeting, String)] = []
        var dirty: [Meeting] = []
        for meeting in finishedMeetings(host) where meeting.id != live && !host.isMeetingDeleted(meeting.id) {
            let fingerprint = MeetingSyncDocument.fingerprint(of: meeting)
            if fingerprint != meeting.localFingerprint { changed.append((meeting, fingerprint)) }
            if fingerprint != meeting.syncFingerprint && meeting.syncStateRaw == nil { dirty.append(meeting) }
            else if fingerprint != meeting.syncFingerprint && meeting.syncStateRaw != nil && fingerprint != meeting.localFingerprint {
                // Content changed since it was skipped: try again.
                dirty.append(meeting)
            }
        }
        if !changed.isEmpty {
            let stamp = now()
            _ = host.cloudCommit {
                for (meeting, fingerprint) in changed {
                    // First observation of a legacy meeting keeps its own history as the timestamp.
                    meeting.updatedAt = meeting.localFingerprint == nil && meeting.updatedAt == nil ? MeetingSyncDocument.fallbackUpdatedAt(meeting) : stamp
                    meeting.localFingerprint = fingerprint
                    if meeting.syncStateRaw != nil { meeting.syncStateRaw = nil }
                }
            }
        }
        return dirty.sorted { $0.startTime < $1.startTime }
    }

    // MARK: Push

    private func push(host: CloudSyncHost, transport: CloudSyncTransport) async throws {
        let dirty = Array(scan(host: host).prefix(Self.pushBatch))
        guard !dirty.isEmpty else { return }
        var done = 0
        phase = .pushing(done: 0, total: dirty.count)
        // Ids are read before any await: a meeting deleted mid-batch must not be touched.
        for (id, meeting) in dirty.map({ ($0.id, $0) }) {
            guard stillAllowed else { return }
            guard meeting.modelContext != nil, !host.isMeetingDeleted(id) else { continue }
            try await push(meeting, id: id, host: host, transport: transport, retrying: false)
            done += 1
            phase = .pushing(done: done, total: dirty.count)
        }
        if dirty.count == Self.pushBatch { rerunRequested = true }
    }

    private func push(_ meeting: Meeting, id: UUID, host: CloudSyncHost, transport: CloudSyncTransport, retrying: Bool) async throws {
        let fingerprint = MeetingSyncDocument.fingerprint(of: meeting)
        let document = MeetingSyncDocument.encode(meeting, segments: meeting.segments)
        let base = meeting.cloudRevision
        let localUpdatedAt = meeting.updatedAt ?? MeetingSyncDocument.fallbackUpdatedAt(meeting)
        let localTranscriptRevision = meeting.transcriptRevision
        let result = try await transport.putMeeting(id: id, baseRevision: base, document: document)
        if host.isMeetingDeleted(id) || meeting.modelContext == nil {
            // Deleted while the upload was in flight: the cloud now has a copy nobody wants.
            if case .ok(let revision) = result, let context = host.cloudModelContext {
                _ = host.cloudCommit { context.insert(MeetingTombstone(id: id, cloudRevision: revision)) }
                rerunRequested = true
            }
            return
        }
        switch result {
        case .ok(let revision):
            _ = host.cloudCommit {
                meeting.cloudRevision = revision
                meeting.syncFingerprint = fingerprint
                meeting.syncedAt = self.now()
                meeting.syncStateRaw = nil
            }
            skippedMeetingIDs.remove(id)
        case .tooLarge:
            _ = host.cloudCommit {
                meeting.syncStateRaw = "skipped_too_large"
                meeting.syncFingerprint = fingerprint
            }
            skippedMeetingIDs.insert(id)
        case .externalDuplicate(let existing):
            // Same import on two devices: the cloud copy wins, this local duplicate goes.
            deleteLocal(meeting, host: host)
            let pendingDeletes = Set((host.cloudFetchTombstones() ?? []).map(\.id))
            if let context = host.cloudModelContext, let document = existing.document, let decoded = MeetingSyncDocument.decode(document),
               !host.isMeetingDeleted(existing.id), !pendingDeletes.contains(existing.id),
               localMeeting(id: existing.id, host: host) == nil {
                var inserted: Meeting?
                _ = host.cloudCommit {
                    let created = MeetingSyncDocument.makeMeeting(decoded, in: context)
                    self.markSynced(created, revision: existing.revision)
                    inserted = created
                }
                if let inserted { host.cloudDidInsertMeetings([inserted]) }
            }
        case .conflict(let state):
            if state.deleted {
                deleteLocal(meeting, host: host)
                return
            }
            let remoteNewer = (state.updatedAt ?? .distantPast) > localUpdatedAt
            let decoded = state.document.flatMap(MeetingSyncDocument.decode)
            if remoteNewer || retrying, let decoded {
                applyRemote(decoded, revision: state.revision, to: meeting, host: host)
                host.cloudDidChangeMeetings()
            } else if !retrying, let decoded, decoded.transcriptRevision > localTranscriptRevision, let context = host.cloudModelContext {
                // The other device trimmed or corrected the transcript: take its transcript, keep
                // this device's newer title, notes and insights, and push the merge.
                _ = host.cloudCommit {
                    MeetingSyncDocument.applyTranscript(decoded, to: meeting, in: context)
                    meeting.cloudRevision = state.revision
                }
                host.cloudDidChangeMeetings()
                try await push(meeting, id: id, host: host, transport: transport, retrying: true)
            } else if !retrying {
                _ = host.cloudCommit { meeting.cloudRevision = state.revision }
                try await push(meeting, id: id, host: host, transport: transport, retrying: true)
            } else {
                // Twice refused without a document to apply: wait for the pull.
                _ = host.cloudCommit { meeting.cloudRevision = state.revision }
            }
        }
    }

    private func pushTombstones(host: CloudSyncHost, transport: CloudSyncTransport) async throws {
        guard let context = host.cloudModelContext else { return }
        for (id, base, tombstone) in (host.cloudFetchTombstones() ?? []).map({ ($0.id, $0.cloudRevision, $0) }) {
            guard stillAllowed else { return }
            let result = try await transport.deleteMeeting(id: id, baseRevision: base)
            guard tombstone.modelContext != nil else { continue }
            switch result {
            case .ok:
                _ = host.cloudCommit { context.delete(tombstone) }
            case .conflict(let state):
                if state.deleted {
                    _ = host.cloudCommit { context.delete(tombstone) }
                } else {
                    // Another device edited it after this one deleted it: the delete still wins.
                    let again = try await transport.deleteMeeting(id: id, baseRevision: state.revision)
                    guard tombstone.modelContext != nil else { continue }
                    if case .ok = again { _ = host.cloudCommit { context.delete(tombstone) } }
                    else if case .conflict(let s) = again, s.deleted { _ = host.cloudCommit { context.delete(tombstone) } }
                }
            }
        }
    }

    // MARK: Pull

    private func pull(host: CloudSyncHost, transport: CloudSyncTransport) async throws {
        guard cursor > 0 else { return }
        var pages = 0
        while pages < 200 {
            pages += 1
            guard stillAllowed else { return }
            let page = try await transport.changes(since: cursor, limit: Self.pullPageSize)
            try apply(page.changes, host: host)
            cursor = max(cursor, page.nextSince)
            if !page.hasMore { break }
        }
    }

    private func apply(_ changes: [CloudChange], host: CloudSyncHost) throws {
        guard let context = host.cloudModelContext, !changes.isEmpty else { return }
        let live = host.liveMeetingID
        let pendingDeletes = Set((host.cloudFetchTombstones() ?? []).map(\.id))
        var inserted: [Meeting] = []
        var changed = false
        _ = host.cloudCommit {
            for change in changes where change.id != live && !host.isMeetingDeleted(change.id) {
                let local = self.localMeeting(id: change.id, host: host)
                if change.deleted {
                    if let local, local.cloudRevision > 0 || local.syncFingerprint != nil {
                        host.cloudRemoveLocally(local)
                        changed = true
                    }
                    continue
                }
                guard let document = change.document, let decoded = MeetingSyncDocument.decode(document) else { continue }
                if let local {
                    guard local.cloudRevision < change.revision else { continue }
                    let dirty = local.syncFingerprint != MeetingSyncDocument.fingerprint(of: local)
                    if dirty, let localUpdated = local.updatedAt, localUpdated > decoded.updatedAt {
                        // Local edit is newer: keep it and push against the new revision.
                        local.cloudRevision = change.revision
                        continue
                    }
                    self.applyRemote(decoded, revision: change.revision, to: local, host: host, commit: false)
                    changed = true
                } else if !pendingDeletes.contains(change.id) {
                    let created = MeetingSyncDocument.makeMeeting(decoded, in: context)
                    self.markSynced(created, revision: change.revision)
                    inserted.append(created)
                }
            }
        }
        if !inserted.isEmpty { host.cloudDidInsertMeetings(inserted) }
        if changed { host.cloudDidChangeMeetings() }
    }

    // MARK: Reconcile

    private func reconcile(host: CloudSyncHost, transport: CloudSyncTransport) async throws {
        guard let context = host.cloudModelContext else { return }
        let manifest = try await transport.manifest()
        let live = host.liveMeetingID
        let pendingDeletes = Set((host.cloudFetchTombstones() ?? []).map(\.id))
        var byID: [UUID: Meeting] = [:]
        for meeting in host.cloudFetchMeetings(FetchDescriptor<Meeting>()) ?? [] { byID[meeting.id] = meeting }
        var toFetch: [UUID] = []
        var seen: Set<UUID> = []
        _ = host.cloudCommit {
            for entry in manifest.entries where entry.id != live && !host.isMeetingDeleted(entry.id) {
                seen.insert(entry.id)
                let local = byID[entry.id]
                if entry.deleted {
                    if let local, local.cloudRevision > 0 || local.syncFingerprint != nil {
                        host.cloudRemoveLocally(local)
                    }
                    continue
                }
                if let local {
                    if local.cloudRevision < entry.revision { toFetch.append(entry.id) }
                    else if local.cloudRevision > entry.revision {
                        // The cloud copy was replaced (purged and re-created); push ours against it.
                        local.cloudRevision = entry.revision
                        local.syncFingerprint = nil
                    }
                } else if !pendingDeletes.contains(entry.id) {
                    toFetch.append(entry.id)
                }
            }
            // Meetings the cloud no longer lists are re-uploaded, never deleted.
            for (id, local) in byID where !seen.contains(id) && local.cloudRevision > 0 {
                local.cloudRevision = 0
                local.syncFingerprint = nil
            }
        }
        var inserted: [Meeting] = []
        var changed = false
        var index = 0
        while index < toFetch.count {
            guard stillAllowed else { return }
            let batch = Array(toFetch[index..<min(index + Self.reconcileBatch, toFetch.count)])
            index += batch.count
            let states = try await transport.fetchMeetings(ids: batch)
            _ = host.cloudCommit {
                for state in states where !state.deleted && !host.isMeetingDeleted(state.id) && state.id != host.liveMeetingID {
                    guard let document = state.document, let decoded = MeetingSyncDocument.decode(document) else { continue }
                    if let local = self.localMeeting(id: state.id, host: host) {
                        let dirty = local.syncFingerprint != MeetingSyncDocument.fingerprint(of: local)
                        if dirty, let localUpdated = local.updatedAt, localUpdated > decoded.updatedAt {
                            local.cloudRevision = state.revision
                            continue
                        }
                        self.applyRemote(decoded, revision: state.revision, to: local, host: host, commit: false)
                        changed = true
                    } else {
                        let created = MeetingSyncDocument.makeMeeting(decoded, in: context)
                        self.markSynced(created, revision: state.revision)
                        inserted.append(created)
                    }
                }
            }
        }
        cursor = max(manifest.latestSeq, 1)
        if !inserted.isEmpty { host.cloudDidInsertMeetings(inserted) }
        if changed { host.cloudDidChangeMeetings() }
    }

    // MARK: Helpers

    private func localMeeting(id: UUID, host: CloudSyncHost) -> Meeting? {
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        return host.cloudFetchMeetings(descriptor)?.first
    }

    private func markSynced(_ meeting: Meeting, revision: Int) {
        let fingerprint = MeetingSyncDocument.fingerprint(of: meeting)
        meeting.cloudRevision = revision
        meeting.syncFingerprint = fingerprint
        meeting.localFingerprint = fingerprint
        meeting.syncedAt = now()
        meeting.syncStateRaw = nil
    }

    private func applyRemote(_ decoded: MeetingSyncDocument.Decoded, revision: Int, to meeting: Meeting, host: CloudSyncHost, commit: Bool = true) {
        guard let context = host.cloudModelContext else { return }
        let replaceSegments = meeting.transcriptRevision != decoded.transcriptRevision || meeting.segments.count != decoded.segments.count
        let work = {
            MeetingSyncDocument.apply(decoded, to: meeting, in: context, replaceSegments: replaceSegments)
            self.markSynced(meeting, revision: revision)
        }
        if commit { _ = host.cloudCommit(work) } else { work() }
    }

    private func deleteLocal(_ meeting: Meeting, host: CloudSyncHost) {
        _ = host.cloudCommit { host.cloudRemoveLocally(meeting) }
        host.cloudDidChangeMeetings()
    }
}
