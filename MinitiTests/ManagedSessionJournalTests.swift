import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

@MainActor
final class ManagedSessionJournalTests: XCTestCase {
    private func report(_ session: String = "sess_v2_one", owner: String = "account-a", version: Int = 2) -> ManagedSessionReport {
        .init(deviceId: "UPPER-DEVICE", sessionId: session, durationMinutes: 0,
              accountID: owner, recordingID: UUID(), accountingVersion: version, durationMS: 0)
    }

    func testAbandonedSessionCannotBillTheIdleGapOrPoisonTheNextAccount() async throws {
        let state = AppState()
        let journal = state.managedSessionJournal
        var clock: TimeInterval = 0
        journal.uptime = { clock }
        try await journal.begin(report())
        journal.captureBegan(); clock = 20; journal.observe()
        clock = 3600
        state.managedRecordingID = journal.active?.recordingID
        state.closeUnusedManagedSession()
        XCTAssertNil(state.managedRecordingID, "The next grant must not reuse the finalized recording identity")
        XCTAssertNil(journal.active)
        XCTAssertEqual(journal.pending.last?.durationMS, 20000)
        try await journal.begin(report("sess_v2_new", owner: "account-b"))
        journal.captureBegan(); clock += 10
        XCTAssertEqual(journal.finish(meetingID: nil)?.durationMS, 10000)
        XCTAssertFalse(ManagedSessionReport.isV2SessionID("sess_v2_123456789"))
        XCTAssertTrue(ManagedSessionReport.isV2SessionID("sess_v2_abcdefghijklmnop"))
    }

    func testRenewalsKeepSeventyFourMinutesAndLongRecordingsCountBeyondFourHours() async throws {
        for minutes in [74, 360] {
            let journal = ManagedSessionJournal(fileURL: nil)
            var clock: TimeInterval = 100
            journal.uptime = { clock }
            try await journal.begin(report())
            clock += 30 // Grant and setup time is excluded.
            journal.captureBegan()
            for _ in 0..<minutes {
                clock += 60
                journal.observe()
                try journal.renew(sessionID: "sess_v2_one", version: 2)
            }
            let final = try XCTUnwrap(journal.finish(meetingID: UUID()))
            XCTAssertEqual(final.durationMS, minutes * 60_000)
            XCTAssertEqual(final.sessionId, "sess_v2_one")
            clock += 3600
            journal.observe()
            XCTAssertEqual(journal.pending.first?.durationMS, minutes * 60_000, "Paused time is excluded")
        }
    }

