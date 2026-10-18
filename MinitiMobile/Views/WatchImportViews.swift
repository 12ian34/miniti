import SwiftUI

/// History rows for watch recordings that are not meetings yet.
struct WatchImportRows: View {
    @ObservedObject private var imports = WatchImportService.shared

    var body: some View {
        if !imports.activeJobs.isEmpty {
            Section("From your watch") {
                ForEach(imports.activeJobs) { job in
                    HStack(spacing: 10) {
                        Image(systemName: "applewatch")
                            .foregroundStyle(ColorPalette.Text.dim)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.startedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(ColorPalette.Text.primary)
                            Text(job.statusText)
                                .font(.system(size: 12))
                                .foregroundStyle(job.status == .failed ? ColorPalette.Status.error : ColorPalette.Text.dim)
                                .lineLimit(2)
                        }
                        Spacer()
                        if job.status == .transcribing || job.status == .insights {
                            ProgressView().controlSize(.small)
                        } else if job.status == .failed || job.status == .waitingForMinutes {
                            Button("Try again") { imports.retry(job.id) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if job.isRemovable {
                            Button(role: .destructive) { imports.dismiss(job.id) } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Settings → Recording: whether a watch is paired and what is waiting.
struct WatchSettingsSection: View {
    @ObservedObject private var bridge = WatchSessionBridge.shared
    @ObservedObject private var imports = WatchImportService.shared

    var body: some View {
        // Only people with a paired watch see this; nothing changes for everyone else.
        if bridge.isPaired {
        Section("Apple Watch") {
            LabeledContent("Watch app") {
                Text(bridge.isWatchAppInstalled ? "Installed" : (bridge.isPaired ? "Not installed" : "No watch paired"))
                    .foregroundStyle(.secondary)
            }
            if !imports.activeJobs.isEmpty {
                LabeledContent("Recordings in progress") {
                    Text("\(imports.activeJobs.count)").foregroundStyle(.secondary)
                }
            }
            Text("Record a meeting from the watch app. The audio moves to this iPhone when the two are in range, gets transcribed by Deepgram, and shows up in History with a summary. Minutes count the same as a live meeting.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        }
    }
}
