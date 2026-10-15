import Foundation
import SwiftData

/// The wire form of a meeting for cloud sync (schema_version 1), shared with the backend and
/// the Linux client (`../miniti-api/docs/agents/08-cloud.md`). Pure functions over `Meeting`
/// and its segments: encode to JSON, apply a document to a model, and a cheap fingerprint the
/// engine uses to notice local edits without hashing the transcript.
///
/// JSON-string columns on `Meeting` (questions, doc topics, attendees, template) travel as
/// their decoded JSON so no field is re-modelled here; fields another client sends that this
/// build does not know are kept in `syncExtraJSON` and echoed back.
enum MeetingSyncDocument {
    static let schemaVersion = 1

    /// Keys this build owns. Anything else in an incoming document is kept as "extra" and
    /// echoed back, `created_at` among them (Linux sets it; this build fills it from the start
    /// time only when absent).
    static let knownKeys: Set<String> = [
        "schema_version", "id", "title", "calendar_event_title", "start_time", "end_time", "updated_at",
        "language", "pinned", "transcript_revision", "transcript_edited_at", "segments", "speaker_names", "speaker_overrides",
        "self_speaker_ids", "summary", "action_items", "key_decisions", "topics", "discussion_flow", "notes", "insights_updated_at",
        "meddpicc", "questions", "doc_topics", "template", "external_source", "external_id", "external_url", "imported_at",
        "managed_session_id", "calendar_event_id", "attendees", "inferred_environment",
    ]

    // MARK: Dates

    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(_ date: Date?) -> Any {
        guard let date else { return NSNull() }
        return formatter.string(from: date)
    }

