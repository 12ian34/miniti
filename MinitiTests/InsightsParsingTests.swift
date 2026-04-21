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
        XCTAssertEqual(InsightsMode.standard.displayName, "standard")
        XCTAssertEqual(InsightsMode.meddpicc.displayName, "MEDDPICC")
        XCTAssertEqual(InsightsMode.training.displayName, "training")
        XCTAssertEqual(InsightsMode.questions.displayName, "questions")
    }

    func testInsightsModeDescriptions() {
        XCTAssertEqual(InsightsMode.standard.description, "General meeting insights")
        XCTAssertEqual(InsightsMode.meddpicc.description, "Sales qualification framework")
        XCTAssertEqual(InsightsMode.training.description, "Speech pattern analysis")
        XCTAssertEqual(InsightsMode.questions.description, "Suggested questions to ask")
    }

    func testInsightsModeRawValues() {
        XCTAssertEqual(InsightsMode.standard.rawValue, "standard")
        XCTAssertEqual(InsightsMode.meddpicc.rawValue, "meddpicc")
        XCTAssertEqual(InsightsMode.training.rawValue, "training")
        XCTAssertEqual(InsightsMode.questions.rawValue, "questions")
    }

    func testInsightsModeAllCases() {
        XCTAssertEqual(InsightsMode.allCases.count, 4)
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
    }

    func testOpenAIModelRoundtrip() throws {
        let encoded = try JSONEncoder().encode(OpenAIModel.gpt5Mini)
        let decoded = try JSONDecoder().decode(OpenAIModel.self, from: encoded)
        XCTAssertEqual(decoded, .gpt5Mini)
    }
}
