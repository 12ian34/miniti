import Foundation

// MARK: - OpenAI Model

enum OpenAIModel: String, Codable {
    case gpt5Mini = "gpt-5-mini-2025-08-07"
}

// MARK: - Insights Mode

enum InsightsMode: String, CaseIterable, Codable {
    case standard = "standard"
    case meddpicc = "meddpicc"
    case training = "training"
    
    var displayName: String {
        switch self {
        case .standard: return "standard"
        case .meddpicc: return "MEDDPICC"
        case .training: return "training"
        }
    }
    
    var description: String {
        switch self {
        case .standard: return "General meeting insights"
        case .meddpicc: return "Sales qualification framework"
        case .training: return "Speech pattern analysis"
        }
    }
}

// MARK: - Training Metrics (locally computed, no LLM)

struct TrainingMetrics {
    struct FillerEntry: Identifiable {
        let id = UUID()
        let word: String
        let count: Int
    }
    
    struct SpeakerStats: Identifiable {
        let id = UUID()
        let speakerLabel: String
        let isLocalMic: Bool
        let wordCount: Int
        let segmentCount: Int
        let fillers: [FillerEntry]
        let totalFillers: Int
        let fillersPerMinute: Double
        let wordsPerMinute: Double
        let longestMonologueWords: Int
        let questionsAsked: Int
        let avgWordsPerTurn: Double
    }
    
    let speakers: [SpeakerStats]
    let talkRatioYou: Double
    let durationMinutes: Double
    
    struct Segment {
        let text: String
        let speaker: Int
        let isFinal: Bool
        let timestamp: TimeInterval
    }
    
