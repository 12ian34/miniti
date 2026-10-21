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

    init(storeURL: URL = DeliveryOutbox.defaultStoreURL(), now: @escaping () -> Date = Date.init) {
        self.storeURL = storeURL
        self.now = now
        load()
    }

    func register(_ kind: Kind, sender: @escaping Sender) {
        senders[kind] = sender
    }

    // MARK: - Enqueue

    /// A webhook for one meeting and event. A pending delivery of the same meeting and event
    /// is superseded in place (one `meeting.updated` per meeting, with the latest body).
    func enqueueWebhook(meetingID: UUID, event: String, body: Data, destination: String) {
        let now = now()
        if let index = items.firstIndex(where: {
            $0.kind == .webhook && $0.meetingID == meetingID && $0.event == event && $0.state == .pending
        }) {
            items[index].body = body
            items[index].destination = destination
            DebugLogger.shared.log(.app, "Outbox: superseded pending webhook \(event) for meeting")
        } else {
            items.append(Item(
                id: UUID(), kind: .webhook, meetingID: meetingID, event: event, createdAt: now,
                attempts: 0, nextAttemptAt: now, state: .pending, lastError: nil,
                body: body, destination: destination
            ))
        }
        persist()
        kick()
    }

    /// An automatic CRM send. The payload is rebuilt from the saved meeting at send time, so
    /// no transcript copy is kept here. One pending item per meeting and CRM.
    func enqueueCRM(_ kind: Kind, meetingID: UUID) {
        precondition(kind != .webhook)
        guard !items.contains(where: { $0.kind == kind && $0.meetingID == meetingID && $0.state == .pending }) else { return }
        let now = now()
        items.append(Item(
            id: UUID(), kind: kind, meetingID: meetingID, event: "auto-sync", createdAt: now,
            attempts: 0, nextAttemptAt: now, state: .pending, lastError: nil,
            body: nil, destination: nil
        ))
        persist()
        kick()
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
        if dead.isEmpty && waiting.isEmpty { return nil }
        var parts: [String] = []
        if !waiting.isEmpty {
            let next = waiting.map(\.nextAttemptAt).min() ?? now()
            let secs = max(0, Int(next.timeIntervalSince(now())))
            let when = secs < 60 ? "shortly" : "in \(Int((Double(secs) / 60).rounded(.up))) min"
            parts.append("\(waiting.count) waiting, next retry \(when)")
        }
        if !dead.isEmpty {
            let reason = dead.last?.lastError ?? "unknown error"
            parts.append("\(dead.count) failed: \(reason)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    func retryNow(_ kind: Kind? = nil) {
        let now = now()
        for index in items.indices where (kind == nil || items[index].kind == kind) {
            if items[index].state == .failed {
                items[index].state = .pending
                items[index].attempts = 0
                items[index].lastError = nil
            }
            if items[index].state == .pending {
                items[index].nextAttemptAt = now
            }
        }
        persist()
        kick()
    }

    func discardFailed(_ kind: Kind? = nil) {
        items.removeAll { ($0.state == .failed || $0.state == .skipped) && (kind == nil || $0.kind == kind) }
        persist()
    }

    /// The meeting is gone: nothing of it may be delivered later.
    func removeAll(forMeeting meetingID: UUID) {
        let before = items.count
        items.removeAll { $0.meetingID == meetingID }
        if items.count != before { persist() }
    }

    // MARK: - Processing

    /// Called on enqueue, on a timer while anything is pending, on app activation and on
    /// network recovery. Safe to call often; one pass runs at a time.
    func kick() {
        Task { await processDue() }
    }

    func processDue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false; scheduleTimer() }

        pruneSkipped()
        let now = now()
        let due = items.filter { $0.state == .pending && $0.nextAttemptAt <= now }
        for item in due {
            guard let sender = senders[item.kind] else { continue }
            let outcome = await sender(item)
            apply(outcome, to: item.id)
        }
        persist()
    }

    private func apply(_ outcome: Outcome, to id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let now = now()
        switch outcome {
        case .delivered:
            DebugLogger.shared.log(.app, "Outbox: delivered \(items[index].kind.label) \(items[index].event) after \(items[index].attempts + 1) attempt(s)")
            items.remove(at: index)
        case .skip(let reason):
            items[index].state = .skipped
            items[index].lastError = reason
            items[index].body = nil
        case .reject(let reason):
            items[index].state = .failed
            items[index].lastError = reason
            items[index].body = nil
            DebugLogger.shared.log(.app, "Outbox: \(items[index].kind.label) rejected: \(reason)", level: .warning)
        case .retry(let reason):
            items[index].attempts += 1
            items[index].lastError = reason
            let tooOld = now.timeIntervalSince(items[index].createdAt) > Self.maxAge
            if let delay = Self.nextDelay(afterAttempts: items[index].attempts), !tooOld {
                items[index].nextAttemptAt = now.addingTimeInterval(delay)
                DebugLogger.shared.log(.app, "Outbox: \(items[index].kind.label) attempt \(items[index].attempts) failed (\(reason)); retry in \(Int(delay))s")
            } else {
                items[index].state = .failed
                items[index].body = nil
                DebugLogger.shared.log(.app, "Outbox: \(items[index].kind.label) gave up after \(items[index].attempts) attempt(s): \(reason)", level: .warning)
            }
        }
    }

    private func pruneSkipped() {
        let cutoff = now().addingTimeInterval(-Self.skippedRetention)
        items.removeAll { $0.state == .skipped && $0.createdAt < cutoff }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard let next = pending.map(\.nextAttemptAt).min() else { return }
        let delay = max(1, next.timeIntervalSince(now()))
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.kick() }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([Item].self, from: data) {
            items = loaded
            if !items.isEmpty {
                DebugLogger.shared.log(.app, "Outbox: restored \(items.count) delivery item(s)")
            }
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            if items.isEmpty {
                try? FileManager.default.removeItem(at: storeURL)
                return
            }
            let data = try encoder.encode(items)
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: storeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            DebugLogger.shared.log(.app, "Outbox: persist FAILED: \(type(of: error))", level: .warning)
        }
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
