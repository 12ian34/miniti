import Foundation
import SwiftData

@Model
final class Meeting {
    var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date?
    @Relationship(deleteRule: .cascade) var segments: [TranscriptSegment]
    var summaryText: String?
    var actionItems: [String]
    var keyDecisions: [String]
    var topics: [String]
    var discussionFlow: [String] = []
    var notes: String = ""
    
    var managedSessionId: String?
    var language: String = "en"
    
    var calendarEventId: String?
    var attendeesJSON: String?
    
    // MEDDPICC fields
    var meddpiccMetrics: String?
    var meddpiccEconomicBuyer: String?
    var meddpiccDecisionCriteria: String?
    var meddpiccDecisionProcess: String?
    var meddpiccPaperProcess: String?
    var meddpiccIdentifiedPain: String?
    var meddpiccChampion: String?
    var meddpiccCompetition: String?
    
    // Suggested questions (JSON-encoded [SuggestedQuestion])
    var suggestedQuestionsJSON: String?

    // Inferred speaker names (JSON-encoded [String: String] where key is speaker ID as string)
    var speakerNamesJSON: String?

    // Speaker IDs (as strings) that the user has manually named/overridden.
    // Present entries — even if the name is the same as the inference — are excluded
    // from automatic inference merges. JSON-encoded [String] for backward compat.
    var speakerOverridesJSON: String?

    // Legacy single-speaker "self" marker. Kept for SwiftData backward compat with meetings
    // saved before multi-self support landed. New code should read/write `selfSpeakerIDs`.
    var selfSpeakerID: Int?

    // All speaker IDs the user has marked as themselves ("You"). JSON-encoded [Int].
    // Supports the case where diarization splits one person across multiple speaker IDs —
    // marking each of those IDs as "You" unifies their training stats and transcript label.
    var selfSpeakerIDsJSON: String?
    
    init(
        id: UUID = UUID(),
        title: String = "new",
        startTime: Date = Date(),
        endTime: Date? = nil,
        segments: [TranscriptSegment] = [],
        summaryText: String? = nil,
        actionItems: [String] = [],
        keyDecisions: [String] = [],
        topics: [String] = [],
        discussionFlow: [String] = [],
        notes: String = "",
        meddpiccMetrics: String? = nil,
        meddpiccEconomicBuyer: String? = nil,
        meddpiccDecisionCriteria: String? = nil,
        meddpiccDecisionProcess: String? = nil,
        meddpiccPaperProcess: String? = nil,
        meddpiccIdentifiedPain: String? = nil,
        meddpiccChampion: String? = nil,
        meddpiccCompetition: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.segments = segments
        self.summaryText = summaryText
        self.actionItems = actionItems
        self.keyDecisions = keyDecisions
        self.topics = topics
        self.discussionFlow = discussionFlow
        self.notes = notes
        self.meddpiccMetrics = meddpiccMetrics
        self.meddpiccEconomicBuyer = meddpiccEconomicBuyer
        self.meddpiccDecisionCriteria = meddpiccDecisionCriteria
        self.meddpiccDecisionProcess = meddpiccDecisionProcess
        self.meddpiccPaperProcess = meddpiccPaperProcess
        self.meddpiccIdentifiedPain = meddpiccIdentifiedPain
        self.meddpiccChampion = meddpiccChampion
        self.meddpiccCompetition = meddpiccCompetition
    }
    
