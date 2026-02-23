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
        HStack(spacing: 0) {
            ForEach(InsightsMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.switchInsightsMode(to: mode)
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(mode.displayName)
                            .font(.system(size: 10, weight: appState.insightsMode == mode ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(appState.insightsMode == mode ? Color(hex: "E6EDF3") : Color(hex: "8B949E"))
                        
                        Rectangle()
                            .fill(appState.insightsMode == mode ? Color(hex: "3FB950") : Color.clear)
                            .frame(height: 2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Mode description
            Text(appState.insightsMode.description)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(hex: "484F58"))
                .padding(.trailing, 12)
        }
        .background(Color(hex: "0F0F11"))
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
                        TerminalSection(title: "action_items", color: Color(hex: "3FB950")) {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if appState.insightsMode == .training {
                    if let metrics = appState.trainingMetrics {
                        LiveTrainingContent_iOSPlain(metrics: metrics)
                    } else {
                        TrainingEmptyState()
                    }
                } else if appState.insightsMode == .meddpicc {
                    LiveMEDDPICCContent_iOSPlain()
                    
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
                        InsightsPlainBlock_iOS(title: "action_items", color: Color(hex: "3FB950")) {
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
    }
}

private struct LiveMEDDPICCContent_iOSPlain: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        InsightsPlainBlock_iOS(title: "MEDDPICC", color: Color(hex: "F59E0B")) {
            VStack(alignment: .leading, spacing: 10) {
                MEDDPICCLiveRow_iOS(letter: "M", title: "Metrics", value: appState.liveMetrics, color: "3B82F6")
                MEDDPICCLiveRow_iOS(letter: "E", title: "Economic Buyer", value: appState.liveEconomicBuyer, color: "8B5CF6")
                MEDDPICCLiveRow_iOS(letter: "D", title: "Decision Criteria", value: appState.liveDecisionCriteria, color: "EC4899")
                MEDDPICCLiveRow_iOS(letter: "D", title: "Decision Process", value: appState.liveDecisionProcess, color: "F59E0B")
                MEDDPICCLiveRow_iOS(letter: "P", title: "Paper Process", value: appState.livePaperProcess, color: "F97316")
                MEDDPICCLiveRow_iOS(letter: "I", title: "Identified Pain", value: appState.liveIdentifiedPain, color: "EF4444")
                MEDDPICCLiveRow_iOS(letter: "C", title: "Champion", value: appState.liveChampion, color: "22C55E")
                MEDDPICCLiveRow_iOS(letter: "C", title: "Competition", value: appState.liveCompetition, color: "6366F1")
            }
        }
    }
}

private struct MEDDPICCLiveRow_iOS: View {
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
                        .foregroundStyle(Color(hex: "E6EDF3"))
                }
                
                Text(value)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                    .lineSpacing(3)
                    .padding(.leading, 22)
            }
        }
    }
}

