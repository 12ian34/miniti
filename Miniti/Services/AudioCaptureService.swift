import Foundation
@preconcurrency import AVFoundation
import AudioToolbox
import Accelerate

@MainActor
final class AudioCaptureService: NSObject, ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    
    // System audio via Core Audio Process Tap (macOS 14.2+)
    // Uses AudioHardwareCreateProcessTap instead of ScreenCaptureKit to land
    // in "System Audio Recording Only" permission category (not Screen Recording).
    // IO proc callback on aggregate device → AVAudioConverter → ring buffer.
    nonisolated(unsafe) private var processTapID: AudioObjectID = kAudioObjectUnknown
    nonisolated(unsafe) private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    nonisolated(unsafe) private var tapDeviceProcID: AudioDeviceIOProcID?
    
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
    
    private let ringCapacity = 8000  // ~500ms at 16kHz mono (samples, not bytes)
    nonisolated(unsafe) private var ringBuffer: UnsafeMutablePointer<Int16>!
    nonisolated(unsafe) private var ringWriteIndex = 0
    nonisolated(unsafe) private var ringReadIndex = 0
    nonisolated(unsafe) private var ringCount = 0  // samples currently in buffer
    private let ringLock = NSLock()
    
    // MARK: - Adaptive Dual AGC
    // Each source is independently normalized to a target Int16 RMS before mixing.
    // Gain is smoothed (fast attack, slow release) to avoid pumping.
    // A noise gate prevents boosting silence/background noise.
    nonisolated(unsafe) private var runningMicRMS: Float = 0.01   // EMA of raw Float32 mic level (0-1), for display
    nonisolated(unsafe) private var runningSysRMS: Float = 0.01   // EMA of raw Float32 sys level (0-1), for display
    private let rmsAlpha: Float = 0.05  // EMA smoothing for display levels
    
    // Smoothed gains applied to Int16 buffers during mixing
    nonisolated(unsafe) private var smoothedMicGain: Float = 1.0
    nonisolated(unsafe) private var smoothedSysGain: Float = 1.0
    
    // MARK: - Source Dominance Tracking
    // Records which audio source (mic vs system) was dominant at each point in the
    // stream. Used to override Deepgram's diarization — mic words → "You",
    // system words → remote speaker(s). Keyed by stream time (seconds from start).
    
    struct SourceSample {
        let streamTime: Double   // seconds from recording start
        let micEnergy: Float     // Int16-scale RMS of mic buffer
        let sysEnergy: Float     // Int16-scale RMS of system buffer
    }
    
    /// Rolling log of per-buffer source dominance. Accessed from mic callback thread.
    nonisolated(unsafe) private var sourceLog: [SourceSample] = []
    private let sourceLogLock = NSLock()
    /// Cumulative samples sent to Deepgram, for computing stream time.
    nonisolated(unsafe) private var cumulativeSamplesSent: Int = 0
    
    /// Returns the dominant audio source for a given time range in the stream.
    /// - Returns: `.system` if system audio energy exceeded mic, `.mic` if mic was louder, `.unknown` if no data.
    enum AudioSource { case mic, system, unknown }
    
    nonisolated func dominantSource(from startTime: Double, to endTime: Double) -> AudioSource {
        sourceLogLock.lock()
        defer { sourceLogLock.unlock() }
        
        var micTotal: Float = 0
        var sysTotal: Float = 0
        var count: Float = 0
        
        for sample in sourceLog {
            if sample.streamTime >= startTime && sample.streamTime <= endTime {
                micTotal += sample.micEnergy
                sysTotal += sample.sysEnergy
                count += 1
            }
        }
        
        guard count > 0 else { return .unknown }
        // Require system to be meaningfully louder (>1.5x) to tag as system,
        // since mic noise gets amplified and may match system during pauses.
        return sysTotal > micTotal * 1.5 ? .system : .mic
    }
    
    /// Clears source log (call when starting a new recording).
    func resetSourceTracking() {
        sourceLogLock.lock()
        sourceLog.removeAll()
        cumulativeSamplesSent = 0
        sourceLogLock.unlock()
    }
    
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
                try startSystemAudioCapture(mixWithMic: microphone)
                capturedAny = true
                isSystemAudioActive = true
                print("System audio capture started")
            } catch {
                print("System audio capture failed: \(error.localizedDescription)")
                print("Tip: Grant System Audio Recording permission in System Settings > Privacy & Security")
                isSystemAudioActive = false
                if !capturedAny { throw error }
            }
        }
        
        isCapturing = capturedAny
    }
    
    func stopCapture() {
        stopMicrophoneCapture()
        stopSystemAudioCapture()
        isCapturing = false
        isMicActive = false
        isSystemAudioActive = false
        resetRingBuffer()
    }
    
    private func stopCaptureAsync() async {
        stopMicrophoneCapture()
        stopSystemAudioCapture()
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
    
    // MARK: - System Audio Capture (Core Audio Process Tap)
    // Uses AudioHardwareCreateProcessTap + aggregate device instead of
    // ScreenCaptureKit. This gets classified as "System Audio Recording Only"
    // in macOS 15+ (like Granola), avoiding the invasive Screen Recording
    // permission and per-window Gatekeeper popups.
    
    private func startSystemAudioCapture(mixWithMic: Bool) throws {
        // 1. Create a global stereo tap capturing all processes
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted
        tapDescription.name = "MinitiAudioTap"
        tapDescription.isPrivate = true
        
        var tapID: AudioObjectID = kAudioObjectUnknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            print("[SystemAudio] AudioHardwareCreateProcessTap failed: \(err)")
            throw AudioCaptureError.systemAudioPermissionDenied
        }
        processTapID = tapID
        print("[SystemAudio] Created process tap #\(tapID)")
        
        // 2. Read tap's native audio format
        var tapFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        err = AudioObjectGetPropertyData(tapID, &formatAddr, 0, nil, &formatSize, &tapFormat)
        guard err == noErr else {
            print("[SystemAudio] Failed to read tap format: \(err)")
            throw AudioCaptureError.formatCreationFailed
        }
        print("[SystemAudio] Tap format: \(tapFormat.mSampleRate)Hz, \(tapFormat.mChannelsPerFrame)ch, \(tapFormat.mBitsPerChannel)bit, Float=\(tapFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0)")
        
        // 3. Get default output device UID (needed for aggregate device)
        var outputDeviceID: AudioDeviceID = 0
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var outputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outputAddr, 0, nil, &deviceSize, &outputDeviceID)
        guard err == noErr else {
            print("[SystemAudio] Failed to get default output device: \(err)")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        
        var outputUIDCF: CFString?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        err = withUnsafeMutablePointer(to: &outputUIDCF) { ptr in
            AudioObjectGetPropertyData(outputDeviceID, &uidAddr, 0, nil, &uidSize,
                                       UnsafeMutableRawPointer(ptr))
        }
        guard err == noErr, let outputUID = outputUIDCF as String? else {
            print("[SystemAudio] Failed to get output device UID: \(err)")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        print("[SystemAudio] Output device: \(outputUID)")
        
        // 4. Create private aggregate device with the tap
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MinitiSystemAudioTap",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]
        
        var aggDeviceID: AudioObjectID = kAudioObjectUnknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggDeviceID)
        guard err == noErr else {
            print("[SystemAudio] Failed to create aggregate device: \(err)")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        aggregateDeviceID = aggDeviceID
        print("[SystemAudio] Created aggregate device #\(aggDeviceID)")
        
        // 5. Determine the actual IO format for the aggregate device.
        // IMPORTANT: the aggregate device's stream format may differ from the
        // tap format (e.g., 24kHz 1ch vs tap's 48kHz 2ch). We MUST use the
        // aggregate device's format for the IO proc buffer interpretation.
        var ioFormat = tapFormat  // fallback
        var ioFmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var ioFmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        let fmtErr = AudioObjectGetPropertyData(aggDeviceID, &ioFmtAddr, 0, nil, &ioFmtSize, &ioFormat)
        if fmtErr == noErr && ioFormat.mSampleRate > 0 {
            print("[SystemAudio] Aggregate IO format: \(ioFormat.mSampleRate)Hz, \(ioFormat.mChannelsPerFrame)ch, Float=\(ioFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0), NonInterleaved=\(ioFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0)")
        } else {
            print("[SystemAudio] Could not read aggregate IO format (\(fmtErr)), using tap format")
            ioFormat = tapFormat
        }
        
        guard let inputFormat = AVAudioFormat(streamDescription: &ioFormat) else {
            throw AudioCaptureError.formatCreationFailed
        }
        
        let directCallback = mixWithMic ? nil : onAudioBuffer
        let targetRate = targetSampleRate
        
        // 6. IO proc callback on a custom dispatch queue. Uses direct vDSP
        // for mono downmix + decimation + Float→Int16 (no AVAudioConverter).
        let queue = DispatchQueue(label: "com.miniti.systemAudioTap", qos: .userInteractive)
        
        var procID: AudioDeviceIOProcID?
        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggDeviceID, queue) { [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            self.processSystemAudioCallback(
                inInputData: inInputData,
                inputFormat: inputFormat,
                targetRate: targetRate,
                mixWithMic: mixWithMic,
                directCallback: directCallback
            )
        }
        guard err == noErr else {
            print("[SystemAudio] Failed to create IO proc: \(err)")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        tapDeviceProcID = procID
        
        // 7. Start the aggregate device
        err = AudioDeviceStart(aggDeviceID, procID)
        guard err == noErr else {
            print("[SystemAudio] Failed to start aggregate device: \(err)")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        
        print("[SystemAudio] Process tap started successfully (audio-only mode)")
    }
    
    private func stopSystemAudioCapture() {
        // 1. Stop and destroy IO proc
        if aggregateDeviceID != kAudioObjectUnknown {
            if let procID = tapDeviceProcID {
                AudioDeviceStop(aggregateDeviceID, procID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
                tapDeviceProcID = nil
            }
            // 2. Destroy aggregate device
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        
        // 3. Destroy process tap
        if processTapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(processTapID)
            processTapID = kAudioObjectUnknown
        }
    }
    
    // MARK: - System Audio IO Callback
    // Uses direct vDSP for conversion (mono downmix + decimation + Float→Int16).
    // AVAudioConverter was producing silent/garbled output in this context.
    
    nonisolated(unsafe) private var lastSystemLevelUpdate: CFAbsoluteTime = 0
    nonisolated(unsafe) private var sysCallbackCount: Int = 0
    
    nonisolated private func processSystemAudioCallback(
        inInputData: UnsafePointer<AudioBufferList>,
        inputFormat: AVAudioFormat,
        targetRate: Double,
        mixWithMic: Bool,
        directCallback: (@Sendable (Data) -> Void)?
    ) {
        // Access the raw buffer list directly
        let abl = inInputData.pointee
        guard abl.mNumberBuffers > 0 else { return }
        let buf = abl.mBuffers
        guard let rawData = buf.mData else { return }
        let byteCount = Int(buf.mDataByteSize)
        guard byteCount > 0 else { return }
        
        let floatPtr = rawData.assumingMemoryBound(to: Float.self)
        let totalFloats = byteCount / MemoryLayout<Float>.size
        let channels = Int(inputFormat.channelCount)
        let isInterleaved = inputFormat.isInterleaved
        
        // Determine frame count and channel layout
        let framesPerChannel: Int
        if isInterleaved {
            framesPerChannel = totalFloats / max(1, channels)
        } else {
            // Non-interleaved: each buffer is one channel
            framesPerChannel = totalFloats
        }
        guard framesPerChannel > 0 else { return }
        
        let decimation = max(1, Int(inputFormat.sampleRate / targetRate))
        let outputFrames = framesPerChannel / decimation
        guard outputFrames > 0 else { return }
        
        // One-time format diagnostic
        if sysCallbackCount == 0 {
            print("[SystemAudio] IO callback: \(inputFormat.sampleRate)Hz, \(channels)ch, interleaved=\(isInterleaved), frames=\(framesPerChannel), decimation=\(decimation), totalFloats=\(totalFloats), mNumberBuffers=\(abl.mNumberBuffers), mDataByteSize=\(byteCount)")
        }
        
        // Calculate system audio level (throttled to ~20Hz)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastSystemLevelUpdate > 0.05 {
            lastSystemLevelUpdate = now
            let levelStride = isInterleaved ? vDSP_Stride(channels) : vDSP_Stride(1)
            var meanSquare: Float = 0
            vDSP_measqv(floatPtr, levelStride, &meanSquare, vDSP_Length(framesPerChannel))
            let rms = sqrt(meanSquare)
            Task { @MainActor [weak self] in
                self?.systemAudioLevel = min(1.0, rms)
            }
            runningSysRMS = runningSysRMS * (1 - rmsAlpha) + rms * rmsAlpha
        }
        
        // === Convert: Float32 stereo 48kHz → Int16 mono 16kHz via vDSP ===
        
        // Step 1: Stereo → Mono downmix (average L+R for proper mono)
        var mono = [Float](repeating: 0, count: framesPerChannel)
        if isInterleaved && channels >= 2 {
            // Interleaved: [L0 R0 L1 R1 ...] — add L+R with stride, then halve
            vDSP_vadd(floatPtr, vDSP_Stride(channels),       // L: 0, 2, 4, ...
                      floatPtr + 1, vDSP_Stride(channels),   // R: 1, 3, 5, ...
                      &mono, 1, vDSP_Length(framesPerChannel))
            var half: Float = 0.5
            vDSP_vsmul(mono, 1, &half, &mono, 1, vDSP_Length(framesPerChannel))
        } else {
            // Mono or non-interleaved: just copy first channel
            memcpy(&mono, floatPtr, framesPerChannel * MemoryLayout<Float>.size)
        }
        
        // Step 2: Decimate (48kHz → 16kHz = take every 3rd sample) + scale to Int16 range
        var scaled = [Float](repeating: 0, count: outputFrames)
        var scale: Float = 32767.0
        vDSP_vsmul(mono, vDSP_Stride(decimation), &scale, &scaled, 1, vDSP_Length(outputFrames))
        
        // Step 3: Clamp to Int16 range
        var lo: Float = -32768
        var hi: Float = 32767
        vDSP_vclip(scaled, 1, &lo, &hi, &scaled, 1, vDSP_Length(outputFrames))
        
        // Step 4: Float32 → Int16
        var int16Out = [Int16](repeating: 0, count: outputFrames)
        vDSP_vfix16(scaled, 1, &int16Out, 1, vDSP_Length(outputFrames))
        
        // Diagnostic: log first callback's output values + periodic output RMS
        sysCallbackCount += 1
        if sysCallbackCount == 1 {
            let first5 = (0..<min(5, outputFrames)).map { String(int16Out[$0]) }
            // Also compute mono RMS at input for reference
            var monoMsq: Float = 0
            vDSP_measqv(mono, 1, &monoMsq, vDSP_Length(framesPerChannel))
            print("[SystemAudio] First output: frames=\(outputFrames), samples=[\(first5.joined(separator: ", "))], monoRMS=\(String(format: "%.4f", sqrt(monoMsq)))")
        }
        
        let data = Data(bytes: int16Out, count: outputFrames * MemoryLayout<Int16>.size)
        
        if mixWithMic {
            appendToRingBuffer(data)
        } else {
            directCallback?(data)
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
    nonisolated(unsafe) private var lastMixDebugLog: CFAbsoluteTime = 0
    // Scratch buffer for mixing (avoids per-call allocation)
    nonisolated(unsafe) private let mixScratch: UnsafeMutablePointer<Int16> = {
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
            // === Adaptive dual AGC ===
            // Measure actual Int16 RMS of each buffer, compute gain to reach
            // target, smooth gain transitions. Works regardless of hardware
            // levels (process tap, ScreenCaptureKit, Bluetooth, etc.).
            
            let mixCount = min(micSamples, sysDrained)
            var micFloat = [Float](repeating: 0, count: mixCount)
            var sysFloat = [Float](repeating: 0, count: mixCount)
            var mixedFloat = [Float](repeating: 0, count: mixCount)
            
            // Int16 -> Float32
            vDSP_vflt16(micPtr, 1, &micFloat, 1, vDSP_Length(mixCount))
            vDSP_vflt16(mixScratch, 1, &sysFloat, 1, vDSP_Length(mixCount))
            
            // Measure RMS of each buffer (Int16 scale: 0–32767)
            var micMsq: Float = 0
            vDSP_measqv(micFloat, 1, &micMsq, vDSP_Length(mixCount))
            let micRMS = sqrt(micMsq)
            
            var sysMsq: Float = 0
            vDSP_measqv(sysFloat, 1, &sysMsq, vDSP_Length(mixCount))
            let sysRMS = sqrt(sysMsq)
            
            // Record source dominance for this buffer (raw energy, before AGC)
            let streamTime = Double(cumulativeSamplesSent) / 16000.0
            sourceLogLock.lock()
            sourceLog.append(SourceSample(streamTime: streamTime, micEnergy: micRMS, sysEnergy: sysRMS))
            // Trim entries older than 10 minutes to bound memory
            if sourceLog.count > 6000 { sourceLog.removeFirst(sourceLog.count - 6000) }
            sourceLogLock.unlock()
            
            // Target RMS in Int16 scale. Mic slightly louder for diarization.
            // ~3000 = ~9% of full scale — comfortable speech level for Deepgram.
            let micTargetRMS: Float = 3000
            let sysTargetRMS: Float = 2000
            let noiseFloor: Float = 30      // Don't boost below this (pure noise/silence)
            let maxGain: Float = 25.0        // Safety cap
            
            // Compute ideal gain for this buffer
            let idealMicGain = micRMS > noiseFloor
                ? min(maxGain, max(1.0, micTargetRMS / micRMS))
                : 1.0
            let idealSysGain = sysRMS > noiseFloor
                ? min(maxGain, max(1.0, sysTargetRMS / sysRMS))
                : 1.0
            
            // Smooth gain: fast attack (0.15), slow release (0.02) to avoid pumping
            let attack: Float = 0.15
            let release: Float = 0.02
            smoothedMicGain += (idealMicGain > smoothedMicGain ? attack : release) * (idealMicGain - smoothedMicGain)
            smoothedSysGain += (idealSysGain > smoothedSysGain ? attack : release) * (idealSysGain - smoothedSysGain)
            
            // Debug: log mixing stats every 30s, only when system audio is active
            if now - lastMixDebugLog > 30.0 && sysRMS > 30 {
                lastMixDebugLog = now
                print("[AudioMix] micGain=\(String(format: "%.1f", smoothedMicGain)) sysGain=\(String(format: "%.1f", smoothedSysGain)) micRMS=\(String(format: "%.0f", micRMS)) sysRMS=\(String(format: "%.0f", sysRMS))")
            }
            
            // Apply gains
            var mGain = smoothedMicGain
            vDSP_vsmul(micFloat, 1, &mGain, &micFloat, 1, vDSP_Length(mixCount))
            var sGain = smoothedSysGain
            vDSP_vsmul(sysFloat, 1, &sGain, &sysFloat, 1, vDSP_Length(mixCount))
            
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
            
            cumulativeSamplesSent += micSamples
            let data = Data(bytes: mixedInt16, count: micSamples * 2)
            callback?(data)
        } else {
            // No system audio buffered — mic only. Log as mic-dominant.
            let streamTime = Double(cumulativeSamplesSent) / 16000.0
            sourceLogLock.lock()
            sourceLog.append(SourceSample(streamTime: streamTime, micEnergy: 1.0, sysEnergy: 0.0))
            if sourceLog.count > 6000 { sourceLog.removeFirst(sourceLog.count - 6000) }
            sourceLogLock.unlock()
            
            cumulativeSamplesSent += micSamples
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
            return "Microphone permission was denied. Please enable in System Settings."
        case .systemAudioPermissionDenied:
            return "System audio permission is required. Please grant access in System Settings > Privacy & Security > Screen & System Audio Recording."
        case .systemAudioSetupFailed:
            return "Failed to set up system audio capture. Please check System Settings > Privacy & Security."
        case .formatCreationFailed:
            return "Failed to create audio format."
        case .converterCreationFailed:
            return "Failed to create audio converter."
        }
    }
}
