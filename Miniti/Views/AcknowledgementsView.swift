import SwiftUI

/// Third-party software and model notices shown under Settings → About. Licence texts ship
/// as plain files in `Miniti/Resources/Acknowledgements` so the app carries the notices the
/// licences require: Apache 2.0 for FluidAudio (and its components), OpenMDW 1.1 for the
/// bundled Nemotron-3-Diarization weights, and Sparkle's licence on macOS.
enum Acknowledgements {
    struct Entry: Identifiable, Equatable {
        let id: String
        let title: String
        let summary: String
        /// File name inside the `Acknowledgements` resource folder.
        let file: String
    }

    static let folder = "Acknowledgements"

    static var entries: [Entry] {
        var list: [Entry] = [
            Entry(id: "nemotron", title: "NVIDIA Nemotron-3-Diarization", summary: "Speaker model that runs on your device. OpenMDW License 1.1.", file: "Nemotron-3-Diarization-NOTICE.txt"),
            Entry(id: "openmdw", title: "OpenMDW License 1.1", summary: "The agreement the speaker model is provided under.", file: "OpenMDW-1.1.txt"),
            Entry(id: "fluidaudio", title: "FluidAudio", summary: "Runs the speaker model with Core ML. Apache License 2.0.", file: "FluidAudio-LICENSE.txt"),
            Entry(id: "fluidaudio-vbx", title: "FluidAudio component: VBx", summary: "Apache License 2.0.", file: "FluidAudio-vbx-LICENSE.txt"),
            Entry(id: "fluidaudio-fastcluster", title: "FluidAudio component: fastcluster", summary: "BSD-style licence.", file: "FluidAudio-fastcluster-LICENSE.txt"),
            Entry(id: "fluidaudio-textprocessing", title: "FluidAudio component: NemoTextProcessing", summary: "Text normalisation library.", file: "FluidAudio-NemoTextProcessing-LICENSE.txt"),
            Entry(id: "fluidaudio-japanese", title: "FluidAudio component: Japanese text frontend", summary: "Ported from Misaki.", file: "FluidAudio-JapaneseG2P-LICENSE.txt"),
            Entry(id: "fluidaudio-kokoro", title: "FluidAudio component: Spanish and French text frontends", summary: "Lexicon data notices.", file: "FluidAudio-KokoroAneSpanishFrenchG2P-LICENSE.txt"),
        ]
        #if os(macOS)
        list.append(Entry(id: "sparkle", title: "Sparkle", summary: "Software updates on macOS. BSD-style licence.", file: "Sparkle-LICENSE.txt"))
        #endif
        return list
    }

    /// Licence text for an entry, or nil when the file is missing from the bundle.
    static func text(for entry: Entry, bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: entry.file, withExtension: nil, subdirectory: folder)
            ?? bundle.url(forResource: entry.file, withExtension: nil) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// Collapsible list of notices for a settings About section. One disclosure per entry; the
/// text loads when opened.
struct AcknowledgementsSection: View {
    var body: some View {
        DisclosureGroup("Acknowledgements") {
            Text("Open-source software and the speaker model miniti ships with, and their licences.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Acknowledgements.entries) { entry in
                AcknowledgementRow(entry: entry)
            }
        }
    }
}

private struct AcknowledgementRow: View {
    let entry: Acknowledgements.Entry
    @State private var expanded = false
    @State private var text: String?

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ScrollView {
                Text(text ?? "Licence text is missing from this build.")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: expanded) { _, isOpen in
            if isOpen, text == nil { text = Acknowledgements.text(for: entry) }
        }
    }
}
