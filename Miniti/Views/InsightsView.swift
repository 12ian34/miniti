import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // Mode Selector (macOS only — iOS has its own mode picker in MeetingView_iOS)
            InsightsModeSelector()
            
            Divider()
                .background(Color(hex: "1C1C1F"))
            #endif
            
            // Content
            Group {
                if appState.isRecording || !appState.liveSummary.isEmpty {
                    LiveInsightsContent()
                } else if let meeting = appState.currentMeeting, meeting.hasInsights {
                    TerminalInsightsContent(meeting: meeting)
                } else if appState.isGeneratingInsights {
                    TerminalGeneratingView()
                } else {
                    TerminalNoInsightsView()
                }
            }
        }
        .background(Color(hex: "09090B"))
    }
}

// MARK: - Mode Selector

struct InsightsModeSelector: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        InsightsModeTabs(
            selectedMode: Binding(
                get: { appState.insightsMode },
                set: { appState.switchInsightsMode(to: $0) }
            )
        )
    }
}

struct InsightsModeTabs: View {
    @Binding var selectedMode: InsightsMode
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(InsightsMode.allCases.enumerated()), id: \.element) { index, mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(mode.displayName)
                            .font(.system(size: 10, weight: selectedMode == mode ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(selectedMode == mode ? Color(hex: "E6EDF3") : Color(hex: "8B949E"))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        Text("⌘\(index + 1)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(selectedMode == mode ? Color(hex: "E6EDF3").opacity(0.4) : Color(hex: "8B949E").opacity(0.5))
                            .fixedSize()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedMode == mode ? Color(hex: "3FB950").opacity(0.15) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

// MARK: - Live Insights Content

struct LiveInsightsContent: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        #if os(iOS)
        LiveInsightsContent_iOSPlain()
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if appState.insightsMode == .training {
                    if let metrics = appState.trainingMetrics {
                        TrainingContent(metrics: metrics)
                    } else {
                        TrainingEmptyState()
                    }
                } else if appState.insightsMode == .meddpicc {
                    if appState.isRecording, appState.appMode == .managed, !appState.hasReceivedMeddpiccInsights {
                        Text("no meddpicc yet...")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "8B949E"))
                    }
                    MEDDPICCContent()
                    
                    if appState.isGeneratingInsights {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("updating...")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: "8B949E"))
                        }
                        .padding(.top, 8)
                    }
                } else {
                    if appState.isRecording, appState.appMode == .managed, !appState.hasReceivedStandardInsights {
                        Text("no insights yet...")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "8B949E"))
                    }
                    // Summary (always shown)
                    if !appState.liveSummary.isEmpty {
                        TerminalSection(title: "summary", color: Color(hex: "58A6FF")) {
                            Text(appState.liveSummary)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color(hex: "E6EDF3"))
                                .lineSpacing(6)
                        }
                    }
                    
                    // Action Items
                    if !appState.liveActionItems.isEmpty {
                        TerminalSection(title: "action items", color: Color(hex: "3FB950")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(appState.liveActionItems.enumerated()), id: \.offset) { index, item in
                                    TerminalListItem(index: index, text: item, style: .checkbox)
                                }
                            }
                        }
                    }
                    
                    // Topics
                    if !appState.liveTopics.isEmpty {
                        TerminalSection(title: "topics", color: Color(hex: "A371F7")) {
                            FlowLayout(spacing: 8) {
                                ForEach(appState.liveTopics, id: \.self) { topic in
                                    TerminalTag(text: topic)
                                }
                            }
                        }
                    }
                    
                    // Loading indicator
                    if appState.isGeneratingInsights {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("updating...")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: "8B949E"))
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding(20)
        }
        #endif
    }
}

