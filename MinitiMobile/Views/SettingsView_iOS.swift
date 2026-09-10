import SwiftUI
import AVFoundation
import SwiftData
import UniformTypeIdentifiers

struct SettingsView_iOS: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var selectedDestination: SettingsDestination? = .general

    private var searchResults: [SettingsSearchItem] {
        SettingsSearchCatalog.availableItems(on: .iOS, appMode: appState.appMode)
            .filter { $0.matches(searchText) }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularWidthSettings
            } else {
                compactSettings
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            let restored = SettingsDestination.fromLegacyID(appState.selectedSettingsTab)
            selectedDestination = SettingsDestination.available(on: .iOS).contains(restored) ? restored : .general
        }
    }

    private var compactSettings: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    ForEach(SettingsDestination.available(on: .iOS)) { destination in
                        NavigationLink {
                            SettingsDetailView_iOS(category: destination)
                        } label: {
                            destinationLabel(destination)
                        }
                    }
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(searchResults) { item in
                        NavigationLink {
                            SettingsDetailView_iOS(category: item.destination, initialSearchTarget: item.id)
                        } label: {
                            searchResultLabel(item)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search settings")
            .scrollContentBackground(.hidden)
            .background(ColorPalette.Background.primary)
        }
    }

    private var regularWidthSettings: some View {
        NavigationSplitView {
            List(selection: $selectedDestination) {
                if searchText.isEmpty {
                    ForEach(SettingsDestination.available(on: .iOS)) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination)
                    }
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(searchResults) { item in
                        Button {
                            openSearchResult(item)
                        } label: {
                            searchResultLabel(item)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Settings")
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search settings")
            .onChange(of: selectedDestination) { _, destination in
                guard let destination else { return }
                appState.selectedSettingsTab = destination.rawValue
                appState.pendingSettingsSearchTarget = nil
            }
        } detail: {
            NavigationStack {
                SettingsDetailView_iOS(category: selectedDestination ?? .general)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func destinationLabel(_ destination: SettingsDestination) -> some View {
        HStack(spacing: 12) {
            Image(systemName: destination.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(destination.title).font(.headline)
                Text(destination.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func searchResultLabel(_ item: SettingsSearchItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .foregroundStyle(.primary)
            Text(item.breadcrumb)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private func openSearchResult(_ item: SettingsSearchItem) {
        selectedDestination = item.destination
        appState.selectedSettingsTab = item.destination.rawValue
        appState.pendingSettingsSearchTarget = nil
        DispatchQueue.main.async {
            appState.pendingSettingsSearchTarget = item.id
        }
    }
}

private struct SettingsScrollTargetModifier_iOS: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let destination: SettingsDestination

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onAppear {
                    scrollIfNeeded(with: proxy, target: appState.pendingSettingsSearchTarget)
                }
                .onChange(of: appState.pendingSettingsSearchTarget) { _, target in
                    scrollIfNeeded(with: proxy, target: target)
                }
        }
    }

    private func scrollIfNeeded(with proxy: ScrollViewProxy, target: String?) {
        guard let target,
              SettingsSearchCatalog.items.first(where: { $0.id == target })?.destination == destination else { return }
        DispatchQueue.main.async {
            if reduceMotion {
                proxy.scrollTo(target, anchor: .center)
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }
}

private extension View {
    func settingsSearchScrolling_iOS(for destination: SettingsDestination) -> some View {
        modifier(SettingsScrollTargetModifier_iOS(destination: destination))
    }
}

private struct SettingsDetailView_iOS: View {
    let category: SettingsDestination
    var initialSearchTarget: String? = nil
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("shareDiagnostics") private var shareDiagnostics: Bool = false
    @AppStorage(PersonalDictionaryPreferences.storageKey) private var personalDictionaryTermsData: Data = Data()
    @AppStorage(LiveActivityPreferences.showTranscriptKey) private var showTranscriptInLiveActivity = true
    @State private var versionTapCount = 0
    @State private var lastVersionTap: Date?
    @State private var showDebugLog = false
    @State private var isPurchasing = false
    @State private var isRestoringPurchases = false
    @State private var subscriptionMessage: String?
    @State private var isGranolaImporterPresented = false
    @State private var isImportingGranola = false
    @State private var granolaImportMessage: String?
    @State private var granolaImportFailed = false
    
    var body: some View {
            Form {
                if category == .general {
                Section("Appearance") {
                    InterfaceScaleSlider()
                        .id("general.interfaceScale")
                }
                }

                if category == .language {
                Section("Language") {
                    Picker("Default Language", selection: $appState.defaultLanguage) {
                        ForEach(TranscriptionLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    .id("language.default")
                    
                    Text("Transcription, insights, and coaching filler detection all adapt to this language. Can be overridden per meeting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    NavigationLink(destination: FillerSettingsDetail_iOS()) {
                        HStack {
                            Text("Filler detection")
                            Spacer()
                            Text("\(TrainingFillerPreferences.currentFillers(for: appState.defaultLanguage).count) tracked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .id("language.fillers")

                    NavigationLink(destination: PersonalDictionaryDetail_iOS()) {
                        HStack {
                            Text("Personal dictionary")
                            Spacer()
                            Text("\(personalDictionaryTermCount) terms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .id("language.dictionary")
                }
                }
                
                if category == .account {
                if appState.appMode == .managed {
                    Section("Subscription") {
                        HStack {
                            Text("Plan")
                            Spacer()
                            if appState.shouldShowManagedSubscriptionPlaceholder {
                                Text("Checking…")
                                    .foregroundStyle(.secondary)
                            } else if appState.isPro {
                                Text("Pro — \(Int(appState.displayMinutesLimit)) min/month")
                                    .foregroundStyle(.purple)
                                    .fontWeight(.medium)
                            } else {
                                Text("Free — 500 min/month")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if appState.shouldShowManagedSubscriptionPlaceholder {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Checking subscription status…")
                                    .foregroundStyle(.secondary)
                            }
                        } else if appState.isPro {
                            Button("Manage Subscription") {
                                Task { await appState.openManageSubscriptionPage() }
                            }
                        } else {
                            Button {
                                guard !isPurchasing else { return }
                                isPurchasing = true
                                subscriptionMessage = nil
                                Task {
                                    let success = await appState.purchaseProSubscription()
                                    isPurchasing = false
                                    if success {
                                        subscriptionMessage = "Pro subscription is now active."
                                    } else {
                                        subscriptionMessage = appState.storeKitService?.purchaseErrorMessage ?? "Purchase not completed."
                                    }
                                }
                            } label: {
                                if isPurchasing {
                                    HStack {
                                        ProgressView()
                                        Text("Purchasing…")
                                    }
                                } else {
                                    Text("Upgrade to Pro — $4.99/month")
                                }
                            }
                        }

                        if !appState.shouldShowManagedSubscriptionPlaceholder && !appState.isPro {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Miniti Pro Monthly")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("$4.99/month · auto-renewable")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Link("Terms", destination: URL(string: "https://miniti.app/terms")!)
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Link("Privacy", destination: URL(string: "https://miniti.app/privacy")!)
                                }
                                .font(.caption2)
                            }
                        }
                        
                        Button {
                            guard !isRestoringPurchases else { return }
                            isRestoringPurchases = true
                            subscriptionMessage = nil
                            Task {
                                let restored = await appState.restoreAppStorePurchases()
                                isRestoringPurchases = false
                                if restored {
                                    subscriptionMessage = "Purchases restored."
                                } else {
                                    subscriptionMessage = appState.storeKitService?.purchaseErrorMessage ?? "No active App Store subscription found."
                                }
                            }
                        } label: {
                            if isRestoringPurchases {
                                HStack {
                                    ProgressView()
                                        Text("Restoring…")
                                }
                            } else {
                                Text("Restore Purchases")
                            }
                        }
                        
                        if let subscriptionMessage {
                            Text(subscriptionMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                    }
                    .id("account.subscription")
                    
                    Section("Usage") {
                        if let usage = appState.usageInfo {
                            HStack {
                                Text("Minutes Used")
                                Spacer()
                                Text("\(Int(appState.displayMinutesUsed.rounded())) / \(Int(appState.displayMinutesLimit))")
                                    .foregroundStyle(.secondary)
                            }
                            
                            ProgressView(value: appState.displayUsagePercentage)
                                .tint(appState.isPro ? .purple : (appState.displayMinutesRemaining < 60 ? .orange : .green))
                            
                            HStack {
                                Text("Remaining")
                                Spacer()
                                Text(appState.formattedDisplayRemaining)
                                    .foregroundStyle(appState.displayMinutesRemaining < 60 ? .orange : (appState.isPro ? .purple : .green))
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Resets")
                                Spacer()
                                Text(usage.resetsAt.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            }
                        } else if appState.isLoadingUsage {
                            HStack {
                                Text("Loading usage…")
                                Spacer()
                                ProgressView()
                            }
                        } else {
                            HStack {
                                Text("Usage data unavailable")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Refresh") {
                                    Task { await appState.refreshUsage() }
                                }
                            }
                        }
                    }
                    .id("account.usage")

                    ManagedAccountSettingsSection()
                }

                Section("Mode") {
                    Picker("API Mode", selection: $appState.appModeRaw) {
                        Text(
                            appState.shouldShowManagedSubscriptionPlaceholder
                                ? "Miniti (checking plan…)"
                                : (appState.isPro ? "Miniti Pro (5,000 min/month)" : "Miniti Free (500 min/month)")
                        )
                        .tag(AppMode.managed.rawValue)
                        Text("Bring Your Own Keys").tag(AppMode.byok.rawValue)
                    }
                    .id("account.apiMode")
                    .onChange(of: appState.appModeRaw) { _, newValue in
                        if newValue == AppMode.managed.rawValue {
                            Task { await appState.refreshUsage() }
                        }
                    }
                    
                    Text(appState.appMode == .managed
                         ? (appState.shouldShowManagedSubscriptionPlaceholder
                            ? "Checking subscription status…"
                            : (appState.isPro
                               ? "Pro subscription active. \(Int(appState.displayMinutesLimit)) minutes per month."
                               : "500 free minutes per month via Miniti's backend."))
                         : "Use your own Deepgram & OpenAI API keys. No limits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // API Keys (BYOK mode)
                if appState.appMode == .byok {
                    Section("API Keys") {
                        APIKeyRow(
                            label: "Deepgram",
                            key: $appState.deepgramApiKey,
                            placeholder: "Enter Deepgram API key"
                        )
                        .id("account.deepgramKey")
                        
                        APIKeyRow(
                            label: "OpenAI",
                            key: $appState.openaiApiKey,
                            placeholder: "Enter OpenAI API key"
                        )
                        .id("account.openAIKey")
                    }
                }
                }
                
                // Audio
                if category == .recording {
                Section("Audio") {
                    HStack {
                        Text("Microphone")
                        Spacer()
                        PermissionBadge_iOS(granted: checkMicPermission())
                    }
                    
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .id("recording.permissions")
                }
                
                // Models (read-only)
                if category == .ai {
                Section("Models") {
                    HStack {
                        Text("Transcription")
                        Spacer()
                        Text("Nova-3")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Insights")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if appState.appMode == .managed {
                                Text("gpt-5-mini-2025-08-07 · live updates")
                                Text("gpt-5.4-mini-2026-03-17 · full insights + investigations")
                            } else {
                                Text("gpt-5-mini-2025-08-07 · insights")
                                Text("gpt-5.4-mini-2026-03-17 · investigations")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    }
                }
                .id("ai.models")

                Section("Provider Mode") {
                    LabeledContent("Current mode", value: appState.appMode == .byok ? "Bring Your Own Keys" : "Managed by Miniti")
                    Text(appState.appMode == .byok
                         ? "Transcription and insights use the Deepgram and OpenAI keys saved under Account & Plan. Calendar, webhooks, Docs MCP, and Smart meetings remain available in BYOK mode."
                         : "Miniti supplies the transcription and insight providers for your plan. Integration and meeting-automation settings work the same way as in BYOK mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Meeting Investigations") {
                    Text("Web investigations run inside Miniti using OpenAI only when you tap Investigate. Results include clickable source citations; nothing runs automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .id("ai.investigations")
                }
                
                // Device
                if category == .account {
                Section("Device") {
                    HStack {
                        Text("Device ID")
                        Spacer()
                        Text(DeviceIdentifier.getOrCreateDeviceId())
                            .foregroundStyle(.secondary)
                            .font(.system(.caption2, design: .default))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                .id("account.deviceID")
                }

                if category == .recording {
                Section("Recording") {
                    Picker("Auto-stop after silence", selection: $appState.autoStopMinutes) {
                        Text("Off").tag(0)
                        Text("3 minutes").tag(3)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                    }
                    .id("recording.autoStop")
                    Text("Automatically stop recording when no speech is detected for the selected duration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Auto-name speakers from transcript", isOn: $appState.autoInferSpeakerNames)
                        .id("recording.autoNameSpeakers")
                    Text("Detects real names from the conversation and labels each speaker accordingly in the live and saved transcripts. When Google Calendar is connected, attendee names are used as hints. Remains \"You\"/\"Speaker N\" until a name is confident.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Live Activity") {
                    Toggle("Show transcript on Lock Screen", isOn: $showTranscriptInLiveActivity)
                        .id("recording.liveActivityTranscript")
                        .onChange(of: showTranscriptInLiveActivity) { _, _ in
                            appState.refreshLiveActivityPrivacySetting()
                        }
                    Text("Shows the latest transcript line in the Lock Screen and expanded Dynamic Island while recording. Turn this off to keep transcript text private; the timer and recording status remain visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                }

                if category == .notifications {
                Section("Meeting Nudges") {
                    Toggle("Notify me about incisive questions", isOn: $appState.notifyOnIncisiveQuestions)
                        .id("notifications.questions")
                        .onChange(of: appState.notifyOnIncisiveQuestions) { _, newValue in
                            if newValue {
                                appState.requestQuestionNotificationPermission()
                            }
                        }
                    Text("Sends a notification during recording when the AI spots a high-priority question you should ask. Only fires when the app is in the background, limited to one every 2 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Nudge me when I'm monologuing", isOn: $appState.notifyOnMonologue)
                        .id("notifications.monologue")
                        .onChange(of: appState.notifyOnMonologue) { _, newValue in
                            if newValue {
                                appState.requestNudgeNotificationPermission()
                            }
                        }
                    Text("Gently alerts you if you've been talking for roughly a minute or more without interruption. Only fires when the app is in the background, limited to one every 3 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Nudge me when I'm using too many fillers", isOn: $appState.notifyOnHighFillerRate)
                        .id("notifications.fillers")
                        .onChange(of: appState.notifyOnHighFillerRate) { _, newValue in
                            if newValue {
                                appState.requestNudgeNotificationPermission()
                            }
                        }
                    Text("Alerts you when filler words like \"um\" and \"uh\" spike in your last minute of speaking. Uses your configured filler list per language. Only fires when the app is in the background, limited to one every 3 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Remind me 1 minute before upcoming meetings", isOn: $appState.notifyOnUpcomingMeeting)
                        .id("notifications.upcomingMeeting")
                        .onChange(of: appState.notifyOnUpcomingMeeting) { _, newValue in
                            if newValue {
                                appState.requestNudgeNotificationPermission { _ in
                                    Task { @MainActor in appState.rescheduleMeetingReminders() }
                                }
                            } else {
                                appState.rescheduleMeetingReminders()
                            }
                        }
                    Text("Fires a notification about 60 seconds before each upcoming Google Calendar event starts. Requires Google Calendar to be connected. In addition to Calendar's own alerts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                }

                if category == .dataExport {
                Section("Import from Granola") {
                    Link(destination: GranolaCSVImporter.exportURL) {
                        HStack {
                            Label("Export meetings in Granola", systemImage: "arrow.up.right.square")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        isGranolaImporterPresented = true
                    } label: {
                        if isImportingGranola {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Importing…")
                            }
                        } else {
                            Label("Import Granola CSV", systemImage: "tray.and.arrow.down")
                        }
                    }
                    .disabled(isImportingGranola)

                    if let granolaImportMessage {
                        Label(
                            granolaImportMessage,
                            systemImage: granolaImportFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(granolaImportFailed ? ColorPalette.Status.error : ColorPalette.Accent.green)
                    }

                    Text("Granola opens Profile → Account management. Generate the CSV, then select the emailed download here. Re-importing skips meetings already brought into Miniti.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .id("data.granola")
                }

                if category == .calendar {
                Section("Calendar & Meeting Automation") {
                    Toggle("Smart meetings", isOn: $appState.smartMeetingsEnabled)
                        .id("integrations.smartMeetings")
                    Text("Notices when a meeting may have ended or another meeting is approaching, then helps you finish, save, and start the right recording. Works with or without Google Calendar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Learn more about Smart meetings ↗", destination: URL(string: "https://miniti.app/docs/features/smart-meetings")!)
                        .font(.caption)

                    Toggle("Enable Google Calendar", isOn: $appState.googleCalendarEnabled)
                        .id("integrations.googleCalendar")
                    Text("Show upcoming meetings on the home screen and pre-fill meeting context with attendees.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if appState.googleCalendarEnabled {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(appState.isGoogleCalendarConnected ? ColorPalette.Status.connected : ColorPalette.Status.disconnected)
                                .frame(width: 8, height: 8)

                            if appState.isGoogleCalendarConnected {
                                if let email = appState.googleCalendarEmail {
                                    Text(email)
                                        .font(.system(size: 12, design: .default))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } else {
                                    Text("connected")
                                        .font(.system(size: 12, design: .default))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("not connected")
                                    .font(.system(size: 12, design: .default))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if appState.isGoogleCalendarConnected {
                                Button("Disconnect") {
                                    Task { await appState.googleDisconnect() }
                                }
                            } else {
                                Button("Connect") {
                                    Task { await appState.googleConnect() }
                                }
                            }
                        }

                        Text("Read-only access to calendar events. Miniti never modifies your calendar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if appState.isGoogleCalendarConnected {
                            Toggle("Auto-start recording", isOn: $appState.autoStartFromCalendar)
                                .id("integrations.autoStart")
                            Text("Show a 15-second countdown when a calendar meeting starts. Dismiss to skip. Only fires while Miniti is open in the foreground.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Toggle("Auto-stop after meeting ends", isOn: $appState.autoStopFromCalendar)
                                .id("integrations.calendarAutoStop")
                            Text("Automatically stop recording when the calendar event ends and no one is speaking.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                }

                if category == .webhooks {
                Section("Webhooks") {
                    TextField("Webhook URL", text: $appState.webhookURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .id("integrations.webhook")
                    if !appState.webhookURL.isEmpty {
                        if let url = URL(string: appState.webhookURL),
                           let scheme = url.scheme?.lowercased(),
                           (scheme == "http" || scheme == "https"),
                           url.host != nil {
                            Label("valid URL", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(ColorPalette.Accent.green)
                        } else {
                            Label("invalid URL — must start with https://", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(ColorPalette.Status.error)
                        }
                    }
                    Text("POST meeting data as JSON when a meeting is saved or insights are updated. Works with Zapier, Make, n8n, or any webhook endpoint.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                }

                if category == .docsMCP {
                DocsMCPSettingsSection_iOS()
                    .id("integrations.docsMCP")
                }

                if category == .privacySupport {
                Section("Diagnostics") {
                    Toggle("Share Diagnostics", isOn: $shareDiagnostics)
                        .id("privacy.diagnostics")
                    Text("Sends structured reliability events (errors, reconnects, health states) with no transcript or audio content.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundStyle(.secondary)
                            .onTapGesture {
                                handleVersionTap()
                            }
                    }
                    .id("privacy.version")
                    Text("Pro is an auto-renewable subscription. Cancel anytime in Apple ID subscriptions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://miniti.app")!) {
                        HStack {
                            Text("Website")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://miniti.app/docs")!) {
                        HStack {
                            Text("Docs")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .id("privacy.docs")
                    Link(destination: URL(string: "https://miniti.app/roadmap")!) {
                        HStack {
                            Text("Roadmap")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://miniti.app/changelog")!) {
                        HStack {
                            Text("Changelog")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://miniti.app/support")!) {
                        HStack {
                            Text("Support")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .id("privacy.support")
                    Link(destination: URL(string: "https://miniti.app/privacy")!) {
                        HStack {
                            Text("Privacy")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .id("privacy.legal")
                    Link(destination: URL(string: "https://miniti.app/terms")!) {
                        HStack {
                            Text("Terms")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "itms-apps://apps.apple.com/app/id6759067308")!) {
                        HStack {
                            Text("Rate on App Store")
                            Spacer()
                            Image(systemName: "star")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                }
            }
            .settingsSearchScrolling_iOS(for: category)
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(ColorPalette.Background.primary)
            .sheet(isPresented: $showDebugLog) {
                DebugLogView()
            }
            .fileImporter(
                isPresented: $isGranolaImporterPresented,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                if case .success(let url) = result {
                    importGranolaCSV(from: url)
                } else if case .failure(let error) = result {
                    granolaImportFailed = true
                    granolaImportMessage = error.localizedDescription
                }
            }
            .onAppear {
                appState.selectedSettingsTab = category.rawValue
                guard let initialSearchTarget else { return }
                appState.pendingSettingsSearchTarget = nil
                DispatchQueue.main.async {
                    appState.pendingSettingsSearchTarget = initialSearchTarget
                }
            }
        .preferredColorScheme(.dark)
    }

    private func importGranolaCSV(from url: URL) {
        isImportingGranola = true
        granolaImportMessage = nil
        granolaImportFailed = false
        Task {
            do {
                let parsed = try await GranolaCSVImporter.load(from: url)
                let result = try GranolaCSVImporter.importMeetings(
                    parsed,
                    into: modelContext,
                    defaultLanguage: appState.defaultLanguage
                )
                granolaImportMessage = result.message
            } catch {
                granolaImportFailed = true
                granolaImportMessage = error.localizedDescription
                DebugLogger.shared.log(.app, "Granola CSV import FAILED: \(error.localizedDescription)")
            }
            isImportingGranola = false
        }
    }

    private var personalDictionaryTermCount: Int {
        guard let decoded = try? JSONDecoder().decode([String].self, from: personalDictionaryTermsData) else {
            return 0
        }

        return PersonalDictionaryPreferences.normalizedTerms(decoded).count
    }
    
    private func handleVersionTap() {
        let now = Date()
        if let last = lastVersionTap, now.timeIntervalSince(last) < 1.5 {
            versionTapCount += 1
        } else {
            versionTapCount = 1
        }
        lastVersionTap = now
        if versionTapCount >= 5 {
            showDebugLog = true
            versionTapCount = 0
        }
    }
    
    private func checkMicPermission() -> Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }
}

struct FillerSettingsDetail_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var fillers: [String] = []
    @State private var newFiller = ""
    @State private var editingIndex: Int?
    @State private var editingText = ""
    @State private var validationMessage: String?
    
    var body: some View {
        Form {
            Section {
                Text("These words and phrases are tracked in Coaching. The list updates when you change the default language in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Tracked Fillers") {
                ForEach(Array(fillers.enumerated()), id: \.offset) { index, filler in
                    HStack {
                        Text(filler)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            editingIndex = index
                            editingText = filler
                            validationMessage = nil
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(filler)")
                        
                        Button(role: .destructive) {
                            removeFiller(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(filler)")
                    }
                }
                
                HStack {
                    TextField("Add phrase (example: i think)", text: $newFiller)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            addFiller()
                        }
                    Button("Add") {
                        addFiller()
                    }
                    .disabled(newFiller.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Actions") {
                Button("Reset to defaults") {
                    fillers = TrainingFillerPreferences.defaultFillers(for: appState.defaultLanguage)
                    persistFillers()
                    validationMessage = "Restored default filler list."
                }
                HStack {
                    Text("Tracked phrases")
                    Spacer()
                    Text("\(fillers.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Filler Detection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fillers = TrainingFillerPreferences.currentFillers(for: appState.defaultLanguage)
        }
        .alert("Edit filler phrase", isPresented: Binding(
            get: { editingIndex != nil },
            set: { showing in
                if !showing {
                    editingIndex = nil
                    editingText = ""
                }
            }
        )) {
            TextField("Phrase", text: $editingText)
            Button("Cancel", role: .cancel) {
                editingIndex = nil
                editingText = ""
            }
            Button("Save") {
                saveEditedFiller()
            }
        }
    }
    
    private func addFiller() {
        let trimmed = newFiller.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        fillers.append(trimmed)
        newFiller = ""
        persistFillers()
        validationMessage = nil
    }
    
    private func removeFiller(at index: Int) {
        guard fillers.indices.contains(index) else { return }
        fillers.remove(at: index)
        persistFillers()
        validationMessage = nil
    }
    
    private func saveEditedFiller() {
        guard let editingIndex, fillers.indices.contains(editingIndex) else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "Filler phrase cannot be empty."
            return
        }
        fillers[editingIndex] = trimmed
        self.editingIndex = nil
        editingText = ""
        persistFillers()
        validationMessage = nil
    }
    
    private func persistFillers() {
        let normalized = TrainingFillerPreferences.normalizedFillers(fillers)
        fillers = normalized.isEmpty ? TrainingFillerPreferences.defaultFillers(for: appState.defaultLanguage) : normalized
        TrainingFillerPreferences.save(fillers, for: appState.defaultLanguage)
        appState.recomputeTrainingMetrics()
    }
}

struct PersonalDictionaryDetail_iOS: View {
    @EnvironmentObject private var appState: AppState
    @State private var dictionaryTerms: [String] = []
    @State private var newDictionaryTerm = ""
    @State private var editingIndex: Int?
    @State private var editingText = ""
    @State private var validationMessage: String?
    @State private var corrections: [PersonalDictionaryPreferences.CorrectionPair] = []
    @State private var newHeard = ""
    @State private var newCorrect = ""
    @State private var correctionValidationMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Add product names, customer names, acronyms, or uncommon words that Deepgram should treat as real terms. Used when a new recording connects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Personal Terms") {
                ForEach(Array(dictionaryTerms.enumerated()), id: \.offset) { index, term in
                    HStack {
                        Text(term)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            editingIndex = index
                            editingText = term
                            validationMessage = nil
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(term)")

                        Button(role: .destructive) {
                            removeDictionaryTerm(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(term)")
                    }
                }

                HStack {
                    TextField("Add word (example: Lightdash)", text: $newDictionaryTerm)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            addDictionaryTerm()
                        }
                    Button("Add") {
                        addDictionaryTerm()
                    }
                    .disabled(newDictionaryTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Corrections") {
                Text("Heard → corrected. Applied live for the rest of the meeting, and on the next Deepgram connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(corrections.enumerated()), id: \.element.id) { index, pair in
                    HStack {
                        Text("\(pair.heard) → \(pair.correct)")
                            .lineLimit(2)
                        Spacer()
                        Button(role: .destructive) {
                            removeCorrection(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete correction \(pair.heard)")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("heard", text: $newHeard)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("correct to", text: $newCorrect)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { addCorrection() }
                    Button("Add correction") { addCorrection() }
                        .disabled(
                            newHeard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || newCorrect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }

                if let correctionValidationMessage {
                    Text(correctionValidationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Summary") {
                HStack {
                    Text("Personal terms")
                    Spacer()
                    Text("\(dictionaryTerms.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Corrections")
                    Spacer()
                    Text("\(corrections.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Personal Dictionary")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dictionaryTerms = PersonalDictionaryPreferences.currentTerms()
            corrections = PersonalDictionaryPreferences.currentCorrections()
        }
        .alert("Edit dictionary term", isPresented: Binding(
            get: { editingIndex != nil },
            set: { showing in
                if !showing {
                    editingIndex = nil
                    editingText = ""
                }
            }
        )) {
            TextField("Term", text: $editingText)
            Button("Cancel", role: .cancel) {
                editingIndex = nil
                editingText = ""
            }
            Button("Save") {
                saveEditedDictionaryTerm()
            }
        }
    }

    private func addDictionaryTerm() {
        let trimmed = newDictionaryTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dictionaryTerms.append(trimmed)
        newDictionaryTerm = ""
        persistDictionaryTerms()
        validationMessage = nil
    }

    private func removeDictionaryTerm(at index: Int) {
        guard dictionaryTerms.indices.contains(index) else { return }
        dictionaryTerms.remove(at: index)
        persistDictionaryTerms()
        validationMessage = nil
    }

    private func saveEditedDictionaryTerm() {
        guard let editingIndex, dictionaryTerms.indices.contains(editingIndex) else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "Dictionary term cannot be empty."
            return
        }
        dictionaryTerms[editingIndex] = trimmed
        self.editingIndex = nil
        editingText = ""
        persistDictionaryTerms()
        validationMessage = nil
    }

    private func persistDictionaryTerms() {
        dictionaryTerms = PersonalDictionaryPreferences.normalizedTerms(dictionaryTerms)
        PersonalDictionaryPreferences.save(dictionaryTerms)
    }

    private func addCorrection() {
        let heard = newHeard.trimmingCharacters(in: .whitespacesAndNewlines)
        let correct = newCorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !correct.isEmpty else { return }
        guard heard.lowercased() != correct.lowercased() else {
            correctionValidationMessage = "Heard and corrected text must differ."
            return
        }
        switch PersonalDictionaryPreferences.upsertCorrection(heard: heard, correct: correct) {
        case .saved:
            newHeard = ""
            newCorrect = ""
            persistCorrections()
            correctionValidationMessage = nil
        case .full:
            correctionValidationMessage = "The dictionary holds up to \(PersonalDictionaryPreferences.maxCorrections) corrections. Remove one first."
        case .invalid:
            correctionValidationMessage = "Heard and corrected text must differ."
        }
    }

    private func removeCorrection(at index: Int) {
        guard corrections.indices.contains(index) else { return }
        corrections.remove(at: index)
        persistCorrections()
        correctionValidationMessage = nil
    }

    private func persistCorrections() {
        PersonalDictionaryPreferences.saveCorrections(corrections)
        corrections = PersonalDictionaryPreferences.currentCorrections()
        dictionaryTerms = PersonalDictionaryPreferences.currentTerms()
        appState.reloadTranscriptCorrector()
    }
}

// MARK: - API Key Row

struct APIKeyRow: View {
    let label: String
    @Binding var key: String
    let placeholder: String
    @State private var showKey = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.headline)
            
            HStack {
                if showKey {
                    TextField(placeholder, text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .default))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField(placeholder, text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .default))
                }
                
                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showKey ? "Hide \(label) API key" : "Show \(label) API key")
            }
            
            HStack(spacing: 4) {
                Circle()
                    .fill(key.isEmpty ? ColorPalette.Status.noApiKey : ColorPalette.Status.success)
                    .frame(width: 6, height: 6)
                Text(key.isEmpty ? "Not set" : "Configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DocsMCPSettingsSection_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false

    var body: some View {
        Section("Docs MCP") {
            TextField("Docs MCP URL", text: $appState.docsMCPURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !appState.docsMCPURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if appState.validatedDocsMCPURL != nil {
                    Label("valid https URL", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(ColorPalette.Accent.green)
                } else {
                    Label("invalid URL — https only, no localhost/private hosts", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(ColorPalette.Status.error)
                }
            }
            Button(isTesting ? "testing…" : "Test Connection") {
                Task { await testConnection() }
            }
            .disabled(isTesting || appState.validatedDocsMCPURL == nil)
            if let testMessage {
                Text(testMessage)
                    .font(.caption)
                    .foregroundStyle(testSucceeded ? ColorPalette.Accent.green : ColorPalette.Status.error)
            }
            Text("HTTPS Streamable HTTP MCP server for product docs. In the Playbook insight view, choose a topic when you want an answer with citations. Example: https://docs.lightdash.com/mcp")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Looking up docs sends recent transcript text from the meeting to this docs host to search for relevant pages.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func testConnection() async {
        guard let url = appState.validatedDocsMCPURL else { return }
        isTesting = true
        testMessage = nil
        defer { isTesting = false }
        do {
            let tool = try await DocsMCPService.probe(mcpURL: url)
            testSucceeded = true
            testMessage = "found search tool: \(tool.name)"
        } catch {
            testSucceeded = false
            testMessage = error.localizedDescription
        }
    }
}

// MARK: - Permission Badge

struct PermissionBadge_iOS: View {
    let granted: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(granted ? "Granted" : "Not Granted")
        }
        .font(.caption)
        .foregroundStyle(granted ? .green : .red)
    }
}
