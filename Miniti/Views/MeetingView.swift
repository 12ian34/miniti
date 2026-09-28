import SwiftUI
import Combine

struct MeetingView: View {
    @EnvironmentObject var appState: AppState
    @State private var meetingTitle: String = ""
    var meetings: [Meeting] = []
    
    var body: some View {
        Group {
            if appState.isRecording || (appState.currentMeeting != nil && !appState.isStartingMeeting) {
                // Active session view
                VStack(spacing: 0) {
                    // Header
                    TerminalHeader(meetingTitle: $meetingTitle)

                    if let error = appState.recordingErrorMessage {
                        RecordingIssueBanner(message: error)
                    }

                    if let grace = appState.endingGrace {
                        EndingGraceBanner(grace: grace)
                    }

                    if let prompt = appState.smartMeetingPrompt {
                        SmartMeetingBanner(prompt: prompt)
                    }

                    if let suggestion = appState.investigationSuggestion {
                        InvestigationSuggestionBanner(suggestion: suggestion)
                    }

                    // Only claim the meeting was saved when finalization is running or there is
                    // transcript content to save — a failed start has neither and should show
                    // just the error banner.
                    if !appState.isRecording,
                       appState.isFinalizingMeeting || !appState.liveSegments.isEmpty {
                        PostMeetingReviewBar()
                    }
                    
                    // Divider
                    Rectangle()
                        .fill(Color(hex: "1C1C1F"))
                        .frame(height: 1)
                    
                    // Main content - split view with transcript+notes and live insights
                    HSplitView {
                        // Left side - transcript and notes
                        ResizableNotesLayout {
                            // Transcript (top) - takes most of the space
                            VStack(spacing: 0) {
                                SectionHeader(title: "transcript", icon: "¶", onCopy: {
                                    appState.transcriptAsMarkdown()
                                })
                                TranscriptView()
                            }
                        } notes: {
                            // Notes (bottom) - starts compact, drag to expand
                            VStack(spacing: 0) {
                                SectionHeader(title: "notes", icon: "✎", shortcut: "⌘⇧N", onCopy: {
                                    "## Notes\n\n\(appState.liveNotes)"
                                })
                                NotesEditor()
                            }
                        }
                        .frame(minWidth: 400)
                        
                        // Live Insights (right side)
                        Group {
                            if appState.isLiveInsightsCollapsed {
                                CollapsedInsightsRail()
                            } else {
                                LiveInsightsColumn(onCopyInsights: {
                                    appState.insightsAsMarkdown()
                                })
                            }
                        }
                        .frame(minWidth: appState.isLiveInsightsCollapsed ? 44 : 280,
                               maxWidth: appState.isLiveInsightsCollapsed ? 44 : 600)
                    }
                }
            } else {
                // Ready state - no active session (or starting)
                VStack(spacing: 0) {
                    if let prompt = appState.smartMeetingPrompt, prompt.kind == .callStart {
                        SmartMeetingBanner(prompt: prompt)
                    }
                    ReadyStateView(meetings: meetings)
                }
            }
        }
        .background(Color(hex: "09090B"))
        .onAppear {
            meetingTitle = appState.currentMeeting?.title ?? ""
        }
        .onChange(of: meetingTitle) { _, newValue in
            // Only update meeting if user manually edited (not from auto-update)
            if let meeting = appState.currentMeeting,
               meeting.title != newValue {
                appState.currentMeeting?.title = newValue
            }
        }
        .onChange(of: appState.currentMeeting) { _, meeting in
            meetingTitle = meeting?.title ?? ""
        }
        .onChange(of: appState.currentMeeting?.title) { _, newTitle in
            // Sync when meeting title changes (e.g., from auto-update)
            if let newTitle, newTitle != meetingTitle {
                meetingTitle = newTitle
            }
        }
        .sheet(
            isPresented: Binding(
                get: { appState.isInvestigationPresented },
                set: { presented in
                    if presented {
                        appState.isInvestigationPresented = true
                    } else {
                        appState.dismissInvestigation()
                    }
                }
            )
        ) {
            InvestigationViewMac()
                .environmentObject(appState)
                .frame(minWidth: 560, idealWidth: 680, minHeight: 520, idealHeight: 640)
        }
    }
}

private struct InvestigationSuggestionBanner: View {
    @EnvironmentObject private var appState: AppState
    let suggestion: AppState.InvestigationSuggestion

    var body: some View {
        HStack(spacing: MinitiDesignSystem.Spacing.comfortable) {
            Image(systemName: "magnifyingglass.circle.fill")
                .foregroundStyle(ColorPalette.Accent.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.hairline) {
                Text("worth investigating")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(ColorPalette.Text.primary)
                Text(suggestion.focus)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(ColorPalette.Text.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: MinitiDesignSystem.Spacing.standard)

            Button {
                appState.triggerInvestigation(scope: .web, focus: suggestion.focus)
            } label: {
                MinitiControlLabel(role: .primary, isEmphasized: true) {
                    Label("research", systemImage: "globe")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                }
            }
            .buttonStyle(.plain)

            Button {
                appState.triggerInvestigation(scope: .codebase, focus: suggestion.focus)
            } label: {
                MinitiControlLabel(role: .secondary) {
                    Label("codebase", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                }
            }
            .buttonStyle(.plain)

            Button {
                appState.dismissInvestigationSuggestion()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ColorPalette.Text.dim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss investigation suggestion")
        }
        .padding(.horizontal, MinitiDesignSystem.Spacing.section)
        .padding(.vertical, MinitiDesignSystem.Spacing.control)
        .background(ColorPalette.Accent.blue.opacity(0.08))
        .accessibilityElement(children: .contain)
    }
}

/// The reversible ending-grace countdown: the strongest end signal fired, capture is
/// suspended, and nothing finalizes until the countdown lapses or the user decides.
private struct EndingGraceBanner: View {
    @EnvironmentObject private var appState: AppState
    let grace: EndingGraceState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.down.fill")
                .foregroundStyle(ColorPalette.Status.recording)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(grace.appDisplayName) call ended")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ColorPalette.Text.primary)
                Text("Finishing in \(grace.remainingSeconds)s")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(ColorPalette.Text.muted)
            }

            Spacer(minLength: 8)

            Button("Keep recording") {
                appState.keepRecordingFromEndingGrace()
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorPalette.Accent.green)

            Button("End now") {
                appState.endEndingGraceNow()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ColorPalette.Status.recording.opacity(0.1))
        .accessibilityElement(children: .contain)
    }
}

private struct SmartMeetingBanner: View {
    @EnvironmentObject private var appState: AppState
    let prompt: AppState.SmartMeetingPrompt

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(ColorPalette.Accent.amber)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ColorPalette.Text.primary)
                Text(countdownMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(ColorPalette.Text.muted)
            }

            Spacer(minLength: 8)

            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ColorPalette.Accent.amber.opacity(0.1))
        .accessibilityElement(children: .contain)
    }

    private var iconName: String {
        switch prompt.kind {
        case .calendar: return "calendar.badge.clock"
        case .quiet: return "moon.zzz.fill"
        case .callStart, .callTransition: return "phone.fill"
        case .callEnd: return "phone.down.fill"
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch prompt.kind {
        case .calendar:
            if let eventID = prompt.eventID {
                let nextEvent = appState.upcomingEvents.first(where: { $0.id == eventID })
                if nextEvent?.joinURL != nil {
                    Button("Join next") {
                        appState.joinAndEndAndStartCalendarMeeting(eventID: eventID)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ColorPalette.Accent.green)
                }

                Button("End & start next") {
                    appState.endAndStartCalendarMeeting(eventID: eventID)
                }
                .buttonStyle(.borderedProminent)
                .tint(ColorPalette.Accent.green)

                Button("End meeting") {
                    appState.endMeetingFromSmartPrompt()
                }
                .buttonStyle(.bordered)

                Button("Remind in 2 min") {
                    appState.remindSmartMeetingPromptInTwoMinutes()
                }
                .buttonStyle(.bordered)
            } else {
                Button("End meeting") {
                    appState.endMeetingFromSmartPrompt()
                }
                .buttonStyle(.borderedProminent)
                .tint(ColorPalette.Accent.amber)
            }
            keepRecordingButton

        case .quiet, .callEnd:
            Button("End meeting") {
                appState.endMeetingFromSmartPrompt()
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorPalette.Accent.amber)
            keepRecordingButton

        case .callStart:
            Button("Take notes") {
                appState.startMeetingFromDetectedCall()
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorPalette.Accent.green)

            Button("Not now") {
                appState.dismissDetectedCallStartPrompt()
            }
            .buttonStyle(.bordered)

        case .callTransition:
            Button("End & start next") {
                appState.endAndStartNewMeeting()
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorPalette.Accent.green)
            keepRecordingButton
        }
    }

    private var keepRecordingButton: some View {
        Button("Keep recording") {
            appState.keepRecordingFromSmartMeetingPrompt()
        }
        .buttonStyle(.bordered)
    }

    private var countdownMessage: String {
        if let countdown = prompt.countdown {
            return "\(prompt.message) Starting the next recording in \(countdown)s."
        }
        return prompt.message
    }
}

