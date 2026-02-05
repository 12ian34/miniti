import SwiftUI
import SwiftData
import AppKit

// MARK: - Dark Theme Colors
struct Theme {
    static let bg = Color(hex: "09090B")           // Near black
    static let bgSecondary = Color(hex: "0C0C0E")  // Slightly lighter
    static let bgTertiary = Color(hex: "111113")   // Card backgrounds
    static let border = Color(hex: "1C1C1F")       // Subtle borders
    static let borderLight = Color(hex: "27272A")  // Lighter borders
    static let text = Color(hex: "FAFAFA")         // Primary text
    static let textMuted = Color(hex: "D4D4D8")    // Muted text (much brighter)
    static let textDim = Color(hex: "A1A1AA")      // Dim text (brighter)
    static let accent = Color(hex: "22C55E")       // Green accent
    static let accentRed = Color(hex: "EF4444")    // Red for recording
    static let accentBlue = Color(hex: "3B82F6")   // Blue accent
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
                selectedMeeting = historicalMeetings.first // Start from top when pressing up with no selection
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
                    Circle()
                        .fill(appState.deepgramApiKey.isEmpty ? Color(hex: "F59E0B") : Theme.accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: appState.deepgramApiKey.isEmpty ? Color(hex: "F59E0B").opacity(0.5) : Theme.accent.opacity(0.5), radius: 4)
                    
                    Text(appState.deepgramApiKey.isEmpty ? "no_api_key" : "connected")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
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
    
    private var displayTitle: String {
        // Show just the suffix if there is one, otherwise timestamp
        if meeting.title.contains(" - ") {
            return String(meeting.title.split(separator: " - ", maxSplits: 1).last ?? "")
        }
        return meeting.title
    }
    
    private var timestamp: String {
        // Extract timestamp portion
        if meeting.title.contains(" - ") {
            return String(meeting.title.split(separator: " - ", maxSplits: 1).first ?? "")
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
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
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
    }
}

// MARK: - Meeting Detail View (for historical meetings)

struct MeetingDetailView: View {
    let meeting: Meeting
    
    private let speakerColors: [Color] = [
        Color(hex: "3B82F6"),
        Color(hex: "A855F7"),
        Color(hex: "22C55E"),
        Color(hex: "F59E0B"),
        Color(hex: "EC4899"),
        Color(hex: "06B6D4"),
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Text(meeting.title)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                
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
                    
                    ScrollView {
                        insightsContent
                    }
                }
                .frame(minWidth: 280, maxWidth: 380)
            }
        }
        .background(Theme.bg)
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
    
    private var insightsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    DetailInsightBlock(title: "discussion", color: Color(hex: "F59E0B")) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(meeting.discussionFlow.enumerated()), id: \.offset) { index, item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color(hex: "F59E0B").opacity(0.7))
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
                    DetailInsightBlock(title: "topics", color: Color(hex: "A855F7")) {
                        FlowLayout(spacing: 6) {
                            ForEach(meeting.topics, id: \.self) { topic in
                                Text("#\(topic.lowercased().replacingOccurrences(of: " ", with: "_"))")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: "A855F7"))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "A855F7").opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
                
                // MEDDPICC Framework
                if meeting.hasMEDDPICC {
                    SavedMEDDPICCSection(meeting: meeting)
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

// MARK: - Saved MEDDPICC Section

struct SavedMEDDPICCSection: View {
    let meeting: Meeting
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color(hex: "F59E0B"))
                    .frame(width: 3, height: 12)
                    .cornerRadius(1.5)
                Text("MEDDPICC")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "F59E0B"))
            }
            
            // Fields
            VStack(alignment: .leading, spacing: 10) {
                MEDDPICCSavedRow(letter: "M", title: "Metrics", value: meeting.meddpiccMetrics, color: "3B82F6")
                MEDDPICCSavedRow(letter: "E", title: "Economic Buyer", value: meeting.meddpiccEconomicBuyer, color: "8B5CF6")
                MEDDPICCSavedRow(letter: "D", title: "Decision Criteria", value: meeting.meddpiccDecisionCriteria, color: "EC4899")
                MEDDPICCSavedRow(letter: "D", title: "Decision Process", value: meeting.meddpiccDecisionProcess, color: "F59E0B")
                MEDDPICCSavedRow(letter: "P", title: "Paper Process", value: meeting.meddpiccPaperProcess, color: "F97316")
                MEDDPICCSavedRow(letter: "I", title: "Identified Pain", value: meeting.meddpiccIdentifiedPain, color: "EF4444")
                MEDDPICCSavedRow(letter: "C", title: "Champion", value: meeting.meddpiccChampion, color: "22C55E")
                MEDDPICCSavedRow(letter: "C", title: "Competition", value: meeting.meddpiccCompetition, color: "6366F1")
            }
            .padding(.leading, 12)
        }
    }
}

struct MEDDPICCSavedRow: View {
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
                        .foregroundStyle(Color(hex: "FAFAFA"))
                }
                
                Text(value)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
                    .padding(.leading, 22)
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
    
    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.7)
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
                .background(Theme.bgSecondary)
                
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
                                        HStack {
                                            Text(shortcut.keys)
                                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(Theme.text)
                                                .frame(width: 70, alignment: .leading)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Theme.bgSecondary)
                                                .cornerRadius(4)
                                            
                                            Text(shortcut.description)
                                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                                .foregroundStyle(Theme.textMuted)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                
                // Footer
                HStack {
                    Text("Press")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    Text("Esc")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.bgSecondary)
                        .cornerRadius(3)
                    Text("or")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    Text("⌘/")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.bgSecondary)
                        .cornerRadius(3)
                    Text("to close")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Theme.bgSecondary)
            }
            .frame(width: 340)
            .background(Theme.bg)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        }
    }
}

#Preview {
    MainWindow()
        .environmentObject(AppState())
        .environmentObject(KeyboardShortcutsService.shared)
}