    var suggestedQuestions: [SuggestedQuestion] {
        get {
            guard let json = suggestedQuestionsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([SuggestedQuestion].self, from: data)) ?? []
        }
        set {
            suggestedQuestionsJSON = newValue.isEmpty ? nil : (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8))
        }
    }
    
    var hasQuestions: Bool {
        !suggestedQuestions.isEmpty
    }

    var speakerNames: [String: String] {
        get {
            guard let json = speakerNamesJSON, let data = json.data(using: .utf8) else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            let cleaned = newValue.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if cleaned.isEmpty {
                speakerNamesJSON = nil
                return
            }
            // On encode failure, preserve the existing JSON rather than clobbering it to nil.
            if let data = try? JSONEncoder().encode(cleaned),
               let str = String(data: data, encoding: .utf8) {
                speakerNamesJSON = str
            }
        }
    }

    var hasSpeakerNames: Bool {
        !speakerNames.isEmpty
    }

    var speakerOverrides: Set<String> {
        get {
            guard let json = speakerOverridesJSON, let data = json.data(using: .utf8) else { return [] }
            return Set((try? JSONDecoder().decode([String].self, from: data)) ?? [])
        }
        set {
            if newValue.isEmpty {
                speakerOverridesJSON = nil
                return
            }
            // On encode failure, preserve the existing JSON rather than clobbering it.
            if let data = try? JSONEncoder().encode(Array(newValue).sorted()),
               let str = String(data: data, encoding: .utf8) {
                speakerOverridesJSON = str
            }
        }
    }

    /// Set or clear a user-controlled speaker name. Pass a non-empty name to set + mark as overridden.
    /// Pass `nil` or whitespace to clear the override — future automatic inference can then refill it.
    func setSpeakerName(id: String, name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var names = speakerNames
        var overrides = speakerOverrides
        if trimmed.isEmpty {
            names.removeValue(forKey: id)
            overrides.remove(id)
        } else {
            names[id] = trimmed
            overrides.insert(id)
        }
        speakerNames = names
        speakerOverrides = overrides
    }

    /// The explicit set of speaker IDs marked as the user. Empty = no explicit override;
    /// resolvers then fall back to the mic speaker on macOS. Reads merge the legacy
    /// `selfSpeakerID` column so meetings saved before multi-self still work.
    var selfSpeakerIDs: Set<Int> {
        get {
            var set: Set<Int> = []
            if let json = selfSpeakerIDsJSON, let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([Int].self, from: data) {
                set.formUnion(decoded)
            }
            if let legacy = selfSpeakerID { set.insert(legacy) }
            return set
        }
        set {
            if newValue.isEmpty {
                selfSpeakerIDsJSON = nil
                selfSpeakerID = nil
                return
            }
            if let data = try? JSONEncoder().encode(Array(newValue).sorted()),
               let str = String(data: data, encoding: .utf8) {
                selfSpeakerIDsJSON = str
                selfSpeakerID = newValue.sorted().first
            }
        }
    }

    /// Toggle whether a speaker is marked as the user. When marking as self, also clears any
    /// inferred/custom name for that ID so the resolver returns "You" unambiguously.
    func setSelfSpeaker(id: Int, isSelf: Bool) {
        var set = selfSpeakerIDs
        if isSelf {
            if set.isEmpty { set = effectiveSelfSpeakerIDs }
            set.insert(id)
        } else {
            set.remove(id)
        }
        selfSpeakerIDs = set

        if isSelf {
            let key = String(id)
            var names = speakerNames
            var overrides = speakerOverrides
            if names.removeValue(forKey: key) != nil { speakerNames = names }
            if overrides.remove(key) != nil { speakerOverrides = overrides }
        }
    }

    /// Effective "self" set used by resolvers and training metrics. If the user hasn't
    /// marked anyone, we fall back to the mic speaker — keeping macOS working out of the box.
    var effectiveSelfSpeakerIDs: Set<Int> {
        let explicit = selfSpeakerIDs
        return explicit.isEmpty ? [DeepgramService.micSpeakerID] : explicit
    }
    
    var hasMEDDPICC: Bool {
        hasValidValue(meddpiccMetrics) || hasValidValue(meddpiccEconomicBuyer) || 
        hasValidValue(meddpiccDecisionCriteria) || hasValidValue(meddpiccDecisionProcess) ||
        hasValidValue(meddpiccPaperProcess) || hasValidValue(meddpiccIdentifiedPain) ||
        hasValidValue(meddpiccChampion) || hasValidValue(meddpiccCompetition)
    }
    
    private func hasValidValue(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !trimmed.isEmpty && trimmed != "null" && trimmed != "n/a" && trimmed != "none"
    }
    
    private static nonisolated(unsafe) let timestampPattern = /^\d{8}-\d{6}$/

    var displayTitle: String {
        for separator in [" - ", " — "] {
            if let range = title.range(of: separator) {
                let prefix = String(title[..<range.lowerBound])
                guard prefix.wholeMatch(of: Self.timestampPattern) != nil else { continue }
                let suffix = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !suffix.isEmpty { return suffix }
                return "untitled"
            }
        }
        if title.wholeMatch(of: Self.timestampPattern) != nil { return "untitled" }
        return title
    }

    var duration: TimeInterval? {
        guard let endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    var formattedDuration: String {
        guard let duration else { return "In progress" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    var fullTranscript: String {
        let names = speakerNames
        let selfIDs = selfSpeakerIDs
        return segments
            .filter { $0.isFinal }
            .sorted { $0.timestamp < $1.timestamp }
            .map { segment in
                let speaker = resolvedSpeakerLabel(for: segment.speaker, names: names, selfIDs: selfIDs)
                return "[\(speaker)] \(segment.text)"
            }
            .joined(separator: "\n")
    }
    
    var hasInsights: Bool {
        summaryText != nil || !actionItems.isEmpty || !keyDecisions.isEmpty
    }
    
    // MARK: - Markdown Export
    
    func transcriptAsMarkdown() -> String {
        var md = "## Transcript\n\n"

        let sortedSegments = segments.filter { $0.isFinal }.sorted { $0.timestamp < $1.timestamp }
        let names = speakerNames
        let selfIDs = selfSpeakerIDs

        var currentKey: String? = nil
        for segment in sortedSegments {
            let key = SelectableAttributed.displayGroupKey(speaker: segment.speaker, names: names, selfIDs: selfIDs)
            if key != currentKey {
                currentKey = key
                let label = resolvedSpeakerLabel(for: segment.speaker, names: names, selfIDs: selfIDs)
                md += "\n**\(label):**\n"
            }
            md += "\(segment.text) "
        }

        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func notesAsMarkdown() -> String {
        if notes.isEmpty {
            return ""
        }
        return "## Notes\n\n\(notes)"
    }
    
    func insightsAsMarkdown() -> String {
        var md = "## Insights\n\n"
        
        if let summary = summaryText, !summary.isEmpty {
            md += "### Summary\n\n\(summary)\n\n"
        }
        
        if !discussionFlow.isEmpty {
            md += "### Discussion Flow\n\n"
            for (index, item) in discussionFlow.enumerated() {
                md += "\(index + 1). \(item)\n"
            }
            md += "\n"
        }
        
        if !actionItems.isEmpty {
            md += "### Action Items\n\n"
            for item in actionItems {
                md += "- [ ] \(item)\n"
            }
            md += "\n"
        }
        
        if !topics.isEmpty {
            md += "### Topics\n\n"
            for topic in topics {
                md += "- \(topic)\n"
            }
            md += "\n"
        }
        
        // Suggested questions if available
        if hasQuestions {
            md += "### Suggested Questions\n\n"
            for q in suggestedQuestions {
                md += "- **\(q.question)**\n  _\(q.context)_\n"
            }
            md += "\n"
        }
        
        // MEDDPICC if available
        if hasMEDDPICC {
            let meddpiccFields: [(String, String?)] = [
                ("Metrics", meddpiccMetrics),
                ("Economic Buyer", meddpiccEconomicBuyer),
                ("Decision Criteria", meddpiccDecisionCriteria),
                ("Decision Process", meddpiccDecisionProcess),
                ("Paper Process", meddpiccPaperProcess),
                ("Identified Pain", meddpiccIdentifiedPain),
                ("Champion", meddpiccChampion),
                ("Competition", meddpiccCompetition)
            ]
            
            md += "### MEDDPICC\n\n"
            for (label, value) in meddpiccFields {
                if hasValidValue(value) {
                    md += "**\(label):** \(value!)\n\n"
                }
            }
        }
        
        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func trainingMetricsAsMarkdown() -> String {
        let duration = endTime?.timeIntervalSince(startTime) ?? 0
        guard duration > 0 else { return "" }

        let segments = self.segments.map {
            TrainingMetrics.Segment(text: $0.text, speaker: $0.speaker, isFinal: $0.isFinal, timestamp: $0.timestamp)
        }
        let metrics = TrainingMetrics.compute(
            from: segments,
            duration: duration,
            language: language,
            names: speakerNames,
            selfIDs: selfSpeakerIDs
        )
        guard !metrics.speakers.isEmpty else { return "" }

        var md = "## Training\n\n"
        md += "**Duration:** \(String(format: "%.1f", metrics.durationMinutes)) min"
        if let you = metrics.speakers.first(where: { $0.isLocalMic }) {
            let totalWords = metrics.speakers.reduce(0) { $0 + $1.wordCount }
            let ratio = totalWords > 0 ? Int(Double(you.wordCount) / Double(totalWords) * 100) : 0
            md += " | **Talk Ratio (You):** \(ratio)%"
        }
        md += "\n\n"

        for speaker in metrics.speakers {
            md += "### \(speaker.speakerLabel)\n"
            md += "- Pace: \(Int(speaker.wordsPerMinute)) wpm\n"
            md += "- Fillers: \(String(format: "%.1f", speaker.fillersPerMinute))/min"
            if !speaker.fillers.isEmpty {
                let top = speaker.fillers.prefix(5).map { "\($0.word): \($0.count)" }.joined(separator: ", ")
                md += " (\(top))"
            }
            md += "\n"
            md += "- Longest monologue: \(speaker.longestMonologueWords) words\n"
            md += "- Questions asked: \(speaker.questionsAsked)\n"
            md += "- Clarity: \(Int(speaker.avgWordsPerTurn)) words/turn\n\n"
        }

        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var attendees: [MeetingAttendee] {
        get {
            guard let json = attendeesJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([MeetingAttendee].self, from: data)) ?? []
        }
        set {
            attendeesJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? nil
        }
    }
    
    func fullMeetingAsMarkdown() -> String {
        var md = "# \(displayTitle)\n\n"
        md += "_\(startTime.formatted(date: .long, time: .shortened))_\n\n"
        md += "---\n\n"
        if !notes.isEmpty {
            md += notesAsMarkdown()
            md += "\n\n---\n\n"
        }
        md += insightsAsMarkdown()
        let training = trainingMetricsAsMarkdown()
        if !training.isEmpty {
            md += "\n\n---\n\n"
            md += training
        }
        md += "\n\n---\n\n"
        md += transcriptAsMarkdown()
        return md
    }
}

/// Resolve a display label for a speaker ID. Priority:
/// 1. Explicit user-marked self (`selfIDs` contains speaker) → "You" (wins over mapped name)
/// 2. Inferred/custom name from `names`
/// 3. Implicit default (mic speaker when `selfIDs` is nil/empty) → "You"
/// 4. "Speaker N" fallback
func resolvedSpeakerLabel(for speaker: Int, names: [String: String]? = nil, selfIDs: Set<Int>? = nil) -> String {
    if let selfIDs, selfIDs.contains(speaker) { return "You" }
    if let mapped = names?[String(speaker)]?.trimmingCharacters(in: .whitespacesAndNewlines), !mapped.isEmpty {
        return mapped
    }
    if (selfIDs ?? []).isEmpty, speaker == DeepgramService.micSpeakerID { return "You" }
    return "Speaker \(speaker + 1)"
}

/// Short variant used where horizontal space is tight (e.g. the live transcript gutter).
func resolvedShortSpeakerLabel(for speaker: Int, names: [String: String]? = nil, selfIDs: Set<Int>? = nil) -> String {
    if let selfIDs, selfIDs.contains(speaker) { return "You" }
    if let mapped = names?[String(speaker)]?.trimmingCharacters(in: .whitespacesAndNewlines), !mapped.isEmpty {
        return mapped
    }
    if (selfIDs ?? []).isEmpty, speaker == DeepgramService.micSpeakerID { return "You" }
    return "S\(speaker + 1)"
}

struct MeetingAttendee: Codable, Identifiable, Sendable {
    var id: String { email }
    let email: String
    let displayName: String?
    let domain: String
    let responseStatus: String
    let isOrganizer: Bool
    let isSelf: Bool
}

@Model
final class TranscriptSegment {
    var id: UUID
    var text: String
    var speaker: Int
    var timestamp: TimeInterval
    var isFinal: Bool
    var confidence: Double
    
    init(
        id: UUID = UUID(),
        text: String,
        speaker: Int = 0,
        timestamp: TimeInterval,
        isFinal: Bool = false,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.text = text
        self.speaker = speaker
        self.timestamp = timestamp
        self.isFinal = isFinal
        self.confidence = confidence
    }
    
    var speakerLabel: String {
        speaker == DeepgramService.micSpeakerID ? "You" : "Speaker \(speaker + 1)"
    }
    
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Meeting Search

struct MeetingSearchResult {
    let meeting: Meeting
    let score: Int
    let snippet: String?
    let matchCount: Int

    static func search(query: String, in meetings: [Meeting]) -> [MeetingSearchResult] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()

        return meetings.compactMap { meeting in
            var score = 0
            var totalMatches = 0
            var bestSnippet: String? = nil

            // Title (highest priority)
            let titleMatches = countOccurrences(of: q, in: meeting.title)
            if titleMatches > 0 {
                score += 100
                totalMatches += titleMatches
            }

            // Topics
            for topic in meeting.topics {
                let n = countOccurrences(of: q, in: topic)
                if n > 0 {
                    if score < 50 { score += 50 }
                    totalMatches += n
                    if bestSnippet == nil { bestSnippet = topic }
                }
            }

            // Notes
            let notesMatches = countOccurrences(of: q, in: meeting.notes)
            if notesMatches > 0 {
                score += 40
                totalMatches += notesMatches
                if bestSnippet == nil { bestSnippet = extractSnippet(from: meeting.notes, matching: q) }
            }

            // Summary
            if let summary = meeting.summaryText {
                let n = countOccurrences(of: q, in: summary)
                if n > 0 {
                    score += 30
                    totalMatches += n
                    if bestSnippet == nil { bestSnippet = extractSnippet(from: summary, matching: q) }
                }
            }

            // Action items
            for item in meeting.actionItems {
                let n = countOccurrences(of: q, in: item)
                if n > 0 {
                    if score < 25 { score += 25 }
                    totalMatches += n
                    if bestSnippet == nil { bestSnippet = extractSnippet(from: item, matching: q) }
                }
            }

            // Discussion flow
            for item in meeting.discussionFlow {
                let n = countOccurrences(of: q, in: item)
                if n > 0 {
                    if score < 25 { score += 25 }
                    totalMatches += n
                    if bestSnippet == nil { bestSnippet = extractSnippet(from: item, matching: q) }
                }
            }

            // MEDDPICC fields
            let meddpiccFields = [meeting.meddpiccMetrics, meeting.meddpiccEconomicBuyer,
                                  meeting.meddpiccDecisionCriteria, meeting.meddpiccDecisionProcess,
                                  meeting.meddpiccPaperProcess, meeting.meddpiccIdentifiedPain,
                                  meeting.meddpiccChampion, meeting.meddpiccCompetition]
            for field in meddpiccFields.compactMap({ $0 }) {
                let n = countOccurrences(of: q, in: field)
                if n > 0 {
                    if score < 20 { score += 20 }
                    totalMatches += n
                    if bestSnippet == nil { bestSnippet = extractSnippet(from: field, matching: q) }
                }
            }

            // Transcript (only for queries 3+ chars to avoid expensive scans)
            if q.count >= 3 {
                let transcriptText = meeting.segments.filter(\.isFinal).map(\.text).joined(separator: " ")
                let n = countOccurrences(of: q, in: transcriptText)
                if n > 0 {
                    score += 10
                    totalMatches += n
                    if bestSnippet == nil { bestSnippet = extractSnippet(from: transcriptText, matching: q) }
                }
            }

            guard score > 0 else { return nil }

            // Slight recency boost
            let daysSince = Date().timeIntervalSince(meeting.startTime) / 86400
            let recencyBoost = max(0, 10 - Int(daysSince))

            return MeetingSearchResult(meeting: meeting, score: score + recencyBoost, snippet: bestSnippet, matchCount: totalMatches)
        }
        .sorted { $0.score > $1.score }
    }

    private static func countOccurrences(of query: String, in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let lower = text.lowercased()
        var count = 0
        var searchStart = lower.startIndex
        while let range = lower.range(of: query, range: searchStart..<lower.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func extractSnippet(from text: String, matching query: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = clean.range(of: query, options: .caseInsensitive) else {
            return String(clean.prefix(80))
        }
        let matchStart = clean.distance(from: clean.startIndex, to: range.lowerBound)
        let contextStart = max(0, matchStart - 30)
        let startIdx = clean.index(clean.startIndex, offsetBy: contextStart)
        let endOffset = min(80, clean.distance(from: startIdx, to: clean.endIndex))
        let endIdx = clean.index(startIdx, offsetBy: endOffset)
        var snippet = String(clean[startIdx..<endIdx])
        if contextStart > 0 { snippet = "…" + snippet }
        if endIdx < clean.endIndex { snippet += "…" }
        return snippet
    }
}

// MARK: - Search Text Highlighting

import SwiftUI

func highlightedText(_ text: String, query: String, baseColor: Color, highlightColor: Color, font: Font) -> Text {
    guard !query.isEmpty else {
        return Text(text).foregroundStyle(baseColor).font(font)
    }
    let lower = text.lowercased()
    let queryLower = query.lowercased()

    var result = Text("")
    var searchStart = lower.startIndex
    var hasMatch = false

    while let range = lower.range(of: queryLower, range: searchStart..<lower.endIndex) {
        hasMatch = true
        // Text before match
        if searchStart < range.lowerBound {
            let before = String(text[searchStart..<range.lowerBound])
            result = result + Text(before).foregroundStyle(baseColor).font(font)
        }
        // Highlighted match (use original case from source text)
        let matchText = String(text[range])
        result = result + Text(matchText).foregroundStyle(highlightColor).bold().font(font)
        searchStart = range.upperBound
    }

    // Remaining text after last match
    if searchStart < lower.endIndex {
        let remaining = String(text[searchStart...])
        result = result + Text(remaining).foregroundStyle(baseColor).font(font)
    }

    if !hasMatch {
        return Text(text).foregroundStyle(baseColor).font(font)
    }

    return result
}