private struct LiveTrainingContent_iOSPlain: View {
    let metrics: TrainingMetrics
    private let externalSpeakerGroupingThreshold = 3
    
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
            InsightsPlainBlock_iOS(title: "fillers", color: Color(hex: "F59E0B")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        if speaker.totalFillers > 0 || speaker.isLocalMic {
                            TrainingMetricRow_iOS(
                                speaker: speaker,
                                value: "total \(speaker.totalFillers)",
                                trailing: "per min \(String(format: "%.1f", speaker.fillersPerMinute))"
                            )
                        }
                    }
                }
            }
            
            if metrics.speakers.count > 1 {
                InsightsPlainBlock_iOS(title: "talk_ratio", color: Color(hex: "58A6FF")) {
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
            
            InsightsPlainBlock_iOS(title: "pace", color: Color(hex: "A371F7")) {
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
            
            InsightsPlainBlock_iOS(title: "longest_monologue", color: Color(hex: "EC4899")) {
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
            
            InsightsPlainBlock_iOS(title: "questions_asked", color: Color(hex: "3FB950")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        TrainingMetricRow_iOS(
                            speaker: speaker,
                            value: "\(speaker.questionsAsked)"
                        )
                    }
                }
            }
            
            InsightsPlainBlock_iOS(title: "clarity", color: Color(hex: "D29922")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        TrainingMetricRow_iOS(
                            speaker: speaker,
                            value: String(format: "%.1f", speaker.avgWordsPerTurn),
                            trailing: "avg words/turn"
                        )
                    }
                    Text("shorter turns = more focused communication")
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
#endif

// MARK: - MEDDPICC Content

struct MEDDPICCContent: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private let meddpiccItems: [(key: String, title: String, color: String, icon: String)] = [
        ("metrics", "Metrics", "3B82F6", "📊"),
        ("economicBuyer", "Economic Buyer", "8B5CF6", "💼"),
        ("decisionCriteria", "Decision Criteria", "EC4899", "✓"),
        ("decisionProcess", "Decision Process", "F59E0B", "⚙"),
        ("identifiedPain", "Identified Pain", "EF4444", "🎯"),
        ("champion", "Champion", "22C55E", "⭐"),
        ("competition", "Competition", "6366F1", "⚔"),
    ]
    
    private var gridColumns: [GridItem] {
        if sizeClass == .compact {
            return [GridItem(.flexible())]
        } else {
            return [GridItem(.flexible()), GridItem(.flexible())]
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MEDDPICC Header
            HStack(spacing: 6) {
                Text("##")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "F59E0B"))
                Text("MEDDPICC")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "F59E0B"))
            }
            
            // Grid of MEDDPICC items — single column on compact (iPhone), 2 columns on regular (Mac/iPad)
            LazyVGrid(columns: gridColumns, spacing: 10) {
                MEDDPICCItem(title: "Metrics", value: appState.liveMetrics, color: "3B82F6")
                MEDDPICCItem(title: "Economic Buyer", value: appState.liveEconomicBuyer, color: "8B5CF6")
                MEDDPICCItem(title: "Decision Criteria", value: appState.liveDecisionCriteria, color: "EC4899")
                MEDDPICCItem(title: "Decision Process", value: appState.liveDecisionProcess, color: "F59E0B")
                MEDDPICCItem(title: "Paper Process", value: appState.livePaperProcess, color: "F97316")
                MEDDPICCItem(title: "Identify Pain", value: appState.liveIdentifiedPain, color: "EF4444")
                MEDDPICCItem(title: "Champion", value: appState.liveChampion, color: "22C55E")
                MEDDPICCItem(title: "Competition", value: appState.liveCompetition, color: "6366F1")
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

struct MEDDPICCItem: View {
    let title: String
    let value: String?
    let color: String
    
    private var hasValue: Bool {
        guard let value else { return false }
        return !value.isEmpty && value.lowercased() != "null"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(hasValue ? Color(hex: color) : Color(hex: "484F58"))
                    .frame(width: 6, height: 6)
                
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(hasValue ? Color(hex: color) : Color(hex: "484F58"))
            }
            
            if hasValue, let value {
                Text(value)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                    .lineLimit(3)
            } else {
                Text("--")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "484F58"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(hex: "09090B"))
        .cornerRadius(4)
    }
}

// MARK: - Training Content

struct TrainingContent: View {
    let metrics: TrainingMetrics
    
    private let accentColor = Color(hex: "22C55E")
    private let externalSpeakerGroupingThreshold = 3
    
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
            title: "fillers — \(speaker.speakerLabel.lowercased())",
            color: speaker.isLocalMic ? Color(hex: "F59E0B") : Color(hex: "8B949E"),
            headerStyle: .plain
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // Summary line
                HStack(spacing: 16) {
                    StatPill(label: "total", value: "\(speaker.totalFillers)")
                    StatPill(label: "per min", value: String(format: "%.1f", speaker.fillersPerMinute))
                }
                
                // Per-word breakdown with bars
                if !speaker.fillers.isEmpty {
                    let maxCount = speaker.fillers.first?.count ?? 1
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(speaker.fillers) { entry in
                            HStack(spacing: 8) {
                                Text(entry.word)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: "D4D4D8"))
                                    .frame(width: 70, alignment: .trailing)
                                
                                GeometryReader { geo in
                                    let width = max(4, geo.size.width * CGFloat(entry.count) / CGFloat(max(maxCount, 1)))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: "F59E0B").opacity(0.6))
                                        .frame(width: width, height: 14)
                                }
                                .frame(height: 14)
                                
                                Text("\(entry.count)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: "8B949E"))
                                    .frame(width: 24, alignment: .trailing)
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
        TerminalSection(title: "talk_ratio", color: Color(hex: "58A6FF"), headerStyle: .plain) {
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
        TerminalSection(title: "pace", color: Color(hex: "A371F7"), headerStyle: .plain) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(speakers) { speaker in
                    HStack {
                        Text(speaker.speakerLabel.lowercased())
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(speaker.isLocalMic ? Color(hex: "3FB950") : Color(hex: "8B949E"))
                            .frame(width: 80, alignment: .leading)
                        
                        Text("\(Int(speaker.wordsPerMinute)) wpm")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                        
                        Spacer()
                        
                        Text("\(speaker.wordCount) words")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "484F58"))
                    }
                }
            }
        }
    }
}

