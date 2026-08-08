import SwiftUI
import Charts

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

#if os(macOS)
struct InsightsModeSelector: View {
    var body: some View {
        InsightsModeTabs()
    }
}

struct InsightsModeTabs: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings

    private var selectedSpecialist: InsightsMode? {
        appState.insightsMode.isSpecialist ? appState.insightsMode : nil
    }

    var body: some View {
        HStack {
            MinitiTabStripSurface {
                HStack(spacing: 0) {
                    ForEach(InsightsMode.coreModes, id: \.self) { mode in
                        modeButton(mode)
                    }

                    Rectangle()
                        .fill(ColorPalette.Border.primary)
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, MinitiDesignSystem.Spacing.compact)

                    specialistMenu
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, MinitiDesignSystem.Spacing.standard)
        .padding(.vertical, MinitiDesignSystem.Spacing.standard)
    }

    private func modeButton(_ mode: InsightsMode) -> some View {
        let isSelected = appState.insightsMode == mode
        return Button {
            appState.switchInsightsMode(to: mode)
        } label: {
            MinitiTabLabel(title: mode.displayName, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(mode.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var specialistMenu: some View {
        Menu {
            Section("Specialist views") {
                specialistButton(.meddpicc)

                if appState.validatedDocsMCPURL != nil || appState.playbookInsightsEnabled {
                    specialistButton(.docs)
                } else {
                    Button {
                        appState.selectedSettingsTab = "integrations"
                        openSettings()
                    } label: {
                        Label("Set Up Playbook…", systemImage: "gearshape")
                    }
                }
            }

            if appState.salesInsightsEnabled || appState.playbookInsightsEnabled {
                Divider()
                Section("Enabled specialist views") {
                    if appState.salesInsightsEnabled {
                        Button {
                            appState.setInsightModeEnabled(.meddpicc, enabled: false)
                        } label: {
                            Label("Turn Off Sales Insights", systemImage: "eye.slash")
                        }
                    }

                    if appState.playbookInsightsEnabled {
                        Button {
                            appState.setInsightModeEnabled(.docs, enabled: false)
                        } label: {
                            Label("Hide Playbook", systemImage: "eye.slash")
                        }
                    }
                }
            }
        } label: {
            MinitiTabLabel(
                title: selectedSpecialist?.displayName ?? "More",
                isSelected: selectedSpecialist != nil
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Specialist insight views")
        .accessibilityLabel(selectedSpecialist.map { "Specialist view: \($0.displayName), selected" } ?? "More insight views")
    }

    private func specialistButton(_ mode: InsightsMode) -> some View {
        Button {
            appState.switchInsightsMode(to: mode)
        } label: {
            Label {
                Text("\(mode.displayName) — \(mode.description)")
            } icon: {
                Image(systemName: appState.insightsMode == mode ? "checkmark.circle.fill" : mode.systemImage)
            }
        }
    }
}
#endif

// MARK: - Live Insights Content

struct LiveInsightsContent: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.interfaceScale) private var interfaceScale
    
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
                } else if appState.insightsMode == .questions {
                    if !appState.liveQuestions.isEmpty {
                        QuestionsContent(questions: appState.liveQuestions)
                    } else if appState.isRecording && !appState.hasReceivedQuestionsInsights {
                        QuestionsEmptyState(variant: .waiting)
                    } else {
                        QuestionsEmptyState(variant: appState.isRecording ? .needsMore : .noQuestions)
                    }
                } else if appState.insightsMode == .docs {
                    DocsTabContent(
                        topics: appState.liveDocTopics,
                        isExtracting: appState.isExtractingDocsTopics,
                        hasMCPURL: appState.validatedDocsMCPURL != nil,
                        autoLookup: appState.canAutoLookupDocs,
                        lookupsRemaining: appState.docsLookupsRemaining,
                        canRefresh: appState.canLookupDocs,
                        errorMessage: appState.docsLookupError,
                        onRefresh: {
                            Task { @MainActor in await appState.refreshDocsTopics() }
                        },
                        onLookup: { topicID in
                            Task { @MainActor in await appState.lookupDocTopic(id: topicID) }
                        }
                    )
                } else if appState.insightsMode == .meddpicc {
                    if appState.isRecording, appState.appMode == .managed, !appState.hasReceivedMeddpiccInsights {
                        Text("no sales insights yet…")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(Color(hex: "8B949E"))
                    }
                    MEDDPICCContent()
                    
                    if appState.isGeneratingInsights {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("updating...")
                                .font(.system(size: 11, weight: .medium, design: .default))
                                .foregroundStyle(Color(hex: "8B949E"))
                        }
                        .padding(.top, 8)
                    }
                } else {
                    if appState.isRecording, appState.appMode == .managed, !appState.hasReceivedStandardInsights {
                        Text("no insights yet...")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(Color(hex: "8B949E"))
                    }
                    // Summary (always shown)
                    if !appState.liveSummary.isEmpty {
                        TerminalSection(title: "summary", color: Color(hex: "58A6FF")) {
                            SelectableTextView(
                                SelectableAttributed.body(
                                    appState.liveSummary,
                                    fontSize: interfaceScale.insightBodySize,
                                    lineSpacing: interfaceScale.insightLineSpacing
                                )
                            )
                        }
                    }

                    // Action Items
                    if !appState.liveActionItems.isEmpty {
                        TerminalSection(title: "action items", color: Color(hex: "3FB950")) {
                            SelectableTextView(
                                SelectableAttributed.bulletList(
                                    items: appState.liveActionItems,
                                    prefix: "→",
                                    prefixColor: Color(hex: "3FB950"),
                                    fontSize: interfaceScale.insightBodySize
                                )
                            )
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
                                .font(.system(size: 11, weight: .medium, design: .default))
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
    @Environment(\.interfaceScale) private var interfaceScale

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                if appState.insightsMode == .training {
                    if let metrics = appState.trainingMetrics {
                        LiveTrainingContent_iOSPlain(metrics: metrics)
                    } else {
                        TrainingEmptyState()
                    }
                } else if appState.insightsMode == .questions {
                    if !appState.liveQuestions.isEmpty {
                        QuestionsContent(questions: appState.liveQuestions)
                    } else if appState.isRecording && !appState.hasReceivedQuestionsInsights {
                        QuestionsEmptyState(variant: .waiting)
                    } else {
                        QuestionsEmptyState(variant: appState.isRecording ? .needsMore : .noQuestions)
                    }
                } else if appState.insightsMode == .docs {
                    DocsTabContent(
                        topics: appState.liveDocTopics,
                        isExtracting: appState.isExtractingDocsTopics,
                        hasMCPURL: appState.validatedDocsMCPURL != nil,
                        autoLookup: appState.canAutoLookupDocs,
                        lookupsRemaining: appState.docsLookupsRemaining,
                        canRefresh: appState.canLookupDocs,
                        errorMessage: appState.docsLookupError,
                        onRefresh: {
                            Task { @MainActor in await appState.refreshDocsTopics() }
                        },
                        onLookup: { topicID in
                            Task { @MainActor in await appState.lookupDocTopic(id: topicID) }
                        }
                    )
                } else if appState.insightsMode == .meddpicc {
                    if appState.isRecording, appState.appMode == .managed, !appState.hasReceivedMeddpiccInsights {
                        Text("no sales insights yet…")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(Color(hex: "8B949E"))
                    }
                    LiveMEDDPICCContent_iOSPlain()
                } else {
                    if appState.isRecording, appState.appMode == .managed, !appState.hasReceivedStandardInsights {
                        Text("no insights yet...")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(Color(hex: "8B949E"))
                    }
                    if !appState.liveSummary.isEmpty {
                        InsightsPlainBlock_iOS(title: "summary", color: Color(hex: "58A6FF")) {
                            SelectableTextView(
                                SelectableAttributed.body(
                                    appState.liveSummary,
                                    fontSize: interfaceScale.insightBodySize,
                                    lineSpacing: interfaceScale.insightLineSpacing
                                )
                            )
                        }
                    }

                    if !appState.liveDiscussionFlow.isEmpty {
                        InsightsPlainBlock_iOS(title: "discussion", color: Color(hex: "F59E0B")) {
                            SelectableTextView(
                                SelectableAttributed.bulletList(
                                    items: appState.liveDiscussionFlow,
                                    prefix: "->",
                                    prefixColor: Color(hex: "D29922"),
                                    fontSize: interfaceScale.insightBodySize
                                )
                            )
                        }
                    }

                    if !appState.liveActionItems.isEmpty {
                        InsightsPlainBlock_iOS(title: "action items", color: Color(hex: "3FB950")) {
                            SelectableTextView(
                                SelectableAttributed.bulletList(
                                    items: appState.liveActionItems,
                                    prefix: "→",
                                    prefixColor: Color(hex: "3FB950"),
                                    fontSize: interfaceScale.insightBodySize
                                )
                            )
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
                        color: speaker.isLocalMic ? ColorPalette.Coaching.fillers : ColorPalette.Text.meta,
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
                            
                            if speaker.speakerLabel != "Others" && !speaker.fillers.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(speaker.fillers) { entry in
                                        HStack(spacing: 6) {
                                            Text(entry.word)
                                                .font(.system(size: 11, weight: .medium, design: .default))
                                                .foregroundStyle(Color(hex: "D4D4D8"))
                                                .frame(width: 70, alignment: .trailing)
                                            Text("\(entry.count)")
                                                .font(.system(size: 11, weight: .semibold, design: .default))
                                                .foregroundStyle(ColorPalette.Coaching.fillers)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            if metrics.speakers.count > 1 {
                InsightsPlainBlock_iOS(title: "talk ratio", color: ColorPalette.Coaching.talkRatio, info: .talkRatio) {
                    HStack(spacing: 8) {
                        Text("you \(Int(metrics.talkRatioYou * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                        Text("•")
                            .foregroundStyle(Color(hex: "484F58"))
                        Text("others \(Int((1 - metrics.talkRatioYou) * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(Color(hex: "8B949E"))
                    }
                }
            }
            
            InsightsPlainBlock_iOS(title: "pace", color: ColorPalette.Coaching.pace, info: .pace) {
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
            
            InsightsPlainBlock_iOS(title: "longest monologue", color: ColorPalette.Coaching.monologue, info: .longestMonologue) {
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
            
            InsightsPlainBlock_iOS(title: "questions asked", color: ColorPalette.Coaching.questions, info: .questionsAsked) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        TrainingMetricRow_iOS(
                            speaker: speaker,
                            value: "\(speaker.questionsAsked)"
                        )
                    }
                }
            }
            
            InsightsPlainBlock_iOS(title: "clarity", color: ColorPalette.Coaching.clarity, info: .clarity) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        TrainingMetricRow_iOS(
                            speaker: speaker,
                            value: String(format: "%.1f", speaker.avgWordsPerTurn),
                            trailing: "avg words/turn"
                        )
                    }
                    Text("lower = clearer = better")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Color(hex: "484F58"))
                }
            }
        }
    }
}

private struct TrainingMetricRow_iOS: View {
    @Environment(\.interfaceScale) private var interfaceScale
    let speaker: TrainingMetrics.SpeakerStats
    let value: String
    var trailing: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Text(speaker.speakerLabel.lowercased())
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(speaker.isLocalMic ? Color(hex: "3FB950") : Color(hex: "8B949E"))
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: interfaceScale.insightBodySize, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "E6EDF3"))
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.system(size: interfaceScale.insightSecondarySize, weight: .regular, design: .default))
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
                    .font(.system(size: 12, weight: .semibold, design: .default))
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

// MARK: - Questions Empty State

struct QuestionsEmptyState: View {
    enum Variant {
        case waiting
        case needsMore
        case noQuestions
    }

    let variant: Variant

    var body: some View {
        VStack(spacing: 12) {
            Text("?")
                .font(.system(size: 28, weight: .ultraLight, design: .default))
                .foregroundStyle(Color(hex: "58A6FF").opacity(0.3))

            switch variant {
            case .waiting:
                Text("generating questions...")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "58A6FF"))
                ProgressView()
                    .controlSize(.small)
            case .needsMore:
                Text("needs more conversation")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "8B949E"))
                Text("questions appear once there's enough\nto find gaps and unstated assumptions")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                    .multilineTextAlignment(.center)
            case .noQuestions:
                Text("no questions yet")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "8B949E"))
                Text("use update above to generate, or\nrecord a longer conversation")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

// MARK: - Questions Content

struct QuestionsContent: View {
    let questions: [SuggestedQuestion]

    private static let typeColors: [String: String] = [
        "deeper": "58A6FF",
        "challenge": "F85149",
        "reframe": "D2A8FF",
        "clarify": "FFA657",
        "explore": "3FB950",
        "follow_up": "79C0FF"
    ]

    var body: some View {
        if !questions.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(questions) { q in
                    QuestionCard(question: q, typeColor: Color(hex: Self.typeColors[q.type] ?? "8B949E"))
                }
            }
        }
    }
}

