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
    case questions = "questions"
    
    var displayName: String {
        switch self {
        case .standard: return "standard"
        case .meddpicc: return "MEDDPICC"
        case .training: return "training"
        case .questions: return "questions"
        }
    }
    
    var description: String {
        switch self {
        case .standard: return "General meeting insights"
        case .meddpicc: return "Sales qualification framework"
        case .training: return "Speech pattern analysis"
        case .questions: return "Suggested questions to ask"
        }
    }
}

struct SuggestedQuestion: Codable, Identifiable, Equatable {
    var id: String { question }
    let question: String
    let type: String
    let context: String
    let priority: String?

    var isHighPriority: Bool {
        priority?.lowercased() == "high"
    }

    init(question: String, type: String, context: String, priority: String? = nil) {
        self.question = question
        self.type = type
        self.context = context
        self.priority = priority
    }

    enum CodingKeys: String, CodingKey {
        case question
        case type
        case context
        case priority
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        question = try c.decode(String.self, forKey: .question)
        type = try c.decode(String.self, forKey: .type)
        context = try c.decode(String.self, forKey: .context)
        priority = try c.decodeIfPresent(String.self, forKey: .priority)
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
    
    static func compute(from segments: [Segment], duration: TimeInterval, language: String = "en", names: [String: String]? = nil, selfIDs: Set<Int>? = nil) -> TrainingMetrics {
        let effectiveSelfIDs: Set<Int> = {
            if let selfIDs, !selfIDs.isEmpty { return selfIDs }
            return [DeepgramService.micSpeakerID]
        }()
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

        // Group speakers: all self-IDs collapse into one virtual "self" bucket so split
        // diarization (one person showing up as two speaker IDs) produces unified stats.
        // Non-self IDs remain individual buckets.
        enum Group: Hashable {
            case selfSpeaker
            case other(Int)
        }
        var groupedSegments: [Group: [Segment]] = [:]
        for seg in finals {
            let key: Group = effectiveSelfIDs.contains(seg.speaker) ? .selfSpeaker : .other(seg.speaker)
            groupedSegments[key, default: []].append(seg)
        }
        let sortedGroups: [Group] = groupedSegments.keys.sorted { a, b in
            switch (a, b) {
            case (.selfSpeaker, _): return true
            case (_, .selfSpeaker): return false
            case (.other(let lhs), .other(let rhs)): return lhs < rhs
            }
        }

        var totalWordsAll = 0
        var youWordCount = 0
        var speakerStatsList: [SpeakerStats] = []

        for group in sortedGroups {
            let speakerSegments = groupedSegments[group] ?? []
            let isLocalMic = group == .selfSpeaker
            let label: String = {
                switch group {
                case .selfSpeaker: return "You"
                case .other(let id): return resolvedSpeakerLabel(for: id, names: names, selfIDs: selfIDs)
                }
            }()

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
            if isLocalMic { youWordCount = wordCount }

            let totalFillers = fillerMap.values.reduce(0, +)
            let fillerEntries = fillerMap
                .sorted { $0.value > $1.value }
                .map { FillerEntry(word: $0.key, count: $0.value) }

            let monologueIDs: Set<Int> = {
                switch group {
                case .selfSpeaker: return effectiveSelfIDs
                case .other(let id): return [id]
                }
            }()
            let longestMonologue = computeLongestMonologue(forSpeakers: monologueIDs, in: finals)

            speakerStatsList.append(SpeakerStats(
                speakerLabel: label,
                isLocalMic: isLocalMic,
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
        computeLongestMonologue(forSpeakers: [speaker], in: segments)
    }

    static func computeLongestMonologue(forSpeakers speakers: Set<Int>, in segments: [Segment]) -> Int {
        var longest = 0
        var current = 0
        for seg in segments {
            if speakers.contains(seg.speaker) {
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

struct CatchUpResult: Codable, Equatable {
    let currentTopic: String
    let questionsForYou: [String]
    let recentDiscussion: [String]
    let keyDecisions: [String]

    enum CodingKeys: String, CodingKey {
        case currentTopic = "current_topic"
        case questionsForYou = "questions_for_you"
        case recentDiscussion = "recent_discussion"
        case keyDecisions = "key_decisions"
    }

    init(
        currentTopic: String,
        questionsForYou: [String],
        recentDiscussion: [String],
        keyDecisions: [String]
    ) {
        self.currentTopic = currentTopic
        self.questionsForYou = questionsForYou
        self.recentDiscussion = recentDiscussion
        self.keyDecisions = keyDecisions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentTopic = (try c.decodeIfPresent(String.self, forKey: .currentTopic) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        questionsForYou = (try c.decodeIfPresent([String].self, forKey: .questionsForYou) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        recentDiscussion = (try c.decodeIfPresent([String].self, forKey: .recentDiscussion) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        keyDecisions = (try c.decodeIfPresent([String].self, forKey: .keyDecisions) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool {
        currentTopic.isEmpty && questionsForYou.isEmpty && recentDiscussion.isEmpty && keyDecisions.isEmpty
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
        let discussionFlow: [String]
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
        // Questions (optional, only populated in questions mode)
        let questions: [SuggestedQuestion]
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
            
        case .questions:
            systemPrompt = "You generate incisive questions that reveal what a conversation is missing. You find gaps, unstated assumptions, dropped threads, and tensions between statements. Your questions reference specific things said in the transcript — never generic. Each question should be something a brilliant, curious person would actually say out loud."
            maxCompletionTokens = 10000
            prompt = """
            \(languageInstruction)Analyze this conversation and generate questions the listener should ask. Focus on what's NOT been said, what's been assumed, and what's been glossed over.

            Hard rules:
            - Return ONLY one valid JSON object. No markdown, no prose, no code fences.
            - Generate 5-8 questions.
            - Each question MUST reference something specific from the transcript. No generic questions like "what are your priorities" or "tell me more".
            - Use at least 3 different question types across the set.
            - Questions must sound natural spoken aloud in a meeting — not academic or stiff.
            - "context" explains WHY this question matters — what it would reveal or uncover.

            Question types:
            - "deeper": follow a thread that was mentioned but not explored ("You mentioned X — what specifically about that...")
            - "challenge": surface a tension or contradiction between two things said
            - "reframe": question the premise, not the conclusion — step outside the conversation's frame
            - "clarify": pin down something vague or ambiguous ("When you say 'soon', do you mean...")
            - "explore": open territory the conversation hasn't touched but should, given context
            - "follow_up": the natural next move that turns understanding into action

            Priority:
            - Label a question "high" ONLY if missing the answer would materially change the outcome of the conversation (an unresolved contradiction, an unstated blocker, a dropped thread that the whole deal/decision hinges on). Otherwise label it "normal".
            - Be strict. At most 1-2 questions per response should be "high". A response with zero "high" questions is expected and correct. Never default to "high".

            Respond in JSON:
            {
                "questions": [
                    {
                        "question": "The actual question to ask",
                        "type": "deeper|challenge|reframe|clarify|explore|follow_up",
                        "context": "One line: why this question matters, what it reveals",
                        "priority": "high|normal"
                    }
                ]
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
            competition: insightsResponse.competition,
            questions: insightsResponse.questions
        )
    }
    
    /// Quick "i zoned out" catch-up. Takes the recent portion of the transcript and surfaces
    /// what's being discussed right now, any questions directed at the user that may be unanswered,
    /// recent discussion highlights, and key decisions made while the user was not paying attention.
    func generateCatchUp(
        recentTranscript: String,
        fullTranscript: String?,
        model: OpenAIModel = .gpt5Mini,
        apiKey: String,
        language: String = "en"
    ) async throws -> CatchUpResult {
        let trimmed = recentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InsightsError.emptyTranscript
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        DebugLogger.shared.log(
            .app,
            "BYOK catchup request: model=\(model.rawValue), recentChars=\(recentTranscript.count), fullChars=\(fullTranscript?.count ?? 0), language=\(language)"
        )

        let langName = TranscriptionLanguage(rawValue: language)?.englishName ?? "English"
        let languageInstruction = language != "en"
            ? "IMPORTANT: The transcript is in \(langName). All content values in your JSON response MUST be in \(langName). JSON keys remain in English.\n\n"
            : ""

        let fullContextBlock: String = {
            guard let full = fullTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !full.isEmpty, full != trimmed else {
                return ""
            }
            return "Earlier meeting context (for grounding only — do not summarize this, focus on the recent window):\n\(full)\n\n"
        }()

        let systemPrompt = "You help someone who just zoned out catch up on a live meeting in 5 seconds. You ground everything in the transcript — never invent questions, topics, or decisions that aren't there. You are concise, specific, and actionable."

        let prompt = """
        \(languageInstruction)The person on the mic (labeled "You") just zoned out of their meeting. Give them a fast catch-up based strictly on what's in the transcript.

        \(fullContextBlock)Most recent portion of the meeting (focus here):
        \(recentTranscript)

        Hard rules:
        - Return ONLY one valid JSON object. No markdown, no prose, no code fences.
        - "current_topic" must be a single short sentence describing what is being discussed RIGHT NOW (at the end of the transcript). If unclear, say so briefly.
        - "questions_for_you" lists questions that were directed at "You" in the recent window that do NOT appear to have been answered. Quote or paraphrase faithfully. If none, return an empty array. Never invent.
        - "recent_discussion" is a chronological bullet list (3-6 items) of what happened in the recent window. Each item is a short phrase, not a full sentence.
        - "key_decisions" lists any decisions, commitments, or agreements made in the recent window. Empty array if none.
        - Be specific. Reference names, numbers, and concrete terms from the transcript. Never generic.

        Respond in JSON:
        {
            "current_topic": "single short sentence",
            "questions_for_you": ["unanswered question directed at You"],
            "recent_discussion": ["bullet point 1", "bullet point 2"],
            "key_decisions": ["decision 1"]
        }
        """

        let requestBody = OpenAIRequest(
            model: model.rawValue,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: prompt)
            ],
            maxCompletionTokens: 4000,
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
            DebugLogger.shared.log(.app, "BYOK catchup response error: status=\(statusCode)")
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw InsightsError.apiError(errorResponse.error.message)
            }
            throw InsightsError.invalidResponse
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let content = openAIResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            DebugLogger.shared.log(.app, "BYOK catchup response missing content")
            throw InsightsError.noContent
        }

        let parsed = try JSONDecoder().decode(CatchUpResult.self, from: jsonData)
        let duration = CFAbsoluteTimeGetCurrent() - startedAt
        DebugLogger.shared.log(
            .app,
            "BYOK catchup response: duration=\(String(format: "%.2fs", duration)), topicChars=\(parsed.currentTopic.count), questions=\(parsed.questionsForYou.count), discussion=\(parsed.recentDiscussion.count), decisions=\(parsed.keyDecisions.count)"
        )
        return parsed
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

    /// Infer real speaker names from the transcript.
    ///
    /// Input transcript should embed each turn as `[SpeakerID:N] text` so the model sees
    /// the stable internal IDs (mic = 1000, remote = 0, 1, 2, ...). `candidates` is an
    /// optional list of known attendee display names (from calendar) used to bias the
    /// model toward real names when available. Returns a `[speakerIDString: name]` map;
    /// IDs the model cannot confidently resolve are omitted.
    func inferSpeakerNames(
        transcript: String,
        candidates: [String],
        model: OpenAIModel = .gpt5Mini,
        apiKey: String,
        language: String = "en"
    ) async throws -> [String: String] {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InsightsError.emptyTranscript
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        DebugLogger.shared.log(
            .app,
            "BYOK speaker-names request: model=\(model.rawValue), transcriptChars=\(transcript.count), candidates=\(candidates.count), language=\(language)"
        )

        let langName = TranscriptionLanguage(rawValue: language)?.englishName ?? "English"
        let languageInstruction = language != "en"
            ? "The transcript is in \(langName). Names may be in \(langName) or English.\n\n"
            : ""

        let candidateBlock: String = {
            let cleaned = candidates
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !cleaned.isEmpty else { return "" }
            return "Known attendees (bias toward these names when a speaker matches one):\n- \(cleaned.joined(separator: "\n- "))\n\n"
        }()

        let systemPrompt = "You identify real speaker names from meeting transcripts. You only return a name when the transcript contains clear evidence (someone introduced themselves, addressed by name, or self-identified). You never guess. Unknown speakers are omitted."

        let prompt = """
        \(languageInstruction)\(candidateBlock)Infer the real first name (or first + last if clearly stated) for each speaker in the transcript.

        The transcript is tagged with internal speaker IDs like `[SpeakerID:1000] ...` for the device's microphone (the user) and `[SpeakerID:0]`, `[SpeakerID:1]`, etc. for remote speakers.

        Hard rules:
        - Return ONLY one valid JSON object. No markdown, no prose, no code fences.
        - Keys are the numeric speaker IDs as strings (e.g. "1000", "0", "1").
        - Values are the inferred names as strings (e.g. "Sarah", "Tom Chen").
        - OMIT any speaker ID you cannot confidently identify. Do not include placeholders like "Speaker 1", "Unknown", or empty strings.
        - Only return a name when the transcript contains clear evidence: self-introduction ("I'm Sarah"), being addressed ("Thanks Tom"), or explicit attribution.
        - Prefer the "Known attendees" list when a speaker's statements match one of them.
        - Do NOT invent names. It is fine (and expected) to return `{}` if no speakers can be identified.

        Respond in JSON:
        {
            "speakers": {
                "1000": "First name or empty if unknown",
                "0": "First name or empty if unknown"
            }
        }

        Transcript:
        \(transcript)
        """

        let requestBody = OpenAIRequest(
            model: model.rawValue,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: prompt)
            ],
            maxCompletionTokens: 1500,
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
            DebugLogger.shared.log(.app, "BYOK speaker-names response error: status=\(statusCode)")
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw InsightsError.apiError(errorResponse.error.message)
            }
            throw InsightsError.invalidResponse
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let content = openAIResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            DebugLogger.shared.log(.app, "BYOK speaker-names response missing content")
            throw InsightsError.noContent
        }

        let parsed = try JSONDecoder().decode(SpeakerNamesResponse.self, from: jsonData)
        let cleaned = SpeakerNamesResponse.sanitize(parsed.speakers)
        let duration = CFAbsoluteTimeGetCurrent() - startedAt
        DebugLogger.shared.log(
            .app,
            "BYOK speaker-names response: duration=\(String(format: "%.2fs", duration)), identified=\(cleaned.count)/\(parsed.speakers.count)"
        )
        return cleaned
    }
}

// MARK: - Speaker Names Response

struct SpeakerNamesResponse: Decodable {
    let speakers: [String: String]

    enum CodingKeys: String, CodingKey {
        case speakers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Accept both `{ "speakers": { ... } }` and a bare `{ "1000": "...", ... }` top-level object.
        if let nested = try? container.decode([String: String].self, forKey: .speakers) {
            speakers = nested
        } else {
            let flat = try decoder.singleValueContainer().decode([String: String].self)
            speakers = flat
        }
    }

    /// Drop empty/placeholder values and trim whitespace so downstream code can rely on the map.
    static func sanitize(_ raw: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in raw {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            if lower == "unknown" || lower == "null" || lower == "n/a" || lower == "none" { continue }
            // Reject "Speaker 2", "S 3", etc. — these are just restatements of the ID.
            if lower.hasPrefix("speaker ") || lower.hasPrefix("s ") { continue }
            // Trim keys (sometimes the model returns "1000 ").
            let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanKey.isEmpty, Int(cleanKey) != nil else { continue }
            out[cleanKey] = trimmed
        }
        return out
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
    // Questions
    let questions: [SuggestedQuestion]
    
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
        case questions
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
        questions = try container.decodeIfPresent([SuggestedQuestion].self, forKey: .questions) ?? []
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
