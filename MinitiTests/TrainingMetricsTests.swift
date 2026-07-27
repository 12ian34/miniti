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
}
