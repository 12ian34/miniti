import SwiftUI

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
