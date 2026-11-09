import Foundation
import SwiftData
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// Roadmap P0.6: the user journeys the UI depends on, driven at the `AppState` level with an
/// in-memory store and a stubbed backend. Audio capture and the Deepgram socket are the
/// manual boundary (see docs/reference/testing.md); everything after "final segments arrived" runs here.
@MainActor
final class MeetingJourneyTests: XCTestCase {
    private var container: ModelContainer!
    private var session: URLSession!
    private var savedDefaults: [String: Any] = [:]
    private let keys = ["appMode", "acceptedTermsVersion", "privateMode", "webhookURL", "autoExportMarkdown", "autoInferSpeakerNames"]

    override func setUp() async throws {
        for key in keys { if let value = UserDefaults.standard.object(forKey: key) { savedDefaults[key] = value } }
        StubURLProtocol.reset()
        container = try TestSupport.makeInMemoryContainer()
        session = TestSupport.stubbedSession()
        // The backend is down for the whole journey: insights and naming requests fail and
        // the meeting must still be saved and reachable.
        StubURLProtocol.script = { _ in StubURLProtocol.json(500, #"{"error": "internal_error", "message": "down"}"#) }
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
        container = nil
        for key in keys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    private func makeState() -> AppState {
        let state = AppState()
        state.modelContext = container.mainContext
        state.appModeRaw = AppMode.managed.rawValue
        state.hasAcceptedTerms = true
        state.privateModeEnabled = false
        state.webhookURL = ""
        state.autoInferSpeakerNames = false
        #if os(macOS)
        state.autoExportMarkdown = false
        #endif
        let auth = TestSupport.enrolledAuthManager(session: session)
        state.clientAuthManager = auth
        state.minitiAPIService = MinitiAPIService(session: session, auth: auth)
        state.insightsService = InsightsService(session: session)
        return state
    }

    private func segment(_ text: String, speaker: Int = 0, at timestamp: TimeInterval) -> AppState.LiveSegment {
        AppState.LiveSegment(id: UUID(), text: text, speaker: speaker, timestamp: timestamp, isFinal: true)
    }

    private func persistedMeetings() throws -> [Meeting] {
        try ModelContext(container).fetch(FetchDescriptor<Meeting>())
    }

    #if os(macOS)
    func testIdleHardwareTimeoutExplainsFailureAndBlocksStartBeforeGrant() async throws {
        let state = makeState()
        let worker = AudioHardwareExecutor(timeout: 0.1)
        let capture = AudioCaptureService(microphoneStart: {}, systemAudioStart: {}, hardware: worker)
        state.audioCaptureService = capture
        capture.onHardwareFailure = { [weak state] in state?.handleCaptureHardwareFailure() }
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        do { try await worker.run { release.wait() } } catch AudioHardwareExecutor.Failure.unresponsive { }
        try await TestSupport.waitUntil { state.recordingErrorMessage != nil }
        XCTAssertFalse(state.canStartRecording)
        XCTAssertFalse(state.startNewMeeting())
        XCTAssertNil(state.currentMeeting)
        XCTAssertNil(state.managedSessionJournal.active)
        XCTAssertTrue(state.recordingErrorMessage?.contains("Quit and reopen") == true)
        state.dismissRecordingError()
        XCTAssertNotNil(state.recordingUnavailableReason, "Disabled control must retain its explanation")
        state.currentMeeting = Meeting(title: "Resume")
        state.isStartingMeeting = true; state.isResumingRecording = true
        await state.startManagedRecording()
        XCTAssertFalse(state.isStartingMeeting)
        XCTAssertFalse(state.isResumingRecording)
        state.startRecording()
        XCTAssertFalse(state.isRecording)
        XCTAssertNil(state.managedSessionJournal.active)
    }

    func testHardwareTimeoutStopsAndSavesWhileTheHardwareWorkerRemainsBlocked() async throws {
        let state = makeState()
        let worker = AudioHardwareExecutor(timeout: 0.1)
        let capture = AudioCaptureService(microphoneStart: {}, systemAudioStart: {}, hardware: worker)
        state.audioCaptureService = capture
        capture.onHardwareFailure = { [weak state] in state?.handleCaptureHardwareFailure() }
        try await capture.startCapture(microphone: true, systemAudio: true)
        let meeting = Meeting(title: "hardware timeout")
        state.currentMeeting = meeting
        state.isRecording = true
        state.liveSegments = [segment("Keep these words", at: 1)]
        let report = ManagedSessionReport(deviceId: "device", sessionId: "session", durationMinutes: 1,
                                         accountID: "owner", accountingVersion: 1)
        try await state.managedSessionJournal.begin(report)
        state.managedSessionJournal.captureBegan()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let entered = expectation(description: "hardware call blocked")
        let blocked = Task {
            try await worker.run { entered.fulfill(); release.wait() }
        }
        await fulfillment(of: [entered], timeout: 2)
        do { try await blocked.value; XCTFail("expected hardware deadline") }
        catch AudioHardwareExecutor.Failure.unresponsive { }
        try await TestSupport.waitUntil { !state.isRecording && !state.isFinalizingMeeting }
        XCTAssertFalse(capture.isCapturing)
        XCTAssertNil(state.managedSessionJournal.active)
        XCTAssertEqual(state.managedSessionJournal.pending.first?.sessionId, report.sessionId)
        XCTAssertEqual(state.managedSessionJournal.pending.first?.meetingId, meeting.id)
        XCTAssertEqual(try persistedMeetings().first?.segments.map(\.text), ["Keep these words"])
        XCTAssertTrue(state.recordingErrorMessage?.contains("Quit and reopen miniti") == true)
        // The semaphore remains held until teardown: saving never waits for the OS call.
    }
    #endif

    // MARK: record → stop → save → history

    func testStopAfterTranscriptSavesTheMeetingIntoHistory() async throws {
        let state = makeState()
        let meeting = Meeting(title: "journey")
        state.currentMeeting = meeting
        state.isRecording = true
        state.liveSegments = [segment("we agreed on the launch date", at: 1), segment("and the pricing page", speaker: 1, at: 4)]

        state.stopRecording()

        XCTAssertFalse(state.isRecording)
        try await TestSupport.waitUntil(timeout: 15) { !state.isFinalizingMeeting && state.finalizingInsightMeetingIDs.isEmpty }

        let saved = try persistedMeetings()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.id, meeting.id)
        XCTAssertNotNil(saved.first?.endTime, "a stopped meeting is finalized on disk")
        XCTAssertEqual(saved.first?.segments.sorted { $0.timestamp < $1.timestamp }.map(\.text), ["we agreed on the launch date", "and the pricing page"])
        XCTAssertNil(state.persistenceIssue)

        // History reads it back through the same policy the sidebar uses.
        let history = state.fetchMeetings(.historyLoad)
        XCTAssertEqual(history?.map(\.id), [meeting.id])
        XCTAssertFalse(StubURLProtocol.requests.isEmpty, "final insights were attempted against the backend")
    }

    func testStopCompletesInPlaceWithoutDoneAndExportsAreCheckpointedOnce() async throws {
        let state = makeState()
        let meeting = Meeting(title: "Saved result")
        state.currentMeeting = meeting; state.isRecording = true
        state.liveSegments = [segment("final saved words", at: 2)]
        state.stopRecording()
        state.stopRecording() // manual/automatic Stop race
        try await TestSupport.waitUntil(timeout: 15) { !state.isFinalizingMeeting && state.finalizingInsightMeetingIDs.isEmpty }
        XCTAssertTrue(state.currentMeeting === meeting, "Selection and review stay on the same result")
        XCTAssertEqual(try persistedMeetings().count, 1)
        XCTAssertNotNil(meeting.automaticCompletionID)
        XCTAssertEqual(meeting.automaticCompletionExportedAt, meeting.endTime)
        let completion = meeting.automaticCompletionID
        state.completeSavedMeetingExports(meeting)
        state.goHome()
        XCTAssertEqual(meeting.automaticCompletionID, completion)
        XCTAssertEqual(try persistedMeetings().count, 1)
        XCTAssertNil(state.currentMeeting)
        XCTAssertEqual(try persistedMeetings()[0].segments.first?.text, "final saved words")
    }

    func testLaunchCompletionStagesCRMBeforeCalendarConnectionCheckFinishes() throws {
        let state = makeState()
        state.isGoogleCalendarConnected = false
        state.autoAttioSync = true; state.autoTwentySync = true
        let meeting = Meeting(title: "Recovered", endTime: Date())
        meeting.attendees = [MeetingAttendee(email: "guest@customer.example", displayName: nil, domain: "customer.example", responseStatus: "accepted", isOrganizer: false, isSelf: false)]
        meeting.automaticCompletionID = UUID()
        meeting.automaticCompletionOwner = state.automaticCompletionOwner
        container.mainContext.insert(meeting); try container.mainContext.save()
        state.completeSavedMeetingExports(meeting)
        let queued = state.deliveryOutbox.items.filter { $0.meetingID == meeting.id }
        XCTAssertEqual(Set(queued.map(\.kind)), Set([.attio, .twenty]))
        XCTAssertEqual(meeting.automaticCompletionExportedAt, meeting.endTime)
        state.completeSavedMeetingExports(meeting)
        XCTAssertEqual(state.deliveryOutbox.items.filter { $0.meetingID == meeting.id }.count, 2)
    }

    func testCompletionCheckpointSaveFailureRetriesWithoutNeedingNavigation() throws {
        let state = makeState()
        let meeting = Meeting(title: "Checkpoint", endTime: Date())
        meeting.automaticCompletionID = UUID()
        meeting.automaticCompletionOwner = state.automaticCompletionOwner
        container.mainContext.insert(meeting); try container.mainContext.save()
        state.persistenceSaveHandler = { _ in throw NSError(domain: "synthetic-disk", code: 1) }
        state.completeSavedMeetingExports(meeting)
        XCTAssertNil(meeting.automaticCompletionExportedAt)
        XCTAssertNotNil(state.persistenceIssue)
        state.persistenceSaveHandler = { try $0.save() }
        state.retryPersistence()
        XCTAssertEqual(meeting.automaticCompletionExportedAt, meeting.endTime)
        XCTAssertNil(state.persistenceIssue)
    }

    func testStopWithNoContentDrainsThenSavesNothing() async throws {
        let state = makeState()
        state.currentMeeting = Meeting(title: "empty")
        state.isRecording = true
        state.liveSegments = []

        state.stopRecording()

        XCTAssertFalse(state.isRecording)
        XCTAssertTrue(state.isFinalizingMeeting)
        try await TestSupport.waitUntil { !state.isFinalizingMeeting }
        XCTAssertEqual(state.finalizationStatusText, "Saved automatically")
        XCTAssertTrue(try persistedMeetings().isEmpty)
    }

    // MARK: kill mid-meeting → relaunch → resume

    func testInterruptedMeetingIsResumedByAFreshLaunch() async throws {
        let first = makeState()
        let meeting = Meeting(title: "interrupted")
        first.currentMeeting = meeting
        first.liveSegments = [segment("first thought", at: 1), segment("second thought", at: 3)]
        let saved = await first.saveCurrentMeetingAndWait()
        XCTAssertTrue(saved)
        XCTAssertNil(try persistedMeetings().first?.endTime, "still a draft on disk")

        // A new AppState on the same store stands in for the relaunch after a hard kill.
        let relaunch = makeState()
        relaunch.resumeInterruptedMeeting()

        XCTAssertEqual(relaunch.currentMeeting?.id, meeting.id)
        XCTAssertEqual(relaunch.liveSegments.map(\.text), ["first thought", "second thought"])
        XCTAssertNil(relaunch.persistenceIssue)
        XCTAssertNotNil(meeting.endTime)
        XCTAssertNil(meeting.automaticCompletionID, "Recovery is not explicit recording completion")
        relaunch.reconcileAutomaticCompletions()
        XCTAssertNil(meeting.automaticCompletionExportedAt)
    }

    func testRecoveringResumedAndStaleDraftsCannotSendPendingCompletion() async throws {
        for stale in [false, true] {
            let first = makeState()
            let meeting = Meeting(title: "Previously stopped", startTime: Date().addingTimeInterval(stale ? -86400 : -20))
            meeting.automaticCompletionID = UUID()
            meeting.automaticCompletionOwner = first.automaticCompletionOwner
            meeting.automaticCompletionMarkdownRequested = true
            first.currentMeeting = meeting
            first.liveSegments = [segment("resumed draft content", at: 1)]
            let saved = await first.saveCurrentMeetingAndWait()
            XCTAssertTrue(saved)
            let relaunch = makeState()
            relaunch.resumeInterruptedMeeting()
            relaunch.reconcileAutomaticCompletions()
            XCTAssertEqual(meeting.automaticCompletionSuspended, true)
            XCTAssertNil(meeting.automaticCompletionExportedAt)
            XCTAssertNil(meeting.automaticCompletionMarkdownExportedAt)
            if !stale {
                relaunch.isRecording = true
                relaunch.stopRecording()
                // Capture finalization ends before saved AI/export completion settles.
                try await TestSupport.waitUntil(timeout: 15) {
                    !relaunch.isFinalizingMeeting && meeting.automaticCompletionExportedAt != nil
                }
                XCTAssertEqual(meeting.automaticCompletionSuspended, false)
                XCTAssertNotNil(meeting.automaticCompletionExportedAt)
            }
        }
    }

    // MARK: pin survives relaunch

    func testPinSurvivesRelaunchAndSortsFirst() async throws {
        let first = makeState()
        let older = Meeting(title: "older", startTime: Date().addingTimeInterval(-3600), endTime: Date().addingTimeInterval(-3000))
        let newer = Meeting(title: "newer", startTime: Date().addingTimeInterval(-600), endTime: Date())
        container.mainContext.insert(older)
        container.mainContext.insert(newer)
        try container.mainContext.save()

        XCTAssertTrue(first.commit(.pin, mutate: { older.isPinned = true }, revert: { older.isPinned = false }))

        let relaunch = makeState()
        let history = try XCTUnwrap(relaunch.fetchMeetings(.historyLoad))
        let pinned = history.filter(\.isPinned)
        XCTAssertEqual(pinned.map(\.title), ["older"])
        XCTAssertEqual(history.count, 2)
    }

    // MARK: Settings search catalog round trip

    func testSettingsSearchCatalogFindsRecoveryKeyOnThisPlatform() {
        #if os(macOS)
        let catalog = SettingsSearchCatalog.availableItems(on: .macOS, appMode: .managed)
        #else
        let catalog = SettingsSearchCatalog.availableItems(on: .iOS, appMode: .managed)
        #endif
        XCTAssertFalse(catalog.isEmpty)
        let hit = catalog.first { $0.id == "account.recoveryKey" }
        XCTAssertNotNil(hit, "the recovery-key entry is the deep link the Home nudge and screenshots rely on")
    }
}

@MainActor
final class SavedMeetingDeliveryTests: XCTestCase {
    var container: ModelContainer!
    var state: AppState!
    var savedDefaults: [String: Any] = [:]
    let keys = ["appMode", "acceptedTermsVersion", "privateMode", "webhookURL", "autoExportMarkdown", "docsMCPURL", "autoInferSpeakerNames", "salesInsightsEnabled", "templateInsightsEnabled", "playbookInsightsEnabled", "insightTemplateID"]

    override func setUp() async throws {
        for key in keys { if let value = UserDefaults.standard.object(forKey: key) { savedDefaults[key] = value } }
        StubURLProtocol.reset()
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, #"{"summary":"fresh summary","action_items":["ship"],"topics":["release"],"questions":[]}"#) }
        container = try TestSupport.makeInMemoryContainer()
        let session = TestSupport.stubbedSession()
        let auth = TestSupport.enrolledAuthManager(session: session)
        state = AppState()
        state.clientAuthManager = auth
        state.appModeRaw = AppMode.managed.rawValue
        state.hasAcceptedTerms = true
        state.privateModeEnabled = false
        state.webhookURL = "https://receiver.example/hook"
        #if os(macOS)
        state.autoExportMarkdown = false
        #endif
        state.autoInferSpeakerNames = false
        state.minitiAPIService = MinitiAPIService(session: session, auth: auth)
        state.deliveryOutbox = DeliveryOutbox(storeURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        state.modelContext = container.mainContext
        state.insightsMode = .standard
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
        for key in keys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        state = nil
    }

    func meeting() throws -> Meeting {
        let meeting = Meeting(title: "saved", endTime: Date())
        meeting.segments = [TranscriptSegment(text: "we agreed to ship on Friday", speaker: 0, timestamp: 1, isFinal: true)]
        container.mainContext.insert(meeting)
        try container.mainContext.save()
        return meeting
    }

    func body(_ item: DeliveryOutbox.Item) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(item.body)) as? [String: Any])
    }

