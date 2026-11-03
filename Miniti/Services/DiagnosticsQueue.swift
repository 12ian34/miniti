import Foundation

struct RecordingDiagnosticAttempt {
    let id = UUID()
    var route: String
    let microphone: Bool
    let system: Bool
    let startedAt = CFAbsoluteTimeGetCurrent()
    var initialDuration: TimeInterval = 0
    var started = false
    var ready = false
    var failed = false
    var degraded = false
    var micPCM = false
    var systemPCM = false
    var sentPCM = false
    var speech = false
    var transcript = false

    var transcriptionOutcome: String {
        transcript ? "words_seen" : speech ? "speech_without_words" : "no_speech_evidence"
    }

    func finalDetails(failed: Bool, duration: TimeInterval) -> [String: String] {
        var result = details
        let lifecycle = failed ? "failed" : started ? "stopped" : "cancelled"
        // Keep legacy outcome vocabulary while separating the two new dimensions.
        result["outcome"] = failed ? "failed" : degraded ? "degraded" : lifecycle
        result["lifecycle_outcome"] = lifecycle
        result["transcription_outcome"] = transcriptionOutcome
        let elapsed = duration - initialDuration
        result["duration_seconds"] = String(elapsed.isFinite ? Int(max(0, min(86400, elapsed))) : 0)
        return result
    }

    var details: [String: String] {
        ["schema_version": "1", "transcription_engine": route == "local" ? "on_device" : "deepgram",
         "attempt_id": id.uuidString, "route": route, "capture_mic": String(microphone), "capture_system": String(system),
         "mic_pcm": String(micPCM), "system_pcm": String(systemPCM), "pcm_sent": String(sentPCM),
         "speech_seen": String(speech), "transcript_seen": String(transcript)]
    }
}

/// A bounded durable outbox. A receipt removes only those IDs from the current queue,
/// never a saved pre-await array. Clearing or changing owner invalidates the flush.
@MainActor
final class DiagnosticsQueue {
    typealias Event = MinitiAPIService.ClientEventPayload
    private struct Saved: Codable {
        var events: [Event]
        var owner: String?
        var dropped: Int
        var expired: Int
        var failures: Int
        var retryAt: Date?
    }
    private let defaults: UserDefaults
    private let key: String
    private var epoch = 0
    private var flushing = false
    private var saved: Saved
    var now: () -> Date = Date.init
    var events: [Event] { saved.events }
    var dropped: Int { saved.dropped }
    var expired: Int { saved.expired }
    var retryDelay: TimeInterval { max(0, saved.retryAt?.timeIntervalSince(now()) ?? 0) }

    init(defaults: UserDefaults, key: String = "pendingClientEvents") {
        self.defaults = defaults; self.key = key
        let data = defaults.data(forKey: key)
        saved = defaults.data(forKey: key + ".metadata").flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
            ?? data.flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
            ?? Saved(events: data.flatMap { try? JSONDecoder().decode([Event].self, from: $0) } ?? [],
                     owner: nil, dropped: 0, expired: 0, failures: 0, retryAt: nil)
        if let events = data.flatMap({ try? JSONDecoder().decode([Event].self, from: $0) }) { saved.events = events }
        // Persist migrated IDs once, so a restart cannot give the same event a new ID.
        if data != nil { persist() }
    }

    func setOwner(_ owner: String?) {
        if saved.owner != nil, saved.owner != owner { clear() }
        saved.owner = owner
        persist()
    }

    func clear() {
        epoch += 1; saved.events.removeAll(); saved.failures = 0; saved.retryAt = nil
        persist()
    }

    func append(_ event: Event) {
        expire()
        saved.events.append(event)
        if saved.events.count > 200 {
            saved.dropped += saved.events.count - 200
            saved.events.removeFirst(saved.events.count - 200)
        }
        persist()
    }

    private func expire() {
        let count = saved.events.count
        saved.events.removeAll { now().timeIntervalSince($0.occurredAt) > 14 * 86400 }
        saved.expired += count - saved.events.count
    }

    func flush(allowed: () -> Bool, send: ([Event]) async throws -> Set<UUID>) async {
        guard !flushing, retryDelay == 0, allowed() else { return }
        flushing = true
        defer { flushing = false }
        expire(); persist()
        let generation = epoch
        // Bounded work, including an info-event producer that continues during the flush.
        for _ in 0..<8 {
            guard epoch == generation, allowed(), !saved.events.isEmpty else { return }
            let batch = Array(saved.events.prefix(25))
            do {
                let receipt = try await send(batch)
                guard epoch == generation, allowed() else { return }
                let accepted = receipt.intersection(Set(batch.map(\.id)))
                saved.events.removeAll { accepted.contains($0.id) }
                guard !accepted.isEmpty else { fail(); return }
                saved.failures = 0; saved.retryAt = nil; persist()
            } catch {
                guard epoch == generation, allowed() else { return }
                fail(); return
            }
        }
    }

