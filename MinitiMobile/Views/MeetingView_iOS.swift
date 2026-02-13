import SwiftUI
import UIKit

struct MeetingView_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var meetingTitle: String = ""
    @State private var activeSection: MeetingSection = .transcript
    
    enum MeetingSection: String, CaseIterable {
        case transcript = "Transcript"
        case insights = "Insights"
        case notes = "Notes"
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if appState.currentMeeting == nil && !appState.isRecording {
                    ReadyStateView_iOS()
                } else {
                    activeSessionView
                }
            }
            .background(ColorPalette.Background.primary)
        }
    }
    
    // MARK: - Active Session
    
    private var activeSessionView: some View {
        VStack(spacing: 0) {
            // Recording header
            recordingHeader
            
            // Section picker
            sectionPicker
            
            // Content
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
        }
        .background(ColorPalette.Background.primary)
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
        VStack(spacing: 12) {
            // Status + timer (only when recording)
            if appState.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "F85149"))
                        .frame(width: 8, height: 8)
                    
                    Text(appState.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.secondary)
                }
            }
            
            // Waveform
            if appState.isRecording || appState.isMonitoring {
                SourceWaveform_iOS(
                    level: appState.microphoneLevel,
                    color: ColorPalette.Speaker.mic
                )
                .frame(height: 24)
                .padding(.horizontal)
            }
            
            // Control buttons — centered layout matching macOS terminal style
            HStack(spacing: 12) {
                // Home button (stopped state only)
                if appState.currentMeeting != nil && !appState.isRecording {
                    Button {
                        appState.goHome()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "house")
                                .font(.system(size: 11, weight: .semibold))
                            Text("home")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: "1C1C1F"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "30363D"), lineWidth: 1)
                        )
                    }
                }
                
                // Main record/stop/resume button — terminal style
                Button {
                    toggleRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: appState.isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text(recordButtonLabel)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(recordButtonColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(recordButtonColor.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(recordButtonColor.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Save button (stopped state only)
                if appState.currentMeeting != nil && !appState.isRecording {
                    Button {
                        appState.goHome()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                            Text("save")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(Color(hex: "58A6FF"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: "58A6FF").opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "58A6FF").opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                
                // Copy button
                if !appState.liveSegments.isEmpty && !appState.isRecording {
                    Button {
                        copyToClipboard(appState.fullMeetingAsMarkdown())
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundStyle(ColorPalette.Text.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: "1C1C1F"))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(hex: "30363D"), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .background(ColorPalette.Background.secondary)
    }
    
    private var recordButtonLabel: String {
        if appState.isRecording {
            return "stop"
        } else if appState.currentMeeting != nil {
            return "resume"
        } else {
            return "rec"
        }
    }
    
    private var recordButtonColor: Color {
        appState.isRecording ? Color(hex: "F85149") : Color(hex: "3FB950")
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
                // Mode selector
                HStack {
                    Text("Mode:")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                    
                    Picker("Insights Mode", selection: $appState.insightsMode) {
                        Text("Standard").tag(InsightsMode.standard)
                        Text("MEDDPICC").tag(InsightsMode.meddpicc)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                InsightsView()
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
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
    
    private func toggleRecording() {
        if appState.isRecording {
            appState.stopRecording()
        } else if appState.currentMeeting != nil {
            appState.startRecording()
        } else {
            appState.startNewMeeting()
        }
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }
}

// MARK: - Ready State (Home Screen)

struct ReadyStateView_iOS: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 24) {
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
            
            // Mic waveform (monitoring)
            if appState.isMonitoring {
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
                .padding(.horizontal, 40)
            }
            
            // Update available banner
            if let update = appState.availableUpdate {
                UpdateAvailableBanner_iOS(versionInfo: update)
            }
            
            // Start button
            if appState.isLimitReached {
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
                    appState.startNewMeeting()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 18))
                        Text("start")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(appState.canStartRecording
                                  ? ColorPalette.Accent.green
                                  : ColorPalette.Text.disabled)
                    )
                }
                .disabled(!appState.canStartRecording)
            }
            
            Spacer()
        }
        .padding()
        .onAppear { appState.startAudioMonitoring() }
        .onDisappear { appState.stopAudioMonitoring() }
    }
}

// MARK: - Status Pills

struct ManagedStatusPill: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if let usage = appState.usageInfo {
            HStack(spacing: 6) {
                Circle()
                    .fill(usage.minutesRemaining > 60 ? ColorPalette.Status.success : ColorPalette.Status.warning)
                    .frame(width: 6, height: 6)
                Text("\(Int(usage.minutesRemaining.rounded())) min left")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
            if let url = URL(string: versionInfo.downloadUrl) {
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
                
                if let notes = versionInfo.releaseNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(ColorPalette.Accent.blue.opacity(0.7))
                        .lineLimit(1)
                }
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
