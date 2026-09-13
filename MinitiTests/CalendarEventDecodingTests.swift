import Foundation
import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// The 2.7.0 regression: `/api/google/events` is camelCase on the wire, and decoding the
/// wrong case silently dropped links and attendee names for months because every field
/// has a default. This pins the wire format, the snake_case fallback, and the join rules.
final class CalendarEventDecodingTests: XCTestCase {
    /// Exactly what `miniti-api` `lib/google.ts` sends, including a filtered event.
    static let wirePayload = """
    {"events": [
      {"id": "evt_design", "title": "Design review", "start": "2026-09-14T10:00:00.000Z", "end": "2026-09-14T10:30:00.000Z",
       "isAllDay": false, "status": "confirmed", "eventType": "default",
       "meetLink": "https://meet.google.com/abc-defg-hij", "conferenceUrl": null,
       "attendees": [
         {"email": "sam@acme.com", "displayName": "Sam Lee", "responseStatus": "accepted", "organizer": true, "self": false},
         {"email": "ian@miniti.app", "responseStatus": "accepted", "self": true}
       ],
       "organizer": {"email": "sam@acme.com", "displayName": "Sam Lee", "self": false}},
      {"id": "evt_ooo", "title": "Out of office", "start": "2026-09-15T00:00:00Z", "end": "2026-09-16T00:00:00Z",
       "isAllDay": true, "status": "confirmed", "eventType": "outOfOffice", "skipReason": "out_of_office", "attendees": []}
    ]}
    """

    private func decode(_ json: String) throws -> [MinitiAPIService.CalendarEvent] {
        try JSONDecoder().decode(MinitiAPIService.GoogleEventsResponse.self, from: Data(json.utf8)).events
    }

    func testCamelCaseWireFormatKeepsLinksNamesAndResponses() throws {
        let events = try decode(Self.wirePayload)
        XCTAssertEqual(events.count, 2)

        let design = events[0]
        XCTAssertEqual(design.meetLink, "https://meet.google.com/abc-defg-hij")
        XCTAssertNil(design.conferenceUrl)
        XCTAssertEqual(design.joinURL?.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(design.attendees.map(\.email), ["sam@acme.com", "ian@miniti.app"])
        XCTAssertEqual(design.attendees[0].displayName, "Sam Lee")
        XCTAssertEqual(design.attendees[0].responseStatus, "accepted")
        XCTAssertTrue(design.attendees[0].organizer)
        XCTAssertTrue(design.attendees[1].isSelf)
        XCTAssertEqual(design.attendees[1].domain, "miniti.app", "domain derives from the email when the backend omits it")
        XCTAssertEqual(design.externalAttendees.map(\.email), ["sam@acme.com"])
        XCTAssertEqual(design.attendeeDomains, ["acme.com"])
        XCTAssertEqual(design.organizer?.displayName, "Sam Lee")
        XCTAssertEqual(design.eventType, "default")
        XCTAssertNil(design.skipReason)
        XCTAssertNotNil(design.startDate, "fractional-second ISO 8601 parses")
        XCTAssertTrue(design.isRecordableMeeting)

        let ooo = events[1]
        XCTAssertTrue(ooo.isAllDay)
        XCTAssertEqual(ooo.eventType, "outOfOffice")
        XCTAssertEqual(ooo.skipReason, "out_of_office")
        XCTAssertFalse(ooo.isRecordableMeeting)
        XCTAssertNotNil(ooo.startDate, "whole-second ISO 8601 parses too")
    }

    func testSnakeCaseFallbackStillDecodes() throws {
        let events = try decode("""
        {"events": [{"id": "e", "title": "Sync", "start": "2026-09-14T10:00:00Z", "end": "2026-09-14T10:30:00Z",
          "is_all_day": false, "event_type": "default", "meet_link": null, "conference_url": "https://zoom.us/j/123",
          "attendees": [{"email": "a@b.co", "display_name": "A B", "response_status": "tentative"}]}]}
        """)
        XCTAssertEqual(events[0].conferenceUrl, "https://zoom.us/j/123")
        XCTAssertEqual(events[0].joinURL?.host, "zoom.us")
        XCTAssertEqual(events[0].attendees[0].displayName, "A B")
        XCTAssertEqual(events[0].attendees[0].responseStatus, "tentative")
    }

    func testDefaultsWhenOptionalFieldsAreMissing() throws {
        let events = try decode(#"{"events": [{"id": "e", "start": "2026-09-14T10:00:00Z", "end": "2026-09-14T10:30:00Z"}]}"#)
        let event = events[0]
        XCTAssertEqual(event.title, "Untitled")
        XCTAssertEqual(event.status, "confirmed")
        XCTAssertFalse(event.isAllDay)
        XCTAssertNil(event.eventType)
        XCTAssertNil(event.joinURL)
        XCTAssertTrue(event.attendees.isEmpty)
        XCTAssertNil(event.organizer)
    }

    func testJoinURLPrefersConferenceURLAndRefusesNonHTTPS() throws {
        let events = try decode("""
        {"events": [
          {"id": "both", "start": "2026-09-14T10:00:00Z", "end": "2026-09-14T10:30:00Z", "meetLink": "https://meet.google.com/x", "conferenceUrl": "https://teams.microsoft.com/l/meetup-join/y"},
          {"id": "http", "start": "2026-09-14T10:00:00Z", "end": "2026-09-14T10:30:00Z", "meetLink": "http://meet.google.com/x"},
          {"id": "blank", "start": "2026-09-14T10:00:00Z", "end": "2026-09-14T10:30:00Z", "meetLink": "   ", "conferenceUrl": ""}
        ]}
        """)
        XCTAssertEqual(events[0].joinURL?.host, "teams.microsoft.com")
        XCTAssertNil(events[1].joinURL, "plain http is never handed to the system opener")
        XCTAssertNil(events[2].joinURL)
    }

    func testMalformedAttendeesDoNotSinkTheEvent() throws {
        let events = try decode(#"{"events": [{"id": "e", "start": "2026-09-14T10:00:00Z", "end": "2026-09-14T10:30:00Z", "attendees": "nope"}]}"#)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].attendees.isEmpty)
    }
}
