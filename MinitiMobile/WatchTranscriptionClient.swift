import AVFoundation
import Foundation

/// Deepgram prerecorded transcription of a saved file, with utterances mapped to transcript segments.
/// The network call is isolated here so the mapping can be tested with fixtures.
enum WatchTranscriptionClient {
    struct Credential: Sendable {
        /// `Bearer` for a managed grant token, `Token` for a BYOK Deepgram key.
        let scheme: String
        let token: String
    }

    struct Result: Codable, Sendable {
        let segments: [TranscriptSegmentDraft]
        /// Audio seconds Deepgram metered, from the response metadata.
        let duration: TimeInterval
    }

    struct WordTiming: Codable, Equatable, Sendable {
        let word: String
        let start: TimeInterval
        let end: TimeInterval
    }

    struct TranscriptSegmentDraft: Codable, Equatable, Sendable {
        let text: String
        let speaker: Int
        let timestamp: TimeInterval
        let confidence: Double
        /// Word timings, so the phone can relabel speakers with the on-device model.
        var words: [WordTiming] = []
    }

    enum Failure: LocalizedError {
        case http(Int, String)
        case throttled(Date)
        case emptyTranscript
        case tooLarge
        case unreadable
        /// Permission for Deepgram and OpenAI was withdrawn between parts (narrowed R2).
        case permissionWithdrawn

        var errorDescription: String? {
            switch self {
            case .throttled: return "Transcription is busy. miniti will retry shortly."
            case .permissionWithdrawn: return "Permission for Deepgram and OpenAI was withdrawn."
            case .http(let code, let body): return "Transcription failed (HTTP \(code)): \(body.prefix(140))"
            case .emptyTranscript: return "No speech was found in the recording"
            case .tooLarge: return "The recording is too large to transcribe"
            case .unreadable: return "The audio files could not be read"
            }
        }
    }

    /// Deepgram allows 2 GB; at 32 kbps that is weeks, so this is a sanity bound, not a limit anyone meets.
    static let maxUploadBytes = 500 * 1024 * 1024