private struct RecordingIssueBanner: View {
    @EnvironmentObject private var appState: AppState
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ColorPalette.Accent.amber)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(ColorPalette.Text.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(appState.isRecording ? "Retry" : "Resume") {
                if appState.isRecording {
                    appState.retryRecordingHealth()
                } else {
                    appState.startRecording()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorPalette.Accent.amber)

            Button {
                appState.dismissRecordingError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss recording issue")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ColorPalette.Accent.amber.opacity(0.1))
        .accessibilityElement(children: .contain)
    }
}

private struct PostMeetingReviewBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            if appState.isFinalizingMeeting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Finalizing meeting")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ColorPalette.Accent.green)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ColorPalette.Text.primary)
                Text(statusDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(ColorPalette.Text.muted)
            }

            Spacer(minLength: 8)

            if !appState.isFinalizingMeeting {
                Button {
                    if appState.isCurrentMeetingGeneratingFinalInsights {
                        appState.goHome()
                    } else {
                        appState.saveAndOpenCurrentMeeting()
                    }
                } label: {
                    MinitiControlLabel(role: .primary, isEmphasized: true) {
                        HStack(spacing: 6) {
                            Image(systemName: appState.isCurrentMeetingGeneratingFinalInsights ? "rectangle.stack" : "clock.arrow.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                            Text(appState.isCurrentMeetingGeneratingFinalInsights ? "back to meetings" : "open in history")
                                .font(.system(size: 11, weight: .semibold, design: .default))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ColorPalette.Background.secondary)
    }

    private var statusTitle: String {
        if appState.isFinalizingMeeting { return appState.finalizationStatusText }
        if appState.isCurrentMeetingGeneratingFinalInsights { return "Generating final insights…" }
        return "Meeting saved automatically"
    }

    private var statusDetail: String {
        if appState.isFinalizingMeeting {
            return "You can keep reviewing while Miniti finishes and saves automatically."
        }
        if appState.isCurrentMeetingGeneratingFinalInsights {
            return "You can return to meetings now; insights will finish in History."
        }
        return "Review the transcript and insights, resume recording, or open it in History."
    }
}

// MARK: - Home Action Button

struct HomeActionButton: View {
    let icon: String
    let label: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MinitiControlLabel(role: .secondary) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))

                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .lineLimit(1)

                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.meta)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .fixedSize()
    }
}

// MARK: - Ready State View

struct ReadyStateView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var keyboardService: KeyboardShortcutsService
    @Environment(\.openSettings) private var openSettings
    @State private var editingDeepgram = false
    @State private var editingOpenAI = false
    @State private var confirmEvent: MinitiAPIService.CalendarEvent?
    var meetings: [Meeting] = []

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Logo and title
            VStack(spacing: 12) {
                Text("⬢")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "3FB950"))

                Text("miniti")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "E6EDF3"))

                FlashingTagline(
                    text: "multi-dimensional meetings",
                    isIdle: !appState.isMonitoring
                )
            }
            
            // BYOK mode: API key pills
            if appState.appMode == .byok {
                HStack(spacing: 12) {
                    APIStatusPill(
                        label: "deepgram",
                        key: $appState.deepgramApiKey,
                        isEditing: $editingDeepgram,
                        placeholder: "dg_..."
                    )

                    APIStatusPill(
                        label: "openai",
                        key: $appState.openaiApiKey,
                        isEditing: $editingOpenAI,
                        placeholder: "sk-..."
                    )
                }
            }

            // Limit reached warning (managed mode)
            if appState.appMode == .managed, let usage = appState.usageInfo, usage.minutesRemaining < 60, !usage.isLimitReached {
                LimitWarningBanner(minutesRemaining: usage.minutesRemaining)
            }

            // Recovery key nudge (managed account created or migrated, key not yet saved)
            if appState.appMode == .managed && appState.showRecoveryKeyNotice {
                RecoveryKeyNudgeCard()
            }

            // Calendar integration nudge
            if appState.shouldShowCalendarNudge && appState.pendingAutoStartEvent == nil {
                CalendarNudgeCard()
            }

            // Auto-start banner
            if let event = appState.pendingAutoStartEvent {
                AutoStartBanner(event: event, countdown: appState.autoStartCountdown)
            }

            // Start button or blocked state
            if appState.isDeviceDisabled {
                VStack(spacing: 8) {
                    Text("account disabled")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(Color(hex: "F85149"))
                    
                    Text("contact support for help")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(Color(hex: "A1A1AA"))
                }
            } else if appState.isLimitReached {
                VStack(spacing: 8) {
                    Text("limit reached")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(Color(hex: "F85149"))
                    
                    Button {
                        appState.appModeRaw = AppMode.byok.rawValue
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 10))
                            Text("switch to BYOK")
                                .font(.system(size: 11, weight: .medium, design: .default))
                        }
                        .foregroundStyle(Color(hex: "58A6FF"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: "58A6FF").opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            } else {
                Button(action: {
                    if !appState.isStartingMeeting {
                        appState.startNewMeeting()
                    }
                }) {
                    HStack(spacing: 10) {
                        if appState.isStartingMeeting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(hex: "09090B"))
                            Text("starting...")
                                .font(.system(size: 13, weight: .semibold, design: .default))
                        } else {
                            Image(systemName: "record.circle")
                                .font(.system(size: 15))
                            Text("start meeting")
                                .font(.system(size: 13, weight: .semibold, design: .default))
                                .lineLimit(1)
                        }
                        
                        if !appState.isStartingMeeting {
                            Text("⌘⇧R")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(Color(hex: "09090B").opacity(0.5))
                        }
                    }
                    .foregroundStyle(Color(hex: "09090B"))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(appState.isStartingMeeting
                                  ? Color(hex: "484F58")
                                  : appState.canStartRecording ? Color(hex: "3FB950") : Color(hex: "484F58"))
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(!appState.canStartRecording || appState.isStartingMeeting)

                MeetingLanguagePicker(language: $appState.meetingLanguage)
            }

            // Upcoming calendar events
            if appState.pendingAutoStartEvent == nil,
               appState.googleCalendarEnabled && appState.isGoogleCalendarConnected && !appState.upcomingMeetingEvents.isEmpty {
                UpcomingEventsPanel(confirmEvent: $confirmEvent)
                    .frame(maxWidth: 380)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    HStack(alignment: .top, spacing: 0) {
                        AudioSourcePanel()
                            .fixedSize()
                        Spacer()
                        HStack(spacing: 8) {
                            HomeActionButton(
                                icon: "keyboard",
                                label: "shortcuts",
                                shortcut: "⌘/",
                                action: { keyboardService.showingHelp.toggle() }
                            )

                            HomeActionButton(
                                icon: "gearshape",
                                label: "settings",
                                shortcut: "⌘,",
                                action: { openSettings() }
                            )
                        }
                    }

                    if appState.appMode == .managed {
                        ManagedStatusInline()
                    }
                }
                .padding(12)
                .animation(.easeInOut(duration: 0.2), value: appState.isMonitoring)

                Rectangle()
                    .fill(Color(hex: "1C1C1F"))
                    .frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
        .overlay {
            if let event = confirmEvent {
                EventConfirmSheet(event: event, onStart: {
                    appState.startMeetingFromEvent(event)
                    withAnimation(.easeOut(duration: 0.12)) { confirmEvent = nil }
                }, onJoin: {
                    appState.joinAndStartMeeting(from: event)
                    withAnimation(.easeOut(duration: 0.12)) { confirmEvent = nil }
                }, onCancel: {
                    withAnimation(.easeOut(duration: 0.12)) { confirmEvent = nil }
                })
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        
    }

}

