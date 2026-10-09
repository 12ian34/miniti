import XCTest
import FluidAudio
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class OnDeviceTranscriptionTests: XCTestCase {

    // MARK: - Helpers

    private func token(_ piece: String, at start: Double, duration: Double = 0.08) -> TokenTiming {
        TokenTiming(token: piece, tokenId: 0, startTime: start, endTime: start + duration, confidence: 1)
    }

    private func texts(_ event: LocalUtteranceAssembler.Event) -> [String] { event.words.map(\.text) }

    // MARK: - Language tiers

    func testEveryMinitiLanguageHasATier() {
        for language in TranscriptionLanguage.allCases {
            _ = OnDeviceTranscriptionSupport.tier(for: language)
        }
        XCTAssertEqual(OnDeviceTranscriptionSupport.tier(forCode: "en"), .tested)
        XCTAssertEqual(OnDeviceTranscriptionSupport.tier(forCode: "pt"), .tested)
        XCTAssertEqual(OnDeviceTranscriptionSupport.tier(forCode: "nl"), .experimental)
        XCTAssertEqual(OnDeviceTranscriptionSupport.tier(forCode: "ru"), .experimental)
        XCTAssertEqual(OnDeviceTranscriptionSupport.tier(forCode: "el"), .cloudOnly)
        XCTAssertEqual(OnDeviceTranscriptionSupport.tier(forCode: "pl"), .cloudOnly)
        XCTAssertEqual(OnDeviceTranscriptionSupport.tier(forCode: "sv"), .cloudOnly)
        XCTAssertEqual(OnDeviceTranscriptionSupport.tier(forCode: "xx"), .cloudOnly)
    }

    func testCloudOnlyLanguagesHaveNoModelLanguageAndLatinFamilyIsPruned() {
        XCTAssertNil(OnDeviceTranscriptionSupport.nemotronLanguage(forCode: "el"))
        XCTAssertNil(OnDeviceTranscriptionSupport.nemotronLanguage(forCode: "sv"))
        XCTAssertEqual(OnDeviceTranscriptionSupport.nemotronLanguage(forCode: "en"), "en-US")
        XCTAssertEqual(OnDeviceTranscriptionSupport.nemotronLanguage(forCode: "ru"), "ru-RU")
        for code in ["en", "es", "fr", "de", "pt", "it"] {
            XCTAssertEqual(OnDeviceTranscriptionSupport.family(forCode: code), "latin", code)
        }
        for code in ["nl", "ru"] {
            XCTAssertEqual(OnDeviceTranscriptionSupport.family(forCode: code), "multilingual", code)
        }
        XCTAssertEqual(OnDeviceTranscriptionSupport.approximateDownloadMB(family: "latin"), 590)
        XCTAssertEqual(OnDeviceTranscriptionSupport.approximateDownloadMB(family: "multilingual"), 640)
    }

    func testSettingCopyNamesEveryLanguageOnce() {
        let copy = OnDeviceTranscriptionCopy.description
        for language in TranscriptionLanguage.allCases {
            XCTAssertTrue(copy.contains(language.englishName), "copy must mention \(language.englishName)")
        }
        XCTAssertTrue(copy.contains("590 MB"))
        XCTAssertTrue(copy.contains("Greek"))
        XCTAssertFalse(copy.contains("Miniti"), "product name stays lowercase")
        XCTAssertEqual(OnDeviceTranscriptionCopy.joined(["A"]), "A")
        XCTAssertEqual(OnDeviceTranscriptionCopy.joined(["A", "B"]), "A and B")
        XCTAssertEqual(OnDeviceTranscriptionCopy.joined(["A", "B", "C"]), "A, B and C")
    }

    // MARK: - Utterance assembly

    func testTokensGroupIntoWordsOnTheBoundaryMarker() {
        var assembler = LocalUtteranceAssembler()
        let events = assembler.consume(tokens: [
            token("▁un", at: 0.0), token("fortu", at: 0.08), token("nately", at: 0.16),
            token("▁yes", at: 0.4),
        ], horizon: 1.12)
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].isFinal)
        XCTAssertEqual(texts(events[0]), ["unfortunately", "yes"])
        XCTAssertEqual(events[0].words[0].start, 0.0)
        XCTAssertEqual(events[0].words[0].end, 0.24, accuracy: 1e-9)
    }

    func testAWordSplitAcrossChunksIsNotCutByTheSilenceRule() {
        var assembler = LocalUtteranceAssembler()
        // Chunk 1 ends mid-word; the decoded horizon is right at the token, so no silence.
        _ = assembler.consume(tokens: [token("▁hello", at: 0.5), token("▁unfortu", at: 1.0)], horizon: 1.12)
        // Chunk 2 continues the word.
        let events = assembler.consume(tokens: [token("nately", at: 1.2)], horizon: 2.24)
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].isFinal)
        XCTAssertEqual(texts(events[0]), ["hello", "unfortunately"])
    }

    func testSentencePunctuationEndsAnUtterance() {
        var assembler = LocalUtteranceAssembler()
        let events = assembler.consume(tokens: [
            token("▁That", at: 0.0), token("'s", at: 0.08), token("▁fine", at: 0.3), token(".", at: 0.4),
        ], horizon: 1.12)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isFinal)
        XCTAssertEqual(texts(events[0]), ["That's", "fine."])
        XCTAssertEqual(events[0].words[0].end, 0.16, accuracy: 1e-9)
        XCTAssertEqual(events[0].words[1].end, 0.48, accuracy: 1e-9)
        XCTAssertTrue(assembler.pendingWords.isEmpty)
        XCTAssertTrue(LocalUtteranceAssembler.endsSentence("done.\""))
        XCTAssertTrue(LocalUtteranceAssembler.endsSentence("why?"))
        XCTAssertFalse(LocalUtteranceAssembler.endsSentence("Dr"))
        XCTAssertFalse(LocalUtteranceAssembler.endsSentence(""))
    }

    func testSilenceAtTheDecodedHorizonEndsAnUtterance() {
        var assembler = LocalUtteranceAssembler()
        let interim = assembler.consume(tokens: [token("▁okay", at: 0.5), token("▁so", at: 0.8)], horizon: 1.12)
        XCTAssertEqual(interim.map(\.isFinal), [false])
        // An empty chunk: nothing decoded, horizon moves 1.12 s past the last token.
        let final = assembler.consume(tokens: [], horizon: 2.24)
        XCTAssertEqual(final.count, 1)
        XCTAssertTrue(final[0].isFinal)
        XCTAssertEqual(texts(final[0]), ["okay", "so"])
        // Nothing pending: another quiet chunk emits nothing.
        XCTAssertEqual(assembler.consume(tokens: [], horizon: 3.36), [])
    }

    func testUnchangedChunkDoesNotRepeatTheInterim() {
        var assembler = LocalUtteranceAssembler()
        XCTAssertEqual(assembler.consume(tokens: [token("▁one", at: 0.9)], horizon: 1.12).count, 1)
        // Horizon advances but by less than the silence gap and with no new tokens.
        XCTAssertEqual(assembler.consume(tokens: [], horizon: 1.5), [])
    }

    func testLongUtteranceIsForcedFinalAtAWordBoundary() {
        var assembler = LocalUtteranceAssembler()
        var tokens: [TokenTiming] = []
        for index in 0..<40 { tokens.append(token("▁w\(index)", at: Double(index) * 0.35)) }
        // 40 words over 13.65 s with no punctuation and no gaps; last word is partial.
        let events = assembler.consume(tokens: tokens, horizon: 14.0)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events[0].isFinal)
        XCTAssertEqual(events[0].words.count, 39)
        XCTAssertFalse(events[1].isFinal)
        XCTAssertEqual(texts(events[1]), ["w39"])
    }

    func testSentenceEndFollowedByANewWordInTheSameChunkSplitsThere() {
        var assembler = LocalUtteranceAssembler()
        let events = assembler.consume(tokens: [
            token("▁Fine", at: 0.0), token(".", at: 0.08), token("▁And", at: 0.5), token("▁then", at: 0.7),
        ], horizon: 1.12)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events[0].isFinal)
        XCTAssertEqual(texts(events[0]), ["Fine."])
        XCTAssertFalse(events[1].isFinal)
        XCTAssertEqual(texts(events[1]), ["And", "then"])
        // The next chunk only sees the new sentence.
        let later = assembler.consume(tokens: [token("▁yes", at: 1.3), token(".", at: 1.38)], horizon: 2.24)
        XCTAssertEqual(later.count, 1)
        XCTAssertEqual(texts(later[0]), ["And", "then", "yes."])
    }

    func testFlushEmitsWhateverIsPendingAsAFinal() {
        var assembler = LocalUtteranceAssembler()
        _ = assembler.consume(tokens: [token("▁bye", at: 0.1), token("▁the", at: 0.3), token("n", at: 0.38)], horizon: 1.12)
        let events = assembler.flush()
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isFinal)
        XCTAssertEqual(texts(events[0]), ["bye", "then"])
        XCTAssertEqual(assembler.flush(), [])
    }

    func testStandaloneBoundaryTokenAndEmptyPiecesAreIgnored() {
        var assembler = LocalUtteranceAssembler()
        let events = assembler.consume(tokens: [
            token("▁yes", at: 0.0), token(".", at: 0.08), token("▁", at: 0.16),
        ], horizon: 1.12)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isFinal)
        XCTAssertEqual(texts(events[0]), ["yes."])
        XCTAssertEqual(assembler.consume(tokens: [token("", at: 0.3)], horizon: 1.12), [])
    }

    func testPlainWordStripsSurroundingPunctuation() {
        XCTAssertEqual(LocalUtteranceAssembler.plainWord("fine."), "fine")
        XCTAssertEqual(LocalUtteranceAssembler.plainWord("\"quoted,\""), "quoted")
        XCTAssertEqual(LocalUtteranceAssembler.plainWord("..."), "...")
        XCTAssertEqual(LocalUtteranceAssembler.plainWord("it's"), "it's")
    }

    // MARK: - Through the Deepgram processing path

    private func event(_ words: [(String, Double, Double)], source: TranscriptSource, isFinal: Bool) -> OnDeviceTranscriptionService.Session.Event {
        .init(
            source: source,
            words: words.map { .init(text: $0.0, start: $0.1, end: $0.2) },
            isFinal: isFinal
        )
    }

    func testLocalResponseCarriesChannelIndexBySourceInDualCapture() {
        let mic = DeepgramService.makeLocalResponse(event([("Hi.", 0.1, 0.3)], source: .microphone, isFinal: true), isMultichannel: true)
        XCTAssertEqual(mic.channelIndex, [DeepgramService.micChannelIndex, 2])
        XCTAssertEqual(mic.isFinal, true)
        XCTAssertEqual(mic.speechFinal, true)
        XCTAssertEqual(mic.channel?.alternatives.first?.transcript, "Hi.")
        XCTAssertEqual(mic.channel?.alternatives.first?.words.first?.word, "Hi")
        XCTAssertEqual(mic.channel?.alternatives.first?.words.first?.punctuatedWord, "Hi.")
        XCTAssertNil(mic.channel?.alternatives.first?.words.first?.speaker)

        let system = DeepgramService.makeLocalResponse(event([("Yes", 2.0, 2.2)], source: .system, isFinal: false), isMultichannel: true)
        XCTAssertEqual(system.channelIndex, [DeepgramService.systemChannelIndex, 2])
        XCTAssertEqual(system.isFinal, false)

        let mono = DeepgramService.makeLocalResponse(event([("Yes", 2.0, 2.2)], source: .microphone, isFinal: true), isMultichannel: false)
        XCTAssertNil(mono.channelIndex)
    }

    func testLocalFinalWithoutATimelineLandsOnTheFirstMicSpeaker() throws {
        let response = DeepgramService.makeLocalResponse(
            event([("We", 0.0, 0.2), ("start.", 0.2, 0.5)], source: .microphone, isFinal: true),
            isMultichannel: true
        )
        let result = DeepgramService.processTranscriptResponse(
            response,
            isMultichannel: true,
            monoSource: .microphone,
            segmentationState: .init(),
            identityState: SpeakerIdentityState(),
            speakerTimeline: nil
        )
        guard case .transcript(let parsed) = result else { return XCTFail("expected a transcript") }
        XCTAssertTrue(parsed.update.isFinal)
        XCTAssertEqual(parsed.update.source, .microphone)
        XCTAssertEqual(parsed.update.text, "We start.")
        XCTAssertEqual(Set(parsed.update.words.map(\.speaker)), [DeepgramService.micSpeakerID])
        XCTAssertEqual(parsed.segments.count, 1)
        XCTAssertEqual(parsed.segments.first?.speaker, DeepgramService.micSpeakerID)
        XCTAssertEqual(parsed.segments.first?.channelIndex, DeepgramService.micChannelIndex)
    }

    func testLocalWordsTakeTheirSpeakerFromTheOnDeviceTimeline() throws {
        // Two mature slots on the system source: slot 0 for the first second, slot 1 after.
        let timeline = OnDeviceSpeakerTimeline(sources: [.system])
        let warm = Int(OnDeviceSpeakerTimeline.slotMaturitySeconds / OnDeviceSpeakerTimeline.frameSeconds)
        func probabilities(_ slot: Int, frames: Int) -> [Float] {
            var out: [Float] = []
            for _ in 0..<frames { for k in 0..<8 { out.append(slot == k ? 0.9 : 0.05) } }
            return out
        }
        for slot in [0, 1] {
            timeline.noteAudioFed(source: .system, sampleCount: warm * 160)
            timeline.append(source: .system, probabilities: probabilities(slot, frames: warm), frameCount: warm, numSpeakers: 8)
        }
        timeline.noteAudioFed(source: .system, sampleCount: 160)
        timeline.markSocketStart()
        timeline.append(source: .system, probabilities: probabilities(0, frames: 100), frameCount: 100, numSpeakers: 8)
        timeline.append(source: .system, probabilities: probabilities(1, frames: 100), frameCount: 100, numSpeakers: 8)

        let response = DeepgramService.makeLocalResponse(
            event([("First", 0.1, 0.5), ("second", 1.2, 1.6)], source: .system, isFinal: true),
            isMultichannel: true
        )
        var identity = SpeakerIdentityState()
        identity.setStableProviderSources([.system])
        let result = DeepgramService.processTranscriptResponse(
            response,
            isMultichannel: true,
            monoSource: .microphone,
            segmentationState: .init(onDeviceSources: [.system]),
            identityState: identity,
            speakerTimeline: timeline
        )
        guard case .transcript(let parsed) = result else { return XCTFail("expected a transcript") }
        XCTAssertEqual(parsed.update.words.map(\.speaker), [0, 1])
        XCTAssertNotNil(parsed.onDeviceSummary)
    }

    func testSpeechStartedJSONStillShortCircuitsAndBadJSONWarns() {
        let state = DeepgramService.SegmentationState()
        let speech = DeepgramService.processTranscriptJSONForTesting("{\"type\":\"SpeechStarted\"}", segmentationState: state)
        if case .speechStarted = speech {} else { XCTFail("expected speechStarted") }
        let bad = DeepgramService.processTranscriptJSONForTesting("{not json", segmentationState: state)
        if case .warning = bad {} else { XCTFail("expected warning") }
    }

    // MARK: - Service gating

    @MainActor
    func testServiceRefusesSessionsUntilReadyAndTracksDownloadDirectory() async {
        let service = OnDeviceTranscriptionService()
        XCTAssertFalse(service.isReady(forLanguageCode: "en"))
        XCTAssertFalse(service.isReady(forLanguageCode: "el"))
        let session = await service.beginSession(sources: [.microphone], languageCode: "en", vocabulary: [])
        XCTAssertNil(session)
        XCTAssertNil(service.activeSession)
        XCTAssertTrue(OnDeviceTranscriptionService.modelsDirectory.path.contains("FluidAudio/Models/nemotron-multilingual"))
        XCTAssertEqual(OnDeviceTranscriptionService.directorySize(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")), 0)
        if OnDeviceTranscriptionService.isHardwareSupported {
            XCTAssertEqual(service.status, .idle)
            XCTAssertTrue(service.statusDescription.contains("Off"))
        } else {
            XCTAssertEqual(service.status, .unsupported)
        }
    }

    // MARK: - Acknowledgements

    func testASRModelNoticeIsListedAndCarriesTheRequiredTerms() throws {
        let entry = try XCTUnwrap(Acknowledgements.entries.first { $0.id == "nemotron-asr" })
        let text = try XCTUnwrap(Acknowledgements.text(for: entry))
        XCTAssertTrue(text.contains("Nemotron-3.5-ASR"))
        XCTAssertTrue(text.contains("OpenMDW License Agreement, version 1.1"))
        XCTAssertTrue(text.contains("FluidInference"))
    }
}

/// Opt-in: runs the real Core ML recogniser on a wav through the service, a session, and the
/// assembler, exactly as a mic-only recording would. Downloads the latin model (about 590 MB)
/// into the test host's container on first run.
///   MINITI_NEMOTRON_ASR_E2E=<16 kHz mono wav> xcodebuild test … -only-testing:MinitiTests/OnDeviceTranscriptionEndToEndTests
final class OnDeviceTranscriptionEndToEndTests: XCTestCase {
    @MainActor
    func testRealModelStreamsWavThroughSessionAndAssembler() async throws {
        guard let path = ProcessInfo.processInfo.environment["MINITI_NEMOTRON_ASR_E2E"], !path.isEmpty else {
            throw XCTSkip("Set MINITI_NEMOTRON_ASR_E2E=<path to 16 kHz mono wav> to run")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(data.count, 44)
        let pcm = data.subdata(in: 44..<data.count)  // canonical 44-byte RIFF header from ffmpeg
        let audioSeconds = Double(pcm.count / 2) / 16_000

        let service = OnDeviceTranscriptionService()
        XCTAssertTrue(OnDeviceTranscriptionService.isHardwareSupported)
        service.prepare(languageCode: "en")
        let deadline = Date().addingTimeInterval(900)
        while !service.isReady(forLanguageCode: "en"), Date() < deadline {
            if case .failed(let message) = service.status { XCTFail("model load failed: \(message)"); return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTAssertTrue(service.isReady(forLanguageCode: "en"), "model did not become ready in time: \(service.statusDescription)")

        guard let session = await service.beginSession(sources: [.microphone], languageCode: "en", vocabulary: ["Miniti"]) else {
            return XCTFail("no session")
        }
        final class Collector: @unchecked Sendable {
            let lock = NSLock()
            var events: [OnDeviceTranscriptionService.Session.Event] = []
            func add(_ event: OnDeviceTranscriptionService.Session.Event) { lock.lock(); events.append(event); lock.unlock() }
            var snapshot: [OnDeviceTranscriptionService.Session.Event] { lock.lock(); defer { lock.unlock() }; return events }
        }
        let collector = Collector()
        session.activate { collector.add($0) }

        let packet = 3_200  // 100 ms of 16 kHz PCM16, the app's send granularity
        var offset = 0
        let started = Date()
        while offset < pcm.count {
            let end = min(offset + packet, pcm.count)
            session.ingest(pcm.subdata(in: offset..<end), multichannel: false, monoSource: .microphone)
            offset = end
        }
        await session.finish()
        service.noteSessionEnded()
        let wall = Date().timeIntervalSince(started)

        let events = collector.snapshot
        let finals = events.filter(\.isFinal)
        let interims = events.filter { !$0.isFinal }
        XCTAssertFalse(finals.isEmpty, "no final utterances")
        XCTAssertFalse(interims.isEmpty, "no interim updates")
        let words = finals.flatMap(\.words)
        XCTAssertGreaterThan(words.count, 20, "too few words for \(audioSeconds)s of speech")
        for pair in zip(words, words.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.start, pair.1.start + 0.001, "word timings must not go backwards")
        }
        XCTAssertLessThanOrEqual(words.last?.end ?? 0, audioSeconds + 1.5)
        XCTAssertTrue(session.failedSources.isEmpty, "a source failed: \(session.summary)")
        let transcript = finals.map { $0.words.map(\.text).joined(separator: " ") }.joined(separator: " | ")
        print("E2E on-device transcription: \(audioSeconds)s audio in \(String(format: "%.1f", wall))s wall, finals=\(finals.count), interims=\(interims.count), words=\(words.count)\n\(transcript)")
    }
}

@MainActor
final class PrivateModeTests: XCTestCase {
    private static let keys = [
        "privateMode", AppState.privateModeRestoreKey,
        "onDeviceTranscription", "onDeviceSpeakerSeparation", "onDeviceTranscriptionCloudFallback",
        "salesInsightsEnabled", "templateInsightsEnabled", "playbookInsightsEnabled",
        "autoInferSpeakerNames", "notifyOnSalesDetection", "jevClassifierEnabled",
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        for key in Self.keys {
            if let value = UserDefaults.standard.object(forKey: key) { saved[key] = value }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in Self.keys {
            if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    func testTurningPrivateModeOnFlipsEverySettingAndOffRestoresThem() throws {
        try XCTSkipUnless(OnDeviceTranscriptionService.isHardwareSupported, "private mode needs Apple silicon")
        #if os(macOS)
        let state = AppState()
        state.salesInsightsEnabled = true
        state.templateInsightsEnabled = true
        state.autoInferSpeakerNames = true
        state.notifyOnSalesDetection = true
        state.jevClassifierEnabled = true
        state.onDeviceTranscriptionCloudFallback = true
        state.insightsMode = .meddpicc
        XCTAssertTrue(state.privateModeAvailable)

        state.setPrivateMode(true)
        XCTAssertTrue(state.privateModeEnabled)
        XCTAssertTrue(state.onDeviceTranscriptionEnabled)
        XCTAssertTrue(state.onDeviceSpeakerSeparationEnabled)
        XCTAssertFalse(state.onDeviceTranscriptionCloudFallback)
        XCTAssertFalse(state.salesInsightsEnabled)
        XCTAssertFalse(state.templateInsightsEnabled)
        XCTAssertFalse(state.playbookInsightsEnabled)
        XCTAssertFalse(state.autoInferSpeakerNames)
        XCTAssertFalse(state.notifyOnSalesDetection)
        XCTAssertFalse(state.jevClassifierEnabled)
        XCTAssertEqual(state.insightsMode, .standard)
        XCTAssertNil(state.rememberedSpecialistMode)
        XCTAssertFalse(state.canInvestigateCurrentConversation)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: AppState.privateModeRestoreKey))

        // Idempotent: a second "on" must not overwrite the snapshot with the private values.
        state.setPrivateMode(true)

        state.setPrivateMode(false)
        XCTAssertFalse(state.privateModeEnabled)
        XCTAssertFalse(state.onDeviceTranscriptionEnabled)
        XCTAssertFalse(state.onDeviceSpeakerSeparationEnabled)
        XCTAssertTrue(state.onDeviceTranscriptionCloudFallback)
        XCTAssertTrue(state.salesInsightsEnabled)
        XCTAssertTrue(state.templateInsightsEnabled)
        XCTAssertTrue(state.autoInferSpeakerNames)
        XCTAssertTrue(state.notifyOnSalesDetection)
        XCTAssertTrue(state.jevClassifierEnabled)
        XCTAssertNil(UserDefaults.standard.data(forKey: AppState.privateModeRestoreKey))
        state.onDeviceTranscription.unload()
        state.onDeviceDiarization.unload()
        #endif
    }

    func testPrivateModeRefusesCloudOnlyLanguagesAndIgnoresTheManagedLimit() throws {
        try XCTSkipUnless(OnDeviceTranscriptionService.isHardwareSupported, "private mode needs Apple silicon")
        #if os(macOS)
        let state = AppState()
        state.setPrivateMode(true)
        state.meetingLanguage = "el"
        XCTAssertTrue(state.onDeviceTranscriptionBlocksStart)
        XCTAssertTrue(state.onDeviceTranscriptionRefusalMessage.contains("Greek"))
        state.meetingLanguage = "en"
        XCTAssertFalse(state.onDeviceTranscriptionRefusalMessage.contains("Greek"))
        state.appMode = .managed
        XCTAssertTrue(state.canStartRecording || state.isDeviceDisabled)
        state.setPrivateMode(false)
        state.onDeviceTranscription.unload()
        state.onDeviceDiarization.unload()
        #endif
    }

    func testPrivateModeCopyNamesTheCloudOnlyLanguages() {
        XCTAssertTrue(PrivateModeCopy.languagesNote.contains("Greek"))
        XCTAssertTrue(PrivateModeCopy.languagesNote.contains("Swedish"))
        XCTAssertFalse(PrivateModeCopy.description.contains("—"))
    }
}
