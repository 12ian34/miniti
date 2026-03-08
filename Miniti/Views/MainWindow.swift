import SwiftUI
import SwiftData
import AppKit
import Combine

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
    @State private var meetings: [Meeting] = []
    @State private var selectedMeetingID: UUID?
    @State private var sidebarCollapsed = false
    @State private var didInitialize = false

    private var selectedMeeting: Meeting? {
        guard let selectedMeetingID else { return nil }
        return meetings.first(where: { $0.id == selectedMeetingID })
    }
    
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Sidebar
                TerminalSidebar(
                    meetings: meetings,
                    selectedMeetingID: $selectedMeetingID,
                    isCollapsed: $sidebarCollapsed,
                    onDeleteMeeting: { meeting in
                        deleteMeeting(meeting)
                    }
                )
                .frame(width: sidebarCollapsed ? 68 : 260)
                
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
                    MeetingDetailView(meeting: meeting)
                        .id(meeting.id)
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
            initializeIfNeeded()
            refreshMeetings()
            selectPendingSavedMeetingIfNeeded()
        }
        .onChange(of: appState.currentMeeting) { _, newMeeting in
            // When starting a new meeting, deselect historical meeting
            if newMeeting != nil {
                selectedMeetingID = nil
            }
            refreshMeetings()
        }
        .onChange(of: appState.pendingOpenSavedMeetingID) { _, _ in
            refreshMeetings()
            selectPendingSavedMeetingIfNeeded()
        }
        .onChange(of: meetings.map(\.id)) { _, _ in
            selectPendingSavedMeetingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMeetings()
            if appState.appMode == .managed {
                Task { await appState.refreshUsage() }
            }
        }
    }

    private func initializeIfNeeded() {
        guard !didInitialize else { return }
        didInitialize = true
        appState.modelContext = modelContext
        appState.resumeInterruptedMeeting()
        setupNavigationHandlers()
    }
    
    private func setupNavigationHandlers() {
        keyboardService.onNewSession = { [self] in
            appState.createNewSession()
            selectedMeetingID = nil
        }

        keyboardService.onNavigateUp = { [self] in
            navigateHistory(direction: -1)
        }
        
        keyboardService.onNavigateDown = { [self] in
            navigateHistory(direction: 1)
        }

        keyboardService.onToggleSidebarCollapse = { [self] in
            withAnimation(.easeInOut(duration: 0.16)) {
                sidebarCollapsed.toggle()
            }
        }

        keyboardService.onToggleInsightsCollapse = { [self] in
            withAnimation(.easeInOut(duration: 0.16)) {
                appState.isLiveInsightsCollapsed.toggle()
            }
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
        
        if let selectedMeetingID,
           let currentIndex = historicalMeetings.firstIndex(where: { $0.id == selectedMeetingID }) {
            // Move from current selection
            let newIndex = currentIndex + direction
            if newIndex >= 0 && newIndex < historicalMeetings.count {
                self.selectedMeetingID = historicalMeetings[newIndex].id
            }
        } else {
            // No selection - select first or last based on direction
            if direction > 0 {
                selectedMeetingID = historicalMeetings.first?.id
            } else {
                selectedMeetingID = historicalMeetings.last?.id
            }
        }
    }
    
    private func deleteMeeting(_ meeting: Meeting) {
        // Deselect if this was selected
        if selectedMeetingID == meeting.id {
            selectedMeetingID = nil
        }
        // Delete from context
        modelContext.delete(meeting)
        try? modelContext.save()
        refreshMeetings()
    }

    private func selectPendingSavedMeetingIfNeeded() {
        guard let pendingID = appState.pendingOpenSavedMeetingID else { return }
        guard let meeting = meetings.first(where: { $0.id == pendingID }) else { return }
        selectedMeetingID = meeting.id
        appState.pendingOpenSavedMeetingID = nil
    }

    private func refreshMeetings() {
        let descriptor = FetchDescriptor<Meeting>()
        guard let fetched = try? modelContext.fetch(descriptor) else { return }
        meetings = fetched.sorted { $0.startTime > $1.startTime }

        if let selectedMeetingID, !fetched.contains(where: { $0.id == selectedMeetingID }) {
            self.selectedMeetingID = nil
        }
    }
}

