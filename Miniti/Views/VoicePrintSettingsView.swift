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
                if needsOnDeviceSpeakers {
                    Text("Needs Speakers set to \(deviceName == "this Mac" ? "This Mac" : "This device") above. Deepgram's speaker separation gives nothing to recognise voices from.")
                        .font(.caption)
                        .foregroundStyle(ColorPalette.Status.error)
                } else {
                    Text(embedder.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .id("transcription.voices")
    }
}
