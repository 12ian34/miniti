import SwiftUI
import SwiftData

struct HistoryView_iOS: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Meeting.startTime, order: .reverse) private var meetings: [Meeting]
    @State private var searchText = ""
    
    private var searchResults: [MeetingSearchResult] {
        MeetingSearchResult.search(query: searchText, in: Array(meetings))
    }

    var filteredMeetings: [Meeting] {
        if searchText.isEmpty {
            return meetings.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.startTime > $1.startTime
            }
        }
        return searchResults.map(\.meeting)
    }

    private var meetingSections: [(title: String, meetings: [Meeting])] {
        if !searchText.isEmpty {
            return [("Search results", filteredMeetings)]
        }

        let calendar = Calendar.current
        let pinned = filteredMeetings.filter(\.isPinned)
        let unpinned = filteredMeetings.filter { !$0.isPinned }
        var sections: [(String, [Meeting])] = []
        if !pinned.isEmpty { sections.append(("Pinned", pinned)) }

        let today = unpinned.filter { calendar.isDateInToday($0.startTime) }
        let yesterday = unpinned.filter { calendar.isDateInYesterday($0.startTime) }
        let week = unpinned.filter {
            !calendar.isDateInToday($0.startTime) &&
            !calendar.isDateInYesterday($0.startTime) &&
            calendar.isDate($0.startTime, equalTo: Date(), toGranularity: .weekOfYear)
        }
        let older = unpinned.filter { meeting in
            !today.contains(where: { $0.id == meeting.id }) &&
            !yesterday.contains(where: { $0.id == meeting.id }) &&
            !week.contains(where: { $0.id == meeting.id })
        }
        if !today.isEmpty { sections.append(("Today", today)) }
        if !yesterday.isEmpty { sections.append(("Yesterday", yesterday)) }
        if !week.isEmpty { sections.append(("This week", week)) }
        if !older.isEmpty { sections.append(("Older", older)) }
        return sections
    }

    private var searchSnippets: [UUID: String] {
        var dict: [UUID: String] = [:]
        for result in searchResults {
            if let snippet = result.snippet {
                dict[result.meeting.id] = snippet
            }
        }
        return dict
    }

    private var searchMatchCounts: [UUID: Int] {
        var dict: [UUID: Int] = [:]
        for result in searchResults {
            dict[result.meeting.id] = result.matchCount
        }
        return dict
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredMeetings.isEmpty {
                    emptyState
                } else {
                    meetingsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ColorPalette.Background.primary)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search meetings...")
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("◌")
                .font(.system(size: 48, weight: .ultraLight, design: .default))
                .foregroundStyle(ColorPalette.Text.disabled)
            Text(searchText.isEmpty ? "No sessions yet" : "No results")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorPalette.Background.primary)
    }
    
    // MARK: - Meetings List
    
    private var meetingsList: some View {
        List {
            ForEach(meetingSections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.meetings) { meeting in
                        NavigationLink {
                            MeetingDetail_iOS(meeting: meeting)
                        } label: {
                            MeetingRow_iOS(
                                meeting: meeting,
                                searchQuery: searchText.isEmpty ? nil : searchText,
                                matchSnippet: searchSnippets[meeting.id],
                                matchCount: searchMatchCounts[meeting.id]
                            )
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                togglePin(meeting)
                            } label: {
                                Label(meeting.isPinned ? "Unpin" : "Pin", systemImage: meeting.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(ColorPalette.Accent.amber)
                        }
                        .contextMenu {
                            Button {
                                togglePin(meeting)
                            } label: {
                                Label(meeting.isPinned ? "Unpin meeting" : "Pin meeting", systemImage: meeting.isPinned ? "pin.slash" : "pin")
                            }
                        }
                    }
                    .onDelete { offsets in
                        deleteMeetings(offsets.map { section.meetings[$0] })
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func deleteMeetings(_ meetings: [Meeting]) {
        for meeting in meetings {
            appState.noteMeetingDeleted(meeting)
            modelContext.delete(meeting)
        }
        try? modelContext.save()
    }

    private func togglePin(_ meeting: Meeting) {
        meeting.isPinned.toggle()
        try? modelContext.save()
    }
}

// MARK: - Meeting Row

struct MeetingRow_iOS: View {
    @EnvironmentObject private var appState: AppState
    let meeting: Meeting
    var searchQuery: String? = nil
    var matchSnippet: String? = nil
    var matchCount: Int? = nil

    private var highlightColor: Color { ColorPalette.Accent.amber }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if meeting.isPinned {
                Label("Pinned", systemImage: "pin.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ColorPalette.Accent.amber)
            }
            if let query = searchQuery, !query.isEmpty {
                highlightedText(
                    meeting.displayTitle,
                    query: query,
                    baseColor: ColorPalette.Text.primary,
                    highlightColor: highlightColor,
                    font: .system(size: 14, weight: .medium, design: .default)
                )
                .lineLimit(1)
            } else {
                Text(meeting.displayTitle)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .lineLimit(1)
            }

            // Match snippet
            if let snippet = matchSnippet, let query = searchQuery, !query.isEmpty {
                highlightedText(
                    snippet,
                    query: query,
                    baseColor: ColorPalette.Text.dim,
                    highlightColor: highlightColor,
                    font: .system(size: 11, design: .default)
                )
                .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(meeting.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, design: .default))
                    .foregroundStyle(ColorPalette.Text.muted)

                Text("·")
                    .foregroundStyle(ColorPalette.Text.disabled)
                Text(meeting.formattedDuration)
                    .font(.system(size: 11, design: .default))
                    .foregroundStyle(ColorPalette.Text.muted)

                if let lang = TranscriptionLanguage(rawValue: meeting.language), lang != .english {
                    Text("·")
                        .foregroundStyle(ColorPalette.Text.disabled)
                    Text("\(lang.flag) \(lang.rawValue.uppercased())")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                }

                if let provenance = meeting.provenanceDisplayName {
                    Text("·")
                        .foregroundStyle(ColorPalette.Text.disabled)
                    Text(provenance.lowercased())
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                }

                if appState.finalizingInsightMeetingIDs.contains(meeting.id) {
                    Text("·")
                        .foregroundStyle(ColorPalette.Text.disabled)
                    ProgressView()
                        .controlSize(.mini)
                    Text("insights")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Accent.blue)
                }

                if !meeting.segments.isEmpty {
                    Text("·")
                        .foregroundStyle(ColorPalette.Text.disabled)
                    Text("\(meeting.segments.count) segments")
                        .font(.system(size: 11, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                }

                if let count = matchCount, count > 0 {
                    Text("·")
                        .foregroundStyle(ColorPalette.Text.disabled)
                    Text("\(count) match\(count == 1 ? "" : "es")")
                        .font(.system(size: 11, design: .default))
                        .foregroundStyle(highlightColor)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Meeting Detail

struct MeetingDetail_iOS: View {
    @Bindable var meeting: Meeting
    var backLabel: String? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceScale) private var interfaceScale
    @EnvironmentObject var appState: AppState
    @State private var activeSection: DetailSection = .transcript
    @State private var renamingSpeaker: Int? = nil

    enum DetailSection: String, CaseIterable {
        case transcript = "transcript"
        case insights = "insights"
        case notes = "notes"
    }

    private var shareContent: String {
        switch activeSection {
        case .transcript:
            return transcriptMarkdown()
        case .insights:
            return insightsMarkdown()
        case .notes:
            return meeting.notes.isEmpty ? "(no notes)" : meeting.notes
        }
    }

    private func transcriptMarkdown() -> String {
        guard !meeting.segments.isEmpty else { return "(no transcript)" }
        var md = "# \(meeting.displayTitle) — Transcript\n\n"
        md += "_\(meeting.startTime.formatted(date: .long, time: .shortened))_\n\n"
        var currentKey: String? = nil
        let names = meeting.speakerNames
        let selfIDs = meeting.selfSpeakerIDs
        for segment in meeting.segments
            .filter({ $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .sorted(by: { $0.timestamp < $1.timestamp }) {
            let key = SelectableAttributed.displayGroupKey(speaker: segment.speaker, names: names, selfIDs: selfIDs)
            if key != currentKey {
                currentKey = key
                md += "\n**\(resolvedSpeakerLabel(for: segment.speaker, names: names, selfIDs: selfIDs)):**\n"
            }
            md += "\(segment.text) "
        }
        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func insightsMarkdown() -> String {
        var md = "# \(meeting.displayTitle) — Insights\n\n"
        md += "_\(meeting.startTime.formatted(date: .long, time: .shortened))_\n\n"
        if let summary = meeting.summaryText, !summary.isEmpty { md += "## Summary\n\n\(summary)\n\n" }
        if !meeting.discussionFlow.isEmpty {
            md += "## Discussion Flow\n\n"
            for (i, item) in meeting.discussionFlow.enumerated() { md += "\(i+1). \(item)\n" }
            md += "\n"
        }
        if !meeting.actionItems.isEmpty {
            md += "## Action Items\n\n"
            for item in meeting.actionItems { md += "- [ ] \(item)\n" }
            md += "\n"
        }
        if !meeting.topics.isEmpty {
            md += "## Topics\n\n"
            for topic in meeting.topics { md += "- \(topic)\n" }
            md += "\n"
        }
        let meddpiccFields: [(String, String?)] = [
            ("Metrics", meeting.meddpiccMetrics), ("Economic Buyer", meeting.meddpiccEconomicBuyer),
            ("Decision Criteria", meeting.meddpiccDecisionCriteria), ("Decision Process", meeting.meddpiccDecisionProcess),
            ("Paper Process", meeting.meddpiccPaperProcess), ("Identified Pain", meeting.meddpiccIdentifiedPain),
            ("Champion", meeting.meddpiccChampion), ("Competition", meeting.meddpiccCompetition)
        ]
        if meddpiccFields.contains(where: { $0.1 != nil && !($0.1?.isEmpty ?? true) }) {
            md += "## MEDDPICC\n\n"
            for (label, value) in meddpiccFields {
                if let value, !value.isEmpty { md += "**\(label):** \(value)\n\n" }
            }
        }
        if !meeting.notes.isEmpty { md += "## Notes\n\n\(meeting.notes)\n" }
        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleEditor

            if let provenance = meeting.provenanceDisplayName {
                HStack(spacing: 5) {
                    Image(systemName: "tray.and.arrow.down")
                    Text("Imported from \(provenance)")
                    Spacer()
                }
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.muted)
                .padding(.horizontal)
                .padding(.top, 6)
            }

            // Custom section picker (matching recording screen style)
            sectionPicker

            // Content
            Group {
                switch activeSection {
                case .transcript:
                    transcriptContent
                case .insights:
                    insightsContent
                case .notes:
                    notesContent
                }
            }
        }
        .navigationTitle(meeting.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            saveTitle()
        }
        .sheet(item: Binding(
            get: { renamingSpeaker.map { SpeakerRenameTarget(id: $0) } },
            set: { renamingSpeaker = $0?.id }
        )) { target in
            let key = String(target.id)
            let currentName = meeting.speakerNames[key]
            let defaultName = resolvedSpeakerLabel(for: target.id, names: nil, selfIDs: meeting.selfSpeakerIDs)
            let isSelf = meeting.effectiveSelfSpeakerIDs.contains(target.id)
            let hasOtherSelves = meeting.effectiveSelfSpeakerIDs.subtracting([target.id]).isEmpty == false
            RenameSpeakerView(
                speakerID: target.id,
                currentName: currentName,
                defaultName: defaultName,
                isSelf: isSelf,
                hasOtherSelves: hasOtherSelves,
                onSave: { newName in
                    meeting.setSpeakerName(id: key, name: newName)
                    renamingSpeaker = nil
                },
                onClear: {
                    meeting.setSpeakerName(id: key, name: nil)
                    renamingSpeaker = nil
                },
                onMarkAsSelf: {
                    meeting.setSelfSpeaker(id: target.id, isSelf: true)
                    try? modelContext.save()
                    renamingSpeaker = nil
                },
                onUnmarkAsSelf: {
                    meeting.setSelfSpeaker(id: target.id, isSelf: false)
                    try? modelContext.save()
                    renamingSpeaker = nil
                },
                onCancel: {
                    renamingSpeaker = nil
                }
            )
            .presentationDetents([.height(320)])
            .presentationBackground(ColorPalette.Background.primary)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                        if let backLabel {
                            Text(backLabel)
                                .font(.system(size: 14, weight: .medium, design: .default))
                        }
                    }
                    .foregroundStyle(ColorPalette.Text.muted)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareContent) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ColorPalette.Text.muted)
                }
            }
        }
    }
    
    // MARK: - Section Picker
    
    private var titleEditor: some View {
        TextField("Meeting title", text: $meeting.title)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .semibold, design: .default))
            .foregroundStyle(ColorPalette.Text.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "09090B"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "27272A"), lineWidth: 1)
                    )
            )
            .padding(.horizontal)
            .padding(.top, 8)
            .onSubmit {
                saveTitle()
            }
    }
    
    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(DetailSection.allCases, id: \.self) { section in
                Button {
                    activeSection = section
                } label: {
                    Text(section.rawValue)
                        .font(.system(size: 12, weight: activeSection == section ? .bold : .medium, design: .default))
                        .foregroundStyle(activeSection == section ? ColorPalette.Text.primary : ColorPalette.Text.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            activeSection == section
                                ? RoundedRectangle(cornerRadius: 4).fill(Color(hex: "1C1C1F"))
                                : RoundedRectangle(cornerRadius: 4).fill(Color.clear)
                        )
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "09090B"))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "27272A"), lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Transcript (per-segment with speaker turn headers)

    private var transcriptContent: some View {
        Group {
            if meeting.segments.isEmpty {
                ScrollView {
                    Text("No transcript available")
                        .font(.system(size: 13, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .padding()
                }
            } else {
                transcriptWithPinnedTrimControls
            }
        }
    }

    private var transcriptWithPinnedTrimControls: some View {
        let sortedSegments = meeting.segments.sorted { $0.timestamp < $1.timestamp }
        let effectiveSelves = meeting.effectiveSelfSpeakerIDs
        let uniqueSpeakers: [Int] = {
            var seen = Set<Int>()
            var ordered: [Int] = []
            for s in sortedSegments where seen.insert(s.speaker).inserted {
                ordered.append(s.speaker)
            }
            return ordered.sorted { a, b in
                let aSelf = effectiveSelves.contains(a)
                let bSelf = effectiveSelves.contains(b)
                if aSelf != bSelf { return aSelf }
                return a < b
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            SpeakerLegend(
                speakers: uniqueSpeakers,
                isRecording: false,
                speakerNames: meeting.speakerNames,
                selfIDs: meeting.selfSpeakerIDs,
                onRename: { renamingSpeaker = $0 }
            )
            TranscriptTrimView(meeting: meeting)
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Insights
    
    private var insightsContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                InsightsModeMenu_iOS(
                    selection: appState.insightsMode,
                    updatedAt: meeting.insightsUpdatedAt,
                    onSelect: appState.switchInsightsMode
                )
                
                if !meeting.segments.isEmpty && appState.insightsMode != .training && appState.insightsMode != .docs {
                    historicalInsightsGenerateButton
                }
                
                switch appState.insightsMode {
                case .standard:
                    historicalStandardInsightsContent
                case .meddpicc:
                    historicalMEDDPICCContent
                case .training:
                    historicalTrainingContent
                case .questions:
                    historicalQuestionsContent
                case .docs:
                    historicalDocsContent
                }
            }
            .padding()
        }
    }
    
    private var historicalStandardInsightsContent: some View {
        Group {
            if hasStandardInsights {
                VStack(alignment: .leading, spacing: 16) {
                    if let summary = meeting.summaryText, !summary.isEmpty {
                        HistoricalDetailBlock_iOS(title: "summary", color: Color(hex: "58A6FF")) {
                            Text(summary)
                                .font(.system(size: interfaceScale.insightBodySize, weight: .regular, design: .default))
                                .foregroundStyle(Color(hex: "E6EDF3"))
                                .lineSpacing(interfaceScale.insightLineSpacing)
                        }
                    }

                    if !meeting.discussionFlow.isEmpty {
                        HistoricalDetailBlock_iOS(title: "discussion", color: Color(hex: "F59E0B")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(meeting.discussionFlow.enumerated()), id: \.offset) { index, item in
                                    TerminalListItem(index: index, text: item, style: .arrow)
                                }
                            }
                        }
                    }

                    if !meeting.actionItems.isEmpty {
                        HistoricalDetailBlock_iOS(title: "actions", color: Color(hex: "3FB950")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(meeting.actionItems.enumerated()), id: \.offset) { index, item in
                                    TerminalListItem(index: index, text: item, style: .checkbox)
                                }
                            }
                        }
                    }

                    if !meeting.keyDecisions.isEmpty {
                        HistoricalDetailBlock_iOS(title: "decisions", color: Color(hex: "D29922")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(meeting.keyDecisions.enumerated()), id: \.offset) { index, decision in
                                    TerminalListItem(index: index, text: decision, style: .arrow)
                                }
                            }
                        }
                    }

                    if !meeting.topics.isEmpty {
                        HistoricalDetailBlock_iOS(title: "topics", color: Color(hex: "A371F7")) {
                            FlowLayout(spacing: 8) {
                                ForEach(meeting.topics, id: \.self) { topic in
                                    TerminalTag(text: topic)
                                }
                            }
                        }
                    }
                }
            } else if !meeting.segments.isEmpty {
                historicalEmptyState(
                    title: "no insights",
                    subtitle: "use update above"
                )
            } else {
                historicalEmptyState(
                    title: "no transcript",
                    subtitle: "record a session to generate insights"
                )
            }
        }
    }
    
    private var historicalMEDDPICCContent: some View {
        Group {
            if meeting.hasMEDDPICC {
                SavedMEDDPICCContent(meeting: meeting)
            } else if !meeting.segments.isEmpty {
                historicalEmptyState(
                    title: "no sales insights yet",
                    subtitle: "use update above"
                )
            } else {
                historicalEmptyState(
                    title: "no transcript",
                    subtitle: "record a session to generate sales qualification"
                )
            }
        }
    }
    
    private var historicalQuestionsContent: some View {
        Group {
            if meeting.hasQuestions {
                QuestionsContent(questions: meeting.suggestedQuestions)
            } else {
                QuestionsEmptyState(variant: .noQuestions)
            }
        }
    }

    private var historicalDocsContent: some View {
        DocsTabContent(
            topics: meeting.docTopics,
            isExtracting: appState.isExtractingDocsTopics,
            hasMCPURL: appState.validatedDocsMCPURL != nil,
            autoLookup: appState.canAutoLookupDocs,
            lookupsRemaining: appState.docsLookupsRemaining,
            canRefresh: !meeting.segments.isEmpty,
            errorMessage: appState.docsLookupError,
            onRefresh: {
                Task { await appState.refreshDocsTopics(for: meeting) }
            },
            onLookup: { topicID in
                Task { await appState.lookupDocTopic(id: topicID, for: meeting) }
            }
        )
    }
    
    private var historicalTrainingContent: some View {
        Group {
            if !meeting.segments.isEmpty {
                HistoricalSavedTrainingContent_iOS(meeting: meeting)
            } else {
                historicalEmptyState(
                    title: "no transcript",
                    subtitle: "coaching metrics need transcript data"
                )
            }
        }
    }
    
    private var historicalInsightsGenerateButton: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await appState.generateInsightsForMeeting(meeting)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text(meeting.needsInsightsAfterTranscriptEdit ? "regenerate" : "update")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                    if appState.insightsMode == .meddpicc && !meeting.hasMEDDPICC {
                        Text("sales")
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.muted)
                    } else if appState.insightsMode == .questions && !meeting.hasQuestions {
                        Text("questions")
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.muted)
                    }
                }
                .foregroundStyle(ColorPalette.Text.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "0F0F11"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "27272A"), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(appState.isGeneratingInsights)
            .opacity(appState.isGeneratingInsights ? 0.5 : 1)
            
            if appState.isGeneratingInsights {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("updating...")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                }
            }
            
            Spacer()
        }
    }
    
    private var hasStandardInsights: Bool {
        (meeting.summaryText != nil && !meeting.summaryText!.isEmpty) ||
        !meeting.actionItems.isEmpty ||
        !meeting.keyDecisions.isEmpty ||
        !meeting.topics.isEmpty ||
        !meeting.discussionFlow.isEmpty
    }
    
    // MARK: - Notes (editable)
    
    private var notesContent: some View {
        TextEditor(text: $meeting.notes)
            .font(.system(size: 14, design: .default))
            .scrollContentBackground(.hidden)
            .background(ColorPalette.Background.primary)
            .padding()
    }
    
    // MARK: - Helpers
    
    private func speakerColor(_ speaker: Int) -> Color {
        let remoteColors = ColorPalette.Speaker.remote
        let index = speaker % remoteColors.count
        return remoteColors[index]
    }
    
    private func saveTitle() {
        meeting.title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if meeting.title.isEmpty {
            meeting.title = "untitled"
        }
        try? modelContext.save()
    }
    
    @ViewBuilder
    private func historicalEmptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text("◇")
                .font(.system(size: 32, weight: .ultraLight, design: .default))
                .foregroundStyle(Color(hex: "1C1C1F"))
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.muted)
            Text(subtitle)
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(ColorPalette.Text.disabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
}