    func testHistoryResponseAfterTrimDoesNotRestoreInsightsOrExport() async throws {
        let meeting = try meeting()
        StubURLProtocol.delay = 0.15
        let task = Task { await state.generateInsightsForMeeting(meeting) }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        meeting.segments[0].text = "redacted"
        meeting.markTranscriptEdited()
        try container.mainContext.save()
        await task.value
        XCTAssertNil(meeting.summaryText)
        XCTAssertNil(meeting.insightsUpdatedAt)
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
    }

    func testOlderHistoryCompletionCannotClearNewerSpinnerOrResult() async throws {
        let meeting = try meeting()
        StubURLProtocol.delay = 0.12
        let first = Task { await state.generateInsightsForMeeting(meeting) }
        try await TestSupport.waitUntil { StubURLProtocol.requests.count == 1 }
        StubURLProtocol.delay = 0.4
        let second = Task { await state.generateInsightsForMeeting(meeting) }
        try await TestSupport.waitUntil { StubURLProtocol.requests.count == 2 }
        await first.value
        XCTAssertTrue(state.isGeneratingInsights)
        XCTAssertNil(meeting.summaryText)
        await second.value
        XCTAssertFalse(state.isGeneratingInsights)
        XCTAssertEqual(meeting.summaryText, "fresh summary")
        XCTAssertEqual(state.deliveryOutbox.items.count, 1)
    }

    func testHistorySaveFailureDoesNotStampFreshnessOrExport() async throws {
        let meeting = try meeting()
        state.persistenceSaveHandler = { _ in throw CocoaError(.fileWriteUnknown) }
        await state.generateInsightsForMeeting(meeting)
        XCTAssertNil(meeting.summaryText)
        XCTAssertNil(meeting.insightsUpdatedAt)
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
        XCTAssertNotNil(state.persistenceIssue)
    }