private struct MonologueSection: View {
    let speakers: [TrainingMetrics.SpeakerStats]
    
    var body: some View {
        TerminalSection(title: "longest_monologue", color: Color(hex: "EC4899"), headerStyle: .plain) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(speakers) { speaker in
                    if speaker.longestMonologueWords > 0 {
                        HStack {
                            Text(speaker.speakerLabel.lowercased())
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(speaker.isLocalMic ? Color(hex: "3FB950") : Color(hex: "8B949E"))
                                .frame(width: 80, alignment: .leading)
                            
                            Text("\(speaker.longestMonologueWords) words")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(hex: "E6EDF3"))
                        }
                    }
                }
            }
        }
    }
}

private struct QuestionsSection: View {
    let speakers: [TrainingMetrics.SpeakerStats]
    
    var body: some View {
        TerminalSection(title: "questions_asked", color: Color(hex: "3FB950"), headerStyle: .plain) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(speakers) { speaker in
                    HStack {
                        Text(speaker.speakerLabel.lowercased())
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(speaker.isLocalMic ? Color(hex: "3FB950") : Color(hex: "8B949E"))
                            .frame(width: 80, alignment: .leading)
                        
                        Text("\(speaker.questionsAsked)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                    }
                }
            }
        }
    }
}

private struct ClaritySection: View {
    let speakers: [TrainingMetrics.SpeakerStats]
    
    var body: some View {
        TerminalSection(title: "clarity", color: Color(hex: "D29922"), headerStyle: .plain) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(speakers) { speaker in
                    HStack {
                        Text(speaker.speakerLabel.lowercased())
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(speaker.isLocalMic ? Color(hex: "3FB950") : Color(hex: "8B949E"))
                            .frame(width: 80, alignment: .leading)
                        
                        Text(String(format: "%.1f", speaker.avgWordsPerTurn))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                        
                        Text("avg words/turn")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "484F58"))
                    }
                }
                
                Text("shorter turns = more focused communication")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "3F3F46"))
                    .padding(.top, 4)
            }
        }
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(hex: "71717A"))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "E6EDF3"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: "18181B"))
        .cornerRadius(4)
    }
}

/// Compute training metrics from a saved Meeting's segments
struct SavedTrainingContent: View {
    let meeting: Meeting
    
    private var metrics: TrainingMetrics {
        let segments = meeting.segments.map {
            TrainingMetrics.Segment(text: $0.text, speaker: $0.speaker, isFinal: $0.isFinal)
        }
        let duration = meeting.endTime?.timeIntervalSince(meeting.startTime) ?? 0
        return TrainingMetrics.compute(from: segments, duration: duration)
    }
    
    var body: some View {
        TrainingContent(metrics: metrics)
    }
}

struct TerminalInsightsContent: View {
    let meeting: Meeting
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                if let summary = meeting.summaryText {
                    TerminalSection(title: "summary", color: Color(hex: "58A6FF")) {
                        Text(summary)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                            .lineSpacing(6)
                    }
                }
                
                // Action Items
                if !meeting.actionItems.isEmpty {
                    TerminalSection(title: "action_items", color: Color(hex: "3FB950")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(meeting.actionItems.enumerated()), id: \.offset) { index, item in
                                TerminalListItem(index: index, text: item, style: .checkbox)
                            }
                        }
                    }
                }
                
                // Key Decisions
                if !meeting.keyDecisions.isEmpty {
                    TerminalSection(title: "decisions", color: Color(hex: "D29922")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(meeting.keyDecisions.enumerated()), id: \.offset) { index, decision in
                                TerminalListItem(index: index, text: decision, style: .arrow)
                            }
                        }
                    }
                }
                
                // Topics
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
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        color: Color,
        headerStyle: HeaderStyle = .markdown,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.color = color
        self.headerStyle = headerStyle
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
        Text("[\(text.lowercased().replacingOccurrences(of: " ", with: "_"))]")
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
            
            Text("generating_insights\(dots)")
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
            
            Text("no_insights")
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
                .disabled(appState.openaiApiKey.isEmpty)
                .padding(.top, 8)
                
                if appState.openaiApiKey.isEmpty {
                    HStack(spacing: 6) {
                        Text("⚠")
                            .foregroundStyle(Color(hex: "D29922"))
                        Text("openai_api_key not set")
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
        TerminalSection(title: title.lowercased().replacingOccurrences(of: " ", with: "_"), color: color, content: content)
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
