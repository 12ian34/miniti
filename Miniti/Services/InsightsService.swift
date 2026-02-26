import Foundation

// MARK: - OpenAI Model

enum OpenAIModel: String, CaseIterable, Codable {
    case gpt5Mini = "gpt-5-mini-2025-08-07"
    case gpt5Nano = "gpt-5-nano-2025-08-07"
    
    var displayName: String {
        switch self {
        case .gpt5Mini: return "GPT-5 Mini"
        case .gpt5Nano: return "GPT-5 Nano"
        }
    }
    
    var shortName: String {
        switch self {
        case .gpt5Mini: return "5-mini"
        case .gpt5Nano: return "5-nano"
        }
    }
    
    var shortDescription: String {
        switch self {
        case .gpt5Mini: return "Best quality insights"
        case .gpt5Nano: return "Fast and efficient"
        }
    }
    
    var pros: [String] {
        switch self {
        case .gpt5Mini: return ["Higher accuracy", "Better reasoning", "More nuanced insights"]
        case .gpt5Nano: return ["2x faster", "Lower cost", "Great for real-time"]
        }
    }
    
    var cons: [String] {
        switch self {
        case .gpt5Mini: return ["Slower response", "Higher API cost"]
        case .gpt5Nano: return ["Less detailed", "May miss nuances"]
        }
    }
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
    
    private static let hardFillers: Set<String> = ["um", "uh", "uh huh", "hmm", "hm", "er", "ah"]
    private static let softFillers: Set<String> = ["like", "basically", "literally", "actually", "honestly"]
    private static let phraseFillers: [(phrase: String, label: String)] = [
        ("you know", "you know"),
        ("i mean", "I mean"),
        ("kind of", "kind of"),
        ("sort of", "sort of"),
    ]
    
    struct Segment {
        let text: String
        let speaker: Int
        let isFinal: Bool
    }
    
    static func compute(from segments: [Segment], duration: TimeInterval) -> TrainingMetrics {
        let finals = segments.filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let durationMinutes = max(duration / 60.0, 0.01)
        
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
            var totalWordsInTurns = 0
            
            for seg in speakerSegments {
                let words = seg.text.split(separator: " ")
                wordCount += words.count
                
                if seg.text.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
                    questionsAsked += 1
                }
                
                let lower = seg.text.lowercased()
                
                for filler in hardFillers {
                    let count = countWordOccurrences(of: filler, in: lower)
                    if count > 0 { fillerMap[filler, default: 0] += count }
                }
                
                for filler in softFillers {
                    let count = countWordOccurrences(of: filler, in: lower)
                    if count > 0 { fillerMap[filler, default: 0] += count }
                }
                
                for (phrase, label) in phraseFillers {
                    let count = countPhraseOccurrences(of: phrase, in: lower)
                    if count > 0 { fillerMap[label, default: 0] += count }
                }
            }
            
            totalWordsAll += wordCount
            if isMic { youWordCount = wordCount }
            totalWordsInTurns = wordCount
            
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
                avgWordsPerTurn: speakerSegments.isEmpty ? 0 : Double(totalWordsInTurns) / Double(speakerSegments.count)
            ))
        }
        
        let ratio = totalWordsAll > 0 ? Double(youWordCount) / Double(totalWordsAll) : 0
        
        return TrainingMetrics(
            speakers: speakerStatsList,
            talkRatioYou: ratio,
            durationMinutes: durationMinutes
        )
    }
    
    private static func countWordOccurrences(of word: String, in text: String) -> Int {
        let words = text.split(separator: " ").map { String($0).trimmingCharacters(in: .punctuationCharacters) }
        return words.filter { $0 == word }.count
    }
    
    private static func countPhraseOccurrences(of phrase: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: phrase, options: [], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }
    
    private static func computeLongestMonologue(for speaker: Int, in segments: [Segment]) -> Int {
        var longest = 0
        var current = 0
        for seg in segments {
            if seg.speaker == speaker {
                current += seg.text.split(separator: " ").count
            } else {
                longest = max(longest, current)
                current = 0
            }
        }
        return max(longest, current)
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
    func generateLiveInsights(transcript: String, existingSummary: String?, existingTitle: String?, mode: InsightsMode = .standard, model: OpenAIModel = .gpt5Mini, apiKey: String) async throws -> LiveInsights {
        guard !transcript.isEmpty else {
            throw InsightsError.emptyTranscript
        }
        
        let contextNote = existingSummary != nil 
            ? "Previous summary: \"\(existingSummary!)\"\n\nUpdate this summary with new information from the transcript below. Keep it concise (2-3 sentences max)."
            : "This is the start of the meeting. Provide a brief summary."
        
        // Ask for title if existingTitle is nil (caller decides when to request updates)
        let needsTitle = existingTitle == nil
        let titleInstruction = needsTitle 
            ? "\"title\": \"Short descriptive title for this meeting (3-6 words, like 'Q4 Planning Review' or 'API Integration Discussion')\","
            : ""
        
        let prompt: String
        let systemPrompt: String
        let maxCompletionTokens: Int
        
        switch mode {
        case .standard:
            systemPrompt = "You provide real-time meeting summaries. Be extremely concise. Focus on what's being discussed RIGHT NOW."
            maxCompletionTokens = 10000
            prompt = """
            You are providing LIVE meeting insights. Be very concise.
            
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
            Analyze this sales call using the MEDDPICC framework. Extract any information mentioned.
            
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
            You are providing LIVE meeting insights. Be very concise.
            
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
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw InsightsError.apiError(errorResponse.error.message)
            }
            throw InsightsError.invalidResponse
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = openAIResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw InsightsError.noContent
        }
        
        let insightsResponse = try JSONDecoder().decode(LiveInsightsResponse.self, from: jsonData)
        
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
    func generateInsights(transcript: String, model: OpenAIModel = .gpt5Mini, apiKey: String) async throws -> MeetingInsights {
        guard !transcript.isEmpty else {
            throw InsightsError.emptyTranscript
        }
        
        let prompt = """
        Analyze this meeting transcript and provide structured insights.
        
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
            throw InsightsError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw InsightsError.apiError(errorResponse.error.message)
            }
            throw InsightsError.httpError(httpResponse.statusCode)
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = openAIResponse.choices.first?.message.content else {
            throw InsightsError.noContent
        }
        
        // Parse the JSON response
        guard let jsonData = content.data(using: .utf8) else {
            throw InsightsError.invalidJson
        }
        
        let insightsResponse = try JSONDecoder().decode(InsightsResponse.self, from: jsonData)
        
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

private struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: MessageContent
    }
    
    struct MessageContent: Codable {
        let content: String
    }
}

private struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let message: String
    }
}

private struct InsightsResponse: Codable {
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

private struct LiveInsightsResponse: Codable {
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
