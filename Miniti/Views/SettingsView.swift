import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            APISettingsView()
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }
            
            AudioSettingsView()
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }
            
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 500, height: 350)
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
    
    enum TestStatus {
        case none, success, failure
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deepgram API Key")
                        .font(.headline)
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
                    
                    Link("Get a Deepgram API key", destination: URL(string: "https://console.deepgram.com/signup")!)
                        .font(.caption)
                }
                .padding(.bottom, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI API Key")
                        .font(.headline)
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
                    
                    Link("Get an OpenAI API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
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
                    Text("Screen Recording")
                    Spacer()
                    PermissionStatusBadge(granted: CGPreflightScreenCaptureAccess())
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

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = false
    
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
                    .disabled(true) // Future feature
                Text("Menu bar support coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }
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
            print("Failed to set launch at login: \(error)")
        }
    }
}

import AVFoundation

#Preview {
    SettingsView()
}
