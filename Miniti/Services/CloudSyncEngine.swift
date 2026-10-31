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

    var diagnosticReason: String {
        switch self {
        case .off: return "off"
        case .notManaged: return "not_managed"
        case .notEnrolled: return "not_enrolled"
        case .privateMode: return "private_mode"
        case .notPro: return "not_pro"
        case .offline: return "network"
        case .unavailable, .notAvailableYet: return "not_available"
        case .deviceRemoved: return "device_removed"
        }
    }

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
    /// Selected meeting, kept safe from incoming changes while its view owns local state.
    var liveMeetingID: UUID? { get }
    /// Active capture/final transcript commit, not merely a stopped meeting still on screen.
    var cloudUploadProtectedMeetingID: UUID? { get }
    func cloudProtectsIncoming(_ id: UUID) -> Bool
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
    /// Existing meetings changed or were deleted from the cloud (History reload); `updated`
    /// lists the ones still present so macOS can refresh their markdown export.
    func cloudDidChangeMeetings(_ updated: [Meeting])
    /// The server said the account is not Pro (or is again).
    func cloudTierChanged(isPro: Bool)
}

extension CloudSyncHost {
    var cloudUploadProtectedMeetingID: UUID? { liveMeetingID }
    func cloudProtectsIncoming(_ id: UUID) -> Bool { id == liveMeetingID }
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
    @Published private(set) var statusFetchedAt: Date?
    @Published private(set) var statusRefreshFailed = false
    @Published private(set) var pendingUploadCount = 0
    @Published private(set) var pendingRemovalCount = 0
    @Published private(set) var protectedMeetingCount = 0
    @Published private(set) var scanFailed = false
    @Published private(set) var waitingForLocalEdits = false

    var statusIsStale: Bool {
        statusRefreshFailed || statusFetchedAt.map { now().timeIntervalSince($0) >= Self.statusFreshness } != false
    }

