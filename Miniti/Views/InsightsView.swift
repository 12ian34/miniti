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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Summary (always shown)
                if !appState.liveSummary.isEmpty {
                    TerminalSection(title: "summary", color: Color(hex: "58A6FF")) {
                        Text(appState.liveSummary)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                            .lineSpacing(6)
                    }
                }
                
                // MEDDPICC sections (only in meddpicc mode)
                if appState.insightsMode == .meddpicc {
                    MEDDPICCContent()
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
            .padding(20)
        }
    }
}

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
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Text("##")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
            
            // Content
            content()
                .padding(.leading, 20)
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
