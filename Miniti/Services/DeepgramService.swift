import Foundation
import Combine

// MARK: - Transcription Language

enum TranscriptionLanguage: String, CaseIterable, Codable {
    case english = "en"
    case spanish = "es"
    case swedish = "sv"
    case greek = "el"
    case french = "fr"
    case german = "de"
    case portuguese = "pt"
    case italian = "it"
    case dutch = "nl"
    case polish = "pl"
    case russian = "ru"
    
    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .spanish: return "🇪🇸"
        case .swedish: return "🇸🇪"
        case .greek: return "🇬🇷"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .portuguese: return "🇵🇹"
        case .italian: return "🇮🇹"
        case .dutch: return "🇳🇱"
        case .polish: return "🇵🇱"
        case .russian: return "🇷🇺"
        }
    }
    
    var displayName: String {
        switch self {
        case .english: return "\(flag) English"
        case .spanish: return "\(flag) Español"
        case .swedish: return "\(flag) Svenska"
        case .greek: return "\(flag) Ελληνικά"
        case .french: return "\(flag) Français"
        case .german: return "\(flag) Deutsch"
        case .portuguese: return "\(flag) Português"
        case .italian: return "\(flag) Italiano"
        case .dutch: return "\(flag) Nederlands"
        case .polish: return "\(flag) Polski"
        case .russian: return "\(flag) Русский"
        }
    }
    
    var englishName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .swedish: return "Swedish"
        case .greek: return "Greek"
        case .french: return "French"
        case .german: return "German"
        case .portuguese: return "Portuguese"
        case .italian: return "Italian"
        case .dutch: return "Dutch"
        case .polish: return "Polish"
        case .russian: return "Russian"
        }
    }
    
    var defaultFillers: [String] {
        switch self {
        case .english:
            // Hesitation entries must match Deepgram's filler vocabulary verbatim
            // (uh, um, mhmm, uh-huh, ...) — it never emits "hmm", "hm" or "er".
            return ["um", "uh", "mhmm", "mhm", "ah", "like", "basically", "literally",
                    "actually", "honestly", "uh huh", "you know", "i mean", "kind of", "sort of"]
        case .spanish:
            return ["eh", "este", "bueno", "o sea", "pues", "es que", "digamos", "entonces", "a ver"]
        case .swedish:
            return ["eh", "öh", "liksom", "typ", "alltså", "asså", "va", "ju", "ba"]
        case .greek:
            return ["ε", "εε", "δηλαδή", "κοίτα", "λοιπόν", "ας πούμε", "τέλος πάντων"]
        case .french:
            return ["euh", "ben", "genre", "en fait", "du coup", "voilà", "quoi", "bah", "bon"]
        case .german:
            return ["äh", "ähm", "halt", "also", "sozusagen", "quasi", "irgendwie", "na ja", "genau"]
        case .portuguese:
            return ["é", "né", "tipo", "assim", "então", "bom", "quer dizer", "enfim"]
        case .italian:
            return ["ehm", "cioè", "tipo", "allora", "praticamente", "insomma", "diciamo", "boh"]
        case .dutch:
            return ["eh", "uhm", "eigenlijk", "zeg maar", "weet je", "dus", "nou", "gewoon"]
        case .polish:
            return ["ee", "no", "w sumie", "jakby", "znaczy", "generalnie", "w zasadzie", "tak naprawdę"]
        case .russian:
            return ["эм", "ну", "вот", "типа", "короче", "как бы", "в общем", "значит", "так сказать"]
        }
    }
}

enum PersonalDictionaryPreferences {
    static let storageKey = "personalDictionaryTerms.v1"
    static let correctionsStorageKey = "personalDictionaryCorrections.v1"
    static let systemKeyterms = ["Miniti", "Lightdash", "Ahuja"]
    static let maxCorrections = 100

    struct CorrectionPair: Codable, Equatable, Hashable, Identifiable, Sendable {
        /// Normalized find text (trimmed, whitespace-collapsed, lowercased).
        var heard: String
        /// Replacement text as the user typed it (trimmed, whitespace-collapsed).
        var correct: String

        var id: String { heard }
    }

    static func currentTerms(defaults: UserDefaults = .standard) -> [String] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return normalizedTerms(decoded)
    }

    static func save(_ terms: [String], defaults: UserDefaults = .standard) {
        let normalized = normalizedTerms(terms)
        guard !normalized.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }

        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func currentCorrections(defaults: UserDefaults = .standard) -> [CorrectionPair] {
        guard let data = defaults.data(forKey: correctionsStorageKey),
              let decoded = try? JSONDecoder().decode([CorrectionPair].self, from: data) else {
            return []
        }
        return normalizedCorrections(decoded)
    }

    /// Persist correction pairs. Also adds each `correct` value to the term list
    /// when missing so the next Deepgram connect learns the preferred spelling.
    static func saveCorrections(_ pairs: [CorrectionPair], defaults: UserDefaults = .standard) {
        let normalized = normalizedCorrections(pairs)
        guard !normalized.isEmpty else {
            defaults.removeObject(forKey: correctionsStorageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: correctionsStorageKey)

        var terms = currentTerms(defaults: defaults)
        var termKeys = Set(terms.map { $0.lowercased() })
        var termsChanged = false
        for pair in normalized {
            let key = pair.correct.lowercased()
            guard !termKeys.contains(key) else { continue }
            terms.append(pair.correct)
            termKeys.insert(key)
            termsChanged = true
        }
        if termsChanged {
            save(terms, defaults: defaults)
        }
    }

    /// Outcome of adding one correction from any surface (live pill, trim view,
    /// Settings). Callers must not report success on `.invalid` or `.full`.
    enum UpsertResult: Equatable {
        case saved
        /// The pair normalized to nothing (empty side, or heard == correct).
        case invalid
        /// The store already holds `maxCorrections` other pairs.
        case full
    }

    /// Add or replace the correction for `heard`. An existing pair with the same
    /// normalized `heard` is replaced (last write wins) rather than silently
    /// dropped by the first-wins dedupe in `normalizedCorrections`.
    @discardableResult
    static func upsertCorrection(
        heard: String,
        correct: String,
        defaults: UserDefaults = .standard
    ) -> UpsertResult {
        guard let incoming = normalizedCorrections([CorrectionPair(heard: heard, correct: correct)]).first else {
            return .invalid
        }
        var pairs = currentCorrections(defaults: defaults)
        if let existing = pairs.firstIndex(where: { $0.heard == incoming.heard }) {
            pairs[existing] = incoming
        } else {
            guard pairs.count < maxCorrections else { return .full }
            pairs.append(incoming)
        }
        saveCorrections(pairs, defaults: defaults)
        return .saved
    }

    static func normalizedCorrections(_ pairs: [CorrectionPair]) -> [CorrectionPair] {
        var seen = Set<String>()
        var normalized: [CorrectionPair] = []
        for pair in pairs {
            // Colons are stripped: Deepgram's `replace=find:replacement` splits on
            // the colon, so a colon inside either side would corrupt the pair.
            let heardAsTyped = pair.heard
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let heard = heardAsTyped.lowercased()
            let correct = pair.correct
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard !heard.isEmpty, !correct.isEmpty else { continue }
            // Only an exact identity is meaningless. A capitals-only fix ("lightdash"
            // to "Lightdash") is the most common correction for a product or person
            // name: the matcher is case-insensitive and Deepgram `replace` keeps the
            // replacement's case, so it works everywhere the pair is applied.
            guard heardAsTyped != correct else { continue }
            guard !seen.contains(heard) else { continue }
            seen.insert(heard)
            normalized.append(CorrectionPair(heard: heard, correct: correct))
            if normalized.count >= maxCorrections { break }
        }
        return normalized
    }

    static func normalizedTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for term in terms {
            let compacted = term
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard !compacted.isEmpty else { continue }

            let key = compacted.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            normalized.append(compacted)
        }

        return normalized
    }

    static func deepgramKeyterms(personalTerms: [String], sessionTerms: [String] = []) -> [String] {
        var seen = Set<String>()
        var keyterms: [String] = []

        // Cap at Nova-3's keyterm budget; keep system + personal terms first.
        let maxKeyterms = 100
        for term in systemKeyterms + normalizedTerms(personalTerms) + normalizedTerms(sessionTerms) {
            guard keyterms.count < maxKeyterms else { break }
            let key = term.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            keyterms.append(term)
        }

        return keyterms
    }

    /// Deepgram `replace=heard:correct` query items. Cap matches the correction store.
    static func deepgramReplaceItems(corrections: [CorrectionPair]) -> [URLQueryItem] {
        normalizedCorrections(corrections).prefix(maxCorrections).map { pair in
            URLQueryItem(name: "replace", value: "\(pair.heard):\(pair.correct)")
        }
    }

    /// Build ephemeral Deepgram keyterms from meeting/calendar context.
    /// Prefer attendee names and company domains; include a short meeting title when useful.
    static func sessionKeyterms(
        meetingTitle: String?,
        attendees: [(displayName: String?, domain: String, isSelf: Bool)]
    ) -> [String] {
        var terms: [String] = []
        let consumerDomains: Set<String> = [
            "gmail", "googlemail", "yahoo", "hotmail", "outlook", "icloud",
            "me", "live", "msn", "aol", "proton", "protonmail", "hey"
        ]

        if let title = meetingTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            let lowered = title.lowercased()
            if lowered != "untitled" && lowered != "new" && title.count <= 80 {
                terms.append(title)
            }
        }

        for attendee in attendees where !attendee.isSelf {
            if let name = attendee.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                terms.append(name)
            }
            let domain = attendee.domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !domain.isEmpty else { continue }
            let company = domain.split(separator: ".").first.map(String.init) ?? ""
            guard company.count >= 3, !consumerDomains.contains(company) else { continue }
            // Preserve a readable casing for prompting (Acme from acme.com).
            terms.append(company.prefix(1).uppercased() + company.dropFirst())
        }

        return normalizedTerms(terms)
    }
}

