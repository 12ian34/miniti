import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

@MainActor
final class DeliveryOutboxTests: XCTestCase {
    private var storeURL: URL!
    private var clock: Date!

    override func setUp() async throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-tests-\(UUID().uuidString).json")
        clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storeURL)
    }

    private func makeOutbox() -> DeliveryOutbox {
        DeliveryOutbox(storeURL: storeURL, now: { self.clock })
    }

    private func advance(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }

    func testScheduleIsBoundedAndThenTerminal() {
        XCTAssertEqual(DeliveryOutbox.nextDelay(afterAttempts: 1), 30)
        XCTAssertEqual(DeliveryOutbox.nextDelay(afterAttempts: 2), 120)
        XCTAssertEqual(DeliveryOutbox.nextDelay(afterAttempts: 5), 7200)
        XCTAssertNil(DeliveryOutbox.nextDelay(afterAttempts: 6), "sixth failure is terminal")
        XCTAssertNil(DeliveryOutbox.nextDelay(afterAttempts: 0))
    }

    func testOutcomeClassification() {
        XCTAssertEqual(DeliveryOutbox.outcome(status: 204, error: nil), .delivered)
        XCTAssertEqual(DeliveryOutbox.outcome(status: 503, error: nil), .retry(reason: "HTTP 503"))
        XCTAssertEqual(DeliveryOutbox.outcome(status: 429, error: nil), .retry(reason: "HTTP 429"))
        XCTAssertEqual(DeliveryOutbox.outcome(status: 404, error: nil), .reject(reason: "HTTP 404"))
        XCTAssertEqual(DeliveryOutbox.outcome(status: nil, error: URLError(.notConnectedToInternet)),
                       .retry(reason: "network error \(URLError.Code.notConnectedToInternet.rawValue)"))
    }

    func testWebhookRetriesWithBackoffThenDelivers() async {
        let outbox = makeOutbox()
        var calls = 0
        var results: [DeliveryOutbox.Outcome] = [.retry(reason: "HTTP 503"), .retry(reason: "network error -1009"), .delivered]
        outbox.register(.webhook) { _ in calls += 1; return results.removeFirst() }
        let meeting = UUID()
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.saved", body: Data("{}".utf8), destination: "https://example.com/hook")

        await outbox.processDue()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(outbox.pending.count, 1)
        XCTAssertEqual(outbox.pending[0].attempts, 1)
        XCTAssertEqual(outbox.pending[0].nextAttemptAt, clock.addingTimeInterval(30))

        await outbox.processDue()
        XCTAssertEqual(calls, 1, "not due yet")

        advance(31)
        await outbox.processDue()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(outbox.pending[0].nextAttemptAt, clock.addingTimeInterval(120))

        advance(121)
        await outbox.processDue()
        XCTAssertEqual(calls, 3)
        XCTAssertTrue(outbox.items.isEmpty, "delivered items leave the queue")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path), "an empty queue leaves no file behind")
    }

    func testRejectionIsTerminalAndDropsTheBody() async {
        let outbox = makeOutbox()
        outbox.register(.webhook) { _ in .reject(reason: "HTTP 404") }
        outbox.enqueueWebhook(meetingID: UUID(), event: "meeting.saved", body: Data("transcript".utf8), destination: "https://example.com/hook")
        await outbox.processDue()
        XCTAssertEqual(outbox.failed.count, 1)
        XCTAssertNil(outbox.failed[0].body, "the transcript copy is released on terminal failure")
        XCTAssertEqual(outbox.statusLine(for: .webhook), "1 failed: HTTP 404")
    }

    func testGivesUpAfterTheScheduleAndCanBeRetriedByHand() async {
        let outbox = makeOutbox()
        var calls = 0
        outbox.register(.webhook) { _ in calls += 1; return .retry(reason: "HTTP 500") }
        outbox.enqueueWebhook(meetingID: UUID(), event: "meeting.saved", body: Data("{}".utf8), destination: "https://example.com/hook")
        for _ in 0..<6 {
            await outbox.processDue()
            advance(7201)
        }
        XCTAssertEqual(calls, 6)
        XCTAssertEqual(outbox.failed.count, 1)
        XCTAssertEqual(outbox.pending.count, 0)

        outbox.register(.webhook) { _ in calls += 1; return .delivered }
        outbox.retryNow(.webhook)
        await outbox.processDue()
        XCTAssertEqual(calls, 7)
        XCTAssertTrue(outbox.items.isEmpty)
    }

    func testSupersedesAPendingUpdateForTheSameMeetingInsteadOfQueuingTwice() async {
        let outbox = makeOutbox()
        outbox.register(.webhook) { _ in .retry(reason: "HTTP 503") }
        let meeting = UUID()
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.updated", body: Data("v1".utf8), destination: "https://example.com/hook")
        await outbox.processDue()
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.updated", body: Data("v2".utf8), destination: "https://example.com/hook")
        XCTAssertEqual(outbox.pending.count, 1)
        XCTAssertEqual(outbox.pending[0].body, Data("v2".utf8))
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.saved", body: Data("s".utf8), destination: "https://example.com/hook")
        XCTAssertEqual(outbox.pending.count, 2, "a different event is its own delivery")
    }

    func testCRMSkipIsNotRetriedAndOnePerMeeting() async {
        let outbox = makeOutbox()
        var calls = 0
        outbox.register(.attio) { _ in calls += 1; return .skip(reason: "3 matches") }
        let meeting = UUID()
        outbox.enqueueCRM(.attio, meetingID: meeting)
        outbox.enqueueCRM(.attio, meetingID: meeting)
        XCTAssertEqual(outbox.pending(.attio).count, 1)
        await outbox.processDue()
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(outbox.pending.isEmpty)
        XCTAssertNil(outbox.statusLine(for: .attio), "a skip is not a failure to shout about")
        advance(DeliveryOutbox.skippedRetention + 1)
        await outbox.processDue()
        XCTAssertTrue(outbox.items.isEmpty, "skipped items are pruned")
    }

    func testPersistsAcrossInstancesAndDropsDeletedMeetings() async {
        let outbox = makeOutbox()
        outbox.register(.webhook) { _ in .retry(reason: "HTTP 503") }
        let a = UUID(), b = UUID()
        outbox.enqueueWebhook(meetingID: a, event: "meeting.saved", body: Data("a".utf8), destination: "https://example.com/hook")
        outbox.enqueueWebhook(meetingID: b, event: "meeting.saved", body: Data("b".utf8), destination: "https://example.com/hook")
        await outbox.processDue()

        let reloaded = makeOutbox()
        XCTAssertEqual(reloaded.pending.count, 2)
        XCTAssertEqual(reloaded.pending.map(\.attempts), [1, 1])
        reloaded.removeAll(forMeeting: a)
        XCTAssertEqual(reloaded.pending.map(\.meetingID), [b])

        let again = makeOutbox()
        XCTAssertEqual(again.pending.map(\.meetingID), [b])
    }

    func testStatusLineDescribesWaitingDeliveries() {
        let outbox = makeOutbox()
        outbox.enqueueWebhook(meetingID: UUID(), event: "meeting.saved", body: Data("{}".utf8), destination: "https://example.com/hook")
        XCTAssertEqual(outbox.statusLine(for: .webhook), "1 waiting, next retry shortly")
        XCTAssertNil(outbox.statusLine(for: .attio))
    }
}
