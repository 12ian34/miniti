import SwiftUI
import SwiftData

struct HistoryView_iOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.startTime, order: .reverse) private var meetings: [Meeting]
    @State private var searchText = ""
    
    var filteredMeetings: [Meeting] {
        if searchText.isEmpty {
            return meetings
        }
        return meetings.filter { meeting in
            meeting.title.localizedCaseInsensitiveContains(searchText) ||
            meeting.fullTranscript.localizedCaseInsensitiveContains(searchText)
        }
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
                .font(.system(size: 48, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.disabled)
            Text("No sessions yet")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorPalette.Background.primary)
    }
    
    // MARK: - Meetings List
    
    private var meetingsList: some View {
        List {
            ForEach(filteredMeetings) { meeting in
                NavigationLink {
                    MeetingDetail_iOS(meeting: meeting)
                } label: {
                    MeetingRow_iOS(meeting: meeting)
                }
            }
            .onDelete(perform: deleteMeetings)
        }
        .listStyle(.plain)
    }
    
    private func deleteMeetings(at offsets: IndexSet) {
        for index in offsets {
            let meeting = filteredMeetings[index]
            modelContext.delete(meeting)
        }
        try? modelContext.save()
    }
}

// MARK: - Meeting Row

struct MeetingRow_iOS: View {
    let meeting: Meeting
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.primary)
                .lineLimit(1)
            
            HStack(spacing: 8) {
                Text(meeting.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.muted)
                
                if !meeting.segments.isEmpty {
                    Text("·")
                        .foregroundStyle(ColorPalette.Text.disabled)
                    Text("\(meeting.segments.count) segments")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Meeting Detail

struct MeetingDetail_iOS: View {
    @Bindable var meeting: Meeting
    @EnvironmentObject var appState: AppState
    @State private var activeSection: DetailSection = .transcript
    
    enum DetailSection: String, CaseIterable {
        case transcript = "transcript"
        case insights = "insights"
        case notes = "notes"
    }
    
    var body: some View {
        VStack(spacing: 0) {
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
        .navigationTitle(meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = meetingAsMarkdown()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }
    
    // MARK: - Section Picker
    
    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(DetailSection.allCases, id: \.self) { section in
                Button {
                    activeSection = section
                } label: {
                    Text(section.rawValue)
                        .font(.system(size: 12, weight: activeSection == section ? .bold : .medium, design: .monospaced))
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
    
    // MARK: - Transcript (collapsed same-speaker segments)
    
    private var transcriptContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if meeting.segments.isEmpty {
                    Text("No transcript available")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .padding()
                } else {
                    ForEach(collapsedSegments) { group in
                        let isMic = group.speaker == DeepgramService.micSpeakerID
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isMic ? "You" : group.speakerLabel)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(isMic ? ColorPalette.Speaker.mic : speakerColor(group.speaker))
                            
                            Text(group.text)
                                .font(.system(size: 14))
                                .foregroundStyle(ColorPalette.Text.primary)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
    
    private var collapsedSegments: [CollapsedSegment] {
        let sorted = meeting.segments.sorted { $0.timestamp < $1.timestamp }
        var result: [CollapsedSegment] = []
        
        for segment in sorted {
            if let last = result.last, last.speaker == segment.speaker {
                result[result.count - 1].text += " " + segment.text
            } else {
                result.append(CollapsedSegment(
                    id: segment.id,
                    speaker: segment.speaker,
                    speakerLabel: segment.speakerLabel,
                    text: segment.text
                ))
            }
        }
        return result
    }
    
    // MARK: - Insights
    
    private var insightsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = meeting.summaryText, !summary.isEmpty {
                    TerminalSection(title: "summary", color: Color(hex: "58A6FF")) {
                        Text(summary)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                            .lineSpacing(6)
                    }
                }
                
                if !meeting.discussionFlow.isEmpty {
                    TerminalSection(title: "discussion", color: Color(hex: "D29922")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(meeting.discussionFlow.enumerated()), id: \.offset) { index, item in
                                TerminalListItem(index: index, text: item, style: .arrow)
                            }
                        }
                    }
                }
                
                if !meeting.actionItems.isEmpty {
                    TerminalSection(title: "action_items", color: Color(hex: "3FB950")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(meeting.actionItems.enumerated()), id: \.offset) { index, item in
                                TerminalListItem(index: index, text: item, style: .checkbox)
                            }
                        }
                    }
                }
                
                if !meeting.keyDecisions.isEmpty {
                    TerminalSection(title: "decisions", color: Color(hex: "D29922")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(meeting.keyDecisions.enumerated()), id: \.offset) { index, decision in
                                TerminalListItem(index: index, text: decision, style: .arrow)
                            }
                        }
                    }
                }
                
                if !meeting.topics.isEmpty {
                    TerminalSection(title: "topics", color: Color(hex: "A371F7")) {
                        FlowLayout(spacing: 8) {
                            ForEach(meeting.topics, id: \.self) { topic in
                                TerminalTag(text: topic)
                            }
                        }
                    }
                }
                
                // MEDDPICC grid
                if meeting.hasMEDDPICC {
                    SavedMEDDPICCContent(meeting: meeting)
                }
                
                // No insights — offer to generate
                if !hasInsights && !meeting.segments.isEmpty {
                    VStack(spacing: 16) {
                        Text("◇")
                            .font(.system(size: 40, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(Color(hex: "1C1C1F"))
                        
                        Text("no_insights")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "8B949E"))
                        
                        Button {
                            Task {
                                await appState.generateInsightsForMeeting(meeting)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("⚡")
                                Text("generate")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(Color(hex: "58A6FF"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(hex: "58A6FF").opacity(0.15))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: "58A6FF").opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isGeneratingInsights)
                        
                        if appState.isGeneratingInsights {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("generating...")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: "8B949E"))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                } else if !hasInsights && meeting.segments.isEmpty {
                    Text("No transcript to generate insights from")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
    }
    
    private var hasInsights: Bool {
        (meeting.summaryText != nil && !meeting.summaryText!.isEmpty) ||
        !meeting.actionItems.isEmpty ||
        !meeting.topics.isEmpty ||
        !meeting.discussionFlow.isEmpty ||
        meeting.hasMEDDPICC
    }
    
    // MARK: - Notes (editable)
    
    private var notesContent: some View {
        TextEditor(text: $meeting.notes)
            .font(.system(size: 14, design: .monospaced))
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
    
    private func meetingAsMarkdown() -> String {
        var md = "# \(meeting.title)\n\n"
        md += "_\(meeting.startTime.formatted(date: .long, time: .shortened))_\n\n"
        
        if !meeting.segments.isEmpty {
            md += "## Transcript\n\n"
            var currentSpeaker: Int? = nil
            for segment in meeting.segments.sorted(by: { $0.timestamp < $1.timestamp }) {
                if segment.speaker != currentSpeaker {
                    currentSpeaker = segment.speaker
                    md += "\n**\(segment.speakerLabel):**\n"
                }
                md += "\(segment.text) "
            }
            md += "\n\n"
        }
        
        if let summary = meeting.summaryText, !summary.isEmpty {
            md += "## Summary\n\n\(summary)\n\n"
        }
        
        if !meeting.actionItems.isEmpty {
            md += "## Action Items\n\n"
            for item in meeting.actionItems {
                md += "- [ ] \(item)\n"
            }
            md += "\n"
        }
        
        return md
    }
}

// MARK: - Collapsed Segment

struct CollapsedSegment: Identifiable {
    let id: UUID
    let speaker: Int
    let speakerLabel: String
    var text: String
}

// MARK: - Saved MEDDPICC Content (reads from Meeting model)

struct SavedMEDDPICCContent: View {
    let meeting: Meeting
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private var gridColumns: [GridItem] {
        if sizeClass == .compact {
            return [GridItem(.flexible())]
        } else {
            return [GridItem(.flexible()), GridItem(.flexible())]
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("##")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "F59E0B"))
                Text("MEDDPICC")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "F59E0B"))
            }
            
            LazyVGrid(columns: gridColumns, spacing: 10) {
                MEDDPICCItem(title: "Metrics", value: meeting.meddpiccMetrics, color: "3B82F6")
                MEDDPICCItem(title: "Economic Buyer", value: meeting.meddpiccEconomicBuyer, color: "8B5CF6")
                MEDDPICCItem(title: "Decision Criteria", value: meeting.meddpiccDecisionCriteria, color: "EC4899")
                MEDDPICCItem(title: "Decision Process", value: meeting.meddpiccDecisionProcess, color: "F59E0B")
                MEDDPICCItem(title: "Paper Process", value: meeting.meddpiccPaperProcess, color: "F97316")
                MEDDPICCItem(title: "Identified Pain", value: meeting.meddpiccIdentifiedPain, color: "EF4444")
                MEDDPICCItem(title: "Champion", value: meeting.meddpiccChampion, color: "22C55E")
                MEDDPICCItem(title: "Competition", value: meeting.meddpiccCompetition, color: "6366F1")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "0F0F11"))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "F59E0B").opacity(0.3), lineWidth: 1)
                )
        )
    }
}
