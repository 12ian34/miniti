import XCTest
import SwiftData
import SwiftUI
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class WebhookPayloadTests: XCTestCase, @unchecked Sendable {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = TestSupport.retain(try! ModelContainer(for: Meeting.self, TranscriptSegment.self, configurations: config))
            context = container.mainContext
        }
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Transport policy (P0.9)

    func testWebhookURLRequiresHTTPSWithHost() {
        XCTAssertEqual(WebhookService.validate(""), .empty)
        XCTAssertEqual(WebhookService.validate("   "), .empty)
        XCTAssertEqual(WebhookService.validate("hooks.zapier.com/hooks/catch/1/abc"), .malformed)
        XCTAssertEqual(WebhookService.validate("https://"), .malformed)
        XCTAssertEqual(WebhookService.validate("ftp://example.com/hook"), .unsupportedScheme)
        XCTAssertEqual(WebhookService.validate("http://hooks.zapier.com/hooks/catch/1/abc"), .plaintextTransport)
        XCTAssertEqual(WebhookService.validate("HTTP://example.com/x"), .plaintextTransport)
        XCTAssertTrue(WebhookService.validate("https://hooks.zapier.com/hooks/catch/1/abc").isValid)
        XCTAssertTrue(WebhookService.validate(" https://example.com/hook?token=1 ").isValid)
    }

    func testPlaintextIsAllowedOnlyToLoopback() {
        XCTAssertTrue(WebhookService.validate("http://localhost:5678/webhook/x").isValid)
        XCTAssertTrue(WebhookService.validate("http://127.0.0.1/hook").isValid)
        XCTAssertTrue(WebhookService.validate("http://LOCALHOST/hook").isValid)
        XCTAssertEqual(WebhookService.validate("http://192.168.1.20:5678/webhook/x"), .plaintextTransport)
        XCTAssertEqual(WebhookService.validate("http://localhost.example.com/hook"), .plaintextTransport)
    }

    func testValidationMessagesOnlyForRejectedURLs() {
        XCTAssertNil(WebhookService.validationMessage(for: ""))
        XCTAssertNil(WebhookService.validationMessage(for: "https://example.com/hook"))
        XCTAssertNotNil(WebhookService.validationMessage(for: "http://example.com/hook"))
        XCTAssertNotNil(WebhookService.validationMessage(for: "not a url"))
    }

    func testRedactedEndpointKeepsOnlySchemeAndHost() {
        XCTAssertEqual(
            WebhookService.redactedEndpoint("https://hooks.zapier.com/hooks/catch/123456/abcdef/?key=secret"),
            "https://hooks.zapier.com"
        )
        XCTAssertEqual(WebhookService.redactedEndpoint("https://user:pass@example.com:8443/path/token"), "https://example.com:8443")
        XCTAssertEqual(WebhookService.redactedEndpoint("http://localhost:5678/webhook/abc"), "http://localhost:5678")
        XCTAssertEqual(WebhookService.redactedEndpoint("garbage"), "<invalid url>")
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

    func testPayloadFromLiveStateWithTemplate() throws {
        let template = try XCTUnwrap(InsightTemplate.builtIn(id: "standup"))
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
            template: template,
            templateSections: ["blockers": "Design review", "done": "Importer shipped", "ghost": "dropped"]
        )
        let data = try XCTUnwrap(payload.meeting.template)
        XCTAssertEqual(data.id, "standup")
        XCTAssertEqual(data.name, "Stand-up")
        XCTAssertEqual(data.sections.map(\.key), ["done", "blockers"], "template order, unknown keys dropped")
        XCTAssertEqual(data.sections.first?.value, "Importer shipped")

        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(json.contains("\"template\""))
        XCTAssertTrue(json.contains("\"key\":\"done\""))
    }

    func testPayloadOmitsTemplateWhenNothingFilled() {
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
            template: InsightTemplate.builtIn(id: "bant"),
            templateSections: [:]
        )
        XCTAssertNil(payload.meeting.template)
    }

    @MainActor
    func testPayloadFromMeetingWithTemplate() throws {
        let meeting = Meeting(title: "Weekly stand-up", endTime: Date())
        meeting.insightTemplateID = "standup"
        meeting.templateSections = ["next": "Ship the fix"]
        context.insert(meeting)

        let payload = WebhookService.payloadFromMeeting(meeting)
        XCTAssertEqual(payload.meeting.template?.id, "standup")
        XCTAssertEqual(payload.meeting.template?.sections.map(\.value), ["Ship the fix"])
    }

    @MainActor
    func testSettledWebhookIsSelfContainedWithAdditiveProcessing() throws {
        let meeting = Meeting(title: "Finished", summaryText: "Final summary", actionItems: ["Follow up"])
        context.insert(meeting)
        meeting.segments = [TranscriptSegment(text: "Saved final words", speaker: 0, timestamp: 1, isFinal: true)]
        meeting.transcriptRevision = 7
        let processing = WebhookService.Processing(inputTranscriptRevision: 7, state: .partial, outcomes: ["standard": .complete, "questions": .failed])
        let payload = WebhookService.payloadFromMeeting(meeting, event: "meeting.saved", processing: processing)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: WebhookService.encode(payload)) as? [String: Any])
        XCTAssertEqual(json["event"] as? String, "meeting.saved")
        let data = try XCTUnwrap(json["meeting"] as? [String: Any])
        XCTAssertEqual(data["summary"] as? String, "Final summary")
        let transcript = try XCTUnwrap(data["transcript"] as? [[String: Any]])
        XCTAssertEqual(transcript.first?["text"] as? String, "Saved final words")
        let state = try XCTUnwrap(json["processing"] as? [String: Any])
        XCTAssertEqual(state["input_transcript_revision"] as? Int, 7)
        XCTAssertEqual(state["state"] as? String, "partial")
        XCTAssertEqual(state["outcomes"] as? [String: String], ["standard": "complete", "questions": "failed"])
        XCTAssertEqual(try JSONDecoder().decode(WebhookService.Processing.self, from: JSONEncoder().encode(processing)), processing, "local completion marker uses the same Codable outcome")
        let legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: WebhookService.encode(WebhookService.payloadFromMeeting(meeting))) as? [String: Any])
        XCTAssertNil(legacy["processing"], "metadata is additive, not required by older call sites")
    }

    @MainActor
    func testStaleWebhookKeepsTranscriptButOmitsGeneratedContent() throws {
        let meeting = Meeting(title: "Edited", summaryText: "Old summary", actionItems: ["Old action"], keyDecisions: ["Old decision"], topics: ["Old topic"], notes: "My notes")
        context.insert(meeting)
        meeting.segments = [TranscriptSegment(text: "Remaining words", speaker: 0, timestamp: 1, isFinal: true)]
        meeting.meddpiccChampion = "Old champion"
        let payload = WebhookService.payloadFromMeeting(meeting, processing: .init(inputTranscriptRevision: 2, state: .interrupted, outcomes: ["standard": .stale]), insightsStale: true)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: WebhookService.encode(payload)) as? [String: Any])
        let data = try XCTUnwrap(json["meeting"] as? [String: Any])
        XCTAssertEqual(data["insights_stale"] as? Bool, true)
        XCTAssertNil(data["summary"])
        XCTAssertNil(data["meddpicc"])
        XCTAssertNil(data["template"])
        XCTAssertNil(data["questions"])
        XCTAssertNil(data["docs"])
        XCTAssertEqual(data["action_items"] as? [String], [])
        XCTAssertEqual(data["topics"] as? [String], [])
        XCTAssertEqual(data["notes"] as? String, "My notes")
        XCTAssertEqual((data["transcript"] as? [[String: Any]])?.first?["text"] as? String, "Remaining words")
    }

}