    static func compute(from segments: [Segment], duration: TimeInterval, language: String = "en") -> TrainingMetrics {
        let finals = segments
            .enumerated()
            .filter { _, segment in
                segment.isFinal && !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { lhs, rhs in
                if lhs.element.timestamp == rhs.element.timestamp {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.timestamp < rhs.element.timestamp
            }
            .map(\.element)
        let reportedDurationSeconds = max(duration, 0)
        let lastSpokenTimestamp = finals.last?.timestamp ?? 0
        let effectiveDurationSeconds = lastSpokenTimestamp > 0
            ? (reportedDurationSeconds > 0 ? min(reportedDurationSeconds, lastSpokenTimestamp) : lastSpokenTimestamp)
            : reportedDurationSeconds
        let durationMinutes = max(effectiveDurationSeconds / 60.0, 0.01)
        let configuredFillersWithTokens: [(tokens: [String], label: String)] = TrainingFillerPreferences.currentFillers(for: language)
            .map { phrase in
                (tokens: tokenize(phrase), label: phrase)
            }
            .filter { !$0.tokens.isEmpty }
        
        let speakerIDs = Array(Set(finals.map(\.speaker))).sorted { a, b in
            if a == DeepgramService.micSpeakerID { return true }
            if b == DeepgramService.micSpeakerID { return false }
            return a < b
        }
        
        var totalWordsAll = 0
        var youWordCount = 0
        var speakerStatsList: [SpeakerStats] = []
        
        for speakerID in speakerIDs {
            let speakerSegments = finals.filter { $0.speaker == speakerID }
            let isMic = speakerID == DeepgramService.micSpeakerID
            let label = isMic ? "You" : "Speaker \(speakerID + 1)"
            
            var wordCount = 0
            var fillerMap: [String: Int] = [:]
            var questionsAsked = 0
            
            for seg in speakerSegments {
                let tokens = tokenize(seg.text)
                wordCount += tokens.count
                
                questionsAsked += seg.text.filter { $0 == "?" }.count
                
                for (phraseTokens, label) in configuredFillersWithTokens {
                    let count = countPhraseOccurrences(of: phraseTokens, in: tokens)
                    if count > 0 { fillerMap[label, default: 0] += count }
                }
            }
            
            totalWordsAll += wordCount
            if isMic { youWordCount = wordCount }
            
            let totalFillers = fillerMap.values.reduce(0, +)
            let fillerEntries = fillerMap
                .sorted { $0.value > $1.value }
                .map { FillerEntry(word: $0.key, count: $0.value) }
            
            let longestMonologue = computeLongestMonologue(for: speakerID, in: finals)
            
            speakerStatsList.append(SpeakerStats(
                speakerLabel: label,
                isLocalMic: isMic,
                wordCount: wordCount,
                segmentCount: speakerSegments.count,
                fillers: fillerEntries,
                totalFillers: totalFillers,
                fillersPerMinute: Double(totalFillers) / durationMinutes,
                wordsPerMinute: Double(wordCount) / durationMinutes,
                longestMonologueWords: longestMonologue,
                questionsAsked: questionsAsked,
                avgWordsPerTurn: speakerSegments.isEmpty ? 0 : Double(wordCount) / Double(speakerSegments.count)
            ))
        }
        
        let ratio = totalWordsAll > 0 ? Double(youWordCount) / Double(totalWordsAll) : 0
        
        return TrainingMetrics(
            speakers: speakerStatsList,
            talkRatioYou: ratio,
            durationMinutes: durationMinutes
        )
    }
    
    static func tokenize(_ text: String) -> [String] {
        let cleaned = text
            .lowercased()
            .replacingOccurrences(
                of: "[^\\p{L}\\p{N}\\s']",
                with: " ",
                options: .regularExpression
            )
        return cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
    }
    
    static func countPhraseOccurrences(of phraseTokens: [String], in tokens: [String]) -> Int {
        guard !phraseTokens.isEmpty else { return 0 }
        guard tokens.count >= phraseTokens.count else { return 0 }
        
        var count = 0
        for idx in 0...(tokens.count - phraseTokens.count) {
            if tokens[idx..<(idx + phraseTokens.count)].elementsEqual(phraseTokens) {
                count += 1
            }
        }
        return count
    }
    
    static func computeLongestMonologue(for speaker: Int, in segments: [Segment]) -> Int {
        var longest = 0
        var current = 0
        for seg in segments {
            if seg.speaker == speaker {
                current += tokenize(seg.text).count
            } else {
                longest = max(longest, current)
                current = 0
            }
        }
        return max(longest, current)
    }
}

enum TrainingFillerPreferences {
    private static let legacyStorageKey = "trainingCustomFillers.v1"
    static let defaultFillers: [String] = TranscriptionLanguage.english.defaultFillers
    
    private static func storageKey(for language: String) -> String {
        "trainingCustomFillers.v1.\(language)"
    }
    
    static func defaultFillers(for language: String) -> [String] {
        TranscriptionLanguage(rawValue: language)?.defaultFillers ?? TranscriptionLanguage.english.defaultFillers
    }
    
    static func currentFillers(for language: String = "en", defaults: UserDefaults = .standard) -> [String] {
        let key = storageKey(for: language)
        
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            let normalized = normalizedFillers(decoded)
            return normalized.isEmpty ? defaultFillers(for: language) : normalized
        }
        
        if language == "en", let legacyData = defaults.data(forKey: legacyStorageKey),
           let decoded = try? JSONDecoder().decode([String].self, from: legacyData) {
            let normalized = normalizedFillers(decoded)
            if !normalized.isEmpty {
                save(normalized, for: language, defaults: defaults)
                return normalized
            }
        }
        
        return defaultFillers(for: language)
    }
    
    static func save(_ fillers: [String], for language: String = "en", defaults: UserDefaults = .standard) {
        let normalized = normalizedFillers(fillers)
        let langDefaults = defaultFillers(for: language)
        if normalized == langDefaults {
            defaults.removeObject(forKey: storageKey(for: language))
            return
        }
        
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: storageKey(for: language))
    }
    
    static func reset(for language: String = "en", defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey(for: language))
    }
    
    static func normalizedFillers(_ fillers: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        
        for filler in fillers {
            let compacted = filler
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard !compacted.isEmpty else { continue }
            guard !seen.contains(compacted) else { continue }
            seen.insert(compacted)
            normalized.append(compacted)
        }
        
        return normalized
    }
}

final class InsightsService: Sendable {
    struct MeetingInsights {
        let summary: String
        let actionItems: [String]
        let decisions: [String]
        let topics: [String]
    }
    
    struct LiveInsights {
        let summary: String
        let actionItems: [String]
        let topics: [String]
        let discussionFlow: [String] // Chronological discussion points
        let suggestedTitle: String?
        // MEDDPICC fields (optional, only populated in meddpicc mode)
        let metrics: String?
        let economicBuyer: String?
        let decisionCriteria: String?
        let decisionProcess: String?
        let paperProcess: String?
        let identifiedPain: String?
        let champion: String?
        let competition: String?
    }
    
