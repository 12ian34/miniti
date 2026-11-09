import AVFoundation
import Foundation
import Network
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// One watch recording as the phone tracks it, from first file to saved meeting.
struct WatchImportJob: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case receiving
        case queued
        case transcribing
        case waitingForMinutes = "waiting_for_minutes"
        /// Deepgram and OpenAI are not allowed yet: audio and job kept, nothing sent, resumed
        /// once when permission is granted (narrowed R2, 2026-10-27).
        case waitingForPermission = "waiting_for_permission"
        case insights
        case done
        case failed
        /// Removed on the phone. Kept so a resend from the watch is answered and never revived.
        case dismissed
    }

    let id: UUID
    let startedAt: Date
    var language: String
    var status: Status
    var message: String?
    var receivedIndexes: [Int]
    /// Known once the manifest arrives.
    var expectedIndexes: [Int]?
    var durationSeconds: TimeInterval
    var meetingID: UUID?
    var updatedAt: Date
    var attemptCount: Int? = nil
    var nextEligibleAt: Date? = nil
    var serverRetryAfter: Date? = nil
    var lastFailureKind: String? = nil
    var managedOwner: String? = nil
    var managedSessionID: String? = nil
    var reportDurationMinutes: Double? = nil
    var lastManualAttemptAt: Date? = nil
    var quotaSnapshot: Double? = nil
    var settledTranscriptionSessions: [String]? = nil
    /// True once grants use per-response receipts. Missing receipts mean zero consumed.
    var usesTranscriptionReceipts: Bool? = nil

    mutating func deferTransient(now: Date, retryAfter: Date? = nil) {
        let attempt = (attemptCount ?? 0) + 1
        attemptCount = attempt
        serverRetryAfter = retryAfter
        lastFailureKind = "transient"
        updatedAt = now
        if attempt >= 8 {
            status = .failed; nextEligibleAt = nil
            message = "Could not finish importing. Your recording is saved here. Tap Retry to try again."
        } else {
            let delays: [TimeInterval] = [5, 15, 60, 300]
            nextEligibleAt = max(now.addingTimeInterval(delays[min(attempt - 1, 3)]), retryAfter ?? .distantPast)
            status = .queued; message = "Waiting to retry"
        }
    }

    var isComplete: Bool {
        guard let expectedIndexes else { return false }
        return Set(expectedIndexes).isSubset(of: Set(receivedIndexes))
    }

    var isActive: Bool { status != .done && status != .dismissed }
    /// Nothing is in flight, so the person may remove it.
    var isRemovable: Bool { status != .transcribing && status != .insights && isActive }

    var statusText: String {
        switch status {
        case .receiving:
            if let expected = expectedIndexes?.count { return "receiving \(receivedIndexes.count) of \(expected)" }
            return "receiving from watch"
        case .queued: return nextEligibleAt == nil ? "waiting to transcribe" : "waiting to retry"
        case .transcribing: return "transcribing"
        case .waitingForMinutes: return "waiting for minutes"
        case .waitingForPermission: return "waiting for permission"
        case .insights: return "writing the summary"
        case .done: return "ready"
        case .failed: return message ?? "failed"
        case .dismissed: return "removed"
        }
    }
}

/// Turns watch recordings into meetings: durable inbox, one job at a time, Deepgram prerecorded,
/// then the same final-insights path a live meeting takes. Everything is idempotent on the
/// recording id, so a resent file or a relaunch mid-job never duplicates a meeting.
@MainActor
final class WatchImportService: ObservableObject {
    static let shared = WatchImportService(root: WatchImportService.defaultRoot)

    static let sourceIdentifier = "watch"

    @Published private(set) var jobs: [WatchImportJob] = []
    weak var appState: AppState? {
        didSet { observeLanguage() }
    }
    /// Receipts go to the watch through the bridge; tests swap this out.
    var sendReceipt: (WatchReceipt) -> Void = { WatchSessionBridge.shared.send($0) }

    var activeJobs: [WatchImportJob] { jobs.filter(\.isActive) }

    private let root: URL
    private(set) var isRunning = false
    private var languageObserver: Any?
    private var wakeTask: Task<Void, Never>?
    var now: () -> Date = Date.init
    /// Worker seam: tests inject a suspended transport, while scheduling remains real.
    var performJob: ((WatchImportJob) async -> Void)?
    /// Provider boundary for full worker interruption/replay tests.
    var transcriptionUpload: ((URL) async throws -> WatchTranscriptionClient.Result)?
    private var worker: Task<Void, Never>?
    private var workerGeneration = UUID()
    private var runningJobID: UUID?
    private var foreground = AppState.isRunningUnderXCTest || UIApplication.shared.applicationState == .active
    private var networkMonitor: NWPathMonitor?

