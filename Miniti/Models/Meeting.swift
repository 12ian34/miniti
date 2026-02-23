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
                md += "\n**Speaker \(segment.speaker + 1):**\n"
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
    
    func fullMeetingAsMarkdown() -> String {
        var md = "# \(title)\n\n"
        md += "_\(startTime.formatted(date: .long, time: .shortened))_\n\n"
        md += "---\n\n"
        md += transcriptAsMarkdown()
        md += "\n\n---\n\n"
        if !notes.isEmpty {
            md += notesAsMarkdown()
            md += "\n\n---\n\n"
        }
        md += insightsAsMarkdown()
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
