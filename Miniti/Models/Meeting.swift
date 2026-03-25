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
    
    // MEDDPICC fields
    var meddpiccMetrics: String?
    var meddpiccEconomicBuyer: String?
    var meddpiccDecisionCriteria: String?
    var meddpiccDecisionProcess: String?
    var meddpiccPaperProcess: String?
    var meddpiccIdentifiedPain: String?
    var meddpiccChampion: String?
    var meddpiccCompetition: String?
    
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
        segments
            .filter { $0.isFinal }
            .sorted { $0.timestamp < $1.timestamp }
            .map { segment in
                let speaker = segment.speakerLabel
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
        
        var currentSpeaker: Int? = nil
        for segment in sortedSegments {
            if segment.speaker != currentSpeaker {
                currentSpeaker = segment.speaker
                md += "\n**\(segment.speakerLabel):**\n"
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
        let metrics = TrainingMetrics.compute(from: segments, duration: duration)
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

    func fullMeetingAsMarkdown() -> String {
        var md = "# \(title)\n\n"
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
