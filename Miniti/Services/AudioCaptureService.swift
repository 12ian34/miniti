import Foundation
@preconcurrency import AVFoundation
import ScreenCaptureKit

@MainActor
final class AudioCaptureService: NSObject, ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var screenCaptureStream: SCStream?
    private var screenCaptureDelegate: ScreenCaptureDelegate?
    
    nonisolated(unsafe) var onAudioBuffer: (@Sendable (Data) -> Void)?
    
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1
    
    @Published var isCapturing = false
    @Published var microphoneLevel: Float = 0
    @Published var systemAudioLevel: Float = 0
    
    override init() {
        super.init()
    }
    
    func startCapture(microphone: Bool, systemAudio: Bool) async throws {
        var capturedAny = false
        
        if microphone {
            do {
                try await startMicrophoneCapture()
                capturedAny = true
                print("Microphone capture started")
            } catch {
                print("Microphone capture failed: \(error.localizedDescription)")
                if !systemAudio {
                    throw error
                }
            }
        }
        
        if systemAudio {
            do {
                try await startSystemAudioCapture()
                capturedAny = true
                print("System audio capture started")
            } catch {
                print("System audio capture failed: \(error.localizedDescription)")
                print("Tip: Grant Screen Recording permission to Xcode in System Settings")
                // Continue with just microphone if available
                if !capturedAny {
                    throw error
                }
            }
        }
        
        isCapturing = capturedAny
    }
    
    func stopCapture() {
        stopMicrophoneCapture()
        stopSystemAudioCapture()
        isCapturing = false
    }
    
    // MARK: - Microphone Capture
    
    private func startMicrophoneCapture() async throws {
        // Request microphone permission
        let granted = await requestMicrophonePermission()
        guard granted else {
            throw AudioCaptureError.microphonePermissionDenied
        }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create format for Deepgram (16kHz mono PCM16)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        
        // Install tap - runs on audio thread
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
    }
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - System Audio Capture
    
    private func startSystemAudioCapture() async throws {
        // Get shareable content for audio-only capture
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        
        // Create a filter for audio-only capture (no specific windows)
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayFound
        }
        
        // Use display filter but we'll configure for audio-only
        let filter = SCContentFilter(display: display, excludingWindows: content.windows)
        
        // Configure stream for audio only - no video capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(targetSampleRate)
        config.channelCount = Int(targetChannels)
        
        // Disable video capture entirely for audio-only permission
        config.width = 1
        config.height = 1
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false
        
        let callback = onAudioBuffer
        screenCaptureDelegate = ScreenCaptureDelegate { data in
            callback?(data)
        }
        
        screenCaptureStream = SCStream(filter: filter, configuration: config, delegate: nil)
        
        guard let stream = screenCaptureStream, let delegate = screenCaptureDelegate else { return }
        
        // Only add audio output, no video output
        try stream.addStreamOutput(delegate, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        
        do {
            try await stream.startCapture()
        } catch {
            print("System audio capture failed: \(error)")
            print("Please grant 'System Audio Recording' permission in System Settings > Privacy & Security")
            throw AudioCaptureError.screenCapturePermissionDenied
        }
    }
    
    private func stopSystemAudioCapture() {
        Task {
            try? await screenCaptureStream?.stopCapture()
            screenCaptureStream = nil
            screenCaptureDelegate = nil
        }
    }
    
    // MARK: - Audio Processing
    
    nonisolated private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat, targetRate: Double, callback: (@Sendable (Data) -> Void)?) {
        let frameCount = AVAudioFrameCount(targetRate * Double(buffer.frameLength) / buffer.format.sampleRate)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard status != .error, error == nil else {
            return
        }
        
        // Convert to Data
        guard let channelData = outputBuffer.int16ChannelData else { return }
        let data = Data(bytes: channelData[0], count: Int(outputBuffer.frameLength) * 2)
        
        // Update level meter
        let level = calculateLevel(buffer)
        Task { @MainActor [weak self] in
            self?.microphoneLevel = level
        }
        
        callback?(data)
    }
    
    nonisolated private func calculateLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        
        for i in 0..<frames {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frames))
        return min(1.0, rms * 5) // Scale for display
    }
}

// MARK: - Screen Capture Delegate

private final class ScreenCaptureDelegate: NSObject, SCStreamOutput, @unchecked Sendable {
    let onAudioData: @Sendable (Data) -> Void
    
    init(onAudioData: @escaping @Sendable (Data) -> Void) {
        self.onAudioData = onAudioData
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == kCMBlockBufferNoErr, let dataPointer else { return }
        
        let data = Data(bytes: dataPointer, count: length)
        onAudioData(data)
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case screenCapturePermissionDenied
    case noDisplayFound
    case formatCreationFailed
    case converterCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Please enable in System Settings."
        case .screenCapturePermissionDenied:
            return "Screen recording permission is required for system audio. Please enable in System Settings."
        case .noDisplayFound:
            return "No display found for screen capture."
        case .formatCreationFailed:
            return "Failed to create audio format."
        case .converterCreationFailed:
            return "Failed to create audio converter."
        }
    }
}
