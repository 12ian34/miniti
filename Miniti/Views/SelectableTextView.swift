import SwiftUI
import SwiftData

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
    let onSelectionChange: ((NSRange?) -> Void)?
    let onDeleteSelection: (() -> Void)?

    init(
        _ attributed: NSAttributedString,
        onSelectionChange: ((NSRange?) -> Void)? = nil,
        onDeleteSelection: (() -> Void)? = nil
    ) {
        self.attributed = attributed
        self.onSelectionChange = onSelectionChange
        self.onDeleteSelection = onDeleteSelection
    }

    var body: some View {
        #if os(macOS)
        _SelectableTextViewMac(
            attributed: attributed,
            onSelectionChange: onSelectionChange,
            onDeleteSelection: onDeleteSelection
        )
        #else
        _SelectableTextViewIOS(attributed: attributed, onSelectionChange: onSelectionChange)
        #endif
    }
}

#if os(macOS)
private struct _SelectableTextViewMac: NSViewRepresentable {
    let attributed: NSAttributedString
    let onSelectionChange: ((NSRange?) -> Void)?
    let onDeleteSelection: (() -> Void)?

    func makeNSView(context: Context) -> _SelectableTextContainer {
        _SelectableTextContainer(
            attributed: attributed,
            onSelectionChange: onSelectionChange,
            onDeleteSelection: onDeleteSelection
        )
    }

    func updateNSView(_ nsView: _SelectableTextContainer, context: Context) {
        nsView.apply(attributed, onSelectionChange: onSelectionChange, onDeleteSelection: onDeleteSelection)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: _SelectableTextContainer, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0 else { return nil }
        let height = nsView.measuredHeight(for: width)
        return CGSize(width: width, height: height)
    }
}

final class _SelectableNativeTextView: NSTextView {
    var onDeleteSelection: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isDeleteKey = event.charactersIgnoringModifiers == "\u{7F}" ||
            event.charactersIgnoringModifiers == "\u{8}"
        if isDeleteKey, selectedRange().length > 0 {
            onDeleteSelection?()
            return
        }
        super.keyDown(with: event)
    }
}

final class _SelectableTextContainer: NSView, NSTextViewDelegate {
    private let textView: _SelectableNativeTextView
    private var lastMeasuredWidth: CGFloat = -1
    private var lastMeasuredHeight: CGFloat = 0
    private var onSelectionChange: ((NSRange?) -> Void)?

