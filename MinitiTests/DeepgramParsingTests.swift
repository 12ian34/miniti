import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class DeepgramParsingTests: XCTestCase {

    // MARK: - Authorization scheme

    func testAuthorizationHeaderBearerForManagedJWT() {
        let header = DeepgramAuthorizationScheme.bearer.authorizationHeader(credential: "eyJhbGciOi.test")
        XCTAssertEqual(header, "Bearer eyJhbGciOi.test")
    }

    func testAuthorizationHeaderTokenForBYOKKey() {
        let header = DeepgramAuthorizationScheme.token.authorizationHeader(credential: "dg-api-key")
        XCTAssertEqual(header, "Token dg-api-key")
    }

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
            "channel_index": [0, 2],
            "is_final": true,
            "speech_final": false,
            "start": 0.0,
            "duration": 1.0
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DeepgramResponse.self, from: json)
        XCTAssertEqual(response.type, "Results")
        XCTAssertEqual(response.isFinal, true)
        XCTAssertEqual(response.channelIndex, [0, 2])
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

    // MARK: - PersonalDictionaryPreferences

    func testPersonalDictionaryNormalizesTerms() {
        let result = PersonalDictionaryPreferences.normalizedTerms([
            "  Lightdash  ",
            "LIGHTDASH",
            "Sales   Force",
            "",
            "   "
        ])

        XCTAssertEqual(result, ["Lightdash", "Sales Force"])
    }

    func testPersonalDictionarySaveAndLoad() {
        let defaults = UserDefaults(suiteName: "test_personal_dictionary_\(UUID().uuidString)")!
        let terms = ["lightdash", "Acme Inc"]

        PersonalDictionaryPreferences.save(terms, defaults: defaults)

        XCTAssertEqual(PersonalDictionaryPreferences.currentTerms(defaults: defaults), terms)
    }

    func testPersonalDictionaryEmptySaveClearsStorage() {
        let defaults = UserDefaults(suiteName: "test_personal_dictionary_\(UUID().uuidString)")!
        PersonalDictionaryPreferences.save(["Lightdash"], defaults: defaults)

        PersonalDictionaryPreferences.save([], defaults: defaults)

        XCTAssertNil(defaults.data(forKey: PersonalDictionaryPreferences.storageKey))
        XCTAssertTrue(PersonalDictionaryPreferences.currentTerms(defaults: defaults).isEmpty)
    }

    func testDeepgramKeytermsIncludeDefaultsAndPersonalTerms() {
        let keyterms = PersonalDictionaryPreferences.deepgramKeyterms(personalTerms: [
            "lightdash",
            "Acme",
            "  Ahuja  ",
            "MEDDPICC"
        ])

        XCTAssertEqual(keyterms, ["Miniti", "Lightdash", "Ahuja", "Acme", "MEDDPICC"])
    }

    func testDeepgramKeytermsMergeSessionTermsAndCapAt100() {
        let personal = (0..<40).map { "Personal\($0)" }
        let session = (0..<80).map { "Session\($0)" }
        let keyterms = PersonalDictionaryPreferences.deepgramKeyterms(
            personalTerms: personal,
            sessionTerms: session
        )

        XCTAssertEqual(keyterms.count, 100)
        XCTAssertEqual(keyterms.prefix(3), ["Miniti", "Lightdash", "Ahuja"])
        XCTAssertTrue(keyterms.contains("Personal0"))
        XCTAssertTrue(keyterms.contains("Session0"))
        XCTAssertFalse(keyterms.contains("Session79"), "Session terms should fill remaining budget after system+personal")
    }

    func testSessionKeytermsFromCalendarContext() {
        let terms = PersonalDictionaryPreferences.sessionKeyterms(
            meetingTitle: "Acme QBR",
            attendees: [
                (displayName: "Sarah Chen", domain: "acme.com", isSelf: false),
                (displayName: "Me", domain: "gmail.com", isSelf: true),
                (displayName: nil, domain: "lightdash.com", isSelf: false),
            ]
        )

        XCTAssertEqual(terms, ["Acme QBR", "Sarah Chen", "Acme", "Lightdash"])
    }

    func testSessionKeytermsSkipsUntitledAndConsumerDomains() {
        let terms = PersonalDictionaryPreferences.sessionKeyterms(
            meetingTitle: "untitled",
            attendees: [
                (displayName: "Bob", domain: "gmail.com", isSelf: false),
            ]
        )

        XCTAssertEqual(terms, ["Bob"])
    }

    func testPersonalDictionaryCorrectionsNormalizeAndRejectIdentity() {
        let pairs = PersonalDictionaryPreferences.normalizedCorrections([
            .init(heard: "  Meet  Up ", correct: "Meetup"),
            .init(heard: "MEET UP", correct: "Other"), // duplicate heard
            .init(heard: "same", correct: "SAME"), // identity
            .init(heard: "", correct: "x"),
            .init(heard: "ok", correct: ""),
        ])
        XCTAssertEqual(pairs, [.init(heard: "meet up", correct: "Meetup")])
    }

    func testPersonalDictionaryCorrectionsSaveAddsTerm() {
        let defaults = UserDefaults(suiteName: "test_personal_corrections_\(UUID().uuidString)")!
        PersonalDictionaryPreferences.saveCorrections(
            [.init(heard: "minitti", correct: "miniti")],
            defaults: defaults
        )
        XCTAssertEqual(
            PersonalDictionaryPreferences.currentCorrections(defaults: defaults),
            [.init(heard: "minitti", correct: "miniti")]
        )
        XCTAssertTrue(PersonalDictionaryPreferences.currentTerms(defaults: defaults).contains("miniti"))
    }

    func testTranscriptCorrectorWordBoundaryAndLongestFirst() {
        let corrector = TranscriptCorrector(corrections: [
            .init(heard: "meet", correct: "meat"),
            .init(heard: "meet up", correct: "Meetup"),
        ])
        XCTAssertEqual(corrector?.apply(to: "Let's meet up tomorrow"), "Let's Meetup tomorrow")
        XCTAssertEqual(corrector?.apply(to: "The meeting starts"), "The meeting starts")
        XCTAssertEqual(corrector?.apply(to: "Please Meet here"), "Please meat here")
        XCTAssertNil(TranscriptCorrector(corrections: []))
    }

    func testTranscriptCorrectorTreatsReplacementAsLiteralText() {
        // "$1" and backslashes in user text must not be read as regex templates.
        let corrector = TranscriptCorrector(corrections: [
            .init(heard: "budget", correct: "$100 \\ ok"),
        ])
        XCTAssertEqual(corrector?.apply(to: "the budget is set"), "the $100 \\ ok is set")
    }

    func testTranscriptCorrectorPunctuationAndUnicode() {
        let corrector = TranscriptCorrector(corrections: [
            .init(heard: "zoe", correct: "Zoë"),
            .init(heard: "many tea", correct: "miniti"),
        ])
        XCTAssertEqual(corrector?.apply(to: "Ask zoe, then many tea."), "Ask Zoë, then miniti.")
        XCTAssertEqual(corrector?.apply(to: "(zoe) 'many tea'"), "(Zoë) 'miniti'")
        XCTAssertEqual(corrector?.apply(to: "nothing here"), "nothing here")
    }

    func testPersonalDictionaryUpsertReplacesExistingHeardAndHonoursCap() {
        let defaults = UserDefaults(suiteName: "test_personal_upsert_\(UUID().uuidString)")!
        XCTAssertEqual(
            PersonalDictionaryPreferences.upsertCorrection(heard: "Many Tea", correct: "minity", defaults: defaults),
            .saved
        )
        // Re-correcting the same heard phrase must win, not be silently dropped.
        XCTAssertEqual(
            PersonalDictionaryPreferences.upsertCorrection(heard: "many tea", correct: "miniti", defaults: defaults),
            .saved
        )
        XCTAssertEqual(
            PersonalDictionaryPreferences.currentCorrections(defaults: defaults),
            [.init(heard: "many tea", correct: "miniti")]
        )
        XCTAssertEqual(
            PersonalDictionaryPreferences.upsertCorrection(heard: "same", correct: "Same", defaults: defaults),
            .invalid
        )

        for index in 1..<PersonalDictionaryPreferences.maxCorrections {
            _ = PersonalDictionaryPreferences.upsertCorrection(heard: "h\(index)", correct: "c\(index)", defaults: defaults)
        }
        XCTAssertEqual(PersonalDictionaryPreferences.currentCorrections(defaults: defaults).count, PersonalDictionaryPreferences.maxCorrections)
        XCTAssertEqual(
            PersonalDictionaryPreferences.upsertCorrection(heard: "overflow", correct: "x", defaults: defaults),
            .full
        )
        // Replacing an existing pair is still allowed when full.
        XCTAssertEqual(
            PersonalDictionaryPreferences.upsertCorrection(heard: "h1", correct: "c1b", defaults: defaults),
            .saved
        )

        PersonalDictionaryPreferences.saveCorrections([], defaults: defaults)
        XCTAssertNil(defaults.data(forKey: PersonalDictionaryPreferences.correctionsStorageKey))
    }

    func testPersonalDictionaryCorrectionsStripColonsForDeepgramReplace() {
        let items = PersonalDictionaryPreferences.deepgramReplaceItems(corrections: [
            .init(heard: "light:dash", correct: "Light:dash Cloud"),
        ])
        XCTAssertEqual(items.map(\.value), ["lightdash:Lightdash Cloud"])
    }

    func testTranscriptCorrectionSelectionSnapsToWordsAndRejectsCrossTurn() {
        let doc = NSAttributedString(string: "You · 0:01\nwe use many tea daily\nAlice · 0:05\nokay")
        let text = doc.string as NSString
        let finalized = text.length

        // Partial selection inside "many" snaps to the whole word.
        let partial = text.range(of: "an")
        XCTAssertEqual(
            TranscriptCorrectionSelection.snappedHeardText(in: doc, selectedRange: partial, finalizedLength: finalized),
            "many"
        )
        // Two words.
        let phrase = text.range(of: "many tea")
        XCTAssertEqual(
            TranscriptCorrectionSelection.snappedHeardText(in: doc, selectedRange: phrase, finalizedLength: finalized),
            "many tea"
        )
        // Crossing into the next turn (includes the newline and the header) is rejected.
        let crossing = text.range(of: "daily\nAlice")
        XCTAssertNil(
            TranscriptCorrectionSelection.snappedHeardText(in: doc, selectedRange: crossing, finalizedLength: finalized)
        )
        // Selection reaching into interim text (past finalizedLength) is rejected.
        XCTAssertNil(
            TranscriptCorrectionSelection.snappedHeardText(in: doc, selectedRange: phrase, finalizedLength: phrase.location + 2)
        )
        // Over the length cap is rejected.
        XCTAssertNil(
            TranscriptCorrectionSelection.snappedHeardText(in: doc, selectedRange: phrase, finalizedLength: finalized, maxCharacters: 3)
        )
    }

    func testTranscriptCorrectionSelectionWordsDedupesInOrder() {
        let words = TranscriptCorrectionSelection.words(in: "Hello hello, Miniti — and hello again.")
        XCTAssertEqual(words, ["Hello", "Miniti", "and", "again"])
    }

    func testDeepgramReplaceItemsFollowKeytermsShape() {
        let items = PersonalDictionaryPreferences.deepgramReplaceItems(corrections: [
            .init(heard: "minitti", correct: "miniti"),
            .init(heard: "light dash", correct: "Lightdash"),
        ])
        XCTAssertEqual(items.map(\.name), ["replace", "replace"])
        XCTAssertEqual(items.map(\.value), ["minitti:miniti", "light dash:Lightdash"])
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
            words: words,
            isFinal: true,
            confidence: 0.9,
            channelIndex: DeepgramService.systemChannelIndex,
            state: &state
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speaker, 0)
        XCTAssertEqual(segments[0].text, "hello world how")
        XCTAssertEqual(segments[0].channelIndex, DeepgramService.systemChannelIndex)
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

    #if !IOS_TEST_TARGET && DEBUG
    @MainActor
    func testSourceTrackingResetRealignsDeepgramTimestampsAfterReconnect() {
        let service = AudioCaptureService()

        service.appendSourceSampleForTesting(
            startTime: 1_200.0,
            endTime: 1_200.1,
            micEnergy: 1_000,
            sysEnergy: 0
        )

        XCTAssertEqual(
            service.dominantSource(from: 0.0, to: 0.1),
            .unknown,
            "A fresh Deepgram socket reports word times from zero, so stale old-session source samples should not match."
        )

        service.resetSourceTracking()
        service.appendSourceSampleForTesting(
            startTime: 0.0,
            endTime: 0.1,
            micEnergy: 1_000,
            sysEnergy: 0
        )

        XCTAssertEqual(service.dominantSource(from: 0.0, to: 0.1), .mic)
    }

    @MainActor
    func testSourceTrackingRingOverwritesOldestSamplesWithoutLosingLatest() {
        let service = AudioCaptureService()
        service.appendSourceSampleForTesting(
            startTime: 0,
            endTime: 0.1,
            micEnergy: 1_000,
            sysEnergy: 0
        )
        for index in 0..<6_000 {
            let start = 10.0 + Double(index)
            service.appendSourceSampleForTesting(
                startTime: start,
                endTime: start + 0.1,
                micEnergy: 0,
                sysEnergy: 1_000
            )
        }

        XCTAssertEqual(service.dominantSource(from: 0, to: 0.1), .unknown)
        XCTAssertEqual(service.dominantSource(from: 6_009, to: 6_009.1), .system)
    }

    func testInt16RMSUsesEntireBuffer() {
        let samples: [Int16] = [3, 4, 0, 0]
        let rms = samples.withUnsafeBufferPointer {
            AudioCaptureService.rmsInt16($0.baseAddress!, count: $0.count)
        }
        XCTAssertEqual(rms, sqrt(6.25), accuracy: 0.0001)
    }

    func testInterleaveStereoInt16PadsSystemUnderrun() {
        let mic: [Int16] = [100, 200, 300]
        let sys: [Int16] = [10, 20]
        let data = mic.withUnsafeBufferPointer { micBuf in
            sys.withUnsafeBufferPointer { sysBuf in
                AudioCaptureService.interleaveStereoInt16(
                    mic: micBuf.baseAddress!,
                    micCount: mic.count,
                    sys: sysBuf.baseAddress!,
                    sysCount: sys.count
                )
            }
        }

        XCTAssertEqual(data.count, 12) // 3 frames * 2 channels * 2 bytes
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(samples, [100, 10, 200, 20, 300, 0])
    }

    func testInterleaveStereoInt16EqualLengths() {
        let mic: [Int16] = [1, 2]
        let sys: [Int16] = [3, 4]
        let data = mic.withUnsafeBufferPointer { micBuf in
            sys.withUnsafeBufferPointer { sysBuf in
                AudioCaptureService.interleaveStereoInt16(
                    mic: micBuf.baseAddress!,
                    micCount: mic.count,
                    sys: sysBuf.baseAddress!,
                    sysCount: sys.count
                )
            }
        }
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(samples, [1, 3, 2, 4])
    }

    func testSystemCallbackWatchdogRecoversSystemOnlyStall() {
        XCTAssertTrue(AudioCaptureService.shouldRecoverSystemCallbackStall(
            expectsSystemAudio: true,
            isSystemAudioActive: true,
            isRecoveryInProgress: false,
            callbackGap: 9,
            timeSinceWatchdogArmed: 9,
            callbackCount: 0,
            timeSinceLastRestart: .infinity
        ))
    }

    func testSystemCallbackWatchdogUsesPriorCallbacksBeforeStartupGrace() {
        XCTAssertTrue(AudioCaptureService.shouldRecoverSystemCallbackStall(
            expectsSystemAudio: true,
            isSystemAudioActive: true,
            isRecoveryInProgress: false,
            callbackGap: 7,
            timeSinceWatchdogArmed: 7,
            callbackCount: 11,
            timeSinceLastRestart: .infinity
        ))
    }

    func testSystemCallbackWatchdogHonorsRestartCooldown() {
        XCTAssertFalse(AudioCaptureService.shouldRecoverSystemCallbackStall(
            expectsSystemAudio: true,
            isSystemAudioActive: true,
            isRecoveryInProgress: false,
            callbackGap: 20,
            timeSinceWatchdogArmed: 20,
            callbackCount: 100,
            timeSinceLastRestart: 10
        ))
    }

    func testSystemCallbackWatchdogSuppressesConcurrentRecovery() {
        XCTAssertFalse(AudioCaptureService.shouldRecoverSystemCallbackStall(
            expectsSystemAudio: true,
            isSystemAudioActive: true,
            isRecoveryInProgress: true,
            callbackGap: 20,
            timeSinceWatchdogArmed: 20,
            callbackCount: 100,
            timeSinceLastRestart: .infinity
        ))
    }
    #endif
}

