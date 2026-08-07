import SwiftUI
import SwiftData
import AppKit

extension Notification.Name {
    static let minitiAttioOAuthCallback = Notification.Name("minitiAttioOAuthCallback")
    static let minitiGoogleOAuthCallback = Notification.Name("minitiGoogleOAuthCallback")
    /// Posted after meetings are inserted outside the main window's own flows
    /// (e.g. Granola CSV import in Settings) so the history sidebar refreshes.
    static let minitiMeetingsImported = Notification.Name("minitiMeetingsImported")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private var isTerminationReplyPending = false
    private var terminationTimeoutTask: Task<Void, Never>?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let scheme = url.scheme?.lowercased() ?? ""
            guard scheme == "miniti-google" || scheme == "miniti-attio" else { continue }
            let notificationName: Notification.Name = scheme == "miniti-google"
                ? .minitiGoogleOAuthCallback
                : .minitiAttioOAuthCallback
            NotificationCenter.default.post(
                name: notificationName,
                object: nil,
                userInfo: ["url": url]
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.closeDuplicateWindows()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !flag
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState, appState.hasUnsavedSession else {
            return .terminateNow
        }
        guard !isTerminationReplyPending else {
            return .terminateLater
        }

        isTerminationReplyPending = true
        Task { @MainActor [weak self, weak sender] in
            let didSave = await appState.saveCurrentMeetingAndWait()
            guard let self, let sender else { return }
            if !didSave {
                DebugLogger.shared.log(.app, "Termination save did not reach SwiftData before reply")
            }
            self.finishTerminationReply(to: sender)
        }
        terminationTimeoutTask = Task { @MainActor [weak self, weak sender] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, let sender else { return }
            DebugLogger.shared.log(.app, "Termination save timed out after 5s")
            self.finishTerminationReply(to: sender)
        }
        return .terminateLater
    }

    private func finishTerminationReply(to application: NSApplication) {
        guard isTerminationReplyPending else { return }
        isTerminationReplyPending = false
        terminationTimeoutTask?.cancel()
        terminationTimeoutTask = nil
        application.reply(toApplicationShouldTerminate: true)
    }

    @MainActor private func closeDuplicateWindows() {
        let mainWindows = NSApp.windows.filter {
            $0.isVisible && $0.level == .normal && !($0 is NSPanel) &&
            $0.styleMask.contains(.fullSizeContentView)
        }
        guard mainWindows.count > 1 else { return }
        for window in mainWindows.dropFirst() {
            window.close()
        }
    }
}

