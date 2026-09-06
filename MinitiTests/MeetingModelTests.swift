import XCTest
import SwiftData
import SwiftUI
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class MeetingModelTests: XCTestCase, @unchecked Sendable {

    private var container: ModelContainer!
    private var context: ModelContext!

    /// Regression: the sidebar highlighter used to index the original string with ranges
    /// taken from its lowercased copy, which crashed when lowercasing changed the length.
    @MainActor
    func testHighlightedTextSurvivesLengthChangingCase() {
        for text in ["İstanbul sync", "STRASSE ẞ review", "plain meeting", "İİİ"] {
            for query in ["i", "meeting", "İ", "ss", "zzz"] {
                _ = highlightedText(text, query: query, baseColor: .primary, highlightColor: .green, font: .body)
            }
        }
    }

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: Meeting.self, TranscriptSegment.self, configurations: config)
            context = container.mainContext
        }
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - History metadata

    @MainActor
    func testHistoryMetadataDefaultsAreNonDisruptive() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)

        XCTAssertFalse(meeting.isPinned)
        XCTAssertNil(meeting.insightsUpdatedAt)
    }

    @MainActor
    func testHistoryMetadataPersists() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let meeting = Meeting(title: "important", isPinned: true, insightsUpdatedAt: updatedAt)
        context.insert(meeting)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<Meeting>()).first)
        XCTAssertTrue(fetched.isPinned)
        XCTAssertEqual(fetched.insightsUpdatedAt, updatedAt)
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

    // MARK: - Meeting.templateSections

    @MainActor
    func testTemplateSectionsPersistAndClearOnTranscriptEdit() {
        let meeting = Meeting(title: "test", summaryText: "A call")
        context.insert(meeting)
        XCTAssertFalse(meeting.hasTemplateInsights)
        XCTAssertNil(meeting.insightTemplate)

        meeting.insightTemplateID = "bant"
        meeting.templateSections = ["budget": "$40k approved", "unknown": "ignored at render time"]
        XCTAssertEqual(meeting.insightTemplate?.id, "bant")
        XCTAssertTrue(meeting.hasTemplateInsights)
        XCTAssertEqual(meeting.templateSections["budget"], "$40k approved")
        XCTAssertTrue(meeting.hasGeneratedInsights)

        let md = meeting.insightsAsMarkdown()
        XCTAssertTrue(md.contains("### BANT qualification"))
        XCTAssertTrue(md.contains("**Budget:** $40k approved"))
        XCTAssertFalse(md.contains("ignored at render time"))

        meeting.markTranscriptEdited()
        XCTAssertFalse(meeting.hasTemplateInsights)
        XCTAssertNil(meeting.templateSectionsJSON)
        XCTAssertEqual(meeting.insightTemplateID, "bant", "the chosen template survives a trim; only its notes are cleared")
        XCTAssertTrue(meeting.needsInsightsAfterTranscriptEdit)
    }

    @MainActor
    func testTemplateSectionsWithUnknownTemplateAreNotInsights() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        meeting.insightTemplateID = "retired-template"
        meeting.templateSections = ["anything": "value"]
        XCTAssertFalse(meeting.hasTemplateInsights)
        XCTAssertFalse(meeting.hasGeneratedInsights)
        XCTAssertFalse(meeting.insightsAsMarkdown().contains("anything"))
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
        XCTAssertTrue(md.contains("## Coaching"))
        XCTAssertFalse(md.contains("## Training"))
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
        // With an explicit self mark elsewhere, the mic speaker is a neutral
        // mic-ordinal label, not "You" and not raw ID arithmetic.
        XCTAssertEqual(
            resolvedSpeakerLabel(for: DeepgramService.micSpeakerID, names: nil, selfIDs: [2]),
            "Speaker 1 (mic)"
        )
    }

    func testResolvedSpeakerLabelForAdditionalMicSpeakers() {
        // Nil self context: primary mic speaker keeps the implicit "You";
        // additional mic speakers are neutral mic-ordinal labels.
        XCTAssertEqual(resolvedSpeakerLabel(for: DeepgramService.micSpeakerID, names: nil, selfIDs: nil), "You")
        XCTAssertEqual(resolvedSpeakerLabel(for: DeepgramService.micSpeakerID + 1, names: nil, selfIDs: nil), "Speaker 2 (mic)")
        // Empty (non-nil) self context: several unmarked mic speakers — nobody is "You".
        XCTAssertEqual(resolvedSpeakerLabel(for: DeepgramService.micSpeakerID, names: nil, selfIDs: []), "Speaker 1 (mic)")
        // Inferred names still win over the implicit default.
        XCTAssertEqual(
            resolvedSpeakerLabel(for: DeepgramService.micSpeakerID + 1, names: ["1001": "Priya"], selfIDs: []),
            "Priya"
        )
        XCTAssertEqual(resolvedShortSpeakerLabel(for: DeepgramService.micSpeakerID + 1, names: nil, selfIDs: []), "S2")
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

    // MARK: - Guarded JSON setters (round-trip + empty clears)

    @MainActor
    func testMeetingSuggestedQuestionsRoundtrip() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        let questions = [
            SuggestedQuestion(question: "What's the timeline?", type: "clarify", context: "unstated"),
            SuggestedQuestion(question: "Who signs off?", type: "deeper", context: "decision")
        ]
        meeting.suggestedQuestions = questions
        XCTAssertEqual(meeting.suggestedQuestions, questions)
        XCTAssertTrue(meeting.hasQuestions)
        XCTAssertNotNil(meeting.suggestedQuestionsJSON)
    }

    @MainActor
    func testMeetingSuggestedQuestionsEmptyClearsJSON() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        meeting.suggestedQuestions = [SuggestedQuestion(question: "Q?", type: "clarify", context: "c")]
        XCTAssertNotNil(meeting.suggestedQuestionsJSON)
        meeting.suggestedQuestions = []
        XCTAssertNil(meeting.suggestedQuestionsJSON)
        XCTAssertFalse(meeting.hasQuestions)
    }

    @MainActor
    func testMeetingDocTopicsRoundtrip() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        let topics = [DocTopic(label: "Rate limits"), DocTopic(label: "Webhooks")]
        meeting.docTopics = topics
        XCTAssertEqual(meeting.docTopics, topics)
        XCTAssertTrue(meeting.hasDocs)
        XCTAssertNotNil(meeting.docTopicsJSON)
    }

    @MainActor
    func testMeetingDocTopicsEmptyClearsJSON() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        meeting.docTopics = [DocTopic(label: "Rate limits")]
        XCTAssertNotNil(meeting.docTopicsJSON)
        meeting.docTopics = []
        XCTAssertNil(meeting.docTopicsJSON)
        XCTAssertFalse(meeting.hasDocs)
    }

    @MainActor
    func testMeetingAttendeesRoundtrip() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        let attendees = [
            MeetingAttendee(email: "a@acme.com", displayName: "Alice", domain: "acme.com", responseStatus: "accepted", isOrganizer: true, isSelf: false),
            MeetingAttendee(email: "me@corp.com", displayName: nil, domain: "corp.com", responseStatus: "accepted", isOrganizer: false, isSelf: true)
        ]
        meeting.attendees = attendees
        XCTAssertEqual(meeting.attendees.map(\.email), attendees.map(\.email))
        XCTAssertNotNil(meeting.attendeesJSON)
    }

    @MainActor
    func testMeetingAttendeesEmptyClearsJSON() {
        let meeting = Meeting(title: "test")
        context.insert(meeting)
        meeting.attendees = [MeetingAttendee(email: "a@acme.com", displayName: "Alice", domain: "acme.com", responseStatus: "accepted", isOrganizer: true, isSelf: false)]
        XCTAssertNotNil(meeting.attendeesJSON)
        meeting.attendees = []
        XCTAssertNil(meeting.attendeesJSON)
        XCTAssertTrue(meeting.attendees.isEmpty)
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

    // MARK: - Granola CSV import

    @MainActor
    func testGranolaCSVParsesQuotedJSONTranscriptAndImportsProvenance() throws {
        let transcriptJSON = #"[{"speaker":{"source":"microphone","attribution":"me"},"text":"Hello, team","start_time":"2026-08-07T09:00:00Z"},{"speaker":{"source":"speaker","name":"Alice Smith"},"text":"Hi there","start_time":"2026-08-07T09:00:05Z"}]"#
        let attendeesJSON = #"[{"name":"Ian","email":"ian@example.com"},{"name":"Alice Smith","email":"alice@acme.com"}]"#
        let csv = """
        Note ID,Title,Created At,Updated At,Summary Text,Transcript,Attendees,Owner Email,Organizer Email,Web URL
        not_12345678901234,Weekly sync,2026-08-07T09:00:00Z,2026-08-07T09:30:00Z,Discussed launch,"\(csvEscaped(transcriptJSON))","\(csvEscaped(attendeesJSON))",ian@example.com,alice@acme.com,https://notes.granola.ai/d/example
        """

        let parsed = try GranolaCSVImporter.parse(data: Data(csv.utf8))
        XCTAssertEqual(parsed.meetings.count, 1)
        XCTAssertEqual(parsed.meetings[0].transcript.count, 2)
        XCTAssertEqual(parsed.meetings[0].attendees.count, 2)

        let result = try GranolaCSVImporter.importMeetings(parsed, into: context, defaultLanguage: "en")
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.duplicates, 0)

        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        let meeting = try XCTUnwrap(meetings.first)
        XCTAssertEqual(meeting.externalSource, "granola")
        XCTAssertEqual(meeting.externalID, "not_12345678901234")
        XCTAssertEqual(meeting.provenanceDisplayName, "Granola")
        XCTAssertEqual(meeting.segments.count, 2)
        XCTAssertTrue(meeting.selfSpeakerIDs.contains(DeepgramService.micSpeakerID))
        XCTAssertEqual(meeting.speakerNames["0"], "Alice Smith")
        XCTAssertEqual(meeting.attendees.first(where: { $0.email == "ian@example.com" })?.isSelf, true)
        XCTAssertEqual(meeting.attendees.first(where: { $0.email == "alice@acme.com" })?.isOrganizer, true)
    }

    @MainActor
    func testGranolaCSVReimportSkipsDuplicateExternalID() throws {
        let csv = """
        ID,Title,Date,Transcript
        granola-1,Customer call,2026-08-07T09:00:00Z,"[00:00] Me: Hello
        [00:05] Pat Lee: Hi"
        """
        let parsed = try GranolaCSVImporter.parse(data: Data(csv.utf8))

        let first = try GranolaCSVImporter.importMeetings(parsed, into: context, defaultLanguage: "en")
        let second = try GranolaCSVImporter.importMeetings(parsed, into: context, defaultLanguage: "en")

        XCTAssertEqual(first.imported, 1)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.duplicates, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Meeting>()), 1)
    }

    @MainActor
    func testGranolaCSVImportsSummaryOnlyExport() throws {
        let csv = """
        id,title,created_at,summary_text,owner_email
        granola-2,Planning review,2026-08-07T09:00:00Z,"### Decisions
        - Ship on Friday",ian@example.com
        """

        let parsed = try GranolaCSVImporter.parse(data: Data(csv.utf8))
        let result = try GranolaCSVImporter.importMeetings(parsed, into: context, defaultLanguage: "en")

        XCTAssertEqual(result.imported, 1)
        let meeting = try XCTUnwrap(try context.fetch(FetchDescriptor<Meeting>()).first)
        XCTAssertEqual(meeting.summaryText, "### Decisions\n- Ship on Friday")
        XCTAssertTrue(meeting.segments.isEmpty)
        XCTAssertEqual(meeting.externalSource, "granola")
    }

    @MainActor
    func testGranolaCSVSkipsRowsWithoutMeetingDate() throws {
        let csv = """
        ID,Title,Date,Transcript
        missing-date,No date,,Me: Hello
        valid,Has date,2026-08-07T09:00:00Z,Me: Hello
        """

        let parsed = try GranolaCSVImporter.parse(data: Data(csv.utf8))
        XCTAssertEqual(parsed.meetings.count, 1)
        XCTAssertEqual(parsed.skippedRows, 1)
    }

    private func csvEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\"\"")
    }
}

