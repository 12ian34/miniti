import SwiftUI

// MARK: - Interface Scale

/// User-selectable interface sizing. Compact intentionally preserves the
/// pre-scaling presentation so users can always return to the original density.
enum InterfaceScale: Int, CaseIterable, Identifiable {
    static let storageKey = "interfaceScale"

    case compact = 0
    case standard = 1
    case large = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .large: return "Large"
        }
    }

    func dynamicTypeSize(from systemSize: DynamicTypeSize) -> DynamicTypeSize {
        let sizes = DynamicTypeSize.allCases
        guard let currentIndex = sizes.firstIndex(of: systemSize) else { return systemSize }
        let targetIndex = min(currentIndex + rawValue, sizes.index(before: sizes.endIndex))
        return sizes[targetIndex]
    }

    var transcriptBodySize: CGFloat {
        #if os(macOS)
        switch self {
        case .compact: return 13
        case .standard: return 14
        case .large: return 15
        }
        #else
        switch self {
        case .compact: return 13
        case .standard: return 15
        case .large: return 17
        }
        #endif
    }

    var transcriptHeaderSize: CGFloat {
        #if os(macOS)
        switch self {
        case .compact: return 10
        case .standard: return 11
        case .large: return 12
        }
        #else
        switch self {
        case .compact: return 10
        case .standard: return 11.5
        case .large: return 13
        }
        #endif
    }

    var transcriptLineSpacing: CGFloat {
        #if os(macOS)
        switch self {
        case .compact: return 2
        case .standard: return 4
        case .large: return 5
        }
        #else
        switch self {
        case .compact: return 2
        case .standard: return 5
        case .large: return 6
        }
        #endif
    }

    /// Insight prose intentionally matches transcript prose at every scale so
    /// switching panes never changes the reading size.
    var insightBodySize: CGFloat {
        transcriptBodySize
    }

    var insightSecondarySize: CGFloat {
        insightBodySize
    }

    var insightLineSpacing: CGFloat {
        transcriptLineSpacing
    }
}

private struct InterfaceScaleEnvironmentKey: EnvironmentKey {
    static let defaultValue = InterfaceScale.compact
}

extension EnvironmentValues {
    var interfaceScale: InterfaceScale {
        get { self[InterfaceScaleEnvironmentKey.self] }
        set { self[InterfaceScaleEnvironmentKey.self] = newValue }
    }
}

/// Clears descendant animation transactions when the user enables Reduce Motion.
/// Applying this once at each app root also covers animations introduced by
/// system-scale changes without requiring every view to remember the setting.
private struct ReduceMotionAwareModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}

extension View {
    func minitiReduceMotionAware() -> some View {
        modifier(ReduceMotionAwareModifier())
    }

    /// Uses the current system material for small utility surfaces on the newest
    /// iOS while leaving the established terminal surfaces untouched elsewhere.
    @ViewBuilder
    func minitiAdaptiveUtilitySurface(tint: Color? = nil) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            glassEffect(
                .regular.tint(tint),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        } else {
            self
        }
        #else
        self
        #endif
    }
}

struct InterfaceScaleSlider: View {
    @AppStorage(InterfaceScale.storageKey) private var rawScale = InterfaceScale.standard.rawValue

    private var selectedScale: InterfaceScale {
        InterfaceScale(rawValue: rawScale) ?? .standard
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(selectedScale.rawValue) },
            set: { rawScale = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Interface scale")
                Spacer()
                Text(selectedScale.title)
                    .foregroundStyle(.secondary)
            }

            Slider(value: sliderValue, in: 0...2, step: 1)
                .accessibilityLabel("Interface scale")
                .accessibilityValue(selectedScale.title)

            HStack {
                ForEach(InterfaceScale.allCases) { scale in
                    Text(scale.title)
                        .font(.caption)
                        .foregroundStyle(scale == selectedScale ? .primary : .secondary)
                    if scale != InterfaceScale.allCases.last {
                        Spacer()
                    }
                }
            }