    init(
        attributed: NSAttributedString,
        onSelectionChange: ((NSRange?) -> Void)?,
        onDeleteSelection: (() -> Void)?
    ) {
        let tv = _SelectableNativeTextView(frame: .zero)
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
        tv.onDeleteSelection = onDeleteSelection
        self.textView = tv
        self.onSelectionChange = onSelectionChange
        super.init(frame: .zero)
        tv.delegate = self
        addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: trailingAnchor),
            tv.topAnchor.constraint(equalTo: topAnchor),
            tv.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(
        _ attributed: NSAttributedString,
        onSelectionChange: ((NSRange?) -> Void)?,
        onDeleteSelection: (() -> Void)?
    ) {
        self.onSelectionChange = onSelectionChange
        textView.onDeleteSelection = onDeleteSelection
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

    func textViewDidChangeSelection(_ notification: Notification) {
        let range = textView.selectedRange()
        let selection = range.length > 0 ? range : nil
        DispatchQueue.main.async { [onSelectionChange] in
            onSelectionChange?(selection)
        }
    }

    func measuredHeight(for width: CGFloat) -> CGFloat {
        if abs(width - lastMeasuredWidth) < 0.5 { return lastMeasuredHeight }
        guard let storage = textView.textStorage,
              let displayContainer = textView.textContainer,
              let displayLayoutManager = textView.layoutManager else { return 0 }

        // Measure via a throwaway layout manager attached to a COPY of the real
        // text storage. Side-effect free (does not mutate the live textView's
        // container or layoutManager), but we must force full glyph generation
        // before reading usedRect — ensureLayout(for:) alone under-reports on
        // some macOS versions because glyphs are generated lazily.
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = displayContainer.lineFragmentPadding
        container.widthTracksTextView = false
        container.heightTracksTextView = false

        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = displayLayoutManager.usesFontLeading
        layoutManager.typesetterBehavior = displayLayoutManager.typesetterBehavior
        layoutManager.allowsNonContiguousLayout = false
        layoutManager.addTextContainer(container)

        let measurementStorage = NSTextStorage(attributedString: storage)
        measurementStorage.addLayoutManager(layoutManager)

        // Canonical force-full-layout idiom: glyphRange(for:) triggers glyph
        // generation for the entire container, then ensureLayout guarantees
        // layout is committed for those glyphs, then usedRect reflects the
        // real rendered height.
        _ = layoutManager.glyphRange(for: container)
        layoutManager.ensureLayout(for: container)
        let rect = layoutManager.usedRect(for: container)

        lastMeasuredWidth = width
        lastMeasuredHeight = ceil(rect.height)
        return lastMeasuredHeight
    }
}

#else

private struct _SelectableTextViewIOS: UIViewRepresentable {
    let attributed: NSAttributedString
    let onSelectionChange: ((NSRange?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

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
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.onSelectionChange = onSelectionChange
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

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSelectionChange: ((NSRange?) -> Void)?

        init(onSelectionChange: ((NSRange?) -> Void)?) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            let selection = range.length > 0 ? range : nil
            DispatchQueue.main.async { [onSelectionChange] in
                onSelectionChange?(selection)
            }
        }
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

    struct TranscriptRenderSegment {
        let id: UUID
        let speaker: Int
        let timestamp: TimeInterval
        let text: String
    }

    struct TranscriptRenderSpan: Identifiable {
        var id: UUID { segmentID }
        let segmentID: UUID
        let speaker: Int
        let timestamp: TimeInterval
        let text: String
        let headerRange: NSRange
        let bodyRange: NSRange
    }

    struct TranscriptRenderModel {
        let attributed: NSAttributedString
        let spans: [TranscriptRenderSpan]

        func textSelections(overlapping selection: NSRange?) -> [TranscriptTextSelection] {
            guard let selection, selection.length > 0 else { return [] }
            return spans.compactMap { span in
                let intersection = NSIntersectionRange(selection, span.bodyRange)
                guard intersection.length > 0 else { return nil }
                let lower = intersection.location - span.bodyRange.location
                return TranscriptTextSelection(
                    segmentID: span.segmentID,
                    lowerUTF16Offset: lower,
                    upperUTF16Offset: lower + intersection.length
                )
            }
        }
    }

    static func transcriptRenderModel(
        segments: [TranscriptRenderSegment],
        speakerNames: [String: String]?,
        selfIDs: Set<Int>? = nil,
        bodyFontSize: CGFloat = 13,
        headerFontSize: CGFloat = 10
    ) -> TranscriptRenderModel {
        let result = NSMutableAttributedString()
        let bodyFont = monoFont(size: bodyFontSize, weight: .regular)
        let headerFont = monoFont(size: headerFontSize, weight: .semibold)
        let bodyPara = NSMutableParagraphStyle()
        bodyPara.paragraphSpacing = 6
        bodyPara.lineSpacing = 2
        let headerPara = NSMutableParagraphStyle()
        headerPara.paragraphSpacingBefore = 10
        headerPara.paragraphSpacing = 2

        var spans: [TranscriptRenderSpan] = []
        spans.reserveCapacity(segments.count)
        for (index, segment) in segments.enumerated() {
            let speakerColor = platformColor(for: speakerColor(for: segment.speaker, selfIDs: selfIDs))
            let label = speakerLabel(for: segment.speaker, names: speakerNames, selfIDs: selfIDs)
            let timestamp = formatTimestamp(segment.timestamp)
            let header = "\(label) · \(timestamp)\n"
            let headerStart = result.length
            result.append(NSAttributedString(string: header, attributes: [
                .font: headerFont,
                .foregroundColor: speakerColor,
                .paragraphStyle: index == 0 ? bodyPara : headerPara,
            ]))
            let headerRange = NSRange(location: headerStart, length: (header as NSString).length)

            let bodyStart = result.length
            result.append(NSAttributedString(string: segment.text, attributes: [
                .font: bodyFont,
                .foregroundColor: platformColor(for: ColorPalette.Text.secondary),
                .paragraphStyle: bodyPara,
            ]))
            let bodyRange = NSRange(location: bodyStart, length: (segment.text as NSString).length)
            if index != segments.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: bodyFont,
                    .foregroundColor: platformColor(for: ColorPalette.Text.secondary),
                    .paragraphStyle: bodyPara,
                ]))
            }

            spans.append(TranscriptRenderSpan(
                segmentID: segment.id,
                speaker: segment.speaker,
                timestamp: segment.timestamp,
                text: segment.text,
                headerRange: headerRange,
                bodyRange: bodyRange
            ))
        }
        return TranscriptRenderModel(attributed: result, spans: spans)
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

