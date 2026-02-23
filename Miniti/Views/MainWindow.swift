import SwiftUI
import SwiftData
import AppKit

// MARK: - Theme (using ColorPalette)
/// Theme struct provides convenient access to the global color palette.
/// All colors reference ColorPalette for consistency.
struct Theme {
    // Backgrounds
    static let bg = ColorPalette.Background.primary
    static let bgSecondary = ColorPalette.Background.secondary
    static let bgTertiary = ColorPalette.Background.tertiary
    
    // Borders
    static let border = ColorPalette.Border.primary
    static let borderLight = ColorPalette.Border.light
    
    // Text
    static let text = ColorPalette.Text.primary
    static let textMuted = ColorPalette.Text.muted
    static let textDim = ColorPalette.Text.dim
    
    // Accents
    static let accent = ColorPalette.Accent.green
    static let accentRed = ColorPalette.Accent.red
    static let accentBlue = ColorPalette.Accent.blue
}

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var keyboardService: KeyboardShortcutsService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.startTime, order: .reverse) private var meetings: [Meeting]
    @State private var selectedMeeting: Meeting?
    
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Sidebar
                TerminalSidebar(
                    meetings: meetings,
                    selectedMeeting: $selectedMeeting,
                    onDeleteMeeting: { meeting in
                        deleteMeeting(meeting)
                    }
                )
                .frame(width: 260)
                
                // Subtle gradient divider
                ZStack {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1)
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.border.opacity(0), Theme.borderLight.opacity(0.5), Theme.border.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1)
                }
                
                // Main content
                if let meeting = selectedMeeting {
                    // Show selected historical meeting
                    MeetingDetailView(meeting: meeting)
                } else {
                    // Show current session or ready state
                    MeetingView()
                }
            }
            
            // Keyboard shortcuts help overlay
            if keyboardService.showingHelp {
                KeyboardShortcutsOverlay()
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .background(Theme.bg)
        .onAppear {
            appState.modelContext = modelContext
            appState.resumeInterruptedMeeting()
            setupNavigationHandlers()
        }
        .onChange(of: appState.currentMeeting) { _, newMeeting in
            // When starting a new meeting, deselect historical meeting
            if newMeeting != nil {
                selectedMeeting = nil
            }
        }
    }
    
    private func setupNavigationHandlers() {
        keyboardService.onNavigateUp = { [self] in
            navigateHistory(direction: -1)
        }
        
        keyboardService.onNavigateDown = { [self] in
            navigateHistory(direction: 1)
        }
        
        keyboardService.onStandardMode = { [self] in
            if selectedMeeting != nil {
                appState.insightsMode = .standard
            } else {
                appState.switchInsightsMode(to: .standard)
            }
        }
        
        keyboardService.onMeddpiccMode = { [self] in
            if selectedMeeting != nil {
                appState.insightsMode = .meddpicc
            } else {
                appState.switchInsightsMode(to: .meddpicc)
            }
        }
        
        keyboardService.onTrainingMode = { [self] in
            if selectedMeeting != nil {
                appState.insightsMode = .training
            } else {
                appState.switchInsightsMode(to: .training)
            }
        }
    }
    
    private func navigateHistory(direction: Int) {
        let historicalMeetings = meetings.filter { $0.id != appState.currentMeeting?.id }
        guard !historicalMeetings.isEmpty else { return }
        
        if let current = selectedMeeting,
           let currentIndex = historicalMeetings.firstIndex(where: { $0.id == current.id }) {
            // Move from current selection
            let newIndex = currentIndex + direction
            if newIndex >= 0 && newIndex < historicalMeetings.count {
                selectedMeeting = historicalMeetings[newIndex]
            }
        } else {
            // No selection - select first or last based on direction
            if direction > 0 {
                selectedMeeting = historicalMeetings.first
            } else {
                selectedMeeting = historicalMeetings.last
            }
        }
    }
    
    private func deleteMeeting(_ meeting: Meeting) {
        // Deselect if this was selected
        if selectedMeeting?.id == meeting.id {
            selectedMeeting = nil
        }
        // Delete from context
        modelContext.delete(meeting)
        try? modelContext.save()
    }
}