// MARK: - Dual-channel diarization fixture (synthetic, per the documented Deepgram
// streaming contract: per-channel messages tagged channel_index [n, 2], per-channel
// speaker numbering starting at 0 — provider IDs overlap across channels).

final class DualChannelDiarizationFixtureTests: XCTestCase {
    private typealias Word = DeepgramService.TranscriptUpdate.Word

    private func decodeWords(_ json: String) throws -> (words: [DeepgramResponse.Word], channelIndex: Int?) {
        let response = try JSONDecoder().decode(DeepgramResponse.self, from: json.data(using: .utf8)!)
        return (response.channel!.alternatives[0].words, response.channelIndex?.first)
    }

    private func micChannelMessage(speakers: [(String, Int, Double, Double)]) -> String {
        channelMessage(channel: 0, speakers: speakers)
    }

    private func systemChannelMessage(speakers: [(String, Int, Double, Double)]) -> String {
        channelMessage(channel: 1, speakers: speakers)
    }

    private func channelMessage(channel: Int, speakers: [(String, Int, Double, Double)]) -> String {
        let words = speakers.map { word, speaker, start, end in
            "{\"word\": \"\(word)\", \"start\": \(start), \"end\": \(end), \"confidence\": 0.95, \"speaker\": \(speaker), \"speaker_confidence\": 0.9}"
        }.joined(separator: ",")
        let transcript = speakers.map(\.0).joined(separator: " ")
        return """
        {
            "type": "Results",
            "channel": {"alternatives": [{"transcript": "\(transcript)", "confidence": 0.95, "words": [\(words)]}]},
            "channel_index": [\(channel), 2],
            "is_final": true,
            "speech_final": true,
            "start": 0.0,
            "duration": 4.0
        }
        """
    }