#if os(iOS)
private struct LiveInsightsContent_iOSPlain: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                if appState.insightsMode == .training {
                    if let metrics = appState.trainingMetrics {
                        LiveTrainingContent_iOSPlain(metrics: metrics)
                    } else {
                        TrainingEmptyState()
                    }
                } else if appState.insightsMode == .meddpicc {
                    if appState.isRecording, appState.appMode == .managed, !appState.hasReceivedMeddpiccInsights {
                        Text("no meddpicc yet...")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "8B949E"))
                    }
                    LiveMEDDPICCContent_iOSPlain()
                } else {
                    if appState.isRecording, appState.appMode == .managed, !appState.hasReceivedStandardInsights {
                        Text("no insights yet...")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "8B949E"))
                    }
                    if !appState.liveSummary.isEmpty {
                        InsightsPlainBlock_iOS(title: "summary", color: Color(hex: "58A6FF")) {
                            Text(appState.liveSummary)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color(hex: "E6EDF3"))
                                .lineSpacing(6)
                        }
                    }
                    
                    if !appState.liveDiscussionFlow.isEmpty {
                        InsightsPlainBlock_iOS(title: "discussion", color: Color(hex: "F59E0B")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(appState.liveDiscussionFlow.enumerated()), id: \.offset) { index, item in
                                    TerminalListItem(index: index, text: item, style: .arrow)
                                }
                            }
                        }
                    }

                    if !appState.liveActionItems.isEmpty {
                        InsightsPlainBlock_iOS(title: "action items", color: Color(hex: "3FB950")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(appState.liveActionItems.enumerated()), id: \.offset) { index, item in
                                    TerminalListItem(index: index, text: item, style: .checkbox)
                                }
                            }
                        }
                    }
                    
                    if !appState.liveTopics.isEmpty {
                        InsightsPlainBlock_iOS(title: "topics", color: Color(hex: "A371F7")) {
                            FlowLayout(spacing: 8) {
                                ForEach(appState.liveTopics, id: \.self) { topic in
                                    TerminalTag(text: topic)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct LiveMEDDPICCContent_iOSPlain: View {
    @EnvironmentObject var appState: AppState
    
    private var fields: [(title: String, color: String, value: String?)] {
        [
            ("metrics", "3B82F6", appState.liveMetrics),
            ("economic buyer", "8B5CF6", appState.liveEconomicBuyer),
            ("decision criteria", "EC4899", appState.liveDecisionCriteria),
            ("decision process", "F59E0B", appState.liveDecisionProcess),
            ("paper process", "F97316", appState.livePaperProcess),
            ("identified pain", "EF4444", appState.liveIdentifiedPain),
            ("champion", "22C55E", appState.liveChampion),
            ("competition", "6366F1", appState.liveCompetition),
        ]
    }
    
    var body: some View {
        ForEach(fields.filter { hasMEDDPICCValue($0.value) }, id: \.title) { field in
            InsightsPlainBlock_iOS(title: field.title, color: Color(hex: field.color)) {
                MEDDPICCBulletText(field.value!, fontSize: 13)
            }
        }
    }
}

private struct LiveTrainingContent_iOSPlain: View {
    let metrics: TrainingMetrics
    
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
                    InsightsPlainBlock_iOS(
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
                InsightsPlainBlock_iOS(title: "talk ratio", color: Color(hex: "58A6FF"), info: .talkRatio) {
                    HStack(spacing: 8) {
                        Text("you \(Int(metrics.talkRatioYou * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                        Text("•")
                            .foregroundStyle(Color(hex: "484F58"))
                        Text("others \(Int((1 - metrics.talkRatioYou) * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "8B949E"))
                    }
                }
            }
            
            InsightsPlainBlock_iOS(title: "pace", color: Color(hex: "A371F7"), info: .pace) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        TrainingMetricRow_iOS(
                            speaker: speaker,
                            value: "\(Int(speaker.wordsPerMinute)) wpm",
                            trailing: "\(speaker.wordCount) words"
                        )
                    }
                }
            }
            
            InsightsPlainBlock_iOS(title: "longest monologue", color: Color(hex: "EC4899"), info: .longestMonologue) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        if speaker.longestMonologueWords > 0 {
                            TrainingMetricRow_iOS(
                                speaker: speaker,
                                value: "\(speaker.longestMonologueWords) words"
                            )
                        }
                    }
                }
            }
            
            InsightsPlainBlock_iOS(title: "questions asked", color: Color(hex: "3FB950"), info: .questionsAsked) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        TrainingMetricRow_iOS(
                            speaker: speaker,
                            value: "\(speaker.questionsAsked)"
                        )
                    }
                }
            }
            
            InsightsPlainBlock_iOS(title: "clarity", color: Color(hex: "D29922"), info: .clarity) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        TrainingMetricRow_iOS(
                            speaker: speaker,
                            value: String(format: "%.1f", speaker.avgWordsPerTurn),
                            trailing: "avg words/turn"
                        )
                    }
                    Text("lower = clearer = better")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "484F58"))
                }
            }
        }
    }
}

