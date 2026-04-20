import SwiftUI
import SwiftData
import UIKit

struct MeetingView_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var meetingTitle: String = ""
    @State private var activeSection: MeetingSection = .transcript
    @State private var showDiscardConfirmation = false
    @State private var isResumingRecording = false
    @State private var showSavedOverlay = false
    
    enum MeetingSection: String, CaseIterable {
        case transcript = "transcript"
        case insights = "insights"
        case notes = "notes"
    }
    
    private var canUpdateInsights: Bool {
        appState.currentMeeting != nil && !appState.liveSegments.isEmpty
    }
    
    private var showsLiveInsightsUpdateButton: Bool {
        appState.insightsMode != .training
    }

    private var isStopped: Bool {
        appState.currentMeeting != nil && !appState.isRecording
    }

    private var isResumePending: Bool {
        isStopped && isResumingRecording
    }

    private var shareContent: String {
        switch activeSection {
        case .transcript:
            return appState.transcriptAsMarkdown()
        case .insights:
            var md = "# \(appState.currentMeeting?.displayTitle ?? "Meeting") — Insights\n\n"
            if !appState.liveSummary.isEmpty { md += "## Summary\n\n\(appState.liveSummary)\n\n" }
            if !appState.liveDiscussionFlow.isEmpty {
                md += "## Discussion Flow\n\n"
                for (i, item) in appState.liveDiscussionFlow.enumerated() { md += "\(i+1). \(item)\n" }
                md += "\n"
            }
            if !appState.liveActionItems.isEmpty {
                md += "## Action Items\n\n"
                for item in appState.liveActionItems { md += "- [ ] \(item)\n" }
                md += "\n"
            }
            if !appState.liveTopics.isEmpty {
                md += "## Topics\n\n"
                for topic in appState.liveTopics { md += "- \(topic)\n" }
                md += "\n"
            }
            let meddpiccFields: [(String, String?)] = [
                ("Metrics", appState.liveMetrics), ("Economic Buyer", appState.liveEconomicBuyer),
                ("Decision Criteria", appState.liveDecisionCriteria), ("Decision Process", appState.liveDecisionProcess),
                ("Paper Process", appState.livePaperProcess), ("Identified Pain", appState.liveIdentifiedPain),
                ("Champion", appState.liveChampion), ("Competition", appState.liveCompetition)
            ]
            if meddpiccFields.contains(where: { $0.1 != nil && !($0.1?.isEmpty ?? true) }) {
                md += "## MEDDPICC\n\n"
                for (label, value) in meddpiccFields {
                    if let value, !value.isEmpty { md += "**\(label):** \(value)\n\n" }
                }
            }
            if !appState.liveNotes.isEmpty { md += "## Notes\n\n\(appState.liveNotes)\n" }
            return md.trimmingCharacters(in: .whitespacesAndNewlines)
        case .notes:
            return appState.liveNotes.isEmpty ? "(no notes)" : appState.liveNotes
        }
    }
    
    private var recoveryAccent: Color {
        switch appState.audioRecoveryState {
        case .healthy:
            return ColorPalette.Accent.green
        case .recovering:
            return Color(hex: "D29922")
        case .degraded:
            return Color(hex: "F85149")
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if appState.isRecording || (appState.currentMeeting != nil && !appState.isStartingMeeting) {
                    activeSessionView
                } else {
                    ReadyStateView_iOS()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ColorPalette.Background.primary)
        }
    }
    
    // MARK: - Active Session
    
    private var activeSessionView: some View {
        VStack(spacing: 0) {
            if appState.audioRecoveryState != .healthy {
                HStack(spacing: 8) {
                    Circle()
                        .fill(recoveryAccent)
                        .frame(width: 6, height: 6)
                    Text(appState.audioRecoveryState.label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(recoveryAccent)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 4).fill(recoveryAccent.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(recoveryAccent.opacity(0.24), lineWidth: 1))
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }

            sectionPicker

            Group {
                switch activeSection {
                case .transcript:
                    TranscriptView()
                case .insights:
                    liveInsightsContent
                case .notes:
                    notesEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.wasAutoStopped && isStopped {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("auto-stopped — no speech detected")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            controlBar
        }
        .background(ColorPalette.Background.primary)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ColorPalette.Background.secondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isStopped ? ColorPalette.Text.disabled : Color(hex: "F85149"))
                        .frame(width: 8, height: 8)
                    Text(appState.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(isStopped ? ColorPalette.Text.muted : ColorPalette.Text.secondary)
                    if appState.isRecording {
                        CompactWaveform_iOS(level: appState.audioLevels.microphoneLevel, color: ColorPalette.Speaker.mic)
                            .frame(width: 24, height: 18)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if appState.isRecording {
                        Button {
                            appState.triggerZonedOutCatchUp()
                        } label: {
                            Text("😶")
                                .font(.system(size: 18))
                                .accessibilityLabel("catch me up")
                        }
                        .disabled(!appState.canRequestZonedOutCatchUp && appState.zonedOutCatchUp == nil && !appState.isGeneratingCatchUp)
                    }
                    ShareLink(item: shareContent) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ColorPalette.Text.muted)
                    }
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { appState.isZonedOutPresented },
                set: { newValue in
                    if newValue {
                        appState.isZonedOutPresented = true
                    } else {
                        // Funnel swipe-down dismissal through the cleanup path so
                        // in-flight requests are cancelled, not orphaned.
                        appState.dismissZonedOutCatchUp()
                    }
                }
            )
        ) {
            ZonedOutSheet_iOS()
                .environmentObject(appState)
        }
        .overlay {
            if showSavedOverlay {
                Text("saved")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Accent.green)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ColorPalette.Background.secondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(ColorPalette.Accent.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .alert("Discard recording?", isPresented: $showDiscardConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                appState.discardCurrentMeeting()
            }
        } message: {
            Text("This can't be undone.")
        }
        .onAppear {
            showSavedOverlay = false
            meetingTitle = appState.currentMeeting?.title ?? ""
        }
        .onChange(of: appState.currentMeeting?.title) { _, newTitle in
            if let newTitle, newTitle != meetingTitle {
                meetingTitle = newTitle
            }
        }
        .onChange(of: appState.isRecording) { _, isRecording in
            if isRecording { isResumingRecording = false }
        }
        .onChange(of: appState.managedSessionError) { _, error in
            if error != nil { isResumingRecording = false }
        }
        .onChange(of: appState.currentMeeting == nil) { _, noMeeting in
            if noMeeting { isResumingRecording = false }
        }
    }
    
    // MARK: - Control Bar (bottom)
    
    private var controlBar: some View {
        Group {
            if isStopped {
                // Stopped: discard | resume | save — equal width, no overlap
                HStack(spacing: 8) {
                    flexButton(icon: "trash", label: "discard", color: Color(hex: "F85149"), bgColor: Color(hex: "F85149").opacity(0.12), borderColor: Color(hex: "F85149").opacity(0.3)) {
                        showDiscardConfirmation = true
                    }

                    flexResumeButton

                    flexButton(icon: "checkmark", label: "save", color: Color(hex: "58A6FF"), bgColor: Color(hex: "58A6FF").opacity(0.12), borderColor: Color(hex: "58A6FF").opacity(0.3)) {
                        withAnimation(.easeIn(duration: 0.2)) {
                            showSavedOverlay = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            appState.goHome()
                        }
                    }
                }
            } else {
                // Recording: centered stop button
                stopButton
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(ColorPalette.Background.secondary)
    }
    
    private var stopButton: some View {
        Button {
            appState.stopRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("stop")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(Color(hex: "F85149"))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(width: 128)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "F85149").opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "F85149").opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private var flexResumeButton: some View {
        Button {
            guard !isResumePending else { return }
            isResumingRecording = true
            appState.managedSessionError = nil
            appState.startRecording()
        } label: {
            HStack(spacing: 6) {
                if isResumePending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(hex: "3FB950"))
                } else {
                    Image(systemName: "record.circle")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isResumePending ? "starting..." : "start")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundStyle(Color(hex: "3FB950"))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "3FB950").opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "3FB950").opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(isResumePending)
    }

    private func flexButton(icon: String, label: String, color: Color, bgColor: Color, borderColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(color)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Section Picker
    
    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(MeetingSection.allCases, id: \.self) { section in
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
        .frame(maxWidth: 500)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Live Insights Content
    
    private var liveInsightsContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                insightsModePicker
                
                if showsLiveInsightsUpdateButton {
                    HStack(spacing: 8) {
                        Button {
                            Task { @MainActor in
                                await appState.generateInsights()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("update")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
                        .disabled(!canUpdateInsights || appState.isGeneratingInsights)
                        .opacity((!canUpdateInsights || appState.isGeneratingInsights) ? 0.5 : 1)

                        if appState.isGeneratingInsights {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("updating...")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: "8B949E"))
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                }
                
                InsightsView()
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    
    private var insightsModePicker: some View {
        HStack(spacing: 0) {
            ForEach(InsightsMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.switchInsightsMode(to: mode)
                    }
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 12, weight: appState.insightsMode == mode ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(appState.insightsMode == mode ? ColorPalette.Text.primary : ColorPalette.Text.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            appState.insightsMode == mode
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
        .frame(maxWidth: 500)
        .padding(.horizontal)
    }

    // MARK: - Notes Editor
    
    private var notesEditor: some View {
        VStack(spacing: 0) {
            TextEditor(text: $appState.liveNotes)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(ColorPalette.Background.primary)
                .padding()
        }
    }
    
    // MARK: - Actions
    
}

// MARK: - Ready State (Home Screen)

struct ReadyStateView_iOS: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Meeting.startTime, order: .reverse) private var meetings: [Meeting]
    @State private var isMicTesting = false
    @State private var isPurchasingPro = false
    @State private var subscriptionMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            if isMicTesting && appState.isMonitoring {
                ObservedSourceWaveform_iOS(
                    audioLevels: appState.audioLevels,
                    source: .microphone,
                    color: ColorPalette.Speaker.mic
                )
                .frame(height: 16)
                .padding(.horizontal, 40)
                .padding(.top, 4)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isMicTesting && appState.isMonitoring)
            }

            // Two spacers push the main block lower (2/3 of free space above)
            Spacer()
            Spacer()

            // Logo + tagline + start button grouped together
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Text("⬢")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(ColorPalette.Accent.green)

                    Text("miniti")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.primary)

                    FlashingTagline_iOS(
                        text: "multi-dimensional meetings",
                        isIdle: !(isMicTesting && appState.isMonitoring)
                    )
                }

                if appState.appMode == .byok {
                    BYOKStatusPills()
                }

                // Update available banner
                if let update = appState.availableUpdate {
                    UpdateAvailableBanner_iOS(versionInfo: update)
                }

                // Auto-start banner
                if let event = appState.pendingAutoStartEvent {
                    AutoStartBanner_iOS(event: event, countdown: appState.autoStartCountdown)
                }

                // Start button or blocked state
                if appState.isDeviceDisabled {
                    VStack(spacing: 8) {
                        Text("account disabled")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(ColorPalette.Status.limitReached)

                        Text("contact support for help")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(ColorPalette.Text.muted)
                    }
                } else if appState.isLimitReached {
                    VStack(spacing: 10) {
                        Text("Monthly limit reached")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(ColorPalette.Status.limitReached)

                        Button {
                            guard !isPurchasingPro else { return }
                            isPurchasingPro = true
                            subscriptionMessage = nil
                            Task {
                                let success = await appState.purchaseProSubscription()
                                isPurchasingPro = false
                                if success {
                                    subscriptionMessage = "Pro subscription is now active."
                                } else {
                                    subscriptionMessage = appState.storeKitService?.purchaseErrorMessage ?? "Purchase not completed."
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isPurchasingPro {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                    Text("purchasing...")
                                } else {
                                    Text("Upgrade to Pro — $4.99/month")
                                }
                            }
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(ColorPalette.Accent.purple))
                        }
                        .disabled(isPurchasingPro)

                        VStack(spacing: 4) {
                            Text("Miniti Pro Monthly · $4.99/month · auto-renewable")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(ColorPalette.Text.muted)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 8) {
                                Link("Terms", destination: URL(string: "https://miniti.app/terms")!)
                                Text("•").foregroundStyle(ColorPalette.Text.disabled)
                                Link("Privacy", destination: URL(string: "https://miniti.app/privacy")!)
                            }
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }

                        if let subscriptionMessage {
                            Text(subscriptionMessage)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(ColorPalette.Text.muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        Button("Switch to BYOK") {
                            appState.appMode = .byok
                        }
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ColorPalette.Accent.blue)
                    }
                } else {
                    Button {
                        if !appState.isStartingMeeting {
                            appState.startNewMeeting()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if appState.isStartingMeeting {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(0.8)
                                Text("starting...")
                                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                            } else {
                                Image(systemName: "record.circle")
                                    .font(.system(size: 18))
                                Text("start")
                                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            }
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(appState.isStartingMeeting
                                      ? ColorPalette.Text.muted
                                      : appState.canStartRecording
                                          ? ColorPalette.Accent.green
                                          : ColorPalette.Text.disabled)
                        )
                    }
                    .disabled(!appState.canStartRecording || appState.isStartingMeeting)

                    MeetingLanguagePicker_iOS(language: $appState.meetingLanguage)
                }

                // Upcoming calendar events
                if appState.pendingAutoStartEvent == nil,
                   appState.googleCalendarEnabled,
                   appState.isGoogleCalendarConnected,
                   !appState.todayEvents.isEmpty {
                    UpcomingEventsPanel_iOS()
                        .frame(maxWidth: 380)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onDisappear {
            if isMicTesting {
                isMicTesting = false
                appState.stopAudioMonitoring()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, isMicTesting, !appState.isMonitoring {
                appState.startAudioMonitoring()
            } else if newPhase == .background, appState.isMonitoring {
                appState.stopAudioMonitoring()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if isMicTesting {
                        isMicTesting = false
                        appState.stopAudioMonitoring()
                    } else {
                        isMicTesting = true
                        appState.startAudioMonitoring()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isMicTesting ? "mic.fill" : "mic")
                            .font(.system(size: 12))
                        Text(isMicTesting ? "stop" : "test")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(isMicTesting ? ColorPalette.Speaker.mic : ColorPalette.Text.muted)
                }
            }
            ToolbarItem(placement: .principal) {
                if appState.appMode == .managed {
                    ManagedStatusInline_iOS()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView_iOS()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ColorPalette.Text.muted)
                }
            }
        }
    }
}

private struct FlashingTagline_iOS: View {
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
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(ColorPalette.Text.muted)
            .tracking(2)
    }
    
    private func highlightedText(motion: FlashMotion_iOS) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(ColorPalette.Accent.green)
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
    
    private func flashMotion(at time: TimeInterval) -> FlashMotion_iOS {
        let t = time * 0.9
        let primaryCenter = clamp01(0.5 + (0.36 * sin(t * 1.4)) + (0.12 * sin((t * 3.1) + 0.8)))
        let secondaryCenter = clamp01(0.5 + (0.41 * sin((t * 1.95) + 1.9)) + (0.08 * sin((t * 5.3) + 0.3)))
        let primaryWidth = CGFloat(0.18 + (0.22 * (0.5 + (0.5 * sin((t * 2.45) + 0.4)))))
        let secondaryWidth = CGFloat(0.09 + (0.14 * (0.5 + (0.5 * sin((t * 3.8) + 2.0)))))
        let spark = CGFloat(0.5 + (0.5 * sin((t * 6.7) + (0.5 * sin(t * 2.2)))))
        
        return FlashMotion_iOS(
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

private struct FlashMotion_iOS {
    let primaryCenter: CGFloat
    let secondaryCenter: CGFloat
    let primaryWidth: CGFloat
    let secondaryWidth: CGFloat
    let spark: CGFloat
}

// MARK: - Status Pills

struct ManagedStatusPill: View {
    @EnvironmentObject var appState: AppState
    
    private var accentColor: Color {
        guard appState.usageInfo != nil else { return appState.isPro ? ColorPalette.Accent.purple : ColorPalette.Status.success }
        if appState.isPro { return ColorPalette.Accent.purple }
        if appState.displayMinutesRemaining < 15 { return ColorPalette.Status.limitReached }
        if appState.displayMinutesRemaining < 60 { return ColorPalette.Status.warning }
        return ColorPalette.Status.success
    }
    
    var body: some View {
        if appState.usageInfo != nil {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 5, height: 5)
                    
                    Text(appState.isPro ? "miniti pro" : "miniti free")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                    
                    Text("•")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.disabled)
                    
                    Text("\(Int(appState.displayMinutesRemaining.rounded())) min left")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(accentColor)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ColorPalette.Background.secondary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(accentColor.opacity(0.85))
                            .frame(width: max(2, geo.size.width * appState.displayUsagePercentage))
                    }
                }
                .frame(width: 180, height: 6)
            }
        }
    }
}

