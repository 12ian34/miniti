import SwiftUI

/// First-launch mode selection: Managed (free 500 min/month) vs BYOK (own keys, unlimited).
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredMode: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Logo
            VStack(spacing: 12) {
                Text("⬢")
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "3FB950"))
                
                Text("miniti")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                
                Text("pick a plan")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "A1A1AA"))
                    .padding(.top, 4)
            }
            
            Spacer().frame(height: 40)
            
            // Mode cards
            HStack(spacing: 16) {
                // Managed mode card
                ModeCard(
                    title: "early adopter",
                    subtitle: "500 min/month",
                    description: "No API keys needed.\nWe handle everything.",
                    features: [
                        "Real-time transcription",
                        "AI-powered insights",
                        "500 minutes per month",
                        "Resets monthly"
                    ],
                    accentColor: Color(hex: "3FB950"),
                    isHovered: hoveredMode == "managed"
                ) {
                    appState.appModeRaw = AppMode.managed.rawValue
                    appState.hasCompletedOnboarding = true
                    Task {
                        await appState.refreshUsage()
                    }
                }
                .onHover { hovering in
                    hoveredMode = hovering ? "managed" : nil
                }
                
                // BYOK mode card
                ModeCard(
                    title: "bring your own keys",
                    subtitle: "unlimited",
                    description: "Use your own Deepgram\n& OpenAI API keys.",
                    features: [
                        "No usage limits",
                        "Your own API costs"
                    ],
                    accentColor: Color(hex: "58A6FF"),
                    isHovered: hoveredMode == "byok"
                ) {
                    appState.appModeRaw = AppMode.byok.rawValue
                    appState.hasCompletedOnboarding = true
                }
                .onHover { hovering in
                    hoveredMode = hovering ? "byok" : nil
                }
            }
            
            Spacer().frame(height: 24)
            
            // Reassurance
            Text("you can switch later")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "71717A"))
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "09090B"))
    }
}

// MARK: - Mode Card

private struct ModeCard: View {
    let title: String
    let subtitle: String
    let description: String
    let features: [String]
    let accentColor: Color
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "E6EDF3"))
                    
                    Text(subtitle)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                    
                    Text(description)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "A1A1AA"))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Divider
                Rectangle()
                    .fill(Color(hex: "27272A"))
                    .frame(height: 1)
                
                // Features
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 8) {
                            Text("✓")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(accentColor)
                            Text(feature)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: "D4D4D8"))
                        }
                    }
                }
                
                Spacer()
                
                // CTA
                HStack {
                    Spacer()
                    Text("select →")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isHovered ? Color(hex: "09090B") : accentColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isHovered ? accentColor : accentColor.opacity(0.15))
                        )
                    Spacer()
                }
            }
            .padding(20)
            .frame(width: 260, height: 300)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "0F0F11"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isHovered ? accentColor.opacity(0.6) : Color(hex: "27272A"),
                        lineWidth: isHovered ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .frame(width: 700, height: 550)
}