// MARK: - Collapsed Segment


// MARK: - Saved MEDDPICC Content (reads from Meeting model)

struct SavedMEDDPICCContent: View {
    let meeting: Meeting
    
    private var fields: [(title: String, color: Color, value: String?)] {
        [
            ("metrics", ColorPalette.MEDDPICC.metrics, meeting.meddpiccMetrics),
            ("economic buyer", ColorPalette.MEDDPICC.economicBuyer, meeting.meddpiccEconomicBuyer),
            ("decision criteria", ColorPalette.MEDDPICC.decisionCriteria, meeting.meddpiccDecisionCriteria),
            ("decision process", ColorPalette.MEDDPICC.decisionProcess, meeting.meddpiccDecisionProcess),
            ("paper process", ColorPalette.MEDDPICC.paperProcess, meeting.meddpiccPaperProcess),
            ("identified pain", ColorPalette.MEDDPICC.identifiedPain, meeting.meddpiccIdentifiedPain),
            ("champion", ColorPalette.MEDDPICC.champion, meeting.meddpiccChampion),
            ("competition", ColorPalette.MEDDPICC.competition, meeting.meddpiccCompetition),
        ]
    }

    private func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !t.isEmpty && t != "null" && t != "n/a" && t != "none"
    }

    var body: some View {
        ForEach(fields.filter { hasValue($0.value) }, id: \.title) { field in
            HistoricalDetailBlock_iOS(title: field.title, color: field.color) {
                MEDDPICCBulletText(field.value!, fontSize: 13)
            }
        }
    }
}

