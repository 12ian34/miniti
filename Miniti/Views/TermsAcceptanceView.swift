import SwiftUI

/// The first screen. Nothing leaves the device until the person has read what goes to Deepgram
/// and OpenAI and allowed it (App Review 5.1.1(i) and 5.1.2(i), 2026-10-21). `AppState.hasAcceptedTerms`
/// gates every recording start and every network insight, so this is the permission step, not
/// a formality. The terms version is bumped when this text changes materially, so everyone sees
/// the new disclosure once.
struct TermsAcceptanceView: View {
    @EnvironmentObject var appState: AppState
    @State private var appeared = false
    @State private var hovering = false

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
                    Text("before we start")
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
                    Text(.init("the full list is in the [privacy policy](https://miniti.app/privacy#what-is-sent-to-third-parties). by continuing you also agree to the [terms](https://miniti.app/terms)."))
                        .font(.system(size: 12))
                        .foregroundStyle(ColorPalette.Text.dim)
                        .tint(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 460, alignment: .leading)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        appState.hasAcceptedTerms = true
                    }
                } label: {
                    Text("allow and continue →")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(hovering ? ColorPalette.Background.primary : accent)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(hovering ? accent : accent.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(accent.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("allow sending meeting audio and text to Deepgram and OpenAI, and continue")
                .onHover { h in hovering = h }
                .animation(.easeInOut(duration: 0.15), value: hovering)
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
}

#Preview {
    TermsAcceptanceView()
        .environmentObject(AppState())
        .frame(width: 600, height: 560)
}
