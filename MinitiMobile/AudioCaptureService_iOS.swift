import Foundation
@preconcurrency import AVFoundation
import Accelerate

/// iOS version of AudioCaptureService — mic-only capture via AVAudioEngine.
/// Same public interface as the macOS version so AppState compiles against either.
@MainActor
final class AudioCaptureService: NSObject, ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    
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
        
        // iOS: ignore systemAudio parameter (not available on iOS)
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
    
    private func startMicrophoneCapture() async throws {
        // Configure AVAudioSession (required on iOS, not needed on macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        
        let granted = await requestMicrophonePermission()
        guard granted else { throw AudioCaptureError.microphonePermissionDenied }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else { throw AudioCaptureError.formatCreationFailed }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        
        let onBuffer = onAudioBuffer
        let targetRate = targetSampleRate
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat, targetRate: targetRate, callback: onBuffer)
        }
        
        try audioEngine.start()
    }
    
    private func stopMicrophoneCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        // Deactivate audio session
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
