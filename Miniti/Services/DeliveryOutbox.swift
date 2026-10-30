import Foundation
import Combine

/// Persisted outbox for outbound deliveries that must not be lost when the network is down:
/// webhooks and automatic Attio / Twenty sends (roadmap P1.2, built 2026-10-05).
///
/// Saving a meeting never waits on a third party: callers enqueue and return. The outbox
/// writes its queue to disk, retries with bounded exponential backoff, gives up after a
/// fixed number of attempts or one day, and exposes its state so Settings can show what is
/// waiting, what failed, and offer retry or discard. Senders are injected so tests drive the
/// whole lifecycle without a network.
@MainActor
final class DeliveryOutbox: ObservableObject {
    enum Kind: String, Codable, CaseIterable {
        case webhook
        case attio
        case twenty

        var label: String {
            switch self {
            case .webhook: return "webhook"
            case .attio: return "Attio"
            case .twenty: return "Twenty"
            }
        }
    }

    enum State: String, Codable {
        /// Waiting for its next attempt.
        case pending
        /// Gave up: attempts exhausted, too old, or the destination rejected it for good.
        case failed
        /// Nothing to send: for CRM, no single matching record. Kept briefly so Settings can
        /// explain, then pruned.
        case skipped
    }

    struct Item: Codable, Identifiable, Equatable {
        let id: UUID
        let kind: Kind
        let meetingID: UUID
        /// Webhook event name, or the CRM reason. Used for coalescing and display.
        let event: String
        let createdAt: Date
        var attempts: Int
        var nextAttemptAt: Date
        var state: State
        /// Short, privacy-safe reason: an HTTP status or an error class, never a URL or body.
        var lastError: String?
        /// Webhook only: the encoded JSON body and the destination. The body carries the
        /// transcript, so it lives only until delivery or terminal failure.
        var body: Data?
        var destination: String?
        /// Optional for decoding pre-3.6 stores. Held rows cannot dispatch until the
        /// meeting-side handoff is durable. An attempted body is immutable across retries.
        var held: Bool? = nil
        var hasBeenAttempted: Bool? = nil
    }

    /// What a sender reports back.
    enum Outcome: Equatable {
        case delivered
        /// Try again later (network error, timeout, 429, 5xx).
        case retry(reason: String)
        /// Never try again (4xx other than 429, malformed destination).
        case reject(reason: String)
        /// Nothing to deliver (CRM: zero or several matches).
        case skip(reason: String)
    }

    typealias Sender = @MainActor (Item) async -> Outcome

    @Published private(set) var items: [Item] = []
    @Published private(set) var persistenceError: String?
    private(set) var hasStorageFailure = false
    private var unreadableStore = false
    var isStoreReadable: Bool { !unreadableStore }
    private var inFlightID: UUID?
    /// Deletion/discard must fence a held sender even if the disk is temporarily unwritable.
    private var invalidatedIDs: Set<UUID> = []
    private let writeStore: ((Data, URL) throws -> Void)?

    private let storeURL: URL
    private let now: () -> Date
    private var senders: [Kind: Sender] = [:]
    private var isProcessing = false
    private var timer: Timer?

    /// Backoff schedule per failed attempt, then terminal.
    nonisolated static let retryDelays: [TimeInterval] = [30, 120, 600, 1800, 7200]
    nonisolated static let maxAge: TimeInterval = 24 * 60 * 60
    nonisolated static let skippedRetention: TimeInterval = 60 * 60

    nonisolated static func nextDelay(afterAttempts attempts: Int) -> TimeInterval? {
        guard attempts >= 1, attempts <= retryDelays.count else { return nil }
        return retryDelays[attempts - 1]
    }