struct TerminalSidebar: View {
    @EnvironmentObject var appState: AppState
    let meetings: [Meeting]
    @Binding var selectedMeetingID: UUID?
    @Binding var isCollapsed: Bool
    let onDeleteMeeting: (Meeting) -> Void
    @State private var historyCollapsed = false
    @State private var collapsedStatusPulse = false
    
    // Filter out the current meeting from history
    private var historicalMeetings: [Meeting] {
        meetings.filter { $0.id != appState.currentMeeting?.id }
    }
    
    var body: some View {
        if isCollapsed {
            collapsedSidebar
        } else {
            expandedSidebar
        }
    }
    
    private var collapsedSidebar: some View {
        VStack(alignment: .center, spacing: 0) {
            Button {
                selectedMeetingID = nil
            } label: {
                Text("⬢")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                        .fill(selectedMeetingID == nil ? Theme.bgTertiary : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.top, 14)
            
            GradientDivider()
                .padding(.top, 14)
                .padding(.bottom, 12)
            
            Button {
                selectedMeetingID = nil
            } label: {
                VStack(spacing: 5) {
                    Circle()
                        .fill(appState.currentMeeting == nil ? Theme.textDim : (appState.isRecording ? Theme.accentRed : Theme.accentBlue))
                        .frame(width: 8, height: 8)
                        .shadow(
                            color: (appState.currentMeeting == nil ? Theme.textDim : (appState.isRecording ? Theme.accentRed : Theme.accentBlue)).opacity(0.5),
                            radius: appState.isRecording ? 4 : 2
                        )
                        .scaleEffect(appState.isRecording && collapsedStatusPulse ? 1.18 : 1.0)
                        .opacity(appState.isRecording && collapsedStatusPulse ? 0.8 : 1.0)
                    
                    Text(appState.currentMeeting == nil ? "idle" : (appState.isRecording ? "rec" : "sess"))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(appState.currentMeeting == nil ? Theme.textDim : Theme.textMuted)
                        .lineLimit(1)
                }
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedMeetingID == nil ? Theme.bgTertiary : Theme.bgSecondary.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedMeetingID == nil ? Theme.border : Color.clear, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            
            Spacer()
            
            VStack(spacing: 0) {
                GradientDivider()
                
                HStack {
                    Spacer()
                    VStack(spacing: 3) {
                        Text("⌘[")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textDim.opacity(0.5))
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isCollapsed = false
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textDim)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Theme.bgTertiary)
                                )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
            }
        }
        .background(Theme.bgSecondary)
        .onAppear {
            updateCollapsedStatusPulse()
        }
        .onChange(of: appState.isRecording) { _, _ in
            updateCollapsedStatusPulse()
        }
        .onChange(of: appState.currentMeeting?.id) { _, _ in
            updateCollapsedStatusPulse()
        }
    }
    
    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo/Title
            HStack(spacing: 10) {
                Button {
                    selectedMeetingID = nil
                } label: {
                    HStack(spacing: 10) {
                        Text("⬢")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                        Text("miniti")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.text)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)

                Spacer()
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
                        isSelected: selectedMeetingID == nil
                    ) {
                        selectedMeetingID = nil
                    }
                } else {
                    // New session button when no current meeting
                    SidebarItem(
                        icon: "+",
                        label: "new session",
                        isSelected: selectedMeetingID == nil,
                        accentColor: Theme.accent,
                        shortcut: "⌘N"
                    ) {
                        appState.createNewSession()
                        selectedMeetingID = nil
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
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                historyCollapsed.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: historyCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Theme.textDim.opacity(0.8))
                                    .frame(width: 10)
                                Text("history")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.textDim)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        
                        Spacer()
                        
                        if !historyCollapsed {
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
                    }
                    .padding(.horizontal, 16)
                    
                    if !historyCollapsed {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(historicalMeetings) { meeting in
                                    SidebarHistoryItem(
                                        meeting: meeting,
                                        isSelected: selectedMeetingID == meeting.id,
                                        action: {
                                            selectedMeetingID = meeting.id
                                        },
                                        onDelete: {
                                            onDeleteMeeting(meeting)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                        .scrollIndicators(.hidden)
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
                    
                    Spacer(minLength: 8)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isCollapsed = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("⌘[")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textDim.opacity(0.5))
                            Image(systemName: "sidebar.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textDim)
                                .frame(width: 26, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Theme.bgTertiary)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(Theme.bgSecondary)
    }

    private func updateCollapsedStatusPulse() {
        guard appState.currentMeeting != nil, appState.isRecording else {
            collapsedStatusPulse = false
            return
        }

        collapsedStatusPulse = false
        withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
            collapsedStatusPulse = true
        }
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
            .contentShape(RoundedRectangle(cornerRadius: 8))
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
            .contentShape(RoundedRectangle(cornerRadius: 8))
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
    @AppStorage("attioExportEnabled") private var attioExportEnabled: Bool = false
    @State private var showingAttioSheet = false
    
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
                
                HStack(spacing: 12) {
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

                    if attioExportEnabled {
                        Button {
                            showingAttioSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                AttioLogoMark()
                                    .frame(width: 14, height: 14)
                                Text("send to attio")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(Color(hex: "F97316"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: "F97316").opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: "F97316").opacity(0.22), lineWidth: 1)
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
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
                Group {
                    if appState.isLiveInsightsCollapsed {
                        HistoricalCollapsedInsightsRail()
                    } else {
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
                            
                            GradientDivider()
                            
                            HStack {
                                HStack(spacing: 4) {
                                    HistoricalInsightsPaneToggleButton(direction: .collapse) {
                                        withAnimation(.easeInOut(duration: 0.16)) {
                                            appState.isLiveInsightsCollapsed = true
                                        }
                                    }
                                    Text("⌘]")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Theme.textDim.opacity(0.5))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.bgSecondary)
                        }
                    }
                }
                .frame(minWidth: appState.isLiveInsightsCollapsed ? 44 : 280,
                       maxWidth: appState.isLiveInsightsCollapsed ? 44 : 380)
            }
        }
        .background(Theme.bg)
        .onDisappear {
            saveTitle()
        }
        .sheet(isPresented: $showingAttioSheet) {
            AttioSendSheet(meeting: meeting)
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
                            
                            Text(segment.speakerLabel)
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
                                Text("#\(topic.lowercased().replacingOccurrences(of: "_", with: " "))")
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

private struct HistoricalInsightsPaneToggleButton: View {
    enum Direction { case collapse, expand }
    let direction: Direction
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .collapse ? "sidebar.right" : "sidebar.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.bgTertiary)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

private struct HistoricalCollapsedInsightsRail: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            Text("insights")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(height: 120)
                .padding(.top, 12)
            
            Spacer()
            
            GradientDivider()
            
            HStack {
                Spacer()
                VStack(spacing: 3) {
                    Text("⌘]")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textDim.opacity(0.5))
                    HistoricalInsightsPaneToggleButton(direction: .expand) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appState.isLiveInsightsCollapsed = false
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .background(Theme.bgSecondary)
        }
        .background(Theme.bg)
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
                        Text(showCopied ? "copied" : "copy")
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
        InsightsModeTabs(selectedMode: $selectedMode)
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
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
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
                MEDDPICCBulletText(field.value!, fontSize: 12, color: Theme.text)
            }
        }
    }
}

