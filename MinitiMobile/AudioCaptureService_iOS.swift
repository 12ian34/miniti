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
    private var pendingMicRestartTask: Task<Void, Never>?
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
        print("Microphone capture started (iOS)")
    }
    
    func stopCapture() {
        stopMicrophoneCapture()
        isCapturing = false
        isMicActive = false
        isSystemAudioActive = false
    }
    
    private func stopCaptureAsync() async {
        stopMicrophoneCapture()
        isCapturing = false
        isMicActive = false
        isSystemAudioActive = false
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
        
        let route = session.currentRoute
        let inputName = route.inputs.first?.portName ?? "none"
        let inputType = route.inputs.first?.portType.rawValue ?? "none"
        DebugLogger.shared.log(.audio, "iOS audio route: input=\(inputName) (\(inputType)), sampleRate=\(session.sampleRate)Hz")
        
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
            Task { @MainActor in
                self?.handleRouteChange(reason: reason)
            }
        }
    }
    
    private func handleEngineConfigurationChange() {
        scheduleMicRestart(reason: "engine configuration changed")
    }
    
    private func handleRouteChange(reason: UInt?) {
        guard let reason, let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }
        
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputName = route.inputs.first?.portName ?? "none"
        let inputType = route.inputs.first?.portType.rawValue ?? "none"
        DebugLogger.shared.log(.audio, "Audio route changed (\(changeReason.debugLabel)): input=\(inputName) (\(inputType))")
        
        guard isCapturing, isMicActive else { return }
        let newIdentity = currentInputIdentity()
        guard !newIdentity.isEmpty, newIdentity != activeInputIdentity else { return }
        activeInputIdentity = newIdentity
        scheduleMicRestart(reason: "input route changed")
    }
    
    private func scheduleMicRestart(reason: String) {
        guard isCapturing, isMicActive else { return }
        pendingMicRestartTask?.cancel()
        pendingMicRestartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pendingMicRestartTask = nil }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard self.isCapturing, self.isMicActive else { return }
            guard !self.isRestartingMicAfterRouteChange else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastMicRestartAt > 0.5 else { return }
            self.lastMicRestartAt = now
            self.isRestartingMicAfterRouteChange = true
            defer { self.isRestartingMicAfterRouteChange = false }
            
            let session = AVAudioSession.sharedInstance()
            let route = session.currentRoute
            let inputName = route.inputs.first?.portName ?? "none"
            DebugLogger.shared.log(.audio, "Restarting iOS mic tap (\(reason)). Input: \(inputName), \(session.sampleRate)Hz")
            
            self.stopMicrophoneCapture()
            do {
                try await self.startMicrophoneCapture(skipPermissionCheck: true)
                DebugLogger.shared.log(.audio, "iOS mic capture restart complete")
            } catch {
                self.isMicActive = false
                DebugLogger.shared.log(.audio, "iOS mic capture restart FAILED: \(error.localizedDescription)")
            }
        }
    }
    
    private func currentInputIdentity() -> String {
        let session = AVAudioSession.sharedInstance()
        let input = session.currentRoute.inputs.first
        let uid = input?.uid ?? "unknown"
        let port = input?.portType.rawValue ?? "none"
        return "\(uid)|\(port)"
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