private struct QuestionCard: View {
    @Environment(\.interfaceScale) private var interfaceScale
    let question: SuggestedQuestion
    let typeColor: Color

    @State private var showCopied = false

    private var typeLabel: String {
        question.type.replacingOccurrences(of: "_", with: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(typeColor)
                    .frame(width: 3, height: 12)
                    .cornerRadius(1)
                Text(typeLabel)
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundStyle(typeColor)

                Spacer()

                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(question.question, forType: .string)
                    #else
                    UIPasteboard.general.string = question.question
                    #endif
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                        Text(showCopied ? "copied" : "copy")
                            .font(.system(size: 10, weight: .medium, design: .default))
                    }
                    .foregroundStyle(showCopied ? Color(hex: "3FB950") : Color(hex: "52525B"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "1C1C1F"))
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            Text(question.question)
                .font(.system(size: interfaceScale.insightBodySize, weight: .regular, design: .default))
                .foregroundStyle(Color(hex: "E6EDF3"))
                .lineSpacing(interfaceScale.insightLineSpacing)
                .textSelection(.enabled)
                .padding(.leading, 12)

            Rectangle()
                .fill(Color(hex: "1C1C1F"))
                .frame(height: 1)
                .padding(.leading, 12)

            Text(question.context)
                .font(.system(size: interfaceScale.insightSecondarySize, weight: .regular, design: .default))
                .foregroundStyle(Color(hex: "484F58"))
                .lineSpacing(interfaceScale.insightLineSpacing)
                .padding(.leading, 12)
        }
    }
}

// MARK: - Docs Topics Content

struct DocsEmptyState: View {
    enum Variant {
        case needsSetup
        case idle(auto: Bool)
        case extracting
        case error(String)
    }

    let variant: Variant

    #if os(macOS)
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        VStack(spacing: 8) {
            Text("◇")
                .font(.system(size: 20, weight: .light, design: .default))
                .foregroundStyle(Color(hex: "484F58"))
            switch variant {
            case .needsSetup:
                Text("add a docs MCP URL")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "8B949E"))
                #if os(macOS)
                Button {
                    appState.selectedSettingsTab = "integrations"
                    openSettings()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 9, weight: .semibold))
                        Text("open Settings → Docs MCP")
                            .font(.system(size: 10, weight: .semibold, design: .default))
                    }
                    .foregroundStyle(Color(hex: "D4D4D8"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: "18181B")))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "27272A"), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                #else
                Text("Settings → Integrations → Docs MCP")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "8B949E"))
                    .multilineTextAlignment(.center)
                #endif
                Text("e.g. https://docs.lightdash.com/mcp")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                    .multilineTextAlignment(.center)
            case .idle(let auto):
                Text("topics will appear as you talk")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "8B949E"))
                Text(auto ? "each one looks itself up in your docs" : "tap a topic to look it up in your docs")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                    .multilineTextAlignment(.center)
            case .extracting:
                ProgressView()
                    .controlSize(.small)
                Text("finding topics...")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "8B949E"))
            case .error(let message):
                Text("docs unavailable")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "8B949E"))
                Text(message)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

struct DocsTabContent: View {
    let topics: [DocTopic]
    let isExtracting: Bool
    let hasMCPURL: Bool
    let autoLookup: Bool
    let lookupsRemaining: Int?
    let canRefresh: Bool
    let errorMessage: String?
    let onRefresh: () -> Void
    let onLookup: (String) -> Void