// Frozen 3.5.0 persisted fields, without computed helpers. Exercises the actual additive
// migration on SQLite, rather than creating a new store with today's schema.
private enum DeliveryStore350 {
@Model
final class Meeting {
    var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date?
    @Relationship(deleteRule: .cascade) var segments: [TranscriptSegment]
    var summaryText: String?
    var actionItems: [String]
    var keyDecisions: [String]
    var topics: [String]
    var discussionFlow: [String] = []
    var notes: String = ""
    var transcriptEditedAt: Date?
    /// Name of the markdown file this meeting was last exported as, so a later export
    /// after a rename replaces it instead of leaving two files (2.11.0).
    var lastExportedMarkdownFilename: String?
    var transcriptRevision: Int = 0
    var isPinned: Bool = false
    var insightsUpdatedAt: Date?

    var managedSessionId: String?
    var language: String = "en"

    var calendarEventId: String?
    /// The calendar event's own title, kept even if the meeting is renamed, so `title:`
    /// search finds the call by what the calendar called it (2.11.0; nil before).
    var calendarEventTitle: String?
    var attendeesJSON: String?

    // Import provenance. Optional fields keep existing SwiftData stores lightweight-migratable.
    var externalSource: String?
    var externalID: String?
    var externalURL: String?
    var importedAt: Date?
    /// Where the audio was captured (`RecordingDevice` raw value), set when a recording starts
    /// and carried through the cloud as `recorded_on`. Nil for meetings from before 3.1.0,
    /// which the device filter therefore never matches.
    var recordedOnRaw: String?

