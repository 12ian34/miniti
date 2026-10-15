import SwiftUI

/// A short first-run path: choose how Miniti is powered, then verify microphone access.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step = 0
    @State private var showRestoreSheet = false

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

            #if os(macOS)
            // App Review (2.10.0, guideline 3.1.1) reads a key-based tier beside the
            // subscription as an unlock mechanism. On iOS the option lives in Settings only.
            OnboardingChoice(
                icon: "key.fill",
                title: "Use my own Deepgram and OpenAI accounts",
                detail: "Audio and text go straight to your own accounts. Add your credentials in Settings after setup.",
                accent: ColorPalette.Accent.blue,
                isPrimary: false
            ) {
                appState.appModeRaw = AppMode.byok.rawValue
                withAnimation(.easeInOut(duration: 0.2)) { step = 1 }
            }
            #endif

            Button("Already use Miniti on another device? Restore with your recovery key") {
                showRestoreSheet = true
            }
            .buttonStyle(.plain)
            .font(.footnote)
            .foregroundStyle(ColorPalette.Accent.green)

            Text("You can change this later in Settings.")
                .font(.footnote)
                .foregroundStyle(ColorPalette.Text.muted)
        }
        .sheet(isPresented: $showRestoreSheet) {
            RestoreRecoveryKeySheet(onRestored: {
                appState.appModeRaw = AppMode.managed.rawValue
                withAnimation(.easeInOut(duration: 0.2)) { step = 1 }
            })
            .environmentObject(appState)
            .preferredColorScheme(.dark)
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Microphone check", systemImage: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(ColorPalette.Text.primary)

                Text("Allow microphone access when asked, then speak. The meter should move. macOS also asks to record system audio so calls can be transcribed.")
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

struct OnboardingMicrophoneMeter: View {
    @ObservedObject var audioLevels: AudioLevelsState

    /// Raw mic RMS for ordinary speech sits around 0.01 to 0.05, so a linear 0 to 1 bar
    /// barely moves (2026-10-15 field report: "pressed test, nothing appeared"). Show a
    /// 50 dB range instead: a quiet room (about 0.003) rests at empty, quiet speech
    /// reaches a third, normal speech about half, a shout the top.
    nonisolated static func displayLevel(for rawLevel: Float) -> Double {
        guard rawLevel.isFinite, rawLevel > 0 else { return 0 }
        let decibels = 20 * log10(Double(rawLevel))
        return min(1, max(0, (decibels + 50) / 50))
    }

    nonisolated static func hasSignal(_ rawLevel: Float) -> Bool {
        rawLevel.isFinite && rawLevel > AppState.speechMicLevelThreshold
    }

    var body: some View {
        ProgressView(value: Self.displayLevel(for: audioLevels.microphoneLevel))
            .tint(ColorPalette.Accent.green)
            .accessibilityLabel("Microphone input level")
            .accessibilityValue(Self.hasSignal(audioLevels.microphoneLevel) ? "Signal detected" : "No signal detected")
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .frame(width: 700, height: 550)
}
