import XCTest
#if os(iOS)
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class SpeakerAttendeeMatcherTests: XCTestCase {
    private func attendee(_ name: String?, _ email: String) -> MeetingAttendee {
        MeetingAttendee(email: email, displayName: name, domain: String(email.split(separator: "@").last ?? ""), responseStatus: "accepted", isOrganizer: false, isSelf: false)
    }

    private let people = [
        MeetingAttendee(email: "sam.jones@acme.com", displayName: "Sam Jones", domain: "acme.com", responseStatus: "accepted", isOrganizer: false, isSelf: false),
        MeetingAttendee(email: "maria@acme.com", displayName: "María Chen", domain: "acme.com", responseStatus: "accepted", isOrganizer: false, isSelf: false),
        MeetingAttendee(email: "sam.patel@beta.io", displayName: "Sam Patel", domain: "beta.io", responseStatus: "accepted", isOrganizer: false, isSelf: false),
        MeetingAttendee(email: "li.wei@gamma.co", displayName: nil, domain: "gamma.co", responseStatus: "accepted", isOrganizer: false, isSelf: false),
    ]

    func testFullNameMatchesCaseAndAccentInsensitively() {
        XCTAssertEqual(SpeakerAttendeeMatcher.match(name: "maria chen", attendees: people)?.email, "maria@acme.com")
        XCTAssertEqual(SpeakerAttendeeMatcher.match(name: "SAM JONES", attendees: people)?.email, "sam.jones@acme.com")
    }

    func testFirstNameOnlyMatchesWhenUnique() {
        XCTAssertEqual(SpeakerAttendeeMatcher.match(name: "Maria", attendees: people)?.email, "maria@acme.com")
        XCTAssertNil(SpeakerAttendeeMatcher.match(name: "Sam", attendees: people), "two Sams: never guess")
    }

    func testEmailLocalPartMatchesANameWithoutADisplayName() {
        XCTAssertEqual(SpeakerAttendeeMatcher.match(name: "Li Wei", attendees: people)?.email, "li.wei@gamma.co")
        XCTAssertNil(SpeakerAttendeeMatcher.match(name: "Wei", attendees: people))
        XCTAssertEqual(SpeakerAttendeeMatcher.displayName(for: people[3]), "Li Wei")
    }

    @MainActor
    func testMeetingResolvesPickedAndMatchedEmailsAndClearsPicksOnRename() {
        let meeting = Meeting(title: "Budget", startTime: Date(), endTime: Date().addingTimeInterval(60))
        meeting.attendees = people
        meeting.speakerNames = ["0": "Maria Chen", "1": "Sam"]
        XCTAssertEqual(meeting.speakerEmail(for: "0"), "maria@acme.com")
        XCTAssertNil(meeting.speakerEmail(for: "1"))
        XCTAssertEqual(meeting.resolvedSpeakerEmails, ["0": "maria@acme.com"])

        meeting.setSpeakerAttendee(id: "1", attendee: people[2])
        XCTAssertEqual(meeting.speakerNames["1"], "Sam Patel")
        XCTAssertEqual(meeting.speakerEmail(for: "1"), "sam.patel@beta.io")
        XCTAssertEqual(meeting.resolvedSpeakerEmails.count, 2)

        // Renaming by hand drops the pick; a name that still matches re-resolves on its own.
        meeting.setSpeakerName(id: "1", name: "Someone Else")
        XCTAssertNil(meeting.speakerEmail(for: "1"))
        meeting.setSpeakerName(id: "1", name: "Sam Patel")
        XCTAssertEqual(meeting.speakerEmail(for: "1"), "sam.patel@beta.io")

        // Re-applying the same name keeps the pick.
        meeting.setSpeakerAttendee(id: "0", attendee: people[1])
        meeting.setSpeakerName(id: "0", name: "maría chen")
        XCTAssertEqual(meeting.speakerEmails["0"], "maria@acme.com")
    }

    @MainActor
    func testWebhookAndMarkdownCarryTheEmails() throws {
        let meeting = Meeting(title: "Budget", startTime: Date(), endTime: Date().addingTimeInterval(60),
                              segments: [TranscriptSegment(text: "Hello", speaker: 0, timestamp: 0, isFinal: true)])
        meeting.attendees = people
        meeting.speakerNames = ["0": "Maria Chen"]
        let payload = WebhookService.payloadFromMeeting(meeting)
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let m = try XCTUnwrap(json["meeting"] as? [String: Any])
        XCTAssertEqual(m["speaker_emails"] as? [String: String], ["0": "maria@acme.com"])
        let attendees = try XCTUnwrap(m["attendees"] as? [[String: Any]])
        XCTAssertEqual(attendees.first(where: { $0["email"] as? String == "maria@acme.com" })?["speaker"] as? String, "0")
        XCTAssertNil(attendees.first(where: { $0["email"] as? String == "sam.jones@acme.com" })?["speaker"] as? String)
        XCTAssertTrue(meeting.fullMeetingAsMarkdown().contains("_Speakers: Maria Chen (maria@acme.com)_"))
    }
}
