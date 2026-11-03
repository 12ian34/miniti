import Foundation
import FluidAudio

// MARK: - Speaker timeline

/// Per-source speaker-activity timeline written by the on-device diarizer and read by the
/// off-main Deepgram parse. One byte per 10 ms frame holds the dominant Nemotron speaker slot
/// (0…7) or `silence`. Deepgram word timestamps are socket-relative; `markSocketStart()`
/// records how much diarizer audio each source had received when the current socket started
/// sending, so a socket time maps onto the timeline as `origin + t`.
///
/// Thread-safe: written from the diarization queue and the audio thread, read from the parse
/// task. Reads are cheap (one pass over a word's frames), writes append.
final class OnDeviceSpeakerTimeline: @unchecked Sendable {
    struct Lookup: Equatable, Sendable {
        /// Provider speaker number in the same namespace Deepgram's `speaker` field uses:
        /// channel-local, arrival-ordered, stable for the whole meeting.
        let providerSpeaker: Int
        /// Share of the word's diarized frames that agree with the chosen speaker, `0…1`;
        /// `fallbackConfidence` when borrowed from a neighbour.
        let confidence: Double
    }

    static let silence: UInt8 = 255
    static let frameSeconds: Double = 0.01
    static let sampleRate: Double = 16_000
    /// A word past the diarizer horizon, or inside a pause, borrows the last active speaker
    /// from at most this far back. Longer gaps mean nobody was talking; keep the provider default.
    static let neighbourLookbackSeconds: Double = 3.0
    /// Confidence given to a borrowed speaker: below the segmentation switch gate (0.58), so a
    /// borrowed label can continue a turn but never start one.
    static let fallbackConfidence: Double = 0.3
    /// A word whose diarized frames cover less than this share of its span is treated as not
    /// yet diarized and borrows a neighbour, instead of getting a confidence discounted by
    /// coverage that the promotion gates would then reject.
    static let minimumCoverage: Double = 0.5
    /// A speaker slot must have been dominant for this much speech before any word can be
    /// attributed to it. Nemotron's arrival-order cache mints a new slot when one voice's
    /// acoustics change (a phone line, a jingle, crowd noise behind a correspondent), and a
    /// slot that never reaches this much speech was churn, not a person. Until a slot
    /// matures its words stay with the current speaker, which is how Deepgram's lag reads
    /// today. Found on BBC World Service audio in the third live test, 2026-09-26.
    static let slotMaturitySeconds: Double = 3.0

    let id = UUID()
    let sources: Set<TranscriptSource>
    private let lock = NSLock()
    private var failed = false
    private var dominant: [TranscriptSource: [UInt8]] = [:]
    /// Dominant-frame count per slot per source; a slot is mature at `slotMaturitySeconds`.
    private var slotFrames: [TranscriptSource: [Int]] = [:]
    private var fedSamples: [TranscriptSource: Int] = [:]
    /// Size of the most recent packet per source, so `markSocketStart()` can place socket
    /// time 0 at the *start* of the packet that opened the socket.
    private var lastPacketSamples: [TranscriptSource: Int] = [:]
    private var socketOriginSeconds: [TranscriptSource: Double] = [:]
    /// Voice prints: called after every append with (source, first frame index, dominant
    /// slots, exclusivity per frame). Set once by the session, before any audio.
    var onFrames: ((TranscriptSource, Int, [UInt8], [Bool]) -> Void)?

    init(sources: Set<TranscriptSource>) {
        self.sources = sources
        for source in sources {
            dominant[source] = []
            slotFrames[source] = [Int](repeating: 0, count: Int(Self.silence))
            fedSamples[source] = 0
            socketOriginSeconds[source] = 0
        }
    }

    private var maturityFrames: Int { Int(Self.slotMaturitySeconds / Self.frameSeconds) }

    /// Slots with at least `slotMaturitySeconds` of dominant speech so far.
    func matureSlots(source: TranscriptSource) -> [Int] {
        lock.lock(); defer { lock.unlock() }
        guard let counts = slotFrames[source] else { return [] }
        return counts.enumerated().filter { $0.element >= maturityFrames }.map(\.offset)
    }

    func covers(_ source: TranscriptSource) -> Bool { sources.contains(source) }

