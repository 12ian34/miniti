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
        #if os(iOS)
        static let minimumIconHitSize: CGFloat = 44
        #else
        static let minimumIconHitSize: CGFloat = 24
        #endif
        static let compactHeight: CGFloat = 30
        static let horizontalPadding: CGFloat = 10
        static let modeHorizontalPadding: CGFloat = 10
        static let modeSpacing: CGFloat = 4
    }

    enum Sidebar {
        static let navigationIconSize: CGFloat = 14
        static let navigationIconWidth: CGFloat = 36
        static let navigationIconHeight: CGFloat = 34
        static let collapsedWidth: CGFloat = 52
        static let toggleSize: CGFloat = 26
        static let collapsedToggleSize: CGFloat = 28
        static let footerVerticalPadding: CGFloat = 14
    }

    enum HomeSetup {
        static let maximumWidth: CGFloat = 480
        static let actionColumnWidth: CGFloat = 320
        static let desktopUtilityClearance: CGFloat = 72
        static let footerMaximumDynamicTypeSize: DynamicTypeSize = .xxxLarge
        static let calendarSidebarWidth: CGFloat = 320
        static let calendarRailWidth = Sidebar.collapsedWidth
        static let minimumContentWidth: CGFloat = 360
    }

    enum Documentation {
        static let popoverWidth: CGFloat = 300
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
        static let disclosureDuration: Double = 0.18
        static let transcriptCommitDuration: Double = 0.28
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
    let height: CGFloat?
    let horizontalPadding: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    init(
        role: MinitiControlRole = .secondary,
        isEmphasized: Bool = false,
        height: CGFloat? = MinitiDesignSystem.Control.compactHeight,
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
    var minimumHeight: CGFloat? = nil
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
                .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
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



/// Mirrored sidebar controls share the same footer chrome and shortcut hints.
/// The enclosing native Button owns interaction and accessibility.
struct MinitiSidebarToggleLabel: View {
    let edge: HorizontalEdge
    let isCollapsed: Bool

    var body: some View {
        HStack(spacing: MinitiDesignSystem.Spacing.compact) {
            if !isCollapsed {
                Text(edge == .leading ? "⌘[" : "⌘]")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ColorPalette.Text.dim.opacity(MinitiDesignSystem.ControlOpacity.supportingContent))
            }
            Image(systemName: (edge == .leading) == isCollapsed ? "sidebar.left" : "sidebar.right")
                .font(.system(size: isCollapsed ? 12 : 11, weight: .semibold))
                .foregroundStyle(ColorPalette.Text.dim)
                .frame(width: toggleSize, height: toggleSize)
                .background(RoundedRectangle(cornerRadius: MinitiDesignSystem.Radius.control)
                    .fill(ColorPalette.Background.tertiary))
        }
        .contentShape(Rectangle())
    }

    private var toggleSize: CGFloat {
        isCollapsed ? MinitiDesignSystem.Sidebar.collapsedToggleSize : MinitiDesignSystem.Sidebar.toggleSize
    }
}

/// Home utility actions share typography as well as compact control chrome.
struct MinitiHomeActionLabel: View {
    let icon: String
    let label: String
    var shortcut: String? = nil
    var isEmphasized = false
    var fillsFooterCell = false
    var body: some View {
        if fillsFooterCell {
            MinitiControlLabel(role: .secondary, isEmphasized: isEmphasized, height: nil,
                               horizontalPadding: MinitiDesignSystem.Spacing.small) {
                VStack(spacing: MinitiDesignSystem.Spacing.compact) {
                    Image(systemName: icon).font(.caption.weight(.semibold))
                    Text(label).font(.caption2.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, MinitiDesignSystem.Spacing.standard)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: MinitiDesignSystem.Control.minimumIconHitSize)
            }
        } else {
            MinitiControlLabel(role: .secondary, isEmphasized: isEmphasized,
                               height: max(MinitiDesignSystem.Control.compactHeight, MinitiDesignSystem.Control.minimumIconHitSize)) {
                HStack(spacing: MinitiDesignSystem.Spacing.standard) {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                    Text(label).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    if let shortcut, !shortcut.isEmpty {
                        Text(shortcut).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ColorPalette.Text.meta).lineLimit(1)
                    }
                }
            }
        }
    }
}


/// Benefit-led descriptions kept consistent between setup and Settings.
enum AudioProcessingChoiceCopy {
    static let transcription = [
        (provider: "Deepgram", benefit: "More languages and less work for your Mac. Processes audio online."),
        (provider: "This Mac", benefit: "Transcribes audio on your Mac. Downloads about 600 MB.")
    ]
    static let speakers = [
        (provider: "Deepgram", benefit: "Labels speakers as part of online transcription."),
        (provider: "This Mac", benefit: "Separates voices on your Mac. Recommended for a shared microphone.")
    ]
}

/// The same readable provider comparison in Home and Settings.
struct AudioProcessingComparison: View {
    let options: [(provider: String, benefit: String)]