struct TranscriptTrimView: View {
    @EnvironmentObject private var appState: AppState
    @Bindable var meeting: Meeting
    @State private var selectedRange: NSRange?
    @State private var undoSnapshots: [TranscriptSegmentSnapshot]?
    @State private var pendingTrimOperation: TranscriptTrimOperation?
    @State private var pendingTrimSnapshots: [TranscriptSegmentSnapshot] = []
    @State private var isConfirmingTrim = false

    private var sortedSegments: [TranscriptSegment] {
        meeting.segments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var renderModel: SelectableAttributed.TranscriptRenderModel {
        SelectableAttributed.transcriptRenderModel(
            segments: sortedSegments.map {
                .init(id: $0.id, speaker: $0.speaker, timestamp: $0.timestamp, text: $0.text)
            },
            speakerNames: meeting.speakerNames,
            selfIDs: meeting.selfSpeakerIDs
        )
    }

    private var selectedTextSelections: [TranscriptTextSelection] {
        renderModel.textSelections(overlapping: selectedRange)
    }

    private var hasSelectedTranscriptText: Bool {
        !selectedTextSelections.isEmpty
    }

    private var currentSnapshots: [TranscriptSegmentSnapshot] {
        sortedSegments.map {
            TranscriptSegmentSnapshot(
                id: $0.id,
                speaker: $0.speaker,
                timestamp: $0.timestamp,
                text: $0.text,
                isFinal: $0.isFinal,
                confidence: $0.confidence
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if meeting.needsInsightsAfterTranscriptEdit {
                transcriptEditedBanner
            }

            trimToolbar

            ScrollView {
                SelectableTextView(
                    renderModel.attributed,
                    onSelectionChange: { range in
                        selectedRange = range
                    },
                    onDeleteSelection: {
                        requestDeleteSelectedText()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .alert("trim transcript?", isPresented: $isConfirmingTrim) {
            Button("cancel", role: .cancel) {
                pendingTrimOperation = nil
                pendingTrimSnapshots = []
            }
            Button("trim", role: .destructive) {
                applyPendingTrim()
            }
        } message: {
            Text("this will clear standard, meddpicc, questions, and docs insights. regenerate insights after trimming. undo restores transcript text only - it does not restore the old insights.")
        }
    }

    private var trimToolbar: some View {
        HStack(spacing: 8) {
            Button {
                deleteSelectedText()
            } label: {
                Label("delete selection", systemImage: "scissors")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .buttonStyle(.plain)
            .disabled(!hasSelectedTranscriptText)
            .foregroundStyle(hasSelectedTranscriptText ? ColorPalette.Status.error : ColorPalette.Text.disabled)

            if let undoSnapshots {
                Button {
                    if appState.restoreTranscriptSnapshots(undoSnapshots, to: meeting) {
                        self.undoSnapshots = nil
                        selectedRange = nil
                    }
                } label: {
                    Label("undo trim", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ColorPalette.Text.muted)
            }

            if let selectedRange, selectedRange.length > 0, selectedTextSelections.isEmpty {
                Text("selection includes only speaker labels")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.meta)
            }
        }
        .padding(.horizontal, 16)
    }

    private var transcriptEditedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ColorPalette.Status.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("transcript edited")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.primary)
                Text("standard, meddpicc, questions, and docs insights were cleared; regenerate after trimming")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(ColorPalette.Text.meta)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(ColorPalette.Background.tertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ColorPalette.Status.warning.opacity(0.45), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func deleteSelectedText() {
        let selections = selectedTextSelections
        guard !selections.isEmpty else { return }
        requestTrim(TranscriptTrimOperation(textSelections: selections))
    }

    private func requestDeleteSelectedText() {
        guard hasSelectedTranscriptText else { return }
        deleteSelectedText()
    }

    private func requestTrim(_ operation: TranscriptTrimOperation) {
        guard !operation.isEmpty else { return }
        pendingTrimOperation = operation
        pendingTrimSnapshots = currentSnapshots
        isConfirmingTrim = true
    }

    private func applyPendingTrim() {
        guard let operation = pendingTrimOperation else { return }
        let snapshots = pendingTrimSnapshots
        pendingTrimOperation = nil
        pendingTrimSnapshots = []
        if appState.applyTranscriptTrim(operation, to: meeting) {
            undoSnapshots = snapshots
            selectedRange = nil
        }
    }
}
