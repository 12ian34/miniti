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
        DiagnosticTimeline.shared.clear()
        lock.lock()
        buffer.removeAll()
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.entries = []
        }
    }

    func supportSnapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return buffer.snapshot()
    }

    func exportText() -> String {
        lock.lock()
        let snap = buffer.snapshot()
        lock.unlock()
        return snap.map(Self.format).joined(separator: "\n") + "\n\nDiagnostic timeline:\n"
            + DiagnosticTimeline.shared.snapshot().map(\.text).joined(separator: "\n")
    }
}

/// Content-free local breadcrumbs, independent of automatic telemetry consent. Only explicit
/// Help Copy/Send exports these. No network, Keychain queries or recovery decisions live here.
final class DiagnosticTimeline: @unchecked Sendable {
    enum Code: String, Codable, CaseIterable {
        case historyTruncated = "history_truncated", storageUnavailable = "diagnostic_storage_unavailable"
        case keychainRead = "keychain_read", keychainWrite = "keychain_write", keychainFallback = "keychain_fallback"
        case keyLoaded = "key_loaded", cloudPaused = "cloud_paused"
        case credentialLoaded = "credential_loaded", credentialMissing = "credential_missing"
        case credentialUnreadable = "client_auth_credential_unreadable", credentialUndecodable = "client_auth_credential_undecodable"
        case keyUnusable = "client_auth_key_unusable", keyUnavailable = "client_auth_key_unavailable"
        case repairAttempt = "client_auth_repair_attempt", repairOutcome = "client_auth_repair_outcome", keyRepaired = "client_auth_key_repaired"
        case signingRecovered = "signing_recovered", refreshStarted = "refresh_started", refreshSucceeded = "refresh_succeeded", refreshFailed = "refresh_failed"
        case authRefused = "auth_refused", credentialStale = "credential_stale", accountChanged = "account_changed"
        case recordingAttempt = "recording_attempt", recordingReady = "recording_ready", recordingFailed = "recording_failed", recordingFinal = "recording_final"
        case audioReceived = "audio_received", transcriptReceived = "transcript_received", transcriptionConnected = "transcription_connected"
        case captureFailed = "microphone_capture_failed", audioStall = "transcript_starvation_detected"
        case recoveryDegraded = "audio_recovery_degraded", recoveryHealthy = "audio_recovery_healthy"
        case connectionFailed = "deepgram_initial_connection_failed", reconnectExhausted = "deepgram_reconnect_exhausted"
        case cloudStarted = "cloud_started", cloudSucceeded = "cloud_succeeded", cloudFailed = "cloud_failed", cloudSuperseded = "cloud_superseded"
        case cloudUpload = "cloud_upload", cloudRemoval = "cloud_removal", cloudChoice = "cloud_choice"
        case purchaseReturned = "purchase_returned", purchaseChecking = "purchase_checking", purchasePending = "purchase_pending", purchaseReady = "purchase_ready", purchaseFailed = "purchase_failed"

        var category: String {
            switch self {
            case .keychainRead, .keychainWrite, .keychainFallback: return "keychain"
            case .recordingAttempt, .recordingReady, .recordingFailed, .recordingFinal, .audioReceived, .transcriptReceived, .transcriptionConnected, .captureFailed, .audioStall, .recoveryDegraded, .recoveryHealthy, .connectionFailed, .reconnectExhausted: return "audio"
            case .cloudPaused, .cloudStarted, .cloudSucceeded, .cloudFailed, .cloudSuperseded, .cloudUpload, .cloudRemoval, .cloudChoice: return "cloud"
            case .purchaseReturned, .purchaseChecking, .purchasePending, .purchaseReady, .purchaseFailed: return "purchase"
            case .historyTruncated, .storageUnavailable: return "app"
            default: return "auth"
            }
        }
    }

    struct Event: Codable, Equatable {
        let code: Code
        let first: Date
        var last: Date
        var count: Int
        let fields: [String: String]
        var level: String {
            if fields["outcome"] == "failed" || fields["outcome"] == "timeout" || code.rawValue.contains("failed") || code.rawValue.contains("unusable") || code.rawValue.contains("unavailable") || code == .authRefused || code == .credentialUnreadable || code == .credentialUndecodable || code == .reconnectExhausted { return "warning" }
            return "info"
        }
        var text: String {
            "\(ISO8601DateFormatter().string(from: first)) [\(code.category)] \(code.rawValue) "
                + fields.keys.sorted().map { "\($0)=\(fields[$0]!)" }.joined(separator: " ")
                + (count > 1 ? " count=\(count) last=\(ISO8601DateFormatter().string(from: last))" : "")
        }
    }

