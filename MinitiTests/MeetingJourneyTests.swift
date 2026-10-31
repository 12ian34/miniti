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

    override func setUp() async throws {
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
    }

    private func makeState() -> AppState {
        let state = AppState()
        state.modelContext = container.mainContext
        state.minitiAPIService = MinitiAPIService(session: session, auth: TestSupport.enrolledAuthManager(session: session))
        state.insightsService = InsightsService(session: session)
        return state
    }

    private func segment(_ text: String, speaker: Int = 0, at timestamp: TimeInterval) -> AppState.LiveSegment {
        AppState.LiveSegment(id: UUID(), text: text, speaker: speaker, timestamp: timestamp, isFinal: true)
    }

    private func persistedMeetings() throws -> [Meeting] {
        try ModelContext(container).fetch(FetchDescriptor<Meeting>())
    }

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

    func testStopWithNoContentSavesNothingAndDoesNotFinalize() async throws {
        let state = makeState()
        state.currentMeeting = Meeting(title: "empty")
        state.isRecording = true
        state.liveSegments = []

        state.stopRecording()

        XCTAssertFalse(state.isRecording)
        XCTAssertFalse(state.isFinalizingMeeting)
        XCTAssertEqual(state.finalizationStatusText, "Saved automatically")
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
        StubURLProtocol.delay = 0.15
        let task = Task { await state.generateFinalInsightsAndSave(for: meeting, transcript: meeting.fullTranscript, language: "en", existingTitle: "saved", includeSales: false) }
        try await TestSupport.waitUntil { !StubURLProtocol.requests.isEmpty }
        var credentials = TestSupport.enrolledCredentials()
        credentials.accountID = "acct_b"
        state.clientAuthManager = TestSupport.enrolledAuthManager(session: TestSupport.stubbedSession(), credentials: credentials)
        await task.value
        XCTAssertNil(meeting.summaryText, "old-account AI must not apply")
        let item = try XCTUnwrap(state.deliveryOutbox.items.first)
        XCTAssertEqual(item.destination, "https://receiver.example/hook")
        XCTAssertEqual(meeting.webhookCompletion?.processing?.state, .interrupted)
        let payload = try XCTUnwrap(try body(item)["meeting"] as? [String: Any])
        XCTAssertEqual((payload["transcript"] as? [[String: Any]])?.first?["text"] as? String, "we agreed to ship on Friday")
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
