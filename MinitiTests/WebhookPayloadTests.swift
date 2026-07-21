import XCTest
import SwiftData
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class WebhookPayloadTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: Meeting.self, TranscriptSegment.self, configurations: config)
        context = container.mainContext
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - MEDDPICCData.isEmpty

    func testMEDDPICCDataIsEmptyAllNil() {
        let data = WebhookService.MeetingPayload.MEDDPICCData(
            metrics: nil, economicBuyer: nil, decisionCriteria: nil,
            decisionProcess: nil, paperProcess: nil, identifiedPain: nil,
            champion: nil, competition: nil
        )
        XCTAssertTrue(data.isEmpty)
    }

    func testMEDDPICCDataIsEmptyAllEmpty() {
        let data = WebhookService.MeetingPayload.MEDDPICCData(
            metrics: "", economicBuyer: "", decisionCriteria: "",
            decisionProcess: "", paperProcess: "", identifiedPain: "",
            champion: "", competition: ""
        )
        XCTAssertTrue(data.isEmpty)
    }

    func testMEDDPICCDataIsNotEmpty() {
        let data = WebhookService.MeetingPayload.MEDDPICCData(
            metrics: "Revenue $10M", economicBuyer: nil, decisionCriteria: nil,
            decisionProcess: nil, paperProcess: nil, identifiedPain: nil,
            champion: nil, competition: nil
        )
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - trainingData

    func testTrainingDataNilInput() {
        let result = WebhookService.trainingData(from: nil)
        XCTAssertNil(result)
    }

    func testTrainingDataMapsCorrectly() {
        let fillerEntry = TrainingMetrics.FillerEntry(word: "um", count: 5)
        let speakerStats = TrainingMetrics.SpeakerStats(
            speakerLabel: "You",
            isLocalMic: true,
            wordCount: 100,
            segmentCount: 10,
            fillers: [fillerEntry],
            totalFillers: 5,
            fillersPerMinute: 2.5,
            wordsPerMinute: 120,
            longestMonologueWords: 30,
            questionsAsked: 3,
            avgWordsPerTurn: 10
        )
        let metrics = TrainingMetrics(
            speakers: [speakerStats],
            talkRatioYou: 0.6,
            durationMinutes: 2.0
        )

        let result = WebhookService.trainingData(from: metrics)!
        XCTAssertEqual(result.talkRatioYou, 0.6, accuracy: 0.01)
        XCTAssertEqual(result.durationMinutes, 2.0, accuracy: 0.01)
        XCTAssertEqual(result.speakers.count, 1)

        let speaker = result.speakers[0]
        XCTAssertEqual(speaker.speaker, "You")
        XCTAssertTrue(speaker.isYou)
        XCTAssertEqual(speaker.wordCount, 100)
        XCTAssertEqual(speaker.totalFillers, 5)
        XCTAssertEqual(speaker.fillers["um"], 5)
        XCTAssertEqual(speaker.questionsAsked, 3)
    }

    // MARK: - payloadFromLiveState

    func testPayloadFromLiveStateEvent() {
        let payload = WebhookService.payloadFromLiveState(
            meetingID: UUID(),
            title: "Test Meeting",
            startTime: Date(),
            endTime: Date(),
            durationSeconds: 600,
            summary: "A good meeting",
            actionItems: ["Do stuff"],
            keyDecisions: ["Decision 1"],
            topics: ["Topic 1"],
            discussionFlow: ["Intro"],
            notes: "Some notes",
            metrics: nil, economicBuyer: nil, decisionCriteria: nil,
            decisionProcess: nil, paperProcess: nil, identifiedPain: nil,
            champion: nil, competition: nil,
            speakerCount: 2,
            transcript: [],
            training: nil
        )

        XCTAssertEqual(payload.event, "meeting.saved")
        XCTAssertEqual(payload.meeting.title, "Test Meeting")
        XCTAssertEqual(payload.meeting.durationSeconds, 600)
        XCTAssertEqual(payload.meeting.summary, "A good meeting")
        XCTAssertEqual(payload.meeting.actionItems, ["Do stuff"])
        XCTAssertEqual(payload.meeting.speakerCount, 2)
    }

    func testPayloadFromLiveStateEmptySummaryIsNil() {
        let payload = WebhookService.payloadFromLiveState(
            meetingID: UUID(),
            title: "Test",
            startTime: Date(),
            endTime: nil,
            durationSeconds: 0,
            summary: "",
            actionItems: [],
            keyDecisions: [],
            topics: [],
            discussionFlow: [],
            notes: "",
            metrics: nil, economicBuyer: nil, decisionCriteria: nil,
            decisionProcess: nil, paperProcess: nil, identifiedPain: nil,
            champion: nil, competition: nil,
            speakerCount: 0,
            transcript: [],
            training: nil
        )

        XCTAssertNil(payload.meeting.summary)
        XCTAssertNil(payload.meeting.meddpicc)
    }

    func testPayloadFromLiveStateMEDDPICCIncluded() {
        let payload = WebhookService.payloadFromLiveState(
            meetingID: UUID(),
            title: "Sales Call",
            startTime: Date(),
            endTime: Date(),
            durationSeconds: 1800,
            summary: "Sales discussion",
            actionItems: [],
            keyDecisions: [],
            topics: [],
            discussionFlow: [],
            notes: "",
            metrics: "Revenue: $5M", economicBuyer: "CFO", decisionCriteria: nil,
            decisionProcess: nil, paperProcess: nil, identifiedPain: nil,
            champion: nil, competition: nil,
            speakerCount: 2,
            transcript: [],
            training: nil
        )

        XCTAssertNotNil(payload.meeting.meddpicc)
        XCTAssertEqual(payload.meeting.meddpicc?.metrics, "Revenue: $5M")
    }

    // MARK: - JSON encoding roundtrip

    func testPayloadEncodesToJSON() throws {
        let payload = WebhookService.payloadFromLiveState(
            meetingID: UUID(),
            title: "Test",
            startTime: Date(),
            endTime: nil,
            durationSeconds: 300,
            summary: "Summary",
            actionItems: ["Task 1"],
            keyDecisions: [],
            topics: ["Topic"],
            discussionFlow: [],
            notes: "Notes",
            metrics: nil, economicBuyer: nil, decisionCriteria: nil,
            decisionProcess: nil, paperProcess: nil, identifiedPain: nil,
            champion: nil, competition: nil,
            speakerCount: 1,
            transcript: [
                WebhookService.MeetingPayload.TranscriptEntry(speaker: "You", text: "Hello", timestamp: 0)
            ],
            training: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["event"] as? String, "meeting.saved")
        let meeting = json["meeting"] as! [String: Any]
        XCTAssertEqual(meeting["title"] as? String, "Test")
        XCTAssertEqual(meeting["duration_seconds"] as? Int, 300)
        XCTAssertEqual(meeting["language"] as? String, "en")
        let transcript = meeting["transcript"] as! [[String: Any]]
        XCTAssertEqual(transcript.count, 1)
        XCTAssertEqual(transcript[0]["speaker"] as? String, "You")
    }

    func testPayloadFromLiveStateWithLanguage() {
        let payload = WebhookService.payloadFromLiveState(
            meetingID: UUID(),
            title: "Spanish Call",
            startTime: Date(),
            endTime: Date(),
            durationSeconds: 300,
            language: "es",
            summary: "Una buena reunión",
            actionItems: [],
            keyDecisions: [],
            topics: [],
            discussionFlow: [],
            notes: "",
            metrics: nil, economicBuyer: nil, decisionCriteria: nil,
            decisionProcess: nil, paperProcess: nil, identifiedPain: nil,
            champion: nil, competition: nil,
            speakerCount: 1,
            transcript: [],
            training: nil
        )
        XCTAssertEqual(payload.meeting.language, "es")
    }

    func testPayloadFromLiveStateIncludesSpeakerNamesAndCalendarContext() throws {
        let payload = WebhookService.payloadFromLiveState(
            meetingID: UUID(),
            title: "Pipeline Review",
            startTime: Date(),
            endTime: Date(),
            durationSeconds: 300,
            summary: "Reviewed the deal",
            actionItems: [],
            keyDecisions: [],
            topics: [],
            discussionFlow: [],
            notes: "",
            metrics: nil, economicBuyer: nil, decisionCriteria: nil,
            decisionProcess: nil, paperProcess: nil, identifiedPain: nil,
            champion: nil, competition: nil,
            speakerCount: 2,
            speakerNames: ["0": "Alice", "\(DeepgramService.micSpeakerID)": "You"],
            transcript: [],
            training: nil,
            calendarEventId: "evt_123",
            attendees: [
                MeetingAttendee(
                    email: "alice@example.com",
                    displayName: "Alice",
                    domain: "example.com",
                    responseStatus: "accepted",
                    isOrganizer: false,
                    isSelf: false
                )
            ]
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let meeting = json["meeting"] as! [String: Any]
        let speakerNames = meeting["speaker_names"] as? [String: Any]
        let attendees = meeting["attendees"] as? [[String: Any]]

        XCTAssertEqual(meeting["calendar_event_id"] as? String, "evt_123")
        XCTAssertEqual(speakerNames?["0"] as? String, "Alice")
        XCTAssertEqual(attendees?.first?["email"] as? String, "alice@example.com")
        XCTAssertEqual(attendees?.first?["domain"] as? String, "example.com")
    }

    func testPayloadFromLiveStateOmitsEmptySpeakerNamesAndCalendarContext() throws {
        let payload = WebhookService.payloadFromLiveState(
            meetingID: UUID(),
            title: "Standalone Meeting",
            startTime: Date(),
            endTime: nil,
            durationSeconds: 60,
            summary: "Summary",
            actionItems: [],
            keyDecisions: [],
            topics: [],
            discussionFlow: [],
            notes: "",
            metrics: nil, economicBuyer: nil, decisionCriteria: nil,
            decisionProcess: nil, paperProcess: nil, identifiedPain: nil,
            champion: nil, competition: nil,
            speakerCount: 1,
            transcript: [],
            training: nil
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let meeting = json["meeting"] as! [String: Any]

        XCTAssertNil(meeting["speaker_names"])
        XCTAssertNil(meeting["calendar_event_id"])
        XCTAssertNil(meeting["attendees"])
    }

    // MARK: - payloadFromMeeting

    @MainActor
    func testPayloadFromMeetingBasic() {
        let start = Date()
        let end = start.addingTimeInterval(600)
        let meeting = Meeting(
            title: "Sales Call",
            startTime: start,
            endTime: end,
            summaryText: "Discussed deal terms",
            actionItems: ["Send proposal"],
            keyDecisions: ["Go with vendor A"],
            topics: ["pricing"],
            discussionFlow: ["Introductions", "Pricing discussion"],
            notes: "Good call overall"
        )
        context.insert(meeting)

        let micID = DeepgramService.micSpeakerID
        let seg1 = TranscriptSegment(text: "Hello there", speaker: micID, timestamp: 0, isFinal: true)
        let seg2 = TranscriptSegment(text: "Hi, how are you", speaker: 0, timestamp: 5, isFinal: true)
        let seg3 = TranscriptSegment(text: "interim text", speaker: 0, timestamp: 8, isFinal: false)
        meeting.segments = [seg1, seg2, seg3]

        let payload = WebhookService.payloadFromMeeting(meeting)

        XCTAssertEqual(payload.event, "meeting.updated")
        XCTAssertEqual(payload.meeting.title, "Sales Call")
        XCTAssertEqual(payload.meeting.durationSeconds, 600)
        XCTAssertEqual(payload.meeting.summary, "Discussed deal terms")
        XCTAssertEqual(payload.meeting.actionItems, ["Send proposal"])
        XCTAssertEqual(payload.meeting.keyDecisions, ["Go with vendor A"])
        XCTAssertEqual(payload.meeting.topics, ["pricing"])
        XCTAssertEqual(payload.meeting.notes, "Good call overall")
        XCTAssertEqual(payload.meeting.speakerCount, 2)
        XCTAssertEqual(payload.meeting.transcript.count, 2, "Only final segments in transcript")
        XCTAssertEqual(payload.meeting.transcript[0].speaker, "You")
        XCTAssertEqual(payload.meeting.transcript[1].speaker, "Speaker 1")
    }

    @MainActor
    func testPayloadFromMeetingWithMEDDPICC() {
        let meeting = Meeting(
            title: "Deal Review",
            startTime: Date(),
            endTime: Date().addingTimeInterval(300),
            meddpiccMetrics: "ARR $2M",
            meddpiccChampion: "VP Engineering"
        )
        context.insert(meeting)

        let payload = WebhookService.payloadFromMeeting(meeting)

        XCTAssertNotNil(payload.meeting.meddpicc)
        XCTAssertEqual(payload.meeting.meddpicc?.metrics, "ARR $2M")
        XCTAssertEqual(payload.meeting.meddpicc?.champion, "VP Engineering")
    }

    @MainActor
    func testPayloadFromMeetingNoEndTime() {
        let meeting = Meeting(title: "Interrupted")
        context.insert(meeting)

        let payload = WebhookService.payloadFromMeeting(meeting)
        XCTAssertEqual(payload.meeting.durationSeconds, 0)
        XCTAssertNil(payload.meeting.endTime)
    }

    @MainActor
    func testPayloadFromMeetingTrainingData() {
        let start = Date()
        let end = start.addingTimeInterval(300)
        let meeting = Meeting(title: "Training Test", startTime: start, endTime: end)
        context.insert(meeting)

        let micID = DeepgramService.micSpeakerID
        var segs: [TranscriptSegment] = []
        for i in 0..<10 {
            segs.append(TranscriptSegment(
                text: "This is a test sentence number \(i)",
                speaker: (i % 2 == 0) ? micID : 0,
                timestamp: Double(i) * 30,
                isFinal: true
            ))
        }
        meeting.segments = segs

        let payload = WebhookService.payloadFromMeeting(meeting)
        XCTAssertNotNil(payload.meeting.training)
        XCTAssertFalse(payload.meeting.training!.speakers.isEmpty)
        XCTAssertGreaterThan(payload.meeting.training!.durationMinutes, 0)
    }

    @MainActor
    func testPayloadFromMeetingEncodesAsJSON() throws {
        let meeting = Meeting(
            title: "JSON Test",
            startTime: Date(),
            endTime: Date().addingTimeInterval(120),
            summaryText: "Quick sync"
        )
        context.insert(meeting)
        let seg = TranscriptSegment(text: "Hello", speaker: 0, timestamp: 0, isFinal: true)
        meeting.segments = [seg]

        let payload = WebhookService.payloadFromMeeting(meeting)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["event"] as? String, "meeting.updated")
        let m = json["meeting"] as! [String: Any]
        XCTAssertEqual(m["title"] as? String, "JSON Test")
        XCTAssertEqual(m["duration_seconds"] as? Int, 120)
    }

    func testPayloadFromLiveStateWithQuestions() {
        let questions = [
            SuggestedQuestion(question: "What's the real blocker?", type: "deeper", context: "They mentioned a blocker but didn't elaborate"),
            SuggestedQuestion(question: "Is speed or cost the priority?", type: "challenge", context: "Conflicting statements")
        ]
        let payload = WebhookService.payloadFromLiveState(
            meetingID: UUID(),
            title: "Test",
            startTime: Date(),
            endTime: nil,
            durationSeconds: 120,
            summary: "Test",
            actionItems: [],
            keyDecisions: [],
            topics: [],
            discussionFlow: [],
            notes: "",
            metrics: nil,
            economicBuyer: nil,
            decisionCriteria: nil,
            decisionProcess: nil,
            paperProcess: nil,
            identifiedPain: nil,
            champion: nil,
            competition: nil,
            speakerCount: 1,
            transcript: [],
            training: nil,
            questions: questions
        )
        XCTAssertNotNil(payload.meeting.questions)
        XCTAssertEqual(payload.meeting.questions?.count, 2)
        XCTAssertEqual(payload.meeting.questions?[0].type, "deeper")
    }

    func testPayloadFromLiveStateEmptyQuestionsIsNil() {
        let payload = WebhookService.payloadFromLiveState(
            meetingID: UUID(),
            title: "Test",
            startTime: Date(),
            endTime: nil,
            durationSeconds: 60,
            summary: "Test",
            actionItems: [],
            keyDecisions: [],
            topics: [],
            discussionFlow: [],
            notes: "",
            metrics: nil,
            economicBuyer: nil,
            decisionCriteria: nil,
            decisionProcess: nil,
            paperProcess: nil,
            identifiedPain: nil,
            champion: nil,
            competition: nil,
            speakerCount: 1,
            transcript: [],
            training: nil
        )
        XCTAssertNil(payload.meeting.questions)
    }

    func testPayloadFromLiveStateWithDocs() {
        let docs = [
            DocPlaybookCard(
                topic: "SSO",
                answer: "Use Okta SAML.",
                citations: [DocCitation(title: "SSO setup", url: "https://docs.lightdash.com/sso", snippet: "Okta")],
                priority: "high"
            )
        ]
        let payload = WebhookService.payloadFromLiveState(
            meetingID: UUID(),
            title: "Test",
            startTime: Date(),
            endTime: nil,
            durationSeconds: 120,
            summary: "Test",
            actionItems: [],
            keyDecisions: [],
            topics: [],
            discussionFlow: [],
            notes: "",
            metrics: nil,
            economicBuyer: nil,
            decisionCriteria: nil,
            decisionProcess: nil,
            paperProcess: nil,
            identifiedPain: nil,
            champion: nil,
            competition: nil,
            speakerCount: 1,
            transcript: [],
            training: nil,
            docs: docs
        )
        XCTAssertEqual(payload.meeting.docs?.count, 1)
        XCTAssertEqual(payload.meeting.docs?[0].topic, "SSO")
        XCTAssertEqual(payload.meeting.docs?[0].citations.first?.url, "https://docs.lightdash.com/sso")
    }
}
