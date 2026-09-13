import SwiftData
import SwiftUI

/// Shown instead of the app when the meeting store cannot be opened (roadmap P0.2).
/// Never deletes or recreates the store: the only actions are retry, diagnostics,
/// export of whatever a read-only open can reach, reveal the folder, and support.
struct StoreRecoveryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    let failure: PersistentStoreOpenFailure
    let readOnlyContainer: ModelContainer?
    let retry: () -> Void

    @State private var appeared = false
    @State private var exportMessage: String?
    #if os(iOS)
    @State private var showDiagnostics = false
    @State private var exportedMarkdown: ExportedMarkdown?
    #endif

    private static let supportURL = URL(string: "https://miniti.app/support")!

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("⬢")
                        .font(.system(size: 56, weight: .bold, design: .default))
                        .foregroundStyle(ColorPalette.Accent.amber.opacity(0.85))
                        .accessibilityHidden(true)

                    Text("can't open your meetings")
                        .font(.system(size: 24, weight: .bold, design: .default))
                        .foregroundStyle(ColorPalette.Text.primary)
                }

                VStack(spacing: 8) {
                    Text(failure.category.userDescription)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)

                    Text(failure.summary)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                        .textSelection(.enabled)
                }

                VStack(spacing: 10) {
                    RecoveryPrimaryButton(title: "try again", action: retry)

                    // One row where it fits (macOS, iPad), a column on a phone.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { secondaryActions }
                        VStack(spacing: 10) { secondaryActions }
                    }

                    if let exportMessage {
                        Text(exportMessage)
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundStyle(ColorPalette.Text.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 24)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorPalette.Background.primary)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                appeared = true
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showDiagnostics) {
            DebugLogView()
        }
        .sheet(item: $exportedMarkdown) { exported in
            VStack(spacing: 16) {
                Text("\(exported.meetingCount) meeting\(exported.meetingCount == 1 ? "" : "s") as markdown")
                    .font(.headline)
                ShareLink(item: exported.text, preview: SharePreview("miniti meetings")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .presentationDetents([.medium])
        }
        #endif
    }

    @ViewBuilder
    private var secondaryActions: some View {
        RecoverySecondaryButton(title: "export diagnostics") {
            #if os(macOS)
            openWindow(id: "debug-log")
            #else
            showDiagnostics = true
            #endif
        }

        if readOnlyContainer != nil {
            RecoverySecondaryButton(title: "export meetings", action: exportMeetings)
        }

        #if os(macOS)
        RecoverySecondaryButton(title: "show database folder", action: revealStoreFolder)
        #endif

        RecoverySecondaryButton(title: "get help ↗") {
            openURL(Self.supportURL)
        }
    }

    // MARK: Actions

    /// Read every finalized meeting from the read-only container and hand it to the
    /// platform's export path. Read-only means the store is never written here.
    private func exportMeetings() {
        guard let readOnlyContainer else { return }
        let meetings: [Meeting]
        do {
            meetings = try readOnlyContainer.mainContext.fetch(FetchDescriptor<Meeting>())
        } catch {
            DebugLogger.shared.log(.app, "Recovery export: fetch FAILED: \(error.localizedDescription)", level: .error)
            exportMessage = "couldn't read meetings from the damaged store"
            return
        }
        let finalized = meetings.filter { $0.endTime != nil && !$0.segments.isEmpty }
        DebugLogger.shared.log(.app, "Recovery export: \(meetings.count) total, \(finalized.count) finalized")
        guard !finalized.isEmpty else {
            exportMessage = "no finished meetings could be read"
            return
        }

        #if os(macOS)
        for meeting in finalized {
            appState.exportMeetingAsMarkdownFile(markdown: meeting.fullMeetingAsMarkdown(), meeting: meeting)
        }
        exportMessage = "exported \(finalized.count) meeting\(finalized.count == 1 ? "" : "s") to \(exportFolderPath)"
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: exportFolderPath)])
        #else
        let text = finalized
            .sorted { $0.startTime < $1.startTime }
            .map { $0.fullMeetingAsMarkdown() }
            .joined(separator: "\n\n---\n\n")
        exportedMarkdown = ExportedMarkdown(text: text, meetingCount: finalized.count)
        #endif
    }

    #if os(macOS)
    private var exportFolderPath: String {
        appState.markdownExportFolderPath.isEmpty
            ? NSString("~/Documents/miniti").expandingTildeInPath
            : appState.markdownExportFolderPath
    }

    private func revealStoreFolder() {
        let url = PersistentStore.storeURLOverride ?? PersistentStore.defaultStoreURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif
}

#if os(iOS)
private struct ExportedMarkdown: Identifiable {
    let id = UUID()
    let text: String
    let meetingCount: Int
}
#endif

// MARK: Buttons

private struct RecoveryPrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(hovering ? ColorPalette.Background.primary : ColorPalette.Accent.green)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hovering ? ColorPalette.Accent.green : ColorPalette.Accent.green.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ColorPalette.Accent.green.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}

private struct RecoverySecondaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(hovering ? ColorPalette.Text.primary : ColorPalette.Text.secondary)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ColorPalette.Text.muted.opacity(hovering ? 0.6 : 0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}

#Preview {
    StoreRecoveryView(
        failure: PersistentStoreOpenFailure(category: .corruption, domain: "NSSQLiteErrorDomain", code: 26, reason: "file is not a database"),
        readOnlyContainer: nil,
        retry: {}
    )
    .environmentObject(AppState())
    .frame(width: 720, height: 480)
}
