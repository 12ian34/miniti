import SwiftUI

/// Reusable visual contracts for Miniti-owned interface elements.
///
/// This layer captures the app's established appearance; it does not replace
/// native platform controls where their behaviour is part of the experience.
enum MinitiDesignSystem {
    enum Spacing {
        static let hairline: CGFloat = 2
        static let compact: CGFloat = 4
        static let small: CGFloat = 6
        static let standard: CGFloat = 8
        static let control: CGFloat = 10
        static let comfortable: CGFloat = 12
        static let section: CGFloat = 16
        static let page: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let utilitySurface: CGFloat = 10
    }

    enum Control {
        static let compactHeight: CGFloat = 30
        static let horizontalPadding: CGFloat = 10
        static let modeHorizontalPadding: CGFloat = 10
        static let modeSpacing: CGFloat = 4
    }

    enum Motion {
        static let hoverDuration: Double = 0.12
    }

    enum VibeyOpacity {
        static let restingFill = 0.10
        static let hoverFill = 0.14
        static let emphasizedFill = 0.18
        static let restingBorder = 0.26
        static let hoverBorder = 0.34
        static let emphasizedBorder = 0.40
        static let supportingContent = 0.55
    }

    enum Accent {
        static let navigation = ColorPalette.Accent.blueGitHub
        static let recording = ColorPalette.Accent.redGitHub
        static let resume = ColorPalette.Accent.greenGitHub
        static let coaching = ColorPalette.Accent.amber
        static let zonedOut = ColorPalette.Accent.zonedOut

        static func insightMode(_ mode: InsightsMode) -> Color {
            switch mode {
            case .standard: return ColorPalette.Accent.blueGitHub
            case .questions: return ColorPalette.Accent.purpleLight
            case .training: return coaching
            case .meddpicc: return ColorPalette.Accent.pink
            case .docs: return ColorPalette.Accent.purpleSoft
            }
        }
    }
}

#if os(macOS)
/// The shared compact, accent-tinted surface used by Miniti's high-frequency
/// actions and insight modes. The enclosing Button or Menu retains ownership
/// of actions, shortcuts, focus, disabled state, menus, and accessibility.
struct MinitiVibeyLabel<Content: View>: View {
    let accent: Color
    let isEmphasized: Bool
    let height: CGFloat
    let horizontalPadding: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    init(
        accent: Color,
        isEmphasized: Bool = false,
        height: CGFloat = MinitiDesignSystem.Control.compactHeight,
        horizontalPadding: CGFloat = MinitiDesignSystem.Control.horizontalPadding,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.accent = accent
        self.isEmphasized = isEmphasized
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.content = content
    }

    var body: some View {
        content()
            .foregroundStyle(accent)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                    .fill(accent.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                    .stroke(accent.opacity(borderOpacity), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control))
            .onHover { hovering in
                if reduceMotion {
                    isHovered = hovering
                } else {
                    withAnimation(.easeOut(duration: MinitiDesignSystem.Motion.hoverDuration)) {
                        isHovered = hovering
                    }
                }
            }
    }

    private var fillOpacity: Double {
        if isEmphasized { return MinitiDesignSystem.VibeyOpacity.emphasizedFill }
        if isHovered { return MinitiDesignSystem.VibeyOpacity.hoverFill }
        return MinitiDesignSystem.VibeyOpacity.restingFill
    }

    private var borderOpacity: Double {
        if isEmphasized { return MinitiDesignSystem.VibeyOpacity.emphasizedBorder }
        if isHovered { return MinitiDesignSystem.VibeyOpacity.hoverBorder }
        return MinitiDesignSystem.VibeyOpacity.restingBorder
    }
}
#endif