            Text("Adjusts readable text and controls while keeping navigation and insight tabs compact.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Color Extension (must be defined before ColorPalette uses it)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Global Color Palette
/// Centralized color palette for the entire app. All colors should reference this palette.
struct ColorPalette {
    // MARK: - Background Colors
    struct Background {
        static let primary = Color(hex: "09090B")      // Main app background (near black)
        static let secondary = Color(hex: "0C0C0E")    // Sidebar, panels
        static let tertiary = Color(hex: "111113")     // Card backgrounds
        static let panel = Color(hex: "0F0F11")         // Panel backgrounds
        static let card = Color(hex: "18181B")          // Card/elevated surfaces
    }
    
    // MARK: - Border Colors
    struct Border {
        static let primary = Color(hex: "1C1C1F")      // Main borders
        static let light = Color(hex: "27272A")        // Lighter borders
        static let hover = Color(hex: "3F3F46")        // Hover state borders
        static let subtle = Color(hex: "30363D")        // Very subtle borders
    }
    
    // MARK: - Text Colors
    struct Text {
        static let primary = Color(hex: "FAFAFA")      // Primary text
        static let secondary = Color(hex: "E6EDF3")     // Secondary text
        static let muted = Color(hex: "D4D4D8")         // Muted text
        static let dim = Color(hex: "A1A1AA")           // Dim text
        static let disabled = Color(hex: "71717A")       // Disabled text
        static let placeholder = Color(hex: "52525B")    // Placeholder text
        static let subtle = Color(hex: "484F58")        // Very subtle text
        static let meta = Color(hex: "8B949E")          // Meta/helper text
    }
    
    // MARK: - Accent Colors
    struct Accent {
        static let green = Color(hex: "22C55E")         // Primary green accent
        static let greenGitHub = Color(hex: "3FB950")   // GitHub-style green
        static let blue = Color(hex: "3B82F6")          // Primary blue
        static let blueGitHub = Color(hex: "58A6FF")    // GitHub-style blue
        static let purple = Color(hex: "A855F7")        // Primary purple
        static let purpleLight = Color(hex: "A78BFA")   // Light purple
        static let purpleSoft = Color(hex: "A371F7")    // Soft purple
        static let red = Color(hex: "EF4444")           // Primary red
        static let redGitHub = Color(hex: "F85149")     // GitHub-style red
        static let amber = Color(hex: "F59E0B")         // Amber/orange
        static let yellow = Color(hex: "FCE728")        // Yellow
        static let pink = Color(hex: "EC4899")          // Pink
        static let cyan = Color(hex: "06B6D4")          // Cyan
        static let orange = Color(hex: "D29922")       // Orange
        static let zonedOut = Color(hex: "D2A8FF")     // Zoned Out catch-up
    }

    // MARK: - Coaching Metric Colors
    /// Stable content taxonomy for coaching metrics. These deliberately do not
    /// reuse control-role or trend-status tokens, even when the hue is related.
    struct Coaching {
        static let fillers = Color(hex: "E3B341")       // Gold
        static let pace = Color(hex: "79C0FF")          // Periwinkle blue
        static let clarity = Color(hex: "BC8CFF")       // Lavender
        static let questions = Color(hex: "FF9B71")     // Warm coral
        static let talkRatio = Color(hex: "39C5CF")     // Cyan
        static let monologue = Color(hex: "F778BA")     // Rose
    }

    // MARK: - Integration Colors
    struct Integrations {
        static let attio = Color(hex: "F97316")
        static let attioLight = Color(hex: "FB923C")
        static let attioPale = Color(hex: "FDBA74")
        static let twenty = Color(hex: "E6EDF3")
    }
    
    // MARK: - Status Colors
    struct Status {
        static let success = Accent.greenGitHub         // Success states
        static let error = Accent.redGitHub             // Error states
        static let warning = Accent.amber               // Warning states
        static let info = Accent.blueGitHub              // Info states
        static let recording = Accent.redGitHub           // Recording indicator
        static let connected = Accent.greenGitHub        // Connected state
        static let disconnected = Text.disabled          // Disconnected state
        static let limitReached = Accent.redGitHub      // Usage limit reached
        static let noApiKey = Accent.amber               // Missing API key
    }
    
    // MARK: - Speaker Colors
    /// Colors for speaker diarization. Index 0 = first remote speaker.
    struct Speaker {
        static let mic = Accent.greenGitHub             // "You" (local mic speaker)
        static let remote: [Color] = [
            Accent.blueGitHub,      // Blue
            Accent.purpleSoft,      // Purple
            Accent.orange,           // Orange
            Color(hex: "F778BA"),   // Pink
            Color(hex: "79C0FF"),    // Cyan
            Color(hex: "FFA657"),    // Light orange
            Color(hex: "7EE787"),   // Light green
        ]
        
        /// Get color for a speaker ID. Returns mic color for mic speaker, cycles through remote colors otherwise.
        static func color(for speaker: Int, micSpeakerID: Int) -> Color {
            if speaker == micSpeakerID {
                return mic
            }
            return remote[speaker % remote.count]
        }
    }
    
    // MARK: - MEDDPICC Colors
    /// Colors for MEDDPICC framework fields
    struct MEDDPICC {
        static let metrics = Accent.blue                 // M - Metrics
        static let economicBuyer = Color(hex: "A78BFA") // E - Economic Buyer (WCAG AA on dark surfaces)
        static let decisionCriteria = Accent.pink       // D - Decision Criteria
        static let decisionProcess = Accent.amber        // D - Decision Process
        static let paperProcess = Color(hex: "F97316")  // P - Paper Process
        static let identifiedPain = Accent.red           // I - Identified Pain
        static let champion = Accent.green               // C - Champion
        static let competition = Color(hex: "818CF8")    // C - Competition (WCAG AA on dark surfaces)

        /// Get color for a MEDDPICC field by letter
        static func color(for letter: String) -> String {
            switch letter.uppercased() {
            case "M": return "3B82F6"
            case "E": return "A78BFA"
            case "D": return "EC4899"
            case "P": return "F59E0B"
            case "I": return "EF4444"
            case "C": return "22C55E"
            default: return "3B82F6"
            }
        }
    }
    
    // MARK: - Template Section Colors
    /// Colors for the Templates specialist view. Sections take colors in order, so
    /// a template's first section is always blue, its second lavender, and so on —
    /// stable across live, saved, macOS, and iOS.
    struct Templates {
        static let sectionColors: [Color] = [
            Accent.blue,
            Color(hex: "A78BFA"),
            Accent.pink,
            Accent.amber,
            Accent.green,
            Color(hex: "818CF8"),
            Color(hex: "F97316"),
            Accent.cyan,
        ]

        static func color(forSectionAt index: Int) -> Color {
            sectionColors[((index % sectionColors.count) + sectionColors.count) % sectionColors.count]
        }
    }

    // MARK: - Insight Section Colors
    struct Insights {
        static let summary = Accent.blueGitHub          // Summary section
        static let discussion = Accent.amber             // Discussion flow
        static let actions = Accent.greenGitHub          // Action items
        static let topics = Accent.purpleSoft            // Topics/tags
        static let meddpicc = Accent.amber               // MEDDPICC framework
    }
}