private struct TrainingMetricRow_iOS: View {
    let speaker: TrainingMetrics.SpeakerStats
    let value: String
    var trailing: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Text(speaker.speakerLabel.lowercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(speaker.isLocalMic ? Color(hex: "3FB950") : Color(hex: "8B949E"))
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "E6EDF3"))
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
            }
        }
    }
}

private struct InsightsPlainBlock_iOS<Content: View>: View {
    let title: String
    let color: Color
    let info: TerminalSectionInfo?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        color: Color,
        info: TerminalSectionInfo? = nil,
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
                    TerminalSectionInfoButton(info: info, accent: color)
                }
            }
            
            content()
                .padding(.leading, 12)
        }
    }
}
#endif

// MARK: - MEDDPICC Content

struct MEDDPICCContent: View {
    @EnvironmentObject var appState: AppState
    
    private var fields: [(title: String, color: String, value: String?)] {
        [
            ("metrics", "3B82F6", appState.liveMetrics),
            ("economic buyer", "8B5CF6", appState.liveEconomicBuyer),
            ("decision criteria", "EC4899", appState.liveDecisionCriteria),
            ("decision process", "F59E0B", appState.liveDecisionProcess),
            ("paper process", "F97316", appState.livePaperProcess),
            ("identified pain", "EF4444", appState.liveIdentifiedPain),
            ("champion", "22C55E", appState.liveChampion),
            ("competition", "6366F1", appState.liveCompetition),
        ]
    }
    
    var body: some View {
        ForEach(fields.filter { hasMEDDPICCValue($0.value) }, id: \.title) { field in
            TerminalSection(title: field.title, color: Color(hex: field.color)) {
                MEDDPICCBulletText(field.value!, fontSize: 13)
            }
        }
    }
}

private func hasMEDDPICCValue(_ value: String?) -> Bool {
    guard let value else { return false }
    let t = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !t.isEmpty && t != "null" && t != "n/a" && t != "none"
}

struct MEDDPICCBulletText: View {
    let text: String
    let fontSize: CGFloat
    let color: Color
    
    init(_ text: String, fontSize: CGFloat = 12, color: Color = Color(hex: "E6EDF3")) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
    }
    
    private var bullets: [String] {
        let lines: [String]
        if text.contains("\n") {
            lines = text.components(separatedBy: "\n")
        } else if text.contains(";") {
            lines = text.components(separatedBy: ";")
        } else {
            return [text.trimmingCharacters(in: .whitespaces)]
        }
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(color.opacity(0.5))
                    Text(bullet)
                        .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(color)
                }
            }
        }
    }
}

// MARK: - Training Content

struct TrainingContent: View {
    let metrics: TrainingMetrics
    
    private let accentColor = Color(hex: "22C55E")
    
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
            if metrics.speakers.isEmpty {
                TrainingEmptyState()
            } else {
                // Filler words (You first, then others)
                ForEach(displaySpeakers) { speaker in
                    if speaker.totalFillers > 0 || speaker.isLocalMic {
                        FillerWordsSection(speaker: speaker, durationMinutes: metrics.durationMinutes)
                    }
                }
                
                // Talk ratio (only when multiple speakers)
                if metrics.speakers.count > 1 {
                    TalkRatioSection(metrics: metrics)
                }
                
                // Pace
                PaceSection(speakers: displaySpeakers)
                
                // Monologue
                MonologueSection(speakers: displaySpeakers)
                
                // Questions
                QuestionsSection(speakers: displaySpeakers)
                
                // Clarity
                ClaritySection(speakers: displaySpeakers)
            }
        }
    }
}

