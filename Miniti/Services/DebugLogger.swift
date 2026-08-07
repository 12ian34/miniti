import Foundation

/// In-memory ring-buffer logger for diagnostics. Entries are viewable via a hidden
/// debug panel (5-tap on version text in Settings). API keys are automatically redacted.
final class DebugLogger: ObservableObject, @unchecked Sendable {
    static let shared = DebugLogger()

    enum Category: String, CaseIterable {
        case audio
        case deepgram
        case app
    }

    enum Level: String, CaseIterable {
        case routine
        case recovery
        case warning
        case error

        var isImportant: Bool {
            self != .routine
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: Category
        let level: Level
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    struct EntryRing {
        private var storage: [Entry?]
        private var startIndex = 0
        private(set) var count = 0

        init(capacity: Int) {
            storage = Array(repeating: nil, count: max(1, capacity))
        }

        mutating func append(_ entry: Entry) {
            if count < storage.count {
                storage[(startIndex + count) % storage.count] = entry
                count += 1
            } else {
                storage[startIndex] = entry
                startIndex = (startIndex + 1) % storage.count
            }
        }

        mutating func removeAll() {
            for index in storage.indices {
                storage[index] = nil
            }
            startIndex = 0
            count = 0
        }

        func snapshot() -> [Entry] {
            guard count > 0 else { return [] }
            var result: [Entry] = []
            result.reserveCapacity(count)
            for offset in 0..<count {
                if let entry = storage[(startIndex + offset) % storage.count] {
                    result.append(entry)
                }
            }
            return result
        }
    }

    private let lock = NSLock()
    nonisolated(unsafe) private var buffer = EntryRing(capacity: 1000)
    nonisolated(unsafe) private var redactPatterns: [String] = []
    nonisolated(unsafe) private var hasPendingPublish = false

    private init() {}

    /// Register strings (API keys) that should be masked in log output.
    func setRedactPatterns(_ patterns: [String]) {
        lock.lock()
        redactPatterns = patterns.filter { $0.count > 4 }
        lock.unlock()
    }

    /// Thread-safe logging — callable from audio callbacks and any isolation domain.
    /// When `level` is omitted, the message is classified so the debug panel can hide
    /// routine success/setup logs by default while keeping failure/recovery breadcrumbs.
    nonisolated func log(_ category: Category, _ message: String, level: Level? = nil) {
        let cleaned = redact(message)
        let entry = Entry(timestamp: Date(), category: category, level: level ?? Self.classify(cleaned), message: cleaned)

        lock.lock()
        buffer.append(entry)
        let shouldSchedulePublish = !hasPendingPublish
        if shouldSchedulePublish {
            hasPendingPublish = true
        }
        lock.unlock()

        guard shouldSchedulePublish else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let snapshot = self.buffer.snapshot()
            self.hasPendingPublish = false
            self.lock.unlock()
            self.entries = snapshot
        }
    }

    nonisolated static func format(_ entry: Entry) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return "[\(fmt.string(from: entry.timestamp))] [\(entry.level.rawValue)] [\(entry.category.rawValue)] \(entry.message)"
    }

    nonisolated private static func classify(_ message: String) -> Level {
        let lower = message.lowercased()

        let errorTokens = [
            "failed", " fail", "failure", "error", "denied", "invalid",
            "unhealthy", "exhausted", "cannot connect", "can't connect",
            "no output device", "no api key", "not available"
        ]
        if errorTokens.contains(where: { lower.contains($0) }) {
            return .error
        }

        let warningTokens = [
            "warning", "stalled", "starvation", "degraded", "dropping stale",
            "dropped stale", "rejected", "unsupported", "near-silent",
            "near silent", "all buffers are near-silent", "no transcript",
            "zero transcript", "suppressed", "cooldown", "skipped",
            "could not", "stale", "mismatch", "limit"
        ]
        if warningTokens.contains(where: { lower.contains($0) }) {
            return .warning
        }

        let recoveryTokens = [
            "route changed", "device changed", "config changed", "restart",
            "reconnect", "recovery", "retry", "reset", "source tracking",
            "output-change", "silent-stall", "callback-stall", "auto-retry",
            "speaker identity reset"
        ]
        if recoveryTokens.contains(where: { lower.contains($0) }) {
            return .recovery
        }

        if lower.hasPrefix("default input device changed") ||
            lower.hasPrefix("default output device changed") ||
            lower.hasPrefix("audio device list changed") {
            return .recovery
        }

        if lower.hasPrefix("speaker-names applied") {
            return .recovery
        }

        return .routine
    }

    nonisolated private func redact(_ message: String) -> String {
        lock.lock()
        let patterns = redactPatterns
        lock.unlock()

        var result = message
        for p in patterns {
            guard result.contains(p) else { continue }
            let prefix = String(p.prefix(4))
            result = result.replacingOccurrences(of: p, with: "\(prefix)***")
        }
        return result
    }

    func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.entries = []
        }
    }

    func exportText() -> String {
        lock.lock()
        let snap = buffer.snapshot()
        lock.unlock()
        return snap.map(Self.format).joined(separator: "\n")
    }
}