private struct AutoStartBanner: View {
    @EnvironmentObject var appState: AppState
    let event: MinitiAPIService.CalendarEvent
    let countdown: Int
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ColorPalette.Accent.green)
                    .frame(width: 8, height: 8)
                    .opacity(countdown % 2 == 0 ? 1 : 0.4)
                    .animation(.easeInOut(duration: 0.5), value: countdown)
                
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .lineLimit(1)
            }
            
            Text("starting in \(countdown)s")
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(ColorPalette.Accent.green)
            
            HStack(spacing: 12) {
                if event.joinURL != nil {
                    Button {
                        appState.joinAndStartMeeting(from: event)
                    } label: {
                        Text("join")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .foregroundStyle(ColorPalette.Background.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(ColorPalette.Accent.green)
                            )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }

                Button {
                    appState.startMeetingFromEvent(event)
                } label: {
                    Text("start now")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(event.joinURL != nil ? ColorPalette.Text.primary : ColorPalette.Background.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(event.joinURL != nil ? ColorPalette.Background.tertiary : ColorPalette.Accent.green)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
                
                Button {
                    appState.dismissAutoStart()
                } label: {
                    Text("dismiss")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ColorPalette.Background.tertiary)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorPalette.Accent.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ColorPalette.Accent.green.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct UpcomingEventsPanel: View {
    @EnvironmentObject var appState: AppState
    @Binding var confirmEvent: MinitiAPIService.CalendarEvent?

    private var displayEvents: [MinitiAPIService.CalendarEvent] {
        Array(appState.upcomingMeetingEvents.prefix(5))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            ForEach(displayEvents) { event in
                CompactEventRow(event: event)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            confirmEvent = event
                        }
                    }
            }
        }
        .frame(width: 320)
    }
}

private struct EventConfirmSheet: View {
    @EnvironmentObject private var appState: AppState
    let event: MinitiAPIService.CalendarEvent
    let onStart: () -> Void
    let onJoin: () -> Void
    let onCancel: () -> Void

    private var timeRange: String? {
        guard let start = event.startDate else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        var s = fmt.string(from: start)
        if let end = event.endDate { s += " – " + fmt.string(from: end) }
        return s
    }

    private var startsInText: String? {
        guard let start = event.startDate else { return nil }
        let mins = Int(ceil(start.timeIntervalSince(Date()) / 60))
        if mins > 1 { return "starts in \(mins) min" }
        if mins == 1 { return "starts in 1 min" }
        return nil
    }

    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let time = timeRange {
                        Text(time)
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(ColorPalette.Text.dim)
                    }
                    if let soon = startsInText {
                        Text(soon)
                            .font(.system(size: 10, weight: .semibold, design: .default))
                            .foregroundStyle(ColorPalette.Accent.amber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(ColorPalette.Accent.amber.opacity(0.12))
                            )
                    }
                }
                .padding(.top, 6)

                if !event.attendees.isEmpty {
                    Divider()
                        .background(ColorPalette.Border.primary)
                        .padding(.vertical, 10)

                    Text("attendees")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(ColorPalette.Text.dim)
                        .padding(.bottom, 6)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(event.attendees) { a in
                            HStack(spacing: 8) {
                                if a.isSelf {
                                    Text("⬢")
                                        .font(.system(size: 10, weight: .bold, design: .default))
                                        .foregroundStyle(ColorPalette.Accent.green)
                                        .frame(width: 14, height: 14)
                                } else {
                                    DomainFavicon(domain: a.domain)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    if let name = a.displayName, name != a.email {
                                        Text(name)
                                            .font(.system(size: 11, weight: .medium, design: .default))
                                            .foregroundStyle(a.isSelf ? ColorPalette.Accent.green : ColorPalette.Text.primary)
                                        Text(a.email)
                                            .font(.system(size: 10, weight: .medium, design: .default))
                                            .foregroundStyle(ColorPalette.Text.dim)
                                    } else {
                                        Text(a.email)
                                            .font(.system(size: 11, weight: .medium, design: .default))
                                            .foregroundStyle(a.isSelf ? ColorPalette.Accent.green : ColorPalette.Text.primary)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()
                    .background(ColorPalette.Border.primary)
                    .padding(.vertical, 10)

                Text("prep notes")
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .foregroundStyle(ColorPalette.Text.dim)
                    .padding(.bottom, 6)

                TextEditor(text: Binding(
                    get: { appState.prepNotes(for: event) },
                    set: { appState.updatePrepNotes($0, for: event) }
                ))
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 92)
                    .background(
                        RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                            .fill(ColorPalette.Background.primary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                            .stroke(ColorPalette.Border.primary, lineWidth: 1)
                    )
                    .accessibilityLabel("Prep notes for \(event.title)")

                HStack(spacing: 10) {
                    Button {
                        onCancel()
                    } label: {
                        HStack(spacing: 6) {
                            Text("cancel")
                                .font(.system(size: 11, weight: .semibold, design: .default))
                            Text("esc")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(ColorPalette.Text.placeholder)
                        }
                        .foregroundStyle(ColorPalette.Text.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ColorPalette.Background.tertiary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(ColorPalette.Border.primary, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)

                    if event.joinURL != nil {
                        Button {
                            onJoin()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 10, weight: .bold))
                                Text("join and take notes")
                                    .font(.system(size: 11, weight: .semibold, design: .default))
                            }
                            .foregroundStyle(ColorPalette.Background.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(ColorPalette.Accent.green)
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }

                    Button {
                        onStart()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 10, weight: .bold))
                            Text("start")
                                .font(.system(size: 11, weight: .semibold, design: .default))
                            Text("⌘↩")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(
                                    (event.joinURL != nil ? ColorPalette.Text.primary : ColorPalette.Background.primary)
                                        .opacity(0.5)
                                )
                        }
                        .foregroundStyle(event.joinURL != nil ? ColorPalette.Text.primary : ColorPalette.Background.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(event.joinURL != nil ? ColorPalette.Background.tertiary : ColorPalette.Accent.green)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(.top, 14)
            }
            .padding(20)
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ColorPalette.Background.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ColorPalette.Border.light, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Escape
                    onCancel()
                    return nil
                }
                if event.modifierFlags.contains(.command) && event.keyCode == 36 { // ⌘↩
                    onStart()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }
}

private struct CompactEventRow: View {
    @EnvironmentObject private var appState: AppState
    let event: MinitiAPIService.CalendarEvent
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(formattedTime)
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(isActive ? ColorPalette.Accent.green : ColorPalette.Text.muted)
                .frame(width: 66, alignment: .leading)

            Text(event.title)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(isHovered ? ColorPalette.Text.primary : ColorPalette.Text.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if let dur = durationText {
                Text(dur)
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(ColorPalette.Text.dim)
            }

            if !event.attendees.isEmpty {
                let extCount = event.externalAttendees.count
                HStack(spacing: 5) {
                    if !allExternalDomains.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(displayDomains, id: \.self) { domain in
                                DomainFavicon(domain: domain)
                            }
                        }
                    }

                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 8))
                        Text("\(extCount > 0 ? extCount : event.attendees.count)")
                            .font(.system(size: 10, weight: .semibold, design: .default))
                    }
                    .foregroundStyle(ColorPalette.Text.dim)
                }
            }

            if !appState.prepNotes(for: event).isEmpty {
                Image(systemName: "note.text")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ColorPalette.Accent.blue)
                    .accessibilityLabel("Has prep notes")
            }

            Image(systemName: "record.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ColorPalette.Accent.green)
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? ColorPalette.Accent.green.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isHovered ? ColorPalette.Accent.green.opacity(0.25) : Color.clear, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var isActive: Bool {
        guard let start = event.startDate, let end = event.endDate else { return false }
        let now = Date()
        return now >= start && now <= end
    }

    private var formattedTime: String {
        guard let date = event.startDate else { return "" }
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInTomorrow(date) {
            formatter.dateFormat = "'tom' HH:mm"
        } else {
            formatter.dateFormat = "EEE HH:mm"
        }
        return formatter.string(from: date).lowercased()
    }

    private var durationText: String? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        let mins = Int(end.timeIntervalSince(start) / 60)
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m > 0 ? "\(h)h\(m)m" : "\(h)h"
        }
        return "\(mins)m"
    }

    private var allExternalDomains: [String] {
        Array(Set(event.externalAttendees.map(\.domain).filter { !$0.isEmpty })).sorted()
    }

    private var displayDomains: [String] {
        Array(allExternalDomains.prefix(4))
    }
}


@MainActor
private final class FaviconCache: ObservableObject {
    static let shared = FaviconCache()
    @Published var images: [String: NSImage] = [:]
    private var inflight: Set<String> = []

    func fetch(_ domain: String) {
        guard images[domain] == nil, !inflight.contains(domain) else { return }
        inflight.insert(domain)
        Task.detached(priority: .utility) {
            guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=32") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = NSImage(data: data), img.size.width > 1 {
                    await MainActor.run { self.images[domain] = img }
                }
            } catch {}
        }
    }
}

private struct DomainFavicon: View {
    let domain: String
    @ObservedObject private var cache = FaviconCache.shared

    var body: some View {
        Group {
            if let nsImage = cache.images[domain] {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Text(String(domain.prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundStyle(ColorPalette.Accent.blue.opacity(0.8))
                    .frame(width: 12, height: 12)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ColorPalette.Accent.blue.opacity(0.15))
                    )
            }
        }
        .onAppear { cache.fetch(domain) }
    }
}

private struct FlashingTagline: View {
    let text: String
    let isIdle: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Group {
            if reduceMotion {
                baseText
            } else {
                TimelineView(.animation(minimumInterval: isIdle ? (1.0 / 8.0) : (1.0 / 24.0), paused: false)) { context in
                    let motion = flashMotion(at: context.date.timeIntervalSinceReferenceDate)
                    ZStack {
                        baseText
                        highlightedText(motion: motion)
                    }
                }
            }
        }
    }
    
    private var baseText: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .default))
            .foregroundStyle(Color(hex: "A1A1AA"))
            .tracking(2)
    }
    
    private func highlightedText(motion: FlashMotion) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .default))
            .foregroundStyle(Color(hex: "3FB950"))
            .tracking(2)
            .opacity(0.72 + (0.20 * motion.spark))
            .blendMode(.plusLighter)
            .mask {
                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    let height = max(proxy.size.height, 1)
                    let primaryX = width * motion.primaryCenter
                    let secondaryX = width * motion.secondaryCenter
                    let primaryWidth = max(width * motion.primaryWidth, 22)
                    let secondaryWidth = max(width * motion.secondaryWidth, 14)
                    
                    ZStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.05 + (0.04 * motion.spark)))
                        
                        Capsule()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: primaryWidth, height: max(height * 0.95, 12))
                            .blur(radius: 5)
                            .offset(x: primaryX - (width / 2))
                        
                        Capsule()
                            .fill(Color.white.opacity(0.62))
                            .frame(width: secondaryWidth, height: max(height * 0.8, 10))
                            .blur(radius: 7)
                            .offset(x: secondaryX - (width / 2))
                    }
                }
            }
    }
    
    private func flashMotion(at time: TimeInterval) -> FlashMotion {
        let t = time * 0.9
        let primaryCenter = clamp01(0.5 + (0.36 * sin(t * 1.4)) + (0.12 * sin((t * 3.1) + 0.8)))
        let secondaryCenter = clamp01(0.5 + (0.41 * sin((t * 1.95) + 1.9)) + (0.08 * sin((t * 5.3) + 0.3)))
        let primaryWidth = CGFloat(0.18 + (0.22 * (0.5 + (0.5 * sin((t * 2.45) + 0.4)))))
        let secondaryWidth = CGFloat(0.09 + (0.14 * (0.5 + (0.5 * sin((t * 3.8) + 2.0)))))
        let spark = CGFloat(0.5 + (0.5 * sin((t * 6.7) + (0.5 * sin(t * 2.2)))))
        
        return FlashMotion(
            primaryCenter: primaryCenter,
            secondaryCenter: secondaryCenter,
            primaryWidth: primaryWidth,
            secondaryWidth: secondaryWidth,
            spark: spark
        )
    }
    
    private func clamp01(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0), 1))
    }
}

private struct FlashMotion {
    let primaryCenter: CGFloat
    let secondaryCenter: CGFloat
    let primaryWidth: CGFloat
    let secondaryWidth: CGFloat
    let spark: CGFloat
}

// MARK: - API Status Pill

struct APIStatusPill: View {
    let label: String
    @Binding var key: String
    @Binding var isEditing: Bool
    let placeholder: String
    
    @FocusState private var isFocused: Bool
    @State private var isHovering = false
    
    var isConnected: Bool { !key.isEmpty }
    
    var body: some View {
        if isEditing {
            // Edit mode - show input field
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "71717A"))
                