    init(
        topics: [DocTopic],
        isExtracting: Bool,
        hasMCPURL: Bool,
        autoLookup: Bool,
        lookupsRemaining: Int? = nil,
        canRefresh: Bool = true,
        errorMessage: String? = nil,
        onRefresh: @escaping () -> Void,
        onLookup: @escaping (String) -> Void
    ) {
        self.topics = topics
        self.isExtracting = isExtracting
        self.hasMCPURL = hasMCPURL
        self.autoLookup = autoLookup
        self.lookupsRemaining = lookupsRemaining
        self.canRefresh = canRefresh
        self.errorMessage = errorMessage
        self.onRefresh = onRefresh
        self.onLookup = onLookup
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if hasMCPURL {
                header
            }

            if !hasMCPURL {
                DocsEmptyState(variant: .needsSetup)
            } else if topics.isEmpty {
                if isExtracting {
                    DocsEmptyState(variant: .extracting)
                } else if let errorMessage {
                    DocsEmptyState(variant: .error(errorMessage))
                } else {
                    DocsEmptyState(variant: .idle(auto: autoLookup))
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(topics) { topic in
                        DocTopicRow(
                            topic: topic,
                            autoLookup: autoLookup,
                            onLookup: { onLookup(topic.id) }
                        )
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Color(hex: "F85149"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onRefresh) {
                HStack(spacing: 6) {
                    if isExtracting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    Text(isExtracting ? "finding topics…" : (topics.isEmpty ? "find topics" : "refresh"))
                        .font(.system(size: 10, weight: .semibold, design: .default))
                }
                .foregroundStyle(Color(hex: "D4D4D8"))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: "18181B")))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "27272A"), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!canRefresh || isExtracting)
            .opacity((!canRefresh || isExtracting) ? 0.5 : 1.0)

            Spacer()

            quotaBadge
        }
    }

    @ViewBuilder
    private var quotaBadge: some View {
        if autoLookup {
            Text("auto")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(Color(hex: "3FB950"))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "14251A")))
        } else if let remaining = lookupsRemaining {
            Text("\(remaining) lookup\(remaining == 1 ? "" : "s") left")
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(remaining <= 0 ? Color(hex: "F85149") : Color(hex: "8B949E"))
        }
    }
}

/// One topic in the docs tab: shows its lookup state, expands to the grounded
/// answer when resolved, and is tappable to look up / retry when it isn't.
private struct DocTopicRow: View {
    let topic: DocTopic
    let autoLookup: Bool
    let onLookup: () -> Void
    @State private var expanded = true

    private var accentColor: Color {
        (topic.card?.isHighPriority ?? false) ? Color(hex: "F85149") : Color(hex: "58A6FF")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: rowTapped) {
                HStack(spacing: 8) {
                    stateIndicator
                    Text(topic.label)
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(topic.lookupState == .answered ? accentColor : Color(hex: "C9D1D9"))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    trailingControl
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(topic.lookupState == .lookingUp)

            if topic.lookupState == .answered, let card = topic.card, expanded {
                DocAnswerBody(card: card)
                    .padding(.leading, 20)
            } else if topic.lookupState == .busy {
                // Transient: keep any prior answer visible, and make the retry clear.
                if let card = topic.card {
                    DocAnswerBody(card: card)
                        .padding(.leading, 20)
                }
                Text(topic.errorMessage ?? "Docs service is busy — tap to try again.")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "D29922"))
                    .padding(.leading, 20)
                    .fixedSize(horizontal: false, vertical: true)
            } else if topic.lookupState == .failed, let message = topic.errorMessage {
                Text(message)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "F85149"))
                    .padding(.leading, 20)
                    .fixedSize(horizontal: false, vertical: true)
            } else if topic.lookupState == .noMatch {
                Text("no docs match this topic")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                    .padding(.leading, 20)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "0F0F11")))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
    }

    private func rowTapped() {
        switch topic.lookupState {
        case .answered:
            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        case .pending, .noMatch, .failed, .busy:
            onLookup()
        case .lookingUp:
            break
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch topic.lookupState {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(hex: "484F58"))
        case .lookingUp:
            ProgressView().controlSize(.small)
        case .answered:
            Image(systemName: "circle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accentColor)
        case .noMatch:
            Image(systemName: "minus.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(hex: "484F58"))
        case .busy:
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(hex: "D29922"))
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(hex: "F85149"))
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch topic.lookupState {
        case .answered:
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(hex: "52525B"))
        case .pending:
            chip(autoLookup ? "queued" : "look up")
        case .busy:
            chip("try again")
        case .noMatch, .failed:
            chip("retry")
        case .lookingUp:
            Text("looking up…")
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "8B949E"))
        }
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .default))
            .foregroundStyle(Color(hex: "D4D4D8"))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "1C1C1F")))
    }
}

/// The grounded answer + citations for a resolved topic (no topic header — the
/// row already shows the label).
private struct DocAnswerBody: View {
    @Environment(\.interfaceScale) private var interfaceScale
    let card: DocPlaybookCard
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Text(card.answer)
                    .font(.system(size: interfaceScale.insightBodySize, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                    .lineSpacing(interfaceScale.insightLineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: copyAnswer) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                        Text(showCopied ? "copied" : "copy")
                            .font(.system(size: 10, weight: .medium, design: .default))
                    }
                    .foregroundStyle(showCopied ? Color(hex: "3FB950") : Color(hex: "52525B"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "1C1C1F")))
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            if !card.citations.isEmpty {
                Rectangle()
                    .fill(Color(hex: "1C1C1F"))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(card.citations) { citation in
                        if let urlString = citation.url, let url = docsCitationLinkURL(urlString) {
                            Link(destination: url) {
                                Text(citation.title)
                                    .font(.system(size: 10, weight: .medium, design: .default))
                                    .foregroundStyle(Color(hex: "58A6FF"))
                                    .underline()
                            }
                        } else {
                            Text(citation.title)
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(Color(hex: "8B949E"))
                        }
                        if let snippet = citation.snippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(.system(size: 10, weight: .regular, design: .default))
                                .foregroundStyle(Color(hex: "484F58"))
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private func copyAnswer() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.answer, forType: .string)
        #else
        UIPasteboard.general.string = card.answer
        #endif
        withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
        }
    }
}

/// Only render citation links for http/https URLs. Citation URLs originate in
/// third-party docs echoed through the LLM, so other schemes (javascript:,
/// file:, data:, …) must not be handed to `openURL`.
private func docsCitationLinkURL(_ raw: String) -> URL? {
    guard let url = URL(string: raw),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else {
        return nil
    }
    return url
}

// MARK: - MEDDPICC Content

