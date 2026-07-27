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
    static let systemKeyterms = ["Miniti", "Lightdash", "Ahuja"]

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

enum DeepgramAuthorizationScheme: String, Equatable {
    case bearer = "Bearer"
    case token = "Token"
    
    func authorizationHeader(credential: String) -> String {
        "\(rawValue) \(credential)"
    }
}

@MainActor
final class DeepgramService: NSObject, ObservableObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var credential: String = ""
    private var authorizationScheme: DeepgramAuthorizationScheme = .token
    private var isConnected = false
    
    // Concurrent-safe references for sendAudio (avoids main actor hop per buffer).
    // Written from @MainActor (connect/disconnect), read from audio thread (sendAudio).
    nonisolated(unsafe) private var _sendTask: URLSessionWebSocketTask?
    nonisolated(unsafe) private var _sendConnected = false
    
    @Published var transcriptUpdate: TranscriptUpdate?
    @Published var speakerSegments: [SpeakerSegment] = []  // Multiple segments per response
    @Published var connectionState: ConnectionState = .disconnected
    @Published var error: Error?
    
    // Track speakers across the session
    private var speakerHistory: [Int: SpeakerInfo] = [:]
    private var keepAliveTimer: Timer?
    
    /// Optional callback to determine audio source for a time range.
    /// Legacy mono-mix path only. Prefer multichannel (ch0=mic) when mic+system
    /// are both active — then `sourceLookup` stays nil.
    var sourceLookup: ((Double, Double) -> AudioCaptureService.AudioSource)?
    
    /// When true, streaming audio is stereo and results arrive per-channel via
    /// `channel_index`. Channel 0 is always the local mic ("You").
    private var isMultichannel = false
    
    /// Reserved speaker ID for the local microphone ("You").
    nonisolated static let micSpeakerID = 1000
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
    
    struct TranscriptUpdate: Equatable {
        let text: String
        let speaker: Int
        let isFinal: Bool
        let confidence: Double
        let words: [Word]
        
        struct Word: Equatable {
            let text: String
            let start: Double
            let end: Double
            let confidence: Double
            let speaker: Int
            let speakerConfidence: Double?
        }
    }
    
    // Represents a continuous segment from one speaker
    struct SpeakerSegment: Identifiable, Equatable {
        let id: UUID
        let speaker: Int
        let text: String
        let startTime: Double
        let endTime: Double
        let isFinal: Bool
        let confidence: Double
    }
    
    // Track info about each speaker
    struct SpeakerInfo {
        var wordCount: Int = 0
        var totalDuration: Double = 0
        var firstSeen: Date = Date()
    }
    
    struct PendingSpeakerEvidence {
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
    
    private var confirmedSpeakerIDs: Set<Int> = []
    private var pendingSpeakerEvidence: [Int: PendingSpeakerEvidence] = [:]
    
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
    
    func connect(
        language: String = "en",
        personalDictionaryTerms: [String] = [],
        sessionKeyterms: [String] = [],
        multichannel: Bool = false
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
        let channelCount = multichannel ? 2 : 1
        DebugLogger.shared.log(
            .deepgram,
            "Connecting with language=\(language), keyterms=\(keyterms.count), channels=\(channelCount), multichannel=\(multichannel)"
        )
        connectionState = .connecting
        speakerHistory = [:]
        confirmedSpeakerIDs = []
        pendingSpeakerEvidence = [:]
        isMultichannel = multichannel
        resetSessionCounters()
        isConnected = false
        _sendConnected = false
        _sendTask = nil
        error = nil
        
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        var queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "filler_words", value: "true"),
            // Prefer diarize_model over deprecated diarize=true. Streaming latest = v1 today;
            // auto-upgrades when Deepgram ships a newer streaming diarizer.
            URLQueryItem(name: "diarize_model", value: "latest"),
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
        components.queryItems = queryItems + keyterms.map { URLQueryItem(name: "keyterm", value: $0) }
        
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
        
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        DebugLogger.shared.log(.deepgram, "WebSocket resume requested")
        
        receiveMessages()
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
        let mbSent = Double(audioBytesSent) / (1024.0 * 1024.0)
        DebugLogger.shared.log(
            .deepgram,
            "Disconnecting: ws=\(wsMessageCount), audio=\(audioPacketsSent) packets / \(String(format: "%.2f", mbSent))MB, transcript(msg=\(transcriptMessageCount), words=\(transcriptWordCount), final=\(finalTranscriptCount), empty=\(emptyTranscriptCount)), sendErrors=\(audioSendErrors)"
        )
        stopKeepAlive()
        _sendConnected = false
        _sendTask = nil
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
    
    nonisolated func sendAudio(_ data: Data) {
        // Use nonisolated refs to avoid creating a Task { @MainActor } per audio
        // buffer (~4/sec). URLSessionWebSocketTask.send is thread-safe.
        guard _sendConnected, let task = _sendTask else { return }
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
    
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.consecutiveSendErrors = 0
                    self.wsMessageCount += 1
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - self.lastWsHeartbeat > 15.0 {
                        self.lastWsHeartbeat = now
                        let kbSent = Double(self.audioBytesSent) / 1024.0
                        let sinceTranscript: String
                        if self.lastTranscriptAt > 0 {
                            sinceTranscript = String(format: "%.1fs", now - self.lastTranscriptAt)
                        } else {
                            sinceTranscript = "never"
                        }
                        DebugLogger.shared.log(
                            .deepgram,
                            "WS heartbeat: msg=\(self.wsMessageCount), speakers=\(self.speakerHistory.count), audio=\(self.audioPacketsSent) packets/\(String(format: "%.0f", kbSent))KB, transcript(msg=\(self.transcriptMessageCount), words=\(self.transcriptWordCount), final=\(self.finalTranscriptCount), empty=\(self.emptyTranscriptCount), last=\(sinceTranscript))"
                        )
                        if self.wsMessageCount > 20 && self.transcriptWordCount == 0 {
                            DebugLogger.shared.log(.deepgram, "WS warning: receiving messages but no transcript words yet")
                        }
                    }
                    self.handleMessage(message)
                    self.receiveMessages()
                    
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
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTranscriptResponse(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseTranscriptResponse(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseTranscriptResponse(_ json: String) {
        guard let data = json.data(using: .utf8) else { return }
        
        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            
            // Handle transcript results
            if let channel = response.channel,
               let alternative = channel.alternatives.first {
                
                let deepgramIsFinal = response.isFinal ?? false
                let speechFinal = response.speechFinal ?? false
                let isFinal = deepgramIsFinal || speechFinal
                let hasTranscriptText = !alternative.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                transcriptMessageCount += 1
                if alternative.words.isEmpty && !hasTranscriptText {
                    emptyTranscriptCount += 1
                } else {
                    transcriptWordCount += alternative.words.count
                    lastTranscriptAt = CFAbsoluteTimeGetCurrent()
                    if isFinal { finalTranscriptCount += 1 }
                }
                if speechFinal && !deepgramIsFinal && hasTranscriptText {
                    DebugLogger.shared.log(
                        .deepgram,
                        "Promoting speech_final transcript to final: words=\(alternative.words.count)"
                    )
                }

                let speakersInResponse = alternative.words.compactMap { $0.speaker }
                let uniqueSpeakers = Set(speakersInResponse)
                if isFinal && !alternative.words.isEmpty {
                    DebugLogger.shared.log(
                        .deepgram,
                        "Final transcript received: words=\(alternative.words.count), speakers=\(Array(uniqueSpeakers).sorted())"
                    )
                }

                // Streaming multichannel delivers one channel per message via channel_index.
                // Prefer that over energy-based sourceLookup when active.
                let streamChannel = response.channelIndex?.first
                let forceMicSpeaker = isMultichannel && streamChannel == Self.micChannelIndex
                
                var micTaggedWordCount = 0
                var unknownTaggedWordCount = 0
                let words = alternative.words.map { word in
                    var speaker = word.speaker ?? 0
                    
                    if forceMicSpeaker {
                        speaker = DeepgramService.micSpeakerID
                        micTaggedWordCount += 1
                    } else if let lookup = sourceLookup {
                        // Legacy mono-mix fallback.
                        let source = lookup(word.start, word.end)
                        if source == .mic {
                            speaker = DeepgramService.micSpeakerID
                            micTaggedWordCount += 1
                        } else if source == .unknown {
                            unknownTaggedWordCount += 1
                        }
                    }
                    
                    return TranscriptUpdate.Word(
                        text: word.punctuatedWord ?? word.word,
                        start: word.start,
                        end: word.end,
                        confidence: word.confidence,
                        speaker: speaker,
                        speakerConfidence: word.speakerConfidence
                    )
                }
                
                // Update speaker history for final results
                if isFinal {
                    if isMultichannel || sourceLookup != nil {
                        DebugLogger.shared.log(
                            .deepgram,
                            "Speaker tagging: channel=\(streamChannel.map(String.init) ?? "n/a"), multichannel=\(isMultichannel), mic=\(micTaggedWordCount), unknown=\(unknownTaggedWordCount), total=\(alternative.words.count)"
                        )
                    }
                    for word in words {
                        var info = speakerHistory[word.speaker] ?? SpeakerInfo()
                        info.wordCount += 1
                        info.totalDuration += word.end - word.start
                        speakerHistory[word.speaker] = info
                    }
                }
                
                // Segment by speaker - group consecutive words by the same speaker
                let segments = segmentBySpeaker(words: words, isFinal: isFinal, confidence: alternative.confidence)
                if isFinal {
                    updateConfirmedSpeakers(from: segments)
                }
                self.speakerSegments = segments
                
                // Also provide the dominant speaker for backward compatibility
                let dominantSpeaker = findDominantSpeaker(words: words)
                
                let update = TranscriptUpdate(
                    text: alternative.transcript,
                    speaker: dominantSpeaker,
                    isFinal: isFinal,
                    confidence: alternative.confidence,
                    words: words
                )
                
                self.transcriptUpdate = update
            }
        } catch {
            // Some messages are metadata or other types we can safely ignore
            let ignoredTypes = ["Metadata", "UtteranceEnd", "SpeechStarted", "Filler"]
            let isIgnoredType = ignoredTypes.contains { json.contains("\"\($0)\"") }
            
            if !isIgnoredType {
                // Only log unexpected parse errors
                DebugLogger.shared.log(.deepgram, "Parse warning: \(error.localizedDescription)")
            }
        }
    }
    
    struct SegmentationState {
        var confirmedSpeakerIDs: Set<Int> = []
        var pendingSpeakerEvidence: [Int: PendingSpeakerEvidence] = [:]
    }

    nonisolated static func segmentBySpeaker(
        words: [TranscriptUpdate.Word],
        isFinal: Bool,
        confidence: Double,
        state: inout SegmentationState
    ) -> [SpeakerSegment] {
        guard !words.isEmpty else { return [] }
        
        let minWordsForSpeakerChange = 4
        let minDurationForSpeakerChange = 0.85
        let minAverageSpeakerConfidenceForSwitch = 0.58
        
        let minWordsForNewSpeakerPromotion = 6
        let minDurationForNewSpeakerPromotion = 1.50
        let minAverageSpeakerConfidenceForNewSpeaker = 0.65
        
        var segments: [SpeakerSegment] = []
        var currentSpeaker = words[0].speaker
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
                let passesSwitchConfidenceCheck = (newSpeaker == DeepgramService.micSpeakerID) ||
                    ((candidateAverageSpeakerConfidence ?? 1.0) >= minAverageSpeakerConfidenceForSwitch)
                let isKnownSpeaker = state.confirmedSpeakerIDs.contains(newSpeaker) || newSpeaker == DeepgramService.micSpeakerID
                
                var allowSwitch = passesGeneralSwitchChecks && passesSwitchConfidenceCheck
                if allowSwitch && !isKnownSpeaker {
                    var evidence = state.pendingSpeakerEvidence[newSpeaker] ?? PendingSpeakerEvidence()
                    evidence.add(words: candidateWords)
                    state.pendingSpeakerEvidence[newSpeaker] = evidence
                    
                    let promotedByWords = evidence.wordCount >= minWordsForNewSpeakerPromotion
                    let promotedByDuration = evidence.duration >= minDurationForNewSpeakerPromotion
                    let promotedByConfidence = (evidence.averageSpeakerConfidence ?? 1.0) >= minAverageSpeakerConfidenceForNewSpeaker
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
                            confidence: confidence
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
                confidence: confidence
            )
            segments.append(segment)
        }
        
        return segments
    }

    private func segmentBySpeaker(words: [TranscriptUpdate.Word], isFinal: Bool, confidence: Double) -> [SpeakerSegment] {
        var state = SegmentationState(
            confirmedSpeakerIDs: confirmedSpeakerIDs,
            pendingSpeakerEvidence: pendingSpeakerEvidence
        )
        let result = Self.segmentBySpeaker(words: words, isFinal: isFinal, confidence: confidence, state: &state)
        confirmedSpeakerIDs = state.confirmedSpeakerIDs
        pendingSpeakerEvidence = state.pendingSpeakerEvidence
        return result
    }
    
    private func updateConfirmedSpeakers(from segments: [SpeakerSegment]) {
        for segment in segments {
            confirmedSpeakerIDs.insert(segment.speaker)
            pendingSpeakerEvidence.removeValue(forKey: segment.speaker)
        }
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

struct DeepgramResponse: Codable {
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
    
    struct Channel: Codable {
        let alternatives: [Alternative]
    }
    
    struct Alternative: Codable {
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
    
    struct Word: Codable {
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