    // MEDDPICC fields
    var meddpiccMetrics: String?
    var meddpiccEconomicBuyer: String?
    var meddpiccDecisionCriteria: String?
    var meddpiccDecisionProcess: String?
    var meddpiccPaperProcess: String?
    var meddpiccIdentifiedPain: String?
    var meddpiccChampion: String?
    var meddpiccCompetition: String?

    // Suggested questions (JSON-encoded [SuggestedQuestion])
    var suggestedQuestionsJSON: String?

    // Templates specialist view: which built-in template this meeting uses, and its filled
    // sections (JSON-encoded [String: String], section key -> text). Optional columns keep
    // existing stores lightweight-migratable.
    var insightTemplateID: String?
    var templateSectionsJSON: String?
    // JSON-encoded InsightTemplate for custom templates, so a meeting keeps rendering its
    // sections after the template is edited or deleted (2.9.0). Nil for built-ins.
    var templateDefinitionJSON: String?

    // Docs topics + their resolved lookup cards (JSON-encoded [DocTopic])
    var docTopicsJSON: String?

    // Inferred speaker names (JSON-encoded [String: String] where key is speaker ID as string)
    var speakerNamesJSON: String?

    // Speaker IDs (as strings) that the user has manually named/overridden.
    // Present entries — even if the name is the same as the inference — are excluded
    // from automatic inference merges. JSON-encoded [String] for backward compat.
    var speakerOverridesJSON: String?
    /// Speaker id to attendee email, only for picks made by hand or received from another device
    /// (3.2.0). Matches derived from the name and the attendee list are computed on read, see
    /// `speakerEmail(for:)`, so they follow a rename without bookkeeping.
    var speakerEmailsJSON: String?

    // Legacy single-speaker "self" marker. Kept for SwiftData backward compat with meetings
    // saved before multi-self support landed. New code should read/write `selfSpeakerIDs`.
    var selfSpeakerID: Int?

    // All speaker IDs the user has marked as themselves ("You"). JSON-encoded [Int].
    // Supports the case where diarization splits one person across multiple speaker IDs —
    // marking each of those IDs as "You" unifies their training stats and transcript label.
    var selfSpeakerIDsJSON: String?

    // Optional internal environment inference (InferredMeetingEnvironment raw value).
    // Diagnostic metadata only — never user-facing, never required to load, trim,
    // export, search, or regenerate insights. Nil (all legacy meetings) = unknown.
    var inferredEnvironmentRaw: String?

    // Cloud sync bookkeeping (3.0.0). All optional or defaulted so existing stores
    // lightweight-migrate; none of it is read while cloud sync is off.
    /// When the meeting last changed on any device, the last-writer-wins key on the wire.
    /// Set by the sync engine when it notices a fingerprint change, or from the server.
    var updatedAt: Date?
    /// When this device last agreed with the cloud copy.
    var syncedAt: Date?
    /// Server revision of the cloud copy this device last saw; 0 = never synced.
    var cloudRevision: Int = 0
    /// Fingerprint of the content the cloud copy holds (what was last pushed or pulled).
    var syncFingerprint: String?
    /// Fingerprint the engine last observed locally; a difference from `syncFingerprint`
    /// means the meeting is dirty.
    var localFingerprint: String?
    /// Never upload this meeting. Set for meetings recorded under private mode and by the
    /// per-meeting "Keep off the cloud" action.
    var syncExcluded: Bool = false
    /// Explicit user request to put a retained local original back after cloud deletion.
    /// Never populated from a downloaded sync document.
    var cloudRestoreRequested: Bool = false
    /// `skipped_too_large` or nil. Shown in Settings → Cloud.
    var syncStateRaw: String?
    /// Fields from another client (Linux) this build does not model, echoed back untouched.
    var syncExtraJSON: String?

