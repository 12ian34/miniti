import XCTest
import SwiftData
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class MeetingModelTests: XCTestCase {

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

    // MARK: - TranscriptSegment

    @MainActor
    func testSpeakerLabelMic() {
        let segment = TranscriptSegment(text: "Hello", speaker: DeepgramService.micSpeakerID, timestamp: 0, isFinal: true)
        XCTAssertEqual(segment.speakerLabel, "You")
    }

    @MainActor
    func testSpeakerLabelRemote() {
        let segment = TranscriptSegment(text: "Hi", speaker: 0, timestamp: 0, isFinal: true)
        XCTAssertEqual(segment.speakerLabel, "Speaker 1")
    }

    @MainActor
    func testSpeakerLabelRemoteHigherID() {
        let segment = TranscriptSegment(text: "Hi", speaker: 2, timestamp: 0, isFinal: true)
        XCTAssertEqual(segment.speakerLabel, "Speaker 3")
    }

    @MainActor
    func testFormattedTimestamp() {
        let segment = TranscriptSegment(text: "Test", speaker: 0, timestamp: 125, isFinal: true) // 2:05
        XCTAssertEqual(segment.formattedTimestamp, "2:05")
    }

    @MainActor
    func testFormattedTimestampZero() {
        let segment = TranscriptSegment(text: "Test", speaker: 0, timestamp: 0, isFinal: true)
        XCTAssertEqual(segment.formattedTimestamp, "0:00")
    }

    @MainActor
    func testFormattedTimestampLong() {
        let segment = TranscriptSegment(text: "Test", speaker: 0, timestamp: 3661, isFinal: true) // 61:01
        XCTAssertEqual(segment.formattedTimestamp, "61:01")
    }

    // MARK: - Meeting.hasMEDDPICC

    @MainActor
    func testHasMEDDPICCAllNil() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        XCTAssertFalse(meeting.hasMEDDPICC)
    }

    @MainActor
    func testHasMEDDPICCOneField() {
        let meeting = Meeting(title: "test", meddpiccMetrics: "Revenue target: $10M")
        context.insert(meeting)
        XCTAssertTrue(meeting.hasMEDDPICC)
    }

    @MainActor
    func testHasMEDDPICCPlaceholderValues() {
        let meeting = Meeting(title: "test", meddpiccMetrics: "null", meddpiccChampion: "n/a", meddpiccCompetition: "none")
        context.insert(meeting)
        XCTAssertFalse(meeting.hasMEDDPICC)
    }

    @MainActor
    func testHasMEDDPICCEmptyString() {
        let meeting = Meeting(title: "test", meddpiccMetrics: "  ")
        context.insert(meeting)
        XCTAssertFalse(meeting.hasMEDDPICC)
    }

    // MARK: - Meeting.duration & formattedDuration

    @MainActor
    func testDurationWithEndTime() {
        let start = Date()
        let end = start.addingTimeInterval(1800) // 30 minutes
        let meeting = Meeting(title: "test", startTime: start, endTime: end)
        context.insert(meeting)

        XCTAssertEqual(meeting.duration!, 1800, accuracy: 0.1)
        XCTAssertEqual(meeting.formattedDuration, "30m")
    }

    @MainActor
    func testDurationNoEndTime() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)

        XCTAssertNil(meeting.duration)
        XCTAssertEqual(meeting.formattedDuration, "In progress")
    }

    @MainActor
    func testDurationWithHours() {
        let start = Date()
        let end = start.addingTimeInterval(5400) // 1h 30m
        let meeting = Meeting(title: "test", startTime: start, endTime: end)
        context.insert(meeting)

        XCTAssertEqual(meeting.formattedDuration, "1h 30m")
    }

    // MARK: - Meeting.hasInsights

    @MainActor
    func testHasInsightsNone() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        XCTAssertFalse(meeting.hasInsights)
    }

    @MainActor
    func testHasInsightsWithSummary() {
        let meeting = Meeting(title: "test", summaryText: "A meeting about things")
        context.insert(meeting)
        XCTAssertTrue(meeting.hasInsights)
    }

    @MainActor
    func testHasInsightsWithActionItems() {
        let meeting = Meeting(title: "test", actionItems: ["Do something"])
        context.insert(meeting)
        XCTAssertTrue(meeting.hasInsights)
    }

    // MARK: - Meeting.fullTranscript

    @MainActor
    func testFullTranscript() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)

        let seg1 = TranscriptSegment(text: "Hello there", speaker: 1000, timestamp: 0, isFinal: true)
        let seg2 = TranscriptSegment(text: "Hi how are you", speaker: 0, timestamp: 5, isFinal: true)
        let seg3 = TranscriptSegment(text: "interim", speaker: 0, timestamp: 6, isFinal: false)
        meeting.segments = [seg1, seg2, seg3]

        let transcript = meeting.fullTranscript
        XCTAssertTrue(transcript.contains("[You] Hello there"))
        XCTAssertTrue(transcript.contains("[Speaker 1] Hi how are you"))
        XCTAssertFalse(transcript.contains("interim"))
    }

    // MARK: - Markdown export

    @MainActor
    func testNotesAsMarkdownEmpty() {
        let meeting = Meeting(title: "test", notes: "")
        context.insert(meeting)
        XCTAssertEqual(meeting.notesAsMarkdown(), "")
    }

    @MainActor
    func testNotesAsMarkdownWithContent() {
        let meeting = Meeting(title: "test", notes: "Some important notes")
        context.insert(meeting)
        XCTAssertEqual(meeting.notesAsMarkdown(), "## Notes\n\nSome important notes")
    }

    @MainActor
    func testInsightsAsMarkdownStructure() {
        let meeting = Meeting(
            title: "test",
            summaryText: "A productive meeting",
            actionItems: ["Review budget"],
            topics: ["Budget"],
            discussionFlow: ["Intro", "Discussion"]
        )
        context.insert(meeting)

        let md = meeting.insightsAsMarkdown()
        XCTAssertTrue(md.contains("### Summary"))
        XCTAssertTrue(md.contains("A productive meeting"))
        XCTAssertTrue(md.contains("### Action Items"))
        XCTAssertTrue(md.contains("- [ ] Review budget"))
        XCTAssertTrue(md.contains("### Topics"))
        XCTAssertTrue(md.contains("### Discussion Flow"))
        XCTAssertTrue(md.contains("1. Intro"))
    }

    @MainActor
    func testInsightsAsMarkdownIncludesMEDDPICC() {
        let meeting = Meeting(
            title: "test",
            summaryText: "Sales call",
            meddpiccMetrics: "Revenue: $10M"
        )
        context.insert(meeting)

        let md = meeting.insightsAsMarkdown()
        XCTAssertTrue(md.contains("### MEDDPICC"))
        XCTAssertTrue(md.contains("**Metrics:**"))
    }

    @MainActor
    func testTranscriptAsMarkdown() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)

        let seg1 = TranscriptSegment(text: "First sentence.", speaker: 1000, timestamp: 0, isFinal: true)
        let seg2 = TranscriptSegment(text: "Second sentence.", speaker: 1000, timestamp: 5, isFinal: true)
        let seg3 = TranscriptSegment(text: "Other person.", speaker: 0, timestamp: 10, isFinal: true)
        meeting.segments = [seg1, seg2, seg3]

        let md = meeting.transcriptAsMarkdown()
        XCTAssertTrue(md.contains("## Transcript"))
        XCTAssertTrue(md.contains("**You:**"))
        XCTAssertTrue(md.contains("**Speaker 1:**"))
    }

    // MARK: - MeetingSearchResult

    @MainActor
    func testSearchByTitle() {
        let meeting = Meeting(title: "Q4 Planning Review")
        context.insert(meeting)

        let results = MeetingSearchResult.search(query: "planning", in: [meeting])
        XCTAssertEqual(results.count, 1)
        XCTAssertGreaterThanOrEqual(results[0].score, 100)
    }

    @MainActor
    func testSearchEmptyQuery() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)

        let results = MeetingSearchResult.search(query: "", in: [meeting])
        XCTAssertTrue(results.isEmpty)
    }

    @MainActor
    func testSearchNoMatch() {
        let meeting = Meeting(title: "Q4 Planning")
        context.insert(meeting)

        let results = MeetingSearchResult.search(query: "zzzznotfound", in: [meeting])
        XCTAssertTrue(results.isEmpty)
    }

    @MainActor
    func testSearchByTopics() {
        let meeting = Meeting(title: "Team Meeting", topics: ["Budget", "Timeline"])
        context.insert(meeting)

        let results = MeetingSearchResult.search(query: "budget", in: [meeting])
        XCTAssertEqual(results.count, 1)
    }

    @MainActor
    func testSearchBySummary() {
        let meeting = Meeting(title: "Team Meeting", summaryText: "Discussed the quarterly roadmap")
        context.insert(meeting)

        let results = MeetingSearchResult.search(query: "roadmap", in: [meeting])
        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results[0].snippet)
    }

    // MARK: - hasInsights with keyDecisions only

    @MainActor
    func testHasInsightsWithKeyDecisionsOnly() {
        let meeting = Meeting(title: "test", keyDecisions: ["Ship by Friday"])
        context.insert(meeting)
        XCTAssertTrue(meeting.hasInsights)
    }

    @MainActor
    func testHasInsightsEmptyKeyDecisions() {
        let meeting = Meeting(title: "test", keyDecisions: [])
        context.insert(meeting)
        XCTAssertFalse(meeting.hasInsights)
    }

    // MARK: - trainingMetricsAsMarkdown

    @MainActor
    func testTrainingMetricsAsMarkdownWithSegments() {
        let start = Date()
        let end = start.addingTimeInterval(300) // 5 minutes
        let meeting = Meeting(title: "Training Test", startTime: start, endTime: end)
        context.insert(meeting)

        let micID = DeepgramService.micSpeakerID
        var segs: [TranscriptSegment] = []
        for i in 0..<20 {
            let speaker = (i % 3 == 0) ? micID : 0
            segs.append(TranscriptSegment(
                text: "This is sentence number \(i) from a speaker",
                speaker: speaker,
                timestamp: Double(i) * 15,
                isFinal: true
            ))
        }
        meeting.segments = segs

        let md = meeting.trainingMetricsAsMarkdown()
        XCTAssertTrue(md.contains("## Training"))
        XCTAssertTrue(md.contains("**Duration:**"))
        XCTAssertTrue(md.contains("Pace:"))
        XCTAssertTrue(md.contains("Fillers:"))
        XCTAssertTrue(md.contains("Longest monologue:"))
        XCTAssertTrue(md.contains("Questions asked:"))
        XCTAssertTrue(md.contains("Clarity:"))
    }

    @MainActor
    func testTrainingMetricsAsMarkdownNoEndTime() {
        let meeting = Meeting(title: "No End")
        context.insert(meeting)

        let md = meeting.trainingMetricsAsMarkdown()
        XCTAssertEqual(md, "")
    }

    @MainActor
    func testTrainingMetricsAsMarkdownNoSegments() {
        let start = Date()
        let end = start.addingTimeInterval(300)
        let meeting = Meeting(title: "Empty", startTime: start, endTime: end)
        context.insert(meeting)

        let md = meeting.trainingMetricsAsMarkdown()
        XCTAssertEqual(md, "")
    }

    // MARK: - fullMeetingAsMarkdown

    @MainActor
    func testFullMeetingAsMarkdownStructure() {
        let start = Date()
        let end = start.addingTimeInterval(600)
        let meeting = Meeting(
            title: "Full Test",
            startTime: start,
            endTime: end,
            summaryText: "A productive call",
            actionItems: ["Follow up"],
            topics: ["planning"],
            notes: "Some important notes"
        )
        context.insert(meeting)

        let seg = TranscriptSegment(text: "Hello world", speaker: 0, timestamp: 0, isFinal: true)
        meeting.segments = [seg]

        let md = meeting.fullMeetingAsMarkdown()
        XCTAssertTrue(md.hasPrefix("# Full Test"))
        XCTAssertTrue(md.contains("## Notes"))
        XCTAssertTrue(md.contains("Some important notes"))
        XCTAssertTrue(md.contains("### Summary"))
        XCTAssertTrue(md.contains("## Transcript"))
    }

    @MainActor
    func testFullMeetingAsMarkdownNoNotes() {
        let meeting = Meeting(
            title: "No Notes",
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            summaryText: "Brief call"
        )
        context.insert(meeting)

        let md = meeting.fullMeetingAsMarkdown()
        XCTAssertTrue(md.contains("# No Notes"))
        XCTAssertFalse(md.contains("## Notes"))
        XCTAssertTrue(md.contains("### Summary"))
    }

    // MARK: - MeetingSearchResult expanded

    @MainActor
    func testSearchByNotes() {
        let meeting = Meeting(title: "Standup", notes: "Discuss the deployment pipeline")
        context.insert(meeting)

        let results = MeetingSearchResult.search(query: "pipeline", in: [meeting])
        XCTAssertEqual(results.count, 1)
    }

    @MainActor
    func testSearchByActionItems() {
        let meeting = Meeting(title: "Review", actionItems: ["Fix the authentication bug"])
        context.insert(meeting)

        let results = MeetingSearchResult.search(query: "authentication", in: [meeting])
        XCTAssertEqual(results.count, 1)
    }

    @MainActor
    func testSearchByDiscussionFlow() {
        let meeting = Meeting(title: "Strategy", discussionFlow: ["Talked about market expansion"])
        context.insert(meeting)

        let results = MeetingSearchResult.search(query: "expansion", in: [meeting])
        XCTAssertEqual(results.count, 1)
    }

    @MainActor
    func testSearchByMEDDPICC() {
        let meeting = Meeting(title: "Sales Call", meddpiccMetrics: "Annual contract value 50K")
        context.insert(meeting)

        let results = MeetingSearchResult.search(query: "contract", in: [meeting])
        XCTAssertEqual(results.count, 1)
    }

    @MainActor
    func testSearchByTranscriptLongQuery() {
        let meeting = Meeting(title: "Call")
        context.insert(meeting)
        let seg = TranscriptSegment(text: "We should investigate the performance regression", speaker: 0, timestamp: 0, isFinal: true)
        meeting.segments = [seg]

        let results = MeetingSearchResult.search(query: "performance", in: [meeting])
        XCTAssertEqual(results.count, 1)
    }

    @MainActor
    func testSearchByTranscriptShortQuerySkipped() {
        let meeting = Meeting(title: "Call")
        context.insert(meeting)
        let seg = TranscriptSegment(text: "We should do AB testing", speaker: 0, timestamp: 0, isFinal: true)
        meeting.segments = [seg]

        let results = MeetingSearchResult.search(query: "AB", in: [meeting])
        XCTAssertTrue(results.isEmpty, "Transcript search requires query >= 3 chars")
    }

    @MainActor
    func testSearchSortOrder() {
        let m1 = Meeting(title: "Planning Review")
        let m2 = Meeting(title: "Other Meeting", summaryText: "Discussed planning for next quarter")
        context.insert(m1)
        context.insert(m2)

        let results = MeetingSearchResult.search(query: "planning", in: [m1, m2])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].score >= results[1].score, "Title match should rank higher")
    }

    @MainActor
    func testSearchMatchCount() {
        let meeting = Meeting(title: "Budget Budget", summaryText: "The budget is tight")
        context.insert(meeting)

        let results = MeetingSearchResult.search(query: "budget", in: [meeting])
        XCTAssertEqual(results.count, 1)
        XCTAssertGreaterThanOrEqual(results[0].matchCount, 3)
    }

    // MARK: - displayTitle

    @MainActor
    func testDisplayTitleOldFormatWithSuffix() {
        let meeting = Meeting(title: "20260403-143022 - Weekly Standup")
        context.insert(meeting)
        XCTAssertEqual(meeting.displayTitle, "Weekly Standup")
    }

    @MainActor
    func testDisplayTitleOldFormatEmDash() {
        let meeting = Meeting(title: "20260403-143022 — Weekly Standup")
        context.insert(meeting)
        XCTAssertEqual(meeting.displayTitle, "Weekly Standup")
    }

    @MainActor
    func testDisplayTitleOldFormatTimestampOnly() {
        let meeting = Meeting(title: "20260403-143022")
        context.insert(meeting)
        XCTAssertEqual(meeting.displayTitle, "untitled")
    }

    @MainActor
    func testDisplayTitleNewFormatCleanTitle() {
        let meeting = Meeting(title: "Weekly Standup")
        context.insert(meeting)
        XCTAssertEqual(meeting.displayTitle, "Weekly Standup")
    }

    @MainActor
    func testDisplayTitleNewFormatUntitled() {
        let meeting = Meeting(title: "untitled")
        context.insert(meeting)
        XCTAssertEqual(meeting.displayTitle, "untitled")
    }

    @MainActor
    func testDisplayTitleNonTimestampPrefix() {
        let meeting = Meeting(title: "2026-04-03 - Weekly Standup")
        context.insert(meeting)
        XCTAssertEqual(meeting.displayTitle, "2026-04-03 - Weekly Standup")
    }

    // MARK: - Speaker name resolution

    func testResolvedSpeakerLabelFallsBackToYouForMic() {
        let label = resolvedSpeakerLabel(for: DeepgramService.micSpeakerID, names: nil)
        XCTAssertEqual(label, "You")
    }

    func testResolvedSpeakerLabelFallsBackToSpeakerNForRemote() {
        XCTAssertEqual(resolvedSpeakerLabel(for: 0, names: nil), "Speaker 1")
        XCTAssertEqual(resolvedSpeakerLabel(for: 2, names: nil), "Speaker 3")
    }

    func testResolvedSpeakerLabelUsesMappedName() {
        let names = ["1000": "Alice", "0": "Bob"]
        XCTAssertEqual(resolvedSpeakerLabel(for: DeepgramService.micSpeakerID, names: names), "Alice")
        XCTAssertEqual(resolvedSpeakerLabel(for: 0, names: names), "Bob")
    }

    func testResolvedSpeakerLabelFallsBackWhenMappingMissing() {
        let names = ["1000": "Alice"]
        XCTAssertEqual(resolvedSpeakerLabel(for: 0, names: names), "Speaker 1")
    }

    func testResolvedSpeakerLabelFallsBackWhenMappingIsWhitespace() {
        let names = ["1000": "   "]
        XCTAssertEqual(resolvedSpeakerLabel(for: DeepgramService.micSpeakerID, names: names), "You")
    }

    func testResolvedShortSpeakerLabelFallsBack() {
        XCTAssertEqual(resolvedShortSpeakerLabel(for: DeepgramService.micSpeakerID, names: nil), "You")
        XCTAssertEqual(resolvedShortSpeakerLabel(for: 1, names: nil), "S2")
    }

    func testResolvedShortSpeakerLabelUsesMappedName() {
        let names = ["1": "Chen"]
        XCTAssertEqual(resolvedShortSpeakerLabel(for: 1, names: names), "Chen")
    }

    // MARK: - selfSpeakerIDs override

    func testResolvedSpeakerLabelHonorsExplicitSelfID() {
        XCTAssertEqual(resolvedSpeakerLabel(for: 2, names: nil, selfIDs: [2]), "You")
        XCTAssertEqual(
            resolvedSpeakerLabel(for: DeepgramService.micSpeakerID, names: nil, selfIDs: [2]),
            "Speaker \(DeepgramService.micSpeakerID + 1)"
        )
    }

    func testResolvedShortSpeakerLabelHonorsExplicitSelfID() {
        XCTAssertEqual(resolvedShortSpeakerLabel(for: 2, names: nil, selfIDs: [2]), "You")
        XCTAssertEqual(resolvedShortSpeakerLabel(for: 0, names: nil, selfIDs: [2]), "S1")
    }

    func testResolvedSpeakerLabelSelfWinsOverMappedName() {
        let names = ["2": "Alice"]
        XCTAssertEqual(resolvedSpeakerLabel(for: 2, names: names, selfIDs: [2]), "You")
    }

    func testResolvedSpeakerLabelHonorsMultipleSelfIDs() {
        // Multiple speakers marked as self should all resolve to "You".
        XCTAssertEqual(resolvedSpeakerLabel(for: 2, names: nil, selfIDs: [2, 3]), "You")
        XCTAssertEqual(resolvedSpeakerLabel(for: 3, names: nil, selfIDs: [2, 3]), "You")
        XCTAssertEqual(resolvedSpeakerLabel(for: 4, names: nil, selfIDs: [2, 3]), "Speaker 5")
    }

    @MainActor
    func testMeetingSetSelfSpeakerRoundtrip() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        XCTAssertTrue(meeting.selfSpeakerIDs.isEmpty)
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [DeepgramService.micSpeakerID])

        // First explicit mark: the previously-implicit mic self is materialized so
        // "also mark as me" preserves "You" instead of demoting it to a raw speaker ID.
        meeting.setSelfSpeaker(id: 3, isSelf: true)
        XCTAssertEqual(meeting.selfSpeakerIDs, [DeepgramService.micSpeakerID, 3])
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [DeepgramService.micSpeakerID, 3])

        meeting.setSelfSpeaker(id: 3, isSelf: false)
        XCTAssertEqual(meeting.selfSpeakerIDs, [DeepgramService.micSpeakerID])
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [DeepgramService.micSpeakerID])
    }

    @MainActor
    func testMeetingSetSelfSpeakerSupportsMultiple() {
        // Diarization can split one person across multiple IDs; the user should be able
        // to mark all of them as "me" and undo each independently. The implicit mic self
        // is materialized on the first mark so the user doesn't lose "You".
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        meeting.setSelfSpeaker(id: 2, isSelf: true)
        meeting.setSelfSpeaker(id: 3, isSelf: true)
        XCTAssertEqual(meeting.selfSpeakerIDs, [DeepgramService.micSpeakerID, 2, 3])
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [DeepgramService.micSpeakerID, 2, 3])

        // Unmarking one preserves the others.
        meeting.setSelfSpeaker(id: 2, isSelf: false)
        XCTAssertEqual(meeting.selfSpeakerIDs, [DeepgramService.micSpeakerID, 3])
    }

    @MainActor
    func testMeetingSetSelfSpeakerClearsExistingNameAndOverride() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        meeting.setSpeakerName(id: "2", name: "Alice")
        XCTAssertEqual(meeting.speakerNames["2"], "Alice")
        XCTAssertTrue(meeting.speakerOverrides.contains("2"))

        meeting.setSelfSpeaker(id: 2, isSelf: true)
        XCTAssertNil(meeting.speakerNames["2"])
        XCTAssertFalse(meeting.speakerOverrides.contains("2"))
    }

    @MainActor
    func testMeetingSelfSpeakerIDsMergesLegacyColumn() {
        // Meetings saved before multi-self support have only the legacy `selfSpeakerID` column.
        // Reading `selfSpeakerIDs` must still surface that ID.
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        meeting.selfSpeakerID = 5
        XCTAssertTrue(meeting.selfSpeakerIDs.contains(5))
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [5])
    }

    // MARK: - SpeakerNamesResponse sanitize

    func testSpeakerNamesSanitizeTrimsAndDropsEmpty() {
        let raw: [String: String] = ["1000": "  Alice  ", "0": "", "1": "   "]
        let cleaned = SpeakerNamesResponse.sanitize(raw)
        XCTAssertEqual(cleaned, ["1000": "Alice"])
    }

    func testSpeakerNamesSanitizeRejectsPlaceholders() {
        let raw: [String: String] = ["1000": "Unknown", "0": "n/a", "1": "null", "2": "none"]
        let cleaned = SpeakerNamesResponse.sanitize(raw)
        XCTAssertTrue(cleaned.isEmpty)
    }

    func testSpeakerNamesSanitizeRejectsSpeakerRestatements() {
        let raw: [String: String] = ["0": "Speaker 2", "1": "S 3", "2": "Alice"]
        let cleaned = SpeakerNamesResponse.sanitize(raw)
        XCTAssertEqual(cleaned, ["2": "Alice"])
    }

    func testSpeakerNamesSanitizeRejectsNonNumericKeys() {
        let raw: [String: String] = ["alice": "Alice", "1000": "Bob", "": "Carol"]
        let cleaned = SpeakerNamesResponse.sanitize(raw)
        XCTAssertEqual(cleaned, ["1000": "Bob"])
    }

    func testSpeakerNamesSanitizeTrimsKey() {
        let raw: [String: String] = [" 1000 ": "Alice"]
        let cleaned = SpeakerNamesResponse.sanitize(raw)
        XCTAssertEqual(cleaned, ["1000": "Alice"])
    }

    // MARK: - SpeakerNamesResponse decoding

    func testSpeakerNamesResponseDecodesNestedShape() throws {
        let json = "{\"speakers\":{\"1000\":\"Alice\",\"0\":\"Bob\"}}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SpeakerNamesResponse.self, from: json)
        XCTAssertEqual(decoded.speakers, ["1000": "Alice", "0": "Bob"])
    }

    func testSpeakerNamesResponseDecodesFlatShape() throws {
        let json = "{\"1000\":\"Alice\",\"0\":\"Bob\"}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SpeakerNamesResponse.self, from: json)
        XCTAssertEqual(decoded.speakers, ["1000": "Alice", "0": "Bob"])
    }

    // MARK: - Meeting.speakerNames roundtrip

    @MainActor
    func testMeetingSpeakerNamesRoundtrip() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        meeting.speakerNames = ["1000": "Alice", "0": "Bob"]
        XCTAssertEqual(meeting.speakerNames, ["1000": "Alice", "0": "Bob"])
        XCTAssertTrue(meeting.hasSpeakerNames)
        XCTAssertNotNil(meeting.speakerNamesJSON)
    }

    @MainActor
    func testMeetingSpeakerNamesFiltersEmptyValues() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        meeting.speakerNames = ["1000": "Alice", "0": "   "]
        XCTAssertEqual(meeting.speakerNames, ["1000": "Alice"])
    }

    @MainActor
    func testMeetingSpeakerNamesEmptyClearsJSON() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        meeting.speakerNames = ["1000": "Alice"]
        XCTAssertNotNil(meeting.speakerNamesJSON)
        meeting.speakerNames = [:]
        XCTAssertNil(meeting.speakerNamesJSON)
        XCTAssertFalse(meeting.hasSpeakerNames)
    }

    @MainActor
    func testMeetingSpeakerNamesDefaultIsEmpty() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        XCTAssertEqual(meeting.speakerNames, [:])
        XCTAssertFalse(meeting.hasSpeakerNames)
    }

    @MainActor
    func testMeetingFullTranscriptUsesResolvedNames() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        let segs = [
            TranscriptSegment(text: "Hello", speaker: DeepgramService.micSpeakerID, timestamp: 0, isFinal: true),
            TranscriptSegment(text: "Hi there", speaker: 0, timestamp: 5, isFinal: true)
        ]
        meeting.segments = segs
        meeting.speakerNames = ["1000": "Alice", "0": "Bob"]

        let transcript = meeting.fullTranscript
        XCTAssertTrue(transcript.contains("Alice"))
        XCTAssertTrue(transcript.contains("Bob"))
        XCTAssertFalse(transcript.contains("Speaker 1"))
        XCTAssertFalse(transcript.contains("You"))
    }
}
