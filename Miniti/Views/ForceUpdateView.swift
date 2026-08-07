import SwiftUI

struct ForceUpdateView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    @State private var appeared = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("⬢")
                        .font(.system(size: 56, weight: .bold, design: .default))
                        .foregroundStyle(ColorPalette.Accent.red.opacity(0.8))

                    Text("update required")
                        .font(.system(size: 24, weight: .bold, design: .default))
                        .foregroundStyle(ColorPalette.Text.primary)
                }

                VStack(spacing: 8) {
                    Text("this version of miniti is no longer supported.")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .multilineTextAlignment(.center)

                    if let update = appState.availableUpdate {
                        Text("latest: v\(update.latestVersion)")
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundStyle(ColorPalette.Text.muted)
                    }
                }

                if let update = appState.availableUpdate {
                    Button {
                        if let url = URL(string: update.downloadUrl) {
                            openURL(url)
                        }
                    } label: {
                        Text("download update →")
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
                    .onHover { h in hovering = h }
                    .animation(.easeInOut(duration: 0.15), value: hovering)
                }
            }
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
    }
}

#Preview {
    ForceUpdateView()
        .environmentObject(AppState())
        .frame(width: 600, height: 450)
}