// MARK: - Saved Training Section

struct SavedTrainingSection: View {
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(displaySpeakers) { speaker in
                if speaker.totalFillers > 0 || speaker.isLocalMic {
                    DetailInsightBlock(
                        title: "fillers: \(speaker.speakerLabel.lowercased())",
                        color: speaker.isLocalMic ? ColorPalette.Accent.amber : Color(hex: "8B949E"),
                        info: .fillers
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
                DetailInsightBlock(title: "talk ratio", color: ColorPalette.Accent.blue, info: .talkRatio) {
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
            
            DetailInsightBlock(title: "pace", color: ColorPalette.Accent.purple, info: .pace) {
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
            
            DetailInsightBlock(title: "longest monologue", color: ColorPalette.Accent.pink, info: .longestMonologue) {
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
            
            DetailInsightBlock(title: "questions asked", color: ColorPalette.Accent.green, info: .questionsAsked) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displaySpeakers) { speaker in
                        SavedTrainingMetricRow(
                            speaker: speaker,
                            value: "\(speaker.questionsAsked)"
                        )
                    }
                }
            }
            
            DetailInsightBlock(title: "clarity", color: ColorPalette.Accent.yellow, info: .clarity) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displaySpeakers) { speaker in
                        SavedTrainingMetricRow(
                            speaker: speaker,
                            value: String(format: "%.1f", speaker.avgWordsPerTurn),
                            trailing: "avg words/turn"
                        )
                    }
                    Text("lower = clearer = better")
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

// MARK: - Attio Send (macOS history detail only)

struct AttioLogoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "FB923C").opacity(0.18))
            Circle()
                .fill(Color(hex: "F97316"))
                .frame(width: 6, height: 6)
                .offset(x: -2.5, y: -1.5)
            Circle()
                .fill(Color(hex: "FDBA74"))
                .frame(width: 4, height: 4)
                .offset(x: 3, y: 2)
        }
    }
}

