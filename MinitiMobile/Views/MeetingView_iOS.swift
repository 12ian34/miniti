import SwiftUI
import UIKit

struct MeetingView_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var meetingTitle: String = ""
    @State private var activeSection: MeetingSection = .transcript
    @State private var showDiscardConfirmation = false
    
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
    
    var body: some View {
        NavigationStack {
            Group {
                if appState.isRecording || (appState.currentMeeting != nil && !appState.isStartingMeeting) {
                    activeSessionView
                } else {
                    ReadyStateView_iOS()
                }
            }
            .background(ColorPalette.Background.primary)
        }
    }
    
    // MARK: - Active Session
    
    private var activeSessionView: some View {
        VStack(spacing: 0) {
            recordingHeader
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
        .alert("Discard recording?", isPresented: $showDiscardConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                appState.discardCurrentMeeting()
            }
        } message: {
            Text("This can't be undone.")
        }
        .onAppear {
            meetingTitle = appState.currentMeeting?.title ?? ""
        }
        .onChange(of: appState.currentMeeting?.title) { _, newTitle in
            if let newTitle, newTitle != meetingTitle {
                meetingTitle = newTitle
            }
        }
    }
    
    // MARK: - Recording Header
    
    private var recordingHeader: some View {
        let isStopped = !appState.isRecording
        
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 60, height: 1)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(isStopped ? ColorPalette.Text.disabled : Color(hex: "F85149"))
                        .frame(width: 8, height: 8)
                    
                    Text(appState.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(isStopped ? ColorPalette.Text.muted : ColorPalette.Text.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Button {
                        appState.goHome()
                    } label: {
                        Image(systemName: "house")
                            .font(.system(size: 14))
                            .foregroundStyle(ColorPalette.Text.muted)
                            .padding(6)
                    }
                    
                    Button {
                        copyToClipboard(appState.fullMeetingAsMarkdown())
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundStyle(ColorPalette.Text.muted)
                            .padding(6)
                    }
                }
                .frame(width: 60, alignment: .trailing)
                .opacity(isStopped ? 1 : 0)
                .allowsHitTesting(isStopped)
            }
            .padding(.horizontal, 12)
            
            SourceWaveform_iOS(
                level: appState.isRecording ? appState.microphoneLevel : 0,
                color: ColorPalette.Speaker.mic
            )
            .frame(height: 24)
            .opacity(appState.isRecording ? 1 : 0)
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(ColorPalette.Background.secondary)
    }
    
    // MARK: - Control Bar (bottom)
    
    private var controlBar: some View {
        let isStopped = appState.currentMeeting != nil && !appState.isRecording
        
        return ZStack {
            // Stop button (always laid out, visible when recording)
            stopButton
                .opacity(appState.isRecording ? 1 : 0)
                .allowsHitTesting(appState.isRecording)
            
            // Resume button (always laid out, visible when stopped)
            resumeButton
                .opacity(isStopped ? 1 : 0)
                .allowsHitTesting(isStopped)
            
            // Discard + save (always laid out, visible when stopped)
            HStack {
                terminalButton(icon: "trash", label: "discard", color: Color(hex: "F85149"), bgColor: Color(hex: "F85149").opacity(0.12), borderColor: Color(hex: "F85149").opacity(0.3)) {
                    showDiscardConfirmation = true
                }
                
                Spacer()
                
                terminalButton(icon: "checkmark", label: "save", color: Color(hex: "58A6FF"), bgColor: Color(hex: "58A6FF").opacity(0.12), borderColor: Color(hex: "58A6FF").opacity(0.3)) {
                    appState.goHome()
                }
            }
            .opacity(isStopped ? 1 : 0)
            .allowsHitTesting(isStopped)
        }
        .padding(.horizontal, 16)
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
    
    private var resumeButton: some View {
        Button {
            appState.startRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "record.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text("resume")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(Color(hex: "3FB950"))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "3FB950").opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "3FB950").opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func terminalButton(icon: String, label: String, color: Color, bgColor: Color, borderColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Live Insights Content
    
    private var liveInsightsContent: some View {
        ScrollView {
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
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }
}

// MARK: - Ready State (Home Screen)

struct ReadyStateView_iOS: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var isMicTesting = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Settings gear (top right)
            HStack {
                Spacer()
                NavigationLink(destination: SettingsView_iOS()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .padding(8)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Logo
            VStack(spacing: 12) {
                Text("⬢")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Accent.green)
                
                Text("miniti")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.primary)
            }
            
            // Mode status
            if appState.appMode == .managed {
                ManagedStatusPill()
            } else {
                BYOKStatusPills()
            }
            
            // Test mic button with waveform overlay above it
            VStack(spacing: 6) {
                // Waveform sits in a fixed-height slot that's always reserved
                ZStack {
                    if isMicTesting && appState.isMonitoring {
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(ColorPalette.Speaker.mic)
                                    .frame(width: 6, height: 6)
                                Text("mic")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(ColorPalette.Text.muted)
                            }
                            SourceWaveform_iOS(
                                level: appState.microphoneLevel,
                                color: ColorPalette.Speaker.mic
                            )
                            .frame(height: 20)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(height: 36)
                .padding(.horizontal, 40)
                
                Button {
                    if isMicTesting {
                        isMicTesting = false
                        appState.stopAudioMonitoring()
                    } else {
                        isMicTesting = true
                        appState.startAudioMonitoring()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isMicTesting ? "mic.fill" : "mic")
                            .font(.system(size: 12))
                        Text(isMicTesting ? "stop test" : "test mic")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(isMicTesting ? ColorPalette.Speaker.mic : ColorPalette.Text.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(isMicTesting ? ColorPalette.Speaker.mic.opacity(0.12) : ColorPalette.Background.secondary)
                            .overlay(
                                Capsule()
                                    .strokeBorder(isMicTesting ? ColorPalette.Speaker.mic.opacity(0.3) : ColorPalette.Border.subtle, lineWidth: 1)
                            )
                    )
                }
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
                VStack(spacing: 8) {
                    Text("Monthly limit reached")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColorPalette.Status.limitReached)
                    
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
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text("starting...")
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        } else {
                            Image(systemName: "record.circle")
                                .font(.system(size: 18))
                            Text("start")
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        }
                    }
                    .foregroundStyle(.white)
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
            
            Spacer()
        }
        .padding()
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
    }
}

// MARK: - Status Pills

struct ManagedStatusPill: View {
    @EnvironmentObject var appState: AppState
    
    private var accentColor: Color {
        guard let usage = appState.usageInfo else { return ColorPalette.Status.success }
        if usage.minutesRemaining < 15 { return ColorPalette.Status.limitReached }
        if usage.minutesRemaining < 60 { return ColorPalette.Status.warning }
        return ColorPalette.Status.success
    }
    
    var body: some View {
        if let usage = appState.usageInfo {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 5, height: 5)
                    
                    Text("miniti free")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                    
                    Text("•")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.disabled)
                    
                    Text("\(Int(usage.minutesRemaining.rounded())) min left")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(accentColor)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ColorPalette.Background.secondary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(accentColor.opacity(0.85))
                            .frame(width: max(2, geo.size.width * usage.usagePercentage))
                    }
                }
                .frame(width: 180, height: 6)
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
    
    var body: some View {
        Button {
            if let url = URL(string: "itms-beta://") {
                openURL(url)
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11))
                    Text("v\(versionInfo.latestVersion) available")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(ColorPalette.Accent.blue)
                
                Text("update via TestFlight")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(ColorPalette.Accent.blue.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ColorPalette.Accent.blue.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ColorPalette.Accent.blue.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Waveform

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
