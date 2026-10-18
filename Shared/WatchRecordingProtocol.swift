import Foundation

/// The contract between the watch app and the iPhone app (3.1.0). Versioned; the phone
/// refuses payloads it cannot read instead of guessing. Every payload crosses Watch
/// Connectivity as a property-list dictionary, so only plist-safe types are used.
enum WatchRecordingProtocol {
    static let version = 1
    /// Segment length the watch rotates files at. A crash costs at most this much audio.
    static let segmentSeconds: TimeInterval = 300
    /// AAC mono at 16 kHz: speech quality at about 14 MB per hour.
    static let sampleRate: Double = 16_000
    static let bitRate = 32_000
}

/// One audio file of a recording, in order.
struct WatchRecordingSegment: Codable, Equatable, Sendable {
    let index: Int
    /// Seconds from the start of the recording to the start of this file.
    let offset: TimeInterval
    var duration: TimeInterval
    var byteCount: Int
    let filename: String
    /// Set on the watch once the phone has the file.
    var delivered = false
}

/// The recording as the watch tracks it; also sent to the phone as the final manifest.
struct WatchRecordingManifest: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case recording
        case stopped
        case interrupted
    }
    let id: UUID
    let protocolVersion: Int
    let startedAt: Date
    var endedAt: Date?
    let language: String
    var state: State
    var segments: [WatchRecordingSegment]

    var duration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }
}

/// `WCSession.transferFile` metadata for one segment.
struct WatchSegmentTransfer: Equatable, Sendable {
    let recordingID: UUID
    let index: Int
    let offset: TimeInterval
    let duration: TimeInterval
    let startedAt: Date
    let language: String
    /// True on the final manifest transfer, which carries no audio.
    let isManifest: Bool

    var dictionary: [String: Any] {
        [
            "protocol": WatchRecordingProtocol.version,
            "recording_id": recordingID.uuidString,
            "index": index,
            "offset": offset,
            "duration": duration,
            "started_at": startedAt.timeIntervalSince1970,
            "language": language,
            "manifest": isManifest,
        ]
    }

    init(recordingID: UUID, index: Int, offset: TimeInterval, duration: TimeInterval, startedAt: Date, language: String, isManifest: Bool) {
        self.recordingID = recordingID
        self.index = index
        self.offset = offset
        self.duration = duration
        self.startedAt = startedAt
        self.language = language
        self.isManifest = isManifest
    }

    init?(dictionary: [String: Any]?) {
        guard let dictionary,
              let version = dictionary["protocol"] as? Int, version == WatchRecordingProtocol.version,
              let idString = dictionary["recording_id"] as? String, let id = UUID(uuidString: idString),
              let index = dictionary["index"] as? Int,
              let startedAt = dictionary["started_at"] as? TimeInterval else { return nil }
        self.recordingID = id
        self.index = index
        self.offset = dictionary["offset"] as? TimeInterval ?? 0
        self.duration = dictionary["duration"] as? TimeInterval ?? 0
        self.startedAt = Date(timeIntervalSince1970: startedAt)
        self.language = dictionary["language"] as? String ?? "en"
        self.isManifest = dictionary["manifest"] as? Bool ?? false
    }
}

/// Phone to watch: what happened to a recording, so the watch can show it and clean up.
struct WatchReceipt: Equatable, Sendable {
    enum Status: String, Sendable {
        /// Every file is safely on the phone; the watch may delete its copy.
        case received
        case transcribing
        case waitingForMinutes = "waiting_for_minutes"
        case ready
        case failed
    }
    let recordingID: UUID
    let receivedIndexes: [Int]
    let status: Status
    let message: String?

    var dictionary: [String: Any] {
        var d: [String: Any] = [
            "protocol": WatchRecordingProtocol.version,
            "receipt": true,
            "recording_id": recordingID.uuidString,
            "received": receivedIndexes,
            "status": status.rawValue,
        ]
        if let message { d["message"] = message }
        return d
    }

    init(recordingID: UUID, receivedIndexes: [Int], status: Status, message: String? = nil) {
        self.recordingID = recordingID
        self.receivedIndexes = receivedIndexes
        self.status = status
        self.message = message
    }

    init?(dictionary: [String: Any]) {
        guard dictionary["receipt"] as? Bool == true,
              let idString = dictionary["recording_id"] as? String, let id = UUID(uuidString: idString),
              let raw = dictionary["status"] as? String, let status = Status(rawValue: raw) else { return nil }
        self.recordingID = id
        self.receivedIndexes = dictionary["received"] as? [Int] ?? []
        self.status = status
        self.message = dictionary["message"] as? String
    }
}

/// Phone to watch application context: settings the watch needs at record time.
struct WatchContext: Equatable, Sendable {
    let language: String
    let phoneName: String

    var dictionary: [String: Any] {
        ["protocol": WatchRecordingProtocol.version, "language": language, "phone_name": phoneName]
    }

    init(language: String, phoneName: String) {
        self.language = language
        self.phoneName = phoneName
    }

    init?(dictionary: [String: Any]) {
        guard let language = dictionary["language"] as? String else { return nil }
        self.language = language
        self.phoneName = dictionary["phone_name"] as? String ?? "iPhone"
    }
}