/// Selection helpers for dictionary corrections (live + saved transcript).
enum TranscriptCorrectionSelection {
    /// Snap a selection outward to word boundaries for dictionary corrections.
    static func snappedHeardText(
        in storage: NSAttributedString,
        selectedRange: NSRange,
        finalizedLength: Int,
        maxCharacters: Int = 80
    ) -> String? {
        guard selectedRange.length > 0,
              selectedRange.location >= 0,
              NSMaxRange(selectedRange) <= finalizedLength,
              NSMaxRange(selectedRange) <= storage.length else {
            return nil
        }
        let nsString = storage.string as NSString
        var wordStart = selectedRange.location
        var wordEnd = NSMaxRange(selectedRange)
        // Scan only a bounded window around the selection. This runs on every
        // selection change while dragging, and the live document grows without
        // bound; a full-document word enumeration here is a hot-path violation.
        // The window is wider than `maxCharacters`, so anything it cannot reach
        // would be rejected by the length cap anyway.
        let windowStart = max(0, selectedRange.location - maxCharacters)
        let windowEnd = min(nsString.length, NSMaxRange(selectedRange) + maxCharacters)
        nsString.enumerateSubstrings(
            in: NSRange(location: windowStart, length: windowEnd - windowStart),
            options: [.byWords, .substringNotRequired]
        ) { _, substringRange, _, stop in
            if selectedRange.location < NSMaxRange(substringRange)
                && NSMaxRange(selectedRange) > substringRange.location {
                wordStart = min(wordStart, substringRange.location)
                wordEnd = max(wordEnd, NSMaxRange(substringRange))
            }
            if substringRange.location > NSMaxRange(selectedRange) {
                stop.pointee = true
            }
        }
        let snapped = NSRange(location: wordStart, length: max(0, wordEnd - wordStart))
        guard snapped.length > 0, NSMaxRange(snapped) <= finalizedLength else { return nil }
        let raw = nsString.substring(with: snapped)
        // A selection that crosses a paragraph would swallow the next turn's
        // speaker header into the "heard" phrase. Corrections are single-turn.
        guard raw.rangeOfCharacter(from: .newlines) == nil else { return nil }
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !collapsed.isEmpty, collapsed.count <= maxCharacters else { return nil }
        return collapsed
    }

    /// Distinct words from a transcript turn, in order, for the iOS chip picker.
    static func words(in text: String, maxCount: Int = 40) -> [String] {
        let nsString = text as NSString
        var seen = Set<String>()
        var words: [String] = []
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: .byWords
        ) { substring, _, _, stop in
            guard let substring else { return }
            let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            words.append(trimmed)
            if words.count >= maxCount {
                stop.pointee = true
            }
        }
        return words
    }
}

/// Local find/replace for dictionary corrections. Nil / empty store means callers
/// pay zero work. Longest `heard` phrases win so multi-word entries beat sub-words.
struct TranscriptCorrector: Sendable {
    private let replacements: [(regex: NSRegularExpression, template: String)]

    init?(corrections: [PersonalDictionaryPreferences.CorrectionPair]) {
        let normalized = PersonalDictionaryPreferences.normalizedCorrections(corrections)
        guard !normalized.isEmpty else { return nil }

        let sorted = normalized.sorted { $0.heard.count > $1.heard.count }
        var built: [(NSRegularExpression, String)] = []
        built.reserveCapacity(sorted.count)
        for pair in sorted {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: pair.heard))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            // The replacement is user text: "$1" or "\\" must land literally.
            built.append((regex, NSRegularExpression.escapedTemplate(for: pair.correct)))
        }
        guard !built.isEmpty else { return nil }
        replacements = built
    }

    func apply(to text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for entry in replacements {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            // Skip the allocating replace when nothing matches; on the per-final
            // path most pairs match nothing.
            guard entry.regex.firstMatch(in: result, options: [], range: range) != nil else { continue }
            result = entry.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: entry.template
            )
        }
        return result
    }
}

enum DeepgramAuthorizationScheme: String, Equatable {
    case bearer = "Bearer"
    case token = "Token"

    func authorizationHeader(credential: String) -> String {
        "\(rawValue) \(credential)"
    }
}

/// Which capture source a transcript word/segment came from. Explicit — never
/// inferred from a speaker ID. `unknown` covers malformed multichannel
/// responses (missing or out-of-range `channel_index`).
enum TranscriptSource: String, Codable, Sendable, Equatable, Hashable {
    case microphone
    case system
    case unknown
}