    var isReliable: Bool {
        lock.lock(); defer { lock.unlock() }
        return !failed
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        failed = true
    }

    /// Advance the diarizer clock for `source`. Call before the same samples go to Deepgram.
    func noteAudioFed(source: TranscriptSource, sampleCount: Int) {
        guard sampleCount > 0, sources.contains(source) else { return }
        lock.lock(); defer { lock.unlock() }
        fedSamples[source, default: 0] += sampleCount
        lastPacketSamples[source] = sampleCount
    }

    /// Call right after the ingest of the first packet a Deepgram socket sends: that packet's
    /// first sample is the socket's time 0, so the origin is the audio fed *before* it.
    /// (Counting the packet itself shifted every lookup late by one packet, which pushed the
    /// last words of each turn onto the next speaker in the first live test, 2026-09-26.)
    func markSocketStart() {
        lock.lock(); defer { lock.unlock() }
        for source in sources {
            let fed = fedSamples[source] ?? 0
            let packet = lastPacketSamples[source] ?? 0
            socketOriginSeconds[source] = Double(max(0, fed - packet)) / Self.sampleRate
        }
    }

    /// Append one chunk of speaker probabilities (`[frameCount * numSpeakers]`, 10 ms frames).
    func append(source: TranscriptSource, probabilities: [Float], frameCount: Int, numSpeakers: Int, threshold: Float = 0.5) {
        guard frameCount > 0, numSpeakers > 0, probabilities.count >= frameCount * numSpeakers, sources.contains(source) else { return }
        var frames = [UInt8](repeating: Self.silence, count: frameCount)
        var exclusive = [Bool](repeating: false, count: frameCount)
        for frame in 0..<frameCount {
            var best = -1
            var bestProbability = threshold
            var active = 0
            let base = frame * numSpeakers
            for slot in 0..<numSpeakers {
                let probability = probabilities[base + slot]
                if probability > threshold { active += 1 }
                if probability > bestProbability {
                    bestProbability = probability
                    best = slot
                }
            }
            if best >= 0 { frames[frame] = UInt8(best) }
            exclusive[frame] = active == 1
        }
        lock.lock()
        guard !failed else { lock.unlock(); return }
        let startFrame = dominant[source]?.count ?? 0
        dominant[source, default: []].append(contentsOf: frames)
        var counts = slotFrames[source] ?? [Int](repeating: 0, count: Int(Self.silence))
        for frame in frames where frame != Self.silence { counts[Int(frame)] += 1 }
        slotFrames[source] = counts
        let hook = onFrames
        lock.unlock()
        hook?(source, startFrame, frames, exclusive)
    }

    /// Seconds of diarizer output available for `source`.
    func processedSeconds(source: TranscriptSource) -> Double {
        lock.lock(); defer { lock.unlock() }
        return Double(dominant[source]?.count ?? 0) * Self.frameSeconds
    }

    /// Seconds of audio fed for `source`.
    func fedSeconds(source: TranscriptSource) -> Double {
        lock.lock(); defer { lock.unlock() }
        return Double(fedSamples[source] ?? 0) / Self.sampleRate
    }

    /// Speaker for a word spanning `socketStart..<socketEnd` seconds of the current socket.
    /// Majority of the dominant speaker over the word's frames; a silent or not-yet-processed
    /// span borrows the last active speaker within `neighbourLookbackSeconds`; nil otherwise.
    func lookup(source: TranscriptSource, socketStart: Double, socketEnd: Double) -> Lookup? {
        lock.lock(); defer { lock.unlock() }
        guard !failed, let frames = dominant[source], let origin = socketOriginSeconds[source] else { return nil }
        let counts = slotFrames[source] ?? []
        let mature = maturityFrames
        let isMature: (UInt8) -> Bool = { slot in slot != Self.silence && Int(slot) < counts.count && counts[Int(slot)] >= mature }
        let absoluteStart = max(0, origin + socketStart)
        let absoluteEnd = max(absoluteStart, origin + socketEnd)
        let first = Int(absoluteStart / Self.frameSeconds)
        let lastExclusive = max(first + 1, Int((absoluteEnd / Self.frameSeconds).rounded(.up)))
        let requested = lastExclusive - first
        let available = max(0, min(lastExclusive, frames.count) - first)

        let coverage = Double(available) / Double(max(requested, 1))
        if available > 0, coverage >= Self.minimumCoverage {
            var wordCounts = [Int](repeating: 0, count: 256)
            for index in first..<(first + available) where isMature(frames[index]) { wordCounts[Int(frames[index])] += 1 }
            var best = -1
            var bestCount = 0
            for slot in 0..<Int(Self.silence) where wordCounts[slot] > bestCount {
                best = slot
                bestCount = wordCounts[slot]
            }
            if best >= 0 {
                let matureTotal = wordCounts.reduce(0, +)
                let agreement = Double(bestCount) / Double(max(matureTotal, 1))
                return Lookup(providerSpeaker: best, confidence: agreement)
            }
        }

        // Silent span, only immature slots, or beyond the horizon: borrow the most recent
        // mature speaker.
        let searchEnd = min(first + available, frames.count)
        let searchStart = max(0, searchEnd - Int(Self.neighbourLookbackSeconds / Self.frameSeconds))
        var index = searchEnd - 1
        while index >= searchStart {
            if isMature(frames[index]) {
                return Lookup(providerSpeaker: Int(frames[index]), confidence: Self.fallbackConfidence)
            }
            index -= 1
        }
        return nil
    }
}