struct TrainingEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("◇")
                .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(Color(hex: "1C1C1F"))
            Text("waiting for speech...")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "484F58"))
            Text("training metrics update as you speak")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(hex: "3F3F46"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

private struct FillerWordsSection: View {
    let speaker: TrainingMetrics.SpeakerStats
    let durationMinutes: Double
    
    var body: some View {
        TerminalSection(
            title: "fillers: \(speaker.speakerLabel.lowercased())",
            color: speaker.isLocalMic ? Color(hex: "F59E0B") : Color(hex: "8B949E"),
            headerStyle: .plain,
            info: .fillers
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(speaker.totalFillers) fillers (\(String(format: "%.1f", speaker.fillersPerMinute))/min)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "71717A"))
                
                if speaker.speakerLabel != "Others" && !speaker.fillers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(speaker.fillers) { entry in
                            HStack(spacing: 6) {
                                Text(entry.word)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: "D4D4D8"))
                                    .fixedSize()
                                
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

private struct TalkRatioSection: View {
    let metrics: TrainingMetrics
    
    var body: some View {
        TerminalSection(title: "talk ratio", color: Color(hex: "58A6FF"), headerStyle: .plain, info: .talkRatio) {
            VStack(alignment: .leading, spacing: 8) {
                // Bar
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "3FB950"))
                            .frame(width: max(4, geo.size.width * metrics.talkRatioYou))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "58A6FF").opacity(0.5))
                            .frame(width: max(4, geo.size.width * (1 - metrics.talkRatioYou)))
                    }
                }
                .frame(height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                
                // Labels
                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: "3FB950")).frame(width: 6, height: 6)
                        Text("you \(Int(metrics.talkRatioYou * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "D4D4D8"))
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("others \(Int((1 - metrics.talkRatioYou) * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "D4D4D8"))
                        Circle().fill(Color(hex: "58A6FF").opacity(0.5)).frame(width: 6, height: 6)
                    }
                }
            }
        }
    }
}

private struct PaceSection: View {
    let speakers: [TrainingMetrics.SpeakerStats]
    
    var body: some View {
        TerminalSection(title: "pace", color: Color(hex: "A371F7"), headerStyle: .plain, info: .pace) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(speakers) { speaker in
                    TerminalTrainingMetricRow(
                        speaker: speaker,
                        primary: "\(Int(speaker.wordsPerMinute)) wpm",
                        secondary: "\(speaker.wordCount) words"
                    )
                }
            }
        }
    }
}

private struct MonologueSection: View {
    let speakers: [TrainingMetrics.SpeakerStats]
    
    var body: some View {
        TerminalSection(title: "longest monologue", color: Color(hex: "EC4899"), headerStyle: .plain, info: .longestMonologue) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(speakers) { speaker in
                    if speaker.longestMonologueWords > 0 {
                        TerminalTrainingMetricRow(
                            speaker: speaker,
                            primary: "\(speaker.longestMonologueWords) words"
                        )
                    }
                }
            }
        }
    }
}

private struct QuestionsSection: View {
    let speakers: [TrainingMetrics.SpeakerStats]
    
    var body: some View {
        TerminalSection(title: "questions asked", color: Color(hex: "3FB950"), headerStyle: .plain, info: .questionsAsked) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(speakers) { speaker in
                    TerminalTrainingMetricRow(
                        speaker: speaker,
                        primary: "\(speaker.questionsAsked)"
                    )
                }
            }
        }
    }
}

private struct ClaritySection: View {
    let speakers: [TrainingMetrics.SpeakerStats]
    
    var body: some View {
        TerminalSection(title: "clarity", color: Color(hex: "D29922"), headerStyle: .plain, info: .clarity) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(speakers) { speaker in
                    TerminalTrainingMetricRow(
                        speaker: speaker,
                        primary: String(format: "%.1f", speaker.avgWordsPerTurn),
                        secondary: "avg words/turn"
                    )
                }
                
                Text("lower = clearer = better")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "3F3F46"))
                    .padding(.top, 4)
            }
        }
    }
}