    func testFinalCompletionWhileSelectedContainsTranscriptAndSummary() async throws {
        let meeting = try meeting()
        state.currentMeeting = meeting
        await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: false)
        let item = try XCTUnwrap(state.deliveryOutbox.items.first)
        XCTAssertEqual(item.event, "meeting.saved")
        XCTAssertEqual(meeting.webhookCompletion?.phase, .handedOff)
        let json = try body(item)
        let payload = try XCTUnwrap(json["meeting"] as? [String: Any])
        XCTAssertEqual(payload["summary"] as? String, "fresh summary")
        XCTAssertEqual((payload["transcript"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((json["processing"] as? [String: Any])?["state"] as? String, "complete")
    }

    func testHomeWhileFinalAIHeldSendsNoEarlyWebhook() async throws {
        let meeting = try meeting()
        state.currentMeeting = meeting
        state.liveSegments = [AppState.LiveSegment(id: meeting.segments[0].id, text: meeting.segments[0].text, speaker: 0, timestamp: 1, isFinal: true)]
        StubURLProtocol.delay = 0.15
        let task = Task { await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: false) }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        state.goHome()
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
        await task.value
        XCTAssertEqual(state.deliveryOutbox.items.map(\.event), ["meeting.saved"])
        XCTAssertEqual(meeting.summaryText, "fresh summary")
    }

    func testSkippedAndFailedAIStillDeliverSavedTranscript() async throws {
        for skip in [true, false] {
            let meeting = try meeting()
            state.privateModeEnabled = skip
            StubURLProtocol.script = { _ in StubURLProtocol.json(400, #"{"error":"invalid_request","message":"refused"}"#) }
            await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: false)
            let item = try XCTUnwrap(state.deliveryOutbox.items.first { $0.meetingID == meeting.id })
            let json = try body(item)
            XCTAssertEqual((json["processing"] as? [String: Any])?["state"] as? String, skip ? "skipped" : "failed")
            XCTAssertEqual(((json["meeting"] as? [String: Any])?["transcript"] as? [[String: Any]])?.count, 1)
        }
    }

    func testHeldHandoffRecoversAfterAcknowledgmentSaveFails() throws {
        let meeting = try meeting()
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        var saves = 0
        state.persistenceSaveHandler = { context in
            saves += 1
            if saves == 2 { throw CocoaError(.fileWriteUnknown) }
            try context.save()
        }
        state.settleMeetingCompletion(meeting, id: id, outcomes: ["standard": .complete], interrupted: false)
        XCTAssertEqual(state.deliveryOutbox.item(id: id)?.held, true)
        XCTAssertEqual(meeting.webhookCompletion?.phase, .ready)
        state.persistenceSaveHandler = { try $0.save() }
        state.retryPersistence()
        XCTAssertEqual(meeting.webhookCompletion?.phase, .handedOff)
        XCTAssertEqual(state.deliveryOutbox.item(id: id)?.held, false)
        state.reconcileWebhookCompletions()
        XCTAssertEqual(state.deliveryOutbox.items.count, 1)
    }

    func testInterruptedMarkerRecoversButHandedOffMarkerDoesNotReplay() throws {
        let meeting = try meeting()
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        state.reconcileWebhookCompletions()
        XCTAssertEqual(state.deliveryOutbox.items.count, 1)
        XCTAssertEqual(meeting.webhookCompletion?.processing?.state, .interrupted)
        XCTAssertTrue(state.deliveryOutbox.discard(id: id))
        state.reconcileWebhookCompletions()
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
    }

    func testResendBuildsCurrentDataWithNewIdentity() async throws {
        let meeting = try meeting()
        let oldID = UUID()
        state.deliveryOutbox.register(.webhook) { _ in .reject(reason: "bad endpoint") }
        XCTAssertTrue(state.deliveryOutbox.enqueueWebhook(meetingID: meeting.id, event: "meeting.updated", body: Data("old".utf8), destination: state.webhookURL, id: oldID))
        await state.deliveryOutbox.processDue()
        XCTAssertNil(state.deliveryOutbox.item(id: oldID)?.body)
        meeting.summaryText = "edited summary"
        meeting.segments[0].text = "current transcript"
        state.deliveryOutbox.register(.webhook) { _ in .retry(reason: "offline") }
        state.resendFailedWebhooks()
        let new = try XCTUnwrap(state.deliveryOutbox.items.first)
        XCTAssertNotEqual(new.id, oldID)
        let payload = try XCTUnwrap(try body(new)["meeting"] as? [String: Any])
        XCTAssertEqual(payload["summary"] as? String, "edited summary")
        XCTAssertEqual((payload["transcript"] as? [[String: Any]])?.first?["text"] as? String, "current transcript")
        state.resendFailedWebhooks()
        XCTAssertEqual(state.deliveryOutbox.items.count, 1)
    }

    func testSavedAuthorityRejectsUndoTemplateSpeakerAndAccountChanges() throws {
        let meeting = try meeting()
        let first = state.beginSavedAIRequest(meeting, scope: "insights")
        let original = meeting.segments[0].text
        meeting.segments[0].text = "trimmed"; meeting.markTranscriptEdited()
        meeting.segments[0].text = original; meeting.markTranscriptEdited()
        XCTAssertFalse(state.savedAIRequestIsCurrent(first, meeting: meeting))
        let second = state.beginSavedAIRequest(meeting, scope: "insights", template: state.selectedInsightTemplate)
        meeting.templateDefinitionJSON = "changed"
        XCTAssertFalse(state.savedAIRequestIsCurrent(second, meeting: meeting))
        let third = state.beginSavedAIRequest(meeting, scope: "insights")
        meeting.speakerNames = ["0": "renamed"]
        XCTAssertFalse(state.savedAIRequestIsCurrent(third, meeting: meeting))
        let fourth = state.beginSavedAIRequest(meeting, scope: "insights")
        state.clientAuthManager = TestSupport.unenrolledAuthManager(session: TestSupport.stubbedSession())
        // Different managers may start at the same integer generation; account identity must fence too.
        XCTAssertFalse(state.savedAIRequestIsCurrent(fourth, meeting: meeting))
    }
}

extension SavedMeetingDeliveryTests {
    func testSpeakerEditDuringFinalProcessingStillCompletesSavedExports() async throws {
        let meeting = try meeting()
        meeting.automaticCompletionID = UUID()
        meeting.automaticCompletionOwner = state.automaticCompletionOwner
        StubURLProtocol.delay = 0.2
        let task = Task { await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript,
            language: "en", existingTitle: meeting.title, includeSales: false) }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        meeting.speakerNames = ["0": "Updated name"]
        await task.value
        XCTAssertEqual(meeting.automaticCompletionExportedAt, meeting.endTime)
        XCTAssertEqual(meeting.speakerNames["0"], "Updated name")
    }

    func testAutomaticSpeakerNamingDoesNotDiscardFinalAI() async throws {
        let meeting = try meeting()
        state.currentMeeting = meeting
        StubURLProtocol.delay = 0.15
        let task = Task { await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: false) }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        meeting.speakerNames = ["0": "automatic name"]
        try container.mainContext.save()
        await task.value
        XCTAssertEqual(meeting.summaryText, "fresh summary")
        XCTAssertEqual(meeting.webhookCompletion?.processing?.state, .complete)
    }

    func testFinalSaveFailureRestoresSelectedLiveValues() async throws {
        let meeting = try meeting()
        state.currentMeeting = meeting
        meeting.summaryText = "original"
        state.liveSummary = "original"
        try container.mainContext.save()
        state.persistenceSaveHandler = { _ in throw CocoaError(.fileWriteUnknown) }
        await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: false)
        XCTAssertEqual(meeting.summaryText, "original")
        XCTAssertEqual(state.liveSummary, "original")
        XCTAssertNil(meeting.insightsUpdatedAt)
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
    }

    func testHistoryUpdateCannotInterruptTheFinalAIRun() async throws {
        let meeting = try meeting()
        StubURLProtocol.delay = 0.4
        let final = Task { await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: false) }
        try await TestSupport.waitUntil { StubURLProtocol.requests.count == 1 }
        StubURLProtocol.delay = 0
        await state.generateInsightsForMeeting(meeting)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        await final.value
        XCTAssertEqual(state.deliveryOutbox.items.map(\.event), ["meeting.saved"])
        let payload = try XCTUnwrap(try body(XCTUnwrap(state.deliveryOutbox.items.first))["meeting"] as? [String: Any])
        XCTAssertEqual(payload["summary"] as? String, "fresh summary")
        XCTAssertEqual(meeting.webhookCompletion?.processing?.state, .complete)
    }

    func testReadyInitialCannotBeOvertakenWhenItsFirstStageFails() async throws {
        let meeting = try meeting()
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        state.persistenceSaveHandler = { _ in throw CocoaError(.fileWriteUnknown) }
        state.settleMeetingCompletion(meeting, id: id, outcomes: ["standard": .complete], interrupted: false)
        XCTAssertEqual(meeting.webhookCompletion?.phase, .ready)
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
        state.persistenceSaveHandler = { try $0.save() }
        await state.generateInsightsForMeeting(meeting)
        XCTAssertEqual(state.deliveryOutbox.items.map(\.event), ["meeting.saved"])
        let item = try XCTUnwrap(state.deliveryOutbox.items.first)
        XCTAssertEqual((try body(item)["meeting"] as? [String: Any])?["summary"] as? String, "fresh summary")
    }

    func testStoppedSaveFailureStaysProtectedAndRetryRunsOnce() async throws {
        let meeting = try meeting()
        state.currentMeeting = meeting
        state.isRecording = true
        state.liveSegments = [AppState.LiveSegment(id: meeting.segments[0].id, text: meeting.segments[0].text, speaker: 0, timestamp: 1, isFinal: true)]
        state.persistenceSaveHandler = { _ in throw CocoaError(.fileWriteUnknown) }
        state.stopRecording()
        try await TestSupport.waitUntil { state.persistenceIssue != nil && state.stoppedFinalizationTasks.isEmpty }
        XCTAssertTrue(state.isFinalizingMeeting)
        XCTAssertEqual(state.cloudUploadProtectedMeetingID, meeting.id)
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
        state.persistenceSaveHandler = { try $0.save() }
        state.retryPersistence()
        state.retryPersistence()
        try await TestSupport.waitUntil { !state.isFinalizingMeeting && state.finalizingInsightMeetingIDs.isEmpty }
        XCTAssertEqual(state.deliveryOutbox.items.map(\.event), ["meeting.saved"])
        let standardRequests = StubURLProtocol.requests.filter {
            let body = try? JSONSerialization.jsonObject(with: TestSupport.bodyData(of: $0)) as? [String: Any]
            return body?["mode"] as? String == "standard"
        }
        XCTAssertEqual(standardRequests.count, 1, "double retry must not launch a second final AI run")
    }

    func testHistoryDocsResponseAfterTrimDoesNotReplaceTopics() async throws {
        let meeting = try meeting()
        meeting.segments[0].text = String(repeating: "deployment question ", count: 20)
        try container.mainContext.save()
        state.docsMCPURL = "https://docs.example/mcp"
        StubURLProtocol.delay = 0.15
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, #"{"topics":["deployment"]}"#) }
        let task = Task { await state.refreshDocsTopics(for: meeting) }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        meeting.markTranscriptEdited()
        await task.value
        XCTAssertTrue(meeting.docTopics.isEmpty)
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
    }

    func testHistoryTemplateAppliesItsOwnNewDefinitionWithoutSelfInvalidation() async throws {
        let meeting = try meeting()
        state.insightsMode = .template
        state.setInsightModeEnabled(.template, enabled: true)
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, #"{"template_sections":{"overview":"accepted"}}"#) }
        await state.generateInsightsForMeeting(meeting)
        XCTAssertNotNil(meeting.insightTemplateID)
        XCTAssertNotNil(meeting.insightsUpdatedAt)
        XCTAssertEqual(state.deliveryOutbox.items.count, 1)
        XCTAssertNil(state.persistenceIssue)
    }
}

