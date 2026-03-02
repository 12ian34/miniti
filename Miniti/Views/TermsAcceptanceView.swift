import SwiftUI

struct TermsAcceptanceView: View {
    @EnvironmentObject var appState: AppState
    @State private var appeared = false
    @State private var hovering = false

    private let accentGreen = Color(hex: "3FB950")

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Logo
                VStack(spacing: 12) {
                    Text("⬢")
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentGreen)

                    Text("miniti")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: "E6EDF3"))
                }

                // Legal text
                VStack(spacing: 12) {
                    Text("before we start")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "A1A1AA"))

                    Text(.init("by using miniti, you agree to our [terms](https://miniti.app/terms) and [privacy policy](https://miniti.app/privacy)."))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(hex: "71717A"))
                        .multilineTextAlignment(.center)
                        .tint(accentGreen)
                }

                // Accept button
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        appState.hasAcceptedTerms = true
                    }
                } label: {
                    Text("i agree →")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(hovering ? Color(hex: "09090B") : accentGreen)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(hovering ? accentGreen : accentGreen.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(accentGreen.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .onHover { h in hovering = h }
                .animation(.easeInOut(duration: 0.15), value: hovering)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "09090B"))
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
        .frame(width: 600, height: 450)
}