private struct TerminalTrainingMetricRow: View {
    let speaker: TrainingMetrics.SpeakerStats
    let primary: String
    var secondary: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Text(speaker.speakerLabel.lowercased())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(speaker.isLocalMic ? Color(hex: "3FB950") : Color(hex: "8B949E"))
                .frame(width: 48, alignment: .leading)
            
            Text(primary)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: "E6EDF3"))
            
            if let secondary {
                Text(secondary)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
            }
        }
    }
}

/// Compute training metrics from a saved Meeting's segments
struct SavedTrainingContent: View {
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
        return TrainingMetrics.compute(from: segments, duration: duration, language: meeting.language)
    }
    
    var body: some View {
        TrainingContent(metrics: metrics)
    }
}

struct TerminalInsightsContent: View {
    let meeting: Meeting

    var body: some View {
        ScrollView(.vertical) {
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
                    TerminalSection(title: "action items", color: Color(hex: "3FB950")) {
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
            .padding(20)
        }
    }
}

struct TerminalSection<Content: View>: View {
    enum HeaderStyle: Equatable {
        case markdown
        case plain
    }

    let title: String
    let color: Color
    let headerStyle: HeaderStyle
    let info: TerminalSectionInfo?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        color: Color,
        headerStyle: HeaderStyle = .markdown,
        info: TerminalSectionInfo? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.color = color
        self.headerStyle = headerStyle
        self.info = info
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                if headerStyle == .markdown {
                    Text("##")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                if let info {
                    TerminalSectionInfoButton(info: info, accent: color)
                }
            }
            
            // Content
            content()
                .padding(.leading, headerStyle == .markdown ? 20 : 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "0F0F11"))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "1C1C1F"), lineWidth: 1)
                )
        )
    }
}

struct TerminalSectionInfo {
    let title: String
    let summary: String
    let guidance: [String]
    var settingsNote: String? = nil
}

struct TerminalSectionInfoButton: View {
    let info: TerminalSectionInfo
    let accent: Color

    @State private var showInfo = false
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        Button {
            showInfo.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent.opacity(0.75))
                .padding(2)
        }
        .buttonStyle(.plain)
        .help("How to read this metric")
        #if os(iOS)
        .fullScreenCover(isPresented: $showInfo) {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showInfo = false
                    }

                TerminalSectionInfoOverlayCard_iOS(info: info, accent: accent) {
                    showInfo = false
                }
                .padding(.horizontal, 20)
            }
            .background(Color.clear)
        }
        #else
        .popover(isPresented: $showInfo, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(info.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                Text(info.summary)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(hex: "C9D1D9"))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(info.guidance, id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(accent.opacity(0.8))
                                .frame(width: 5, height: 5)
                                .padding(.top, 4)
                            Text(line)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(hex: "C9D1D9"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let note = info.settingsNote {
                    Divider()
                        .background(Color(hex: "30363D"))
                    Button {
                        showInfo = false
                        openSettings()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 9))
                            Text(note)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(accent.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(width: 300, alignment: .leading)
            .background(Color(hex: "0F0F11"))
        }
        #endif
    }
}

#if os(iOS)
private struct TerminalSectionInfoOverlayCard_iOS: View {
    let info: TerminalSectionInfo
    let accent: Color
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(info.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: "C9D1D9"))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }

            Text(info.summary)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color(hex: "C9D1D9"))
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
                            .foregroundStyle(Color(hex: "C9D1D9"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let note = info.settingsNote {
                Divider()
                    .background(Color(hex: "30363D"))
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10))
                    Text(note)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(accent.opacity(0.85))
            }
        }
        .padding(16)
        .frame(maxWidth: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "0F0F11"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
        )
        .onTapGesture {
            // Prevent backdrop tap gesture from triggering when tapping inside the card.
        }
    }
}
#endif