@main
struct MinitiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var keyboardService = KeyboardShortcutsService.shared
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true
    @AppStorage(InterfaceScale.storageKey) private var interfaceScaleRaw = InterfaceScale.standard.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize

    private var interfaceScale: InterfaceScale {
        InterfaceScale(rawValue: interfaceScaleRaw) ?? .standard
    }
    
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
                if appState.requiresForceUpdate {
                    ForceUpdateView()
                } else if !appState.hasAcceptedTerms {
                    TermsAcceptanceView()
                } else if appState.hasCompletedOnboarding {
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
            .environment(\.interfaceScale, interfaceScale)
            .dynamicTypeSize(interfaceScale.dynamicTypeSize(from: systemDynamicTypeSize))
            .minitiReduceMotionAware()
            .onAppear {
                appDelegate.appState = appState
            }
        }
        .handlesExternalEvents(matching: ["*"])
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task {
                    _ = await appState.saveCurrentMeetingAndWait()
                }
            } else if newPhase == .active && appState.appMode == .managed {
                Task {
                    await appState.refreshUsage()
                    await appState.retryPendingSessionEndReports()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    if let onNewSession = keyboardService.onNewSession {
                        onNewSession()
                    } else {
                        appState.createNewSession()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Divider()

                Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                    toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.requiresForceUpdate || (!appState.hasAcceptedTerms && !appState.isRecording))

                Button("Generate Insights") {
                    generateInsights()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(appState.currentMeeting == nil || appState.liveSegments.isEmpty)
            }

            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .toolbar) {}

            SettingsCommands(appState: appState)

            #if canImport(Sparkle)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdateService.shared.checkForUpdates()
                }
                .disabled(!UpdateService.shared.canCheckForUpdates)
            }
            #endif

            CommandGroup(replacing: .help) {
                Button("Miniti Docs") {
                    if let url = URL(string: "https://miniti.app/docs") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Miniti Support") {
                    if let url = URL(string: "https://miniti.app/support") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environment(\.interfaceScale, interfaceScale)
                .dynamicTypeSize(interfaceScale.dynamicTypeSize(from: systemDynamicTypeSize))
                .minitiReduceMotionAware()
        }
        .modelContainer(sharedModelContainer)
        
        Window("Debug Log", id: "debug-log") {
            DebugLogView()
                .environment(\.interfaceScale, interfaceScale)
                .dynamicTypeSize(interfaceScale.dynamicTypeSize(from: systemDynamicTypeSize))
                .minitiReduceMotionAware()
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 750, height: 500)
        .windowResizability(.contentMinSize)
        
        // Menu Bar
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarView()
                .environmentObject(appState)
                .environment(\.interfaceScale, interfaceScale)
                .dynamicTypeSize(interfaceScale.dynamicTypeSize(from: systemDynamicTypeSize))
        } label: {
            MenuBarIcon(
                isRecording: appState.isRecording,
                nextEventTitle: appState.nextEvent?.title,
                nextEventTime: menuBarNextEventTime
            )
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
        
        let existingOnNewSession = keyboardService.onNewSession
        keyboardService.onNewSession = { [weak appState] in
            if let existingOnNewSession {
                existingOnNewSession()
                return
            }
            guard let appState else { return }
            appState.createNewSession()
        }
        
        keyboardService.onGoHome = { [weak appState] in
            guard let appState else { return }
            if !appState.isRecording {
                appState.goHome()
            }
        }
        
        keyboardService.onZonedOut = { [weak appState] in
            guard let appState else { return }
            if appState.isZonedOutPresented {
                appState.dismissZonedOutCatchUp()
            } else if appState.isRecording {
                appState.triggerZonedOutCatchUp()
            }
        }

        keyboardService.startMonitoring()
    }
    
    private func toggleRecording() {
        toggleRecording(appState: appState)
    }
    
    private func toggleRecording(appState: AppState) {
        guard !appState.requiresForceUpdate, appState.hasAcceptedTerms || appState.isRecording else { return }

        if appState.isRecording {
            appState.stopRecording()
        } else if appState.currentMeeting != nil {
            // Resume recording on the current session
            appState.startRecording()
        } else {
            appState.startNewMeeting()
        }
    }
    
    private var menuBarNextEventTime: String? {
        guard let event = appState.nextEvent, let start = event.startDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: start).lowercased()
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
    let nextEventTitle: String?
    let nextEventTime: String?
    @State private var isPulsing: Bool = false

    var body: some View {
        Group {
            if isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                        .opacity(isPulsing ? 1.0 : 0.5)

                    Text("REC")
                        .font(.system(size: 10, weight: .bold, design: .default))
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
                HStack(spacing: 5) {
                    Text("⬢")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)

                    if let time = nextEventTime, let title = nextEventTitle {
                        Text(time)
                            .font(.system(size: 10, weight: .semibold, design: .default))
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
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
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .monospacedDigit()
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
                    Text(meeting.displayTitle)
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
            .disabled(appState.requiresForceUpdate || (!appState.hasAcceptedTerms && !appState.isRecording))
            
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

struct SettingsCommands: Commands {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandMenu("Settings") {
            Button("General") { open("general") }
            Button("Language") { open("language") }
            Button("Account") { open("account") }
            if appState.appMode == .byok {
                Button("API Keys") { open("apikeys") }
            }
            Button("Audio") { open("audio") }
            Button("Integrations") { open("integrations") }
            Button("About") { open("about") }
        }
    }

    private func open(_ tab: String) {
        appState.selectedSettingsTab = tab
        openSettings()
    }
}