                HStack(spacing: 8) {
                    SecureField(placeholder, text: $key)
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(Color(hex: "E6EDF3"))
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                    
                    Button {
                        isEditing = false
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isConnected ? Color(hex: "3FB950") : Color(hex: "71717A"))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "18181B"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "3FB950").opacity(0.5), lineWidth: 1)
                )
            }
            .frame(width: 160)
            .onAppear {
                isFocused = true
            }
        } else {
            // Status pill - click to edit
            Button {
                isEditing = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Color(hex: "3FB950") : Color(hex: "71717A"))
                        .frame(width: 6, height: 6)
                    
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(isConnected ? Color(hex: "D4D4D8") : Color(hex: "71717A"))
                    
                    if isConnected {
                        Text("connected")
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(Color(hex: "3FB950").opacity(0.8))
                    } else {
                        Text("click to add")
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(Color(hex: "71717A").opacity(0.6))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(hex: "0F0F11"))
                        .overlay(
                            Capsule()
                                .stroke(
                                    isConnected 
                                        ? Color(hex: "3FB950").opacity(isHovering ? 0.5 : 0.3) 
                                        : Color(hex: "3F3F46").opacity(isHovering ? 0.8 : 0.5),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }
}

// MARK: - Home Screen Components

struct MeetingLanguagePicker: View {
    @Binding var language: String
    
    private var selectedLang: TranscriptionLanguage {
        TranscriptionLanguage(rawValue: language) ?? .english
    }
    
    var body: some View {
        Menu {
            ForEach(TranscriptionLanguage.allCases, id: \.self) { lang in
                Button {
                    language = lang.rawValue
                } label: {
                    HStack {
                        Text(lang.displayName)
                        if lang == selectedLang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedLang.rawValue.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .default))
                Text(selectedLang.displayName)
                    .font(.system(size: 11, weight: .medium, design: .default))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(ColorPalette.Text.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(ColorPalette.Background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ColorPalette.Border.primary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

struct StatusCheckRow: View {
    let label: String
    let isReady: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Text(isReady ? "✓" : "○")
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(isReady ? Color(hex: "3FB950") : Color(hex: "484F58"))
                .frame(width: 16)
            
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "8B949E"))
            
            Spacer()
            
            Text(isReady ? "configured" : "missing")
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(isReady ? Color(hex: "3FB950") : Color(hex: "D29922"))
        }
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    var onCopy: (() -> String)? = nil
    
    @State private var showCopied = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "484F58"))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(Color(hex: "8B949E"))
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
            
            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "3F3F46"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "0F0F11"))
    }
}

// MARK: - Resizable Notes Layout

/// Custom vertical split: transcript fills available space, notes starts compact
/// with a drag handle to resize, and the transcript keeps a usable minimum height.
struct ResizableNotesLayout<Transcript: View, Notes: View>: View {
    let transcript: Transcript
    let notes: Notes
    
    @State private var notesHeight: CGFloat = 100
    @GestureState private var dragOffset: CGFloat = 0
    private let minNotesHeight: CGFloat = 50
    private let maxNotesHeight: CGFloat = 500
    private let minTranscriptHeight: CGFloat = 200
    private let dividerHeight: CGFloat = 8
    
    init(@ViewBuilder transcript: () -> Transcript, @ViewBuilder notes: () -> Notes) {
        self.transcript = transcript()
        self.notes = notes()
    }
    
    private func maximumNotesHeight(availableHeight: CGFloat) -> CGFloat {
        min(
            maxNotesHeight,
            max(minNotesHeight, availableHeight - minTranscriptHeight - dividerHeight)
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            let maximumNotesHeight = maximumNotesHeight(availableHeight: geometry.size.height)
            let effectiveHeight = min(
                max(notesHeight - dragOffset, minNotesHeight),
                maximumNotesHeight
            )

            VStack(spacing: 0) {
                transcript
                    .frame(maxHeight: .infinity)

                // Drag handle
                Rectangle()
                    .fill(Color(hex: "1C1C1F"))
                    .frame(height: dividerHeight)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(hex: "3F3F46"))
                            .frame(width: 32, height: 2)
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeUpDown.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation.height
                            }
                            .onEnded { value in
                                notesHeight = min(
                                    max(notesHeight - value.translation.height, minNotesHeight),
                                    maximumNotesHeight
                                )
                            }
                    )

                notes
                    .frame(height: effectiveHeight)
                    .clipped()
            }
        }
    }
}

// MARK: - Notes Editor

struct NotesEditor: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if appState.liveNotes.isEmpty && !isFocused {
                Text("relax and take notes...")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "3F3F46"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            
            // Text editor
            TextEditor(text: $appState.liveNotes)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(Color(hex: "E6EDF3"))
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(Color(hex: "09090B"))
    }
}

struct InsightsSectionHeader: View {
    @EnvironmentObject var appState: AppState
    var onCopyInsights: (() -> String)? = nil
    
    @State private var showCopied = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("◇")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                Text("insights")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(Color(hex: "8B949E"))
                
                Spacer()
                
                if let onCopyInsights = onCopyInsights {
                    Button {
                        let markdown = onCopyInsights()
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            InsightsModeTabs()
        }
    }
}

private struct LiveInsightsColumn: View {
    @EnvironmentObject var appState: AppState
    let onCopyInsights: () -> String
    
    var body: some View {
        VStack(spacing: 0) {
            InsightsSectionHeader(onCopyInsights: onCopyInsights)
            LiveInsightsPanel()
            
            Rectangle()
                .fill(Color(hex: "1C1C1F"))
                .frame(height: 1)
            
            HStack {
                HStack(spacing: 4) {
                    InsightsPaneToggleButton(direction: .collapse) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appState.isLiveInsightsCollapsed = true
                        }
                    }
                    Text("⌘]")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(Color(hex: "71717A").opacity(0.5))
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: "0F0F11"))
        }
    }
}

private struct CollapsedInsightsRail: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            Text("insights")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(Color(hex: "8B949E"))
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(height: 120)
                .padding(.top, 12)
            
            Spacer()
            
            Rectangle()
                .fill(Color(hex: "1C1C1F"))
                .frame(height: 1)
            
            HStack {
                Spacer()
                VStack(spacing: 3) {
                    Text("⌘]")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(Color(hex: "71717A").opacity(0.5))
                    InsightsPaneToggleButton(direction: .expand) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appState.isLiveInsightsCollapsed = false
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .background(Color(hex: "0F0F11"))
        }
        .background(Color(hex: "09090B"))
    }
}

private struct InsightsPaneToggleButton: View {
    enum Direction {
        case collapse
        case expand
    }
    