struct MEDDPICCContent: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.interfaceScale) private var interfaceScale
    
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
                MEDDPICCBulletText(field.value!, fontSize: interfaceScale.insightBodySize)
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
        SelectableTextView(
            SelectableAttributed.bulletList(
                items: bullets,
                prefix: "•",
                prefixColor: color.opacity(0.5),
                fontSize: fontSize,
                textColor: color
            )
        )
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
        VStack(spacing: 10) {
            Text("◇")
                .font(.system(size: 28, weight: .ultraLight, design: .default))
                .foregroundStyle(Color(hex: "1C1C1F"))
            Text("waiting for speech...")
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "484F58"))
            Text("fillers, pace, clarity, and talk ratio\nupdate as you speak")
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(Color(hex: "3F3F46"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

private struct FillerWordsSection: View {
    @Environment(\.interfaceScale) private var interfaceScale
    let speaker: TrainingMetrics.SpeakerStats
    let durationMinutes: Double
    
    var body: some View {
        TerminalSection(
            title: "fillers: \(speaker.speakerLabel.lowercased())",
            color: speaker.isLocalMic ? ColorPalette.Coaching.fillers : ColorPalette.Text.meta,
            headerStyle: .plain,
            info: .fillers
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(speaker.totalFillers) fillers (\(String(format: "%.1f", speaker.fillersPerMinute))/min)")
                    .font(.system(size: interfaceScale.insightSecondarySize, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "71717A"))
                
                if speaker.speakerLabel != "Others" && !speaker.fillers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(speaker.fillers) { entry in
                            HStack(spacing: 6) {
                                Text(entry.word)
                                    .font(.system(size: interfaceScale.insightBodySize, weight: .medium, design: .default))
                                    .foregroundStyle(Color(hex: "D4D4D8"))
                                    .fixedSize()
                                
                                Text("\(entry.count)")
                                    .font(.system(size: interfaceScale.insightBodySize, weight: .semibold, design: .default))
                                    .foregroundStyle(ColorPalette.Coaching.fillers)
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
        TerminalSection(title: "talk ratio", color: ColorPalette.Coaching.talkRatio, headerStyle: .plain, info: .talkRatio) {
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
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(Color(hex: "D4D4D8"))
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("others \(Int((1 - metrics.talkRatioYou) * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .default))
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
        TerminalSection(title: "pace", color: ColorPalette.Coaching.pace, headerStyle: .plain, info: .pace) {
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
        TerminalSection(title: "longest monologue", color: ColorPalette.Coaching.monologue, headerStyle: .plain, info: .longestMonologue) {
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
        TerminalSection(title: "questions asked", color: ColorPalette.Coaching.questions, headerStyle: .plain, info: .questionsAsked) {
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
        TerminalSection(title: "clarity", color: ColorPalette.Coaching.clarity, headerStyle: .plain, info: .clarity) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(speakers) { speaker in
                    TerminalTrainingMetricRow(
                        speaker: speaker,
                        primary: String(format: "%.1f", speaker.avgWordsPerTurn),
                        secondary: "avg words/turn"
                    )
                }
                
                Text("lower = clearer = better")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "3F3F46"))
                    .padding(.top, 4)
            }
        }
    }
}

private struct TerminalTrainingMetricRow: View {
    @Environment(\.interfaceScale) private var interfaceScale
    let speaker: TrainingMetrics.SpeakerStats
    let primary: String
    var secondary: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Text(speaker.speakerLabel.lowercased())
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(speaker.isLocalMic ? Color(hex: "3FB950") : Color(hex: "8B949E"))
                .frame(width: 48, alignment: .leading)
            
            Text(primary)
                .font(.system(size: interfaceScale.insightBodySize, weight: .semibold, design: .default))
                .foregroundStyle(Color(hex: "E6EDF3"))
            
            if let secondary {
                Text(secondary)
                    .font(.system(size: interfaceScale.insightSecondarySize, weight: .regular, design: .default))
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
        return TrainingMetrics.compute(from: segments, duration: duration, language: meeting.language, names: meeting.speakerNames, selfIDs: meeting.selfSpeakerIDs)
    }

    var body: some View {
        TrainingContent(metrics: metrics)
    }
}

struct TerminalInsightsContent: View {
    @Environment(\.interfaceScale) private var interfaceScale
    let meeting: Meeting

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                if let summary = meeting.summaryText {
                    TerminalSection(title: "summary", color: Color(hex: "58A6FF")) {
                        SelectableTextView(SelectableAttributed.body(
                            summary,
                            fontSize: interfaceScale.insightBodySize,
                            lineSpacing: interfaceScale.insightLineSpacing
                        ))
                    }
                }

                if !meeting.discussionFlow.isEmpty {
                    TerminalSection(title: "discussion", color: Color(hex: "F59E0B")) {
                        SelectableTextView(
                            SelectableAttributed.bulletList(
                                items: meeting.discussionFlow,
                                prefix: "->",
                                prefixColor: Color(hex: "D29922"),
                                fontSize: interfaceScale.insightBodySize
                            )
                        )
                    }
                }

                if !meeting.actionItems.isEmpty {
                    TerminalSection(title: "action items", color: Color(hex: "3FB950")) {
                        SelectableTextView(
                            SelectableAttributed.bulletList(
                                items: meeting.actionItems,
                                prefix: "→",
                                prefixColor: Color(hex: "3FB950"),
                                fontSize: interfaceScale.insightBodySize
                            )
                        )
                    }
                }

                if !meeting.keyDecisions.isEmpty {
                    TerminalSection(title: "decisions", color: Color(hex: "D29922")) {
                        SelectableTextView(
                            SelectableAttributed.bulletList(
                                items: meeting.keyDecisions,
                                prefix: "->",
                                prefixColor: Color(hex: "D29922"),
                                fontSize: interfaceScale.insightBodySize
                            )
                        )
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
                        .font(.system(size: 12, weight: .bold, design: .default))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .default))
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
                    .foregroundStyle(ColorPalette.Text.muted)
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
                                .foregroundStyle(ColorPalette.Text.muted)
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
                        .foregroundStyle(ColorPalette.Text.muted)
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
        settingsNote: "You can add or edit your own filler words in Settings → Language."
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
        summary: "Words spoken per minute. Faster is not always better; clarity usually drops when pace gets too high.",
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

// MARK: - Training Main View (Sidebar)

enum CoachingOverviewTab: String, CaseIterable {
    case focus
    case stats
    case history

    var accessibilityHint: String {
        switch self {
        case .focus:
            return "Shows your next-meeting focus, strengths, trends, and examples"
        case .stats:
            return "Shows overall, recent, and latest coaching metrics"
        case .history:
            return "Shows coaching metrics for each meeting"
        }
    }
}

struct TrainingMainView: View {
    let meetings: [Meeting]
    var onSelectMeeting: ((UUID) -> Void)? = nil
    @State private var sortColumn: TrainingSortColumn = .date
    @State private var sortAscending = false
    @State private var cachedRows: [TrainingRow] = []
    @State private var isComputing = false
    @State private var lastComputedHash = ""
    @State private var selectedTab: CoachingOverviewTab = .focus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("coaching")
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(20), weight: .bold, design: .default))
                        .foregroundStyle(ColorPalette.Text.primary)
                    Text("personal coaching across your recent meetings")
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(12), weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                }

                coachingTabs

                if isComputing && cachedRows.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("computing metrics...")
                            .font(.system(size: MinitiDesignSystem.CoachingTypography.size(11), weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.dim)
                    }
                    .padding(.vertical, 20)
                } else if !cachedRows.isEmpty {
                    selectedTabContent
                } else if !isComputing {
                    Text("no meetings with enough data yet. record a meeting longer than 5 seconds to see coaching stats.")
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(12), weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.dim)
                        .padding(.vertical, 20)
                }
            }
            #if os(iOS)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            #else
            .padding(24)
            #endif
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorPalette.Background.primary)
        .task(id: meetingsHash) {
            await computeRows()
        }
        .onAppear {
            if cachedRows.isEmpty {
                Task { await computeRows() }
            }
        }
    }

    private var coachingTabs: some View {
        MinitiTabStripSurface {
            HStack(spacing: 0) {
                ForEach(CoachingOverviewTab.allCases, id: \.self) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        MinitiTabLabel(
                            title: tab.rawValue,
                            isSelected: isSelected,
                            fillsAvailableWidth: true
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .accessibilityHint(tab.accessibilityHint)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: MinitiDesignSystem.CoachingLayout.compactColumnMaxWidth)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .focus:
            CoachingGuidanceView(rows: cachedRows, onSelectMeeting: onSelectMeeting)
        case .stats:
            TrainingStatsOverview(rows: cachedRows)
        case .history:
            VStack(alignment: .leading, spacing: 2) {
                trainingTableHeader

                ForEach(displayedRows) { row in
                    trainingTableRow(row)
                }
            }
        }
    }

    private var meetingsHash: String {
        let parts = meetings.compactMap { m -> String? in
            guard m.endTime != nil else { return nil }
            return "\(m.id):\(m.segments.count)"
        }
        return parts.joined(separator: ",")
    }

    private func computeRows() async {
        let currentHash = meetingsHash
        guard currentHash != lastComputedHash else { return }
        isComputing = true

        let validMeetings = meetings.filter { $0.endTime != nil && !$0.segments.isEmpty }

        let snapshots: [(UUID, Date, String, [TrainingMetrics.Segment], Double, String, [String: String], Set<Int>)] = validMeetings.compactMap { meeting in
            guard let duration = meeting.duration, duration > 5 else { return nil }
            let segs = meeting.segments
                .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { $0.timestamp < $1.timestamp }
                .map { TrainingMetrics.Segment(text: $0.text, speaker: $0.speaker, isFinal: true, timestamp: $0.timestamp) }
            guard !segs.isEmpty else { return nil }
            let titleForRow = meeting.displayTitle
            return (meeting.id, meeting.startTime, titleForRow, segs, duration, meeting.language, meeting.speakerNames, meeting.selfSpeakerIDs)
        }

        let rows: [TrainingRow] = await Task.detached(priority: .userInitiated) {
            snapshots.compactMap { (id, startTime, title, segments, duration, language, names, selfIDs) in
                let metrics = TrainingMetrics.compute(from: segments, duration: duration, language: language, names: names, selfIDs: selfIDs)
                guard let speaker = metrics.speakers.first(where: { $0.isLocalMic })
                        ?? metrics.speakers.max(by: { $0.wordCount < $1.wordCount }) else { return nil }
                let topFiller = speaker.fillers.first?.word
                let examples = CoachingExampleExtractor.examples(
                    meetingID: id,
                    meetingTitle: title,
                    meetingDate: startTime,
                    segments: segments,
                    selfIDs: selfIDs,
                    detectedFillers: speaker.fillers.map(\.word),
                    topFiller: topFiller,
                    talkRatio: metrics.speakers.contains(where: { !$0.isLocalMic }) ? metrics.talkRatioYou : nil
                )
                return TrainingRow(
                    id: id,
                    date: startTime,
                    dateString: TrainingRow.formatDate(startTime),
                    title: title,
                    fillers: speaker.fillersPerMinute,
                    pace: speaker.wordsPerMinute,
                    clarity: speaker.avgWordsPerTurn,
                    questions: speaker.questionsAsked,
                    durationMinutes: metrics.durationMinutes,
                    talkRatio: metrics.speakers.contains(where: { !$0.isLocalMic }) ? metrics.talkRatioYou : nil,
                    longestMonologue: speaker.longestMonologueWords,
                    topFiller: topFiller,
                    examples: examples
                )
            }
        }.value

        cachedRows = rows
        lastComputedHash = currentHash
        isComputing = false
    }

    private var displayedRows: [TrainingRow] {
        cachedRows.sorted { a, b in
            let result: Bool
            switch sortColumn {
            case .date: result = a.date < b.date
            case .name: result = a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .fillers: result = a.fillers < b.fillers
            case .pace: result = a.pace < b.pace
            case .clarity: result = a.clarity < b.clarity
            case .questions: result = a.questions < b.questions
            }
            return sortAscending ? result : !result
        }
    }

    #if os(iOS)
    private static let dateColumnWidth: CGFloat = 62
    private static let statColumnWidth: CGFloat = 32
    #else
    private static let dateColumnWidth: CGFloat = 80
    private static let statColumnWidth: CGFloat = 70
    #endif

    private var trainingTableHeader: some View {
        HStack(spacing: 0) {
            #if os(iOS)
            sortableHeader("date", unit: nil, column: .date, width: Self.dateColumnWidth, alignment: .leading)
                .padding(.trailing, 4)
            sortableHeader("meeting", unit: nil, column: .name, alignment: .leading)
                .padding(.leading, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            compactStatHeader("f", fullLabel: "fillers", column: .fillers, color: ColorPalette.Coaching.fillers, info: .fillers)
            compactStatHeader("p", fullLabel: "pace", column: .pace, color: ColorPalette.Coaching.pace, info: .pace)
            compactStatHeader("c", fullLabel: "clarity", column: .clarity, color: ColorPalette.Coaching.clarity, info: .clarity)
            compactStatHeader("q", fullLabel: "questions", column: .questions, color: ColorPalette.Coaching.questions, info: .questionsAsked)
            #else
            sortableHeader("date", unit: nil, column: .date, width: Self.dateColumnWidth, alignment: .leading)
            sortableHeader("meeting", unit: nil, column: .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortableHeader("fillers", unit: "f/min", column: .fillers, width: Self.statColumnWidth)
            sortableHeader("pace", unit: "w/min", column: .pace, width: Self.statColumnWidth)
            sortableHeader("clarity", unit: "w/turn", column: .clarity, width: Self.statColumnWidth)
            sortableHeader("questions", unit: "qs", column: .questions, width: Self.statColumnWidth)
            #endif
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ColorPalette.Background.secondary)
    }

    #if os(iOS)
    @State private var infoPopupColumn: TrainingSortColumn?

    private func compactStatHeader(_ letter: String, fullLabel: String, column: TrainingSortColumn, color: Color, info: TerminalSectionInfo) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
        } label: {
            HStack(spacing: 1) {
                Text(letter)
                    .font(.system(size: 12, weight: .bold, design: .default))
                    .foregroundStyle(sortColumn == column ? color : color.opacity(0.5))
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(color.opacity(0.7))
                }
            }
            .frame(width: Self.statColumnWidth)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            infoPopupColumn = column
        })
        .fullScreenCover(isPresented: Binding(
            get: { infoPopupColumn == column },
            set: { if !$0 { infoPopupColumn = nil } }
        )) {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { infoPopupColumn = nil }
                TrainingColumnInfoCard(info: info, accent: color) { infoPopupColumn = nil }
                    .padding(.horizontal, 20)
            }
            .background(Color.clear)
        }
    }
    #endif

    private func sortableHeader(_ label: String, unit: String?, column: TrainingSortColumn, width: CGFloat? = nil, alignment: Alignment = .trailing) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = column == .name || column == .date ? false : true
            }
        } label: {
            HStack(spacing: 3) {
                if alignment == .leading {
                    headerContent(label, unit: unit, column: column, alignment: .leading)
                    Spacer()
                } else {
                    Spacer()
                    headerContent(label, unit: unit, column: column, alignment: .trailing)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .frame(width: width, alignment: alignment)
    }

    private func headerContent(_ label: String, unit: String?, column: TrainingSortColumn, alignment: HorizontalAlignment) -> some View {
        #if os(iOS)
        let labelSize: CGFloat = 11
        let chevronSize: CGFloat = 8
        let unitSize: CGFloat = 9
        #else
        let labelSize = MinitiDesignSystem.CoachingTypography.size(9)
        let chevronSize = MinitiDesignSystem.CoachingTypography.size(7)
        let unitSize = MinitiDesignSystem.CoachingTypography.size(8)
        #endif

        return VStack(alignment: alignment, spacing: 1) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: labelSize, weight: .semibold, design: .default))
                    .foregroundStyle(sortColumn == column ? ColorPalette.Text.secondary : ColorPalette.Text.dim)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: chevronSize, weight: .bold))
                        .foregroundStyle(ColorPalette.Text.muted)
                }
            }
            if let unit {
                Text(unit)
                    .font(.system(size: unitSize, weight: .medium, design: .default))
                    .foregroundStyle(ColorPalette.Text.dim.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private func trainingTableRow(_ row: TrainingRow) -> some View {
        if let onSelectMeeting {
            Button {
                onSelectMeeting(row.id)
            } label: {
                trainingTableRowContent(row)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(row.title)")
            .accessibilityHint("Opens this meeting and its coaching details")
        } else {
            trainingTableRowContent(row)
        }
    }

    private func trainingTableRowContent(_ row: TrainingRow) -> some View {
        HStack(spacing: 0) {
            #if os(iOS)
            Text(row.dateString)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.dim)
                .frame(width: Self.dateColumnWidth, alignment: .leading)
                .padding(.trailing, 4)

            Text(row.title)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.primary)
                .lineLimit(1)
                .padding(.leading, 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f", row.fillers))
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(ColorPalette.Coaching.fillers)
                .frame(width: Self.statColumnWidth, alignment: .center)

            Text("\(Int(row.pace))")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(ColorPalette.Coaching.pace)
                .frame(width: Self.statColumnWidth, alignment: .center)

            Text("\(Int(row.clarity))")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(ColorPalette.Coaching.clarity)
                .frame(width: Self.statColumnWidth, alignment: .center)

            Text("\(row.questions)")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(ColorPalette.Coaching.questions)
                .frame(width: Self.statColumnWidth, alignment: .center)
            #else
            Text(row.dateString)
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.dim)
                .frame(width: Self.dateColumnWidth, alignment: .leading)

            Text(row.title)
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(11), weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f", row.fillers))
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .semibold, design: .default))
                .foregroundStyle(ColorPalette.Coaching.fillers)
                .frame(width: Self.statColumnWidth, alignment: .trailing)

            Text("\(Int(row.pace))")
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .semibold, design: .default))
                .foregroundStyle(ColorPalette.Coaching.pace)
                .frame(width: Self.statColumnWidth, alignment: .trailing)

            Text("\(Int(row.clarity))")
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .semibold, design: .default))
                .foregroundStyle(ColorPalette.Coaching.clarity)
                .frame(width: Self.statColumnWidth, alignment: .trailing)

            Text("\(row.questions)")
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .semibold, design: .default))
                .foregroundStyle(ColorPalette.Coaching.questions)
                .frame(width: Self.statColumnWidth, alignment: .trailing)
            #endif
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(ColorPalette.Background.secondary.opacity(0.55))
        )
    }

}

