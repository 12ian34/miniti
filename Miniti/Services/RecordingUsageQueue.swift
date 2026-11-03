import Foundation

/// Content-free local capture accounting. No diagnostic consent or meeting identity.
@MainActor
final class RecordingUsageQueue {
    struct Owner: Codable, Equatable {
        let deviceID: String
        let accountID: String
    }
    struct Report: Codable, Equatable, Identifiable {
        let id: UUID
        let owner: Owner
        let day: String
        var durationMS: Int
    }
    enum DeliveryError: Error { case rejected }
    private struct Saved: Codable {
        var pending: [Report] = []
        var active: [Report] = []
        var dropped = 0
    }
    private static let dayFormatter = ISO8601DateFormatter()
    private let url: URL?
    private var saved = Saved()
    private var owner: Owner?
    private var lastDate: Date?
    private var lastUptime: TimeInterval?
    private var checkpointMS = 0
    private var flushing = false
    private var durable = true
    private var retryAt = Date.distantPast
    private var failures = 0
    var now: () -> Date = Date.init
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var pending: [Report] { saved.pending }
    var dropped: Int { saved.dropped }
    var isActive: Bool { owner != nil }

    init(fileURL: URL?) {
        url = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do { saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: fileURL)) }
            catch { saved.dropped += 1 }
        }
        // Validate persisted days once. Generated UTC day strings sort chronologically,
        // so periodic expiry does not parse thousands of dates on the main actor.
        let loadedCount = saved.pending.count + saved.active.count
        let invalidDay: (Report) -> Bool = { report in
            guard let date = Self.dayFormatter.date(from: report.day + "T00:00:00Z") else { return true }
            return String(Self.dayFormatter.string(from: date).prefix(10)) != report.day
        }
        saved.pending.removeAll(where: invalidDay)
        saved.active.removeAll(where: invalidDay)
        saved.dropped += loadedCount - saved.pending.count - saved.active.count
        // A crash can recover only the last durable checkpoint, never time spent closed.
        saved.pending.append(contentsOf: saved.active)
        saved.active = []
        expireAndBound()
        persist()
    }

    func begin(owner: Owner) {
        guard self.owner == nil else { return }
        self.owner = owner
        lastDate = now(); lastUptime = uptime(); checkpointMS = 0
    }

    func observe(owner current: Owner?) {
        guard let owner else { return }
        guard current == owner else { finish(observeTail: false); return }
        let date = now(), clock = uptime()
        defer { lastDate = date; lastUptime = clock }
        guard let lastDate, let lastUptime else { return }
        let elapsed = max(0, clock - lastUptime)
        // The active timer samples every second. A suspended or stalled process does
        // not prove capture for its whole absence; bound the contribution and expose loss.
        if elapsed > 5 { saved.dropped += 1 }
        let milliseconds = Int((min(elapsed, 5) * 1000).rounded())
        guard milliseconds > 0 else { return }
        let intervalStart = date.timeIntervalSince(lastDate) >= 0 && date.timeIntervalSince(lastDate) < 6 ? lastDate : date.addingTimeInterval(-Double(milliseconds) / 1000)
        append(milliseconds, from: intervalStart, owner: owner)
        checkpointMS += milliseconds
        if checkpointMS >= 15000 { checkpointMS = 0; expireAndBound(); persist() }
    }

    func finish(observeTail: Bool = true) {
        if observeTail, let owner { observe(owner: owner) }
        saved.pending.append(contentsOf: saved.active)
        saved.active = []; owner = nil; lastDate = nil; lastUptime = nil; checkpointMS = 0
        expireAndBound(); persist()
    }

    /// Explicit account deletion removes its pending/checkpointed reports. A late
    /// acknowledgement only removes rows, so it cannot resurrect deleted work.
    @discardableResult
    func remove(accountID: String) -> Bool {
        saved.pending.removeAll { $0.owner.accountID == accountID }
        saved.active.removeAll { $0.owner.accountID == accountID }
        if owner?.accountID == accountID {
            owner = nil; lastDate = nil; lastUptime = nil; checkpointMS = 0
        }
        persist()
        return durable
    }

    private func append(_ milliseconds: Int, from start: Date, owner: Owner) {
        var remaining = milliseconds
        var cursor = start
        while remaining > 0 {
            let dayStart = floor(cursor.timeIntervalSince1970 / 86400) * 86400
            let day = Self.dayFormatter.string(from: Date(timeIntervalSince1970: dayStart)).prefix(10)
            let untilMidnight = max(1, Int(((dayStart + 86400 - cursor.timeIntervalSince1970) * 1000).rounded()))
            if saved.active.last?.day != String(day) || saved.active.last?.durationMS == 14400000 {
                saved.active.append(Report(id: UUID(), owner: owner, day: String(day), durationMS: 0))
            }
            let index = saved.active.count - 1
            let part = min(remaining, untilMidnight, 14400000 - saved.active[index].durationMS)
            saved.active[index].durationMS += part
            remaining -= part; cursor.addTimeInterval(Double(part) / 1000)
        }
        boundCapacity()
    }

    private func expireAndBound() {
        let today = floor(now().timeIntervalSince1970 / 86400) * 86400
        let oldestDay = String(Self.dayFormatter.string(from: Date(timeIntervalSince1970: today - 30 * 86400)).prefix(10))
        let oldCount = saved.pending.count + saved.active.count
        let expired: (Report) -> Bool = { report in
            report.day < oldestDay || report.durationMS <= 0 || report.durationMS > 14400000
        }
        saved.pending.removeAll(where: expired)
        saved.active.removeAll(where: expired)
        saved.dropped += oldCount - saved.pending.count - saved.active.count
        boundCapacity()
    }

    private func boundCapacity() {
        let excess = max(0, saved.pending.count + saved.active.count - 2048)
        guard excess > 0 else { return }
        saved.dropped += excess
        let pendingCount = min(excess, saved.pending.count)
        saved.pending.removeFirst(pendingCount)
        saved.active.removeFirst(excess - pendingCount)
    }
    private func persist() {
        guard let url else { durable = true; return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: url, options: .atomic)
            durable = true
        } catch { durable = false }
    }

    func flush(currentOwner: () -> Owner?, send: (Report) async throws -> UUID) async {
        guard !saved.pending.isEmpty, !flushing, now() >= retryAt else { return }
        expireAndBound(); persist()
        guard durable else { return }
        flushing = true
        defer { flushing = false }
        // At most 20 requests per attempt, leaving room below the server burst limit.
        for _ in 0..<20 {
            guard let owner = currentOwner(), let report = saved.pending.first(where: { $0.owner == owner }) else { return }
            do {
                let receipt = try await send(report)
                guard currentOwner() == owner else { return }
                guard receipt == report.id else { throw URLError(.badServerResponse) }
                saved.pending.removeAll { $0.id == report.id && $0.owner == owner }
                failures = 0; retryAt = .distantPast; persist()
                guard durable else { return }
            } catch DeliveryError.rejected {
                guard currentOwner() == owner else { return }
                saved.pending.removeAll { $0.id == report.id && $0.owner == owner }
                saved.dropped += 1; persist()
                guard durable else { return }
            } catch {
                failures = min(failures + 1, 8)
                retryAt = now().addingTimeInterval(min(3600, pow(2, Double(failures)) * 15))
                return
            }
        }
        retryAt = now().addingTimeInterval(60)
    }
}