    let direction: Direction
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .collapse ? "sidebar.right" : "sidebar.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "71717A"))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "18181B"))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

struct LiveInsightsPanel: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.interfaceScale) private var interfaceScale
    
    private var canUpdateInsights: Bool {
        appState.currentMeeting != nil && !appState.liveSegments.isEmpty
    }
    
    private var showsUpdateButton: Bool {
        appState.insightsMode != .training && appState.insightsMode != .docs
    }
    
    private var hasMEDDPICCContent: Bool {
        [appState.liveMetrics, appState.liveEconomicBuyer, appState.liveDecisionCriteria,
         appState.liveDecisionProcess, appState.livePaperProcess, appState.liveIdentifiedPain,
         appState.liveChampion, appState.liveCompetition].contains { v in
            guard let v else { return false }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !t.isEmpty && t != "null" && t != "n/a" && t != "none"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    if showsUpdateButton {
                        Button {
                            Task { @MainActor in
                                await appState.generateInsights()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("update")
                                    .font(.system(size: 10, weight: .semibold, design: .default))
                                Text("⌘⇧I")
                                    .font(.system(size: 10, weight: .medium, design: .default))
                                    .foregroundStyle(Color(hex: "52525B"))
                            }
                            .foregroundStyle(Color(hex: "D4D4D8"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(hex: "18181B"))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: "27272A"), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .disabled(!canUpdateInsights || appState.isGeneratingInsights)
                        .opacity((!canUpdateInsights || appState.isGeneratingInsights) ? 0.5 : 1.0)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                
                if appState.insightsMode == .training {
                    // Training mode: locally-computed speech metrics
                    if let metrics = appState.trainingMetrics {
                        LiveTrainingInsightsContent(metrics: metrics)
                    } else {
                        TrainingEmptyState()
                    }
                } else if appState.insightsMode == .questions {
                    if !appState.liveQuestions.isEmpty {
                        QuestionsContent(questions: appState.liveQuestions)
                            .padding(.horizontal, 16)
                    } else if appState.isRecording && !appState.hasReceivedQuestionsInsights {
                        QuestionsEmptyState(variant: .waiting)
                    } else if appState.liveQuestions.isEmpty {
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
                    .padding(.horizontal, 16)
                } else if appState.insightsMode == .template {
                    InsightTemplateCaption(template: appState.liveTemplate)
                        .padding(.horizontal, 16)

                    if appState.isGeneratingInsights {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("filling \(appState.liveTemplate.name.lowercased())…")
                                .font(.system(size: 11, weight: .medium, design: .default))
                                .foregroundStyle(Color(hex: "58A6FF"))
                        }
                        .padding(.horizontal, 16)
                    }

                    LiveTemplateSections()

                    if !appState.hasLiveTemplateContent && !appState.isGeneratingInsights {
                        LiveInsightsEmptyState()
                    }
                } else if appState.insightsMode == .meddpicc {
                    if appState.isGeneratingInsights {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("analyzing sales qualification…")
                                .font(.system(size: 11, weight: .medium, design: .default))
                                .foregroundStyle(Color(hex: "58A6FF"))
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    LiveMEDDPICCSections()
                    
                    if !hasMEDDPICCContent && !appState.isGeneratingInsights {
                        LiveInsightsEmptyState()
                    }
                } else {
                    if appState.isGeneratingInsights {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("updating...")
                                .font(.system(size: 11, weight: .medium, design: .default))
                                .foregroundStyle(Color(hex: "58A6FF"))
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    if !appState.liveSummary.isEmpty {
                        LiveInsightSection(title: "summary", color: Color(hex: "58A6FF")) {
                            SelectableTextView(
                                SelectableAttributed.body(
                                    appState.liveSummary,
                                    fontSize: interfaceScale.insightBodySize,
                                    color: Color(hex: "E6EDF3"),
                                    lineSpacing: interfaceScale.insightLineSpacing
                                )
                            )
                        }
                    }

                    if !appState.liveDiscussionFlow.isEmpty {
                        LiveInsightSection(title: "discussion", color: Color(hex: "F59E0B")) {
                            SelectableTextView(
                                SelectableAttributed.bulletList(
                                    items: appState.liveDiscussionFlow.enumerated().map { "\($0.offset + 1). \($0.element)" },
                                    prefix: "",
                                    prefixColor: Color(hex: "F59E0B"),
                                    fontSize: interfaceScale.insightSecondarySize,
                                    textColor: Color(hex: "D4D4D8")
                                )
                            )
                        }
                    }

                    if !appState.liveActionItems.isEmpty {
                        LiveInsightSection(title: "actions", color: Color(hex: "3FB950")) {
                            SelectableTextView(
                                SelectableAttributed.bulletList(
                                    items: appState.liveActionItems,
                                    prefix: "→",
                                    prefixColor: Color(hex: "3FB950"),
                                    fontSize: interfaceScale.insightSecondarySize,
                                    textColor: Color(hex: "E6EDF3")
                                )
                            )
                        }
                    }
                    
                    if !appState.liveTopics.isEmpty {
                        LiveInsightSection(title: "topics", color: Color(hex: "A371F7")) {
                            FlowLayout(spacing: 6) {
                                ForEach(appState.liveTopics, id: \.self) { topic in
                                    Text("#\(topic.lowercased().replacingOccurrences(of: "_", with: " "))")
                                        .font(.system(size: 10, weight: .medium, design: .default))
                                        .foregroundStyle(Color(hex: "A371F7"))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color(hex: "A371F7").opacity(0.15))
                                        .cornerRadius(3)
                                }
                            }
                        }
                    }
                    
                    if appState.liveSummary.isEmpty && !appState.isGeneratingInsights {
                        LiveInsightsEmptyState()
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding(.top, 12)
        }
        .background(Color(hex: "09090B"))
    }
}

// MARK: - Live MEDDPICC Sections

struct LiveMEDDPICCSections: View {
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
        ForEach(fields.filter { hasValue($0.value) }, id: \.title) { field in
            LiveInsightSection(title: field.title, color: Color(hex: field.color)) {
                MEDDPICCBulletText(field.value!, fontSize: interfaceScale.insightBodySize)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !t.isEmpty && t != "null" && t != "n/a" && t != "none"
    }
}

struct LiveTemplateSections: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.interfaceScale) private var interfaceScale

    var body: some View {
        InsightTemplateSectionList(template: appState.liveTemplate, sections: appState.liveTemplateSections) { title, color, value in
            LiveInsightSection(title: title, color: color) {
                MEDDPICCBulletText(value, fontSize: interfaceScale.insightBodySize)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LiveInsightsEmptyState: View {
    @EnvironmentObject var appState: AppState

    private var mode: InsightsMode { appState.insightsMode }

    var body: some View {
        VStack(spacing: 10) {
            Text(icon)
                .font(.system(size: 28, weight: .ultraLight, design: .default))
                .foregroundStyle(Color(hex: "1C1C1F"))

            if appState.appMode == .byok && appState.openaiApiKey.isEmpty {
                Text("openai key missing")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "D29922"))
            } else if appState.isRecording {
                Text(waitingTitle)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
                Text(waitingSubtitle)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "3F3F46"))
                    .multilineTextAlignment(.center)
            } else {
                Text("start recording")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var icon: String {
        switch mode {
        case .standard: return "◇"
        case .meddpicc: return "◇"
        case .training: return "◇"
        case .questions: return "?"
        case .docs: return "◇"
        case .template: return "◇"
        }
    }

    private var waitingTitle: String {
        switch mode {
        case .standard: return "listening..."
        case .meddpicc: return "listening..."
        case .training: return "waiting for speech..."
        case .questions: return "listening..."
        case .docs: return "finding topics..."
        case .template: return "listening..."
        }
    }

    private var waitingSubtitle: String {
        switch mode {
        case .standard: return "summaries and actions appear\nafter a few sentences"
        case .meddpicc: return "MEDDPICC analysis appears\nonce there's enough context"
        case .training: return "speech metrics update\nas you speak"
        case .questions: return "questions appear once there's\nenough to find gaps"
        case .docs: return "topics appear as you talk,\ngrounded in your docs"
        case .template: return "\(appState.liveTemplate.name.lowercased()) notes appear\nonce there's enough context"
        }
    }
}

struct LiveTrainingInsightsContent: View {
    let metrics: TrainingMetrics

    private var speakerPresentations: [TrainingMetrics.SpeakerPresentation] {
        metrics.speakerPresentations()
    }
    
    private var displaySpeakers: [TrainingMetrics.SpeakerStats] {
        speakerPresentations.map(\.summary)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LiveTrainingFillersSection(presentations: speakerPresentations)
            
            if metrics.speakers.count > 1 {
                LiveInsightSection(title: "talk ratio", color: ColorPalette.Coaching.talkRatio, info: .talkRatio) {
                    VStack(alignment: .leading, spacing: 8) {
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
                        .frame(height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        
                        HStack {
                            Text("you \(Int(metrics.talkRatioYou * 100))%")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(Color(hex: "D4D4D8"))
                            Spacer()
                            Text("others \(Int((1 - metrics.talkRatioYou) * 100))%")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(Color(hex: "D4D4D8"))
                        }
                    }
                }
            }
            
            LiveInsightSection(title: "pace", color: ColorPalette.Coaching.pace, info: .pace) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        LiveTrainingMetricRow(
                            speaker: speaker,
                            value: "\(Int(speaker.wordsPerMinute)) wpm",
                            trailing: "\(speaker.wordCount) words"
                        )
                    }
                }
            }
            
            LiveInsightSection(title: "longest monologue", color: ColorPalette.Coaching.monologue, info: .longestMonologue) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        if speaker.longestMonologueWords > 0 {
                            LiveTrainingMetricRow(
                                speaker: speaker,
                                value: "\(speaker.longestMonologueWords) words"
                            )
                        }
                    }
                }
            }
            
            LiveInsightSection(title: "questions asked", color: ColorPalette.Coaching.questions, info: .questionsAsked) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        LiveTrainingMetricRow(
                            speaker: speaker,
                            value: "\(speaker.questionsAsked)"
                        )
                    }
                }
            }
            
            LiveInsightSection(title: "clarity", color: ColorPalette.Coaching.clarity, info: .clarity) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displaySpeakers) { speaker in
                        LiveTrainingMetricRow(
                            speaker: speaker,
                            value: String(format: "%.1f", speaker.avgWordsPerTurn),
                            trailing: "avg words/turn"
                        )
                    }
                    
                    Text("lower = clearer = better")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Color(hex: "3F3F46"))
                }
            }
        }
    }
}

private struct LiveTrainingFillersSection: View {
    let presentations: [TrainingMetrics.SpeakerPresentation]
    @State private var expandedPresentationIDs: Set<String> = []
    
    var body: some View {
        ForEach(presentations) { presentation in
            let speaker = presentation.summary
            if speaker.totalFillers > 0 || speaker.isLocalMic {
                LiveInsightSection(
                    title: "fillers: \(speaker.speakerLabel.lowercased())",
                    color: speaker.isLocalMic ? ColorPalette.Coaching.fillers : ColorPalette.Text.meta,
                    info: .fillers
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(speaker.totalFillers) fillers (\(String(format: "%.1f", speaker.fillersPerMinute))/min)")
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(Color(hex: "71717A"))
                        
                        if presentation.hasMultipleDetails {
                            Button {
                                toggleDetails(for: presentation.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: expandedPresentationIDs.contains(presentation.id) ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(expandedPresentationIDs.contains(presentation.id) ? "hide speaker details" : "show speaker details")
                                        .font(.system(size: 10, weight: .semibold, design: .default))
                                }
                                .foregroundStyle(ColorPalette.Accent.blue)
                            }
                            .buttonStyle(.plain)

                            if expandedPresentationIDs.contains(presentation.id) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(presentation.details.enumerated()), id: \.offset) { _, detail in
                                        fillerDetail(for: detail)
                                    }
                                }
                            }
                        } else if !speaker.fillers.isEmpty {
                            fillerEntries(speaker.fillers)
                        }
                    }
                }
            }
        }
    }

    private func toggleDetails(for id: String) {
        if expandedPresentationIDs.contains(id) {
            expandedPresentationIDs.remove(id)
        } else {
            expandedPresentationIDs.insert(id)
        }
    }

    private func fillerDetail(for speaker: TrainingMetrics.SpeakerStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(speaker.speakerLabel.lowercased()) · \(speaker.totalFillers)")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(speaker.isLocalMic ? ColorPalette.Accent.green : ColorPalette.Text.secondary)
            if speaker.fillers.isEmpty {
                Text("no fillers detected")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(ColorPalette.Text.meta)
            } else {
                fillerEntries(speaker.fillers)
            }
        }
    }

    private func fillerEntries(_ entries: [TrainingMetrics.FillerEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries) { entry in
                HStack(spacing: 6) {
                    Text(entry.word)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize()
                    Text("\(entry.count)")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(ColorPalette.Coaching.fillers)
                }
            }
        }
    }
}

