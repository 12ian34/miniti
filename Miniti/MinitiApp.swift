import SwiftUI
import SwiftData
import AppKit
import UserNotifications
import os

extension Notification.Name {
    static let minitiAttioOAuthCallback = Notification.Name("minitiAttioOAuthCallback")
    static let minitiTwentyOAuthCallback = Notification.Name("minitiTwentyOAuthCallback")
    static let minitiGoogleOAuthCallback = Notification.Name("minitiGoogleOAuthCallback")
    /// Posted after meetings are inserted outside the main window's own flows
    /// (e.g. Granola CSV import in Settings) so the history sidebar refreshes.
    static let minitiMeetingsImported = Notification.Name("minitiMeetingsImported")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("miniti.main-window")
    private static let lifecycleLogger = Logger(subsystem: "com.miniti.app", category: "window-lifecycle")
    weak var appState: AppState?
    var openMainWindow: (() -> Void)?
    private var isTerminationReplyPending = false
    private var terminationTimeoutTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        AppState.registerSmartMeetingNotificationCategory()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let scheme = url.scheme?.lowercased() ?? ""
            guard ["miniti-google", "miniti-attio", "miniti-twenty"].contains(scheme) else { continue }
            let notificationName: Notification.Name
            switch scheme {
            case "miniti-google": notificationName = .minitiGoogleOAuthCallback
            case "miniti-twenty": notificationName = .minitiTwentyOAuthCallback
            default: notificationName = .minitiAttioOAuthCallback
            }
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
        openOrRestoreMainWindow()
        return false
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
        let mainWindows = NSApp.windows.filter { $0.isVisible && Self.isMainAppWindow($0) }
        guard mainWindows.count > 1 else { return }
        Self.lifecycleLogger.info("Closing \(mainWindows.count - 1, privacy: .public) duplicate main window(s)")
        for window in mainWindows.dropFirst() {
            window.close()
        }
    }

    static func restoreMainWindowIfPresent() -> Bool {
        guard let window = NSApp.windows.first(where: {
            isRestorableMainWindow($0, applicationIsHidden: NSApp.isHidden)
        }) else { return false }
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        lifecycleLogger.info("Restored identified main window")
        return true
    }

    /// Restore a live main window or ask SwiftUI to create a new scene after the old
    /// window was closed. A closed WindowGroup window can linger briefly in NSApp.windows;
    /// treating that stale object as restorable makes `makeKeyAndOrderFront` a no-op.
    func openOrRestoreMainWindow() {
        if Self.restoreMainWindowIfPresent() { return }

        Self.lifecycleLogger.info("Main window recreation requested")
        NSApp.activate(ignoringOtherApps: true)
        openMainWindow?()

        // Scene creation completes asynchronously. Re-activate and restore the newly
        // identified window on the next runloop so the action works from a floating panel.
        DispatchQueue.main.async { [weak self] in
            guard self != nil else { return }
            NSApp.activate(ignoringOtherApps: true)
            _ = Self.restoreMainWindowIfPresent()
        }
    }

    static func isRestorableMainWindow(
        _ window: NSWindow,
        applicationIsHidden: Bool
    ) -> Bool {
        isMainAppWindow(window)
            && (window.isVisible || window.isMiniaturized || applicationIsHidden)
    }

    private static func isMainAppWindow(_ window: NSWindow) -> Bool {
        window.identifier == mainWindowIdentifier
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let eventID = response.notification.request.content.userInfo["eventID"] as? String
        Task { @MainActor [weak self] in
            if actionIdentifier != UNNotificationDefaultActionIdentifier {
                self?.appState?.handleSmartMeetingNotificationAction(actionIdentifier, eventID: eventID)
            }
            self?.openOrRestoreMainWindow()
        }
        completionHandler()
    }
}

private struct MainWindowIdentifierInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.identifier = AppDelegate.mainWindowIdentifier
        }
    }
}

