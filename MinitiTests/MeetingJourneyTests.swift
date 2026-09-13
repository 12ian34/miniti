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
/// manual boundary (see docs/testing.md); everything after "final segments arrived" runs here.
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
