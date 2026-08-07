import SwiftUI

/// Compact banner showing remaining managed-mode minutes. Hidden in BYOK mode.
struct UsageBanner: View {
    @EnvironmentObject var appState: AppState
    
    private var usage: MinitiAPIService.UsageInfo? {
        appState.usageInfo
    }
    
    private var isLow: Bool {
        guard let usage else { return false }
        return usage.minutesRemaining < 60
    }
    
    private var isCritical: Bool {
        guard let usage else { return false }
        return usage.minutesRemaining < 15
    }
    
    private var usageProgress: Double {
        if let usage {
            return usage.usagePercentage
        }
        return appState.shouldShowManagedSubscriptionPlaceholder ? 0.35 : 0
    }

    private var accentColor: Color {
        if appState.shouldShowManagedSubscriptionPlaceholder { return Color(hex: "71717A") }
        if appState.isPro { return Color(hex: "A78BFA") }
        if isCritical { return Color(hex: "F85149") }
        if isLow { return Color(hex: "F59E0B") }
        return Color(hex: "3FB950")
    }
    
    var body: some View {
        // Only show in managed mode
        if appState.appMode == .managed {
            HStack(spacing: 10) {
                // Usage bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "1C1C1F"))
                        
                        // Fill
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accentColor.opacity(0.8))
                            .frame(width: geo.size.width * usageProgress)
                    }
                }
                .frame(width: 40, height: 4)
                
                // Label
                if let usage {
                    if usage.isLimitReached {
                        Text("limit reached")
                            .font(.system(size: 10, weight: .semibold, design: .default))
                            .foregroundStyle(Color(hex: "F85149"))
                    } else {
                        Text("\(usage.formattedRemaining) left")
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(accentColor)
                    }
                } else if appState.shouldShowManagedSubscriptionPlaceholder {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("checking plan...")
                            .font(.system(size: 10, weight: .medium, design: .default))
                            .foregroundStyle(Color(hex: "71717A"))
                    }
                } else if appState.isLoadingUsage {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text(appState.isPro ? "pro" : "free")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(appState.isPro ? Color(hex: "A78BFA") : Color(hex: "3FB950"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(hex: "0F0F11"))
                    .overlay(
                        Capsule()
                            .stroke(accentColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
}

/// Larger usage display for the home screen in managed mode.
struct ManagedStatusView: View {
    @EnvironmentObject var appState: AppState
    
    private var usage: MinitiAPIService.UsageInfo? {
        appState.usageInfo
    }
    
    private var accentColor: Color {
        if appState.shouldShowManagedSubscriptionPlaceholder { return Color(hex: "71717A") }
        guard let usage else { return Color(hex: "3FB950") }
        if usage.isPro { return Color(hex: "A78BFA") }
        if usage.minutesRemaining < 15 { return Color(hex: "F85149") }
        if usage.minutesRemaining < 60 { return Color(hex: "F59E0B") }
        return Color(hex: "3FB950")
    }
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 5, height: 5)
                
                Text(appState.shouldShowManagedSubscriptionPlaceholder ? "checking plan..." : (appState.isPro ? "miniti pro" : "miniti free"))
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "A1A1AA"))
                
                if let usage {
                    Text("•")
                        .foregroundStyle(Color(hex: "484F58"))
                    Text("\(Int(usage.minutesRemaining)) min left")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(accentColor)
                }
            }
            
            if let usage {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: "1C1C1F"))
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor.opacity(0.6), accentColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(2, geo.size.width * usage.usagePercentage))
                        }
                    }
                    .frame(width: 200, height: 6)
                    
                    HStack {
                        Text("\(Int(usage.minutesUsed.rounded()))m used")
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(Color(hex: "71717A"))
                        
                        Spacer()
                        
                        Text("\(Int(usage.minutesLimit))m total")
                            .font(.system(size: 10, weight: .regular, design: .default))
                            .foregroundStyle(Color(hex: "71717A"))
                    }
                    .frame(width: 200)
                }
            } else if appState.shouldShowManagedSubscriptionPlaceholder {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: "1C1C1F"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: "71717A").opacity(0.35))
                            .frame(width: 70, alignment: .leading),
                        alignment: .leading
                    )
                    .frame(width: 200, height: 6)
            }
            
            #if os(macOS)
            if !appState.shouldShowManagedSubscriptionPlaceholder && !appState.isPro {
                Button {
                    Task { await appState.openSubscribePage() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10))
                        Text("upgrade to pro")
                            .font(.system(size: 10, weight: .semibold, design: .default))
                    }
                    .foregroundStyle(Color(hex: "A78BFA"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(hex: "A78BFA").opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(hex: "A78BFA").opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            #endif
            
        }
    }
}

/// Sheet for entering a Polar license key to restore a subscription.
#if os(macOS)
struct RestoreLicenseKeySheet: View {
    @Binding var licenseKeyInput: String
    @Binding var isRestoring: Bool
    @Binding var restoreError: String?
    let onRestore: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("restore subscription")
                .font(.system(size: 14, weight: .bold, design: .default))
                .foregroundStyle(Color(hex: "E6EDF3"))
            
            Text("Enter the license key from your purchase email or Polar account.")
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "A1A1AA"))
                .multilineTextAlignment(.center)
            
            TextField("license key", text: $licenseKeyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .default))
                .frame(width: 300)
            
            if let restoreError {
                Text(restoreError)
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(Color(hex: "F85149"))
            }
            
            HStack(spacing: 12) {
                Button("cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(Color(hex: "71717A"))
                
                Button {
                    onRestore()
                } label: {
                    if isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("restore")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: "A78BFA"))
                .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRestoring)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color(hex: "0F0F11"))
    }
}
#endif

#Preview {
    VStack(spacing: 20) {
        UsageBanner()
        ManagedStatusView()
    }
    .environmentObject(AppState())
    .frame(width: 400, height: 200)
    .background(Color(hex: "09090B"))
}
