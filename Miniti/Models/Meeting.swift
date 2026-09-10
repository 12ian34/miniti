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
    var transcriptEditedAt: Date?
    var transcriptRevision: Int = 0
    var isPinned: Bool = false
    var insightsUpdatedAt: Date?
    
    var managedSessionId: String?
    var language: String = "en"
    
    var calendarEventId: String?
    var attendeesJSON: String?

    // Import provenance. Optional fields keep existing SwiftData stores lightweight-migratable.
    var externalSource: String?
    var externalID: String?
    var externalURL: String?
    var importedAt: Date?
    
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

    // Templates specialist view: which built-in template this meeting uses, and its filled
    // sections (JSON-encoded [String: String], section key -> text). Optional columns keep
    // existing stores lightweight-migratable.
    var insightTemplateID: String?
    var templateSectionsJSON: String?

    // Docs topics + their resolved lookup cards (JSON-encoded [DocTopic])
    var docTopicsJSON: String?

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

    // Optional internal environment inference (InferredMeetingEnvironment raw value).
    // Diagnostic metadata only — never user-facing, never required to load, trim,
    // export, search, or regenerate insights. Nil (all legacy meetings) = unknown.
    var inferredEnvironmentRaw: String?
    
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
        transcriptEditedAt: Date? = nil,
        transcriptRevision: Int = 0,
        isPinned: Bool = false,
        insightsUpdatedAt: Date? = nil,
        externalSource: String? = nil,
        externalID: String? = nil,
        externalURL: String? = nil,
        importedAt: Date? = nil,
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
        self.transcriptEditedAt = transcriptEditedAt
        self.transcriptRevision = transcriptRevision
        self.isPinned = isPinned
        self.insightsUpdatedAt = insightsUpdatedAt
        self.externalSource = externalSource
        self.externalID = externalID
        self.externalURL = externalURL
        self.importedAt = importedAt
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
            if newValue.isEmpty {
                suggestedQuestionsJSON = nil
                return
            }
            // On encode failure, preserve the existing JSON rather than clobbering it to nil.
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                suggestedQuestionsJSON = str
            }
        }
    }
    
    var hasQuestions: Bool {
        !suggestedQuestions.isEmpty
    }

    /// Filled template sections, keyed by section key.
    var templateSections: [String: String] {
        get { InsightTemplateSections.decode(templateSectionsJSON) }
        set {
            if newValue.isEmpty {
                templateSectionsJSON = nil
                return
            }
            // On encode failure, preserve the existing JSON rather than clobbering it to nil.
            if let encoded = InsightTemplateSections.encode(newValue) {
                templateSectionsJSON = encoded
            }
        }
    }

    /// The template these sections belong to, when it is one we know.
    var insightTemplate: InsightTemplate? {
        InsightTemplate.builtIn(id: insightTemplateID)
    }

    var hasTemplateInsights: Bool {
        guard let template = insightTemplate else { return false }
        return !template.orderedSections(from: templateSections).isEmpty
    }

    var docTopics: [DocTopic] {
        get {
            guard let json = docTopicsJSON, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([DocTopic].self, from: data)) ?? []
        }
        set {
            if newValue.isEmpty {
                docTopicsJSON = nil
                return
            }
            // On encode failure, preserve the existing JSON rather than clobbering it to nil.
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                docTopicsJSON = str
            }
        }
    }

    /// Resolved answer cards from answered topics — used for markdown/webhook export.
    var docsPlaybook: [DocPlaybookCard] {
        docTopics.compactMap { $0.card }
    }

    var hasDocs: Bool {
        !docTopics.isEmpty
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

    /// Mark every mic speaker on this meeting as self in one action.
    func markAllMicSpeakersAsSelf() {
        let micIDs = micSpeakerIDs
        guard micIDs.count > 1 else { return }
        for id in micIDs.sorted() {
            setSelfSpeaker(id: id, isSelf: true)
        }
    }

    /// One pass over segments summarizing speaker sources. Explicit source wins;
    /// legacy segments without one fall back to the reserved mic ID range.
    private struct SpeakerSourceSummary {
        var micIDs: Set<Int> = []
        var hasSystemSource = false
        var hasLegacySegments = false
    }

    private var speakerSourceSummary: SpeakerSourceSummary {
        var summary = SpeakerSourceSummary()
        for segment in segments {
            if let source = segment.source {
                switch source {
                case .microphone: summary.micIDs.insert(segment.speaker)
                case .system: summary.hasSystemSource = true
                case .unknown: break
                }
            } else {
                summary.hasLegacySegments = true
                if DeepgramService.isMicAppSpeakerID(segment.speaker) {
                    summary.micIDs.insert(segment.speaker)
                }
            }
        }
        return summary
    }

    /// Distinct app speaker IDs attributed to the device microphone.
    var micSpeakerIDs: Set<Int> {
        speakerSourceSummary.micIDs
    }

    /// Whether the implicit "the sole mic speaker is You" default applies when nobody
    /// is explicitly marked. It only ever applied to dual-source (mic+system) meetings
    /// — mic-only recordings (iOS, macOS mic-only) never labeled anyone "You", and must
    /// not start now: a solo recording can be someone else's lecture or an interview.
    /// Legacy meetings (no source metadata) predate mic diarization and keep it.
    private func implicitSelfAllowed(_ summary: SpeakerSourceSummary) -> Bool {
        let hasDualSourceOrLegacy =
            summary.hasSystemSource || summary.hasLegacySegments || segments.isEmpty
        let environment = InferredMeetingEnvironment(rawValue: inferredEnvironmentRaw ?? "") ?? .unknown
        return ImplicitSelfPolicy.allowed(
            micSpeakerCount: summary.micIDs.count,
            hasDualSourceOrLegacy: hasDualSourceOrLegacy,
            environment: environment
        )
    }

    /// Effective "self" set used for membership checks (rename UI, nudges). Explicit
    /// markings win; otherwise the implicit mic default applies only in dual-source or
    /// legacy meetings with at most one microphone speaker.
    var effectiveSelfSpeakerIDs: Set<Int> {
        let explicit = selfSpeakerIDs
        if !explicit.isEmpty { return explicit }
        return implicitSelfAllowed(speakerSourceSummary) ? [DeepgramService.micSpeakerID] : []
    }

    /// Self context for label/metrics resolution, which must let an inferred name beat
    /// the *implicit* "You" (but never an explicit mark): explicit marks → that set;
    /// implicit default applicable → nil (resolver applies it after names); otherwise
    /// an empty set (no implicit "You" at all).
    var speakerLabelSelfIDs: Set<Int>? {
        let explicit = selfSpeakerIDs
        if !explicit.isEmpty { return explicit }
        return implicitSelfAllowed(speakerSourceSummary) ? nil : []
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

    var provenanceDisplayName: String? {
        switch externalSource?.lowercased() {
        case "granola": return "Granola"
        case let source?: return source.capitalized
        case nil: return nil
        }
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
        let selfIDs = speakerLabelSelfIDs
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

    var hasGeneratedInsights: Bool {
        let hasSummary = summaryText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let meddpiccFields = [
            meddpiccMetrics, meddpiccEconomicBuyer, meddpiccDecisionCriteria, meddpiccDecisionProcess,
            meddpiccPaperProcess, meddpiccIdentifiedPain, meddpiccChampion, meddpiccCompetition
        ]
        let hasMEDDPICCContent = meddpiccFields.contains {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return hasSummary ||
            !actionItems.isEmpty ||
            !keyDecisions.isEmpty ||
            !topics.isEmpty ||
            !discussionFlow.isEmpty ||
            hasMEDDPICCContent ||
            hasQuestions ||
            hasDocs ||
            hasTemplateInsights
    }

    var needsInsightsAfterTranscriptEdit: Bool {
        transcriptEditedAt != nil && !hasGeneratedInsights
    }

    var hasTranscriptEdits: Bool {
        transcriptRevision > 0 || transcriptEditedAt != nil
    }

    func markTranscriptEdited(at date: Date = Date()) {
        transcriptRevision += 1
        transcriptEditedAt = date
        clearGeneratedInsightsAfterTranscriptEdit()
    }

    /// Bump transcript revision after a dictionary correction without clearing
    /// generated insights (unlike trim).
    func markTranscriptCorrected(at date: Date = Date()) {
        transcriptRevision += 1
        transcriptEditedAt = date
    }

    func clearGeneratedInsightsAfterTranscriptEdit() {
        summaryText = nil
        actionItems = []
        keyDecisions = []
        topics = []
        discussionFlow = []
        meddpiccMetrics = nil
        meddpiccEconomicBuyer = nil
        meddpiccDecisionCriteria = nil
        meddpiccDecisionProcess = nil
        meddpiccPaperProcess = nil
        meddpiccIdentifiedPain = nil
        meddpiccChampion = nil
        meddpiccCompetition = nil
        suggestedQuestions = []
        docTopics = []
        templateSections = [:]
    }
    
    // MARK: - Markdown Export
    
    func transcriptAsMarkdown() -> String {
        var md = "## Transcript\n\n"

        let sortedSegments = segments.filter { $0.isFinal }.sorted { $0.timestamp < $1.timestamp }
        let names = speakerNames
        let selfIDs = speakerLabelSelfIDs

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

        if hasDocs {
            md += "### Docs\n\n"
            for card in docsPlaybook {
                md += "- **\(card.topic)**\n  \(card.answer)\n"
                for citation in card.citations {
                    if let url = citation.url, !url.isEmpty {
                        md += "  - [\(citation.title)](\(url))\n"
                    } else {
                        md += "  - \(citation.title)\n"
                    }
                }
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

        // Template sections if available
        if let template = insightTemplate {
            md += InsightTemplateSections.markdown(template: template, sections: templateSections)
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
            selfIDs: speakerLabelSelfIDs
        )
        guard !metrics.speakers.isEmpty else { return "" }

        var md = "## Coaching\n\n"
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
            if newValue.isEmpty {
                attendeesJSON = nil
                return
            }
            // On encode failure, preserve the existing JSON rather than clobbering it to nil.
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                attendeesJSON = str
            }
        }
    }
    
    func fullMeetingAsMarkdown() -> String {
        var md = "# \(displayTitle)\n\n"
        md += "_\(startTime.formatted(date: .long, time: .shortened))_\n\n"
        if let provenanceDisplayName {
            md += "_Imported from \(provenanceDisplayName)_\n\n"
        }
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
/// 1. Explicit or effective self (`selfIDs` contains speaker) → "You" (wins over mapped name)
/// 2. Inferred/custom name from `names`
/// 3. Implicit default (mic speaker when self context is unknown, i.e. `selfIDs` is nil) → "You"
/// 4. Neutral fallback. Microphone-range speakers (1000+n) label by mic ordinal with a
///    "(mic)" tag so a hybrid meeting cannot show two different people as "Speaker 2";
///    an empty (non-nil) `selfIDs` means several people share the microphone and nobody
///    is assumed to be the user.
func resolvedSpeakerLabel(for speaker: Int, names: [String: String]? = nil, selfIDs: Set<Int>? = nil) -> String {
    if let selfIDs, selfIDs.contains(speaker) { return "You" }
    if let mapped = names?[String(speaker)]?.trimmingCharacters(in: .whitespacesAndNewlines), !mapped.isEmpty {
        return mapped
    }
    if selfIDs == nil, speaker == DeepgramService.micSpeakerID { return "You" }
    if DeepgramService.isMicAppSpeakerID(speaker) {
        return "Speaker \(speaker - DeepgramService.micSpeakerID + 1) (mic)"
    }
    return "Speaker \(speaker + 1)"
}

/// Short variant used where horizontal space is tight (e.g. the live transcript gutter).
func resolvedShortSpeakerLabel(for speaker: Int, names: [String: String]? = nil, selfIDs: Set<Int>? = nil) -> String {
    if let selfIDs, selfIDs.contains(speaker) { return "You" }
    if let mapped = names?[String(speaker)]?.trimmingCharacters(in: .whitespacesAndNewlines), !mapped.isEmpty {
        return mapped
    }
    if selfIDs == nil, speaker == DeepgramService.micSpeakerID { return "You" }
    if DeepgramService.isMicAppSpeakerID(speaker) {
        // Compact contexts drop the "(mic)" disambiguation — color and grouping
        // keep mic/system speakers distinct where space is tight.
        return "S\(speaker - DeepgramService.micSpeakerID + 1)"
    }
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
    /// Explicit capture source (TranscriptSource raw value). Optional and additive so
    /// existing stores lightweight-migrate; nil (all legacy segments) falls back to the
    /// reserved mic ID range where source matters.
    var sourceRaw: String?

    init(
        id: UUID = UUID(),
        text: String,
        speaker: Int = 0,
        timestamp: TimeInterval,
        isFinal: Bool = false,
        confidence: Double = 1.0,
        sourceRaw: String? = nil
    ) {
        self.id = id
        self.text = text
        self.speaker = speaker
        self.timestamp = timestamp
        self.isFinal = isFinal
        self.confidence = confidence
        self.sourceRaw = sourceRaw
    }

    var source: TranscriptSource? {
        sourceRaw.flatMap(TranscriptSource.init(rawValue:))
    }

    var speakerLabel: String {
        if speaker == DeepgramService.micSpeakerID { return "You" }
        if DeepgramService.isMicAppSpeakerID(speaker) {
            return "Speaker \(speaker - DeepgramService.micSpeakerID + 1) (mic)"
        }
        return "Speaker \(speaker + 1)"
    }
    
    var formattedTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct TranscriptTextSelection: Equatable {
    let segmentID: UUID
    let lowerUTF16Offset: Int
    let upperUTF16Offset: Int

    var isEmpty: Bool {
        lowerUTF16Offset >= upperUTF16Offset
    }
}

struct TranscriptTrimOperation: Equatable {
    var segmentIDsToDelete: Set<UUID> = []
    var textSelections: [TranscriptTextSelection] = []

    var isEmpty: Bool {
        segmentIDsToDelete.isEmpty && textSelections.allSatisfy(\.isEmpty)
    }
}

struct TranscriptSegmentSnapshot: Equatable {
    let id: UUID
    let speaker: Int
    let timestamp: TimeInterval
    let text: String
    let isFinal: Bool
    let confidence: Double
    var sourceRaw: String? = nil
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

            // Template sections
            for value in meeting.templateSections.values {
                let n = countOccurrences(of: q, in: value)
                if n > 0 {
                    if score < 20 { score += 20 }
                    totalMatches += n
                    if bestSnippet == nil { bestSnippet = extractSnippet(from: value, matching: q) }
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
    // Search the original string case-insensitively. Indexing `text` with ranges taken
    // from `text.lowercased()` crashes when lowercasing changes the length (e.g. "İ").
    var result = Text("")
    var searchStart = text.startIndex
    var hasMatch = false

    while searchStart < text.endIndex,
          let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<text.endIndex),
          !range.isEmpty {
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
    if searchStart < text.endIndex {
        let remaining = String(text[searchStart...])
        result = result + Text(remaining).foregroundStyle(baseColor).font(font)
    }

    if !hasMatch {
        return Text(text).foregroundStyle(baseColor).font(font)
    }

    return result
}