private enum TrainingSortColumn {
    case date, name, fillers, pace, clarity, questions
}

#if os(iOS)
private struct TrainingColumnInfoCard: View {
    let info: TerminalSectionInfo
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
                        .background(Circle().fill(Color.white.opacity(0.08)))
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
        .onTapGesture {}
    }
}
#endif

struct TrainingRow: Identifiable {
    let id: UUID
    let date: Date
    let dateString: String
    let title: String
    let fillers: Double
    let pace: Double
    let clarity: Double
    let questions: Int
    let durationMinutes: Double
    let talkRatio: Double?
    let longestMonologue: Int
    let topFiller: String?
    let examples: [CoachingMetric: CoachingExample]

    var coachingSnapshot: CoachingSnapshot {
        CoachingSnapshot(
            date: date,
            fillersPerMinute: fillers,
            wordsPerMinute: pace,
            avgWordsPerTurn: clarity,
            // Avoid turning one question in a very short test recording into an
            // extreme rate while retaining duration comparability for real calls.
            questionsPer30Minutes: Double(questions) / max(durationMinutes, 5) * 30,
            talkRatio: talkRatio,
            longestMonologueWords: Double(longestMonologue),
            topFiller: topFiller,
            examples: examples
        )
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Personalized Coaching Guidance

private struct CoachingGuidanceView: View {
    let rows: [TrainingRow]
    let onSelectMeeting: ((UUID) -> Void)?

    private var report: CoachingReport? {
        CoachingAdvisor.analyze(rows.map(\.coachingSnapshot))
    }

    var body: some View {
        if let report {
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
                coachingFocus(report)

                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("your trends")
                            .font(.system(size: MinitiDesignSystem.CoachingTypography.size(13), weight: .bold, design: .default))
                            .foregroundStyle(ColorPalette.Text.primary)
                        Spacer()
                        Text(baselineLabel(report.meetingCount))
                            .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.meta)
                    }

                    LazyVStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
                        ForEach(report.summaries) { summary in
                            CoachingTrendCard(
                                summary: summary,
                                onSelectMeeting: onSelectMeeting
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: MinitiDesignSystem.CoachingLayout.trendColumnMaxWidth, alignment: .leading)
        }
    }

    private func coachingFocus(_ report: CoachingReport) -> some View {
        let focus = report.focus
        let accent = focus.metric.accent
        return MinitiCardSurface(
            style: .accented(accent),
            contentPadding: MinitiDesignSystem.Spacing.section
        ) {
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.comfortable) {
                HStack(spacing: MinitiDesignSystem.Spacing.small) {
                    Image(systemName: focus.status == .strong ? "sparkles" : "scope")
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(11), weight: .semibold))
                    Text(focus.status == .strong ? "keep building" : "next meeting focus")
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .bold, design: .default))
                }
                .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.small) {
                    Text(focus.headline)
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(17), weight: .bold, design: .default))
                        .foregroundStyle(ColorPalette.Text.primary)
                    Text(focus.observation)
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(12), weight: .regular, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: MinitiDesignSystem.Spacing.standard) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(11), weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.top, 2)
                    Text(focus.tip)
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(12), weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(MinitiDesignSystem.Spacing.comfortable)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                        .fill(accent.opacity(0.08))
                )

                if !report.strengths.isEmpty {
                    HStack(alignment: .top, spacing: MinitiDesignSystem.Spacing.small) {
                        Text("working well")
                            .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .bold, design: .default))
                            .foregroundStyle(ColorPalette.Status.success)
                        Text(report.strengths.map(\.headline).joined(separator: " • "))
                            .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.meta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func baselineLabel(_ count: Int) -> String {
        if count < 4 { return "building a baseline • \(count) meeting\(count == 1 ? "" : "s")" }
        return "recent vs previous • \(count) meetings"
    }
}