// MARK: - Historical Training Content (iOS, desktop-style rows)

struct HistoricalSavedTrainingContent_iOS: View {
    let meeting: Meeting
    @State private var expandedPresentationIDs: Set<String> = []
    
    private var metrics: TrainingMetrics {
        let segments = meeting.segments.map {
            TrainingMetrics.Segment(
                text: $0.text,
                speaker: $0.speaker,
                isFinal: $0.isFinal,
                timestamp: $0.timestamp
            )
        }
        let duration = meeting.endTime?.timeIntervalSince(meeting.startTime) ?? 0
        return TrainingMetrics.compute(from: segments, duration: duration, language: meeting.language, names: meeting.speakerNames, selfIDs: meeting.selfSpeakerIDs)
    }

    private var speakerPresentations: [TrainingMetrics.SpeakerPresentation] {
        metrics.speakerPresentations()
    }

    private var displaySpeakers: [TrainingMetrics.SpeakerStats] {
        speakerPresentations.map(\.summary)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(speakerPresentations) { presentation in
                let speaker = presentation.summary
                if speaker.totalFillers > 0 || speaker.isLocalMic {
                    HistoricalDetailBlock_iOS(
                        title: "fillers: \(speaker.speakerLabel.lowercased())",
                        color: speaker.isLocalMic ? Color(hex: "F59E0B") : Color(hex: "8B949E"),
                        info: .fillers
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Text("total \(speaker.totalFillers)")
                                    .font(.system(size: 11, weight: .medium, design: .default))
                                    .foregroundStyle(Color(hex: "E6EDF3"))
                                Text("per min \(String(format: "%.1f", speaker.fillersPerMinute))")
                                    .font(.system(size: 11, weight: .medium, design: .default))
                                    .foregroundStyle(Color(hex: "8B949E"))
                            }
                            
                            if presentation.hasMultipleDetails {
                                Button {
                                    toggleDetails(for: presentation.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: expandedPresentationIDs.contains(presentation.id) ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                        Text(expandedPresentationIDs.contains(presentation.id) ? "hide speaker details" : "show speaker details")
                                            .font(.system(size: 11, weight: .semibold, design: .default))
                                    }
                                    .foregroundStyle(ColorPalette.Accent.blue)
                                }
                                .buttonStyle(.plain)

                                if expandedPresentationIDs.contains(presentation.id) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(Array(presentation.details.enumerated()), id: \.offset) { _, detail in
                                            historicalFillerDetail(for: detail)
                                        }
                                    }
                                }
                            } else if !speaker.fillers.isEmpty {
                                historicalFillerEntries(speaker.fillers)
                            }
                        }
                    }
                }
            }
            
            if metrics.speakers.count > 1 {
                HistoricalDetailBlock_iOS(title: "talk ratio", color: Color(hex: "58A6FF"), info: .talkRatio) {
                    HStack(spacing: 8) {
                        Text("you \(Int(metrics.talkRatioYou * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.primary)
                        Text("•")
                            .foregroundStyle(ColorPalette.Text.disabled)
                        Text("others \(Int((1 - metrics.talkRatioYou) * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.muted)
                    }
                }
            }
            
            HistoricalDetailBlock_iOS(title: "pace", color: Color(hex: "A371F7"), info: .pace) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        HistoricalTrainingMetricRow_iOS(
                            speaker: speaker,
                            value: "\(Int(speaker.wordsPerMinute)) wpm",
                            trailing: "\(speaker.wordCount) words"
                        )
                    }
                }
            }
            
            HistoricalDetailBlock_iOS(title: "longest monologue", color: Color(hex: "EC4899"), info: .longestMonologue) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        if speaker.longestMonologueWords > 0 {
                            HistoricalTrainingMetricRow_iOS(
                                speaker: speaker,
                                value: "\(speaker.longestMonologueWords) words"
                            )
                        }
                    }
                }
            }
            
            HistoricalDetailBlock_iOS(title: "questions asked", color: Color(hex: "3FB950"), info: .questionsAsked) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        HistoricalTrainingMetricRow_iOS(
                            speaker: speaker,
                            value: "\(speaker.questionsAsked)"
                        )
                    }
                }
            }
            
            HistoricalDetailBlock_iOS(title: "clarity", color: Color(hex: "D29922"), info: .clarity) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        HistoricalTrainingMetricRow_iOS(
                            speaker: speaker,
                            value: String(format: "%.1f", speaker.avgWordsPerTurn),
                            trailing: "avg words/turn"
                        )
                    }
                    Text("lower = clearer = better")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(ColorPalette.Text.disabled)
                }
            }
        }
    }

    private func toggleDetails(for id: String) {
        if expandedPresentationIDs.contains(id) {
            expandedPresentationIDs.remove(id)
        } else {
            expandedPresentationIDs.insert(id)
        }
    }

    private func historicalFillerDetail(for speaker: TrainingMetrics.SpeakerStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(speaker.speakerLabel.lowercased()) · \(speaker.totalFillers)")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(speaker.isLocalMic ? ColorPalette.Accent.green : ColorPalette.Text.secondary)
            if speaker.fillers.isEmpty {
                Text("no fillers detected")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(ColorPalette.Text.meta)
            } else {
                historicalFillerEntries(speaker.fillers)
            }
        }
    }

    private func historicalFillerEntries(_ entries: [TrainingMetrics.FillerEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries) { entry in
                HStack(spacing: 6) {
                    Text(entry.word)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .frame(width: 70, alignment: .trailing)
                    Text("\(entry.count)")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(ColorPalette.Accent.amber)
                }
            }
        }
    }
}

