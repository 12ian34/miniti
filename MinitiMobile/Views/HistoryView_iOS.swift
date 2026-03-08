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
                
                Text("·")
                    .foregroundStyle(ColorPalette.Text.disabled)
                Text(meeting.formattedDuration)
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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    @State private var activeSection: DetailSection = .transcript
    
    enum DetailSection: String, CaseIterable {
        case transcript = "transcript"
        case insights = "insights"
        case notes = "notes"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            titleEditor
            
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
        .onDisappear {
            saveTitle()
        }
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
    
    private var titleEditor: some View {
        TextField("Meeting title", text: $meeting.title)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
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
                historicalInsightsModePicker
                
                if !meeting.segments.isEmpty && appState.insightsMode != .training {
                    historicalInsightsGenerateButton
                }
                
                switch appState.insightsMode {
                case .standard:
                    historicalStandardInsightsContent
                case .meddpicc:
                    historicalMEDDPICCContent
                case .training:
                    historicalTrainingContent
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
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color(hex: "E6EDF3"))
                                .lineSpacing(6)
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
                    title: "no meddpicc yet",
                    subtitle: "use update above"
                )
            } else {
                historicalEmptyState(
                    title: "no transcript",
                    subtitle: "record a session to generate MEDDPICC"
                )
            }
        }
    }
    
    private var historicalTrainingContent: some View {
        Group {
            if !meeting.segments.isEmpty {
                HistoricalSavedTrainingContent_iOS(meeting: meeting)
            } else {
                historicalEmptyState(
                    title: "no transcript",
                    subtitle: "training metrics need transcript data"
                )
            }
        }
    }
    
    private var historicalInsightsModePicker: some View {
        HStack(spacing: 2) {
            ForEach(InsightsMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.switchInsightsMode(to: mode)
                    }
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: appState.insightsMode == mode ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(appState.insightsMode == mode ? ColorPalette.Text.primary : ColorPalette.Text.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appState.insightsMode == mode ? ColorPalette.Accent.green.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "09090B"))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "27272A"), lineWidth: 1)
                )
        )
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
                    Text((meeting.hasInsights || meeting.hasMEDDPICC) ? "update" : "generate")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    if appState.insightsMode == .meddpicc && !meeting.hasMEDDPICC {
                        Text("meddpicc")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(Color(hex: "1C1C1F"))
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.muted)
            Text(subtitle)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.disabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
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
        ForEach(fields.filter { hasValue($0.value) }, id: \.title) { field in
            HistoricalDetailBlock_iOS(title: field.title, color: Color(hex: field.color)) {
                MEDDPICCBulletText(field.value!, fontSize: 13)
            }
        }
    }
}

// MARK: - Historical Training Content (iOS, desktop-style rows)

struct HistoricalSavedTrainingContent_iOS: View {
    let meeting: Meeting
    
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
        return TrainingMetrics.compute(from: segments, duration: duration)
    }
    
    private var displaySpeakers: [TrainingMetrics.SpeakerStats] {
        let localSpeakers = metrics.speakers.filter(\.isLocalMic)
        let externalSpeakers = metrics.speakers.filter { !$0.isLocalMic }
        guard externalSpeakers.count > 1, !localSpeakers.isEmpty else {
            return metrics.speakers
        }
        
        var fillerCounts: [String: Int] = [:]
        
        let totalExternalWords = externalSpeakers.reduce(0) { $0 + $1.wordCount }
        let totalExternalSegments = externalSpeakers.reduce(0) { $0 + $1.segmentCount }
        let totalExternalQuestions = externalSpeakers.reduce(0) { $0 + $1.questionsAsked }
        let totalExternalFillers = externalSpeakers.reduce(0) { $0 + $1.totalFillers }
        let longestExternalMonologue = externalSpeakers.map(\.longestMonologueWords).max() ?? 0
        
        for speaker in externalSpeakers {
            for filler in speaker.fillers {
                fillerCounts[filler.word, default: 0] += filler.count
            }
        }
        
        let mergedFillers = fillerCounts
            .map { TrainingMetrics.FillerEntry(word: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count { return $0.word < $1.word }
                return $0.count > $1.count
            }
        
        let others = TrainingMetrics.SpeakerStats(
            speakerLabel: "Others",
            isLocalMic: false,
            wordCount: totalExternalWords,
            segmentCount: totalExternalSegments,
            fillers: mergedFillers,
            totalFillers: totalExternalFillers,
            fillersPerMinute: Double(totalExternalFillers) / max(metrics.durationMinutes, 0.01),
            wordsPerMinute: Double(totalExternalWords) / max(metrics.durationMinutes, 0.01),
            longestMonologueWords: longestExternalMonologue,
            questionsAsked: totalExternalQuestions,
            avgWordsPerTurn: totalExternalSegments > 0 ? Double(totalExternalWords) / Double(totalExternalSegments) : 0
        )
        
        return localSpeakers + [others]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(displaySpeakers) { speaker in
                if speaker.totalFillers > 0 || speaker.isLocalMic {
                    HistoricalDetailBlock_iOS(
                        title: "fillers: \(speaker.speakerLabel.lowercased())",
                        color: speaker.isLocalMic ? Color(hex: "F59E0B") : Color(hex: "8B949E"),
                        info: .fillers
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Text("total \(speaker.totalFillers)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: "E6EDF3"))
                                Text("per min \(String(format: "%.1f", speaker.fillersPerMinute))")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: "8B949E"))
                            }
                            
                            if speaker.speakerLabel != "Others" && !speaker.fillers.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(speaker.fillers) { entry in
                                        HStack(spacing: 6) {
                                            Text(entry.word)
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundStyle(Color(hex: "D4D4D8"))
                                                .frame(width: 70, alignment: .trailing)
                                            Text("\(entry.count)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(Color(hex: "F59E0B"))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            if metrics.speakers.count > 1 {
                HistoricalDetailBlock_iOS(title: "talk ratio", color: Color(hex: "58A6FF"), info: .talkRatio) {
                    HStack(spacing: 8) {
                        Text("you \(Int(metrics.talkRatioYou * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(ColorPalette.Text.primary)
                        Text("•")
                            .foregroundStyle(ColorPalette.Text.disabled)
                        Text("others \(Int((1 - metrics.talkRatioYou) * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.disabled)
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
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(speaker.isLocalMic ? ColorPalette.Accent.green : ColorPalette.Text.muted)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.primary)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.disabled)
            }
        }
    }
}