    var body: some View {
        Grid(alignment: .topLeading,
             horizontalSpacing: MinitiDesignSystem.Spacing.section,
             verticalSpacing: MinitiDesignSystem.Spacing.standard) {
            ForEach(options.indices, id: \.self) { index in
                GridRow {
                    Text(options[index].provider)
                        .fontWeight(.medium)
                        .foregroundStyle(ColorPalette.Text.primary)
                        .fixedSize()
                    Text(options[index].benefit)
                        .foregroundStyle(ColorPalette.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
        .lineSpacing(MinitiDesignSystem.Spacing.hairline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stable, topic-specific documentation destinations shared by setup and Settings.
enum MinitiDocumentationTopic: String, CaseIterable {
    case permissions, account, calendar, transcription, speakers, exports, smartMeetings, folders
    var title: String {
        switch self {
        case .permissions: return "Recording access"
        case .account: return "Your account"
        case .calendar: return "Google Calendar"
        case .transcription: return "Transcription"
        case .speakers: return "Speaker separation"
        case .exports: return "Markdown export"
        case .smartMeetings: return "Smart meetings"
        case .folders: return "Meeting folders"
        }
    }
    var url: URL {
        let path: String
        switch self {
        case .permissions: path = "get-started/permissions"
        case .account: path = "reference/account-and-recovery-key"
        case .calendar: path = "integrations/google-calendar"
        case .transcription: path = "features/transcription"
        case .speakers: path = "features/transcription#multi-speaker-diarization"
        case .exports: path = "features/markdown-export"
        case .smartMeetings: path = "features/smart-meetings"
        case .folders: path = "features/folders"
        }
        return URL(string: "https://miniti.app/docs/" + path)!
    }
    var explanation: String {
        switch self {
        case .permissions:
            return "Microphone access lets miniti capture your voice when you record. On Mac, system audio access is checked when recording starts. Opening this guide does not record anything."
        case .account:
            return "Add a verified email for free account recovery. Cloud storage and sync between devices are optional Pro features, enabled separately in Cloud settings. Your recovery key remains a backup."
        case .calendar:
            return "Connect Google Calendar for upcoming meetings, titles and attendees. Automatic recording is a separate choice. Connected calendars no longer need a Home setup task; you can change these choices in Settings, Calendar."
        case .transcription:
            return "Deepgram sends audio to an online transcription service. It supports more languages and leaves more of your Mac available for other work. This Mac processes speech on your device after a model download, so transcription can work offline in supported languages. It uses your Mac’s processing power. The fallback setting can allow Deepgram when the model is not ready. Enabled AI insights still send transcript text to the AI service."
        case .speakers:
            return "Speaker separation labels who spoke when. Deepgram does this as part of online transcription, without running a speaker model on your device. This Mac uses the included model and is recommended for several people sharing one microphone. With local transcription, choose local speaker separation too if you want voices labelled. Local speaker separation alone does not make transcription or AI insights local."
        case .exports:
            return "Save readable copies of your meetings in a folder you choose. If you use an AI assistant with access to that folder, the optional meeting list helps it find the right notes when you ask about past discussions or decisions. miniti updates this list in AGENTS.md whenever it exports a meeting, keeping existing instructions. This does not connect an AI service or upload your notes. Your meeting history stays in miniti."
        case .folders:
            return "Folders help you find related conversations. miniti can organise new completed meetings using text already on your device, with no extra AI request. You can create or rename folders and describe what belongs in them. Existing history changes only after you preview and apply. Cloud sync stays a separate choice."
        case .smartMeetings:
            return "Detect supported calls and finish recordings after the call ends, with a countdown you can cancel. Calendar automatic start is a separate setting."
        }
    }
}

struct MinitiDocumentationLink: View {
    let topic: MinitiDocumentationTopic
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presented = false
    private var usesSheet: Bool {
        #if os(iOS)
        return true
        #else
        return dynamicTypeSize.isAccessibilitySize
        #endif
    }
    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.callout)
                .foregroundStyle(ColorPalette.Text.muted)
                .padding(MinitiDesignSystem.Spacing.compact)
                .frame(minWidth: MinitiDesignSystem.Control.minimumIconHitSize, minHeight: MinitiDesignSystem.Control.minimumIconHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("About \(topic.title.lowercased())")
        .accessibilityLabel("About \(topic.title.lowercased())")
        .accessibilityHint("Shows an explanation and a link to the documentation")
        .accessibilityIdentifier("docs.\(topic.rawValue)")
        .popover(isPresented: Binding(get: { presented && !usesSheet }, set: { presented = $0 })) {
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.comfortable) {
                HStack(alignment: .top) {
                    Text(topic.title).font(.headline)
                    Spacer()
                    Button { presented = false } label: {
                        Image(systemName: "xmark").font(.callout)
                            .frame(minWidth: MinitiDesignSystem.Control.minimumIconHitSize, minHeight: MinitiDesignSystem.Control.minimumIconHitSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close help")
                    .accessibilityIdentifier("docs.close.\(topic.rawValue)")
                }
                explanation
                Link("Read the docs", destination: topic.url)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("docs.open.\(topic.rawValue)")
            }
            .foregroundStyle(ColorPalette.Text.primary)
            .padding(MinitiDesignSystem.Spacing.section)
            .frame(width: MinitiDesignSystem.Documentation.popoverWidth)
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(dynamicTypeSize)
            .presentationCompactAdaptation(.popover)
        }
        .sheet(isPresented: Binding(get: { presented && usesSheet }, set: { presented = $0 })) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Close") { presented = false }
                        .accessibilityLabel("Close help")
                        .accessibilityIdentifier("docs.close.\(topic.rawValue)")
                }
                .padding(MinitiDesignSystem.Spacing.section)
                ScrollView {
                    VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.section) {
                        Text(topic.title).font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        explanation
                        Link("Read the docs", destination: topic.url)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("docs.open.\(topic.rawValue)")
                    }
                    .padding(MinitiDesignSystem.Spacing.section)
                }
                .accessibilityIdentifier("docs.body.\(topic.rawValue)")
            }
            .foregroundStyle(ColorPalette.Text.primary)
            .dynamicTypeSize(dynamicTypeSize)
            #if os(iOS)
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
    }

    private var explanation: some View {
        Text(topic.explanation).font(.callout)
            .foregroundStyle(ColorPalette.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