extension TerminalSectionInfo {
    static let fillers = TerminalSectionInfo(
        title: "Fillers",
        summary: "Lower is usually better. This counts words like um, uh, like, and similar verbal placeholders.",
        guidance: [
            "Rough coaching range: under 1-3 fillers/min is usually solid.",
            "3-6/min is common in casual conversation or when thinking live.",
            "6+/min can make delivery feel less confident or less crisp.",
            "Context matters: brainstorming and interviews usually spike filler usage."
        ],
        settingsNote: "You can add or edit your own filler words in Settings → Training."
    )
    
    static let talkRatio = TerminalSectionInfo(
        title: "Talk Ratio",
        summary: "There is no single best number. Good ratio depends on your role in the conversation.",
        guidance: [
            "Presenter/demo: you may be 60-90% and that can be correct.",
            "Interview or discovery call: balanced turns (roughly 40-60%) often feels stronger.",
            "Coaching/support roles usually improve when the other person talks more.",
            "Watch sudden extremes: very high ratio can mean not leaving space."
        ]
    )
    
    static let pace = TerminalSectionInfo(
        title: "Pace",
        summary: "Words per minute (WPM). Faster is not always better; clarity usually drops when pace gets too high.",
        guidance: [
            "Common clear speaking range: ~120-170 wpm.",
            "Energetic but still understandable often lands around 150-190 wpm.",
            "Above ~200 wpm can feel rushed unless the audience is highly familiar.",
            "Below ~100 wpm can work for emphasis, but may feel slow if sustained."
        ]
    )
    
    static let longestMonologue = TerminalSectionInfo(
        title: "Longest Monologue",
        summary: "Tracks the longest uninterrupted stretch by word count. Lower is usually better in back-and-forth conversations.",
        guidance: [
            "Shorter monologues usually create more room for engagement.",
            "Long stretches are fine in demos or explanations when the listener expects it.",
            "If this keeps growing in meetings, pause and check for questions.",
            "Compare to your own baseline by meeting type, not a single fixed target."
        ]
    )
    
    static let questionsAsked = TerminalSectionInfo(
        title: "Questions Asked",
        summary: "This is directional, not a quality score. More questions can improve engagement, but only in the right context.",
        guidance: [
            "Discovery, coaching, and interviews usually benefit from more questions.",
            "Status updates and presentations may be strong even with few or no questions.",
            "Use this with talk ratio: low questions + high talk ratio can signal one-way delivery.",
            "Quality matters more than raw count."
        ]
    )
    
