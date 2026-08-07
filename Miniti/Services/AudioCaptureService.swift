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
    nonisolated(unsafe) private var isMicActiveForWatchdog = false
    @Published var isSystemAudioActive = false
    nonisolated(unsafe) private var isSystemAudioActiveForWatchdog = false
    
    // MARK: - Ring Buffer for Stereo Interleave
    // When mic + system are both active, system PCM16 is buffered here and the
    // mic callback interleaves stereo frames for Deepgram multichannel:
    // ch0 = mic ("You"), ch1 = system (remote speakers via Deepgram diarization).
    // Pre-allocated Int16 ring buffer avoids Data allocations in the hot path.
    
    private let ringCapacity = 8000  // ~500ms at 16kHz mono (samples, not bytes)
    nonisolated(unsafe) private var ringBuffer: UnsafeMutablePointer<Int16>!
    nonisolated(unsafe) private var ringWriteIndex = 0
    nonisolated(unsafe) private var ringReadIndex = 0
    nonisolated(unsafe) private var ringCount = 0  // samples currently in buffer
    private let ringLock = NSLock()
    
    // Display-level EMA only (no longer used for Deepgram AGC).
    nonisolated(unsafe) private var runningMicRMS: Float = 0.01
    nonisolated(unsafe) private var runningSysRMS: Float = 0.01
    private let rmsAlpha: Float = 0.05
    
    // MARK: - Runtime Diagnostics
    
    nonisolated(unsafe) private var sysInputFrameCount: Int = 0
    nonisolated(unsafe) private var sysOutputFrameCount: Int = 0
    nonisolated(unsafe) private var sysNonSilentCallbacks: Int = 0
    nonisolated(unsafe) private var sysSilentCallbacks: Int = 0
    nonisolated(unsafe) private var ringSamplesAppended: Int = 0
    nonisolated(unsafe) private var ringSamplesDrained: Int = 0
    nonisolated(unsafe) private var interleaveWithSystemCount: Int = 0
    nonisolated(unsafe) private var interleaveMicPadCount: Int = 0
    nonisolated(unsafe) private var lastSystemHeartbeat: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastSystemCallbackAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastNoSystemInterleaveWarning: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastSystemNonSilentAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastSystemAutoRestartAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private var systemCallbackWatchdogArmedAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastSilenceCheck: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastSystemInputRMS: Float = 0
    // Post-recovery health tracking. After any system-tap recovery we watch the
    // next few heartbeats for the new tap being alive but silent (inRMS≈0 with
    // near-zero non-silent delta). If degraded heartbeats exceed the budget, we
    // escalate to a full capture restart (matching what user-initiated stop/continue does).
    nonisolated(unsafe) private var postRecoveryHeartbeatsRemaining: Int = 0
    nonisolated(unsafe) private var postRecoveryDegradedHeartbeats: Int = 0
    nonisolated(unsafe) private var postRecoveryBaselineCallbacks: Int = 0
    nonisolated(unsafe) private var postRecoveryBaselineNonSilent: Int = 0
    nonisolated(unsafe) private var lastFullRestartAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private var isEscalatingFullRestart = false
    private var isRestartingMicAfterConfigChange = false
    private var isRestartingSystemAfterOutputChange = false
    private var lastOutputChangeRestartAt: CFAbsoluteTime = 0
    private var pendingMicRestartTask: Task<Void, Never>?
    private var pendingMicRetryTask: Task<Void, Never>?
    private var micRetryAttempt = 0
    private let maxMicRetryAttempts = 3
    private var pendingSystemRetryTask: Task<Void, Never>?
    private var systemCallbackWatchdogTask: Task<Void, Never>?
    private var systemRetryAttempt = 0
    private let maxSystemRetryAttempts = 4
    nonisolated(unsafe) private var expectsMicAudio = false
    nonisolated(unsafe) private var expectsSystemAudio = false
    private var lastMicRestartAt: CFAbsoluteTime = 0
    private var activeMicInputDeviceID: AudioDeviceID?
    private var activeMicInputSampleRate: Double = 0
    private var activeMicInputChannels: AVAudioChannelCount = 0
    
    // MARK: - Source Dominance Tracking
    // Speaker identity is channel-based in dual-source capture (ch0=mic, ch1=system).
    // These samples are still used as corroborating evidence when AppState reconciles
    // acoustic playback leaking into the mic channel; energy alone never assigns a
    // remote system transcript to "You".
    
    struct SourceSample {
        let startTime: Double    // seconds from recording start
        let endTime: Double      // seconds from recording start
        let micEnergy: Float     // Int16-scale RMS of mic buffer
        let sysEnergy: Float     // Int16-scale RMS of system buffer
    }

    private struct SourceSampleRing {
        private var storage: [SourceSample?]
        private var startIndex = 0
        private(set) var count = 0

        nonisolated init(capacity: Int) {
            storage = Array(repeating: nil, count: max(1, capacity))
        }

        nonisolated mutating func append(_ sample: SourceSample) {
            if count < storage.count {
                storage[(startIndex + count) % storage.count] = sample
                count += 1
            } else {
                storage[startIndex] = sample
                startIndex = (startIndex + 1) % storage.count
            }
        }

        nonisolated mutating func removeAll() {
            for index in storage.indices {
                storage[index] = nil
            }
            startIndex = 0
            count = 0
        }

        nonisolated func forEachChronological(_ body: (SourceSample) -> Void) {
            guard count > 0 else { return }
            for offset in 0..<count {
                if let sample = storage[(startIndex + offset) % storage.count] {
                    body(sample)
                }
            }
        }
    }
    
    /// Rolling log of per-buffer source dominance. Accessed from mic callback thread.
    private static let sourceLogCapacity = 6000
    nonisolated(unsafe) private var sourceLog: SourceSampleRing
    private let sourceLogLock = NSLock()
    /// Cumulative frames sent to Deepgram (per channel), for stream time.
    nonisolated(unsafe) private var cumulativeSamplesSent: Int = 0
    
    /// Returns the dominant audio source for a given time range in the stream.
    /// - Returns: `.system` if system audio energy exceeded mic, `.mic` if mic was louder, `.unknown` if no data.
    enum AudioSource: Sendable { case mic, system, unknown }

    /// Whether Deepgram is receiving interleaved stereo (mic+system dual capture).
    var isSendingMultichannel: Bool {
        expectsMicAudio && expectsSystemAudio
    }

    /// Interleave mono Int16 mic (ch0) + system (ch1) into stereo PCM16.
    /// Pads system with silence when `sysCount < micCount`.
    nonisolated static func interleaveStereoInt16(
        mic: UnsafePointer<Int16>,
        micCount: Int,
        sys: UnsafePointer<Int16>,
        sysCount: Int
    ) -> Data {
        guard micCount > 0 else { return Data() }
        var data = Data(count: micCount * MemoryLayout<Int16>.size * 2)
        data.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: Int16.self)
            for i in 0..<micCount {
                out[i * 2] = mic[i]
                out[i * 2 + 1] = i < sysCount ? sys[i] : 0
            }
        }
        return data
    }

    nonisolated static func rmsInt16(_ samples: UnsafePointer<Int16>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var sumSquares: Double = 0
        for index in 0..<count {
            let sample = Double(samples[index])
            sumSquares += sample * sample
        }
        return Float(sqrt(sumSquares / Double(count)))
    }
    
    nonisolated func dominantSource(from startTime: Double, to endTime: Double) -> AudioSource {
        sourceLogLock.lock()
        defer { sourceLogLock.unlock() }
        
        let windowStart = min(startTime, endTime)
        let windowEnd = max(startTime, endTime)
        let fallbackMidpoint = (windowStart + windowEnd) * 0.5
        let fallbackMaxDistance: Double = 1.5
        
        var micWeightedTotal: Double = 0
        var sysWeightedTotal: Double = 0
        var overlapSecondsTotal: Double = 0
        var nearestSample: SourceSample?
        var nearestDistance = Double.greatestFiniteMagnitude
        
        sourceLog.forEachChronological { sample in
            let overlapStart = max(windowStart, sample.startTime)
            let overlapEnd = min(windowEnd, sample.endTime)
            if overlapEnd > overlapStart {
                let overlapSeconds = overlapEnd - overlapStart
                micWeightedTotal += Double(sample.micEnergy) * overlapSeconds
                sysWeightedTotal += Double(sample.sysEnergy) * overlapSeconds
                overlapSecondsTotal += overlapSeconds
                return
            }
            
            let distance: Double
            if fallbackMidpoint < sample.startTime {
                distance = sample.startTime - fallbackMidpoint
            } else if fallbackMidpoint > sample.endTime {
                distance = fallbackMidpoint - sample.endTime
            } else {
                distance = 0
            }
            if distance < nearestDistance {
                nearestDistance = distance
                nearestSample = sample
            }
        }
        
        if overlapSecondsTotal <= 0 {
            guard let nearestSample, nearestDistance <= fallbackMaxDistance else {
                return .unknown
            }
            micWeightedTotal = Double(nearestSample.micEnergy)
            sysWeightedTotal = Double(nearestSample.sysEnergy)
            overlapSecondsTotal = nearestSample.endTime - nearestSample.startTime
        }
        
        // Mic must show speech-level energy to be considered dominant.
        // Keyboard typing / ambient noise (~50-300 RMS) should not count.
        let avgMicEnergy = overlapSecondsTotal > 0
            ? Float(micWeightedTotal / overlapSecondsTotal)
            : 0
        let micSpeechFloor: Float = 200
        if avgMicEnergy < micSpeechFloor {
            return .system
        }
        
        // Mic must be clearly louder than system (>2x) to tag as "You".
        return micWeightedTotal > sysWeightedTotal * 2.0 ? .mic : .system
    }
    
    /// Clears source log (call when starting a new recording).
    func resetSourceTracking() {
        sourceLogLock.lock()
        sourceLog.removeAll()
        cumulativeSamplesSent = 0
        sourceLogLock.unlock()
    }

    #if DEBUG
    nonisolated func appendSourceSampleForTesting(
        startTime: Double,
        endTime: Double,
        micEnergy: Float,
        sysEnergy: Float
    ) {
        sourceLogLock.lock()
        sourceLog.append(
            SourceSample(
                startTime: startTime,
                endTime: endTime,
                micEnergy: micEnergy,
                sysEnergy: sysEnergy
            )
        )
        sourceLogLock.unlock()
    }
    #endif
    
    override init() {
        sourceLog = SourceSampleRing(capacity: Self.sourceLogCapacity)
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
            DebugLogger.shared.log(.audio, "Default INPUT device changed → \(Self.detailedInputDeviceInfo())")
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
            DebugLogger.shared.log(.audio, "Default OUTPUT device changed → \(Self.detailedOutputDeviceInfo())")
            Task { @MainActor in
                self?.handleDefaultOutputDeviceChange()
            }
        }

        // Device list changes catch Bluetooth/USB connect/disconnect events that
        // don't flip the default input/output (e.g. headphones connecting but system
        // keeping built-in as default). Without this we had silent recoveries with
        // no log trail to diagnose.
        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &devicesAddr, DispatchQueue.main
        ) { _, _ in
            DebugLogger.shared.log(
                .audio,
                "Audio device list changed — output=\(Self.detailedOutputDeviceInfo()), input=\(Self.detailedInputDeviceInfo())"
            )
        }
    }
    
    nonisolated static func defaultInputDeviceInfo() -> String {
        return deviceInfo(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    nonisolated static func defaultOutputDeviceInfo() -> String {
        return deviceInfo(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    nonisolated private static func transportTypeName(_ t: UInt32) -> String {
        switch t {
        case kAudioDeviceTransportTypeBuiltIn: return "builtin"
        case kAudioDeviceTransportTypeAggregate: return "aggregate"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        case kAudioDeviceTransportTypePCI: return "pci"
        case kAudioDeviceTransportTypeUSB: return "usb"
        case kAudioDeviceTransportTypeFireWire: return "firewire"
        case kAudioDeviceTransportTypeBluetooth: return "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "bluetooth-le"
        case kAudioDeviceTransportTypeHDMI: return "hdmi"
        case kAudioDeviceTransportTypeDisplayPort: return "displayport"
        case kAudioDeviceTransportTypeAirPlay: return "airplay"
        case kAudioDeviceTransportTypeAVB: return "avb"
        case kAudioDeviceTransportTypeThunderbolt: return "thunderbolt"
        case kAudioDeviceTransportTypeContinuityCaptureWired: return "continuity-wired"
        case kAudioDeviceTransportTypeContinuityCaptureWireless: return "continuity-wireless"
        default: return "transport:0x" + String(t, radix: 16)
        }
    }

    /// Returns "Name (48000Hz, id:N, uid:..., transport=bluetooth, profile=bluetooth-hfp-like)".
    /// Used around recovery/stall
    /// events so we can tell in the debug log whether a Bluetooth/AirPlay handoff was
    /// in play.
    nonisolated static func detailedDeviceInfo(selector: AudioObjectPropertySelector) -> String {
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

        let sampleRate = deviceNominalSampleRate(deviceID)
        let transportType = deviceTransportType(deviceID)
        let transport = transportType.map(transportTypeName) ?? "transport:?"
        let uid = deviceUID(deviceID) ?? "uid:?"
        let inputChannels = streamChannelCount(deviceID, scope: kAudioObjectPropertyScopeInput)
        let outputChannels = streamChannelCount(deviceID, scope: kAudioObjectPropertyScopeOutput)
        let profile = deviceProfileHint(
            transportType: transportType,
            sampleRate: sampleRate,
            inputChannels: inputChannels,
            outputChannels: outputChannels
        )

        return "\(name) (\(Int(sampleRate))Hz, id:\(deviceID), uid:\(uid), transport=\(transport), inCh=\(inputChannels), outCh=\(outputChannels), profile=\(profile))"
    }

    nonisolated static func detailedOutputDeviceInfo() -> String {
        return detailedDeviceInfo(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    nonisolated static func detailedInputDeviceInfo() -> String {
        return detailedDeviceInfo(selector: kAudioHardwarePropertyDefaultInputDevice)
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

    nonisolated private static func streamChannelCount(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> UInt32 {
        var streamSize: UInt32 = 0
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(deviceID, &streamAddr, 0, nil, &streamSize) == noErr,
              streamSize > 0 else { return 0 }

        let streamCount = Int(streamSize) / MemoryLayout<AudioStreamID>.size
        var streams = [AudioStreamID](repeating: 0, count: streamCount)
        guard AudioObjectGetPropertyData(deviceID, &streamAddr, 0, nil, &streamSize, &streams) == noErr else {
            return 0
        }

        return streams.reduce(UInt32(0)) { total, streamID in
            total + streamPhysicalFormat(streamID).mChannelsPerFrame
        }
    }

    nonisolated private static func streamPhysicalFormat(_ streamID: AudioStreamID) -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyPhysicalFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectGetPropertyData(streamID, &addr, 0, nil, &size, &format)
        return format
    }

    nonisolated private static func deviceProfileHint(
        transportType: UInt32?,
        sampleRate: Double,
        inputChannels: UInt32,
        outputChannels: UInt32
    ) -> String {
        guard transportType == kAudioDeviceTransportTypeBluetooth ||
              transportType == kAudioDeviceTransportTypeBluetoothLE else {
            return "n/a"
        }
        if sampleRate <= 24_000 || (inputChannels > 0 && outputChannels <= 1) {
            return "bluetooth-hfp-like"
        }
        return "bluetooth-a2dp-like"
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
        sysScratch.deinitialize(count: sysScratchCapacity)
        sysScratch.deallocate()
        systemMonoScratch.deinitialize(count: systemDSPScratchCapacity)
        systemMonoScratch.deallocate()
        systemScaledScratch.deinitialize(count: systemDSPScratchCapacity)
        systemScaledScratch.deallocate()
        systemInt16Scratch.deinitialize(count: systemDSPScratchCapacity)
        systemInt16Scratch.deallocate()
    }
    
    private func resetRuntimeDiagnostics() {
        sysInputFrameCount = 0
        sysOutputFrameCount = 0
        sysNonSilentCallbacks = 0
        sysSilentCallbacks = 0
        ringSamplesAppended = 0
        ringSamplesDrained = 0
        interleaveWithSystemCount = 0
        interleaveMicPadCount = 0
        lastSystemHeartbeat = CFAbsoluteTimeGetCurrent()
        lastSystemCallbackAt = lastSystemHeartbeat
        lastNoSystemInterleaveWarning = 0
        lastSystemNonSilentAt = lastSystemHeartbeat
        lastSystemAutoRestartAt = 0
        systemCallbackWatchdogArmedAt = lastSystemHeartbeat
        lastSilenceCheck = 0
        sysCallbackCount = 0
        postRecoveryHeartbeatsRemaining = 0
        postRecoveryDegradedHeartbeats = 0
        postRecoveryBaselineCallbacks = 0
        postRecoveryBaselineNonSilent = 0
        lastSystemInputRMS = 0
    }

    /// Begin watching the next few heartbeats for recovery that's technically
    /// "complete" (tap started, callbacks firing) but silent (inRMS≈0, no non-silent
    /// delta). Called at the end of every recovery path.
    private func beginPostRecoveryHealthCheck(reason: String) {
        postRecoveryHeartbeatsRemaining = 3
        postRecoveryDegradedHeartbeats = 0
        postRecoveryBaselineCallbacks = sysCallbackCount
        postRecoveryBaselineNonSilent = sysNonSilentCallbacks
        DebugLogger.shared.log(
            .audio,
            "Post-recovery health check armed (reason=\(reason), output=\(Self.detailedOutputDeviceInfo()))"
        )
    }
    
    nonisolated private func currentRingSampleCount() -> Int {
        ringLock.lock()
        defer { ringLock.unlock() }
        return ringCount
    }

    private func setSystemAudioActive(_ active: Bool) {
        isSystemAudioActive = active
        isSystemAudioActiveForWatchdog = active
    }
    
    private func setMicActive(_ active: Bool) {
        isMicActive = active
        isMicActiveForWatchdog = active
    }
    
    func startCapture(microphone: Bool, systemAudio: Bool) async throws {
        await stopCaptureAsync()
        
        DebugLogger.shared.log(.audio, "startCapture(mic=\(microphone), sys=\(systemAudio))")
        DebugLogger.shared.log(
            .audio,
            "Audio environment: input=\(Self.detailedInputDeviceInfo()), output=\(Self.detailedOutputDeviceInfo())"
        )
        resetRuntimeDiagnostics()
        pendingMicRetryTask?.cancel()
        pendingMicRetryTask = nil
        micRetryAttempt = 0
        pendingSystemRetryTask?.cancel()
        pendingSystemRetryTask = nil
        systemRetryAttempt = 0
        expectsMicAudio = microphone
        expectsSystemAudio = systemAudio
        var capturedAny = false
        
        if microphone {
            do {
                try await startMicrophoneCapture()
                capturedAny = true
                setMicActive(true)
            } catch {
                DebugLogger.shared.log(.audio, "Mic capture FAILED: \(error.localizedDescription)")
                setMicActive(false)
                if !systemAudio { throw error }
            }
        }
        
        if systemAudio {
            do {
                try startSystemAudioCapture(mixWithMic: microphone)
                capturedAny = true
                setSystemAudioActive(true)
            } catch {
                DebugLogger.shared.log(.audio, "System audio FAILED: \(error.localizedDescription)")
                setSystemAudioActive(false)
                if case AudioCaptureError.systemAudioPermissionDenied = error {
                    // Permission errors should not auto-retry.
                } else if capturedAny {
                    scheduleSystemTapRetry(
                        reason: "initial start failed",
                        mixWithMic: microphone
                    )
                }
                if !capturedAny { throw error }
            }
        }
        
        isCapturing = capturedAny
        startSystemCallbackWatchdogIfNeeded()
        DebugLogger.shared.log(.audio, "Capture result: mic=\(isMicActive), sys=\(isSystemAudioActive)")
    }
    
    func stopCapture() {
        if isCapturing {
            let ringNow = currentRingSampleCount()
            DebugLogger.shared.log(
                .audio,
                "Capture stop summary: micBuf=\(micBufferCount), sysCb=\(sysCallbackCount), sysNonSilent=\(sysNonSilentCallbacks), interleave(sys=\(interleaveWithSystemCount), micPad=\(interleaveMicPadCount)), ring(appended=\(ringSamplesAppended), drained=\(ringSamplesDrained), left=\(ringNow))"
            )
        }
        stopMicrophoneCapture()
        stopSystemAudioCapture()
        pendingMicRestartTask?.cancel()
        pendingMicRestartTask = nil
        pendingMicRetryTask?.cancel()
        pendingMicRetryTask = nil
        micRetryAttempt = 0
        pendingSystemRetryTask?.cancel()
        pendingSystemRetryTask = nil
        systemCallbackWatchdogTask?.cancel()
        systemCallbackWatchdogTask = nil
        systemRetryAttempt = 0
        expectsMicAudio = false
        expectsSystemAudio = false
        isCapturing = false
        setMicActive(false)
        setSystemAudioActive(false)
        resetRingBuffer()
    }
    
    private func stopCaptureAsync() async {
        if isCapturing {
            let ringNow = currentRingSampleCount()
            DebugLogger.shared.log(
                .audio,
                "Capture stop summary: micBuf=\(micBufferCount), sysCb=\(sysCallbackCount), sysNonSilent=\(sysNonSilentCallbacks), interleave(sys=\(interleaveWithSystemCount), micPad=\(interleaveMicPadCount)), ring(appended=\(ringSamplesAppended), drained=\(ringSamplesDrained), left=\(ringNow))"
            )
        }
        stopMicrophoneCapture()
        stopSystemAudioCapture()
        pendingMicRestartTask?.cancel()
        pendingMicRestartTask = nil
        pendingMicRetryTask?.cancel()
        pendingMicRetryTask = nil
        micRetryAttempt = 0
        pendingSystemRetryTask?.cancel()
        pendingSystemRetryTask = nil
        systemCallbackWatchdogTask?.cancel()
        systemCallbackWatchdogTask = nil
        systemRetryAttempt = 0
        expectsMicAudio = false
        expectsSystemAudio = false
        isCapturing = false
        setMicActive(false)
        setSystemAudioActive(false)
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
        
        DebugLogger.shared.log(.audio, "Default input device: \(Self.detailedInputDeviceInfo())")
        
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
            
            DebugLogger.shared.log(.audio, "Engine config changed — restarting mic tap. New input device: \(Self.detailedInputDeviceInfo())")
            
            self.stopMicrophoneCapture()
            do {
                try await self.startMicrophoneCapture(skipPermissionCheck: true)
                if let newFormat = self.audioEngine?.inputNode.outputFormat(forBus: 0) {
                    DebugLogger.shared.log(.audio, "Mic restart complete after config change: \(newFormat.sampleRate)Hz, \(newFormat.channelCount)ch")
                } else {
                    DebugLogger.shared.log(.audio, "Mic restart complete after config change")
                }
            } catch {
                self.setMicActive(false)
                DebugLogger.shared.log(.audio, "Mic restart FAILED after config change: \(error.localizedDescription)")
                self.scheduleMicRestartRetry(reason: "config change restart failed")
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
        
        DebugLogger.shared.log(.audio, "Output device changed during capture — scheduling system tap restart")
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRestartingSystemAfterOutputChange = false }
            
            // Allow CoreAudio route change to settle before rebuilding aggregate device.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard self.isCapturing else { return }
            
            let mixWithMic = self.isMicActive
            do {
                self.resetRingBuffer()
                self.stopSystemAudioCapture()
                try self.startSystemAudioCapture(mixWithMic: mixWithMic)
                self.setSystemAudioActive(true)
                let restartedAt = CFAbsoluteTimeGetCurrent()
                self.lastSystemNonSilentAt = restartedAt
                self.lastSystemCallbackAt = restartedAt
                self.lastSystemAutoRestartAt = restartedAt
                self.beginPostRecoveryHealthCheck(reason: "output-change restart")
                DebugLogger.shared.log(.audio, "System tap restart complete after output change")
            } catch {
                self.setSystemAudioActive(false)
                DebugLogger.shared.log(.audio, "System tap restart FAILED after output change: \(error.localizedDescription)")
                if case AudioCaptureError.systemAudioPermissionDenied = error {
                    // Permission errors should not auto-retry.
                } else {
                    self.scheduleSystemTapRetry(
                        reason: "output-change restart failed",
                        mixWithMic: mixWithMic
                    )
                }
            }
        }
    }

    private func scheduleMicRestartRetry(reason: String) {
        guard isCapturing, expectsMicAudio else { return }
        guard pendingMicRetryTask == nil else { return }
        guard micRetryAttempt < maxMicRetryAttempts else {
            DebugLogger.shared.log(
                .audio,
                "Mic auto-retry exhausted (\(micRetryAttempt) attempts), reason=\(reason)"
            )
            return
        }
        
        micRetryAttempt += 1
        let attempt = micRetryAttempt
        let delayNanos: UInt64 = [500_000_000, 1_500_000_000, 3_000_000_000][min(attempt - 1, 2)]
        let delaySec = String(format: "%.1f", Double(delayNanos) / 1_000_000_000)
        DebugLogger.shared.log(
            .audio,
            "Scheduling mic restart retry \(attempt)/\(maxMicRetryAttempts) in \(delaySec)s (\(reason))"
        )
        
        pendingMicRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else {
                self.pendingMicRetryTask = nil
                return
            }
            self.pendingMicRetryTask = nil
            guard self.isCapturing, self.expectsMicAudio else { return }
            guard !self.isMicActive else {
                self.micRetryAttempt = 0
                return
            }
            
            DebugLogger.shared.log(.audio, "Mic restart retry \(attempt)/\(self.maxMicRetryAttempts) — attempting. Input: \(Self.detailedInputDeviceInfo())")
            
            self.stopMicrophoneCapture()
            do {
                try await self.startMicrophoneCapture(skipPermissionCheck: true)
                self.setMicActive(true)
                self.micRetryAttempt = 0
                if let fmt = self.audioEngine?.inputNode.outputFormat(forBus: 0) {
                    DebugLogger.shared.log(.audio, "Mic restart retry succeeded: \(fmt.sampleRate)Hz, \(fmt.channelCount)ch")
                } else {
                    DebugLogger.shared.log(.audio, "Mic restart retry succeeded")
                }
                
                if self.isSystemAudioActive, self.expectsSystemAudio {
                    await self.restartSystemTapForMixMode()
                }
            } catch {
                self.setMicActive(false)
                DebugLogger.shared.log(.audio, "Mic restart retry FAILED: \(error.localizedDescription)")
                self.scheduleMicRestartRetry(reason: "retry \(attempt) failed")
            }
        }
    }
    
    private func restartSystemTapForMixMode() async {
        guard isCapturing, isSystemAudioActive, !isRestartingSystemAfterOutputChange else { return }
        
        DebugLogger.shared.log(.audio, "Restarting system tap with mixing after mic recovery")
        
        do {
            resetRingBuffer()
            stopSystemAudioCapture()
            try startSystemAudioCapture(mixWithMic: true)
            setSystemAudioActive(true)
            let now = CFAbsoluteTimeGetCurrent()
            lastSystemNonSilentAt = now
            lastSystemCallbackAt = now
            lastSystemAutoRestartAt = now
            beginPostRecoveryHealthCheck(reason: "mix-mode restart after mic recovery")
            DebugLogger.shared.log(.audio, "System tap restarted with mixing after mic recovery")
        } catch {
            setSystemAudioActive(false)
            DebugLogger.shared.log(.audio, "System tap mix-mode restart FAILED: \(error.localizedDescription)")
            if case AudioCaptureError.systemAudioPermissionDenied = error {
                return
            }
            scheduleSystemTapRetry(reason: "mix-mode restart failed", mixWithMic: true)
        }
    }

    nonisolated static func shouldRecoverSystemCallbackStall(
        expectsSystemAudio: Bool,
        isSystemAudioActive: Bool,
        isRecoveryInProgress: Bool,
        callbackGap: CFAbsoluteTime,
        timeSinceWatchdogArmed: CFAbsoluteTime,
        callbackCount: Int,
        timeSinceLastRestart: CFAbsoluteTime
    ) -> Bool {
        guard expectsSystemAudio, isSystemAudioActive, !isRecoveryInProgress else { return false }
        guard callbackGap > 6, timeSinceLastRestart > 45 else { return false }
        return callbackCount > 10 || timeSinceWatchdogArmed > 8
    }

    private func startSystemCallbackWatchdogIfNeeded() {
        systemCallbackWatchdogTask?.cancel()
        systemCallbackWatchdogTask = nil
        guard isCapturing, expectsSystemAudio else { return }

        systemCallbackWatchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled,
                      let self,
                      self.isCapturing,
                      self.expectsSystemAudio else { break }
                await self.checkSystemCallbackWatchdog()
            }
        }
    }

    private func checkSystemCallbackWatchdog() async {
        let now = CFAbsoluteTimeGetCurrent()
        let callbackGap = now - lastSystemCallbackAt
        let timeSinceRestart = lastSystemAutoRestartAt > 0
            ? now - lastSystemAutoRestartAt
            : .infinity
        let recoveryInProgress = isRestartingSystemAfterOutputChange
            || isEscalatingFullRestart
            || pendingSystemRetryTask != nil

        guard Self.shouldRecoverSystemCallbackStall(
            expectsSystemAudio: expectsSystemAudio,
            isSystemAudioActive: isSystemAudioActiveForWatchdog,
            isRecoveryInProgress: recoveryInProgress,
            callbackGap: callbackGap,
            timeSinceWatchdogArmed: now - systemCallbackWatchdogArmedAt,
            callbackCount: sysCallbackCount,
            timeSinceLastRestart: timeSinceRestart
        ) else { return }

        // Claim the shared cooldown before suspending so the silent-buffer detector cannot
        // schedule a second recovery for the same Core Audio failure.
        lastSystemAutoRestartAt = now
        DebugLogger.shared.log(
            .audio,
            "System tap appears callback-stalled (\(String(format: "%.1f", callbackGap))s without callbacks) — scheduling restart"
        )
        await recoverSystemTapAfterCallbackStall(
            mixWithMic: isMicActiveForWatchdog,
            callbackGap: callbackGap
        )
    }
    
    private func recoverSystemTapAfterSilentStall(
        mixWithMic: Bool,
        silenceDuration: CFAbsoluteTime
    ) async {
        guard isCapturing, isSystemAudioActive, expectsSystemAudio else { return }
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
            resetRingBuffer()
            stopSystemAudioCapture()
            try startSystemAudioCapture(mixWithMic: mixWithMic)
            setSystemAudioActive(true)
            let restartedAt = CFAbsoluteTimeGetCurrent()
            lastSystemNonSilentAt = restartedAt
            lastSystemCallbackAt = restartedAt
            lastSystemAutoRestartAt = restartedAt
            beginPostRecoveryHealthCheck(reason: "silent-stall recovery")
            DebugLogger.shared.log(.audio, "System tap recovery complete")
        } catch {
            setSystemAudioActive(false)
            DebugLogger.shared.log(.audio, "System tap recovery FAILED: \(error.localizedDescription)")
            if case AudioCaptureError.systemAudioPermissionDenied = error {
                // Permission errors should not auto-retry.
            } else {
                scheduleSystemTapRetry(
                    reason: "silent-stall recovery failed",
                    mixWithMic: mixWithMic
                )
            }
        }
    }
    
    /// Second-tier recovery when the first system-tap restart came back empty
    /// (callbacks firing but inRMS≈0 across multiple heartbeats). Mirrors what
    /// happens when the user hits stop → continue: full teardown of both mic +
    /// system, then a fresh startCapture. Only fires from the post-recovery
    /// health check, with its own cooldown so it can't loop.
    private func escalateFullCaptureRestart(
        microphone: Bool,
        systemAudio: Bool,
        reason: String
    ) async {
        guard isCapturing else { return }
        guard !isEscalatingFullRestart else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFullRestartAt > 60.0 else {
            DebugLogger.shared.log(
                .audio,
                "Full capture restart suppressed (cooldown, reason=\(reason))"
            )
            return
        }
        isEscalatingFullRestart = true
        lastFullRestartAt = now
        defer { isEscalatingFullRestart = false }

        DebugLogger.shared.log(
            .audio,
            "Full capture restart starting (reason=\(reason), input=\(Self.detailedInputDeviceInfo()), output=\(Self.detailedOutputDeviceInfo()))"
        )

        do {
            try await startCapture(microphone: microphone, systemAudio: systemAudio)
            DebugLogger.shared.log(.audio, "Full capture restart complete")
        } catch {
            DebugLogger.shared.log(.audio, "Full capture restart FAILED: \(error.localizedDescription)")
        }
    }

    private func recoverSystemTapAfterCallbackStall(
        mixWithMic: Bool,
        callbackGap: CFAbsoluteTime
    ) async {
        guard isCapturing, isSystemAudioActive, expectsSystemAudio else { return }
        guard !isRestartingSystemAfterOutputChange else { return }
        isRestartingSystemAfterOutputChange = true
        defer { isRestartingSystemAfterOutputChange = false }
        
        DebugLogger.shared.log(
            .audio,
            "System tap callback-stall recovery starting after \(String(format: "%.1f", callbackGap))s without callbacks"
        )
        
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard isCapturing else { return }
        
        do {
            resetRingBuffer()
            stopSystemAudioCapture()
            try startSystemAudioCapture(mixWithMic: mixWithMic)
            setSystemAudioActive(true)
            let restartedAt = CFAbsoluteTimeGetCurrent()
            lastSystemNonSilentAt = restartedAt
            lastSystemCallbackAt = restartedAt
            lastSystemAutoRestartAt = restartedAt
            beginPostRecoveryHealthCheck(reason: "callback-stall recovery")
            DebugLogger.shared.log(.audio, "System tap callback-stall recovery complete")
        } catch {
            setSystemAudioActive(false)
            DebugLogger.shared.log(.audio, "System tap callback-stall recovery FAILED: \(error.localizedDescription)")
            if case AudioCaptureError.systemAudioPermissionDenied = error {
                // Permission errors should not auto-retry.
            } else {
                scheduleSystemTapRetry(
                    reason: "callback-stall recovery failed",
                    mixWithMic: mixWithMic
                )
            }
        }
    }
    
    private func scheduleSystemTapRetry(reason: String, mixWithMic: Bool) {
        guard isCapturing, expectsSystemAudio else { return }
        guard pendingSystemRetryTask == nil else { return }
        guard systemRetryAttempt < maxSystemRetryAttempts else {
            DebugLogger.shared.log(
                .audio,
                "System tap auto-retry exhausted (\(systemRetryAttempt) attempts), reason=\(reason)"
            )
            return
        }
        
        systemRetryAttempt += 1
        let attempt = systemRetryAttempt
        let delaySeconds = min(8, 1 << max(0, attempt - 1))
        DebugLogger.shared.log(
            .audio,
            "Scheduling system tap retry \(attempt)/\(maxSystemRetryAttempts) in \(delaySeconds)s (\(reason))"
        )
        
        pendingSystemRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            guard !Task.isCancelled else {
                self.pendingSystemRetryTask = nil
                return
            }
            self.pendingSystemRetryTask = nil
            guard self.isCapturing, self.expectsSystemAudio else { return }
            guard !self.isSystemAudioActive else {
                self.systemRetryAttempt = 0
                return
            }
            guard !self.isRestartingSystemAfterOutputChange else {
                self.scheduleSystemTapRetry(
                    reason: "retry deferred; restart in progress",
                    mixWithMic: mixWithMic
                )
                return
            }
            
            do {
                self.resetRingBuffer()
                self.stopSystemAudioCapture()
                try self.startSystemAudioCapture(mixWithMic: mixWithMic)
                self.setSystemAudioActive(true)
                self.systemRetryAttempt = 0
                DebugLogger.shared.log(.audio, "System tap auto-retry succeeded")
            } catch {
                self.setSystemAudioActive(false)
                DebugLogger.shared.log(.audio, "System tap auto-retry FAILED: \(error.localizedDescription)")
                if case AudioCaptureError.systemAudioPermissionDenied = error {
                    return
                }
                self.scheduleSystemTapRetry(reason: "retry failed", mixWithMic: mixWithMic)
            }
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
        var started = false
        defer {
            if !started {
                stopSystemAudioCapture()
            }
        }
        
        // 1. Create a global stereo tap capturing all processes
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted
        tapDescription.name = "MinitiAudioTap"
        tapDescription.isPrivate = true
        
        var tapID: AudioObjectID = kAudioObjectUnknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            DebugLogger.shared.log(.audio, "AudioHardwareCreateProcessTap FAILED: osstatus=\(err)")
            throw AudioCaptureError.systemAudioPermissionDenied
        }
        processTapID = tapID
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
            DebugLogger.shared.log(.audio, "Read tap format FAILED: osstatus=\(err)")
            throw AudioCaptureError.formatCreationFailed
        }
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
            DebugLogger.shared.log(.audio, "Create aggregate device FAILED: osstatus=\(err)")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        aggregateDeviceID = aggDeviceID
        DebugLogger.shared.log(.audio, "Aggregate device created (#\(aggDeviceID))")
        
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
            DebugLogger.shared.log(.audio, "Aggregate input format: \(Self.formatSummary(ioFormat))")
        } else {
            ioFormat = tapFormat
            DebugLogger.shared.log(.audio, "Aggregate format read failed (\(fmtErr)) — using tap format")
        }
        
        guard let inputFormat = AVAudioFormat(streamDescription: &ioFormat) else {
            throw AudioCaptureError.formatCreationFailed
        }
        
        let directCallback = mixWithMic ? nil : onAudioBuffer
        let targetRate = targetSampleRate
        lastSystemHeartbeat = CFAbsoluteTimeGetCurrent()
        lastSystemCallbackAt = lastSystemHeartbeat
        systemCallbackWatchdogArmedAt = lastSystemHeartbeat
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
            DebugLogger.shared.log(.audio, "Create IO proc FAILED: osstatus=\(err)")
            throw AudioCaptureError.systemAudioSetupFailed
        }
        tapDeviceProcID = procID
        
        // 7. Start the aggregate device
        err = AudioDeviceStart(aggDeviceID, procID)
        guard err == noErr else {
            DebugLogger.shared.log(.audio, "Start aggregate device FAILED: osstatus=\(err)")
            throw AudioCaptureError.systemAudioSetupFailed
        }

        DebugLogger.shared.log(.audio, "System audio tap started. Output device: \(Self.detailedOutputDeviceInfo())")
        pendingSystemRetryTask?.cancel()
        pendingSystemRetryTask = nil
        systemRetryAttempt = 0
        started = true
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
    private let systemDSPScratchCapacity = 65_536
    nonisolated(unsafe) private let systemMonoScratch: UnsafeMutablePointer<Float> = {
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: 65_536)
        pointer.initialize(repeating: 0, count: 65_536)
        return pointer
    }()
    nonisolated(unsafe) private let systemScaledScratch: UnsafeMutablePointer<Float> = {
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: 65_536)
        pointer.initialize(repeating: 0, count: 65_536)
        return pointer
    }()
    nonisolated(unsafe) private let systemInt16Scratch: UnsafeMutablePointer<Int16> = {
        let pointer = UnsafeMutablePointer<Int16>.allocate(capacity: 65_536)
        pointer.initialize(repeating: 0, count: 65_536)
        return pointer
    }()
    
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
        guard framesPerChannel <= systemDSPScratchCapacity,
              outputFrames <= systemDSPScratchCapacity else {
            DebugLogger.shared.log(
                .audio,
                "System callback exceeded DSP scratch capacity: input=\(framesPerChannel), output=\(outputFrames)"
            )
            return
        }
        
        // One-time format diagnostic
        if sysCallbackCount == 0 {
            let formatLabel = isFloatFormat ? "float\(bitsPerChannel)" : "int\(bitsPerChannel)"
            let resampleMode = canUseDecimation ? "decimate(x\(decimation))" : "linear(\(String(format: "%.3f", sampleRateRatio))x)"
            let diag = "System callback format: \(inputFormat.sampleRate)Hz, \(channels)ch, \(formatLabel), interleaved=\(isInterleaved), frames=\(framesPerChannel), mode=\(resampleMode), buffers=\(bufferList.count), bytes=\(byteCount)"
            DebugLogger.shared.log(.audio, diag)
        }
        
        // Step 1: Downmix to mono Float buffer. Supports float and Int16 input.
        let mono = systemMonoScratch
        if isFloatFormat {
            let floatPtr = rawData.assumingMemoryBound(to: Float.self)
            if isInterleaved && channels >= 2 {
                // Interleaved: [L0 R0 L1 R1 ...] — add L+R with stride, then halve
                vDSP_vadd(floatPtr, vDSP_Stride(channels),
                          floatPtr + 1, vDSP_Stride(channels),
                          mono, 1, vDSP_Length(framesPerChannel))
                var half: Float = 0.5
                vDSP_vsmul(mono, 1, &half, mono, 1, vDSP_Length(framesPerChannel))
            } else if !isInterleaved && channels >= 2 && bufferList.count >= 2,
                      let rightData = bufferList[1].mData {
                let leftPtr = rawData.assumingMemoryBound(to: Float.self)
                let rightPtr = rightData.assumingMemoryBound(to: Float.self)
                vDSP_vadd(leftPtr, 1, rightPtr, 1, mono, 1, vDSP_Length(framesPerChannel))
                var half: Float = 0.5
                vDSP_vsmul(mono, 1, &half, mono, 1, vDSP_Length(framesPerChannel))
            } else {
                mono.update(from: floatPtr, count: framesPerChannel)
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
                DebugLogger.shared.log(.audio, "Unsupported system tap format: bits=\(bitsPerChannel), flags=\(asbd.mFormatFlags)")
            }
            return
        }
        
        var meanSquare: Float = 0
        vDSP_measqv(mono, 1, &meanSquare, vDSP_Length(framesPerChannel))
        let inputRMS = sqrt(meanSquare)
        let normalizedInputRMS = isFloatFormat ? inputRMS : (inputRMS / 32767.0)
        let now = CFAbsoluteTimeGetCurrent()
        lastSystemCallbackAt = now
        
        sysInputFrameCount += framesPerChannel
        lastSystemInputRMS = normalizedInputRMS
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
        let scaled = systemScaledScratch
        let amplitudeScale: Float = isFloatFormat ? 32767.0 : 1.0
        if canUseDecimation {
            var scale = amplitudeScale
            vDSP_vsmul(mono, vDSP_Stride(decimation), &scale, scaled, 1, vDSP_Length(outputFrames))
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
        vDSP_vclip(scaled, 1, &lo, &hi, scaled, 1, vDSP_Length(outputFrames))
        
        // Step 4: Float32 → Int16
        let int16Out = systemInt16Scratch
        vDSP_vfix16(scaled, 1, int16Out, 1, vDSP_Length(outputFrames))
        sysOutputFrameCount += outputFrames
        
        sysCallbackCount += 1
        if sysCallbackCount == 1 {
            let first5 = (0..<min(5, outputFrames)).map { String(int16Out[$0]) }
            var monoMsq: Float = 0
            vDSP_measqv(mono, 1, &monoMsq, vDSP_Length(framesPerChannel))
            DebugLogger.shared.log(.audio, "System first output: frames=\(outputFrames), samples=[\(first5.joined(separator: ", "))], inRMS=\(String(format: "%.5f", normalizedInputRMS)), monoRMS=\(String(format: "%.4f", sqrt(monoMsq)))")
        }
        
        // Silence detection safety net (every 2s). With the built-in clock
        // source, tap stalls should not occur, but this catches unknown edge
        // cases — primarily Bluetooth route/profile changes mid-call. Threshold
        // tightened from 18s to 8s in v1.24.0 to halve the transcript gap seen
        // when headphones connect mid-meeting.
        if now - lastSilenceCheck > 2.0 {
            lastSilenceCheck = now
            let silenceDuration = now - lastSystemNonSilentAt
            let hadPriorSignal = sysNonSilentCallbacks >= 40
            let cooldownElapsed = (now - lastSystemAutoRestartAt) > 30.0
            if hadPriorSignal && cooldownElapsed && silenceDuration > 8.0 {
                lastSystemAutoRestartAt = now
                DebugLogger.shared.log(
                    .audio,
                    "System tap appears stalled (silent \(String(format: "%.1f", silenceDuration))s after prior signal, output=\(Self.detailedOutputDeviceInfo())) — scheduling restart"
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

            // Post-recovery health evaluation: measure whether the recovered tap is
            // actually passing audio (not just firing empty callbacks). Delta-based
            // because cumulative %nonSilent barely moves after a long good stretch.
            if postRecoveryHeartbeatsRemaining > 0 {
                let deltaCallbacks = sysCallbackCount - postRecoveryBaselineCallbacks
                let deltaNonSilent = sysNonSilentCallbacks - postRecoveryBaselineNonSilent
                let deltaPct = deltaCallbacks > 0
                    ? (Double(deltaNonSilent) / Double(deltaCallbacks) * 100.0)
                    : 0
                let degraded = deltaCallbacks > 20
                    && (deltaNonSilent < 5 || (normalizedInputRMS < 0.00005 && deltaPct < 5.0))
                if degraded {
                    postRecoveryDegradedHeartbeats += 1
                }
                DebugLogger.shared.log(
                    .audio,
                    "Post-recovery health: deltaCb=\(deltaCallbacks), deltaNonSilent=\(deltaNonSilent), deltaPct=\(String(format: "%.1f", deltaPct))%, inRMS=\(String(format: "%.5f", normalizedInputRMS)), degraded=\(degraded) (\(postRecoveryDegradedHeartbeats)/\(postRecoveryHeartbeatsRemaining))"
                )
                postRecoveryHeartbeatsRemaining -= 1

                if postRecoveryDegradedHeartbeats >= 2 && !isEscalatingFullRestart {
                    DebugLogger.shared.log(
                        .audio,
                        "Post-recovery health: degraded \(postRecoveryDegradedHeartbeats)/2 heartbeats — escalating to full capture restart"
                    )
                    postRecoveryHeartbeatsRemaining = 0
                    let micWanted = expectsMicAudio
                    let sysWanted = expectsSystemAudio
                    Task { @MainActor [weak self] in
                        await self?.escalateFullCaptureRestart(
                            microphone: micWanted,
                            systemAudio: sysWanted,
                            reason: "post-recovery silent tap"
                        )
                    }
                } else if postRecoveryHeartbeatsRemaining == 0 {
                    DebugLogger.shared.log(
                        .audio,
                        "Post-recovery health: window cleared (degraded=\(postRecoveryDegradedHeartbeats)/3)"
                    )
                }
            }
        }
        
        // `Data` owns an immutable copy before the preallocated scratch storage is reused.
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
    nonisolated(unsafe) private var lastInterleaveDebugLog: CFAbsoluteTime = 0
    private let sysScratchCapacity = 4096
    // Scratch buffer for draining system audio before stereo interleave.
    nonisolated(unsafe) private let sysScratch: UnsafeMutablePointer<Int16> = {
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
                "Mic heartbeat: buffers=\(micBufferCount), level=\(String(format: "%.5f", level)), frames=\(micSamples), interleave(sys=\(interleaveWithSystemCount), micPad=\(interleaveMicPadCount)), sys(cb=\(sysCallbackCount), nonSilent=\(sysNonSilentCallbacks)), ring=\(ringNow)/\(ringCapacity)"
            )
        }
        
        let wantsMultichannel = expectsMicAudio && expectsSystemAudio
        if micSamples > sysScratchCapacity && now - lastNoSystemInterleaveWarning > 5.0 {
            lastNoSystemInterleaveWarning = now
            DebugLogger.shared.log(
                .audio,
                "Interleave warning: mic frame count (\(micSamples)) exceeds scratch capacity (\(sysScratchCapacity)); draining system audio in chunks"
            )
        }
        let drainCap = min(micSamples, sysScratchCapacity)
        let sysDrained = wantsMultichannel
            ? drainRingBuffer(into: sysScratch, maxSamples: drainCap)
            : 0
        
        if wantsMultichannel {
            // Stereo for Deepgram multichannel: always emit ch0=mic, ch1=system.
            // Pad system with silence on underrun so channel count stays stable.
            if sysDrained > 0 {
                interleaveWithSystemCount += 1
            } else {
                interleaveMicPadCount += 1
                if sysCallbackCount > 0 && now - lastNoSystemInterleaveWarning > 5.0 {
                    lastNoSystemInterleaveWarning = now
                    DebugLogger.shared.log(
                        .audio,
                        "Interleave warning: no system samples drained (ring empty). sysCb=\(sysCallbackCount), sysNonSilent=\(sysNonSilentCallbacks)"
                    )
                }
            }
            
            let micRMS = Self.rmsInt16(micPtr, count: micSamples)
            let sysRMS = Self.rmsInt16(sysScratch, count: sysDrained)
            
            let bufferStartTime = Double(cumulativeSamplesSent) / 16000.0
            let bufferEndTime = bufferStartTime + (Double(micSamples) / 16000.0)
            sourceLogLock.lock()
            sourceLog.append(SourceSample(startTime: bufferStartTime, endTime: bufferEndTime, micEnergy: micRMS, sysEnergy: sysRMS))
            sourceLogLock.unlock()
            
            if now - lastInterleaveDebugLog > 30.0 && (micRMS > 30 || sysRMS > 30) {
                lastInterleaveDebugLog = now
                DebugLogger.shared.log(
                    .audio,
                    "Audio interleave: frames=\(micSamples), sysDrained=\(sysDrained), micRMS=\(String(format: "%.0f", micRMS)), sysRMS=\(String(format: "%.0f", sysRMS))"
                )
            }
            
            cumulativeSamplesSent += micSamples
            let data = Self.interleaveStereoInt16(
                mic: micPtr,
                micCount: micSamples,
                sys: sysScratch,
                sysCount: sysDrained
            )
            callback?(data)
        } else {
            // Mic-only mono path (system-only uses the direct system callback).
            let bufferStartTime = Double(cumulativeSamplesSent) / 16000.0
            let bufferEndTime = bufferStartTime + (Double(micSamples) / 16000.0)
            sourceLogLock.lock()
            sourceLog.append(SourceSample(startTime: bufferStartTime, endTime: bufferEndTime, micEnergy: 1.0, sysEnergy: 0.0))
            sourceLogLock.unlock()
            
            cumulativeSamplesSent += micSamples
            let data = Data(bytes: micPtr, count: micSamples * MemoryLayout<Int16>.size)
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
