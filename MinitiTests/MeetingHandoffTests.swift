import XCTest
import CoreAudio
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
    private static let touchedDefaults = [
        "appMode", "deepgramApiKey", "acceptedTermsVersion", "declinedTermsVersion", "hasAcceptedTerms",
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
        state = AppState()
        state.appMode = .byok
        state.deepgramApiKey = "test-key-not-real"
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
        state.audioCaptureService?.stopCapture()
        state = nil
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
        XCTAssertTrue(state.isRecording, describePipeline("after handoff"))
        XCTAssertTrue(cap.isCapturing, describePipeline("after handoff"))
        XCTAssertTrue(cap.isMicActive, describePipeline("after handoff"))
        XCTAssertNotNil(cap.onAudioBuffer, describePipeline("after handoff"))
        XCTAssertFalse(cap.isSendSuspended, describePipeline("after handoff"))
    }

    // MARK: - Mic engine stops on an output-device switch (the field bug)

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