extension SavedMeetingDeliveryTests {
    func testManualRenameDuringFinalAIPreservesTitleWhileSummaryCompletes() async throws {
        let meeting = try meeting()
        state.currentMeeting = meeting
        StubURLProtocol.delay = 0.15
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, #"{"summary":"fresh summary","title":"AI title","questions":[]}"#) }
        let task = Task {
            await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript,
                                                     language: "en", existingTitle: "saved", includeSales: false)
        }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        meeting.title = "my title"
        try container.mainContext.save()
        await task.value
        XCTAssertEqual(meeting.title, "my title")
        XCTAssertEqual(meeting.summaryText, "fresh summary")
        let item = try XCTUnwrap(state.deliveryOutbox.items.first)
        let payload = try XCTUnwrap(try body(item)["meeting"] as? [String: Any])
        XCTAssertEqual(payload["title"] as? String, "my title")
        XCTAssertEqual(payload["summary"] as? String, "fresh summary")
    }

    func testFailedFinalCommitDoesNotRollBackRenameMadeWhileRequestWasHeld() async throws {
        let meeting = try meeting()
        state.currentMeeting = meeting
        meeting.summaryText = "original summary"
        state.liveSummary = "original summary"
        try container.mainContext.save()
        StubURLProtocol.delay = 0.15
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, #"{"summary":"fresh summary","title":"AI title","questions":[]}"#) }
        let task = Task {
            await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript,
                                                     language: "en", existingTitle: "saved", includeSales: false)
        }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        meeting.title = "my title"
        try container.mainContext.save()
        state.persistenceSaveHandler = { _ in throw CocoaError(.fileWriteUnknown) }
        await task.value
        XCTAssertEqual(meeting.title, "my title")
        XCTAssertEqual(meeting.summaryText, "original summary")
        XCTAssertEqual(state.liveSummary, "original summary")
        XCTAssertNil(meeting.insightsUpdatedAt)
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
    }

    func testFailedHistoryCommitDoesNotRollBackRenameMadeWhileRequestWasHeld() async throws {
        let meeting = try meeting()
        meeting.summaryText = "original summary"
        try container.mainContext.save()
        StubURLProtocol.delay = 0.15
        let task = Task { await state.generateInsightsForMeeting(meeting) }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        meeting.title = "my title"
        try container.mainContext.save()
        state.persistenceSaveHandler = { _ in throw CocoaError(.fileWriteUnknown) }
        await task.value
        XCTAssertEqual(meeting.title, "my title")
        XCTAssertEqual(meeting.summaryText, "original summary")
        XCTAssertNil(meeting.insightsUpdatedAt)
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
    }
}


extension SavedMeetingDeliveryTests {
    func testFirstDurableStoppedSaveIncludesCompletionIntent() async throws {
        let meeting = try meeting()
        state.currentMeeting = meeting
        state.liveSegments = [.init(id: UUID(), text: "final transcript", speaker: 0, timestamp: 1, isFinal: true)]
        state.isRecording = true
        var firstStoppedSaveHadIntent: Bool?
        state.persistenceSaveHandler = { context in
            try context.save()
            if firstStoppedSaveHadIntent == nil, meeting.endTime != nil {
                let saved = try ModelContext(self.container).fetch(FetchDescriptor<Meeting>()).first
                firstStoppedSaveHadIntent = saved?.webhookCompletion?.phase == .processing
            }
        }
        state.stopRecording()
        try await TestSupport.waitUntil { !self.state.isFinalizingMeeting && self.state.finalizingInsightMeetingIDs.isEmpty }
        XCTAssertEqual(firstStoppedSaveHadIntent, true)
        XCTAssertEqual(state.deliveryOutbox.items.map(\.event), ["meeting.saved"])
    }
}


