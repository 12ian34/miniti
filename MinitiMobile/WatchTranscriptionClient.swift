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

    struct Result: Sendable {
        let segments: [TranscriptSegmentDraft]
        /// Audio seconds Deepgram metered, from the response metadata.
        let duration: TimeInterval
    }

    struct WordTiming: Equatable, Sendable {
        let word: String
        let start: TimeInterval
        let end: TimeInterval
    }

    struct TranscriptSegmentDraft: Equatable, Sendable {
        let text: String
        let speaker: Int
        let timestamp: TimeInterval
        let confidence: Double
        /// Word timings, so the phone can relabel speakers with the on-device model.
        var words: [WordTiming] = []
    }

    enum Failure: LocalizedError {
        case http(Int, String)
        case emptyTranscript
        case tooLarge
        case unreadable

        var errorDescription: String? {
            switch self {
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
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try parse(data)
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

    static func parse(_ data: Data, offset: TimeInterval = 0) throws -> Result {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let utterances = response.results?.utterances ?? []
        let segments = utterances.compactMap { u -> TranscriptSegmentDraft? in
            let text = u.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let words = (u.words ?? []).map { WordTiming(word: $0.punctuatedWord ?? $0.word, start: offset + $0.start, end: offset + $0.end) }
            return TranscriptSegmentDraft(text: text, speaker: u.speaker ?? 0, timestamp: offset + u.start, confidence: u.confidence ?? 1, words: words)
        }
        guard !segments.isEmpty else { throw Failure.emptyTranscript }
        return Result(segments: segments, duration: response.metadata?.duration ?? (utterances.last?.end ?? 0))
    }

    // MARK: - Stitching

    /// Joins the watch's 5-minute AAC files into one without re-encoding, so Deepgram sees a single
    /// recording and keeps speaker labels consistent across the whole meeting.
    /// A part that cannot be read (a file the watch never finalised because it died mid-meeting)
    /// is skipped so the rest of the recording still becomes a meeting. Throws only when nothing
    /// is readable.
    ///
    /// Several files are re-encoded with the Apple M4A preset (about 25 kbps for 16 kHz mono,
    /// five minutes of audio in 0.2 s on a Mac). A passthrough export of a composition built from
    /// more than one file fails with "Operation Stopped, not supported for this media" (-11838),
    /// which is what every watch recording over five minutes hit in 3.1.0.
    static func stitch(_ parts: [URL], into output: URL) async throws {
        var readable: [(AVURLAsset, AVAssetTrack, CMTime)] = []
        for part in parts {
            let asset = AVURLAsset(url: part)
            guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration), duration.seconds > 0 else { continue }
            readable.append((asset, source, duration))
        }
        guard !readable.isEmpty else { throw Failure.unreadable }
        if readable.count == 1 {
            if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
            try FileManager.default.copyItem(at: readable[0].0.url, to: output)
            return
        }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.unreadable
        }
        var cursor = CMTime.zero
        for (_, source, duration) in readable {
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.unreadable
        }
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try await export.export(to: output, as: .m4a)
        // The export must have produced something Deepgram can read.
        guard let seconds = try? await AVURLAsset(url: output).load(.duration).seconds, seconds > 0 else {
            try? FileManager.default.removeItem(at: output)
            throw Failure.unreadable
        }
    }

    /// Fallback when joining fails: transcribe every part on its own and shift the timestamps.
    /// Speaker numbers restart per part, so people may get a new number after each five minutes;
    /// still a meeting rather than a permanent failure.
    static func transcribeParts(_ parts: [(url: URL, offset: TimeInterval)], language: String, credential: Credential) async throws -> Result {
        var segments: [TranscriptSegmentDraft] = []
        var duration: TimeInterval = 0
        var nextSpeakerBase = 0
        for (index, part) in parts.enumerated() {
            let one: Result
            do {
                one = try await transcribe(fileURL: part.url, language: language, credential: credential)
            } catch Failure.emptyTranscript {
                continue
            }
            let shifted = one.segments.map { s in
                TranscriptSegmentDraft(text: s.text, speaker: s.speaker + nextSpeakerBase, timestamp: s.timestamp + part.offset, confidence: s.confidence,
                                       words: s.words.map { WordTiming(word: $0.word, start: $0.start + part.offset, end: $0.end + part.offset) })
            }
            segments.append(contentsOf: shifted)
            nextSpeakerBase += (one.segments.map(\.speaker).max() ?? -1) + 1
            duration += one.duration
            DebugLogger.shared.log(.app, "Watch import: transcribed part \(index + 1) of \(parts.count) separately")
        }
        guard !segments.isEmpty else { throw Failure.emptyTranscript }
        return Result(segments: segments, duration: duration)
    }
}