    static let clarity = TerminalSectionInfo(
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

// MARK: - Training Stats Overview (Home Screen)

struct TrainingStatsOverview: View {
    let meetings: [Meeting]

    private struct MeetingStats {
        let pace: Double
        let fillersPerMinute: Double
        let clarity: Double
        let questionsAsked: Int
    }

    private var recentStats: [MeetingStats] {
        let sorted = meetings
            .filter { $0.endTime != nil && !$0.segments.isEmpty }
            .sorted { $0.startTime > $1.startTime }

        var result: [MeetingStats] = []
        for meeting in sorted {
            guard result.count < 5 else { break }
            guard let duration = meeting.duration, duration > 30 else { continue }

            let segments = meeting.segments
                .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { $0.timestamp < $1.timestamp }
                .map { TrainingMetrics.Segment(text: $0.text, speaker: $0.speaker, isFinal: true, timestamp: $0.timestamp) }

            guard !segments.isEmpty else { continue }

            let metrics = TrainingMetrics.compute(from: segments, duration: duration, language: meeting.language)
            let speaker = metrics.speakers.first(where: { $0.isLocalMic })
                ?? metrics.speakers.max(by: { $0.wordCount < $1.wordCount })
            guard let speaker else { continue }

            result.append(MeetingStats(
                pace: speaker.wordsPerMinute,
                fillersPerMinute: speaker.fillersPerMinute,
                clarity: speaker.avgWordsPerTurn,
                questionsAsked: speaker.questionsAsked
            ))
        }
        return result
    }

    var body: some View {
        let stats = recentStats
        if !stats.isEmpty {
            let last = stats[0]
            let avgPace = stats.map(\.pace).reduce(0, +) / Double(stats.count)
            let avgFillers = stats.map(\.fillersPerMinute).reduce(0, +) / Double(stats.count)
            let avgClarity = stats.map(\.clarity).reduce(0, +) / Double(stats.count)
            let avgQuestions = Double(stats.map(\.questionsAsked).reduce(0, +)) / Double(stats.count)

            VStack(spacing: 2) {
                TrainingStatHeader(meetingCount: stats.count)

                VStack(spacing: 0) {
                    TrainingStatRow(
                        label: "fillers",
                        avgValue: String(format: "%.1f", avgFillers),
                        lastValue: String(format: "%.1f", last.fillersPerMinute),
                        unit: "f/min",
                        trend: trend(last: last.fillersPerMinute, avg: avgFillers),
                        color: Color(hex: "F59E0B"),
                        info: .fillers
                    )
                    TrainingStatRow(
                        label: "pace",
                        avgValue: "\(Int(avgPace))",
                        lastValue: "\(Int(last.pace))",
                        unit: "w/min",
                        trend: trend(last: last.pace, avg: avgPace),
                        color: Color(hex: "58A6FF"),
                        info: .pace
                    )
                    TrainingStatRow(
                        label: "clarity",
                        avgValue: "\(Int(avgClarity))",
                        lastValue: "\(Int(last.clarity))",
                        unit: "w/turn",
                        trend: trend(last: last.clarity, avg: avgClarity),
                        color: Color(hex: "A371F7"),
                        info: .clarity
                    )
                    TrainingStatRow(
                        label: "questions",
                        avgValue: "\(avgQuestions)",
                        lastValue: "\(last.questionsAsked)",
                        unit: "qs",
                        trend: trend(last: Double(last.questionsAsked), avg: Double(avgQuestions)),
                        color: Color(hex: "3FB950"),
                        info: .questionsAsked
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "0F0F11"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "1C1C1F"), lineWidth: 1)
                        )
                )
            }
            .frame(maxWidth: 360)
        }
    }

    enum Trend {
        case up, down, same
    }

    fileprivate func trend(last: Double, avg: Double) -> Trend {
        guard avg > 0 else { return .same }
        let ratio = last / avg
        if ratio > 1.10 { return .up }
        if ratio < 0.90 { return .down }
        return .same
    }
}

private struct TrainingStatHeader: View {
    let meetingCount: Int

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 100, height: 1)

            Spacer(minLength: 4)

            Text("last \(meetingCount)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "52525B"))
                .frame(width: TrainingStatRow.colWidth)

            Spacer(minLength: 8)

            Text("last 1")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "52525B"))
                .frame(width: TrainingStatRow.colWidth)

            Color.clear
                .frame(width: 28, height: 1)
        }
        .padding(.horizontal, 12)
    }
}

private struct TrainingStatRow: View {
    let label: String
    let avgValue: String
    let lastValue: String
    let unit: String
    let trend: TrainingStatsOverview.Trend
    let color: Color
    let info: TerminalSectionInfo

    private var trendIcon: String {
        switch trend {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .same: return "arrow.right"
        }
    }

    fileprivate static let numWidth: CGFloat = 36
    fileprivate static let unitWidth: CGFloat = 42
    fileprivate static let colWidth: CGFloat = numWidth + 4 + unitWidth

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: 12)
                    .cornerRadius(1)
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                TerminalSectionInfoButton(info: info, accent: color)
            }
            .frame(width: 100, alignment: .leading)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Text(avgValue)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "A1A1AA"))
                    .frame(width: Self.numWidth, alignment: .trailing)
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "52525B"))
                    .frame(width: Self.unitWidth, alignment: .leading)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text(lastValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .frame(width: Self.numWidth, alignment: .trailing)
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "52525B"))
                    .frame(width: Self.unitWidth, alignment: .leading)
            }

            Image(systemName: trendIcon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "71717A"))
                .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct TerminalListItem: View {
    let index: Int
    let text: String
    let style: ListStyle
    
    @State private var isCompleted = false
    
    enum ListStyle {
        case checkbox
        case arrow
        case bullet
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch style {
            case .checkbox:
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isCompleted.toggle()
                    }
                } label: {
                    Text(isCompleted ? "[x]" : "[ ]")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(isCompleted ? Color(hex: "3FB950") : Color(hex: "484F58"))
                }
                .buttonStyle(.plain)
                .focusable(false)
            case .arrow:
                Text("->")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "D29922"))
            case .bullet:
                Text("•")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
            }
            
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(isCompleted ? Color(hex: "484F58") : Color(hex: "E6EDF3"))
                .strikethrough(isCompleted)
        }
    }
}

