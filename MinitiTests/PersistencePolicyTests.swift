import Foundation
import SwiftData
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// Roadmap P0.3: every user-initiated mutation reports failure once, reverts what it can,
/// and a fetch failure never masquerades as an empty history.
@MainActor
final class PersistencePolicyTests: XCTestCase {
    private struct InjectedSaveFailure: Error {}
    private struct InjectedFetchFailure: Error {}

    private var container: ModelContainer!
    private var context: ModelContext!
    private var state: AppState!
    private var events: [(name: String, details: [String: String])] = []

    override func setUp() async throws {
        container = try ModelContainer(
            for: Meeting.self, TranscriptSegment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        state = AppState()
        state.modelContext = context
        events = []
        state.diagnosticEventObserver = { [weak self] name, details in
            self?.events.append((name, details))
        }
    }

    override func tearDown() async throws {
        state = nil
        context = nil
        container = nil
    }

    private func savedMeeting(title: String = "saved", segments: [String] = ["hello there"], endTime: Date? = Date()) throws -> Meeting {
        let meeting = Meeting(title: title)
        meeting.endTime = endTime
        for (index, text) in segments.enumerated() {
            meeting.segments.append(TranscriptSegment(text: text, speaker: 0, timestamp: TimeInterval(index), isFinal: true))
        }
        context.insert(meeting)
        try context.save()
        return meeting
    }

    private func failSaves() {
        state.persistenceSaveHandler = { _ in throw InjectedSaveFailure() }
    }

    private func restoreSaves() {
        state.persistenceSaveHandler = { try $0.save() }
    }

    /// What a fresh context (i.e. the store) holds, ignoring unsaved changes on `mainContext`.
    private func persistedMeetings() throws -> [Meeting] {
        try ModelContext(container).fetch(FetchDescriptor<Meeting>())
    }

    private func failureEvents(op: PersistenceOperation, kind: PersistenceIssue.Kind) -> Int {
        events.filter { $0.name == "persistence_\(kind.rawValue)_failed" && $0.details["op"] == op.rawValue }.count
    }

    // MARK: commit

    func testSuccessfulCommitPersistsAndLeavesNoIssue() throws {
        let meeting = try savedMeeting()
        XCTAssertTrue(state.commit(.pin, mutate: { meeting.isPinned = true }, revert: { meeting.isPinned = false }))
        XCTAssertNil(state.persistenceIssue)
        XCTAssertEqual(try persistedMeetings().first?.isPinned, true)
        XCTAssertTrue(events.isEmpty)
    }

    func testPinFailureRevertsReportsOnceAndOffersRetry() throws {
        let meeting = try savedMeeting()
        failSaves()

        let ok = state.commit(.pin, mutate: { meeting.isPinned = true }, revert: { meeting.isPinned = false })

        XCTAssertFalse(ok)
        XCTAssertFalse(meeting.isPinned, "revert must undo the in-memory change")
        XCTAssertEqual(state.persistenceIssue?.operation, .pin)
        XCTAssertEqual(state.persistenceIssue?.kind, .save)
        XCTAssertEqual(state.persistenceIssue?.message, "pin didn't save")
        XCTAssertNotNil(state.persistenceRetryAction)
        XCTAssertEqual(failureEvents(op: .pin, kind: .save), 1)
        let details = events.first?.details ?? [:]
        XCTAssertNotNil(details["domain"])
        XCTAssertNotNil(details["code"])
        XCTAssertEqual(details.count, 3, "only op, domain, and code leave the process")
    }

    func testRetryAfterFailureClearsIssueAndPersists() throws {
        let meeting = try savedMeeting()
        failSaves()
        state.commit(.pin, mutate: { meeting.isPinned = true }, revert: { meeting.isPinned = false })
        XCTAssertNotNil(state.persistenceIssue)

        restoreSaves()
        state.retryPersistence()

        XCTAssertNil(state.persistenceIssue)
        XCTAssertNil(state.persistenceRetryAction)
        XCTAssertTrue(meeting.isPinned)
        XCTAssertEqual(try persistedMeetings().first?.isPinned, true)
    }

    func testRenameSpeakerEditAndTemplateChangeReport() throws {
        let meeting = try savedMeeting()
        failSaves()

        state.commit(.rename, mutate: { meeting.title = "renamed" })
        XCTAssertEqual(state.persistenceIssue?.message, "rename didn't save")

        state.commit(.speakerEdit, mutate: { meeting.setSpeakerName(id: "0", name: "Sam") })
        XCTAssertEqual(state.persistenceIssue?.message, "speaker change didn't save")

        state.commit(.templateChange, mutate: { meeting.templateSections = [:] })
        XCTAssertEqual(state.persistenceIssue?.operation, .templateChange)

        XCTAssertEqual(failureEvents(op: .rename, kind: .save), 1)
        XCTAssertEqual(failureEvents(op: .speakerEdit, kind: .save), 1)
        XCTAssertEqual(failureEvents(op: .templateChange, kind: .save), 1)
        XCTAssertEqual(try persistedMeetings().first?.title, "saved", "nothing reached the store")
    }

    func testDeleteFailureKeepsMeetingOnDiskUntilRetry() throws {
        let meeting = try savedMeeting()
        let meetingID = meeting.id
        failSaves()

        // No rollback: SwiftData traps when a pending cascade delete is rolled back, so the
        // delete stays pending in the context and is committed by the retry.
        let ok = state.commit(.delete, in: context, mutate: { [self] in
            state.noteMeetingDeleted(meeting)
            context.delete(meeting)
        })

        XCTAssertFalse(ok)
        XCTAssertTrue(state.isMeetingDeleted(meetingID), "in-flight saves must still not resurrect it")
        XCTAssertEqual(try persistedMeetings().count, 1, "nothing reached the store")
        XCTAssertEqual(state.persistenceIssue?.operation, .delete)
        XCTAssertEqual(state.persistenceIssue?.message, "delete didn't save yet. it goes through with the next successful save")
        XCTAssertNotNil(state.persistenceRetryAction)

        restoreSaves()
        state.retryPersistence()
        XCTAssertNil(state.persistenceIssue)
        XCTAssertEqual(try persistedMeetings().count, 0, "the retry commits the pending delete")
    }

    func testDeleteSuccessRemovesMeeting() throws {
        let meeting = try savedMeeting()
        let ok = state.commit(.delete, in: context, mutate: { [self] in
            state.noteMeetingDeleted(meeting)
            context.delete(meeting)
        })
        XCTAssertTrue(ok)
        XCTAssertEqual(try persistedMeetings().count, 0)
        XCTAssertNil(state.persistenceIssue)
    }

    func testDiscardCurrentMeetingFailureKeepsDraft() throws {
        let draft = try savedMeeting(title: "draft", endTime: nil)
        state.currentMeeting = draft
        failSaves()

        state.discardCurrentMeeting()

        XCTAssertNil(state.currentMeeting, "the session still clears")
        XCTAssertTrue(state.isMeetingDeleted(draft.id))
        XCTAssertEqual(try persistedMeetings().count, 1, "the draft stays on disk instead of vanishing")
        XCTAssertEqual(state.persistenceIssue?.operation, .discard)
        XCTAssertNotNil(state.persistenceRetryAction)

        restoreSaves()
        state.retryPersistence()
        XCTAssertNil(state.persistenceIssue)
        XCTAssertEqual(try persistedMeetings().count, 0)
    }

    func testTranscriptRestoreFailureReturnsFalseAndReports() throws {
        let meeting = try savedMeeting(segments: ["one", "two"])
        let snapshots = meeting.segments.map {
            TranscriptSegmentSnapshot(id: $0.id, speaker: $0.speaker, timestamp: $0.timestamp, text: $0.text.uppercased(), isFinal: $0.isFinal, confidence: $0.confidence, sourceRaw: $0.sourceRaw)
        }
        failSaves()

        XCTAssertFalse(state.restoreTranscriptSnapshots(snapshots, to: meeting))
        XCTAssertEqual(state.persistenceIssue?.operation, .transcriptRestore)
        XCTAssertEqual(failureEvents(op: .transcriptRestore, kind: .save), 1)
        XCTAssertEqual(Set(try persistedMeetings().first?.segments.map(\.text) ?? []), ["one", "two"])
    }

    func testCorrectionSaveFailedOutcomeIsNotSaved() {
        let outcome = AppState.DictionaryCorrectionOutcome.saveFailed
        XCTAssertFalse(outcome.isSaved)
        XCTAssertEqual(outcome.message(heard: "lightdash", fixEarlierMentions: true), "correction didn't save. try again")
    }

    func testStaleFinalizationFailureDoesNotPersistOrReportSessions() throws {
        let stale = try savedMeeting(title: "stale", segments: ["old words"], endTime: nil)
        stale.startTime = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        stale.managedSessionId = "sess_123"
        try context.save()
        failSaves()

        state.resumeInterruptedMeeting()

        XCTAssertNil(state.currentMeeting, "a stale draft is never resumed")
        XCTAssertEqual(state.persistenceIssue?.operation, .staleMeetingFinalize)
        XCTAssertNil(state.persistenceRetryAction, "the next launch retries finalization")
        XCTAssertEqual(failureEvents(op: .staleMeetingFinalize, kind: .save), 1)
        XCTAssertNil(try persistedMeetings().first?.endTime, "the finalization did not reach the store")
    }

    // MARK: load

    func testFetchFailureIsDistinctFromEmptyHistory() throws {
        _ = try savedMeeting()
        state.persistenceFetchHandler = { _, _ in throw InjectedFetchFailure() }

        let result = state.fetchMeetings(.historyLoad)

        XCTAssertNil(result, "nil means failed; an empty store returns []")
        XCTAssertEqual(state.persistenceIssue?.kind, .load)
        XCTAssertEqual(state.persistenceIssue?.message, "couldn't load your meetings")
        XCTAssertEqual(failureEvents(op: .historyLoad, kind: .load), 1)
        XCTAssertNil(state.persistenceRetryAction)
    }

    func testFetchSuccessOnEmptyStoreReturnsEmptyArray() {
        XCTAssertEqual(state.fetchMeetings(.historyLoad)?.count, 0)
        XCTAssertNil(state.persistenceIssue)
    }

    func testResumeInterruptedMeetingReportsFetchFailureInsteadOfSilence() throws {
        let draft = try savedMeeting(title: "recent draft", segments: ["still here"], endTime: nil)
        draft.startTime = Date().addingTimeInterval(-60)
        try context.save()
        state.persistenceFetchHandler = { _, _ in throw InjectedFetchFailure() }

        state.resumeInterruptedMeeting()

        XCTAssertNil(state.currentMeeting)
        XCTAssertEqual(state.persistenceIssue?.operation, .interruptedMeetingCheck)
        XCTAssertEqual(state.persistenceIssue?.kind, .load)
    }

    // MARK: live transcript queue

    func testLiveQueueFailureRaisesOneIssueAcrossTicksAndClearsOnSuccess() async throws {
        let meeting = Meeting(title: "live")
        state.currentMeeting = meeting
        state.liveSegments = [AppState.LiveSegment(id: UUID(), text: "first", speaker: 0, timestamp: 1, isFinal: true)]
        failSaves()

        let firstSave = await state.saveCurrentMeetingAndWait()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(state.persistenceIssue?.operation, .liveTranscript)
        XCTAssertNil(state.persistenceRetryAction, "the queue retries itself on the next checkpoint")
        let firstIssueID = state.persistenceIssue?.id

        state.liveSegments.append(AppState.LiveSegment(id: UUID(), text: "second", speaker: 0, timestamp: 2, isFinal: true))
        let secondSave = await state.saveCurrentMeetingAndWait()
        XCTAssertFalse(secondSave)
        state.liveSegments.append(AppState.LiveSegment(id: UUID(), text: "third", speaker: 0, timestamp: 3, isFinal: true))
        let thirdSave = await state.saveCurrentMeetingAndWait()
        XCTAssertFalse(thirdSave)

        XCTAssertEqual(state.persistenceIssue?.id, firstIssueID, "one banner per outage, not one per tick")
        XCTAssertEqual(failureEvents(op: .liveTranscript, kind: .save), 1)

        restoreSaves()
        let recoveredSave = await state.saveCurrentMeetingAndWait()
        XCTAssertTrue(recoveredSave)
        XCTAssertNil(state.persistenceIssue)
        XCTAssertEqual(Set(try persistedMeetings().first?.segments.map(\.text) ?? []), ["first", "second", "third"])
    }

    // MARK: issue lifecycle

    func testSuccessClearsOnlyTheSameOperation() throws {
        let meeting = try savedMeeting()
        failSaves()
        state.commit(.pin, mutate: { meeting.isPinned = true }, revert: { meeting.isPinned = false })
        restoreSaves()

        state.commit(.rename, mutate: { meeting.title = "other" })
        XCTAssertEqual(state.persistenceIssue?.operation, .pin, "an unrelated success keeps the pin issue visible")

        state.commit(.pin, mutate: { meeting.isPinned = true }, revert: { meeting.isPinned = false })
        XCTAssertNil(state.persistenceIssue)
    }

    func testDismissClearsIssueAndRetry() throws {
        let meeting = try savedMeeting()
        failSaves()
        state.commit(.pin, mutate: { meeting.isPinned = true }, revert: { meeting.isPinned = false })
        XCTAssertNotNil(state.persistenceRetryAction)

        state.dismissPersistenceIssue()

        XCTAssertNil(state.persistenceIssue)
        XCTAssertNil(state.persistenceRetryAction)
    }

    func testCommitWithoutContextReturnsFalseQuietly() {
        state.modelContext = nil
        XCTAssertFalse(state.commit(.pin, mutate: {}))
        XCTAssertNil(state.persistenceIssue, "no context is a wiring state, not a user-facing persistence failure")
        XCTAssertTrue(events.isEmpty)
    }

    func testEveryOperationHasALowercaseLabel() {
        for operation in PersistenceOperation.allCases {
            XCTAssertFalse(operation.userLabel.isEmpty)
            XCTAssertEqual(operation.userLabel, operation.userLabel.lowercased())
            XCTAssertEqual(PersistenceIssue(operation: operation, kind: .save).message, PersistenceIssue(operation: operation, kind: .save).message.lowercased())
        }
        XCTAssertTrue(PersistenceOperation.delete.isRetryable)
        XCTAssertFalse(PersistenceOperation.staleMeetingFinalize.isRetryable)
        XCTAssertFalse(PersistenceOperation.liveTranscript.isRetryable)
        XCTAssertTrue(PersistenceOperation.pin.isRetryable)
    }
}