extension SavedMeetingDeliveryTests {
    func testAccountSwitchDuringFinalAIStillDeliversInterruptedSavedTranscript() async throws {
        let meeting = try meeting()
        let entered = expectation(description: "final summary request is held")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let reply = try XCTUnwrap(StubURLProtocol.script)
        StubURLProtocol.script = { request in
            if request.url?.path.hasSuffix("/insights") == true {
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 10), .success)
            }
            return try reply(request)
        }
        let task = Task { await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: false) }
        await fulfillment(of: [entered], timeout: 5)
        var credentials = TestSupport.enrolledCredentials()
        credentials.accountID = "acct_b"
        state.clientAuthManager = TestSupport.enrolledAuthManager(session: TestSupport.stubbedSession(), credentials: credentials)
        release.signal()
        await task.value
        XCTAssertNil(meeting.summaryText, "old-account AI must not apply")
        let item = try XCTUnwrap(state.deliveryOutbox.items.first)
        XCTAssertEqual(item.destination, "https://receiver.example/hook")
        XCTAssertEqual(meeting.webhookCompletion?.processing?.state, .interrupted)
        let payload = try XCTUnwrap(try body(item)["meeting"] as? [String: Any])
        XCTAssertEqual((payload["transcript"] as? [[String: Any]])?.first?["text"] as? String, "we agreed to ship on Friday")
    }

    func testMarkerRetainsOnlyFingerprintUntilSuccessfulRelease() throws {
        let meeting = try meeting()
        let destination = state.webhookURL
        let fingerprint = WebhookCompletion.fingerprint(destination)
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        XCTAssertEqual(meeting.webhookCompletion?.destinationFingerprint, fingerprint)
        XCTAssertFalse(try XCTUnwrap(meeting.webhookCompletionJSON).contains(destination))
        state.settleMeetingCompletion(meeting, id: id, outcomes: [:], interrupted: false)
        XCTAssertEqual(meeting.webhookCompletion?.phase, .handedOff)
        XCTAssertNil(meeting.webhookCompletion?.destinationFingerprint)
        let data = try XCTUnwrap(meeting.webhookCompletionJSON?.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["destination"])
        XCTAssertNil(json["destinationFingerprint"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(fingerprint))
    }

    func testLegacyPlaintextMarkerNeedsExplicitRetryAndIsScrubbed() throws {
        let meeting = try meeting()
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(meeting.webhookCompletionJSON).utf8)) as? [String: Any])
        json.removeValue(forKey: "destinationFingerprint")
        json["destination"] = state.webhookURL
        json["phase"] = "ready"
        meeting.webhookCompletionJSON = String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
        try container.mainContext.save()
        XCTAssertEqual(meeting.webhookCompletion?.id, id)
        XCTAssertNil(meeting.webhookCompletion?.destinationFingerprint)
        state.reconcileWebhookCompletions()
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty, "even an identical legacy URL is unknown authority")
        XCTAssertNotNil(state.webhookResendError)
        state.retryWebhookDeliveries()
        XCTAssertNotEqual(meeting.webhookCompletion?.id, id)
        XCTAssertEqual(meeting.webhookCompletion?.phase, .handedOff)
        XCTAssertEqual(state.deliveryOutbox.items.first?.held, false)
        XCTAssertFalse(try XCTUnwrap(meeting.webhookCompletionJSON).contains("destination"))
        // A legacy already-handed-off marker is scrubbed without replaying its row.
        json["phase"] = "handedOff"
        meeting.webhookCompletionJSON = String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
        try container.mainContext.save()
        state.reconcileWebhookCompletions()
        XCTAssertFalse(try XCTUnwrap(meeting.webhookCompletionJSON).contains("destination"))
        XCTAssertEqual(state.deliveryOutbox.items.count, 1)
    }

    func testHistoryUpdateReachesNewURLWhileInitialCompletionStaysBlocked() async throws {
        let meeting = try meeting()
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        state.webhookURL = "https://new.example/hook"
        state.settleMeetingCompletion(meeting, id: id, outcomes: [:], interrupted: false)
        state.enqueueWebhook(WebhookService.payloadFromMeeting(meeting, event: "meeting.saved"))
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty, "a second saved payload cannot bypass the destination fence")
        await state.generateInsightsForMeeting(meeting)
        let update = try XCTUnwrap(state.deliveryOutbox.items.first)
        XCTAssertEqual(update.event, "meeting.updated")
        XCTAssertEqual(update.destination, state.webhookURL)
        XCTAssertEqual(meeting.webhookCompletion?.phase, .ready)
        XCTAssertEqual(meeting.webhookCompletion?.id, id)
        XCTAssertTrue(state.webhookResendError?.contains("URL changed") == true)
        XCTAssertEqual(state.webhookDeliveryStatusLine, "1 waiting")
        XCTAssertEqual((try body(update)["meeting"] as? [String: Any])?["summary"] as? String, "fresh summary")
    }

    func testExpiredHeldCompletionResolvesBeforeResendAndNeverReplays() async throws {
        var clock = Date()
        state.deliveryOutbox = DeliveryOutbox(storeURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString), now: { clock })
        let meeting = try meeting()
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        var saves = 0
        state.persistenceSaveHandler = { context in
            saves += 1
            if saves == 2 { throw CocoaError(.fileWriteUnknown) }
            try context.save()
        }
        state.settleMeetingCompletion(meeting, id: id, outcomes: [:], interrupted: false)
        XCTAssertEqual(meeting.webhookCompletion?.phase, .ready)
        XCTAssertEqual(state.deliveryOutbox.item(id: id)?.held, true)
        clock = clock.addingTimeInterval(DeliveryOutbox.maxAge + 1)
        await state.deliveryOutbox.processDue()
        XCTAssertEqual(state.deliveryOutbox.item(id: id)?.state, .failed)
        state.persistenceSaveHandler = { try $0.save() }
        state.webhookURL = "https://new.example/hook"
        // Resend can be invoked before lifecycle reconciliation sees the expired row.
        state.resendFailedWebhooks()
        XCTAssertEqual(meeting.webhookCompletion?.phase, .handedOff)
        XCTAssertNil(meeting.webhookCompletion?.destinationFingerprint)
        XCTAssertEqual(state.deliveryOutbox.items.map(\.event), ["meeting.updated"])
        let replacement = try XCTUnwrap(state.deliveryOutbox.items.first)
        XCTAssertNotEqual(replacement.id, id)
        XCTAssertEqual(replacement.destination, state.webhookURL)
        state.reconcileWebhookCompletions()
        XCTAssertEqual(state.deliveryOutbox.items.map(\.id), [replacement.id])
    }

    func testReleaseWriteFailureKeepsFingerprintUntilReconciliation() throws {
        var failRelease = true
        let store = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        state.deliveryOutbox = DeliveryOutbox(storeURL: store, writeStore: { data, url in
            let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            if failRelease && rows?.first?["held"] as? Bool == false { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        })
        let meeting = try meeting()
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        state.settleMeetingCompletion(meeting, id: id, outcomes: [:], interrupted: false)
        XCTAssertEqual(meeting.webhookCompletion?.phase, .handedOff)
        XCTAssertNotNil(meeting.webhookCompletion?.destinationFingerprint)
        XCTAssertEqual(state.deliveryOutbox.item(id: id)?.held, true)
        failRelease = false
        state.reconcileWebhookCompletions()
        XCTAssertEqual(state.deliveryOutbox.item(id: id)?.held, false)
        XCTAssertNil(meeting.webhookCompletion?.destinationFingerprint)
    }

    func testFingerprintCleanupSaveFailureCannotReplayDeliveredRow() throws {
        let meeting = try meeting()
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        var saves = 0
        state.persistenceSaveHandler = { context in
            saves += 1
            if saves == 3 { throw CocoaError(.fileWriteUnknown) }
            try context.save()
        }
        state.settleMeetingCompletion(meeting, id: id, outcomes: [:], interrupted: false)
        XCTAssertEqual(meeting.webhookCompletion?.phase, .handedOff)
        XCTAssertNotNil(meeting.webhookCompletion?.destinationFingerprint)
        XCTAssertEqual(state.deliveryOutbox.item(id: id)?.held, false)
        XCTAssertTrue(state.deliveryOutbox.discard(id: id)) // Simulate completed delivery before restart.
        state.persistenceSaveHandler = { try $0.save() }
        state.webhookURL = ""
        state.reconcileWebhookCompletions()
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
        XCTAssertNil(meeting.webhookCompletion?.destinationFingerprint)
    }

    func testChangedWebhookDestinationWaitsForExplicitRetryAndSurvivesReconciliation() async throws {
        let meeting = try meeting()
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        state.webhookURL = "https://new.example/hook"
        state.settleMeetingCompletion(meeting, id: id, outcomes: ["standard": .skipped], interrupted: false)
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
        XCTAssertNotNil(state.webhookResendError)
        state.webhookResendError = nil
        state.reconcileWebhookCompletions()
        XCTAssertNotNil(state.webhookResendError)
        XCTAssertTrue(state.deliveryOutbox.items.isEmpty)
        state.retryWebhookDeliveries()
        let item = try XCTUnwrap(state.deliveryOutbox.items.first)
        XCTAssertNotEqual(item.id, id)
        XCTAssertEqual(item.destination, "https://new.example/hook")
        XCTAssertNil(state.webhookResendError)
    }

    func testStoppedUpdateWaitsForFinalAIAndCoachingStillRecomputes() async throws {
        let meeting = try meeting()
        state.currentMeeting = meeting
        state.liveSegments = [.init(id: UUID(), text: "one two three four five six", speaker: 0, timestamp: 1, isFinal: true)]
        state.recordingDuration = 60
        StubURLProtocol.delay = 0.15
        let task = Task { await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: true) }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        XCTAssertTrue(state.currentMeetingFinalAIInProgress)
        await state.generateInsights()
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        state.insightsMode = .training
        await state.generateInsights()
        XCTAssertNotNil(state.trainingMetrics)
        await task.value
        XCTAssertFalse(state.currentMeetingFinalAIInProgress)
        XCTAssertEqual(meeting.webhookCompletion?.processing?.outcomes["standard"], .complete)
        XCTAssertEqual(meeting.webhookCompletion?.processing?.outcomes["questions"], .complete)
        XCTAssertEqual(meeting.webhookCompletion?.processing?.outcomes["meddpicc"], .complete)
    }

    func testTemplatePickerChangeDoesNotDiscardSummaryOrQuestions() async throws {
        let meeting = try meeting()
        let template = state.selectedInsightTemplate
        StubURLProtocol.delay = 0.15
        let task = Task { await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: false, template: template) }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        state.insightTemplateID = try XCTUnwrap(InsightTemplate.builtIn.first { $0.id != template.id }).id
        await task.value
        XCTAssertEqual(meeting.summaryText, "fresh summary")
        XCTAssertEqual(meeting.webhookCompletion?.processing?.state, .partial)
        XCTAssertEqual(meeting.webhookCompletion?.processing?.outcomes["template"], .stale)
        XCTAssertEqual(meeting.webhookCompletion?.processing?.outcomes["questions"], .complete)
        let payload = try XCTUnwrap(try body(XCTUnwrap(state.deliveryOutbox.items.first))["meeting"] as? [String: Any])
        XCTAssertEqual(payload["summary"] as? String, "fresh summary")
    }

    func testMarkerOnlyWritesDoNotNotifyCloudButPendingContentStillDoes() throws {
        let meeting = try meeting()
        var operations: [PersistenceOperation] = []
        // User-visible persistence failures expose which kind of commit was selected.
        state.persistenceSaveHandler = { _ in throw CocoaError(.fileWriteUnknown) }
        _ = state.beginMeetingCompletion(meeting)
        operations.append(try XCTUnwrap(state.persistenceIssue?.operation))
        state.persistenceSaveHandler = { try $0.save() }
        try container.mainContext.save()
        meeting.notes = "new local edit"
        state.persistenceSaveHandler = { _ in throw CocoaError(.fileWriteUnknown) }
        var marker = try XCTUnwrap(meeting.webhookCompletion)
        marker.phase = .ready
        _ = state.persistWebhookCompletion(marker, on: meeting)
        operations.append(try XCTUnwrap(state.persistenceIssue?.operation))
        XCTAssertEqual(operations, [.webhookCompletion, .finalInsights])
    }
}


extension SavedMeetingDeliveryTests {
    func testStoppedTemplatePickerInvalidatesOnlyItsOldTemplateJob() async throws {
        let meeting = try meeting()
        let template = state.selectedInsightTemplate
        let replacement = try XCTUnwrap(InsightTemplate.builtIn.first { $0.id != template.id })
        meeting.applyInsightTemplate(template)
        try container.mainContext.save()
        state.currentMeeting = meeting
        state.liveTemplateID = template.id
        StubURLProtocol.delay = 0.15
        let task = Task { await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: false, template: template) }
        try await TestSupport.waitUntil {
            StubURLProtocol.requests.contains {
                let body = try? JSONSerialization.jsonObject(with: TestSupport.bodyData(of: $0)) as? [String: Any]
                return body?["mode"] as? String == "template"
            }
        }
        state.selectInsightTemplate(replacement.id)
        await task.value
        XCTAssertEqual(meeting.insightTemplateID, replacement.id)
        XCTAssertEqual(meeting.summaryText, "fresh summary")
        XCTAssertEqual(meeting.webhookCompletion?.processing?.outcomes["template"], .stale)
        XCTAssertEqual(meeting.webhookCompletion?.processing?.outcomes["questions"], .complete)
        XCTAssertEqual(meeting.webhookCompletion?.processing?.state, .partial)
    }
}


