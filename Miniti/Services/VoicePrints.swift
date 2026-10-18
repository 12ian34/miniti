import Foundation
import FluidAudio

// MARK: - Print

/// A voice fingerprint: the running mean of CAM++ embeddings (192 floats, L2-normalised) of one
/// person's speech, kept only on this device. `key` is `self` for the person using miniti or a
/// lowercased attendee email. Never synced, exported or sent anywhere.
struct VoicePrint: Codable, Equatable, Identifiable, Sendable {
    static let selfKey = "self"

    let key: String
    var displayName: String
    var email: String?
    var vector: [Float]
    /// How many meetings (or enrolments) were merged in.
    var meetings: Int
    var speechSeconds: Double
    let createdAt: Date
    var updatedAt: Date

    var id: String { key }
    var isSelf: Bool { key == Self.selfKey }

    static func normalised(_ v: [Float]) -> [Float] {
        let norm = max(sqrt(v.reduce(0) { $0 + $1 * $1 }), 1e-9)
        return v.map { $0 / norm }
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return -1 }
        return zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }
}

// MARK: - Store

/// One JSON file per print under Application Support/VoicePrints. Nothing here reaches the
/// SwiftData store, the sync document, exports or diagnostics; a test asserts that.
@MainActor
final class VoicePrintStore: ObservableObject {
    /// Weight cap on history when merging: a print never gets so settled that a changed voice
    /// (or one bad early match) cannot move it.
    static let historyCap = 10

    @Published private(set) var prints: [VoicePrint] = []
    private let root: URL

    init(root: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = root ?? support.appendingPathComponent("VoicePrints", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        prints = load()
    }

    var selfPrint: VoicePrint? { prints.first { $0.isSelf } }
    var others: [VoicePrint] { prints.filter { !$0.isSelf }.sorted { $0.updatedAt > $1.updatedAt } }

    func print(for key: String) -> VoicePrint? { prints.first { $0.key == key } }

    /// Merge a meeting's embedding into the print for `key`, creating it when new.
    @discardableResult
    func merge(key: String, displayName: String, email: String?, vector: [Float], speechSeconds: Double) -> VoicePrint {
        let now = Date()
        var print: VoicePrint
        if var existing = self.print(for: key) {
            let w = Float(min(existing.meetings, Self.historyCap))
            let merged = zip(existing.vector, vector).map { ($0 * w + $1) / (w + 1) }
            existing.vector = VoicePrint.normalised(merged)
            existing.meetings += 1
            existing.speechSeconds += speechSeconds
            existing.updatedAt = now
            if !displayName.isEmpty { existing.displayName = displayName }
            if let email { existing.email = email }
            print = existing
        } else {
            print = VoicePrint(key: key, displayName: displayName, email: email, vector: VoicePrint.normalised(vector),
                               meetings: 1, speechSeconds: speechSeconds, createdAt: now, updatedAt: now)
        }
        upsert(print)
        return print
    }

    func remove(key: String) {
        prints.removeAll { $0.key == key }
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func removeAll(keepSelf: Bool) {
        for p in prints where !(keepSelf && p.isSelf) { remove(key: p.key) }
    }

    // MARK: Files

    private func fileURL(for key: String) -> URL {
        let safe = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return root.appendingPathComponent("\(safe).json")
    }

    private func upsert(_ print: VoicePrint) {
        if let i = prints.firstIndex(where: { $0.key == print.key }) { prints[i] = print } else { prints.append(print) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(print) {
            try? data.write(to: fileURL(for: print.key), options: [.atomic])
        }
    }

    private func load() -> [VoicePrint] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(VoicePrint.self, from: data)
        }
    }
}

// MARK: - Matcher

/// Pure assignment of live speakers to prints. Thresholds come from the spike in
/// `scripts/voiceprint-poc/RESULTS.md` (2026-10-18): a 30 s per-speaker average matched every
/// speaker with no false accepts at 0.4 to 0.6 within a meeting; across microphones 0.5 kept
/// false accepts under 3% on one meeting and 7 to 12% on the harder one, which 0.6 cut to 0 to 7%
/// with the rest unassigned. Hence match at 0.60, ask between 0.45 and 0.60, ignore below.
enum VoicePrintMatcher {
    static let matchThreshold: Float = 0.60
    static let confirmThreshold: Float = 0.45
    /// Speech a speaker needs before being compared at all (single 6 s windows had an 8.5% EER).
    static let minimumSpeechSeconds: Double = 10
    /// Speech a speaker needs before their voice is learnt.
    static let learnMinimumSeconds: Double = 20