// MARK: - Service

/// Runs NVIDIA Nemotron-3-Diarization on device (Core ML via FluidAudio) on the same 16 kHz PCM
/// miniti streams to Deepgram, one diarizer per capture source. While a session is active its
/// `OnDeviceSpeakerTimeline` replaces Deepgram's per-word speaker numbers, and the Deepgram
/// socket is opened without the diarization add-on. Before start, unavailable models leave
/// provider separation enabled. Mid-session failure invalidates local labels; it does not
/// restore provider separation or initiate a reconnect.
@MainActor
final class OnDeviceDiarizationService: ObservableObject {
    enum Status: Equatable {
        /// Not Apple silicon (or Core ML unavailable); the setting is shown as unavailable.
        case unsupported
        /// Supported, nothing loaded.
        case idle
        /// Downloading or compiling; fraction in `0…1`.
        case preparing(Double)
        /// Models loaded for every requested source; sessions can start.
        case ready
        case failed(String)
    }

    /// Model-card streaming profile with 1.04 s latency; sits inside Deepgram's own
    /// finalisation delay so speaker labels never arrive after the words.
    nonisolated static let preset = Nemotron3Config.low

    /// The model ships inside the app: `Miniti/Resources/NemotronDiarizer` (a folder
    /// reference, filled by `scripts/fetch-nemotron-model.sh` as a build phase) holds the
    /// preset's `.mlmodelc` and `learnable_sil_emb.bin`. Nil when the folder is missing
    /// from the bundle, in which case the HuggingFace download is the backup.
    nonisolated static var bundledModelDirectory: URL? {
        guard let dir = Bundle.main.url(forResource: "NemotronDiarizer", withExtension: nil) else { return nil }
        let fm = FileManager.default
        let model = dir.appendingPathComponent(preset.modelFileName).appendingPathComponent("coremldata.bin")
        let silence = dir.appendingPathComponent(ModelNames.Nemotron3.silenceEmbeddingFile)
        guard fm.fileExists(atPath: model.path), fm.fileExists(atPath: silence.path) else { return nil }
        return dir
    }