private struct CoachingTrendCard: View {
    let summary: CoachingMetricSummary
    let onSelectMeeting: ((UUID) -> Void)?

    private var accent: Color { summary.metric.accent }

    private var content: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
            HStack(spacing: MinitiDesignSystem.Spacing.small) {
                Image(systemName: summary.metric.systemImage)
                    .font(.system(size: MinitiDesignSystem.CoachingTypography.size(11), weight: .semibold))
                Text(summary.metric.displayName)
                    .font(.system(size: MinitiDesignSystem.CoachingTypography.size(11), weight: .bold, design: .default))
                Spacer(minLength: MinitiDesignSystem.Spacing.small)
                trendLabel
            }
            .foregroundStyle(accent)

            HStack(alignment: .firstTextBaseline, spacing: MinitiDesignSystem.Spacing.small) {
                Text(summary.recentValue)
                    .font(.system(size: MinitiDesignSystem.CoachingTypography.size(14), weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(ColorPalette.Text.primary)
                if let previous = summary.previousValue {
                    Text("from \(previous)")
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .medium, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(ColorPalette.Text.meta)
                }
            }

            Text(summary.observation)
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(11), weight: .regular, design: .default))
                .foregroundStyle(ColorPalette.Text.muted)

            if let example = summary.example {
                CoachingExampleView(
                    example: example,
                    accent: accent,
                    onSelectMeeting: onSelectMeeting
                )
            }

            HStack(alignment: .top, spacing: MinitiDesignSystem.Spacing.small) {
                Text("try")
                    .font(.system(size: MinitiDesignSystem.CoachingTypography.size(11), weight: .bold, design: .default))
                    .foregroundStyle(accent)
                Text(summary.tip)
                    .font(.system(size: MinitiDesignSystem.CoachingTypography.size(11), weight: .medium, design: .default))
                    .foregroundStyle(ColorPalette.Text.meta)
            }
        }
    }

    var body: some View {
        MinitiCardSurface {
            content
        }
        .accessibilityElement(children: .contain)
    }

    private var trendLabel: some View {
        HStack(spacing: MinitiDesignSystem.Spacing.compact) {
            Image(systemName: summary.trend.systemImage)
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(9), weight: .bold))
            Text(summary.trend.label)
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(9), weight: .bold, design: .default))
        }
        .foregroundStyle(summary.trend.color)
    }
}

private struct CoachingExampleView: View {
    let example: CoachingExample
    let accent: Color
    let onSelectMeeting: ((UUID) -> Void)?

    var body: some View {
        if let onSelectMeeting {
            Button {
                onSelectMeeting(example.meetingID)
            } label: {
                exampleContent(showsDisclosure: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Example from \(example.meetingTitle), \(example.meetingDate.formatted(date: .abbreviated, time: .omitted)): \(example.excerpt)"
            )
            .accessibilityHint("Opens the source meeting")
        } else {
            exampleContent(showsDisclosure: false)
                .accessibilityElement(children: .combine)
        }
    }

    private func exampleContent(showsDisclosure: Bool) -> some View {
        MinitiCardSurface(
            style: .inset,
            contentPadding: MinitiDesignSystem.Spacing.standard
        ) {
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.small) {
                HStack(spacing: MinitiDesignSystem.Spacing.small) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(9), weight: .bold))
                    Text(example.label)
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(9), weight: .bold, design: .default))
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: MinitiDesignSystem.Spacing.small)
                    if showsDisclosure {
                        Image(systemName: "chevron.right")
                            .font(.system(size: MinitiDesignSystem.CoachingTypography.size(8), weight: .bold))
                            .foregroundStyle(ColorPalette.Text.disabled)
                    }
                }
                .foregroundStyle(accent)

                HStack(spacing: MinitiDesignSystem.Spacing.compact) {
                    Text(example.meetingTitle)
                        .lineLimit(1)
                    Text("·")
                    Text(example.meetingDate, format: .dateTime.day().month(.abbreviated).year())
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(9), weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.meta)

                Text("“\(example.excerpt)”")
                    .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .regular, design: .default))
                    .foregroundStyle(ColorPalette.Text.muted)
            }
        }
    }
}

private extension CoachingMetric {
    var displayName: String {
        switch self {
        case .fillers: return "fillers"
        case .pace: return "pace"
        case .clarity: return "clarity"
        case .questions: return "questions"
        case .talkRatio: return "talk ratio"
        case .monologue: return "longest monologue"
        }
    }

    var systemImage: String {
        switch self {
        case .fillers: return "pause.fill"
        case .pace: return "speedometer"
        case .clarity: return "text.alignleft"
        case .questions: return "questionmark.bubble.fill"
        case .talkRatio: return "person.2.fill"
        case .monologue: return "quote.bubble.fill"
        }
    }

    var accent: Color {
        MinitiDesignSystem.ContentAccent.coachingMetric(self)
    }
}

private extension CoachingTrend {
    var label: String {
        switch self {
        case .improving: return "improving"
        case .steady: return "steady"
        case .needsAttention: return "watch"
        case .buildingBaseline: return "baseline"
        }
    }

    var systemImage: String {
        switch self {
        case .improving: return "arrow.down.right"
        case .steady: return "arrow.right"
        case .needsAttention: return "arrow.up.right"
        case .buildingBaseline: return "ellipsis"
        }
    }

    var color: Color {
        switch self {
        case .improving: return ColorPalette.Accent.green
        case .steady, .buildingBaseline: return ColorPalette.Text.meta
        case .needsAttention: return ColorPalette.Status.warning
        }
    }
}