    /// Two mic speakers and two system speakers, all using provider IDs 0/1 —
    /// the mapping must keep the four people distinct and preserve mic diarization.
    func testOverlappingProviderIDsAcrossChannelsStayDistinct() throws {
        var identity = SpeakerIdentityState()
        identity.beginConnection(preservingIdentities: false)
        var segmentation = DeepgramService.SegmentationState()
        // Promotion evidence gates are exercised elsewhere; confirm identities here.
        segmentation.confirmedSpeakerIDs = [0, 1, 1000, 1001]

        let mic = try decodeWords(micChannelMessage(speakers: [
            ("shall", 0, 0.0, 0.4), ("we", 0, 0.4, 0.8), ("start", 0, 0.8, 1.2), ("now", 0, 1.2, 1.6),
            ("yes", 1, 2.0, 2.4), ("lets", 1, 2.4, 2.8), ("go", 1, 2.8, 3.2), ("ahead", 1, 3.2, 3.6),
        ]))
        let micSource = DeepgramService.responseSource(isMultichannel: true, streamChannel: mic.channelIndex, monoSource: .microphone)
        XCTAssertEqual(micSource, .microphone)
        let micWords = mic.words.map { word in
            Word(
                text: word.punctuatedWord ?? word.word,
                start: word.start,
                end: word.end,
                confidence: word.confidence,
                speaker: identity.appSpeakerID(source: micSource, providerID: word.speaker ?? 0),
                speakerConfidence: word.speakerConfidence
            )
        }
        XCTAssertEqual(Set(micWords.map(\.speaker)), [1000, 1001])

        let system = try decodeWords(systemChannelMessage(speakers: [
            ("hearing", 0, 0.5, 0.9), ("you", 0, 0.9, 1.3), ("clearly", 0, 1.3, 1.7), ("thanks", 0, 1.7, 2.1),
            ("same", 1, 2.5, 2.9), ("here", 1, 2.9, 3.3), ("all", 1, 3.3, 3.7), ("good", 1, 3.7, 4.1),
        ]))
        let systemSource = DeepgramService.responseSource(isMultichannel: true, streamChannel: system.channelIndex, monoSource: .microphone)
        XCTAssertEqual(systemSource, .system)
        let systemWords = system.words.map { word in
            Word(
                text: word.punctuatedWord ?? word.word,
                start: word.start,
                end: word.end,
                confidence: word.confidence,
                speaker: identity.appSpeakerID(source: systemSource, providerID: word.speaker ?? 0),
                speakerConfidence: word.speakerConfidence
            )
        }
        XCTAssertEqual(Set(systemWords.map(\.speaker)), [0, 1])

        // Segmentation keeps the two mic speakers as distinct segments with source.
        let micSegments = DeepgramService.segmentBySpeaker(
            words: micWords,
            isFinal: true,
            confidence: 0.95,
            channelIndex: 0,
            source: .microphone,
            state: &segmentation
        )
        XCTAssertEqual(micSegments.map(\.speaker), [1000, 1001])
        XCTAssertTrue(micSegments.allSatisfy { $0.source == .microphone })

        let systemSegments = DeepgramService.segmentBySpeaker(
            words: systemWords,
            isFinal: true,
            confidence: 0.95,
            channelIndex: 1,
            source: .system,
            state: &segmentation
        )
        XCTAssertEqual(systemSegments.map(\.speaker), [0, 1])
        XCTAssertTrue(systemSegments.allSatisfy { $0.source == .system })
    }