    struct Candidate: Equatable, Sendable {
        let speakerID: Int
        let vector: [Float]
        let speechSeconds: Double
    }

    struct Match: Equatable, Sendable {
        let speakerID: Int
        let print: VoicePrint
        let similarity: Float
        /// Above `matchThreshold`; otherwise it is a suggestion to confirm.
        var isConfident: Bool { similarity >= VoicePrintMatcher.matchThreshold }
    }

    /// One print per speaker and one speaker per print, highest similarity first. The self
    /// print is settled first so nobody else can take it.
    static func assign(candidates: [Candidate], prints: [VoicePrint]) -> [Match] {
        let eligible = candidates.filter { $0.speechSeconds >= minimumSpeechSeconds }
        guard !eligible.isEmpty, !prints.isEmpty else { return [] }
        var pairs: [(Float, Candidate, VoicePrint)] = []
        for c in eligible {
            for p in prints {
                let s = VoicePrint.cosine(c.vector, p.vector)
                if s >= confirmThreshold { pairs.append((s, c, p)) }
            }
        }
        pairs.sort { a, b in
            if a.2.isSelf != b.2.isSelf { return a.2.isSelf }
            return a.0 > b.0
        }
        var usedSpeakers: Set<Int> = []
        var usedPrints: Set<String> = []
        var out: [Match] = []
        for (s, c, p) in pairs where !usedSpeakers.contains(c.speakerID) && !usedPrints.contains(p.key) {
            usedSpeakers.insert(c.speakerID)
            usedPrints.insert(p.key)
            out.append(Match(speakerID: c.speakerID, print: p, similarity: s))
        }
        return out
    }
}

// MARK: - Embedder

/// Loads the CAM++ speaker embedding model (FluidAudio, two Core ML stages, about 17 MB,
/// downloaded on first use) and hands out a Sendable embedding function.
@MainActor
final class VoicePrintEmbedderService: ObservableObject {
    enum Status: Equatable {
        case idle
        case preparing
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    nonisolated(unsafe) private var embedder: CampPlusEmbedder?
    private var prepareTask: Task<Void, Never>?

    var isReady: Bool { status == .ready }

    var statusDescription: String {
        switch status {
        case .idle: return "Off."
        case .preparing: return "Downloading the voice model (about 17 MB)."
        case .ready: return "Ready."
        case .failed(let m): return "Could not load the voice model (\(m))."
        }
    }

    func prepare() {
        guard OnDeviceDiarizationService.isHardwareSupported else { status = .failed("needs Apple silicon"); return }
        guard embedder == nil, prepareTask == nil else { if embedder != nil { status = .ready }; return }
        status = .preparing
        prepareTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await CampPlusEmbedder.load()
                self.embedder = loaded
                self.status = .ready
                DebugLogger.shared.log(.audio, "Voice print model ready")
            } catch {
                self.status = .failed(error.localizedDescription)
                DebugLogger.shared.log(.audio, "Voice print model failed: \(error.localizedDescription)")
            }
            self.prepareTask = nil
        }
    }

    func unload() {
        prepareTask?.cancel()
        prepareTask = nil
        embedder = nil
        status = .idle
    }

    /// Thread-safe embedding closure for collectors, or nil until the model is loaded.
    nonisolated func embedFunction() -> (@Sendable ([Float]) async throws -> [Float])? {
        guard let embedder else { return nil }
        return { samples in try await embedder.embed(audio: samples) }
    }
}

// MARK: - Collector

/// Gathers each diarizer slot's own speech (frames where exactly one speaker is active) into
/// 6 s windows, embeds them off the audio thread, and keeps a running mean per slot. Lives for
/// one recording session next to the diarizer; the matcher reads `snapshot()`.
final class VoicePrintCollector: @unchecked Sendable {
    struct SlotVoice: Equatable, Sendable {
        let source: TranscriptSource
        let slot: Int
        let vector: [Float]
        let speechSeconds: Double
    }

    static let windowSeconds: Double = 6
    static let minimumTailSeconds: Double = 3
    /// Audio kept per source while the diarizer catches up (its latency is about 1 s).
    static let ringSeconds: Double = 60

