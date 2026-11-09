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

    func testCompletionCRMIsHeldUntilDurableAcknowledgementAndResumesOnce() async {
        let id = UUID(), meeting = UUID()
        let outbox = makeOutbox()
        XCTAssertTrue(outbox.stageCRM(.attio, meetingID: meeting, id: id))
        XCTAssertTrue(outbox.stageCRM(.attio, meetingID: meeting, id: id))
        let restored = makeOutbox()
        var sent = 0
        restored.register(.attio) { _ in sent += 1; return .delivered }
        await restored.processDue()
        XCTAssertEqual(sent, 0)
        XCTAssertTrue(restored.releaseCRM(id: id))
        await restored.processDue()
        XCTAssertEqual(sent, 1)
        XCTAssertFalse(restored.releaseCRM(id: id))
        await restored.processDue()
        XCTAssertEqual(sent, 1)
    }

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

    func testTerminalWebhookRequiresARebuiltBodyRatherThanRetryingNil() async {
        let outbox = makeOutbox()
        var calls = 0
        outbox.register(.webhook) { _ in calls += 1; return .retry(reason: "HTTP 500") }
        let meeting = UUID()
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.saved", body: Data("{}".utf8), destination: "https://example.com/hook")
        for delay in DeliveryOutbox.retryDelays {
            await outbox.processDue()
            advance(delay + 1)
        }
        await outbox.processDue()
        XCTAssertEqual(calls, 6)
        XCTAssertEqual(outbox.failed.count, 1)
        XCTAssertNil(outbox.failed.first?.body)
        let oldID = outbox.failed[0].id
        outbox.retryNow(.webhook)
        await outbox.processDue()
        XCTAssertEqual(calls, 6, "bodyless failures must not call the sender")
        let replacement = UUID()
        XCTAssertTrue(outbox.replaceFailedWebhook(id: oldID, replacementID: replacement, meetingID: meeting, event: "meeting.updated", body: Data("current saved data".utf8), destination: "https://example.com/hook"))
        outbox.register(.webhook) { item in
            calls += 1
            XCTAssertEqual(item.id, replacement)
            XCTAssertEqual(item.body, Data("current saved data".utf8))
            return .delivered
        }
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

    func testOldOutcomeCannotRemoveTheLatestSuccessor() async {
        for outcome in [DeliveryOutbox.Outcome.delivered, .retry(reason: "offline"), .reject(reason: "HTTP 400")] {
            let outbox = DeliveryOutbox(storeURL: storeURL.appendingPathExtension(UUID().uuidString), now: { self.clock })
            let meeting = UUID()
            let firstID = UUID(), secondID = UUID(), thirdID = UUID()
            var observed: [DeliveryOutbox.Item] = []
            outbox.register(.webhook) { item in
                observed.append(item)
                if item.id == firstID {
                    // Simulates a local commit while the sender owns its old snapshot.
                    XCTAssertTrue(outbox.enqueueWebhook(meetingID: meeting, event: "meeting.updated", body: Data("v2".utf8), destination: "https://example.com/hook", id: secondID))
                    await Task.yield()
                    XCTAssertTrue(outbox.enqueueWebhook(meetingID: meeting, event: "meeting.updated", body: Data("v3".utf8), destination: "https://example.com/hook", id: thirdID))
                    XCTAssertEqual(outbox.item(id: firstID)?.body, Data("v1".utf8))
                    XCTAssertNil(outbox.item(id: secondID), "only latest unattempted successor is retained")
                    return outcome
                }
                return .delivered
            }
            outbox.enqueueWebhook(meetingID: meeting, event: "meeting.updated", body: Data("v1".utf8), destination: "https://example.com/hook", id: firstID)
            await outbox.processDue()
            XCTAssertEqual(outbox.item(id: thirdID)?.body, Data("v3".utf8))
            await outbox.processDue()
            XCTAssertEqual(observed.map(\.id), [firstID, thirdID])
            XCTAssertEqual(observed.map(\.body), [Data("v1".utf8), Data("v3".utf8)])
            outbox.discardFailed()
        }
    }

    func testStagedHandoffSurvivesReloadAndDoesNotSendBeforeRelease() async {
        let id = UUID(), meeting = UUID()
        let outbox = makeOutbox()
        var calls = 0
        outbox.register(.webhook) { _ in calls += 1; return .delivered }
        XCTAssertTrue(outbox.stageWebhook(id: id, meetingID: meeting, event: "meeting.saved", body: Data("saved snapshot".utf8), destination: "https://example.com/hook"))
        await outbox.processDue()
        XCTAssertEqual(calls, 0)
        let restored = makeOutbox()
        XCTAssertEqual(restored.heldWebhooks.map(\.id), [id])
        XCTAssertTrue(restored.stageWebhook(id: id, meetingID: meeting, event: "meeting.saved", body: Data("saved snapshot".utf8), destination: "https://example.com/hook"))
        XCTAssertFalse(restored.stageWebhook(id: id, meetingID: meeting, event: "meeting.saved", body: Data("changed snapshot".utf8), destination: "https://example.com/hook"))
        XCTAssertEqual(restored.items.count, 1)
        restored.register(.webhook) { item in
            calls += 1; XCTAssertEqual(item.id, id); XCTAssertEqual(item.body, Data("saved snapshot".utf8)); return .delivered
        }
        XCTAssertTrue(restored.releaseWebhook(id: id))
        XCTAssertTrue(restored.releaseWebhook(id: id), "releasing an already released pending row is idempotent")
        await restored.processDue()
        XCTAssertEqual(calls, 1)
        XCTAssertNil(makeOutbox().item(id: id))
    }

    func testLostResponseRetriesTheSameIdentityAndBodyAfterReload() async {
        let id = UUID(), meeting = UUID()
        let outbox = makeOutbox()
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.saved", body: Data("snapshot".utf8), destination: "https://example.com/hook", id: id)
        outbox.register(.webhook) { _ in .retry(reason: "network timeout") }
        await outbox.processDue()
        advance(31)
        let restored = makeOutbox()
        XCTAssertEqual(restored.item(id: id)?.hasBeenAttempted, true)
        restored.register(.webhook) { item in
            XCTAssertEqual(item.id, id); XCTAssertEqual(item.body, Data("snapshot".utf8)); return .delivered
        }
        await restored.processDue()
        XCTAssertTrue(restored.items.isEmpty)
    }

    func testHeldSavedDoesNotBlockUpdatedDelivery() async {
        let outbox = makeOutbox(), meeting = UUID(), initialID = UUID()
        var events: [String] = []
        outbox.stageWebhook(id: initialID, meetingID: meeting, event: "meeting.saved", body: Data("initial".utf8), destination: "https://example.com/hook")
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.updated", body: Data("update".utf8), destination: "https://example.com/hook")
        outbox.register(.webhook) { item in events.append(item.event); return .delivered }
        await outbox.processDue()
        XCTAssertEqual(events, ["meeting.updated"])
        XCTAssertTrue(outbox.releaseWebhook(id: initialID))
        await outbox.processDue()
        XCTAssertEqual(events, ["meeting.updated", "meeting.saved"])
    }

    func testReleasedSavedStillBlocksUpdatedUntilDelivered() async {
        let outbox = makeOutbox(), meeting = UUID()
        var events: [String] = []
        var failSaved = true
        outbox.register(.webhook) { item in
            events.append(item.event)
            return item.event == "meeting.saved" && failSaved ? .retry(reason: "offline") : .delivered
        }
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.saved", body: Data("saved".utf8), destination: "https://example.com/hook")
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.updated", body: Data("update".utf8), destination: "https://example.com/hook")
        await outbox.processDue()
        XCTAssertEqual(events, ["meeting.saved"])
        XCTAssertEqual(outbox.nextProcessingAt, clock.addingTimeInterval(30))
        advance(30); failSaved = false
        await outbox.processDue()
        XCTAssertEqual(events, ["meeting.saved", "meeting.saved", "meeting.updated"])
    }

    func testHeldRowExpiresWithoutSenderAndCannotBeReleasedOrRestaged() async {
        let outbox = makeOutbox(), id = UUID(), meeting = UUID()
        let body = Data("sensitive transcript".utf8)
        XCTAssertTrue(outbox.stageWebhook(id: id, meetingID: meeting, event: "meeting.saved", body: body, destination: "https://example.com/hook"))
        XCTAssertEqual(outbox.nextProcessingAt, clock.addingTimeInterval(DeliveryOutbox.maxAge), "held-only queue wakes for expiry, not every second")
        advance(DeliveryOutbox.maxAge)
        await outbox.processDue()
        let expired = outbox.item(id: id)
        XCTAssertEqual(expired?.state, .failed)
        XCTAssertEqual(expired?.lastError, "Delivery expired")
        XCTAssertNil(expired?.body)
        XCTAssertNil(makeOutbox().item(id: id)?.body, "expiry is durable")
        XCTAssertFalse(outbox.releaseWebhook(id: id))
        XCTAssertFalse(outbox.stageWebhook(id: id, meetingID: meeting, event: "meeting.saved", body: body, destination: "https://example.com/hook"))
        XCTAssertNil(outbox.nextProcessingAt, "terminal queue has no retry loop")
        XCTAssertEqual(outbox.statusLine(for: .webhook), "1 failed: Delivery expired")
    }

    func testHeldOnlyQueueExpiresFromItsTimerWithoutAKickOrSender() async throws {
        let outbox = DeliveryOutbox(storeURL: storeURL)
        let id = UUID()
        XCTAssertTrue(outbox.stageWebhook(id: id, meetingID: UUID(), event: "meeting.saved", body: Data("body".utf8), destination: "https://example.com/hook", createdAt: Date().addingTimeInterval(-DeliveryOutbox.maxAge + 0.1)))
        try await TestSupport.waitUntil(timeout: 5) { outbox.item(id: id)?.state == .failed }
        XCTAssertNil(outbox.item(id: id)?.body)
        XCTAssertNil(outbox.nextProcessingAt)
    }

    func testReleaseChecksExpiryBeforeAnyProcessingPass() {
        let outbox = makeOutbox(), id = UUID()
        outbox.stageWebhook(id: id, meetingID: UUID(), event: "meeting.saved", body: Data("body".utf8), destination: "https://example.com/hook")
        advance(DeliveryOutbox.maxAge)
        XCTAssertFalse(outbox.releaseWebhook(id: id))
        XCTAssertEqual(outbox.item(id: id)?.state, .failed)
        XCTAssertNil(outbox.item(id: id)?.body)
    }

    func testStagingAnAlreadyExpiredMarkerNeverPersistsItsBody() {
        let outbox = makeOutbox(), id = UUID()
        XCTAssertTrue(outbox.stageWebhook(id: id, meetingID: UUID(), event: "meeting.saved", body: Data("body".utf8), destination: "https://example.com/hook", createdAt: clock.addingTimeInterval(-DeliveryOutbox.maxAge)))
        XCTAssertEqual(outbox.item(id: id)?.state, .failed)
        XCTAssertNil(makeOutbox().item(id: id)?.body)
    }

    func testHeldStatusDoesNotInventABlockingReason() {
        let outbox = makeOutbox()
        outbox.stageWebhook(id: UUID(), meetingID: UUID(), event: "meeting.saved", body: Data(), destination: "https://example.com/hook")
        XCTAssertEqual(outbox.statusLine(for: .webhook, hasBlockingReason: true), "1 waiting")
        XCTAssertEqual(outbox.statusLine(for: .webhook), "1 waiting")
    }

    func testOldPassDoesNotSendARowRemovedDuringAnAwait() async {
        let outbox = makeOutbox(), a = UUID(), b = UUID()
        var meetings: [UUID] = []
        outbox.enqueueWebhook(meetingID: a, event: "meeting.saved", body: Data("a".utf8), destination: "https://example.com/hook")
        outbox.enqueueWebhook(meetingID: b, event: "meeting.saved", body: Data("b".utf8), destination: "https://example.com/hook")
        outbox.register(.webhook) { item in
            meetings.append(item.meetingID)
            outbox.removeAll(forMeeting: b)
            await Task.yield()
            return .delivered
        }
        await outbox.processDue()
        XCTAssertEqual(meetings, [a])
    }

    func testFailedDiskWriteDoesNotAcknowledgeEnqueueOrReplacement() async {
        var fail = false
        let outbox = DeliveryOutbox(storeURL: storeURL, now: { self.clock }, writeStore: { data, url in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let meeting = UUID(), id = UUID()
        fail = true
        XCTAssertFalse(outbox.stageWebhook(id: id, meetingID: meeting, event: "meeting.saved", body: Data("v1".utf8), destination: "https://example.com/hook"))
        XCTAssertTrue(outbox.items.isEmpty)
        XCTAssertTrue(outbox.hasStorageFailure)
        fail = false
        XCTAssertTrue(outbox.enqueueWebhook(meetingID: meeting, event: "meeting.saved", body: Data("v1".utf8), destination: "https://example.com/hook", id: id))
        outbox.register(.webhook) { _ in .reject(reason: "HTTP 404") }
        await outbox.processDue()
        fail = true
        XCTAssertFalse(outbox.replaceFailedWebhook(id: id, replacementID: UUID(), meetingID: meeting, event: "meeting.updated", body: Data("new".utf8), destination: "https://example.com/hook"))
        XCTAssertEqual(outbox.failed.map(\.id), [id])
        XCTAssertNotNil(outbox.persistenceError)
    }

    func testFailedSettlementRetainsOriginalIdentityForRecovery() async {
        var fail = false
        let outbox = DeliveryOutbox(storeURL: storeURL, now: { self.clock }, writeStore: { data, url in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let id = UUID()
        outbox.enqueueWebhook(meetingID: UUID(), event: "meeting.saved", body: Data("v1".utf8), destination: "https://example.com/hook", id: id)
        outbox.register(.webhook) { _ in fail = true; return .delivered }
        await outbox.processDue()
        XCTAssertEqual(outbox.pending.map(\.id), [id])
        XCTAssertTrue(outbox.hasStorageFailure)
        XCTAssertEqual(makeOutbox().pending.first?.id, id, "an uncertain delivery reuses its durable identity")
    }

    func testLegacyRowsDecodeAndExpiredBodyIsNotSent() async throws {
        let outbox = makeOutbox()
        let id = UUID()
        outbox.enqueueWebhook(meetingID: UUID(), event: "meeting.saved", body: Data("legacy".utf8), destination: "https://example.com/hook", id: id)
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: storeURL)) as? [[String: Any]])
        rows[0].removeValue(forKey: "held"); rows[0].removeValue(forKey: "hasBeenAttempted")
        try JSONSerialization.data(withJSONObject: rows).write(to: storeURL)
        advance(DeliveryOutbox.maxAge + 1)
        let legacy = makeOutbox()
        var sent = false
        legacy.register(.webhook) { _ in sent = true; return .delivered }
        await legacy.processDue()
        XCTAssertFalse(sent)
        XCTAssertEqual(legacy.failed.first?.lastError, "Delivery expired")
        XCTAssertNil(legacy.failed.first?.body)
    }

    func testCorruptStoreIsReportedAndNeverOverwrittenAsAnEmptyQueue() throws {
        let original = Data("not valid queue data".utf8)
        try original.write(to: storeURL)
        let outbox = makeOutbox()
        XCTAssertTrue(outbox.hasStorageFailure)
        XCTAssertFalse(outbox.enqueueWebhook(meetingID: UUID(), event: "meeting.saved", body: Data("new".utf8), destination: "https://example.com/hook"))
        XCTAssertEqual(try Data(contentsOf: storeURL), original)
    }


    func testHeldReleaseRetriesTransientStorageFailureWithoutBypassingCorruptLoad() async {
        var fail = false
        let outbox = DeliveryOutbox(storeURL: storeURL, now: { self.clock }, writeStore: { data, url in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let id = UUID()
        XCTAssertTrue(outbox.stageWebhook(id: id, meetingID: UUID(), event: "meeting.saved", body: Data("snapshot".utf8), destination: "https://example.com/hook"))
        fail = true
        XCTAssertFalse(outbox.releaseWebhook(id: id))
        XCTAssertEqual(outbox.item(id: id)?.held, true)
        XCTAssertTrue(outbox.isStoreReadable)
        fail = false
        XCTAssertTrue(outbox.retryStorage())
        XCTAssertFalse(outbox.hasStorageFailure)
        XCTAssertTrue(outbox.releaseWebhook(id: id))
        outbox.register(.webhook) { _ in .delivered }
        await outbox.processDue()
        XCTAssertTrue(outbox.items.isEmpty)
        try? Data("broken".utf8).write(to: storeURL)
        let corrupt = makeOutbox()
        XCTAssertFalse(corrupt.isStoreReadable)
        XCTAssertFalse(corrupt.retryStorage())
    }


    func testCurrentDataResendResolvesAllFailuresForMeetingAtomically() async {
        var fail = false
        let outbox = DeliveryOutbox(storeURL: storeURL, now: { self.clock }, writeStore: { data, url in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let meeting = UUID(), otherMeeting = UUID()
        let first = UUID(), second = UUID(), replacement = UUID()
        outbox.register(.webhook) { _ in .reject(reason: "HTTP 400") }
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.saved", body: Data("old saved".utf8), destination: "https://example.com/hook", id: first)
        await outbox.processDue()
        outbox.enqueueWebhook(meetingID: meeting, event: "meeting.updated", body: Data("old update".utf8), destination: "https://example.com/hook", id: second)
        outbox.enqueueWebhook(meetingID: otherMeeting, event: "meeting.saved", body: Data("other".utf8), destination: "https://example.com/hook")
        await outbox.processDue()
        XCTAssertEqual(outbox.failed.count, 3)
        fail = true
        XCTAssertFalse(outbox.replaceFailedWebhook(id: first, replacementID: replacement, meetingID: meeting, event: "meeting.updated", body: Data("current".utf8), destination: "https://example.com/hook"))
        XCTAssertEqual(outbox.failed.count, 3, "failed persistence resolves nothing")
        fail = false
        XCTAssertTrue(outbox.replaceFailedWebhook(id: first, replacementID: replacement, meetingID: meeting, event: "meeting.updated", body: Data("current".utf8), destination: "https://example.com/hook"))
        XCTAssertEqual(outbox.failed.map(\.meetingID), [otherMeeting])
        XCTAssertEqual(outbox.pending.map(\.id), [replacement])
        XCTAssertFalse(outbox.replaceFailedWebhook(id: second, replacementID: UUID(), meetingID: meeting, event: "meeting.updated", body: Data("current".utf8), destination: "https://example.com/hook"), "another old failure cannot create a second replacement")
        XCTAssertEqual(outbox.pending.map(\.id), [replacement])
    }

}
