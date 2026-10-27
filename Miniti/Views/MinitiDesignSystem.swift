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

    enum CoachingTypography {
        /// Coaching is a reading-heavy desktop surface, so it steps fixed
        /// compact metrics up without changing the already-accessible iPhone scale.
        static func size(_ compactSize: CGFloat) -> CGFloat {
            #if os(macOS)
            return compactSize + 2
            #else
            return compactSize
            #endif
        }
    }

    enum CoachingLayout {
        static let trendColumnMaxWidth: CGFloat = 720
        static let compactColumnMaxWidth: CGFloat = 480
        static let statsColumnMaxWidth: CGFloat = 720
        #if os(macOS)
        static let statsChartHeight: CGFloat = 116
        #else
        static let statsChartHeight: CGFloat = 108
        #endif
    }

    enum Motion {
        static let hoverDuration: Double = 0.12
        static let navigationCueDismissDuration: Double = 0.14
    }

    enum NavigationGesture {
        static let commitDistance: CGFloat = 84
        static let horizontalDominanceRatio: CGFloat = 1.4
        static let cueDiameter: CGFloat = 36
        static let cueEdgeInset: CGFloat = 12
        static let cueTravel: CGFloat = 14
    }

    enum ControlOpacity {
        static let restingFill = 0.10
        static let hoverFill = 0.14
        static let emphasizedFill = 0.18
        static let restingBorder = 0.26
        static let hoverBorder = 0.34
        static let emphasizedBorder = 0.40
        static let supportingContent = 0.55
    }

    enum ContentAccent {
        static let summary = ColorPalette.Accent.blueGitHub
        static let questions = ColorPalette.Accent.purpleLight
        static let sales = ColorPalette.Accent.pink
        static let playbook = ColorPalette.Accent.purpleSoft
        static let zonedOut = ColorPalette.Accent.zonedOut

        static func coachingMetric(_ metric: CoachingMetric) -> Color {
            switch metric {
            case .fillers: return ColorPalette.Coaching.fillers
            case .pace: return ColorPalette.Coaching.pace
            case .clarity: return ColorPalette.Coaching.clarity
            case .questions: return ColorPalette.Coaching.questions
            case .talkRatio: return ColorPalette.Coaching.talkRatio
            case .monologue: return ColorPalette.Coaching.monologue
            }
        }
    }

    enum NavigationCopy {
        /// Product-authored tabs use sentence-style lowercase labels on every
        /// platform. Accessibility labels remain supplied by the native owner.
        static func tabTitle(_ title: String) -> String {
            title.lowercased()
        }
    }
}

enum MinitiControlRole {
    case primary
    case secondary
    case positive
    case recording
    case destructive
    case warning

    var accent: Color {
        switch self {
        case .primary: return ColorPalette.Accent.blueGitHub
        case .secondary: return ColorPalette.Text.muted
        case .positive: return ColorPalette.Accent.greenGitHub
        case .recording, .destructive: return ColorPalette.Accent.redGitHub
        case .warning: return ColorPalette.Accent.amber
        }
    }

    fileprivate var usesNeutralChrome: Bool {
        self == .secondary
    }
}

enum MinitiCardSurfaceStyle {
    case standard
    case inset
    case accented(Color)

    fileprivate var fill: Color {
        switch self {
        case .standard: return ColorPalette.Background.tertiary
        case .inset: return ColorPalette.Background.panel
        case .accented: return ColorPalette.Background.panel
        }
    }

    fileprivate var border: Color {
        switch self {
        case .standard: return ColorPalette.Border.primary
        case .inset: return ColorPalette.Border.light
        case .accented(let accent): return accent.opacity(0.35)
        }
    }
}

/// Shared Miniti-owned card chrome. Feature views provide content and semantic
/// accent only; padding, radius, fill, and border stay consistent here.
struct MinitiCardSurface<Content: View>: View {
    let style: MinitiCardSurfaceStyle
    let contentPadding: CGFloat
    let height: CGFloat?
    @ViewBuilder let content: () -> Content

    init(
        style: MinitiCardSurfaceStyle = .standard,
        contentPadding: CGFloat = MinitiDesignSystem.Spacing.comfortable,
        height: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.style = style
        self.contentPadding = contentPadding
        self.height = height
        self.content = content
    }

    var body: some View {
        content()
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                    .fill(style.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                            .stroke(style.border, lineWidth: 1)
                    )
            )
    }
}

/// A quiet content separator that carries a section accent into the interface
/// without turning the surrounding content into another bordered surface.
struct MinitiFadingDivider: View {
    let accent: Color

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: accent.opacity(0.62), location: 0),
                        .init(color: ColorPalette.Border.light.opacity(0.52), location: 0.42),
                        .init(color: ColorPalette.Border.light.opacity(0.18), location: 0.72),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Shared compact control chrome. The enclosing Button or Menu retains
