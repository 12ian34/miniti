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
    
    private func startMicrophoneCapture() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        
        let route = session.currentRoute
        let inputName = route.inputs.first?.portName ?? "none"
        let inputType = route.inputs.first?.portType.rawValue ?? "none"
        DebugLogger.shared.log(.audio, "iOS audio route: input=\(inputName) (\(inputType)), sampleRate=\(session.sampleRate)Hz")
        
        let granted = await requestMicrophonePermission()
        guard granted else {
            DebugLogger.shared.log(.audio, "Mic permission DENIED")
            throw AudioCaptureError.microphonePermissionDenied
        }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        DebugLogger.shared.log(.audio, "Mic input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else { throw AudioCaptureError.formatCreationFailed }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            DebugLogger.shared.log(.audio, "FAILED to create converter: \(inputFormat.sampleRate)Hz → \(targetSampleRate)Hz")
            throw AudioCaptureError.converterCreationFailed
        }
        
        DebugLogger.shared.log(.audio, "Mic converter ready: \(inputFormat.sampleRate)Hz → \(targetSampleRate)Hz")
        micBufferCount = 0
        lastMicHeartbeat = CFAbsoluteTimeGetCurrent()
        
        let onBuffer = onAudioBuffer
        let targetRate = targetSampleRate
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat, targetRate: targetRate, callback: onBuffer)
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
        guard isCapturing, isMicActive else { return }
        guard let audioEngine else { return }
        
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        let inputName = route.inputs.first?.portName ?? "none"
        DebugLogger.shared.log(.audio, "Engine config changed — restarting mic tap. Input: \(inputName), \(session.sampleRate)Hz")
        
        audioEngine.inputNode.removeTap(onBus: 0)
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            DebugLogger.shared.log(.audio, "INVALID new format — mic capture suspended")
            return
        }
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else { return }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            DebugLogger.shared.log(.audio, "FAILED to create converter for new format")
            return
        }
        
        let onBuffer = onAudioBuffer
        let targetRate = targetSampleRate
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat, targetRate: targetRate, callback: onBuffer)
        }
        
        do {
            try audioEngine.start()
            DebugLogger.shared.log(.audio, "Mic capture restarted with \(inputFormat.sampleRate)Hz format")
        } catch {
            DebugLogger.shared.log(.audio, "FAILED to restart engine: \(error.localizedDescription)")
        }
    }
    
    private func handleRouteChange(reason: UInt?) {
        guard let reason, let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }
        
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputName = route.inputs.first?.portName ?? "none"
        let inputType = route.inputs.first?.portType.rawValue ?? "none"
        DebugLogger.shared.log(.audio, "Audio route changed (\(changeReason.debugLabel)): input=\(inputName) (\(inputType))")
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