private struct ManagedStatusInline_iOS: View {
    @EnvironmentObject var appState: AppState

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
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "52525B"))
        } else if let usage = appState.usageInfo {
            HStack(spacing: 6) {
                Text(appState.isPro ? "miniti pro" : "miniti free")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "52525B"))
                Text("\(Int(usage.minutesUsed.rounded()))/\(Int(appState.displayMinutesLimit)) min")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
            }
        }
    }
}

struct BYOKStatusPills: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 8) {
            StatusPill(
                label: "deepgram",
                isSet: !appState.deepgramApiKey.isEmpty
            )
            StatusPill(
                label: "openai",
                isSet: !appState.openaiApiKey.isEmpty
            )
        }
    }
}

struct StatusPill: View {
    let label: String
    let isSet: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isSet ? ColorPalette.Status.success : ColorPalette.Status.noApiKey)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(ColorPalette.Background.secondary)
                .overlay(
                    Capsule()
                        .strokeBorder(ColorPalette.Border.subtle, lineWidth: 1)
                )
        )
    }
}

// MARK: - Update Available Banner (iOS)

struct UpdateAvailableBanner_iOS: View {
    let versionInfo: MinitiAPIService.VersionInfo
    @Environment(\.openURL) private var openURL
    @State private var isShowingFullNotes = false
    