    static let maxEvents = 300
    static let maxBytes = 96 * 1024
    static let maxAge: TimeInterval = 48 * 3600
    static let shared: DiagnosticTimeline = {
        // Tests must not overwrite or export the user's real diagnostic history.
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
        let url = testing ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Miniti/Diagnostics/timeline.json")
        return DiagnosticTimeline(fileURL: url)
    }()
    private let queue = DispatchQueue(label: "com.miniti.diagnostic-timeline", qos: .utility)
    private let admission = NSLock()
    private var pending = 0
    private var dropped = 0
    private var storageFailed = false
    private var events: [Event] = [] // queue-owned
    private var writeScheduled = false
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        queue.async { [self] in
            if let fileURL,
               let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.maxBytes,
               let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([Event].self, from: data) {
                events = saved.filter { $0.fields == Self.sanitize($0.fields) && $0.count > 0 && $0.count <= 1_000_000 && $0.first <= $0.last }
            }
            prune(now: Date())
            // Also remove expired data from disk after a quiet launch.
            scheduleWrite()
        }
    }

    /// Fixed vocabularies only. Callers may pass existing outcome metadata, never raw messages.
    static func sanitize(_ fields: [String: String]) -> [String: String] {
        let vocabularies: [String: Set<String>] = [
            "phase": ["launch", "load", "sign", "read", "write", "refresh", "restore", "attach", "rotate", "create", "migrate", "sign_out", "delete"],
            "outcome": ["started", "success", "failed", "stale", "missing", "unreadable", "pending", "stopped", "cancelled", "degraded", "timeout", "sign_in", "throttled", "expired", "ready"],
            "item": ["credential", "device_id", "other"], "store": ["data_protection", "login"],
            "key_kind": ["enclave", "software"], "recovery": ["yes", "no"], "via": ["email", "recovery_key"],
            "route": ["local", "managed", "byok"], "reason": ["manual", "rule", "private_mode", "network", "auth", "quota", "rate_limited", "server", "timeout", "unknown", "off", "not_managed", "not_enrolled", "not_pro", "not_available", "device_removed", "cursor_expired"],
            "error_domain": ["NSOSStatusErrorDomain", "NSCocoaErrorDomain", "NSURLErrorDomain", "CryptoTokenKit", "TKErrorDomain", "other"],
            "server_code": ["installation_revoked", "token_expired", "device_already_enrolled", "invalid_key", "rate_limited", "provider_config", "provider_unavailable", "not_enrolled", "unknown", "invalid_proof", "device_cap_reached", "subscription_conflict", "invalid_recovery_key", "recovery_key_unknown", "device_not_eligible"],
        ]
        let booleans: Set<String> = ["capture_mic", "capture_system", "mic_pcm", "system_pcm", "pcm_sent", "speech_seen", "transcript_seen", "excluded"]
        let numbers: Set<String> = ["error_code", "status", "duration_seconds", "pending_uploads", "pending_removals", "dropped"]
        var result: [String: String] = [:]
        for (key, value) in fields {
            if vocabularies[key]?.contains(value) == true { result[key] = value }
            else if booleans.contains(key), value == "true" || value == "false" { result[key] = value }
            else if numbers.contains(key), let n = Int(value), (-10_000_000...10_000_000).contains(n) { result[key] = String(n) }
            else if key == "attempt_id", let id = UUID(uuidString: value) { result[key] = id.uuidString.lowercased() }
        }
        return result
    }

    static func errorFields(_ error: Error) -> [String: String] {
        let ns = error as NSError
        let domain = sanitize(["error_domain": ns.domain])["error_domain"] ?? "other"
        return sanitize(["error_domain": domain, "error_code": String(ns.code)])
    }

    func record(_ code: Code, fields: [String: String] = [:], at date: Date = Date()) {
        // Bounded admission as well as bounded storage: a busy producer cannot build an
        // unbounded Dispatch queue. No I/O or calls back into auth/audio on the producer.
        admission.lock()
        guard pending < 64 else { dropped = min(10_000_000, dropped + 1); admission.unlock(); return }
        pending += 1
        admission.unlock()
        let safe = Self.sanitize(fields)
        queue.async { [self] in
            defer { admission.lock(); pending -= 1; admission.unlock() }
            prune(now: date)
            if let index = events.lastIndex(where: { $0.code == code && $0.fields == safe && date.timeIntervalSince($0.last) >= 0 && date.timeIntervalSince($0.last) < 60 }) {
                events[index].last = date
                events[index].count = min(1_000_000, events[index].count + 1)
            } else {
                let event = Event(code: code, first: date, last: date, count: 1, fields: safe)
                events.append(event)
                if fileURL != nil {
                    DebugLogger.shared.log(.app, event.text, level: event.level == "warning" ? .warning : .routine)
                }
            }
            prune(now: date)
            scheduleWrite()
        }
    }

    private func prune(now: Date) {
        events.removeAll { now.timeIntervalSince($0.last) > Self.maxAge || $0.last > now.addingTimeInterval(300) }
        if events.count > Self.maxEvents { events.removeFirst(events.count - Self.maxEvents) }
        while !events.isEmpty, (try? JSONEncoder().encode(events).count) ?? Int.max > Self.maxBytes { events.removeFirst() }
    }

    private func scheduleWrite() {
        guard fileURL != nil, !writeScheduled else { return }
        writeScheduled = true
        queue.asyncAfter(deadline: .now() + 2) { [self] in
            guard writeScheduled else { return }
            writeScheduled = false; write()
        }
    }

    private func write() {
        guard var fileURL, let data = try? JSONEncoder().encode(events), data.count <= Self.maxBytes else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try fileURL.setResourceValues(values)
            storageFailed = false
        } catch { storageFailed = true /* No app decisions depend on diagnostic storage. */ }
    }

    func snapshot(now: Date = Date()) -> [Event] {
        queue.sync {
            prune(now: now)
            var result = events
            admission.lock(); let lost = dropped; admission.unlock()
            if lost > 0 { result.append(Event(code: .historyTruncated, first: now, last: now, count: 1, fields: ["dropped": String(lost)])) }
            if storageFailed { result.append(Event(code: .storageUnavailable, first: now, last: now, count: 1, fields: [:])) }
            return Array(result.suffix(Self.maxEvents))
        }
    }
    func clear() { queue.async { [self] in events.removeAll(); admission.lock(); dropped = 0; admission.unlock(); write() } }
    /// Test seam. Production persistence is always batched on the utility queue.
    func flushForTesting() { queue.sync { writeScheduled = false; write() } }
}