// MARK: - Automatic environment inference (table-driven, per the diarization plan)

final class MeetingEnvironmentInferenceTests: XCTestCase {
    private func evidence(
        associatedCallApp: Bool = false,
        callAppActive: Bool = false,
        calendarConference: Bool? = nil,
        micSpeakers: Int = 0,
        micFinal: Bool = false,
        systemFinal: Bool = false,
        systemFinalWithContext: Bool = false,
        micSeconds: Double = 0
    ) -> MeetingEnvironmentEvidence {
        var e = MeetingEnvironmentEvidence()
        e.hasAssociatedCallApp = associatedCallApp
        e.recognizedCallAppActive = callAppActive
        e.calendarEventHasConferenceURL = calendarConference
        e.confirmedMicSpeakerCount = micSpeakers
        e.hasMeaningfulMicFinal = micFinal
        e.hasMeaningfulSystemFinal = systemFinal
        e.systemFinalWithCallContext = systemFinalWithContext
        e.meaningfulMicSpeechSeconds = micSeconds
        return e
    }

    private func infer(_ e: MeetingEnvironmentEvidence) -> InferredMeetingEnvironment {
        MeetingEnvironmentInferenceEngine.infer(e)
    }

    func testNoEvidenceIsUnknown() {
        XCTAssertEqual(infer(evidence()), .unknown)
    }