/// Allocates collision-free app speaker IDs from Deepgram's channel-local,
/// socket-local speaker numbers. Provider identity is `(source, providerID,
/// generation)`; the app ID is the presentation/persistence key.
///
/// Mapping contract:
/// - Microphone speakers occupy `micSpeakerID + n` (1000, 1001, …) by
///   first-seen ordinal, preserving `1000` for the first microphone speaker
///   and legacy meetings.
/// - System speakers on the first socket keep their provider number (0, 1, …)
///   so existing display behaviour is unchanged; later sockets allocate fresh
///   sequential low IDs (provider numbers restart at 0 per socket and must
///   not collide with earlier speakers).
/// - Reconnect continuity: while the meeting has seen at most one microphone
///   speaker (the `1000` primary), the first microphone speaker of the next
///   socket maps back to `1000` — preserving the shipped single-user "You"
///   contract. Once several microphone speakers exist, a reconnect cannot
///   tell who is who, so every mic speaker gets a fresh identity.
struct SpeakerIdentityState: Sendable, Equatable {
    private var assignments: [String: Int] = [:]
    private var nextSystemAppID: Int = 0
    private var nextMicOffset: Int = 0
    private var allocatedMicAppIDs: Set<Int> = []
    private(set) var generation: UInt64 = 0
    private var micContinuityAvailable: Bool = false
    /// Sources whose provider speaker numbers come from the on-device diarizer, which keeps
    /// one arrival-ordered slot per speaker for the whole meeting. Those sources are keyed
    /// at generation 0 so a socket reconnect keeps every app ID; Deepgram-diarized sources
    /// stay generation-aware because Deepgram restarts numbering per socket.
    private var stableProviderSources: Set<TranscriptSource> = []

    /// Begin a new WebSocket connection. `preservingIdentities` keeps earlier
    /// allocations (reconnect within one meeting); false resets for a fresh
    /// recording session.
    mutating func beginConnection(preservingIdentities: Bool) {
        guard preservingIdentities else {
            self = SpeakerIdentityState()
            return
        }
        generation &+= 1
        micContinuityAvailable = allocatedMicAppIDs.isEmpty
            || allocatedMicAppIDs == [DeepgramService.micSpeakerID]
    }

    /// Register app speaker IDs restored from a persisted meeting (resume after
    /// relaunch), so allocations for the next socket cannot collide with them.
    mutating func seedRestoredAppSpeakerIDs(_ ids: Set<Int>) {
        for id in ids {
            if DeepgramService.isMicAppSpeakerID(id) {
                allocatedMicAppIDs.insert(id)
                nextMicOffset = max(nextMicOffset, id - DeepgramService.micSpeakerID + 1)
            } else {
                nextSystemAppID = max(nextSystemAppID, id + 1)
            }
        }
    }

    /// Mark `sources` as diarized on device (provider numbers stable across reconnects).
    /// Call after `beginConnection` for every socket of the session.
    mutating func setStableProviderSources(_ sources: Set<TranscriptSource>) {
        stableProviderSources = sources
    }

    mutating func appSpeakerID(source: TranscriptSource, providerID: Int) -> Int {
        guard source != .unknown else { return providerID }
        let keyGeneration: UInt64 = stableProviderSources.contains(source) ? 0 : generation
        let key = "\(source.rawValue)#\(providerID)#\(keyGeneration)"
        if let existing = assignments[key] { return existing }

        let appID: Int
        switch source {
        case .microphone:
            if micContinuityAvailable {
                appID = DeepgramService.micSpeakerID
                micContinuityAvailable = false
            } else {
                var candidate = DeepgramService.micSpeakerID + nextMicOffset
                while allocatedMicAppIDs.contains(candidate) {
                    nextMicOffset += 1
                    candidate = DeepgramService.micSpeakerID + nextMicOffset
                }
                appID = candidate
                nextMicOffset += 1
            }
            allocatedMicAppIDs.insert(appID)
        case .system:
            if keyGeneration == 0 {
                appID = providerID
                nextSystemAppID = max(nextSystemAppID, providerID + 1)
            } else {
                appID = nextSystemAppID
                nextSystemAppID += 1
            }
        case .unknown:
            appID = providerID
        }
        assignments[key] = appID
        return appID
    }

    var micAppSpeakerIDs: Set<Int> { allocatedMicAppIDs }
}

