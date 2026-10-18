import Foundation
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
        case .queued: return "waiting to transcribe"
        case .transcribing: return "transcribing"
        case .waitingForMinutes: return "waiting for minutes"
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
    private var isRunning = false
    private var languageObserver: Any?

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
                upsert(job)
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
        upsert(job)
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
        if let appState { WatchSessionBridge.shared.publishContext(language: appState.meetingLanguage) }
        kick()
    }

    func retry(_ id: UUID) {
        guard var job = jobs.first(where: { $0.id == id }) else { return }
        guard job.status == .failed || job.status == .waitingForMinutes else { return }
        job.status = job.isComplete ? .queued : .receiving
        job.message = nil
        job.updatedAt = Date()
        upsert(job)
        kick()
    }

    /// Removes a job the person gave up on. The entry stays as `dismissed` so a resend from the
    /// watch is answered with `ready` (the watch then deletes its copy) instead of reviving the job.
    func dismiss(_ id: UUID) {
        guard var job = jobs.first(where: { $0.id == id }), job.isRemovable else { return }
        job.status = .dismissed
        job.message = nil
        job.updatedAt = Date()
        upsert(job)
        try? FileManager.default.removeItem(at: directory(for: id))
        sendReceipt(WatchReceipt(recordingID: id, receivedIndexes: job.expectedIndexes ?? job.receivedIndexes, status: .ready))
    }

    /// Starts the next runnable job if none is running.
    func kick() {
        guard !isRunning else { return }
        guard let appState, appState.modelContext != nil else { return }
        guard let next = jobs.first(where: { $0.status == .queued || $0.status == .waitingForMinutes }) else { return }
        isRunning = true
        Task { @MainActor in
            await run(next)
            isRunning = false
            kick()
        }
    }

    // MARK: - The job

    private func run(_ initial: WatchImportJob) async {
        guard let appState else { return }
        var job = initial
        let lease = BackgroundLease.begin(name: "Watch recording import")
        defer { lease.end() }

        func fail(_ message: String) {
            job.status = .failed
            job.message = message
            job.updatedAt = Date()
            upsert(job)
            sendReceipt(WatchReceipt(recordingID: job.id, receivedIndexes: job.receivedIndexes, status: .failed, message: message))
            DebugLogger.shared.log(.app, "Watch import failed \(job.id): \(message)")
        }

        /// Nothing was consumed yet and the cause is temporary (network, suspension): back to the
        /// queue, picked up on the next activation without a tap.
        func retryLater(_ reason: String) {
            job.status = .queued
            job.message = nil
            job.updatedAt = Date()
            upsert(job)
            DebugLogger.shared.log(.app, "Watch import deferred \(job.id): \(reason)")
        }

        // Already a meeting? (A crash between save and ledger write, or during insights.)
        if let existing = existingMeeting(for: job.id, in: appState) {
            job.meetingID = existing.id
            let hasInsights = !(existing.summaryText ?? "").isEmpty
            if !hasInsights, !existing.fullTranscript.isEmpty {
                job.status = .insights
                upsert(job)
                await appState.generateFinalInsightsAndSave(
                    for: existing, transcript: existing.fullTranscript, language: job.language,
                    existingTitle: "", includeSales: false
                )
            }
            job.status = .done
            job.updatedAt = Date()
            upsert(job)
            finishFiles(job)
            return
        }
        guard appState.privateModeEnabled == false else {
            fail("Private mode is on. Watch recordings are transcribed by Deepgram, so turn it off to continue.")
            return
        }

        // 1. Every file present.
        let parts = (job.expectedIndexes ?? job.receivedIndexes).map {
            directory(for: job.id).appendingPathComponent(String(format: "segment-%03d.m4a", $0))
        }
        guard parts.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            job.status = .receiving
            job.message = nil
            upsert(job)
            return
        }
        job.status = .transcribing
        job.message = nil
        upsert(job)
        sendReceipt(WatchReceipt(recordingID: job.id, receivedIndexes: job.receivedIndexes, status: .transcribing))

        // 2. Credentials first: a refused grant (limit reached) costs nothing.
        let credential: WatchTranscriptionClient.Credential
        var sessionID: String?
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
                sessionID = grant.sessionId
            } catch MinitiAPIService.ServiceError.limitReached {
                job.status = .waitingForMinutes
                job.message = "Monthly minutes are used up"
                job.updatedAt = Date()
                upsert(job)
                sendReceipt(WatchReceipt(recordingID: job.id, receivedIndexes: job.receivedIndexes, status: .waitingForMinutes))
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

        // 3. One file, joined without re-encoding. Reused when a previous attempt already made it.
        let joined = directory(for: job.id).appendingPathComponent("joined.m4a")
        if !FileManager.default.fileExists(atPath: joined.path) {
            do {
                try await WatchTranscriptionClient.stitch(parts, into: joined)
            } catch {
                if let sessionID { await appState.reportPrerecordedSessionEnd(sessionId: sessionID, durationMinutes: 0) }
                fail("Could not read the audio: \(error.localizedDescription)")
                return
            }
        }

        // 4. Transcribe. A dropped connection (or the app being suspended mid-upload) is not a
        // failure of the recording: it goes back to the queue.
        let result: WatchTranscriptionClient.Result
        do {
            result = try await WatchTranscriptionClient.transcribe(fileURL: joined, language: job.language, credential: credential)
        } catch let error as URLError {
            if let sessionID { await appState.reportPrerecordedSessionEnd(sessionId: sessionID, durationMinutes: 0) }
            retryLater("upload: \(error.localizedDescription)")
            return
        } catch {
            if let sessionID { await appState.reportPrerecordedSessionEnd(sessionId: sessionID, durationMinutes: 0) }
            fail(error.localizedDescription)
            return
        }

        // 5. Save the meeting, then settle the minutes: a crash between the two replays into the
        // "already a meeting" branch above instead of a second Deepgram call.
        guard let context = appState.modelContext else {
            fail("Storage unavailable")
            return
        }
        let meeting = Self.makeMeeting(job: job, result: result)
        job.meetingID = meeting.id
        upsert(job)
        let saved = appState.commit(.watchImport, in: context, mutate: { context.insert(meeting) })
        guard saved else {
            fail("The meeting could not be saved")
            return
        }
        NotificationCenter.default.post(name: .minitiMeetingsImported, object: nil)
        job.meetingID = meeting.id
        job.durationSeconds = result.duration
        job.status = .insights
        upsert(job)
        if let sessionID {
            await appState.reportPrerecordedSessionEnd(sessionId: sessionID, durationMinutes: result.duration / 60)
        }

        // 6. Insights, through the same path a live meeting takes at the end.
        await appState.generateFinalInsightsAndSave(
            for: meeting, transcript: meeting.fullTranscript, language: job.language,
            existingTitle: "", includeSales: false
        )
        job.status = .done
        job.message = nil
        job.updatedAt = Date()
        upsert(job)
        finishFiles(job)
        DebugLogger.shared.log(.app, "Watch import done \(job.id): \(Int(result.duration))s, \(result.segments.count) segments")
    }

    static func makeMeeting(job: WatchImportJob, result: WatchTranscriptionClient.Result) -> Meeting {
        let segments = result.segments.map {
            TranscriptSegment(text: $0.text, speaker: $0.speaker, timestamp: $0.timestamp, isFinal: true, confidence: $0.confidence)
        }
        let end = job.startedAt.addingTimeInterval(max(result.duration, job.durationSeconds))
        let meeting = Meeting(title: "Watch recording", startTime: job.startedAt, endTime: end, segments: segments)
        meeting.language = job.language
        meeting.externalSource = sourceIdentifier
        meeting.externalID = job.id.uuidString
        meeting.importedAt = Date()
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
        jobs.removeAll { ($0.status == .done || $0.status == .dismissed) && $0.updatedAt < cutoff }
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
        for i in loaded.indices where loaded[i].status == .transcribing || loaded[i].status == .insights {
            loaded[i].status = .queued
        }
        return loaded
    }

    private func saveLedger() {
        guard let data = try? Self.encoder.encode(jobs) else { return }
        try? data.write(to: ledgerURL, options: .atomic)
    }

    private func upsert(_ job: WatchImportJob) {
        if let i = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[i] = job
        } else {
            jobs.append(job)
            jobs.sort { $0.startedAt > $1.startedAt }
        }
        saveLedger()
    }

    private func observeLanguage() {
        guard let appState else { return }
        languageObserver = appState.$meetingLanguage.sink { language in
            WatchSessionBridge.shared.publishContext(language: language)
        }
    }
}

/// Asks iOS for the short background allowance (about 30 s) when the app leaves the foreground
/// mid-job. It covers a short recording, not a long upload; anything cut off is requeued by the
/// URLError path above and resumes on the next activation.
@MainActor
private final class BackgroundLease {
    #if canImport(UIKit)
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    static func begin(name: String) -> BackgroundLease {
        let lease = BackgroundLease()
        #if canImport(UIKit)
        lease.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak lease] in
            Task { @MainActor in lease?.end() }
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