    /// Generate real-time insights during a meeting (faster, more concise)
    func generateLiveInsights(transcript: String, existingSummary: String?, existingTitle: String?, mode: InsightsMode = .standard, model: OpenAIModel = .gpt5Mini, apiKey: String, language: String = "en") async throws -> LiveInsights {
        guard !transcript.isEmpty else {
            throw InsightsError.emptyTranscript
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        DebugLogger.shared.log(
            .app,
            "BYOK insights request: mode=\(mode.rawValue), model=\(model.rawValue), transcriptChars=\(transcript.count), hasSummary=\(existingSummary != nil), hasTitle=\(existingTitle != nil), language=\(language)"
        )
        
        let contextNote = existingSummary != nil 
            ? "Previous summary: \"\(existingSummary!)\"\n\nUpdate this summary with new information from the transcript below. Keep it concise (2-3 sentences max)."
            : "This is the start of the meeting. Provide a brief summary."
        
        // Ask for title if existingTitle is nil (caller decides when to request updates)
        let needsTitle = existingTitle == nil
        let titleInstruction = needsTitle 
            ? "\"title\": \"Short descriptive title for this meeting (3-6 words, like 'Q4 Planning Review' or 'API Integration Discussion')\","
            : ""
        
        let langName = TranscriptionLanguage(rawValue: language)?.englishName ?? "English"
        let languageInstruction = language != "en"
            ? "IMPORTANT: The transcript is in \(langName). All content values in your JSON response MUST be in \(langName). JSON keys remain in English.\n\n"
            : ""
        
        let prompt: String
        let systemPrompt: String
        let maxCompletionTokens: Int
        
        switch mode {
        case .standard:
            systemPrompt = "You provide real-time meeting summaries. Be extremely concise. Focus on what's being discussed RIGHT NOW."
            maxCompletionTokens = 10000
            prompt = """
            \(languageInstruction)You are providing LIVE meeting insights. Be very concise.
            
            \(contextNote)
            
            Respond in JSON:
            {
                \(titleInstruction)
                "summary": "Brief 1-2 sentence summary of what's being discussed",
                "action_items": ["Any action items mentioned (keep short)"],
                "topics": ["Broad themes/categories being discussed (1-2 words each, max 4 topics, e.g. 'Strategy', 'Budget', 'Timeline')"],
                "discussion_flow": ["Chronological list of what was discussed, in order (e.g. 'Introductions', 'Reviewed Q3 metrics', 'Discussed budget concerns', 'Agreed on next steps')"]
            }
            
            Latest transcript:
            \(transcript)
            """
            
        case .meddpicc:
            systemPrompt = "You are a sales qualification analyst using the MEDDPICC framework. Extract qualification insights from sales conversations. Be concise but thorough on qualification criteria."
            maxCompletionTokens = 10000
            prompt = """
            \(languageInstruction)Analyze this sales call using the MEDDPICC framework. Extract any information mentioned.
            
            \(contextNote)
            
            MEDDPICC Framework:
            - Metrics: Quantifiable success measures the prospect mentioned
            - Economic Buyer: Who controls budget/final decision
            - Decision Criteria: Factors influencing their decision
            - Decision Process: Their buying/evaluation process
            - Paper Process: Legal, procurement, security review steps
            - Identify Pain: Problems they're trying to solve
            - Champion: Internal advocate for your solution
            - Competition: Other solutions they're considering
            
            For each MEDDPICC field, list each distinct point on its own line starting with "- ". Use null if no information.
            
            Respond in JSON:
            {
                \(titleInstruction)
                "summary": "Brief summary of the sales conversation",
                "action_items": ["Follow-up actions needed"],
                "topics": ["Broad themes discussed (1-2 words each)"],
                "metrics": "- Point one\\n- Point two (or null)",
                "economic_buyer": "- Point one\\n- Point two (or null)",
                "decision_criteria": "- Point one\\n- Point two (or null)",
                "decision_process": "- Point one\\n- Point two (or null)",
                "paper_process": "- Point one\\n- Point two (or null)",
                "identified_pain": "- Point one\\n- Point two (or null)",
                "champion": "- Point one\\n- Point two (or null)",
                "competition": "- Point one\\n- Point two (or null)"
            }
            
            Latest transcript:
            \(transcript)
            """
        
        case .training:
            systemPrompt = "You provide real-time meeting summaries. Be extremely concise. Focus on what's being discussed RIGHT NOW."
            maxCompletionTokens = 10000
            prompt = """
            \(languageInstruction)You are providing LIVE meeting insights. Be very concise.
            
            \(contextNote)
            
            Respond in JSON:
            {
                \(titleInstruction)
                "summary": "Brief 1-2 sentence summary of what's being discussed",
                "action_items": ["Any action items mentioned (keep short)"],
                "topics": ["Broad themes/categories being discussed (1-2 words each, max 4 topics)"],
                "discussion_flow": ["Chronological list of what was discussed, in order"]
            }
            
            Latest transcript:
            \(transcript)
            """
        }
        
        let requestBody = OpenAIRequest(
            model: model.rawValue,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: prompt)
            ],
            maxCompletionTokens: maxCompletionTokens,
            responseFormat: ResponseFormat(type: "json_object")
        )
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            DebugLogger.shared.log(.app, "BYOK insights response error: mode=\(mode.rawValue), status=\(statusCode)")
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw InsightsError.apiError(errorResponse.error.message)
            }
            throw InsightsError.invalidResponse
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = openAIResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            DebugLogger.shared.log(.app, "BYOK insights response missing content: mode=\(mode.rawValue)")
            throw InsightsError.noContent
        }
        
        let insightsResponse = try JSONDecoder().decode(LiveInsightsResponse.self, from: jsonData)
        let duration = CFAbsoluteTimeGetCurrent() - startedAt
        let meddpiccFieldCount = [
            insightsResponse.metrics,
            insightsResponse.economicBuyer,
            insightsResponse.decisionCriteria,
            insightsResponse.decisionProcess,
            insightsResponse.paperProcess,
            insightsResponse.identifiedPain,
            insightsResponse.champion,
            insightsResponse.competition
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && $0.lowercased() != "null" }
        .count
        DebugLogger.shared.log(
            .app,
            "BYOK insights response: mode=\(mode.rawValue), duration=\(String(format: "%.2fs", duration)), summaryChars=\(insightsResponse.summary.count), actionItems=\(insightsResponse.actionItems.count), topics=\(insightsResponse.topics.count), meddpiccFields=\(meddpiccFieldCount)"
        )
        
        return LiveInsights(
            summary: insightsResponse.summary,
            actionItems: insightsResponse.actionItems,
            topics: insightsResponse.topics,
            discussionFlow: insightsResponse.discussionFlow,
            suggestedTitle: insightsResponse.title,
            metrics: insightsResponse.metrics,
            economicBuyer: insightsResponse.economicBuyer,
            decisionCriteria: insightsResponse.decisionCriteria,
            decisionProcess: insightsResponse.decisionProcess,
            paperProcess: insightsResponse.paperProcess,
            identifiedPain: insightsResponse.identifiedPain,
            champion: insightsResponse.champion,
            competition: insightsResponse.competition
        )
    }
    
    /// Generate full insights at end of meeting
    func generateInsights(transcript: String, model: OpenAIModel = .gpt5Mini, apiKey: String, language: String = "en") async throws -> MeetingInsights {
        guard !transcript.isEmpty else {
            throw InsightsError.emptyTranscript
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        DebugLogger.shared.log(
            .app,
            "BYOK final insights request: model=\(model.rawValue), transcriptChars=\(transcript.count), language=\(language)"
        )
        
        let langName = TranscriptionLanguage(rawValue: language)?.englishName ?? "English"
        let languageInstruction = language != "en"
            ? "IMPORTANT: The transcript is in \(langName). All content values in your JSON response MUST be in \(langName). JSON keys remain in English.\n\n"
            : ""
        
        let prompt = """
        \(languageInstruction)Analyze this meeting transcript and provide structured insights.
        
        Respond in JSON format with the following structure:
        {
            "summary": "A 2-3 sentence summary of the meeting",
            "action_items": ["List of action items mentioned"],
            "decisions": ["Key decisions made during the meeting"],
            "topics": ["Broad themes/categories (1-2 words each, e.g. 'Strategy', 'Budget', 'Hiring')"]
        }
        
        Be concise. If no action items or decisions were made, return empty arrays.
        Topics should be high-level categories, not specific details.
        
        Transcript:
        \(transcript)
        """
        
        let requestBody = OpenAIRequest(
            model: model.rawValue,
            messages: [
                Message(role: "system", content: "You are a meeting analyst. Provide concise, actionable insights from meeting transcripts. Always respond with valid JSON."),
                Message(role: "user", content: prompt)
            ],
            maxCompletionTokens: 1000,
            responseFormat: ResponseFormat(type: "json_object")
        )
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLogger.shared.log(.app, "BYOK final insights response error: invalid HTTP response")
            throw InsightsError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            DebugLogger.shared.log(.app, "BYOK final insights response error: status=\(httpResponse.statusCode)")
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw InsightsError.apiError(errorResponse.error.message)
            }
            throw InsightsError.httpError(httpResponse.statusCode)
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = openAIResponse.choices.first?.message.content else {
            DebugLogger.shared.log(.app, "BYOK final insights response missing content")
            throw InsightsError.noContent
        }
        
        // Parse the JSON response
        guard let jsonData = content.data(using: .utf8) else {
            throw InsightsError.invalidJson
        }
        
        let insightsResponse = try JSONDecoder().decode(InsightsResponse.self, from: jsonData)
        let duration = CFAbsoluteTimeGetCurrent() - startedAt
        DebugLogger.shared.log(
            .app,
            "BYOK final insights response: duration=\(String(format: "%.2fs", duration)), summaryChars=\(insightsResponse.summary.count), actionItems=\(insightsResponse.actionItems.count), decisions=\(insightsResponse.decisions.count), topics=\(insightsResponse.topics.count)"
        )
        
        return MeetingInsights(
            summary: insightsResponse.summary,
            actionItems: insightsResponse.actionItems,
            decisions: insightsResponse.decisions,
            topics: insightsResponse.topics
        )
    }
}

