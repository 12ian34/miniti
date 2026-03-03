import Foundation
@preconcurrency import AVFoundation
import AudioToolbox
import Accelerate

@MainActor
final class AudioCaptureService: NSObject, ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var engineConfigObserver: Any?
    
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
    
    // MARK: - Runtime Diagnostics
    
    nonisolated(unsafe) private var sysInputFrameCount: Int = 0
    nonisolated(unsafe) private var sysOutputFrameCount: Int = 0
    nonisolated(unsafe) private var sysNonSilentCallbacks: Int = 0
    nonisolated(unsafe) private var sysSilentCallbacks: Int = 0
    nonisolated(unsafe) private var ringSamplesAppended: Int = 0
    nonisolated(unsafe) private var ringSamplesDrained: Int = 0
    nonisolated(unsafe) private var mixWithSystemCount: Int = 0
    nonisolated(unsafe) private var mixMicOnlyCount: Int = 0
    nonisolated(unsafe) private var lastSystemHeartbeat: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastNoSystemMixWarning: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastSystemNonSilentAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastSystemAutoRestartAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastSilenceCheck: CFAbsoluteTime = 0
    private var isRestartingMicAfterConfigChange = false
    private var isRestartingSystemAfterOutputChange = false
    private var lastOutputChangeRestartAt: CFAbsoluteTime = 0
    private var pendingMicRestartTask: Task<Void, Never>?
    private var lastMicRestartAt: CFAbsoluteTime = 0
    private var activeMicInputDeviceID: AudioDeviceID?
    private var activeMicInputSampleRate: Double = 0
    private var activeMicInputChannels: AVAudioChannelCount = 0
    
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
        monitorAudioDeviceChanges()
    }
    
    // MARK: - Audio Device Monitoring
    
    private func monitorAudioDeviceChanges() {
        var inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &inputAddr, DispatchQueue.main
        ) { [weak self] _, _ in
            DebugLogger.shared.log(.audio, "Default INPUT device changed → \(Self.defaultInputDeviceInfo())")
            Task { @MainActor in
                self?.handleEngineConfigurationChange()
            }
        }
        
        var outputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &outputAddr, DispatchQueue.main
        ) { [weak self] _, _ in
            DebugLogger.shared.log(.audio, "Default OUTPUT device changed → \(Self.defaultOutputDeviceInfo())")
            Task { @MainActor in
                self?.handleDefaultOutputDeviceChange()
            }
        }
    }
    
    nonisolated static func defaultInputDeviceInfo() -> String {
        return deviceInfo(selector: kAudioHardwarePropertyDefaultInputDevice)
    }
    
    nonisolated static func defaultOutputDeviceInfo() -> String {
        return deviceInfo(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    nonisolated static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        return err == noErr ? deviceID : nil
    }
    
    nonisolated private static func formatSummary(_ asbd: AudioStreamBasicDescription) -> String {
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let sampleType = isFloat ? "float" : "int"
        return "\(Int(asbd.mSampleRate))Hz, \(asbd.mChannelsPerFrame)ch, \(sampleType)\(asbd.mBitsPerChannel), interleaved=\(!isNonInterleaved)"
    }
    
    nonisolated private static func deviceNominalSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &sampleRate)
        return sampleRate
    }

    nonisolated private static func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var uidCF: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = withUnsafeMutablePointer(to: &uidCF) { ptr in
            AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, UnsafeMutableRawPointer(ptr))
        }
        return err == noErr ? (uidCF as String?) : nil
    }
    
    nonisolated private static func deviceTransportType(_ deviceID: AudioDeviceID) -> UInt32? {
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transportType)
        return err == noErr ? transportType : nil
    }
    
    nonisolated private static func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var streamSize: UInt32 = 0
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyDataSize(deviceID, &streamAddr, 0, nil, &streamSize) == noErr
            && streamSize > 0
    }
    
    nonisolated private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        return err == noErr ? deviceID : nil
    }

    /// Find a built-in output device to use as a stable clock source when the
    /// default output has a sample rate mismatch with the process tap (e.g.
    /// Bluetooth HFP at 24kHz vs tap at 48kHz).
    nonisolated private static func findBuiltInOutputDevice() -> AudioDeviceID? {
        var propSize: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize
        ) == noErr else { return nil }

        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceIDs
        ) == noErr else { return nil }

        for id in deviceIDs {
            guard let transportType = deviceTransportType(id) else { continue }
            guard transportType == kAudioDeviceTransportTypeBuiltIn else { continue }
            guard hasOutputStreams(id) else { continue }

            return id
        }
        return nil
    }

    nonisolated private static func deviceInfo(selector: AudioObjectPropertySelector) -> String {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        ) == noErr else { return "unknown (read error)" }
        
        var nameRef: CFString?
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = withUnsafeMutablePointer(to: &nameRef) { ptr in
            AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, UnsafeMutableRawPointer(ptr))
        }
        let name = (nameRef as String?) ?? "unknown"
        
        var sampleRate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &rateAddr, 0, nil, &rateSize, &sampleRate)
        
        return "\(name) (\(Int(sampleRate))Hz, id:\(deviceID))"
    }
    
    deinit {
        ringBuffer?.deinitialize(count: ringCapacity)
        ringBuffer?.deallocate()
    }
    
    private func resetRuntimeDiagnostics() {
        sysInputFrameCount = 0
        sysOutputFrameCount = 0
        sysNonSilentCallbacks = 0
        sysSilentCallbacks = 0
        ringSamplesAppended = 0
        ringSamplesDrained = 0
        mixWithSystemCount = 0
        mixMicOnlyCount = 0
        lastSystemHeartbeat = CFAbsoluteTimeGetCurrent()
        lastNoSystemMixWarning = 0
        lastSystemNonSilentAt = lastSystemHeartbeat
        lastSystemAutoRestartAt = 0
        lastSilenceCheck = 0
        sysCallbackCount = 0
    }
    
    nonisolated private func currentRingSampleCount() -> Int {
        ringLock.lock()
        defer { ringLock.unlock() }
        return ringCount
    }
    
    func startCapture(microphone: Bool, systemAudio: Bool) async throws {
        await stopCaptureAsync()
        
        DebugLogger.shared.log(.audio, "startCapture(mic=\(microphone), sys=\(systemAudio))")
        resetRuntimeDiagnostics()
        var capturedAny = false
        
        if microphone {
            do {
                try await startMicrophoneCapture()
                capturedAny = true
                isMicActive = true
                print("Microphone capture started")
            } catch {
                print("Microphone capture failed: \(error.localizedDescription)")
                DebugLogger.shared.log(.audio, "Mic capture FAILED: \(error.localizedDescription)")
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
                DebugLogger.shared.log(.audio, "System audio FAILED: \(error.localizedDescription)")
                isSystemAudioActive = false
                if !capturedAny { throw error }
            }
        }
        
        isCapturing = capturedAny
        DebugLogger.shared.log(.audio, "Capture result: mic=\(isMicActive), sys=\(isSystemAudioActive)")
    }
    
    func stopCapture() {
        if isCapturing {
            let ringNow = currentRingSampleCount()
            DebugLogger.shared.log(
                .audio,
                "Capture stop summary: micBuf=\(micBufferCount), sysCb=\(sysCallbackCount), sysNonSilent=\(sysNonSilentCallbacks), mix(sys=\(mixWithSystemCount), micOnly=\(mixMicOnlyCount)), ring(appended=\(ringSamplesAppended), drained=\(ringSamplesDrained), left=\(ringNow))"
            )
        }
        stopMicrophoneCapture()
        stopSystemAudioCapture()
        pendingMicRestartTask?.cancel()
        pendingMicRestartTask = nil
        isCapturing = false
        isMicActive = false
        isSystemAudioActive = false
        resetRingBuffer()
    }
    
    private func stopCaptureAsync() async {
        if isCapturing {
            let ringNow = currentRingSampleCount()
            DebugLogger.shared.log(
                .audio,
                "Capture stop summary: micBuf=\(micBufferCount), sysCb=\(sysCallbackCount), sysNonSilent=\(sysNonSilentCallbacks), mix(sys=\(mixWithSystemCount), micOnly=\(mixMicOnlyCount)), ring(appended=\(ringSamplesAppended), drained=\(ringSamplesDrained), left=\(ringNow))"
            )
        }
        stopMicrophoneCapture()
        stopSystemAudioCapture()
        pendingMicRestartTask?.cancel()
        pendingMicRestartTask = nil
        isCapturing = false
        isMicActive = false
        isSystemAudioActive = false
        resetRingBuffer()
    }
    
    // MARK: - Microphone Capture
    
    nonisolated(unsafe) private var micBufferCount: Int = 0
    nonisolated(unsafe) private var lastMicHeartbeat: CFAbsoluteTime = 0
    
    private func startMicrophoneCapture(skipPermissionCheck: Bool = false) async throws {
        if !skipPermissionCheck {
            let granted = await requestMicrophonePermission()
            guard granted else {
                DebugLogger.shared.log(.audio, "Mic permission DENIED")
                throw AudioCaptureError.microphonePermissionDenied
            }
        }
        
        DebugLogger.shared.log(.audio, "Default input device: \(Self.defaultInputDeviceInfo())")
        
        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let nodeFormat = inputNode.outputFormat(forBus: 0)
        
        DebugLogger.shared.log(.audio, "Mic input format: \(nodeFormat.sampleRate)Hz, \(nodeFormat.channelCount)ch, \(nodeFormat.commonFormat.rawValue)fmt")
        
        guard nodeFormat.sampleRate > 0 && nodeFormat.channelCount > 0 else {
            DebugLogger.shared.log(.audio, "INVALID input format (0Hz or 0ch) — audio device may be unavailable")
            throw AudioCaptureError.formatCreationFailed
        }

        activeMicInputDeviceID = Self.defaultInputDeviceID()
        activeMicInputSampleRate = nodeFormat.sampleRate
        activeMicInputChannels = nodeFormat.channelCount
        
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
        let hasCallback = onBuffer != nil
        DebugLogger.shared.log(.audio, "Mic tap installing (callback \(hasCallback ? "set" : "nil — monitoring only"))")
        
        let targetRate = targetSampleRate
        // Pass nil tap format to follow the node's current hardware format and avoid
        // install-time format mismatches during route changes (e.g., AirPods connect).
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
                    DebugLogger.shared.log(.audio, "FAILED to create mic converter in callback: \(inFormat.sampleRate)Hz, \(inFormat.channelCount)ch → \(targetSampleRate)Hz")
                    return
                }
                activeConverter = newConverter
                activeInputSampleRate = inFormat.sampleRate
                activeInputChannels = inFormat.channelCount
                DebugLogger.shared.log(.audio, "Mic converter ready: \(inFormat.sampleRate)Hz, \(inFormat.channelCount)ch → \(targetSampleRate)Hz")
            }
            
            guard let converter = activeConverter else { return }
            self.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat, targetRate: targetRate, callback: onBuffer)
        }
        
        try audioEngine.start()
        DebugLogger.shared.log(.audio, "Mic AVAudioEngine started")
        
        // Handle audio device changes (e.g. AirPods switching to HFP when Zoom grabs the mic).
        // Without this, the engine silently stops producing buffers after the hardware reconfigures.
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
    }
    
    /// Restart mic capture after audio hardware changes (Bluetooth codec switch, device unplug, etc.).
    /// Rebuilding the engine avoids format-mismatch crashes during route transitions.
    private func handleEngineConfigurationChange() {
        guard isCapturing, isMicActive else { return }
        
        // Coalesce event bursts that happen during Bluetooth route/profile transitions.
        pendingMicRestartTask?.cancel()
        pendingMicRestartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pendingMicRestartTask = nil }
            
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard self.isCapturing, self.isMicActive else { return }
            
            let currentInputID = Self.defaultInputDeviceID()
            let currentFormat = self.audioEngine?.inputNode.outputFormat(forBus: 0)
            let hasMeaningfulInputChange: Bool
            if let currentFormat {
                let deviceChanged = currentInputID != self.activeMicInputDeviceID
                let rateChanged = abs(currentFormat.sampleRate - self.activeMicInputSampleRate) > 0.1
                let channelChanged = currentFormat.channelCount != self.activeMicInputChannels
                hasMeaningfulInputChange = deviceChanged || rateChanged || channelChanged
            } else {
                hasMeaningfulInputChange = true
            }
            
            guard hasMeaningfulInputChange else {
                DebugLogger.shared.log(.audio, "Engine config changed but mic input format/device is unchanged — skipping mic restart")
                return
            }
            
            guard !self.isRestartingMicAfterConfigChange else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastMicRestartAt > 0.5 else {
                DebugLogger.shared.log(.audio, "Engine config changed — mic restart coalesced")
                return
            }
            
            self.lastMicRestartAt = now
            self.isRestartingMicAfterConfigChange = true
            defer { self.isRestartingMicAfterConfigChange = false }
            
            DebugLogger.shared.log(.audio, "Engine config changed — restarting mic tap. New input device: \(Self.defaultInputDeviceInfo())")
            
            self.stopMicrophoneCapture()
            do {
                try await self.startMicrophoneCapture(skipPermissionCheck: true)
                if let newFormat = self.audioEngine?.inputNode.outputFormat(forBus: 0) {
                    DebugLogger.shared.log(.audio, "Mic restart complete after config change: \(newFormat.sampleRate)Hz, \(newFormat.channelCount)ch")
                } else {
                    DebugLogger.shared.log(.audio, "Mic restart complete after config change")
                }
            } catch {
                self.isMicActive = false
                DebugLogger.shared.log(.audio, "Mic restart FAILED after config change: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleDefaultOutputDeviceChange() {
        guard isCapturing, isSystemAudioActive else { return }
        guard !isRestartingSystemAfterOutputChange else { return }
        
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastOutputChangeRestartAt > 0.6 else { return }
        lastOutputChangeRestartAt = now
        isRestartingSystemAfterOutputChange = true
        
        let mixWithMic = isMicActive
        DebugLogger.shared.log(.audio, "Output device changed during capture — scheduling system tap restart")
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRestartingSystemAfterOutputChange = false }
            
            // Allow CoreAudio route change to settle before rebuilding aggregate device.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard self.isCapturing else { return }
            
            do {
                self.stopSystemAudioCapture()
                try self.startSystemAudioCapture(mixWithMic: mixWithMic)
                self.isSystemAudioActive = true
                DebugLogger.shared.log(.audio, "System tap restart complete after output change")
            } catch {
                self.isSystemAudioActive = false
                DebugLogger.shared.log(.audio, "System tap restart FAILED after output change: \(error.localizedDescription)")
            }
        }
    }

    private func recoverSystemTapAfterSilentStall(
        mixWithMic: Bool,
        silenceDuration: CFAbsoluteTime
    ) async {
        guard isCapturing, isSystemAudioActive else { return }
        guard !isRestartingSystemAfterOutputChange else { return }
        isRestartingSystemAfterOutputChange = true
        defer { isRestartingSystemAfterOutputChange = false }

        DebugLogger.shared.log(
            .audio,
            "System tap recovery starting after \(String(format: "%.1f", silenceDuration))s near-silence"
        )

        try? await Task.sleep(nanoseconds: 250_000_000)
        guard isCapturing else { return }

        do {
            stopSystemAudioCapture()
            try startSystemAudioCapture(mixWithMic: mixWithMic)
            isSystemAudioActive = true
            lastSystemNonSilentAt = CFAbsoluteTimeGetCurrent()
            DebugLogger.shared.log(.audio, "System tap recovery complete")
        } catch {
            isSystemAudioActive = false
            DebugLogger.shared.log(.audio, "System tap recovery FAILED: \(error.localizedDescription)")
        }
    }
    
    private func stopMicrophoneCapture() {
        if let observer = engineConfigObserver {
            NotificationCenter.default.removeObserver(observer)
            engineConfigObserver = nil
        }
        pendingMicRestartTask?.cancel()
        pendingMicRestartTask = nil
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
            DebugLogger.shared.log(.audio, "AudioHardwareCreateProcessTap FAILED: osstatus=\(err)")
            throw AudioCaptureError.systemAudioPermissionDenied
        }
        processTapID = tapID
        print("[SystemAudio] Created process tap #\(tapID)")
        DebugLogger.shared.log(.audio, "System audio process tap created (#\(tapID))")
        
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
            DebugLogger.shared.log(.audio, "Read tap format FAILED: osstatus=\(err)")
            throw AudioCaptureError.formatCreationFailed
        }
        print("[SystemAudio] Tap format: \(tapFormat.mSampleRate)Hz, \(tapFormat.mChannelsPerFrame)ch, \(tapFormat.mBitsPerChannel)bit, Float=\(tapFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0)")
        DebugLogger.shared.log(.audio, "System tap format: \(Self.formatSummary(tapFormat))")
        
        // 3. Pick a clock source for the aggregate device.
        // The process tap captures ALL system audio from the mixer regardless
        // of which device clocks the aggregate — it only needs a stable clock.
        // The built-in output shares the same hardware oscillator as the system
        // mixer, so there is zero drift. External devices (Bluetooth, USB, HDMI)
        // have independent oscillators — even when sample rates nominally match,
        // real clock drift accumulates and can cause the tap to deliver silent
        // buffers (especially severe with Bluetooth HFP at 24kHz vs tap at
        // 48kHz). Always prefer built-in; fall back to default output only if
        // no built-in device exists.
        var clockDeviceID: AudioDeviceID
        var clockSource: String
        
        if let builtInID = Self.findBuiltInOutputDevice() {
            clockDeviceID = builtInID
            let rate = Self.deviceNominalSampleRate(builtInID)
            clockSource = "built-in output (\(Int(rate))Hz)"
        } else if let defaultID = Self.defaultOutputDeviceID() {
            clockDeviceID = defaultID
            let rate = Self.deviceNominalSampleRate(defaultID)
            clockSource = "default output fallback (\(Int(rate))Hz, no built-in found)"
        } else {
            DebugLogger.shared.log(.audio, "No output device available for aggregate clock source")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        
        guard let outputUID = Self.deviceUID(clockDeviceID) else {
            DebugLogger.shared.log(.audio, "Get clock device UID FAILED")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        DebugLogger.shared.log(.audio, "Aggregate clock source: \(clockSource)")
        
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
            DebugLogger.shared.log(.audio, "Create aggregate device FAILED: osstatus=\(err)")
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
            DebugLogger.shared.log(.audio, "Aggregate input format: \(Self.formatSummary(ioFormat))")
        } else {
            print("[SystemAudio] Could not read aggregate IO format (\(fmtErr)), using tap format")
            ioFormat = tapFormat
            DebugLogger.shared.log(.audio, "Aggregate format read failed (\(fmtErr)) — using tap format")
        }
        
        guard let inputFormat = AVAudioFormat(streamDescription: &ioFormat) else {
            throw AudioCaptureError.formatCreationFailed
        }
        
        let directCallback = mixWithMic ? nil : onAudioBuffer
        let targetRate = targetSampleRate
        lastSystemHeartbeat = CFAbsoluteTimeGetCurrent()
        DebugLogger.shared.log(.audio, "System path routing: mixWithMic=\(mixWithMic), directCallback=\(directCallback != nil)")
        
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
            DebugLogger.shared.log(.audio, "Create IO proc FAILED: osstatus=\(err)")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        tapDeviceProcID = procID
        
        // 7. Start the aggregate device
        err = AudioDeviceStart(aggDeviceID, procID)
        guard err == noErr else {
            print("[SystemAudio] Failed to start aggregate device: \(err)")
            DebugLogger.shared.log(.audio, "Start aggregate device FAILED: osstatus=\(err)")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        
        print("[SystemAudio] Process tap started successfully (audio-only mode)")
        DebugLogger.shared.log(.audio, "System audio tap started. Output device: \(Self.defaultOutputDeviceInfo())")
    }
    
    private func stopSystemAudioCapture() {
        if isSystemAudioActive || sysCallbackCount > 0 {
            let ringNow = currentRingSampleCount()
            DebugLogger.shared.log(
                .audio,
                "System tap stopping: callbacks=\(sysCallbackCount), inFrames=\(sysInputFrameCount), outFrames=\(sysOutputFrameCount), nonSilent=\(sysNonSilentCallbacks), silent=\(sysSilentCallbacks), ring=\(ringNow)/\(ringCapacity)"
            )
        }
        
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
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
        guard let firstBuffer = bufferList.first else { return }
        guard let rawData = firstBuffer.mData else { return }
        let byteCount = Int(firstBuffer.mDataByteSize)
        guard byteCount > 0 else { return }
        
        let asbd = inputFormat.streamDescription.pointee
        let isFloatFormat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let bitsPerChannel = Int(asbd.mBitsPerChannel)
        let bytesPerSample = bitsPerChannel / 8
        guard bytesPerSample > 0 else { return }
        
        let channels = max(1, Int(inputFormat.channelCount))
        let isInterleaved = inputFormat.isInterleaved
        let totalSamples = byteCount / bytesPerSample
        
        // Determine frame count and channel layout
        let framesPerChannel: Int
        if isInterleaved {
            framesPerChannel = totalSamples / channels
        } else {
            // Non-interleaved: each buffer is one channel
            framesPerChannel = totalSamples
        }
        guard framesPerChannel > 0 else { return }
        
        let sampleRateRatio = inputFormat.sampleRate / targetRate
        let roundedRatio = round(sampleRateRatio)
        let canUseDecimation = abs(sampleRateRatio - roundedRatio) < 0.001
        let decimation = max(1, Int(roundedRatio))
        let outputFrames = canUseDecimation
            ? (framesPerChannel / decimation)
            : Int(Double(framesPerChannel) * targetRate / inputFormat.sampleRate)
        guard outputFrames > 0 else { return }
        
        // One-time format diagnostic
        if sysCallbackCount == 0 {
            let formatLabel = isFloatFormat ? "float\(bitsPerChannel)" : "int\(bitsPerChannel)"
            let resampleMode = canUseDecimation ? "decimate(x\(decimation))" : "linear(\(String(format: "%.3f", sampleRateRatio))x)"
            let diag = "System callback format: \(inputFormat.sampleRate)Hz, \(channels)ch, \(formatLabel), interleaved=\(isInterleaved), frames=\(framesPerChannel), mode=\(resampleMode), buffers=\(bufferList.count), bytes=\(byteCount)"
            print("[SystemAudio] IO callback: \(inputFormat.sampleRate)Hz, \(channels)ch, \(formatLabel), interleaved=\(isInterleaved), frames=\(framesPerChannel), mode=\(resampleMode), mNumberBuffers=\(bufferList.count), mDataByteSize=\(byteCount)")
            DebugLogger.shared.log(.audio, diag)
        }
        
        // Step 1: Downmix to mono Float buffer. Supports float and Int16 input.
        var mono = [Float](repeating: 0, count: framesPerChannel)
        if isFloatFormat {
            let floatPtr = rawData.assumingMemoryBound(to: Float.self)
            if isInterleaved && channels >= 2 {
                // Interleaved: [L0 R0 L1 R1 ...] — add L+R with stride, then halve
                vDSP_vadd(floatPtr, vDSP_Stride(channels),
                          floatPtr + 1, vDSP_Stride(channels),
                          &mono, 1, vDSP_Length(framesPerChannel))
                var half: Float = 0.5
                vDSP_vsmul(mono, 1, &half, &mono, 1, vDSP_Length(framesPerChannel))
            } else if !isInterleaved && channels >= 2 && bufferList.count >= 2,
                      let rightData = bufferList[1].mData {
                let leftPtr = rawData.assumingMemoryBound(to: Float.self)
                let rightPtr = rightData.assumingMemoryBound(to: Float.self)
                vDSP_vadd(leftPtr, 1, rightPtr, 1, &mono, 1, vDSP_Length(framesPerChannel))
                var half: Float = 0.5
                vDSP_vsmul(mono, 1, &half, &mono, 1, vDSP_Length(framesPerChannel))
            } else {
                mono.withUnsafeMutableBufferPointer { dst in
                    dst.baseAddress?.update(from: floatPtr, count: framesPerChannel)
                }
            }
        } else if bitsPerChannel == 16 {
            let intPtr = rawData.assumingMemoryBound(to: Int16.self)
            if isInterleaved && channels >= 2 {
                for i in 0..<framesPerChannel {
                    let base = i * channels
                    mono[i] = (Float(intPtr[base]) + Float(intPtr[base + 1])) * 0.5
                }
            } else if !isInterleaved && channels >= 2 && bufferList.count >= 2,
                      let rightData = bufferList[1].mData {
                let leftPtr = rawData.assumingMemoryBound(to: Int16.self)
                let rightPtr = rightData.assumingMemoryBound(to: Int16.self)
                for i in 0..<framesPerChannel {
                    mono[i] = (Float(leftPtr[i]) + Float(rightPtr[i])) * 0.5
                }
            } else {
                for i in 0..<framesPerChannel {
                    mono[i] = Float(intPtr[i])
                }
            }
        } else {
            if sysCallbackCount == 0 {
                print("[SystemAudio] Unsupported tap format: bits=\(bitsPerChannel), flags=\(asbd.mFormatFlags)")
                DebugLogger.shared.log(.audio, "Unsupported system tap format: bits=\(bitsPerChannel), flags=\(asbd.mFormatFlags)")
            }
            return
        }
        
        var meanSquare: Float = 0
        vDSP_measqv(mono, 1, &meanSquare, vDSP_Length(framesPerChannel))
        let inputRMS = sqrt(meanSquare)
        let normalizedInputRMS = isFloatFormat ? inputRMS : (inputRMS / 32767.0)
        let now = CFAbsoluteTimeGetCurrent()
        
        sysInputFrameCount += framesPerChannel
        if normalizedInputRMS > 0.0003 {
            sysNonSilentCallbacks += 1
            lastSystemNonSilentAt = now
        } else {
            sysSilentCallbacks += 1
        }
        
        // Calculate system audio level (throttled to ~20Hz). Keep display normalized to 0...1.
        if now - lastSystemLevelUpdate > 0.05 {
            lastSystemLevelUpdate = now
            Task { @MainActor [weak self] in
                self?.systemAudioLevel = min(1.0, normalizedInputRMS)
            }
            runningSysRMS = runningSysRMS * (1 - rmsAlpha) + normalizedInputRMS * rmsAlpha
        }
        
        // Step 2: Resample to 16kHz and scale to Int16 range.
        // Integer ratios use cheap decimation (e.g. 48k→16k). Non-integer
        // ratios (e.g. 24k→16k on Bluetooth HFP) use linear interpolation.
        var scaled = [Float](repeating: 0, count: outputFrames)
        let amplitudeScale: Float = isFloatFormat ? 32767.0 : 1.0
        if canUseDecimation {
            var scale = amplitudeScale
            vDSP_vsmul(mono, vDSP_Stride(decimation), &scale, &scaled, 1, vDSP_Length(outputFrames))
        } else {
            let sourceStep = Float(inputFormat.sampleRate / targetRate)
            var sourcePos: Float = 0
            for i in 0..<outputFrames {
                let base = Int(sourcePos)
                let next = min(base + 1, framesPerChannel - 1)
                let frac = sourcePos - Float(base)
                let value = mono[base] + (mono[next] - mono[base]) * frac
                scaled[i] = value * amplitudeScale
                sourcePos += sourceStep
            }
        }
        
        // Step 3: Clamp to Int16 range
        var lo: Float = -32768
        var hi: Float = 32767
        vDSP_vclip(scaled, 1, &lo, &hi, &scaled, 1, vDSP_Length(outputFrames))
        
        // Step 4: Float32 → Int16
        var int16Out = [Int16](repeating: 0, count: outputFrames)
        vDSP_vfix16(scaled, 1, &int16Out, 1, vDSP_Length(outputFrames))
        sysOutputFrameCount += outputFrames
        
        // Diagnostic: log first callback's output values + periodic output RMS
        sysCallbackCount += 1
        if sysCallbackCount == 1 {
            let first5 = (0..<min(5, outputFrames)).map { String(int16Out[$0]) }
            // Also compute mono RMS at input for reference
            var monoMsq: Float = 0
            vDSP_measqv(mono, 1, &monoMsq, vDSP_Length(framesPerChannel))
            print("[SystemAudio] First output: frames=\(outputFrames), samples=[\(first5.joined(separator: ", "))], monoRMS=\(String(format: "%.4f", sqrt(monoMsq)))")
            DebugLogger.shared.log(.audio, "System first output: frames=\(outputFrames), samples=[\(first5.joined(separator: ", "))], inRMS=\(String(format: "%.5f", normalizedInputRMS))")
        }
        
        // Silence detection safety net (every 3s). With the built-in clock
        // source, tap stalls should not occur, but this catches unknown edge
        // cases. Threshold is 18s to avoid false positives during normal
        // conversation (one person talking while the other is silent).
        if now - lastSilenceCheck > 3.0 {
            lastSilenceCheck = now
            let silenceDuration = now - lastSystemNonSilentAt
            let hadPriorSignal = sysNonSilentCallbacks >= 120
            let cooldownElapsed = (now - lastSystemAutoRestartAt) > 45.0
            if hadPriorSignal && cooldownElapsed && silenceDuration > 18.0 {
                lastSystemAutoRestartAt = now
                DebugLogger.shared.log(
                    .audio,
                    "System tap appears stalled (silent \(String(format: "%.1f", silenceDuration))s after prior signal) — scheduling restart"
                )
                Task { @MainActor [weak self] in
                    await self?.recoverSystemTapAfterSilentStall(
                        mixWithMic: mixWithMic,
                        silenceDuration: silenceDuration
                    )
                }
            }
        }
        
        if now - lastSystemHeartbeat > 10.0 {
            lastSystemHeartbeat = now
            let ringNow = currentRingSampleCount()
            let nonSilentPct = sysCallbackCount > 0
                ? (Double(sysNonSilentCallbacks) / Double(sysCallbackCount) * 100.0)
                : 0
            DebugLogger.shared.log(
                .audio,
                "System heartbeat: callbacks=\(sysCallbackCount), inFrames=\(sysInputFrameCount), outFrames=\(sysOutputFrameCount), inRMS=\(String(format: "%.5f", normalizedInputRMS)), nonSilent=\(String(format: "%.1f", nonSilentPct))%, ring=\(ringNow)/\(ringCapacity)"
            )
            if sysCallbackCount > 60 && sysNonSilentCallbacks == 0 {
                DebugLogger.shared.log(.audio, "System warning: tap callbacks are active but all buffers are near-silent")
            }
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
            ringSamplesAppended += sampleCount
            
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
        ringSamplesDrained += drainCount
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
    private let mixScratchCapacity = 4096
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
        
        micBufferCount += 1
        if now - lastMicHeartbeat > 10.0 {
            lastMicHeartbeat = now
            let level = calculateLevelVDSP(buffer)
            let ringNow = currentRingSampleCount()
            DebugLogger.shared.log(
                .audio,
                "Mic heartbeat: buffers=\(micBufferCount), level=\(String(format: "%.5f", level)), frames=\(micSamples), mix(sys=\(mixWithSystemCount), micOnly=\(mixMicOnlyCount)), sys(cb=\(sysCallbackCount), nonSilent=\(sysNonSilentCallbacks)), ring=\(ringNow)/\(ringCapacity)"
            )
        }
        
        // Mix with buffered system audio (gain-normalized)
        if micSamples > mixScratchCapacity && now - lastNoSystemMixWarning > 5.0 {
            lastNoSystemMixWarning = now
            DebugLogger.shared.log(
                .audio,
                "Mix warning: mic frame count (\(micSamples)) exceeds scratch capacity (\(mixScratchCapacity)); draining system audio in chunks"
            )
        }
        let drainCap = min(micSamples, mixScratchCapacity)
        let sysDrained = drainRingBuffer(into: mixScratch, maxSamples: drainCap)
        
        if sysDrained > 0 {
            mixWithSystemCount += 1
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
            mixMicOnlyCount += 1
            if sysCallbackCount > 0 && now - lastNoSystemMixWarning > 5.0 {
                lastNoSystemMixWarning = now
                DebugLogger.shared.log(
                    .audio,
                    "Mix warning: no system samples drained (ring empty). sysCb=\(sysCallbackCount), sysNonSilent=\(sysNonSilentCallbacks)"
                )
            }
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