    nonisolated static func defaultStoreURL() -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("deliveries-outbox.json")
    }

    init(storeURL: URL = DeliveryOutbox.defaultStoreURL(), now: @escaping () -> Date = Date.init, writeStore: ((Data, URL) throws -> Void)? = nil) {
        self.storeURL = storeURL
        self.now = now
        self.writeStore = writeStore
        load()
    }

    func register(_ kind: Kind, sender: @escaping Sender) {
        senders[kind] = sender
    }

    // MARK: - Enqueue

    /// New content always gets a new identity. Only the actual in-flight row is kept
    /// alongside its newest successor; a failed old retry cannot overtake new content.
    @discardableResult
    func enqueueWebhook(meetingID: UUID, event: String, body: Data, destination: String, id: UUID = UUID()) -> Bool {
        let accepted = insertWebhook(id: id, meetingID: meetingID, event: event, body: body, destination: destination, held: false)
        if accepted { kick() }
        return accepted
    }

    /// Persist before acknowledging the meeting marker. Repeating the exact handoff is
    /// idempotent; a supplied ID can never acquire a different body.
    @discardableResult
    func stageWebhook(id: UUID, meetingID: UUID, event: String, body: Data, destination: String, createdAt: Date? = nil) -> Bool {
        insertWebhook(id: id, meetingID: meetingID, event: event, body: body, destination: destination, held: true, createdAt: createdAt)
    }

    @discardableResult
    func releaseWebhook(id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id && $0.kind == .webhook }), !invalidatedIDs.contains(id) else { return false }
        if items[index].held != true { return !hasStorageFailure }
        var next = items
        next[index].held = false
        guard commit(next) else { return false }
        kick()
        return true
    }

    /// Retry a temporary disk failure explicitly, including an empty queue. A corrupt
    /// existing file is kept intact and requires recovery rather than an empty overwrite.
    @discardableResult
    func retryStorage() -> Bool {
        commit(items.filter { !invalidatedIDs.contains($0.id) })
    }

    func item(id: UUID) -> Item? { items.first { $0.id == id } }
    var heldWebhooks: [Item] { items.filter { $0.kind == .webhook && $0.held == true } }

    /// R6 resolves this meeting's bodyless failures only after its current-state replacement is durably queued.
    /// Repeated taps with the same replacement identity do not duplicate the delivery.
    @discardableResult
    func replaceFailedWebhook(id: UUID, replacementID: UUID, meetingID: UUID, event: String, body: Data, destination: String) -> Bool {
        if let existing = item(id: replacementID) {
            return existing.meetingID == meetingID && existing.event == event && existing.body == body && existing.destination == destination
        }
        guard let old = item(id: id), old.kind == .webhook, old.state == .failed, old.meetingID == meetingID else { return false }
        let accepted = insertWebhook(id: replacementID, meetingID: meetingID, event: event, body: body, destination: destination, held: false, replacingFailure: id)
        if accepted { kick() }
        return accepted
    }

    private func insertWebhook(id: UUID, meetingID: UUID, event: String, body: Data, destination: String, held: Bool, createdAt: Date? = nil, replacingFailure: UUID? = nil) -> Bool {
        guard !unreadableStore else { return false }
        if let old = item(id: id) {
            return !invalidatedIDs.contains(id) && old.kind == .webhook && old.meetingID == meetingID && old.event == event && old.body == body && old.destination == destination
        }
        let date = createdAt ?? now()
        var next = items.filter { item in
            if replacingFailure != nil && item.kind == .webhook && item.meetingID == meetingID && item.state == .failed { return false }
            return !(item.kind == .webhook && item.meetingID == meetingID && item.event == event && item.state == .pending && item.id != inFlightID)
        }
        next.append(Item(id: id, kind: .webhook, meetingID: meetingID, event: event, createdAt: date,
                         attempts: 0, nextAttemptAt: now(), state: .pending, lastError: nil,
                         body: body, destination: destination, held: held, hasBeenAttempted: false))
        return commit(next)
    }

    /// CRM bodies still rebuild from saved state at dispatch; its retry policy is unchanged.
    @discardableResult
    func enqueueCRM(_ kind: Kind, meetingID: UUID) -> Bool {
        precondition(kind != .webhook)
        guard !items.contains(where: { $0.kind == kind && $0.meetingID == meetingID && $0.state == .pending }) else { return true }
        let date = now()
        var next = items
        next.append(Item(id: UUID(), kind: kind, meetingID: meetingID, event: "auto-sync", createdAt: date,
                         attempts: 0, nextAttemptAt: date, state: .pending, lastError: nil, body: nil, destination: nil))
        guard commit(next) else { return false }
        kick()
        return true
    }

    // MARK: - Queries for the UI

    var pending: [Item] { items.filter { $0.state == .pending } }
    var failed: [Item] { items.filter { $0.state == .failed } }
    func pending(_ kind: Kind) -> [Item] { pending.filter { $0.kind == kind } }
    func failed(_ kind: Kind) -> [Item] { failed.filter { $0.kind == kind } }

    /// Human line for a Settings section: nil when there is nothing to say.
    func statusLine(for kind: Kind) -> String? {
        let waiting = pending(kind)
        let dead = failed(kind)
        if let persistenceError { return persistenceError }
        if dead.isEmpty && waiting.isEmpty { return nil }
        var parts: [String] = []
        if !waiting.isEmpty {
            let ready = waiting.filter { $0.held != true }
            if ready.isEmpty {
                parts.append("\(waiting.count) waiting for saved meeting")
            } else {
                let next = ready.map(\.nextAttemptAt).min() ?? now()
                let secs = max(0, Int(next.timeIntervalSince(now())))
                let when = secs < 60 ? "shortly" : "in \(Int((Double(secs) / 60).rounded(.up))) min"
                parts.append("\(waiting.count) waiting, next retry \(when)")
            }
        }
        if !dead.isEmpty {
            let reason = dead.last?.lastError ?? "unknown error"
            parts.append("\(dead.count) failed: \(reason)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    func retryNow(_ kind: Kind? = nil) {
        var next = items
        let date = now()
        for index in next.indices where (kind == nil || next[index].kind == kind) {
            // A terminal webhook has no body. R6 rebuilds it from current saved data.
            if next[index].state == .failed && next[index].kind != .webhook {
                next[index].state = .pending
                next[index].attempts = 0
                next[index].lastError = nil
            }
            if next[index].state == .pending { next[index].nextAttemptAt = date }
        }
        if commit(next) { kick() }
    }

    func discardFailed(_ kind: Kind? = nil) {
        let removing = items.filter { ($0.state == .failed || $0.state == .skipped) && (kind == nil || $0.kind == kind) }
        invalidatedIDs.formUnion(removing.map(\.id))
        _ = commit(items.filter { !invalidatedIDs.contains($0.id) })
    }

    @discardableResult
    func removeAll(forMeeting meetingID: UUID) -> Bool {
        invalidatedIDs.formUnion(items.filter { $0.meetingID == meetingID }.map(\.id))
        return commit(items.filter { !invalidatedIDs.contains($0.id) })
    }

    /// Cancel an obsolete held handoff without affecting another revision's delivery.
    @discardableResult
    func discard(id: UUID) -> Bool {
        invalidatedIDs.insert(id)
        return commit(items.filter { $0.id != id })
    }

    // MARK: - Processing

    func kick() { Task { await processDue() } }

    func processDue() async {
        guard !isProcessing, !unreadableStore else { return }
        isProcessing = true
        defer { inFlightID = nil; isProcessing = false; scheduleTimer() }

        // Retry a failed persistence operation before allowing another network send.
        let cutoff = now().addingTimeInterval(-Self.skippedRetention)
        let retained = items.filter { !invalidatedIDs.contains($0.id) && !($0.state == .skipped && $0.createdAt < cutoff) }
        if retained != items || hasStorageFailure {
            guard commit(retained) else { return }
        }
        let dueIDs = items.filter { $0.state == .pending && $0.held != true && $0.nextAttemptAt <= now() }.map(\.id)
        for id in dueIDs {
            // An await above can replace/delete another row captured by this pass.
            guard let index = items.firstIndex(where: { $0.id == id }), !invalidatedIDs.contains(id),
                  items[index].state == .pending, items[index].held != true,
                  let sender = senders[items[index].kind] else { continue }
            let item = items[index]
            if item.kind == .webhook && item.event == "meeting.updated" && items.contains(where: {
                $0.kind == .webhook && $0.meetingID == item.meetingID && $0.event == "meeting.saved" && $0.state == .pending
            }) { continue }
            if item.kind == .webhook && now().timeIntervalSince(item.createdAt) >= Self.maxAge {
                guard apply(.reject(reason: "Delivery expired"), to: id) else { return }
                continue
            }
            // Persist the attempted identity before leaving the process. A restart retries
            // this immutable body even if its previous response was lost.
            var attempted = items
            attempted[index].hasBeenAttempted = true
            guard commit(attempted) else { return }
            inFlightID = id
            let outcome = await sender(attempted[index])
            inFlightID = nil
            guard apply(outcome, to: id) else { return }
        }
    }

    @discardableResult
    private func apply(_ outcome: Outcome, to id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), !invalidatedIDs.contains(id) else { return true }
        var next = items
        let item = next[index]
        let successor = item.kind == .webhook && next.contains {
            $0.id != id && $0.kind == .webhook && $0.meetingID == item.meetingID && $0.event == item.event && $0.state == .pending
        }
        switch outcome {
        case .delivered:
            next.remove(at: index)
        case .skip(let reason):
            next[index].state = .skipped; next[index].lastError = reason; next[index].body = nil
        case .reject(let reason):
            next[index].state = .failed; next[index].lastError = reason; next[index].body = nil
        case .retry(let reason):
            if successor {
                next.remove(at: index)
            } else {
                next[index].attempts += 1
                next[index].lastError = reason
                if let delay = Self.nextDelay(afterAttempts: next[index].attempts), now().timeIntervalSince(item.createdAt) < Self.maxAge {
                    next[index].nextAttemptAt = now().addingTimeInterval(delay)
                } else {
                    next[index].state = .failed; next[index].body = nil
                }
            }
        }
        guard commit(next) else { return false }
        switch outcome {
        case .delivered:
            DebugLogger.shared.log(.app, "Outbox: delivered \(item.kind.label) \(item.event) after \(item.attempts + 1) attempt(s)")
        case .retry:
            DebugLogger.shared.log(.app, successor ? "Outbox: superseded old retry" : "Outbox: delivery retry scheduled or exhausted")
        case .reject:
            DebugLogger.shared.log(.app, "Outbox: \(item.kind.label) rejected", level: .warning)
        case .skip:
            break
        }
        return true
    }

    private func scheduleTimer() {
        timer?.invalidate(); timer = nil
        let candidates = pending.filter { item in
            guard item.held != true, !invalidatedIDs.contains(item.id) else { return false }
            return !(item.kind == .webhook && item.event == "meeting.updated" && pending.contains {
                $0.kind == .webhook && $0.meetingID == item.meetingID && $0.event == "meeting.saved"
            })
        }
        guard !unreadableStore, let next = candidates.map(\.nextAttemptAt).min() else { return }
        let delay = hasStorageFailure ? 30 : max(1, next.timeIntervalSince(now()))
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.kick() }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        do {
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([Item].self, from: data)
        } catch {
            unreadableStore = true
            recordStorageFailure()
        }
    }

    /// Disk first, then publish. A failed write cannot report a durable enqueue/settlement.
    private func commit(_ next: [Item]) -> Bool {
        guard !unreadableStore else { return false }
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(next)
            if let writeStore {
                try writeStore(data, storeURL)
            } else if next.isEmpty {
                if FileManager.default.fileExists(atPath: storeURL.path) { try FileManager.default.removeItem(at: storeURL) }
            } else {
                try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: storeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            items = next
            hasStorageFailure = false; persistenceError = nil
            invalidatedIDs = invalidatedIDs.intersection(Set(next.map(\.id)))
            return true
        } catch {
            recordStorageFailure()
            return false
        }
    }

    private func recordStorageFailure() {
        hasStorageFailure = true
        persistenceError = "Could not save deliveries. Try again when storage is available."
        DebugLogger.shared.log(.app, "Outbox: storage unavailable", level: .warning)
    }

    // MARK: - Classification helpers for senders

    /// Map an HTTP status or transport error to an outcome. 2xx delivered, 429 and 5xx
    /// retry, other 4xx reject, no response (URLError) retry.
    nonisolated static func outcome(status: Int?, error: Error?) -> Outcome {
        if let error {
            if let urlError = error as? URLError {
                return .retry(reason: "network error \(urlError.code.rawValue)")
            }
            return .retry(reason: String(describing: type(of: error)))
        }
        guard let status else { return .retry(reason: "no response") }
        switch status {
        case 200..<300: return .delivered
        case 429, 500..<600: return .retry(reason: "HTTP \(status)")
        default: return .reject(reason: "HTTP \(status)")
        }
    }
}