    func sessionDeactivated() { foreground = false; wakeTask?.cancel(); wakeTask = nil; networkMonitor?.cancel(); networkMonitor = nil }
    static func eligible(_ job: WatchImportJob, now: Date, permitted: Bool, minutesRemaining: Double?) -> Bool {
        guard job.isComplete else { return false }
        switch job.status {
        case .queued: return (job.nextEligibleAt ?? .distantPast) <= now
        case .waitingForPermission: return permitted
        case .waitingForMinutes:
            guard let minutesRemaining, minutesRemaining > 0 else { return false }
            return minutesRemaining > (job.quotaSnapshot ?? 0)
        default: return false
        }
    }

    func deferJob(_ id: UUID, retryAfter: Date? = nil) {
        guard var job = jobs.first(where: { $0.id == id }) else { return }
        job.deferTransient(now: now(), retryAfter: retryAfter)
        guard upsert(job) else { return }
    }

    nonisolated static var defaultRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("WatchInbox", isDirectory: true)
    }

    nonisolated static func inboxDirectory(for id: UUID) -> URL {
        defaultRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        jobs = loadLedger()
    }

    func directory(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    // MARK: - Arrivals

    /// Called by the bridge after a file is safely in the inbox.
    func noteArrival(_ transfer: WatchSegmentTransfer, at url: URL) {
        var job = jobs.first(where: { $0.id == transfer.recordingID }) ?? WatchImportJob(
            id: transfer.recordingID, startedAt: transfer.startedAt, language: transfer.language,
            status: .receiving, message: nil, receivedIndexes: [], expectedIndexes: nil,
            durationSeconds: 0, meetingID: nil, updatedAt: Date()
        )
        if job.status == .done || job.status == .dismissed {
            // The watch resent something already turned into a meeting, or removed here: tell it
            // the recording is finished so it deletes its copy, and drop the file.
            try? FileManager.default.removeItem(at: url)
            sendReceipt(WatchReceipt(recordingID: job.id, receivedIndexes: job.expectedIndexes ?? job.receivedIndexes, status: .ready))
            return
        }
        if transfer.isManifest {
            guard let data = try? Data(contentsOf: url), let manifest = try? Self.decoder.decode(WatchRecordingManifest.self, from: data) else {
                job.status = .failed
                job.message = "The watch sent a recording this version cannot read"
                job.updatedAt = Date()
                guard upsert(job) else { return }
                sendReceipt(WatchReceipt(recordingID: job.id, receivedIndexes: job.receivedIndexes, status: .failed, message: job.message))
                return
            }
            job.expectedIndexes = manifest.segments.map(\.index).sorted()
            job.durationSeconds = manifest.duration
            job.language = manifest.language
        } else if !job.receivedIndexes.contains(transfer.index) {
            job.receivedIndexes.append(transfer.index)
            job.receivedIndexes.sort()
        }
        // A job still collecting files moves on when the last file lands; anything further
        // along (queued, failed, waiting) keeps its state.
        if job.status == .receiving {
            job.status = job.isComplete ? .queued : .receiving
        }
        job.updatedAt = Date()
        guard upsert(job) else { return }
        // A job that already failed or is waiting keeps showing that on the watch; a resent
        // manifest must not turn "failed" into "on iPhone".
        let receiptStatus: WatchReceipt.Status
        switch job.status {
        case .failed: receiptStatus = .failed
        case .waitingForMinutes: receiptStatus = .waitingForMinutes
        case .transcribing, .insights: receiptStatus = .transcribing
        default: receiptStatus = .received
        }
        sendReceipt(WatchReceipt(recordingID: job.id, receivedIndexes: job.receivedIndexes, status: receiptStatus, message: job.message))
        kick()
    }

    func sessionActivated() {
        foreground = true
        settleDismissedReceipts()
        if networkMonitor == nil && !AppState.isRunningUnderXCTest {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in self?.kick() }
            }
            networkMonitor = monitor
            monitor.start(queue: DispatchQueue(label: "miniti.watch-import.network"))
        }
        if let appState { WatchSessionBridge.shared.publishContext(language: appState.meetingLanguage) }
        kick()
    }

    func retry(_ id: UUID) {
        guard var job = jobs.first(where: { $0.id == id }) else { return }
        guard job.status == .failed || job.status == .waitingForMinutes || job.status == .waitingForPermission else { return }
        guard now().timeIntervalSince(job.lastManualAttemptAt ?? .distantPast) >= 5 else { return }
        job.lastManualAttemptAt = now()
        job.attemptCount = 0
        job.nextEligibleAt = nil
        job.status = job.isComplete ? .queued : .receiving
        job.message = nil
        job.updatedAt = now()
        guard upsert(job) else { return }
        kick()
    }

    /// Removes a job the person gave up on. The entry stays as `dismissed` so a resend from the
    /// watch is answered with `ready` (the watch then deletes its copy) instead of reviving the job.
    func dismiss(_ id: UUID) {
        guard var job = jobs.first(where: { $0.id == id }), job.isRemovable, runningJobID != id else { return }
        job.status = .dismissed
        job.message = nil
        job.updatedAt = Date()
        guard upsert(job) else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory(for: id), includingPropertiesForKeys: nil)) ?? []
        let hasReceipts = files.contains { $0.lastPathComponent.hasPrefix("paid-transcription-") }
        if hasReceipts || job.managedSessionID != nil {
            // The person can discard audio without discarding already incurred usage.
            for file in files where file.pathExtension != "json" { try? FileManager.default.removeItem(at: file) }
            settleDismissedReceipts()
        } else { try? FileManager.default.removeItem(at: directory(for: id)) }
        sendReceipt(WatchReceipt(recordingID: id, receivedIndexes: job.expectedIndexes ?? job.receivedIndexes, status: .ready))
    }

    private var dismissedSettlementTask: Task<Void, Never>?
    private var dismissedSettlementRerun = false
    private var unreadableDismissedReceipts: Set<UUID> = []

    private func settleDismissedReceipts() {
        guard let appState else { return }
        guard dismissedSettlementTask == nil else { dismissedSettlementRerun = true; return }
        dismissedSettlementRerun = false
        dismissedSettlementTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.dismissedSettlementTask = nil
                if self.dismissedSettlementRerun { self.settleDismissedReceipts() }
            }
            for initial in self.jobs where initial.status == .dismissed {
                let directory = self.directory(for: initial.id)
                guard FileManager.default.fileExists(atPath: directory.path) else { continue }
                // Dismiss already authorizes removal. Retain unpaid checkpoints only
                // within the same 30-day delivery window as the managed usage journal.
                if now().timeIntervalSince(initial.updatedAt) >= 30 * 86_400 {
                    try? FileManager.default.removeItem(at: directory)
                    unreadableDismissedReceipts.remove(initial.id)
                    continue
                }
                guard !unreadableDismissedReceipts.contains(initial.id) else { continue }
                guard var receipts = try? WatchTranscriptionClient.transcriptionReceipts(in: directory) else {
                    unreadableDismissedReceipts.insert(initial.id)
                    continue
                }
                if let session = initial.managedSessionID, let owner = initial.managedOwner, receipts[session] == nil {
                    let legacy = (try? Data(contentsOf: directory.appendingPathComponent("transcription.json")))
                        .flatMap { try? JSONDecoder().decode(WatchTranscriptionClient.Result.self, from: $0) }
                    receipts[session] = (owner, (initial.usesTranscriptionReceipts == true || WatchTranscriptionClient.hasTranscriptionCheckpoints(in: directory)) ? 0 : (initial.reportDurationMinutes ?? legacy.map { $0.duration / 60 } ?? 0))
                }
                var job = initial
                var settled = Set(job.settledTranscriptionSessions ?? [])
                var saved = true
                for (session, receipt) in receipts where !settled.contains(session) {
                    guard await appState.reportPrerecordedSessionEnd(sessionId: session, durationMinutes: receipt.minutes, accountID: receipt.owner) else { saved = false; break }
                    settled.insert(session); job.settledTranscriptionSessions = Array(settled)
                    guard self.upsert(job) else { saved = false; break }
                }
                if saved { try? FileManager.default.removeItem(at: directory) }
            }
        }
    }

    private var appStateAccountTransition: Bool { appState?.accountTransitionInFlight == true }

    /// Connectivity activation is independent of the phone scene lifecycle.
    func connectionActivated() { kick() }

    /// Starts the next runnable job if none is running.
    func kick() {
        // Background transfers are acknowledged and kept on disk. Begin provider work
        // only while the phone is active; a long upload cannot fit a background lease.
        guard !isRunning, foreground, !appStateAccountTransition else { return }
        guard let appState, appState.modelContext != nil else { return }
        wakeTask?.cancel(); wakeTask = nil
        let current = now()
        let next = jobs.filter { Self.eligible($0, now: current, permitted: appState.aiContentPermitted,
            minutesRemaining: appState.usageInfo?.minutesRemaining) }.min { $0.startedAt < $1.startedAt }
        guard let next else {
            if let date = jobs.filter({ $0.status == .queued && $0.isComplete }).compactMap(\.nextEligibleAt).min() {
                let delay = max(5, date.timeIntervalSince(current))
                wakeTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    self?.wakeTask = nil
                    self?.kick()
                }
            }
            return
        }
        isRunning = true
        workerGeneration = UUID()
        runningJobID = next.id
        worker = Task { @MainActor in
            if let performJob { await performJob(next) } else { await run(next) }
            isRunning = false
            runningJobID = nil
            worker = nil
            kick()
        }
    }

    // MARK: - The job

    private func run(_ initial: WatchImportJob) async {
        guard let appState else { return }
        var job = initial
        let generation = workerGeneration
        let lease = BackgroundLease.begin(name: "Watch recording import") { [weak self] in
            guard let self, self.workerGeneration == generation else { return }
            self.worker?.cancel()
        }
        defer { lease.end() }

        func fail(_ message: String) {
            job.status = .failed
            job.message = message
            job.updatedAt = Date()
            guard upsert(job) else { return }
            sendReceipt(WatchReceipt(recordingID: job.id, receivedIndexes: job.receivedIndexes, status: .failed, message: message))
            DebugLogger.shared.log(.app, "Watch import failed \(job.id): \(message)")
            appState.enqueueDiagnosticEvent("watch_import_failed", category: .app, level: .warning)
        }

        /// Nothing was consumed yet and the cause is temporary (network, suspension): back to the
        /// queue, picked up on the next activation without a tap.
        func retryLater(_ reason: String, retryAfter: Date? = nil) {
            if Task.isCancelled {
                job.status = .queued
                job.nextEligibleAt = nil
                job.message = "Open miniti to finish importing. Your recording is saved here."
                job.updatedAt = now()
            } else {
                job.deferTransient(now: now(), retryAfter: retryAfter)
            }
            guard upsert(job) else { return }
            DebugLogger.shared.log(.app, "Watch import deferred \(job.id): \(reason)")
        }

        /// Permission for Deepgram and OpenAI is absent: keep the audio and the job, send
        /// nothing, and let the worker pick it up once when the answer is yes. Not a failure,
        /// not done, not retried on its own.
        func waitForPermission(_ stage: String) {
            job.status = .waitingForPermission
            job.message = "Needs permission for Deepgram and OpenAI. Allow it in Settings, Privacy."
            job.updatedAt = Date()
            guard upsert(job) else { return }
            DebugLogger.shared.log(.app, "Watch import waiting for permission \(job.id) at \(stage)")
        }

        func settleTranscription() async -> Bool {
            let receipts: [String: (owner: String, minutes: Double)]
            do { receipts = try WatchTranscriptionClient.transcriptionReceipts(in: directory(for: job.id)) }
            catch { fail("The saved transcription could not be read. Your audio is still here."); return false }
            var pending = receipts
            if let session = job.managedSessionID, let owner = job.managedOwner, pending[session] == nil {
                let legacyURL = directory(for: job.id).appendingPathComponent("transcription.json")
                let legacyResult = (try? Data(contentsOf: legacyURL)).flatMap { try? JSONDecoder().decode(WatchTranscriptionClient.Result.self, from: $0) }
                pending[session] = (owner, (job.usesTranscriptionReceipts == true || WatchTranscriptionClient.hasTranscriptionCheckpoints(in: directory(for: job.id))) ? 0 : (job.reportDurationMinutes ?? legacyResult.map { $0.duration / 60 } ?? 0))
            }
            var settled = Set(job.settledTranscriptionSessions ?? [])
            for (session, receipt) in pending where !settled.contains(session) {
                guard await appState.reportPrerecordedSessionEnd(sessionId: session, durationMinutes: receipt.minutes, accountID: receipt.owner) else {
                    retryLater("usage checkpoint unavailable"); return false
                }
                settled.insert(session)
                job.settledTranscriptionSessions = Array(settled)
                guard upsert(job) else { return false }
            }
            job.managedSessionID = nil; job.reportDurationMinutes = nil
            return upsert(job)
        }

        guard await settleTranscription() else { return }
        if let owner = job.managedOwner, appState.clientAuthManager.status.accountID != owner {
            fail("Sign in to the account that started this import, then tap Retry. Your recording is saved here.")
            return
        }

        var skipsInsights: Bool { appState.privateModeEnabled || (appState.appMode == .byok && appState.openaiApiKey.isEmpty) }

        // Already a meeting? (A crash between save and ledger write, or during insights.)
        if let existing = existingMeeting(for: job.id, in: appState) {
            job.meetingID = existing.id
            let hasInsights = !(existing.summaryText ?? "").isEmpty
            let settled = existing.webhookCompletion.map { $0.phase != .processing } ?? false
            if !skipsInsights, !hasInsights, !settled, !existing.fullTranscript.isEmpty {
                guard appState.aiContentPermitted else {
                    waitForPermission("insights")
                    return
                }
                job.status = .insights
                guard upsert(job) else { return }
                await appState.generateFinalInsightsAndSave(
                    for: existing, transcript: existing.fullTranscript, language: job.language,
                    existingTitle: "", includeSales: false
                )
            }
            if Task.isCancelled { retryLater("summary suspended"); return }
            job.message = !skipsInsights && (existing.summaryText ?? "").isEmpty && !existing.fullTranscript.isEmpty
                ? "Recording saved. Summary unavailable. You can generate it from History." : nil
            job.status = .done
            job.updatedAt = Date()
            guard upsert(job) else { return }
            finishFiles(job)
            return
        }
        guard appState.privateModeEnabled == false else {
            fail("Private mode is on. Watch recordings are transcribed by Deepgram, so turn it off to continue.")
            return
        }
        // Checked at dispatch, and again before the upload and before the insights: a request
        // already in flight may finish, the next one needs the answer.
        guard appState.aiContentPermitted else {
            waitForPermission("dispatch")
            return
        }

        // 1. Every file present.
        let parts = (job.expectedIndexes ?? job.receivedIndexes).map {
            directory(for: job.id).appendingPathComponent(String(format: "segment-%03d.m4a", $0))
        }
        guard parts.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            job.status = .receiving
            job.message = nil
            guard upsert(job) else { return }
            return
        }
        job.status = .transcribing
        job.message = nil
        guard upsert(job) else { return }
        sendReceipt(WatchReceipt(recordingID: job.id, receivedIndexes: job.receivedIndexes, status: .transcribing))

        var sessionID: String? = job.managedSessionID
        let sessionOwner = job.managedOwner ?? appState.clientAuthManager.status.accountID
        let joined = directory(for: job.id).appendingPathComponent("joined.m4a")
        let resultURL = directory(for: job.id).appendingPathComponent("transcription.json")
        let completeParts: WatchTranscriptionClient.Result?
        do {
            let manifestData = try Data(contentsOf: directory(for: job.id).appendingPathComponent("manifest.json"))
            let manifest = try Self.decoder.decode(WatchRecordingManifest.self, from: manifestData)
            let offsets = manifest.segments.sorted { $0.index < $1.index }.map(\.offset)
            completeParts = try WatchTranscriptionClient.cachedParts(in: directory(for: job.id), offsets: offsets)
        } catch { fail("The saved transcription could not be read. Your audio is still here."); return }
        let result: WatchTranscriptionClient.Result
        if let data = try? Data(contentsOf: resultURL), let cached = try? JSONDecoder().decode(WatchTranscriptionClient.Result.self, from: data) {
            result = cached
        } else if let data = try? Data(contentsOf: directory(for: job.id).appendingPathComponent("paid-transcription-full.json")),
                  let cached = try? JSONDecoder().decode(WatchTranscriptionClient.Checkpoint.self, from: data) {
            // A complete paid result survives a failed final-cache write. Do not request
            // another grant or fall back to part uploads if the joined audio is damaged.
            result = cached.result
        } else if let completeParts {
            result = completeParts
        } else {
        // 2. Credentials first: a refused grant (limit reached) costs nothing.
        let credential: WatchTranscriptionClient.Credential
        if appState.appMode == .managed {
            guard let api = appState.minitiAPIService else {
                fail("Not signed in")
                return
            }
            do {
                let grant = try await api.requestPrerecordedSession(
                    deviceId: DeviceIdentifier.getOrCreateDeviceId(),
                    language: job.language, recordingID: job.id.uuidString
                )
                credential = .init(scheme: "Bearer", token: grant.accessToken)
                guard appState.clientAuthManager.status.accountID == sessionOwner else {
                    fail("Your account changed. Tap Retry after signing in to the original account.")
                    return
                }
                sessionID = grant.sessionId
                job.managedOwner = sessionOwner
                job.managedSessionID = grant.sessionId
                job.usesTranscriptionReceipts = true
                guard upsert(job) else { return }
            } catch MinitiAPIService.ServiceError.limitReached {
                job.status = .waitingForMinutes
                job.quotaSnapshot = appState.usageInfo?.minutesRemaining ?? 0
                job.message = "Monthly minutes are used up"
                job.updatedAt = Date()
                guard upsert(job) else { return }
                sendReceipt(WatchReceipt(recordingID: job.id, receivedIndexes: job.receivedIndexes, status: .waitingForMinutes))
                return
            } catch is CancellationError {
                retryLater("grant suspended")
                return
            } catch let error as MinitiAPIService.TransientSessionError {
                retryLater("grant busy", retryAfter: error.retryAfter)
                return
            } catch let error as URLError {
                retryLater("grant: \(error.localizedDescription)")
                return
            } catch MinitiAPIService.ServiceError.networkError(let underlying) {
                retryLater("grant: \(underlying.localizedDescription)")
                return
            } catch {
                fail(error.localizedDescription)
                return
            }
        } else {
            let key = appState.deepgramApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                fail("Add a Deepgram key in Settings")
                return
            }
            credential = .init(scheme: "Token", token: key)
        }

        // 3. One file. Reused when a previous attempt already made it. If joining fails, the
        // parts are transcribed one by one instead (speaker numbers may restart per part).
        var transcribeSeparately = ((try? FileManager.default.contentsOfDirectory(atPath: directory(for: job.id).path)) ?? [])
            .contains { $0.hasPrefix("paid-transcription-part-") }
        do {
            let reusable = try await WatchTranscriptionClient.canReuseJoinedAudio(joined, parts: parts)
            if !reusable && !transcribeSeparately {
                try await WatchTranscriptionClient.stitch(parts, into: joined)
            }
        } catch {
            if Task.isCancelled {
                guard await settleTranscription() else { return }
                retryLater("audio preparation suspended"); return
            }
            transcribeSeparately = true
            DebugLogger.shared.log(.app, "Watch import: joining failed (\(error.localizedDescription)), transcribing \(parts.count) parts separately")
            appState.enqueueDiagnosticEvent("watch_import_join_failed", category: .app, level: .warning)
        }
        if Task.isCancelled {
            guard await settleTranscription() else { return }
            retryLater("audio preparation suspended"); return
        }

        // Permission withdrawn while the grant or the file was being prepared: no upload.
        guard sessionOwner == appState.clientAuthManager.status.accountID else {
            _ = await settleTranscription()
            fail("Sign in to the account that started this import, then tap Retry. Your recording is saved here.")
            return
        }
        guard appState.aiContentPermitted else {
            guard await settleTranscription() else { return }
            waitForPermission("upload")
            return
        }

        // 4. Transcribe. A dropped connection (or the app being suspended mid-upload) is not a
        // failure of the recording: it goes back to the queue.
        do {
            if transcribeSeparately {
                var running: TimeInterval = 0
                var partList: [(url: URL, offset: TimeInterval)] = []
                for url in parts {
                    partList.append((url, running))
                    let duration = try await AVURLAsset(url: url).load(.duration).seconds
                    guard duration.isFinite, duration > 0 else { throw WatchTranscriptionClient.Failure.unreadable }
                    running += duration
                }
                result = try await WatchTranscriptionClient.transcribeParts(partList, language: job.language, credential: credential, mayContinue: { appState.aiContentPermitted && sessionOwner == appState.clientAuthManager.status.accountID },
                    cacheDirectory: directory(for: job.id), managedSessionID: sessionID, managedOwner: sessionOwner, upload: transcriptionUpload)
            } else {
                result = try await WatchTranscriptionClient.transcribeCached(fileURL: joined,
                    cacheURL: directory(for: job.id).appendingPathComponent("paid-transcription-full.json"),
                    language: job.language, credential: credential, managedSessionID: sessionID, managedOwner: sessionOwner, upload: transcriptionUpload)
            }
        } catch is CancellationError {
            guard await settleTranscription() else { return }
            retryLater("upload suspended")
            return
        } catch WatchTranscriptionClient.Failure.throttled(let date) {
            guard await settleTranscription() else { return }
            retryLater("upload busy", retryAfter: date)
            return
        } catch WatchTranscriptionClient.Failure.http(let code, _) where code >= 500 {
            guard await settleTranscription() else { return }
            retryLater("upload unavailable")
            return
        } catch WatchTranscriptionClient.Failure.permissionWithdrawn {
            guard await settleTranscription() else { return }
            if sessionOwner != appState.clientAuthManager.status.accountID {
                fail("Sign in to the account that started this import, then tap Retry. Your recording is saved here.")
            } else { waitForPermission("upload parts") }
            return
        } catch let error as URLError {
            guard await settleTranscription() else { return }
            retryLater("upload: \(error.localizedDescription)")
            return
        } catch {
            guard await settleTranscription() else { return }
            fail(error.localizedDescription)
            return
        }

            do { try JSONEncoder().encode(result).write(to: resultURL, options: .atomic) }
            catch { fail("The transcription could not be saved. Your recording is still here."); return }
        }

        guard await settleTranscription() else { return }
        guard !result.segments.isEmpty else { fail("No speech was found in the recording"); return }
        if Task.isCancelled { retryLater("transcription suspended"); return }
        job.attemptCount = 0; job.nextEligibleAt = nil; job.lastFailureKind = nil
        guard upsert(job) else { return }

        // 5. Save the meeting. Paid results and their usage receipts are already durable,
        // so retrying a failed meeting save does not upload the audio again.
        guard let context = appState.modelContext else {
            fail("Storage unavailable")
            return
        }
        // Local speaker labels and remembered voices, when the on-device diarizer is on.
        let labels = await WatchVoiceDiarization.relabel(fileURL: joined, result: result, appState: appState)
        if Task.isCancelled { retryLater("speaker processing suspended"); return }
        let meeting = Self.makeMeeting(job: job, result: result, labels: labels)
        job.meetingID = meeting.id
        guard upsert(job) else { return }
        let saved = appState.commit(.watchImport, in: context, mutate: { context.insert(meeting) })
        guard saved else {
            fail("The meeting could not be saved")
            return
        }
        NotificationCenter.default.post(name: .minitiMeetingsImported, object: nil)
        job.meetingID = meeting.id
        job.durationSeconds = result.duration
        job.status = .insights
        guard upsert(job) else { return }
        // 6. Insights, through the same path a live meeting takes at the end. Withdrawn
        // meanwhile: the meeting is saved and the job waits; the resume generates them.
        guard appState.aiContentPermitted else {
            waitForPermission("insights")
            return
        }
        await appState.generateFinalInsightsAndSave(
            for: meeting, transcript: meeting.fullTranscript, language: job.language,
            existingTitle: "", includeSales: false
        )
        if Task.isCancelled { retryLater("summary suspended"); return }
        job.status = .done
        job.message = !skipsInsights && !meeting.fullTranscript.isEmpty && (meeting.summaryText ?? "").isEmpty
            ? "Recording saved. Summary unavailable. You can generate it from History." : nil
        job.updatedAt = Date()
        guard upsert(job) else { return }
        finishFiles(job)
        DebugLogger.shared.log(.app, "Watch import done \(job.id): \(Int(result.duration))s, \(result.segments.count) segments")
    }

    static func makeMeeting(job: WatchImportJob, result: WatchTranscriptionClient.Result, labels: WatchVoiceDiarization.Outcome? = nil) -> Meeting {
        let segments = (labels?.segments ?? result.segments).map {
            TranscriptSegment(text: $0.text, speaker: $0.speaker, timestamp: $0.timestamp, isFinal: true, confidence: $0.confidence)
        }
        let end = job.startedAt.addingTimeInterval(max(result.duration, job.durationSeconds))
        let meeting = Meeting(title: "Watch recording", startTime: job.startedAt, endTime: end, segments: segments)
        meeting.language = job.language
        meeting.externalSource = sourceIdentifier
        meeting.externalID = job.id.uuidString
        meeting.importedAt = Date()
        meeting.recordedOnRaw = RecordingDevice.watch.rawValue
        if let labels {
            meeting.speakerNames = labels.speakerNames
            meeting.speakerEmails = labels.speakerEmails
            meeting.selfSpeakerIDs = labels.selfSpeakerIDs
        }
        return meeting
    }

    private func existingMeeting(for id: UUID, in appState: AppState) -> Meeting? {
        guard let context = appState.modelContext else { return nil }
        // No `#Predicate`: it trips Swift 6's KeyPath sendability check (see CloudSyncEngine).
        // Runs once per job, and the ledger carries the meeting id after a save, so this is the
        // slow path only for a replay after a crash.
        if let meetingID = jobs.first(where: { $0.id == id })?.meetingID,
           let match = (try? context.fetch(FetchDescriptor<Meeting>()))?.first(where: { $0.id == meetingID }) {
            return match
        }
        let externalID = id.uuidString
        return (try? context.fetch(FetchDescriptor<Meeting>()))?.first { $0.externalSource == Self.sourceIdentifier && $0.externalID == externalID }
    }

    private func finishFiles(_ job: WatchImportJob) {
        sendReceipt(WatchReceipt(recordingID: job.id, receivedIndexes: job.expectedIndexes ?? job.receivedIndexes, status: .ready))
        try? FileManager.default.removeItem(at: directory(for: job.id))
        // Finished rows drop off History after a day; the ledger stays small.
        let cutoff = Date().addingTimeInterval(-86_400)
        jobs.removeAll { ($0.status == .done || $0.status == .dismissed) && $0.updatedAt < cutoff && !FileManager.default.fileExists(atPath: directory(for: $0.id).path) }
        saveLedger()
    }

    // MARK: - Ledger

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private var ledgerURL: URL { root.appendingPathComponent("ledger.json") }

    private func loadLedger() -> [WatchImportJob] {
        guard let data = try? Data(contentsOf: ledgerURL) else { return [] }
        var loaded = (try? Self.decoder.decode([WatchImportJob].self, from: data)) ?? []
        // A job that was mid-flight when the app died goes back to the queue.
        for i in loaded.indices {
            if loaded[i].status == .transcribing || loaded[i].status == .insights { loaded[i].status = .queued }
            if let date = loaded[i].nextEligibleAt {
                loaded[i].nextEligibleAt = max(Date().addingTimeInterval(5), min(date, max(Date().addingTimeInterval(300), loaded[i].serverRetryAfter ?? .distantPast)))
            }
        }
        return loaded
    }

    var ledgerWriter: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }

    @discardableResult
    private func saveLedger() -> Bool {
        do {
            try ledgerWriter(Self.encoder.encode(jobs), ledgerURL)
            return true
        } catch { return false }
    }

    @discardableResult
    private func upsert(_ job: WatchImportJob) -> Bool {
        if let i = jobs.firstIndex(where: { $0.id == job.id }) {
            guard jobs[i].status != .dismissed || job.status == .dismissed else { return false }
            jobs[i] = job
        } else {
            jobs.append(job)
            jobs.sort { $0.startedAt > $1.startedAt }
        }
        guard saveLedger() else {
            // Keep the last durable checkpoint on disk and all audio. Suppress this
            // process's worker until the person retries or relaunches.
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[index].status = .failed
                jobs[index].message = "The import could not be saved. Your recording is still here. Free some storage, then tap Retry."
            }
            return false
        }
        return true
    }

    private func observeLanguage() {
        guard let appState else { return }
        languageObserver = appState.$meetingLanguage.sink { language in
            WatchSessionBridge.shared.publishContext(language: language)
        }
    }
}

/// Asks iOS for the short background allowance (about 30 s) when the app leaves the foreground
/// mid-job. Expiration cancels the worker and requeues it without consuming a retry attempt.
/// New provider work starts only while the scene is active.
@MainActor
private final class BackgroundLease {
    #if canImport(UIKit)
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    static func begin(name: String, onExpiration: @escaping @MainActor () -> Void) -> BackgroundLease {
        let lease = BackgroundLease()
        #if canImport(UIKit)
        lease.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak lease] in
            Task { @MainActor in onExpiration(); lease?.end() }
        }
        #endif
        return lease
    }

    func end() {
        #if canImport(UIKit)
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
        #endif
    }
}
