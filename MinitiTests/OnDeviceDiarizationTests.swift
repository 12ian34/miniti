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
            try await Task.sleep(for: .milliseconds(100))
        }
        await service.flushActiveSession()
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

private final class FixtureSpeakerProcessor: OnDeviceDiarizationService.Processor, @unchecked Sendable {
    var processBody: @Sendable ([Float]) throws -> [OnDeviceDiarizationService.Output]
    var finishBody: @Sendable () throws -> [OnDeviceDiarizationService.Output]
    init(process: @escaping @Sendable ([Float]) throws -> [OnDeviceDiarizationService.Output] = { _ in [] },
         finish: @escaping @Sendable () throws -> [OnDeviceDiarizationService.Output] = { [] }) {
        processBody = process; finishBody = finish
    }
    func process(_ samples: [Float]) throws -> [OnDeviceDiarizationService.Output] { try processBody(samples) }
    func finish() throws -> [OnDeviceDiarizationService.Output] { try finishBody() }
}

@MainActor
final class LocalSpeakerFailureTests: XCTestCase {
    private enum Fault: Error { case fixture }
    private func readyService(_ processor: FixtureSpeakerProcessor = FixtureSpeakerProcessor(), sources: Set<TranscriptSource> = [.microphone]) async throws -> OnDeviceDiarizationService {
        let service = OnDeviceDiarizationService(loader: { _, _ in { processor } }, hardwareSupported: true)
        service.prepare(sources: sources)
        try await TestSupport.waitUntil { service.isReady }
        return service
    }

    func testCancelledPreparationCannotRepopulateModelsOrOverwriteRetry() async throws {
        var suspended: CheckedContinuation<OnDeviceDiarizationService.ProcessorFactory, Error>?
        var oldProgress: (@Sendable (Double) -> Void)?
        var calls = 0
        let service = OnDeviceDiarizationService(loader: { _, progress in
            calls += 1
            if calls == 1 {
                oldProgress = progress
                return try await withCheckedThrowingContinuation { suspended = $0 }
            }
            return { FixtureSpeakerProcessor() }
        }, hardwareSupported: true)
        service.prepare(sources: [.microphone])
        try await TestSupport.waitUntil { suspended != nil }
        service.unload()
        service.prepare(sources: [.microphone])
        XCTAssertEqual(calls, 1, "Never pile up another load behind uncooperative cancellation")
        suspended?.resume(returning: { FixtureSpeakerProcessor() })
        try await TestSupport.waitUntil { service.canRetry }
        XCTAssertFalse(service.isReady)
        XCTAssertNil(service.beginSession(sources: [.microphone]))
        service.prepare(sources: [.microphone])
        try await TestSupport.waitUntil { service.isReady }
        oldProgress?(0.5)
        await Task.yield()
        XCTAssertEqual(service.status, .ready)
        XCTAssertEqual(calls, 2)
    }

    func testEveryRequestedSourceMustBeReadyAndFailedLoadDiscardsPartialModels() async throws {
        let service = OnDeviceDiarizationService(loader: { source, _ in
            if source == .system { throw Fault.fixture }
            return { FixtureSpeakerProcessor() }
        }, hardwareSupported: true)
        service.prepare(sources: [.microphone, .system])
        try await TestSupport.waitUntil { if case .failed = service.status { return true }; return false }
        XCTAssertNil(service.beginSession(sources: [.microphone]))
        let single = try await readyService()
        XCTAssertNil(single.beginSession(sources: [.microphone, .system]))
        XCTAssertNotNil(single.beginSession(sources: [.microphone]))
        await single.endSessionAndWait()
    }

    func testRetryIsOfferedOnlyForAFailedModelAndWaitsForTheRecordingToEnd() async throws {
        let processor = FixtureSpeakerProcessor(process: { _ in throw Fault.fixture })
        let service = try await readyService(processor)
        XCTAssertEqual(service.retryAvailability(recordingActive: false), .hidden)
        XCTAssertNotNil(service.beginSession(sources: [.microphone]))
        var failed = false
        service.onSessionFailure = { _, _ in failed = true }
        service.ingest(samples: [0, 0], source: .microphone)
        try await TestSupport.waitUntil { failed }
        XCTAssertEqual(service.retryAvailability(recordingActive: true), .afterRecording)
        await service.endSessionAndWait()
        try await TestSupport.waitUntil { service.canRetry }
        XCTAssertEqual(service.retryAvailability(recordingActive: false), .available)
        XCTAssertEqual(service.retryAvailability(recordingActive: true), .afterRecording)
        XCTAssertTrue(service.statusDescription.contains("stopped during the last recording"))
        XCTAssertFalse(service.statusDescription.contains("—"))
        service.prepare(sources: [.microphone])
        try await TestSupport.waitUntil { service.isReady }
        XCTAssertEqual(service.retryAvailability(recordingActive: false), .hidden)
    }

