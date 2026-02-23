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
    
    private var accentColor: Color {
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
                            .frame(width: geo.size.width * (usage?.usagePercentage ?? 0))
                    }
                }
                .frame(width: 40, height: 4)
                
                // Label
                if let usage {
                    if usage.isLimitReached {
                        Text("limit reached")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "F85149"))
                    } else {
                        Text("\(usage.formattedRemaining) left")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(accentColor)
                    }
                } else if appState.isLoadingUsage {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Text("free")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "3FB950"))
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
        guard let usage else { return Color(hex: "3FB950") }
        if usage.minutesRemaining < 15 { return Color(hex: "F85149") }
        if usage.minutesRemaining < 60 { return Color(hex: "F59E0B") }
        return Color(hex: "3FB950")
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // Managed plan status (textual, not button-like)
            HStack(spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 5, height: 5)
                
                Text("miniti free")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: "A1A1AA"))
                
                if let usage {
                    Text("•")
                        .foregroundStyle(Color(hex: "484F58"))
                    Text("\(Int(usage.minutesRemaining)) min left")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(accentColor)
                }
            }
            
            // Usage progress bar
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
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "71717A"))
                        
                        Spacer()
                        
                        Text("\(Int(usage.minutesLimit))m total")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(hex: "71717A"))
                    }
                    .frame(width: 200)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        UsageBanner()
        ManagedStatusView()
    }
    .environmentObject(AppState())
    .frame(width: 400, height: 200)
    .background(Color(hex: "09090B"))
}