extension SavedMeetingDeliveryTests {
    func testChangedDestinationAfterAcknowledgmentCannotReleaseUntilExplicitRetry() throws {
        let meeting = try meeting()
        let id = try XCTUnwrap(state.beginMeetingCompletion(meeting))
        var marker = try XCTUnwrap(meeting.webhookCompletion)
        marker.phase = .handedOff
        XCTAssertTrue(state.persistWebhookCompletion(marker, on: meeting))
        let payload = WebhookService.payloadFromMeeting(meeting, event: "meeting.saved")
        XCTAssertTrue(state.deliveryOutbox.stageWebhook(id: id, meetingID: meeting.id, event: "meeting.saved", body: try WebhookService.encode(payload), destination: state.webhookURL))
        state.webhookURL = "https://new.example/hook"
        state.handOffWebhookCompletion(meeting)
        XCTAssertEqual(state.deliveryOutbox.item(id: id)?.held, true)
        XCTAssertNotNil(state.webhookResendError)
        state.retryWebhookDeliveries()
        XCTAssertNil(state.deliveryOutbox.item(id: id))
        let replacement = try XCTUnwrap(state.deliveryOutbox.items.first)
        XCTAssertEqual(replacement.destination, state.webhookURL)
        XCTAssertEqual(replacement.held, false)
        XCTAssertEqual(meeting.webhookCompletion?.phase, .handedOff)
    }
}


extension MeetingJourneyTests {
    func testStopBeforeFirstWordsDrainsBothSourcesAndPersistsLateFinals() async throws {
        let state = makeState()
        let meeting = Meeting(title: "late words")
        state.currentMeeting = meeting
        state.isRecording = true
        state.insightsService = nil
        state.beginRecordingDiagnostics()
        var finalEvidence: [String: String]?
        state.diagnosticEventObserver = { name, fields in if name == "recording_final" { finalEvidence = fields } }
        let service = try XCTUnwrap(state.deepgramService)
        service.finalDrainDuration = .milliseconds(150)
        var flushes = 0
        service.finalDrainOperation = {
            flushes += 1
            for (index, text) in ["first source tail", "second source tail"].enumerated() {
                try? await Task.sleep(for: .milliseconds(25))
                service.speakerSegments = [.init(id: UUID(), speaker: index, text: text,
                    startTime: Double(index * 2), endTime: Double(index * 2 + 1), isFinal: true,
                    confidence: 1, channelIndex: nil, source: .system)]
            }
        }
        state.stopRecording()
        state.stopRecording() // A duplicate Stop must not start another drain or completion.
        XCTAssertTrue(state.isFinalizingMeeting)
        try await TestSupport.waitUntil(timeout: 5) { !state.isFinalizingMeeting }
        XCTAssertEqual(flushes, 1)
        XCTAssertEqual(finalEvidence?["transcription_outcome"], "words_seen", "Final classification follows both-source drain")
        let saved = try XCTUnwrap(persistedMeetings().first)
        XCTAssertEqual(saved.id, meeting.id)
        XCTAssertEqual(saved.segments.sorted { $0.timestamp < $1.timestamp }.map(\.text),
                       ["first source tail", "second source tail"])
    }

    func testFinalDrainIsBoundedWhenItsCloseOperationNeverCompletes() async throws {
        let service = DeepgramService()
        service.finalDrainDuration = .milliseconds(50)
        var gate: CheckedContinuation<Void, Never>?
        service.finalDrainOperation = { await withCheckedContinuation { gate = $0 } }
        let started = ContinuousClock.now
        await service.gracefulDisconnect()
        XCTAssertNotNil(gate)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        XCTAssertEqual(service.connectionState, .disconnected)
        gate?.resume()
    }

    func testAnOlderDrainDoesNotDisconnectAReplacementConnection() async throws {
        let service = DeepgramService()
        service.finalDrainDuration = .milliseconds(100)
        var started = false
        service.finalDrainOperation = { started = true }
        let drain = Task { await service.gracefulDisconnect() }
        try await TestSupport.waitUntil { started }
        service.disconnect()
        service.socketStarter = { _ in } // Keep a replacement handshake pending, with no network.
        service.configure(credential: "synthetic-key", authorizationScheme: .token)
        service.connect()
        await drain.value
        XCTAssertEqual(service.connectionState, .connecting)
        service.disconnect()
    }
}


extension MeetingJourneyTests {
    func testConnectionWaitAllowsHandshakeToSettleAndRejectsReplacement() async throws {
        let service = DeepgramService()
        service.connectionTimeoutSeconds = 0.5
        service.connectionState = .connecting
        let slowHandshake = Task {
            try? await Task.sleep(for: .milliseconds(150))
            service.connectionState = .connected
        }
        let connected = await service.waitForConnectionAttempt()
        XCTAssertTrue(connected)
        await slowHandshake.value
        service.connectionState = .connecting
        let wait = Task { await service.waitForConnectionAttempt() }
        try await Task.sleep(for: .milliseconds(25))
        service.disconnect()
        service.connectionState = .connected
        let replaced = await wait.value
        XCTAssertFalse(replaced, "A newer socket cannot complete the older attempt")
        service.disconnect()
    }
}

extension MeetingJourneyTests {
    func testResumedRecordingDoesNotUseExistingMeetingWordsAsFreshTranscriptionEvidence() async throws {
        let state = makeState()
        let meeting = Meeting(title: "resumed recording")
        state.currentMeeting = meeting
        state.liveSegments = [segment("words from the earlier recording", at: 1)]
        state.isRecording = true
        state.insightsService = nil
        state.deepgramService?.finalDrainDuration = .milliseconds(20)
        state.beginRecordingDiagnostics()
        var finalEvidence: [String: String]?
        state.diagnosticEventObserver = { name, fields in if name == "recording_final" { finalEvidence = fields } }
        state.stopRecording()
        try await TestSupport.waitUntil(timeout: 5) { !state.isFinalizingMeeting }
        XCTAssertEqual(finalEvidence?["transcription_outcome"], "no_speech_evidence")
        XCTAssertEqual(try persistedMeetings().first?.segments.map(\.text), ["words from the earlier recording"])
    }
}

extension MeetingJourneyTests {
    func testFinalAIDecodeFailureKeepsTranscriptAndSettlesCompletionWithBoundedDiagnostics() async throws {
        let state = makeState()
        let sharing = state.shareDiagnostics
        defer { state.shareDiagnostics = sharing }
        state.shareDiagnostics = true
        let meeting = Meeting(title: "decode fixture")
        state.currentMeeting = meeting
        state.liveSegments = [segment("retained transcript fixture", at: 1)]
        state.isRecording = true
        state.beginRecordingDiagnostics()
        state.deepgramService?.finalDrainDuration = .milliseconds(20)
        StubURLProtocol.script = { _ in StubURLProtocol.json(200, "broken JSON") }
        var failures: [[String: String]] = []
        state.diagnosticEventObserver = { name, fields in if name == "insights_request_failed" { failures.append(fields) } }
        state.stopRecording()
        try await TestSupport.waitUntil(timeout: 5) { !state.isFinalizingMeeting && !state.currentMeetingFinalAIInProgress }
        let saved = try XCTUnwrap(persistedMeetings().first)
        XCTAssertEqual(saved.segments.map(\.text), ["retained transcript fixture"])
        let final = try XCTUnwrap(failures.first { $0["ai_stage"] == "final" && $0["task_mode"] == "standard" })
        XCTAssertEqual(final["failure_category"], "decode")
        XCTAssertEqual(final["status"], "200")
        XCTAssertNotNil(final["request_id"].flatMap(UUID.init(uuidString:)))
        XCTAssertFalse(final.values.contains { $0.contains("fixture") || $0.contains("JSON") })
    }

    func testAIDiagnosticModeConsentPrivateAndOwnerGates() async {
        let state = makeState()
        let sharing = state.shareDiagnostics
        defer { state.shareDiagnostics = sharing; state.privateModeEnabled = false }
        state.shareDiagnostics = true
        var names: [String] = []
        state.diagnosticEventObserver = { name, _ in names.append(name) }
        state.reportAIRequestFailure(URLError(.timedOut), mode: "standard", stage: "live")
        XCTAssertEqual(names, ["insights_request_failed"])
        state.shareDiagnostics = false
        state.reportAIRequestFailure(URLError(.timedOut), mode: "standard", stage: "live")
        state.shareDiagnostics = true
        state.privateModeEnabled = true
        state.reportAIRequestFailure(URLError(.timedOut), mode: "standard", stage: "live")
        state.privateModeEnabled = false
        state.appModeRaw = AppMode.byok.rawValue
        state.reportAIRequestFailure(URLError(.timedOut), mode: "standard", stage: "live")
        state.appModeRaw = AppMode.managed.rawValue
        let old = AIRequestObservation(accountID: "acct_other", credentialGeneration: -1, stage: "final")
        await AIRequestDiagnostics.$current.withValue(old) {
            state.reportAIRequestFailure(URLError(.timedOut), mode: "standard", stage: "final")
        }
        XCTAssertEqual(names, ["insights_request_failed"])
    }
}


extension MeetingJourneyTests {
    func testPlannedRestartKeepsOneOwnerAndIgnoresQueuedOldConnectionStates() async throws {
        let state = makeState()
        state.shareDiagnostics = true
        let service = try XCTUnwrap(state.deepgramService)
        service.socketStarter = { _ in } // No provider traffic.
        service.connectionState = .connected
        state.isRecording = true
        state.beginRecordingDiagnostics()
        var names: [String] = []
        var restart: [String: String]?
        state.diagnosticEventObserver = { name, fields in
            names.append(name)
            if name == "recording_restart_planned" { restart = fields }
        }
        state.handleDeepgramConnectionState(.error) // Old queued notification.
        XCTAssertFalse(names.contains("deepgram_connection_error"))
        state.scheduleDeepgramReconnect(reason: "manual retry")
        state.scheduleDeepgramReconnect(reason: "unexpected disconnect")
        try await TestSupport.waitUntil(timeout: 5) { restart != nil }
        state.handleDeepgramConnectionState(.disconnected)
        XCTAssertEqual(names.filter { $0 == "deepgram_reconnect_scheduled" }.count, 1)
        XCTAssertFalse(names.contains("deepgram_unexpected_disconnect"))
        XCTAssertEqual(restart?["recovery_reason"], "manual")
        XCTAssertEqual(restart?["recovery_generation"], "1")
        XCTAssertFalse(names.contains("recording_transcription_resumed"))
        state.stopRecording()
        try await TestSupport.waitUntil { !state.isFinalizingMeeting }
    }
}