    func testAssociatedCallAppIsRemoteLikely() {
        XCTAssertEqual(infer(evidence(associatedCallApp: true)), .remoteLikely)
    }

    func testSystemFinalWithCallContextIsRemoteLikely() {
        XCTAssertEqual(infer(evidence(systemFinal: true, systemFinalWithContext: true)), .remoteLikely)
    }

    func testSingleSupportingSignalsStayUnknown() {
        // System speech alone can be media playback in a room.
        XCTAssertEqual(infer(evidence(systemFinal: true)), .unknown)
        // A conference URL alone: the user may join late, muted, or not at all.
        XCTAssertEqual(infer(evidence(calendarConference: true)), .unknown)
        // An active-but-unassociated call app alone is not proof.
        XCTAssertEqual(infer(evidence(callAppActive: true)), .unknown)
    }

    func testTwoSupportingSignalsAreRemoteLikely() {
        XCTAssertEqual(infer(evidence(callAppActive: true, calendarConference: true)), .remoteLikely)
        XCTAssertEqual(infer(evidence(callAppActive: true, systemFinal: true)), .remoteLikely)
    }

    func testInRoomNeedsSpeakersSilentSystemAndObservationWindow() {
        let inRoom = evidence(micSpeakers: 2, micFinal: true, micSeconds: 35)
        XCTAssertEqual(infer(inRoom), .inRoomLikely)

        // Below the meaningful-speech window: unknown.
        XCTAssertEqual(infer(evidence(micSpeakers: 2, micFinal: true, micSeconds: 10)), .unknown)
        // A single mic speaker is never in-room evidence.
        XCTAssertEqual(infer(evidence(micSpeakers: 1, micFinal: true, micSeconds: 60)), .unknown)
        // Any remote signal blocks the in-room conclusion.
        XCTAssertEqual(infer(evidence(calendarConference: true, micSpeakers: 2, micFinal: true, micSeconds: 60)), .unknown)
        XCTAssertEqual(infer(evidence(callAppActive: true, micSpeakers: 2, micFinal: true, micSeconds: 60)), .unknown)
    }

