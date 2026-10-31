import XCTest
import CoreAudio
import SwiftData
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

#if os(macOS)
/// Field report (2026-10-02): "End & start next" between back-to-back calls left the new
/// meeting saying it was recording while nothing reached the transcript; stop + resume
/// fixed it. These drive the real AppState handoff in BYOK mode (no backend) and check
/// the capture pipeline is actually live on the second meeting.
@MainActor
final class MeetingHandoffTests: XCTestCase {
    private var state: AppState!
    private var container: ModelContainer!
    private static let touchedDefaults = [
        "appMode", "deepgramApiKey", "openaiApiKey", "autoInferSpeakerNames", "autoAttioSync", "autoTwentySync", "acceptedTermsVersion", "declinedTermsVersion", "hasAcceptedTerms",
        "captureMicrophone", "captureSystemAudio", "smartMeetingsEnabled",
        "autoExportMarkdown", "webhookURL",
        // The host install may run the on-device engines; these tests exercise the Deepgram path.
        "onDeviceTranscription", "onDeviceTranscriptionCloudFallback", "onDeviceSpeakerSeparation",
    ]
    private var savedDefaults: [String: Any] = [:]

    override func setUp() async throws {
        // The test host is the real app, so AppStorage writes land in its defaults.
        for key in Self.touchedDefaults {
            if let value = UserDefaults.standard.object(forKey: key) { savedDefaults[key] = value }
        }
        // Off before the state exists, so its launch refresh loads no model.
        for key in ["onDeviceTranscription", "onDeviceTranscriptionCloudFallback", "onDeviceSpeakerSeparation"] {
            UserDefaults.standard.set(false, forKey: key)
        }
        container = try TestSupport.makeInMemoryContainer()
        state = AppState()
        // The real stop path must save durably before it can hand off. Keep that contract
        // in this hardware fixture without touching the host install's meeting store.
        state.modelContext = container.mainContext
        state.appMode = .byok
        state.deepgramApiKey = "test-key-not-real"
        // These tests verify real HAL capture and callback ownership, not provider service.
        // Cancel the native task immediately, without reaching a provider. Leaving it
        // suspended would make gracefulDisconnect's CloseStream send wait indefinitely.
        state.deepgramService?.socketStarter = { $0.cancel() }
        state.openaiApiKey = ""
        state.autoInferSpeakerNames = false
        state.insightsService = nil
        state.minitiAPIService = nil
        state.autoAttioSync = false
        state.autoTwentySync = false
        state.hasAcceptedTerms = true
        state.captureMicrophone = true
        state.captureSystemAudio = true
        state.smartMeetingsEnabled = true
        // Never write into the host install's export folder or call its webhook.
        state.autoExportMarkdown = false
        state.webhookURL = ""
        state.upcomingEvents = [Self.event(id: "next", title: "Next call")]
    }