extension MeetingJourneyTests {
    func testLocalFinishLongerThanTwoSecondsSavesTailOnceAfterReceiveWindow() async throws {
        let state = makeState()
        state.currentMeeting = Meeting(title: "local tail")
        state.isRecording = true
        state.insightsService = nil
        let service = try XCTUnwrap(state.deepgramService)
        var gate: CheckedContinuation<Void, Never>?
        var flushes = 0
        service.localFinishOperation = {
            flushes += 1
            await withCheckedContinuation { gate = $0 }
            service.speakerSegments = [.init(id: UUID(), speaker: 1000, text: "final local words",
                startTime: 0, endTime: 1, isFinal: true, confidence: 1, channelIndex: nil, source: .microphone)]
        }
        state.stopRecording(); state.stopRecording()
        try await TestSupport.waitUntil { gate != nil }
        try await Task.sleep(for: .milliseconds(2300))
        XCTAssertTrue(state.isFinalizingMeeting)
        let released = ContinuousClock.now
        gate?.resume()
        try await TestSupport.waitUntil(timeout: 5) { !state.isFinalizingMeeting }
        XCTAssertGreaterThanOrEqual(released.duration(to: .now), .milliseconds(800))
        XCTAssertEqual(flushes, 1)
        XCTAssertEqual(try XCTUnwrap(persistedMeetings().first).segments.map(\.text), ["final local words"])
    }

    func testHungLocalFinishHasHardCap() async throws {
        let service = DeepgramService()
        service.localFinishTimeout = .milliseconds(50)
        var gate: CheckedContinuation<Void, Never>?
        service.localFinishOperation = { await withCheckedContinuation { gate = $0 } }
        let start = ContinuousClock.now
        await service.gracefulDisconnect()
        XCTAssertNotNil(gate)
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        gate?.resume()
    }
}


extension MeetingJourneyTests {
    func testManagedRefreshCoordinatorKeepsWholeRecordingAcrossRenewalsAndLongDurations() async throws {
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.managedAccounting.utf8)) as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: fixture["start_response"]!)
        StubURLProtocol.script = nil
        StubURLProtocol.handler = { _ in (200, data) }
        for minutes in [74, 360] {
            let state = makeState()
            var clock: TimeInterval = 0
            state.managedSessionJournal.uptime = { clock }
            let started = await state.refreshManagedDeepgramCredential(trigger: "start")
            XCTAssertTrue(started)
            let root = try XCTUnwrap(state.managedSessionJournal.active)
            state.managedSessionJournal.captureBegan()
            for _ in 0..<3 {
                clock += Double(minutes * 20)
                state.managedSessionJournal.observe()
                let refreshed = await state.refreshManagedDeepgramCredential(trigger: "renewal")
                XCTAssertTrue(refreshed)
            }
            let report = try XCTUnwrap(state.managedSessionJournal.finish(meetingID: nil))
            XCTAssertEqual(report.recordingID, root.recordingID)
            XCTAssertEqual(report.sessionId, root.sessionId)
            XCTAssertEqual(report.durationMS, minutes * 60000)
        }
    }

    func testActualManagedStartRetainsRecordingIDAfterLostResponses() async throws {
        let state = makeState()
        let meeting = Meeting(title: "Start awaiting response")
        container.mainContext.insert(meeting)
        state.currentMeeting = meeting
        state.managedEnrollmentTestResult = true
        #if os(macOS)
        state.onDeviceTranscriptionEnabled = false
        #endif
        StubURLProtocol.script = nil
        StubURLProtocol.requests = []
        StubURLProtocol.script = { _ in throw URLError(.timedOut) }
        await state.startManagedRecording()
        let id = try XCTUnwrap(state.managedRecordingID)
        XCTAssertFalse(state.isStartingMeeting)
        await state.startManagedRecording()
        XCTAssertEqual(state.managedRecordingID, id)
        let starts = try StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/session") == true }.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: TestSupport.bodyData(of: $0)) as? [String: Any])["recording_id"] as? String
        }
        XCTAssertGreaterThanOrEqual(starts.count, 2)
        XCTAssertEqual(Set(starts.compactMap { $0 }).count, 1)
    }

    func testAmbiguousUncapturedStartCanRetryOnRollbackBackendWithSameRecordingID() async throws {
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.managedAccounting.utf8)) as? [String: Any])
        let legacy = try JSONSerialization.data(withJSONObject: fixture["legacy_response"]!)
        let state = makeState()
        StubURLProtocol.script = nil
        StubURLProtocol.handler = { _ in (500, Data(#"{"error":"internal_error"}"#.utf8)) }
        let first = await state.refreshManagedDeepgramCredential(trigger: "start")
        XCTAssertFalse(first)
        StubURLProtocol.handler = { _ in (200, legacy) }
        let retry = await state.refreshManagedDeepgramCredential(trigger: "start")
        XCTAssertTrue(retry)
        XCTAssertEqual(state.managedSessionJournal.active?.accountingVersion, 1)
        let starts = try StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/session") == true }.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: TestSupport.bodyData(of: $0)) as? [String: Any])["recording_id"] as? String
        }
        XCTAssertEqual(starts.count, 2)
        XCTAssertNotNil(starts[0]); XCTAssertEqual(starts[0], starts[1])
    }
}


extension MeetingJourneyTests {
    func testCoalescedGrantCannotApplyAfterStopOrAccountChange() async throws {
        for signOut in [false, true] {
            let state = makeState()
            state.isRecording = true
            let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.managedAccounting.utf8)) as? [String: Any])
            let data = try JSONSerialization.data(withJSONObject: fixture["start_response"]!)
            StubURLProtocol.script = nil
            StubURLProtocol.handler = { _ in (200, data) }
            StubURLProtocol.requests = []
            let gate = StubURLProtocol.ResponseGate()
            StubURLProtocol.context.gate = gate
            let one = Task { await state.refreshManagedDeepgramCredential(trigger: "start") }
            let two = Task { await state.refreshManagedDeepgramCredential(trigger: "start") }
            try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
            if signOut { state.clientAuthManager.clearLocal(reason: "signout") }
            else { state.stopRecording() }
            gate.release()
            let first = await one.value, second = await two.value
            XCTAssertFalse(first); XCTAssertFalse(second)
            XCTAssertEqual(StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/session") == true }.count, 1)
            XCTAssertNil(state.managedSessionJournal.active)
            XCTAssertNil(state.recordingErrorMessage, "Old work cannot overwrite the current UI")
            state.isRecording = false
            StubURLProtocol.context.gate = nil
        }
    }
}