    private func fail() {
        saved.failures = min(saved.failures + 1, 10)
        saved.retryAt = now().addingTimeInterval(min(3600, 15 * pow(2, Double(saved.failures - 1))))
        persist()
    }

    private func persist() {
        // Keep the original array readable by a rolled-back client. Metadata is additive.
        if let data = try? JSONEncoder().encode(saved.events) { defaults.set(data, forKey: key) }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: key + ".metadata") }
    }
}

/// Fixed v1 reporting vocabulary, mirrored by the canonical reporting fixture.
enum RecordingReportingContract {
    static let vocabulary: [String: Set<String>] = [
        "schema_version": ["1"],
        "transcription_engine": ["deepgram", "on_device", "unavailable", "unknown"],
        "speaker_engine": ["deepgram", "on_device", "unavailable", "unknown"],
        "lifecycle_outcome": ["stopped", "cancelled", "failed"],
        "transcription_outcome": ["words_seen", "speech_without_words", "no_speech_evidence", "unknown"],
        "failure_category": ["transport", "timeout", "auth", "admission", "decode", "provider", "persistence", "model_access", "cancelled", "superseded", "unknown"],
        "task_mode": ["standard", "meddpicc", "questions", "template", "docs", "investigation", "speaker_names", "catchup", "docs_topics", "template_draft"],
        "ai_stage": ["live", "final", "saved", "helper"],
        "model_family": ["macbook_air", "macbook_pro", "mac_mini", "mac_studio", "imac", "mac_pro", "unknown"],
        "chip_family": ["apple_m1", "apple_m2", "apple_m3", "apple_m4", "apple_m5", "intel", "unknown"],
        "ram_band": ["up_to_8_gb", "9_to_16_gb", "17_to_32_gb", "33_to_64_gb", "over_64_gb", "unknown"],
        "hardware_support": ["supported", "unsupported", "unknown"],
        "preparation_state": ["off", "preparing", "ready", "failed", "unknown"],
        "thermal_state": ["nominal", "fair", "serious", "critical", "unknown"],
        "speaker_failure": ["load", "inference", "lag", "unsupported", "not_ready", "cancelled", "unknown"],
    ]
    static let limits: [String: Int] = ["gap_seconds": 86400, "max_attempts": 10, "lag_ms": 3600000, "preparation_ms": 3600000]
    static func valid(_ key: String, _ value: String) -> Bool {
        if RecoveryReportingContract.valid(key, value) { return true }
        if let choices = vocabulary[key] { return choices.contains(value) }
        if let limit = limits[key] {
            return value.range(of: "^[0-9]{1,8}$", options: .regularExpression) != nil && Int(value).map { $0 <= limit } == true
        }
        if key == "request_id" { return UUID(uuidString: value) != nil }
        if key == "producer_version" { return value.range(of: "^[0-9]{1,3}(\\.[0-9]{1,3}){1,3}$", options: .regularExpression) != nil }
        return false
    }
}

/// Recovery evidence is scoped to one attempt and connection generation. Quiet
/// after reconnect is unresolved, not evidence of another failure.
struct RecordingRecoveryEvidence {
    private(set) var generation = 0
    private(set) var startedAt: TimeInterval?
    private var minimumConnection: UInt64 = 0
    private var reportedConnection: UInt64?
    private(set) var awaitingTranscript = false

    mutating func begin(at uptime: TimeInterval, connection: UInt64, replacement: Bool) {
        generation = min(99_999_999, generation + 1)
        startedAt = uptime
        minimumConnection = connection + (replacement ? 1 : 0)
        reportedConnection = nil
        awaitingTranscript = true
    }

    func accepts(connection: UInt64) -> Bool { connection >= minimumConnection }

    mutating func observe(connection: UInt64, connected: Bool, transcriptAt: TimeInterval,
                          recentCapture: Bool) -> (connectionRestored: Bool, transcriptionResumed: Bool) {
        guard awaitingTranscript, let startedAt, connected, accepts(connection: connection) else { return (false, false) }
        let restored = reportedConnection != connection
        reportedConnection = connection
        guard recentCapture, transcriptAt > startedAt else { return (restored, false) }
        awaitingTranscript = false
        return (restored, true)
    }
}

/// Additive recovery vocabulary, shared with recovery-v1.json. Existing fixture
/// bytes and legacy pcm_sent (send/ingest attempted) semantics remain unchanged.
enum RecoveryReportingContract {
    static let reasons: Set<String> = ["connection_error", "unexpected_close", "transcript_stall", "retry_exhausted", "manual", "capture_gap", "unknown"]
    static let counters: Set<String> = ["connection_generation", "recovery_generation", "send_attempts", "send_completions", "local_ingest_attempts", "dropped_packets", "audio_gap_seconds"]
    static func valid(_ key: String, _ value: String) -> Bool {
        if key == "recovery_reason" { return reasons.contains(value) }
        guard counters.contains(key), value.range(of: "^[0-9]{1,8}$", options: .regularExpression) != nil,
              let count = Int(value) else { return false }
        return count <= (key == "audio_gap_seconds" ? 86400 : 99_999_999)
    }
}
