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

    private func timeline(mic slots: [Int?]) -> OnDeviceSpeakerTimeline {
        let t = OnDeviceSpeakerTimeline(sources: [.microphone])
        t.markSocketStart()
        t.append(source: .microphone, probabilities: probabilities(slots), frameCount: slots.count, numSpeakers: 8)
        return t
    }

    // MARK: - Timeline lookup

    func testLookupMajoritySpeakerOverWord() {
        // 0.00–0.30 s speaker 0, 0.30–0.60 s speaker 1
        let t = timeline(mic: Array(repeating: 0, count: 30) + Array(repeating: 1, count: 30))
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 0.05, socketEnd: 0.25)?.providerSpeaker, 0)
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 0.35, socketEnd: 0.55)?.providerSpeaker, 1)
        // A word straddling the boundary goes to whoever dominates it
        let straddle = t.lookup(source: .microphone, socketStart: 0.25, socketEnd: 0.45)
        XCTAssertEqual(straddle?.providerSpeaker, 1)
        XCTAssertLessThan(straddle!.confidence, 1.0)
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 0.0, socketEnd: 0.3)?.confidence ?? 0, 1.0, accuracy: 0.001)
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

    func testSocketOriginShiftsLookups() {
        let t = OnDeviceSpeakerTimeline(sources: [.microphone])
        // 2 s of audio fed and diarized (speaker 0) before this socket started sending
        t.noteAudioFed(source: .microphone, sampleCount: 32_000)
        t.append(source: .microphone, probabilities: probabilities(Array(repeating: 0, count: 200)), frameCount: 200, numSpeakers: 8)
        t.markSocketStart()
        // Then 1 s of speaker 1 on the new socket
        t.noteAudioFed(source: .microphone, sampleCount: 16_000)
        t.append(source: .microphone, probabilities: probabilities(Array(repeating: 1, count: 100)), frameCount: 100, numSpeakers: 8)
        XCTAssertEqual(t.fedSeconds(source: .microphone), 3.0, accuracy: 0.001)
        XCTAssertEqual(t.lookup(source: .microphone, socketStart: 0.1, socketEnd: 0.4)?.providerSpeaker, 1)
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
            if !socketMarked { timeline.markSocketStart(); socketMarked = true }
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
