#if os(macOS)
import Foundation
import CoreAudio
import AppKit

/// Polls Core Audio process objects once per second (off the main actor) and reports which
/// recognized call applications are running an active input stream. Emits immutable
/// `CallActivitySnapshot`s; owns no product policy and never mutates AppState directly.
///
/// Uses only public HAL properties (`kAudioHardwarePropertyProcessObjectList` and the
/// `kAudioProcessProperty*` family). No camera, Accessibility, screen contents, log
/// scraping, or private API — see docs/archive/call-lifecycle-and-recording-presence-plan.md.
@MainActor
final class CallActivityMonitor {
    var onSnapshot: ((CallActivitySnapshot) -> Void)?

    private var pollTask: Task<Void, Never>?
    private var generation = UUID()
    private let pollInterval: TimeInterval

    var isRunning: Bool { pollTask != nil }

    init(pollInterval: TimeInterval = 1.0) {
        self.pollInterval = pollInterval
    }

    func start() {
        guard pollTask == nil else { return }
        generation = UUID()
        let generation = generation
        let interval = pollInterval
        let ownPID = getpid()
        DebugLogger.shared.log(.app, "CallActivityMonitor started")
        pollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let snapshot = CallActivityMonitor.captureSnapshot(excludingPID: ownPID)
                await MainActor.run { [weak self] in
                    guard let self, self.generation == generation, self.pollTask != nil else { return }
                    self.onSnapshot?(snapshot)
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        guard pollTask != nil else { return }
        generation = UUID()
        pollTask?.cancel()
        pollTask = nil
        DebugLogger.shared.log(.app, "CallActivityMonitor stopped")
    }

    // MARK: - Snapshot capture (nonisolated; runs on the polling task)

    nonisolated static func captureSnapshot(excludingPID: pid_t, now: Date = Date()) -> CallActivitySnapshot {
        let observations = processObjectIDs().map { ids in
            ids.map { object -> CallProcessObservation in
                let pid = pidProperty(of: object)
                let input = uint32Property(kAudioProcessPropertyIsRunningInput, of: object).map { $0 == 1 }
                let output = uint32Property(kAudioProcessPropertyIsRunningOutput, of: object).map { $0 == 1 }
                return .init(pid: pid, bundleID: stringProperty(kAudioProcessPropertyBundleID, of: object),
                    ownerBundleID: (input == true || output == true) ? pid.flatMap(owningBundleID) : nil,
                    runningInput: input, runningOutput: output,
                    deviceUIDs: input == true ? deviceUIDs(of: object) : [])
            }
        }
        return CallSnapshotInterpreter.snapshot(observations, excludingPID: excludingPID, now: now)
    }

    /// Resolve each current process anew. No PID-only cache survives helper exit/reuse.
    /// Embedded helpers can expose their own app URL; the outermost known bundle owns it.
    private nonisolated static func owningBundleID(for pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        var result = app.bundleIdentifier.flatMap { CallApplicationDirectory.normalize(bundleID: $0)?.canonicalBundleID }
        var url = app.bundleURL
        var remaining = 16
        while let candidate = url, candidate.path != "/", remaining > 0 {
            if candidate.pathExtension == "app", let id = Bundle(url: candidate)?.bundleIdentifier,
               let known = CallApplicationDirectory.normalize(bundleID: id) { result = known.canonicalBundleID }
            url = candidate.deletingLastPathComponent()
            remaining -= 1
        }
        return result
    }

    // MARK: - HAL property helpers

    private nonisolated static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Nil means the query itself failed (unreliable); an empty array is a legitimate
    /// "no processes attached to the audio system" reading.
    private nonisolated static func processObjectIDs() -> [AudioObjectID]? {
        var address = globalAddress(kAudioHardwarePropertyProcessObjectList)
        var dataSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }
        guard dataSize > 0 else { return [] }
        guard dataSize <= 2048 * MemoryLayout<AudioObjectID>.size else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, buffer.baseAddress!)
        }
        guard status == noErr else { return nil }
        return ids
    }

    private nonisolated static func uint32Property(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32? {
        var address = globalAddress(selector)
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, &value) == noErr else { return nil }
        return value
    }

    private nonisolated static func pidProperty(of object: AudioObjectID) -> pid_t? {
        var address = globalAddress(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var dataSize = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, &value) == noErr else { return nil }
        return value
    }

    private nonisolated static func stringProperty(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = globalAddress(selector)
        var unmanaged: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr, let unmanaged else { return nil }
        let value = unmanaged.takeRetainedValue() as String
        return value.isEmpty ? nil : value
    }

    private nonisolated static func deviceUIDs(of processObject: AudioObjectID) -> Set<String> {
        var address = globalAddress(kAudioProcessPropertyDevices)
        address.mScope = kAudioObjectPropertyScopeInput
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(processObject, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(processObject, &address, 0, nil, &dataSize, buffer.baseAddress!)
        }
        guard status == noErr else { return [] }
        var uids: Set<String> = []
        for deviceID in ids {
            var uidAddress = globalAddress(kAudioDevicePropertyDeviceUID)
            var unmanaged: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let uidStatus = withUnsafeMutablePointer(to: &unmanaged) { pointer in
                AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, pointer)
            }
            if uidStatus == noErr, let unmanaged {
                uids.insert(unmanaged.takeRetainedValue() as String)
            }
        }
        return uids
    }
}
#endif
