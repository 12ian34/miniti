import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class TrainingMetricsTests: XCTestCase {

    // MARK: - tokenize

    func testTokenizeSimple() {
        let result = TrainingMetrics.tokenize("Hello world")
        XCTAssertEqual(result, ["hello", "world"])
    }

    func testTokenizeStripsSpecialCharacters() {
        let result = TrainingMetrics.tokenize("Well, you know, it's great!")
        XCTAssertEqual(result, ["well", "you", "know", "it's", "great"])
    }

    func testTokenizeEmpty() {
        let result = TrainingMetrics.tokenize("")
        XCTAssertTrue(result.isEmpty)
    }

    func testTokenizeWhitespaceOnly() {
        let result = TrainingMetrics.tokenize("   \t\n  ")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - countPhraseOccurrences

    func testCountPhraseOccurrencesSingleWord() {
        let tokens = ["i", "um", "think", "um", "that", "um"]
        let count = TrainingMetrics.countPhraseOccurrences(of: ["um"], in: tokens)
        XCTAssertEqual(count, 3)
    }

    func testCountPhraseOccurrencesMultiWord() {
        let tokens = ["you", "know", "i", "think", "you", "know", "right"]
        let count = TrainingMetrics.countPhraseOccurrences(of: ["you", "know"], in: tokens)
        XCTAssertEqual(count, 2)
    }

    func testCountPhraseOccurrencesNoMatch() {
        let tokens = ["hello", "world"]
        let count = TrainingMetrics.countPhraseOccurrences(of: ["um"], in: tokens)
        XCTAssertEqual(count, 0)
    }

    func testCountPhraseOccurrencesEmptyPhrase() {
        let count = TrainingMetrics.countPhraseOccurrences(of: [], in: ["hello"])
        XCTAssertEqual(count, 0)
    }

    func testCountPhraseOccurrencesPhraseLongerThanTokens() {
        let count = TrainingMetrics.countPhraseOccurrences(of: ["a", "b", "c"], in: ["a"])
        XCTAssertEqual(count, 0)
    }

    // MARK: - computeLongestMonologue

    func testLongestMonologueSingleSpeaker() {
        let segments = [
            TrainingMetrics.Segment(text: "Hello world", speaker: 0, isFinal: true, timestamp: 0),
            TrainingMetrics.Segment(text: "How are you doing today", speaker: 0, isFinal: true, timestamp: 5),
        ]
        let result = TrainingMetrics.computeLongestMonologue(for: 0, in: segments)
        XCTAssertEqual(result, 7) // 2 + 5
    }

    func testLongestMonologueWithInterruption() {
        let segments = [
            TrainingMetrics.Segment(text: "Hello world foo", speaker: 0, isFinal: true, timestamp: 0),
            TrainingMetrics.Segment(text: "yes", speaker: 1, isFinal: true, timestamp: 3),
            TrainingMetrics.Segment(text: "continuing on with more words here", speaker: 0, isFinal: true, timestamp: 5),
        ]
        let result = TrainingMetrics.computeLongestMonologue(for: 0, in: segments)
        XCTAssertEqual(result, 6) // second run: "continuing on with more words here" = 6 words
    }

    func testLongestMonologueNoSegments() {
        let result = TrainingMetrics.computeLongestMonologue(for: 0, in: [])
        XCTAssertEqual(result, 0)
    }

    // MARK: - countFillerOccurrences (longest match, no double counting)

    func testFillerCountsDoNotDoubleCountOverlappingPhrases() {
        let phrases = [["uh"], ["uh", "huh"], ["um"]]
        let tokens = TrainingMetrics.tokenize("uh huh, yes. uh, I think so. um, uh huh.")
        XCTAssertEqual(TrainingMetrics.countFillerOccurrences(of: phrases, in: tokens), [1, 2, 1])
        // The old per-phrase counter counts each "uh huh" as an "uh" too.
        XCTAssertEqual(TrainingMetrics.countPhraseOccurrences(of: ["uh"], in: tokens), 3)
    }

    func testFillerCountsLongestMatchWinsRegardlessOfPhraseOrder() {
        let tokens = TrainingMetrics.tokenize("you know what I mean, you know")
        XCTAssertEqual(TrainingMetrics.countFillerOccurrences(of: [["know"], ["you", "know"], ["i", "mean"]], in: tokens), [0, 2, 1])
        XCTAssertEqual(TrainingMetrics.countFillerOccurrences(of: [["you", "know"], ["know"]], in: tokens), [2, 0])
    }

    func testFillerCountsRepeatedAndAdjacentFillers() {
        let tokens = TrainingMetrics.tokenize("um um um, like like")
        XCTAssertEqual(TrainingMetrics.countFillerOccurrences(of: [["um"], ["like"]], in: tokens), [3, 2])
    }

    func testFillerCountsHyphenatedPunctuatedAndSpanishPhrases() {
        // Configured phrases go through the same tokenizer as transcript text, so a
        // hyphenated filler becomes a two-token phrase and still matches once.
        let tokens = TrainingMetrics.tokenize("Mm-hmm. O sea, bueno... o sea, ¿no?")
        let phrases = ["mm-hmm", "o sea", "bueno"].map { TrainingMetrics.tokenize($0) }
        XCTAssertEqual(phrases[0], ["mm", "hmm"])
        XCTAssertEqual(TrainingMetrics.countFillerOccurrences(of: phrases, in: tokens), [1, 2, 1])
    }

    func testFillerCountsEmptyInputs() {
        XCTAssertEqual(TrainingMetrics.countFillerOccurrences(of: [], in: ["um"]), [])
        XCTAssertEqual(TrainingMetrics.countFillerOccurrences(of: [["um"], []], in: []), [0, 0])
        XCTAssertEqual(TrainingMetrics.countFillerOccurrences(of: [[], ["um"]], in: ["um"]), [0, 1])
    }

    func testFillerCountsAgreeWithPerPhraseCounterWhenPhrasesCannotOverlap() {
        let tokens = TrainingMetrics.tokenize("Mhmm, that makes sense. Um, so, uh, Mhmm.")
        let phrases = TranscriptionLanguage.english.defaultFillers.map { TrainingMetrics.tokenize($0) }
        let combined = TrainingMetrics.countFillerOccurrences(of: phrases, in: tokens)
        for (phrase, count) in zip(phrases, combined) where count > 0 {
            XCTAssertEqual(count, TrainingMetrics.countPhraseOccurrences(of: phrase, in: tokens), "\(phrase)")
        }
    }

    // MARK: - normalizedFillers

    func testNormalizedFillersTrimsAndLowercases() {
        let result = TrainingFillerPreferences.normalizedFillers(["  UM  ", "Uh", " LIKE "])
        XCTAssertEqual(result, ["um", "uh", "like"])
    }

    func testNormalizedFillersDeduplicates() {
        let result = TrainingFillerPreferences.normalizedFillers(["um", "UM", "Um"])
        XCTAssertEqual(result, ["um"])
    }

    func testNormalizedFillersCollapsesWhitespace() {
        let result = TrainingFillerPreferences.normalizedFillers(["you   know", "i  mean"])
        XCTAssertEqual(result, ["you know", "i mean"])
    }

    func testNormalizedFillersFiltersEmpty() {
        let result = TrainingFillerPreferences.normalizedFillers(["um", "", "   ", "uh"])
        XCTAssertEqual(result, ["um", "uh"])
    }

    // MARK: - TrainingMetrics.compute

    func testComputeEmptySegments() {
        let metrics = TrainingMetrics.compute(from: [], duration: 60)
        XCTAssertTrue(metrics.speakers.isEmpty)
        XCTAssertEqual(metrics.talkRatioYou, 0)
    }

    func testComputeSingleSpeaker() {
        let segments = [
            TrainingMetrics.Segment(text: "Hello world how are you", speaker: 1000, isFinal: true, timestamp: 10),
            TrainingMetrics.Segment(text: "I am doing great today", speaker: 1000, isFinal: true, timestamp: 20),
        ]
        let metrics = TrainingMetrics.compute(from: segments, duration: 60)

        XCTAssertEqual(metrics.speakers.count, 1)
        let you = metrics.speakers[0]
        XCTAssertTrue(you.isLocalMic)
        XCTAssertEqual(you.speakerLabel, "You")
        XCTAssertEqual(you.wordCount, 10)
        XCTAssertEqual(metrics.talkRatioYou, 1.0)
    }

    func testComputeMultipleSpeakers() {
        let segments = [
            TrainingMetrics.Segment(text: "Hello from me", speaker: 1000, isFinal: true, timestamp: 0),
            TrainingMetrics.Segment(text: "Hi there nice to meet you", speaker: 0, isFinal: true, timestamp: 5),
        ]
        let metrics = TrainingMetrics.compute(from: segments, duration: 30)

        XCTAssertEqual(metrics.speakers.count, 2)
        let you = metrics.speakers.first(where: { $0.isLocalMic })!
        let other = metrics.speakers.first(where: { !$0.isLocalMic })!
        XCTAssertEqual(you.wordCount, 3)
        XCTAssertEqual(other.wordCount, 6)
        XCTAssertEqual(metrics.talkRatioYou, 3.0 / 9.0, accuracy: 0.01)
    }

    func testComputeFiltersNonFinalSegments() {
        let segments = [
            TrainingMetrics.Segment(text: "Hello world", speaker: 1000, isFinal: true, timestamp: 0),
            TrainingMetrics.Segment(text: "interim text", speaker: 1000, isFinal: false, timestamp: 5),
        ]
        let metrics = TrainingMetrics.compute(from: segments, duration: 30)

        XCTAssertEqual(metrics.speakers.count, 1)
        XCTAssertEqual(metrics.speakers[0].wordCount, 2) // only final segment counted
    }

    func testComputeQuestionsAsked() {
        let segments = [
            TrainingMetrics.Segment(text: "How are you? What do you think?", speaker: 1000, isFinal: true, timestamp: 0),
        ]
        let metrics = TrainingMetrics.compute(from: segments, duration: 30)
        XCTAssertEqual(metrics.speakers[0].questionsAsked, 2)
    }

    func testComputeWordsPerMinute() {
        let segments = [
            TrainingMetrics.Segment(text: "one two three four five six seven eight nine ten", speaker: 1000, isFinal: true, timestamp: 30),
        ]
        let metrics = TrainingMetrics.compute(from: segments, duration: 60)
        XCTAssertEqual(metrics.speakers[0].wordsPerMinute, 10.0 / metrics.durationMinutes, accuracy: 0.1)
    }

    func testComputeAvgWordsPerTurn() {
        let segments = [
            TrainingMetrics.Segment(text: "Hello world", speaker: 1000, isFinal: true, timestamp: 0),
            TrainingMetrics.Segment(text: "One two three four", speaker: 1000, isFinal: true, timestamp: 10),
        ]
        let metrics = TrainingMetrics.compute(from: segments, duration: 30)
        XCTAssertEqual(metrics.speakers[0].avgWordsPerTurn, 3.0, accuracy: 0.01) // (2+4)/2
    }

    func testComputeFiltersEmptySegments() {
        let segments = [
            TrainingMetrics.Segment(text: "  ", speaker: 1000, isFinal: true, timestamp: 0),
            TrainingMetrics.Segment(text: "Hello", speaker: 1000, isFinal: true, timestamp: 5),
        ]
        let metrics = TrainingMetrics.compute(from: segments, duration: 30)
        XCTAssertEqual(metrics.speakers[0].segmentCount, 1)
    }

    // MARK: - Per-language filler defaults

    func testDefaultFillersForSpanish() {
        let fillers = TrainingFillerPreferences.defaultFillers(for: "es")
        XCTAssertTrue(fillers.contains("o sea"))
        XCTAssertTrue(fillers.contains("bueno"))
        XCTAssertFalse(fillers.contains("um"))
    }

    func testDefaultFillersForFrench() {
        let fillers = TrainingFillerPreferences.defaultFillers(for: "fr")
        XCTAssertTrue(fillers.contains("euh"))
        XCTAssertTrue(fillers.contains("du coup"))
    }

    func testDefaultFillersForUnknownLanguageFallsBackToEnglish() {
        let fillers = TrainingFillerPreferences.defaultFillers(for: "xx")
        XCTAssertEqual(fillers, TranscriptionLanguage.english.defaultFillers)
    }

    func testCurrentFillersForLanguageReturnsDefaults() {
        let defaults = UserDefaults(suiteName: "test_fillers_\(UUID().uuidString)")!
        let fillers = TrainingFillerPreferences.currentFillers(for: "de", defaults: defaults)
        XCTAssertEqual(fillers, TranscriptionLanguage.german.defaultFillers)
    }

    func testSaveAndLoadFillersForLanguage() {
        let defaults = UserDefaults(suiteName: "test_fillers_\(UUID().uuidString)")!
        let custom = ["pues", "vale"]
        TrainingFillerPreferences.save(custom, for: "es", defaults: defaults)
        let loaded = TrainingFillerPreferences.currentFillers(for: "es", defaults: defaults)
        XCTAssertEqual(loaded, custom)
    }

    func testResetFillersForLanguage() {
        let defaults = UserDefaults(suiteName: "test_fillers_\(UUID().uuidString)")!
        TrainingFillerPreferences.save(["custom"], for: "fr", defaults: defaults)
        TrainingFillerPreferences.reset(for: "fr", defaults: defaults)
        let loaded = TrainingFillerPreferences.currentFillers(for: "fr", defaults: defaults)
        XCTAssertEqual(loaded, TranscriptionLanguage.french.defaultFillers)
    }

    func testEnglishFillersMatchDeepgramHesitationVocabulary() {
        let fillers = TranscriptionLanguage.english.defaultFillers
        // Deepgram emits these verbatim when filler_words=true; anything it never
        // emits is dead weight in the list users see in Settings.
        XCTAssertTrue(fillers.contains("um"))
        XCTAssertTrue(fillers.contains("uh"))
        XCTAssertTrue(fillers.contains("mhmm"))
        XCTAssertFalse(fillers.contains("hmm"))
        XCTAssertFalse(fillers.contains("hm"))
        XCTAssertFalse(fillers.contains("er"))
    }

    /// Deliberately avoids `compute`, which reads the user's saved filler list from
    /// `UserDefaults.standard` and so would depend on the host machine's prefs.
    func testDefaultEnglishFillersMatchDeepgramHesitationsInTranscriptText() {
        let tokens = TrainingMetrics.tokenize("Mhmm, that makes sense. Um, so, uh, Mhmm.")
        let counts = TranscriptionLanguage.english.defaultFillers.reduce(into: [String: Int]()) { acc, phrase in
            let n = TrainingMetrics.countPhraseOccurrences(of: TrainingMetrics.tokenize(phrase), in: tokens)
            if n > 0 { acc[phrase] = n }
        }
        XCTAssertEqual(counts["mhmm"], 2)
        XCTAssertEqual(counts["um"], 1)
        XCTAssertEqual(counts["uh"], 1)
    }

    func testComputeWithSpanishFillers() {
        let segments = [
            TrainingMetrics.Segment(text: "bueno o sea el proyecto va bien", speaker: 1000, isFinal: true, timestamp: 0),
        ]
        let metrics = TrainingMetrics.compute(from: segments, duration: 30, language: "es")
        XCTAssertGreaterThan(metrics.speakers[0].totalFillers, 0)
    }

    func testComputeAttributesYouToExplicitSelfID() {
        // Speaker 2 is the user (not the mic default). Talk ratio and "You" label
        // should attach to speaker 2, not 1000.
        let segments = [
            TrainingMetrics.Segment(text: "hey everyone quick question", speaker: 2, isFinal: true, timestamp: 0),
            TrainingMetrics.Segment(text: "that is an interesting point", speaker: 0, isFinal: true, timestamp: 5),
        ]
        let metrics = TrainingMetrics.compute(from: segments, duration: 30, selfIDs: [2])

        let you = metrics.speakers.first(where: { $0.isLocalMic })
        XCTAssertNotNil(you)
        XCTAssertEqual(you?.speakerLabel, "You")
        XCTAssertEqual(you?.wordCount, 4)
        XCTAssertEqual(metrics.talkRatioYou, 4.0 / 9.0, accuracy: 0.01)
    }

    func testComputeMergesMultipleSelfSpeakersIntoOneYouRow() {
        // Diarization can split one person's speech across multiple speaker IDs.
        // When the user marks both IDs as "me", all of those words should collapse
        // into a single "You" row in the training stats instead of showing two.
        let segments = [
            TrainingMetrics.Segment(text: "so basically we need to align the roadmap", speaker: 2, isFinal: true, timestamp: 0),
            TrainingMetrics.Segment(text: "that sounds good to me", speaker: 1, isFinal: true, timestamp: 5),
            TrainingMetrics.Segment(text: "and also we should double click on pricing", speaker: 3, isFinal: true, timestamp: 10),
        ]
        let metrics = TrainingMetrics.compute(from: segments, duration: 60, selfIDs: [2, 3])

        let youRows = metrics.speakers.filter { $0.isLocalMic }
        XCTAssertEqual(youRows.count, 1, "self-speakers should collapse into a single You row")
        let you = youRows.first!
        XCTAssertEqual(you.speakerLabel, "You")
        // 8 words from speaker 2 + 8 words from speaker 3 = 16 total "You" words.
        XCTAssertEqual(you.wordCount, 16)

        // The non-self speaker should still be reported separately.
        let others = metrics.speakers.filter { !$0.isLocalMic }
        XCTAssertEqual(others.count, 1)
        XCTAssertEqual(others.first?.wordCount, 5)
    }

    func testComputeUsesMappedNameWhenSpeakerNotSelf() {
        let segments = [
            TrainingMetrics.Segment(text: "hello world", speaker: 1000, isFinal: true, timestamp: 0),
            TrainingMetrics.Segment(text: "nice to meet you", speaker: 0, isFinal: true, timestamp: 5),
        ]
        let names = ["0": "Alice"]
        let metrics = TrainingMetrics.compute(from: segments, duration: 30, names: names)
        let alice = metrics.speakers.first(where: { !$0.isLocalMic })
        XCTAssertEqual(alice?.speakerLabel, "Alice")
    }

    // MARK: - Speaker presentations

    func testSpeakerPresentationsMergeDiarizationIDsWithSameDisplayedName() throws {
        let metrics = TrainingMetrics(
            speakers: [
                speakerStats(label: "You", isLocal: true, words: 80, fillers: ["um": 1]),
                speakerStats(label: "Max", words: 50, fillers: ["uh": 2]),
                speakerStats(label: "MAX", words: 30, fillers: ["uh": 1, "like": 2]),
            ],
            talkRatioYou: 0.5,
            durationMinutes: 2
        )

        let presentations = metrics.speakerPresentations()
        XCTAssertEqual(presentations.map(\.summary.speakerLabel), ["You", "Max"])

        let max = try XCTUnwrap(presentations.last?.summary)
        XCTAssertEqual(max.wordCount, 80)
        XCTAssertEqual(max.totalFillers, 5)
        XCTAssertEqual(max.fillers.first(where: { $0.word == "uh" })?.count, 3)
        XCTAssertFalse(presentations.last?.hasMultipleDetails ?? true)
    }

    func testSpeakerPresentationsExposeDistinctPeopleBehindOthers() throws {
        let metrics = TrainingMetrics(
            speakers: [
                speakerStats(label: "You", isLocal: true, words: 100),
                speakerStats(label: "Max", words: 60, fillers: ["um": 2]),
                speakerStats(label: "Alex", words: 40, fillers: ["like": 3]),
            ],
            talkRatioYou: 0.5,
            durationMinutes: 2
        )

        let others = try XCTUnwrap(metrics.speakerPresentations().last)
        XCTAssertEqual(others.summary.speakerLabel, "Others")
        XCTAssertEqual(others.summary.wordCount, 100)
        XCTAssertEqual(others.summary.totalFillers, 5)
        XCTAssertEqual(others.details.map(\.speakerLabel), ["Max", "Alex"])
        XCTAssertTrue(others.hasMultipleDetails)
    }

    // MARK: - Personalized coaching guidance

    @MainActor
    func testCoachingOverviewSignatureIgnoresMeetingUntilItCompletes() {
        let meeting = Meeting(
            title: "Live meeting",
            startTime: Date(timeIntervalSince1970: 100),
            segments: [
                TranscriptSegment(
                    text: "This meeting is still live.",
                    speaker: DeepgramService.micSpeakerID,
                    timestamp: 1,
                    isFinal: true
                )
            ]
        )
        XCTAssertNil(CoachingOverviewStore.signature(for: meeting))

        meeting.title = "Renamed while live"
        XCTAssertNil(CoachingOverviewStore.signature(for: meeting))

        meeting.endTime = Date(timeIntervalSince1970: 200)
        XCTAssertNotNil(CoachingOverviewStore.signature(for: meeting))
    }

    @MainActor
    func testCoachingOverviewSignatureTracksDerivedMetricInputs() {
        let meeting = Meeting(
            title: "Completed meeting",
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            segments: [
                TranscriptSegment(
                    text: "A completed coaching sample.",
                    speaker: DeepgramService.micSpeakerID,
                    timestamp: 1,
                    isFinal: true
                )
            ]
        )
        let original = CoachingOverviewStore.signature(for: meeting)

        meeting.transcriptRevision += 1
        let revised = CoachingOverviewStore.signature(for: meeting)
        XCTAssertNotEqual(revised, original)

        meeting.setSpeakerName(id: "0", name: "Alex")
        XCTAssertNotEqual(CoachingOverviewStore.signature(for: meeting), revised)
    }

    @MainActor
    func testCoachingOverviewCachesCompletedRowsAndPrunesDeletedMeetingsImmediately() async throws {
        let meeting = Meeting(
            title: "Cached meeting",
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            segments: [
                TranscriptSegment(
                    text: "I have a useful coaching example for this meeting.",
                    speaker: DeepgramService.micSpeakerID,
                    timestamp: 1,
                    isFinal: true
                )
            ]
        )
        let store = CoachingOverviewStore()

        store.refreshIfNeeded(meetings: [meeting])
        try await waitForCoachingStore(store) {
            store.rows.map(\.id) == [meeting.id]
        }
        XCTAssertEqual(store.rows.map(\.id), [meeting.id])

        store.refreshIfNeeded(meetings: [])
        XCTAssertTrue(store.rows.isEmpty)
        XCTAssertFalse(store.isComputing)
    }

    @MainActor
    func testCoachingOverviewKeepsCachedRowVisibleWhileChangedMeetingRefreshes() async throws {
        let meeting = Meeting(
            title: "Original title",
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            segments: [
                TranscriptSegment(
                    text: "I have a useful coaching example for this meeting.",
                    speaker: DeepgramService.micSpeakerID,
                    timestamp: 1,
                    isFinal: true
                )
            ]
        )
        let store = CoachingOverviewStore()
        store.refreshIfNeeded(meetings: [meeting])
        try await waitForCoachingStore(store) {
            store.rows.first?.title == "Original title"
        }

        meeting.title = "Updated title"
        store.refreshIfNeeded(meetings: [meeting])
        XCTAssertEqual(store.rows.first?.title, "Original title")

        try await waitForCoachingStore(store) {
            store.rows.first?.title == "Updated title"
        }
        XCTAssertEqual(store.rows.first?.title, "Updated title")
    }

    func testCoachingAdvisorNeedsAtLeastOneSnapshot() {
        XCTAssertNil(CoachingAdvisor.analyze([]))
    }

    func testCoachingAdvisorBuildsBaselineBeforeFourMeetings() throws {
        let report = try XCTUnwrap(CoachingAdvisor.analyze([
            coachingSnapshot(day: 1),
            coachingSnapshot(day: 2),
            coachingSnapshot(day: 3),
        ]))

        XCTAssertEqual(report.meetingCount, 3)
        XCTAssertTrue(report.summaries.allSatisfy { $0.trend == .buildingBaseline })
        XCTAssertFalse(report.summaries.contains { $0.metric == .talkRatio })
    }

    func testCoachingAdvisorComparesDistinctRecentAndPreviousWindows() throws {
        let report = try XCTUnwrap(CoachingAdvisor.analyze([
            coachingSnapshot(day: 1, fillers: 8),
            coachingSnapshot(day: 2, fillers: 8),
            coachingSnapshot(day: 3, fillers: 2),
            coachingSnapshot(day: 4, fillers: 2),
        ]))
        let fillers = try XCTUnwrap(report.summaries.first { $0.metric == .fillers })

        XCTAssertEqual(fillers.recentValue, "2.0 / min")
        XCTAssertEqual(fillers.previousValue, "8.0 / min")
        XCTAssertEqual(fillers.trend, .improving)
        XCTAssertEqual(fillers.status, .strong)
    }

    func testCoachingComparisonToneUsesMetricMeaning() {
        XCTAssertEqual(CoachingAdvisor.comparisonTone(for: .fillers, latest: 2, baseline: 4), .positive)
        XCTAssertEqual(CoachingAdvisor.comparisonTone(for: .monologue, latest: 300, baseline: 150), .negative)
        XCTAssertEqual(CoachingAdvisor.comparisonTone(for: .questions, latest: 8, baseline: 4), .positive)
        XCTAssertEqual(CoachingAdvisor.comparisonTone(for: .pace, latest: 120, baseline: 90), .positive)
        XCTAssertEqual(CoachingAdvisor.comparisonTone(for: .pace, latest: 220, baseline: 150), .negative)
        XCTAssertEqual(CoachingAdvisor.comparisonTone(for: .clarity, latest: 8, baseline: 12), .neutral)
        XCTAssertEqual(CoachingAdvisor.comparisonTone(for: .talkRatio, latest: nil, baseline: 0.5), .neutral)
    }

    func testCoachingAdvisorPrioritizesAnExtremePace() throws {
        let report = try XCTUnwrap(CoachingAdvisor.analyze([
            coachingSnapshot(day: 1, pace: 230, talkRatio: 0.5),
        ]))

        XCTAssertEqual(report.focus.metric, .pace)
        XCTAssertEqual(report.focus.status, .focus)
        XCTAssertEqual(report.focus.headline, "Give ideas room to land")
        XCTAssertTrue(report.strengths.contains { $0.metric == .fillers })
    }

    func testCoachingAdvisorIncludesFillerSuggestion() throws {
        let report = try XCTUnwrap(CoachingAdvisor.analyze([
            coachingSnapshot(day: 1, fillers: 8, topFiller: "um"),
        ]))
        let fillers = try XCTUnwrap(report.summaries.first { $0.metric == .fillers })

        XCTAssertEqual(fillers.headline, "Make pauses do the work")
        XCTAssertTrue(fillers.tip.contains("one filler"))
    }

    func testCoachingAdvisorCarriesGroundedExampleIntoFocus() throws {
        let meetingID = UUID()
        let example = CoachingExample(
            meetingID: meetingID,
            meetingTitle: "Product review",
            meetingDate: Date(timeIntervalSince1970: 86_400),
            label: "A recent passage behind this pattern",
            excerpt: "I want to walk through the whole plan before we decide."
        )
        let report = try XCTUnwrap(CoachingAdvisor.analyze([
            coachingSnapshot(day: 1, pace: 230, examples: [.pace: example]),
        ]))

        XCTAssertEqual(report.focus.metric, .pace)
        XCTAssertEqual(report.focus.example, example)
    }

    func testCoachingExampleExtractorFindsFillerInUserSpeech() throws {
        let meetingID = UUID()
        let examples = CoachingExampleExtractor.examples(
            meetingID: meetingID,
            meetingTitle: "Weekly review",
            meetingDate: Date(timeIntervalSince1970: 172_800),
            segments: [
                TrainingMetrics.Segment(
                    text: "Um, I think the launch plan is ready.",
                    speaker: DeepgramService.micSpeakerID,
                    isFinal: true,
                    timestamp: 1
                ),
                TrainingMetrics.Segment(text: "Great, let's ship it.", speaker: 0, isFinal: true, timestamp: 2),
            ],
            selfIDs: [],
            detectedFillers: ["um"],
            topFiller: "um",
            talkRatio: 0.6
        )
        let filler = try XCTUnwrap(examples[.fillers])

        XCTAssertEqual(filler.meetingID, meetingID)
        XCTAssertEqual(filler.meetingTitle, "Weekly review")
        XCTAssertEqual(filler.meetingDate, Date(timeIntervalSince1970: 172_800))
        XCTAssertEqual(filler.label, "A filler in context")
        XCTAssertTrue(filler.excerpt.hasPrefix("Um,"))
    }

    func testCoachingExampleExtractorUsesRemoteMomentWhenNoQuestionWasAsked() throws {
        let examples = CoachingExampleExtractor.examples(
            meetingID: UUID(),
            meetingTitle: "Customer call",
            meetingDate: Date(timeIntervalSince1970: 259_200),
            segments: [
                TrainingMetrics.Segment(text: "Here is the rollout plan.", speaker: 2, isFinal: true, timestamp: 1),
                TrainingMetrics.Segment(
                    text: "Onboarding takes longer because our data is spread across three systems.",
                    speaker: 0,
                    isFinal: true,
                    timestamp: 2
                ),
            ],
            selfIDs: [2],
            detectedFillers: [],
            topFiller: nil,
            talkRatio: 0.4
        )
        let question = try XCTUnwrap(examples[.questions])

        XCTAssertEqual(question.label, "A moment you could explore further")
        XCTAssertTrue(question.excerpt.contains("three systems"))
    }

    func testCoachingExampleExtractorClipsLongEvidenceAtWordBoundary() {
        let text = Array(repeating: "thoughtful", count: 30).joined(separator: "   ")
        let clipped = CoachingExampleExtractor.clipped(text, limit: 40)

        XCTAssertLessThanOrEqual(clipped.count, 41)
        XCTAssertTrue(clipped.hasSuffix("…"))
        XCTAssertFalse(clipped.contains("  "))
    }

    func testTrainingRowNormalizesQuestionsAndCarriesConversationMetrics() {
        let row = TrainingRow(
            id: UUID(),
            date: Date(),
            dateString: "26-08-08",
            title: "Short meeting",
            fillers: 1,
            pace: 140,
            clarity: 10,
            questions: 1,
            durationMinutes: 2,
            talkRatio: 0.6,
            longestMonologue: 80,
            topFiller: "um",
            examples: [:]
        )

        XCTAssertEqual(row.coachingSnapshot.questionsPer30Minutes, 6, accuracy: 0.001)
        XCTAssertEqual(row.coachingSnapshot.talkRatio, 0.6)
        XCTAssertEqual(row.coachingSnapshot.longestMonologueWords, 80)
    }

    @MainActor
    func testCoachingChartPointsUseMeetingSequenceAndPreserveMissingMetricGaps() {
        let rows = [
            trainingRow(day: 3, talkRatio: 0.55),
            trainingRow(day: 2, talkRatio: nil),
            trainingRow(day: 1, talkRatio: 0.45),
        ]

        let points = TrainingStatsOverview.chartPoints(from: rows) { $0.talkRatio }

        XCTAssertEqual(points.map(\.meetingIndex), [1, 3])
        XCTAssertEqual(points.map(\.value), [0.45, 0.55])
        XCTAssertEqual(points.map(\.date), [
            Date(timeIntervalSince1970: 86_400),
            Date(timeIntervalSince1970: 3 * 86_400),
        ])
    }

    @MainActor
    func testCoachingChartMeetingAxisAdaptsToHistorySize() {
        XCTAssertEqual(
            TrainingStatsOverview.chartAxisMeetingIndices(meetingCount: 4),
            [1, 2, 3, 4]
        )
        XCTAssertEqual(
            TrainingStatsOverview.chartAxisMeetingIndices(meetingCount: 23),
            [1, 5, 10, 15, 20, 23]
        )
        XCTAssertEqual(
            TrainingStatsOverview.chartAxisMeetingIndices(meetingCount: 100),
            [1, 20, 40, 60, 80, 100]
        )

        let veryLargeHistory = TrainingStatsOverview.chartAxisMeetingIndices(meetingCount: 10_000)
        XCTAssertLessThanOrEqual(veryLargeHistory.count, 7)
        XCTAssertEqual(veryLargeHistory.first, 1)
        XCTAssertEqual(veryLargeHistory.last, 10_000)
    }

    private func trainingRow(day: TimeInterval, talkRatio: Double?) -> TrainingRow {
        TrainingRow(
            id: UUID(),
            date: Date(timeIntervalSince1970: day * 86_400),
            dateString: "",
            title: "Meeting",
            fillers: 1,
            pace: 140,
            clarity: 10,
            questions: 1,
            durationMinutes: 30,
            talkRatio: talkRatio,
            longestMonologue: 80,
            topFiller: nil,
            examples: [:]
        )
    }

    @MainActor
    private func waitForCoachingStore(
        _ store: CoachingOverviewStore,
        until condition: () -> Bool
    ) async throws {
        for _ in 0..<400 {
            if condition(), !store.isComputing { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for Coaching overview refresh")
    }

    private func coachingSnapshot(
        day: TimeInterval,
        fillers: Double = 1,
        pace: Double = 145,
        clarity: Double = 10,
        questions: Double = 4,
        talkRatio: Double? = nil,
        monologue: Double = 100,
        topFiller: String? = nil,
        examples: [CoachingMetric: CoachingExample] = [:]
    ) -> CoachingSnapshot {
        CoachingSnapshot(
            date: Date(timeIntervalSince1970: day * 86_400),
            fillersPerMinute: fillers,
            wordsPerMinute: pace,
            avgWordsPerTurn: clarity,
            questionsPer30Minutes: questions,
            talkRatio: talkRatio,
            longestMonologueWords: monologue,
            topFiller: topFiller,
            examples: examples
        )
    }

    private func speakerStats(
        label: String,
        isLocal: Bool = false,
        words: Int,
        fillers: [String: Int] = [:]
    ) -> TrainingMetrics.SpeakerStats {
        let entries = fillers
            .map { TrainingMetrics.FillerEntry(word: $0.key, count: $0.value) }
            .sorted { $0.word < $1.word }
        let totalFillers = fillers.values.reduce(0, +)
        return TrainingMetrics.SpeakerStats(
            speakerLabel: label,
            isLocalMic: isLocal,
            wordCount: words,
            segmentCount: 1,
            fillers: entries,
            totalFillers: totalFillers,
            fillersPerMinute: Double(totalFillers) / 2,
            wordsPerMinute: Double(words) / 2,
            longestMonologueWords: words,
            questionsAsked: 0,
            avgWordsPerTurn: Double(words)
        )
    }
}