    func testRecoveryUsesLastCheckpointAndNoIdleWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")
        let journal = ManagedSessionJournal(fileURL: url)
        var clock: TimeInterval = 0
        journal.uptime = { clock }
        journal.observe()
        XCTAssertEqual(journal.checkpointWrites, 0)
        try await journal.begin(report())
        journal.captureBegan()
        clock = 15
        journal.observe()
        XCTAssertEqual(journal.checkpointWrites, 1)
        let persisted = await journal.persist()
        XCTAssertTrue(persisted)
        let restored = ManagedSessionJournal(fileURL: url)
        XCTAssertNil(restored.active)
        XCTAssertEqual(restored.pending.first?.durationMS, 15_000)
        XCTAssertEqual(restored.pending.first?.accountID, "account-a")
    }

    func testFormatCannotChangeAfterCaptureAndV2RootCannotBeReplaced() async throws {
        let journal = ManagedSessionJournal(fileURL: nil)
        try await journal.begin(report())
        XCTAssertThrowsError(try journal.renew(sessionID: "sess_legacy", version: 1))
        XCTAssertThrowsError(try journal.renew(sessionID: "sess_v2_different", version: 2))
        XCTAssertEqual(journal.active?.sessionId, "sess_v2_one")
    }

    func testOfflineSignOutAndDifferentOwnerRetainReportUntilOriginalAccountReturns() async throws {
        let journal = ManagedSessionJournal(fileURL: nil)
        _ = await journal.enqueue(report())
        await journal.flush(currentAccount: { nil }) { _ in XCTFail("Signed out") }
        XCTAssertEqual(journal.pending.count, 1)
        await journal.flush(currentAccount: { "account-b" }) { _ in XCTFail("Wrong owner") }
        XCTAssertEqual(journal.pending.count, 1)
        XCTAssertEqual(journal.dropped, 0)
        var delivered: [String?] = []
        await journal.flush(currentAccount: { "account-a" }) { delivered.append($0.accountID) }
        XCTAssertEqual(delivered, ["account-a"])
        XCTAssertTrue(journal.pending.isEmpty)
    }

    func testEnqueueDuringHeldFlushIsNotLostAndTransientFailureRetries() async throws {
        let journal = ManagedSessionJournal(fileURL: nil)
        _ = await journal.enqueue(report())
        await journal.flush(currentAccount: { "account-a" }) { _ in
            _ = await journal.enqueue(self.report("sess_v2_two"))
        }
        XCTAssertEqual(journal.pending.map(\.sessionId), ["sess_v2_two"])
        await journal.flush(currentAccount: { "account-a" }) { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(journal.pending.first?.retryCount, 1)
        await journal.flush(currentAccount: { "account-a" }) { _ in XCTFail("Retry deadline must be respected") }
        journal.now = { Date().addingTimeInterval(301) }
        await journal.flush(currentAccount: { "account-a" }) { _ in throw ManagedSessionJournal.DeliveryError.terminal }
        XCTAssertTrue(journal.pending.isEmpty)
        XCTAssertEqual(journal.dropped, 1)
    }

    func testLegacyOwnerlessMigrationNeverBindsToCurrentAccount() throws {
        let old = ManagedSessionReport(deviceId: "device", sessionId: "sess_old", durationMinutes: 20)
        let journal = ManagedSessionJournal(fileURL: nil, legacyData: try JSONEncoder().encode([old]))
        XCTAssertEqual(journal.dropped, 1)
        XCTAssertTrue(journal.pending.isEmpty)
    }
    func testAccountDeletionRemovesOnlyThatOwnersDurableReports() async throws {
        let journal = ManagedSessionJournal(fileURL: nil)
        _ = await journal.enqueue(report("a", owner: "account-a"))
        _ = await journal.enqueue(report("b", owner: "account-b"))
        try await journal.begin(report("active", owner: "account-a"))
        let persisted = await journal.remove(accountID: "account-a")
        XCTAssertTrue(persisted)
        XCTAssertNil(journal.active)
        XCTAssertEqual(journal.pending.map(\.accountID), ["account-b"])
    }

    func testSixHourCheckpointBudgetIdleWritesAndPendingRetentionAreBounded() async throws {
        let journal = ManagedSessionJournal(fileURL: nil)
        var clock: TimeInterval = 0
        journal.uptime = { clock }
        try await journal.begin(report())
        journal.captureBegan()
        for second in 1...21600 { clock = Double(second); journal.observe() }
        XCTAssertEqual(journal.checkpointWrites, 1440)
        XCTAssertEqual(journal.finish(meetingID: nil)?.durationMS, 21_600_000)
        for _ in 1...1800 { clock += 1; journal.observe() }
        XCTAssertEqual(journal.checkpointWrites, 1440, "Idle time never writes checkpoints")
        for item in 1...200 { _ = await journal.enqueue(report("pending-\(item)")) }
        XCTAssertEqual(journal.pending.count, 200)
        XCTAssertEqual(journal.dropped, 1)
        journal.now = { Date().addingTimeInterval(31 * 86400) }
        await journal.flush(currentAccount: { "account-a" }) { _ in XCTFail("Expired reports must not be sent") }
        XCTAssertTrue(journal.pending.isEmpty)
        XCTAssertEqual(journal.dropped, 201)
    }

}