    func testCalendarWithoutConferenceURLDoesNotBlockInRoom() {
        XCTAssertEqual(
            infer(evidence(calendarConference: false, micSpeakers: 2, micFinal: true, micSeconds: 40)),
            .inRoomLikely
        )
    }

    func testLateSystemSpeechUpgradesInRoomToHybrid() {
        var e = evidence(micSpeakers: 2, micFinal: true, micSeconds: 40)
        XCTAssertEqual(infer(e), .inRoomLikely)
        // A remote participant finally speaks on an associated call.
        e.hasAssociatedCallApp = true
        e.hasMeaningfulSystemFinal = true
        e.systemFinalWithCallContext = true
        XCTAssertEqual(infer(e), .hybridLikely)
    }

    func testHybridNeedsBothRoomAndRemoteEvidence() {
        XCTAssertEqual(
            infer(evidence(associatedCallApp: true, micSpeakers: 2, micFinal: true, systemFinal: true, micSeconds: 40)),
            .hybridLikely
        )
        // Associated call with several mic speakers but no system speech yet: remote.
        XCTAssertEqual(
            infer(evidence(associatedCallApp: true, micSpeakers: 2, micFinal: true, micSeconds: 40)),
            .remoteLikely
        )
    }

    func testMediaPlaybackDuringInRoomMeetingStaysUnknown() {
        // Two room speakers + system speech without call/calendar context: conflicting.
        XCTAssertEqual(
            infer(evidence(micSpeakers: 2, micFinal: true, systemFinal: true, micSeconds: 40)),
            .unknown
        )
    }

    func testEnvironmentRawValueRoundTripsAndLegacyDecodesUnknown() {
        XCTAssertEqual(InferredMeetingEnvironment(rawValue: "inRoomLikely"), .inRoomLikely)
        XCTAssertNil(InferredMeetingEnvironment(rawValue: "banana"))
        let meeting = Meeting(title: "legacy")
        XCTAssertNil(meeting.inferredEnvironmentRaw)
    }
}