    static func listenURL(language: String) -> URL {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "diarize", value: "true"),
            URLQueryItem(name: "utterances", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
        ]
        return components.url!
    }

    static func transcribe(fileURL: URL, language: String, credential: Credential) async throws -> Result {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxUploadBytes else { throw Failure.tooLarge }
        var request = URLRequest(url: listenURL(language: language))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("\(credential.scheme) \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 {
            throw Failure.throttled(ClientAuthManager.retryDate((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"), now: Date()))
        }
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try parse(data, allowEmpty: true)
    }

    // MARK: - Response mapping

    struct Response: Decodable {
        struct Metadata: Decodable { let duration: Double? }
        struct Word: Decodable {
            let word: String
            let punctuatedWord: String?
            let start: Double
            let end: Double
            enum CodingKeys: String, CodingKey { case word, start, end, punctuatedWord = "punctuated_word" }
        }
        struct Utterance: Decodable {
            let start: Double
            let end: Double
            let confidence: Double?
            let transcript: String
            let speaker: Int?
            let words: [Word]?
        }
        struct Results: Decodable { let utterances: [Utterance]? }
        let metadata: Metadata?
        let results: Results?
    }

    static func parse(_ data: Data, offset: TimeInterval = 0, allowEmpty: Bool = false) throws -> Result {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let utterances = response.results?.utterances ?? []
        let segments = utterances.compactMap { u -> TranscriptSegmentDraft? in
            let text = u.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let words = (u.words ?? []).map { WordTiming(word: $0.punctuatedWord ?? $0.word, start: offset + $0.start, end: offset + $0.end) }
            return TranscriptSegmentDraft(text: text, speaker: u.speaker ?? 0, timestamp: offset + u.start, confidence: u.confidence ?? 1, words: words)
        }
        guard allowEmpty || !segments.isEmpty else { throw Failure.emptyTranscript }
        return Result(segments: segments, duration: response.metadata?.duration ?? (utterances.last?.end ?? 0))
    }

    // MARK: - Stitching

    /// Every expected part must be readable. Never publish a partial join: original parts
    /// remain available for retry or separate transcription until the full import is saved.
    static func stitch(_ parts: [URL], into output: URL) async throws {
        guard !parts.isEmpty else { throw Failure.unreadable }
        var readable: [(AVURLAsset, AVAssetTrack, CMTime)] = []
        for part in parts {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: part)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else { throw Failure.unreadable }
            let duration = try await asset.load(.duration)
            try Task.checkCancellation()
            guard duration.seconds.isFinite, duration.seconds > 0 else { throw Failure.unreadable }
            readable.append((asset, source, duration))
        }
        let expectedDuration = readable.reduce(0) { $0 + $1.2.seconds }
        let temporary = output.deletingLastPathComponent().appendingPathComponent("join-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if readable.count == 1 {
            try FileManager.default.copyItem(at: readable[0].0.url, to: temporary)
        } else {
            let composition = AVMutableComposition()
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw Failure.unreadable
            }
            var cursor = CMTime.zero
            for (_, source, duration) in readable {
                try Task.checkCancellation()
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
                cursor = CMTimeAdd(cursor, duration)
            }
            // Passthrough fails on multi-file AAC compositions; re-encode to M4A.
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
                throw Failure.unreadable
            }
            try await export.export(to: temporary, as: .m4a)
        }
        try Task.checkCancellation()
        let seconds = try await AVURLAsset(url: temporary).load(.duration).seconds
        try Task.checkCancellation()
        guard durationMatches(seconds, expected: expectedDuration, partCount: parts.count) else { throw Failure.unreadable }
        if FileManager.default.fileExists(atPath: output.path) {
            _ = try FileManager.default.replaceItemAt(output, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: output)
        }
    }

    /// Older interrupted imports may have left a valid but incomplete joined.m4a.
    /// Its mere existence is insufficient evidence that all source audio is present.
    static func canReuseJoinedAudio(_ output: URL, parts: [URL]) async throws -> Bool {
        try Task.checkCancellation()
        guard !parts.isEmpty, FileManager.default.fileExists(atPath: output.path) else { return false }
        do {
            var expected: TimeInterval = 0
            for part in parts {
                let seconds = try await AVURLAsset(url: part).load(.duration).seconds
                try Task.checkCancellation()
                guard seconds.isFinite, seconds > 0 else { return false }
                expected += seconds
            }
            let actual = try await AVURLAsset(url: output).load(.duration).seconds
            try Task.checkCancellation()
            return durationMatches(actual, expected: expected, partCount: parts.count)
        } catch {
            try Task.checkCancellation()
            return false
        }
    }

    private static func durationMatches(_ actual: TimeInterval, expected: TimeInterval, partCount: Int) -> Bool {
        // Allow AAC encoder frame padding, not a missing source part.
        actual.isFinite && actual > 0 && abs(actual - expected) <= max(0.25, Double(partCount) * 0.05)
    }

    /// Fallback when joining fails: transcribe every part on its own and shift the timestamps.
    /// Speaker numbers restart per part, so people may get a new number after each five minutes;
    /// still a meeting rather than a permanent failure.
    struct Checkpoint: Codable {
        let result: Result
        let managedSessionID: String?
        let managedOwner: String?
    }

    /// Persist a successful provider response before observing cancellation. The same
    /// checkpoint owns its metering receipt, so a later mode change cannot bill BYOK work.
    static func transcribeCached(fileURL: URL, cacheURL: URL, language: String, credential: Credential,
                                 managedSessionID: String?, managedOwner: String?,
                                 upload: ((URL) async throws -> Result)? = nil) async throws -> Result {
        if let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode(Checkpoint.self, from: data) {
            return cached.result
        }
        try Task.checkCancellation()
        // Preserve provider duration even when no speech was found. No await may
        // intervene between receiving a paid response and writing its checkpoint.
        let result: Result
        if let upload { result = try await upload(fileURL) }
        else { result = try await transcribe(fileURL: fileURL, language: language, credential: credential) }
        guard result.duration.isFinite, result.duration > 0 else { throw Failure.unreadable }
        let checkpoint = Checkpoint(result: result, managedSessionID: managedSessionID, managedOwner: managedOwner)
        try JSONEncoder().encode(checkpoint).write(to: cacheURL, options: .atomic)
        return result
    }

    /// Reassemble a complete set before asking for another provider credential.
    /// Offsets come from the Watch manifest, including silent parts.
    static func cachedParts(in directory: URL, offsets: [TimeInterval]) throws -> Result? {
        guard !offsets.isEmpty else { return nil }
        var results: [Result] = []
        for index in offsets.indices {
            let url = directory.appendingPathComponent("paid-transcription-part-\(index).json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let saved = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: url))
            guard saved.result.duration.isFinite, saved.result.duration > 0 else { throw Failure.unreadable }
            results.append(saved.result)
        }
        var segments: [TranscriptSegmentDraft] = []
        var speakerBase = 0
        for (index, result) in results.enumerated() {
            let offset = offsets[index]
            segments += result.segments.map { s in
                .init(text: s.text, speaker: s.speaker + speakerBase, timestamp: s.timestamp + offset,
                      confidence: s.confidence, words: s.words.map { .init(word: $0.word, start: $0.start + offset, end: $0.end + offset) })
            }
            speakerBase += (result.segments.map(\.speaker).max() ?? -1) + 1
        }
        return Result(segments: segments, duration: results.reduce(0) { $0 + $1.duration })
    }

    static func hasTranscriptionCheckpoints(in directory: URL) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .contains { $0.hasPrefix("paid-transcription-") && $0.hasSuffix(".json") }
    }

    static func transcriptionReceipts(in directory: URL) throws -> [String: (owner: String, minutes: Double)] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var receipts: [String: (owner: String, minutes: Double)] = [:]
        for file in files where file.lastPathComponent.hasPrefix("paid-transcription-") && file.pathExtension == "json" {
            let checkpoint = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: file))
            guard checkpoint.result.duration.isFinite, checkpoint.result.duration > 0 else { throw Failure.unreadable }
            guard let session = checkpoint.managedSessionID, let owner = checkpoint.managedOwner else { continue }
            if let previous = receipts[session], previous.owner != owner { throw Failure.unreadable }
            receipts[session] = (owner, (receipts[session]?.minutes ?? 0) + checkpoint.result.duration / 60)
        }
        return receipts
    }

    static func transcribeParts(_ parts: [(url: URL, offset: TimeInterval)], language: String, credential: Credential,
                               mayContinue: @escaping @MainActor @Sendable () -> Bool = { true },
                               cacheDirectory: URL? = nil, managedSessionID: String? = nil, managedOwner: String? = nil,
                               upload: ((URL) async throws -> Result)? = nil) async throws -> Result {
        var segments: [TranscriptSegmentDraft] = []
        var duration: TimeInterval = 0
        var nextSpeakerBase = 0
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            guard await mayContinue() else { throw Failure.permissionWithdrawn }
            let one: Result
            if let cacheDirectory {
                one = try await transcribeCached(fileURL: part.url,
                    cacheURL: cacheDirectory.appendingPathComponent("paid-transcription-part-\(index).json"),
                    language: language, credential: credential, managedSessionID: managedSessionID,
                    managedOwner: managedOwner, upload: upload)
            } else {
                do { one = try await transcribe(fileURL: part.url, language: language, credential: credential) }
                catch Failure.emptyTranscript { continue }
            }
            let shifted = one.segments.map { s in
                TranscriptSegmentDraft(text: s.text, speaker: s.speaker + nextSpeakerBase, timestamp: s.timestamp + part.offset, confidence: s.confidence,
                                       words: s.words.map { WordTiming(word: $0.word, start: $0.start + part.offset, end: $0.end + part.offset) })
            }
            segments.append(contentsOf: shifted)
            nextSpeakerBase += (one.segments.map(\.speaker).max() ?? -1) + 1
            duration += one.duration
        }
        return Result(segments: segments, duration: duration)
    }
}