    init(
        id: UUID = UUID(),
        title: String = "new",
        startTime: Date = Date(),
        endTime: Date? = nil,
        segments: [TranscriptSegment] = [],
        summaryText: String? = nil,
        actionItems: [String] = [],
        keyDecisions: [String] = [],
        topics: [String] = [],
        discussionFlow: [String] = [],
        notes: String = "",
        transcriptEditedAt: Date? = nil,
        transcriptRevision: Int = 0,
        isPinned: Bool = false,
        insightsUpdatedAt: Date? = nil,
        externalSource: String? = nil,
        externalID: String? = nil,
        externalURL: String? = nil,
        importedAt: Date? = nil,
        meddpiccMetrics: String? = nil,
        meddpiccEconomicBuyer: String? = nil,
        meddpiccDecisionCriteria: String? = nil,
        meddpiccDecisionProcess: String? = nil,
        meddpiccPaperProcess: String? = nil,
        meddpiccIdentifiedPain: String? = nil,
        meddpiccChampion: String? = nil,
        meddpiccCompetition: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.segments = segments
        self.summaryText = summaryText
        self.actionItems = actionItems
        self.keyDecisions = keyDecisions
        self.topics = topics
        self.discussionFlow = discussionFlow
        self.notes = notes
        self.transcriptEditedAt = transcriptEditedAt
        self.transcriptRevision = transcriptRevision
        self.isPinned = isPinned
        self.insightsUpdatedAt = insightsUpdatedAt
        self.externalSource = externalSource
        self.externalID = externalID
        self.externalURL = externalURL
        self.importedAt = importedAt
        self.meddpiccMetrics = meddpiccMetrics
        self.meddpiccEconomicBuyer = meddpiccEconomicBuyer
        self.meddpiccDecisionCriteria = meddpiccDecisionCriteria
        self.meddpiccDecisionProcess = meddpiccDecisionProcess
        self.meddpiccPaperProcess = meddpiccPaperProcess
        self.meddpiccIdentifiedPain = meddpiccIdentifiedPain
        self.meddpiccChampion = meddpiccChampion
        self.meddpiccCompetition = meddpiccCompetition
    }

}
@Model
final class TranscriptSegment {
    var id: UUID
    var text: String
    var speaker: Int
    var timestamp: TimeInterval
    var isFinal: Bool
    var confidence: Double
    /// Explicit capture source (TranscriptSource raw value). Optional and additive so
    /// existing stores lightweight-migrate; nil (all legacy segments) falls back to the
    /// reserved mic ID range where source matters.
    var sourceRaw: String?

    init(
        id: UUID = UUID(),
        text: String,
        speaker: Int = 0,
        timestamp: TimeInterval,
        isFinal: Bool = false,
        confidence: Double = 1.0,
        sourceRaw: String? = nil
    ) {
        self.id = id
        self.text = text
        self.speaker = speaker
        self.timestamp = timestamp
        self.isFinal = isFinal
        self.confidence = confidence
        self.sourceRaw = sourceRaw
    }

}
}

@MainActor
final class DeliveryStoreMigrationTests: XCTestCase {
    func test350StoreUpgradesAndCompletionMarkerSurvivesReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("meetings.store")
        let id = UUID()
        try autoreleasepool {
            let legacy = try ModelContainer(for: DeliveryStore350.Meeting.self, DeliveryStore350.TranscriptSegment.self, MeetingTombstone.self,
                configurations: ModelConfiguration(url: url))
            let meeting = DeliveryStore350.Meeting(id: id, title: "existing meeting", endTime: Date(),
                segments: [DeliveryStore350.TranscriptSegment(text: "keep this transcript", timestamp: 1, isFinal: true)], summaryText: "keep this summary")
            meeting.syncExcluded = true
            meeting.cloudRevision = 12
            legacy.mainContext.insert(meeting)
            try legacy.mainContext.save()
        }
        let deliveryID = UUID()
        try autoreleasepool {
            let upgraded = try ModelContainer(for: Meeting.self, TranscriptSegment.self, MeetingTombstone.self,
                configurations: ModelConfiguration(url: url))
            let meeting = try XCTUnwrap(upgraded.mainContext.fetch(FetchDescriptor<Meeting>()).first)
            XCTAssertEqual(meeting.id, id)
            XCTAssertEqual(meeting.title, "existing meeting")
            XCTAssertEqual(meeting.segments.first?.text, "keep this transcript")
            XCTAssertEqual(meeting.summaryText, "keep this summary")
            XCTAssertTrue(meeting.syncExcluded)
            XCTAssertEqual(meeting.cloudRevision, 12)
            XCTAssertNil(meeting.webhookCompletion)
            meeting.webhookCompletion = WebhookCompletion(id: deliveryID, phase: .ready, revision: 0, createdAt: Date(), accountID: nil, processing: nil)
            try upgraded.mainContext.save()
        }
        try autoreleasepool {
            let reopened = try ModelContainer(for: Meeting.self, TranscriptSegment.self, MeetingTombstone.self,
                configurations: ModelConfiguration(url: url))
            let meeting = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Meeting>()).first)
            XCTAssertEqual(meeting.webhookCompletion?.id, deliveryID)
            XCTAssertEqual(meeting.webhookCompletion?.phase, .ready)
            XCTAssertEqual(meeting.segments.first?.text, "keep this transcript")
        }
    }
}