    func testInferenceFailureInvalidatesTimelineCollectorAndRequiresFreshPreparation() async throws {
        for source in [TranscriptSource.microphone, .system] {
            let processor = FixtureSpeakerProcessor(process: { _ in throw Fault.fixture })
            let service = try await readyService(processor, sources: [.microphone, .system])
            let collector = VoicePrintCollector(embed: { _ in [1, 0] })
            let timeline = try XCTUnwrap(service.beginSession(sources: [.microphone, .system], collector: collector))
            var failures = 0
            service.onSessionFailure = { _, reason in XCTAssertEqual(reason, .inference); failures += 1 }
            service.ingest(samples: [0, 0], source: source)
            try await TestSupport.waitUntil { failures == 1 }
            XCTAssertFalse(timeline.isReliable)
            XCTAssertFalse(service.isReady)
            XCTAssertNil(service.activeCollector)
            service.ingest(samples: [0, 0], source: source)
            await service.endSessionAndWait()
            XCTAssertEqual(failures, 1)
            XCTAssertNil(service.beginSession(sources: [.microphone, .system]))
            service.prepare(sources: [.microphone, .system])
            try await TestSupport.waitUntil { service.isReady }
            XCTAssertNotNil(service.beginSession(sources: [.microphone, .system]))
            await service.endSessionAndWait()
        }
    }

    func testSlowWorkerHasBoundedAdmissionAndOneFailureSignal() async {
        let entered = expectation(description: "worker entered")
        let failed = expectation(description: "bounded lag failure")
        failed.assertForOverFulfill = true
        let release = DispatchSemaphore(value: 0)
        let processor = FixtureSpeakerProcessor(process: { _ in
            entered.fulfill(); release.wait(); return []
        })
        let timeline = OnDeviceSpeakerTimeline(sources: [.microphone])
        let session = OnDeviceDiarizationService.Session(timeline: timeline, processors: [.microphone: processor], onFailure: { _, reason in
            XCTAssertEqual(reason, .lag); failed.fulfill()
        })
        session.ingest(samples: [0], source: .microphone)
        await fulfillment(of: [entered], timeout: 2)
        for _ in 0..<200 { session.ingest(samples: [0], source: .microphone) }
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertLessThanOrEqual(session.queuedSampleCount, OnDeviceDiarizationService.Session.maximumQueuedPackets)
        XCTAssertFalse(timeline.isReliable)
        release.signal()
        await withCheckedContinuation { continuation in session.finish { continuation.resume() } }
        XCTAssertEqual(session.queuedSampleCount, 0)
    }

    func testHungFinishIsBoundedAndCannotStartAnotherWorkerUntilItSettles() async throws {
        let entered = expectation(description: "finish entered")
        let release = DispatchSemaphore(value: 0)
        let processor = FixtureSpeakerProcessor(finish: { entered.fulfill(); release.wait(); return [] })
        let service = try await readyService(processor)
        let timeline = try XCTUnwrap(service.beginSession(sources: [.microphone]))
        let ending = Task { await service.endSessionAndWait() }
        await fulfillment(of: [entered], timeout: 2)
        await ending.value
        XCTAssertFalse(timeline.isReliable)
        XCTAssertFalse(service.canRetry)
        XCTAssertNil(service.beginSession(sources: [.microphone]))
        release.signal()
        try await TestSupport.waitUntil { service.canRetry }
        XCTAssertTrue(service.isReady)
        XCTAssertNotNil(service.beginSession(sources: [.microphone]))
        // Replace the fixture's held finish before closing the next recording.
        processor.finishBody = { [] }
        await service.endSessionAndWait()
    }

