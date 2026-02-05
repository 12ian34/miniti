import Foundation
@preconcurrency import AVFoundation
import ScreenCaptureKit
import Accelerate

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
    @Published var isMicActive = false
    @Published var isSystemAudioActive = false
    
    // MARK: - Ring Buffer for Audio Mixing
    // System audio is buffered and mixed into the mic stream so Deepgram
    // receives a single coherent audio stream (required for diarization).
    // Pre-allocated Int16 ring buffer avoids Data allocations in the hot path.
    
    private let ringCapacity = 3200  // ~200ms at 16kHz mono (samples, not bytes)
    nonisolated(unsafe) private var ringBuffer: UnsafeMutablePointer<Int16>!
    nonisolated(unsafe) private var ringWriteIndex = 0
    nonisolated(unsafe) private var ringReadIndex = 0
    nonisolated(unsafe) private var ringCount = 0  // samples currently in buffer
    private let ringLock = NSLock()
    
    // MARK: - Gain Normalization
    // Exponential moving average of RMS for each source, used to normalize
    // system audio level relative to mic before mixing.
    nonisolated(unsafe) private var runningMicRMS: Float = 0.01
    nonisolated(unsafe) private var runningSysRMS: Float = 0.01
    private let rmsAlpha: Float = 0.05  // EMA smoothing (lower = more stable)
    
    override init() {
        super.init()
        ringBuffer = .allocate(capacity: ringCapacity)
        ringBuffer.initialize(repeating: 0, count: ringCapacity)
    }
    
    deinit {
        ringBuffer?.deinitialize(count: ringCapacity)
        ringBuffer?.deallocate()
    }
    
    func startCapture(microphone: Bool, systemAudio: Bool) async throws {
        await stopCaptureAsync()
        
        var capturedAny = false
        
        if microphone {
            do {
                try await startMicrophoneCapture()
                capturedAny = true
                isMicActive = true
                print("Microphone capture started")
            } catch {
                print("Microphone capture failed: \(error.localizedDescription)")
                isMicActive = false
                if !systemAudio { throw error }
            }
        }
        
        if systemAudio {
            do {
                try await startSystemAudioCapture(mixWithMic: microphone)
                capturedAny = true
                isSystemAudioActive = true
                print("System audio capture started")
            } catch {
                print("System audio capture failed: \(error.localizedDescription)")
                print("Tip: Grant Screen Recording permission in System Settings")
                isSystemAudioActive = false
                if !capturedAny { throw error }
            }
        }
        
        isCapturing = capturedAny
    }
    
    func stopCapture() {
        stopMicrophoneCapture()
        screenCaptureStream = nil
        screenCaptureDelegate = nil
        isCapturing = false
        isMicActive = false
        isSystemAudioActive = false
        resetRingBuffer()
    }
    
    private func stopCaptureAsync() async {
        stopMicrophoneCapture()
        if let stream = screenCaptureStream {
            try? await stream.stopCapture()
        }
        screenCaptureStream = nil
        screenCaptureDelegate = nil
        isCapturing = false
        isMicActive = false
        isSystemAudioActive = false
        resetRingBuffer()
    }
    
    // MARK: - Microphone Capture
    
    private func startMicrophoneCapture() async throws {
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
    }
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - System Audio Capture
    
    private func startSystemAudioCapture(mixWithMic: Bool) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayFound
        }
        
        print("[SystemAudio] Display: \(display.width)x\(display.height), apps: \(content.applications.count), windows: \(content.windows.count)")
        
        let filter = SCContentFilter(display: display, including: content.applications, exceptingWindows: [])
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(targetSampleRate)
        config.channelCount = Int(targetChannels)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false
        
        let directCallback = mixWithMic ? nil : onAudioBuffer
        screenCaptureDelegate = ScreenCaptureDelegate(
            onAudioData: { [weak self] data in
                if mixWithMic {
                    self?.appendToRingBuffer(data)
                } else {
                    directCallback?(data)
                }
            },
            onLevelUpdate: { [weak self] level in
                Task { @MainActor in
                    self?.systemAudioLevel = level
                }
            },
            onRMSUpdate: { [weak self] rms in
                guard let self else { return }
                self.runningSysRMS = self.runningSysRMS * (1 - self.rmsAlpha) + rms * self.rmsAlpha
            }
        )
        
        screenCaptureStream = SCStream(filter: filter, configuration: config, delegate: nil)
        guard let stream = screenCaptureStream, let delegate = screenCaptureDelegate else { return }
        
        try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: .global(qos: .background))
        try stream.addStreamOutput(delegate, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        
        do {
            try await stream.startCapture()
            print("[SystemAudio] Capture started successfully")
        } catch {
            print("[SystemAudio] startCapture failed: \(error)")
            throw AudioCaptureError.screenCapturePermissionDenied
        }
    }
    
    // MARK: - Ring Buffer Operations (lock-protected, no allocations)
    
    nonisolated private func appendToRingBuffer(_ data: Data) {
        data.withUnsafeBytes { raw in
            guard let basePtr = raw.baseAddress else { return }
            let int16Ptr = basePtr.assumingMemoryBound(to: Int16.self)
            let sampleCount = raw.count / MemoryLayout<Int16>.size
            
            ringLock.lock()
            defer { ringLock.unlock() }
            
            for i in 0..<sampleCount {
                ringBuffer[ringWriteIndex] = int16Ptr[i]
                ringWriteIndex = (ringWriteIndex + 1) % ringCapacity
                if ringCount < ringCapacity {
                    ringCount += 1
                } else {
                    // Overwrite oldest: advance read index
                    ringReadIndex = (ringReadIndex + 1) % ringCapacity
                }
            }
        }
    }
    
    /// Drain up to `maxSamples` from the ring buffer into `output`.
    /// Returns actual number of samples written.
    nonisolated private func drainRingBuffer(into output: UnsafeMutablePointer<Int16>, maxSamples: Int) -> Int {
        ringLock.lock()
        defer { ringLock.unlock() }
        
        let drainCount = min(ringCount, maxSamples)
        for i in 0..<drainCount {
            output[i] = ringBuffer[ringReadIndex]
            ringReadIndex = (ringReadIndex + 1) % ringCapacity
        }
        ringCount -= drainCount
        return drainCount
    }
    
    private func resetRingBuffer() {
        ringLock.lock()
        ringWriteIndex = 0
        ringReadIndex = 0
        ringCount = 0
        ringLock.unlock()
    }
    
    // MARK: - Audio Processing (vDSP accelerated)
    
    nonisolated(unsafe) private var lastMicLevelUpdate: CFAbsoluteTime = 0
    // Scratch buffer for mixing (avoids per-call allocation)
    nonisolated(unsafe) private lazy var mixScratch: UnsafeMutablePointer<Int16> = {
        let ptr = UnsafeMutablePointer<Int16>.allocate(capacity: 4096)
        ptr.initialize(repeating: 0, count: 4096)
        return ptr
    }()
    
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
            // Update running mic RMS for gain normalization
            runningMicRMS = runningMicRMS * (1 - rmsAlpha) + level * rmsAlpha
            Task { @MainActor [weak self] in
                self?.microphoneLevel = level
            }
        }
        
        // Mix with buffered system audio (gain-normalized)
        let sysDrained = drainRingBuffer(into: mixScratch, maxSamples: micSamples)
        
        if sysDrained > 0 {
            // Gain normalization: scale system audio to match mic level
            let gainFactor = max(0.1, min(5.0, runningMicRMS / max(runningSysRMS, 0.001)))
            
            // Mix using vDSP: convert both to Float32, scale sys, add, convert back
            let mixCount = min(micSamples, sysDrained)
            var micFloat = [Float](repeating: 0, count: mixCount)
            var sysFloat = [Float](repeating: 0, count: mixCount)
            var mixedFloat = [Float](repeating: 0, count: mixCount)
            
            // Int16 -> Float32
            vDSP_vflt16(micPtr, 1, &micFloat, 1, vDSP_Length(mixCount))
            vDSP_vflt16(mixScratch, 1, &sysFloat, 1, vDSP_Length(mixCount))
            
            // Scale system audio by gain factor
            var gain = gainFactor
            vDSP_vsmul(sysFloat, 1, &gain, &sysFloat, 1, vDSP_Length(mixCount))
            
            // Add
            vDSP_vadd(micFloat, 1, sysFloat, 1, &mixedFloat, 1, vDSP_Length(mixCount))
            
            // Clamp to Int16 range
            var lo: Float = -32768
            var hi: Float = 32767
            vDSP_vclip(mixedFloat, 1, &lo, &hi, &mixedFloat, 1, vDSP_Length(mixCount))
            
            // Float32 -> Int16
            var mixedInt16 = [Int16](repeating: 0, count: micSamples)
            vDSP_vfix16(mixedFloat, 1, &mixedInt16, 1, vDSP_Length(mixCount))
            
            // Copy remaining unmixed mic samples if mic is longer
            if micSamples > mixCount {
                for i in mixCount..<micSamples {
                    mixedInt16[i] = micPtr[i]
                }
            }
            
            let data = Data(bytes: mixedInt16, count: micSamples * 2)
            callback?(data)
        } else {
            // No system audio buffered - send mic directly (zero-copy)
            let data = Data(bytes: micPtr, count: micSamples * 2)
            callback?(data)
        }
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

