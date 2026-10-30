import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

@MainActor
final class DiagnosticsQueueTests: XCTestCase {
    private func event(_ name: String = "recording_attempt") -> MinitiAPIService.ClientEventPayload {
        .init(name: name, category: .app, level: .info, occurredAt: Date(), diagnosticsSessionId: UUID().uuidString,
              appMode: "managed", meetingId: nil, details: nil)
    }

    func testReceiptKeepsArrivalsAndConcurrentFlushCannotDuplicateTheSend() async {
        let suite = "DiagnosticsQueueTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = DiagnosticsQueue(defaults: defaults)
        let first = event(), second = event()
        queue.append(first)
        var held: CheckedContinuation<Set<UUID>, Error>?
        var sent: [[UUID]] = []
        let task = Task { await queue.flush(allowed: { true }) { batch in
            sent.append(batch.map(\.id))
            if sent.count == 1 { return try await withCheckedThrowingContinuation { held = $0 } }
            throw URLError(.notConnectedToInternet)
        } }
        while held == nil { await Task.yield() }
        queue.append(second)
        await queue.flush(allowed: { true }) { _ in XCTFail("Concurrent send"); return [] }
        held?.resume(returning: [first.id])
        await task.value
        XCTAssertEqual(queue.events.map(\.id), [second.id])
        XCTAssertEqual(sent, [[first.id], [second.id]])
        XCTAssertEqual(DiagnosticsQueue(defaults: defaults).events.map(\.id), [second.id])
        XCTAssertGreaterThan(queue.retryDelay, 0)
    }

    func testClearedOrReownedQueueCannotBeRestoredByLateReceipt() async {
        let suite = "DiagnosticsQueueTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = DiagnosticsQueue(defaults: defaults)
        queue.setOwner("a")
        let first = event(); queue.append(first)
        var held: CheckedContinuation<Set<UUID>, Error>?
        let task = Task { await queue.flush(allowed: { true }) { _ in try await withCheckedThrowingContinuation { held = $0 } } }
        while held == nil { await Task.yield() }
        queue.clear() // diagnostics consent withdrawn
        queue.setOwner("b")
        let newEvent = event(); queue.append(newEvent)
        held?.resume(returning: [first.id])
        await task.value
        XCTAssertEqual(queue.events.map(\.id), [newEvent.id])
    }

    func testLostResponseKeepsIdentityAcrossRelaunchAndBackoff() async {
        let suite = "DiagnosticsQueueTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = DiagnosticsQueue(defaults: defaults)
        let item = event(); queue.append(item)
        await queue.flush(allowed: { true }) { _ in throw URLError(.networkConnectionLost) }
        let reloaded = DiagnosticsQueue(defaults: defaults)
        XCTAssertEqual(reloaded.events.map(\.id), [item.id])
        XCTAssertGreaterThan(reloaded.retryDelay, 0)
        reloaded.now = { Date().addingTimeInterval(16) }
        await reloaded.flush(allowed: { true }) { batch in Set(batch.map(\.id)) }
        XCTAssertTrue(reloaded.events.isEmpty)
    }
}
