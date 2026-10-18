import XCTest
import SwiftData
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// Attribute search (2.11.0): the query parser and the engine behind history search on
/// both platforms. Dates use an injected "now" (Thu 1 Oct 2026, 12:00 UTC) and calendar.
final class MeetingSearchTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }()
    private static let now = utc.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        Self.utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func parse(_ text: String) -> MeetingSearchQuery {
        MeetingSearchQuery.parse(text, now: Self.now, calendar: Self.utc)
    }

    override func setUp() async throws {
        container = try TestSupport.makeInMemoryContainer()
        context = ModelContext(container)
    }

    // MARK: - Parser

    func testPlainWordsAreLowercasedAndQuotedPhrasesStayTogether() {
        let q = parse("Sasha Pricing \"next steps\"")
        XCTAssertEqual(q.words, ["sasha", "pricing", "next steps"])
        XCTAssertFalse(q.hasFilters)
    }

    func testWithTitleAndInTokens() {
        let q = parse("with:sam with:\"Maria Chen\" title:Budget in:transcript hello")
        XCTAssertEqual(q.people, ["sam", "maria chen"])
        XCTAssertEqual(q.titles, ["budget"])
        XCTAssertEqual(q.scope, .transcript)
        XCTAssertEqual(q.words, ["hello"])
    }

    func testFromTokensNameDevicesAndGranola() {
        let q = parse("from:watch from:\"Apple Watch\" from:phone from:granola from:toaster budget")
        XCTAssertEqual(q.devices, ["watch", "iphone", "granola"])
        XCTAssertEqual(q.words, ["from:toaster", "budget"])
        XCTAssertTrue(q.hasFilters)
        XCTAssertEqual(MeetingSearchQuery.clearingFilters(from: "from:watch budget"), "budget")
    }

    @MainActor func testFromMatchesTheRecordingDeviceOrTheImportSource() {
        let watch = makeMeeting(title: "Walk", start: Self.now)
        watch.externalSource = "watch"
        let mac = makeMeeting(title: "Desk", start: Self.now.addingTimeInterval(-60))
        mac.recordedOnRaw = RecordingDevice.mac.rawValue
        let granola = makeMeeting(title: "Imported", start: Self.now.addingTimeInterval(-120))
        granola.externalSource = "granola"
        let legacy = makeMeeting(title: "Old", start: Self.now.addingTimeInterval(-180))
        let all = [watch, mac, granola, legacy]

        XCTAssertEqual(run("from:watch", all).map(\.meeting.title), ["Walk"])
        XCTAssertEqual(run("from:mac", all).map(\.meeting.title), ["Desk"])
        XCTAssertEqual(run("from:mac from:watch", all).map(\.meeting.title), ["Walk", "Desk"])
        XCTAssertEqual(run("from:granola", all).map(\.meeting.title), ["Imported"])
        XCTAssertEqual(run("from:iphone", all).count, 0, "a meeting from before 3.1.0 has no device")
        XCTAssertEqual(run("from:watch", all).first?.context, "from Apple Watch · " + shown(Self.now))

        let options = MeetingSearchDeviceOption.collect(from: all)
        XCTAssertEqual(options.map(\.value), ["mac", "watch", "granola"])
        XCTAssertEqual(options.map(\.meetingCount), [1, 1, 1])
        XCTAssertEqual(options.first?.token, "from:mac")
    }

    func testUnknownKeyIsAWord() {
        let q = parse("mailto:sam@acme.com in:nowhere")
        XCTAssertEqual(q.words, ["mailto:sam@acme.com", "in:nowhere"])
        XCTAssertNil(q.scope)
        XCTAssertFalse(q.hasFilters)
    }

    func testOnIsoDateIsOneDayInclusiveOfBothEnds() throws {
        let range = try XCTUnwrap(parse("on:2026-09-14").dateRange)
        XCTAssertEqual(range.start, date(2026, 9, 14, 0))
        XCTAssertEqual(range.end, date(2026, 9, 15, 0))
        XCTAssertTrue(range.contains(date(2026, 9, 14, 0)))
        XCTAssertTrue(range.contains(date(2026, 9, 14, 23)))
        XCTAssertFalse(range.contains(date(2026, 9, 15, 0)))
    }

    func testOnDayAndMonthBorrowsTheNextToken() throws {
        let q = parse("on:14 sep budget")
        let range = try XCTUnwrap(q.dateRange)
        XCTAssertEqual(range.start, date(2026, 9, 14, 0))
        XCTAssertEqual(q.words, ["budget"], "the month name was consumed by the date, not treated as a word")
        XCTAssertEqual(parse("on:sep 14").dateRange, range)
        XCTAssertEqual(parse("on:\"14 september\"").dateRange, range)
    }

    func testOnMonthNameIsTheMostRecentSuchMonth() throws {
        let sep = try XCTUnwrap(parse("on:september").dateRange)
        XCTAssertEqual(sep.start, date(2026, 9, 1, 0))
        XCTAssertEqual(sep.end, date(2026, 10, 1, 0))
        // November has not happened yet in 2026, so it means November 2025.
        let nov = try XCTUnwrap(parse("on:november").dateRange)
        XCTAssertEqual(nov.start, date(2025, 11, 1, 0))
    }

    func testTodayYesterdayAndWeekday() throws {
        XCTAssertEqual(parse("on:today").dateRange?.start, date(2026, 10, 1, 0))
        XCTAssertEqual(parse("on:yesterday").dateRange?.start, date(2026, 9, 30, 0))
        // 1 Oct 2026 is a Thursday; "monday" is the most recent one, 28 Sep.
        XCTAssertEqual(parse("on:monday").dateRange?.start, date(2026, 9, 28, 0))
        XCTAssertEqual(parse("on:thursday").dateRange?.start, date(2026, 10, 1, 0), "today counts")
    }

    func testAfterIsInclusiveAndBeforeIsExclusive() throws {
        let after = try XCTUnwrap(parse("after:1 sep").dateRange)
        XCTAssertEqual(after.start, date(2026, 9, 1, 0))
        XCTAssertNil(after.end)
        let before = try XCTUnwrap(parse("before:friday").dateRange)
        XCTAssertNil(before.start)
        XCTAssertEqual(before.end, date(2026, 9, 25, 0), "the most recent Friday before Thu 1 Oct is 25 Sep")
        let both = try XCTUnwrap(parse("after:2026-09-01 before:2026-09-15").dateRange)
        XCTAssertEqual(both.start, date(2026, 9, 1, 0))
        XCTAssertEqual(both.end, date(2026, 9, 15, 0))
    }

    func testLastArithmetic() throws {
        XCTAssertEqual(parse("last:7d").dateRange?.start, date(2026, 9, 24, 0))
        XCTAssertEqual(parse("last:2w").dateRange?.start, date(2026, 9, 17, 0))
        XCTAssertEqual(parse("last:3m").dateRange?.start, date(2026, 7, 1, 0))
        XCTAssertNil(parse("last:7d").dateRange?.end)
        XCTAssertEqual(parse("last:soon").words, ["last:soon"], "an unparseable date value falls back to a word")
    }

    func testTokenInsertionReplacesDatesAndStacksPeople() {
        var text = "budget"
        text = MeetingSearchQuery.inserting(token: "with:sam", into: text)
        text = MeetingSearchQuery.inserting(token: MeetingSearchQuery.filterToken(key: "with", value: "Maria Chen"), into: text)
        text = MeetingSearchQuery.inserting(token: "last:7d", into: text)
        text = MeetingSearchQuery.inserting(token: "on:today", into: text)
        XCTAssertEqual(text, "budget with:sam with:\"Maria Chen\" on:today")
        XCTAssertEqual(MeetingSearchQuery.clearingFilters(from: text), "budget")
        XCTAssertEqual(parse(text).people, ["sam", "maria chen"])
    }

    func testDatePresetsProduceParseableTokens() {
        for preset in MeetingSearchDatePreset.allCases {
            let token = preset.token(now: Self.now, calendar: Self.utc)
            XCTAssertNotNil(parse(token).dateRange, "\(preset) -> \(token)")
        }
        XCTAssertEqual(MeetingSearchDatePreset.thisMonth.token(now: Self.now, calendar: Self.utc), "on:october")
        XCTAssertEqual(MeetingSearchDatePreset.lastMonth.token(now: Self.now, calendar: Self.utc), "on:september")
        let tokens = MeetingSearchDatePreset.rangeTokens(from: date(2026, 9, 1), to: date(2026, 9, 14), calendar: Self.utc)
        XCTAssertEqual(tokens, ["after:2026-09-01", "before:2026-09-15"])
        let range = parse(tokens.joined(separator: " ")).dateRange
        XCTAssertTrue(range?.contains(date(2026, 9, 14, 23)) == true, "the chosen last day is included")
        XCTAssertFalse(range?.contains(date(2026, 9, 15, 0)) == true)
    }

    // MARK: - Engine fixtures

    @MainActor
    private func makeMeeting(
        title: String,
        eventTitle: String? = nil,
        start: Date,
        attendees: [MeetingAttendee] = [],
        speakers: [String: String] = [:],
        notes: String = "",
        summary: String? = nil,
        transcript: [String] = []
    ) -> Meeting {
        let meeting = Meeting(title: title, startTime: start, summaryText: summary, notes: notes)
        meeting.calendarEventTitle = eventTitle
        meeting.attendees = attendees
        meeting.speakerNames = speakers
        meeting.segments = transcript.enumerated().map { i, text in
            TranscriptSegment(text: text, speaker: i % 2, timestamp: Double(i), isFinal: true, confidence: 1)
        }
        context.insert(meeting)
        return meeting
    }

    private func attendee(_ name: String?, _ email: String) -> MeetingAttendee {
        MeetingAttendee(email: email, displayName: name, domain: String(email.split(separator: "@").last ?? ""), responseStatus: "accepted", isOrganizer: false, isSelf: false)
    }

    /// The engine's own date rendering, so the context assertions do not depend on ICU's
    /// month abbreviation for the test locale.
    private func shown(_ date: Date) -> String {
        MeetingSearchQuery.displayDate(date, now: Self.now, calendar: Self.utc)
    }

    private func run(_ text: String, _ meetings: [Meeting]) -> [MeetingSearchResult] {
        MeetingSearchResult.search(query: parse(text), in: meetings, now: Self.now, calendar: Self.utc)
    }

    // MARK: - Engine

    @MainActor
    func testEveryWordMustMatchSomewhere() {
        let a = makeMeeting(title: "Pricing review", start: date(2026, 9, 20), attendees: [attendee("Sasha Petrov", "sasha@acme.com")])
        let b = makeMeeting(title: "Pricing review", start: date(2026, 9, 21))
        let results = run("sasha pricing", [a, b])
        XCTAssertEqual(results.map(\.meeting.id), [a.id], "b has pricing but no sasha")
        XCTAssertEqual(run("pricing", [a, b]).count, 2)
    }

    @MainActor
    func testWithMatchesAttendeeNameEmailDomainAndSpeaker() {
        let m = makeMeeting(title: "Sync", start: date(2026, 9, 20),
                            attendees: [attendee("Sasha Petrov", "sasha@acme.com")],
                            speakers: ["1001": "Lena"])
        let other = makeMeeting(title: "Sync", start: date(2026, 9, 21))
        for query in ["with:sasha", "with:petrov", "with:sasha@acme.com", "with:acme.com", "with:lena"] {
            XCTAssertEqual(run(query, [m, other]).map(\.meeting.id), [m.id], query)
        }
        XCTAssertTrue(run("with:nobody", [m, other]).isEmpty)
        XCTAssertEqual(run("with:sasha", [m]).first?.context, "with Sasha Petrov · " + shown(date(2026, 9, 20)))
        XCTAssertEqual(run("with:lena", [m]).first?.context, "with Lena · " + shown(date(2026, 9, 20)))
    }

    @MainActor
    func testTitleMatchesTheCalendarEventTitleAfterARename() {
        let m = makeMeeting(title: "Pricing and rollout", eventTitle: "Sasha / Ian 1:1", start: date(2026, 9, 20))
        XCTAssertEqual(run("title:1:1", [m]).count, 1)
        XCTAssertEqual(run("title:rollout", [m]).count, 1)
        XCTAssertTrue(run("title:standup", [m]).isEmpty)
        XCTAssertEqual(run("sasha", [m]).count, 1, "plain words also see the event title")
    }

    @MainActor
    func testDateFiltersAreInclusiveAtDayBoundariesAndOrderNewestFirst() {
        let early = makeMeeting(title: "A", start: date(2026, 9, 14, 0))
        let late = makeMeeting(title: "B", start: date(2026, 9, 14, 23))
        let next = makeMeeting(title: "C", start: date(2026, 9, 15, 0))
        let on = run("on:2026-09-14", [early, next, late])
        XCTAssertEqual(on.map(\.meeting.title), ["B", "A"], "newest first with a date filter, next day excluded")
        XCTAssertEqual(on.first?.context, shown(date(2026, 9, 14)))
        XCTAssertEqual(run("after:14 sep", [early, next, late]).count, 3)
        XCTAssertEqual(run("before:15 sep", [early, next, late]).count, 2)
        XCTAssertEqual(run("last:2w", [early, next, late]).count, 0, "all three are more than two weeks before 1 Oct")
    }

    @MainActor
    func testWordsAndFiltersCombineAndRelevanceOrdersWithoutADate() {
        let titleHit = makeMeeting(title: "Budget planning", start: date(2026, 9, 10), attendees: [attendee("Sasha Petrov", "sasha@acme.com")])
        let transcriptHit = makeMeeting(title: "Sync", start: date(2026, 9, 12), attendees: [attendee("Sasha Petrov", "sasha@acme.com")],
                                        transcript: ["we should revisit the budget next week"])
        let noSasha = makeMeeting(title: "Budget", start: date(2026, 9, 13))
        let results = run("with:sasha budget", [transcriptHit, noSasha, titleHit])
        XCTAssertEqual(results.map(\.meeting.id), [titleHit.id, transcriptHit.id], "title beats transcript; noSasha excluded")
        XCTAssertEqual(results.first?.context, "with Sasha Petrov · " + shown(date(2026, 9, 10)))
        XCTAssertNotNil(results.last?.snippet)
    }

    @MainActor
    func testInScopeRestrictsPlainWords() {
        let m = makeMeeting(title: "Budget", start: date(2026, 9, 10), notes: "nothing here", transcript: ["talked about the forecast"])
        XCTAssertEqual(run("in:transcript forecast", [m]).count, 1)
        XCTAssertTrue(run("in:notes forecast", [m]).isEmpty)
        XCTAssertTrue(run("in:transcript budget", [m]).isEmpty, "the title is out of scope")
    }

    @MainActor
    func testFilterOnlyQueryReturnsMembersAndEmptyQueryReturnsNothing() {
        let m = makeMeeting(title: "Sync", start: date(2026, 9, 20), attendees: [attendee("Sam Jones", "sam@x.com")])
        XCTAssertEqual(run("with:sam", [m]).count, 1)
        XCTAssertTrue(MeetingSearchResult.search(query: "", in: [m]).isEmpty)
        XCTAssertTrue(MeetingSearchResult.search(query: "   ", in: [m]).isEmpty)
    }

    @MainActor
    func testTranscriptCacheInvalidatesOnRevision() {
        let m = makeMeeting(title: "Sync", start: date(2026, 9, 20), transcript: ["alpha words here"])
        XCTAssertEqual(run("alpha", [m]).count, 1)
        XCTAssertTrue(MeetingSearchResult.isTranscriptCached(m))
        m.segments.append(TranscriptSegment(text: "omega words here", speaker: 0, timestamp: 9, isFinal: true, confidence: 1))
        XCTAssertTrue(run("omega", [m]).isEmpty, "stale cache until the revision changes")
        m.transcriptRevision += 1
        XCTAssertFalse(MeetingSearchResult.isTranscriptCached(m))
        XCTAssertEqual(run("omega", [m]).count, 1)
    }

    @MainActor
    func testPeopleListRanksByMeetingCountAndMergesSpeakers() {
        let sasha = attendee("Sasha Petrov", "sasha@acme.com")
        let m1 = makeMeeting(title: "A", start: date(2026, 9, 1), attendees: [sasha], speakers: ["1001": "Lena"])
        let m2 = makeMeeting(title: "B", start: date(2026, 9, 2), attendees: [sasha, attendee(nil, "tom@okafor.io")])
        let m3 = makeMeeting(title: "C", start: date(2026, 9, 3), speakers: ["5": "Sasha Petrov"])
        let people = MeetingSearchPerson.collect(from: [m1, m2, m3])
        XCTAssertEqual(people.first?.name, "Sasha Petrov")
        XCTAssertEqual(people.first?.meetingCount, 2, "the speaker-name copy in m3 is not double counted as a new person")
        XCTAssertTrue(people.contains { $0.name == "tom@okafor.io" && $0.source == .attendee }, "no display name falls back to the email")
        XCTAssertTrue(people.contains { $0.name == "Lena" && $0.source == .speaker })
        XCTAssertEqual(people.first?.token, "with:\"Sasha Petrov\"")
    }
}
