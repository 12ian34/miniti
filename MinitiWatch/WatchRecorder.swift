import AVFoundation
import Foundation

/// Records the watch microphone to AAC files, rotating every `WatchRecordingProtocol.segmentSeconds`.
/// The next recorder is prepared before the current one stops so the gap is a few milliseconds.
@MainActor
final class WatchRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var manifest: WatchRecordingManifest?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var lastError: String?

    var isRecording: Bool { manifest?.state == .recording }

    /// Fires when a segment file is closed and ready to send: (manifest, segment).
    var onSegmentClosed: ((WatchRecordingManifest, WatchRecordingSegment) -> Void)?
    /// Fires when the recording stops, with the final manifest.
    var onStopped: ((WatchRecordingManifest) -> Void)?

    private let store: WatchRecordingStore
    private var recorder: AVAudioRecorder?
    private var segmentStartedAt: Date?
    private var ticker: Timer?
    private var recordingStartedAt: Date?
    private var interruptionObserver: NSObjectProtocol?

    init(store: WatchRecordingStore = .shared) {
        self.store = store
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor [weak self] in self?.handleInterruptionBegan() }
        }
    }

    static var settings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: WatchRecordingProtocol.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: WatchRecordingProtocol.bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(language: String) async {
        guard !isRecording else { return }
        lastError = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [])
            // watchOS activates asynchronously; the synchronous call blocks the main thread.
            try await session.activate(options: [])
        } catch {
            lastError = "Microphone unavailable"
            return
        }
        guard !isRecording else { return }
        let id = UUID()
        let now = Date()
        manifest = WatchRecordingManifest(
            id: id, protocolVersion: WatchRecordingProtocol.version, startedAt: now,
            endedAt: nil, language: language, state: .recording, segments: []
        )
        recordingStartedAt = now
        elapsed = 0
        store.save(manifest!)
        startSegment(index: 0, offset: 0)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func stop() {
        guard var current = manifest, current.state == .recording else { return }
        ticker?.invalidate()
        ticker = nil
        closeSegment(final: true)
        current = manifest ?? current
        current.state = .stopped
        current.endedAt = Date()
        manifest = current
        store.save(current)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onStopped?(current)
        level = 0
    }

    // MARK: - Segments

    /// A recorder with its file created and buffers allocated, so `record()` is immediate.
    private func prepareRecorder(index: Int) -> (AVAudioRecorder, String)? {
        guard let current = manifest else { return nil }
        let filename = String(format: "segment-%03d.m4a", index)
        let url = store.segmentURL(recordingID: current.id, filename: filename)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let next = try? AVAudioRecorder(url: url, settings: Self.settings) else { return nil }
        next.delegate = self
        next.isMeteringEnabled = true
        guard next.prepareToRecord() else { return nil }
        return (next, filename)
    }

    private func startSegment(index: Int, offset: TimeInterval) {
        guard let prepared = prepareRecorder(index: index) else {
            lastError = "Recording could not start"
            return
        }
        startPrepared(prepared, index: index, offset: offset)
    }

    private func startPrepared(_ prepared: (AVAudioRecorder, String), index: Int, offset: TimeInterval) {
        guard let current = manifest else { return }
        let (next, filename) = prepared
        guard next.record() else {
            lastError = "Recording could not start"
            return
        }
        recorder = next
        segmentStartedAt = Date()
        var updated = current
        updated.segments.append(WatchRecordingSegment(
            index: index, offset: offset, duration: 0, byteCount: 0, filename: filename
        ))
        manifest = updated
        store.save(updated)
    }

    /// Closes the open segment. On rotation the next recorder is fully prepared before the open
    /// one stops, so the gap is one `stop()` plus one `record()` call. If the next one cannot
    /// start, the recording ends cleanly instead of silently counting on a stopped recorder.
    private func closeSegment(final: Bool) {
        guard let current = manifest, let open = recorder, let openIndex = current.segments.last?.index else { return }
        let duration = open.currentTime
        if final {
            open.stop()
        } else {
            let nextOffset = (current.segments.last?.offset ?? 0) + duration
            let prepared = prepareRecorder(index: openIndex + 1)
            open.stop()
            if let prepared {
                startPrepared(prepared, index: openIndex + 1, offset: nextOffset)
            }
            if recorder === open {
                // The next segment did not start: finish with what we have.
                finishAfterRotationFailure(openIndex: openIndex, duration: duration)
                return
            }
        }
        guard var updated = manifest, let i = updated.segments.firstIndex(where: { $0.index == openIndex }) else { return }
        updated.segments[i].duration = duration
        updated.segments[i].byteCount = store.fileSize(recordingID: updated.id, filename: updated.segments[i].filename)
        manifest = updated
        store.save(updated)
        onSegmentClosed?(updated, updated.segments[i])
    }

    private func finishAfterRotationFailure(openIndex: Int, duration: TimeInterval) {
        ticker?.invalidate()
        ticker = nil
        guard var updated = manifest, let i = updated.segments.firstIndex(where: { $0.index == openIndex }) else { return }
        updated.segments[i].duration = duration
        updated.segments[i].byteCount = store.fileSize(recordingID: updated.id, filename: updated.segments[i].filename)
        updated.state = .interrupted
        updated.endedAt = Date()
        manifest = updated
        store.save(updated)
        recorder = nil
        level = 0
        lastError = "Recording stopped: the next file could not start"
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onSegmentClosed?(updated, updated.segments[i])
        onStopped?(updated)
    }

    private func tick() {
        guard isRecording, let recorder, let started = recordingStartedAt else { return }
        elapsed = Date().timeIntervalSince(started)
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        level = max(0, min(1, (db + 50) / 50))
        if recorder.currentTime >= WatchRecordingProtocol.segmentSeconds {
            closeSegment(final: false)
        }
    }

    // MARK: - Interruptions

    /// A call or Siri took the microphone. The recording ends cleanly with what it has; the
    /// person taps Record again afterwards, and both parts become meetings.
    private func handleInterruptionBegan() {
        guard isRecording else { return }
        stop()
        lastError = "Recording was interrupted"
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            lastError = "Recording error"
            stop()
        }
    }
}

extension WatchRecorder {
    /// Duration of an existing audio file, for segments whose recorder never closed cleanly.
    nonisolated static func measuredDuration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
