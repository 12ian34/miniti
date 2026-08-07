import SwiftUI

/// A short first-run path: choose how Miniti is powered, then verify microphone access.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)

                VStack(spacing: 10) {
                    Text("⬢")
                        .font(.system(size: 52, weight: .bold, design: .monospaced))
                        .foregroundStyle(ColorPalette.Accent.green)
                        .accessibilityHidden(true)
                    Text("miniti")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(ColorPalette.Text.primary)
                    Text(step == 0 ? "Turn meetings into useful notes while you talk." : "Make sure Miniti can hear you.")
                        .font(.headline)
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .multilineTextAlignment(.center)
                }

                if step == 0 {
                    planStep
                        .transition(.opacity)
                } else {
                    microphoneStep
                        .transition(.opacity)
                }

                Spacer(minLength: 24)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .background(ColorPalette.Background.primary)
        .onDisappear { appState.stopAudioMonitoring() }
    }

    private var planStep: some View {
        VStack(spacing: 14) {
            OnboardingChoice(
                icon: "sparkles",
                title: "Continue with Miniti Free",
                detail: "No API keys. Includes 500 transcription minutes each month.",
                accent: ColorPalette.Accent.green,
                isPrimary: true
            ) {
                appState.appModeRaw = AppMode.managed.rawValue
                withAnimation(.easeInOut(duration: 0.2)) { step = 1 }
                Task { await appState.refreshUsage() }
            }

            OnboardingChoice(
                icon: "key.fill",
                title: "Use my own API keys",
                detail: "Unlimited use billed directly by Deepgram and OpenAI. Add keys in Settings after setup.",
                accent: ColorPalette.Accent.blue,
                isPrimary: false
            ) {
                appState.appModeRaw = AppMode.byok.rawValue
                withAnimation(.easeInOut(duration: 0.2)) { step = 1 }
            }

            Text("You can switch modes later in Settings.")
                .font(.footnote)
                .foregroundStyle(ColorPalette.Text.muted)
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Microphone check", systemImage: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(ColorPalette.Text.primary)

                Text("Allow microphone access when asked, then speak. The meter should move. On macOS, system-audio permission is requested when your first recording starts.")
                    .font(.body)
                    .foregroundStyle(ColorPalette.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                OnboardingMicrophoneMeter(audioLevels: appState.audioLevels)

                Button(appState.isMonitoring ? "Stop microphone test" : "Test microphone") {
                    if appState.isMonitoring {
                        appState.stopAudioMonitoring()
                    } else {
                        appState.startAudioMonitoring()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: 44)
            }
            .padding(20)
            .background(ColorPalette.Background.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ColorPalette.Border.primary, lineWidth: 1)
            }

            Button("Continue") { finish() }
                .buttonStyle(.borderedProminent)
                .tint(ColorPalette.Accent.green)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 48)

            Button("Set up microphone later") { finish() }
                .buttonStyle(.plain)
                .font(.footnote.weight(.medium))
                .foregroundStyle(ColorPalette.Text.muted)
                .frame(minHeight: 44)
        }
    }

    private func finish() {
        appState.stopAudioMonitoring()
        appState.hasCompletedOnboarding = true
    }
}

private struct OnboardingChoice: View {
    let icon: String
    let title: String
    let detail: String
    let accent: Color
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isPrimary ? ColorPalette.Background.primary : accent)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isPrimary ? ColorPalette.Background.primary : ColorPalette.Text.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(isPrimary ? ColorPalette.Background.primary.opacity(0.72) : ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(isPrimary ? ColorPalette.Background.primary.opacity(0.65) : ColorPalette.Text.muted)
                    .accessibilityHidden(true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(isPrimary ? accent : ColorPalette.Background.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isPrimary ? accent : ColorPalette.Border.primary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingMicrophoneMeter: View {
    @ObservedObject var audioLevels: AudioLevelsState

    var body: some View {
        ProgressView(value: Double(min(max(audioLevels.microphoneLevel, 0), 1)))
            .tint(ColorPalette.Accent.green)
            .accessibilityLabel("Microphone input level")
            .accessibilityValue(audioLevels.microphoneLevel > 0.01 ? "Signal detected" : "No signal detected")
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .frame(width: 700, height: 550)
}
