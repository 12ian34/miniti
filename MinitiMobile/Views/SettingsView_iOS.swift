import SwiftUI
import AVFoundation

struct SettingsView_iOS: View {
    @EnvironmentObject var appState: AppState
    @State private var versionTapCount = 0
    @State private var lastVersionTap: Date?
    @State private var showDebugLog = false
    @State private var showRestoreSheet = false
    @State private var licenseKeyInput = ""
    @State private var isRestoring = false
    @State private var restoreError: String?
    
    var body: some View {
        NavigationStack {
            Form {
                // Account section
                Section("Mode") {
                    Picker("API Mode", selection: $appState.appModeRaw) {
                        Text(appState.isPro ? "Miniti Pro (5,000 min/month)" : "Miniti Free (500 min/month)").tag(AppMode.managed.rawValue)
                        Text("Bring Your Own Keys").tag(AppMode.byok.rawValue)
                    }
                    .onChange(of: appState.appModeRaw) { _, newValue in
                        if newValue == AppMode.managed.rawValue {
                            Task { await appState.refreshUsage() }
                        }
                    }
                    
                    Text(appState.appMode == .managed
                         ? (appState.isPro
                            ? "Pro subscription active. \(Int(appState.usageInfo?.minutesLimit ?? 5000)) minutes per month."
                            : "500 free minutes per month via Miniti's backend.")
                         : "Use your own Deepgram & OpenAI API keys. No limits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if appState.appMode == .managed {
                    Section("Subscription") {
                        HStack {
                            Text("Plan")
                            Spacer()
                            if appState.isPro {
                                Text("Pro — \(Int(appState.usageInfo?.minutesLimit ?? 5000)) min/month")
                                    .foregroundStyle(.purple)
                                    .fontWeight(.medium)
                            } else {
                                Text("Free — 500 min/month")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if appState.isPro {
                            Button("Manage Subscription") {
                                Task { await appState.openManageSubscriptionPage() }
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
                
                // Models
                Section("Models") {
                    Picker("Transcription", selection: $appState.deepgramModel) {
                        Text("Nova-2").tag(DeepgramModel.nova2.rawValue)
                        Text("Nova-3").tag(DeepgramModel.nova3.rawValue)
                    }
                    
                    Picker("Insights", selection: $appState.openaiModel) {
                        Text("GPT-5 Mini").tag(OpenAIModel.gpt5Mini.rawValue)
                        Text("GPT-5 Nano").tag(OpenAIModel.gpt5Nano.rawValue)
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
                    Link(destination: URL(string: "https://ianahuja.com/miniti/privacy/")!) {
                        HStack {
                            Text("Privacy & Terms")
                            Spacer()
                            Image(systemName: "arrow.up.right")
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
            .sheet(isPresented: $showRestoreSheet) {
                NavigationStack {
                    Form {
                        Section {
                            Text("Enter the license key from your purchase email or Polar account.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            TextField("License key", text: $licenseKeyInput)
                                .font(.system(.body, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            
                            if let restoreError {
                                Text(restoreError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        
                        Section {
                            Button {
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
                            } label: {
                                if isRestoring {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                } else {
                                    Text("Restore")
                                }
                            }
                            .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRestoring)
                        }
                    }
                    .navigationTitle("Restore Subscription")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showRestoreSheet = false
                                licenseKeyInput = ""
                                restoreError = nil
                            }
                        }
                    }
                }
                .preferredColorScheme(.dark)
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
