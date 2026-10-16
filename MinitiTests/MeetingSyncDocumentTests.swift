import Foundation
import SwiftData
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// The wire form of a meeting (3.0.0): every field survives a round trip, ids are lowercase,
/// unknown fields from another client are echoed, and the fingerprint moves only when
/// something that syncs moves.
@MainActor
final class MeetingSyncDocumentTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TestSupport.makeInMemoryContainer()
        context = ModelContext(container)
    }

    private func sampleMeeting() -> Meeting {
        let meeting = Meeting(
            id: UUID(uuidString: "0F1E2D3C-4B5A-4C6D-8E7F-9A0B1C2D3E4F")!,
            title: "Budget review",
            startTime: Date(timeIntervalSince1970: 1_790_000_000),
            endTime: Date(timeIntervalSince1970: 1_790_001_800),
            segments: [
                TranscriptSegment(id: UUID(uuidString: "2B3C4D5E-6F7A-4B8C-9D0E-1F2A3B4C5D6E")!, text: "Hello everyone", speaker: 0, timestamp: 0.5, isFinal: true, confidence: 0.98, sourceRaw: "system"),
                TranscriptSegment(text: "Hi", speaker: DeepgramService.micSpeakerID, timestamp: 2.0, isFinal: true, confidence: 1.0, sourceRaw: "microphone"),
            ],
            summaryText: "We agreed the budget.",
            actionItems: ["Send the deck"],
            keyDecisions: ["Ship in March"],
            topics: ["budget"],
            discussionFlow: ["intro", "numbers"],
            notes: "Prep notes",
            isPinned: true,
            meddpiccMetrics: "20% faster"
        )
        meeting.language = "fr"
        meeting.calendarEventTitle = "Budget sync"
        meeting.calendarEventId = "evt_1"
        meeting.speakerNames = ["0": "Sasha"]
        meeting.speakerOverrides = ["0"]
        meeting.selfSpeakerIDs = [DeepgramService.micSpeakerID]
        meeting.attendees = [MeetingAttendee(email: "sasha@example.com", displayName: "Sasha Petrov", domain: "example.com", responseStatus: "accepted", isOrganizer: true, isSelf: false)]
        meeting.suggestedQuestions = [SuggestedQuestion(question: "Why March?", type: "challenge", context: "timing")]
        meeting.externalSource = "granola"
        meeting.externalID = "csv-1"
        meeting.importedAt = Date(timeIntervalSince1970: 1_790_002_000)
        meeting.transcriptRevision = 2
        meeting.updatedAt = Date(timeIntervalSince1970: 1_790_003_000)
        context.insert(meeting)
        return meeting
    }

    func testEncodeProducesLowercaseIdsAndEveryField() throws {
        let meeting = sampleMeeting()
        let doc = MeetingSyncDocument.encode(meeting, segments: meeting.segments)
        XCTAssertEqual(doc["schema_version"] as? Int, 1)
        XCTAssertEqual(doc["id"] as? String, "0f1e2d3c-4b5a-4c6d-8e7f-9a0b1c2d3e4f")
        XCTAssertEqual(doc["title"] as? String, "Budget review")
        XCTAssertEqual(doc["language"] as? String, "fr")
        XCTAssertEqual(doc["pinned"] as? Bool, true)
        XCTAssertEqual(doc["transcript_revision"] as? Int, 2)
        XCTAssertEqual(doc["updated_at"] as? String, "2026-09-21T15:03:20.000Z")
        let segments = try XCTUnwrap(doc["segments"] as? [[String: Any]])
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0]["id"] as? String, "2b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e")
        XCTAssertEqual(segments[0]["speaker"] as? Int, 0)
        XCTAssertEqual(segments[1]["speaker"] as? Int, DeepgramService.micSpeakerID)
        XCTAssertEqual(segments[1]["source"] as? String, "microphone")
        XCTAssertEqual(doc["speaker_names"] as? [String: String], ["0": "Sasha"])
        XCTAssertEqual(doc["self_speaker_ids"] as? [Int], [DeepgramService.micSpeakerID])
        let meddpicc = try XCTUnwrap(doc["meddpicc"] as? [String: Any])
        XCTAssertEqual(meddpicc["metrics"] as? String, "20% faster")
        XCTAssertTrue(meddpicc["champion"] is NSNull)
        let attendees = try XCTUnwrap(doc["attendees"] as? [[String: Any]])
        XCTAssertEqual(attendees.first?["name"] as? String, "Sasha Petrov")
        XCTAssertEqual(attendees.first?["is_organizer"] as? Bool, true)
        let questions = try XCTUnwrap(doc["questions"] as? [[String: Any]])
        XCTAssertEqual(questions.first?["question"] as? String, "Why March?")
        XCTAssertEqual(doc["external_id"] as? String, "csv-1")
        XCTAssertNoThrow(try MeetingSyncDocument.encodeData(meeting, segments: meeting.segments))
    }

    func testRoundTripThroughApplyKeepsEveryField() throws {
        let original = sampleMeeting()
        let doc = MeetingSyncDocument.encode(original, segments: original.segments)
        let decoded = try XCTUnwrap(MeetingSyncDocument.decode(doc))
        let copy = MeetingSyncDocument.makeMeeting(decoded, in: context)
        XCTAssertEqual(copy.id, original.id)
        XCTAssertEqual(copy.title, original.title)
        XCTAssertEqual(copy.calendarEventTitle, "Budget sync")
        XCTAssertEqual(copy.startTime, original.startTime)
        XCTAssertEqual(copy.endTime, original.endTime)
        XCTAssertEqual(copy.updatedAt, original.updatedAt)
        XCTAssertEqual(copy.language, "fr")
        XCTAssertTrue(copy.isPinned)
        XCTAssertEqual(copy.transcriptRevision, 2)
        XCTAssertEqual(copy.segments.count, 2)
        XCTAssertEqual(Set(copy.segments.map(\.id)), Set(original.segments.map(\.id)))
        XCTAssertEqual(copy.segments.sorted { $0.timestamp < $1.timestamp }.map(\.text), ["Hello everyone", "Hi"])
        XCTAssertEqual(copy.speakerNames, ["0": "Sasha"])
        XCTAssertEqual(copy.speakerOverrides, ["0"])
        XCTAssertEqual(copy.selfSpeakerIDs, [DeepgramService.micSpeakerID])
        XCTAssertEqual(copy.summaryText, "We agreed the budget.")
        XCTAssertEqual(copy.actionItems, ["Send the deck"])
        XCTAssertEqual(copy.keyDecisions, ["Ship in March"])
        XCTAssertEqual(copy.topics, ["budget"])
        XCTAssertEqual(copy.discussionFlow, ["intro", "numbers"])
        XCTAssertEqual(copy.notes, "Prep notes")
        XCTAssertEqual(copy.meddpiccMetrics, "20% faster")
        XCTAssertNil(copy.meddpiccChampion)
        XCTAssertEqual(copy.suggestedQuestions.first?.question, "Why March?")
        XCTAssertEqual(copy.attendees.first?.displayName, "Sasha Petrov")
        XCTAssertEqual(copy.attendees.first?.responseStatus, "accepted")
        XCTAssertEqual(copy.externalSource, "granola")
        XCTAssertEqual(copy.externalID, "csv-1")
        XCTAssertEqual(copy.importedAt, original.importedAt)
        XCTAssertEqual(copy.calendarEventId, "evt_1")
        XCTAssertNil(copy.syncExtraJSON)
        XCTAssertEqual(MeetingSyncDocument.fingerprint(of: copy), MeetingSyncDocument.fingerprint(of: original))
    }

    func testUnknownFieldsFromAnotherClientAreEchoedAndUppercaseIdsParse() throws {
        let meeting = sampleMeeting()
        var doc = MeetingSyncDocument.encode(meeting, segments: meeting.segments)
        doc["id"] = (doc["id"] as! String).uppercased()
        doc["investigations"] = [["topic": "pricing"]]
        doc["join_url"] = "https://meet.example"
        doc["created_at"] = "2026-09-21T03:00:00.000Z"
        let decoded = try XCTUnwrap(MeetingSyncDocument.decode(doc))
        XCTAssertEqual(decoded.id, meeting.id)
        MeetingSyncDocument.apply(decoded, to: meeting, in: context, replaceSegments: false)
        let extra = try XCTUnwrap(meeting.syncExtraJSON)
        XCTAssertTrue(extra.contains("pricing"))
        XCTAssertTrue(extra.contains("join_url"))
        let again = MeetingSyncDocument.encode(meeting, segments: meeting.segments)
        XCTAssertEqual((again["investigations"] as? [[String: String]])?.first?["topic"], "pricing")
        XCTAssertEqual(again["join_url"] as? String, "https://meet.example")
        XCTAssertEqual(again["created_at"] as? String, "2026-09-21T03:00:00.000Z")
        XCTAssertEqual(again["id"] as? String, "0f1e2d3c-4b5a-4c6d-8e7f-9a0b1c2d3e4f")
    }

    func testDecodeRejectsDocumentsTheEngineCannotApply() {
        XCTAssertNil(MeetingSyncDocument.decode(["id": "nope", "updated_at": "2026-01-01T00:00:00Z", "start_time": "2026-01-01T00:00:00Z", "segments": []]))
        XCTAssertNil(MeetingSyncDocument.decode(["id": UUID().uuidString, "start_time": "2026-01-01T00:00:00Z", "segments": []]))
        XCTAssertNil(MeetingSyncDocument.decode(["id": UUID().uuidString, "updated_at": "2026-01-01T00:00:00Z", "start_time": "2026-01-01T00:00:00Z"]))
        XCTAssertNil(MeetingSyncDocument.decode(["id": UUID().uuidString, "updated_at": "2026-01-01T00:00:00Z", "start_time": "2026-01-01T00:00:00Z", "segments": []]), "no end time: a live meeting elsewhere, never applied")
        XCTAssertNotNil(MeetingSyncDocument.decode(["id": UUID().uuidString, "updated_at": "2026-01-01T00:00:00Z", "start_time": "2026-01-01T00:00:00Z", "end_time": "2026-01-01T00:30:00Z", "segments": []]))
    }

    func testApplyWithoutReplacingSegmentsKeepsRowsAndUpdatesScalars() throws {
        let meeting = sampleMeeting()
        let before = Set(meeting.segments.map(\.id))
        var doc = MeetingSyncDocument.encode(meeting, segments: meeting.segments)
        doc["title"] = "Renamed"
        doc["pinned"] = false
        doc["segments"] = []
        let decoded = try XCTUnwrap(MeetingSyncDocument.decode(doc))
        MeetingSyncDocument.apply(decoded, to: meeting, in: context, replaceSegments: false)
        XCTAssertEqual(meeting.title, "Renamed")
        XCTAssertFalse(meeting.isPinned)
        XCTAssertEqual(Set(meeting.segments.map(\.id)), before)
        MeetingSyncDocument.apply(decoded, to: meeting, in: context, replaceSegments: true)
        XCTAssertEqual(meeting.segments.count, 0)
    }

    func testFingerprintMovesOnlyWithSyncedFields() {
        let meeting = sampleMeeting()
        let base = MeetingSyncDocument.fingerprint(of: meeting)
        XCTAssertEqual(base, MeetingSyncDocument.fingerprint(of: meeting))
        meeting.lastExportedMarkdownFilename = "x.md"
        meeting.syncedAt = Date()
        meeting.cloudRevision = 4
        XCTAssertEqual(MeetingSyncDocument.fingerprint(of: meeting), base, "bookkeeping and export names never move the fingerprint")
        meeting.isPinned = false
        let pinned = MeetingSyncDocument.fingerprint(of: meeting)
        XCTAssertNotEqual(pinned, base)
        meeting.setSpeakerName(id: "0", name: "Alex")
        XCTAssertNotEqual(MeetingSyncDocument.fingerprint(of: meeting), pinned)
        let afterName = MeetingSyncDocument.fingerprint(of: meeting)
        meeting.markTranscriptEdited()
        XCTAssertNotEqual(MeetingSyncDocument.fingerprint(of: meeting), afterName, "trims bump the revision, which the fingerprint tracks")
    }

    func testFallbackUpdatedAtIsTheLatestOwnTimestamp() {
        let meeting = sampleMeeting()
        meeting.updatedAt = nil
        meeting.insightsUpdatedAt = Date(timeIntervalSince1970: 1_790_009_000)
        XCTAssertEqual(MeetingSyncDocument.fallbackUpdatedAt(meeting), Date(timeIntervalSince1970: 1_790_009_000))
        let doc = MeetingSyncDocument.encode(meeting, segments: [])
        XCTAssertEqual(doc["updated_at"] as? String, "2026-09-21T16:43:20.000Z")
    }
}