struct TerminalTag: View {
    let text: String
    
    var body: some View {
        Text("#\(text.lowercased().replacingOccurrences(of: "_", with: " "))")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(hex: "A371F7"))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: "A371F7").opacity(0.15))
            .cornerRadius(4)
    }
}

struct TerminalGeneratingView: View {
    @State private var dots = ""
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 16) {
            Text("⟳")
                .font(.system(size: 32, weight: .light, design: .monospaced))
                .foregroundStyle(Color(hex: "58A6FF"))
                .rotationEffect(.degrees(Double(dots.count) * 90))
                .animation(.linear(duration: 0.4), value: dots)
            
            Text("generating insights\(dots)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "8B949E"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            if dots.count >= 3 {
                dots = ""
            } else {
                dots += "."
            }
        }
    }
}

struct TerminalNoInsightsView: View {
    @EnvironmentObject var appState: AppState
    
    private var hasTranscript: Bool {
        !appState.liveSegments.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("◇")
                .font(.system(size: 40, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(Color(hex: "1C1C1F"))
            
            Text("no insights")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "8B949E"))
            
            if hasTranscript {
                Text("$ generate --from=transcript")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
                
                Button {
                    Task {
                        await appState.generateInsights()
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
                .focusable(false)
                .disabled(appState.appMode == .byok && appState.openaiApiKey.isEmpty)
                .padding(.top, 8)

                if appState.appMode == .byok && appState.openaiApiKey.isEmpty {
                    HStack(spacing: 6) {
                        Text("⚠")
                            .foregroundStyle(Color(hex: "D29922"))
                        Text("openai api key not set")
                            .foregroundStyle(Color(hex: "D29922"))
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            } else {
                Text("record a session first")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Flow Layout (keep for compatibility)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var positions: [CGPoint] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                
                self.size.width = max(self.size.width, currentX)
            }
            
            self.size.height = currentY + lineHeight
        }
    }
}

// Legacy components kept for compatibility
struct InsightSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        TerminalSection(title: title.lowercased(), color: color, content: content)
    }
}

struct ActionItemRow: View {
    let text: String
    var body: some View {
        TerminalListItem(index: 0, text: text, style: .checkbox)
    }
}

struct BulletPoint: View {
    let text: String
    var body: some View {
        TerminalListItem(index: 0, text: text, style: .arrow)
    }
}

struct TopicTag: View {
    let text: String
    var body: some View {
        TerminalTag(text: text)
    }
}

#Preview("With Insights") {
    let appState = AppState()
    let meeting = Meeting()
    meeting.summaryText = "The team discussed the upcoming API integration project. Key focus areas include authentication, rate limiting, and documentation."
    meeting.actionItems = [
        "Review API documentation by Friday",
        "Set up development environment",
        "Schedule follow-up with backend team"
    ]
    meeting.keyDecisions = [
        "Use OAuth 2.0 for authentication",
        "Implement rate limiting at 1000 req/min"
    ]
    meeting.topics = ["API Integration", "Auth", "Rate Limiting"]
    appState.currentMeeting = meeting
    
    return InsightsView()
        .environmentObject(appState)
        .frame(width: 700, height: 500)
}

#Preview("Empty") {
    InsightsView()
        .environmentObject(AppState())
        .frame(width: 700, height: 400)
}