    func testFailedTimelineAllocatesNeutralBucketWithoutReusingKnownPeople() throws {
        for source in [TranscriptSource.microphone, .system] {
            let timeline = OnDeviceSpeakerTimeline(sources: [source])
            timeline.invalidate()
            var identity = SpeakerIdentityState()
            identity.setStableProviderSources([source])
            let known = identity.appSpeakerID(source: source, providerID: 0)
            var segmentation = DeepgramService.SegmentationState()
            segmentation.lastCommittedSpeakerBySource[source] = known
            segmentation.confirmedSpeakerIDs.insert(known)
            let json = #"{"type":"Results","is_final":true,"channel":{"alternatives":[{"transcript":"still recording","confidence":1,"words":[{"word":"still","start":1,"end":1.2,"confidence":1,"speaker":0,"speaker_confidence":1},{"word":"recording","start":1.2,"end":1.5,"confidence":1,"speaker":0,"speaker_confidence":1}]}]}}"#
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: Data(json.utf8))
            let result = DeepgramService.processTranscriptResponse(response, isMultichannel: false, monoSource: source,
                segmentationState: segmentation, identityState: identity, speakerTimeline: timeline)
            guard case .transcript(let parsed) = result else { return XCTFail("expected words") }
            XCTAssertTrue(parsed.update.speakerSeparationUnavailable)
            XCTAssertNotEqual(parsed.update.speaker, known)
            XCTAssertGreaterThanOrEqual(parsed.update.speaker, 0, "Keep the persisted ID contract")
            XCTAssertEqual(parsed.segments.first?.speaker, parsed.update.speaker, "Do not let promotion retain the previous person")
            XCTAssertTrue(parsed.update.words.allSatisfy { $0.speakerConfidence == 0 })
            XCTAssertNil(parsed.identityState.stableProviderMap()[source]?[-1], "Never enroll the unavailable bucket")
        }
    }

    func testLiveFailureDoesNotReconnectAndNewMetadataHonorsPrivacyAndMode() async throws {
        let defaults = UserDefaults.standard
        let keys = ["onDeviceSpeakerSeparation", "appMode", "shareDiagnostics", "privateMode"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer { for key in keys { if let value = saved[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        for (mode, shared, privateMode, expectedEvents) in [(AppMode.managed, true, false, 2), (.managed, false, false, 0), (.managed, true, true, 0), (.byok, true, false, 0)] {
            let processor = FixtureSpeakerProcessor(process: { _ in throw Fault.fixture })
            let service = try await readyService(processor)
            let state = AppState(diarizationService: service)
            state.appModeRaw = mode.rawValue; state.shareDiagnostics = shared; state.privateModeEnabled = privateMode
            state.onDeviceSpeakerSeparationEnabled = true
            state.refreshOnDeviceDiarizationAvailability()
            try await TestSupport.waitUntil { service.isReady && service.canRetry }
            // This fixture represents an already-connected recording. Settle the
            // initial Combine delivery before observing speaker-only failures.
            state.deepgramService?.connectionState = .connected
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            state.currentMeeting = Meeting(title: "fixture")
            state.isRecording = true
            var events: [String] = []
            state.diagnosticEventObserver = { name, _ in events.append(name) }
            XCTAssertNotNil(state.beginOnDeviceDiarizationSession(multichannel: false, monoSource: .microphone, transcribesOnDevice: false))
            let id = try XCTUnwrap(service.activeSessionID)
            state.handleLocalSpeakerFailure(id: UUID(), reason: .inference)
            XCTAssertEqual(state.sessionSpeakerState, .onDevice, "Ignore a stale recording's failure")
            service.ingest(samples: [0], source: .microphone)
            try await TestSupport.waitUntil { state.sessionSpeakerState == .unavailable }
            XCTAssertEqual(service.activeSessionID, id)
            XCTAssertTrue(state.isRecording)
            XCTAssertNotNil(state.speakerSeparationIssue)
            XCTAssertEqual(events.count, expectedEvents)
            XCTAssertFalse(events.contains { $0.contains("reconnect") })
            state.isRecording = false
            await service.endSessionAndWait()
        }
    }

    func testUnknownSpeakerLabelPersistsAndManualCorrectionWins() async throws {
        let state = AppState()
        state.currentMeeting = Meeting(title: "fixture")
        state.isRecording = true
        defer { state.isRecording = false }
        let update = DeepgramService.TranscriptUpdate(text: "still recording", speaker: 1001, isFinal: true, confidence: 1,
            words: [.init(text: "still recording", start: 1, end: 2, confidence: 1, speaker: 1001, speakerConfidence: 0)],
            channelIndex: nil, source: .microphone, speakerSeparationUnavailable: true)
        state.deepgramService?.transcriptUpdate = update
        try await TestSupport.waitUntil { state.currentMeeting?.speakerNames["1001"] == AppState.unavailableSpeakerName }
        XCTAssertEqual(state.liveSpeakerNames["1001"], AppState.unavailableSpeakerName)
        state.setLiveSpeakerName(id: 1001, name: "Confirmed by user")
        state.deepgramService?.transcriptUpdate = update
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(state.currentMeeting?.speakerNames["1001"], "Confirmed by user")
        XCTAssertEqual(state.liveSpeakerNames["1001"], "Confirmed by user")
    }

    func testUnavailableBeforeStartKeepsCloudDiarizationAndDoesNotLoadDuringSession() async throws {
        let service = OnDeviceDiarizationService(loader: { _, _ in throw Fault.fixture }, hardwareSupported: true)
        XCTAssertNil(service.beginSession(sources: [.microphone]))
        let query = DeepgramService.makeListenQueryItems(language: "en", channelCount: 1, multichannel: false,
            providerDiarization: service.beginSession(sources: [.microphone]) == nil)
        XCTAssertEqual(query.first { $0.name == "diarize_model" }?.value, "latest")
        let ready = try await readyService()
        let timeline = try XCTUnwrap(ready.beginSession(sources: [.microphone]))
        ready.unload()
        XCTAssertTrue(timeline.isReliable, "A setting change affects the next session")
        XCTAssertEqual(ready.activeSessionID != nil, true)
        ready.prepare(sources: [.microphone, .system])
        XCTAssertFalse(ready.isReady, "Do not prepare another engine inside the active session")
        await ready.endSessionAndWait()
    }

    func testDiscardRetiresWorkerWithoutReportingFailureOrBlockingReplacement() async throws {
        let entered = expectation(description: "discarded processor entered")
        let release = DispatchSemaphore(value: 0)
        let processor = FixtureSpeakerProcessor(process: { _ in entered.fulfill(); release.wait(); throw Fault.fixture })
        let service = try await readyService(processor)
        let timeline = try XCTUnwrap(service.beginSession(sources: [.microphone]))
        service.ingest(samples: [0], source: .microphone)
        await fulfillment(of: [entered], timeout: 2)
        var failures = 0
        service.onSessionFailure = { _, _ in failures += 1 }
        service.discardSession()
        release.signal()
        XCTAssertNil(service.activeSessionID)
        XCTAssertFalse(timeline.isReliable)
        try await TestSupport.waitUntil { service.canRetry }
        XCTAssertTrue(service.isReady)
        XCTAssertNotNil(service.beginSession(sources: [.microphone]))
        XCTAssertEqual(failures, 0)
        await service.endSessionAndWait()
    }

    func testVoiceCollectorRejectsLateEmbeddingAfterInvalidation() async throws {
        let started = expectation(description: "embedding started")
        let released = expectation(description: "embedding returned")
        let gate = AsyncSpeakerEmbeddingGate()
        let collector = VoicePrintCollector(embed: { _ in
            started.fulfill()
            let result = await gate.wait()
            released.fulfill()
            return result
        })
        collector.noteAudio(source: .microphone, samples: [Float](repeating: 0.1, count: 96000))
        collector.noteFrames(source: .microphone, startFrame: 0, dominant: [UInt8](repeating: 0, count: 600), exclusive: [Bool](repeating: true, count: 600))
        await fulfillment(of: [started], timeout: 2)
        collector.invalidate()
        await gate.release()
        await fulfillment(of: [released], timeout: 2)
        await collector.finish()
        XCTAssertTrue(collector.snapshot().isEmpty)
    }
}

private actor AsyncSpeakerEmbeddingGate {
    var continuation: CheckedContinuation<[Float], Never>?
    var released = false
    func wait() async -> [Float] {
        if released { return [1, 0] }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume(returning: [1, 0]); continuation = nil
    }
}


extension LocalSpeakerFailureTests {
    func testPrerecordedBackpressureProcessesLongFileAndStaleOwnersCannotEndIt() async throws {
        let processor = FixtureSpeakerProcessor(process: { samples in
            let frames = samples.count / 160
            return [.init(probabilities: Array(repeating: 1, count: frames), frameCount: frames, numSpeakers: 1)]
        })
        let service = try await readyService(processor)
        let timeline = try XCTUnwrap(service.beginSession(sources: [.microphone]))
        let id = try XCTUnwrap(service.activeSessionID)
        for _ in 0..<20 {
            let accepted = await service.ingestPrerecorded(samples: Array(repeating: 0, count: 16000), source: .microphone, expectedID: id)
            XCTAssertTrue(accepted)
        }
        XCTAssertTrue(timeline.isReliable)
        XCTAssertEqual(timeline.processedSeconds(source: .microphone), 20, accuracy: 0.01)
        let stale = UUID()
        let rejected = await service.ingestPrerecorded(samples: [0], source: .microphone, expectedID: stale)
        XCTAssertFalse(rejected)
        await service.flushActiveSession(expectedID: stale)
        await service.endSessionAndWait(expectedID: stale)
        service.discardSession(expectedID: stale)
        XCTAssertEqual(service.activeSessionID, id)
        await service.endSessionAndWait(expectedID: id)
        XCTAssertNil(service.activeSessionID)
        XCTAssertTrue(timeline.isReliable)
    }

    func testPrerecordedHungChunkReturnsWithinItsBoundWithoutTrustedLabels() async throws {
        let entered = expectation(description: "prerecorded worker entered")
        let release = DispatchSemaphore(value: 0)
        let service = try await readyService(FixtureSpeakerProcessor(process: { _ in
            entered.fulfill(); release.wait(); return []
        }))
        let timeline = try XCTUnwrap(service.beginSession(sources: [.microphone]))
        let id = try XCTUnwrap(service.activeSessionID)
        let run = Task { await service.ingestPrerecorded(samples: [0], source: .microphone, expectedID: id, timeout: .milliseconds(50)) }
        await fulfillment(of: [entered], timeout: 2)
        let accepted = await run.value
        XCTAssertFalse(accepted)
        XCTAssertFalse(timeline.isReliable)
        release.signal()
        await service.endSessionAndWait(expectedID: id)
    }

    func testLiveFallbackDoesNotReportOrStopAnotherPrerecordedSpeakerOwner() async throws {
        let service = try await readyService()
        _ = try XCTUnwrap(service.beginSession(sources: [.microphone]))
        let fileID = try XCTUnwrap(service.activeSessionID)
        let state = AppState(diarizationService: service)
        state.deepgramService?.connectionState = .connected
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        state.isRecording = true
        XCTAssertNil(state.beginOnDeviceDiarizationSession(multichannel: false, monoSource: .microphone, transcribesOnDevice: false))
        XCTAssertEqual(state.sessionSpeakerState, .deepgram)
        state.handleLocalSpeakerFailure(id: fileID, reason: .inference)
        XCTAssertEqual(state.sessionSpeakerState, .deepgram)
        state.stopRecording()
        XCTAssertEqual(service.activeSessionID, fileID)
        await service.endSessionAndWait(expectedID: fileID)
    }
}

extension LocalSpeakerFailureTests {
    func testStopAllowsQueuedAudioToSettleAndNextRecordingNeedsNoRetry() async throws {
        let entered = expectation(description: "queued decode")
        let release = DispatchSemaphore(value: 0)
        let processor = FixtureSpeakerProcessor(process: { samples in
            entered.fulfill(); release.wait()
            return [.init(probabilities: Array(repeating: 1, count: samples.count / 160), frameCount: samples.count / 160, numSpeakers: 1)]
        })
        let service = try await readyService(processor)
        let timeline = try XCTUnwrap(service.beginSession(sources: [.microphone]))
        service.ingest(samples: Array(repeating: 0, count: 4 * 16000), source: .microphone)
        await fulfillment(of: [entered], timeout: 2)
        let stopping = Task { await service.endSessionAndWait() }
        // Cross the old two-second Stop deadline with four seconds of accepted audio.
        try await Task.sleep(for: .milliseconds(2300))
        XCTAssertTrue(timeline.isReliable)
        release.signal()
        await stopping.value
        XCTAssertTrue(timeline.isReliable)
        XCTAssertEqual(timeline.processedSeconds(source: .microphone), 4, accuracy: 0.01)
        XCTAssertEqual(timeline.matureSlots(source: .microphone), [0])
        XCTAssertTrue(service.isReady)
        XCTAssertNotNil(service.beginSession(sources: [.microphone]))
        await service.endSessionAndWait()
    }

    func testAdmissionLagInvalidatesEvidenceButKeepsPreparedModel() async throws {
        let service = try await readyService()
        let collector = VoicePrintCollector(embed: { _ in [1, 0] })
        let timeline = try XCTUnwrap(service.beginSession(sources: [.microphone], collector: collector))
        service.ingest(samples: Array(repeating: 0, count: 9 * 16000), source: .microphone)
        try await TestSupport.waitUntil { service.activeCollector == nil }
        XCTAssertFalse(timeline.isReliable)
        XCTAssertTrue(service.isReady)
        await service.endSessionAndWait()
        XCTAssertNotNil(service.beginSession(sources: [.microphone]))
        await service.endSessionAndWait()
    }

    func testLocalTranscriptionWithSeparationOffKeepsMicIdentityAndNoFailure() async throws {
        let state = AppState()
        state.appModeRaw = AppMode.managed.rawValue
        state.shareDiagnostics = true; state.privateModeEnabled = false
        state.onDeviceSpeakerSeparationEnabled = false
        state.isRecording = true
        defer { state.isRecording = false }
        var events: [(String, [String: String])] = []
        state.diagnosticEventObserver = { events.append(($0, $1)) }
        let timeline = state.beginOnDeviceDiarizationSession(multichannel: false, monoSource: .microphone, transcribesOnDevice: true)
        XCTAssertNil(timeline)
        XCTAssertNil(state.speakerSeparationIssue)
        XCTAssertEqual(events.last?.0, "speaker_separation_state")
        XCTAssertEqual(events.last?.1["speaker_engine"], "unavailable")
        XCTAssertNil(events.last?.1["speaker_failure"])
        let response = try JSONDecoder().decode(DeepgramResponse.self, from: Data(#"{"type":"Results","is_final":true,"channel":{"alternatives":[{"transcript":"hello there","confidence":1,"words":[{"word":"hello","start":0,"end":0.2,"confidence":1,"speaker":0},{"word":"there","start":0.2,"end":0.5,"confidence":1,"speaker":0}]}]}}"#.utf8))
        let result = DeepgramService.processTranscriptResponse(response, isMultichannel: false, monoSource: .microphone,
            segmentationState: .init(), identityState: .init(), speakerTimeline: timeline)
        guard case .transcript(let parsed) = result else { return XCTFail("expected mic words") }
        XCTAssertEqual(parsed.update.speaker, 1000)
        XCTAssertFalse(parsed.update.speakerSeparationUnavailable)
        state.currentMeeting = Meeting(title: "mic only")
        state.liveSpeakerNames = ["1000": "Sasha"]
        state.deepgramService?.transcriptUpdate = parsed.update
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(state.liveSpeakerNames["1000"], "Sasha")
        XCTAssertFalse(state.liveSpeakerNames.values.contains(AppState.unavailableSpeakerName))

        state.onDeviceSpeakerSeparationEnabled = true
        let unavailable = state.beginOnDeviceDiarizationSession(multichannel: false, monoSource: .microphone, transcribesOnDevice: true)
        XCTAssertEqual(unavailable?.isReliable, false)
        XCTAssertNotNil(state.speakerSeparationIssue)
        XCTAssertEqual(events.last?.0, "speaker_separation_failed")
        XCTAssertEqual(events.last?.1["speaker_failure"], "not_ready")
    }
}

extension LocalSpeakerFailureTests {
    func testStopBudgetIncludesAudioBufferedInsideProcessor() async throws {
        let entered = expectation(description: "buffered tail finish")
        let release = DispatchSemaphore(value: 0)
        let processor = FixtureSpeakerProcessor(finish: {
            entered.fulfill(); release.wait()
            return [.init(probabilities: Array(repeating: 1, count: 400), frameCount: 400, numSpeakers: 1)]
        })
        let service = try await readyService(processor)
        let timeline = try XCTUnwrap(service.beginSession(sources: [.microphone]))
        service.ingest(samples: Array(repeating: 0, count: 4 * 16000), source: .microphone)
        // The serial worker reaches finish after process returned, with no pending PCM.
        let stopping = Task { await service.endSessionAndWait() }
        await fulfillment(of: [entered], timeout: 2)
        try await Task.sleep(for: .milliseconds(2300))
        XCTAssertTrue(timeline.isReliable)
        release.signal()
        await stopping.value
        XCTAssertTrue(timeline.isReliable)
        XCTAssertEqual(timeline.matureSlots(source: .microphone), [0])
        XCTAssertTrue(service.isReady)
    }
}
