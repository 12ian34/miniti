import SwiftUI

/// Settings, Transcription: "Your voice" and "Remember voices" (3.2.0). Shared by both
/// platforms; the caller wraps it in the Transcription tab after the Speakers picker.
struct VoicePrintSettingsSection: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store: VoicePrintStore
    @ObservedObject private var embedder: VoicePrintEmbedderService

    init(store: VoicePrintStore, embedder: VoicePrintEmbedderService) {
        self.store = store
        self.embedder = embedder
    }

    private var deviceName: String {
        #if os(macOS)
        return "this Mac"
        #else
        return "this device"
        #endif
    }

    private var needsOnDeviceSpeakers: Bool { !appState.onDeviceSpeakerSeparationEnabled }

    var body: some View {
        Section("Voices") {
            Toggle("Your voice", isOn: Binding(
                get: { appState.voicePrintSelfEnabled },
                set: { appState.voicePrintSelfEnabled = $0; appState.refreshVoicePrintAvailability() }
            ))
            .id("transcription.yourVoice")
            .disabled(!OnDeviceDiarizationService.isHardwareSupported)
            if let me = store.selfPrint {
                LabeledContent("Learned from") {
                    Text("\(me.meetings) \(me.meetings == 1 ? "meeting" : "meetings"), \(Int(me.speechSeconds / 60)) min of speech")
                        .foregroundStyle(.secondary)
                }
                Button("Forget my voice", role: .destructive) { store.remove(key: VoicePrint.selfKey) }
            }
            Text("Learns what you sound like from the speakers you mark as me, and labels you from the first sentence on the phone, in a room, and in watch recordings. Nothing leaves \(deviceName).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Remember voices", isOn: Binding(
                get: { appState.voicePrintOthersEnabled },
                set: { appState.voicePrintOthersEnabled = $0; appState.refreshVoicePrintAvailability(); if !$0 { store.removeAll(keepSelf: true) } }
            ))
            .id("transcription.rememberVoices")
            .disabled(!OnDeviceDiarizationService.isHardwareSupported)
            Text("Keeps a voice fingerprint on \(deviceName) for each person miniti has matched to a calendar guest, so they are named next time before anyone says their name. Turning it off deletes them all.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(store.others) { print in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(print.displayName)
                        if let email = print.email {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(print.meetings) \(print.meetings == 1 ? "meeting" : "meetings")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) { store.remove(key: print.key) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Forget \(print.displayName)")
                }
            }

            if appState.voicePrintSelfEnabled || appState.voicePrintOthersEnabled {
                Text(appState.voiceModelStatus(embedder.status))
                    .font(.caption)
                    .foregroundStyle(needsOnDeviceSpeakers ? ColorPalette.Status.error : ColorPalette.Text.secondary)
            }
        }
        .id("transcription.voices")
    }
}

/// All local model families in one inventory. Feature choices remain under Transcription.
struct LocalModelsSettingsSections<Configure: View>: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var embedder: VoicePrintEmbedderService
    @ViewBuilder var configure: (String) -> Configure

    var body: some View {
        Section("On this device") {
            Text("Models used for local transcription, speaker separation and voice recognition. Cloud services are listed under Privacy.")
                .font(.callout).foregroundStyle(.secondary)
        }
        #if os(macOS)
        Section("Speech transcription") {
            Text("NVIDIA Nemotron 3.5")
            Text("Turns audio into words on this Mac. Downloads when you choose This Mac in Transcription.")
                .font(.caption).foregroundStyle(.secondary)
            OnDeviceTranscriptionModelsRow(service: appState.onDeviceTranscription, isEnabled: appState.onDeviceTranscriptionEnabled)
            configure("transcription.model")
        }
        #endif
        Section("Speaker separation") {
            Text("NVIDIA Nemotron")
            Text("Identifies who spoke when. Included with miniti, about 190 MB.")
                .font(.caption).foregroundStyle(.secondary)
            Text(appState.onDeviceSpeakerSeparationEnabled ? "Enabled for new recordings" : "Not enabled")
                .font(.caption).foregroundStyle(.secondary)
            configure("transcription.speakers")
        }
        Section("Voice recognition") {
            Text("CAM++")
            Text("Recognises familiar voices. Downloads when a voice option is enabled and Speakers uses this device, about 17 MB.")
                .font(.caption).foregroundStyle(.secondary)
            Text(appState.voiceModelStatus(embedder.status))
                .font(.caption).foregroundStyle(.secondary)
            Text("Voice fingerprints stay on this device. Manage or forget them in Transcription, Voices.")
                .font(.caption).foregroundStyle(.secondary)
            configure("transcription.voices")
        }
    }
}

#if os(macOS)
/// The downloaded speech model: size on disk and a remove button, enabled only while the
/// model is not in use so an active download or session is never pulled from under it.
private struct OnDeviceTranscriptionModelsRow: View {
    @ObservedObject var service: OnDeviceTranscriptionService
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Speech model")
            Spacer()
            if service.downloadedBytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: service.downloadedBytes, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Remove") { service.removeDownloadedModels() }
                    .disabled(isEnabled)
                    .help(isEnabled ? "Turn transcription on this Mac off first." : "Delete the downloaded files.")
            } else {
                Text("not downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#endif