private struct HistoricalDetailBlock_iOS<Content: View>: View {
    let title: String
    let color: Color
    let info: HistoricalMetricInfo_iOS?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        color: Color,
        info: HistoricalMetricInfo_iOS? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.color = color
        self.info = info
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: 12)
                    .cornerRadius(1.5)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(color)
                if let info {
                    HistoricalMetricInfoButton_iOS(info: info, accent: color)
                }
            }
            
            content()
                .padding(.leading, 12)
        }
    }
}

private struct HistoricalMetricInfo_iOS {
    let title: String
    let summary: String
    let guidance: [String]
}

private struct HistoricalMetricInfoButton_iOS: View {
    let info: HistoricalMetricInfo_iOS
    let accent: Color
    
    @State private var showInfo = false
    
    var body: some View {
        Button {
            showInfo.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent.opacity(0.85))
                .padding(2)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showInfo) {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showInfo = false
                    }

                HistoricalMetricInfoOverlayCard_iOS(info: info, accent: accent) {
                    showInfo = false
                }
                .padding(.horizontal, 20)
            }
            .background(Color.clear)
        }
    }
}

private struct HistoricalMetricInfoOverlayCard_iOS: View {
    let info: HistoricalMetricInfo_iOS
    let accent: Color
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(info.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorPalette.Text.primary)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ColorPalette.Text.primary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }

            Text(info.summary)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(ColorPalette.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(info.guidance, id: \.self) { line in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(accent.opacity(0.85))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(line)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(ColorPalette.Text.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ColorPalette.Background.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accent.opacity(0.26), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 10)
        )
        .onTapGesture {
            // Prevent backdrop tap gesture from firing when interacting with the card.
        }
    }
}

