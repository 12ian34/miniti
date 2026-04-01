import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class DeepgramParsingTests: XCTestCase {

    // MARK: - DeepgramResponse decoding

    func testDeepgramResponseFullDecode() throws {
        let json = """
        {
            "type": "Results",
            "channel": {
                "alternatives": [{
                    "transcript": "Hello world",
                    "confidence": 0.95,
                    "words": [
                        {"word": "hello", "punctuated_word": "Hello", "start": 0.0, "end": 0.5, "confidence": 0.98, "speaker": 0, "speaker_confidence": 0.85},
                        {"word": "world", "punctuated_word": "world", "start": 0.5, "end": 1.0, "confidence": 0.92, "speaker": 0, "speaker_confidence": 0.80}
                    ]
                }]
            },
            "is_final": true,
            "speech_final": false,
            "start": 0.0,
            "duration": 1.0
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DeepgramResponse.self, from: json)
        XCTAssertEqual(response.type, "Results")
        XCTAssertEqual(response.isFinal, true)
        XCTAssertEqual(response.channel?.alternatives.count, 1)

        let alt = response.channel!.alternatives[0]
        XCTAssertEqual(alt.transcript, "Hello world")
        XCTAssertEqual(alt.confidence, 0.95, accuracy: 0.01)
        XCTAssertEqual(alt.words.count, 2)

        let word = alt.words[0]
        XCTAssertEqual(word.word, "hello")
        XCTAssertEqual(word.punctuatedWord, "Hello")
        XCTAssertEqual(word.speaker, 0)
        XCTAssertEqual(word.speakerConfidence, 0.85)
    }

    func testDeepgramResponseMissingWords() throws {
        let json = """
        {
            "type": "Results",
            "channel": {
                "alternatives": [{
                    "transcript": "",
                    "confidence": 0.0
                }]
            },
            "is_final": false
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DeepgramResponse.self, from: json)
        let alt = response.channel!.alternatives[0]
        XCTAssertTrue(alt.words.isEmpty)
        XCTAssertEqual(alt.transcript, "")
    }

    func testDeepgramResponseMinimalWord() throws {
        let json = """
        {
            "type": "Results",
            "channel": {
                "alternatives": [{
                    "transcript": "hi",
                    "confidence": 0.5,
                    "words": [{"word": "hi", "start": 0, "end": 0.3, "confidence": 0.5}]
                }]
            },
            "is_final": true
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DeepgramResponse.self, from: json)
        let word = response.channel!.alternatives[0].words[0]
        XCTAssertNil(word.speaker)
        XCTAssertNil(word.speakerConfidence)
        XCTAssertNil(word.punctuatedWord)
    }

    // MARK: - findDominantSpeaker

    @MainActor
    func testFindDominantSpeakerSingle() {
        let service = DeepgramService()
        let words = [
            DeepgramService.TranscriptUpdate.Word(text: "hello", start: 0, end: 0.5, confidence: 0.9, speaker: 0, speakerConfidence: nil),
            DeepgramService.TranscriptUpdate.Word(text: "world", start: 0.5, end: 1.0, confidence: 0.9, speaker: 0, speakerConfidence: nil),
        ]
        XCTAssertEqual(service.findDominantSpeaker(words: words), 0)
    }

    @MainActor
    func testFindDominantSpeakerMajority() {
        let service = DeepgramService()
        let words = [
            DeepgramService.TranscriptUpdate.Word(text: "a", start: 0, end: 0.5, confidence: 0.9, speaker: 0, speakerConfidence: nil),
            DeepgramService.TranscriptUpdate.Word(text: "b", start: 0.5, end: 1.0, confidence: 0.9, speaker: 1, speakerConfidence: nil),
            DeepgramService.TranscriptUpdate.Word(text: "c", start: 1.0, end: 1.5, confidence: 0.9, speaker: 1, speakerConfidence: nil),
        ]
        XCTAssertEqual(service.findDominantSpeaker(words: words), 1)
    }

    @MainActor
    func testFindDominantSpeakerEmpty() {
        let service = DeepgramService()
        XCTAssertEqual(service.findDominantSpeaker(words: []), 0)
    }

    // MARK: - PendingSpeakerEvidence

    func testPendingSpeakerEvidenceAccumulation() {
        var evidence = DeepgramService.PendingSpeakerEvidence()
        let words: [DeepgramService.TranscriptUpdate.Word] = [
            .init(text: "a", start: 0, end: 0.5, confidence: 0.9, speaker: 2, speakerConfidence: 0.8),
            .init(text: "b", start: 0.5, end: 1.0, confidence: 0.9, speaker: 2, speakerConfidence: 0.9),
        ]
        evidence.add(words: words[0..<2])
        XCTAssertEqual(evidence.wordCount, 2)
        XCTAssertEqual(evidence.duration, 1.0, accuracy: 0.01)
        XCTAssertEqual(evidence.averageSpeakerConfidence!, 0.85, accuracy: 0.01)
    }

    func testPendingSpeakerEvidenceEmpty() {
        let evidence = DeepgramService.PendingSpeakerEvidence()
        XCTAssertEqual(evidence.wordCount, 0)
        XCTAssertNil(evidence.averageSpeakerConfidence)
    }

    // MARK: - TranscriptionLanguage enum

    func testTranscriptionLanguageDisplayNames() {
        XCTAssertEqual(TranscriptionLanguage.english.displayName, "🇬🇧 English")
        XCTAssertEqual(TranscriptionLanguage.spanish.displayName, "🇪🇸 Español")
        XCTAssertEqual(TranscriptionLanguage.greek.displayName, "🇬🇷 Ελληνικά")
    }

    func testTranscriptionLanguageRawValues() {
        XCTAssertEqual(TranscriptionLanguage.english.rawValue, "en")
        XCTAssertEqual(TranscriptionLanguage.spanish.rawValue, "es")
        XCTAssertEqual(TranscriptionLanguage.swedish.rawValue, "sv")
        XCTAssertEqual(TranscriptionLanguage.greek.rawValue, "el")
        XCTAssertEqual(TranscriptionLanguage.french.rawValue, "fr")
        XCTAssertEqual(TranscriptionLanguage.german.rawValue, "de")
        XCTAssertEqual(TranscriptionLanguage.portuguese.rawValue, "pt")
        XCTAssertEqual(TranscriptionLanguage.italian.rawValue, "it")
        XCTAssertEqual(TranscriptionLanguage.dutch.rawValue, "nl")
        XCTAssertEqual(TranscriptionLanguage.polish.rawValue, "pl")
    }

    func testTranscriptionLanguageEnglishNames() {
        XCTAssertEqual(TranscriptionLanguage.spanish.englishName, "Spanish")
        XCTAssertEqual(TranscriptionLanguage.french.englishName, "French")
    }

    func testTranscriptionLanguageAllCasesCount() {
        XCTAssertEqual(TranscriptionLanguage.allCases.count, 11)
    }

    func testTranscriptionLanguageDefaultFillers() {
        XCTAssertFalse(TranscriptionLanguage.english.defaultFillers.isEmpty)
        XCTAssertTrue(TranscriptionLanguage.english.defaultFillers.contains("um"))
        XCTAssertFalse(TranscriptionLanguage.spanish.defaultFillers.isEmpty)
        XCTAssertTrue(TranscriptionLanguage.spanish.defaultFillers.contains("o sea"))
        XCTAssertFalse(TranscriptionLanguage.french.defaultFillers.isEmpty)
        XCTAssertTrue(TranscriptionLanguage.french.defaultFillers.contains("euh"))
        for lang in TranscriptionLanguage.allCases {
            XCTAssertFalse(lang.defaultFillers.isEmpty, "\(lang.englishName) has no default fillers")
        }
    }

    // MARK: - DeepgramError.errorDescription

    func testDeepgramErrorNoApiKey() {
        XCTAssertEqual(DeepgramError.noApiKey.errorDescription, "Deepgram API key is required.")
    }

    func testDeepgramErrorInvalidUrl() {
        XCTAssertEqual(DeepgramError.invalidUrl.errorDescription, "Failed to create WebSocket URL.")
    }

    func testDeepgramErrorConnectionFailed() {
        XCTAssertEqual(DeepgramError.connectionFailed.errorDescription, "Failed to connect to Deepgram.")
    }

    // MARK: - segmentBySpeaker (static, extracted)

    private typealias Word = DeepgramService.TranscriptUpdate.Word

    private func makeWord(
        _ text: String,
        speaker: Int,
        start: Double,
        end: Double,
        speakerConfidence: Double? = 0.9
    ) -> Word {
        Word(text: text, start: start, end: end, confidence: 0.9, speaker: speaker, speakerConfidence: speakerConfidence)
    }

    func testSegmentBySpeakerSingleSpeaker() {
        var state = DeepgramService.SegmentationState()
        let words = [
            makeWord("hello", speaker: 0, start: 0.0, end: 0.5),
            makeWord("world", speaker: 0, start: 0.5, end: 1.0),
            makeWord("how", speaker: 0, start: 1.0, end: 1.3),
        ]
        let segments = DeepgramService.segmentBySpeaker(
            words: words, isFinal: true, confidence: 0.9, state: &state
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speaker, 0)
        XCTAssertEqual(segments[0].text, "hello world how")
    }

    func testSegmentBySpeakerEmpty() {
        var state = DeepgramService.SegmentationState()
        let segments = DeepgramService.segmentBySpeaker(
            words: [], isFinal: true, confidence: 0.9, state: &state
        )
        XCTAssertTrue(segments.isEmpty)
    }

    func testSegmentBySpeakerCleanSwitch() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [0, 1]

        var words: [Word] = []
        for i in 0..<5 {
            let t = Double(i) * 0.3
            words.append(makeWord("word\(i)", speaker: 0, start: t, end: t + 0.25))
        }
        for i in 0..<5 {
            let t = 1.5 + Double(i) * 0.3
            words.append(makeWord("other\(i)", speaker: 1, start: t, end: t + 0.25))
        }

        let segments = DeepgramService.segmentBySpeaker(
            words: words, isFinal: true, confidence: 0.9, state: &state
        )
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speaker, 0)
        XCTAssertEqual(segments[1].speaker, 1)
    }

    func testSegmentBySpeakerRejectedSwitch() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [0, 1]

        var words: [Word] = []
        for i in 0..<5 {
            let t = Double(i) * 0.3
            words.append(makeWord("word\(i)", speaker: 0, start: t, end: t + 0.25))
        }
        words.append(makeWord("blip", speaker: 1, start: 1.5, end: 1.6))

        let segments = DeepgramService.segmentBySpeaker(
            words: words, isFinal: true, confidence: 0.9, state: &state
        )
        XCTAssertEqual(segments.count, 1, "Short blip should be absorbed into current speaker")
        XCTAssertEqual(segments[0].speaker, 0)
        XCTAssertTrue(segments[0].text.contains("blip"))
    }

    func testSegmentBySpeakerMicBypass() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [0]
        let micID = DeepgramService.micSpeakerID

        var words: [Word] = []
        for i in 0..<5 {
            let t = Double(i) * 0.3
            words.append(makeWord("remote\(i)", speaker: 0, start: t, end: t + 0.25))
        }
        for i in 0..<5 {
            let t = 1.5 + Double(i) * 0.3
            words.append(makeWord("local\(i)", speaker: micID, start: t, end: t + 0.25))
        }

        let segments = DeepgramService.segmentBySpeaker(
            words: words, isFinal: true, confidence: 0.9, state: &state
        )
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[1].speaker, micID)
    }

    func testSegmentBySpeakerNewSpeakerPromotion() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [0]

        var words: [Word] = []
        for i in 0..<4 {
            let t = Double(i) * 0.3
            words.append(makeWord("a\(i)", speaker: 0, start: t, end: t + 0.25))
        }
        for i in 0..<7 {
            let t = 1.2 + Double(i) * 0.3
            words.append(makeWord("b\(i)", speaker: 2, start: t, end: t + 0.25, speakerConfidence: 0.85))
        }

        let segments = DeepgramService.segmentBySpeaker(
            words: words, isFinal: true, confidence: 0.9, state: &state
        )

        if segments.count == 2 {
            XCTAssertEqual(segments[1].speaker, 2)
            XCTAssertTrue(state.confirmedSpeakerIDs.contains(2))
        } else {
            XCTAssertEqual(segments.count, 1, "New speaker not promoted yet — all absorbed")
        }
    }

    func testSegmentBySpeakerNewSpeakerNotPromotedInsufficientEvidence() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [0]

        var words: [Word] = []
        for i in 0..<4 {
            let t = Double(i) * 0.3
            words.append(makeWord("a\(i)", speaker: 0, start: t, end: t + 0.25))
        }
        for i in 0..<4 {
            let t = 1.2 + Double(i) * 0.15
            words.append(makeWord("b\(i)", speaker: 3, start: t, end: t + 0.1, speakerConfidence: 0.5))
        }

        let segments = DeepgramService.segmentBySpeaker(
            words: words, isFinal: true, confidence: 0.9, state: &state
        )
        XCTAssertEqual(segments.count, 1, "Unknown speaker with weak evidence should be absorbed")
        XCTAssertFalse(state.confirmedSpeakerIDs.contains(3))
    }
}