// MARK: - Training Stats Overview (Home Screen)

struct TrainingStatsOverview: View {
    let rows: [TrainingRow]

    var body: some View {
        let sorted = rows.sorted { $0.date > $1.date }
        let recent = Array(sorted.prefix(5))
        if !recent.isEmpty {
            let last = recent[0]
            let avgPace = recent.map(\.pace).reduce(0, +) / Double(recent.count)
            let avgFillers = recent.map(\.fillers).reduce(0, +) / Double(recent.count)
            let avgClarity = recent.map(\.clarity).reduce(0, +) / Double(recent.count)
            let avgQuestions = recent.map(\.coachingSnapshot.questionsPer30Minutes).reduce(0, +) / Double(recent.count)
            let avgTalkRatio = average(recent.compactMap(\.talkRatio))
            let avgLongestMonologue = Double(recent.map(\.longestMonologue).reduce(0, +)) / Double(recent.count)

            let allPace = sorted.isEmpty ? 0 : sorted.map(\.pace).reduce(0, +) / Double(sorted.count)
            let allFillers = sorted.isEmpty ? 0 : sorted.map(\.fillers).reduce(0, +) / Double(sorted.count)
            let allClarity = sorted.isEmpty ? 0 : sorted.map(\.clarity).reduce(0, +) / Double(sorted.count)
            let allQuestions = sorted.isEmpty ? 0 : sorted.map(\.coachingSnapshot.questionsPer30Minutes).reduce(0, +) / Double(sorted.count)
            let allTalkRatio = average(sorted.compactMap(\.talkRatio))
            let allLongestMonologue = sorted.isEmpty ? 0 : Double(sorted.map(\.longestMonologue).reduce(0, +)) / Double(sorted.count)
            let fillersChart = Self.chartPoints(from: sorted) { $0.fillers }
            let paceChart = Self.chartPoints(from: sorted) { $0.pace }
            let clarityChart = Self.chartPoints(from: sorted) { $0.clarity }
            let questionsChart = Self.chartPoints(from: sorted) { $0.coachingSnapshot.questionsPer30Minutes }
            let talkRatioChart = Self.chartPoints(from: sorted) { $0.talkRatio }
            let monologueChart = Self.chartPoints(from: sorted) { Double($0.longestMonologue) }

            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.comfortable) {
                VStack(spacing: 2) {
                    TrainingStatHeader(meetingCount: recent.count, allCount: sorted.count)

                    VStack(spacing: 0) {
                    TrainingStatRow(
                        label: "fillers",
                        allValue: String(format: "%.1f", allFillers),
                        avgValue: String(format: "%.1f", avgFillers),
                        lastValue: String(format: "%.1f", last.fillers),
                        unit: "/ min",
                        trend: trend(last: last.fillers, avg: avgFillers),
                        comparisonTone: CoachingAdvisor.comparisonTone(for: .fillers, latest: last.fillers, baseline: avgFillers),
                        color: ColorPalette.Coaching.fillers,
                        info: .fillers
                    )
                    TrainingStatRow(
                        label: "pace",
                        allValue: "\(Int(allPace))",
                        avgValue: "\(Int(avgPace))",
                        lastValue: "\(Int(last.pace))",
                        unit: "words / min",
                        trend: trend(last: last.pace, avg: avgPace),
                        comparisonTone: CoachingAdvisor.comparisonTone(for: .pace, latest: last.pace, baseline: avgPace),
                        color: ColorPalette.Coaching.pace,
                        info: .pace
                    )
                    TrainingStatRow(
                        label: "clarity",
                        allValue: "\(Int(allClarity))",
                        avgValue: "\(Int(avgClarity))",
                        lastValue: "\(Int(last.clarity))",
                        unit: "words / turn",
                        trend: trend(last: last.clarity, avg: avgClarity),
                        comparisonTone: CoachingAdvisor.comparisonTone(for: .clarity, latest: last.clarity, baseline: avgClarity),
                        color: ColorPalette.Coaching.clarity,
                        info: .clarity
                    )
                    TrainingStatRow(
                        label: "questions",
                        allValue: String(format: "%.0f", allQuestions),
                        avgValue: String(format: "%.0f", avgQuestions),
                        lastValue: String(format: "%.0f", last.coachingSnapshot.questionsPer30Minutes),
                        unit: "/ 30 min",
                        trend: trend(last: last.coachingSnapshot.questionsPer30Minutes, avg: avgQuestions),
                        comparisonTone: CoachingAdvisor.comparisonTone(for: .questions, latest: last.coachingSnapshot.questionsPer30Minutes, baseline: avgQuestions),
                        color: ColorPalette.Coaching.questions,
                        info: .questionsAsked
                    )
                    TrainingStatRow(
                        label: "talk ratio",
                        allValue: formatPercentageNumber(allTalkRatio),
                        avgValue: formatPercentageNumber(avgTalkRatio),
                        lastValue: formatPercentageNumber(last.talkRatio),
                        unit: "% you",
                        trend: trend(last: last.talkRatio, avg: avgTalkRatio),
                        comparisonTone: CoachingAdvisor.comparisonTone(for: .talkRatio, latest: last.talkRatio, baseline: avgTalkRatio),
                        color: ColorPalette.Coaching.talkRatio,
                        info: .talkRatio
                    )
                    TrainingStatRow(
                        label: "longest monologue",
                        allValue: "\(Int(allLongestMonologue.rounded()))",
                        avgValue: "\(Int(avgLongestMonologue.rounded()))",
                        lastValue: "\(last.longestMonologue)",
                        unit: "words",
                        trend: trend(last: Double(last.longestMonologue), avg: avgLongestMonologue),
                        comparisonTone: CoachingAdvisor.comparisonTone(for: .monologue, latest: Double(last.longestMonologue), baseline: avgLongestMonologue),
                        color: ColorPalette.Coaching.monologue,
                        info: .longestMonologue
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

                VStack(spacing: MinitiDesignSystem.Spacing.comfortable) {
                    CoachingMetricChartCard(
                        label: "fillers",
                        unit: "/ min",
                        color: ColorPalette.Coaching.fillers,
                        points: fillersChart,
                        meetingCount: sorted.count
                    )
                    CoachingMetricChartCard(
                        label: "pace",
                        unit: "words / min",
                        color: ColorPalette.Coaching.pace,
                        points: paceChart,
                        meetingCount: sorted.count
                    )
                    CoachingMetricChartCard(
                        label: "clarity",
                        unit: "words / turn",
                        color: ColorPalette.Coaching.clarity,
                        points: clarityChart,
                        meetingCount: sorted.count
                    )
                    CoachingMetricChartCard(
                        label: "questions",
                        unit: "/ 30 min",
                        color: ColorPalette.Coaching.questions,
                        points: questionsChart,
                        meetingCount: sorted.count
                    )
                    CoachingMetricChartCard(
                        label: "talk ratio",
                        unit: "% you",
                        color: ColorPalette.Coaching.talkRatio,
                        points: talkRatioChart,
                        meetingCount: sorted.count
                    )
                    CoachingMetricChartCard(
                        label: "longest monologue",
                        unit: "words",
                        color: ColorPalette.Coaching.monologue,
                        points: monologueChart,
                        meetingCount: sorted.count
                    )
                }
            }
            .frame(maxWidth: MinitiDesignSystem.CoachingLayout.statsColumnMaxWidth)
        }
    }

    enum Trend {
        case up, down, same
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func chartPoints(
        from rows: [TrainingRow],
        value: (TrainingRow) -> Double?
    ) -> [CoachingChartPoint] {
        Array(rows.reversed()).enumerated().compactMap { index, row in
            guard let metricValue = value(row), metricValue.isFinite else { return nil }
            return CoachingChartPoint(
                id: row.id,
                meetingIndex: Double(index + 1),
                date: row.date,
                value: metricValue
            )
        }
    }

    private func formatPercentageNumber(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))"
    }

    fileprivate func trend(last: Double?, avg: Double?) -> Trend {
        guard let last, let avg, avg > 0 else { return .same }
        let ratio = last / avg
        if ratio > 1.10 { return .up }
        if ratio < 0.90 { return .down }
        return .same
    }
}

struct CoachingChartPoint: Identifiable {
    let id: UUID
    let meetingIndex: Double
    let date: Date
    let value: Double
}

private struct TrainingStatHeader: View {
    let meetingCount: Int
    let allCount: Int

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: TrainingStatRow.labelWidth, height: 1)

            Spacer(minLength: 4)