struct AttioSendSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meeting: Meeting
    @AppStorage("attioCreateTasksFromActionItems") private var createTasksFromActionItems: Bool = true

    @State private var api = MinitiAPIService()
    @State private var status: MinitiAPIService.AttioStatusResponse?
    @State private var isLoadingStatus = false
    @State private var isConnecting = false
    @State private var connectionError: String?

    @State private var query = ""
    @State private var selectedScope: AttioSearchScope = .both
    @State private var results: [MinitiAPIService.AttioSearchRecord] = []
    @State private var selectedRecordID: String?
    @State private var selectedRecordObject: String?
    @State private var selectedRecordText: String?
    @State private var selectedRecordDetail: String?
    @State private var showSearchResults = false
    @State private var isSearching = false
    @State private var searchError: String?

    @State private var isSending = false
    @State private var sendMessage: String?
    @State private var sendError: String?
    @State private var localEscapeMonitor: Any?

    private let deviceId = DeviceIdentifier.getOrCreateDeviceId()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(hex: "1C1C1F"))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionSection
                    searchSection
                    payloadPreviewSection
                    sendSection
                }
                .padding(16)
            }
            .background(Color(hex: "09090B"))
        }
        .frame(width: 640, height: 620)
        .background(Color(hex: "09090B"))
        .task {
            loadPersistedSelection()
            await refreshStatus()
        }
        .onAppear {
            installLocalEscapeMonitor()
        }
        .onDisappear {
            removeLocalEscapeMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minitiAttioOAuthCallback)) { notification in
            guard let callbackURL = notification.userInfo?["url"] as? URL else { return }
            guard callbackURL.scheme?.lowercased() == "miniti-attio" else { return }
            DebugLogger.shared.log(.app, "[attio] oauth callback received path=\(callbackURL.host ?? "")")
            Task { @MainActor in
                await handleOAuthCallback(callbackURL)
            }
        }
#if os(macOS) || os(tvOS)
        .onExitCommand {
            dismiss()
        }