extension MeetingJourneyTests {
    func testQuotaRejectionCanRetryAgainstLegacyBackend() async throws {
        let state = makeState()
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.managedAccounting.utf8)) as? [String: Any])
        let legacy = try JSONSerialization.data(withJSONObject: fixture["legacy_response"]!)
        StubURLProtocol.script = nil
        StubURLProtocol.handler = { _ in (402, Data(#"{"error":"limit_reached","minutes_used":500}"#.utf8)) }
        let rejected = await state.refreshManagedDeepgramCredential(trigger: "start")
        XCTAssertFalse(rejected)
        StubURLProtocol.handler = { _ in (200, legacy) }
        let recovered = await state.refreshManagedDeepgramCredential(trigger: "start")
        XCTAssertTrue(recovered)
        XCTAssertEqual(state.managedSessionJournal.active?.accountingVersion, 1)
    }

    func testOfflineStartCanRetryAgainstLegacyBackend() async throws {
        let state = makeState()
        StubURLProtocol.script = { _ in throw URLError(.notConnectedToInternet) }
        let failed = await state.refreshManagedDeepgramCredential(trigger: "start")
        XCTAssertFalse(failed)
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.managedAccounting.utf8)) as? [String: Any])
        let legacy = try JSONSerialization.data(withJSONObject: fixture["legacy_response"]!)
        StubURLProtocol.script = nil
        StubURLProtocol.handler = { _ in (200, legacy) }
        let recovered = await state.refreshManagedDeepgramCredential(trigger: "start")
        XCTAssertTrue(recovered)
    }

    func testRepeatedStartWhileGrantIsPendingDoesNotPoisonNextGrant() async throws {
        let state = makeState()
        state.managedEnrollmentTestResult = true
        state.onDeviceTranscriptionEnabled = false
        StubURLProtocol.script = nil
        StubURLProtocol.handler = { _ in (402, Data(#"{"error":"limit_reached"}"#.utf8)) }
        let gate = StubURLProtocol.ResponseGate()
        StubURLProtocol.context.gate = gate
        XCTAssertTrue(state.startNewMeeting())
        try await TestSupport.waitUntil { StubURLProtocol.requests.contains { $0.url?.path.hasSuffix("/session") == true } }
        state.startRecording()
        state.startRecording()
        gate.release()
        try await TestSupport.waitUntil { !state.isStartingMeeting && !state.isResumingRecording }
        StubURLProtocol.context.gate = nil
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.managedAccounting.utf8)) as? [String: Any])
        let legacy = try JSONSerialization.data(withJSONObject: fixture["legacy_response"]!)
        StubURLProtocol.handler = { _ in (200, legacy) }
        let recovered = await state.refreshManagedDeepgramCredential(trigger: "start")
        XCTAssertTrue(recovered)
    }

    func testDiscardWhileResumeGrantIsPendingCannotStartPhantomRecording() async throws {
        let state = makeState()
        state.managedEnrollmentTestResult = true
        state.onDeviceTranscriptionEnabled = false
        let meeting = Meeting(title: "Resume then discard", endTime: Date())
        container.mainContext.insert(meeting); try container.mainContext.save()
        state.currentMeeting = meeting
        state.isResumingRecording = true
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ContractFixtures.managedAccounting.utf8)) as? [String: Any])
        let response = try JSONSerialization.data(withJSONObject: fixture["start_response"]!)
        StubURLProtocol.script = nil
        StubURLProtocol.handler = { _ in (200, response) }
        let gate = StubURLProtocol.ResponseGate()
        StubURLProtocol.context.gate = gate
        let start = Task { await state.startManagedRecording() }
        try await TestSupport.waitUntil { StubURLProtocol.requests.contains { $0.url?.path.hasSuffix("/session") == true } }
        state.discardCurrentMeeting()
        XCTAssertFalse(state.startNewMeeting(), "Wait for the cancelled start to unwind before another start")
        gate.release()
        await start.value
        StubURLProtocol.context.gate = nil
        XCTAssertNil(state.currentMeeting)
        XCTAssertFalse(state.isRecording)
        XCTAssertFalse(state.isResumingRecording)
        XCTAssertNil(state.managedSessionJournal.active)
        state.startRecording()
        XCTAssertFalse(state.isRecording, "A missing meeting cannot capture even with a late credential")
    }

    func testAccountTransitionWaitsForOwnedUsageAndExcludesNewStarts() async throws {
        let state = makeState()
        let account = try XCTUnwrap(state.clientAuthManager.status.accountID)
        let report = ManagedSessionReport(deviceId: DeviceIdentifier.getOrCreateDeviceId(), sessionId: "pending-legacy", durationMinutes: 2, accountID: account)
        let queued = await state.managedSessionJournal.enqueue(report)
        XCTAssertTrue(queued)
        StubURLProtocol.script = nil
        StubURLProtocol.handler = { _ in (503, Data(#"{"error":"busy"}"#.utf8)) }
        let gate = StubURLProtocol.ResponseGate()
        StubURLProtocol.context.gate = gate
        let move = Task { await state.attachManagedDevice(recoveryKey: "unused") }
        try await TestSupport.waitUntil { state.accountTransitionInFlight && !StubURLProtocol.requests.isEmpty }
        XCTAssertFalse(state.canStartRecording)
        XCTAssertFalse(state.startNewMeeting())
        gate.release()
        let moved = await move.value
        StubURLProtocol.context.gate = nil
        XCTAssertFalse(moved)
        XCTAssertFalse(state.accountTransitionInFlight)
        XCTAssertEqual(state.clientAuthManager.status.accountID, account)
        XCTAssertEqual(state.managedSessionJournal.pending.count, 1)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url?.path.hasSuffix("/attach") == true })
        XCTAssertGreaterThan(try XCTUnwrap(state.managedSessionJournal.pending.first?.nextAttemptAt), Date())

        // Switching to BYOK does not erase managed minutes already owed. An explicit
        // retry sends now, even inside the automatic retry delay, then permits the move.
        state.appModeRaw = AppMode.byok.rawValue
        StubURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/session/end") == true {
                return (200, Data(#"{"minutes_used":2,"minutes_remaining":498}"#.utf8))
            }
            if request.url?.path.hasSuffix("/auth/account/attach") == true {
                return (200, Data(#"{"access_token":"new-account-token","expires_in":3600,"refresh_token":"new-refresh","account_id":"account-after-settlement","device_cap":5,"moved":true}"#.utf8))
            }
            return (503, Data(#"{"error":"busy"}"#.utf8))
        }
        let retriedMove = await state.joinAccount(approvedLinkID: "approved-link")
        XCTAssertTrue(retriedMove, state.managedEnrollmentError ?? "")
        XCTAssertTrue(state.managedSessionJournal.pending.isEmpty)
        XCTAssertEqual(state.clientAuthManager.status.accountID, "account-after-settlement")
        XCTAssertFalse(state.accountTransitionInFlight)
    }

    func testAccountMoveIsBlockedDuringRecordingAndPendingResume() async {
        let state = makeState()
        state.isRecording = true
        let recording = await state.attachManagedDevice(recoveryKey: "unused")
        XCTAssertFalse(recording)
        state.isRecording = false; state.isResumingRecording = true
        let resume = await state.joinAccount(approvedLinkID: "unused")
        XCTAssertFalse(resume)
        XCTAssertFalse(state.accountTransitionInFlight)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        state.isResumingRecording = false
    }

    func testResumeAndStopKeepTheOriginalCRMCompletionCheckpoint() async throws {
        let state = makeState()
        let meeting = Meeting(title: "Continued meeting")
        state.currentMeeting = meeting; state.isRecording = true
        state.liveSegments = [segment("first part", at: 2)]
        state.stopRecording()
        try await TestSupport.waitUntil(timeout: 15) {
            !state.isFinalizingMeeting && state.finalizingInsightMeetingIDs.isEmpty
        }
        let completion = try XCTUnwrap(meeting.automaticCompletionID)
        let checkpoint = try XCTUnwrap(meeting.automaticCompletionExportedAt)
        state.isRecording = true; meeting.endTime = nil
        state.liveSegments.append(segment("second part", at: 12))
        state.stopRecording()
        try await TestSupport.waitUntil(timeout: 15) {
            !state.isFinalizingMeeting && state.finalizingInsightMeetingIDs.isEmpty
        }
        XCTAssertEqual(meeting.automaticCompletionID, completion)
        XCTAssertEqual(meeting.automaticCompletionExportedAt, checkpoint)
        XCTAssertGreaterThan(try XCTUnwrap(meeting.endTime), checkpoint)
    }

    #if os(macOS)
    func testEnablingExportLaterDoesNotExportPreviouslyCompletedMeetings() throws {
        let originalTZ = getenv("TZ").map { String(cString: $0) }
        defer {
            if let originalTZ { setenv("TZ", originalTZ, 1) } else { unsetenv("TZ") }
            tzset(); NSTimeZone.resetSystemTimeZone()
        }
        setenv("TZ", "UTC", 1); tzset(); NSTimeZone.resetSystemTimeZone()
        let state = makeState()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertTrue(state.saveExportFolderBookmark(for: folder))
        let meeting = Meeting(title: "Earlier meeting", endTime: Date())
        meeting.managedSessionId = "pending-accounting-session"
        meeting.automaticCompletionID = UUID(); meeting.automaticCompletionOwner = state.automaticCompletionOwner
        meeting.automaticCompletionMarkdownRequested = false
        container.mainContext.insert(meeting); try container.mainContext.save()
        state.completeSavedMeetingExports(meeting)
        state.autoExportMarkdown = true
        state.reconcileAutomaticCompletions()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        meeting.automaticCompletionMarkdownRequested = true
        state.completeSavedMeetingExports(meeting)
        XCTAssertNotNil(meeting.automaticCompletionMarkdownExportedAt)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
        meeting.notes = "Notes added after stopping"
        try container.mainContext.save()
        state.reconcileAutomaticCompletions()
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let markdown = try XCTUnwrap(files.first { $0.pathExtension == "md" })
        XCTAssertTrue(try String(contentsOf: markdown, encoding: .utf8).contains(meeting.notes))
        XCTAssertEqual(meeting.automaticCompletionMarkdownFingerprint, MeetingSyncDocument.markdownFingerprint(of: meeting))
        var renders = 0
        state.automaticMarkdownRenderer = { meeting in renders += 1; return meeting.fullMeetingAsMarkdown() }
        try "My edits in my editor".write(to: markdown, atomically: true, encoding: .utf8)
        meeting.isPinned.toggle(); meeting.folderID = UUID(); meeting.folderManual = true
        meeting.managedSessionId = nil; meeting.insightsUpdatedAt = Date()
        meeting.calendarEventId = "unrendered-calendar-id"; meeting.externalURL = "https://example.com"
        try container.mainContext.save()
        state.reconcileAutomaticCompletions()
        XCTAssertEqual(try String(contentsOf: markdown, encoding: .utf8), "My edits in my editor")
        let oldRenderedDate = meeting.fullMeetingAsMarkdown()
        setenv("TZ", "Pacific/Auckland", 1); tzset(); NSTimeZone.resetSystemTimeZone()
        XCTAssertNotEqual(meeting.fullMeetingAsMarkdown(), oldRenderedDate,
                          "exercise an actual formatted-date change, not a cached timezone")
        state.reconcileAutomaticCompletions()
        XCTAssertEqual(try String(contentsOf: markdown, encoding: .utf8), "My edits in my editor")
        XCTAssertEqual(renders, 0, "unchanged content must not render transcripts even across timezone changes")
        state.autoExportMarkdown = false
        meeting.notes += " changed but export disabled"
        state.reconcileAutomaticCompletions()
        XCTAssertEqual(renders, 0, "disabled export must never render the completed history")
        state.autoExportMarkdown = true
        state.reconcileAutomaticCompletions()
        XCTAssertEqual(renders, 1, "a genuine content change still refreshes the export")

    }

    func testMissingMarkdownDestinationDoesNotBlockCompletionCheckpoint() throws {
        let state = makeState()
        state.autoExportMarkdown = true
        let meeting = Meeting(title: "Export", endTime: Date())
        meeting.automaticCompletionID = UUID(); meeting.automaticCompletionOwner = state.automaticCompletionOwner
        meeting.automaticCompletionMarkdownRequested = true
        container.mainContext.insert(meeting); try container.mainContext.save()
        state.completeSavedMeetingExports(meeting)
        XCTAssertEqual(meeting.automaticCompletionExportedAt, meeting.endTime)
    }
    #endif
}
