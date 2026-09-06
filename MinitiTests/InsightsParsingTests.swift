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
        XCTAssertEqual(OpenAIModel.gpt5Mini.rawValue, "gpt-5-mini-2025-08-07")
        XCTAssertEqual(OpenAIModel.gpt54Mini.rawValue, "gpt-5.4-mini-2026-03-17")
    }

    func testOpenAIModelRoundtrip() throws {
        let encoded = try JSONEncoder().encode(OpenAIModel.gpt5Mini)
        let decoded = try JSONDecoder().decode(OpenAIModel.self, from: encoded)
        XCTAssertEqual(decoded, .gpt5Mini)
    }
}