#endif
    }

    private var header: some View {
        HStack(spacing: 10) {
            AttioLogoMark()
                .frame(width: 18, height: 18)
            Text("send to attio")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "E6EDF3"))
            Spacer()
            Button("close") { dismiss() }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: "8B949E"))
                .focusable(false)
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
        .background(Color(hex: "0F0F11"))
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("attio account")

            HStack(spacing: 10) {
                Circle()
                    .fill((status?.connected ?? false) ? Color(hex: "3FB950") : Color(hex: "6B7280"))
                    .frame(width: 8, height: 8)
                Text(connectionStatusText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                Spacer()
                if isLoadingStatus {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await startOAuth() }
                } label: {
                    Text((status?.connected ?? false) ? "reconnect" : "connect")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(hex: "F97316"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: "F97316").opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(isConnecting)
            }

            if let connectionError {
                errorLine(connectionError)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "0F0F11"))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
        )
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("find attio record")

            HStack(spacing: 8) {
                ForEach(AttioSearchScope.allCases, id: \.self) { scope in
                    Button {
                        selectedScope = scope
                    } label: {
                        Text(scope.label)
                            .font(.system(size: 11, weight: selectedScope == scope ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(selectedScope == scope ? Color(hex: "E6EDF3") : Color(hex: "8B949E"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedScope == scope ? Color(hex: "18181B") : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                TextField(searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: "09090B"))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
                    )
                    .onSubmit {
                        Task { await runSearch() }
                    }

                Button {
                    Task { await runSearch() }
                } label: {
                    HStack(spacing: 6) {
                        if isSearching { ProgressView().controlSize(.small) }
                        Text("search")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Color(hex: "58A6FF"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: "58A6FF").opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(isSearching || !(status?.connected ?? false) || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }

            if let searchError {
                errorLine(searchError)
            }

            if let selectedRecordID, let selectedRecordObject {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "pin")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: "8B949E"))
                        Text(selectedRecordText ?? selectedRecordID)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                            .lineLimit(1)
                        Text("· \(selectedRecordObject)")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "8B949E"))
                        Spacer()
                    }
                    if let selectedRecordDetail, !selectedRecordDetail.isEmpty {
                        Text(selectedRecordDetail)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "8B949E"))
                            .padding(.leading, 18)
                            .textSelection(.enabled)
                    }
                }
            }

            if showSearchResults || !results.isEmpty {
                VStack(spacing: 6) {
                if results.isEmpty {
                    Text("no results yet")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "6B7280"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                } else {
                    ForEach(results) { record in
                        Button {
                            selectRecord(record)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(color(for: record.objectSlug))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.recordText)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color(hex: "E6EDF3"))
                                        .lineLimit(1)
                                    if let secondary = record.secondaryIdentifier, !secondary.isEmpty {
                                        Text(secondary)
                                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                                            .foregroundStyle(Color(hex: "8B949E"))
                                            .textSelection(.enabled)
                                    } else {
                                        Text(record.objectSlug)
                                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                                            .foregroundStyle(Color(hex: "8B949E"))
                                    }
                                }
                                Spacer()
                                if selectedRecordID == record.idPayload.recordID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(hex: "3FB950"))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedRecordID == record.idPayload.recordID ? Color(hex: "18181B") : Color(hex: "09090B"))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
            }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "0F0F11"))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
        )
    }

    private var payloadPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("what will be sent")
            VStack(alignment: .leading, spacing: 6) {
                payloadLine("summary", hasValue(meeting.summaryText))
                payloadLine("discussion", !meeting.discussionFlow.isEmpty)
                payloadLine("action items", !normalizedActionItems.isEmpty)
                payloadLine("decisions", !meeting.keyDecisions.isEmpty)
                payloadLine("topics", !meeting.topics.isEmpty)
                payloadLine("MEDDPICC", meeting.hasMEDDPICC)
                payloadLine("notes", !meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                payloadLine("transcript", false, note: "not sent")
                payloadLine("training", false, note: "not sent")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "0F0F11"))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
        )
    }

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("send")

            Toggle(isOn: $createTasksFromActionItems) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("create tasks from action items")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "E6EDF3"))
                    Text(normalizedActionItems.isEmpty ? "No action items found in this meeting" : "Creates Attio tasks linked to the selected record")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "8B949E"))
                }
            }
            .toggleStyle(.switch)
            .focusable(false)
            .disabled(normalizedActionItems.isEmpty)

            if let sendMessage {
                Text(sendMessage)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "3FB950"))
            }
            if let sendError {
                errorLine(sendError)
            }

            Button {
                Task { await sendToAttio() }
            } label: {
                HStack(spacing: 8) {
                    if isSending { ProgressView().controlSize(.small) }
                    AttioLogoMark().frame(width: 12, height: 12)
                    Text("send to attio")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(Color(hex: "F97316"))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(hex: "F97316").opacity(0.08))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "F97316").opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(!(status?.connected ?? false) || selectedRecordID == nil || selectedRecordObject == nil || isSending)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "0F0F11"))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "1C1C1F"), lineWidth: 1))
        )
    }

    private var connectionStatusText: String {
        if isConnecting { return "connecting..." }
        if let status, status.connected {
            if let label = status.accountLabel, !label.isEmpty {
                return "connected (\(label))"
            }
            return "connected"
        }
        return "not connected"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(hex: "E6EDF3"))
    }

    private func errorLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(hex: "F85149"))
    }

    private func payloadLine(_ label: String, _ included: Bool, note: String? = nil) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(included ? Color(hex: "3FB950") : Color(hex: "6B7280"))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "E6EDF3"))
            if let note {
                Text("(\(note))")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "8B949E"))
            }
            Spacer()
        }
    }

    private func color(for objectSlug: String) -> Color {
        switch objectSlug.lowercased() {
        case "people": return Color(hex: "58A6FF")
        case "companies": return Color(hex: "A371F7")
        default: return Color(hex: "8B949E")
        }
    }

    private var searchPlaceholder: String {
        switch selectedScope {
        case .people:
            return "search people..."
        case .companies:
            return "search companies..."
        case .both:
            return "search people or companies..."
        }
    }

    private func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var normalizedActionItems: [String] {
        AttioMeetingPayload.normalizedActionItems(from: meeting.actionItems)
    }

    private func refreshStatus() async {
        isLoadingStatus = true
        defer { isLoadingStatus = false }
        DebugLogger.shared.log(.app, "[attio] status refresh start")
        do {
            status = try await api.attioStatus(deviceId: deviceId)
            connectionError = nil
            DebugLogger.shared.log(
                .app,
                "[attio] status refresh success connected=\(status?.connected == true) account=\(status?.accountLabel ?? "-")"
            )
        } catch {
            status = .init(connected: false, accountLabel: nil)
            if isMissingAttioBackend(error) {
                connectionError = "Attio backend endpoints are not deployed yet"
            }
            DebugLogger.shared.log(.app, "[attio] status refresh failed \(error.localizedDescription)")
        }
    }

    private func startOAuth() async {
        connectionError = nil
        isConnecting = true
        defer { isConnecting = false }
        DebugLogger.shared.log(.app, "[attio] oauth start requested")

        do {
            let start = try await api.attioConnectStart(deviceId: deviceId)
            DebugLogger.shared.log(.app, "[attio] oauth start response callbackScheme=\(start.callbackScheme)")
            guard let authURL = URL(string: start.authURL) else {
                DebugLogger.shared.log(.app, "[attio] oauth start invalid auth URL")
                connectionError = "Invalid Attio auth URL from server"
                return
            }
            guard start.callbackScheme.lowercased() == "miniti-attio" else {
                DebugLogger.shared.log(.app, "[attio] oauth start unexpected callback scheme=\(start.callbackScheme)")
                connectionError = "Unexpected callback scheme from server"
                return
            }
            guard NSWorkspace.shared.open(authURL) else {
                DebugLogger.shared.log(.app, "[attio] oauth browser open failed")
                connectionError = "Could not open browser for Attio login"
                return
            }
            DebugLogger.shared.log(.app, "[attio] oauth browser opened host=\(authURL.host ?? "-")")
        } catch {
            DebugLogger.shared.log(.app, "[attio] oauth start failed \(error.localizedDescription)")
            connectionError = userFacingAttioError(error)
        }
    }

    @MainActor
    private func handleOAuthCallback(_ callbackURL: URL) async {
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let statusValue = components?.queryItems?.first(where: { $0.name == "status" })?.value
        let message = components?.queryItems?.first(where: { $0.name == "message" })?.value
        DebugLogger.shared.log(
            .app,
            "[attio] oauth callback parsed status=\(statusValue ?? "nil") message=\((message ?? "").prefix(120))"
        )

        if statusValue != "success" {
            connectionError = message ?? "Attio connection failed"
            DebugLogger.shared.log(.app, "[attio] oauth callback failed")
            return
        }

        connectionError = nil
        DebugLogger.shared.log(.app, "[attio] oauth callback success, refreshing status")
        await refreshStatus()
    }

    private func runSearch() async {
        searchError = nil
        sendMessage = nil
        guard status?.connected == true else {
            searchError = "Connect Attio first"
            DebugLogger.shared.log(.app, "[attio] search blocked not connected")
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            DebugLogger.shared.log(.app, "[attio] search skipped query too short")
            return
        }

        isSearching = true
        showSearchResults = true
        defer { isSearching = false }
        DebugLogger.shared.log(
            .app,
            "[attio] search start scope=\(selectedScope.label.lowercased()) query='\(trimmed.prefix(80))'"
        )
        do {
            results = try await api.attioSearch(
                deviceId: deviceId,
                query: trimmed,
                objects: selectedScope.objectSlugs
            )
            DebugLogger.shared.log(.app, "[attio] search success results=\(results.count)")
            if let selectedRecordID,
               let selectedRecordObject,
               !results.contains(where: { $0.idPayload.recordID == selectedRecordID && $0.objectSlug == selectedRecordObject }) {
                // Keep persisted target, but clear highlighted current search selection if missing.
                // (Selection remains sendable; this only affects visual matching in results list.)
            }
        } catch {
            searchError = userFacingAttioError(error)
            results = []
            DebugLogger.shared.log(.app, "[attio] search failed \(error.localizedDescription)")
        }
    }

    private func sendToAttio() async {
        sendError = nil
        sendMessage = nil
        guard let selectedRecordID, let selectedRecordObject else {
            sendError = "Select an Attio record first"
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            let meetingPayload = AttioMeetingPayload.from(meeting: meeting)
            let shouldCreateTasks = createTasksFromActionItems && !meetingPayload.actionItems.isEmpty
            DebugLogger.shared.log(
                .app,
                "[attio] send start object=\(selectedRecordObject) record=\(selectedRecordID) " +
                "notesPayload actionItems=\(meetingPayload.actionItems.count) createTasks=\(shouldCreateTasks)"
            )
            if shouldCreateTasks {
                let previewItems = meetingPayload.actionItems.prefix(5).joined(separator: " | ")
                DebugLogger.shared.log(.app, "[attio] normalized action items: \(previewItems)")
            }
            let response = try await api.attioSendMeeting(
                deviceId: deviceId,
                meetingPayload: meetingPayload,
                targetObject: selectedRecordObject,
                targetRecordID: selectedRecordID,
                createTasksFromActionItems: shouldCreateTasks
            )
            if response.success {
                let notePart = "\(response.noteIDs.count) note\(response.noteIDs.count == 1 ? "" : "s")"
                let createdTaskCount = response.taskCount ?? response.taskIDs.count
                let taskPart = shouldCreateTasks
                    ? ", \(createdTaskCount) task\(createdTaskCount == 1 ? "" : "s")"
                    : ""
                let warningPart: String
                if let taskError = response.taskError {
                    DebugLogger.shared.log(
                        .app,
                        "[attio] task creation skipped error='\(taskError)' createdTasks=\(createdTaskCount) noteIDs=\(response.noteIDs.count)"
                    )
                    warningPart = " · task creation skipped: \(taskError)"
                } else if shouldCreateTasks && !meetingPayload.actionItems.isEmpty && createdTaskCount == 0 {
                    DebugLogger.shared.log(
                        .app,
                        "[attio] task creation returned zero tasks without explicit error; actionItems=\(meetingPayload.actionItems.count)"
                    )
                    warningPart = " · sent action items but Attio returned 0 tasks"
                } else {
                    warningPart = ""
                }
                DebugLogger.shared.log(
                    .app,
                    "[attio] send success notes=\(response.noteIDs.count) tasks=\(createdTaskCount)"
                )
                sendMessage = "sent (\(notePart)\(taskPart))\(warningPart)"
            } else {
                DebugLogger.shared.log(.app, "[attio] send response success=false")
                sendError = "Attio send failed"
            }
        } catch {
            DebugLogger.shared.log(.app, "[attio] send failed \(error.localizedDescription)")
            sendError = userFacingAttioError(error)
        }
    }

    private func isMissingAttioBackend(_ error: Error) -> Bool {
        guard case let MinitiAPIService.ServiceError.serverError(message) = error else { return false }
        return message.contains("HTTP 404")
    }

    private func userFacingAttioError(_ error: Error) -> String {
        if isMissingAttioBackend(error) {
            return "Attio backend endpoints are not deployed yet"
        }
        return error.localizedDescription
    }

    private func selectRecord(_ record: MinitiAPIService.AttioSearchRecord) {
        selectedRecordID = record.idPayload.recordID
        selectedRecordObject = record.objectSlug
        selectedRecordText = record.recordText
        selectedRecordDetail = record.secondaryIdentifier
        showSearchResults = false
        results = []
        DebugLogger.shared.log(
            .app,
            "[attio] selected record object=\(record.objectSlug) id=\(record.idPayload.recordID) text='\(record.recordText.prefix(80))'"
        )
        persistSelection()
    }

    private func loadPersistedSelection() {
        let defaults = UserDefaults.standard
        selectedRecordID = defaults.string(forKey: persistedSelectionKey("record_id"))
        selectedRecordObject = defaults.string(forKey: persistedSelectionKey("object"))
        selectedRecordText = defaults.string(forKey: persistedSelectionKey("label"))
        selectedRecordDetail = defaults.string(forKey: persistedSelectionKey("detail"))
    }

    private func persistSelection() {
        let defaults = UserDefaults.standard
        defaults.set(selectedRecordID, forKey: persistedSelectionKey("record_id"))
        defaults.set(selectedRecordObject, forKey: persistedSelectionKey("object"))
        defaults.set(selectedRecordText, forKey: persistedSelectionKey("label"))
        defaults.set(selectedRecordDetail, forKey: persistedSelectionKey("detail"))
    }

    private func persistedSelectionKey(_ suffix: String) -> String {
        "crm.attio.lastSelection.\(meeting.id.uuidString).\(suffix)"
    }

    private func installLocalEscapeMonitor() {
        guard localEscapeMonitor == nil else { return }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard event.keyCode == 53 else { return event } // Esc
            if event.type == .keyDown {
                dismiss()
            }
            return nil // consume to avoid window flash/beep
        }
    }

    private func removeLocalEscapeMonitor() {
        guard let localEscapeMonitor else { return }
        NSEvent.removeMonitor(localEscapeMonitor)
        self.localEscapeMonitor = nil
    }
}

private enum AttioSearchScope: CaseIterable {
    case people
    case companies
    case both

    var label: String {
        switch self {
        case .people: return "people"
        case .companies: return "companies"
        case .both: return "both"
        }
    }

    var objectSlugs: [String] {
        switch self {
        case .people: return ["people"]
        case .companies: return ["companies"]
        case .both: return ["people", "companies"]
        }
    }
}



#Preview {
    MainWindow()
        .environmentObject(AppState())
        .environmentObject(KeyboardShortcutsService.shared)
}