    private let embed: @Sendable ([Float]) async throws -> [Float]
    private let lock = NSLock()
    private var ring: [TranscriptSource: [Float]] = [:]
    private var ringStart: [TranscriptSource: Int] = [:]
    private var pools: [String: [Float]] = [:]
    private var sums: [String: [Float]] = [:]
    private var counts: [String: Int] = [:]
    private var seconds: [String: Double] = [:]
    private var pending = 0

    init(embed: @escaping @Sendable ([Float]) async throws -> [Float]) {
        self.embed = embed
    }

    private static func key(_ source: TranscriptSource, _ slot: Int) -> String { "\(source.rawValue)#\(slot)" }

    /// Samples fed to the diarizer for `source`, in order. Call from the diarization queue.
    func noteAudio(source: TranscriptSource, samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        ring[source, default: []].append(contentsOf: samples)
        let cap = Int(Self.ringSeconds * OnDeviceSpeakerTimeline.sampleRate)
        if let buffer = ring[source], buffer.count > cap {
            let drop = buffer.count - cap
            ring[source] = Array(buffer.dropFirst(drop))
            ringStart[source, default: 0] += drop
        }
    }

    /// Dominant slot and exclusivity per 10 ms frame starting at `startFrame`.
    func noteFrames(source: TranscriptSource, startFrame: Int, dominant: [UInt8], exclusive: [Bool]) {
        let frameSamples = Int(OnDeviceSpeakerTimeline.frameSeconds * OnDeviceSpeakerTimeline.sampleRate)
        var ready: [(String, [Float])] = []
        lock.lock()
        guard let buffer = ring[source] else { lock.unlock(); return }
        let start = ringStart[source] ?? 0
        for i in 0..<dominant.count where dominant[i] != OnDeviceSpeakerTimeline.silence && exclusive[i] {
            let a = (startFrame + i) * frameSamples - start
            let b = a + frameSamples
            guard a >= 0, b <= buffer.count else { continue }
            let k = Self.key(source, Int(dominant[i]))
            pools[k, default: []].append(contentsOf: buffer[a..<b])
            let need = Int(Self.windowSeconds * OnDeviceSpeakerTimeline.sampleRate)
            if let pool = pools[k], pool.count >= need {
                ready.append((k, Array(pool.prefix(need))))
                pools[k] = Array(pool.dropFirst(need))
            }
        }
        pending += ready.count
        lock.unlock()
        for (k, window) in ready { embedWindow(key: k, window: window) }
    }

    private func embedWindow(key: String, window: [Float]) {
        Task { [self] in
            let vector = try? await embed(window)
            record(key: key, vector: vector, seconds: Double(window.count) / OnDeviceSpeakerTimeline.sampleRate)
        }
    }

    /// Synchronous so the lock never spans a suspension point.
    private func record(key: String, vector: [Float]?, seconds windowSeconds: Double) {
        lock.lock(); defer { lock.unlock() }
        pending -= 1
        guard let vector else { return }
        if var sum = sums[key] { for i in 0..<sum.count { sum[i] += vector[i] }; sums[key] = sum } else { sums[key] = vector }
        counts[key, default: 0] += 1
        seconds[key, default: 0] += windowSeconds
    }

    private func takeTails() -> [(String, [Float])] {
        lock.lock(); defer { lock.unlock() }
        var tails: [(String, [Float])] = []
        for (k, pool) in pools where Double(pool.count) / OnDeviceSpeakerTimeline.sampleRate >= Self.minimumTailSeconds {
            tails.append((k, pool))
        }
        pools = [:]
        pending += tails.count
        return tails
    }

    private var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    /// Embed what is left in every pool (at least `minimumTailSeconds`) and wait for the work.
    func finish() async {
        for (k, window) in takeTails() { embedWindow(key: k, window: window) }
        for _ in 0..<200 {
            if pendingCount == 0 { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func snapshot() -> [SlotVoice] {
        lock.lock(); defer { lock.unlock() }
        return sums.compactMap { k, sum in
            guard let n = counts[k], n > 0 else { return nil }
            let parts = k.split(separator: "#")
            guard parts.count == 2, let source = TranscriptSource(rawValue: String(parts[0])), let slot = Int(parts[1]) else { return nil }
            return SlotVoice(source: source, slot: slot, vector: VoicePrint.normalised(sum.map { $0 / Float(n) }), speechSeconds: seconds[k] ?? 0)
        }
    }
}
