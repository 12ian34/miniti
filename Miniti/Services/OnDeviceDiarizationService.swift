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

    let sources: Set<TranscriptSource>
    private let lock = NSLock()
    private var dominant: [TranscriptSource: [UInt8]] = [:]
    /// Dominant-frame count per slot per source; a slot is mature at `slotMaturitySeconds`.
    private var slotFrames: [TranscriptSource: [Int]] = [:]
    private var fedSamples: [TranscriptSource: Int] = [:]
    /// Size of the most recent packet per source, so `markSocketStart()` can place socket
    /// time 0 at the *start* of the packet that opened the socket.
    private var lastPacketSamples: [TranscriptSource: Int] = [:]
    private var socketOriginSeconds: [TranscriptSource: Double] = [:]

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
        for frame in 0..<frameCount {
            var best = -1
            var bestProbability = threshold
            let base = frame * numSpeakers
            for slot in 0..<numSpeakers {
                let probability = probabilities[base + slot]
                if probability > bestProbability {
                    bestProbability = probability
                    best = slot
                }
            }
            if best >= 0 { frames[frame] = UInt8(best) }
        }
        lock.lock(); defer { lock.unlock() }
        dominant[source, default: []].append(contentsOf: frames)
        var counts = slotFrames[source] ?? [Int](repeating: 0, count: Int(Self.silence))
        for frame in frames where frame != Self.silence { counts[Int(frame)] += 1 }
        slotFrames[source] = counts
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
        guard let frames = dominant[source], let origin = socketOriginSeconds[source] else { return nil }
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
/// socket is opened without the diarization add-on. Every failure path leaves Deepgram
/// diarization in charge: unsupported hardware, model not downloaded, load failure, or an
/// inference error mid-session.
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
    private var models: [TranscriptSource: Nemotron3Models] = [:]
    private var prepareTask: Task<Void, Never>?
    /// The live session, read from the audio thread by `ingest`.
    nonisolated(unsafe) private var _session: Session?
    private(set) var activeTimeline: OnDeviceSpeakerTimeline?

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

    init() {
        status = Self.isHardwareSupported ? .idle : .unsupported
    }

    var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    /// One-line status for Settings.
    var statusDescription: String {
        switch status {
        case .unsupported:
            return "Needs a Mac or iPhone with Apple silicon. Deepgram separates speakers on this device."
        case .idle:
            return "Off. Turn the setting on to load the model."
        case .preparing(let fraction):
            return fraction > 0 ? "Downloading and preparing the model, \(Int((fraction * 100).rounded()))%." : "Preparing the model."
        case .ready:
            return "Ready. New recordings separate speakers on this device."
        case .failed(let message):
            return "Could not load the model (\(message)). Deepgram separates speakers until it loads."
        }
    }

    /// Download (first time) and load one model per source. Safe to call repeatedly.
    func prepare(sources: Set<TranscriptSource>) {
        guard Self.isHardwareSupported else { status = .unsupported; return }
        if prepareTask != nil { return }
        let missing = sources.filter { models[$0] == nil }
        guard !missing.isEmpty else { status = .ready; return }
        status = .preparing(0)
        prepareTask = Task { [weak self] in
            guard let self else { return }
            do {
                let bundled = Self.bundledModelDirectory
                for source in missing.sorted(by: { $0.rawValue < $1.rawValue }) {
                    let loaded: Nemotron3Models
                    if let bundled {
                        loaded = try await Nemotron3Models.load(config: Self.preset, directory: bundled, computeUnits: .all)
                    } else {
                        // Backup path: the bundle is missing its model folder (a build without
                        // the fetch phase). Download from HuggingFace into the app container.
                        DebugLogger.shared.log(.audio, "On-device diarization model not in the app bundle; downloading")
                        loaded = try await Nemotron3Models.loadFromHuggingFace(
                            config: Self.preset,
                            computeUnits: .all,
                            progressHandler: { [weak self] progress in
                                let fraction = progress.fractionCompleted
                                Task { @MainActor [weak self] in
                                    guard let self, case .preparing = self.status else { return }
                                    self.status = .preparing(fraction)
                                }
                            }
                        )
                    }
                    self.models[source] = loaded
                    DebugLogger.shared.log(.audio, "On-device diarization model ready for \(source.rawValue) from \(bundled != nil ? "bundle" : "download") (compile \(String(format: "%.1f", loaded.compilationDuration))s)")
                }
                self.status = .ready
            } catch {
                self.status = .failed(error.localizedDescription)
                DebugLogger.shared.log(.audio, "On-device diarization model load failed: \(error.localizedDescription)")
            }
            self.prepareTask = nil
        }
    }

    /// Drop loaded models (setting switched off). Active sessions keep running to their end.
    func unload() {
        prepareTask?.cancel()
        prepareTask = nil
        models = [:]
        if status != .unsupported { status = .idle }
    }

    /// Start diarizing `sources` for one recording session. Returns nil, leaving Deepgram
    /// diarization in charge, unless models for at least one requested source are loaded.
    func beginSession(sources: Set<TranscriptSource>) -> OnDeviceSpeakerTimeline? {
        guard isReady, _session == nil else { return nil }
        let usable = sources.filter { models[$0] != nil }
        guard !usable.isEmpty else { return nil }
        let timeline = OnDeviceSpeakerTimeline(sources: usable)
        var diarizers: [TranscriptSource: Nemotron3Diarizer] = [:]
        for source in usable {
            guard let model = models[source] else { continue }
            diarizers[source] = Nemotron3Diarizer(config: Self.preset, models: model)
        }
        let session = Session(timeline: timeline, diarizers: diarizers)
        _session = session
        activeTimeline = timeline
        DebugLogger.shared.log(.audio, "On-device diarization session started: sources=\(usable.map(\.rawValue).sorted())")
        return timeline
    }

    /// Stop feeding the diarizers and flush their tails. The timeline stays valid for any
    /// transcript still being parsed.
    func endSession() {
        guard let session = _session else { return }
        _session = nil
        activeTimeline = nil
        session.finish()
        DebugLogger.shared.log(.audio, "On-device diarization session ended: mic=\(String(format: "%.0f", session.timeline.processedSeconds(source: .microphone)))s system=\(String(format: "%.0f", session.timeline.processedSeconds(source: .system)))s")
    }

    /// Feed the PCM16 the app is about to send to Deepgram. Call before `sendAudio` so the
    /// socket-start alignment sees these samples. Cheap when no session is active.
    nonisolated func ingest(_ data: Data, multichannel: Bool, monoSource: TranscriptSource) {
        guard let session = _session else { return }
        session.ingest(data, multichannel: multichannel, monoSource: monoSource)
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
        let timeline: OnDeviceSpeakerTimeline
        private let queue = DispatchQueue(label: "com.miniti.onDeviceDiarization", qos: .userInitiated)
        private var diarizers: [TranscriptSource: Nemotron3Diarizer]
        private var failed = false

        init(timeline: OnDeviceSpeakerTimeline, diarizers: [TranscriptSource: Nemotron3Diarizer]) {
            self.timeline = timeline
            self.diarizers = diarizers
        }

        func ingest(_ data: Data, multichannel: Bool, monoSource: TranscriptSource) {
            let split = OnDeviceDiarizationService.splitPCM16(data, multichannel: multichannel, monoSource: monoSource)
            for (source, samples) in split where timeline.covers(source) {
                // Clock advances on the audio thread so `markSocketStart` (same thread, right
                // after this call) sees exactly the samples Deepgram is about to receive.
                timeline.noteAudioFed(source: source, sampleCount: samples.count)
                queue.async { [self] in process(source: source, samples: samples) }
            }
        }

        private func process(source: TranscriptSource, samples: [Float]) {
            guard !failed, let diarizer = diarizers[source] else { return }
            diarizer.appendAudio(samples)
            do {
                for chunk in try diarizer.processBufferedAudio() {
                    timeline.append(source: source, probabilities: chunk.probabilities, frameCount: chunk.frameCount, numSpeakers: chunk.numSpeakers)
                }
            } catch {
                failed = true
                DebugLogger.shared.log(.audio, "On-device diarization stopped for this session: \(error.localizedDescription)")
            }
        }

        func finish() {
            queue.async { [self] in
                guard !failed else { return }
                for (source, diarizer) in diarizers {
                    if let chunks = try? diarizer.finishStream() {
                        for chunk in chunks {
                            timeline.append(source: source, probabilities: chunk.probabilities, frameCount: chunk.frameCount, numSpeakers: chunk.numSpeakers)
                        }
                    }
                }
                diarizers = [:]
            }
        }
    }
}
