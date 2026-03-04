import SwiftUI
import ServiceManagement
import AppKit
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        TabView {
            AccountSettingsView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
            
            // API Keys tab only shown in BYOK mode — managed users
            // should never see or need the app's backend keys.
            if appState.appMode == .byok {
                APISettingsView()
                    .tabItem {
                        Label("API Keys", systemImage: "key")
                    }
            }
            
            AudioSettingsView()
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }
            
            ModelsSettingsView()
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
            
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
        
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
                            Text("Loading usage...")
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
            }
            
            Section("Device") {
                HStack {
                    Text("Device ID")
                    Spacer()
                    Text(DeviceIdentifier.getOrCreateDeviceId())
                        .foregroundStyle(.secondary)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
        Form {
            Section {
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
                        Label("Invalid API key", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(.bottom, 8)
                
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
                        .popover(isPresented: $showOpenAIInfo, arrowEdge: .trailing) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("OpenAI")
                                    .font(.headline)
                                Text("Powers meeting insights — summaries, action items, key topics, and MEDDPICC analysis.")
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
                        Label("Invalid API key", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
    @AppStorage("captureSystemAudio") private var captureSystemAudio: Bool = true
    @AppStorage("captureMicrophone") private var captureMicrophone: Bool = true
    
    var body: some View {
        Form {
            Section("Audio Sources") {
                Toggle("Capture Microphone", isOn: $captureMicrophone)
                Text("Record audio from your microphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Toggle("Capture System Audio", isOn: $captureSystemAudio)
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
        }
        .formStyle(.grouped)
        .padding()
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

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    private var selectedDeepgramModel: DeepgramModel {
        DeepgramModel(rawValue: appState.deepgramModel) ?? .nova3
    }
    
    private var selectedOpenAIModel: OpenAIModel {
        OpenAIModel(rawValue: appState.openaiModel) ?? .gpt5Mini
    }
    
    var body: some View {
        Form {
            Section("Transcription") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Model", selection: $appState.deepgramModel) {
                        ForEach(DeepgramModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    
                    SettingsModelSummaryCard(
                        title: selectedDeepgramModel.displayName,
                        subtitle: selectedDeepgramModel.shortDescription.capitalized,
                        pros: selectedDeepgramModel.pros.prefix(2).joined(separator: " • "),
                        cons: selectedDeepgramModel.cons.prefix(2).joined(separator: " • ")
                    )
                }
                
                Text("Deepgram model used for real-time speech-to-text transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Insights") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Model", selection: $appState.openaiModel) {
                        ForEach(OpenAIModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    
                    SettingsModelSummaryCard(
                        title: selectedOpenAIModel.displayName,
                        subtitle: selectedOpenAIModel.shortDescription,
                        pros: selectedOpenAIModel.pros.prefix(2).joined(separator: " • "),
                        cons: selectedOpenAIModel.cons.prefix(2).joined(separator: " • ")
                    )
                }
                
                Text("OpenAI model used for generating summaries, action items, and MEDDPICC analysis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct SettingsModelSummaryCard: View {
    let title: String
    let subtitle: String
    let pros: String
    let cons: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Label(pros, systemImage: "plus.circle.fill")
                .foregroundStyle(.secondary)
            
            Label(cons, systemImage: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true
    @AppStorage("attioExportEnabled") private var attioExportEnabled: Bool = false
    @AppStorage("shareDiagnostics") private var shareDiagnostics: Bool = false
    
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
            
            Section("Appearance") {
                Toggle("Show in Menu Bar", isOn: $showInMenuBar)
                Text(showInMenuBar
                     ? "Miniti icon is shown in the menu bar."
                     : "Turn this back on to restore the Miniti menu bar icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Integrations") {
                Toggle("Enable \"Send to Attio\"", isOn: $attioExportEnabled)
                Text(attioExportEnabled
                     ? "\"Send to Attio\" is available in saved meeting history."
                     : "\"Send to Attio\" is hidden until you enable it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                Toggle("Share Diagnostics", isOn: $shareDiagnostics)
                Text("Sends structured reliability events (errors, reconnects, health states) with no transcript or audio content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
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

struct AboutSettingsView: View {
    @State private var versionTapCount = 0
    @State private var lastVersionTap: Date?
    @State private var showDebugLog = false

    var body: some View {
        Form {
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
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showDebugLog) {
            DebugLogView()
                .frame(width: 700, height: 500)
        }
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
}

#Preview {
    SettingsView()
}
