import Foundation

/// The parsed form of what someone typed into meeting search (2.11.0).
///
/// Plain words must all match somewhere in a meeting. `"quoted phrases"` match as one
/// term. Filters are `key:value` tokens: `with:` (attendee or speaker), `title:`
/// (calendar event title or meeting title), `on:` / `after:` / `before:` / `last:`
/// (dates, on the meeting's start time), `in:` (restrict words to one field). An unknown
/// `key:value` is just a word, so an email with a colon never breaks a query. The people
/// and date menus insert these same tokens, so the typed text stays the single source of
/// truth for the search.
struct MeetingSearchQuery: Equatable {
    enum Scope: String, CaseIterable {
        case transcript, notes, summary, title
    }

    /// Inclusive `start`, exclusive `end`; either side may be open.
    struct DateRange: Equatable {
        var start: Date?
        var end: Date?

        func contains(_ date: Date) -> Bool {
            if let start, date < start { return false }
            if let end, date >= end { return false }
            return true
        }

        func intersected(with other: DateRange) -> DateRange {
            DateRange(
                start: [start, other.start].compactMap { $0 }.max(),
                end: [end, other.end].compactMap { $0 }.min()
            )
        }
    }

    /// Lowercased plain words and quoted phrases, every one of which must match.
    var words: [String] = []
    /// Lowercased `with:` values; every one must match an attendee or speaker.
    var people: [String] = []
    /// Lowercased `title:` values; every one must match the event or meeting title.
    var titles: [String] = []
    /// `from:` values (device raw values, or `granola`); a meeting matches any one of them.
    var devices: [String] = []
    var dateRange: DateRange?
    var scope: Scope?

    var hasFilters: Bool { !people.isEmpty || !titles.isEmpty || !devices.isEmpty || dateRange != nil }
    var isEmpty: Bool { words.isEmpty && !hasFilters }

    static let filterKeys: Set<String> = ["with", "title", "from", "on", "after", "before", "last", "in"]
    /// Non-device `from:` value: meetings imported from Granola.
    static let granolaSource = "granola"
    static let dateKeys: Set<String> = ["on", "after", "before", "last"]

