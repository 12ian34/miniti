import Foundation

struct ManagedSessionReport: Codable, Equatable, Identifiable, Sendable {
    static func isV2SessionID(_ value: String) -> Bool {
        value.range(of: #"^sess_v2_[A-Za-z0-9_-]{12,64}$"#, options: .regularExpression) != nil
    }
    let id: UUID
    let deviceId: String
    var sessionId: String
    var durationMinutes: Double
    let createdAt: Date
    var retryCount: Int
    var meetingId: UUID?
    var accountID: String?
    var recordingID: UUID?
    var accountingVersion: Int?
    var durationMS: Int?
    var nextAttemptAt: Date?

    init(id: UUID = UUID(), deviceId: String, sessionId: String, durationMinutes: Double,
         createdAt: Date = Date(), retryCount: Int = 0, meetingId: UUID? = nil,
         accountID: String? = nil, recordingID: UUID? = nil, accountingVersion: Int? = nil, durationMS: Int? = nil) {
        self.id = id; self.deviceId = deviceId; self.sessionId = sessionId
        self.durationMinutes = durationMinutes; self.createdAt = createdAt; self.retryCount = retryCount
        self.meetingId = meetingId; self.accountID = accountID; self.recordingID = recordingID
        self.accountingVersion = accountingVersion; self.durationMS = durationMS
    }
}

private struct ManagedSessionSaved: Codable, Sendable {
    var active: ManagedSessionReport?
    var pending: [ManagedSessionReport] = []
    var dropped = 0
}

private actor ManagedSessionDisk {
    let url: URL?
    private var revision = 0
    init(url: URL?) { self.url = url }
    func write(_ saved: ManagedSessionSaved, revision next: Int) -> Bool {
        guard next >= revision else { return true }
        guard let url else { revision = next; return true }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: url, options: .atomic)
            revision = next
            return true
        } catch { return false }
    }
}

/// Immutable accounting format/owner per recording. Periodic checkpoints never
/// encode or write on the capture/main actor, and never run for an idle session.
@MainActor
final class ManagedSessionJournal {
    enum DeliveryError: Error { case terminal, incompatibleSession, persistenceFailed }
    private var saved: ManagedSessionSaved
    private let disk: ManagedSessionDisk
    private var revision = 0
    private var lastUptime: TimeInterval?
    private var lastCheckpoint: TimeInterval?
    private var flushing = false
    var now: () -> Date = Date.init
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    private(set) var checkpointWrites = 0
    var active: ManagedSessionReport? { saved.active }
    var pending: [ManagedSessionReport] { saved.pending }
    var dropped: Int { saved.dropped }

    init(fileURL: URL?, legacyData: Data? = nil) {
        disk = ManagedSessionDisk(url: fileURL)
        if let fileURL, let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(ManagedSessionSaved.self, from: data) {
            saved = decoded
        } else {
            saved = ManagedSessionSaved()
            if let legacyData, let old = try? JSONDecoder().decode([ManagedSessionReport].self, from: legacyData) {
                // Old reports carry no trustworthy owner; never assign today's account.
                saved.pending = old.filter { $0.accountID != nil }
                saved.dropped += old.count - saved.pending.count
            }
        }
        if let active = saved.active {
            if active.accountingVersion == 2 || active.durationMinutes > 0 { saved.pending.append(active) }
            saved.active = nil
        }
        bound()
    }

    private func bound() {
        let previous = saved.pending.count
        saved.pending.removeAll { report in
            report.accountID == nil || now().timeIntervalSince(report.createdAt) > 30 * 86400
                || !report.durationMinutes.isFinite || report.durationMinutes < 0
        }
        saved.dropped += previous - saved.pending.count
        if saved.pending.count > 200 {
            saved.dropped += saved.pending.count - 200
            saved.pending.removeFirst(saved.pending.count - 200)
        }
    }

    @discardableResult
    func persist() async -> Bool {
        revision += 1
        return await disk.write(saved, revision: revision)
    }

