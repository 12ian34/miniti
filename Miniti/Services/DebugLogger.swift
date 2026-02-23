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

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: Category
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    private let lock = NSLock()
    nonisolated(unsafe) private var buffer: [Entry] = []
    nonisolated(unsafe) private var redactPatterns: [String] = []
    private let maxEntries = 1000

    private init() {}

    /// Register strings (API keys) that should be masked in log output.
    func setRedactPatterns(_ patterns: [String]) {
        lock.lock()
        redactPatterns = patterns.filter { $0.count > 4 }
        lock.unlock()
    }

    /// Thread-safe logging — callable from audio callbacks and any isolation domain.
    nonisolated func log(_ category: Category, _ message: String) {
        let cleaned = redact(message)
        let entry = Entry(timestamp: Date(), category: category, message: cleaned)

        lock.lock()
        buffer.append(entry)
        if buffer.count > maxEntries {
            buffer.removeFirst(buffer.count - maxEntries)
        }
        let snapshot = buffer
        lock.unlock()

        print("[dbg:\(category.rawValue)] \(cleaned)")

        DispatchQueue.main.async { [weak self] in
            self?.entries = snapshot
        }
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

    @MainActor func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
        entries = []
    }

    func exportText() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        lock.lock()
        let snap = buffer
        lock.unlock()
        return snap.map { entry in
            "[\(fmt.string(from: entry.timestamp))] [\(entry.category.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }
}
