import Foundation
@preconcurrency import AVFoundation
import Accelerate

/// iOS version of AudioCaptureService — mic-only capture via AVAudioEngine.
/// Same public interface as the macOS version so AppState compiles against either.
@MainActor
final class AudioCaptureService: NSObject, ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var engineConfigObserver: Any?
    private var routeChangeObserver: Any?
    private var interruptionObserver: Any?
    private var pendingMicRestartTask: Task<Void, Never>?
    private var pendingMicRetryTask: Task<Void, Never>?
    private var micRetryAttempt = 0
    private let maxMicRetryAttempts = 3
    private var isRestartingMicAfterRouteChange = false
    private var lastMicRestartAt: CFAbsoluteTime = 0
    private var activeInputIdentity: String = ""
    
    #if compiler(>=6.2)
    private let bluetoothCallProfileOption: AVAudioSession.CategoryOptions = .allowBluetoothHFP
    #else
    private let bluetoothCallProfileOption: AVAudioSession.CategoryOptions = .allowBluetooth
    #endif
    
    nonisolated(unsafe) var onAudioBuffer: (@Sendable (Data) -> Void)?
    
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1
    
    @Published var isCapturing = false
    @Published var microphoneLevel: Float = 0
    @Published var systemAudioLevel: Float = 0  // Always 0 on iOS (no system audio)
    @Published var isMicActive = false
    @Published var isSystemAudioActive = false  // Always false on iOS
    
    // MARK: - Source Dominance (stubs for API compatibility)
    
    enum AudioSource { case mic, system, unknown }
    
    /// On iOS, always returns `.mic` since there's no system audio.
    nonisolated func dominantSource(from startTime: Double, to endTime: Double) -> AudioSource {
        return .mic
    }
    
    /// No-op on iOS.
    func resetSourceTracking() {}
    
    // MARK: - Capture
    
    func startCapture(microphone: Bool, systemAudio: Bool) async throws {
        await stopCaptureAsync()
        
        DebugLogger.shared.log(.audio, "startCapture(mic=\(microphone)) [iOS]")
        guard microphone else { return }
        
        try await startMicrophoneCapture()
        isCapturing = true
        isMicActive = true
    }
    
    func stopCapture() {
        cancelPendingMicRecovery()
        stopMicrophoneCapture()
        isCapturing = false
        isMicActive = false
        isSystemAudioActive = false
    }
    
    private func stopCaptureAsync() async {
        cancelPendingMicRecovery()
        stopMicrophoneCapture()
        isCapturing = false
        isMicActive = false
        isSystemAudioActive = false
    }
    
    private func cancelPendingMicRecovery() {
        pendingMicRetryTask?.cancel()
        pendingMicRetryTask = nil
        micRetryAttempt = 0
    }
    
    // MARK: - Microphone Capture
    
    nonisolated(unsafe) private var micBufferCount: Int = 0
    nonisolated(unsafe) private var lastMicHeartbeat: CFAbsoluteTime = 0
    
    private func startMicrophoneCapture(skipPermissionCheck: Bool = false) async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, bluetoothCallProfileOption]
        )
        try session.setActive(true)
        
        DebugLogger.shared.log(.audio, "iOS audio session: \(sessionRouteSummary(session))")
        
        if !skipPermissionCheck {
            let granted = await requestMicrophonePermission()
            guard granted else {
                DebugLogger.shared.log(.audio, "Mic permission DENIED")
                throw AudioCaptureError.microphonePermissionDenied
            }
        }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        activeInputIdentity = currentInputIdentity()
        
        DebugLogger.shared.log(.audio, "Mic input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else { throw AudioCaptureError.formatCreationFailed }
        
        DebugLogger.shared.log(.audio, "Mic converter armed (dynamic input format) → \(targetSampleRate)Hz")
        micBufferCount = 0
        lastMicHeartbeat = CFAbsoluteTimeGetCurrent()
        
        let onBuffer = onAudioBuffer
        let targetRate = targetSampleRate
        var activeConverter: AVAudioConverter?
        var activeInputSampleRate: Double = 0
        var activeInputChannels: AVAudioChannelCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            let inFormat = buffer.format
            if activeConverter == nil ||
                abs(activeInputSampleRate - inFormat.sampleRate) > 0.001 ||
                activeInputChannels != inFormat.channelCount {
                guard let newConverter = AVAudioConverter(from: inFormat, to: outputFormat) else {
                    DebugLogger.shared.log(.audio, "FAILED to create mic converter in callback: \(inFormat.sampleRate)Hz, \(inFormat.channelCount)ch → \(targetRate)Hz")
                    return
                }
                activeConverter = newConverter
                activeInputSampleRate = inFormat.sampleRate
                activeInputChannels = inFormat.channelCount
                DebugLogger.shared.log(.audio, "Mic converter ready: \(inFormat.sampleRate)Hz, \(inFormat.channelCount)ch → \(targetRate)Hz")
            }
            
            guard let converter = activeConverter else { return }
            self.processAudioBuffer(
                buffer,
                converter: converter,
                outputFormat: outputFormat,
                targetRate: targetRate,
                callback: onBuffer
            )
        }
        
        try audioEngine.start()
        DebugLogger.shared.log(.audio, "Mic AVAudioEngine started [iOS]")
        
        // Handle audio hardware changes (Bluetooth codec switch, headphones plugged in, etc.)
        if let observer = engineConfigObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleEngineConfigurationChange()
            }
        }
        
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let previousRouteSummary = Self.routeSummary(previousRoute)
            Task { @MainActor in
                self?.handleRouteChange(reason: reason, previousRouteSummary: previousRouteSummary)
            }
        }
        
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(type: type)
            }
        }
    }
    
    private func handleEngineConfigurationChange() {
        scheduleMicRestart(reason: "engine configuration changed")
    }
    
    /// Phone calls, FaceTime, Siri, and alarms suspend the engine. Nothing restarts it for us, so
    /// without this the rest of the meeting records silence.
    private func handleInterruption(type: UInt?) {
        guard let type, let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch interruption {
        case .began:
            DebugLogger.shared.log(.audio, "iOS audio session interrupted — mic suspended")
            isMicActive = false
        case .ended:
            guard isCapturing else { return }
            DebugLogger.shared.log(.audio, "iOS audio session interruption ended — restarting mic")
            // Restart regardless of `shouldResume`: that hint is advisory, and a recorder that
            // never comes back is worse than one that retries and fails loudly.
            scheduleMicRestart(reason: "interruption ended")
        @unknown default:
            break
        }
    }
    
    private func handleRouteChange(reason: UInt?, previousRouteSummary: String) {
        guard let reason, let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }
        
        let session = AVAudioSession.sharedInstance()
        DebugLogger.shared.log(.audio, "Audio route changed (\(changeReason.debugLabel)): previous=[\(previousRouteSummary)], current=\(sessionRouteSummary(session))")
        
        guard isCapturing else { return }
        // A dead mic still needs recovering, so don't gate on `isMicActive` here.
        guard isMicActive else {
            scheduleMicRestart(reason: "route changed while mic inactive")
            return
        }
        let newIdentity = currentInputIdentity()
        guard !newIdentity.isEmpty, newIdentity != activeInputIdentity else { return }
        activeInputIdentity = newIdentity
        scheduleMicRestart(reason: "input route changed")
    }
    
    private func scheduleMicRestart(reason: String) {
        guard isCapturing else { return }
        pendingMicRestartTask?.cancel()
        pendingMicRestartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pendingMicRestartTask = nil }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard self.isCapturing else { return }
            guard !self.isRestartingMicAfterRouteChange else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastMicRestartAt > 0.5 else { return }
            self.lastMicRestartAt = now
            // A fresh trigger (interruption ended, route changed, engine reconfigured) earns a
            // fresh ladder — otherwise an exhausted counter from an earlier failure would make
            // `scheduleMicRestartRetry` give up immediately and leave the mic dead.
            self.pendingMicRetryTask?.cancel()
            self.pendingMicRetryTask = nil
            self.micRetryAttempt = 0
            await self.restartMicrophone(reason: reason)
        }
    }
    
    /// Tear down and re-arm the mic tap. On failure, hands off to the bounded retry ladder —
    /// otherwise a single failed restart leaves the mic dead for the rest of the meeting.
    private func restartMicrophone(reason: String) async {
        guard !isRestartingMicAfterRouteChange else { return }
        isRestartingMicAfterRouteChange = true
        defer { isRestartingMicAfterRouteChange = false }
        
        let session = AVAudioSession.sharedInstance()
        DebugLogger.shared.log(.audio, "Restarting iOS mic tap (\(reason)): \(sessionRouteSummary(session))")
        
        stopMicrophoneCapture()
        do {
            try await startMicrophoneCapture(skipPermissionCheck: true)
            isMicActive = true
            micRetryAttempt = 0
            DebugLogger.shared.log(.audio, "iOS mic capture restart complete")
        } catch {
            isMicActive = false
            DebugLogger.shared.log(.audio, "iOS mic capture restart FAILED: \(error.localizedDescription)")
            scheduleMicRestartRetry(reason: "restart failed (\(reason))")
        }
    }
    
    private func scheduleMicRestartRetry(reason: String) {
        guard isCapturing else { return }
        guard pendingMicRetryTask == nil else { return }
        guard micRetryAttempt < maxMicRetryAttempts else {
            DebugLogger.shared.log(
                .audio,
                "iOS mic auto-retry exhausted (\(micRetryAttempt) attempts), reason=\(reason)"
            )
            return
        }
        
        micRetryAttempt += 1
        let attempt = micRetryAttempt
        let delayNanos: UInt64 = [500_000_000, 1_500_000_000, 3_000_000_000][min(attempt - 1, 2)]
        DebugLogger.shared.log(
            .audio,
            "Scheduling iOS mic restart retry \(attempt)/\(maxMicRetryAttempts) in \(String(format: "%.1f", Double(delayNanos) / 1_000_000_000))s (\(reason))"
        )
        
        pendingMicRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delayNanos)
            self.pendingMicRetryTask = nil
            guard !Task.isCancelled, self.isCapturing else { return }
            guard !self.isMicActive else {
                self.micRetryAttempt = 0
                return
            }
            self.lastMicRestartAt = CFAbsoluteTimeGetCurrent()
            await self.restartMicrophone(reason: "retry \(attempt)/\(self.maxMicRetryAttempts)")
        }
    }
    
    private func currentInputIdentity() -> String {
        let session = AVAudioSession.sharedInstance()
        let input = session.currentRoute.inputs.first
        let uid = input?.uid ?? "unknown"
        let port = input?.portType.rawValue ?? "none"
        return "\(uid)|\(port)"
    }

    private func sessionRouteSummary(_ session: AVAudioSession) -> String {
        let inputSummary = Self.routePortSummary(session.currentRoute.inputs)
        let outputSummary = Self.routePortSummary(session.currentRoute.outputs)
        return "category=\(session.category.rawValue), mode=\(session.mode.rawValue), options=0x\(String(session.categoryOptions.rawValue, radix: 16)), sampleRate=\(Int(session.sampleRate))Hz, ioBuffer=\(String(format: "%.4f", session.ioBufferDuration))s, input=[\(inputSummary)], output=[\(outputSummary)]"
    }

    nonisolated private static func routePortSummary(_ ports: [AVAudioSessionPortDescription]) -> String {
        guard !ports.isEmpty else { return "none" }
        return ports.map { port in
            "\(port.portName) (\(port.portType.rawValue), uid:\(port.uid), channels:\(port.channels?.count ?? 0))"
        }.joined(separator: "; ")
    }

    nonisolated private static func routeSummary(_ route: AVAudioSessionRouteDescription?) -> String {
        guard let route else { return "unknown" }
        return "input=[\(routePortSummary(route.inputs))], output=[\(routePortSummary(route.outputs))]"
    }
    
    private func stopMicrophoneCapture() {
        if let observer = engineConfigObserver {
            NotificationCenter.default.removeObserver(observer)
            engineConfigObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        pendingMicRestartTask?.cancel()
        pendingMicRestartTask = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    private func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
    
    // MARK: - Audio Processing (vDSP accelerated)
    
    nonisolated(unsafe) private var lastMicLevelUpdate: CFAbsoluteTime = 0
    
    nonisolated private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat, targetRate: Double, callback: (@Sendable (Data) -> Void)?) {
        let frameCount = AVAudioFrameCount(targetRate * Double(buffer.frameLength) / buffer.format.sampleRate)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else { return }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { return }
        guard let channelData = outputBuffer.int16ChannelData else { return }
        
        let micSamples = Int(outputBuffer.frameLength)
        let micPtr = channelData[0]
        
        // Update mic level with vDSP (throttled to ~20Hz)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastMicLevelUpdate > 0.05 {
            lastMicLevelUpdate = now
            let level = calculateLevelVDSP(buffer)
            Task { @MainActor [weak self] in
                self?.microphoneLevel = level
            }
        }
        
        micBufferCount += 1
        if now - lastMicHeartbeat > 10.0 {
            lastMicHeartbeat = now
            let level = calculateLevelVDSP(buffer)
            DebugLogger.shared.log(.audio, "Mic heartbeat: \(micBufferCount) buffers, level=\(String(format: "%.5f", level)), frames=\(micSamples)")
        }
        
        // Send mic-only data to callback
        let data = Data(bytes: micPtr, count: micSamples * 2)
        callback?(data)
    }
    
    /// RMS level calculation using vDSP (vectorized)
    nonisolated private func calculateLevelVDSP(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        
        var meanSquare: Float = 0
        vDSP_measqv(channelData[0], 1, &meanSquare, vDSP_Length(frames))
        return min(1.0, sqrt(meanSquare))
    }
}

// MARK: - Route Change Reason Labels

extension AVAudioSession.RouteChangeReason {
    var debugLabel: String {
        switch self {
        case .newDeviceAvailable: return "new device"
        case .oldDeviceUnavailable: return "device removed"
        case .categoryChange: return "category change"
        case .override: return "override"
        case .wakeFromSleep: return "wake"
        case .noSuitableRouteForCategory: return "no route"
        case .routeConfigurationChange: return "config change"
        default: return "reason \(rawValue)"
        }
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case systemAudioPermissionDenied
    case systemAudioSetupFailed
    case formatCreationFailed
    case converterCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Please enable in Settings."
        case .systemAudioPermissionDenied:
            return "System audio is not available on iOS."
        case .systemAudioSetupFailed:
            return "System audio is not available on iOS."
        case .formatCreationFailed:
            return "Failed to create audio format."
        case .converterCreationFailed:
            return "Failed to create audio converter."
        }
    }
}