    func begin(_ report: ManagedSessionReport) async throws {
        guard saved.active == nil, report.accountID != nil,
              report.accountingVersion == 1 || report.accountingVersion == 2 else { throw DeliveryError.incompatibleSession }
        saved.active = report
        lastUptime = nil; lastCheckpoint = nil
        guard await persist() else { saved.active = nil; throw DeliveryError.persistenceFailed }
    }

    func captureBegan() {
        guard saved.active != nil, lastUptime == nil else { return }
        lastUptime = uptime(); lastCheckpoint = lastUptime
    }

    func observe() {
        guard var report = saved.active, let previous = lastUptime else { return }
        let current = uptime()
        let delta = max(0, current - previous)
        guard delta.isFinite, delta < Double(Int.max) / 1000 else { return }
        let ms = (report.durationMS ?? 0) + Int((delta * 1000).rounded())
        report.durationMS = ms; report.durationMinutes = Double(ms) / 60000
        saved.active = report; lastUptime = current
        if current - (lastCheckpoint ?? current) >= 15 {
            lastCheckpoint = current
            revision += 1; checkpointWrites += 1
            let snapshot = saved, sequence = revision, disk = disk
            Task { _ = await disk.write(snapshot, revision: sequence) }
        }
    }

    func renew(sessionID: String, version: Int) throws {
        guard var report = saved.active, report.accountingVersion == version,
              version == 1 || report.sessionId == sessionID else { throw DeliveryError.incompatibleSession }
        // Legacy deliberately retains its old final-grant accounting semantics.
        report.sessionId = sessionID
        saved.active = report
    }

    func finish(meetingID: UUID?, includeUnobservedTime: Bool = true) -> ManagedSessionReport? {
        if includeUnobservedTime { observe() }
        guard var report = saved.active else { return nil }
        report.meetingId = meetingID
        saved.active = nil; lastUptime = nil; lastCheckpoint = nil
        // Legacy zero uses elapsed server time; never send it for failed capture.
        guard report.accountingVersion == 2 || report.durationMinutes > 0 else {
            Task { _ = await persist() }
            return nil
        }
        saved.pending.append(report)
        bound()
        Task { _ = await persist() }
        return report
    }

    @discardableResult
    func enqueue(_ report: ManagedSessionReport) async -> Bool {
        guard report.accountID != nil else { saved.dropped += 1; return await persist() }
        if !saved.pending.contains(where: { $0.sessionId == report.sessionId && $0.deviceId == report.deviceId && $0.accountID == report.accountID }) {
            saved.pending.append(report)
        }
        bound()
        return await persist()
    }

    @discardableResult
    func remove(accountID: String) async -> Bool {
        saved.pending.removeAll { $0.accountID == accountID }
        if saved.active?.accountID == accountID {
            saved.active = nil; lastUptime = nil; lastCheckpoint = nil
        }
        return await persist()
    }

    func flush(ignoringBackoff: Bool = false, currentAccount: () -> String?, send: (ManagedSessionReport) async throws -> Void) async {
        guard !flushing, !saved.pending.isEmpty, currentAccount() != nil else { return }
        flushing = true; defer { flushing = false }
        bound()
        let snapshot = saved.pending
        for report in snapshot {
            if !ignoringBackoff, let date = report.nextAttemptAt, date > now() { continue }
            guard let owner = currentAccount() else { break }
            guard report.accountID == owner else {
                // A credential repair may temporarily leave this owner. Retain the report
                // for a return to that account, within the existing age/count bounds.
                continue
            }
            do {
                try await send(report)
                saved.pending.removeAll { $0.id == report.id }
            } catch DeliveryError.terminal {
                saved.pending.removeAll { $0.id == report.id }; saved.dropped += 1
            } catch {
                if let index = saved.pending.firstIndex(where: { $0.id == report.id }) {
                    saved.pending[index].retryCount += 1
                    let delay = min(300.0, 15 * pow(2, Double(min(saved.pending[index].retryCount, 5))))
                    saved.pending[index].nextAttemptAt = now().addingTimeInterval(delay)
                }
                break
            }
        }
        _ = await persist()
    }
}
