import SwiftUI

/// Shown when managed-mode user hits 500 min/month. Hard blocks recording.
/// Offers: switch to BYOK, or wait for monthly reset.
struct LimitReachedView: View {
    @EnvironmentObject var appState: AppState
    
    private var resetsAt: Date? {
        appState.usageInfo?.resetsAt
    }
    
    private var daysUntilReset: Int {
        guard let resetsAt else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: resetsAt).day ?? 0)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            Text("⬢")
                .font(.system(size: 40, weight: .bold, design: .default))
                .foregroundStyle(Color(hex: "F85149").opacity(0.6))
            
            // Message
            VStack(spacing: 8) {
                Text("limit reached")
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundStyle(Color(hex: "E6EDF3"))
                
                Text("You've used all \(Int(appState.usageInfo?.minutesLimit ?? 500)) minutes this month.")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "A1A1AA"))
                    .multilineTextAlignment(.center)
            }
            
            // Reset info
            if let resetsAt {
                VStack(spacing: 4) {
                    Text("resets in \(daysUntilReset) day\(daysUntilReset == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(Color(hex: "F59E0B"))
                    
                    Text(resetsAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Color(hex: "71717A"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "F59E0B").opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "F59E0B").opacity(0.2), lineWidth: 1)
                        )
                )
            }
            
            #if os(macOS)
            if !appState.isPro {
                // Upgrade option
                VStack(spacing: 8) {
                    Button {
                        Task { await appState.openSubscribePage() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 11))
                            Text("upgrade to pro — 5,000 min/mo")
                                .font(.system(size: 12, weight: .semibold, design: .default))
                        }
                        .foregroundStyle(Color(hex: "A78BFA"))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: "A78BFA").opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(hex: "A78BFA").opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    
                    Text("$5/month")
                        .font(.system(size: 10, weight: .regular, design: .default))
                        .foregroundStyle(Color(hex: "52525B"))
                }
            }
            #endif
            
            // Divider
            Rectangle()
                .fill(Color(hex: "27272A"))
                .frame(width: 200, height: 1)
            
            // BYOK option
            VStack(spacing: 12) {
                Text("or use your own API keys for unlimited access")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "A1A1AA"))
                    .multilineTextAlignment(.center)
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.appModeRaw = AppMode.byok.rawValue
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 11))
                        Text("switch to BYOK")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                    }
                    .foregroundStyle(Color(hex: "58A6FF"))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: "58A6FF").opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: "58A6FF").opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                
                Text("You'll need Deepgram & OpenAI API keys")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(Color(hex: "52525B"))
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "09090B"))
    }
}

/// Inline limit warning shown in the home screen when close to limit.
struct LimitWarningBanner: View {
    let minutesRemaining: Double
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "F59E0B"))
            
            Text("\(Int(minutesRemaining)) min remaining this month")
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "F59E0B"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "F59E0B").opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "F59E0B").opacity(0.2), lineWidth: 1)
                )
        )
    }
}

#Preview {
    LimitReachedView()
        .environmentObject(AppState())
        .frame(width: 600, height: 500)
}