// MARK: - Screen Capture Delegate

private final class ScreenCaptureDelegate: NSObject, SCStreamOutput, @unchecked Sendable {
    let onAudioData: @Sendable (Data) -> Void
    let onLevelUpdate: @Sendable (Float) -> Void
    let onRMSUpdate: @Sendable (Float) -> Void
    
    init(
        onAudioData: @escaping @Sendable (Data) -> Void,
        onLevelUpdate: @escaping @Sendable (Float) -> Void,
        onRMSUpdate: @escaping @Sendable (Float) -> Void
    ) {
        self.onAudioData = onAudioData
        self.onLevelUpdate = onLevelUpdate
        self.onRMSUpdate = onRMSUpdate
    }
    
    private var hasLoggedFormat = false
    private var lastLevelUpdate: CFAbsoluteTime = 0
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let dataPointer else { return }
        
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else { return }
        
        let isFloat = asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let bitsPerChannel = asbd.pointee.mBitsPerChannel
        let channelCount = Int(asbd.pointee.mChannelsPerFrame)
        
        if !hasLoggedFormat {
            hasLoggedFormat = true
            print("[SystemAudio] Format: \(isFloat ? "Float" : "Int")\(bitsPerChannel), channels: \(channelCount), sampleRate: \(asbd.pointee.mSampleRate), bytes: \(length)")
        }
        