private extension HistoricalMetricInfo_iOS {
    static let fillers = HistoricalMetricInfo_iOS(
        title: "Fillers",
        summary: "Lower is usually better. This counts words like um, uh, like, and similar verbal placeholders.",
        guidance: [
            "Rough coaching range: under 1-3 fillers/min is usually solid.",
            "3-6/min is common in casual conversation or when thinking live.",
            "6+/min can make delivery feel less confident or less crisp.",
            "Context matters: brainstorming and interviews usually spike filler usage."
        ]
    )
    
    static let talkRatio = HistoricalMetricInfo_iOS(
        title: "Talk Ratio",
        summary: "There is no single best number. Good ratio depends on your role in the conversation.",
        guidance: [
            "Presenter/demo: you may be 60-90% and that can be correct.",
            "Interview or discovery call: balanced turns (roughly 40-60%) often feels stronger.",
            "Coaching/support roles usually improve when the other person talks more.",
            "Watch sudden extremes: very high ratio can mean not leaving space."
        ]
    )
    
    static let pace = HistoricalMetricInfo_iOS(
        title: "Pace",
        summary: "Words per minute (WPM). Faster is not always better; clarity usually drops when pace gets too high.",
        guidance: [
            "Common clear speaking range: ~120-170 wpm.",
            "Energetic but still understandable often lands around 150-190 wpm.",
            "Above ~200 wpm can feel rushed unless the audience is highly familiar.",
            "Below ~100 wpm can work for emphasis, but may feel slow if sustained."
        ]
    )
    
