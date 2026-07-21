import SwiftUI
import AVFoundation

struct SettingsView_iOS: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("shareDiagnostics") private var shareDiagnostics: Bool = false
    @AppStorage(PersonalDictionaryPreferences.storageKey) private var personalDictionaryTermsData: Data = Data()
    @State private var versionTapCount = 0
    @State private var lastVersionTap: Date?
    @State private var showDebugLog = false
    @State private var isPurchasing = false
    @State private var isRestoringPurchases = false
    @State private var subscriptionMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Language") {
                    Picker("Default Language", selection: $appState.defaultLanguage) {
                        ForEach(TranscriptionLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    
                    Text("Transcription, insights, and training filler detection all adapt to this language. Can be overridden per meeting.")
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

                    NavigationLink(destination: PersonalDictionaryDetail_iOS()) {
                        HStack {
                            Text("Personal dictionary")
                            Spacer()
                            Text("\(personalDictionaryTermCount) terms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if appState.appMode == .managed {
                    Section("Subscription") {
                        HStack {
                            Text("Plan")
                            Spacer()
                            if appState.shouldShowManagedSubscriptionPlaceholder {
                                Text("Checking...")
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
                                Text("Checking subscription status...")
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
                                        Text("Purchasing...")
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
                                    Text("Restoring...")
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
                                Text("Loading usage...")
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

                }

                Section("Mode") {
                    Picker("API Mode", selection: $appState.appModeRaw) {
                        Text(
                            appState.shouldShowManagedSubscriptionPlaceholder
                                ? "Miniti (checking plan...)"
                                : (appState.isPro ? "Miniti Pro (5,000 min/month)" : "Miniti Free (500 min/month)")
                        )
                        .tag(AppMode.managed.rawValue)
                        Text("Bring Your Own Keys").tag(AppMode.byok.rawValue)
                    }
                    .onChange(of: appState.appModeRaw) { _, newValue in
                        if newValue == AppMode.managed.rawValue {
                            Task { await appState.refreshUsage() }
                        }
                    }
                    
                    Text(appState.appMode == .managed
                         ? (appState.shouldShowManagedSubscriptionPlaceholder
                            ? "Checking subscription status..."
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
                        
                        APIKeyRow(
                            label: "OpenAI",
                            key: $appState.openaiApiKey,
                            placeholder: "Enter OpenAI API key"
                        )
                    }
                }
                
                // Audio
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
                
                // Models (read-only)
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
                        Text("GPT-5 Mini")
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Device
                Section("Device") {
                    HStack {
                        Text("Device ID")
                        Spacer()
                        Text(DeviceIdentifier.getOrCreateDeviceId())
                            .foregroundStyle(.secondary)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }

                Section("Recording") {
                    Picker("Auto-stop after silence", selection: $appState.autoStopMinutes) {
                        Text("Off").tag(0)
                        Text("3 minutes").tag(3)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                    }
                    Text("Automatically stop recording when no speech is detected for the selected duration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Auto-name speakers from transcript", isOn: $appState.autoInferSpeakerNames)
                    Text("Detects real names from the conversation and labels each speaker accordingly in the live and saved transcripts. When Google Calendar is connected, attendee names are used as hints. Remains \"You\"/\"Speaker N\" until a name is confident.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Nudges") {
                    Toggle("Notify me about incisive questions", isOn: $appState.notifyOnIncisiveQuestions)
                        .onChange(of: appState.notifyOnIncisiveQuestions) { _, newValue in
                            if newValue {
                                appState.requestQuestionNotificationPermission()
                            }
                        }
                    Text("Sends a notification during recording when the AI spots a high-priority question you should ask. Only fires when the app is in the background, limited to one every 2 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Nudge me when I'm monologuing", isOn: $appState.notifyOnMonologue)
                        .onChange(of: appState.notifyOnMonologue) { _, newValue in
                            if newValue {
                                appState.requestNudgeNotificationPermission()
                            }
                        }
                    Text("Gently alerts you if you've been talking for roughly a minute or more without interruption. Only fires when the app is in the background, limited to one every 3 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Nudge me when I'm using too many fillers", isOn: $appState.notifyOnHighFillerRate)
                        .onChange(of: appState.notifyOnHighFillerRate) { _, newValue in
                            if newValue {
                                appState.requestNudgeNotificationPermission()
                            }
                        }
                    Text("Alerts you when filler words like \"um\" and \"uh\" spike in your last minute of speaking. Uses your configured filler list per language. Only fires when the app is in the background, limited to one every 3 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Remind me 1 minute before upcoming meetings", isOn: $appState.notifyOnUpcomingMeeting)
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

                Section("Google Calendar") {
                    Toggle("Enable Google Calendar", isOn: $appState.googleCalendarEnabled)
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
                                        .font(.system(size: 12, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } else {
                                    Text("connected")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("not connected")
                                    .font(.system(size: 12, design: .monospaced))
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
                            Text("Show a 15-second countdown when a calendar meeting starts. Dismiss to skip. Only fires while Miniti is open in the foreground.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Toggle("Auto-stop after meeting ends", isOn: $appState.autoStopFromCalendar)
                            Text("Automatically stop recording when the calendar event ends and no one is speaking.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Webhooks") {
                    TextField("Webhook URL", text: $appState.webhookURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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

                DocsMCPSettingsSection_iOS()

                Section("Diagnostics") {
                    Toggle("Share Diagnostics", isOn: $shareDiagnostics)
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
                    Link(destination: URL(string: "https://miniti.app/privacy")!) {
                        HStack {
                            Text("Privacy")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(ColorPalette.Background.primary)
            .sheet(isPresented: $showDebugLog) {
                DebugLogView()
            }
        }
        .preferredColorScheme(.dark)
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
                Text("These words and phrases are tracked in training mode. The list updates when you change the default language in Settings.")
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
                        
                        Button(role: .destructive) {
                            removeFiller(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
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
    @State private var dictionaryTerms: [String] = []
    @State private var newDictionaryTerm = ""
    @State private var editingIndex: Int?
    @State private var editingText = ""
    @State private var validationMessage: String?

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

                        Button(role: .destructive) {
                            removeDictionaryTerm(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
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

            Section("Summary") {
                HStack {
                    Text("Personal terms")
                    Spacer()
                    Text("\(dictionaryTerms.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Personal Dictionary")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dictionaryTerms = PersonalDictionaryPreferences.currentTerms()
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
                        .font(.system(size: 13, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField(placeholder, text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }
                
                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
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
            Text("HTTPS Streamable HTTP MCP server for product docs. In the Docs insights tab, tap look up when you want answers with citations. Example: https://docs.lightdash.com/mcp")
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
