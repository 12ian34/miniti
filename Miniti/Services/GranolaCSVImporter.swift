import Foundation
import SwiftData

struct GranolaCSVParseResult: Sendable {
    let meetings: [GranolaImportedMeeting]
    let skippedRows: Int
}

struct GranolaCSVImportResult: Sendable {
    let imported: Int
    let duplicates: Int
    let skippedRows: Int

    var message: String {
        var parts: [String] = []
        if imported > 0 {
            parts.append("Imported \(imported) meeting\(imported == 1 ? "" : "s")")
        } else {
            parts.append("No new meetings imported")
        }
        if duplicates > 0 {
            parts.append("\(duplicates) already imported")
        }
        if skippedRows > 0 {
            parts.append("\(skippedRows) row\(skippedRows == 1 ? "" : "s") skipped")
        }
        return parts.joined(separator: " · ")
    }
}

struct GranolaImportedMeeting: Sendable {
    let externalID: String
    let title: String
    let startTime: Date
    let endTime: Date
    let summary: String?
    let notes: String
    let transcript: [GranolaImportedTranscriptTurn]
    let attendees: [GranolaImportedAttendee]
    let calendarEventID: String?
    let sourceURL: String?
}

struct GranolaImportedTranscriptTurn: Sendable {
    let text: String
    let speakerKey: String
    let speakerName: String?
    let isSelf: Bool
    let relativeTimestamp: TimeInterval?
    let absoluteTimestamp: Date?
}

struct GranolaImportedAttendee: Sendable {
    let name: String?
    let email: String
    let isOrganizer: Bool
    let isSelf: Bool
}

enum GranolaCSVImportError: LocalizedError {
    case unreadableText
    case malformedCSV
    case missingRecognizedColumns
    case noImportableMeetings

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            return "The Granola export could not be read as a UTF-8 CSV file."
        case .malformedCSV:
            return "The Granola CSV contains an unfinished quoted field."
        case .missingRecognizedColumns:
            return "This CSV does not contain recognizable Granola meeting columns."
        case .noImportableMeetings:
            return "No importable meetings were found. Each row needs a meeting date."
        }
    }
}

enum GranolaCSVImporter {
    static let sourceIdentifier = "granola"
    static let exportURL = URL(string: "https://notes.granola.ai/settings/profile")!

    private static let idHeaders = ["id", "noteid", "documentid", "meetingid", "granolaid"]
    private static let titleHeaders = ["title", "notetitle", "meetingtitle", "name"]
    private static let startHeaders = [
        "starttime", "meetingstart", "meetingdate", "date", "createdat", "created",
        "scheduledstarttime", "calendareventstart"
    ]
    private static let endHeaders = [
        "endtime", "meetingend", "updatedat", "updated", "scheduledendtime", "calendareventend"
    ]
    private static let summaryHeaders = ["summarytext", "summary", "notesummary", "aisummary"]
    private static let notesHeaders = [
        "notes", "notemarkdown", "notesmarkdown", "summarymarkdown", "enhancednotes", "private notes"
    ].map(normalizeHeader)
    private static let transcriptHeaders = ["transcript", "rawtranscript", "fulltranscript", "transcription"]
    private static let attendeeHeaders = ["attendees", "invitees", "participants", "people"]
    private static let ownerEmailHeaders = ["owneremail", "owner", "createdbyemail"]
    private static let organizerHeaders = ["organizer", "organiser", "organizeremail", "organiseremail"]
    private static let calendarIDHeaders = ["calendareventid", "calendarid", "eventid"]
    private static let urlHeaders = ["weburl", "granolaurl", "url", "link"]

    static func load(from url: URL) async throws -> GranolaCSVParseResult {
        try await Task.detached(priority: .userInitiated) {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try parse(data: Data(contentsOf: url))
        }.value
    }

    static func parse(data: Data) throws -> GranolaCSVParseResult {
        guard var text = String(data: data, encoding: .utf8) else {
            throw GranolaCSVImportError.unreadableText
        }
        if text.first == "\u{feff}" {
            text.removeFirst()
        }

        let rows = try parseCSVRows(text)
        guard let rawHeaders = rows.first, !rawHeaders.isEmpty else {
            throw GranolaCSVImportError.missingRecognizedColumns
        }
        let headers = rawHeaders.map(normalizeHeader)
        let recognizedHeaders = Set(
            idHeaders + titleHeaders + startHeaders + endHeaders + summaryHeaders + notesHeaders +
            transcriptHeaders + attendeeHeaders + ownerEmailHeaders + organizerHeaders +
            calendarIDHeaders + urlHeaders
        )
        guard headers.contains(where: recognizedHeaders.contains) else {
            throw GranolaCSVImportError.missingRecognizedColumns
        }

        var meetings: [GranolaImportedMeeting] = []
        var skippedRows = 0
        for row in rows.dropFirst() where row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            if let meeting = importedMeeting(from: row, headers: headers) {
                meetings.append(meeting)
            } else {
                skippedRows += 1
            }
        }