    override func tearDown() async throws {
        if state.isRecording { state.stopRecording() }
        try? await Task.sleep(for: .seconds(1.5))
        await waitUntil { !self.state.isFinalizingMeeting && self.state.finalizingInsightMeetingIDs.isEmpty }
        state.audioCaptureService?.stopCapture()
        state.deepgramService?.disconnect()
        state = nil
        container = nil
        for key in Self.touchedDefaults {
            if let value = savedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private static func event(id: String, title: String) -> MinitiAPIService.CalendarEvent {
        let f = ISO8601DateFormatter()
        let json: [String: Any] = [
            "id": id, "title": title,
            "start": f.string(from: Date().addingTimeInterval(-60)),
            "end": f.string(from: Date().addingTimeInterval(1_800)),
            "isAllDay": false, "status": "confirmed", "attendees": [] as [[String: Any]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MinitiAPIService.CalendarEvent.self, from: data)
    }

    private static let zoom = ActiveCallApplication(
        bundleID: "us.zoom.xos", displayName: "Zoom", deviceUIDs: ["mic"], confidence: .native
    )

    private func feedCall(_ calls: [ActiveCallApplication]) {
        state.handleCallActivitySnapshot(
            CallActivitySnapshot(capturedAt: Date(), activeCalls: calls, isReliable: true)
        )
    }

    private func dumpLog(_ label: String) {
        let lines = DebugLogger.shared.entries.suffix(80).map { "\($0.category.rawValue): \($0.message)" }
        print("=== \(label) ===\n" + lines.joined(separator: "\n") + "\n=== end ===")
    }

    private func waitUntil(_ timeout: TimeInterval = 6, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func describePipeline(_ label: String) -> String {
        let cap = state.audioCaptureService
        return "\(label): isRecording=\(state.isRecording) meeting=\(state.currentMeeting?.title ?? "nil") finalizing=\(state.isFinalizingMeeting) capturing=\(cap?.isCapturing ?? false) mic=\(cap?.isMicActive ?? false) handler=\(cap?.onAudioBuffer != nil) sendSuspended=\(cap?.isSendSuspended ?? false) dg=\(state.deepgramService?.connectionState as Any)"
    }

    func testEndAndStartNextLeavesCaptureLiveOnTheNewMeeting() async throws {
        try Self.requireMicrophone()
        // A Zoom call is already running when the first meeting starts, and stays up through
        // the handoff: that is the back-to-back shape the report describes.
        feedCall([Self.zoom])
        XCTAssertTrue(state.startNewMeeting())
        await waitUntil { self.state.audioCaptureService?.isCapturing == true }
        XCTAssertTrue(state.isRecording)
        XCTAssertTrue(state.audioCaptureService?.isCapturing ?? false, describePipeline("first meeting"))
        let firstID = state.currentMeeting?.id
        feedCall([Self.zoom])

        // Give the first meeting content so the stop takes the full finalization path
        // (graceful Deepgram close, save, final insights) exactly as a real call does.
        state.liveSegments = [
            AppState.LiveSegment(id: UUID(), text: "hello from the first call", speaker: 0, timestamp: 1, isFinal: true)
        ]

        state.endAndStartCalendarMeeting(eventID: "next")

        await waitUntil(10) {
            self.state.currentMeeting?.id != firstID && self.state.isRecording
                && self.state.audioCaptureService?.isCapturing == true
        }
        // The old call is still up for a moment, then ends, then the next call starts.
        feedCall([Self.zoom])
        try? await Task.sleep(for: .seconds(1))
        feedCall([])
        try? await Task.sleep(for: .seconds(1))
        feedCall([Self.zoom])
        // Let any late restart or teardown from the old meeting land.
        try? await Task.sleep(for: .seconds(2))
        dumpLog("calendar handoff")

        let cap = try XCTUnwrap(state.audioCaptureService)
        XCTAssertNotEqual(state.currentMeeting?.id, firstID, describePipeline("after handoff"))
        let verificationContext = ModelContext(container)
        let savedFirst = try XCTUnwrap(verificationContext.fetch(FetchDescriptor<Meeting>()).first { $0.id == firstID })
        XCTAssertNotNil(savedFirst.endTime)
        XCTAssertEqual(savedFirst.segments.filter(\.isFinal).map(\.text), ["hello from the first call"])
        XCTAssertNil(state.persistenceIssue)
        XCTAssertEqual(state.currentMeeting?.calendarEventId, "next")
        XCTAssertTrue(state.isRecording, describePipeline("after handoff"))
        XCTAssertTrue(cap.isCapturing, describePipeline("after handoff"))
        XCTAssertTrue(cap.isMicActive, describePipeline("after handoff"))
        XCTAssertNotNil(cap.onAudioBuffer, describePipeline("after handoff"))
        XCTAssertFalse(cap.isSendSuspended, describePipeline("after handoff"))
    }

    func testEndAndStartUnscheduledLeavesCaptureLiveOnTheNewMeeting() async throws {
        try Self.requireMicrophone()
        XCTAssertTrue(state.startNewMeeting())
        await waitUntil { self.state.audioCaptureService?.isCapturing == true }
        let firstID = state.currentMeeting?.id
        state.liveSegments = [
            AppState.LiveSegment(id: UUID(), text: "hello from the first call", speaker: 0, timestamp: 1, isFinal: true)
        ]

        state.endAndStartNewMeeting()

        await waitUntil(10) {
            self.state.currentMeeting?.id != firstID && self.state.isRecording
                && self.state.audioCaptureService?.isCapturing == true
        }
        try? await Task.sleep(for: .seconds(2))
        dumpLog("unscheduled handoff")

        let cap = try XCTUnwrap(state.audioCaptureService)
        XCTAssertNotEqual(state.currentMeeting?.id, firstID, describePipeline("after handoff"))
        let verificationContext = ModelContext(container)
        let savedFirst = try XCTUnwrap(verificationContext.fetch(FetchDescriptor<Meeting>()).first { $0.id == firstID })
        XCTAssertNotNil(savedFirst.endTime)
        XCTAssertEqual(savedFirst.segments.filter(\.isFinal).map(\.text), ["hello from the first call"])
        XCTAssertNil(state.persistenceIssue)
        XCTAssertTrue(state.isRecording, describePipeline("after handoff"))
        XCTAssertTrue(cap.isCapturing, describePipeline("after handoff"))
        XCTAssertTrue(cap.isMicActive, describePipeline("after handoff"))
        XCTAssertNotNil(cap.onAudioBuffer, describePipeline("after handoff"))
        XCTAssertFalse(cap.isSendSuspended, describePipeline("after handoff"))
    }

    // MARK: - Mic engine stops on an output-device switch (the field bug)

    func testRecoveryDoesNotCallASilentCaptureHealthyJustBecauseTheSourcesAreActive() async throws {
        let service = AudioCaptureService(microphoneStart: {}, systemAudioStart: {})
        state.audioCaptureService = service
        state.isRecording = true
        try await service.startCapture(microphone: true, systemAudio: true)
        state.updateAudioRecoveryState()
        XCTAssertEqual(state.audioRecoveryState, .recovering)
        let now = CFAbsoluteTimeGetCurrent()
        service.deliverSystemPCM(Data([0, 0]), multichannel: true, at: now, callback: nil)
        state.updateAudioRecoveryState()
        XCTAssertEqual(state.audioRecoveryState, .recovering, "system-only output cannot hide the missing mic")
        var sample: Int16 = 0
        withUnsafePointer(to: &sample) {
            service.deliverMicrophonePCM($0, count: 1, multichannel: true, at: now, callback: nil)
        }
        state.updateAudioRecoveryState()
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(state.audioRecoveryState, .healthy, "silent buffers count; speaking is not required")
    }

    func testMicRestartRuleRestartsAStoppedEngineEvenWhenInputIsUnchanged() {
        XCTAssertFalse(AudioCaptureService.shouldRestartMicAfterConfigChange(hasMeaningfulInputChange: false, engineRunning: true))
        XCTAssertTrue(AudioCaptureService.shouldRestartMicAfterConfigChange(hasMeaningfulInputChange: false, engineRunning: false))
        XCTAssertTrue(AudioCaptureService.shouldRestartMicAfterConfigChange(hasMeaningfulInputChange: true, engineRunning: true))
    }

    func testMicStallRuleFiresOnlyForAnActiveWantedMicWithNoBuffers() {
        XCTAssertTrue(AudioCaptureService.shouldRecoverMicStall(
            expectsMicAudio: true, isMicActive: true, isRecoveryInProgress: false, bufferGap: 7, timeSinceLastRecovery: .infinity))
        XCTAssertFalse(AudioCaptureService.shouldRecoverMicStall(
            expectsMicAudio: true, isMicActive: true, isRecoveryInProgress: false, bufferGap: 3, timeSinceLastRecovery: .infinity),
            "ordinary buffer cadence is well under the gap")
        XCTAssertFalse(AudioCaptureService.shouldRecoverMicStall(
            expectsMicAudio: false, isMicActive: false, isRecoveryInProgress: false, bufferGap: 60, timeSinceLastRecovery: .infinity),
            "system-only capture has no mic to recover")
        XCTAssertFalse(AudioCaptureService.shouldRecoverMicStall(
            expectsMicAudio: true, isMicActive: true, isRecoveryInProgress: true, bufferGap: 60, timeSinceLastRecovery: .infinity),
            "a restart already under way must not be doubled")
        XCTAssertFalse(AudioCaptureService.shouldRecoverMicStall(
            expectsMicAudio: true, isMicActive: true, isRecoveryInProgress: false, bufferGap: 60, timeSinceLastRecovery: 5),
            "cooldown after a recovery")
    }

    // MARK: - System tap created during the permission prompt never carries audio

    func testSilentFromBirthTapRuleRebuildsOnlyATapThatNeverCarriedAudio() {
        func decide(
            nonSilent: Int = 0, callbacks: Int = 900, silence: CFAbsoluteTime = 11,
            sinceRestart: CFAbsoluteTime = .infinity, rebuilds: Int = 0,
            expects: Bool = true, active: Bool = true, recovering: Bool = false, suspended: Bool = false
        ) -> Bool {
            AudioCaptureService.shouldRebuildSilentFromBirthSystemTap(
                expectsSystemAudio: expects, isSystemAudioActive: active, isRecoveryInProgress: recovering,
                isSendSuspended: suspended, callbackCount: callbacks, nonSilentCallbacks: nonSilent,
                silenceDuration: silence, timeSinceLastRestart: sinceRestart, rebuildsSoFar: rebuilds)
        }
        XCTAssertTrue(decide(), "alive for 10 s, callbacks firing, not one non-silent buffer")
        XCTAssertFalse(decide(nonSilent: 1), "a tap that carried audio once belongs to the silent-stall detector")
        XCTAssertFalse(decide(callbacks: 10), "too few callbacks to call the tap alive")
        XCTAssertFalse(decide(silence: 5), "startup grace")
        XCTAssertFalse(decide(sinceRestart: 10, rebuilds: 1), "cooldown between the two rebuilds")
        XCTAssertTrue(decide(sinceRestart: 31, rebuilds: 1), "second attempt after the cooldown")
        XCTAssertFalse(decide(sinceRestart: 120, rebuilds: 2), "bounded: plain silence stops costing taps")
        XCTAssertFalse(decide(expects: false, active: false), "mic-only capture has no tap")
        XCTAssertFalse(decide(active: false), "a tap that failed to start is the retry path's job")
        XCTAssertFalse(decide(recovering: true), "a full restart already under way")
        XCTAssertFalse(decide(suspended: true), "ending grace is deliberate silence")
    }

    func testOnboardingMeterShowsOrdinarySpeechLevels() {
        XCTAssertEqual(OnboardingMicrophoneMeter.displayLevel(for: 0), 0)
        XCTAssertEqual(OnboardingMicrophoneMeter.displayLevel(for: 0.002), 0, "a quiet room rests at empty")
        XCTAssertLessThan(OnboardingMicrophoneMeter.displayLevel(for: 0.005), 0.1, "room noise barely shows")
        XCTAssertGreaterThan(OnboardingMicrophoneMeter.displayLevel(for: 0.02), 0.25, "quiet speech must visibly move the bar")
        XCTAssertGreaterThan(OnboardingMicrophoneMeter.displayLevel(for: 0.1), 0.5)
        XCTAssertEqual(OnboardingMicrophoneMeter.displayLevel(for: 1.5), 1)
        XCTAssertFalse(OnboardingMicrophoneMeter.hasSignal(0.005))
        XCTAssertTrue(OnboardingMicrophoneMeter.hasSignal(0.02))
    }

    /// Real HAL check for the silent-from-birth rebuild: a mic + system capture with nothing
    /// playing lets the 10 s rule fire, then the tap and its private aggregate device are
    /// destroyed and recreated. The mic engine must neither restart nor stop delivering.
    func testSilentFromBirthRebuildLeavesTheMicEngineAlone() async throws {
        // The logger is a 1000-entry ring; in the full suite it is already full, so
        // positions shift under us. Start empty and compare by timestamp, not index.
        DebugLogger.shared.clear()
        XCTAssertTrue(state.startNewMeeting())
        await waitUntil { (self.state.audioCaptureService?.micBufferCountForTesting ?? 0) > 5 }
        let cap = try XCTUnwrap(state.audioCaptureService)
        guard cap.isSystemAudioActive else { throw XCTSkip("no system audio tap in this test host") }
        let firedPrefix = "System tap has never carried audio"
        await waitUntil(16) { DebugLogger.shared.entries.contains { $0.message.hasPrefix(firedPrefix) } }
        guard let fired = DebugLogger.shared.entries.first(where: { $0.message.hasPrefix(firedPrefix) }) else {
            dumpLog("silent-from-birth rule did not fire")
            throw XCTSkip("the tap carried audio (something is playing on this Mac), so the rule did not fire")
        }
        await waitUntil(4) { DebugLogger.shared.entries.contains { $0.message == "System tap recovery complete" } }
        let countAfterRebuild = cap.micBufferCountForTesting
        try? await Task.sleep(for: .seconds(2))

        XCTAssertTrue(state.isRecording, describePipeline("after rebuild"))
        XCTAssertTrue(cap.isMicActive, describePipeline("after rebuild"))
        XCTAssertTrue(cap.isSystemAudioActive, describePipeline("after rebuild"))
        XCTAssertGreaterThan(cap.micBufferCountForTesting, countAfterRebuild, "mic buffers must keep arriving across the tap rebuild. " + describePipeline("after rebuild"))
        let afterRebuild = DebugLogger.shared.entries.filter { $0.timestamp >= fired.timestamp }
        XCTAssertTrue(afterRebuild.contains { $0.message == "System tap recovery complete" }, describePipeline("after rebuild"))
        let micDisturbed = afterRebuild.filter {
            $0.message.localizedCaseInsensitiveContains("configuration change")
                || $0.message.localizedCaseInsensitiveContains("mic restart")
                || $0.message.localizedCaseInsensitiveContains("engine restart")
        }
        XCTAssertTrue(micDisturbed.isEmpty, "rebuilding the tap must not touch the mic engine: \(micDisturbed.map(\.message))")
        dumpLog("silent-from-birth rebuild")
    }

    /// Real HAL reproduction: moving the default output device to another device object
    /// makes the input-only AVAudioEngine post a configuration change and stop, with the
    /// input device and format unchanged. Before the fix the mic stayed dead (every flag
    /// still true) until stop/resume. The default output is restored afterwards.
    func testMicKeepsDeliveringAfterTheDefaultOutputDeviceChanges() async throws {
        try Self.requireMicrophone()
        XCTAssertTrue(state.startNewMeeting())
        await waitUntil { (self.state.audioCaptureService?.micBufferCountForTesting ?? 0) > 5 }
        let cap = try XCTUnwrap(state.audioCaptureService)
        XCTAssertGreaterThan(cap.micBufferCountForTesting, 5, describePipeline("before output switch"))

        let originalOutput = try XCTUnwrap(Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice))
        let outputUID = try XCTUnwrap(Self.deviceUID(originalOutput))
        var aggregate: AudioDeviceID = 0
        let desc: [String: Any] = [
            kAudioAggregateDeviceUIDKey as String: "miniti-test-output-switch",
            kAudioAggregateDeviceNameKey as String: "miniti test output",
            kAudioAggregateDeviceSubDeviceListKey as String: [[kAudioSubDeviceUIDKey as String: outputUID]],
        ]
        guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggregate) == noErr else {
            throw XCTSkip("could not create an aggregate output device on this Mac")
        }
        defer {
            Self.setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, originalOutput)
            AudioHardwareDestroyAggregateDevice(aggregate)
        }

        Self.setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, aggregate)
        // Coalesce delay (0.25 s) + engine rebuild; give the stall watchdog a tick as well.
        try? await Task.sleep(for: .seconds(2))
        let countAfterSwitch = cap.micBufferCountForTesting
        try? await Task.sleep(for: .seconds(3))
        let countLater = cap.micBufferCountForTesting

        XCTAssertTrue(state.isRecording, describePipeline("after output switch"))
        XCTAssertTrue(cap.isMicActive, describePipeline("after output switch"))
        XCTAssertGreaterThan(countLater, countAfterSwitch, "mic buffers must keep arriving after the output device changed. " + describePipeline("after output switch"))
        dumpLog("output switch")
    }

