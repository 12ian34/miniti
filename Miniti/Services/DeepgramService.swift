import Foundation
import Combine

// MARK: - Deepgram Model Selection

enum DeepgramModel: String, CaseIterable, Codable {
    case nova2 = "nova-2"
    case nova3 = "nova-3"
    
    var displayName: String {
        switch self {
        case .nova2: return "Nova-2"
        case .nova3: return "Nova-3"
        }
    }
    
    var shortDescription: String {
        switch self {
        case .nova2: return "faster"
        case .nova3: return "smarter"
        }
    }
    
    var pros: [String] {
        switch self {
        case .nova2:
            return ["Lower latency", "Battle-tested", "Slightly cheaper"]
        case .nova3:
            return ["Better diarization", "Higher accuracy", "Handles accents better"]
        }
    }
    
    var cons: [String] {
        switch self {
        case .nova2:
            return ["Less accurate diarization", "Older model"]
        case .nova3:
            return ["Slightly higher latency", "Newer (less tested)"]
        }
    }
}

@MainActor
final class DeepgramService: NSObject, ObservableObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var apiKey: String = ""
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
    
    /// Optional callback to determine audio source for a time range.
    /// When set, words from the microphone are assigned a dedicated speaker ID (1000)
    /// to separate them from system audio speakers (Deepgram's own diarization).
    var sourceLookup: ((Double, Double) -> AudioCaptureService.AudioSource)?
    
    /// Reserved speaker ID for the local microphone ("You").
    nonisolated static let micSpeakerID = 1000
    
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
    
    private struct PendingSpeakerEvidence {
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
    
    func configure(apiKey: String) {
        self.apiKey = apiKey
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
    
    func connect(model: DeepgramModel = .nova3) {
        guard !apiKey.isEmpty else {
            DebugLogger.shared.log(.deepgram, "No API key — cannot connect")
            error = DeepgramError.noApiKey
            return
        }
        
        if webSocketTask != nil {
            disconnect()
        }
        
        DebugLogger.shared.log(.deepgram, "Connecting with model=\(model.rawValue)")
        connectionState = .connecting
        speakerHistory = [:]
        confirmedSpeakerIDs = []
        pendingSpeakerEvidence = [:]
        resetSessionCounters()
        isConnected = false
        _sendConnected = false
        _sendTask = nil
        error = nil
        
        // Build URL with parameters - optimized for speaker diarization
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: model.rawValue),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "filler_words", value: "true"),
            // Diarization - enables speaker identification
            URLQueryItem(name: "diarize", value: "true"),
            // Streaming settings
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "utterance_end_ms", value: model == .nova3 ? "1000" : "1500"),
            URLQueryItem(name: "vad_events", value: "true"),
            URLQueryItem(name: "endpointing", value: model == .nova3 ? "300" : "500"),
            // Audio format
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
        ]
        
        print("[Deepgram] Using model: \(model.displayName)")
        
        guard let url = components.url else {
            error = DeepgramError.invalidUrl
            return
        }
        
        print("[Deepgram] Connecting to: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()
        DebugLogger.shared.log(.deepgram, "WebSocket resume requested")
        
        receiveMessages()
    }
    
    func disconnect() {
        let mbSent = Double(audioBytesSent) / (1024.0 * 1024.0)
        DebugLogger.shared.log(
            .deepgram,
            "Disconnecting: ws=\(wsMessageCount), audio=\(audioPacketsSent) packets / \(String(format: "%.2f", mbSent))MB, transcript(msg=\(transcriptMessageCount), words=\(transcriptWordCount), final=\(finalTranscriptCount), empty=\(emptyTranscriptCount)), sendErrors=\(audioSendErrors)"
        )
        _sendConnected = false
        _sendTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        consecutiveSendErrors = 0
        connectionState = .disconnected
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
                    print("WebSocket send error: \(error)")
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
                    print("WebSocket receive error: \(error)")
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
                
                let isFinal = response.isFinal ?? false
                let hasTranscriptText = !alternative.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                transcriptMessageCount += 1
                if alternative.words.isEmpty && !hasTranscriptText {
                    emptyTranscriptCount += 1
                } else {
                    transcriptWordCount += alternative.words.count
                    lastTranscriptAt = CFAbsoluteTimeGetCurrent()
                    if isFinal { finalTranscriptCount += 1 }
                }
                
                // Debug: Log speaker info from raw response
                let speakersInResponse = alternative.words.compactMap { $0.speaker }
                let uniqueSpeakers = Set(speakersInResponse)
                if isFinal && !alternative.words.isEmpty {
                    print("[Deepgram] Final result - Speakers detected: \(uniqueSpeakers), Words: \(alternative.words.count)")
                    let preview = alternative.transcript.prefix(80)
                    DebugLogger.shared.log(
                        .deepgram,
                        "Final transcript: words=\(alternative.words.count), speakers=\(Array(uniqueSpeakers).sorted()), text=\"\(preview)\""
                    )
                    // Log first few words with speaker info
                    for word in alternative.words.prefix(5) {
                        print("  - '\(word.word)' speaker: \(word.speaker ?? -1)")
                    }
                }
                
                // Parse words with speaker info, overriding with source dominance
                var micTaggedWordCount = 0
                var unknownTaggedWordCount = 0
                let words = alternative.words.map { word in
                    var speaker = word.speaker ?? 0
                    
                    // If source tracking is available, override speaker based on
                    // which audio source was dominant during this word's timeframe.
                    // Mic words → micSpeakerID ("You"), system words → keep Deepgram's ID.
                    if let lookup = sourceLookup {
                        let source = lookup(word.start, word.end)
                        if source == .mic {
                            speaker = DeepgramService.micSpeakerID
                            micTaggedWordCount += 1
                        } else if source == .unknown {
                            unknownTaggedWordCount += 1
                        }
                        // .system → keep Deepgram's speaker (for multi-speaker remote diarization)
                        // .unknown → keep Deepgram's speaker as fallback
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
                    if sourceLookup != nil {
                        DebugLogger.shared.log(
                            .deepgram,
                            "Source tagging: mic=\(micTaggedWordCount), unknown=\(unknownTaggedWordCount), total=\(alternative.words.count)"
                        )
                    }
                    for word in alternative.words {
                        let speaker = word.speaker ?? 0
                        var info = speakerHistory[speaker] ?? SpeakerInfo()
                        info.wordCount += 1
                        info.totalDuration += word.end - word.start
                        speakerHistory[speaker] = info
                    }
                    print("[Deepgram] Total unique speakers so far: \(speakerHistory.keys.sorted())")
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
                print("[Deepgram] Parse warning: \(error.localizedDescription)")
            }
        }
    }
    
    /// Segments words by speaker, creating separate segments when speaker changes
    /// Uses lookahead to avoid splitting on spurious single-word speaker changes
    private func segmentBySpeaker(words: [TranscriptUpdate.Word], isFinal: Bool, confidence: Double) -> [SpeakerSegment] {
        guard !words.isEmpty else { return [] }
        
        // Conservative switch confirmation to reduce boundary bleed.
        let minWordsForSpeakerChange = 4
        let minDurationForSpeakerChange = 0.85
        let minAverageSpeakerConfidenceForSwitch = 0.58
        
        // New speaker IDs need stronger evidence before we start rendering them.
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
                // Potential speaker change - look ahead to confirm
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
                let isKnownSpeaker = confirmedSpeakerIDs.contains(newSpeaker) || newSpeaker == DeepgramService.micSpeakerID
                
                var allowSwitch = passesGeneralSwitchChecks && passesSwitchConfidenceCheck
                if allowSwitch && !isKnownSpeaker {
                    var evidence = pendingSpeakerEvidence[newSpeaker] ?? PendingSpeakerEvidence()
                    evidence.add(words: candidateWords)
                    pendingSpeakerEvidence[newSpeaker] = evidence
                    
                    let promotedByWords = evidence.wordCount >= minWordsForNewSpeakerPromotion
                    let promotedByDuration = evidence.duration >= minDurationForNewSpeakerPromotion
                    let promotedByConfidence = (evidence.averageSpeakerConfidence ?? 1.0) >= minAverageSpeakerConfidenceForNewSpeaker
                    let isPromoted = promotedByWords && promotedByDuration && promotedByConfidence
                    if isPromoted {
                        confirmedSpeakerIDs.insert(newSpeaker)
                        pendingSpeakerEvidence.removeValue(forKey: newSpeaker)
                    } else {
                        allowSwitch = false
                    }
                }
                
                // Only split when checks pass; otherwise absorb the run into current speaker.
                if allowSwitch {
                    // Save current segment
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
                    
                    // Start new segment with new speaker
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
        
        // Don't forget the last segment
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
    
    private func updateConfirmedSpeakers(from segments: [SpeakerSegment]) {
        for segment in segments {
            confirmedSpeakerIDs.insert(segment.speaker)
            pendingSpeakerEvidence.removeValue(forKey: segment.speaker)
        }
    }
    
    /// Find the speaker who spoke the most words in this segment
    private func findDominantSpeaker(words: [TranscriptUpdate.Word]) -> Int {
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

private struct DeepgramResponse: Codable {
    let type: String?
    let channel: Channel?
    let isFinal: Bool?
    let speechFinal: Bool?
    let start: Double?
    let duration: Double?
    let fromFinalize: Bool?
    
    enum CodingKeys: String, CodingKey {
        case type
        case channel
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