    static func orNull(_ value: String?) -> Any {
        value ?? NSNull()
    }

    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return formatter.date(from: s) ?? plainFormatter.date(from: s)
    }

    // MARK: Encode

    /// The document for `meeting`. `segments` are passed explicitly so callers decide what
    /// they load; pass `meeting.segments` for the saved meeting.
    static func encode(_ meeting: Meeting, segments: [TranscriptSegment]) -> [String: Any] {
        var doc: [String: Any] = extras(from: meeting)
        doc["schema_version"] = schemaVersion
        doc["id"] = meeting.id.uuidString.lowercased()
        doc["title"] = meeting.title
        doc["calendar_event_title"] = orNull(meeting.calendarEventTitle)
        doc["start_time"] = string(meeting.startTime)
        doc["end_time"] = string(meeting.endTime)
        if doc["created_at"] == nil { doc["created_at"] = string(meeting.startTime) }
        doc["updated_at"] = string(meeting.updatedAt ?? fallbackUpdatedAt(meeting))
        doc["language"] = meeting.language
        doc["pinned"] = meeting.isPinned
        doc["transcript_revision"] = meeting.transcriptRevision
        doc["transcript_edited_at"] = string(meeting.transcriptEditedAt)
        doc["segments"] = segments
            .sorted { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }
            .map { segment -> [String: Any] in
                var s: [String: Any] = [:]
                s["id"] = segment.id.uuidString.lowercased()
                s["speaker"] = segment.speaker
                s["text"] = segment.text
                s["start"] = segment.timestamp
                s["final"] = segment.isFinal
                s["confidence"] = segment.confidence
                s["source"] = orNull(segment.sourceRaw)
                return s
            }
        doc["speaker_names"] = meeting.speakerNames
        doc["speaker_overrides"] = Array(meeting.speakerOverrides).sorted()
        doc["self_speaker_ids"] = Array(meeting.selfSpeakerIDs).sorted()
        doc["summary"] = orNull(meeting.summaryText)
        doc["action_items"] = meeting.actionItems
        doc["key_decisions"] = meeting.keyDecisions
        doc["topics"] = meeting.topics
        doc["discussion_flow"] = meeting.discussionFlow
        doc["notes"] = meeting.notes
        doc["insights_updated_at"] = string(meeting.insightsUpdatedAt)
        var meddpicc: [String: Any] = [:]
        meddpicc["metrics"] = orNull(meeting.meddpiccMetrics)
        meddpicc["economic_buyer"] = orNull(meeting.meddpiccEconomicBuyer)
        meddpicc["decision_criteria"] = orNull(meeting.meddpiccDecisionCriteria)
        meddpicc["decision_process"] = orNull(meeting.meddpiccDecisionProcess)
        meddpicc["paper_process"] = orNull(meeting.meddpiccPaperProcess)
        meddpicc["identified_pain"] = orNull(meeting.meddpiccIdentifiedPain)
        meddpicc["champion"] = orNull(meeting.meddpiccChampion)
        meddpicc["competition"] = orNull(meeting.meddpiccCompetition)
        doc["meddpicc"] = meddpicc
        doc["questions"] = jsonValue(meeting.suggestedQuestionsJSON) ?? []
        doc["doc_topics"] = jsonValue(meeting.docTopicsJSON) ?? []
        var template: [String: Any] = [:]
        template["id"] = orNull(meeting.insightTemplateID)
        template["definition"] = jsonValue(meeting.templateDefinitionJSON) ?? NSNull()
        template["sections"] = jsonValue(meeting.templateSectionsJSON) ?? [String: Any]()
        doc["template"] = template
        doc["external_source"] = orNull(meeting.externalSource)
        doc["external_id"] = orNull(meeting.externalID)
        doc["external_url"] = orNull(meeting.externalURL)
        doc["imported_at"] = string(meeting.importedAt)
        doc["managed_session_id"] = orNull(meeting.managedSessionId)
        doc["calendar_event_id"] = orNull(meeting.calendarEventId)
        doc["attendees"] = meeting.attendees.map { attendee -> [String: Any] in
            var a: [String: Any] = [:]
            a["email"] = attendee.email
            a["name"] = orNull(attendee.displayName)
            a["domain"] = attendee.domain
            a["response_status"] = attendee.responseStatus
            a["is_organizer"] = attendee.isOrganizer
            a["is_self"] = attendee.isSelf
            return a
        }
        doc["inferred_environment"] = orNull(meeting.inferredEnvironmentRaw)
        return doc
    }

    static func encodeData(_ meeting: Meeting, segments: [TranscriptSegment]) throws -> Data {
        try JSONSerialization.data(withJSONObject: encode(meeting, segments: segments), options: [.sortedKeys])
    }

    /// A meeting that predates the column: the latest of its own timestamps.
    static func fallbackUpdatedAt(_ meeting: Meeting) -> Date {
        [meeting.endTime, meeting.insightsUpdatedAt, meeting.transcriptEditedAt, meeting.importedAt]
            .compactMap { $0 }
            .reduce(meeting.startTime) { max($0, $1) }
    }

    private static func extras(from meeting: Meeting) -> [String: Any] {
        guard let json = meeting.syncExtraJSON, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private static func jsonValue(_ json: String?) -> Any? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func jsonString(_ value: Any?) -> String? {
        guard let value, !(value is NSNull), JSONSerialization.isValidJSONObject(value) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Decode

    struct Decoded {
        let id: UUID
        let updatedAt: Date
        let transcriptRevision: Int
        let endTime: Date?
        let segments: [[String: Any]]
        let document: [String: Any]
    }

    /// Validate the parts the engine needs before touching a model.
    static func decode(_ document: [String: Any]) -> Decoded? {
        guard let idString = document["id"] as? String, let id = UUID(uuidString: idString),
              let updatedAt = date(document["updated_at"]),
              date(document["start_time"]) != nil,
              // Only finished meetings sync; a document without an end would turn a saved
              // meeting into an "interrupted" one that the next launch tries to resume.
              let endTime = date(document["end_time"]),
              let segments = document["segments"] as? [[String: Any]] else { return nil }
        let revision = (document["transcript_revision"] as? NSNumber)?.intValue ?? 0
        return Decoded(id: id, updatedAt: updatedAt, transcriptRevision: revision, endTime: endTime, segments: segments, document: document)
    }

    /// Write every field of `document` onto `meeting`. Segments are replaced only when
    /// `replaceSegments` is true (the transcript revision moved or the meeting is new), so
    /// a rename or an insight update never recreates segment rows a view may hold.
    static func apply(_ decoded: Decoded, to meeting: Meeting, in context: ModelContext, replaceSegments: Bool) {
        let doc = decoded.document
        meeting.title = doc["title"] as? String ?? meeting.title
        meeting.calendarEventTitle = doc["calendar_event_title"] as? String
        if let start = date(doc["start_time"]) { meeting.startTime = start }
        meeting.endTime = decoded.endTime
        meeting.updatedAt = decoded.updatedAt
        meeting.language = doc["language"] as? String ?? meeting.language
        meeting.isPinned = doc["pinned"] as? Bool ?? false
        meeting.transcriptRevision = decoded.transcriptRevision
        meeting.transcriptEditedAt = date(doc["transcript_edited_at"])
        if let names = doc["speaker_names"] as? [String: String] { meeting.speakerNames = names } else { meeting.speakerNames = [:] }
        meeting.speakerOverrides = Set((doc["speaker_overrides"] as? [String]) ?? [])
        meeting.selfSpeakerIDs = Set(((doc["self_speaker_ids"] as? [NSNumber]) ?? []).map(\.intValue))
        meeting.summaryText = doc["summary"] as? String
        meeting.actionItems = doc["action_items"] as? [String] ?? []
        meeting.keyDecisions = doc["key_decisions"] as? [String] ?? []
        meeting.topics = doc["topics"] as? [String] ?? []
        meeting.discussionFlow = doc["discussion_flow"] as? [String] ?? []
        meeting.notes = doc["notes"] as? String ?? ""
        meeting.insightsUpdatedAt = date(doc["insights_updated_at"])
        let meddpicc = doc["meddpicc"] as? [String: Any] ?? [:]
        meeting.meddpiccMetrics = meddpicc["metrics"] as? String
        meeting.meddpiccEconomicBuyer = meddpicc["economic_buyer"] as? String
        meeting.meddpiccDecisionCriteria = meddpicc["decision_criteria"] as? String
        meeting.meddpiccDecisionProcess = meddpicc["decision_process"] as? String
        meeting.meddpiccPaperProcess = meddpicc["paper_process"] as? String
        meeting.meddpiccIdentifiedPain = meddpicc["identified_pain"] as? String
        meeting.meddpiccChampion = meddpicc["champion"] as? String
        meeting.meddpiccCompetition = meddpicc["competition"] as? String
        meeting.suggestedQuestionsJSON = (doc["questions"] as? [Any]).flatMap { $0.isEmpty ? nil : jsonString($0) }
        meeting.docTopicsJSON = (doc["doc_topics"] as? [Any]).flatMap { $0.isEmpty ? nil : jsonString($0) }
        let template = doc["template"] as? [String: Any] ?? [:]
        meeting.insightTemplateID = template["id"] as? String
        meeting.templateDefinitionJSON = jsonString(template["definition"])
        meeting.templateSectionsJSON = (template["sections"] as? [String: Any]).flatMap { $0.isEmpty ? nil : jsonString($0) }
        meeting.externalSource = doc["external_source"] as? String
        meeting.externalID = doc["external_id"] as? String
        meeting.externalURL = doc["external_url"] as? String
        meeting.importedAt = date(doc["imported_at"])
        meeting.managedSessionId = doc["managed_session_id"] as? String
        meeting.calendarEventId = doc["calendar_event_id"] as? String
        meeting.attendees = ((doc["attendees"] as? [[String: Any]]) ?? []).compactMap { a in
            guard let email = a["email"] as? String else { return nil }
            return MeetingAttendee(
                email: email,
                displayName: a["name"] as? String,
                domain: a["domain"] as? String ?? "",
                responseStatus: a["response_status"] as? String ?? "unknown",
                isOrganizer: a["is_organizer"] as? Bool ?? false,
                isSelf: a["is_self"] as? Bool ?? false
            )
        }
        meeting.inferredEnvironmentRaw = doc["inferred_environment"] as? String
        var extra = doc.filter { !knownKeys.contains($0.key) }
        // Our own documents carry created_at equal to the start time; only another client's
        // distinct value is worth echoing.
        if let created = extra["created_at"] as? String, created == formatter.string(from: meeting.startTime) { extra.removeValue(forKey: "created_at") }
        meeting.syncExtraJSON = extra.isEmpty ? nil : jsonString(extra)

        if replaceSegments { applyTranscript(decoded, to: meeting, in: context) }
    }

    /// Replace the transcript by id: rows that still exist are updated in place (a History
    /// view holding them keeps valid objects), rows the document dropped are deleted, new
    /// ones inserted. Also sets the transcript revision and edit time.
    static func applyTranscript(_ decoded: Decoded, to meeting: Meeting, in context: ModelContext) {
        var existing: [UUID: TranscriptSegment] = [:]
        for segment in meeting.segments { existing[segment.id] = segment }
        var kept: Set<UUID> = []
        var result: [TranscriptSegment] = []
        for s in decoded.segments {
            guard let text = s["text"] as? String, let speaker = (s["speaker"] as? NSNumber)?.intValue,
                  let start = (s["start"] as? NSNumber)?.doubleValue else { continue }
            let id = (s["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            let isFinal = s["final"] as? Bool ?? true
            let confidence = (s["confidence"] as? NSNumber)?.doubleValue ?? 1.0
            let source = s["source"] as? String
            if let current = existing[id], !kept.contains(id) {
                if current.text != text { current.text = text }
                if current.speaker != speaker { current.speaker = speaker }
                if current.timestamp != start { current.timestamp = start }
                if current.isFinal != isFinal { current.isFinal = isFinal }
                if current.confidence != confidence { current.confidence = confidence }
                if current.sourceRaw != source { current.sourceRaw = source }
                kept.insert(id)
                result.append(current)
            } else {
                result.append(TranscriptSegment(id: id, text: text, speaker: speaker, timestamp: start, isFinal: isFinal, confidence: confidence, sourceRaw: source))
            }
        }
        for (id, segment) in existing where !kept.contains(id) { context.delete(segment) }
        meeting.segments = result
        meeting.transcriptRevision = decoded.transcriptRevision
        meeting.transcriptEditedAt = date(decoded.document["transcript_edited_at"])
    }

    /// A new local meeting from a cloud document.
    static func makeMeeting(_ decoded: Decoded, in context: ModelContext) -> Meeting {
        let meeting = Meeting(id: decoded.id, title: decoded.document["title"] as? String ?? "new", startTime: date(decoded.document["start_time"]) ?? Date())
        context.insert(meeting)
        apply(decoded, to: meeting, in: context, replaceSegments: true)
        return meeting
    }

    // MARK: Fingerprint

    /// Cheap change detector over everything that syncs except the transcript text, which is
    /// covered by `transcriptRevision` (trims and corrections bump it) and the segment count
    /// is not consulted so the relation is never loaded for an untouched meeting.
    static func fingerprint(of meeting: Meeting) -> String {
        var parts: [String] = []
        parts.append(meeting.title)
        parts.append(meeting.calendarEventTitle ?? "")
        parts.append(String(meeting.startTime.timeIntervalSince1970))
        parts.append(meeting.endTime.map { String($0.timeIntervalSince1970) } ?? "")
        parts.append(meeting.language)
        parts.append(meeting.isPinned ? "1" : "0")
        parts.append(String(meeting.transcriptRevision))
        parts.append(meeting.transcriptEditedAt.map { String($0.timeIntervalSince1970) } ?? "")
        parts.append(canonical(meeting.speakerNamesJSON))
        parts.append(Array(meeting.speakerOverrides).sorted().joined(separator: ","))
        parts.append(Array(meeting.selfSpeakerIDs).sorted().map(String.init).joined(separator: ","))
        parts.append(meeting.summaryText ?? "")
        parts.append(meeting.actionItems.joined(separator: "\u{1F}"))
        parts.append(meeting.keyDecisions.joined(separator: "\u{1F}"))
        parts.append(meeting.topics.joined(separator: "\u{1F}"))
        parts.append(meeting.discussionFlow.joined(separator: "\u{1F}"))
        parts.append(meeting.notes)
        parts.append(meeting.insightsUpdatedAt.map { String($0.timeIntervalSince1970) } ?? "")
        parts.append([meeting.meddpiccMetrics, meeting.meddpiccEconomicBuyer, meeting.meddpiccDecisionCriteria, meeting.meddpiccDecisionProcess,
                      meeting.meddpiccPaperProcess, meeting.meddpiccIdentifiedPain, meeting.meddpiccChampion, meeting.meddpiccCompetition]
            .map { $0 ?? "" }.joined(separator: "\u{1F}"))
        parts.append(canonical(meeting.suggestedQuestionsJSON))
        parts.append(canonical(meeting.docTopicsJSON))
        parts.append(meeting.insightTemplateID ?? "")
        parts.append(canonical(meeting.templateDefinitionJSON))
        parts.append(canonical(meeting.templateSectionsJSON))
        parts.append(meeting.externalSource ?? "")
        parts.append(meeting.externalID ?? "")
        parts.append(meeting.externalURL ?? "")
        parts.append(meeting.managedSessionId ?? "")
        parts.append(meeting.calendarEventId ?? "")
        parts.append(canonical(meeting.attendeesJSON))
        parts.append(meeting.inferredEnvironmentRaw ?? "")
        parts.append(canonical(meeting.syncExtraJSON))
        return fnv1a(parts.joined(separator: "\u{1E}"))
    }

    /// JSON-string columns are rewritten by their setters with whatever key order the
    /// dictionary had, so the fingerprint hashes a sorted-keys form, never the raw string.
    static func canonical(_ json: String?) -> String {
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              JSONSerialization.isValidJSONObject(object),
              let sorted = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: sorted, encoding: .utf8) else { return json ?? "" }
        return text
    }

    static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