    func testMalformedChannelIndexMapsToUnknownSource() {
        XCTAssertEqual(
            DeepgramService.responseSource(isMultichannel: true, streamChannel: nil, monoSource: .microphone),
            .unknown
        )
        XCTAssertEqual(
            DeepgramService.responseSource(isMultichannel: true, streamChannel: 5, monoSource: .microphone),
            .unknown
        )
        XCTAssertEqual(
            DeepgramService.responseSource(isMultichannel: false, streamChannel: nil, monoSource: .system),
            .system
        )
    }

    /// A second mic speaker below the promotion evidence bar is folded into the
    /// current speaker instead of inventing a spurious room participant.
    func testUnpromotedSecondMicSpeakerFoldsIntoCurrent() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [1000]
        let words: [Word] = [
            Word(text: "we", start: 0.0, end: 0.3, confidence: 0.9, speaker: 1000, speakerConfidence: 0.9),
            Word(text: "should", start: 0.3, end: 0.6, confidence: 0.9, speaker: 1000, speakerConfidence: 0.9),
            Word(text: "ship", start: 0.6, end: 0.9, confidence: 0.9, speaker: 1000, speakerConfidence: 0.9),
            Word(text: "friday", start: 0.9, end: 1.2, confidence: 0.9, speaker: 1000, speakerConfidence: 0.9),
            Word(text: "yes", start: 1.3, end: 1.5, confidence: 0.9, speaker: 1001, speakerConfidence: 0.9),
        ]
        let segments = DeepgramService.segmentBySpeaker(
            words: words,
            isFinal: true,
            confidence: 0.9,
            channelIndex: 0,
            source: .microphone,
            state: &state
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speaker, 1000)
        XCTAssertFalse(state.confirmedSpeakerIDs.contains(1001))
    }
}