// MARK: - Shared wire fixture

extension MeetingSyncDocumentTests {
    /// The same JSON lives at `../miniti-api/test/fixtures/sync-documents/meeting-v1.json`
    /// and is mirrored by the Linux client. A change here is a contract change for three clients.
    static let sharedFixture = #"""
{
  "schema_version": 1,
  "id": "0f1e2d3c-4b5a-4c6d-8e7f-9a0b1c2d3e4f",
  "title": "Budget review",
  "calendar_event_title": "Budget sync",
  "start_time": "2026-10-01T09:00:00.000Z",
  "end_time": "2026-10-01T09:30:00.000Z",
  "created_at": "2026-10-01T08:58:00.000Z",
  "updated_at": "2026-10-01T09:31:00.000Z",
  "language": "fr",
  "pinned": true,
  "transcript_revision": 2,
  "transcript_edited_at": "2026-10-01T09:20:00.000Z",
  "segments": [
    { "id": "2b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e", "speaker": 0, "text": "Hello everyone", "start": 0.5, "final": true, "confidence": 0.98, "source": "system" },
    { "id": "3c4d5e6f-7a8b-4c9d-8e0f-2a3b4c5d6e7f", "speaker": 1000, "text": "Hi", "start": 2.0, "final": true, "confidence": 1.0, "source": "microphone" }
  ],
  "speaker_names": { "0": "Sasha" },
  "speaker_overrides": ["0"],
  "self_speaker_ids": [1000],
  "summary": "We agreed the budget.",
  "action_items": ["Send the deck"],
  "key_decisions": ["Ship in March"],
  "topics": ["budget"],
  "discussion_flow": ["intro", "numbers"],
  "notes": "Prep notes",
  "insights_updated_at": "2026-10-01T09:31:00.000Z",
  "meddpicc": { "metrics": "20% faster", "economic_buyer": null, "decision_criteria": null, "decision_process": null, "paper_process": null, "identified_pain": null, "champion": null, "competition": null },
  "questions": [{ "question": "Why March?", "type": "challenge", "context": "timing", "priority": "high" }],
  "doc_topics": [],
  "template": { "id": "bant", "definition": null, "sections": { "budget": "20k" } },
  "external_source": "granola",
  "external_id": "csv-1",
  "external_url": null,
  "imported_at": "2026-10-01T09:40:00.000Z",
  "managed_session_id": "sess_1",
  "calendar_event_id": "evt_1",
  "attendees": [{ "email": "sasha@example.com", "name": "Sasha Petrov", "domain": "example.com", "response_status": "accepted", "is_organizer": true, "is_self": false }],
  "inferred_environment": "online",
  "investigations": [{ "topic": "pricing" }],
  "join_url": "https://meet.example/abc",
  "sales_enabled": true,
  "title_auto": false
}
"""#

    func testSharedFixtureRoundTripsThroughTheModelWithEveryFieldAndTheExtras() throws {
        let data = Data(Self.sharedFixture.utf8)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try XCTUnwrap(MeetingSyncDocument.decode(original))
        let meeting = MeetingSyncDocument.makeMeeting(decoded, in: context)
        XCTAssertEqual(meeting.title, "Budget review")
        XCTAssertEqual(meeting.language, "fr")
        XCTAssertTrue(meeting.isPinned)
        XCTAssertEqual(meeting.transcriptRevision, 2)
        XCTAssertEqual(meeting.segments.count, 2)
        XCTAssertEqual(meeting.selfSpeakerIDs, [1000])
        XCTAssertEqual(meeting.templateSections["budget"], "20k")
        XCTAssertEqual(meeting.insightTemplateID, "bant")
        XCTAssertEqual(meeting.externalID, "csv-1")
        XCTAssertEqual(meeting.managedSessionId, "sess_1")
        XCTAssertEqual(meeting.inferredEnvironmentRaw, "online")
        XCTAssertEqual(meeting.attendees.first?.displayName, "Sasha Petrov")
        XCTAssertEqual(meeting.suggestedQuestions.first?.priority, "high")
        let back = MeetingSyncDocument.encode(meeting, segments: meeting.segments)
        let normalised = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: back)) as? [String: Any])
        for key in original.keys {
            let a = original[key] as? NSObject
            let b = normalised[key] as? NSObject
            XCTAssertEqual(a, b, "field \(key) survives the round trip")
        }
    }
}
