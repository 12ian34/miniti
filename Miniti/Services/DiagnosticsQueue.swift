import Foundation

struct RecordingDiagnosticAttempt {
    let id = UUID()
    let route: String
    let microphone: Bool
    let system: Bool
    var ready = false
    var failed = false
    var degraded = false
    var micPCM = false
    var systemPCM = false
    var sentPCM = false
    var speech = false
    var transcript = false

    var details: [String: String] {
        ["attempt_id": id.uuidString, "route": route, "capture_mic": String(microphone), "capture_system": String(system),
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
