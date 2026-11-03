import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class InsightsParsingTests: XCTestCase {

    // MARK: - LiveInsightsResponse decoding

    func testLiveInsightsResponseFull() throws {
        let json = """
        {
            "summary": "Discussed Q4 targets",
            "action_items": ["Review budget", "Set up follow-up"],
            "topics": ["Budget", "Timeline"],
            "discussion_flow": ["Intro", "Budget review", "Next steps"],
            "title": "Q4 Planning",
            "metrics": "Revenue: $10M",
            "economic_buyer": "VP Sales",
            "decision_criteria": "Cost and timeline",
            "decision_process": "Board approval",
            "paper_process": "Legal review",
            "identified_pain": "Slow onboarding",
            "champion": "Director of Ops",
            "competition": "Competitor X"
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(LiveInsightsResponse.self, from: json)
        XCTAssertEqual(resp.summary, "Discussed Q4 targets")
        XCTAssertEqual(resp.actionItems.count, 2)
        XCTAssertEqual(resp.topics, ["Budget", "Timeline"])
        XCTAssertEqual(resp.discussionFlow.count, 3)
        XCTAssertEqual(resp.title, "Q4 Planning")
        XCTAssertEqual(resp.metrics, "Revenue: $10M")
        XCTAssertEqual(resp.champion, "Director of Ops")
        XCTAssertTrue(resp.questions.isEmpty)
    }

    func testLiveInsightsResponseMinimal() throws {
        let json = "{}".data(using: .utf8)!

        let resp = try JSONDecoder().decode(LiveInsightsResponse.self, from: json)
        XCTAssertEqual(resp.summary, "")
        XCTAssertTrue(resp.actionItems.isEmpty)
        XCTAssertTrue(resp.topics.isEmpty)
        XCTAssertTrue(resp.discussionFlow.isEmpty)
        XCTAssertNil(resp.title)
        XCTAssertNil(resp.metrics)
        XCTAssertTrue(resp.questions.isEmpty)
    }

    func testLiveInsightsResponseStandardOnly() throws {
        let json = """
        {
            "summary": "Quick sync about sprint progress",
            "action_items": [],
            "topics": ["Sprint"],
            "discussion_flow": ["Status update"]
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(LiveInsightsResponse.self, from: json)
        XCTAssertEqual(resp.summary, "Quick sync about sprint progress")
        XCTAssertNil(resp.metrics)
        XCTAssertNil(resp.economicBuyer)
    }

    // MARK: - InsightsResponse decoding

    func testInsightsResponseDecode() throws {
        let json = """
        {
            "summary": "Meeting summary",
            "action_items": ["Action 1", "Action 2"],
            "decisions": ["Decision 1"],
            "topics": ["Topic A", "Topic B"]
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(InsightsResponse.self, from: json)
        XCTAssertEqual(resp.summary, "Meeting summary")
        XCTAssertEqual(resp.actionItems.count, 2)
        XCTAssertEqual(resp.decisions, ["Decision 1"])
        XCTAssertEqual(resp.topics.count, 2)
    }

    // MARK: - OpenAI response wrapper

    func testOpenAIResponseDecode() throws {
        let json = """
        {
            "choices": [
                {
                    "message": {
                        "content": "{\\"summary\\": \\"test\\"}"
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(OpenAIResponse.self, from: json)
        XCTAssertEqual(resp.choices.count, 1)
        XCTAssertEqual(resp.choices[0].message.content, "{\"summary\": \"test\"}")
    }

    // MARK: - OpenAI error response

    func testOpenAIErrorResponseDecode() throws {
        let json = """
        {
            "error": {
                "message": "Invalid API key provided"
            }
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(OpenAIErrorResponse.self, from: json)
        XCTAssertEqual(resp.error.message, "Invalid API key provided")
    }

    // MARK: - InsightsMode

    func testLiveInsightsResponseWithQuestions() throws {
        let json = """
        {
            "questions": [
                {
                    "question": "You mentioned the timeline is tight — what specifically would slip if it extends by two weeks?",
                    "type": "deeper",
                    "context": "They mentioned a tight timeline but never quantified the consequences"
                },
                {
                    "question": "You said cost is the main factor, but earlier you emphasized speed — which actually wins when they conflict?",
                    "type": "challenge",
                    "context": "Surfaces a tension between two stated priorities"
                }
            ]
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(LiveInsightsResponse.self, from: json)
        XCTAssertEqual(resp.questions.count, 2)
        XCTAssertEqual(resp.questions[0].type, "deeper")
        XCTAssertEqual(resp.questions[1].type, "challenge")
        XCTAssertFalse(resp.questions[0].question.isEmpty)
        XCTAssertFalse(resp.questions[0].context.isEmpty)
    }

    // MARK: - SuggestedQuestion

    func testSuggestedQuestionDecoding() throws {
        let json = """
        {
            "question": "What happens if the deal doesn't close this quarter?",
            "type": "explore",
            "context": "No one has discussed the downside scenario"
        }
        """.data(using: .utf8)!

        let q = try JSONDecoder().decode(SuggestedQuestion.self, from: json)
        XCTAssertEqual(q.question, "What happens if the deal doesn't close this quarter?")
        XCTAssertEqual(q.type, "explore")
        XCTAssertEqual(q.id, q.question)
    }

    func testSuggestedQuestionEquality() {
        let a = SuggestedQuestion(question: "Why?", type: "deeper", context: "reason")
        let b = SuggestedQuestion(question: "Why?", type: "deeper", context: "reason")
        let c = SuggestedQuestion(question: "How?", type: "clarify", context: "method")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testSuggestedQuestionRoundtrip() throws {
        let original = SuggestedQuestion(question: "Test question?", type: "reframe", context: "Test context")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SuggestedQuestion.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSuggestedQuestionPriorityDecoding() throws {
        let json = """
        {
            "question": "Why is the timeline slipping?",
            "type": "challenge",
            "context": "Conflicts with earlier confidence about the date",
            "priority": "high"
        }
        """.data(using: .utf8)!

        let q = try JSONDecoder().decode(SuggestedQuestion.self, from: json)
        XCTAssertEqual(q.priority, "high")
        XCTAssertTrue(q.isHighPriority)
    }

    func testSuggestedQuestionPriorityDefaultsToNotHigh() throws {
        let json = """
        {
            "question": "Tell me more about the rollout plan.",
            "type": "explore",
            "context": "Glossed over earlier"
        }
        """.data(using: .utf8)!

        let q = try JSONDecoder().decode(SuggestedQuestion.self, from: json)
        XCTAssertNil(q.priority)
        XCTAssertFalse(q.isHighPriority)
    }

    // MARK: - Incremental questions payload

    func testIncrementalRollingStateIncludesQuestionsDictionary() {
        let rollingState = MinitiAPIService.IncrementalInsightsRollingState(
            summary: nil,
            discussionFlow: [],
            actionItems: [],
            topics: [],
            suggestedTitle: "Weekly Deal Review",
            meddpicc: nil,
            questions: [
                .init(
                    question: "You said procurement is still vague — who actually owns that step internally?",
                    type: "clarify",
                    context: "Ownership of procurement is still unresolved.",
                    priority: "high"
                )
            ]
        )

        let dictionary = rollingState.dictionary
        let questions = dictionary["questions"] as? [[String: Any]]

        XCTAssertEqual(questions?.count, 1)
        XCTAssertEqual(questions?.first?["question"] as? String, "You said procurement is still vague — who actually owns that step internally?")
        XCTAssertEqual(questions?.first?["type"] as? String, "clarify")
        XCTAssertEqual(questions?.first?["context"] as? String, "Ownership of procurement is still unresolved.")
        XCTAssertEqual(questions?.first?["priority"] as? String, "high")
    }

    func testIncrementalRollingStateOmitsEmptyQuestionsArray() {
        let rollingState = MinitiAPIService.IncrementalInsightsRollingState(
            summary: nil,
            discussionFlow: [],
            actionItems: [],
            topics: [],
            suggestedTitle: nil,
            meddpicc: nil,
            questions: []
        )

        XCTAssertNil(rollingState.dictionary["questions"])
    }

    func testInsightsModeDisplayNames() {
        XCTAssertEqual(InsightsMode.standard.displayName, "Summary")
        XCTAssertEqual(InsightsMode.meddpicc.displayName, "Sales")
        XCTAssertEqual(InsightsMode.training.displayName, "Coaching")
        XCTAssertEqual(InsightsMode.questions.displayName, "Questions")
        XCTAssertEqual(InsightsMode.docs.displayName, "Playbook")
        XCTAssertEqual(InsightsMode.template.displayName, "Template")
    }

    func testInsightsModeDescriptions() {
        XCTAssertEqual(InsightsMode.standard.description, "Notes, decisions, and action items")
        XCTAssertEqual(InsightsMode.meddpicc.description, "MEDDPICC qualification")
        XCTAssertEqual(InsightsMode.training.description, "Talk ratio, pace, and speech patterns")
        XCTAssertEqual(InsightsMode.questions.description, "Suggested questions to ask")
        XCTAssertEqual(InsightsMode.docs.description, "Answers from connected docs")
        XCTAssertEqual(InsightsMode.template.description, "Structured notes from a template")
    }

    func testInsightsModeProgressiveDisclosureGroups() {
        XCTAssertEqual(InsightsMode.coreModes, [.standard, .questions, .training])
        XCTAssertEqual(InsightsMode.specialistModes, [.meddpicc, .template, .docs])
        XCTAssertFalse(InsightsMode.standard.isSpecialist)
        XCTAssertTrue(InsightsMode.meddpicc.isSpecialist)
        XCTAssertTrue(InsightsMode.docs.isSpecialist)
        XCTAssertTrue(InsightsMode.template.isSpecialist)
    }

    func testInsightsModeRawValues() {
        XCTAssertEqual(InsightsMode.standard.rawValue, "standard")
        XCTAssertEqual(InsightsMode.meddpicc.rawValue, "meddpicc")
        XCTAssertEqual(InsightsMode.training.rawValue, "training")
        XCTAssertEqual(InsightsMode.questions.rawValue, "questions")
        XCTAssertEqual(InsightsMode.docs.rawValue, "docs")
        XCTAssertEqual(InsightsMode.template.rawValue, "template")
    }

    func testInsightsModeAllCases() {
        XCTAssertEqual(InsightsMode.allCases.count, 6)
    }

    // MARK: - Insight templates

    func testBuiltInTemplatesRespectBackendLimits() {
        XCTAssertFalse(InsightTemplate.builtIn.isEmpty)
        XCTAssertNotNil(InsightTemplate.builtIn(id: InsightTemplate.defaultID))
        XCTAssertEqual(Set(InsightTemplate.builtIn.map(\.id)).count, InsightTemplate.builtIn.count, "template ids must be unique")
        let keyPattern = try! NSRegularExpression(pattern: "^[a-z][a-z0-9_]{0,31}$")
        for template in InsightTemplate.builtIn {
            XCTAssertLessThanOrEqual(template.sections.count, InsightTemplate.maxSections, template.id)
            XCTAssertFalse(template.sections.isEmpty, template.id)
            XCTAssertLessThanOrEqual(template.name.count, InsightTemplate.maxNameLength, template.id)
            XCTAssertEqual(Set(template.sections.map(\.key)).count, template.sections.count, "\(template.id) keys must be unique")
            for section in template.sections {
                let range = NSRange(section.key.startIndex..., in: section.key)
                XCTAssertNotNil(keyPattern.firstMatch(in: section.key, range: range), "\(template.id).\(section.key) key shape")
                XCTAssertLessThanOrEqual(section.title.count, InsightTemplate.maxTitleLength, "\(template.id).\(section.key) title")
                XCTAssertLessThanOrEqual(section.guidance.count, InsightTemplate.maxGuidanceLength, "\(template.id).\(section.key) guidance")
            }
        }
    }

    func testTemplateSectionsNormalizeDropsUnknownKeysAndPlaceholders() throws {
        let template = try XCTUnwrap(InsightTemplate.builtIn(id: "bant"))
        let raw: [String: String?] = [
            "budget": "- $40k approved\n• CFO sign-off above $20k",
            "authority": "null",
            "need": "   ",
            "timeline": nil,
            "unknown_key": "should be dropped",
        ]
        let normalized = InsightTemplateSections.normalize(raw, for: template)
        XCTAssertEqual(normalized, ["budget": "$40k approved\nCFO sign-off above $20k"])
        XCTAssertEqual(template.orderedSections(from: normalized).map(\.section.key), ["budget"])
    }

    func testTemplateSectionsRoundTripAndMarkdown() throws {
        let template = try XCTUnwrap(InsightTemplate.builtIn(id: "standup"))
        let sections = ["done": "Shipped the importer", "blockers": "Waiting on design review"]
        let encoded = try XCTUnwrap(InsightTemplateSections.encode(sections))
        XCTAssertEqual(InsightTemplateSections.decode(encoded), sections)
        XCTAssertNil(InsightTemplateSections.encode([:]))
        XCTAssertEqual(InsightTemplateSections.decode(nil), [:])

        let md = InsightTemplateSections.markdown(template: template, sections: sections)
        XCTAssertTrue(md.hasPrefix("### Stand-up"))
        XCTAssertTrue(md.contains("**Done:** Shipped the importer"))
        XCTAssertTrue(md.contains("**Blockers:** Waiting on design review"))
        // Template order, not dictionary order.
        XCTAssertLessThan(try XCTUnwrap(md.range(of: "**Done:**")).lowerBound, try XCTUnwrap(md.range(of: "**Blockers:**")).lowerBound)
        XCTAssertEqual(InsightTemplateSections.markdown(template: template, sections: [:]), "")
    }

    func testTemplatePromptListsEverySectionAndBaseline() throws {
        let template = try XCTUnwrap(InsightTemplate.builtIn(id: "interview"))
        let prompt = InsightTemplatePrompt.userPrompt(
            template: template,
            previousSections: ["strengths": "Clear communicator"],
            languageInstruction: "",
            transcript: "[You] Tell me about a project you led."
        )
        for section in template.sections {
            XCTAssertTrue(prompt.contains("- \(section.key) — \(section.title)"), section.key)
            XCTAssertTrue(prompt.contains("\"\(section.key)\": \"Point one"), section.key)
        }
        XCTAssertTrue(prompt.contains("Previous sections"))
        XCTAssertTrue(prompt.contains("Clear communicator"))
        XCTAssertTrue(prompt.contains("Interview scorecard"))
        XCTAssertTrue(prompt.contains("Latest transcript:"))

        let fresh = InsightTemplatePrompt.userPrompt(template: template, previousSections: nil, languageInstruction: "", transcript: "x")
        XCTAssertTrue(fresh.contains("This is the start of the meeting"))
        XCTAssertFalse(fresh.contains("Previous sections"))
    }

    func testLiveInsightsResponseDecodesTemplateSections() throws {
        let json = """
        {"sections": {"budget": "Point one\\nPoint two", "authority": null, "extra": "ignored"}}
        """
        let response = try JSONDecoder().decode(LiveInsightsResponse.self, from: Data(json.utf8))
        let sections = try XCTUnwrap(response.templateSections)
        XCTAssertEqual(sections["budget"] ?? nil, "Point one\nPoint two")
        XCTAssertEqual(sections.keys.contains("authority"), true)
        XCTAssertNil(sections["authority"] ?? nil)
        XCTAssertEqual(response.summary, "")
        XCTAssertTrue(response.questions.isEmpty)
    }

    func testManagedInsightsResponseMapsTemplateSections() throws {
        let template = try XCTUnwrap(InsightTemplate.builtIn(id: "bant"))
        let json = """
        {"summary": "", "action_items": [], "topics": [], "discussion_flow": [], "questions": [],
         "template_id": "bant", "template_sections": {"need": "- Notes arrive a day late", "timeline": null},
         "meta": {"degraded": false, "fallback_reason": null, "request_seq": 3}}
        """
        let decoded = try JSONDecoder().decode(ManagedInsightsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.templateID, "bant")
        let live = decoded.toLiveInsights(template: template)
        XCTAssertEqual(live.templateID, "bant")
        XCTAssertEqual(live.templateSections, ["need": "Notes arrive a day late"])
        XCTAssertEqual(decoded.meta?.requestSeq, 3)
        // Without a template the sections are not surfaced (nothing to order them by).
        XCTAssertTrue(decoded.toLiveInsights().templateSections.isEmpty)
    }

    func testDocsPlaybookCardDecoding() throws {
        let json = """
        {
          "docs": [
            {
              "topic": "SSO with Okta",
              "answer": "Use Okta SAML.",
              "citations": [
                { "title": "SSO setup", "url": "https://docs.lightdash.com/sso", "snippet": "Okta" }
              ],
              "priority": "high"
            }
          ]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DocsPlaybookResponse.self, from: json)
        XCTAssertEqual(decoded.docs.count, 1)
        XCTAssertEqual(decoded.docs[0].topic, "SSO with Okta")
        XCTAssertTrue(decoded.docs[0].isHighPriority)
        XCTAssertEqual(decoded.docs[0].citations.first?.url, "https://docs.lightdash.com/sso")
    }

    func testDocsTopicsResponseCleaning() throws {
        let json = """
        { "topics": ["  SSO / SAML  ", "sso / saml", "Data retention", "", "x", "Rate limits", "Webhooks", "Audit logs", "Extra topic"] }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DocsTopicsResponse.self, from: json)
        // Dedups by slug ("SSO / SAML" == "sso / saml"), drops empty/too-short, caps at 6.
        XCTAssertEqual(decoded.cleanedTopics.count, 6)
        XCTAssertEqual(decoded.cleanedTopics.first, "SSO / SAML")
        XCTAssertFalse(decoded.cleanedTopics.contains("x"))
    }

    func testDocTopicSlugIdentityAndCodable() throws {
        XCTAssertEqual(DocTopic.slug("  SSO / SAML  "), DocTopic.slug("sso / saml"))
        let card = DocPlaybookCard(topic: "SSO", answer: "Use SAML.", citations: [])
        let topic = DocTopic(label: "SSO Support", lookupState: .answered, card: card)
        let data = try JSONEncoder().encode(topic)
        let decoded = try JSONDecoder().decode(DocTopic.self, from: data)
        XCTAssertEqual(decoded.id, topic.id)
        XCTAssertEqual(decoded.label, "SSO Support")
        XCTAssertEqual(decoded.lookupState, .answered)
        XCTAssertEqual(decoded.card?.answer, "Use SAML.")
    }

    @MainActor
    func testMergeDocTopicsPreservesStateAndDedups() {
        let answered = DocTopic(
            label: "SSO",
            lookupState: .answered,
            card: DocPlaybookCard(topic: "SSO", answer: "SAML.", citations: [])
        )
        let merged = AppState.mergeDocTopics(
            existing: [answered],
            newLabels: ["sso", "Data retention", "Rate limits"]
        )
        // "sso" collides with existing "SSO" and must not duplicate or reset it.
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[0].lookupState, .answered)
        XCTAssertEqual(merged[0].card?.answer, "SAML.")
        XCTAssertEqual(merged[1].label, "Data retention")
        XCTAssertEqual(merged[1].lookupState, .pending)
    }

    func testDocsMCPURLValidation() {
        XCTAssertNoThrow(try DocsMCPService.validateMCPURL("https://docs.lightdash.com/mcp"))
        XCTAssertThrowsError(try DocsMCPService.validateMCPURL("http://docs.lightdash.com/mcp"))
        XCTAssertThrowsError(try DocsMCPService.validateMCPURL("https://localhost/mcp"))
        XCTAssertThrowsError(try DocsMCPService.validateMCPURL("https://127.0.0.1/mcp"))
    }

    func testDocsMCPURLAllowsHostnamesStartingWithFCorFD() {
        // Hostnames like "fd7.example.com" are not IPv6 unique-local addresses.
        XCTAssertNoThrow(try DocsMCPService.validateMCPURL("https://fd7.example.com/mcp"))
        XCTAssertNoThrow(try DocsMCPService.validateMCPURL("https://fcdocs.acme.com/mcp"))
        XCTAssertFalse(DocsMCPService.isBlockedIPv6("fd7.example.com"))
        XCTAssertFalse(DocsMCPService.isBlockedIPv6("fcdocs.acme.com"))
        // Genuine IPv6 unique-local / link-local literals stay blocked.
        XCTAssertTrue(DocsMCPService.isBlockedIPv6("fd00::1"))
        XCTAssertTrue(DocsMCPService.isBlockedIPv6("fe80::1"))
        XCTAssertTrue(DocsMCPService.isBlockedIPv6("::1"))
    }

    func testDiscoverSearchToolPrefersSearch() {
        let searchSchema: [String: Any] = [
            "type": "object",
            "properties": ["query": ["type": "string"] as [String: Any]],
            "required": ["query"],
        ]
        let feedbackSchema: [String: Any] = [
            "type": "object",
            "properties": ["feedback": ["type": "string"] as [String: Any]],
            "required": ["feedback"],
        ]
        let tools: [DocsMCPService.Tool] = [
            DocsMCPService.Tool(name: "search_lightdash", inputSchema: searchSchema),
            DocsMCPService.Tool(name: "submit_feedback", inputSchema: feedbackSchema),
        ]
        let found = DocsMCPService.discoverSearchTool(tools)
        XCTAssertEqual(found?.name, "search_lightdash")
        XCTAssertEqual(found?.queryArgument, "query")
    }

    func testInvestigationResultDecodesSourcesAndReferencedFiles() throws {
        let json = Data("""
        {
          "answer": "The API supports this approach.",
          "sources": [
            { "title": "OpenAI web search", "url": "https://developers.openai.com/api/docs/guides/tools-web-search" }
          ],
          "referenced_files": ["Sources/Billing.swift", "  "]
        }
        """.utf8)

        let result = try JSONDecoder().decode(InvestigationResult.self, from: json)
        XCTAssertEqual(result.answer, "The API supports this approach.")
        XCTAssertEqual(result.sources.first?.title, "OpenAI web search")
        XCTAssertEqual(result.referencedFiles, ["Sources/Billing.swift"])
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - InsightsError

    func testInsightsErrorDescriptions() {
        XCTAssertNotNil(InsightsError.emptyTranscript.errorDescription)
        XCTAssertNotNil(InsightsError.invalidResponse.errorDescription)
        XCTAssertNotNil(InsightsError.httpError(500).errorDescription)
        XCTAssertTrue(InsightsError.apiError("test").errorDescription!.contains("test"))
    }

    func testInsightsErrorEmptyTranscript() {
        XCTAssertEqual(InsightsError.emptyTranscript.errorDescription, "No transcript to analyze.")
    }

    func testInsightsErrorInvalidResponse() {
        XCTAssertEqual(InsightsError.invalidResponse.errorDescription, "Invalid response from OpenAI.")
    }

    func testInsightsErrorHttpError() {
        XCTAssertEqual(InsightsError.httpError(429).errorDescription, "HTTP error: 429")
    }

    func testInsightsErrorApiError() {
        XCTAssertEqual(InsightsError.apiError("rate limit").errorDescription, "API error: rate limit")
    }

    func testInsightsErrorNoContent() {
        XCTAssertEqual(InsightsError.noContent.errorDescription, "No content in response.")
    }

    func testInsightsErrorInvalidJson() {
        XCTAssertEqual(InsightsError.invalidJson.errorDescription, "Failed to parse insights JSON.")
    }

    // MARK: - OpenAIModel enum

    func testOpenAIModelRawValue() {
        XCTAssertEqual(OpenAIModel.gpt6Luna.rawValue, "gpt-6-luna")
        XCTAssertEqual(OpenAIModel.gpt54Mini.rawValue, "gpt-5.4-mini-2026-03-17")
    }

    func testOpenAIModelRoundtrip() throws {
        let encoded = try JSONEncoder().encode(OpenAIModel.gpt6Luna)
        let decoded = try JSONDecoder().decode(OpenAIModel.self, from: encoded)
        XCTAssertEqual(decoded, .gpt6Luna)
    }
}

// Verify actual direct-client request bytes, not just the model enum.
extension InsightsParsingTests {
    @MainActor
    private func checkBYOKRequest(
        model: String, reasoning: String, response: String = "{}", responsesAPI: Bool = false,
        run: (InsightsService) async throws -> Void
    ) async throws {
        let context = StubURLProtocol.Context()
        context.script = { request in
            XCTAssertEqual(request.url?.path, responsesAPI ? "/v1/responses" : "/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
            let body = try! JSONSerialization.jsonObject(with: TestSupport.bodyData(of: request)) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, model)
            if responsesAPI {
                XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], reasoning)
                return StubURLProtocol.json(200, #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Grounded answer","annotations":[]}]}]}"#)
            }
            XCTAssertEqual(body["reasoning_effort"] as? String, reasoning)
            XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
            let data = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": response]]]])
            return StubURLProtocol.json(200, String(decoding: data, as: UTF8.self))
        }
        let session = TestSupport.stubbedSession(context: context)
        defer { session.invalidateAndCancel() }
        try await run(InsightsService(session: session))
        XCTAssertEqual(context.requests.count, 1, "one selected model, no cross-model retry")
    }

    @MainActor
    func testBYOKFullAndIncrementalWorkloadsUseSupportedModelAndExplicitReasoning() async throws {
        let text = "[Sasha] We agreed the budget and will send the proposal on Friday."
        let payload = MinitiAPIService.IncrementalInsightsPayload(
            strategy: "delta_recent_window_v1", fullSegmentCount: 2, ackedSegmentCount: 1,
            deltaSegmentCount: 1, recentSegmentCount: 2, transcriptDelta: text, recentTranscript: text,
            rollingState: .init(summary: "Earlier budget", discussionFlow: [], actionItems: [], topics: [], suggestedTitle: nil, meddpicc: nil, questions: nil))
        for mode in [InsightsMode.standard, .meddpicc, .questions, .template] {
            for incremental in [false, true] {
                let luna = mode == .standard
                try await checkBYOKRequest(model: luna ? "gpt-6-luna" : "gpt-5.4-mini-2026-03-17", reasoning: luna ? "none" : "low") { service in
                    _ = try await service.generateLiveInsights(
                        transcript: text, existingSummary: nil, existingTitle: nil, mode: mode,
                        apiKey: "synthetic-key", incrementalPayload: incremental ? payload : nil,
                        template: mode == .template ? InsightTemplate.builtIn[0] : nil)
                }
            }
        }
    }

    @MainActor
    func testBYOKHelpersFinalSummaryAndGroundedTasksUseTheirSelectedModels() async throws {
        let text = "[SpeakerID:0] I am Sasha. We agreed the budget and will send the proposal on Friday."
        try await checkBYOKRequest(model: "gpt-6-luna", reasoning: "none", response: #"{"summary":"Agreed budget","action_items":[],"decisions":[],"topics":[]}"#) {
            let result = try await $0.generateInsights(transcript: text, apiKey: "synthetic-key")
            XCTAssertEqual(result.summary, "Agreed budget")
        }
        try await checkBYOKRequest(model: "gpt-6-luna", reasoning: "none", response: #"{"speakers":{"0":"Sasha"}}"#) {
            let names = try await $0.inferSpeakerNames(transcript: text, candidates: [], apiKey: "synthetic-key")
            XCTAssertEqual(names, ["0": "Sasha"])
        }
        try await checkBYOKRequest(model: "gpt-6-luna", reasoning: "none", response: #"{"topics":["Budget"]}"#) {
            let topics = try await $0.extractDocsTopics(transcript: text, apiKey: "synthetic-key")
            XCTAssertEqual(topics, ["Budget"])
        }
        try await checkBYOKRequest(model: "gpt-6-luna", reasoning: "none", response: #"{"current_topic":"Budget","questions_for_you":[],"recent_discussion":[],"key_decisions":[]}"#) {
            _ = try await $0.generateCatchUp(recentTranscript: text, fullTranscript: nil, apiKey: "synthetic-key")
        }
        try await checkBYOKRequest(model: "gpt-6-luna", reasoning: "none", response: #"{"name":"Budget","summary":"Spending","sections":[{"title":"budget","guidance":"Agreed spending"}]}"#) {
            _ = try await $0.draftInsightTemplate(description: "Budget review", apiKey: "synthetic-key")
        }
        try await checkBYOKRequest(model: "gpt-5.4-mini-2026-03-17", reasoning: "low") {
            _ = try await $0.generateDocsCard(topic: "Budget", chunks: [.init(title: "Budget", url: "https://docs.example.test/budget", text: "Monthly limits")], transcript: text, apiKey: "synthetic-key")
        }
        try await checkBYOKRequest(model: "gpt-5.4-mini-2026-03-17", reasoning: "low", responsesAPI: true) {
            _ = try await $0.generateInvestigation(focus: "Budget", meetingContext: text, scope: .web, codebaseContext: nil, referencedFiles: [], apiKey: "synthetic-key")
        }
    }

    @MainActor
    func testBYOKModelAccessFailureKeepsProviderExplanationAndDoesNotSwitchModels() async throws {
        let context = StubURLProtocol.Context()
        context.script = { _ in StubURLProtocol.json(404, #"{"error":{"code":"model_not_found","message":"Your project does not have access to gpt-6-luna."}}"#) }
        let session = TestSupport.stubbedSession(context: context)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await InsightsService(session: session).generateInsights(transcript: "Synthetic budget discussion", apiKey: "synthetic-key")
            XCTFail("access refusal must not be treated as a summary")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Your OpenAI key needs access to gpt-6-luna"))
        }
        XCTAssertEqual(context.requests.count, 1)
    }
}

extension InsightsParsingTests {
    @MainActor
    func testLunaAccessMappingIsSpecificAndNeverRetries() async throws {
        for (status, code, message, model, mapped) in [
            (404, "model_not_found", "Missing model", OpenAIModel.gpt6Luna, true),
            (400, "invalid_request_error", "No access to gpt-6-luna", .gpt6Luna, true),
            (403, "permission_denied", "Project cannot use gpt-6-luna", .gpt6Luna, true),
            (403, "permission_denied", "Project suspended", .gpt6Luna, false),
            (429, "rate_limit", "Slow down for gpt-6-luna", .gpt6Luna, false),
            (404, "other", "Unknown endpoint", .gpt6Luna, false),
            (404, "model_not_found", "Missing model", .gpt54Mini, false)
        ] {
            let context = StubURLProtocol.Context()
            context.script = { _ in StubURLProtocol.json(status, "{\"error\":{\"code\":\"\(code)\",\"message\":\"\(message)\"}}") }
            let session = TestSupport.stubbedSession(context: context)
            defer { session.invalidateAndCancel() }
            do {
                _ = try await InsightsService(session: session).generateInsights(transcript: "budget discussion", model: model, apiKey: "synthetic")
                XCTFail("Expected refusal")
            } catch {
                XCTAssertEqual(AIRequestDiagnostics.category(error, status: status) == "model_access", mapped)
                if mapped { XCTAssertTrue(error.localizedDescription.contains("Your OpenAI key needs access to gpt-6-luna")) }
            }
            XCTAssertEqual(context.requests.count, 1)
        }
    }

    @MainActor
    func testBYOKAccessErrorIsVisibleWithoutAutomaticDiagnostics() {
        let state = AppState()
        state.appModeRaw = AppMode.byok.rawValue
        state.shareDiagnostics = true
        state.diagnosticEventObserver = { _, _ in XCTFail("BYOK must not report automatically") }
        state.reportAIRequestFailure(InsightsError.lunaAccessRequired, mode: "standard", stage: "final")
        XCTAssertTrue(state.showBYOKModelAccessError)
        XCTAssertEqual(DiagnosticTimeline.sanitize(["failure_category": "model_access"]), ["failure_category": "model_access"])
    }
}

extension InsightsParsingTests {
    @MainActor
    func testFullQuestionsPromptMatchesManagedFixtureVerbatim() async throws {
        struct Fixture: Decodable {
            struct Question: Decodable { let transcript: String; let existing_summary: String?; let system: String; let user: String }
            let questions: [Question]
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(ContractFixtures.review370.utf8))
        for row in fixture.questions {
            let context = StubURLProtocol.Context()
            context.script = { request in
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: TestSupport.bodyData(of: request)) as? [String: Any])
                let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
                XCTAssertEqual(messages.first?["content"], row.system)
                XCTAssertEqual(messages.last?["content"], row.user)
                return StubURLProtocol.json(200, #"{"choices":[{"message":{"content":"{\"questions\":[]}"}}]}"#)
            }
            let session = TestSupport.stubbedSession(context: context)
            defer { session.invalidateAndCancel() }
            _ = try await InsightsService(session: session).generateLiveInsights(transcript: row.transcript, existingSummary: row.existing_summary,
                existingTitle: nil, mode: .questions, apiKey: "synthetic")
            XCTAssertEqual(context.requests.count, 1)
        }
    }
}