    // MARK: - Parsing

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> MeetingSearchQuery {
        var query = MeetingSearchQuery()
        let tokens = tokenize(text)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            guard let colon = token.firstIndex(of: ":"), colon != token.startIndex else {
                query.words.append(token.lowercased())
                continue
            }
            let key = String(token[..<colon]).lowercased()
            var value = String(token[token.index(after: colon)...])
            guard filterKeys.contains(key) else {
                query.words.append(token.lowercased())
                continue
            }
            // `on:14 sep` / `on:sep 14`: a bare day number borrows the following month
            // name, and a bare month name borrows a following day number.
            if dateKeys.contains(key), key != "last", index < tokens.count {
                let next = tokens[index]
                let valueIsDay = Int(value).map { (1...31).contains($0) } ?? false
                let nextIsDay = Int(next).map { (1...31).contains($0) } ?? false
                if (valueIsDay && monthNumber(for: next.lowercased()) != nil)
                    || (nextIsDay && monthNumber(for: value.lowercased()) != nil) {
                    value += " " + next
                    index += 1
                }
            }
            let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
            guard !lower.isEmpty else { continue }
            switch key {
            case "with": query.people.append(lower)
            case "title": query.titles.append(lower)
            case "from":
                if let device = RecordingDevice.parse(lower) {
                    if !query.devices.contains(device.rawValue) { query.devices.append(device.rawValue) }
                } else if lower == granolaSource {
                    if !query.devices.contains(granolaSource) { query.devices.append(granolaSource) }
                } else {
                    query.words.append(token.lowercased())
                }
            case "in":
                if let scope = Scope(rawValue: lower) { query.scope = scope } else { query.words.append(token.lowercased()) }
            case "on", "after", "before", "last":
                guard let range = dateRange(key: key, value: lower, now: now, calendar: calendar) else {
                    query.words.append(token.lowercased())
                    continue
                }
                query.dateRange = query.dateRange.map { $0.intersected(with: range) } ?? range
            default:
                query.words.append(token.lowercased())
            }
        }
        return query
    }

    /// Whitespace-separated tokens; double quotes group words, including after a `key:`.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for ch in text {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if ch.isWhitespace && !inQuotes {
                if !current.isEmpty { tokens.append(current); current = "" }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Dates

    private static let monthNames = ["january", "february", "march", "april", "may", "june", "july",
                                     "august", "september", "october", "november", "december"]
    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    static func monthNumber(for word: String) -> Int? {
        guard word.count >= 3 else { return nil }
        return monthNames.firstIndex { $0.hasPrefix(word) }.map { $0 + 1 }
    }

    static func weekdayNumber(for word: String) -> Int? {
        guard word.count >= 3 else { return nil }
        return weekdayNames.firstIndex { $0.hasPrefix(word) }.map { $0 + 1 }
    }

    /// Resolves a date value to the calendar days it names: a single day, a whole month,
    /// or (for `last:`) a trailing window. Returns nil for anything unrecognised.
    static func dateSpan(for value: String, now: Date, calendar: Calendar) -> DateRange? {
        let v = value.lowercased().trimmingCharacters(in: .whitespaces)
        let today = calendar.startOfDay(for: now)
        func day(_ d: Date) -> DateRange {
            let s = calendar.startOfDay(for: d)
            return DateRange(start: s, end: calendar.date(byAdding: .day, value: 1, to: s))
        }
        if v == "today" { return day(today) }
        if v == "yesterday" { return day(calendar.date(byAdding: .day, value: -1, to: today)!) }
        if let weekday = weekdayNumber(for: v) {
            // The most recent such weekday, today included.
            let todayWeekday = calendar.component(.weekday, from: today)
            let back = (todayWeekday - weekday + 7) % 7
            return day(calendar.date(byAdding: .day, value: -back, to: today)!)
        }
        // 2026-09-14
        let iso = v.split(separator: "-").map(String.init)
        if iso.count == 3, let y = Int(iso[0]), let m = Int(iso[1]), let d = Int(iso[2]),
           let date = calendar.date(from: DateComponents(year: y, month: m, day: d)) {
            return day(date)
        }
        // 14 sep, 14 september, sep 14
        let parts = v.split(separator: " ").map(String.init)
        if parts.count == 2 {
            let (dayPart, monthPart) = Int(parts[0]) != nil ? (parts[0], parts[1]) : (parts[1], parts[0])
            if let d = Int(dayPart), let m = monthNumber(for: monthPart) {
                return recentDate(month: m, day: d, now: now, calendar: calendar).map(day)
            }
        }
        // september: the most recent such month, this one included
        if parts.count == 1, let m = monthNumber(for: v) {
            guard let first = recentDate(month: m, day: 1, now: now, calendar: calendar) else { return nil }
            return DateRange(start: first, end: calendar.date(byAdding: .month, value: 1, to: first))
        }
        return nil
    }

    /// The most recent occurrence of month/day that is not after today.
    private static func recentDate(month: Int, day: Int, now: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: now)
        for y in [year, year - 1] {
            if let date = calendar.date(from: DateComponents(year: y, month: month, day: day)),
               calendar.startOfDay(for: date) <= calendar.startOfDay(for: now) {
                return calendar.startOfDay(for: date)
            }
        }
        return nil
    }

    static func dateRange(key: String, value: String, now: Date, calendar: Calendar) -> DateRange? {
        switch key {
        case "last":
            // 7d, 2w, 3m
            let unit = value.last.map(String.init) ?? ""
            guard let count = Int(value.dropLast()), count > 0 else { return nil }
            let component: Calendar.Component
            switch unit {
            case "d": component = .day
            case "w": component = .weekOfYear
            case "m": component = .month
            default: return nil
            }
            guard let start = calendar.date(byAdding: component, value: -count, to: now) else { return nil }
            return DateRange(start: calendar.startOfDay(for: start), end: nil)
        case "on":
            return dateSpan(for: value, now: now, calendar: calendar)
        case "after":
            // Inclusive from the start of the named day or month: "since".
            return dateSpan(for: value, now: now, calendar: calendar).map { DateRange(start: $0.start, end: nil) }
        case "before":
            // Everything strictly before the named day or month.
            return dateSpan(for: value, now: now, calendar: calendar).map { DateRange(start: nil, end: $0.start) }
        default:
            return nil
        }
    }

    // MARK: - Token insertion (shared by the people and date menus)

    /// Appends a filter token to the typed text. Date tokens replace any date token already
    /// present, since two date presets never make sense together; people tokens stack.
    static func inserting(token: String, into text: String) -> String {
        var tokens = tokenize(text).map(quotedIfNeeded)
        let newKey = token.split(separator: ":", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        if dateKeys.contains(newKey) {
            tokens.removeAll { t in
                let key = t.split(separator: ":", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
                return t.contains(":") && dateKeys.contains(key)
            }
        }
        if !tokens.contains(token) { tokens.append(token) }
        return tokens.joined(separator: " ")
    }

    /// Removes every filter token, leaving the plain words.
    static func clearingFilters(from text: String) -> String {
        tokenize(text).filter { t in
            guard let colon = t.firstIndex(of: ":"), colon != t.startIndex else { return true }
            return !filterKeys.contains(String(t[..<colon]).lowercased())
        }.map(quotedIfNeeded).joined(separator: " ")
    }

    /// `with:Sam Jones` becomes `with:"Sam Jones"` so it survives tokenisation.
    static func filterToken(key: String, value: String) -> String {
        let v = value.trimmingCharacters(in: .whitespaces)
        return v.contains(" ") ? "\(key):\"\(v)\"" : "\(key):\(v)"
    }

    private static func quotedIfNeeded(_ token: String) -> String {
        guard token.contains(" ") else { return token }
        if let colon = token.firstIndex(of: ":"), filterKeys.contains(String(token[..<colon]).lowercased()) {
            return "\(token[..<colon]):\"\(token[token.index(after: colon)...])\""
        }
        return "\"\(token)\""
    }

    // MARK: - Display

    /// "14 Sep", or "14 Sep 2025" when the year differs from now's.
    static func displayDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale ?? calendar.locale ?? .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "d MMM" : "d MMM yyyy")
        return formatter.string(from: date)
    }
}

