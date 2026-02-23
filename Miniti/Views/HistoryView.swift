import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.startTime, order: .reverse) private var meetings: [Meeting]
    @State private var selectedMeeting: Meeting?
    @State private var searchText = ""
    
    init() {}
    
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
        HSplitView {
            // Meeting list
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Text("⌕")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "484F58"))
                    TextField("search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "E6EDF3"))
                }
                .padding(12)
                .background(Color(hex: "0F0F11"))
                
                Rectangle()
                    .fill(Color(hex: "1C1C1F"))
                    .frame(height: 1)
                
                if filteredMeetings.isEmpty {
                    VStack(spacing: 12) {
                        Text("◌")
                            .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(Color(hex: "1C1C1F"))
                        Text("no_sessions")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "484F58"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredMeetings) { meeting in
                                TerminalMeetingRow(
                                    meeting: meeting,
                                    isSelected: selectedMeeting?.id == meeting.id
                                ) {
                                    selectedMeeting = meeting
                                }
                                .contextMenu {
                                    Button {
                                        exportTranscript(meeting)
                                    } label: {
                                        Text("Export")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        deleteMeeting(meeting)
                                    } label: {
                                        Text("Delete")
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(minWidth: 260, maxWidth: 320)
            .background(Color(hex: "09090B"))
            
            // Meeting detail
            if let meeting = selectedMeeting {
                TerminalMeetingDetail(meeting: meeting)
            } else {
                VStack(spacing: 12) {
                    Text("◇")
                        .font(.system(size: 40, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(Color(hex: "1C1C1F"))
                    Text("select_session")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "484F58"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: "09090B"))
            }
        }
        .background(Color(hex: "09090B"))
    }
    
    private func deleteMeeting(_ meeting: Meeting) {
        if selectedMeeting == meeting {
            selectedMeeting = nil
        }
        modelContext.delete(meeting)
    }
    
    private func exportTranscript(_ meeting: Meeting) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(meeting.title).txt"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let content = formatExport(meeting)
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    private func formatExport(_ meeting: Meeting) -> String {
        var content = """
        # \(meeting.title)
        # Date: \(meeting.startTime.formatted(date: .long, time: .shortened))
        # Duration: \(meeting.formattedDuration)
        
        ## TRANSCRIPT
        
        \(meeting.fullTranscript)
        """
        
        if meeting.hasInsights {
            content += """
            
            
            ## INSIGHTS
            
            """
            
            if let summary = meeting.summaryText {
                content += "### Summary\n\(summary)\n\n"
            }
            
            if !meeting.actionItems.isEmpty {
                content += "### Action Items\n"
                for item in meeting.actionItems {
                    content += "- [ ] \(item)\n"
                }
                content += "\n"
            }
            
            if !meeting.keyDecisions.isEmpty {
                content += "### Decisions\n"
                for decision in meeting.keyDecisions {
                    content += "-> \(decision)\n"
                }
            }
        }
        
        return content
    }
}

struct TerminalMeetingRow: View {
    let meeting: Meeting
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.title.lowercased().replacingOccurrences(of: " ", with: "_"))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Color(hex: "E6EDF3") : Color(hex: "8B949E"))
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Text(formatDate(meeting.startTime))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "484F58"))
                    
                    Text(meeting.formattedDuration)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "484F58"))
                    
                    if meeting.hasInsights {
                        Text("⚡")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "A371F7"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color(hex: "18181B") : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).lowercased()
    }
}

struct TerminalMeetingDetail: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Tab = .transcript
    
    enum Tab: String, CaseIterable {
        case transcript
        case insights
        case meddpicc
        case training
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                TextField("meeting_title", text: $meeting.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                    .onSubmit {
                        saveTitle()
                    }
                
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("◷")
                        Text(meeting.startTime.formatted(date: .abbreviated, time: .shortened))
                    }
                    HStack(spacing: 4) {
                        Text("⏱")
                        Text(meeting.formattedDuration)
                    }
                    HStack(spacing: 4) {
                        Text("¶")
                        Text("\(meeting.segments.count)")
                    }
                }
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(hex: "484F58"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(hex: "0F0F11"))
            
            // Tab bar
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium, design: .monospaced))
                                .foregroundStyle(selectedTab == tab ? Color(hex: "E6EDF3") : Color(hex: "8B949E"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            
                            Rectangle()
                                .fill(selectedTab == tab ? Color(hex: "F78166") : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .background(Color(hex: "0F0F11"))
            
            Rectangle()
                .fill(Color(hex: "1C1C1F"))
                .frame(height: 1)
            
            // Content
            ScrollView {
                switch selectedTab {
                case .transcript:
                    TerminalHistoryTranscript(meeting: meeting)
                case .insights:
                    TerminalHistoryInsights(meeting: meeting)
                case .meddpicc:
                    TerminalHistoryMEDDPICC(meeting: meeting)
                case .training:
                    SavedTrainingContent(meeting: meeting)
                        .padding(16)
                }
            }
            .background(Color(hex: "09090B"))
        }
        .background(Color(hex: "09090B"))
        .onDisappear {
            saveTitle()
        }
    }
    
    private func saveTitle() {
        meeting.title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if meeting.title.isEmpty {
            meeting.title = "untitled"
        }
        try? modelContext.save()
    }
}