// MARK: - Source-aware segments and self-set rules

final class TranscriptSourceModelTests: XCTestCase {
    func testTranscriptSegmentSourceRoundTrip() {
        let segment = TranscriptSegment(text: "hi", speaker: 1001, timestamp: 0, isFinal: true, sourceRaw: "microphone")
        XCTAssertEqual(segment.source, .microphone)
        let legacy = TranscriptSegment(text: "hi", speaker: 1000, timestamp: 0, isFinal: true)
        XCTAssertNil(legacy.source)
    }

    func testMeetingMicSpeakerIDsUsesSourceWithLegacyFallback() {
        let meeting = Meeting(title: "m")
        meeting.segments = [
            TranscriptSegment(text: "a", speaker: 1000, timestamp: 0, isFinal: true),
            TranscriptSegment(text: "b", speaker: 3, timestamp: 1, isFinal: true, sourceRaw: "microphone"),
            TranscriptSegment(text: "c", speaker: 0, timestamp: 2, isFinal: true, sourceRaw: "system"),
        ]
        XCTAssertEqual(meeting.micSpeakerIDs, [1000, 3])
    }

    func testEffectiveSelfIDsWithdrawImplicitYouForMultipleMicSpeakers() {
        // Dual-source meeting: the implicit "You" applies while there is one mic
        // speaker, and withdraws when a second is confirmed.
        let meeting = Meeting(title: "m")
        meeting.segments = [
            TranscriptSegment(text: "remote", speaker: 0, timestamp: 0, isFinal: true, sourceRaw: "system"),
            TranscriptSegment(text: "a", speaker: 1000, timestamp: 1, isFinal: true, sourceRaw: "microphone"),
        ]
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [1000])
        XCTAssertNil(meeting.speakerLabelSelfIDs)

        meeting.segments.append(
            TranscriptSegment(text: "b", speaker: 1001, timestamp: 2, isFinal: true, sourceRaw: "microphone")
        )
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [])
        XCTAssertEqual(meeting.speakerLabelSelfIDs, [])

        meeting.selfSpeakerIDs = [1001]
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [1001])
        XCTAssertEqual(meeting.speakerLabelSelfIDs, [1001])
    }

    /// A mic-only recording can be someone else's lecture or an interview — its sole
    /// speaker must not be assumed to be the user (that matches pre-diarization
    /// behavior, where mic-only recordings never labeled anyone "You").
    func testMicOnlyMeetingHasNoImplicitYou() {
        let meeting = Meeting(title: "lecture")
        meeting.segments = [
            TranscriptSegment(text: "welcome to the talk", speaker: 1000, timestamp: 0, isFinal: true, sourceRaw: "microphone"),
        ]
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [])
        XCTAssertEqual(meeting.speakerLabelSelfIDs, [])
        XCTAssertEqual(
            resolvedSpeakerLabel(for: 1000, names: nil, selfIDs: meeting.speakerLabelSelfIDs),
            "Speaker 1 (mic)"
        )
        // Explicit mark still wins.
        meeting.selfSpeakerIDs = [1000]
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [1000])
    }

    /// Legacy meetings (no source metadata) keep the historical implicit mic default.
    func testLegacyMeetingKeepsImplicitYou() {
        let meeting = Meeting(title: "legacy")
        meeting.segments = [
            TranscriptSegment(text: "hello", speaker: 1000, timestamp: 0, isFinal: true),
            TranscriptSegment(text: "hi", speaker: 0, timestamp: 1, isFinal: true),
        ]
        XCTAssertEqual(meeting.effectiveSelfSpeakerIDs, [1000])
        XCTAssertNil(meeting.speakerLabelSelfIDs)
    }

    func testLiveSegmentSourceDrivesIsLocalMic() {
        let micByRange = AppState.LiveSegment(id: UUID(), text: "a", speaker: 1000, timestamp: 0, isFinal: true)
        XCTAssertTrue(micByRange.isLocalMic)
        let systemExplicit = AppState.LiveSegment(id: UUID(), text: "a", speaker: 1000, timestamp: 0, isFinal: true, source: .system)
        XCTAssertFalse(systemExplicit.isLocalMic)
        let micExplicitLowID = AppState.LiveSegment(id: UUID(), text: "a", speaker: 2, timestamp: 0, isFinal: true, source: .microphone)
        XCTAssertTrue(micExplicitLowID.isLocalMic)
    }
}