struct TerminalSidebar: View {
    @EnvironmentObject var appState: AppState
    let meetings: [Meeting]
    @Binding var selectedMeeting: Meeting?
    let onDeleteMeeting: (Meeting) -> Void
    
    // Filter out the current meeting from history
    private var historicalMeetings: [Meeting] {
        meetings.filter { $0.id != appState.currentMeeting?.id }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo/Title
            HStack(spacing: 10) {
                Text("⬢")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                Text("miniti")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            
            // Gradient divider
            GradientDivider()
            
            // Current session or new session button
            VStack(alignment: .leading, spacing: 6) {
                if let meeting = appState.currentMeeting {
                    SidebarSessionItem(
                        title: meeting.title,
                        isRecording: appState.isRecording,
                        isSelected: selectedMeeting == nil
                    ) {
                        selectedMeeting = nil
                    }
                } else {
                    // New session button when no current meeting
                    SidebarItem(
                        icon: "+",
                        label: "new_session",
                        isSelected: selectedMeeting == nil,
                        accentColor: Theme.accent,
                        shortcut: "⌘N"
                    ) {
                        appState.createNewSession()
                        selectedMeeting = nil
                    }
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 10)
            
            // History section
            if !historicalMeetings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    GradientDivider()
                        .padding(.vertical, 12)
                    
                    HStack {
                        Text("history")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                        
                        Spacer()
                        
                        // Navigation hints
                        HStack(spacing: 4) {
                            HStack(spacing: 2) {
                                Text("↑")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                Text("K")
                                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(Theme.textDim.opacity(0.6))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.bgTertiary)
                            )
                            
                            HStack(spacing: 2) {
                                Text("↓")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                Text("J")
                                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(Theme.textDim.opacity(0.6))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.bgTertiary)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(historicalMeetings) { meeting in
                                SidebarHistoryItem(
                                    meeting: meeting,
                                    isSelected: selectedMeeting?.id == meeting.id,
                                    action: {
                                        selectedMeeting = meeting
                                    },
                                    onDelete: {
                                        onDeleteMeeting(meeting)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
            }
            
            Spacer()
            
            // Status bar
            VStack(alignment: .leading, spacing: 0) {
                GradientDivider()
                
                HStack(spacing: 8) {
                    if appState.appMode == .managed {
                        // Managed mode status
                        Circle()
                            .fill(appState.isLimitReached ? ColorPalette.Status.limitReached : Theme.accent)
                            .frame(width: 6, height: 6)
                            .shadow(color: (appState.isLimitReached ? ColorPalette.Status.limitReached : Theme.accent).opacity(0.5), radius: 4)
                        
                        if let usage = appState.usageInfo {
                            Text("free • \(usage.formattedRemaining) left")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                        } else {
                            Text("free")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                        }
                    } else {
                        // BYOK mode status
                        Circle()
                            .fill(appState.deepgramApiKey.isEmpty ? ColorPalette.Status.noApiKey : Theme.accent)
                            .frame(width: 6, height: 6)
                            .shadow(color: appState.deepgramApiKey.isEmpty ? ColorPalette.Status.noApiKey.opacity(0.5) : Theme.accent.opacity(0.5), radius: 4)
                        
                        Text(appState.deepgramApiKey.isEmpty ? "byok • no_api_key" : "byok • connected")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(Theme.bgSecondary)
    }
}

// MARK: - Gradient Divider
struct GradientDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Theme.border.opacity(0), Theme.borderLight, Theme.border.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

// MARK: - Sidebar History Item
struct SidebarHistoryItem: View {
    let meeting: Meeting
    let isSelected: Bool
    let action: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    @State private var showDeleteConfirm = false
    
    private var splitTitle: (timestamp: String, suffix: String)? {
        for separator in [" - ", " — "] {
            guard let range = meeting.title.range(of: separator) else { continue }
            return (
                timestamp: String(meeting.title[..<range.lowerBound]),
                suffix: String(meeting.title[range.upperBound...])
            )
        }
        return nil
    }
    
    private var displayTitle: String {
        // Show just the suffix if there is one, otherwise timestamp
        if let splitTitle {
            return splitTitle.suffix
        }
        return meeting.title
    }
    
    private var timestamp: String {
        // Extract timestamp portion
        if let splitTitle {
            return splitTitle.timestamp
        }
        return meeting.title
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle.isEmpty ? timestamp : displayTitle)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(formatDate(meeting.startTime))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                        Text("•")
                            .foregroundStyle(Theme.textDim.opacity(0.6))
                        Text(meeting.formattedDuration)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            
            // Delete button (show on hover)
            if isHovering {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.bgTertiary : (isHovering ? Theme.bgSecondary : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Theme.border : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .alert("Delete Meeting", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(displayTitle.isEmpty ? timestamp : displayTitle)\"? This cannot be undone.")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct SidebarItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let accentColor: Color
    var shortcut: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(icon)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .frame(width: 16)
                
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)
                
                Spacer()
                
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.bgTertiary : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Theme.border : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

struct SidebarSessionItem: View {
    let title: String
    let isRecording: Bool
    let isSelected: Bool
    let action: () -> Void
    
    private var statusColor: Color {
        isRecording ? Theme.accentRed : Theme.accentBlue
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Status row
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor.opacity(0.6), radius: isRecording ? 4 : 2)
                    
                    Text(isRecording ? "recording" : "session")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(statusColor)
                    
                    Spacer()
                }
                
                // Title
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Theme.text : Theme.textMuted)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.bgTertiary : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Theme.border : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Meeting Detail View (for historical meetings)

struct MeetingDetailView: View {
    @Bindable var meeting: Meeting
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    private let speakerColors: [Color] = [
        ColorPalette.Accent.blue,
        ColorPalette.Accent.purple,
        ColorPalette.Accent.green,
        ColorPalette.Accent.amber,
        ColorPalette.Accent.pink,
        ColorPalette.Accent.cyan,
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                TextField("meeting_title", text: $meeting.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .onSubmit {
                        saveTitle()
                    }
                
                Spacer()
                
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
                .foregroundStyle(Theme.textDim)
            }
            .padding(16)
            .background(Theme.bgSecondary)
            
            GradientDivider()
            
            // Side by side content
            HSplitView {
                // Left side - transcript and notes
                VSplitView {
                    // Transcript - takes most of the space
                    VStack(spacing: 0) {
                        DetailSectionHeader(title: "transcript", icon: "¶", onCopy: {
                            meeting.transcriptAsMarkdown()
                        })
                        
                        ScrollView {
                            transcriptContent
                        }
                    }
                    .frame(minHeight: 400)
                    
                    // Notes - compact, resizable
                    VStack(spacing: 0) {
                        DetailSectionHeader(title: "notes", icon: "✎", onCopy: {
                            meeting.notesAsMarkdown()
                        })
                        
                        SavedNotesView(meeting: meeting)
                    }
                    .frame(minHeight: 44, maxHeight: 200)
                }
                .frame(minWidth: 400)
                
                // Insights (right)
                VStack(spacing: 0) {
                    DetailSectionHeader(title: "insights", icon: "◇", onCopy: {
                        meeting.insightsAsMarkdown()
                    })
                    
                    HistoricalInsightsModeSelector(
                        selectedMode: Binding(
                            get: { appState.insightsMode },
                            set: { appState.insightsMode = $0 }
                        )
                    )
                    GradientDivider()
                    
                    ScrollView {
                        insightsContent
                    }
                }
                .frame(minWidth: 280, maxWidth: 380)
            }
        }
        .background(Theme.bg)
        .onDisappear {
            saveTitle()
        }
    }
    
    private var transcriptContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            let sortedSegments = meeting.segments.sorted { $0.timestamp < $1.timestamp }
            ForEach(Array(sortedSegments.enumerated()), id: \.element.id) { index, segment in
                let isNewTurn = index == 0 || sortedSegments[index].speaker != sortedSegments[index - 1].speaker
                
                VStack(alignment: .leading, spacing: 0) {
                    if isNewTurn {
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(speakerColors[segment.speaker % speakerColors.count])
                                .frame(width: 3, height: 12)
                                .cornerRadius(1.5)
                            
                            Text("Speaker \(segment.speaker + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(speakerColors[segment.speaker % speakerColors.count])
                            
                            Text("•")
                                .foregroundStyle(Theme.textDim)
                            
                            Text(segment.formattedTimestamp)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    }
                    
                    HStack(alignment: .top, spacing: 0) {
                        Rectangle()
                            .fill(speakerColors[segment.speaker % speakerColors.count].opacity(0.3))
                            .frame(width: 2)
                        
                        Text(segment.text)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                            .padding(.leading, 12)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(16)
    }
    
    private func saveTitle() {
        meeting.title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if meeting.title.isEmpty {
            meeting.title = "untitled"
        }
        try? modelContext.save()
    }
    
    private var insightsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !meeting.segments.isEmpty && appState.insightsMode != .training {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await appState.generateInsightsForMeeting(meeting)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .semibold))
                            Text((meeting.hasInsights || meeting.hasMEDDPICC) ? "update" : "generate")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            if appState.insightsMode == .meddpicc && !meeting.hasMEDDPICC {
                                Text("meddpicc")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.bgTertiary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(appState.isGeneratingInsights)
                    .opacity(appState.isGeneratingInsights ? 0.5 : 1.0)
                    
                    if appState.isGeneratingInsights {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("updating...")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                    
                    Spacer()
                }
            }

            if appState.insightsMode == .standard {
                if meeting.hasInsights {
                // Summary
                if let summary = meeting.summaryText {
                    DetailInsightBlock(title: "summary", color: Theme.accentBlue) {
                        Text(summary)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .lineSpacing(4)
                    }
                }
                
                // Discussion Flow
                if !meeting.discussionFlow.isEmpty {
                    DetailInsightBlock(title: "discussion", color: ColorPalette.Accent.yellow) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(meeting.discussionFlow.enumerated()), id: \.offset) { index, item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(ColorPalette.Accent.yellow.opacity(0.7))
                                        .frame(width: 16, alignment: .trailing)
                                    Text(item)
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(Theme.text)
                                }
                            }
                        }
                    }
                }
                
                // Actions
                if !meeting.actionItems.isEmpty {
                    DetailInsightBlock(title: "actions", color: Theme.accent) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(meeting.actionItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("→")
                                        .foregroundStyle(Theme.accent)
                                    Text(item)
                                        .foregroundStyle(Theme.text)
                                }
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                            }
                        }
                    }
                }
                
                // Topics
                if !meeting.topics.isEmpty {
                    DetailInsightBlock(title: "topics", color: ColorPalette.Accent.purple) {
                        FlowLayout(spacing: 6) {
                            ForEach(meeting.topics, id: \.self) { topic in
                                Text("#\(topic.lowercased().replacingOccurrences(of: " ", with: "_"))")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(ColorPalette.Accent.purple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ColorPalette.Accent.purple.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Text("◇")
                            .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                        Text("no insights")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if appState.insightsMode == .meddpicc {
                if meeting.hasMEDDPICC {
                    SavedMEDDPICCBlocks(meeting: meeting)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Text("◇")
                            .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                        Text("no meddpicc yet")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                        Text("use update above")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                if !meeting.segments.isEmpty {
                    SavedTrainingSection(meeting: meeting)
                } else {
                VStack(spacing: 12) {
                    Spacer()
                    Text("◇")
                        .font(.system(size: 32, weight: .ultraLight, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    Text("no transcript")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Detail Section Header

struct DetailSectionHeader: View {
    let title: String
    let icon: String
    var onCopy: (() -> String)? = nil
    
    @State private var showCopied = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textDim)
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            Spacer()
            
            // Copy button
            if let onCopy = onCopy {
                Button {
                    let markdown = onCopy()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
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
                        Text(showCopied ? "copied" : "md")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(showCopied ? Theme.accent : Theme.textDim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.bgTertiary)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bgSecondary)
    }
}

struct HistoricalInsightsModeSelector: View {
    @Binding var selectedMode: InsightsMode
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(InsightsMode.allCases.enumerated()), id: \.element) { index, mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(mode.displayName)
                            .font(.system(size: 11, weight: selectedMode == mode ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(selectedMode == mode ? Theme.text : Theme.textDim)
                        
                        Text("⌘\(index + 1)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(selectedMode == mode ? Theme.text.opacity(0.4) : Theme.textDim.opacity(0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedMode == mode ? Theme.accent.opacity(0.15) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bgSecondary)
    }
}

// MARK: - Saved Notes View

struct SavedNotesView: View {
    @Bindable var meeting: Meeting
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if meeting.notes.isEmpty && !isFocused {
                Text("No notes for this meeting")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            
            // Editable text editor
            TextEditor(text: $meeting.notes)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(Theme.bg)
    }
}

// MARK: - Detail Insight Block

struct DetailInsightBlock<Content: View>: View {
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
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            
            content()
                .padding(.leading, 12)
        }
    }
}

// MARK: - Saved MEDDPICC Blocks

struct SavedMEDDPICCBlocks: View {
    let meeting: Meeting
    
    private var fields: [(title: String, color: Color, value: String?)] {
        [
            ("metrics", Color(hex: "3B82F6"), meeting.meddpiccMetrics),
            ("economic buyer", Color(hex: "8B5CF6"), meeting.meddpiccEconomicBuyer),
            ("decision criteria", Color(hex: "EC4899"), meeting.meddpiccDecisionCriteria),
            ("decision process", Color(hex: "F59E0B"), meeting.meddpiccDecisionProcess),
            ("paper process", Color(hex: "F97316"), meeting.meddpiccPaperProcess),
            ("identified pain", Color(hex: "EF4444"), meeting.meddpiccIdentifiedPain),
            ("champion", Color(hex: "22C55E"), meeting.meddpiccChampion),
            ("competition", Color(hex: "6366F1"), meeting.meddpiccCompetition),
        ]
    }
    
    private func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !t.isEmpty && t != "null" && t != "n/a" && t != "none"
    }
    
    var body: some View {
        ForEach(fields.filter { hasValue($0.value) }, id: \.title) { field in
            DetailInsightBlock(title: field.title, color: field.color) {
                Text(field.value!)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
            }
        }
    }
}

// MARK: - Saved Training Section

struct SavedTrainingSection: View {
    let meeting: Meeting
    
    private var metrics: TrainingMetrics {
        let segments = meeting.segments.map {
            TrainingMetrics.Segment(text: $0.text, speaker: $0.speaker, isFinal: $0.isFinal)
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(displaySpeakers) { speaker in
                if speaker.totalFillers > 0 || speaker.isLocalMic {
                    DetailInsightBlock(
                        title: "fillers — \(speaker.speakerLabel.lowercased())",
                        color: speaker.isLocalMic ? ColorPalette.Accent.amber : Color(hex: "8B949E")
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Text("total \(speaker.totalFillers)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                                Text("per min \(String(format: "%.1f", speaker.fillersPerMinute))")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.textDim)
                            }
                            
                            if speaker.speakerLabel != "Others" && !speaker.fillers.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(speaker.fillers) { entry in
                                        HStack(spacing: 6) {
                                            Text(entry.word)
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundStyle(Color(hex: "D4D4D8"))
                                                .frame(width: 60, alignment: .trailing)
                                            Text("\(entry.count)")
                                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(ColorPalette.Accent.amber)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            if metrics.speakers.count > 1 {
                DetailInsightBlock(title: "talk_ratio", color: ColorPalette.Accent.blue) {
                    HStack(spacing: 8) {
                        Text("you \(Int(metrics.talkRatioYou * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.text)
                        Text("•")
                            .foregroundStyle(Theme.textDim)
                        Text("others \(Int((1 - metrics.talkRatioYou) * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                }
            }
            
            DetailInsightBlock(title: "pace", color: ColorPalette.Accent.purple) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displaySpeakers) { speaker in
                        SavedTrainingMetricRow(
                            speaker: speaker,
                            value: "\(Int(speaker.wordsPerMinute)) wpm",
                            trailing: "\(speaker.wordCount) words"
                        )
                    }
                }
            }
            
            DetailInsightBlock(title: "longest_monologue", color: ColorPalette.Accent.pink) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displaySpeakers) { speaker in
                        if speaker.longestMonologueWords > 0 {
                            SavedTrainingMetricRow(
                                speaker: speaker,
                                value: "\(speaker.longestMonologueWords) words"
                            )
                        }
                    }
                }
            }
            
            DetailInsightBlock(title: "questions_asked", color: ColorPalette.Accent.green) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displaySpeakers) { speaker in
                        SavedTrainingMetricRow(
                            speaker: speaker,
                            value: "\(speaker.questionsAsked)"
                        )
                    }
                }
            }
            
            DetailInsightBlock(title: "clarity", color: ColorPalette.Accent.yellow) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displaySpeakers) { speaker in
                        SavedTrainingMetricRow(
                            speaker: speaker,
                            value: String(format: "%.1f", speaker.avgWordsPerTurn),
                            trailing: "avg words/turn"
                        )
                    }
                    Text("shorter turns = more focused communication")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }
}

private struct SavedTrainingMetricRow: View {
    let speaker: TrainingMetrics.SpeakerStats
    let value: String
    var trailing: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Text(speaker.speakerLabel.lowercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(speaker.isLocalMic ? Theme.accent : Theme.textDim)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }
}

// MARK: - Visual Effect View (keep for compatibility)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Keyboard Shortcuts Overlay

struct KeyboardShortcutsOverlay: View {
    @EnvironmentObject var keyboardService: KeyboardShortcutsService
    
    private var groupedShortcuts: [String: [KeyboardShortcut]] {
        Dictionary(grouping: allKeyboardShortcuts, by: { $0.category })
    }
    
    private let categoryOrder = ["Recording", "Navigation", "Insights", "App"]
    
    private func keycap(_ text: String, minWidth: CGFloat = 86, compact: Bool = false) -> some View {
        Text(text)
            .font(.system(size: compact ? 11 : 14, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.text)
            .frame(minWidth: minWidth, alignment: .center)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 7)
            .background(
                RoundedRectangle(cornerRadius: compact ? 6 : 8)
                    .fill(Theme.bgSecondary.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 6 : 8)
                    .stroke(Theme.border.opacity(0.9), lineWidth: 1)
            )
    }
    
    var body: some View {
        ZStack {
            // Dim background
            LinearGradient(
                colors: [
                    Color.black.opacity(0.82),
                    Color.black.opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()
                .onTapGesture {
                    keyboardService.showingHelp = false
                }
            
            // Shortcuts panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("⌨")
                        .font(.system(size: 18))
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    
                    Spacer()
                    
                    Button {
                        keyboardService.showingHelp = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textDim)
                            .frame(width: 24, height: 24)
                            .background(Theme.bgSecondary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Theme.bgSecondary.opacity(0.9))
                
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                
                // Shortcuts grid
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(categoryOrder, id: \.self) { category in
                            if let shortcuts = groupedShortcuts[category] {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(category.uppercased())
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.accent)
                                        .padding(.bottom, 4)
                                    
                                    ForEach(shortcuts) { shortcut in
                                        HStack(alignment: .center, spacing: 12) {
                                            keycap(shortcut.keys, minWidth: 96)
                                            
                                            Text(shortcut.description)
                                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                                .foregroundStyle(Theme.textMuted)
                                            
                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(maxHeight: 420)
                
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                
                // Footer
                HStack {
                    Text("Press")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    keycap("Esc", minWidth: 0, compact: true)
                    Text("or")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    keycap("⌘/", minWidth: 0, compact: true)
                    Text("to close")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Theme.bgSecondary.opacity(0.9))
            }
            .frame(width: 460)
            .frame(maxHeight: 560)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.bg.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Theme.border.opacity(0.95), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    .padding(1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.42), radius: 28, y: 10)
            .shadow(color: Theme.accent.opacity(0.08), radius: 40, y: 0)
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
    }
}

#Preview {
    MainWindow()
        .environmentObject(AppState())
        .environmentObject(KeyboardShortcutsService.shared)
}