private struct LiveTrainingMetricRow: View {
    let speaker: TrainingMetrics.SpeakerStats
    let value: String
    var trailing: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Text(speaker.speakerLabel.lowercased())
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(speaker.isLocalMic ? Color(hex: "3FB950") : Color(hex: "8B949E"))
                .frame(width: 48, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(Color(hex: "E6EDF3"))
            
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "484F58"))
            }
        }
    }
}

struct LiveInsightSection<Content: View>: View {
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
                    .cornerRadius(1)
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundStyle(color)
                if let info {
                    TerminalSectionInfoButton(info: info, accent: color)
                }
            }
            
            content()
                .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
    }
}

struct TerminalHeader: View {
    @EnvironmentObject var appState: AppState
    @Binding var meetingTitle: String
    @State private var isEditingTitle = false
    @State private var showDiscardConfirmation = false
    
    private let headerActionHeight = MinitiDesignSystem.Control.compactHeight

    private var isStopped: Bool {
        appState.currentMeeting != nil && !appState.isRecording
    }

    private var isResumePending: Bool {
        isStopped && appState.isResumingRecording
    }
    
    private var recoveryAccent: Color {
        switch appState.audioRecoveryState {
        case .healthy:
            return Color(hex: "3FB950")
        case .recovering:
            return Color(hex: "D29922")
        case .degraded:
            return Color(hex: "F85149")
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if isStopped {
                    Button {
                        showDiscardConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 11)
                                Text("discard")
                                    .font(.system(size: 11, weight: .medium, design: .default))
                            }
                            
                            Text("⌘⌫")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(Color(hex: "F85149").opacity(0.5))
                                .lineLimit(1)
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(Color(hex: "F85149"))
                        .frame(height: headerActionHeight)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: "F85149").opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "F85149").opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.delete, modifiers: .command)
                }
                
                Button {
                    guard !isResumePending else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if appState.isRecording {
                            appState.stopRecording()
                        } else if appState.currentMeeting != nil {
                            appState.managedSessionError = nil
                            appState.startRecording()
                        } else {
                            appState.startNewMeeting()
                        }
                    }
                } label: {
                    let role: MinitiControlRole = appState.isRecording ? .recording : .positive
                    MinitiControlLabel(role: role, isEmphasized: appState.isRecording) {
                        HStack(spacing: 6) {
                            if isResumePending {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(role.accent)
                                    .frame(width: 11)
                            } else {
                                Image(systemName: appState.isRecording ? "stop.fill" : "record.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 11)
                            }
                            Text(isResumePending ? "starting..." : (appState.isRecording ? "stop" : "resume"))
                                .font(.system(size: 12, weight: .semibold, design: .default))
                                .lineLimit(1)
                            Text("⌘⇧R")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .foregroundStyle(role.accent.opacity(MinitiDesignSystem.ControlOpacity.supportingContent))
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isResumePending || appState.isFinalizingMeeting || appState.isCurrentMeetingGeneratingFinalInsights)
                .accessibilityLabel(appState.isRecording ? "Stop recording" : "Resume recording")
                
                if isStopped {
                    if appState.isFinalizingMeeting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 11)
                            Text("finishing...")
                                .font(.system(size: 11, weight: .medium, design: .default))
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(ColorPalette.Text.muted)
                        .frame(height: headerActionHeight)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ColorPalette.Background.tertiary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ColorPalette.Border.subtle, lineWidth: 1)
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(appState.finalizationStatusText)
                    } else if appState.isCurrentMeetingGeneratingFinalInsights {
                        Button {
                            appState.goHome()
                        } label: {
                            MinitiControlLabel(role: .primary, isEmphasized: true) {
                                HStack(spacing: 6) {
                                    Image(systemName: "rectangle.stack")
                                        .font(.system(size: 10, weight: .semibold))
                                        .frame(width: 11)
                                    Text("back to meetings")
                                        .font(.system(size: 11, weight: .semibold, design: .default))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Returns home while insights finish in History")
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                appState.saveAndOpenCurrentMeeting()
                            }
                        } label: {
                            MinitiControlLabel(role: .primary, isEmphasized: true) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .frame(width: 11)
                                    Text("done")
                                        .font(.system(size: 11, weight: .semibold, design: .default))
                                    Text("⌘S")
                                        .font(.system(size: 10, weight: .medium, design: .default))
                                        .foregroundStyle(MinitiControlRole.primary.accent.opacity(MinitiDesignSystem.ControlOpacity.supportingContent))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("s", modifiers: .command)
                        .accessibilityHint("Opens the saved meeting in History")
                    }
                }

                if appState.isRecording {
                    InvestigationButton()
                    ZonedOutButton()
                }

                if let lang = TranscriptionLanguage(rawValue: appState.meetingLanguage), lang != .english {
                    HStack(spacing: 3) {
                        Text(lang.flag)
                            .font(.system(size: 11))
                        Text(lang.rawValue.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .default))
                            .foregroundStyle(ColorPalette.Text.muted)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ColorPalette.Background.tertiary)
                    )
                }
                
                if let meeting = appState.currentMeeting, !meeting.attendees.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text("\(meeting.attendees.filter { !$0.isSelf }.count)")
                            .font(.system(size: 10, weight: .medium, design: .default))
                    }
                    .foregroundStyle(ColorPalette.Text.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ColorPalette.Background.tertiary)
                    )
                }
                
                Spacer(minLength: 0)
            }
            
            HStack(spacing: 8) {
                Circle()
                    .fill(recoveryAccent)
                    .frame(width: 6, height: 6)
                Text(appState.audioRecoveryState.label)
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(recoveryAccent)
                Spacer(minLength: 0)
                if appState.audioRecoveryState == .degraded {
                    Button("Retry") {
                        appState.retryRecordingHealth()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(recoveryAccent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(recoveryAccent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(recoveryAccent.opacity(0.24), lineWidth: 1)
            )
            .opacity(appState.audioRecoveryState == .healthy ? 0 : 1)
            .allowsHitTesting(appState.audioRecoveryState == .degraded)
            .accessibilityHidden(appState.audioRecoveryState == .healthy)
            
            if appState.wasAutoStopped && isStopped {
                let reason = appState.autoStopReason ?? .silence
                HStack(spacing: 6) {
                    Image(systemName: reason.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(reason.label)
                        .font(.system(size: 10, weight: .medium, design: .default))
                }
                .foregroundStyle(ColorPalette.Accent.amber)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ColorPalette.Accent.amber.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ColorPalette.Accent.amber.opacity(0.2), lineWidth: 1)
                )
            }
            
            if appState.calendarEventEndedWhileRecording && appState.isRecording {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10, weight: .semibold))
                    Text("meeting time ended — will stop when silent")
                        .font(.system(size: 10, weight: .medium, design: .default))
                }
                .foregroundStyle(ColorPalette.Accent.amber)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ColorPalette.Accent.amber.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ColorPalette.Accent.amber.opacity(0.2), lineWidth: 1)
                )
            }

            HStack(spacing: 12) {
                if appState.isRecording {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: "F85149"))
                                .frame(width: 8, height: 8)
                                .shadow(color: Color(hex: "F85149").opacity(0.5), radius: 4)
                            
                            Text(appState.formattedDuration)
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .monospacedDigit()
                                .foregroundStyle(Color(hex: "F85149"))
                        }
                        .fixedSize()
                        
                        if appState.captureMicrophone {
                            HStack(spacing: 4) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Color(hex: "3FB950").opacity(0.7))
                                ObservedSourceWaveform(
                                    audioLevels: appState.audioLevels,
                                    source: .microphone,
                                    color: Color(hex: "3FB950"),
                                    bandCount: 5,
                                    barWidth: 3,
                                    maxHeight: 20
                                )
                                .frame(width: 22, height: 20)
                            }
                            .fixedSize()
                        }
                        
                        if appState.captureSystemAudio {
                            HStack(spacing: 4) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Color(hex: "58A6FF").opacity(0.7))
                                ObservedSourceWaveform(
                                    audioLevels: appState.audioLevels,
                                    source: .system,
                                    color: Color(hex: "58A6FF"),
                                    bandCount: 5,
                                    barWidth: 3,
                                    maxHeight: 20
                                )
                                .frame(width: 22, height: 20)
                            }
                            .fixedSize()
                        }
                    }
                }
                
                HStack(spacing: 6) {
                    Text("~")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundStyle(Color(hex: "484F58"))
                    
                    if isEditingTitle {
                        TextField("session_name", text: $meetingTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundStyle(Color(hex: "E6EDF3"))
                            .onSubmit { isEditingTitle = false }
                    } else {
                        Button {
                            isEditingTitle = true
                        } label: {
                            Text(meetingTitle)
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .foregroundStyle(ColorPalette.Text.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit meeting title")
                    }

                    if let event = appState.selectedCalendarEvent, let joinURL = event.joinURL {
                        Button {
                            _ = appState.openMeetingLink(for: event, allowingRepeat: true)
                        } label: {
                            MinitiControlLabel(role: .secondary) {
                                HStack(spacing: 6) {
                                    Image(systemName: "video")
                                        .font(.system(size: 10, weight: .semibold))
                                        .frame(width: 11)
                                    Text("join call")
                                        .font(.system(size: 11, weight: .medium, design: .default))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("Open \(joinURL.host ?? "the meeting link") in your browser")
                        .accessibilityLabel("Join call")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "0F0F11"))
        .alert("Discard recording?", isPresented: $showDiscardConfirmation) {
            Button("Discard", role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if appState.isRecording {
                        appState.stopRecording()
                    }
                    appState.discardCurrentMeeting()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the recording and all associated data.")
        }
    }
}

// MARK: - Source Waveform (per-source mini waveform)

private enum AudioWaveformSource {
    case microphone
    case system
}

private struct ObservedSourceWaveform: View {
    @ObservedObject var audioLevels: AudioLevelsState
    let source: AudioWaveformSource
    let color: Color
    let bandCount: Int
    let barWidth: CGFloat
    let maxHeight: CGFloat

    private var resolvedLevel: Float {
        switch source {
        case .microphone:
            return audioLevels.microphoneLevel < 0.003 ? 0 : audioLevels.microphoneLevel
        case .system:
            return audioLevels.systemAudioLevel
        }
    }

    var body: some View {
        SourceWaveform(
            level: resolvedLevel,
            color: color,
            bandCount: bandCount,
            barWidth: barWidth,
            maxHeight: maxHeight
        )
    }
}

struct SourceWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let level: Float
    let color: Color
    let bandCount: Int
    let barWidth: CGFloat
    let maxHeight: CGFloat
    
    init(level: Float, color: Color, bandCount: Int = 5, barWidth: CGFloat = 3, maxHeight: CGFloat = 18) {
        self.level = level
        self.color = color
        self.bandCount = bandCount
        self.barWidth = barWidth
        self.maxHeight = maxHeight
    }
    
    @State private var bands: [CGFloat] = []
    @State private var previousLevel: CGFloat = 0
    @State private var idleTick = false
    
    let timer = Timer.publish(every: 1.0 / 16.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<bandCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(0.5 + (index < bands.count ? bands[index] : 0.05) * 0.5))
                    .frame(width: barWidth, height: max(2, maxHeight * (index < bands.count ? bands[index] : 0.05)))
            }
        }
        .onAppear {
            bands = Array(repeating: 0.05, count: bandCount)
        }
        .onReceive(timer) { _ in
            guard bands.count == bandCount else { return }
            let rawLevel = CGFloat(max(level, 0))
            if rawLevel < 0.001 {
                idleTick.toggle()
                guard idleTick else { return }
            }
            var transaction = Transaction()
            transaction.animation = reduceMotion ? nil : .linear(duration: 1.0 / 16.0)
            withTransaction(transaction) {
                // Noise gate: suppress levels below threshold
                let gated = rawLevel < 0.001 ? 0.0 : rawLevel
                let amplified = gated > 0 ? min(1.0, pow(gated, 0.2)) : 0.0
                let delta = amplified - previousLevel
                previousLevel = amplified
                
                for i in 0..<bandCount {
                    let position = CGFloat(i) / CGFloat(bandCount - 1)
                    let bassWeight = 1.0 - position * 0.35
                    let transientWeight = position * 4.0
                    let jitter = amplified > 0.1 ? CGFloat.random(in: 0...0.08) : 0
                    let target = amplified * bassWeight + abs(delta) * transientWeight + jitter
                    let factor: CGFloat = target > bands[i] ? 0.6 : 0.15
                    bands[i] = bands[i] + (target - bands[i]) * factor
                    bands[i] = min(1.0, max(0.03, bands[i]))
                }
            }
        }
    }
}

// MARK: - Audio Source Panel (home screen pre-flight)

struct AudioSourcePanel: View {
    @EnvironmentObject var appState: AppState
    @State private var isTesting = false
    
    private var isActive: Bool { isTesting && appState.isMonitoring }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Mic pill + waveform below it
            VStack(alignment: .center, spacing: 4) {
                MicrophoneSourcePill(
                    isEnabled: $appState.captureMicrophone,
                    color: Color(hex: "3FB950")
                )
                if isActive && appState.captureMicrophone {
                    ObservedSourceWaveform(
                        audioLevels: appState.audioLevels,
                        source: .microphone,
                        color: Color(hex: "3FB950"),
                        bandCount: 8,
                        barWidth: 3,
                        maxHeight: 20
                    )
                    .frame(width: 32, height: 20)
                    .transition(.opacity)
                }
            }

            // System pill + waveform below it
            VStack(alignment: .center, spacing: 4) {
                AudioSourcePill(
                    label: "system",
                    isEnabled: $appState.captureSystemAudio,
                    color: Color(hex: "58A6FF")
                )
                if isActive && appState.captureSystemAudio {
                    ObservedSourceWaveform(
                        audioLevels: appState.audioLevels,
                        source: .system,
                        color: Color(hex: "58A6FF"),
                        bandCount: 8,
                        barWidth: 3,
                        maxHeight: 20
                    )
                    .frame(width: 32, height: 20)
                    .transition(.opacity)
                }
            }

            // Test button
            Button {
                if isTesting {
                    isTesting = false
                    appState.stopAudioMonitoring()
                } else {
                    isTesting = true
                    appState.startAudioMonitoring()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                    Text(isTesting ? "stop" : "test")
                        .font(.system(size: 11, weight: .medium, design: .default))
                }
                .foregroundStyle(isTesting ? Color(hex: "3FB950") : Color(hex: "71717A"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isTesting ? Color(hex: "3FB950").opacity(0.12) : Color(hex: "0F0F11"))
                        .overlay(
                            Capsule()
                                .strokeBorder(isTesting ? Color(hex: "3FB950").opacity(0.3) : Color(hex: "3F3F46").opacity(0.5), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .onChange(of: appState.captureMicrophone) { _, _ in
            if isTesting { appState.restartAudioMonitoring() }
        }
        .onChange(of: appState.captureSystemAudio) { _, _ in
            if isTesting { appState.restartAudioMonitoring() }
        }
        .onDisappear {
            if isTesting {
                isTesting = false
                appState.stopAudioMonitoring()
            }
        }
    }
}

// MARK: - Managed Status Inline (home screen top bar)

private struct ManagedStatusInline: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var isHovered = false

    private var accent: Color {
        if appState.shouldShowManagedSubscriptionPlaceholder { return Color(hex: "71717A") }
        guard let usage = appState.usageInfo else { return Color(hex: "3FB950") }
        if appState.isPro { return Color(hex: "A78BFA") }
        if usage.minutesRemaining < 15 { return Color(hex: "F85149") }
        if usage.minutesRemaining < 60 { return Color(hex: "F59E0B") }
        return Color(hex: "3FB950")
    }

    var body: some View {
        if appState.shouldShowManagedSubscriptionPlaceholder {
            Text("checking plan...")
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "52525B"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        } else if let usage = appState.usageInfo {
            Button {
                appState.selectedSettingsTab = "account"
                openSettings()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                    Text(appState.isPro ? "miniti pro" : "miniti free")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(isHovered ? ColorPalette.Text.secondary : ColorPalette.Text.dim)
                        .lineLimit(1)
                    Text("\(Int(usage.minutesUsed.rounded()))/\(Int(usage.minutesLimit))")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundStyle(isHovered ? accent : accent.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isHovered ? accent.opacity(0.1) : ColorPalette.Background.card.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isHovered ? accent.opacity(0.25) : ColorPalette.Border.primary, lineWidth: 0.5)
                        )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovered ? accent.opacity(0.06) : ColorPalette.Background.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            isHovered ? accent.opacity(0.3) : ColorPalette.Border.light,
                            lineWidth: isHovered ? 1 : 0.5
                        )
                )
                .shadow(
                    color: isHovered ? accent.opacity(0.15) : .clear,
                    radius: 8, x: 0, y: 2
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .fixedSize()
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
    }
}

struct AudioSourcePill: View {
    let label: String
    @Binding var isEnabled: Bool
    let color: Color
    
    @State private var isHovering = false
    
    var body: some View {
        Button {
            isEnabled.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isEnabled ? color.opacity(0.5) : Color(hex: "71717A"))
                    .frame(width: 6, height: 6)
                
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(isEnabled ? Color(hex: "D4D4D8") : Color(hex: "71717A"))
                    .lineLimit(1)

                Text(isEnabled ? "on" : "off")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(isEnabled ? color.opacity(0.8) : Color(hex: "71717A").opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(hex: "0F0F11"))
                    .overlay(
                        Capsule()
                            .stroke(
                                isEnabled
                                    ? color.opacity(isHovering ? 0.5 : 0.3)
                                    : Color(hex: "3F3F46").opacity(isHovering ? 0.8 : 0.5),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Update Available Banner

struct CalendarNudgeCard: View {
    @EnvironmentObject var appState: AppState
    @State private var isHovering = false
    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ColorPalette.Accent.green)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text("see your meetings here")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(ColorPalette.Text.primary)

                    Text("connect google calendar to see upcoming meetings, auto-start recording, and get attendee context in insights.")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    appState.dismissCalendarNudgeForever()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("dismiss permanently")
            }

            HStack(spacing: 10) {
                Button {
                    guard !isConnecting else { return }
                    isConnecting = true
                    appState.startCalendarConnectFromNudge()
                    // The browser-based OAuth returns to the app asynchronously;
                    // flip back after a short grace period so the button re-enables.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        isConnecting = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color(hex: "09090B"))
                        } else {
                            Image(systemName: "link")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(isConnecting ? "opening browser..." : "connect calendar")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                    }
                    .foregroundStyle(Color(hex: "09090B"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovering ? ColorPalette.Accent.green : ColorPalette.Accent.green.opacity(0.78))
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(isConnecting)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
                }

                Button {
                    appState.snoozeCalendarNudge()
                } label: {
                    Text("not now")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ColorPalette.Background.tertiary)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.leading, 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 480, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorPalette.Accent.green.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ColorPalette.Accent.green.opacity(0.22), lineWidth: 1)
                )
        )
    }
}

// MARK: - Investigation handoff

private struct InvestigationViewMac: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: MinitiDesignSystem.Spacing.standard) {
                Image(systemName: appState.activeInvestigationScope == .web ? "globe" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ColorPalette.Accent.blue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.hairline) {
                    Text(appState.activeInvestigationScope == .web ? "web investigation" : "codebase investigation")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(ColorPalette.Text.primary)
                    Text(appState.activeInvestigationFocus)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: MinitiDesignSystem.Spacing.standard)
                Button("Done") { appState.dismissInvestigation() }
            }
            .padding(MinitiDesignSystem.Spacing.section)

            Divider().background(ColorPalette.Border.primary)

            ScrollView {
                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
                    if let result = appState.investigationResult {
                        Text(LocalizedStringKey(result.answer))
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(ColorPalette.Text.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        if !result.sources.isEmpty {
                            investigationSection(title: "sources") {
                                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact) {
                                    ForEach(result.sources) { source in
                                        if let url = URL(string: source.url) {
                                            Link(destination: url) {
                                                Label(source.title, systemImage: "arrow.up.right.square")
                                                    .font(.system(size: 11, weight: .medium, design: .default))
                                                    .foregroundStyle(ColorPalette.Accent.blue)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if !result.referencedFiles.isEmpty {
                            investigationSection(title: "files reviewed") {
                                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.hairline) {
                                    ForEach(result.referencedFiles, id: \.self) { file in
                                        Text(file)
                                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                                            .foregroundStyle(ColorPalette.Text.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    } else if appState.isGeneratingInvestigation {
                        HStack(spacing: MinitiDesignSystem.Spacing.standard) {
                            ProgressView().controlSize(.small)
                            Text(appState.activeInvestigationScope == .web ? "researching with OpenAI…" : "reviewing code with OpenAI…")
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundStyle(ColorPalette.Text.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, MinitiDesignSystem.Spacing.section)
                    }

                    if let error = appState.investigationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(ColorPalette.Accent.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(MinitiDesignSystem.Spacing.section)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().background(ColorPalette.Border.primary)

            HStack {
                Text("runs only when you click investigate")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(ColorPalette.Text.dim)
                Spacer()
                Button("Run again") { appState.refreshInvestigation() }
                    .disabled(appState.isGeneratingInvestigation)
            }
            .padding(MinitiDesignSystem.Spacing.section)
        }
        .background(ColorPalette.Background.primary)
    }

    private func investigationSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(ColorPalette.Text.dim)
            content()
        }
    }
}

private struct InvestigationButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var isScopePickerPresented = false

    var body: some View {
        Button {
            isScopePickerPresented.toggle()
        } label: {
            MinitiControlLabel(role: .secondary) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 11)
                    Text("investigate")
                        .font(.system(size: 11, weight: .medium, design: .default))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ColorPalette.Text.meta)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .fixedSize()
        .disabled(!appState.canInvestigateCurrentConversation)
        .popover(isPresented: $isScopePickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
                Text("investigate")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(ColorPalette.Text.primary)

                investigationScopeButton(
                    title: "research the web",
                    detail: "current information with citations",
                    icon: "globe",
                    scope: .web
                )

                investigationScopeButton(
                    title: "investigate codebase",
                    detail: "selected local folder excerpts",
                    icon: "chevron.left.forwardslash.chevron.right",
                    scope: .codebase
                )
            }
            .padding(MinitiDesignSystem.Spacing.section)
            .frame(width: 280)
            .background(ColorPalette.Background.primary)
        }
        .help("Investigate recent meeting context")
        .accessibilityHint("Runs an OpenAI investigation using recent meeting context")
    }

    private func investigationScopeButton(
        title: String,
        detail: String,
        icon: String,
        scope: InvestigationScope
    ) -> some View {
        Button {
            isScopePickerPresented = false
            appState.triggerInvestigation(scope: scope)
        } label: {
            MinitiControlLabel(role: .secondary, height: 46) {
                HStack(spacing: MinitiDesignSystem.Spacing.standard) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.hairline) {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold, design: .default))
                        Text(detail)
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(ColorPalette.Text.dim)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Zoned Out button + popover

struct ZonedOutButton: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button {
            if appState.isZonedOutPresented {
                appState.dismissZonedOutCatchUp()
            } else {
                appState.triggerZonedOutCatchUp()
            }
        } label: {
            MinitiControlLabel(role: .secondary) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 11)
                    Text("zoned out")
                        .font(.system(size: 11, weight: .medium, design: .default))
                    Text("⌘⇧Z")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.meta)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!appState.canRequestZonedOutCatchUp && appState.zonedOutCatchUp == nil && !appState.isGeneratingCatchUp)
        .popover(
            isPresented: Binding(
                get: { appState.isZonedOutPresented },
                set: { newValue in
                    if newValue {
                        appState.isZonedOutPresented = true
                    } else {
                        // Funnel any popover dismissal (outside-click, Escape, etc.)
                        // through the cleanup path so in-flight requests are cancelled.
                        appState.dismissZonedOutCatchUp()
                    }
                }
            ),
            arrowEdge: .bottom
        ) {
            ZonedOutPopoverContent()
                .environmentObject(appState)
                .frame(width: 420, height: 460)
        }
    }
}

private struct ZonedOutPopoverContent: View {
    @EnvironmentObject var appState: AppState
    private let accent = MinitiDesignSystem.ContentAccent.zonedOut

    private var generatedLabel: String? {
        guard let date = appState.zonedOutCatchUpGeneratedAt else { return nil }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        return "\(minutes)m ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text("catch me up")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                if let label = generatedLabel {
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted)
                }
                Button {
                    appState.refreshZonedOutCatchUp()
                } label: {
                    HStack(spacing: 4) {
                        if appState.isGeneratingCatchUp {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(appState.isGeneratingCatchUp ? "thinking" : "refresh")
                            .font(.system(size: 10, weight: .medium, design: .default))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(appState.isGeneratingCatchUp)
            }

            Divider()
                .overlay(ColorPalette.Border.subtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let catchUp = appState.zonedOutCatchUp {
                        if !catchUp.currentTopic.isEmpty {
                            ZonedOutSection(title: "current topic", accent: accent) {
                                Text(catchUp.currentTopic)
                                    .font(.system(size: 12, design: .default))
                                    .foregroundStyle(ColorPalette.Text.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if !catchUp.questionsForYou.isEmpty {
                            ZonedOutSection(title: "questions for you", accent: Color(hex: "FFA657")) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(catchUp.questionsForYou, id: \.self) { q in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("?")
                                                .font(.system(size: 11, weight: .bold, design: .default))
                                                .foregroundStyle(Color(hex: "FFA657"))
                                            Text(q)
                                                .font(.system(size: 12, design: .default))
                                                .foregroundStyle(ColorPalette.Text.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }

                        if !catchUp.recentDiscussion.isEmpty {
                            ZonedOutSection(title: "recent discussion", accent: ColorPalette.Accent.blue) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(catchUp.recentDiscussion, id: \.self) { line in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("›")
                                                .font(.system(size: 11, weight: .semibold, design: .default))
                                                .foregroundStyle(ColorPalette.Text.muted)
                                            Text(line)
                                                .font(.system(size: 12, design: .default))
                                                .foregroundStyle(ColorPalette.Text.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }

                        if !catchUp.keyDecisions.isEmpty {
                            ZonedOutSection(title: "key decisions", accent: ColorPalette.Accent.green) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(catchUp.keyDecisions, id: \.self) { line in
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(ColorPalette.Accent.green)
                                                .padding(.top, 3)
                                            Text(line)
                                                .font(.system(size: 12, design: .default))
                                                .foregroundStyle(ColorPalette.Text.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                    } else if appState.isGeneratingCatchUp {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(accent)
                            Text("catching you up…")
                                .font(.system(size: 12, design: .default))
                                .foregroundStyle(ColorPalette.Text.muted)
                        }
                    }

                    if let err = appState.zonedOutCatchUpError {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ColorPalette.Accent.amber)
                            Text(err)
                                .font(.system(size: 11, design: .default))
                                .foregroundStyle(ColorPalette.Accent.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ColorPalette.Accent.amber.opacity(0.08))
                        )
                    }

                    Text("covers roughly the last 3 minutes of discussion")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.muted.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)
        }
        .padding(14)
        .background(ColorPalette.Background.panel)
    }
}

private struct ZonedOutSection<Content: View>: View {
    let title: String
    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(accent)
                .textCase(.lowercase)
            content()
        }
    }
}

#Preview {
    MeetingView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}


/// The mic pill opens a menu: the microphone on/off switch first, then which microphone
/// miniti records from (System default or a specific device). Clicking used to toggle
/// capture; the toggle is now the first menu item so a click can also pick the device.
struct MicrophoneSourcePill: View {
    @EnvironmentObject var appState: AppState
    @Binding var isEnabled: Bool
    let color: Color

    var body: some View {
        Menu {
            Toggle("Microphone on", isOn: $isEnabled)
            Divider()
            Section("Record from") {
                Picker("Record from", selection: $appState.preferredInputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(appState.availableInputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            if appState.isUsingFallbackInputDevice {
                Text("Chosen microphone not connected, using the system default")
            } else if let name = appState.activeInputDeviceName {
                Text("Using \(name)")
            }
        } label: {
            AudioSourcePillLabel(label: "mic", isEnabled: isEnabled, color: color)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .focusable(false)
        .onAppear { appState.audioCaptureService?.refreshInputDevices() }
        .help(appState.activeInputDeviceName.map { "Microphone: \($0). Click to switch it on or off, or pick another microphone." } ?? "Click to switch the microphone on or off, or pick which microphone to use.")
    }
}

/// The pill's face, shared by the plain toggle pill and the microphone menu pill.
struct AudioSourcePillLabel: View {
    let label: String
    let isEnabled: Bool
    let color: Color
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isEnabled ? color.opacity(0.5) : Color(hex: "71717A"))
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(isEnabled ? Color(hex: "D4D4D8") : Color(hex: "71717A"))
                .lineLimit(1)

            Text(isEnabled ? "on" : "off")
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(isEnabled ? color.opacity(0.8) : Color(hex: "71717A").opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(hex: "0F0F11"))
                .overlay(
                    Capsule()
                        .stroke(
                            isEnabled
                                ? color.opacity(isHovering ? 0.5 : 0.3)
                                : Color(hex: "3F3F46").opacity(isHovering ? 0.8 : 0.5),
                            lineWidth: 1
                        )
                )
        )
        .onHover { isHovering = $0 }
    }
}