/// ownership of actions, focus, disabled state, shortcuts, and accessibility.
struct MinitiControlLabel<Content: View>: View {
    let role: MinitiControlRole
    let isEmphasized: Bool
    let height: CGFloat
    let horizontalPadding: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    init(
        role: MinitiControlRole = .secondary,
        isEmphasized: Bool = false,
        height: CGFloat = MinitiDesignSystem.Control.compactHeight,
        horizontalPadding: CGFloat = MinitiDesignSystem.Control.horizontalPadding,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.role = role
        self.isEmphasized = isEmphasized
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.content = content
    }

    var body: some View {
        content()
            .foregroundStyle(foregroundColor)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                    .stroke(borderColor, lineWidth: 1)
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

    private var foregroundColor: Color {
        if role.usesNeutralChrome {
            return isEmphasized || isHovered ? ColorPalette.Text.primary : ColorPalette.Text.muted
        }
        return role.accent
    }

    private var fillColor: Color {
        if role.usesNeutralChrome {
            if isEmphasized { return ColorPalette.Background.card }
            if isHovered { return ColorPalette.Background.tertiary }
            return ColorPalette.Background.panel
        }
        return role.accent.opacity(fillOpacity)
    }

    private var borderColor: Color {
        if role.usesNeutralChrome {
            return isEmphasized || isHovered ? ColorPalette.Border.light : ColorPalette.Border.primary
        }
        return role.accent.opacity(borderOpacity)
    }

    private var fillOpacity: Double {
        if isEmphasized { return MinitiDesignSystem.ControlOpacity.emphasizedFill }
        if isHovered { return MinitiDesignSystem.ControlOpacity.hoverFill }
        return MinitiDesignSystem.ControlOpacity.restingFill
    }

    private var borderOpacity: Double {
        if isEmphasized { return MinitiDesignSystem.ControlOpacity.emphasizedBorder }
        if isHovered { return MinitiDesignSystem.ControlOpacity.hoverBorder }
        return MinitiDesignSystem.ControlOpacity.restingBorder
    }
}

/// Visual label for mutually exclusive views. Selection is communicated with
/// neutral contrast so content-category colors remain inside the content.
struct MinitiTabLabel: View {
    let title: String
    let isSelected: Bool
    let height: CGFloat
    let fillsAvailableWidth: Bool

    init(
        title: String,
        isSelected: Bool,
        height: CGFloat = MinitiDesignSystem.Control.compactHeight,
        fillsAvailableWidth: Bool = false
    ) {
        self.title = title
        self.isSelected = isSelected
        self.height = height
        self.fillsAvailableWidth = fillsAvailableWidth
    }

    var body: some View {
        Text(MinitiDesignSystem.NavigationCopy.tabTitle(title))
            .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .default))
            .foregroundStyle(isSelected ? ColorPalette.Text.primary : ColorPalette.Text.muted)
            .lineLimit(1)
            .frame(height: height)
            .padding(.horizontal, MinitiDesignSystem.Control.modeHorizontalPadding)
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                    .fill(isSelected ? ColorPalette.Background.card : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                    .stroke(isSelected ? ColorPalette.Border.light : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control))
    }
}

struct MinitiTabStripSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(MinitiDesignSystem.Spacing.compact)
            .background(
                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                    .fill(ColorPalette.Background.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.card)
                            .stroke(ColorPalette.Border.primary, lineWidth: 1)
                    )
            )
    }
}

/// Settings disclosures: a full-width row with the title, an optional trailing summary and a
/// chevron in a small round well that turns when open, instead of the bare ">" of the default
/// style (Ian, 2026-10-27). Content slides in below with a left inset. Reduce Motion drops
/// the turn and the slide.
struct MinitiDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if reduceMotion {
                    configuration.isExpanded.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) { configuration.isExpanded.toggle() }
                }
            } label: {
                HStack(spacing: MinitiDesignSystem.Spacing.standard) {
                    configuration.label
                    Spacer(minLength: MinitiDesignSystem.Spacing.standard)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 180 : 0))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(ColorPalette.Background.card))
                        .overlay(Circle().stroke(ColorPalette.Border.primary, lineWidth: 1))
                }
                .contentShape(Rectangle())
                .padding(.vertical, MinitiDesignSystem.Spacing.hairline)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isExpanded ? "expanded" : "collapsed")
            #if os(macOS)
            .onHover { hovering = $0 }
            .background(
                RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                    .fill(ColorPalette.Text.dim.opacity(hovering ? 0.08 : 0))
                    .padding(.horizontal, -MinitiDesignSystem.Spacing.small)
            )
            #endif
            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
                    configuration.content
                }
                .padding(.leading, MinitiDesignSystem.Spacing.compact)
                .padding(.top, MinitiDesignSystem.Spacing.standard)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// One clipboard helper for every copy button.
enum MinitiPasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