/// Real SwiftUI controls hosted by the platform view system. The PNGs are release-review
/// evidence; model/action tests elsewhere cover current-data resend and its durability.
@MainActor
final class DeliveryControlsRenderingTests: XCTestCase {
    private func failedOutbox(in directory: URL) throws -> DeliveryOutbox {
        let item = DeliveryOutbox.Item(id: UUID(), kind: .webhook, meetingID: UUID(),
            event: "meeting.saved", createdAt: Date(), attempts: 6, nextAttemptAt: Date(),
            state: .failed, lastError: "Delivery expired", body: nil, destination: nil)
        let url = directory.appendingPathComponent("render-outbox.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([item]).write(to: url, options: .atomic)
        let outbox = DeliveryOutbox(storeURL: url)
        XCTAssertNil(outbox.persistenceError, "render fixture must decode using the production date format")
        XCTAssertEqual(outbox.failed(.webhook).count, 1)
        return outbox
    }

    private func saveRender(_ data: Data, name: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("miniti-360-delivery-renders")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name + ".png")
        try data.write(to: url, options: .atomic)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixels = try XCTUnwrap(image.dataProvider?.data) as Data
        XCTAssertGreaterThan(Set(pixels).count, 16, "a blank/offscreen bitmap is not rendered QA evidence")
        print("DELIVERY_RENDER: \(url.path)")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    #if os(macOS)
    func testFailedWebhookControlsRenderAtMacSettingsWidth() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = try failedOutbox(in: directory)
        let state = AppState()
        state.deliveryOutbox = outbox
        let root = VStack(alignment: .leading, spacing: 12) {
            Text("Webhooks").font(.headline)
            DeliveryStatusRow(kind: .webhook, outbox: outbox)
        }
        .padding(20)
        .frame(width: 600, alignment: .leading)
        .background(ColorPalette.Background.primary)
        .environmentObject(state)
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        let fitting = host.fittingSize
        XCTAssertEqual(fitting.width, 600, accuracy: 1)
        XCTAssertGreaterThan(fitting.height, 50)
        XCTAssertLessThan(fitting.height, 260)
        let previousWindow = NSApp.keyWindow
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: fitting)
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close(); previousWindow?.makeKey() }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try saveRender(XCTUnwrap(bitmap.representation(using: .png, properties: [:])), name: "mac-failed-webhook-600")
        XCTAssertEqual(outbox.failed(.webhook).count, 1, "presenting controls must not retry or discard")
    }
    #else
    func testFailedWebhookControlsRenderAtPhoneAccessibilityAndTabletWidths() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = try failedOutbox(in: directory)
        let state = AppState()
        state.deliveryOutbox = outbox
        let cases: [(String, CGFloat, DynamicTypeSize)] = [
            ("iphone-failed-webhook-390", 390, .large),
            ("iphone-failed-webhook-accessibility-390", 390, .accessibility3),
            ("ipad-failed-webhook-768", 768, .large)
        ]
        for (name, width, typeSize) in cases {
            let root = VStack(alignment: .leading, spacing: 12) {
                Text("Webhooks").font(.headline)
                DeliveryStatusRow_iOS(outbox: outbox)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorPalette.Background.primary)
            .environmentObject(state)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, typeSize)
            let host = UIHostingController(rootView: root)
            host.loadViewIfNeeded()
            let size = host.sizeThatFits(in: CGSize(width: width, height: 1000))
            XCTAssertEqual(size.width, width, accuracy: 1)
            XCTAssertGreaterThan(size.height, 60)
            XCTAssertLessThan(size.height, 600, "controls must fit a compact phone without clipping")
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousWindow = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; previousWindow?.makeKey() }
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            host.view.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(size: size)
            var drewHierarchy = false
            let data = renderer.pngData { _ in
                drewHierarchy = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            XCTAssertTrue(drewHierarchy, "native hosting hierarchy must finish drawing")
            try saveRender(data, name: name)
            window.isHidden = true
            previousWindow?.makeKey()
            XCTAssertEqual(outbox.failed(.webhook).count, 1, "presenting controls must not retry or discard")
        }
    }
    #endif
}