    private var updateURL: URL? {
        URL(string: versionInfo.downloadUrl)
    }
    
    private var releaseNotes: String? {
        guard let notes = versionInfo.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty else { return nil }
        return notes
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14))
                Text("v\(versionInfo.latestVersion) available")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                
                Spacer()
                
                Button {
                    if let url = updateURL {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 10, weight: .semibold))
                        Text("update")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(ColorPalette.Accent.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ColorPalette.Accent.blue.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(ColorPalette.Accent.blue)
            
            if releaseNotes != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingFullNotes.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(isShowingFullNotes ? 90 : 0))
                        Text(isShowingFullNotes ? "hide release notes" : "show release notes")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(ColorPalette.Accent.blue.opacity(0.7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            if let notes = releaseNotes, isShowingFullNotes {
                Text(notes)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(ColorPalette.Accent.blue.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 13)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorPalette.Accent.blue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ColorPalette.Accent.blue.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Waveform

private enum AudioWaveformSource_iOS {
    case microphone
    case system
}

private struct ObservedSourceWaveform_iOS: View {
    @ObservedObject var audioLevels: AudioLevelsState
    let source: AudioWaveformSource_iOS
    let zeroWhenNotRecording: Bool
    let color: Color

    init(
        audioLevels: AudioLevelsState,
        source: AudioWaveformSource_iOS,
        zeroWhenNotRecording: Bool = false,
        color: Color
    ) {
        self.audioLevels = audioLevels
        self.source = source
        self.zeroWhenNotRecording = zeroWhenNotRecording
        self.color = color
    }

    private var level: Float {
        if zeroWhenNotRecording {
            return 0
        }
        switch source {
        case .microphone:
            return audioLevels.microphoneLevel
        case .system:
            return audioLevels.systemAudioLevel
        }
    }

    var body: some View {
        SourceWaveform_iOS(level: level, color: color)
    }
}

struct SourceWaveform_iOS: View {
    let level: Float
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let normalized = CGFloat(pow(level, 0.2))
            let barWidth = max(normalized * geo.size.width, 2)

            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.6))
                .frame(width: barWidth, height: geo.size.height)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.linear(duration: 0.05), value: level)
        }
    }
}