@MainActor
final class DeepgramService: NSObject, ObservableObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    /// Seams for tests: a `URLProtocol`-backed configuration can refuse or drop the WebSocket
    /// handshake, and the endpoint can point at a local server. Production leaves both alone.
    var sessionConfiguration: URLSessionConfiguration = .default
    var endpointURL = URL(string: "wss://api.deepgram.com/v1/listen")!

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var credential: String = ""
    private var authorizationScheme: DeepgramAuthorizationScheme = .token
    private var isConnected = false
    private var connectionGeneration: UInt64 = 0
    
    // Concurrent-safe references for sendAudio (avoids main actor hop per buffer).
    // Written from @MainActor (connect/disconnect), read from audio thread (sendAudio).
    nonisolated(unsafe) private var _sendTask: URLSessionWebSocketTask?
    nonisolated(unsafe) private var _sendConnected = false
    /// On-device speaker timeline for the current session, or nil when Deepgram diarizes.
    /// Read on the audio thread (`sendAudio`) and captured into the off-main parse.
    nonisolated(unsafe) private var _onDeviceTimeline: OnDeviceSpeakerTimeline?
    /// True until the first audio packet of the current socket, which pins socket time 0
    /// onto the diarizer clock.
    nonisolated(unsafe) private var _socketAudioStartPending = false
    
    @Published var transcriptUpdate: TranscriptUpdate?
    /// Wall-clock time of the last `SpeechStarted` event from Deepgram's own voice
    /// activity detection (`vad_events=true`). Speech-specific, unlike the raw capture
    /// level, so a fan or keyboard does not count as someone talking.
    @Published private(set) var lastSpeechStartedAt: CFAbsoluteTime = 0
    @Published var speakerSegments: [SpeakerSegment] = []  // Multiple segments per response
    @Published var connectionState: ConnectionState = .disconnected
    @Published var error: Error?
    
    // Track speakers across the session
    private var speakerHistory: [Int: SpeakerInfo] = [:]
    private var keepAliveTimer: Timer?
    
    /// When true, streaming audio is stereo and results arrive per-channel via
    /// `channel_index`. Channel 0 is always the local mic.
    private var isMultichannel = false

    /// Source attributed to mono (single-channel) responses, decided by the
    /// caller from the active capture topology (mic-only vs system-only).
    private var monoSource: TranscriptSource = .microphone

    /// Collision-free app speaker ID allocation across sources and reconnects.
    /// Survives reconnects within one meeting; reset for a fresh session.
    private var speakerIdentityState = SpeakerIdentityState()

    /// App speaker IDs allocated to microphone-channel speakers this session.
    var micAppSpeakerIDs: Set<Int> { speakerIdentityState.micAppSpeakerIDs }

    /// Register app speaker IDs restored from a persisted meeting before a
    /// resume connect, so new allocations cannot collide with restored ones.
    func seedRestoredSpeakerIdentities(_ ids: Set<Int>) {
        speakerIdentityState.seedRestoredAppSpeakerIDs(ids)
    }

    /// Reserved app speaker ID for the first microphone speaker ("You" in
    /// single-speaker meetings, and all mic speech in legacy meetings).
    /// Microphone speakers occupy `micSpeakerID + n`.
    nonisolated static let micSpeakerID = 1000

    /// Whether an app speaker ID belongs to the microphone range.
    nonisolated static func isMicAppSpeakerID(_ id: Int) -> Bool {
        id >= micSpeakerID
    }
    /// Deepgram channel index for local mic in multichannel mode.
    nonisolated static let micChannelIndex = 0
    /// Deepgram channel index for system/remote audio in multichannel mode.
    nonisolated static let systemChannelIndex = 1
    
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case error
    }
    
    struct TranscriptUpdate: Equatable, Sendable {
        let text: String
        let speaker: Int
        let isFinal: Bool
        let confidence: Double
        let words: [Word]
        /// Deepgram stream channel for multichannel audio (`0` mic, `1` system).
        /// Nil for mono responses that omit `channel_index`.
        let channelIndex: Int?
        /// Explicit capture source for this response.
        let source: TranscriptSource

        struct Word: Equatable, Sendable {
            let text: String
            let start: Double
            let end: Double
            let confidence: Double
            let speaker: Int
            let speakerConfidence: Double?
        }
    }

    // Represents a continuous segment from one speaker
    struct SpeakerSegment: Identifiable, Equatable, Sendable {
        let id: UUID
        let speaker: Int
        let text: String
        let startTime: Double
        let endTime: Double
        let isFinal: Bool
        let confidence: Double
        /// Deepgram stream channel for multichannel audio (`0` mic, `1` system).
        /// Nil for mono responses that omit `channel_index`.
        let channelIndex: Int?
        /// Explicit capture source for this segment.
        let source: TranscriptSource
    }
    
    // Track info about each speaker
    struct SpeakerInfo: Sendable {
        var wordCount: Int = 0
        var totalDuration: Double = 0
        var firstSeen: Date = Date()
    }
    
    struct PendingSpeakerEvidence: Sendable {
        var wordCount: Int = 0
        var duration: Double = 0
        var speakerConfidenceSum: Double = 0
        var speakerConfidenceCount: Int = 0
        
        mutating func add(words: ArraySlice<TranscriptUpdate.Word>) {
            guard !words.isEmpty else { return }
            wordCount += words.count
            if let first = words.first, let last = words.last {
                duration += max(0, last.end - first.start)
            }
            for word in words {
                if let conf = word.speakerConfidence {
                    speakerConfidenceSum += conf
                    speakerConfidenceCount += 1
                }
            }
        }
        
        var averageSpeakerConfidence: Double? {
            guard speakerConfidenceCount > 0 else { return nil }
            return speakerConfidenceSum / Double(speakerConfidenceCount)
        }
    }

    /// How hard an additional mic speaker (1001+) must work to earn promotion.
    /// `strict` is used in remote-likely meetings so headset bleed / diarizer
    /// churn cannot mint clones of the sole local talker.
    enum MicSpeakerPromotionPolicy: String, Sendable, Equatable {
        case standard
        case strict

        var minWordsForNewMicSpeaker: Int {
            switch self {
            case .standard: return 6
            case .strict: return 12
            }
        }

        var minDurationForNewMicSpeaker: Double {
            switch self {
            case .standard: return 1.50
            case .strict: return 4.0
            }
        }

        var minAverageSpeakerConfidenceForNewMicSpeaker: Double {
            switch self {
            case .standard: return 0.65
            case .strict: return 0.85
            }
        }
    }
    
    private var confirmedSpeakerIDs: Set<Int> = []
    private var pendingSpeakerEvidence: [Int: PendingSpeakerEvidence] = [:]
    private var lastCommittedSpeakerBySource: [TranscriptSource: Int] = [:]
    /// Pushed from AppState when environment inference transitions; default
    /// `standard` preserves shared-mic room behaviour.
    var micSpeakerPromotionPolicy: MicSpeakerPromotionPolicy = .standard
    
    /// - Parameters:
    ///   - credential: Managed JWT or BYOK Deepgram API key.
    ///   - authorizationScheme: `.bearer` for managed JWTs, `.token` for BYOK API keys.
    func configure(credential: String, authorizationScheme: DeepgramAuthorizationScheme) {
        self.credential = credential
        self.authorizationScheme = authorizationScheme
    }
    
    nonisolated(unsafe) private var wsMessageCount: Int = 0
    nonisolated(unsafe) private var lastWsHeartbeat: CFAbsoluteTime = 0
    nonisolated(unsafe) private var audioPacketsSent: Int = 0
    nonisolated(unsafe) private var audioBytesSent: Int = 0
    nonisolated(unsafe) private var audioSendErrors: Int = 0
    nonisolated(unsafe) private var consecutiveSendErrors: Int = 0
    private var transcriptMessageCount: Int = 0
    private var transcriptWordCount: Int = 0
    private var finalTranscriptCount: Int = 0
    private var emptyTranscriptCount: Int = 0
    private var lastTranscriptAt: CFAbsoluteTime = 0
    
    private func resetSessionCounters() {
        wsMessageCount = 0
        lastWsHeartbeat = CFAbsoluteTimeGetCurrent()
        audioPacketsSent = 0
        audioBytesSent = 0
        audioSendErrors = 0
        consecutiveSendErrors = 0
        transcriptMessageCount = 0
        transcriptWordCount = 0
        finalTranscriptCount = 0
        emptyTranscriptCount = 0
        lastTranscriptAt = 0
    }
    
    var lastTranscriptTimestamp: CFAbsoluteTime {
        lastTranscriptAt
    }
    
    var packetsSentCount: Int {
        audioPacketsSent
    }
    
    /// - Parameters:
    ///   - multichannel: stereo mic+system capture (macOS dual-source).
    ///   - monoSource: source attributed to mono responses when `multichannel`
    ///     is false (mic-only vs system-only capture).
    ///   - preserveSpeakerIdentities: true on reconnect within one meeting so
    ///     app speaker IDs stay collision-free across sockets; false for a
    ///     fresh recording session.
    func connect(
        language: String = "en",
        personalDictionaryTerms: [String] = [],
        sessionKeyterms: [String] = [],
        multichannel: Bool = false,
        monoSource: TranscriptSource = .microphone,
        preserveSpeakerIdentities: Bool = false,
        onDeviceSpeakerTimeline: OnDeviceSpeakerTimeline? = nil
    ) {
        guard !credential.isEmpty else {
            DebugLogger.shared.log(.deepgram, "No credential — cannot connect")
            error = DeepgramError.noApiKey
            return
        }
        
        if webSocketTask != nil {
            disconnect()
        }
        
        let keyterms = PersonalDictionaryPreferences.deepgramKeyterms(
            personalTerms: personalDictionaryTerms,
            sessionTerms: sessionKeyterms
        )
        let replaceItems = PersonalDictionaryPreferences.deepgramReplaceItems(
            corrections: PersonalDictionaryPreferences.currentCorrections()
        )
        let channelCount = multichannel ? 2 : 1
        DebugLogger.shared.log(
            .deepgram,
            "Connecting with language=\(language), keyterms=\(keyterms.count), replaces=\(replaceItems.count), channels=\(channelCount), multichannel=\(multichannel)"
        )
        connectionState = .connecting
        speakerHistory = [:]
        confirmedSpeakerIDs = []
        pendingSpeakerEvidence = [:]
        lastCommittedSpeakerBySource = [:]
        isMultichannel = multichannel
        self.monoSource = monoSource
        speakerIdentityState.beginConnection(preservingIdentities: preserveSpeakerIdentities)
        speakerIdentityState.setStableProviderSources(onDeviceSpeakerTimeline?.sources ?? [])
        _onDeviceTimeline = onDeviceSpeakerTimeline
        _socketAudioStartPending = onDeviceSpeakerTimeline != nil
        if let onDeviceSpeakerTimeline {
            DebugLogger.shared.log(.deepgram, "On-device diarization active for \(onDeviceSpeakerTimeline.sources.map(\.rawValue).sorted()); diarize_model omitted")
        }
        resetSessionCounters()
        isConnected = false
        _sendConnected = false
        _sendTask = nil
        error = nil
        
        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)!
        components.queryItems = Self.makeListenQueryItems(
            language: language,
            channelCount: channelCount,
            multichannel: multichannel,
            providerDiarization: onDeviceSpeakerTimeline == nil
        )
            + keyterms.map { URLQueryItem(name: "keyterm", value: $0) }
            + replaceItems
        
        guard let url = components.url else {
            error = DeepgramError.invalidUrl
            return
        }

        DebugLogger.shared.log(.deepgram, "Connecting to Deepgram WebSocket")

        var request = URLRequest(url: url)
        request.setValue(
            authorizationScheme.authorizationHeader(credential: credential),
            forHTTPHeaderField: "Authorization"
        )
        
        urlSession = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: OperationQueue.main)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        DebugLogger.shared.log(.deepgram, "WebSocket resume requested")
        
        connectionGeneration &+= 1
        receiveMessages(generation: connectionGeneration)
    }
    
    /// Gracefully disconnect: stop sending audio, send CloseStream, wait for final transcripts, then tear down.
    func gracefulDisconnect() async {
        _sendConnected = false
        let finalCountBefore = finalTranscriptCount

        // Send Deepgram CloseStream message to signal end of audio stream
        if let task = webSocketTask {
            let closeStreamJSON = "{\"type\": \"CloseStream\"}"
            try? await task.send(.string(closeStreamJSON))
            DebugLogger.shared.log(.deepgram, "Sent CloseStream, waiting for final transcripts (finalCount=\(finalCountBefore))")
        }

        // Wait briefly for any remaining final transcripts to arrive
        let deadline = Date().addingTimeInterval(0.8)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            if finalTranscriptCount > finalCountBefore {
                DebugLogger.shared.log(.deepgram, "Received final transcript after CloseStream (finalCount=\(finalTranscriptCount))")
                break
            }
        }

        disconnect()
    }

    func disconnect() {
        connectionGeneration &+= 1
        let mbSent = Double(audioBytesSent) / (1024.0 * 1024.0)
        DebugLogger.shared.log(
            .deepgram,
            "Disconnecting: ws=\(wsMessageCount), audio=\(audioPacketsSent) packets / \(String(format: "%.2f", mbSent))MB, transcript(msg=\(transcriptMessageCount), words=\(transcriptWordCount), final=\(finalTranscriptCount), empty=\(emptyTranscriptCount)), sendErrors=\(audioSendErrors)"
        )
        stopKeepAlive()
        _sendConnected = false
        _sendTask = nil
        _socketAudioStartPending = false
        // Keep `_onDeviceTimeline` until the next connect: in-flight parses for this
        // socket still need it, and a reconnect within the meeting replaces it anyway.
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        isMultichannel = false
        consecutiveSendErrors = 0
        connectionState = .disconnected
    }

    /// Deepgram closes idle sockets after ~10–12s with no client messages.
    /// KeepAlive is free (no audio billed) and protects mic/system restart gaps.
    private func startKeepAlive() {
        stopKeepAlive()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendKeepAlive()
            }
        }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    private func sendKeepAlive() {
        guard isConnected, let task = webSocketTask else { return }
        task.send(.string(#"{"type":"KeepAlive"}"#)) { error in
            if let error {
                Task { @MainActor in
                    DebugLogger.shared.log(.deepgram, "KeepAlive send error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Fixed part of the `/v1/listen` query. `providerDiarization` adds Deepgram's streaming
    /// diarizer (`diarize_model=latest`, billed per channel-minute); sessions diarized on
    /// device leave it out and take speaker numbers from `OnDeviceSpeakerTimeline`.
    nonisolated static func makeListenQueryItems(
        language: String,
        channelCount: Int,
        multichannel: Bool,
        providerDiarization: Bool
    ) -> [URLQueryItem] {
        var queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "filler_words", value: "true"),
        ]
        if providerDiarization {
            // Prefer diarize_model over deprecated diarize=true. Streaming latest = v1 today;
            // auto-upgrades when Deepgram ships a newer streaming diarizer.
            queryItems.append(URLQueryItem(name: "diarize_model", value: "latest"))
        }
        queryItems += [
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "utterance_end_ms", value: "1000"),
            URLQueryItem(name: "vad_events", value: "true"),
            URLQueryItem(name: "endpointing", value: "300"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: String(channelCount)),
        ]
        if multichannel {
            queryItems.append(URLQueryItem(name: "multichannel", value: "true"))
        }
        return queryItems
    }

    struct ProviderSpeaker: Equatable, Sendable {
        var speaker: Int
        var confidence: Double?
        /// True when the on-device timeline had not diarized the word yet and lent a neighbour.
        var borrowed: Bool
    }

    /// Provider speaker number and confidence for one word. With an on-device timeline that
    /// covers the word's source the timeline decides; otherwise Deepgram's own fields stand.
    nonisolated static func providerSpeaker(
        wordStart: Double,
        wordEnd: Double,
        deepgramSpeaker: Int?,
        deepgramConfidence: Double?,
        source: TranscriptSource,
        timeline: OnDeviceSpeakerTimeline?
    ) -> ProviderSpeaker {
        if let timeline, timeline.covers(source),
           let hit = timeline.lookup(source: source, socketStart: wordStart, socketEnd: wordEnd) {
            return ProviderSpeaker(speaker: hit.providerSpeaker, confidence: hit.confidence, borrowed: hit.confidence == OnDeviceSpeakerTimeline.fallbackConfidence)
        }
        return ProviderSpeaker(speaker: deepgramSpeaker ?? 0, confidence: deepgramConfidence, borrowed: false)
    }

    /// Words the diarizer has not reached yet continue the speaker of the last diarized word in
    /// the same response, not whoever the timeline last heard. Within one utterance that is the
    /// better guess, and it stops the interim line flipping speaker between updates as the
    /// horizon advances. Words before the first diarized word keep their lookup result.
    nonisolated static func continueBorrowedSpeakers(_ providers: [ProviderSpeaker]) -> [ProviderSpeaker] {
        var out = providers
        var lastDiarized: Int? = nil
        for index in out.indices {
            if !out[index].borrowed {
                lastDiarized = out[index].speaker
            } else if let lastDiarized {
                out[index].speaker = lastDiarized
            }
        }
        return out
    }

    nonisolated func sendAudio(_ data: Data) {
        // Use nonisolated refs to avoid creating a Task { @MainActor } per audio
        // buffer (~4/sec). URLSessionWebSocketTask.send is thread-safe.
        guard _sendConnected, let task = _sendTask else { return }
        if _socketAudioStartPending {
            _socketAudioStartPending = false
            _onDeviceTimeline?.markSocketStart()
        }
        audioPacketsSent += 1
        audioBytesSent += data.count
        task.send(.data(data)) { [weak self] error in
            if let error {
                self?.audioSendErrors += 1
                Task { @MainActor in
                    guard let self, self.isConnected else { return }
                    self.consecutiveSendErrors += 1
                    DebugLogger.shared.log(.deepgram, "WS send error: \(error.localizedDescription)")
                    self.error = error
                    if self.consecutiveSendErrors >= 5 {
                        self.isConnected = false
                        self._sendConnected = false
                        self.connectionState = .error
                        DebugLogger.shared.log(.deepgram, "WS marked unhealthy after consecutive send failures")
                    }
                }
            }
        }
    }
    
    private struct ProcessedTranscript: Sendable {
        let update: TranscriptUpdate
        let segments: [SpeakerSegment]
        let segmentationState: SegmentationState
        let identityState: SpeakerIdentityState
        let deepgramIsFinal: Bool
        let speechFinal: Bool
        let hasTranscriptText: Bool
        let originalWordCount: Int
        let originalSpeakerIDs: [Int]
        let mappedSpeakerIDs: [Int]
        let wasMultichannel: Bool
        /// Content-free summary of the on-device diarizer's view of this response, or nil.
        var onDeviceSummary: String? = nil
    }

    private enum BackgroundParseResult: Sendable {
        case transcript(ProcessedTranscript)
        case speechStarted
        case ignored
        case warning(String)
    }

    /// Deepgram's VAD event. Cheap substring check so the full decode is skipped.
    nonisolated static func isSpeechStartedMessage(_ json: String) -> Bool {
        json.contains("\"type\":\"SpeechStarted\"") || json.contains("\"type\": \"SpeechStarted\"")
    }

    private func receiveMessages(generation: UInt64) {
        guard generation == connectionGeneration, let task = webSocketTask else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self,
                      generation == self.connectionGeneration,
                      self.webSocketTask === task else { return }
                switch result {
                case .success(let message):
                    self.consecutiveSendErrors = 0
                    self.wsMessageCount += 1
                    self.logHeartbeatIfNeeded()

                    if let json = Self.jsonString(from: message) {
                        let state = SegmentationState(
                            confirmedSpeakerIDs: self.confirmedSpeakerIDs,
                            pendingSpeakerEvidence: self.pendingSpeakerEvidence,
                            lastCommittedSpeakerBySource: self.lastCommittedSpeakerBySource,
                            micSpeakerPromotionPolicy: self.micSpeakerPromotionPolicy,
                            onDeviceSources: self._onDeviceTimeline?.sources ?? []
                        )
                        let multichannel = self.isMultichannel
                        let mono = self.monoSource
                        let identity = self.speakerIdentityState
                        let timeline = self._onDeviceTimeline
                        let parsed = await Task.detached(priority: .userInitiated) {
                            Self.processTranscriptJSON(
                                json,
                                isMultichannel: multichannel,
                                monoSource: mono,
                                segmentationState: state,
                                identityState: identity,
                                speakerTimeline: timeline
                            )
                        }.value
                        guard generation == self.connectionGeneration,
                              self.webSocketTask === task else { return }
                        self.applyBackgroundParseResult(parsed)
                    }
                    self.receiveMessages(generation: generation)

                case .failure(let error):
                    guard self.isConnected else { return }
                    DebugLogger.shared.log(.deepgram, "WS receive error: \(error.localizedDescription)")
                    self.stopKeepAlive()
                    self.error = error
                    self.isConnected = false
                    self._sendConnected = false
                    self.connectionState = .error
                }
            }
        }
    }

    nonisolated private static func jsonString(from message: URLSessionWebSocketTask.Message) -> String? {
        switch message {
        case .string(let text): return text
        case .data(let data): return String(data: data, encoding: .utf8)
        @unknown default: return nil
        }
    }

    /// Determine the capture source of one streaming response.
    nonisolated static func responseSource(
        isMultichannel: Bool,
        streamChannel: Int?,
        monoSource: TranscriptSource
    ) -> TranscriptSource {
        guard isMultichannel else { return monoSource }
        switch streamChannel {
        case micChannelIndex: return .microphone
        case systemChannelIndex: return .system
        default: return .unknown
        }
    }

    nonisolated private static func processTranscriptJSON(
        _ json: String,
        isMultichannel: Bool,
        monoSource: TranscriptSource,
        segmentationState: SegmentationState,
        identityState: SpeakerIdentityState,
        speakerTimeline: OnDeviceSpeakerTimeline? = nil
    ) -> BackgroundParseResult {
        guard let data = json.data(using: .utf8) else { return .ignored }
        if isSpeechStartedMessage(json) { return .speechStarted }
        let response: DeepgramResponse
        do {
            response = try JSONDecoder().decode(DeepgramResponse.self, from: data)
        } catch {
            let ignoredTypes = ["Metadata", "UtteranceEnd", "SpeechStarted", "Filler"]
            if ignoredTypes.contains(where: { json.contains("\"\($0)\"") }) {
                return .ignored
            }
            return .warning(error.localizedDescription)
        }

        guard let alternative = response.channel?.alternatives.first else { return .ignored }
        let deepgramIsFinal = response.isFinal ?? false
        let speechFinal = response.speechFinal ?? false
        let isFinal = deepgramIsFinal || speechFinal
        let hasTranscriptText = !alternative.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let streamChannel = response.channelIndex?.first
        let source = responseSource(
            isMultichannel: isMultichannel,
            streamChannel: streamChannel,
            monoSource: monoSource
        )

        // Preserve Deepgram's per-channel diarization: map channel-local
        // provider speaker numbers to collision-free app speaker IDs. The
        // mic channel is no longer flattened to a single reserved ID.
        var nextIdentityState = identityState
        var onDeviceSlotCounts: [Int: Int] = [:]
        var onDeviceBorrowed = 0
        let onDeviceCovers = speakerTimeline?.covers(source) ?? false
        var providers = alternative.words.map { word in
            providerSpeaker(
                wordStart: word.start,
                wordEnd: word.end,
                deepgramSpeaker: word.speaker,
                deepgramConfidence: word.speakerConfidence,
                source: source,
                timeline: speakerTimeline
            )
        }
        if onDeviceCovers { providers = continueBorrowedSpeakers(providers) }
        let words = zip(alternative.words, providers).map { word, provider in
            if onDeviceCovers {
                onDeviceSlotCounts[provider.speaker, default: 0] += 1
                if provider.borrowed { onDeviceBorrowed += 1 }
            }
            let appSpeaker = nextIdentityState.appSpeakerID(source: source, providerID: provider.speaker)
            return TranscriptUpdate.Word(
                text: word.punctuatedWord ?? word.word,
                start: word.start,
                end: word.end,
                confidence: word.confidence,
                speaker: appSpeaker,
                speakerConfidence: provider.confidence
            )
        }

        var nextState = segmentationState
        let segments = segmentBySpeaker(
            words: words,
            isFinal: isFinal,
            confidence: alternative.confidence,
            channelIndex: streamChannel,
            source: source,
            state: &nextState
        )
        if isFinal {
            for segment in segments {
                nextState.confirmedSpeakerIDs.insert(segment.speaker)
                nextState.pendingSpeakerEvidence.removeValue(forKey: segment.speaker)
            }
        }

        var speakerCounts: [Int: Int] = [:]
        for word in words { speakerCounts[word.speaker, default: 0] += 1 }
        let dominantSpeaker = speakerCounts.max(by: { $0.value < $1.value })?.key ?? 0
        let update = TranscriptUpdate(
            text: alternative.transcript,
            speaker: dominantSpeaker,
            isFinal: isFinal,
            confidence: alternative.confidence,
            words: words,
            channelIndex: streamChannel,
            source: source
        )
        return .transcript(ProcessedTranscript(
            update: update,
            segments: segments,
            segmentationState: nextState,
            identityState: nextIdentityState,
            deepgramIsFinal: deepgramIsFinal,
            speechFinal: speechFinal,
            hasTranscriptText: hasTranscriptText,
            originalWordCount: alternative.words.count,
            originalSpeakerIDs: Array(Set(alternative.words.compactMap(\.speaker))).sorted(),
            mappedSpeakerIDs: Array(Set(words.map(\.speaker))).sorted(),
            wasMultichannel: isMultichannel,
            onDeviceSummary: onDeviceSlotCounts.isEmpty ? nil : "slots=\(onDeviceSlotCounts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }) borrowed=\(onDeviceBorrowed)/\(words.count) horizon=\(String(format: "%.1f", speakerTimeline?.processedSeconds(source: source) ?? 0))s fed=\(String(format: "%.1f", speakerTimeline?.fedSeconds(source: source) ?? 0))s lastWord=\(String(format: "%.1f", alternative.words.last?.end ?? 0))s mature=\(speakerTimeline?.matureSlots(source: source) ?? [])"
        ))
    }

    private func applyBackgroundParseResult(_ result: BackgroundParseResult) {
        switch result {
        case .ignored:
            return
        case .speechStarted:
            lastSpeechStartedAt = CFAbsoluteTimeGetCurrent()
        case .warning(let message):
            DebugLogger.shared.log(.deepgram, "Parse warning: \(message)")
        case .transcript(let parsed):
            transcriptMessageCount += 1
            if parsed.originalWordCount == 0 && !parsed.hasTranscriptText {
                emptyTranscriptCount += 1
            } else {
                transcriptWordCount += parsed.originalWordCount
                lastTranscriptAt = CFAbsoluteTimeGetCurrent()
                if parsed.update.isFinal { finalTranscriptCount += 1 }
            }
            if parsed.speechFinal && !parsed.deepgramIsFinal && parsed.hasTranscriptText {
                DebugLogger.shared.log(.deepgram, "Promoting speech_final transcript to final: words=\(parsed.originalWordCount)")
            }
            if parsed.update.isFinal && parsed.originalWordCount > 0 {
                DebugLogger.shared.log(
                    .deepgram,
                    "Final transcript received: words=\(parsed.originalWordCount), providerSpeakers=\(parsed.originalSpeakerIDs), appSpeakers=\(parsed.mappedSpeakerIDs)"
                )
                if parsed.wasMultichannel {
                    DebugLogger.shared.log(
                        .deepgram,
                        "Speaker mapping: channel=\(parsed.update.channelIndex.map(String.init) ?? "n/a"), source=\(parsed.update.source.rawValue), total=\(parsed.originalWordCount)"
                    )
                }
                if let summary = parsed.onDeviceSummary {
                    DebugLogger.shared.log(.deepgram, "On-device speakers (\(parsed.update.source.rawValue)): \(summary) → app=\(parsed.mappedSpeakerIDs)")
                }
                for word in parsed.update.words {
                    var info = speakerHistory[word.speaker] ?? SpeakerInfo()
                    info.wordCount += 1
                    info.totalDuration += word.end - word.start
                    speakerHistory[word.speaker] = info
                }
            }
            // Promotion evidence persists from finals only. Cumulative interims
            // replay the same words on every message, so accruing from them would
            // let a 4-word run clear the 12-word strict bar after four interims
            // without anyone saying anything new. Interims still segment against
            // a copy of the current state so their display stays consistent.
            if parsed.update.isFinal {
                confirmedSpeakerIDs = parsed.segmentationState.confirmedSpeakerIDs
                pendingSpeakerEvidence = parsed.segmentationState.pendingSpeakerEvidence
                lastCommittedSpeakerBySource = parsed.segmentationState.lastCommittedSpeakerBySource
            }
            speakerIdentityState = parsed.identityState
            speakerSegments = parsed.segments
            transcriptUpdate = parsed.update
        }
    }

    private func logHeartbeatIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastWsHeartbeat > 15.0 else { return }
        lastWsHeartbeat = now
        let kbSent = Double(audioBytesSent) / 1024.0
        let sinceTranscript = lastTranscriptAt > 0
            ? String(format: "%.1fs", now - lastTranscriptAt)
            : "never"
        DebugLogger.shared.log(
            .deepgram,
            "WS heartbeat: msg=\(wsMessageCount), speakers=\(speakerHistory.count), audio=\(audioPacketsSent) packets/\(String(format: "%.0f", kbSent))KB, transcript(msg=\(transcriptMessageCount), words=\(transcriptWordCount), final=\(finalTranscriptCount), empty=\(emptyTranscriptCount), last=\(sinceTranscript))"
        )
        if wsMessageCount > 20 && transcriptWordCount == 0 {
            DebugLogger.shared.log(.deepgram, "WS warning: receiving messages but no transcript words yet")
        }
    }
    
    /// Keys are app speaker IDs, which are already source-scoped by the
    /// identity mapping (mic ≥ 1000, system < 1000), so a speaker confirmed
    /// on the system channel can never make a mic-channel provider ID look
    /// confirmed, and vice versa.
    struct SegmentationState: Sendable {
        var confirmedSpeakerIDs: Set<Int> = []
        var pendingSpeakerEvidence: [Int: PendingSpeakerEvidence] = [:]
        var lastCommittedSpeakerBySource: [TranscriptSource: Int] = [:]
        var micSpeakerPromotionPolicy: MicSpeakerPromotionPolicy = .standard
        /// Sources whose speaker numbers come from the on-device diarizer. Its slots are
        /// stable and voice-based, so an additional mic speaker there never needs the strict
        /// clone guard that exists for Deepgram's per-socket diarizer churn.
        var onDeviceSources: Set<TranscriptSource> = []
    }

    nonisolated static func segmentBySpeaker(
        words: [TranscriptUpdate.Word],
        isFinal: Bool,
        confidence: Double,
        channelIndex: Int? = nil,
        source: TranscriptSource = .unknown,
        state: inout SegmentationState
    ) -> [SpeakerSegment] {
        guard !words.isEmpty else { return [] }
        
        let minWordsForSpeakerChange = 4
        let minDurationForSpeakerChange = 0.85
        let minAverageSpeakerConfidenceForSwitch = 0.58
        
        // B1: do not accept an unconfirmed first-word speaker on a source that
        // already has a committed speaker. Treat it as a candidate switch away
        // from the last committed ID and require the same evidence mid-response
        // switches need. The very first response on a source stays ungated.
        let firstSpeaker = words[0].speaker
        let otherMicAtStart = state.confirmedSpeakerIDs.contains {
            DeepgramService.isMicAppSpeakerID($0) && $0 != DeepgramService.micSpeakerID
        }
        let firstIsMicPrimaryPrivileged =
            firstSpeaker == DeepgramService.micSpeakerID && !otherMicAtStart
        let firstIsKnown =
            state.confirmedSpeakerIDs.contains(firstSpeaker) || firstIsMicPrimaryPrivileged
        let currentSpeakerSeed: Int
        if let lastCommitted = state.lastCommittedSpeakerBySource[source],
           firstSpeaker != lastCommitted,
           !firstIsKnown {
            currentSpeakerSeed = lastCommitted
        } else {
            currentSpeakerSeed = firstSpeaker
        }

        var segments: [SpeakerSegment] = []
        var currentSpeaker = currentSpeakerSeed
        var currentWords: [TranscriptUpdate.Word] = []
        var startTime = words[0].start
        
        var i = 0
        while i < words.count {
            let word = words[i]
            
            if word.speaker != currentSpeaker {
                var lookAhead = i
                let newSpeaker = word.speaker
                
                while lookAhead < words.count && words[lookAhead].speaker == newSpeaker {
                    lookAhead += 1
                }
                
                let candidateWords = words[i..<lookAhead]
                let candidateWordCount = candidateWords.count
                let candidateDuration: Double
                if let first = candidateWords.first, let last = candidateWords.last {
                    candidateDuration = max(0, last.end - first.start)
                } else {
                    candidateDuration = 0
                }
                let candidateAverageSpeakerConfidence: Double? = {
                    let confidences = candidateWords.compactMap(\.speakerConfidence)
                    guard !confidences.isEmpty else { return nil }
                    return confidences.reduce(0, +) / Double(confidences.count)
                }()
                
                let passesGeneralSwitchChecks =
                    candidateWordCount >= minWordsForSpeakerChange &&
                    candidateDuration >= minDurationForSpeakerChange
                // The primary mic identity (1000) keeps the historical
                // confidence/promotion exemption ONLY while it is the sole mic
                // speaker — that preserves the shipped single-user contract.
                // Once a second mic speaker is confirmed, switches back to 1000
                // must pass the same confidence gate as everyone else; otherwise
                // borderline diarizer words preferentially flip to the primary
                // speaker and shred turn boundaries in shared-mic meetings.
                // Additional mic speakers (1001+) always earn promotion like
                // system speakers so diarizer churn cannot invent room speakers.
                let otherMicSpeakerConfirmed = state.confirmedSpeakerIDs.contains {
                    DeepgramService.isMicAppSpeakerID($0) && $0 != DeepgramService.micSpeakerID
                }
                let micPrimaryPrivileged = newSpeaker == DeepgramService.micSpeakerID && !otherMicSpeakerConfirmed
                let passesSwitchConfidenceCheck = micPrimaryPrivileged ||
                    ((candidateAverageSpeakerConfidence ?? 1.0) >= minAverageSpeakerConfidenceForSwitch)
                let isKnownSpeaker = state.confirmedSpeakerIDs.contains(newSpeaker) || micPrimaryPrivileged
                
                var allowSwitch = passesGeneralSwitchChecks && passesSwitchConfidenceCheck
                if allowSwitch && !isKnownSpeaker {
                    var evidence = state.pendingSpeakerEvidence[newSpeaker] ?? PendingSpeakerEvidence()
                    evidence.add(words: candidateWords)
                    state.pendingSpeakerEvidence[newSpeaker] = evidence

                    // B2: remote-likely meetings raise the bar only for additional
                    // mic speakers (1001+). System speakers and the primary mic
                    // keep standard thresholds.
                    let isAdditionalMicSpeaker =
                        DeepgramService.isMicAppSpeakerID(newSpeaker)
                        && newSpeaker != DeepgramService.micSpeakerID
                    let promotionPolicy = isAdditionalMicSpeaker && !state.onDeviceSources.contains(source)
                        ? state.micSpeakerPromotionPolicy
                        : .standard
                    let minWords = promotionPolicy.minWordsForNewMicSpeaker
                    let minDuration = promotionPolicy.minDurationForNewMicSpeaker
                    let minConfidence = promotionPolicy.minAverageSpeakerConfidenceForNewMicSpeaker
                    
                    let promotedByWords = evidence.wordCount >= minWords
                    let promotedByDuration = evidence.duration >= minDuration
                    let promotedByConfidence = (evidence.averageSpeakerConfidence ?? 1.0) >= minConfidence
                    let isPromoted = promotedByWords && promotedByDuration && promotedByConfidence
                    if isPromoted {
                        state.confirmedSpeakerIDs.insert(newSpeaker)
                        state.pendingSpeakerEvidence.removeValue(forKey: newSpeaker)
                    } else {
                        allowSwitch = false
                    }
                }
                
                if allowSwitch {
                    if !currentWords.isEmpty {
                        let text = currentWords.map { $0.text }.joined(separator: " ")
                        let segment = SpeakerSegment(
                            id: UUID(),
                            speaker: currentSpeaker,
                            text: text,
                            startTime: startTime,
                            endTime: currentWords.last?.end ?? startTime,
                            isFinal: isFinal,
                            confidence: confidence,
                            channelIndex: channelIndex,
                            source: source
                        )
                        segments.append(segment)
                    }
                    
                    currentSpeaker = newSpeaker
                    currentWords = Array(candidateWords)
                    startTime = candidateWords.first?.start ?? word.start
                } else {
                    currentWords.append(contentsOf: candidateWords)
                }
                
                i = lookAhead
                continue
            } else {
                currentWords.append(word)
            }
            i += 1
        }
        
        if !currentWords.isEmpty {
            let text = currentWords.map { $0.text }.joined(separator: " ")
            let segment = SpeakerSegment(
                id: UUID(),
                speaker: currentSpeaker,
                text: text,
                startTime: startTime,
                endTime: currentWords.last?.end ?? startTime,
                isFinal: isFinal,
                confidence: confidence,
                channelIndex: channelIndex,
                source: source
            )
            segments.append(segment)
        }

        if let lastSpeaker = segments.last?.speaker {
            state.lastCommittedSpeakerBySource[source] = lastSpeaker
        }

        return segments
    }

    /// Find the speaker who spoke the most words in this segment
    func findDominantSpeaker(words: [TranscriptUpdate.Word]) -> Int {
        var speakerWordCount: [Int: Int] = [:]
        for word in words {
            speakerWordCount[word.speaker, default: 0] += 1
        }
        return speakerWordCount.max(by: { $0.value < $1.value })?.key ?? 0
    }
    
    /// Get the number of unique speakers detected so far
    var detectedSpeakerCount: Int {
        speakerHistory.count
    }
}