    static let longestMonologue = HistoricalMetricInfo_iOS(
        title: "Longest Monologue",
        summary: "Tracks the longest uninterrupted stretch by word count. Lower is usually better in back-and-forth conversations.",
        guidance: [
            "Shorter monologues usually create more room for engagement.",
            "Long stretches are fine in demos or explanations when the listener expects it.",
            "If this keeps growing in meetings, pause and check for questions.",
            "Compare to your own baseline by meeting type, not a single fixed target."
        ]
    )
    
    static let questionsAsked = HistoricalMetricInfo_iOS(
        title: "Questions Asked",
        summary: "This is directional, not a quality score. More questions can improve engagement, but only in the right context.",
        guidance: [
            "Discovery, coaching, and interviews usually benefit from more questions.",
            "Status updates and presentations may be strong even with few or no questions.",
            "Use this with talk ratio: low questions + high talk ratio can signal one-way delivery.",
            "Quality matters more than raw count."
        ]
    )
    
    static let clarity = HistoricalMetricInfo_iOS(
        title: "Clarity (avg words/turn)",
        summary: "This metric is average words per speaking turn. Lower usually means shorter turns, which often feels easier to follow.",
        guidance: [
            "Lower is usually better for conversational clarity, but too low can sound choppy.",
            "Rough guide: ~5-15 words/turn often feels concise in discussion.",
            "15-25 can be fine for explanations; 25+ may feel dense if repeated.",
            "Do not compare across formats (presentation vs interview) without context."
        ]
    )
}


private struct HistoricalTrainingMetricRow_iOS: View {
    let speaker: TrainingMetrics.SpeakerStats
    let value: String
    var trailing: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Text(speaker.speakerLabel.lowercased())
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(speaker.isLocalMic ? ColorPalette.Accent.green : ColorPalette.Text.muted)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.primary)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(ColorPalette.Text.disabled)
            }
        }
    }
}