// MARK: - Symmetric mic gating once several mic speakers exist

final class MicPrimaryGatingTests: XCTestCase {
    private typealias Word = DeepgramService.TranscriptUpdate.Word

    private func word(_ text: String, speaker: Int, start: Double, confidence: Double?) -> Word {
        Word(text: text, start: start, end: start + 0.3, confidence: 0.9, speaker: speaker, speakerConfidence: confidence)
    }

    /// Sole-mic meetings keep the historical exemption: low-confidence switches back
    /// to the primary mic identity still succeed (shipped single-user behaviour).
    func testSwitchToPrimaryMicBypassesConfidenceWhileSoleMicSpeaker() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [0, 1000]
        let words = (0..<4).map { word("sys\($0)", speaker: 0, start: Double($0) * 0.4, confidence: 0.9) }
            + (0..<4).map { word("mic\($0)", speaker: 1000, start: 2.0 + Double($0) * 0.4, confidence: 0.2) }
        let segments = DeepgramService.segmentBySpeaker(
            words: words, isFinal: true, confidence: 0.9, source: .microphone, state: &state
        )
        XCTAssertEqual(segments.map(\.speaker), [0, 1000])
    }

    /// Once a second mic speaker is confirmed, switches back to 1000 must pass the
    /// same confidence gate as everyone else — borderline diarizer words no longer
    /// preferentially flip to the primary speaker.
    func testSwitchToPrimaryMicNeedsConfidenceOnceSecondMicSpeakerConfirmed() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [1000, 1001]
        let words = (0..<4).map { word("a\($0)", speaker: 1001, start: Double($0) * 0.4, confidence: 0.9) }
            + (0..<4).map { word("b\($0)", speaker: 1000, start: 2.0 + Double($0) * 0.4, confidence: 0.2) }
        let segments = DeepgramService.segmentBySpeaker(
            words: words, isFinal: true, confidence: 0.9, source: .microphone, state: &state
        )
        // The low-confidence run stays folded into the current speaker's segment.
        XCTAssertEqual(segments.map(\.speaker), [1001])

        // A confident switch back to 1000 still goes through.
        var confidentState = DeepgramService.SegmentationState()
        confidentState.confirmedSpeakerIDs = [1000, 1001]
        let confidentWords = (0..<4).map { word("a\($0)", speaker: 1001, start: Double($0) * 0.4, confidence: 0.9) }
            + (0..<4).map { word("b\($0)", speaker: 1000, start: 2.0 + Double($0) * 0.4, confidence: 0.9) }
        let confidentSegments = DeepgramService.segmentBySpeaker(
            words: confidentWords, isFinal: true, confidence: 0.9, source: .microphone, state: &confidentState
        )
        XCTAssertEqual(confidentSegments.map(\.speaker), [1001, 1000])
    }
}

