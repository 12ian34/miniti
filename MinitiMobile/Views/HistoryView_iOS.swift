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
                        HistoricalDetailBlock_iOS(title: "discussion", color: Color(hex: "D29922")) {
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
                    subtitle: "use generate/update above"
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
                    subtitle: "use generate/update above"
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
    
    var body: some View {
        HistoricalDetailBlock_iOS(title: "MEDDPICC", color: Color(hex: "F59E0B")) {
            VStack(alignment: .leading, spacing: 10) {
                MEDDPICCSavedRow_iOS(letter: "M", title: "Metrics", value: meeting.meddpiccMetrics, color: "3B82F6")
                MEDDPICCSavedRow_iOS(letter: "E", title: "Economic Buyer", value: meeting.meddpiccEconomicBuyer, color: "8B5CF6")
                MEDDPICCSavedRow_iOS(letter: "D", title: "Decision Criteria", value: meeting.meddpiccDecisionCriteria, color: "EC4899")
                MEDDPICCSavedRow_iOS(letter: "D", title: "Decision Process", value: meeting.meddpiccDecisionProcess, color: "F59E0B")
                MEDDPICCSavedRow_iOS(letter: "P", title: "Paper Process", value: meeting.meddpiccPaperProcess, color: "F97316")
                MEDDPICCSavedRow_iOS(letter: "I", title: "Identified Pain", value: meeting.meddpiccIdentifiedPain, color: "EF4444")
                MEDDPICCSavedRow_iOS(letter: "C", title: "Champion", value: meeting.meddpiccChampion, color: "22C55E")
                MEDDPICCSavedRow_iOS(letter: "C", title: "Competition", value: meeting.meddpiccCompetition, color: "6366F1")
            }
        }
    }
}

// MARK: - Historical Training Content (iOS, desktop-style rows)

struct HistoricalSavedTrainingContent_iOS: View {
    let meeting: Meeting
    
    private let externalSpeakerGroupingThreshold = 3
    
    private var metrics: TrainingMetrics {
        let segments = meeting.segments.map {
            TrainingMetrics.Segment(text: $0.text, speaker: $0.speaker, isFinal: $0.isFinal)
        }
        let duration = meeting.endTime?.timeIntervalSince(meeting.startTime) ?? 0
        return TrainingMetrics.compute(from: segments, duration: duration)
    }
    
    private var displaySpeakers: [TrainingMetrics.SpeakerStats] {
        let externalSpeakers = metrics.speakers.filter { !$0.isLocalMic }
        guard externalSpeakers.count > externalSpeakerGroupingThreshold else {
            return metrics.speakers
        }
        
        let localSpeakers = metrics.speakers.filter(\.isLocalMic)
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
            HistoricalDetailBlock_iOS(title: "fillers", color: Color(hex: "F59E0B")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        if speaker.totalFillers > 0 || speaker.isLocalMic {
                            HistoricalTrainingMetricRow_iOS(
                                speaker: speaker,
                                value: "total \(speaker.totalFillers)",
                                trailing: "per min \(String(format: "%.1f", speaker.fillersPerMinute))"
                            )
                        }
                    }
                }
            }
            
            if metrics.speakers.count > 1 {
                HistoricalDetailBlock_iOS(title: "talk_ratio", color: Color(hex: "58A6FF")) {
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
            
            HistoricalDetailBlock_iOS(title: "pace", color: Color(hex: "A371F7")) {
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
            
            HistoricalDetailBlock_iOS(title: "longest_monologue", color: Color(hex: "EC4899")) {
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
            
            HistoricalDetailBlock_iOS(title: "questions_asked", color: Color(hex: "3FB950")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        HistoricalTrainingMetricRow_iOS(
                            speaker: speaker,
                            value: "\(speaker.questionsAsked)"
                        )
                    }
                }
            }
            
            HistoricalDetailBlock_iOS(title: "clarity", color: Color(hex: "D29922")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        HistoricalTrainingMetricRow_iOS(
                            speaker: speaker,
                            value: String(format: "%.1f", speaker.avgWordsPerTurn),
                            trailing: "avg words/turn"
                        )
                    }
                    Text("shorter turns = more focused communication")
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
    @ViewBuilder let content: () -> Content
    
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
            }
            
            content()
                .padding(.leading, 12)
        }
    }
}

private struct MEDDPICCSavedRow_iOS: View {
    let letter: String
    let title: String
    let value: String?
    let color: String
    
    private var hasValue: Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !trimmed.isEmpty && trimmed != "null" && trimmed != "n/a" && trimmed != "none"
    }
    
    var body: some View {
        if hasValue, let value {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(letter)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: color))
                        .frame(width: 16, height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: color).opacity(0.15))
                        )
                    
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.primary)
                }
                
                Text(value)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .lineSpacing(3)
                    .padding(.leading, 22)
            }
        }
    }
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