private struct MainWindowSceneBridge: View {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: AppDelegate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate.openMainWindow = {
                    openWindow(id: "main")
                }
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
        WindowGroup("Miniti", id: "main") {
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
                RecordingIndicatorCoordinator.shared.configure(appState: appState)
            }
            .background {
                MainWindowIdentifierInstaller()
                MainWindowSceneBridge(appDelegate: appDelegate)
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
                Button(appState.currentMeeting == nil ? "New Meeting" : "End & Start New Meeting") {
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
                elapsedText: AppState.presenceDuration(appState.recordingDuration),
                graceRemainingSeconds: appState.endingGrace?.remainingSeconds,
                nextEventTitle: appState.nextEvent?.title,
                nextEventTime: menuBarNextEventTime
            )
            .onAppear {
                RecordingIndicatorCoordinator.shared.configure(appState: appState)
            }
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
    let elapsedText: String
    let graceRemainingSeconds: Int?
    let nextEventTitle: String?
    let nextEventTime: String?
    @State private var isPulsing: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let remaining = graceRemainingSeconds {
                // Ending grace: distinguished by glyph and wording, not colour alone.
                HStack(spacing: 4) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                    Text("ENDING \(remaining)s")
                        .font(.system(size: 10, weight: .bold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .fixedSize(horizontal: true, vertical: true)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(ColorPalette.Status.recording)
                )
            } else if isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                        .opacity(isPulsing && !reduceMotion ? 1.0 : 0.5)

                    // Keep REC and elapsed time in one fixed-size text run. MenuBarExtra's
                    // label can otherwise compress the trailing Text away entirely.
                    Text("REC \(elapsedText)")
                        .font(.system(size: 10, weight: .bold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .fixedSize(horizontal: true, vertical: true)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(ColorPalette.Status.recording)
                )
                .onAppear {
                    guard !reduceMotion else { return }
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
                            // Long event names must not expand the menu bar excessively.
                            .frame(maxWidth: 140, alignment: .leading)
                            .truncationMode(.tail)
                    }
                }
            }
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let grace = appState.endingGrace {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(grace.appDisplayName) call ended")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text("Finishing in \(grace.remainingSeconds)s")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Keep recording") {
                            appState.keepRecordingFromEndingGrace()
                        }
                        Button("End now") {
                            appState.endEndingGraceNow()
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            if let prompt = appState.smartMeetingPrompt {
                VStack(alignment: .leading, spacing: 6) {
                    Text(prompt.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(prompt.countdown.map { "Starting next in \($0)s" } ?? prompt.message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack {
                        switch prompt.kind {
                        case .calendar:
                            if let eventID = prompt.eventID {
                                Button("End & start") {
                                    appState.endAndStartCalendarMeeting(eventID: eventID)
                                }
                            } else {
                                Button("End") {
                                    appState.endMeetingFromSmartPrompt()
                                }
                            }
                            Button("Keep") {
                                appState.keepRecordingFromSmartMeetingPrompt()
                            }
                        case .quiet, .callEnd:
                            Button("End") {
                                appState.endMeetingFromSmartPrompt()
                            }
                            Button("Keep") {
                                appState.keepRecordingFromSmartMeetingPrompt()
                            }
                        case .callStart:
                            Button("Take notes") {
                                appState.startMeetingFromDetectedCall()
                            }
                            Button("Not now") {
                                appState.dismissDetectedCallStartPrompt()
                            }
                        case .callTransition:
                            Button("End & start next") {
                                appState.endAndStartNewMeeting()
                            }
                            Button("Keep") {
                                appState.keepRecordingFromSmartMeetingPrompt()
                            }
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            // Status section
            if appState.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(ColorPalette.Status.recording)
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
                .background(ColorPalette.Status.recording.opacity(0.1))

                if let lifecycle = appState.recordingPresence.lifecycleStatus {
                    Text(lifecycle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                Divider()
            }

            // Current meeting info
            if let meeting = appState.currentMeeting {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // liveSegments is finalized-only by contract; no O(n) filter per tick.
                        Text("\(appState.liveSegments.count) segments")
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
                    appState.isRecording ? "Stop Recording" : (appState.currentMeeting == nil ? "Start Recording" : "Resume Meeting"),
                    systemImage: appState.isRecording ? "stop.fill" : "record.circle"
                )
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(appState.requiresForceUpdate || (!appState.hasAcceptedTerms && !appState.isRecording))

            if appState.currentMeeting != nil {
                Button {
                    appState.endAndStartNewMeeting()
                } label: {
                    Label("End & Start New Meeting", systemImage: "plus.square.on.square")
                }
            }
            
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
                (NSApp.delegate as? AppDelegate)?.openOrRestoreMainWindow()
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
    @FocusedValue(\.settingsSearchFocusAction) private var focusSettingsSearch

    var body: some Commands {
        CommandMenu("Settings") {
            Button("Search Settings") {
                focusSettingsSearch?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(focusSettingsSearch == nil)

            Divider()

            Button("General") { open("general") }
            Button("Account & Plan") { open("account") }
            Button("Recording & Audio") { open("recording") }
            Button("Language") { open("language") }
            Button("AI & Models") { open("ai") }
            Button("Notifications") { open("notifications") }
            Divider()
            Button("Calendar & Meetings") { open("calendar") }
            Button("CRM") { open("crm") }
            Button("Webhooks") { open("webhooks") }
            Button("Docs MCP") { open("docsMCP") }
            Button("Data & Export") { open("dataExport") }
            Button("Privacy & Support") { open("privacySupport") }
        }
    }

    private func open(_ tab: String) {
        appState.selectedSettingsTab = SettingsDestination.fromLegacyID(tab).rawValue
        appState.pendingSettingsSearchTarget = nil
        openSettings()
    }
}