final class FirstWordSpeakerGatingTests: XCTestCase {
    private typealias Word = DeepgramService.TranscriptUpdate.Word

    private func word(
        _ text: String,
        speaker: Int,
        start: Double,
        end: Double? = nil,
        confidence: Double = 0.9
    ) -> Word {
        Word(
            text: text,
            start: start,
            end: end ?? (start + 0.3),
            confidence: confidence,
            speaker: speaker,
            speakerConfidence: confidence
        )
    }

    func testFirstWordUnconfirmedSpeakerFoldsIntoLastCommitted() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [1000]
        state.lastCommittedSpeakerBySource[.microphone] = 1000

        // A new response that opens on unconfirmed 1001 with too little evidence.
        let words = (0..<3).map { word("x\($0)", speaker: 1001, start: Double($0) * 0.3) }
        let segments = DeepgramService.segmentBySpeaker(
            words: words,
            isFinal: true,
            confidence: 0.9,
            source: .microphone,
            state: &state
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speaker, 1000)
        XCTAssertFalse(state.confirmedSpeakerIDs.contains(1001))
        XCTAssertEqual(state.lastCommittedSpeakerBySource[.microphone], 1000)
    }

    func testFirstWordUnconfirmedSpeakerPromotesAfterEvidenceAcrossResponses() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [1000]
        state.lastCommittedSpeakerBySource[.microphone] = 1000

        // First response: 5 words from 1001 (~1.5s) — under standard promotion bar.
        let first = (0..<5).map { word("a\($0)", speaker: 1001, start: Double($0) * 0.35) }
        _ = DeepgramService.segmentBySpeaker(
            words: first, isFinal: true, confidence: 0.9, source: .microphone, state: &state
        )
        XCTAssertFalse(state.confirmedSpeakerIDs.contains(1001))

        // Second response continues accruing pending evidence until promotion.
        let second = (0..<5).map { word("b\($0)", speaker: 1001, start: 2.0 + Double($0) * 0.35) }
        let segments = DeepgramService.segmentBySpeaker(
            words: second, isFinal: true, confidence: 0.9, source: .microphone, state: &state
        )
        XCTAssertTrue(state.confirmedSpeakerIDs.contains(1001))
        XCTAssertEqual(segments.last?.speaker, 1001)
    }

    func testStrictPolicyRequiresMoreEvidenceForAdditionalMicSpeaker() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [1000]
        state.lastCommittedSpeakerBySource[.microphone] = 1000
        state.micSpeakerPromotionPolicy = .strict

        // 8 words / ~2.4s / high confidence — enough for standard, not for strict.
        let words = (0..<8).map { word("c\($0)", speaker: 1001, start: Double($0) * 0.3) }
        let segments = DeepgramService.segmentBySpeaker(
            words: words, isFinal: true, confidence: 0.9, source: .microphone, state: &state
        )
        XCTAssertEqual(segments.map(\.speaker), [1000])
        XCTAssertFalse(state.confirmedSpeakerIDs.contains(1001))
    }

    func testStrictPolicyLeavesSystemSpeakersOnStandardThresholds() {
        var state = DeepgramService.SegmentationState()
        state.confirmedSpeakerIDs = [0]
        state.lastCommittedSpeakerBySource[.system] = 0
        state.micSpeakerPromotionPolicy = .strict

        // 8 words / ~2.4s from a new remote speaker: enough for standard promotion.
        let words = (0..<8).map { word("r\($0)", speaker: 1, start: Double($0) * 0.3) }
        let segments = DeepgramService.segmentBySpeaker(
            words: words, isFinal: true, confidence: 0.9, source: .system, state: &state
        )
        XCTAssertEqual(segments.map(\.speaker), [1])
        XCTAssertTrue(state.confirmedSpeakerIDs.contains(1))
    }

    func testImplicitSelfPolicyTable() {
        XCTAssertTrue(
            ImplicitSelfPolicy.allowed(micSpeakerCount: 1, hasDualSourceOrLegacy: true, environment: .unknown)
        )
        XCTAssertFalse(
            ImplicitSelfPolicy.allowed(micSpeakerCount: 2, hasDualSourceOrLegacy: true, environment: .unknown)
        )
        XCTAssertTrue(
            ImplicitSelfPolicy.allowed(micSpeakerCount: 2, hasDualSourceOrLegacy: true, environment: .remoteLikely)
        )
        XCTAssertFalse(
            ImplicitSelfPolicy.allowed(micSpeakerCount: 2, hasDualSourceOrLegacy: true, environment: .inRoomLikely)
        )
        XCTAssertFalse(
            ImplicitSelfPolicy.allowed(micSpeakerCount: 1, hasDualSourceOrLegacy: false, environment: .remoteLikely)
        )
    }
}