extension DeepgramService {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self, webSocketTask == self.webSocketTask else { return }
            self.isConnected = true
            self._sendConnected = true
            self._sendTask = webSocketTask
            self.connectionState = .connected
            self.error = nil
            self.startKeepAlive()
            DebugLogger.shared.log(.deepgram, "WebSocket connected")
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            guard let self, webSocketTask == self.webSocketTask else { return }
            self.stopKeepAlive()
            self.isConnected = false
            self._sendConnected = false
            if self.connectionState != .error {
                self.connectionState = .disconnected
            }
            let reasonText: String
            if let reason, let decoded = String(data: reason, encoding: .utf8), !decoded.isEmpty {
                reasonText = decoded
            } else {
                reasonText = "none"
            }
            DebugLogger.shared.log(.deepgram, "WebSocket closed: code=\(closeCode.rawValue), reason=\(reasonText)")
        }
    }
}

// MARK: - Deepgram Response Models

struct DeepgramResponse: Codable, Sendable {
    let type: String?
    let channel: Channel?
    /// Streaming multichannel: `[channelIndex, channelCount]` e.g. `[0, 2]` or `[1, 2]`.
    let channelIndex: [Int]?
    let isFinal: Bool?
    let speechFinal: Bool?
    let start: Double?
    let duration: Double?
    let fromFinalize: Bool?
    