    var idleLabel: String {
        if scanFailed { return "Could not check local meetings" }
        if waitingForLocalEdits { return "Waiting for local edits to save" }
        if pendingUploadCount > 0 || pendingRemovalCount > 0 { return "Changes waiting to sync" }
        if protectedMeetingCount > 0 { return "Recording or edits are still in progress" }
        if !skippedMeetingIDs.isEmpty { return "Some meetings could not upload" }
        return lastSyncedAt == nil ? "Waiting to check" : "Checked for changes"
    }
    var pendingChangesCaption: String? {
        var parts: [String] = []
        if pendingUploadCount > 0 { parts.append("\(pendingUploadCount) upload\(pendingUploadCount == 1 ? "" : "s")") }
        if pendingRemovalCount > 0 { parts.append("\(pendingRemovalCount) removal\(pendingRemovalCount == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : "This device: " + parts.joined(separator: " and ") + " waiting."
    }
    @Published private(set) var skippedMeetingIDs: Set<UUID> = []
    @Published private(set) var lastError: String?
    /// What moved and why, newest first, for Settings → Cloud → View log. Kept in
    /// UserDefaults across launches (the last 300 entries, titles only, never transcript text).
    @Published private(set) var log: [CloudSyncLogEntry] = [] {
        didSet { persistLog() }
    }
    static let logCapacity = 300
    static let logKey = "cloudSync.log"

    struct CloudSyncLogEntry: Identifiable, Equatable, Codable {
        enum Kind: String, Codable { case uploaded, downloaded, updated, deletedLocally = "deleted here", deletedInCloud = "deleted in cloud", conflict, skipped, paused, error, info }
        var id = UUID()
        let at: Date
        let kind: Kind
        let title: String
        let detail: String?
    }

    func note(_ kind: CloudSyncLogEntry.Kind, _ title: String, _ detail: String? = nil) {
        log.insert(CloudSyncLogEntry(at: now(), kind: kind, title: title, detail: detail), at: 0)
        if log.count > Self.logCapacity { log.removeLast(log.count - Self.logCapacity) }
    }

    func clearLog() { log = [] }

    private var logLoaded = false
    func loadLogIfNeeded() {
        guard !logLoaded else { return }
        logLoaded = true
        if let data = defaults.data(forKey: Self.logKey), let saved = try? JSONDecoder().decode([CloudSyncLogEntry].self, from: data) {
            log = saved
        }
    }

    private func persistLog() {
        guard logLoaded else { return }
        if let data = try? JSONEncoder().encode(Array(log.prefix(Self.logCapacity))) { defaults.set(data, forKey: Self.logKey) }
    }

    weak var host: CloudSyncHost?
    var transport: CloudSyncTransport?
    /// Injectable for tests.
    var now: () -> Date = Date.init

    /// Cloud stamps carry milliseconds; a local `Date` carries microseconds. A meeting's own
    /// stamp, echoed back by the cloud, must not read as "newer than itself" (2026-10-21: every
    /// meeting re-uploaded as a conflict after a reconcile, bumping every revision).
    nonisolated static func isNewer(_ local: Date, than remote: Date) -> Bool {
        local.timeIntervalSince(remote) > 0.001
    }

    /// Stamps written locally are rounded to the millisecond so they survive the round trip unchanged.
    nonisolated static func stamp(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }
    var sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    var defaults: UserDefaults = .standard

    static let pushDebounce: TimeInterval = 5
    static let pollInterval: TimeInterval = 60
    static let statusFreshness: TimeInterval = 300
    static let pushBatch = 200
    static let pullPageSize = 50
    static let reconcileBatch = 50

    private var running = false
    private var rerunRequested = false
    private var attemptedCursorRecovery = false
    private var needsReconcile = false
    private var deferredIncomingIDs: Set<UUID> = []
    private var lastScannedUploadProtectedID: UUID?
    private enum PassDeferral: Error { case localEdits, committedEdits }

    private func rememberProtectedIncoming(id: UUID, revision: Int, deleted: Bool, host: CloudSyncHost) {
        guard host.cloudProtectsIncoming(id) else { return }
        // Our own upload echoed through the feed needs no later manifest revisit.
        if !deleted, let local = localMeeting(id: id, host: host), local.cloudRevision >= revision { return }
        deferredIncomingIDs.insert(id)
    }

    private func deferForLocalEdits() throws {
        pendingScan = true
        needsReconcile = true
        throw PassDeferral.localEdits
    }
    private var statusDirty = false
    private var requestedStatusRefresh = false

    // MARK: Pass authority (R3, 2026-10-27)

    /// What a pass runs under: the account it started for and a generation that moves on
    /// every account or credential change, sign-out, revoke and explicit reset. Captured once
    /// per pass and compared after every await, before anything learned is applied.
    struct PassContext: Equatable {
        let accountID: String?
        let generation: Int
    }
    private var generation = 0

    /// Discard the authority of every pass in flight. Called by `resetBookkeeping` and by the
    /// host on account or credential changes.
    func invalidatePasses(reason: String) {
        generation += 1
        status = nil
        statusFetchedAt = nil
        statusRefreshFailed = false
        lastSyncedAt = nil
        pendingUploadCount = 0
        pendingRemovalCount = 0
        protectedMeetingCount = 0
        waitingForLocalEdits = false
        // A same-account credential replacement keeps its cursor. Reconcile once under
        // the new authority before forgetting protected rows skipped by the old pass.
        // On an account change the same flag safely checks only the new account.
        needsReconcile = true
        deferredIncomingIDs = []
        lastScannedUploadProtectedID = nil
        pendingScan = true
        DebugLogger.shared.log(.app, "Cloud sync: passes invalidated (\(reason))")
    }

    private func currentContext() -> PassContext {
        PassContext(accountID: host?.cloudAccountID, generation: generation)
    }

    private func isCurrent(_ context: PassContext) -> Bool {
        context == currentContext()
    }

    /// After an await: the pass may continue only if nothing took its authority away.
    private func check(_ context: PassContext) throws {
        guard isCurrent(context) else { throw CloudSyncError.superseded }
    }

    /// Cursor writes belong to the captured account, and only while that context holds.
    private func setCursor(_ value: Int, for context: PassContext) {
        guard isCurrent(context), let account = context.accountID else { return }
        defaults.set(value, forKey: Self.cursorKey(account))
    }
    private var debounceTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var deviceRemoved = false
    /// A commit happened since the last fingerprint scan. The 60 s poll only pulls unless
    /// this is set; a full scan still runs every fifth poll as a safety net.
    private var pendingScan = true
    private var localChangeGeneration = 0
    private var pollsSinceScan = 0
    static let fullScanEveryPolls = 5

    // MARK: Lifecycle

    /// Start polling. Safe to call again.
    func start() {
        loadLogIfNeeded()
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
            if phase != .paused(reason) { DiagnosticTimeline.shared.record(.cloudPaused, fields: ["reason": reason.diagnosticReason]) }
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
        localChangeGeneration += 1
        pendingScan = true
        guard effectivePause() == nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await self.sleep(Self.pushDebounce)
            guard !Task.isCancelled else { return }
            // Debounce only the wait, never an upload already in progress. A later save
            // queues another pass through sync's single-flight guard instead of cancelling
            // this task's URLSession request (-999).
            self.debounceTask = nil
            await self.sync(reason: "change")
        }
    }

    /// Capture or final processing released a protected meeting. Reconcile skipped inbound
    /// rows as well as scanning its newly eligible durable transcript.
    func noteLifecycleChange() {
        guard let host else { return }
        let released = deferredIncomingIDs.filter { !host.cloudProtectsIncoming($0) }
        if !released.isEmpty {
            needsReconcile = true
            deferredIncomingIDs.subtract(released)
        }
        // Finishing AI, leaving the screen, and releasing capture can fire separately.
        // Only revisit the manifest for incoming rows we actually skipped. Durable AI
        // commits already schedule their own scans through noteLocalChange.
        if !released.isEmpty || lastScannedUploadProtectedID != host.cloudUploadProtectedMeetingID {
            noteLocalChange()
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
        invalidatePasses(reason: "reset")
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
        requestedStatusRefresh = requestedStatusRefresh || refreshStatus
        if running {
            rerunRequested = true
            return
        }
        running = true
        attemptedCursorRecovery = false
        var passes = 0
        repeat {
            rerunRequested = false
            passes += 1
            let refresh = requestedStatusRefresh
            requestedStatusRefresh = false
            await pass(reason: passes == 1 ? reason : "rerun", refreshStatus: refresh)
        } while rerunRequested && passes < 5 && !Task.isCancelled
        running = false
        // Yield after a bounded run without losing a commit or a batch beyond the cap.
        if rerunRequested { noteLocalChange() }
    }

    private func pass(reason: String, refreshStatus: Bool) async {
        guard let host, let transport, host.cloudModelContext != nil else { return }
        if let reason = effectivePause() {
            phase = .paused(reason)
            return
        }
        lastError = nil
        let context = currentContext()
        let diagnosticID = UUID().uuidString
        // Background polls/autosaves can repeat all meeting long. Their useful uploads,
        // removals and failures are recorded separately, without an empty-pass heartbeat.
        let explicitPass = !["poll", "change", "rerun"].contains(reason)
        if explicitPass { DiagnosticTimeline.shared.record(.cloudStarted, fields: ["attempt_id": diagnosticID]) }
        do {
            // Stamp local edits before anything compares timestamps with the cloud. The poll
            // skips the scan when nothing committed since the last one.
            let shouldScan = pendingScan || reason != "poll" || pollsSinceScan + 1 >= Self.fullScanEveryPolls || cursor == 0 || needsReconcile
            if shouldScan {
                pendingScan = false
                _ = try scan(host: host)
                pollsSinceScan = 0
            } else {
                pollsSinceScan += 1
            }
            if cursor == 0 || needsReconcile {
                phase = .reconciling
                needsReconcile = false
                do {
                    try await reconcile(host: host, transport: transport, context: context)
                    try check(context)
                } catch {
                    // A failed manifest/batch must not consume the only signal to revisit
                    // incoming changes skipped while a meeting was protected.
                    if isCurrent(context) { needsReconcile = true }
                    throw error
                }
            }
            if shouldScan { try await push(host: host, transport: transport, context: context) }
            try await pushTombstones(host: host, transport: transport, context: context)
            guard stillAllowed else { refreshPause(); return }
            phase = .pulling
            try await pull(host: host, transport: transport, context: context)
            try check(context)
            guard stillAllowed else { refreshPause(); return }
            if shouldScan || pendingScan || statusDirty { _ = try scan(host: host) }
            if refreshStatus || status == nil || statusDirty || statusIsStale {
                do {
                    let fresh = try await transport.status()
                    try check(context)
                    status = fresh
                    statusFetchedAt = now()
                    statusRefreshFailed = false
                    statusDirty = false
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try check(context)
                    // A count refresh cannot undo accepted uploads or masquerade as a fresh count.
                    statusRefreshFailed = true
                    if let error = error as? CloudSyncError,
                       [.revoked, .notEnrolled, .proRequired].contains(error) { throw error }
                }
            }
            try check(context)
            lastSyncedAt = now()
            waitingForLocalEdits = false
            phase = .idle
            if explicitPass { DiagnosticTimeline.shared.record(.cloudSucceeded, fields: ["attempt_id": diagnosticID]) }
            DebugLogger.shared.log(.app, "Cloud sync done reason=\(reason)")
        } catch is CancellationError {
            guard isCurrent(context) else { rerunRequested = true; return }
            // No completed-check timestamp or failure for an interrupted request. Keep
            // local work eligible for the next automatic poll or explicit kick.
            pendingScan = true
            refreshPause()
            if effectivePause() == nil { phase = .idle }
        } catch let deferral as PassDeferral {
            guard isCurrent(context) else { rerunRequested = true; return }
            switch deferral {
            case .localEdits: waitingForLocalEdits = true
            case .committedEdits: waitingForLocalEdits = false
            }
            phase = .idle
            // Keep the previous completed-check timestamp and do not emit cloudSucceeded.
            // A durable local save or the next poll will retry the preserved cursor.
        } catch CloudSyncError.superseded {
            // Another account or credential owns the engine now: nothing from this pass is
            // applied, and the new owner gets its own pass.
            DebugLogger.shared.log(.app, "Cloud sync pass superseded reason=\(reason)")
            DiagnosticTimeline.shared.record(.cloudSuperseded, fields: ["attempt_id": diagnosticID])
            rerunRequested = true
        } catch let error as CloudSyncError {
            // An answer for an account that is no longer current says nothing about this one:
            // it must not pause, fail or mark anything here.
            guard isCurrent(context) else {
                DebugLogger.shared.log(.app, "Cloud sync: stale error dropped (\(error))")
                rerunRequested = true
                return
            }
            DiagnosticTimeline.shared.record(.cloudFailed, fields: DiagnosticTimeline.errorFields(error))
            handle(error)
        } catch {
            guard isCurrent(context) else { rerunRequested = true; return }
            DiagnosticTimeline.shared.record(.cloudFailed, fields: DiagnosticTimeline.errorFields(error))
            phase = .failed("Sync failed")
            lastError = String(describing: type(of: error))
            note(.error, "Sync failed", String(describing: type(of: error)))
            DebugLogger.shared.log(.app, "Cloud sync FAILED: \(type(of: error))", level: .warning)
        }
    }

    private func handle(_ error: CloudSyncError) {
        switch error {
        case .cursorExpired:
            needsReconcile = true
            cursor = 0
            if attemptedCursorRecovery {
                // A manifest watermark can itself be outside the retained feed during
                // server churn. One immediate recovery is enough; keep reconciliation
                // pending for the next poll/action rather than chaining five-pass runs.
                rerunRequested = false
                phase = .failed("Could not finish checking cloud changes. Will try again.")
            } else {
                attemptedCursorRecovery = true
                rerunRequested = true
            }
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
        case .superseded:
            break
        }
        if case .paused(let reason) = phase { note(.paused, reason.label) } else if case .failed(let text) = phase { note(.error, text) }
        if case .paused(let reason) = phase { DiagnosticTimeline.shared.record(.cloudPaused, fields: ["reason": reason.diagnosticReason]) }
        switch error {
        case .server(_, let status): DiagnosticTimeline.shared.record(.cloudFailed, fields: ["reason": "server", "status": String(status)])
        case .rateLimited: DiagnosticTimeline.shared.record(.cloudFailed, fields: ["reason": "rate_limited"])
        case .cursorExpired: DiagnosticTimeline.shared.record(.cloudFailed, fields: ["reason": "cursor_expired"])
        default: break
        }
        DebugLogger.shared.log(.app, "Cloud sync paused: \(error)", level: .warning)
    }

    // MARK: Scan

    /// A failed fetch/save is not an empty or synchronized history. Cache counts at scan
    /// boundaries, never from a view render or transcript sample.
    private func scan(host: CloudSyncHost) throws -> [Meeting] {
        if scanFailed, !host.cloudCommit({}) {
            pendingScan = true
            throw CloudSyncError.server(code: "local_save_failed", status: 0)
        }
        guard let meetings = host.cloudFetchMeetings(FetchDescriptor<Meeting>()),
              let tombstones = host.cloudFetchTombstones() else {
            scanFailed = true
            pendingScan = true
            throw CloudSyncError.server(code: "local_scan_failed", status: 0)
        }
        let protected = host.cloudUploadProtectedMeetingID
        lastScannedUploadProtectedID = protected
        var changed: [(Meeting, String)] = []
        var dirty: [Meeting] = []
        var skipped: Set<UUID> = []
        protectedMeetingCount = meetings.filter { !$0.syncExcluded && !host.isMeetingDeleted($0.id) && ($0.id == protected || $0.endTime == nil) }.count
        pendingRemovalCount = tombstones.count
        for meeting in meetings where meeting.endTime != nil && !meeting.syncExcluded && meeting.id != protected && !host.isMeetingDeleted(meeting.id) {
            let fingerprint = MeetingSyncDocument.fingerprint(of: meeting)
            if fingerprint != meeting.localFingerprint { changed.append((meeting, fingerprint)) }
            if meeting.cloudRestoreRequested || (fingerprint != meeting.syncFingerprint && meeting.syncStateRaw == nil) { dirty.append(meeting) }
            else if fingerprint != meeting.syncFingerprint && meeting.syncStateRaw != nil && fingerprint != meeting.localFingerprint {
                dirty.append(meeting)
            } else if meeting.syncStateRaw != nil { skipped.insert(meeting.id) }
        }
        if !changed.isEmpty {
            let stamp = Self.stamp(now())
            guard host.cloudCommit({
                for (meeting, fingerprint) in changed {
                    meeting.updatedAt = meeting.localFingerprint == nil && meeting.updatedAt == nil ? MeetingSyncDocument.fallbackUpdatedAt(meeting) : stamp
                    meeting.localFingerprint = fingerprint
                    if meeting.syncStateRaw != nil { meeting.syncStateRaw = nil }
                }
            }) else {
                scanFailed = true
                pendingScan = true
                throw CloudSyncError.server(code: "local_save_failed", status: 0)
            }
        }
        pendingUploadCount = dirty.count
        skippedMeetingIDs = skipped
        scanFailed = false
        return dirty.sorted { $0.startTime < $1.startTime }
    }

    // MARK: Push

    private func push(host: CloudSyncHost, transport: CloudSyncTransport, context: PassContext) async throws {
        let dirty = Array(try scan(host: host).prefix(Self.pushBatch))
        guard !dirty.isEmpty else { return }
        DiagnosticTimeline.shared.record(.cloudUpload, fields: ["outcome": "pending", "pending_uploads": String(dirty.count)])
        var done = 0
        phase = .pushing(done: 0, total: dirty.count)
        // Ids are read before any await: a meeting deleted mid-batch must not be touched.
        for (id, meeting) in dirty.map({ ($0.id, $0) }) {
            guard stillAllowed else { return }
            guard meeting.modelContext != nil, !host.isMeetingDeleted(id), !meeting.syncExcluded, id != host.cloudUploadProtectedMeetingID else { continue }
            try await push(meeting, id: id, host: host, transport: transport, retrying: false, context: context)
            done += 1
            phase = .pushing(done: done, total: dirty.count)
        }
        if dirty.count == Self.pushBatch { rerunRequested = true }
    }

    private var inFlightUploadIDs: Set<UUID> = []
    func isUploading(_ id: UUID) -> Bool { inFlightUploadIDs.contains(id) }

    private func push(_ meeting: Meeting, id: UUID, host: CloudSyncHost, transport: CloudSyncTransport, retrying: Bool, context pass: PassContext) async throws {
        guard !meeting.syncExcluded, id != host.cloudUploadProtectedMeetingID, meeting.endTime != nil else { return }
        let fingerprint = MeetingSyncDocument.fingerprint(of: meeting)
        let document = try MeetingSyncDocument.encodeData(meeting, segments: meeting.segments)
        let base = meeting.cloudRevision
        let localUpdatedAt = meeting.updatedAt ?? MeetingSyncDocument.fallbackUpdatedAt(meeting)
        let localTranscriptRevision = meeting.transcriptRevision
        let restoring = meeting.cloudRestoreRequested
        inFlightUploadIDs.insert(id)
        defer { inFlightUploadIDs.remove(id) }
        let result = try await transport.putMeeting(id: id, baseRevision: base, document: document, restoreDeleted: restoring)
        try check(pass)
        if case .ok = result { statusDirty = true }
        if host.isMeetingDeleted(id) || meeting.modelContext == nil {
            // Deleted while the upload was in flight: the cloud now has a copy nobody wants.
            if case .ok(let revision) = result, let context = host.cloudModelContext {
                try save(host: host) { context.insert(MeetingTombstone(id: id, cloudRevision: revision)) }
                rerunRequested = true
            }
            return
        }
        // Exclusion may have happened while the first upload was in flight, when the
        // local revision was still zero. Persist deletion against the server's answer
        // before another pass can pull that copy back onto the device.
        if meeting.syncExcluded {
            let revision: Int?
            switch result {
            case .ok(let accepted): revision = accepted
            case .conflict(let state): revision = state.deleted ? nil : state.revision
            case .tooLarge, .externalDuplicate: revision = nil
            }
            if let revision {
                try save(host: host) { self.retainExcludedMeeting(meeting, remoteRevision: revision, host: host) }
            }
            return
        }
        let contentChanged = fingerprint != MeetingSyncDocument.fingerprint(of: meeting)
        let captureProtected = id == host.cloudUploadProtectedMeetingID || meeting.endTime == nil
        if contentChanged || captureProtected {
            // An accepted snapshot can record its server revision, but never certify newer
            // local content. Conflict documents/tombstones cannot overwrite a resumed capture.
            if case .ok(let revision) = result {
                guard host.cloudCommit({
                    meeting.cloudRevision = revision
                    meeting.syncFingerprint = fingerprint
                    meeting.syncedAt = self.now()
                }) else { scanFailed = true; pendingScan = true; throw CloudSyncError.server(code: "local_save_failed", status: 0) }
            }
            pendingScan = true
            if !captureProtected { rerunRequested = true }
            needsReconcile = true
            return
        }
        switch result {
        case .ok(let revision):
            guard host.cloudCommit({
                meeting.cloudRevision = revision
                meeting.syncFingerprint = fingerprint
                meeting.syncedAt = self.now()
                meeting.syncStateRaw = nil
                if restoring { meeting.cloudRestoreRequested = false }
            }) else { scanFailed = true; pendingScan = true; throw CloudSyncError.server(code: "local_save_failed", status: 0) }
            skippedMeetingIDs.remove(id)
            DiagnosticTimeline.shared.record(.cloudUpload, fields: ["outcome": "success"])
            note(base == 0 ? .uploaded : .updated, meeting.title, base == 0 ? "uploaded" : "changes sent")
        case .tooLarge:
            try save(host: host) {
                meeting.syncStateRaw = "skipped_too_large"
                meeting.syncFingerprint = fingerprint
            }
            skippedMeetingIDs.insert(id)
            note(.skipped, meeting.title, "too large for the cloud, kept on this device")
        case .externalDuplicate(let existing):
            guard !host.cloudProtectsIncoming(id) else { deferredIncomingIDs.insert(id); return }
            // Same import on two devices: the cloud copy wins, this local duplicate goes.
            note(.deletedLocally, meeting.title, "same import already in the cloud, local copy replaced")
            try deleteLocal(meeting, host: host)
            let pendingDeletes = Set((host.cloudFetchTombstones() ?? []).map(\.id))
            if let context = host.cloudModelContext, let document = existing.document, let decoded = MeetingSyncDocument.decode(document),
               !host.isMeetingDeleted(existing.id), !pendingDeletes.contains(existing.id),
               localMeeting(id: existing.id, host: host) == nil {
                var inserted: Meeting?
                try save(host: host) {
                    let created = MeetingSyncDocument.makeMeeting(decoded, in: context)
                    self.markSynced(created, revision: existing.revision)
                    inserted = created
                }
                if let inserted { host.cloudDidInsertMeetings([inserted]) }
            }
        case .conflict(let state):
            if host.cloudProtectsIncoming(id) {
                deferredIncomingIDs.insert(id)
                return
            }
            if state.deleted {
                if meeting.cloudRestoreRequested {
                    try save(host: host) { meeting.cloudRevision = state.revision }
                    if !retrying {
                        try await push(meeting, id: id, host: host, transport: transport, retrying: true, context: pass)
                    } else {
                        throw CloudSyncError.server(code: "cloud_restore_pending", status: 409)
                    }
                    return
                }
                note(.deletedLocally, meeting.title, "deleted on another device")
                try deleteLocal(meeting, host: host)
                return
            }
            let remoteStamp = state.updatedAt ?? .distantPast
            let localNewer = Self.isNewer(localUpdatedAt, than: remoteStamp)
            if !retrying {
                if localNewer || Self.isNewer(remoteStamp, than: localUpdatedAt) {
                    note(.conflict, meeting.title, "edited on another device too")
                } else {
                    // Same stamp on both sides: this is our own edit coming back, or the same
                    // edit made on both devices. The cloud copy is taken, nothing is pushed.
                    note(.info, meeting.title, "already in the cloud")
                }
            }
            let decoded = state.document.flatMap(MeetingSyncDocument.decode)
            if !localNewer || retrying, let decoded {
                guard applyRemote(decoded, revision: state.revision, to: meeting, host: host) else {
                    scanFailed = true; pendingScan = true
                    throw CloudSyncError.server(code: "local_save_failed", status: 0)
                }
                host.cloudDidChangeMeetings([meeting])
            } else if !retrying, let decoded, decoded.transcriptRevision > localTranscriptRevision, let context = host.cloudModelContext {
                // The other device trimmed or corrected the transcript: take its transcript, keep
                // this device's newer title, notes and insights, and push the merge.
                try save(host: host) {
                    MeetingSyncDocument.applyTranscript(decoded, to: meeting, in: context)
                    meeting.cloudRevision = state.revision
                }
                host.cloudDidChangeMeetings([meeting])
                try await push(meeting, id: id, host: host, transport: transport, retrying: true, context: pass)
            } else if !retrying {
                try save(host: host) { meeting.cloudRevision = state.revision }
                try await push(meeting, id: id, host: host, transport: transport, retrying: true, context: pass)
            } else {
                // Twice refused without a document to apply: wait for the pull.
                try save(host: host) { meeting.cloudRevision = state.revision }
            }
        }
    }

    private func pushTombstones(host: CloudSyncHost, transport: CloudSyncTransport, context pass: PassContext) async throws {
        guard let context = host.cloudModelContext else { return }
        let pending = (host.cloudFetchTombstones() ?? []).map { ($0.id, $0.cloudRevision, $0) }
        if !pending.isEmpty { DiagnosticTimeline.shared.record(.cloudRemoval, fields: ["outcome": "pending", "pending_removals": String(pending.count)]) }
        for (id, base, tombstone) in pending {
            guard stillAllowed else { return }
            let result = try await transport.deleteMeeting(id: id, baseRevision: base)
            try check(pass)
            guard tombstone.modelContext != nil else { continue }
            switch result {
            case .ok:
                statusDirty = true
                DiagnosticTimeline.shared.record(.cloudRemoval, fields: ["outcome": "success"])
                note(.deletedInCloud, String(id.uuidString.prefix(8)), "delete sent")
                try save(host: host) { context.delete(tombstone) }
            case .conflict(let state):
                if state.deleted {
                    try save(host: host) { context.delete(tombstone) }
                } else {
                    // Another device edited it after this one deleted it: the delete still wins.
                    let again = try await transport.deleteMeeting(id: id, baseRevision: state.revision)
                    try check(pass)
                    guard tombstone.modelContext != nil else { continue }
                    if case .ok = again { statusDirty = true; try save(host: host) { context.delete(tombstone) } }
                    else if case .conflict(let s) = again, s.deleted { try save(host: host) { context.delete(tombstone) } }
                }
            }
        }
    }

    // MARK: Pull

    private func pull(host: CloudSyncHost, transport: CloudSyncTransport, context: PassContext) async throws {
        guard cursor > 0 else { return }
        var pages = 0
        while pages < 200 {
            pages += 1
            guard stillAllowed else { return }
            let localGeneration = localChangeGeneration
            let page = try await transport.changes(since: cursor, limit: Self.pullPageSize)
            try check(context)
            if host.cloudModelContext?.hasChanges == true {
                // UI edits can exist before their queued save calls noteLocalChange. Keep
                // the cursor and retry after a durable save, without spinning on live audio.
                try deferForLocalEdits()
            }
            if localGeneration != localChangeGeneration {
                pendingScan = true
                needsReconcile = true
                rerunRequested = true
                throw PassDeferral.committedEdits
            }
            if !page.changes.isEmpty { statusDirty = true }
            try apply(page.changes, host: host)
            setCursor(max(cursor, page.nextSince), for: context)
            if !page.hasMore { break }
        }
    }

    private func apply(_ changes: [CloudChange], host: CloudSyncHost) throws {
        guard let context = host.cloudModelContext, !changes.isEmpty else { return }
        let pendingDeletes = Set((host.cloudFetchTombstones() ?? []).map(\.id))
        var inserted: [Meeting] = []
        var updated: [Meeting] = []
        var changed = false
        for change in changes { rememberProtectedIncoming(id: change.id, revision: change.revision, deleted: change.deleted, host: host) }
        try save(host: host) {
            for change in changes where !host.cloudProtectsIncoming(change.id) && !host.isMeetingDeleted(change.id) {
                let local = self.localMeeting(id: change.id, host: host)
                if let local, local.syncExcluded {
                    if !change.deleted { self.retainExcludedMeeting(local, remoteRevision: change.revision, host: host) }
                    continue
                }
                if let local, local.cloudRestoreRequested {
                    local.cloudRevision = max(local.cloudRevision, change.revision)
                    local.syncFingerprint = nil
                    self.rerunRequested = true
                    continue
                }
                if change.deleted {
                    if let local, local.cloudRevision > 0 || local.syncFingerprint != nil {
                        self.note(.deletedLocally, local.title, "deleted on another device")
                        host.cloudRemoveLocally(local)
                        changed = true
                    }
                    continue
                }
                guard let document = change.document, let decoded = MeetingSyncDocument.decode(document) else { continue }
                if let local {
                    guard local.cloudRevision < change.revision else { continue }
                    let dirty = local.syncFingerprint != MeetingSyncDocument.fingerprint(of: local)
                    if dirty, let localUpdated = local.updatedAt, Self.isNewer(localUpdated, than: decoded.updatedAt) {
                        // Local edit is newer: keep it and push against the new revision.
                        local.cloudRevision = change.revision
                        self.note(.conflict, local.title, "kept this device's newer edit")
                        continue
                    }
                    self.applyRemote(decoded, revision: change.revision, to: local, host: host, commit: false)
                    self.note(.updated, local.title, "changes from another device")
                    updated.append(local)
                    changed = true
                } else if !pendingDeletes.contains(change.id) {
                    let created = MeetingSyncDocument.makeMeeting(decoded, in: context)
                    self.markSynced(created, revision: change.revision)
                    self.note(.downloaded, created.title, "downloaded")
                    inserted.append(created)
                }
            }
        }
        if !inserted.isEmpty { host.cloudDidInsertMeetings(inserted) }
        if changed { host.cloudDidChangeMeetings(updated.filter { $0.modelContext != nil }) }
    }

    // MARK: Reconcile

    private func reconcile(host: CloudSyncHost, transport: CloudSyncTransport, context pass: PassContext) async throws {
        guard let context = host.cloudModelContext else { return }
        let localGeneration = localChangeGeneration
        let manifest = try await transport.manifest()
        try check(pass)
        if host.cloudModelContext?.hasChanges == true {
            try deferForLocalEdits()
        }
        if localGeneration != localChangeGeneration {
            pendingScan = true
            needsReconcile = true
            rerunRequested = true
            throw PassDeferral.committedEdits
        }
        statusDirty = statusDirty || manifest.latestSeq > cursor
        note(.info, "Checked the cloud", "\(manifest.entries.filter { !$0.deleted }.count) meetings there")
        let pendingDeletes = Set((host.cloudFetchTombstones() ?? []).map(\.id))
        var byID: [UUID: Meeting] = [:]
        for meeting in host.cloudFetchMeetings(FetchDescriptor<Meeting>()) ?? [] { byID[meeting.id] = meeting }
        var toFetch: [UUID] = []
        var seen: Set<UUID> = []
        for entry in manifest.entries { rememberProtectedIncoming(id: entry.id, revision: entry.revision, deleted: entry.deleted, host: host) }
        let manifestIDs = Set(manifest.entries.map(\.id))
        // Absence also carries meaning: a purged cloud row must become eligible to
        // upload again once selection/final AI releases its inbound protection.
        for (id, local) in byID where !manifestIDs.contains(id) && host.cloudProtectsIncoming(id) && local.cloudRevision > 0 {
            deferredIncomingIDs.insert(id)
        }
        try save(host: host) {
            for entry in manifest.entries where !host.cloudProtectsIncoming(entry.id) && !host.isMeetingDeleted(entry.id) {
                seen.insert(entry.id)
                let local = byID[entry.id]
                if let local, local.syncExcluded {
                    if !entry.deleted { self.retainExcludedMeeting(local, remoteRevision: entry.revision, host: host) }
                    continue
                }
                if let local, local.cloudRestoreRequested {
                    local.cloudRevision = max(local.cloudRevision, entry.revision)
                    local.syncFingerprint = nil
                    continue
                }
                if entry.deleted {
                    if let local, local.cloudRevision > 0 || local.syncFingerprint != nil {
                        self.note(.deletedLocally, local.title, "deleted on another device")
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
            for (id, local) in byID where !seen.contains(id) && !host.cloudProtectsIncoming(id) && local.cloudRevision > 0 {
                local.cloudRevision = 0
                local.syncFingerprint = nil
            }
        }
        var inserted: [Meeting] = []
        var updated: [Meeting] = []
        var changed = false
        var index = 0
        // What the other devices hold comes down before anything goes up; say so.
        if !toFetch.isEmpty { phase = .pulling }
        while index < toFetch.count {
            guard stillAllowed else { return }
            let batch = Array(toFetch[index..<min(index + Self.reconcileBatch, toFetch.count)])
            index += batch.count
            let fingerprints = Dictionary(uniqueKeysWithValues: batch.compactMap { id -> (UUID, String)? in
                guard let local = self.localMeeting(id: id, host: host) else { return nil }
                return (id, MeetingSyncDocument.fingerprint(of: local))
            })
            let states = try await transport.fetchMeetings(ids: batch)
            try check(pass)
            if context.hasChanges {
                try deferForLocalEdits()
            }
            if states.contains(where: { state in
                guard !state.deleted, !host.isMeetingDeleted(state.id), !host.cloudProtectsIncoming(state.id),
                      let local = self.localMeeting(id: state.id, host: host) else { return false }
                return fingerprints[state.id] != MeetingSyncDocument.fingerprint(of: local)
            }) {
                pendingScan = true
                needsReconcile = true
                rerunRequested = true
                throw PassDeferral.committedEdits
            }
            for state in states { rememberProtectedIncoming(id: state.id, revision: state.revision, deleted: state.deleted, host: host) }
            try save(host: host) {
                for state in states where !state.deleted && !host.isMeetingDeleted(state.id) && !host.cloudProtectsIncoming(state.id) {
                    guard let document = state.document, let decoded = MeetingSyncDocument.decode(document) else { continue }
                    if let local = self.localMeeting(id: state.id, host: host) {
                        if local.syncExcluded {
                            self.retainExcludedMeeting(local, remoteRevision: state.revision, host: host)
                            continue
                        }
                        if local.cloudRestoreRequested {
                            local.cloudRevision = max(local.cloudRevision, state.revision)
                            local.syncFingerprint = nil
                            continue
                        }
                        let dirty = local.syncFingerprint != MeetingSyncDocument.fingerprint(of: local)
                        if dirty, let localUpdated = local.updatedAt, Self.isNewer(localUpdated, than: decoded.updatedAt) {
                            local.cloudRevision = state.revision
                            self.note(.conflict, local.title, "kept this device's newer edit")
                            continue
                        }
                        self.applyRemote(decoded, revision: state.revision, to: local, host: host, commit: false)
                        self.note(.updated, local.title, "changes from another device")
                        updated.append(local)
                        changed = true
                    } else {
                        let created = MeetingSyncDocument.makeMeeting(decoded, in: context)
                        self.markSynced(created, revision: state.revision)
                        self.note(.downloaded, created.title, "downloaded")
                        inserted.append(created)
                    }
                }
            }
        }
        setCursor(max(manifest.latestSeq, 1), for: pass)
        if !inserted.isEmpty { host.cloudDidInsertMeetings(inserted) }
        if changed { host.cloudDidChangeMeetings(updated.filter { $0.modelContext != nil }) }
    }

    // MARK: Helpers

    /// Call inside the host's commit. Keep the local content and persist the outstanding
    /// removal so a crash, offline retry or delayed pull cannot undo the user's choice.
    private func retainExcludedMeeting(_ meeting: Meeting, remoteRevision: Int, host: CloudSyncHost) {
        guard let context = host.cloudModelContext, remoteRevision > 0 else { return }
        if let pending = host.cloudFetchTombstones()?.first(where: { $0.id == meeting.id }) {
            if pending.cloudRevision < remoteRevision { pending.cloudRevision = remoteRevision }
        } else {
            context.insert(MeetingTombstone(id: meeting.id, cloudRevision: remoteRevision))
        }
        meeting.cloudRevision = 0
        meeting.syncFingerprint = nil
        meeting.syncedAt = nil
        rerunRequested = true
    }

    private func localMeeting(id: UUID, host: CloudSyncHost) -> Meeting? {
        host.cloudFetchMeetings(FetchDescriptor<Meeting>())?.first { $0.id == id }
    }

    private func markSynced(_ meeting: Meeting, revision: Int) {
        let fingerprint = MeetingSyncDocument.fingerprint(of: meeting)
        meeting.cloudRevision = revision
        meeting.syncFingerprint = fingerprint
        meeting.localFingerprint = fingerprint
        meeting.syncedAt = now()
        meeting.syncStateRaw = nil
    }

    @discardableResult
    private func applyRemote(_ decoded: MeetingSyncDocument.Decoded, revision: Int, to meeting: Meeting, host: CloudSyncHost, commit: Bool = true) -> Bool {
        guard let context = host.cloudModelContext else { return false }
        let replaceSegments = meeting.transcriptRevision != decoded.transcriptRevision || meeting.segments.count != decoded.segments.count
        let work = {
            MeetingSyncDocument.apply(decoded, to: meeting, in: context, replaceSegments: replaceSegments)
            self.markSynced(meeting, revision: revision)
        }
        if commit { return host.cloudCommit(work) }
        work()
        return true
    }

    private func save(host: CloudSyncHost, _ mutate: @escaping () -> Void) throws {
        guard host.cloudCommit(mutate) else {
            scanFailed = true
            pendingScan = true
            needsReconcile = true
            throw CloudSyncError.server(code: "local_save_failed", status: 0)
        }
    }

    private func deleteLocal(_ meeting: Meeting, host: CloudSyncHost) throws {
        try save(host: host) { host.cloudRemoveLocally(meeting) }
        host.cloudDidChangeMeetings([])
    }
}
