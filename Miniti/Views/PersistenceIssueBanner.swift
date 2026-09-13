import SwiftUI

/// Root-level strip for a save or load that did not persist (roadmap P0.3). Mounted once per
/// platform: at the top of `MainWindow` on macOS and above the tab content on iOS. Mirrors
/// `RecordingIssueBanner` so the two failure surfaces read the same.
struct PersistenceIssueBanner: View {
    @EnvironmentObject private var appState: AppState
    let issue: PersistenceIssue

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ColorPalette.Accent.amber)
                .accessibilityHidden(true)

            Text(issue.message)
                .font(.system(size: 12))
                .foregroundStyle(ColorPalette.Text.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if appState.persistenceRetryAction != nil {
                Button("retry") {
                    appState.retryPersistence()
                }
                .buttonStyle(.borderedProminent)
                .tint(ColorPalette.Accent.amber)
                .controlSize(.small)
            }

            Button {
                appState.dismissPersistenceIssue()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss save issue")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ColorPalette.Accent.amber.opacity(0.12))
        .background(ColorPalette.Background.primary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ColorPalette.Accent.amber.opacity(0.35))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Attach to a root view: shows the banner whenever `appState.persistenceIssue` is set.
struct PersistenceIssueOverlay: ViewModifier {
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let issue = appState.persistenceIssue {
                PersistenceIssueBanner(issue: issue)
                    .id(issue.id)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.persistenceIssue)
    }
}

extension View {
    func persistenceIssueOverlay() -> some View {
        modifier(PersistenceIssueOverlay())
    }
}