    enum CodingKeys: String, CodingKey {
        case type
        case channel
        case channelIndex = "channel_index"
        case isFinal = "is_final"
        case speechFinal = "speech_final"
        case start
        case duration
        case fromFinalize = "from_finalize"
    }
    
    struct Channel: Codable, Sendable {
        let alternatives: [Alternative]
    }
    
    struct Alternative: Codable, Sendable {
        let transcript: String
        let confidence: Double
        let words: [Word]
        
        // Make words optional with default empty array
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
            confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.0
            words = try container.decodeIfPresent([Word].self, forKey: .words) ?? []
        }
        
        enum CodingKeys: String, CodingKey {
            case transcript
            case confidence
            case words
        }
    }
    
    struct Word: Codable, Sendable {
        let word: String
        let punctuatedWord: String?
        let start: Double
        let end: Double
        let confidence: Double
        let speaker: Int?
        let speakerConfidence: Double?
        
        enum CodingKeys: String, CodingKey {
            case word
            case punctuatedWord = "punctuated_word"
            case start
            case end
            case confidence
            case speaker
            case speakerConfidence = "speaker_confidence"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            word = try container.decodeIfPresent(String.self, forKey: .word) ?? ""
            punctuatedWord = try container.decodeIfPresent(String.self, forKey: .punctuatedWord)
            start = try container.decodeIfPresent(Double.self, forKey: .start) ?? 0.0
            end = try container.decodeIfPresent(Double.self, forKey: .end) ?? 0.0
            confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.0
            speaker = try container.decodeIfPresent(Int.self, forKey: .speaker)
            speakerConfidence = try container.decodeIfPresent(Double.self, forKey: .speakerConfidence)
        }
    }
}

// MARK: - Errors

enum DeepgramError: LocalizedError {
    case noApiKey
    case invalidUrl
    case connectionFailed
    
    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Deepgram API key is required."
        case .invalidUrl:
            return "Failed to create WebSocket URL."
        case .connectionFailed:
            return "Failed to connect to Deepgram."
        }
    }
}
