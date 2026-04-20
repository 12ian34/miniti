import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Read-only text view backed by native AppKit/UIKit so users can select and copy
/// across multiple paragraphs/segments — something SwiftUI's `Text` cannot do
/// when multiple `Text` views are stacked.
struct SelectableTextView: View {
    let attributed: NSAttributedString

    init(_ attributed: NSAttributedString) {
        self.attributed = attributed
    }

    var body: some View {
        #if os(macOS)
        _SelectableTextViewMac(attributed: attributed)
        #else
        _SelectableTextViewIOS(attributed: attributed)
        #endif
    }
}

#if os(macOS)
private struct _SelectableTextViewMac: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> _SelectableTextContainer {
        _SelectableTextContainer(attributed: attributed)
    }

    func updateNSView(_ nsView: _SelectableTextContainer, context: Context) {
        nsView.apply(attributed)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: _SelectableTextContainer, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0 else { return nil }
        let height = nsView.measuredHeight(for: width)
        return CGSize(width: width, height: height)
    }
}

final class _SelectableTextContainer: NSView {
    private let textView: NSTextView
    private var lastMeasuredWidth: CGFloat = -1
    private var lastMeasuredHeight: CGFloat = 0

    init(attributed: NSAttributedString) {
        let tv = NSTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        // Disable autoresizing-mask-derived constraints. Without this, AppKit
        // regenerates autoresizing constraints on every bounds change and
        // forwards the engine events to SwiftUI's hosting view, which schedules
        // a setNeedsUpdateConstraints mid-traversal and crashes the window
        // display cycle with an NSInternalInconsistencyException.
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.textStorage?.setAttributedString(attributed)
        self.textView = tv
        super.init(frame: .zero)
        addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: trailingAnchor),
            tv.topAnchor.constraint(equalTo: topAnchor),
            tv.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ attributed: NSAttributedString) {
        guard textView.textStorage?.isEqual(to: attributed) == false else { return }
        textView.textStorage?.setAttributedString(attributed)
        lastMeasuredWidth = -1
        // Do NOT call invalidateIntrinsicContentSize() or needsLayout = true here.
        // updateNSView can run inside an in-progress SwiftUI/AppKit layout pass,
        // and either call would propagate setNeedsUpdateConstraints up the host
        // view chain during layout, which AppKit traps as a recursive constraint
        // update. Sizing is driven by our sizeThatFits(_:nsView:context:)
        // implementation, so SwiftUI re-measures automatically when the
        // representable's attributed input changes.
    }

    func measuredHeight(for width: CGFloat) -> CGFloat {
        if abs(width - lastMeasuredWidth) < 0.5 { return lastMeasuredHeight }
        guard let storage = textView.textStorage else { return 0 }
        // Measure via the attributed string directly. NSTextView's layout manager
        // can under-report height on the first render (before glyphs have been
        // generated / the view is in a window), which let the interim row paint
        // on top of the first finalized segment.
        // Do NOT mutate textView/textContainer state here — sizeThatFits runs
        // during SwiftUI measurement and any layout-triggering side effect can
        // re-enter the window's constraint traversal.
        let rect = storage.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        lastMeasuredWidth = width
        lastMeasuredHeight = ceil(rect.height)
        return lastMeasuredHeight
    }
}

#else

private struct _SelectableTextViewIOS: UIViewRepresentable {
    let attributed: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = []
        tv.adjustsFontForContentSizeCategory = false
        tv.attributedText = attributed
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.attributedText != attributed {
            uiView.attributedText = attributed
            uiView.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }
}
#endif

// MARK: - Attributed string builders

enum SelectableAttributed {
    /// Build an attributed transcript from segments. Each turn gets a small header
    /// line (speaker · m:ss) in the speaker's color, then the body text in primary.
    /// The whole thing is one attributed string so selection spans across turns.
    static func transcript(
        turns: [TranscriptTurn],
        speakerNames: [String: String]?,
        selfIDs: Set<Int>? = nil,
        bodyFontSize: CGFloat = 13,
        headerFontSize: CGFloat = 10
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = monoFont(size: bodyFontSize, weight: .regular)
        let headerFont = monoFont(size: headerFontSize, weight: .semibold)
        let bodyPara = NSMutableParagraphStyle()
        bodyPara.paragraphSpacing = 6
        bodyPara.lineSpacing = 2
        let headerPara = NSMutableParagraphStyle()
        headerPara.paragraphSpacingBefore = 10
        headerPara.paragraphSpacing = 2

        for (index, turn) in turns.enumerated() {
            let speakerColor = platformColor(for: speakerColor(for: turn.speaker, selfIDs: selfIDs))
            let label = speakerLabel(for: turn.speaker, names: speakerNames, selfIDs: selfIDs)
            let timestamp = formatTimestamp(turn.timestamp)
            let header = "\(label) · \(timestamp)\n"
            result.append(NSAttributedString(string: header, attributes: [
                .font: headerFont,
                .foregroundColor: speakerColor,
                .paragraphStyle: index == 0 ? bodyPara : headerPara,
            ]))
            let body = turn.text + (index == turns.count - 1 ? "" : "\n")
            result.append(NSAttributedString(string: body, attributes: [
                .font: bodyFont,
                .foregroundColor: platformColor(for: Color(hex: "E6EDF3")),
                .paragraphStyle: bodyPara,
            ]))
        }
        return result
    }

