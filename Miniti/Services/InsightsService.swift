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
    
    var displayName: String {
        switch self {
        case .standard: return "standard"
        case .meddpicc: return "MEDDPICC"
        }
    }
    
    var description: String {
        switch self {
        case .standard: return "General meeting insights"
        case .meddpicc: return "Sales qualification framework"
        }
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
            
            Respond in JSON (use null for fields with no information yet):
            {
                \(titleInstruction)
                "summary": "Brief summary of the sales conversation",
                "action_items": ["Follow-up actions needed"],
                "topics": ["Broad themes discussed (1-2 words each)"],
                "metrics": "What success metrics were mentioned (or null)",
                "economic_buyer": "Who is the economic buyer (or null)",
                "decision_criteria": "What decision criteria were mentioned (or null)",
                "decision_process": "What's their decision process (or null)",
                "paper_process": "What's their paper/procurement process (or null)",
                "identified_pain": "What pain points were identified (or null)",
                "champion": "Who could be a champion (or null)",
                "competition": "What competitors were mentioned (or null)"
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