            Text("all \(allCount)")
                .font(.system(size: TrainingStatRow.headerFontSize, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "52525B"))
                .frame(width: TrainingStatRow.colWidth)

            Spacer(minLength: 8)

            Text("last \(meetingCount)")
                .font(.system(size: TrainingStatRow.headerFontSize, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "52525B"))
                .frame(width: TrainingStatRow.colWidth)

            Spacer(minLength: 8)

            Text("last 1")
                .font(.system(size: TrainingStatRow.headerFontSize, weight: .medium, design: .default))
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
    let allValue: String
    let avgValue: String
    let lastValue: String
    let unit: String
    let trend: TrainingStatsOverview.Trend
    let comparisonTone: CoachingComparisonTone
    let color: Color
    let info: TerminalSectionInfo

    private var trendIcon: String {
        switch trend {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .same: return "arrow.right"
        }
    }

    private var trendColor: Color {
        switch comparisonTone {
        case .positive: return ColorPalette.Status.success
        case .negative: return ColorPalette.Status.error
        case .neutral: return ColorPalette.Text.meta
        }
    }

    #if os(iOS)
    fileprivate static let labelWidth: CGFloat = 150
    fileprivate static let colWidth: CGFloat = 36
    fileprivate static let fontSize: CGFloat = 12
    fileprivate static let headerFontSize: CGFloat = 10
    #else
    fileprivate static let labelWidth: CGFloat = 220
    fileprivate static let colWidth: CGFloat = 96
    fileprivate static let fontSize = MinitiDesignSystem.CoachingTypography.size(10)
    fileprivate static let headerFontSize = MinitiDesignSystem.CoachingTypography.size(9)
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.small) {
            HStack(spacing: 0) {
                (
                    Text(label)
                        .font(.system(size: Self.fontSize, weight: .semibold, design: .default))
                        .foregroundColor(color)
                    + Text(" \(unit)")
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .medium, design: .default))
                        .foregroundColor(ColorPalette.Text.meta)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.leading, MinitiDesignSystem.Spacing.control)
                .frame(width: Self.labelWidth, alignment: .leading)

                Spacer(minLength: 4)

                Text(allValue)
                    .font(.system(size: Self.fontSize, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "71717A"))
                    .frame(width: Self.colWidth, alignment: .center)

                Spacer(minLength: 8)

                Text(avgValue)
                    .font(.system(size: Self.fontSize, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "A1A1AA"))
                    .frame(width: Self.colWidth, alignment: .center)

                Spacer(minLength: 8)

                Text(lastValue)
                    .font(.system(size: Self.fontSize, weight: .semibold, design: .default))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .frame(width: Self.colWidth, alignment: .center)

                Image(systemName: trendIcon)
                    .font(.system(size: MinitiDesignSystem.CoachingTypography.size(12), weight: .bold))
                    .foregroundStyle(trendColor)
                    .frame(width: 28)
            }

            Text(info.summary)
                .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Text.dim)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, MinitiDesignSystem.Spacing.control)

        }
        .padding(.horizontal, 12)
        .padding(.vertical, MinitiDesignSystem.Spacing.control)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, MinitiDesignSystem.Spacing.control)
                .padding(.leading, 12)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ColorPalette.Border.primary.opacity(0.7))
                .frame(height: 1)
                .padding(.horizontal, 12)
        }
    }
}

private struct CoachingMetricChartCard: View {
    let label: String
    let unit: String
    let color: Color
    let points: [CoachingChartPoint]
    let meetingCount: Int

    var body: some View {
        MinitiCardSurface(
            style: .standard,
            contentPadding: MinitiDesignSystem.Spacing.control
        ) {
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
                (
                    Text(label)
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .semibold, design: .default))
                        .foregroundColor(color)
                    + Text(" \(unit)")
                        .font(.system(size: MinitiDesignSystem.CoachingTypography.size(10), weight: .medium, design: .default))
                        .foregroundColor(ColorPalette.Text.meta)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)

                CoachingMetricLineChart(
                    points: points,
                    meetingCount: meetingCount,
                    color: color,
                    metricLabel: label,
                    unit: unit
                )
            }
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, MinitiDesignSystem.Spacing.control)
        }
    }
}

private struct CoachingMetricLineChart: View {
    let points: [CoachingChartPoint]
    let meetingCount: Int
    let color: Color
    let metricLabel: String
    let unit: String

    private var valueDomain: ClosedRange<Double> {
        guard let minimum = points.map(\.value).min(),
              let maximum = points.map(\.value).max() else { return 0...1 }
        let spread = maximum - minimum
        let scale = max(abs(maximum), 1)
        let padding = max(spread * 0.16, scale * 0.08)
        return max(0, minimum - padding)...(maximum + padding)
    }

    private var latestPoint: CoachingChartPoint? {
        points.last
    }

    private var meetingDomain: ClosedRange<Double> {
        0.5...(Double(max(meetingCount, 1)) + 0.5)
    }

    var body: some View {
        Group {
            if points.isEmpty {
                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                    .fill(ColorPalette.Background.primary.opacity(0.35))
                    .overlay {
                        Text("not enough meeting history yet")
                            .font(.system(size: MinitiDesignSystem.CoachingTypography.size(9), weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.meta)
                    }
            } else {
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Meeting", point.meetingIndex),
                            yStart: .value("Chart baseline", valueDomain.lowerBound),
                            yEnd: .value(metricLabel, point.value)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.20), color.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Meeting", point.meetingIndex),
                            y: .value(metricLabel, point.value)
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(color)
                    }

                    if let latestPoint {
                        PointMark(
                            x: .value("Latest meeting", latestPoint.meetingIndex),
                            y: .value(metricLabel, latestPoint.value)
                        )
                        .symbolSize(46)
                        .foregroundStyle(ColorPalette.Background.panel)

                        PointMark(
                            x: .value("Latest meeting", latestPoint.meetingIndex),
                            y: .value(metricLabel, latestPoint.value)
                        )
                        .symbolSize(20)
                        .foregroundStyle(color)
                    }
                }
                .chartXScale(domain: meetingDomain)
                .chartYScale(domain: valueDomain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(ColorPalette.Border.primary.opacity(0.75))
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(ColorPalette.Background.primary.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                                .stroke(ColorPalette.Border.primary.opacity(0.7), lineWidth: 1)
                        }
                }
            }
        }
        .frame(height: MinitiDesignSystem.CoachingLayout.statsChartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metricLabel) history")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let latestPoint else { return "Not enough meeting history yet" }
        let date = latestPoint.date.formatted(date: .abbreviated, time: .omitted)
        return "Latest value \(latestPoint.value.formatted()) \(unit) on \(date), across \(points.count) meetings"
    }
}

struct TerminalListItem: View {
    @Environment(\.interfaceScale) private var interfaceScale
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
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(isCompleted ? Color(hex: "3FB950") : Color(hex: "484F58"))
                }
                .buttonStyle(.plain)
                .focusable(false)
            case .arrow:
                Text("->")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "D29922"))
            case .bullet:
                Text("•")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
            }
            
            Text(text)
                .font(.system(size: interfaceScale.insightBodySize, weight: .regular, design: .default))
                .foregroundStyle(isCompleted ? Color(hex: "484F58") : Color(hex: "E6EDF3"))
                .lineSpacing(interfaceScale.insightLineSpacing)
                .strikethrough(isCompleted)
        }
    }
}

struct TerminalTag: View {
    let text: String
    
    var body: some View {
        Text("#\(text.lowercased().replacingOccurrences(of: "_", with: " "))")
            .font(.system(size: 11, weight: .medium, design: .default))
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
                .font(.system(size: 32, weight: .light, design: .default))
                .foregroundStyle(Color(hex: "58A6FF"))
                .rotationEffect(.degrees(Double(dots.count) * 90))
                .animation(.linear(duration: 0.4), value: dots)
            
            Text("generating insights\(dots)")
                .font(.system(size: 13, weight: .medium, design: .default))
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
                .font(.system(size: 40, weight: .ultraLight, design: .default))
                .foregroundStyle(Color(hex: "1C1C1F"))
            
            Text("no insights")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "8B949E"))
            
            if hasTranscript {
                Text("$ generate --from=transcript")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                
                Button {
                    Task {
                        await appState.generateInsights()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("⚡")
                        Text("generate")
                            .font(.system(size: 12, weight: .semibold, design: .default))
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
                    .font(.system(size: 11, weight: .medium, design: .default))
                }
            } else {
                Text("record a session first")
                    .font(.system(size: 12, weight: .regular, design: .default))
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
