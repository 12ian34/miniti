import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class OnDeviceDiarizationTests: XCTestCase {

    // MARK: - Helpers

    /// Frames of `[frameCount * 8]` probabilities where `slot` is active (0.9) and the rest 0.05;
    /// slot nil means silence.
    private func probabilities(_ slots: [Int?]) -> [Float] {
        var out: [Float] = []
        for slot in slots {
            for k in 0..<8 { out.append(slot == k ? 0.9 : 0.05) }
        }
        return out
    }

    /// Timeline whose slots are already mature (3 s of prior speech each), then the given frames
    /// on the current socket.
    private func timeline(mic slots: [Int?]) -> OnDeviceSpeakerTimeline {
        let t = OnDeviceSpeakerTimeline(sources: [.microphone])
        let used = Set(slots.compactMap { $0 })
        let warm = Int(OnDeviceSpeakerTimeline.slotMaturitySeconds / OnDeviceSpeakerTimeline.frameSeconds)
        for slot in used.sorted() {
            t.noteAudioFed(source: .microphone, sampleCount: warm * 160)
            t.append(source: .microphone, probabilities: probabilities(Array(repeating: slot, count: warm)), frameCount: warm, numSpeakers: 8)
        }
        t.noteAudioFed(source: .microphone, sampleCount: 160)
        t.markSocketStart()
        t.append(source: .microphone, probabilities: probabilities(slots), frameCount: slots.count, numSpeakers: 8)
        return t
    }

    func testImmatureSlotNeverTakesAWordUntilItHasThreeSecondsOfSpeech() {
        let t = OnDeviceSpeakerTimeline(sources: [.microphone])
        let warm = Int(OnDeviceSpeakerTimeline.slotMaturitySeconds / OnDeviceSpeakerTimeline.frameSeconds)
        t.noteAudioFed(source: .microphone, sampleCount: 160)
        t.markSocketStart()
        // 3 s of speaker 0 (mature), then a 1 s burst of slot 3 (churn), then speaker 0 again
        t.append(source: .microphone, probabilities: probabilities(Array(repeating: 0, count: warm)), frameCount: warm, numSpeakers: 8)
        t.append(source: .microphone, probabilities: probabilities(Array(repeating: 3, count: 100)), frameCount: 100, numSpeakers: 8)
        t.append(source: .microphone, probabilities: probabilities(Array(repeating: 0, count: 100)), frameCount: 100, numSpeakers: 8)
        XCTAssertEqual(t.matureSlots(source: .microphone), [0])
        // A word inside the burst stays with the mature speaker, borrowed
        let burst = t.lookup(source: .microphone, socketStart: 3.2, socketEnd: 3.6)
        XCTAssertEqual(burst?.providerSpeaker, 0)
        XCTAssertEqual(burst?.confidence, OnDeviceSpeakerTimeline.fallbackConfidence)
        // Slot 3 keeps talking for 2 more seconds: now mature, and later words go to it
        t.append(source: .microphone, probabilities: probabilities(Array(repeating: 3, count: 200)), frameCount: 200, numSpeakers: 8)
        XCTAssertEqual(t.matureSlots(source: .microphone), [0, 3])
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 5.5, socketEnd: 5.9)?.providerSpeaker, 3)
        // Earlier burst words still read as speaker 0 only if re-looked-up before maturity; a
        // re-lookup now sees slot 3 as mature, which is fine: finals are never re-labelled.
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 3.2, socketEnd: 3.6)?.providerSpeaker, 3)
    }

    // MARK: - Timeline lookup

    func testLookupMajoritySpeakerOverWord() {
        // 0.00–0.30 s speaker 0, 0.30–0.60 s speaker 1
        let t = timeline(mic: Array(repeating: 0, count: 30) + Array(repeating: 1, count: 30))
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 0.05, socketEnd: 0.25)?.providerSpeaker, 0)
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 0.35, socketEnd: 0.55)?.providerSpeaker, 1)
        // A word straddling the boundary goes to whoever dominates it, at the agreement share
        let straddle = t.lookup(source: .microphone, socketStart: 0.25, socketEnd: 0.45)
        XCTAssertEqual(straddle?.providerSpeaker, 1)
        XCTAssertEqual(straddle!.confidence, 0.75, accuracy: 0.001)
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 0.0, socketEnd: 0.3)?.confidence ?? 0, 1.0, accuracy: 0.001)
    }

    func testLookupHalfCoveredWordKeepsFullAgreementConfidence() {
        // 0.4 s diarized as speaker 2; a word spanning 0.3–0.5 s is half covered
        let t = timeline(mic: Array(repeating: 2, count: 40))
        let half = t.lookup(source: .microphone, socketStart: 0.3, socketEnd: 0.5)
        XCTAssertEqual(half?.providerSpeaker, 2)
        XCTAssertEqual(half?.confidence ?? 0, 1.0, accuracy: 0.001, "coverage must not discount confidence")
        // Under half covered: borrowed at the fallback confidence instead
        let mostlyPast = t.lookup(source: .microphone, socketStart: 0.35, socketEnd: 0.65)
        XCTAssertEqual(mostlyPast?.providerSpeaker, 2)
        XCTAssertEqual(mostlyPast?.confidence, OnDeviceSpeakerTimeline.fallbackConfidence)
    }

    // MARK: - Promotion of a second mic speaker from the on-device diarizer

    private func word(_ text: String, _ start: Double, speaker: Int, confidence: Double) -> DeepgramService.TranscriptUpdate.Word {
        DeepgramService.TranscriptUpdate.Word(text: text, start: start, end: start + 0.4, confidence: 0.95, speaker: speaker, speakerConfidence: confidence)
    }

    func testOnDeviceMicSpeakerPromotesUnderStrictPolicyButDeepgramOneDoesNot() {
        // Eight words of a second mic voice (1001) at confidence 0.9 after the primary spoke.
        var words = (0..<4).map { word("w\($0)", Double($0) * 0.5, speaker: DeepgramService.micSpeakerID, confidence: 0.9) }
        words += (0..<8).map { word("s\($0)", 2.0 + Double($0) * 0.5, speaker: DeepgramService.micSpeakerID + 1, confidence: 0.9) }

        var onDevice = DeepgramService.SegmentationState(micSpeakerPromotionPolicy: .strict, onDeviceSources: [.microphone])
        onDevice.confirmedSpeakerIDs = [DeepgramService.micSpeakerID]
        let promoted = DeepgramService.segmentBySpeaker(words: words, isFinal: true, confidence: 0.95, channelIndex: 0, source: .microphone, state: &onDevice)
        XCTAssertEqual(Set(promoted.map(\.speaker)), [DeepgramService.micSpeakerID, DeepgramService.micSpeakerID + 1], "on-device slots use the standard policy even in a remote-likely meeting")

        var deepgram = DeepgramService.SegmentationState(micSpeakerPromotionPolicy: .strict)
        deepgram.confirmedSpeakerIDs = [DeepgramService.micSpeakerID]
        let guarded = DeepgramService.segmentBySpeaker(words: words, isFinal: true, confidence: 0.95, channelIndex: 0, source: .microphone, state: &deepgram)
        XCTAssertEqual(Set(guarded.map(\.speaker)), [DeepgramService.micSpeakerID], "Deepgram's second mic id still needs the strict evidence")
    }

    func testLookupSilentWordBorrowsRecentSpeakerAtLowConfidence() {
        let t = timeline(mic: Array(repeating: 2, count: 20) + Array(repeating: nil, count: 50))
        let hit = t.lookup(source: .microphone, socketStart: 0.3, socketEnd: 0.5)
        XCTAssertEqual(hit?.providerSpeaker, 2)
        XCTAssertEqual(hit?.confidence, OnDeviceSpeakerTimeline.fallbackConfidence)
    }

    func testLookupBeyondHorizonBorrowsLastActiveSpeaker() {
        let t = timeline(mic: Array(repeating: 3, count: 10))
        // Word entirely after the 0.1 s of processed audio
        let hit = t.lookup(source: .microphone, socketStart: 0.5, socketEnd: 0.8)
        XCTAssertEqual(hit?.providerSpeaker, 3)
        XCTAssertEqual(hit?.confidence, OnDeviceSpeakerTimeline.fallbackConfidence)
    }

    func testLookupReturnsNilWhenNothingNearby() {
        let t = timeline(mic: Array(repeating: nil, count: 400))
        XCTAssertNil(t.lookup(source: .microphone, socketStart: 3.5, socketEnd: 3.8))
        XCTAssertNil(t.lookup(source: .system, socketStart: 0, socketEnd: 1))
        XCTAssertFalse(t.covers(.system))
    }

    func testSocketOriginIsTheStartOfTheFirstSentPacket() {
        let t = OnDeviceSpeakerTimeline(sources: [.microphone])
        // 3.2 s of audio fed and diarized (speaker 0) before the socket connected (dropped by Deepgram)
        t.noteAudioFed(source: .microphone, sampleCount: 51_200)
        t.append(source: .microphone, probabilities: probabilities(Array(repeating: 0, count: 320)), frameCount: 320, numSpeakers: 8)
        // The first packet Deepgram receives (100 ms) is ingested first, then the socket start is marked
        t.noteAudioFed(source: .microphone, sampleCount: 1_600)
        t.markSocketStart()
        // 3 s of speaker 1 on the socket, including that first packet, enough to mature the slot
        t.noteAudioFed(source: .microphone, sampleCount: 46_400)
        t.append(source: .microphone, probabilities: probabilities(Array(repeating: 1, count: 300)), frameCount: 300, numSpeakers: 8)
        XCTAssertEqual(t.fedSeconds(source: .microphone), 6.2, accuracy: 0.001)
        XCTAssertEqual(t.matureSlots(source: .microphone), [0, 1])
        // Socket 0.00–0.10 s is the first packet: speaker 1, not the pre-socket speaker 0
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 0.0, socketEnd: 0.1)?.providerSpeaker, 1)
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 0.1, socketEnd: 0.4)?.providerSpeaker, 1)
    }

    func testBorrowedWordsContinueTheLastDiarizedWordInTheResponse() {
        let d = { (s: Int, c: Double) in DeepgramService.ProviderSpeaker(speaker: s, confidence: c, borrowed: false) }
        let b = { (s: Int) in DeepgramService.ProviderSpeaker(speaker: s, confidence: OnDeviceSpeakerTimeline.fallbackConfidence, borrowed: true) }
        // Timeline last heard speaker 0, but this utterance's diarized words are speaker 1
        let out = DeepgramService.continueBorrowedSpeakers([d(1, 0.9), d(1, 1.0), b(0), b(0)])
        XCTAssertEqual(out.map(\.speaker), [1, 1, 1, 1])
        XCTAssertEqual(out.map(\.borrowed), [false, false, true, true])
        // Nothing diarized yet: lookups stand
        XCTAssertEqual(DeepgramService.continueBorrowedSpeakers([b(0), b(0)]).map(\.speaker), [0, 0])
        // Borrowed words before the first diarized word keep their own guess
        XCTAssertEqual(DeepgramService.continueBorrowedSpeakers([b(0), d(2, 0.8), b(5)]).map(\.speaker), [0, 2, 2])
    }

    func testAppendIgnoresMalformedInput() {
        let t = OnDeviceSpeakerTimeline(sources: [.microphone])
        t.append(source: .microphone, probabilities: [0.9], frameCount: 5, numSpeakers: 8)
        t.append(source: .system, probabilities: probabilities([0]), frameCount: 1, numSpeakers: 8)
        XCTAssertEqual(t.processedSeconds(source: .microphone), 0)
    }

    // MARK: - PCM split

    func testSplitPCM16DeinterleavesStereo() {
        var data = Data()
        for pair in [(Int16(16_384), Int16(-16_384)), (Int16(0), Int16(32_767))] {
            withUnsafeBytes(of: pair.0.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: pair.1.littleEndian) { data.append(contentsOf: $0) }
        }
        let split = OnDeviceDiarizationService.splitPCM16(data, multichannel: true, monoSource: .microphone)
        XCTAssertEqual(split[.microphone]!.count, 2)
        XCTAssertEqual(split[.microphone]![0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(split[.microphone]![1], 0.0, accuracy: 0.0001)
        XCTAssertEqual(split[.system]!.count, 2)
        XCTAssertEqual(split[.system]![0], -0.5, accuracy: 0.0001)
        XCTAssertEqual(split[.system]![1], 32_767.0 / 32_768.0, accuracy: 0.0001)
    }

    func testSplitPCM16MonoUsesMonoSource() {
        var data = Data()
        withUnsafeBytes(of: Int16(-32_768).littleEndian) { data.append(contentsOf: $0) }
        let split = OnDeviceDiarizationService.splitPCM16(data, multichannel: false, monoSource: .system)
        XCTAssertEqual(split.keys.count, 1)
        XCTAssertEqual(split[.system]!, [-1.0])
        XCTAssertTrue(OnDeviceDiarizationService.splitPCM16(Data(), multichannel: true, monoSource: .microphone).isEmpty)
    }

    // MARK: - Provider speaker selection

    func testProviderSpeakerPrefersTimelineWhenItCoversSource() {
        let t = timeline(mic: Array(repeating: 4, count: 100))
        let hit = DeepgramService.providerSpeaker(wordStart: 0.1, wordEnd: 0.3, deepgramSpeaker: 0, deepgramConfidence: 0.9, source: .microphone, timeline: t)
        XCTAssertEqual(hit.speaker, 4)
        XCTAssertEqual(hit.confidence ?? 0, 1.0, accuracy: 0.001)
        XCTAssertFalse(hit.borrowed)
        let past = DeepgramService.providerSpeaker(wordStart: 5.0, wordEnd: 5.3, deepgramSpeaker: 0, deepgramConfidence: 0.9, source: .microphone, timeline: t)
        XCTAssertEqual(past.speaker, 4)
        XCTAssertTrue(past.borrowed)
        // Source not covered: Deepgram's numbers stand
        let miss = DeepgramService.providerSpeaker(wordStart: 0.1, wordEnd: 0.3, deepgramSpeaker: 2, deepgramConfidence: 0.7, source: .system, timeline: t)
        XCTAssertEqual(miss.speaker, 2)
        XCTAssertEqual(miss.confidence, 0.7)
        // No timeline at all
        let none = DeepgramService.providerSpeaker(wordStart: 0.1, wordEnd: 0.3, deepgramSpeaker: nil, deepgramConfidence: nil, source: .microphone, timeline: nil)
        XCTAssertEqual(none.speaker, 0)
        XCTAssertNil(none.confidence)
    }

    // MARK: - Query items

    func testListenQueryOmitsDeepgramDiarizerWhenOnDevice() {
        let with = DeepgramService.makeListenQueryItems(language: "en", channelCount: 2, multichannel: true, providerDiarization: true)
        XCTAssertEqual(with.first { $0.name == "diarize_model" }?.value, "latest")
        XCTAssertEqual(with.first { $0.name == "multichannel" }?.value, "true")
        XCTAssertEqual(with.first { $0.name == "channels" }?.value, "2")
        let without = DeepgramService.makeListenQueryItems(language: "en", channelCount: 1, multichannel: false, providerDiarization: false)
        XCTAssertNil(without.first { $0.name == "diarize_model" })
        XCTAssertNil(without.first { $0.name == "multichannel" })
        XCTAssertEqual(without.map(\.name).filter { $0 != "diarize_model" }, with.map(\.name).filter { $0 != "diarize_model" && $0 != "multichannel" })
    }

    // MARK: - Identity stability across reconnects

    func testStableProviderSourcesKeepIdentitiesAcrossReconnect() {
        var state = SpeakerIdentityState()
        state.beginConnection(preservingIdentities: false)
        state.setStableProviderSources([.microphone, .system])
        let mic0 = state.appSpeakerID(source: .microphone, providerID: 0)
        let mic1 = state.appSpeakerID(source: .microphone, providerID: 1)
        let sys0 = state.appSpeakerID(source: .system, providerID: 0)
        XCTAssertEqual(mic0, DeepgramService.micSpeakerID)
        XCTAssertEqual(mic1, DeepgramService.micSpeakerID + 1)
        XCTAssertEqual(sys0, 0)

        state.beginConnection(preservingIdentities: true)
        state.setStableProviderSources([.microphone, .system])
        XCTAssertEqual(state.appSpeakerID(source: .microphone, providerID: 0), mic0)
        XCTAssertEqual(state.appSpeakerID(source: .microphone, providerID: 1), mic1)
        XCTAssertEqual(state.appSpeakerID(source: .system, providerID: 0), sys0)
        XCTAssertEqual(state.appSpeakerID(source: .system, providerID: 1), 1)
    }

    func testDeepgramDiarizedSourcesStayGenerationAware() {
        var state = SpeakerIdentityState()
        state.beginConnection(preservingIdentities: false)
        _ = state.appSpeakerID(source: .microphone, providerID: 0)
        _ = state.appSpeakerID(source: .microphone, providerID: 1)
        let sys0 = state.appSpeakerID(source: .system, providerID: 0)
        state.beginConnection(preservingIdentities: true)
        // Without stable sources a reconnect cannot trust provider numbers: fresh identities
        XCTAssertNotEqual(state.appSpeakerID(source: .system, providerID: 0), sys0)
        XCTAssertNotEqual(state.appSpeakerID(source: .microphone, providerID: 0), DeepgramService.micSpeakerID)
    }

    // MARK: - Service state

    @MainActor
    func testServiceStartsIdleOrUnsupportedAndRefusesSessionsUntilReady() {
        let service = OnDeviceDiarizationService()
        XCTAssertFalse(service.isReady)
        XCTAssertNil(service.beginSession(sources: [.microphone]))
        XCTAssertNil(service.activeTimeline)
        service.endSession()  // no-op without a session
        service.ingest(Data(repeating: 0, count: 64), multichannel: false, monoSource: .microphone)  // no-op without a session
        XCTAssertNil(service.activeTimeline)
    }
}

// MARK: - Opt-in end-to-end run with the real model
//
// Skipped unless MINITI_NEMOTRON_E2E points at a 16 kHz mono PCM16 wav with at least two
// speakers (for example scripts/diarization-poc/data/ES2004a.Array1-01.16k.wav). Downloads the
// model into the test host's container on first use (about 190 MB), then streams the file
// through the same ingest → session → timeline path the app uses at 100 ms packets.
final class OnDeviceDiarizationEndToEndTests: XCTestCase {
    @MainActor
    func testRealModelStreamsWavThroughSessionAndTimeline() async throws {
        guard let path = ProcessInfo.processInfo.environment["MINITI_NEMOTRON_E2E"], !path.isEmpty else {
            throw XCTSkip("Set MINITI_NEMOTRON_E2E=<path to 16 kHz mono wav> to run")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(data.count, 44)
        let pcm = data.subdata(in: 44..<data.count)  // canonical 44-byte RIFF header from ffmpeg

        let service = OnDeviceDiarizationService()
        XCTAssertTrue(OnDeviceDiarizationService.isHardwareSupported)
        service.prepare(sources: [.microphone])
        let deadline = Date().addingTimeInterval(300)
        while !service.isReady, Date() < deadline {
            if case .failed(let message) = service.status { XCTFail("model load failed: \(message)"); return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertTrue(service.isReady, "model did not become ready in time: \(service.statusDescription)")

        guard let timeline = service.beginSession(sources: [.microphone]) else { return XCTFail("no session") }
        let packet = 3_200  // 100 ms of 16 kHz PCM16, the app's send granularity
        var offset = 0
        var socketMarked = false
        let started = Date()
        while offset < pcm.count {
            let end = min(offset + packet, pcm.count)
            service.ingest(pcm.subdata(in: offset..<end), multichannel: false, monoSource: .microphone)
            if !socketMarked { timeline.markSocketStart(); socketMarked = true }  // same order as the app: ingest, then mark
            offset = end
        }
        service.endSession()
        let audioSeconds = Double(pcm.count / 2) / 16_000
        // Let the serial queue drain: the flush runs after every queued packet.
        let drainDeadline = Date().addingTimeInterval(120)
        while timeline.processedSeconds(source: .microphone) < audioSeconds - 0.5, Date() < drainDeadline {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        let wall = Date().timeIntervalSince(started)
        XCTAssertGreaterThan(timeline.processedSeconds(source: .microphone), audioSeconds - 0.5, "diarizer did not cover the file")

        var speakers = Set<Int>()
        var covered = 0
        var probes = 0
        var second = 1.0
        while second < audioSeconds - 1 {
            probes += 1
            if let hit = timeline.lookup(source: .microphone, socketStart: second, socketEnd: second + 0.3) {
                covered += 1
                speakers.insert(hit.providerSpeaker)
            }
            second += 2
        }
        XCTAssertGreaterThanOrEqual(speakers.count, 2, "expected at least two speakers, got \(speakers)")
        XCTAssertLessThanOrEqual(speakers.count, 8)
        XCTAssertGreaterThan(Double(covered) / Double(max(probes, 1)), 0.5)
        print("E2E: \(String(format: "%.0f", audioSeconds))s audio in \(String(format: "%.1f", wall))s wall (rtf \(String(format: "%.3f", wall / audioSeconds))), speakers \(speakers.sorted()), coverage \(covered)/\(probes)")
    }
}

// MARK: - Acknowledgements ship with the app

final class AcknowledgementsTests: XCTestCase {
    func testEveryAcknowledgementHasItsLicenceTextInTheBundle() {
        let entries = Acknowledgements.entries
        XCTAssertGreaterThanOrEqual(entries.count, 8)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count, "entry ids must be unique")
        for entry in entries {
            let text = Acknowledgements.text(for: entry)
            XCTAssertNotNil(text, "missing licence file \(entry.file)")
            XCTAssertGreaterThan(text?.count ?? 0, 200, "licence file \(entry.file) looks truncated")
        }
    }

    func testBundledModelNoticesCarryTheRequiredTerms() throws {
        let openmdw = try XCTUnwrap(Acknowledgements.entries.first { $0.id == "openmdw" }.flatMap { Acknowledgements.text(for: $0) })
        XCTAssertTrue(openmdw.contains("OpenMDW License Agreement, version 1.1"))
        XCTAssertTrue(openmdw.contains("retain in your distribution"))
        let notice = try XCTUnwrap(Acknowledgements.entries.first { $0.id == "nemotron" }.flatMap { Acknowledgements.text(for: $0) })
        XCTAssertTrue(notice.contains("NVIDIA"))
        XCTAssertTrue(notice.contains("FluidInference"))
        let apache = try XCTUnwrap(Acknowledgements.entries.first { $0.id == "fluidaudio" }.flatMap { Acknowledgements.text(for: $0) })
        XCTAssertTrue(apache.contains("Apache License"))
        XCTAssertTrue(apache.contains("Version 2.0"))
    }
}

#if os(macOS)
// MARK: - Microphone selection (macOS)

final class MicrophoneSelectionTests: XCTestCase {
    private func device(_ id: UInt32, _ uid: String, _ name: String) -> AudioCaptureService.InputDevice {
        AudioCaptureService.InputDevice(id: id, uid: uid, name: name, transport: "usb")
    }

    func testNoPreferenceUsesSystemDefault() {
        let r = AudioCaptureService.resolveInputDevice(preferredUID: nil, devices: [device(1, "a", "A")], systemDefault: 7)
        XCTAssertEqual(r.deviceID, 7)
        XCTAssertFalse(r.usedFallback)
        let empty = AudioCaptureService.resolveInputDevice(preferredUID: "", devices: [device(1, "a", "A")], systemDefault: 7)
        XCTAssertEqual(empty.deviceID, 7)
        XCTAssertFalse(empty.usedFallback)
    }

    func testPreferredDeviceWinsOverDefaultWhenPresent() {
        let r = AudioCaptureService.resolveInputDevice(preferredUID: "rode", devices: [device(3, "airpods", "AirPods"), device(9, "rode", "RØDE")], systemDefault: 3)
        XCTAssertEqual(r.deviceID, 9)
        XCTAssertFalse(r.usedFallback)
    }

    func testMissingPreferredDeviceFallsBackToDefaultAndSaysSo() {
        let r = AudioCaptureService.resolveInputDevice(preferredUID: "rode", devices: [device(3, "airpods", "AirPods")], systemDefault: 3)
        XCTAssertEqual(r.deviceID, 3)
        XCTAssertTrue(r.usedFallback)
    }

    func testEnumerationExcludesAggregatesAndListsRealInputs() {
        // Runs against the real HAL: every listed device has a uid and a name, none is an aggregate.
        let devices = AudioCaptureService.availableInputDevices()
        for d in devices {
            XCTAssertFalse(d.uid.isEmpty)
            XCTAssertFalse(d.name.isEmpty)
            XCTAssertNotEqual(d.transport, "aggregate")
        }
        XCTAssertEqual(Set(devices.map(\.uid)).count, devices.count, "uids must be unique")
    }
}
#endif
