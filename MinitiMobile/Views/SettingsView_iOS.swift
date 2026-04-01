import SwiftUI
import AVFoundation

struct SettingsView_iOS: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("shareDiagnostics") private var shareDiagnostics: Bool = false
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