    /// These tests run the real capture pipeline, so they need a microphone the host may read.
    /// GitHub's runner lists a default input device that delivers nothing and never grants the
    /// unsigned host microphone access, so the pipeline reports `mic=false capturing=false`
    /// there (2026-10-19 and 2026-10-21 runs). Authorization is the reliable signal.
    private static func requireMicrophone() throws {
        guard let input = defaultDevice(kAudioHardwarePropertyDefaultInputDevice), input != kAudioObjectUnknown else {
            throw XCTSkip("no microphone on this Mac")
        }
        guard TestHost.microphoneIsAuthorized else {
            throw XCTSkip("this host has no microphone access")
        }
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    private static func setDefaultDevice(_ selector: AudioObjectPropertySelector, _ id: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = id
        _ = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
    }

    private static func deviceUID(_ id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var ref: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = withUnsafeMutablePointer(to: &ref) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, UnsafeMutableRawPointer(ptr))
        }
        return err == noErr ? (ref as String?) : nil
    }
}
#endif

#if os(macOS)
/// Charlie's 2026-10-27 report: the AirPods mic never started, so the system ring
/// never drained. Exercise the production PCM delivery and startup paths without HAL.
@MainActor
final class CaptureFailureTests: XCTestCase {
    private final class Packets: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [[Int16]] = []
        func append(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            values.append(data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) })
        }
        var all: [[Int16]] { lock.lock(); defer { lock.unlock() }; return values }
    }

    private func pcm(_ samples: [Int16]) -> Data {
        samples.withUnsafeBytes { Data($0) }
    }

    private func mic(_ service: AudioCaptureService, _ samples: [Int16], at time: Double, into packets: Packets, stereo: Bool = true) {
        samples.withUnsafeBufferPointer {
            service.deliverMicrophonePCM($0.baseAddress!, count: $0.count, multichannel: stereo, at: time, callback: { packets.append($0) })
        }
    }

    func testFailedMicDoesNotHoldSystemAudioAndRecoveryKeepsTheStereoChannels() {
        let service = AudioCaptureService(microphoneStart: {}, systemAudioStart: {})
        let packets = Packets()
        service.deliverSystemPCM(pcm([101, 102]), multichannel: true, at: 100, callback: { packets.append($0) })
        XCTAssertEqual(packets.all, [[0, 101, 0, 102]])
        XCTAssertFalse(service.hasRecentCaptureBuffers(microphone: true, systemAudio: true, at: 100))
        mic(service, [11, 12], at: 100.1, into: packets)
        XCTAssertEqual(packets.all.last, [11, 0, 12, 0], "do not replay already-delivered system audio")
        service.deliverSystemPCM(pcm([201, 202]), multichannel: true, at: 100.2, callback: { packets.append($0) })
        XCTAssertEqual(packets.all.count, 2, "healthy mic clocks the combined stream")
        mic(service, [21, 22], at: 100.3, into: packets)
        XCTAssertEqual(packets.all.last, [21, 201, 22, 202])
        XCTAssertTrue(service.hasRecentCaptureBuffers(microphone: true, systemAudio: true, at: 100.3))
        // Mic callbacks disappear again, even though its engine might still say active.
        service.deliverSystemPCM(pcm([301, 302]), multichannel: true, at: 103, callback: { packets.append($0) })
        XCTAssertEqual(packets.all.last, [0, 301, 0, 302])
        XCTAssertFalse(service.hasRecentCaptureBuffers(microphone: true, systemAudio: true, at: 103))
        mic(service, [31, 32], at: 103.1, into: packets)
        XCTAssertEqual(packets.all.last, [31, 0, 32, 0])
    }

    func testFallbackRespectsSendingSuspensionAndMonoSessionsStayMono() {
        let service = AudioCaptureService(microphoneStart: {}, systemAudioStart: {})
        let packets = Packets()
        service.suspendSending()
        service.deliverSystemPCM(pcm([101, 102]), multichannel: true, at: 100, callback: { packets.append($0) })
        mic(service, [11, 12], at: 100, into: packets)
        XCTAssertTrue(packets.all.isEmpty)
        service.resumeSending()
        service.deliverSystemPCM(pcm([201, 202]), multichannel: false, at: 103, callback: { packets.append($0) })
        mic(service, [21, 22], at: 103, into: packets, stereo: false)
        XCTAssertEqual(packets.all, [[201, 202], [21, 22]])
    }

    func testSilenceCountsAsHealthyBuffersAndStopClearsTheirHistory() {
        let service = AudioCaptureService(microphoneStart: {}, systemAudioStart: {})
        let packets = Packets()
        mic(service, [0, 0], at: 100, into: packets)
        service.deliverSystemPCM(pcm([0, 0]), multichannel: true, at: 100, callback: { packets.append($0) })
        XCTAssertTrue(service.hasRecentCaptureBuffers(microphone: true, systemAudio: true, at: 100))
        service.stopCapture()
        XCTAssertFalse(service.hasRecentCaptureBuffers(microphone: true, systemAudio: true, at: 100))
    }

    func testInitialFormatFailureRetriesTheMicWithoutStoppingSystemCapture() async throws {
        var attempts = 0
        var systemStarts = 0
        let service = AudioCaptureService(microphoneStart: {
            attempts += 1
            if attempts == 1 { throw NSError(domain: "com.apple.coreaudio.avfaudio", code: -10868) }
        }, systemAudioStart: { systemStarts += 1 })
        defer { service.stopCapture() }
        try await service.startCapture(microphone: true, systemAudio: true)
        XCTAssertTrue(service.isCapturing)
        XCTAssertFalse(service.isMicActive)
        XCTAssertNotNil(service.microphoneCaptureIssue)
        let deadline = Date().addingTimeInterval(2)
        while !service.isMicActive, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(service.isMicActive)
        XCTAssertTrue(service.isSystemAudioActive)
        XCTAssertNil(service.microphoneCaptureIssue)
        XCTAssertFalse(service.hasRecentCaptureBuffers(microphone: true, systemAudio: true), "successful engine startup alone is not recovery")
        XCTAssertEqual(systemStarts, 1, "mic recovery must not interrupt the healthy system tap")
    }

    func testStopCancelsTheInitialMicRetry() async throws {
        var attempts = 0
        let service = AudioCaptureService(microphoneStart: {
            attempts += 1
            throw NSError(domain: "com.apple.coreaudio.avfaudio", code: -10868)
        }, systemAudioStart: {})
        try await service.startCapture(microphone: true, systemAudio: true)
        service.stopCapture()
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(service.isCapturing)
        XCTAssertNil(service.microphoneCaptureIssue)
    }

    func testMicRetriesAreBoundedAndPermissionDenialDoesNotRetry() async throws {
        var attempts = 0
        let service = AudioCaptureService(microphoneStart: {
            attempts += 1
            throw NSError(domain: "com.apple.coreaudio.avfaudio", code: -10868)
        }, systemAudioStart: {})
        defer { service.stopCapture() }
        try await service.startCapture(microphone: true, systemAudio: true)
        try await Task.sleep(for: .seconds(6))
        XCTAssertEqual(attempts, 4, "one start plus three bounded retries")
        XCTAssertTrue(service.microphoneCaptureIssue?.contains("built-in microphone") == true)
        XCTAssertTrue(service.isSystemAudioActive)
        var deniedAttempts = 0
        let denied = AudioCaptureService(microphoneStart: {
            deniedAttempts += 1
            throw AudioCaptureError.microphonePermissionDenied
        }, systemAudioStart: {})
        defer { denied.stopCapture() }
        try await denied.startCapture(microphone: true, systemAudio: true)
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertEqual(deniedAttempts, 1)
        XCTAssertTrue(denied.microphoneCaptureIssue?.contains("Microphone access is off") == true)
    }
}
#endif
