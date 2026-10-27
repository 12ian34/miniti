import SwiftUI

/// The permission step for Deepgram and OpenAI (App Review 5.1.1(i) and 5.1.2(i), 2026-10-21).
/// Shown as the first screen until it has been answered once, and again as a sheet whenever a
/// recording is attempted without permission or Settings, Privacy asks for it.
/// `AppState.hasAcceptedTerms` gates every recording start and the insight paths that check it,
/// so this is the permission, not a formality. "not now" is a real answer: the app opens with
/// recording and the AI features off. The terms version is bumped when the recipients, the data
/// or the purposes change; a shorter wording of the same disclosure keeps the version (U2,
/// docs/account-sending-consent-ux-plan.md).
///
/// Layout contract (U2): the disclosure scrolls, the two actions sit below it in their own bar
/// and never scroll out of reach, whatever the window size or text size.
struct TermsAcceptanceView: View {
    enum Presentation {
        /// First screen, before onboarding. Offers allow and not now.
        case firstScreen
        /// Over the main view, from a record attempt or Settings, Privacy. Offers allow and cancel.
        case sheet
    }

    /// One recipient and what it receives, in the person's words. Kept as data so the review
    /// notes, the privacy policy and the tests can quote exactly what the screen says.
    struct ProviderLine: Equatable {
        let name: String
        let text: String
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var hoveringAllow = false
    @State private var hoveringDecline = false

    var presentation: Presentation = .firstScreen

    private let accent = ColorPalette.Status.success

    // MARK: Copy

    /// What audio Deepgram receives on this platform. The Watch prerecorded route is the only
    /// recorded-audio path in the app, so the iPhone names it and the Mac says live audio only.
    static var audioDescription: String {
        #if os(iOS)
        return "live audio while you record and recordings from your watch"
        #else
        return "live audio while you record"
        #endif
    }

    static var providerLines: [ProviderLine] {
        [
            ProviderLine(name: "Deepgram", text: "receives \(audioDescription), the meeting title and attendee names, and returns the transcript."),
            ProviderLine(name: "OpenAI", text: "receives the transcript, your notes, the meeting title and attendee names, and returns summaries, action items, questions and speaker names."),
        ]
    }

    /// Where the data travels. Audio goes straight to Deepgram on both plans; managed text goes
    /// through miniti's servers.
    static let pathLine = "on the managed plan, audio goes straight from this device to Deepgram and text goes to OpenAI through miniti. with your own keys, both go straight to the provider."

    /// What "not now" means, so it reads as a real option.
    static let choiceLine = "choose not now and miniti still opens: you can read, import and export meetings, and recording asks again. change this any time in Settings, Privacy."

    /// Every sentence the screen shows, in order, for the tests and the review notes.
    static var disclosureText: String {
        var parts = providerLines.map { "\($0.name) \($0.text)" }
        parts.append(pathLine)
        parts.append(choiceLine)
        #if os(macOS)
        parts.append(privateModeLine)
        #endif
        return parts.joined(separator: " ")
    }

    #if os(macOS)
    static let privateModeLine = "private mode in Settings, Privacy keeps transcription on this Mac."
    #endif

    /// Whether the decline action records an answer. The first screen records "not now" so it
    /// steps aside; the sheet only closes and leaves the stored answer alone.
    nonisolated static func declineRecordsAnswer(_ presentation: Presentation) -> Bool {
        presentation == .firstScreen
    }

    private var heading: String {
        "use cloud transcription and AI?"
    }

