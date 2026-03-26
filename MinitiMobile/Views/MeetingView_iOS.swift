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
            var md = "# \(appState.currentMeeting?.title ?? "Meeting") — Insights\n\n"
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
                ShareLink(item: shareContent) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ColorPalette.Text.muted)
                }
            }
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
                }
            }

            // Single spacer below main block — training pins near bottom
            Spacer()

            // Training stats near bottom
            TrainingStatsOverview(meetings: meetings)
                .padding(.bottom, 24)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11))
                Text("v\(versionInfo.latestVersion) available")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                
                if releaseNotes != nil {
                    Button(isShowingFullNotes ? "hide" : "notes") {
                        isShowingFullNotes.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Accent.blue.opacity(0.85))
                }
            }
            .foregroundStyle(ColorPalette.Accent.blue)
            
            if let notes = releaseNotes {
                Text(notes)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(ColorPalette.Accent.blue.opacity(0.7))
                    .lineLimit(isShowingFullNotes ? nil : 1)
                    .fixedSize(horizontal: false, vertical: isShowingFullNotes)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isShowingFullNotes {
                            isShowingFullNotes = true
                        }
                    }
            }
            
            Button {
                if let url = updateURL {
                    openURL(url)
                }
            } label: {
                Text("update")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(ColorPalette.Accent.blue.opacity(0.8))
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorPalette.Accent.blue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ColorPalette.Accent.blue.opacity(0.2), lineWidth: 1)
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