// MARK: - Request/Response Models

private struct OpenAIRequest: Codable {
    let model: String
    let messages: [Message]
    let maxCompletionTokens: Int
    let responseFormat: ResponseFormat
    
    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxCompletionTokens = "max_completion_tokens"
        case responseFormat = "response_format"
    }
}

private struct Message: Codable {
    let role: String
    let content: String
}

private struct ResponseFormat: Codable {
    let type: String
}

struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: MessageContent
    }
    
    struct MessageContent: Codable {
        let content: String
    }
}

struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let message: String
    }
}

struct InsightsResponse: Codable {
    let summary: String
    let actionItems: [String]
    let decisions: [String]
    let topics: [String]
    
    enum CodingKeys: String, CodingKey {
        case summary
        case actionItems = "action_items"
        case decisions
        case topics
    }
}

struct LiveInsightsResponse: Codable {
    let summary: String
    let actionItems: [String]
    let topics: [String]
    let discussionFlow: [String]
    let title: String?
    // MEDDPICC fields
    let metrics: String?
    let economicBuyer: String?
    let decisionCriteria: String?
    let decisionProcess: String?
    let paperProcess: String?
    let identifiedPain: String?
    let champion: String?
    let competition: String?
    
    enum CodingKeys: String, CodingKey {
        case summary
        case actionItems = "action_items"
        case topics
        case discussionFlow = "discussion_flow"
        case title
        case metrics
        case economicBuyer = "economic_buyer"
        case decisionCriteria = "decision_criteria"
        case decisionProcess = "decision_process"
        case paperProcess = "paper_process"
        case identifiedPain = "identified_pain"
        case champion
        case competition
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        actionItems = try container.decodeIfPresent([String].self, forKey: .actionItems) ?? []
        topics = try container.decodeIfPresent([String].self, forKey: .topics) ?? []
        discussionFlow = try container.decodeIfPresent([String].self, forKey: .discussionFlow) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title)
        metrics = try container.decodeIfPresent(String.self, forKey: .metrics)
        economicBuyer = try container.decodeIfPresent(String.self, forKey: .economicBuyer)
        decisionCriteria = try container.decodeIfPresent(String.self, forKey: .decisionCriteria)
        decisionProcess = try container.decodeIfPresent(String.self, forKey: .decisionProcess)
        paperProcess = try container.decodeIfPresent(String.self, forKey: .paperProcess)
        identifiedPain = try container.decodeIfPresent(String.self, forKey: .identifiedPain)
        champion = try container.decodeIfPresent(String.self, forKey: .champion)
        competition = try container.decodeIfPresent(String.self, forKey: .competition)
    }
}

// MARK: - Errors

enum InsightsError: LocalizedError {
    case emptyTranscript
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noContent
    case invalidJson
    
    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "No transcript to analyze."
        case .invalidResponse:
            return "Invalid response from OpenAI."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .noContent:
            return "No content in response."
        case .invalidJson:
            return "Failed to parse insights JSON."
        }
    }
}