    @Published private(set) var status: Status
    private(set) var preparationDurationMS: Int?
    var preparationState: String {
        switch status {
        case .idle: return "off"
        case .unsupported: return "unknown"
        case .preparing: return "preparing"
        case .ready: return "ready"
        case .failed: return "failed"
        }
    }
    enum Failure: String, Sendable { case inference, lag }
    struct Output: Sendable {
        let probabilities: [Float]
        let frameCount: Int
        let numSpeakers: Int
    }
    protocol Processor: AnyObject {
        func process(_ samples: [Float]) throws -> [Output]
        func finish() throws -> [Output]
    }
    private final class ModelProcessor: Processor {
        let diarizer: Nemotron3Diarizer
        init(_ models: Nemotron3Models) { diarizer = Nemotron3Diarizer(config: OnDeviceDiarizationService.preset, models: models) }
        func process(_ samples: [Float]) throws -> [Output] {
            diarizer.appendAudio(samples)
            return try diarizer.processBufferedAudio().map { Output(probabilities: $0.probabilities, frameCount: $0.frameCount, numSpeakers: $0.numSpeakers) }
        }
        func finish() throws -> [Output] {
            try diarizer.finishStream().map { Output(probabilities: $0.probabilities, frameCount: $0.frameCount, numSpeakers: $0.numSpeakers) }
        }
    }
    typealias ProcessorFactory = @MainActor () -> any Processor
    typealias Loader = @MainActor (TranscriptSource, @escaping @Sendable (Double) -> Void) async throws -> ProcessorFactory
    private let loader: Loader
    private let hardwareSupported: Bool
    private var preparationTimeoutTask: Task<Void, Never>?
    private var models: [TranscriptSource: ProcessorFactory] = [:]
    private var preparationGeneration = UUID()
    private var prepareTaskID: UUID?
    private let sessionLock = NSLock()
    private var retiringSession: Session?
    var onSessionFailure: ((UUID, Failure) -> Void)?
    var activeSessionID: UUID? { sessionSnapshot()?.id }
    var canRetry: Bool { prepareTask == nil && sessionSnapshot() == nil && (retiringSession?.isSettled ?? true) }

