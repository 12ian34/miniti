import SwiftUI

/// The permission step for Deepgram and OpenAI (App Review 5.1.1(i) and 5.1.2(i), 2026-10-21).
/// Shown as the first screen until it has been answered once, and again as a sheet whenever a
/// recording is attempted without permission or Settings, Privacy asks for it.
/// `AppState.hasAcceptedTerms` gates every recording start and every network insight, so this
/// is the permission, not a formality. "not now" is a real answer: the app opens with recording
/// and every AI feature off and nothing is sent. The terms version is bumped when this text
/// changes materially, so everyone answers the new disclosure once.
struct TermsAcceptanceView: View {
    enum Presentation {
        /// First screen, before onboarding. Offers allow and not now.
        case firstScreen
        /// Over the main view, from a record attempt or Settings, Privacy. Offers allow and cancel.
        case sheet
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    @State private var hoveringAllow = false
    @State private var hoveringDecline = false

    var presentation: Presentation = .firstScreen

    private let accent = ColorPalette.Status.success

    /// What goes where, in the person's words. Kept in one place so the review notes and the
    /// privacy policy can quote it.
    static var disclosures: [String] {
        var items = [
            "Deepgram gets the live audio and turns it into text. it also gets the meeting title and attendee names so it spells them right.",
            "OpenAI gets the transcript, your notes and the meeting title, and writes the summary, action items, questions and speaker names.",
            "on the managed plan this goes through miniti's servers, which keep no copy unless you turn on cloud. with your own keys it goes straight to Deepgram and OpenAI.",
        ]
        #if os(macOS)
        items.append("private mode in Settings, Privacy keeps transcription and speaker names on this Mac and sends nothing.")
        #endif
        return items
    }

    /// What "not now" means, shown under the choice so it reads as a real option.
    static let declineExplanation = "if you choose not now, miniti opens but recording and AI features stay off and nothing is sent. you can still read, import and export your meetings. miniti asks again when you tap record, and Settings, Privacy lets you change your choice at any time."

    private var heading: String {
        switch presentation {
        case .firstScreen: return "before we start"
        case .sheet: return "allow miniti to send your meeting?"
        }
    }

    private var declineTitle: String {
        switch presentation {
        case .firstScreen: return "not now"
        case .sheet: return "cancel"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("⬢")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                    Text("miniti")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(heading)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ColorPalette.Text.primary)
                    Text("miniti sends parts of your meetings to two companies so it can work. nothing leaves this device until you allow it here and start a recording.")
                        .font(.system(size: 13))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Self.disclosures, id: \.self) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Text("•")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(accent)
                            Text(line)
                                .font(.system(size: 13))
                                .foregroundStyle(ColorPalette.Text.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("both companies process this only to provide the service, under their business terms. audio is never stored.")
                        .font(.system(size: 13))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.declineExplanation)
                        .font(.system(size: 13))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(.init("the full list is in the [privacy policy](https://miniti.app/privacy#what-is-sent-to-third-parties). the [terms](https://miniti.app/terms) apply to your use of miniti."))
                        .font(.system(size: 12))
                        .foregroundStyle(ColorPalette.Text.dim)
                        .tint(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 460, alignment: .leading)

                HStack(spacing: 12) {
                    Button(action: decline) {
                        Text(declineTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(hoveringDecline ? ColorPalette.Text.primary : ColorPalette.Text.secondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(ColorPalette.Text.dim.opacity(hoveringDecline ? 0.2 : 0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(ColorPalette.Text.dim.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(presentation == .firstScreen
                        ? "not now: open miniti without sending anything to Deepgram or OpenAI"
                        : "cancel: do not send anything")
                    .onHover { h in hoveringDecline = h }

                    Button(action: allow) {
                        Text("allow")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(hoveringAllow ? ColorPalette.Background.primary : accent)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(hoveringAllow ? accent : accent.opacity(0.15))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(accent.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("allow sending meeting audio and text to Deepgram and OpenAI")
                    .onHover { h in hoveringAllow = h }
                }
                .animation(.easeInOut(duration: 0.15), value: hoveringAllow)
                .animation(.easeInOut(duration: 0.15), value: hoveringDecline)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorPalette.Background.primary)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                appeared = true
            }
        }
    }

    private func allow() {
        withAnimation(.easeOut(duration: 0.2)) {
            appState.setThirdPartyAIConsent(true)
        }
        if presentation == .sheet { dismiss() }
    }

    private func decline() {
        switch presentation {
        case .firstScreen:
            withAnimation(.easeOut(duration: 0.2)) {
                appState.setThirdPartyAIConsent(false)
            }
        case .sheet:
            dismiss()
        }
    }
}

#Preview {
    TermsAcceptanceView()
        .environmentObject(AppState())
        .frame(width: 600, height: 620)
}