struct CompactWaveform_iOS: View {
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

    let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

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
            withAnimation(.linear(duration: 0.04)) {
                let rawLevel = CGFloat(max(level, 0))
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

// MARK: - Language Picker (iOS)

struct MeetingLanguagePicker_iOS: View {
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
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(selectedLang.displayName)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(ColorPalette.Text.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(ColorPalette.Background.secondary)
            )
            .overlay(
                Capsule()
                    .stroke(ColorPalette.Border.primary, lineWidth: 1)
            )
        }
    }
}

// MARK: - Google Calendar UI

private struct AutoStartBanner_iOS: View {
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
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.primary)
                    .lineLimit(1)
            }

            Text("starting in \(countdown)s")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ColorPalette.Accent.green)

            HStack(spacing: 12) {
                Button {
                    appState.startMeetingFromEvent(event)
                } label: {
                    Text("start now")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ColorPalette.Accent.green)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    appState.dismissAutoStart()
                } label: {
                    Text("dismiss")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ColorPalette.Background.tertiary)
                        )
                }
                .buttonStyle(.plain)
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

private struct UpcomingEventsPanel_iOS: View {
    @EnvironmentObject var appState: AppState

    private var displayEvents: [MinitiAPIService.CalendarEvent] {
        Array(appState.todayEvents.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("today")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.dim)
                .padding(.horizontal, 8)

            VStack(spacing: 2) {
                ForEach(displayEvents) { event in
                    Button {
                        appState.startMeetingFromEvent(event)
                    } label: {
                        CompactEventRow_iOS(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CompactEventRow_iOS: View {
    let event: MinitiAPIService.CalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            Text(formattedTime)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(isActive ? ColorPalette.Accent.green : ColorPalette.Text.muted)
                .frame(width: 44, alignment: .leading)

            Text(event.title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ColorPalette.Text.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if !event.attendees.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 8))
                    let ext = event.externalAttendees.count
                    Text("\(ext > 0 ? ext : event.attendees.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(ColorPalette.Text.dim)
            }

            Image(systemName: "record.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ColorPalette.Accent.green.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(ColorPalette.Background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? ColorPalette.Accent.green.opacity(0.3) : ColorPalette.Border.primary, lineWidth: 1)
        )
    }

    private var isActive: Bool {
        guard let start = event.startDate, let end = event.endDate else { return false }
        let now = Date()
        return now >= start && now <= end
    }

    private var formattedTime: String {
        guard let start = event.startDate else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: start)
    }
}

// MARK: - Zoned Out sheet (iOS)

struct ZonedOutSheet_iOS: View {
    @EnvironmentObject var appState: AppState
    private let accent = Color(hex: "D2A8FF")

    private var generatedLabel: String? {
        guard let date = appState.zonedOutCatchUpGeneratedAt else { return nil }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        return "\(minutes)m ago"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ColorPalette.Background.primary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Text("😶")
                                .font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("catch me up")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(accent)
                                Text("covers the last ~3 minutes")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(ColorPalette.Text.muted)
                            }
                            Spacer(minLength: 0)
                            if let label = generatedLabel {
                                Text(label)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(ColorPalette.Text.muted)
                            }
                        }

                        if let catchUp = appState.zonedOutCatchUp {
                            if !catchUp.currentTopic.isEmpty {
                                ZonedOutSection_iOS(title: "current topic", accent: accent) {
                                    Text(catchUp.currentTopic)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(ColorPalette.Text.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            if !catchUp.questionsForYou.isEmpty {
                                ZonedOutSection_iOS(title: "questions for you", accent: Color(hex: "FFA657")) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(catchUp.questionsForYou, id: \.self) { q in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("?")
                                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(Color(hex: "FFA657"))
                                                Text(q)
                                                    .font(.system(size: 13, design: .monospaced))
                                                    .foregroundStyle(ColorPalette.Text.primary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                }
                            }

                            if !catchUp.recentDiscussion.isEmpty {
                                ZonedOutSection_iOS(title: "recent discussion", accent: ColorPalette.Accent.blue) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(catchUp.recentDiscussion, id: \.self) { line in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("›")
                                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                    .foregroundStyle(ColorPalette.Text.muted)
                                                Text(line)
                                                    .font(.system(size: 13, design: .monospaced))
                                                    .foregroundStyle(ColorPalette.Text.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                }
                            }

                            if !catchUp.keyDecisions.isEmpty {
                                ZonedOutSection_iOS(title: "key decisions", accent: ColorPalette.Accent.green) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(catchUp.keyDecisions, id: \.self) { line in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(ColorPalette.Accent.green)
                                                    .padding(.top, 3)
                                                Text(line)
                                                    .font(.system(size: 13, design: .monospaced))
                                                    .foregroundStyle(ColorPalette.Text.primary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                }
                            }
                        } else if appState.isGeneratingCatchUp {
                            HStack(spacing: 10) {
                                ProgressView().tint(accent)
                                Text("catching you up…")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(ColorPalette.Text.muted)
                            }
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let err = appState.zonedOutCatchUpError {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ColorPalette.Accent.amber)
                                Text(err)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(ColorPalette.Accent.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(ColorPalette.Accent.amber.opacity(0.08))
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.dismissZonedOutCatchUp()
                    } label: {
                        Text("done")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ColorPalette.Text.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.refreshZonedOutCatchUp()
                    } label: {
                        HStack(spacing: 4) {
                            if appState.isGeneratingCatchUp {
                                ProgressView().controlSize(.mini).tint(accent)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text(appState.isGeneratingCatchUp ? "thinking" : "refresh")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(accent)
                    }
                    .disabled(appState.isGeneratingCatchUp)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ZonedOutSection_iOS<Content: View>: View {
    let title: String
    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorPalette.Background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
    }
}