    private var declineTitle: String {
        switch presentation {
        case .firstScreen: return "not now"
        case .sheet: return "cancel"
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
                    Text("miniti")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.secondary)

                    Text(heading)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ColorPalette.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Self.providerLines, id: \.name) { line in
                        (Text(line.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(ColorPalette.Text.primary)
                            + Text(" \(line.text)").font(.system(size: 13)).foregroundStyle(ColorPalette.Text.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("\(line.name) \(line.text)")
                    }

                    Text(Self.pathLine)
                        .font(.system(size: 13))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(Self.choiceLine)
                        .font(.system(size: 13))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    #if os(macOS)
                    Text(Self.privateModeLine)
                        .font(.system(size: 12))
                        .foregroundStyle(ColorPalette.Text.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    #endif

                    Text(.init("[privacy policy](https://miniti.app/privacy#what-is-sent-to-third-parties) · [terms](https://miniti.app/terms)"))
                        .font(.system(size: 12))
                        .foregroundStyle(ColorPalette.Text.dim)
                        .tint(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 460, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, MinitiDesignSystem.Spacing.page)
                .padding(.vertical, MinitiDesignSystem.Spacing.section)
            }

            Divider()
                .overlay(ColorPalette.Border.primary)

            actionBar
                .padding(.horizontal, MinitiDesignSystem.Spacing.page)
                .padding(.vertical, MinitiDesignSystem.Spacing.comfortable)
                .frame(maxWidth: .infinity)
                .background(ColorPalette.Background.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorPalette.Background.primary)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.4).delay(0.05)) { appeared = true }
            }
        }
    }

    /// Both actions, side by side when they fit, stacked with Allow on top when they do not.
    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MinitiDesignSystem.Spacing.comfortable) {
                Spacer(minLength: 0)
                declineButton
                allowButton
                Spacer(minLength: 0)
            }
            VStack(spacing: MinitiDesignSystem.Spacing.standard) {
                allowButton
                declineButton
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: MinitiDesignSystem.Motion.hoverDuration), value: hoveringAllow)
        .animation(reduceMotion ? nil : .easeInOut(duration: MinitiDesignSystem.Motion.hoverDuration), value: hoveringDecline)
    }

    private var declineButton: some View {
        Button(action: decline) {
            Text(declineTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hoveringDecline ? ColorPalette.Text.primary : ColorPalette.Text.secondary)
                .padding(.horizontal, MinitiDesignSystem.Spacing.page)
                .padding(.vertical, MinitiDesignSystem.Spacing.comfortable)
                .frame(minWidth: 120)
                .background(
                    RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                        .fill(ColorPalette.Text.dim.opacity(hoveringDecline ? 0.2 : 0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                        .stroke(ColorPalette.Text.dim.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .modifier(SheetEscapeShortcut(enabled: presentation == .sheet))
        .accessibilityLabel(presentation == .firstScreen
            ? "not now: open miniti without sending anything to Deepgram or OpenAI"
            : "cancel: do not send anything")
        .onHover { h in hoveringDecline = h }
    }

    private var allowButton: some View {
        Button(action: allow) {
            Text("allow")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hoveringAllow ? ColorPalette.Background.primary : accent)
                .padding(.horizontal, 32)
                .padding(.vertical, MinitiDesignSystem.Spacing.comfortable)
                .frame(minWidth: 120)
                .background(
                    RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                        .fill(hoveringAllow ? accent : accent.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                        .stroke(accent.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel("allow sending meeting audio and text to Deepgram and OpenAI")
        .onHover { h in hoveringAllow = h }
    }

    // MARK: Actions

    private func allow() {
        if reduceMotion {
            appState.setThirdPartyAIConsent(true)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                appState.setThirdPartyAIConsent(true)
            }
        }
        if presentation == .sheet { dismiss() }
    }

    private func decline() {
        if Self.declineRecordsAnswer(presentation) {
            if reduceMotion {
                appState.setThirdPartyAIConsent(false)
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    appState.setThirdPartyAIConsent(false)
                }
            }
        } else {
            dismiss()
        }
    }
}

/// Escape closes the sheet. On the first screen "not now" is a recorded answer, so it takes a
/// click and no key.
private struct SheetEscapeShortcut: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.keyboardShortcut(.cancelAction)
        } else {
            content
        }
    }
}

#Preview("first screen, minimum window") {
    TermsAcceptanceView()
        .environmentObject(AppState())
        .frame(width: 600, height: 400)
}

#Preview("sheet") {
    TermsAcceptanceView(presentation: .sheet)
        .environmentObject(AppState())
        .frame(width: 520, height: 480)
}
