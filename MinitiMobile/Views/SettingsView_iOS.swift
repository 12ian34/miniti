import SwiftUI
import AVFoundation

struct SettingsView_iOS: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            Form {
                // Account section
                Section("Mode") {
                    Picker("API Mode", selection: $appState.appModeRaw) {
                        Text("Miniti Free (500 min/month)").tag(AppMode.managed.rawValue)
                        Text("Bring Your Own Keys").tag(AppMode.byok.rawValue)
                    }
                    .onChange(of: appState.appModeRaw) { _, newValue in
                        if newValue == AppMode.managed.rawValue {
                            Task { await appState.refreshUsage() }
                        }
                    }
                    
                    Text(appState.appMode == .managed
                         ? "500 free minutes per month via Miniti's backend."
                         : "Use your own Deepgram & OpenAI API keys. No limits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Usage (managed mode)
                if appState.appMode == .managed {
                    Section("Usage") {
                        if let usage = appState.usageInfo {
                            HStack {
                                Text("Minutes Used")
                                Spacer()
                                Text("\(Int(usage.minutesUsed.rounded())) / \(Int(usage.minutesLimit))")
                                    .foregroundStyle(.secondary)
                            }
                            
                            ProgressView(value: usage.usagePercentage)
                                .tint(usage.minutesRemaining < 60 ? .orange : .green)
                            
                            HStack {
                                Text("Remaining")
                                Spacer()
                                Text(usage.formattedRemaining)
                                    .foregroundStyle(usage.minutesRemaining < 60 ? .orange : .green)
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
        }
        .preferredColorScheme(.dark)
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