/// A person who appears in saved meetings, for the people menu: calendar attendees by
/// display name (or email), and speaker names from transcripts, ranked by how many
/// meetings they appear in.
struct MeetingSearchPerson: Identifiable, Equatable {
    enum Source: Equatable { case attendee, speaker }
    let name: String
    let source: Source
    let meetingCount: Int
    var id: String { "\(source == .attendee ? "a" : "s"):\(name.lowercased())" }

    /// The `with:` value that finds this person. Attendees use their display name; the
    /// engine also matches email and domain, so a name is enough.
    var token: String { MeetingSearchQuery.filterToken(key: "with", value: name) }

    static func collect(from meetings: [Meeting], limit: Int = 60) -> [MeetingSearchPerson] {
        var attendeeCounts: [String: (display: String, count: Int)] = [:]
        var speakerCounts: [String: (display: String, count: Int)] = [:]
        for meeting in meetings {
            var seen = Set<String>()
            for attendee in meeting.attendees where !attendee.isSelf {
                let display = (attendee.displayName?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? attendee.email
                let key = display.lowercased()
                guard seen.insert("a:" + key).inserted else { continue }
                attendeeCounts[key, default: (display, 0)].count += 1
            }
            for name in meeting.speakerNames.values {
                let display = name.trimmingCharacters(in: .whitespaces)
                guard !display.isEmpty else { continue }
                let key = display.lowercased()
                guard attendeeCounts[key] == nil, seen.insert("s:" + key).inserted else { continue }
                speakerCounts[key, default: (display, 0)].count += 1
            }
        }
        let attendees = attendeeCounts.values.map { MeetingSearchPerson(name: $0.display, source: .attendee, meetingCount: $0.count) }
        let speakers = speakerCounts.values.map { MeetingSearchPerson(name: $0.display, source: .speaker, meetingCount: $0.count) }
        return (attendees + speakers)
            .sorted { ($0.meetingCount, $1.name.lowercased()) > ($1.meetingCount, $0.name.lowercased()) }
            .prefix(limit)
            .map { $0 }
    }
}

/// Date presets for the date menu, each a ready-to-insert token.
enum MeetingSearchDatePreset: String, CaseIterable, Identifiable {
    case today, yesterday, last7Days, last30Days, thisMonth, lastMonth
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .last7Days: return "last 7 days"
        case .last30Days: return "last 30 days"
        case .thisMonth: return "this month"
        case .lastMonth: return "last month"
        }
    }

    func token(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .today: return "on:today"
        case .yesterday: return "on:yesterday"
        case .last7Days: return "last:7d"
        case .last30Days: return "last:30d"
        case .thisMonth:
            let month = calendar.component(.month, from: now)
            return "on:" + MeetingSearchDatePreset.monthToken(month)
        case .lastMonth:
            let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return "on:" + MeetingSearchDatePreset.monthToken(calendar.component(.month, from: previous))
        }
    }

    private static func monthToken(_ month: Int) -> String {
        ["january", "february", "march", "april", "may", "june", "july",
         "august", "september", "october", "november", "december"][max(0, min(11, month - 1))]
    }

    /// A custom range from two dates: `after:YYYY-MM-DD before:YYYY-MM-DD` where the end is
    /// the day after the chosen last day, so both ends are inclusive for the person picking.
    static func rangeTokens(from start: Date, to end: Date, calendar: Calendar = .current) -> [String] {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        return ["after:" + f.string(from: start), "before:" + f.string(from: endExclusive)]
    }
}


/// One row of the device filter menu: a device (or Granola) that at least one meeting came from.
struct MeetingSearchDeviceOption: Identifiable, Equatable {
    let value: String
    let label: String
    let symbolName: String
    let meetingCount: Int
    var id: String { value }

    /// `from:` token for this option.
    var token: String { MeetingSearchQuery.filterToken(key: "from", value: value) }

    /// Devices present in `meetings`, in a fixed order, with counts. Meetings from before
    /// 3.1.0 have no device and are not counted.
    static func collect(from meetings: [Meeting]) -> [MeetingSearchDeviceOption] {
        var counts: [String: Int] = [:]
        for meeting in meetings {
            if let device = meeting.recordingDevice {
                counts[device.rawValue, default: 0] += 1
            } else if meeting.externalSource?.lowercased() == MeetingSearchQuery.granolaSource {
                counts[MeetingSearchQuery.granolaSource, default: 0] += 1
            }
        }
        var options: [MeetingSearchDeviceOption] = RecordingDevice.allCases.compactMap { device in
            guard let n = counts[device.rawValue] else { return nil }
            return MeetingSearchDeviceOption(value: device.rawValue, label: device.displayName, symbolName: device.symbolName, meetingCount: n)
        }
        if let n = counts[MeetingSearchQuery.granolaSource] {
            options.append(MeetingSearchDeviceOption(value: MeetingSearchQuery.granolaSource, label: "Granola", symbolName: "square.and.arrow.down", meetingCount: n))
        }
        return options
    }
}