        // Throttle level + RMS calculation to ~20Hz
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastLevelUpdate > 0.05 {
            lastLevelUpdate = now
            
            if isFloat && bitsPerChannel == 32 {
                let floatPtr = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
                let frameCount = length / (MemoryLayout<Float>.size * channelCount)
                if frameCount > 0 {
                    var meanSquare: Float = 0
                    // Use stride of channelCount to pick first channel only
                    vDSP_measqv(floatPtr, vDSP_Stride(channelCount), &meanSquare, vDSP_Length(frameCount))
                    let rms = sqrt(meanSquare)
                    onLevelUpdate(min(1.0, rms))
                    onRMSUpdate(rms)
                }
            } else if !isFloat && bitsPerChannel == 16 {
                let int16Ptr = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Int16.self)
                let frameCount = length / (MemoryLayout<Int16>.size * channelCount)
                if frameCount > 0 {
                    // Convert to float for vDSP
                    var floats = [Float](repeating: 0, count: frameCount)
                    for i in 0..<frameCount {
                        floats[i] = Float(int16Ptr[i * channelCount]) / 32768.0
                    }
                    var meanSquare: Float = 0
                    vDSP_measqv(floats, 1, &meanSquare, vDSP_Length(frameCount))
                    let rms = sqrt(meanSquare)
                    onLevelUpdate(min(1.0, rms))
                    onRMSUpdate(rms)
                }
            }
        }
        
        // Convert to PCM16 for Deepgram / mixing buffer
        if isFloat && bitsPerChannel == 32 {
            let floatPtr = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
            let sampleCount = length / MemoryLayout<Float>.size
            
            // vDSP: scale Float32 [-1,1] -> Int16 range, then convert
            var scaled = [Float](repeating: 0, count: sampleCount)
            var scale: Float = 32767
            vDSP_vsmul(floatPtr, 1, &scale, &scaled, 1, vDSP_Length(sampleCount))
            
            // Clamp
            var lo: Float = -32768
            var hi: Float = 32767
            vDSP_vclip(scaled, 1, &lo, &hi, &scaled, 1, vDSP_Length(sampleCount))
            
            // Float -> Int16
            var int16Samples = [Int16](repeating: 0, count: sampleCount)
            vDSP_vfix16(scaled, 1, &int16Samples, 1, vDSP_Length(sampleCount))
            
            let data = Data(bytes: int16Samples, count: sampleCount * MemoryLayout<Int16>.size)
            onAudioData(data)
        } else {
            let data = Data(bytes: dataPointer, count: length)
            onAudioData(data)
        }
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
