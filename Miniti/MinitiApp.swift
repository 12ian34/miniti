import SwiftUI
import SwiftData
import AppKit

@main
struct MinitiApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var keyboardService = KeyboardShortcutsService.shared
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Meeting.self,
            TranscriptSegment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if appState.hasCompletedOnboarding {
                    MainWindow()
                        .environmentObject(keyboardService)
                        .onAppear {
                            setupKeyboardShortcuts()
                        }
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(appState)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Meeting") {
                    appState.startNewMeeting()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Divider()
                
                Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                    toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                
                Button("Generate Insights") {
                    generateInsights()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(appState.currentMeeting == nil || appState.liveSegments.isEmpty)
            }
            
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        
        // Menu Bar
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarIcon(isRecording: appState.isRecording)
        }
    }
    
    private func setupKeyboardShortcuts() {
        keyboardService.onToggleRecording = { [weak appState] in
            guard let appState else { return }
            toggleRecording(appState: appState)
        }
        
        keyboardService.onGenerateInsights = { [weak appState] in
            guard let appState else { return }
            Task { @MainActor in
                await appState.generateInsights()
            }
        }
        
        keyboardService.onNewSession = { [weak appState] in
            guard let appState else { return }
            appState.createNewSession()
        }
        
        keyboardService.onGoHome = { [weak appState] in
            guard let appState else { return }
            if !appState.isRecording {
                appState.goHome()
            }
        }
        
        keyboardService.onStandardMode = { [weak appState] in
            guard let appState else { return }
            appState.switchInsightsMode(to: .standard)
        }
        
        keyboardService.onMeddpiccMode = { [weak appState] in
            guard let appState else { return }
            appState.switchInsightsMode(to: .meddpicc)
        }
        
        keyboardService.onTrainingMode = { [weak appState] in
            guard let appState else { return }
            appState.switchInsightsMode(to: .training)
        }
        
        keyboardService.startMonitoring()
    }
    
    private func toggleRecording() {
        toggleRecording(appState: appState)
    }
    
    private func toggleRecording(appState: AppState) {
        if appState.isRecording {
            appState.stopRecording()
        } else if appState.currentMeeting != nil {
            // Resume recording on the current session
            appState.startRecording()
        } else {
            appState.startNewMeeting()
        }
    }
    
    private func generateInsights() {
        Task { @MainActor in
            await appState.generateInsights()
        }
    }
}

// MARK: - Menu Bar Icon

struct MenuBarIcon: View {
    let isRecording: Bool
    @State private var isPulsing: Bool = false
    
    var body: some View {
        Group {
            if isRecording {
                // Recording: red pill with pulsing dot and REC text
                HStack(spacing: 4) {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                        .opacity(isPulsing ? 1.0 : 0.5)
                    
                    Text("REC")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(.red)
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
                .onDisappear {
                    isPulsing = false
                }
            } else {
                // Idle: hexagon icon
                Text("⬢")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status section
            if appState.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Recording")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(formatDuration(appState.recordingDuration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.1))
                
                Divider()
            }
            
            // Current meeting info
            if let meeting = appState.currentMeeting {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text("\(appState.liveSegments.filter { $0.isFinal }.count) segments")
                        if !appState.liveSummary.isEmpty {
                            Text("•")
                            Text("insights ready")
                                .foregroundStyle(.green)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                Divider()
            }
            
            // Actions
            Button {
                if appState.isRecording {
                    appState.stopRecording()
                } else if appState.currentMeeting != nil {
                    // Resume recording on the current session
                    appState.startRecording()
                } else {
                    appState.startNewMeeting()
                }
            } label: {
                Label(
                    appState.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: appState.isRecording ? "stop.fill" : "record.circle"
                )
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            
            if appState.currentMeeting != nil && !appState.liveSegments.isEmpty {
                Button {
                    Task { @MainActor in
                        await appState.generateInsights()
                    }
                } label: {
                    Label("Generate Insights", systemImage: "sparkles")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            
            Divider()
            
            Button {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title.isEmpty || $0.title == "miniti" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open Miniti", systemImage: "macwindow")
            }
            .keyboardShortcut("o", modifiers: .command)
            
            Divider()
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .frame(width: 220)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