    private var prepareTask: Task<Void, Never>?
    /// The live session, read from the audio thread by `ingest`.
    nonisolated(unsafe) private var _session: Session?
    nonisolated private func sessionSnapshot() -> Session? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _session
    }
    private func setSession(_ session: Session?) {
        sessionLock.lock(); defer { sessionLock.unlock() }
        _session = session
    }
    @Published private(set) var activeTimeline: OnDeviceSpeakerTimeline?
    /// Voice print collector of the live session, when prints are on.
    private(set) var activeCollector: VoicePrintCollector?

    nonisolated static var isHardwareSupported: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let ok = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0
        return ok && value == 1
        #endif
    }

    init(loader: Loader? = nil, hardwareSupported: Bool = OnDeviceDiarizationService.isHardwareSupported) {
        self.loader = loader ?? Self.loadModel
        self.hardwareSupported = hardwareSupported
        status = hardwareSupported ? .idle : .unsupported
    }

    private static func loadModel(source: TranscriptSource, progress: @escaping @Sendable (Double) -> Void) async throws -> ProcessorFactory {
        let loaded: Nemotron3Models
        if let bundled = bundledModelDirectory {
            loaded = try await Nemotron3Models.load(config: preset, directory: bundled, computeUnits: .all)
        } else {
            loaded = try await Nemotron3Models.loadFromHuggingFace(config: preset, computeUnits: .all,
                progressHandler: { progress($0.fractionCompleted) })
        }
        return { ModelProcessor(loaded) }
    }

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    /// One-line status for Settings.
    var statusDescription: String {
        if let timeline = activeTimeline {
            return timeline.isReliable ? "Separating speakers on this device for this recording." : "Speaker separation is unavailable for this recording."
        }
        switch status {
        case .unsupported:
            return "Local speaker separation needs Apple silicon. Cloud recordings use Deepgram speakers."
        case .idle:
            return "Off. Turn the setting on to load the model."
        case .preparing(let fraction):
            return fraction > 0 ? "Downloading and preparing the model, \(Int((fraction * 100).rounded()))%." : "Preparing the model."
        case .ready:
            return "Ready. New recordings separate speakers on this device."
        case .failed:
            return "Local speaker separation is unavailable. Retry preparation before the next recording."
        }
    }

    /// Preparation never changes an active recording's route. Late cancelled loads
    /// cannot repopulate models or clear a replacement task.
    func prepare(sources: Set<TranscriptSource>) {
        guard hardwareSupported else { status = .unsupported; return }
        guard canRetry else { return }
        if let retiringSession, retiringSession.requiresModelReload { models = [:] }
        retiringSession = nil
        let missing = sources.filter { models[$0] == nil }
        guard !missing.isEmpty else { status = .ready; return }
        let generation = UUID()
        preparationGeneration = generation
        prepareTaskID = generation
        preparationDurationMS = nil
        let preparationStarted = ProcessInfo.processInfo.systemUptime
        status = .preparing(0)
        preparationTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            guard let self, self.preparationGeneration == generation, case .preparing = self.status else { return }
            self.preparationGeneration = UUID()
            self.prepareTask?.cancel()
            self.models = [:]
            self.preparationDurationMS = 120000
            self.status = .failed("load")
        }
        prepareTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.prepareTaskID == generation {
                    self.preparationTimeoutTask?.cancel(); self.preparationTimeoutTask = nil
                    self.prepareTask = nil; self.prepareTaskID = nil
                    self.objectWillChange.send()
                }
            }
            do {
                for source in missing.sorted(by: { $0.rawValue < $1.rawValue }) {
                    let factory = try await self.loader(source) { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            guard let self, self.preparationGeneration == generation, case .preparing = self.status else { return }
                            self.status = .preparing(min(1, max(0, fraction)))
                        }
                    }
                    guard !Task.isCancelled, self.preparationGeneration == generation else { return }
                    self.models[source] = factory
                }
                self.preparationDurationMS = min(3600000, Int((ProcessInfo.processInfo.systemUptime - preparationStarted) * 1000))
                self.status = .ready
            } catch {
                guard !Task.isCancelled, self.preparationGeneration == generation else { return }
                self.models = [:]
                self.preparationDurationMS = min(3600000, Int((ProcessInfo.processInfo.systemUptime - preparationStarted) * 1000))
                self.status = .failed("load")
                DebugLogger.shared.log(.audio, "Local speaker model preparation failed")
            }
        }
    }

    /// Active sessions own their processors until settlement; changing preferences
    /// affects the next recording only.
    func unload() {
        preparationGeneration = UUID()
        preparationTimeoutTask?.cancel()
        prepareTask?.cancel()
        models = [:]
        if status != .unsupported { status = .idle }
    }

    func beginSession(sources: Set<TranscriptSource>, collector: VoicePrintCollector? = nil) -> OnDeviceSpeakerTimeline? {
        if let retiringSession, retiringSession.requiresModelReload {
            models = [:]
            status = .failed("inference")
            self.retiringSession = nil
            // A previous failed worker must settle before another processor starts.
            if !retiringSession.isSettled { self.retiringSession = retiringSession }
            return nil
        }
        guard isReady, canRetry, !sources.isEmpty, sources.allSatisfy({ models[$0] != nil }) else { return nil }
        let timeline = OnDeviceSpeakerTimeline(sources: sources)
        if let collector {
            timeline.onFrames = { source, start, frames, exclusive in
                collector.noteFrames(source: source, startFrame: start, dominant: frames, exclusive: exclusive)
            }
        }
        let processors = Dictionary(uniqueKeysWithValues: sources.map { ($0, models[$0]!()) })
        let session = Session(timeline: timeline, processors: processors, collector: collector, onSettled: { [weak self] _ in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }) { [weak self] id, reason in
            Task { @MainActor [weak self] in
                guard let self, self.activeSessionID == id || (self.activeSessionID == nil && self.retiringSession?.id == id) else { return }
                if reason != .lag {
                    self.models = [:]
                    self.status = .failed(reason.rawValue)
                }
                self.activeCollector = nil
                if self.activeSessionID == id { self.onSessionFailure?(id, reason) }
            }
        }
        setSession(session)
        activeTimeline = timeline
        activeCollector = collector
        return timeline
    }

    /// Stop feeding the diarizers and flush their tails. The timeline stays valid for any
    /// transcript still being parsed.
    /// Like `endSession()` but waits for the diarizers to flush (watch recordings).
    func flushActiveSession(expectedID: UUID? = nil) async {
        guard let session = sessionSnapshot(), expectedID == nil || session.id == expectedID else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.finish { continuation.resume() }
        }
    }

    func endSessionAndWait(expectedID: UUID? = nil) async {
        guard let session = sessionSnapshot(), expectedID == nil || session.id == expectedID else { return }
        setSession(nil)
        retiringSession = session
        activeTimeline = nil
        activeCollector = nil
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.finish { c.resume() }
        }
    }

    func discardSession(expectedID: UUID? = nil) {
        guard let session = sessionSnapshot(), expectedID == nil || session.id == expectedID else { return }
        session.cancel()
        endSession(expectedID: session.id)
    }

    func endSession(expectedID: UUID? = nil) {
        guard let session = sessionSnapshot(), expectedID == nil || session.id == expectedID else { return }
        setSession(nil)
        retiringSession = session
        activeTimeline = nil
        activeCollector = nil
        session.finish()
        DebugLogger.shared.log(.audio, "On-device diarization session ended: mic=\(String(format: "%.0f", session.timeline.processedSeconds(source: .microphone)))s system=\(String(format: "%.0f", session.timeline.processedSeconds(source: .system)))s")
    }

    /// Feed the PCM16 the app is about to send to Deepgram. Call before `sendAudio` so the
    /// socket-start alignment sees these samples. Cheap when no session is active.
    /// Feed already-decoded 16 kHz mono samples for one source (watch recordings on the phone).
    nonisolated func ingest(samples: [Float], source: TranscriptSource) {
        guard let session = sessionSnapshot() else { return }
        session.ingest(samples: samples, source: source)
    }

    nonisolated func ingest(_ data: Data, multichannel: Bool, monoSource: TranscriptSource, expectedID: UUID? = nil) {
        guard let session = sessionSnapshot(), expectedID == nil || session.id == expectedID else { return }
        session.ingest(data, multichannel: multichannel, monoSource: monoSource)
    }

    /// Prerecorded callers can wait for each bounded chunk; live capture cannot.
    /// No flush/reset between chunks, and no newer session can receive this file.
    func ingestPrerecorded(samples: [Float], source: TranscriptSource, expectedID: UUID,
                           timeout: Duration = .seconds(2)) async -> Bool {
        guard let session = sessionSnapshot(), session.id == expectedID, !Task.isCancelled else { return false }
        session.ingest(samples: samples, source: source)
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while session.queuedSampleCount > 0 && session.timeline.isReliable {
            guard !Task.isCancelled, activeSessionID == expectedID else { session.cancel(); return false }
            guard ContinuousClock.now < deadline else { session.fail(.lag); return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return !Task.isCancelled && activeSessionID == expectedID && session.timeline.isReliable
    }

    /// Split the PCM16 miniti sends to Deepgram into Float samples per source. Dual capture is
    /// interleaved stereo (channel 0 mic, channel 1 system); everything else is mono.
    nonisolated static func splitPCM16(_ data: Data, multichannel: Bool, monoSource: TranscriptSource) -> [TranscriptSource: [Float]] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return [:] }
        var ints = [Int16](repeating: 0, count: sampleCount)
        _ = ints.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        let scale: Float = 1.0 / 32_768.0
        if multichannel {
            let frames = sampleCount / 2
            var mic = [Float](repeating: 0, count: frames)
            var system = [Float](repeating: 0, count: frames)
            for frame in 0..<frames {
                mic[frame] = Float(ints[frame * 2]) * scale
                system[frame] = Float(ints[frame * 2 + 1]) * scale
            }
            return [.microphone: mic, .system: system]
        }
        return [monoSource: ints.map { Float($0) * scale }]
    }

    // MARK: Session

    final class Session: @unchecked Sendable {
        let id = UUID()
        let timeline: OnDeviceSpeakerTimeline
        static let maximumQueuedSamplesPerSource = 8 * 16000
        static let maximumQueuedPackets = 128
        private let queue = DispatchQueue(label: "com.miniti.onDeviceDiarization", qos: .userInitiated)
        private let lock = NSLock()
        private var processors: [TranscriptSource: any Processor]
        private let collector: VoicePrintCollector?
        private let onFailure: @Sendable (UUID, Failure) -> Void
        private let onSettled: @Sendable (UUID) -> Void
        private var failure: Failure?
        private var failed: Bool { failure != nil }
        private var closing = false
        private var cancelled = false
        private var settled = false
        private var pendingSamples: [TranscriptSource: Int] = [:]
        private var pendingPackets = 0
        private var completions: [@Sendable () -> Void] = []
        private var completionDelivered = false

        init(timeline: OnDeviceSpeakerTimeline, processors: [TranscriptSource: any Processor], collector: VoicePrintCollector? = nil,
             onSettled: @escaping @Sendable (UUID) -> Void = { _ in },
             onFailure: @escaping @Sendable (UUID, Failure) -> Void = { _, _ in }) {
            self.timeline = timeline; self.processors = processors; self.collector = collector; self.onFailure = onFailure; self.onSettled = onSettled
        }
        var requiresModelReload: Bool { lock.lock(); defer { lock.unlock() }; return failure == .inference }
        func cancel() {
            lock.lock(); cancelled = true; lock.unlock()
            timeline.invalidate()
            collector?.invalidate()
        }
        var isSettled: Bool { lock.lock(); defer { lock.unlock() }; return settled }
        var queuedSampleCount: Int { lock.lock(); defer { lock.unlock() }; return pendingSamples.values.reduce(0, +) }

        fileprivate func fail(_ reason: Failure) {
            lock.lock()
            guard !cancelled, !failed || (failure == .lag && reason == .inference) else { lock.unlock(); return }
            failure = reason
            lock.unlock()
            timeline.invalidate()
            collector?.invalidate()
            onFailure(id, reason)
        }

        func ingest(samples: [Float], source: TranscriptSource) {
            guard timeline.covers(source), !samples.isEmpty else { return }
            lock.lock()
            guard !failed, !closing, !cancelled else { lock.unlock(); return }
            let tooFarBehind = timeline.fedSeconds(source: source) - timeline.processedSeconds(source: source) > 8
            guard pendingPackets < Self.maximumQueuedPackets,
                  (pendingSamples[source] ?? 0) + samples.count <= Self.maximumQueuedSamplesPerSource, !tooFarBehind else {
                lock.unlock(); fail(.lag); return
            }
            pendingSamples[source, default: 0] += samples.count
            pendingPackets += 1
            timeline.noteAudioFed(source: source, sampleCount: samples.count)
            // Enqueue while admission is locked so finish cannot overtake accepted audio.
            queue.async { [self] in
                defer {
                    lock.lock(); pendingSamples[source, default: 0] -= samples.count; pendingPackets -= 1; lock.unlock()
                }
                guard timeline.isReliable, let processor = processors[source] else { return }
                collector?.noteAudio(source: source, samples: samples)
                do { append(try processor.process(samples), source: source) }
                catch { fail(.inference) }
            }
            lock.unlock()
        }
        func ingest(_ data: Data, multichannel: Bool, monoSource: TranscriptSource) {
            lock.lock(); let accepting = !failed && !closing && !cancelled; lock.unlock()
            guard accepting else { return }
            // Reject oversized input before allocating decoded buffers.
            let maxBytes = Self.maximumQueuedSamplesPerSource * 2 * (multichannel ? 2 : 1)
            guard data.count <= maxBytes else { fail(.lag); return }
            for (source, samples) in OnDeviceDiarizationService.splitPCM16(data, multichannel: multichannel, monoSource: monoSource) {
                ingest(samples: samples, source: source)
            }
        }
        private func append(_ chunks: [Output], source: TranscriptSource) {
            for chunk in chunks where timeline.isReliable {
                timeline.append(source: source, probabilities: chunk.probabilities, frameCount: chunk.frameCount, numSpeakers: chunk.numSpeakers)
            }
        }
        private func complete() {
            lock.lock()
            completionDelivered = true
            let callbacks = completions; completions = []
            lock.unlock()
            callbacks.forEach { $0() }
        }
        func finish(completion: (@Sendable () -> Void)? = nil) {
            lock.lock()
            if completionDelivered { lock.unlock(); completion?(); return }
            if let completion { completions.append(completion) }
            guard !closing else { lock.unlock(); return }
            closing = true
            // Sources share a serial worker. Include pending/in-flight PCM and audio
            // buffered inside the processor but not yet represented in its timeline.
            // Budget that backlog at real-time speed plus 2 s for the model tail.
            // Live admission is 8 s per source; mic + system therefore cap at 18 s.
            let backlogSeconds = processors.keys.reduce(0.0) { total, source in
                total + max(Double(pendingSamples[source] ?? 0) / 16000,
                            timeline.fedSeconds(source: source) - timeline.processedSeconds(source: source))
            }
            let finishAllowance = min(18, 2 + backlogSeconds)
            queue.async { [self] in
                if timeline.isReliable {
                    for (source, processor) in processors {
                        do { append(try processor.finish(), source: source) }
                        catch { fail(.inference); break }
                    }
                }
                processors = [:]
                lock.lock(); settled = true; lock.unlock()
                onSettled(id)
                complete()
            }
            lock.unlock()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + finishAllowance) { [self] in
                guard !isSettled else { return }
                fail(.lag)
                complete()
            }
        }
    }
}