struct TerminalHistoryTranscript: View {
    let meeting: Meeting
    
    private let speakerColors: [Color] = [
        Color(hex: "58A6FF"),
        Color(hex: "A371F7"),
        Color(hex: "3FB950"),
        Color(hex: "D29922"),
        Color(hex: "F778BA"),
        Color(hex: "79C0FF"),
        Color(hex: "FFA657"),
        Color(hex: "7EE787"),
    ]
    
    private var sortedSegments: [TranscriptSegment] {
        meeting.segments.sorted { $0.timestamp < $1.timestamp }
    }
    
    // Get unique speakers in order of appearance
    private var uniqueSpeakers: [Int] {
        var seen = Set<Int>()
        return sortedSegments.compactMap { segment -> Int? in
            if seen.contains(segment.speaker) { return nil }
            seen.insert(segment.speaker)
            return segment.speaker
        }
    }
    
    private func isNewSpeakerTurn(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return sortedSegments[index].speaker != sortedSegments[index - 1].speaker
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Speaker legend
            if uniqueSpeakers.count > 1 {
                HStack(spacing: 16) {
                    Text("speakers:")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "484F58"))
                    
                    ForEach(uniqueSpeakers, id: \.self) { speaker in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(speakerColors[speaker % speakerColors.count])
                                .frame(width: 6, height: 6)
                            Text("S\(speaker + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(speakerColors[speaker % speakerColors.count])
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "0F0F11"))
            }
            
            // Transcript content
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sortedSegments.enumerated()), id: \.element.id) { index, segment in
                    HistorySegmentRow(
                        segment: segment,
                        isNewTurn: isNewSpeakerTurn(at: index),
                        speakerColor: speakerColors[segment.speaker % speakerColors.count]
                    )
                }
            }
            .padding(16)
        }
    }
}

struct HistorySegmentRow: View {
    let segment: TranscriptSegment
    let isNewTurn: Bool
    let speakerColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Speaker turn indicator
            if isNewTurn {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(speakerColor)
                        .frame(width: 3, height: 12)
                        .cornerRadius(1.5)
                    
                    Text("Speaker \(segment.speaker + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(speakerColor)
                    
                    Text("•")
                        .foregroundStyle(Color(hex: "1C1C1F"))
                    
                    Text(segment.formattedTimestamp)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "484F58"))
                }
                .padding(.top, isNewTurn ? 12 : 0)
                .padding(.bottom, 4)
            }
            
            // Message content
            HStack(alignment: .top, spacing: 0) {
                // Left border indicator
                Rectangle()
                    .fill(speakerColor.opacity(0.3))
                    .frame(width: 2)
                
                // Message text
                Text(segment.text)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                    .textSelection(.enabled)
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
            }
        }
    }
}

struct TerminalHistoryInsights: View {
    let meeting: Meeting
    
    var body: some View {
        if meeting.hasInsights {
            VStack(alignment: .leading, spacing: 20) {
                if let summary = meeting.summaryText {
                    TerminalSection(title: "summary", color: Color(hex: "58A6FF")) {
                        Text(summary)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                            .lineSpacing(6)
                    }
                }
                
                if !meeting.discussionFlow.isEmpty {
                    TerminalSection(title: "discussion", color: Color(hex: "F59E0B")) {
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
            }
            .padding(16)
        } else {
            VStack(spacing: 12) {
                Text("◇")
                    .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1F"))
                Text("no_insights")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

struct TerminalHistoryMEDDPICC: View {
    let meeting: Meeting
    @EnvironmentObject var appState: AppState
    
    private var fields: [(title: String, color: String, value: String?)] {
        [
            ("metrics", "3B82F6", meeting.meddpiccMetrics),
            ("economic buyer", "8B5CF6", meeting.meddpiccEconomicBuyer),
            ("decision criteria", "EC4899", meeting.meddpiccDecisionCriteria),
            ("decision process", "F59E0B", meeting.meddpiccDecisionProcess),
            ("paper process", "F97316", meeting.meddpiccPaperProcess),
            ("identified pain", "EF4444", meeting.meddpiccIdentifiedPain),
            ("champion", "22C55E", meeting.meddpiccChampion),
            ("competition", "6366F1", meeting.meddpiccCompetition),
        ]
    }
    
    private func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !t.isEmpty && t != "null" && t != "n/a" && t != "none"
    }
    
    var body: some View {
        if meeting.hasMEDDPICC {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(fields.filter { hasValue($0.value) }, id: \.title) { field in
                    TerminalSection(title: field.title, color: Color(hex: field.color)) {
                        Text(field.value!)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                            .lineSpacing(6)
                    }
                }
                
                Button {
                    Task {
                        await appState.generateInsightsForMeeting(meeting)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("update")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Color(hex: "58A6FF"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "58A6FF").opacity(0.1))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: "58A6FF").opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        } else {
            VStack(spacing: 16) {
                Text("◇")
                    .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(Color(hex: "1C1C1F"))
                Text("no MEDDPICC data")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
                
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [Meeting.self, TranscriptSegment.self], inMemory: true)
        .frame(width: 900, height: 600)
}