        guard !meetings.isEmpty else {
            throw GranolaCSVImportError.noImportableMeetings
        }
        return GranolaCSVParseResult(meetings: meetings, skippedRows: skippedRows)
    }

    @MainActor
    static func importMeetings(
        _ parsed: GranolaCSVParseResult,
        into modelContext: ModelContext,
        defaultLanguage: String
    ) throws -> GranolaCSVImportResult {
        let existingMeetings = try modelContext.fetch(FetchDescriptor<Meeting>())
        var knownIDs = Set(
            existingMeetings.compactMap { meeting -> String? in
                guard meeting.externalSource == sourceIdentifier else { return nil }
                return meeting.externalID
            }
        )
        var imported = 0
        var duplicates = 0

        for record in parsed.meetings {
            guard knownIDs.insert(record.externalID).inserted else {
                duplicates += 1
                continue
            }

            let meeting = makeMeeting(from: record, defaultLanguage: defaultLanguage)
            modelContext.insert(meeting)
            imported += 1
        }

        if imported > 0 {
            try modelContext.save()
        }
        return GranolaCSVImportResult(
            imported: imported,
            duplicates: duplicates,
            skippedRows: parsed.skippedRows
        )
    }

    @MainActor
    private static func makeMeeting(from record: GranolaImportedMeeting, defaultLanguage: String) -> Meeting {
        var remoteSpeakerIDs: [String: Int] = [:]
        var nextRemoteSpeakerID = 0
        var speakerNames: [String: String] = [:]
        var selfSpeakerIDs: Set<Int> = []
        let duration = max(0, record.endTime.timeIntervalSince(record.startTime))

        let segments = record.transcript.enumerated().map { index, turn in
            let speakerID: Int
            if turn.isSelf {
                speakerID = DeepgramService.micSpeakerID
                selfSpeakerIDs.insert(speakerID)
            } else if let existing = remoteSpeakerIDs[turn.speakerKey] {
                speakerID = existing
            } else {
                speakerID = nextRemoteSpeakerID
                remoteSpeakerIDs[turn.speakerKey] = speakerID
                nextRemoteSpeakerID += 1
            }

            if !turn.isSelf,
               let name = turn.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty,
               !isGenericSpeakerName(name) {
                speakerNames[String(speakerID)] = name
            }

            let timestamp: TimeInterval
            if let relative = turn.relativeTimestamp {
                timestamp = max(0, relative)
            } else if let absolute = turn.absoluteTimestamp {
                timestamp = max(0, absolute.timeIntervalSince(record.startTime))
            } else if duration > 0, record.transcript.count > 1 {
                timestamp = duration * Double(index) / Double(record.transcript.count - 1)
            } else {
                timestamp = Double(index)
            }

            return TranscriptSegment(
                text: turn.text,
                speaker: speakerID,
                timestamp: timestamp,
                isFinal: true,
                confidence: 1
            )
        }

        let meeting = Meeting(
            title: record.title,
            startTime: record.startTime,
            endTime: record.endTime,
            segments: segments,
            summaryText: record.summary,
            notes: record.notes
        )
        meeting.language = defaultLanguage
        meeting.externalSource = sourceIdentifier
        meeting.externalID = record.externalID
        meeting.externalURL = record.sourceURL
        meeting.importedAt = Date()
        meeting.calendarEventId = record.calendarEventID
        meeting.speakerNames = speakerNames
        meeting.selfSpeakerIDs = selfSpeakerIDs
        meeting.attendees = record.attendees.map { attendee in
            MeetingAttendee(
                email: attendee.email,
                displayName: attendee.name,
                domain: emailDomain(attendee.email),
                responseStatus: "unknown",
                isOrganizer: attendee.isOrganizer,
                isSelf: attendee.isSelf
            )
        }
        return meeting
    }

    private static func importedMeeting(from row: [String], headers: [String]) -> GranolaImportedMeeting? {
        let title = value(in: row, headers: headers, aliases: titleHeaders)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptText = value(in: row, headers: headers, aliases: transcriptHeaders)
        let transcript = parseTranscript(transcriptText)
        let rowStart = parseDate(value(in: row, headers: headers, aliases: startHeaders))
        let firstTranscriptDate = transcript.compactMap(\.absoluteTimestamp).min()
        guard let startTime = rowStart ?? firstTranscriptDate else { return nil }

        let rowEnd = parseDate(value(in: row, headers: headers, aliases: endHeaders))
        let lastTranscriptDate = transcript.compactMap(\.absoluteTimestamp).max()
        let lastRelativeTimestamp = transcript.compactMap(\.relativeTimestamp).max()
        let endTime = max(
            startTime,
            rowEnd ?? lastTranscriptDate ?? lastRelativeTimestamp.map { startTime.addingTimeInterval($0) } ?? startTime
        )
        let summary = nilIfEmpty(value(in: row, headers: headers, aliases: summaryHeaders))
        let notes = value(in: row, headers: headers, aliases: notesHeaders)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceURL = nilIfEmpty(value(in: row, headers: headers, aliases: urlHeaders))
        let rawID = nilIfEmpty(value(in: row, headers: headers, aliases: idHeaders))
        let externalID = rawID ?? sourceURL ?? stableCSVIdentifier(
            title: title,
            startTime: startTime,
            transcript: transcriptText
        )
        let ownerEmail = extractEmail(value(in: row, headers: headers, aliases: ownerEmailHeaders))
        let organizerEmail = extractEmail(value(in: row, headers: headers, aliases: organizerHeaders))
        let attendees = parseAttendees(
            value(in: row, headers: headers, aliases: attendeeHeaders),
            ownerEmail: ownerEmail,
            organizerEmail: organizerEmail
        )

        return GranolaImportedMeeting(
            externalID: externalID,
            title: title.isEmpty ? "untitled" : title,
            startTime: startTime,
            endTime: endTime,
            summary: summary,
            notes: notes,
            transcript: transcript,
            attendees: attendees,
            calendarEventID: nilIfEmpty(value(in: row, headers: headers, aliases: calendarIDHeaders)),
            sourceURL: sourceURL
        )
    }

    private static func parseCSVRows(_ text: String) throws -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = 0

        func finishField() {
            row.append(field)
            field = ""
        }

        func finishRow() {
            finishField()
            rows.append(row)
            row = []
        }

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isQuoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 2
                    continue
                }
                isQuoted.toggle()
            } else if character == ",", !isQuoted {
                finishField()
            } else if (character == "\n" || character == "\r"), !isQuoted {
                finishRow()
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
            } else {
                field.append(character)
            }
            index += 1
        }

        guard !isQuoted else { throw GranolaCSVImportError.malformedCSV }
        if !field.isEmpty || !row.isEmpty {
            finishRow()
        }
        while rows.last?.allSatisfy({ $0.isEmpty }) == true {
            rows.removeLast()
        }
        return rows
    }

    private static func parseTranscript(_ rawValue: String) -> [GranolaImportedTranscriptTurn] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let jsonTurns = parseJSONTranscript(trimmed), !jsonTurns.isEmpty {
            return jsonTurns
        }

        var turns: [GranolaImportedTranscriptTurn] = []
        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let timestampResult = extractLeadingTimestamp(from: line)
            let remainder = timestampResult.remainder
            if let speakerSplit = splitSpeakerPrefix(remainder) {
                let speaker = speakerMetadata(from: speakerSplit.speaker)
                turns.append(GranolaImportedTranscriptTurn(
                    text: speakerSplit.text,
                    speakerKey: speaker.key,
                    speakerName: speaker.name,
                    isSelf: speaker.isSelf,
                    relativeTimestamp: timestampResult.timestamp,
                    absoluteTimestamp: nil
                ))
            } else if let last = turns.popLast() {
                turns.append(GranolaImportedTranscriptTurn(
                    text: last.text + " " + remainder,
                    speakerKey: last.speakerKey,
                    speakerName: last.speakerName,
                    isSelf: last.isSelf,
                    relativeTimestamp: last.relativeTimestamp ?? timestampResult.timestamp,
                    absoluteTimestamp: last.absoluteTimestamp
                ))
            } else {
                turns.append(GranolaImportedTranscriptTurn(
                    text: remainder,
                    speakerKey: "unknown",
                    speakerName: nil,
                    isSelf: false,
                    relativeTimestamp: timestampResult.timestamp,
                    absoluteTimestamp: nil
                ))
            }
        }
        return turns.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func parseJSONTranscript(_ text: String) -> [GranolaImportedTranscriptTurn]? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return nil }

        let rawItems: [Any]
        if let items = root as? [Any] {
            rawItems = items
        } else if let object = root as? [String: Any], let items = object["transcript"] as? [Any] {
            rawItems = items
        } else {
            return nil
        }

        return rawItems.compactMap { item in
            guard let object = item as? [String: Any],
                  let text = stringValue(object, keys: ["text", "transcript", "content"]),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

            let speakerObject = object["speaker"] as? [String: Any]
            let rawSpeaker = speakerObject.flatMap {
                stringValue($0, keys: ["diarization_label", "name", "attribution", "source"])
            } ?? stringValue(object, keys: ["speaker_name", "speaker", "source"]) ?? "unknown"
            var speaker = speakerMetadata(from: rawSpeaker)
            if let attribution = speakerObject.flatMap({ stringValue($0, keys: ["attribution"]) }) {
                speaker.isSelf = attribution.lowercased() == "me"
            }
            if let name = speakerObject.flatMap({ stringValue($0, keys: ["name"]) }), !name.isEmpty {
                speaker.name = name
            }
            if let label = speakerObject.flatMap({ stringValue($0, keys: ["diarization_label"]) }), !label.isEmpty {
                speaker.key = label.lowercased()
            }
            if speakerObject.flatMap({ stringValue($0, keys: ["source"]) })?.lowercased() == "microphone",
               speakerObject?["diarization_label"] == nil,
               speakerObject?["name"] == nil,
               speakerObject?["attribution"] == nil {
                speaker.isSelf = true
            }

            let timestampValue = value(object, keys: ["start_time", "start_timestamp", "startTime", "timestamp"])
            let parsedTimestamp = parseTranscriptTimestamp(timestampValue)
            return GranolaImportedTranscriptTurn(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                speakerKey: speaker.key,
                speakerName: speaker.name,
                isSelf: speaker.isSelf,
                relativeTimestamp: parsedTimestamp.relative,
                absoluteTimestamp: parsedTimestamp.absolute
            )
        }
    }

    private static func extractLeadingTimestamp(from line: String) -> (timestamp: TimeInterval?, remainder: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "[", let closing = trimmed.firstIndex(of: "]") {
            let timecode = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closing])
            if let timestamp = parseTimecode(timecode) {
                return (timestamp, String(trimmed[trimmed.index(after: closing)...]).trimmingCharacters(in: .whitespaces))
            }
        }

        if let firstSpace = trimmed.firstIndex(where: { $0.isWhitespace }) {
            let timecode = String(trimmed[..<firstSpace]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            if let timestamp = parseTimecode(timecode) {
                return (timestamp, String(trimmed[firstSpace...]).trimmingCharacters(in: .whitespaces))
            }
        }
        return (nil, trimmed)
    }

    private static func parseTimecode(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    private static func splitSpeakerPrefix(_ line: String) -> (speaker: String, text: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let speaker = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        let text = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, isPlausibleSpeaker(speaker) else { return nil }
        return (speaker, text)
    }

    private static func isPlausibleSpeaker(_ value: String) -> Bool {
        let words = value.split(whereSeparator: { $0.isWhitespace })
        guard !value.isEmpty, value.count <= 60, words.count <= 6 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) ||
            CharacterSet.whitespaces.contains($0) || "-_'.".unicodeScalars.contains($0)
        }
    }

    private static func speakerMetadata(from rawValue: String) -> (key: String, name: String?, isSelf: Bool) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = value.lowercased()
        let isSelf = ["me", "you", "myself", "microphone"].contains(lowered)
        let generic = isGenericSpeakerName(value) || ["them", "speaker", "system", "unknown"].contains(lowered)
        return (lowered.isEmpty ? "unknown" : lowered, generic ? nil : value, isSelf)
    }

    private static func isGenericSpeakerName(_ value: String) -> Bool {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.range(of: #"^(speaker|participant)(\s+[a-z0-9]+)?$"#, options: .regularExpression) != nil ||
            ["me", "you", "myself", "them", "microphone", "system", "unknown"].contains(lowered)
    }

    private static func parseAttendees(
        _ rawValue: String,
        ownerEmail: String?,
        organizerEmail: String?
    ) -> [GranolaImportedAttendee] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var pairs: [(String?, String)] = []

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let items = json as? [Any] {
            for item in items {
                if let object = item as? [String: Any],
                   let email = stringValue(object, keys: ["email", "emailAddress", "address"]) {
                    pairs.append((stringValue(object, keys: ["name", "displayName"]), email))
                } else if let value = item as? String, let email = extractEmail(value) {
                    pairs.append((extractName(value), email))
                }
            }
        } else {
            for item in trimmed.components(separatedBy: CharacterSet(charactersIn: ";\n")) {
                guard let email = extractEmail(item) else { continue }
                pairs.append((extractName(item), email))
            }
            if pairs.isEmpty {
                let emails = trimmed.matches(of: /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/.ignoresCase())
                    .map { String($0.output) }
                pairs = emails.map { (nil, $0) }
            }
        }

        var seen: Set<String> = []
        return pairs.compactMap { name, email in
            let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !cleanedEmail.isEmpty, seen.insert(cleanedEmail).inserted else { return nil }
            return GranolaImportedAttendee(
                name: nilIfEmpty(name ?? ""),
                email: cleanedEmail,
                isOrganizer: cleanedEmail == organizerEmail?.lowercased(),
                isSelf: cleanedEmail == ownerEmail?.lowercased()
            )
        }
    }

    private static func extractEmail(_ value: String) -> String? {
        value.firstMatch(of: /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/.ignoresCase()).map { String($0.output) }
    }

    private static func extractName(_ value: String) -> String? {
        guard let email = extractEmail(value), let range = value.range(of: email) else { return nil }
        let name = value[..<range.lowerBound]
            .trimmingCharacters(in: CharacterSet(charactersIn: " <>\"'"))
        return nilIfEmpty(name)
    }

    private static func parseDate(_ rawValue: String) -> Date? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let numeric = Double(value) {
            if numeric > 1_000_000_000_000 { return Date(timeIntervalSince1970: numeric / 1_000) }
            if numeric > 1_000_000_000 { return Date(timeIntervalSince1970: numeric) }
            if numeric > 20_000, numeric < 100_000 {
                return Calendar(identifier: .gregorian).date(
                    byAdding: .day,
                    value: Int(numeric),
                    to: Date(timeIntervalSince1970: -2_209_161_600)
                )
            }
        }

        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalISO.date(from: value) { return date }
        let standardISO = ISO8601DateFormatter()
        if let date = standardISO.date(from: value) { return date }

        for format in [
            "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd", "MMM d, yyyy h:mm a", "MMM d, yyyy, h:mm a",
            "MM/dd/yyyy h:mm a", "MM/dd/yyyy HH:mm", "dd/MM/yyyy HH:mm"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func parseTranscriptTimestamp(_ rawValue: Any?) -> (relative: TimeInterval?, absolute: Date?) {
        if let number = rawValue as? NSNumber {
            let value = number.doubleValue
            if value > 1_000_000_000_000 { return (nil, Date(timeIntervalSince1970: value / 1_000)) }
            if value > 1_000_000_000 { return (nil, Date(timeIntervalSince1970: value)) }
            return (value, nil)
        }
        if let string = rawValue as? String {
            if let date = parseDate(string), !string.contains(":") || string.contains("-") || string.contains("T") {
                return (nil, date)
            }
            if let timecode = parseTimecode(string) { return (timecode, nil) }
            if let numeric = Double(string) { return (numeric, nil) }
            if let date = parseDate(string) { return (nil, date) }
        }
        return (nil, nil)
    }

    private static func value(in row: [String], headers: [String], aliases: [String]) -> String {
        for alias in aliases {
            if let index = headers.firstIndex(of: alias), index < row.count {
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return ""
    }

    private static func value(_ object: [String: Any], keys: [String]) -> Any? {
        for key in keys where object[key] != nil { return object[key] }
        return nil
    }

    private static func stringValue(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private static func normalizeHeader(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stableCSVIdentifier(title: String, startTime: Date, transcript: String) -> String {
        let input = "\(title)|\(startTime.timeIntervalSince1970)|\(transcript)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "csv-%016llx", hash)
    }

    private static func emailDomain(_ email: String) -> String {
        guard let at = email.lastIndex(of: "@") else { return "" }
        return String(email[email.index(after: at)...]).lowercased()
    }
}