    /// Build a plain monospaced attributed string from a single body of text.
    static func body(
        _ text: String,
        fontSize: CGFloat = 13,
        color: Color = Color(hex: "E6EDF3"),
        lineSpacing: CGFloat = 6
    ) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: monoFont(size: fontSize, weight: .regular),
            .foregroundColor: platformColor(for: color),
            .paragraphStyle: para,
        ])
    }

    /// Bulleted list — each item rendered on its own line with a prefix, all in one string.
    static func bulletList(
        items: [String],
        prefix: String,
        prefixColor: Color,
        fontSize: CGFloat = 13,
        textColor: Color = Color(hex: "E6EDF3")
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = monoFont(size: fontSize, weight: .regular)
        let prefixFont = monoFont(size: fontSize, weight: .medium)
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 6
        para.headIndent = (prefix.count == 3 ? 32 : 20) // crude indent for wrapped lines
        for (idx, item) in items.enumerated() {
            result.append(NSAttributedString(string: prefix + " ", attributes: [
                .font: prefixFont,
                .foregroundColor: platformColor(for: prefixColor),
                .paragraphStyle: para,
            ]))
            let trailing = idx == items.count - 1 ? "" : "\n"
            result.append(NSAttributedString(string: item + trailing, attributes: [
                .font: font,
                .foregroundColor: platformColor(for: textColor),
                .paragraphStyle: para,
            ]))
        }
        return result
    }

    struct TranscriptTurn {
        let speaker: Int
        let timestamp: TimeInterval
        let text: String
    }

    /// Merge consecutive turns that would render as the same on-screen speaker, unless
    /// the previous turn ended with a sentence terminator. Groups all self-IDs into
    /// one "you" bucket and collapses IDs that share an inferred/manual name, so
    /// diarization drift across IDs doesn't fragment a single speaker into multiple
    /// visual blocks in saved transcripts.
    static func mergeTurns(
        _ turns: [TranscriptTurn],
        speakerNames: [String: String]?,
        selfIDs: Set<Int>?
    ) -> [TranscriptTurn] {
        var merged: [TranscriptTurn] = []
        merged.reserveCapacity(turns.count)
        for turn in turns {
            if let last = merged.last,
               turnDisplayKey(last.speaker, names: speakerNames, selfIDs: selfIDs)
                == turnDisplayKey(turn.speaker, names: speakerNames, selfIDs: selfIDs),
               !endsSentence(last.text) {
                merged[merged.count - 1] = TranscriptTurn(
                    speaker: last.speaker,
                    timestamp: last.timestamp,
                    text: joinTranscriptFragments(last.text, turn.text)
                )
            } else {
                merged.append(turn)
            }
        }
        return merged
    }

    static func displayGroupKey(speaker: Int, names: [String: String]?, selfIDs: Set<Int>?) -> String {
        turnDisplayKey(speaker, names: names, selfIDs: selfIDs)
    }

    private static func turnDisplayKey(_ speaker: Int, names: [String: String]?, selfIDs: Set<Int>?) -> String {
        let effectiveSelves: Set<Int> = (selfIDs?.isEmpty == false) ? selfIDs! : [DeepgramService.micSpeakerID]
        if effectiveSelves.contains(speaker) { return "self" }
        if let mapped = names?[String(speaker)]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mapped.isEmpty {
            return "name:\(mapped.lowercased())"
        }
        return "id:\(speaker)"
    }

    private static func endsSentence(_ text: String) -> Bool {
        let trailingClosers = CharacterSet(charactersIn: "\"'”’)]}")
        let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let scalar = trimmed.unicodeScalars.last, trailingClosers.contains(scalar) {
            trimmed.removeLast()
        }
        guard let last = trimmed.last else { return false }
        return sentenceTerminators.contains(last)
    }

    private static func joinTranscriptFragments(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }
        let noLeadingSpaceChars: Set<Character> = [",", ".", "!", "?", ";", ":", ")", "]", "}"]
        if let first = right.first, noLeadingSpaceChars.contains(first) {
            return left + right
        }
        return left + " " + right
    }

    private static func formatTimestamp(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    #if os(macOS)
    private static func monoFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
    #else
    private static func monoFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
    #endif

    #if os(macOS)
    private static func platformColor(for color: Color) -> NSColor {
        NSColor(color)
    }
    #else
    private static func platformColor(for color: Color) -> UIColor {
        UIColor(color)
    }
    #endif
}
