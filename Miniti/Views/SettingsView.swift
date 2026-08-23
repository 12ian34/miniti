import SwiftUI
import SwiftData
import ServiceManagement
import AppKit
import AVFoundation
import UniformTypeIdentifiers

struct SettingsSearchFocusActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var settingsSearchFocusAction: (() -> Void)? {
        get { self[SettingsSearchFocusActionKey.self] }
        set { self[SettingsSearchFocusActionKey.self] = newValue }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedDestination: SettingsDestination = .general
    @FocusState private var isSearchFocused: Bool

    private var searchResults: [SettingsSearchItem] {
        SettingsSearchCatalog.availableItems(on: .macOS, appMode: appState.appMode)
            .filter { $0.matches(searchText) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search settings", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear settings search")
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .padding(10)

                Divider()

            List(selection: $selectedDestination) {
                if searchText.isEmpty {
                    Section("Settings") {
                        destinationRow(.general)
                        destinationRow(.recording)
                        destinationRow(.language)
                        destinationRow(.ai)
                        destinationRow(.notifications)
                    }

                    Section("Account") {
                        destinationRow(.account)
                    }

                    Section("Connections") {
                        destinationRow(.calendar)
                        destinationRow(.crm)
                        destinationRow(.webhooks)
                        destinationRow(.docsMCP)
                    }

                    Section("Files") {
                        destinationRow(.dataExport)
                    }

                    Section("Support") {
                        destinationRow(.privacySupport)
                    }
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    Section("Results") {
                        ForEach(searchResults) { item in
                            Button {
                                openSearchResult(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .foregroundStyle(.primary)
                                    Text(item.breadcrumb)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            }
            .frame(width: 230)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(selectedDestination.title)
                        .font(.title2.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .frame(height: 52)

                Divider()

                settingsDetail(for: selectedDestination)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, idealWidth: 880, minHeight: 520, idealHeight: 600)
        .focusedSceneValue(\.settingsSearchFocusAction) {
            isSearchFocused = true
        }
        .onAppear {
            selectedDestination = SettingsDestination.fromLegacyID(appState.selectedSettingsTab)
        }
        .onChange(of: selectedDestination) { _, destination in
            guard appState.selectedSettingsTab != destination.rawValue else { return }
            appState.selectedSettingsTab = destination.rawValue
            appState.pendingSettingsSearchTarget = nil
        }
        .onChange(of: appState.selectedSettingsTab) { _, destinationID in
            let destination = SettingsDestination.fromLegacyID(destinationID)
            guard selectedDestination != destination else { return }
            selectedDestination = destination
        }
        .onReceive(NotificationCenter.default.publisher(for: .minitiGoogleOAuthCallback)) { notification in
            guard let callbackURL = notification.userInfo?["url"] as? URL else { return }
            Task { @MainActor in
                await appState.handleGoogleOAuthCallback(callbackURL)
            }
        }
    }

    @ViewBuilder
    private func destinationRow(_ destination: SettingsDestination) -> some View {
        Label(destination.title, systemImage: destination.systemImage)
            .tag(destination)
    }

    @ViewBuilder
    private func settingsDetail(for destination: SettingsDestination) -> some View {
        switch destination {
        case .general:
            GeneralSettingsView()
        case .account:
            AccountSettingsView()
        case .recording:
            AudioSettingsView()
        case .language:
            LanguageSettingsView()
        case .ai:
            AISettingsView()
        case .notifications:
            NotificationsSettingsView()
        case .calendar:
            IntegrationsSettingsView(content: .calendar)
        case .crm:
            IntegrationsSettingsView(content: .crm)
        case .webhooks:
            IntegrationsSettingsView(content: .webhooks)
        case .docsMCP:
            IntegrationsSettingsView(content: .docsMCP)
        case .dataExport:
            IntegrationsSettingsView(content: .dataExport)
        case .privacySupport:
            AboutSettingsView()
        }
    }

    private func openSearchResult(_ item: SettingsSearchItem) {
        selectedDestination = item.destination
        appState.pendingSettingsSearchTarget = nil
        DispatchQueue.main.async {
            appState.pendingSettingsSearchTarget = item.id
        }
    }
}

private struct SettingsScrollTargetModifier: ViewModifier {
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
    func settingsSearchScrolling(for destination: SettingsDestination) -> some View {
        modifier(SettingsScrollTargetModifier(destination: destination))
    }
}

// MARK: - Account Settings (Mode + Usage)

struct AccountSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showRestoreSheet = false
    @State private var licenseKeyInput = ""
    @State private var isRestoring = false
    @State private var restoreError: String?
    
    var body: some View {
        Form {
            Section("Mode") {
                Picker("API Mode", selection: $appState.appModeRaw) {
                    Text(appState.isPro ? "Miniti Pro (5,000 min/month)" : "Miniti Free (500 min/month)").tag(AppMode.managed.rawValue)
                    Text("Bring Your Own Keys (unlimited)").tag(AppMode.byok.rawValue)
                }
                .id("account.apiMode")
                .pickerStyle(.radioGroup)
                .onChange(of: appState.appModeRaw) { _, newValue in
                    if newValue == AppMode.managed.rawValue {
                        Task { await appState.refreshUsage() }
                    }
                }
                
                Text(appState.appMode == .managed
                     ? (appState.isPro
                        ? "Pro subscription active. \(Int(appState.usageInfo?.minutesLimit ?? 5000)) minutes per month."
                        : "API calls routed through Miniti's backend. 500 free minutes per month.")
                     : "Use your own Deepgram & OpenAI API keys. No limits, no tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if appState.appMode == .managed {
                Section("Subscription") {
                    if appState.isPro {
                        HStack {
                            Text("Plan")
                            Spacer()
                            Text("Pro — \(Int(appState.usageInfo?.minutesLimit ?? 5000)) min/month")
                                .foregroundStyle(Color(hex: "A78BFA"))
                                .fontWeight(.medium)
                        }
                        
                        Button("Manage Subscription") {
                            Task { await appState.openManageSubscriptionPage() }
                        }
                    } else {
                        HStack {
                            Text("Plan")
                            Spacer()
                            Text("Free — 500 min/month")
                                .foregroundStyle(.secondary)
                        }
                        
                        Button("Upgrade to Pro ($5/month — 5,000 min)") {
                            Task { await appState.openSubscribePage() }
                        }
                    }
                    
                    Button("Restore with License Key") {
                        showRestoreSheet = true
                    }
                }
                .id("account.subscription")
                
                Section("Usage") {
                    if let usage = appState.usageInfo {
                        HStack {
                            Text("Minutes Used")
                            Spacer()
                            Text("\(Int(usage.minutesUsed.rounded())) / \(Int(usage.minutesLimit))")
                                .foregroundStyle(.secondary)
                        }
                        
                        ProgressView(value: usage.usagePercentage)
                            .tint(usage.isPro ? .purple : (usage.minutesRemaining < 60 ? .orange : .green))
                        
                        HStack {
                            Text("Remaining")
                            Spacer()
                            Text(usage.formattedRemaining)
                                .foregroundStyle(usage.minutesRemaining < 60 ? .orange : (usage.isPro ? .purple : .green))
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
                                .controlSize(.small)
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
            }

            if appState.appMode == .byok {
                APISettingsView()
            }
            
            Section("Device") {
                HStack {
                    Text("Device ID")
                    Spacer()
                    Text(DeviceIdentifier.getOrCreateDeviceId())
                        .foregroundStyle(.secondary)
                        .font(.system(.caption, design: .default))
                        .textSelection(.enabled)
                }
                .id("account.deviceID")
            }
        }
        .formStyle(.grouped)
        .padding()
        .settingsSearchScrolling(for: .account)
        .sheet(isPresented: $showRestoreSheet) {
            RestoreLicenseKeySheet(
                licenseKeyInput: $licenseKeyInput,
                isRestoring: $isRestoring,
                restoreError: $restoreError,
                onRestore: {
                    isRestoring = true
                    restoreError = nil
                    Task {
                        let success = await appState.restoreSubscription(licenseKey: licenseKeyInput)
                        isRestoring = false
                        if success {
                            showRestoreSheet = false
                            licenseKeyInput = ""
                        } else {
                            restoreError = "Invalid or expired license key"
                        }
                    }
                },
                onCancel: {
                    showRestoreSheet = false
                    licenseKeyInput = ""
                    restoreError = nil
                }
            )
        }
    }
}

struct LanguageSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var fillers: [String] = []
    @State private var newFiller = ""
    @State private var editingIndex: Int?
    @State private var editingText = ""
    @State private var validationMessage: String?
    @State private var dictionaryTerms: [String] = []
    @State private var newDictionaryTerm = ""
    @State private var editingDictionaryIndex: Int?
    @State private var editingDictionaryText = ""
    @State private var dictionaryValidationMessage: String?
    
    var body: some View {
        Form {
            Section("Default Language") {
                Picker("Language", selection: $appState.defaultLanguage) {
                    ForEach(TranscriptionLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .id("language.default")
                .onChange(of: appState.defaultLanguage) { _, newLang in
                    fillers = TrainingFillerPreferences.currentFillers(for: newLang)
                    validationMessage = nil
                }
                
                Text("Transcription, insights, and filler detection all use this language. Changing the language updates the filler list below. Can be overridden per meeting before recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Personal Dictionary") {
                Text("Add product names, customer names, acronyms, or uncommon words that Deepgram should treat as real terms. Used when a new recording connects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(dictionaryTerms.enumerated()), id: \.offset) { index, term in
                    HStack {
                        Text(term)
                            .textSelection(.enabled)
                        Spacer()

                        Button {
                            editingDictionaryIndex = index
                            editingDictionaryText = term
                            dictionaryValidationMessage = nil
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit \(term)")
                        .help("Edit \(term)")

                        Button(role: .destructive) {
                            removeDictionaryTerm(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(term)")
                        .help("Delete \(term)")
                    }
                }

                HStack {
                    TextField("Add word (example: Lightdash)", text: $newDictionaryTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addDictionaryTerm()
                        }

                    Button("Add") {
                        addDictionaryTerm()
                    }
                    .disabled(newDictionaryTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let dictionaryValidationMessage {
                    Text(dictionaryValidationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Personal terms")
                    Spacer()
                    Text("\(dictionaryTerms.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .id("language.dictionary")
            
            Section("Filler Detection") {
                Text("These words and phrases are tracked in Coaching across live and saved meetings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                ForEach(Array(fillers.enumerated()), id: \.offset) { index, filler in
                    HStack {
                        Text(filler)
                            .textSelection(.enabled)
                        Spacer()
                        
                        Button {
                            editingIndex = index
                            editingText = filler
                            validationMessage = nil
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit \(filler)")
                        .help("Edit \(filler)")
                        
                        Button(role: .destructive) {
                            removeFiller(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(filler)")
                        .help("Delete \(filler)")
                    }
                }
                
                HStack {
                    TextField("Add phrase (example: i think)", text: $newFiller)
                        .textFieldStyle(.roundedBorder)
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
            .id("language.fillers")
            
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
        .formStyle(.grouped)
        .padding()
        .settingsSearchScrolling(for: .language)
        .onAppear {
            fillers = TrainingFillerPreferences.currentFillers(for: appState.defaultLanguage)
            dictionaryTerms = PersonalDictionaryPreferences.currentTerms()
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
        .alert("Edit dictionary term", isPresented: Binding(
            get: { editingDictionaryIndex != nil },
            set: { showing in
                if !showing {
                    editingDictionaryIndex = nil
                    editingDictionaryText = ""
                }
            }
        )) {
            TextField("Term", text: $editingDictionaryText)
            Button("Cancel", role: .cancel) {
                editingDictionaryIndex = nil
                editingDictionaryText = ""
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
        dictionaryValidationMessage = nil
    }

    private func removeDictionaryTerm(at index: Int) {
        guard dictionaryTerms.indices.contains(index) else { return }
        dictionaryTerms.remove(at: index)
        persistDictionaryTerms()
        dictionaryValidationMessage = nil
    }

    private func saveEditedDictionaryTerm() {
        guard let editingDictionaryIndex, dictionaryTerms.indices.contains(editingDictionaryIndex) else { return }
        let trimmed = editingDictionaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dictionaryValidationMessage = "Dictionary term cannot be empty."
            return
        }
        dictionaryTerms[editingDictionaryIndex] = trimmed
        self.editingDictionaryIndex = nil
        editingDictionaryText = ""
        persistDictionaryTerms()
        dictionaryValidationMessage = nil
    }

    private func persistDictionaryTerms() {
        dictionaryTerms = PersonalDictionaryPreferences.normalizedTerms(dictionaryTerms)
        PersonalDictionaryPreferences.save(dictionaryTerms)
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

struct AISettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Models") {
                HStack {
                    Text("Transcription")
                    Spacer()
                    Text("Deepgram Nova-3")
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top) {
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
                     ? "Transcription and insights use the Deepgram and OpenAI keys saved under Account & Plan. Calendar, CRM, webhooks, Docs MCP, and Smart meetings remain available in BYOK mode."
                     : "Miniti supplies the transcription and insight providers for your plan. Integration and meeting-automation settings work the same way as in BYOK mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Meeting Investigations") {
                LabeledContent("Codebase folder") {
                    HStack(spacing: 8) {
                        Text(appState.investigationCodebaseFolderName ?? "Not configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300, alignment: .trailing)

                        Button("Choose…") {
                            chooseInvestigationCodebaseFolder()
                        }

                        if appState.investigationCodebaseFolderName != nil {
                            Button {
                                appState.clearInvestigationCodebaseFolder()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Clear investigation codebase folder")
                        }
                    }
                }

                Text("Investigations run inside Miniti with OpenAI only when you click. Web research includes clickable citations. Codebase investigation reads a bounded set of relevant excerpts from the folder you choose; OpenAI never receives unrestricted filesystem access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id("ai.investigations")
        }
        .formStyle(.grouped)
        .padding()
        .settingsSearchScrolling(for: .ai)
    }

    private func chooseInvestigationCodebaseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the codebase Miniti may search for explicitly requested OpenAI investigations."
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try appState.setInvestigationCodebaseFolder(url)
            } catch {
                DebugLogger.shared.log(.app, "Could not save investigation codebase permission: \(error.localizedDescription)")
            }
        }
    }
}

struct APISettingsView: View {
    @AppStorage("deepgramApiKey") private var deepgramApiKey: String = ""
    @AppStorage("openaiApiKey") private var openaiApiKey: String = ""
    
    @State private var showDeepgramKey = false
    @State private var showOpenAIKey = false
    @State private var isTestingDeepgram = false
    @State private var isTestingOpenAI = false
    @State private var deepgramStatus: TestStatus = .none
    @State private var openaiStatus: TestStatus = .none
    @State private var showDeepgramInfo = false
    @State private var showOpenAIInfo = false
    
    enum TestStatus {
        case none, success, failure
    }
    
    var body: some View {
        Group {
            Section("API Keys") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 6) {
                        Text("Deepgram API Key")
                            .font(.headline)
                        
                        Button {
                            showDeepgramInfo.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("About Deepgram API keys")
                        .help("About Deepgram API keys")
                        .popover(isPresented: $showDeepgramInfo, arrowEdge: .trailing) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Deepgram")
                                    .font(.headline)
                                Text("Powers real-time speech-to-text transcription with speaker diarization (who said what).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Divider()
                                
                                Text("How to get your key:")
                                    .font(.caption.bold())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("1. Create a free account at deepgram.com")
                                    Text("2. Go to Settings → API Keys")
                                    Text("3. Click \"Create a New API Key\"")
                                    Text("4. Copy and paste it here")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                
                                HStack(spacing: 12) {
                                    Link(destination: URL(string: "https://console.deepgram.com/signup")!) {
                                        Label("Sign Up", systemImage: "person.badge.plus")
                                            .font(.caption.bold())
                                    }
                                    Link(destination: URL(string: "https://console.deepgram.com/project/keys")!) {
                                        Label("API Keys", systemImage: "key")
                                            .font(.caption.bold())
                                    }
                                }
                                .padding(.top, 2)
                                
                                Text("Free tier includes $200 in credit.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .frame(width: 260)
                        }
                    }
                    Text("Used for real-time speech-to-text transcription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        if showDeepgramKey {
                            TextField("Enter your Deepgram API key", text: $deepgramApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Enter your Deepgram API key", text: $deepgramApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button {
                            showDeepgramKey.toggle()
                        } label: {
                            Image(systemName: showDeepgramKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(showDeepgramKey ? "Hide Deepgram API key" : "Show Deepgram API key")
                        .help(showDeepgramKey ? "Hide API key" : "Show API key")
                        
                        Button {
                            testDeepgramKey()
                        } label: {
                            if isTestingDeepgram {
                                ProgressView()
                                    .scaleEffect(0.5)
                            } else {
                                Text("Test")
                            }
                        }
                        .disabled(deepgramApiKey.isEmpty || isTestingDeepgram)
                    }
                    
                    if deepgramStatus == .success {
                        Label("API key is valid", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if deepgramStatus == .failure {
                        Label("API key is invalid. Check the key and try again.", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(.bottom, 8)
                .id("account.deepgramKey")
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 6) {
                        Text("OpenAI API Key")
                            .font(.headline)
                        
                        Button {
                            showOpenAIInfo.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("About OpenAI API keys")
                        .help("About OpenAI API keys")
                        .popover(isPresented: $showOpenAIInfo, arrowEdge: .trailing) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("OpenAI")
                                    .font(.headline)
                                Text("Powers summaries, action items, questions, and any specialist insights you enable.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Divider()
                                
                                Text("How to get your key:")
                                    .font(.caption.bold())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("1. Sign in at platform.openai.com")
                                    Text("2. Go to API Keys in the sidebar")
                                    Text("3. Click \"Create new secret key\"")
                                    Text("4. Copy and paste it here")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                
                                HStack(spacing: 12) {
                                    Link(destination: URL(string: "https://platform.openai.com/signup")!) {
                                        Label("Sign Up", systemImage: "person.badge.plus")
                                            .font(.caption.bold())
                                    }
                                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                                        Label("API Keys", systemImage: "key")
                                            .font(.caption.bold())
                                    }
                                }
                                .padding(.top, 2)
                                
                                Text("Optional — only needed for AI insights.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .frame(width: 260)
                        }
                    }
                    Text("Used for generating meeting insights")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        if showOpenAIKey {
                            TextField("Enter your OpenAI API key", text: $openaiApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Enter your OpenAI API key", text: $openaiApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button {
                            showOpenAIKey.toggle()
                        } label: {
                            Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(showOpenAIKey ? "Hide OpenAI API key" : "Show OpenAI API key")
                        .help(showOpenAIKey ? "Hide API key" : "Show API key")
                        
                        Button {
                            testOpenAIKey()
                        } label: {
                            if isTestingOpenAI {
                                ProgressView()
                                    .scaleEffect(0.5)
                            } else {
                                Text("Test")
                            }
                        }
                        .disabled(openaiApiKey.isEmpty || isTestingOpenAI)
                    }
                    
                    if openaiStatus == .success {
                        Label("API key is valid", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if openaiStatus == .failure {
                        Label("API key is invalid. Check the key and try again.", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .id("account.openAIKey")
            }
        }
    }
    
    private func testDeepgramKey() {
        isTestingDeepgram = true
        deepgramStatus = .none
        
        Task {
            do {
                var request = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
                request.setValue("Token \(deepgramApiKey)", forHTTPHeaderField: "Authorization")
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    deepgramStatus = .success
                } else {
                    deepgramStatus = .failure
                }
            } catch {
                deepgramStatus = .failure
            }
            isTestingDeepgram = false
        }
    }
    
    private func testOpenAIKey() {
        isTestingOpenAI = true
        openaiStatus = .none
        
        Task {
            do {
                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                request.setValue("Bearer \(openaiApiKey)", forHTTPHeaderField: "Authorization")
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    openaiStatus = .success
                } else {
                    openaiStatus = .failure
                }
            } catch {
                openaiStatus = .failure
            }
            isTestingOpenAI = false
        }
    }
}

struct AudioSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("captureSystemAudio") private var captureSystemAudio: Bool = true
    @AppStorage("captureMicrophone") private var captureMicrophone: Bool = true
    
    var body: some View {
        Form {
            Section("Audio Sources") {
                Toggle("Capture Microphone", isOn: $captureMicrophone)
                    .id("recording.microphone")
                Text("Record audio from your microphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Toggle("Capture System Audio", isOn: $captureSystemAudio)
                    .id("recording.systemAudio")
                Text("Record audio from other applications (e.g., video calls)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Permissions") {
                HStack {
                    Text("Microphone Access")
                    Spacer()
                    PermissionStatusBadge(granted: checkMicrophonePermission())
                }
                
                HStack {
                    Text("System Audio")
                    Spacer()
                    Text("Check in System Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }
            .id("recording.permissions")

            Section("Recording") {
                Picker("Auto-stop after silence", selection: $appState.autoStopMinutes) {
                    Text("Off").tag(0)
                    Text("3 minutes").tag(3)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                }
                .id("recording.autoStop")
                Text("Advanced fallback: stops recording after prolonged silence. Intended for in-person meetings and unsupported call apps — supported calls end automatically when the call ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-name speakers from transcript", isOn: $appState.autoInferSpeakerNames)
                    .id("recording.autoNameSpeakers")
                Text("Detects real names from the conversation and labels each speaker accordingly in the live and saved transcripts. When Google Calendar is connected, attendee names are used as hints. Remains \"You\"/\"Speaker N\" until a name is confident.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .settingsSearchScrolling(for: .recording)
    }
    
    private func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

struct PermissionStatusBadge: View {
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

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .id("general.launchAtLogin")
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Appearance") {
                Toggle("Show in Menu Bar", isOn: $showInMenuBar)
                    .id("general.showInMenuBar")
                Text(showInMenuBar
                     ? "Miniti icon is shown in the menu bar."
                     : "Turn this back on to restore the Miniti menu bar icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show recording indicator", isOn: $appState.showRecordingIndicator)
                    .id("general.recordingIndicator")
                Text("Floating strip with the recording timer and controls, visible even when the main window is closed. Independent of Smart meetings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                InterfaceScaleSlider()
                    .id("general.interfaceScale")
            }
        }
        .formStyle(.grouped)
        .padding()
        .settingsSearchScrolling(for: .general)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DebugLogger.shared.log(.app, "Launch at login update FAILED: \(error.localizedDescription)")
        }
    }
}

struct NotificationsSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Meeting Nudges") {
                Toggle("Notify me about incisive questions", isOn: $appState.notifyOnIncisiveQuestions)
                    .id("notifications.questions")
                    .onChange(of: appState.notifyOnIncisiveQuestions) { _, newValue in
                        if newValue {
                            appState.requestQuestionNotificationPermission()
                        }
                    }
                Text("Shows a floating prompt while you're using Miniti, or a system notification when your attention is elsewhere or the recording indicator is off. Limited to one every 2 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Nudge me when I'm monologuing", isOn: $appState.notifyOnMonologue)
                    .id("notifications.monologue")
                    .onChange(of: appState.notifyOnMonologue) { _, newValue in
                        if newValue {
                            appState.requestNudgeNotificationPermission()
                        }
                    }
                Text("Gently alerts you if you've been talking for roughly a minute or more without interruption. Uses the floating recording surface in Miniti and a system notification elsewhere, limited to one every 3 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Nudge me when I'm using too many fillers", isOn: $appState.notifyOnHighFillerRate)
                    .id("notifications.fillers")
                    .onChange(of: appState.notifyOnHighFillerRate) { _, newValue in
                        if newValue {
                            appState.requestNudgeNotificationPermission()
                        }
                    }
                Text("Alerts you when filler words like \"um\" and \"uh\" spike in your last minute of speaking. Uses your configured filler list per language, the floating recording surface in Miniti, and a system notification elsewhere. Limited to one every 3 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Suggest Sales analysis when a meeting sounds like a sales call", isOn: $appState.notifyOnSalesDetection)
                    .id("notifications.salesDetection")
                Text("When Sales analysis is off and the conversation mentions several commercial terms (pricing, contract, procurement, …), offers to enable live MEDDPICC analysis. At most once per meeting; detection runs locally on your transcript.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Calendar Reminders") {
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
                Text("Fires a system notification about 60 seconds before each upcoming Google Calendar event starts. Requires Google Calendar to be connected. In addition to Calendar's own alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Meeting Decisions") {
                Text("Smart meeting start, ending, and handoff decisions raise the floating recording surface. When Miniti is behind another app or the surface is turned off, an actionable system notification is used when notification permission is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .settingsSearchScrolling(for: .notifications)
    }
}

enum IntegrationsSettingsContent: Equatable {
    case calendar
    case crm
    case webhooks
    case docsMCP
    case dataExport

    var destination: SettingsDestination {
        switch self {
        case .calendar: return .calendar
        case .crm: return .crm
        case .webhooks: return .webhooks
        case .docsMCP: return .docsMCP
        case .dataExport: return .dataExport
        }
    }
}

struct IntegrationsSettingsView: View {
    let content: IntegrationsSettingsContent
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("attioExportEnabled") private var attioExportEnabled: Bool = false
    @AppStorage("twentyExportEnabled") private var twentyExportEnabled: Bool = false
    @AppStorage("autoExportMarkdown") private var autoExportMarkdown: Bool = false
    @AppStorage("markdownExportFolderPath") private var markdownExportFolderPath: String = ""
    @AppStorage("generateAgentsMd") private var generateAgentsMd: Bool = false
    @State private var isExportingAll = false
    @State private var exportAllCount: Int?
    @State private var isGranolaImporterPresented = false
    @State private var isImportingGranola = false
    @State private var granolaImportMessage: String?
    @State private var granolaImportFailed = false

    var body: some View {
        Form {
            if content == .dataExport {
            Section("Import from Granola") {
                Text("Generate a CSV from Granola, then import it into Miniti. Imported meetings keep their Granola provenance, and importing the same export again skips duplicates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Link(destination: GranolaCSVImporter.exportURL) {
                        Label("Export meetings in Granola", systemImage: "arrow.up.right.square")
                    }

                    Spacer()

                    Button {
                        isGranolaImporterPresented = true
                    } label: {
                        if isImportingGranola {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("importing…")
                            }
                        } else {
                            Label("Import CSV…", systemImage: "tray.and.arrow.down")
                        }
                    }
                    .disabled(isImportingGranola)
                }

                if let granolaImportMessage {
                    Label(
                        granolaImportMessage,
                        systemImage: granolaImportFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(granolaImportFailed ? ColorPalette.Status.error : ColorPalette.Accent.green)
                }

                Text("Granola opens Profile → Account management. Choose Generate CSV; Granola emails the download when it is ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id("data.granola")

            Section("Markdown Export") {
                HStack {
                    Text(resolvedExportPath)
                        .font(.system(size: 11, design: .default))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose Folder") {
                        chooseExportFolder()
                    }
                }
                .id("data.markdownFolder")

                Toggle("Auto-export meetings as markdown", isOn: $autoExportMarkdown)
                    .id("data.autoExport")
                Text("Automatically saves each meeting as a markdown file. Works with Obsidian, Cursor, and other tools.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if autoExportMarkdown {
                    Toggle("Generate AGENTS.md index", isOn: $generateAgentsMd)
                    Text("Maintains an AGENTS.md file listing all exported meetings for AI agents.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        exportAllMeetings()
                    } label: {
                        if isExportingAll {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("exporting…")
                            }
                        } else if let count = exportAllCount {
                            Text("exported \(count) meeting\(count == 1 ? "" : "s")")
                                .foregroundStyle(ColorPalette.Accent.green)
                        } else {
                            Text("Export All Meetings")
                        }
                    }
                    .disabled(isExportingAll)
                    .id("data.exportAll")
                }
            }
            }

            if content == .calendar {
            Section("Calendar & Meeting Automation") {
                Toggle("Smart meetings", isOn: $appState.smartMeetingsEnabled)
                    .id("integrations.smartMeetings")
                Text("Detects calls from apps like Zoom, Teams, Meet and Slack, keeps recordings separated, and finishes when a call ends — after a visible, cancellable countdown. Works with or without Google Calendar.")
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
                                    .foregroundStyle(.primary)
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
                        Text("Show a 15-second countdown when a calendar meeting starts. Dismiss to skip.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Toggle("Auto-stop after meeting ends", isOn: $appState.autoStopFromCalendar)
                            .id("integrations.calendarAutoStop")
                        Text("Advanced fallback: stop when the calendar event ends and no one is speaking. Supported calls already end automatically when the call ends.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                }
            }

            }

            if content == .crm {
            Section("Attio CRM") {
                Toggle("Enable \"Send to Attio\"", isOn: $attioExportEnabled)
                Text(attioExportEnabled
                     ? "\"Send to Attio\" is available in saved meeting history."
                     : "\"Send to Attio\" is hidden until you enable it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if attioExportEnabled {
                    Toggle("Auto-sync calendar meetings to Attio", isOn: $appState.autoAttioSync)
                        .disabled(!appState.isGoogleCalendarConnected)
                    Text(appState.isGoogleCalendarConnected
                         ? "Automatically match attendee domains to Attio records and send meeting data after saving."
                         : "Connect Google Calendar under Calendar & Meetings to enable automatic Attio sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .id("integrations.attio")

            Section("Twenty CRM") {
                Toggle("Enable \"Send to Twenty\"", isOn: $twentyExportEnabled)
                Text(twentyExportEnabled
                     ? "\"Send to Twenty\" is available in saved meeting history."
                     : "\"Send to Twenty\" is hidden until you enable it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if twentyExportEnabled {
                    Toggle("Auto-sync calendar meetings to Twenty", isOn: $appState.autoTwentySync)
                        .disabled(!appState.isGoogleCalendarConnected)
                    Text(appState.isGoogleCalendarConnected
                         ? "Automatically match attendee domains to Twenty companies and send meeting data after saving."
                         : "Connect Google Calendar under Calendar & Meetings to enable automatic Twenty sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .id("integrations.twenty")
            }

            if content == .webhooks {
            Section("Webhooks") {
                TextField("Webhook URL", text: $appState.webhookURL)
                    .textFieldStyle(.roundedBorder)
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

            if content == .docsMCP {
            DocsMCPSettingsSection()
                .id("integrations.docsMCP")
            }
        }
        .formStyle(.grouped)
        .padding()
        .settingsSearchScrolling(for: content.destination)
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
    }

    private var resolvedExportPath: String {
        markdownExportFolderPath.isEmpty
            ? NSString("~/Documents/miniti").expandingTildeInPath
            : markdownExportFolderPath
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
                if result.imported > 0 {
                    NotificationCenter.default.post(name: .minitiMeetingsImported, object: nil)
                }
            } catch {
                granolaImportFailed = true
                granolaImportMessage = error.localizedDescription
                DebugLogger.shared.log(.app, "Granola CSV import FAILED: \(error.localizedDescription)")
            }
            isImportingGranola = false
        }
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a folder for exported meeting markdown files"
        if panel.runModal() == .OK, let url = panel.url {
            appState.saveExportFolderBookmark(for: url)
        }
    }

    private func exportAllMeetings() {
        isExportingAll = true
        exportAllCount = nil
        let descriptor = FetchDescriptor<Meeting>()
        guard let meetings = try? modelContext.fetch(descriptor) else {
            DebugLogger.shared.log(.app, "Export all: failed to fetch meetings from modelContext")
            isExportingAll = false
            return
        }
        let finalized = meetings.filter { $0.endTime != nil && !$0.segments.isEmpty }
        DebugLogger.shared.log(.app, "Export all: \(meetings.count) total, \(finalized.count) finalized")
        for meeting in finalized {
            let markdown = meeting.fullMeetingAsMarkdown()
            appState.exportMeetingAsMarkdownFile(markdown: markdown, meeting: meeting)
        }
        isExportingAll = false
        exportAllCount = finalized.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            exportAllCount = nil
        }
    }
}

private struct DocsMCPSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false

    var body: some View {
        Section("Docs MCP") {
            TextField("Docs MCP URL", text: $appState.docsMCPURL)
                .textFieldStyle(.roundedBorder)
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
            HStack {
                Button(isTesting ? "testing…" : "Test Connection") {
                    Task { await testConnection() }
                }
                .disabled(isTesting || appState.validatedDocsMCPURL == nil)
                if let testMessage {
                    Text(testMessage)
                        .font(.caption)
                        .foregroundStyle(testSucceeded ? ColorPalette.Accent.green : ColorPalette.Status.error)
                        .lineLimit(2)
                }
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

struct AboutSettingsView: View {
    @AppStorage("shareDiagnostics") private var shareDiagnostics: Bool = false
    @State private var versionTapCount = 0
    @State private var lastVersionTap: Date?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Share Diagnostics", isOn: $shareDiagnostics)
                    .id("privacy.diagnostics")
                Text("Sends structured reliability events (errors, reconnects, health states) with no transcript or audio content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
            }
        }
        .formStyle(.grouped)
        .padding()
        .settingsSearchScrolling(for: .privacySupport)
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
            openWindow(id: "debug-log")
            versionTapCount = 0
        }
    }
}

#Preview {
    SettingsView()
}
