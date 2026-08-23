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
struct SelectableTextMutation {
    let revision: UInt64
    let range: NSRange
    let replacement: NSAttributedString
}

struct SelectableTextView: View {
    let attributed: NSAttributedString
    let mutation: SelectableTextMutation?
    let onSelectionChange: ((NSRange?) -> Void)?
    let onDeleteSelection: (() -> Void)?

    init(
        _ attributed: NSAttributedString,
        mutation: SelectableTextMutation? = nil,
        onSelectionChange: ((NSRange?) -> Void)? = nil,
        onDeleteSelection: (() -> Void)? = nil
    ) {
        self.attributed = attributed
        self.mutation = mutation
        self.onSelectionChange = onSelectionChange
        self.onDeleteSelection = onDeleteSelection
    }

    var body: some View {
        #if os(macOS)
        _SelectableTextViewMac(
            attributed: attributed,
            mutation: mutation,
            onSelectionChange: onSelectionChange,
            onDeleteSelection: onDeleteSelection
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        _SelectableTextViewIOS(
            attributed: attributed,
            mutation: mutation,
            onSelectionChange: onSelectionChange
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

#if os(macOS)
private struct _SelectableTextViewMac: NSViewRepresentable {
    let attributed: NSAttributedString
    let mutation: SelectableTextMutation?
    let onSelectionChange: ((NSRange?) -> Void)?
    let onDeleteSelection: (() -> Void)?

    func makeNSView(context: Context) -> _SelectableTextContainer {
        _SelectableTextContainer(
            attributed: attributed,
            mutation: mutation,
            onSelectionChange: onSelectionChange,
            onDeleteSelection: onDeleteSelection
        )
    }

    func updateNSView(_ nsView: _SelectableTextContainer, context: Context) {
        nsView.apply(
            attributed,
            mutation: mutation,
            onSelectionChange: onSelectionChange,
            onDeleteSelection: onDeleteSelection
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: _SelectableTextContainer, context: Context) -> CGSize? {
        // A vertical ScrollView can briefly issue an unspecified or sliver-width
        // proposal while it reconciles a growing child. Keep the proposed width
        // for SwiftUI's layout negotiation, but measure height at the last
        // trustworthy transcript width so one transient pass cannot create a
        // many-thousand-point frame around otherwise correctly rendered text.
        guard let measurementWidth = nsView.reliableMeasurementWidth(for: proposal.width) else {
            return nil
        }
        let height = nsView.measuredHeight(for: measurementWidth)
        return CGSize(width: proposal.width ?? measurementWidth, height: height)
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
    private struct PendingMeasurementMutation {
        let previousTail: NSAttributedString
        let replacementTail: NSAttributedString
    }

    private static let minimumReliableMeasurementWidth: CGFloat = 160
    private static let measurementResetInterval = 64
    private static let maximumPendingMeasurementMutations = 8
    private static let measurementDeltaTolerance: CGFloat = 8

    private let textView: _SelectableNativeTextView
    private let measurementStorage: NSTextStorage
    private var measurementLayoutManager: NSLayoutManager
    private var measurementContainer: NSTextContainer
    private var lastMeasuredWidth: CGFloat = -1
    private var lastMeasuredHeight: CGFloat = 0
    private var measurementMutationCount = 0
    private var measurementNeedsReset = false
    private var measurementContentChanged = true
    private var pendingMeasurementMutations: [PendingMeasurementMutation] = []
    private var lastAppliedRevision: UInt64
    private var lastAttributedInput: NSAttributedString
    private var onSelectionChange: ((NSRange?) -> Void)?

    init(
        attributed: NSAttributedString,
        mutation: SelectableTextMutation?,
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

        let measurementStorage = NSTextStorage(attributedString: attributed)
        let measurementLayoutManager = NSLayoutManager()
        measurementLayoutManager.allowsNonContiguousLayout = false
        let measurementContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        measurementContainer.lineFragmentPadding = tv.textContainer?.lineFragmentPadding ?? 0
        measurementContainer.widthTracksTextView = false
        measurementContainer.heightTracksTextView = false
        measurementLayoutManager.addTextContainer(measurementContainer)
        measurementStorage.addLayoutManager(measurementLayoutManager)

        self.textView = tv
        self.measurementStorage = measurementStorage
        self.measurementLayoutManager = measurementLayoutManager
        self.measurementContainer = measurementContainer
        self.lastAppliedRevision = mutation?.revision ?? 0
        self.lastAttributedInput = attributed
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
        mutation: SelectableTextMutation?,
        onSelectionChange: ((NSRange?) -> Void)?,
        onDeleteSelection: (() -> Void)?
    ) {
        self.onSelectionChange = onSelectionChange
        textView.onDeleteSelection = onDeleteSelection
        guard let displayStorage = textView.textStorage else { return }

        let appliedIncrementally: Bool
        if let mutation,
           mutation.revision != lastAppliedRevision,
           NSMaxRange(mutation.range) <= displayStorage.length,
           NSMaxRange(mutation.range) <= measurementStorage.length {
            let previousMeasurementLength = measurementStorage.length
            let replacesMeasuredTail = mutation.range.location > 0
                && NSMaxRange(mutation.range) == previousMeasurementLength
                && lastMeasuredWidth >= Self.minimumReliableMeasurementWidth
                && !measurementNeedsReset
            if replacesMeasuredTail {
                pendingMeasurementMutations.append(PendingMeasurementMutation(
                    previousTail: measurementStorage.attributedSubstring(from: mutation.range),
                    replacementTail: mutation.replacement
                ))
                if pendingMeasurementMutations.count > Self.maximumPendingMeasurementMutations {
                    measurementNeedsReset = true
                    pendingMeasurementMutations.removeAll(keepingCapacity: true)
                }
            } else {
                measurementNeedsReset = true
                pendingMeasurementMutations.removeAll(keepingCapacity: true)
            }

            displayStorage.replaceCharacters(in: mutation.range, with: mutation.replacement)
            measurementStorage.replaceCharacters(in: mutation.range, with: mutation.replacement)
            let invalidatedRange = NSRange(
                location: mutation.range.location,
                length: max(0, measurementStorage.length - mutation.range.location)
            )
            measurementLayoutManager.invalidateLayout(
                forCharacterRange: invalidatedRange,
                actualCharacterRange: nil
            )
            measurementMutationCount += 1
            if measurementMutationCount >= Self.measurementResetInterval {
                measurementNeedsReset = true
            }
            measurementContentChanged = true
            lastAppliedRevision = mutation.revision
            lastAttributedInput = attributed
            appliedIncrementally = true
        } else {
            appliedIncrementally = false
        }

        if !appliedIncrementally {
            // NSAttributedString inputs are immutable view values. Unrelated SwiftUI
            // updates commonly pass the exact same instance, so avoid an O(n) deep
            // equality walk over a 45–60 minute transcript in that case.
            guard attributed !== lastAttributedInput else { return }
            lastAttributedInput = attributed
            guard displayStorage.isEqual(to: attributed) == false else { return }
            displayStorage.setAttributedString(attributed)
            measurementStorage.setAttributedString(attributed)
            measurementNeedsReset = true
            measurementContentChanged = true
            pendingMeasurementMutations.removeAll(keepingCapacity: true)
            if let mutation { lastAppliedRevision = mutation.revision }
        }
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

    func reliableMeasurementWidth(for proposedWidth: CGFloat?) -> CGFloat? {
        let placedWidth = bounds.width >= Self.minimumReliableMeasurementWidth
            ? bounds.width
            : nil

        if let proposedWidth,
           proposedWidth >= Self.minimumReliableMeasurementWidth {
            // During ScrollView reconciliation SwiftUI can briefly propose a
            // narrower-but-still-plausible width. Measuring a long transcript
            // at that width inflates its height even though AppKit is still
            // displaying it at the wider placed width. Prefer the placed width
            // for that pass; a real pane shrink updates bounds and is measured
            // correctly on the next layout pass.
            if let placedWidth, proposedWidth < placedWidth {
                return placedWidth
            }
            return proposedWidth
        }

        // An unspecified proposal is routine inside SwiftUI scroll views. Once
        // the native view has been placed, its current bounds are a better
        // measurement source than a width cached before a pane/window resize.
        if let placedWidth {
            return placedWidth
        }

        if lastMeasuredWidth >= Self.minimumReliableMeasurementWidth {
            return lastMeasuredWidth
        }
        return nil
    }

    func measuredHeight(for width: CGFloat) -> CGFloat {
        let widthChanged = abs(width - lastMeasuredWidth) >= 0.5
        if !widthChanged,
           !measurementNeedsReset,
           !measurementContentChanged,
           lastMeasuredWidth >= 0 {
            return lastMeasuredHeight
        }

        // TextKit can retain stale line fragments after many tail replacements
        // or after a narrow transient layout pass. Periodically rebuilding only
        // the measurement layout manager keeps the displayed text incremental
        // while preventing that stale usedRect from becoming permanent blank
        // space in both live and finalized transcripts.
        let previousMeasuredHeight = lastMeasuredHeight
        let mutationsToValidate = pendingMeasurementMutations
        let canValidateIncrementalHeight = !widthChanged
            && !measurementNeedsReset
            && previousMeasuredHeight > 0
            && !mutationsToValidate.isEmpty

        if widthChanged || measurementNeedsReset {
            rebuildMeasurementLayout(for: width)
        }

        // The dedicated measurement stack persists across updates, so TextKit
        // can reuse glyph/layout work before an appended or replaced tail.
        _ = measurementLayoutManager.glyphRange(for: measurementContainer)
        measurementLayoutManager.ensureLayout(for: measurementContainer)
        var measuredHeight = ceil(
            measurementLayoutManager.usedRect(for: measurementContainer).height
        )

        if canValidateIncrementalHeight {
            let expectedHeight = previousMeasuredHeight + mutationsToValidate.reduce(CGFloat.zero) {
                partialResult, mutation in
                partialResult
                    + freshMeasuredHeight(of: mutation.replacementTail, for: width)
                    - freshMeasuredHeight(of: mutation.previousTail, for: width)
            }
            if abs(measuredHeight - expectedHeight) > Self.measurementDeltaTolerance {
                rebuildMeasurementLayout(for: width)
                _ = measurementLayoutManager.glyphRange(for: measurementContainer)
                measurementLayoutManager.ensureLayout(for: measurementContainer)
                measuredHeight = ceil(
                    measurementLayoutManager.usedRect(for: measurementContainer).height
                )
            }
        }

        lastMeasuredWidth = width
        lastMeasuredHeight = measuredHeight
        measurementContentChanged = false
        pendingMeasurementMutations.removeAll(keepingCapacity: true)
        return lastMeasuredHeight
    }

    private func freshMeasuredHeight(of attributed: NSAttributedString, for width: CGFloat) -> CGFloat {
        guard attributed.length > 0 else { return 0 }

        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = false
        let container = NSTextContainer(
            size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        _ = layoutManager.glyphRange(for: container)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    private func rebuildMeasurementLayout(for width: CGFloat) {
        measurementStorage.removeLayoutManager(measurementLayoutManager)

        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = false
        let container = NSTextContainer(
            size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        measurementStorage.addLayoutManager(layoutManager)

        measurementLayoutManager = layoutManager
        measurementContainer = container
        measurementMutationCount = 0
        measurementNeedsReset = false
        measurementContentChanged = true
        pendingMeasurementMutations.removeAll(keepingCapacity: true)
        lastMeasuredWidth = -1
        lastMeasuredHeight = 0
    }
}

#else

private struct _SelectableTextViewIOS: UIViewRepresentable {
    let attributed: NSAttributedString
    let mutation: SelectableTextMutation?
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
        context.coordinator.lastAppliedRevision = mutation?.revision ?? 0
        context.coordinator.lastAttributedInput = attributed
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.onSelectionChange = onSelectionChange
        if let mutation,
           mutation.revision != context.coordinator.lastAppliedRevision,
           NSMaxRange(mutation.range) <= uiView.textStorage.length {
            uiView.textStorage.replaceCharacters(in: mutation.range, with: mutation.replacement)
            context.coordinator.lastAppliedRevision = mutation.revision
            context.coordinator.lastAttributedInput = attributed
            uiView.invalidateIntrinsicContentSize()
        } else if attributed !== context.coordinator.lastAttributedInput {
            context.coordinator.lastAttributedInput = attributed
            guard uiView.attributedText != attributed else { return }
            uiView.attributedText = attributed
            if let mutation { context.coordinator.lastAppliedRevision = mutation.revision }
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
        var lastAppliedRevision: UInt64 = 0
        var lastAttributedInput: NSAttributedString?

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
    struct TranscriptDocument {
        let attributed: NSAttributedString
        let turns: [TranscriptTurn]
        let turnStartOffsets: [Int]
    }

    /// Build an attributed transcript from speaker turns. Transport-finalized chunks
    /// from the same displayed speaker share one header and body paragraph.
    static func transcript(
        turns: [TranscriptTurn],
        speakerNames: [String: String]?,
        selfIDs: Set<Int>? = nil,
        bodyFontSize: CGFloat = 13,
        headerFontSize: CGFloat = 10,
        lineSpacing: CGFloat = 2
    ) -> NSAttributedString {
        transcriptDocument(
            turns: turns,
            speakerNames: speakerNames,
            selfIDs: selfIDs,
            bodyFontSize: bodyFontSize,
            headerFontSize: headerFontSize,
            lineSpacing: lineSpacing
        ).attributed
    }

    static func transcriptDocument(
        turns: [TranscriptTurn],
        speakerNames: [String: String]?,
        selfIDs: Set<Int>? = nil,
        bodyFontSize: CGFloat = 13,
        headerFontSize: CGFloat = 10,
        lineSpacing: CGFloat = 2,
        startsAtDocumentBeginning: Bool = true
    ) -> TranscriptDocument {
        let result = NSMutableAttributedString()
        let bodyFont = appFont(size: bodyFontSize, weight: .regular)
        let headerFont = appFont(size: headerFontSize, weight: .semibold)
        let bodyPara = NSMutableParagraphStyle()
        bodyPara.paragraphSpacing = 6
        bodyPara.lineSpacing = lineSpacing
        let headerPara = NSMutableParagraphStyle()
        headerPara.paragraphSpacingBefore = 10
        headerPara.paragraphSpacing = 2

        let displayTurns = mergeTurns(turns, speakerNames: speakerNames, selfIDs: selfIDs)
        var turnStartOffsets: [Int] = []
        turnStartOffsets.reserveCapacity(displayTurns.count)
        for (index, turn) in displayTurns.enumerated() {
            turnStartOffsets.append(result.length)
            let speakerColor = platformColor(for: speakerColor(for: turn.speaker, selfIDs: selfIDs))
            let label = speakerLabel(for: turn.speaker, names: speakerNames, selfIDs: selfIDs)
            let timestamp = formatTimestamp(turn.timestamp)
            let header = "\(label) · \(timestamp)\n"
            result.append(NSAttributedString(string: header, attributes: [
                .font: headerFont,
                .foregroundColor: speakerColor,
                .paragraphStyle: startsAtDocumentBeginning && index == 0 ? bodyPara : headerPara,
            ]))
            let body = turn.text + (index == displayTurns.count - 1 ? "" : "\n")
            result.append(NSAttributedString(string: body, attributes: [
                .font: bodyFont,
                .foregroundColor: platformColor(for: Color(hex: "E6EDF3")),
                .paragraphStyle: bodyPara,
            ]))
        }
        return TranscriptDocument(
            attributed: result,
            turns: displayTurns,
            turnStartOffsets: turnStartOffsets
        )
    }

    /// Build a plain attributed string from a single body of text.
    static func body(
        _ text: String,
        fontSize: CGFloat = 13,
        color: Color = Color(hex: "E6EDF3"),
        lineSpacing: CGFloat = 6
    ) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: appFont(size: fontSize, weight: .regular),
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
        let font = appFont(size: fontSize, weight: .regular)
        let prefixFont = appFont(size: fontSize, weight: .medium)
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
        headerFontSize: CGFloat = 10,
        lineSpacing: CGFloat = 2
    ) -> TranscriptRenderModel {
        let result = NSMutableAttributedString()
        let bodyFont = appFont(size: bodyFontSize, weight: .regular)
        let headerFont = appFont(size: headerFontSize, weight: .semibold)
        let bodyPara = NSMutableParagraphStyle()
        bodyPara.paragraphSpacing = 6
        bodyPara.lineSpacing = lineSpacing
        let headerPara = NSMutableParagraphStyle()
        headerPara.paragraphSpacingBefore = 10
        headerPara.paragraphSpacing = 2

        var spans: [TranscriptRenderSpan] = []
        spans.reserveCapacity(segments.count)
        var previousDisplayKey: String?
        for (index, segment) in segments.enumerated() {
            let displayKey = turnDisplayKey(segment.speaker, names: speakerNames, selfIDs: selfIDs)
            let startsNewTurn = displayKey != previousDisplayKey
            let headerStart = result.length
            let headerRange: NSRange
            if startsNewTurn {
                let speakerColor = platformColor(for: speakerColor(for: segment.speaker, selfIDs: selfIDs))
                let label = speakerLabel(for: segment.speaker, names: speakerNames, selfIDs: selfIDs)
                let timestamp = formatTimestamp(segment.timestamp)
                let header = "\(label) · \(timestamp)\n"
                result.append(NSAttributedString(string: header, attributes: [
                    .font: headerFont,
                    .foregroundColor: speakerColor,
                    .paragraphStyle: index == 0 ? bodyPara : headerPara,
                ]))
                headerRange = NSRange(location: headerStart, length: (header as NSString).length)
            } else {
                // Keep a span for every stored segment so transcript trimming can
                // still map selections precisely, even though the repeated header
                // is omitted from the visual speaker turn.
                headerRange = NSRange(location: headerStart, length: 0)
            }

            let bodyStart = result.length
            result.append(NSAttributedString(string: segment.text, attributes: [
                .font: bodyFont,
                .foregroundColor: platformColor(for: ColorPalette.Text.secondary),
                .paragraphStyle: bodyPara,
            ]))
            let bodyRange = NSRange(location: bodyStart, length: (segment.text as NSString).length)
            if index != segments.count - 1 {
                let next = segments[index + 1]
                let nextKey = turnDisplayKey(next.speaker, names: speakerNames, selfIDs: selfIDs)
                let separator = nextKey == displayKey ? " " : "\n"
                result.append(NSAttributedString(string: separator, attributes: [
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
            previousDisplayKey = displayKey
        }
        return TranscriptRenderModel(attributed: result, spans: spans)
    }

    /// Merge consecutive chunks that render as the same on-screen speaker into one
    /// visual turn. Sentence punctuation affects prose, not speaker identity. Groups
    /// all self IDs and IDs sharing an inferred/manual name into the same turn.
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
                == turnDisplayKey(turn.speaker, names: speakerNames, selfIDs: selfIDs) {
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
        // An empty (non-nil) self set means several people share the microphone and
        // nobody is implicitly "You"; nil means self context is unknown (legacy default).
        let effectiveSelves: Set<Int> = selfIDs ?? [DeepgramService.micSpeakerID]
        if effectiveSelves.contains(speaker) { return "self" }
        if let mapped = names?[String(speaker)]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mapped.isEmpty {
            return "name:\(mapped.lowercased())"
        }
        return "id:\(speaker)"
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
    private static func appFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
    #else
    private static func appFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
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
    @Environment(\.interfaceScale) private var interfaceScale
    @Environment(\.undoManager) private var undoManager
    @Bindable var meeting: Meeting
    @State private var selectedRange: NSRange?
    @State private var undoSnapshots: [TranscriptSegmentSnapshot]?
    @State private var pendingTrimOperation: TranscriptTrimOperation?
    @State private var pendingTrimSnapshots: [TranscriptSegmentSnapshot] = []
    @State private var isConfirmingTrim = false
    @State private var cachedSortedSegments: [TranscriptSegment] = []
    @State private var cachedRenderModel = SelectableAttributed.TranscriptRenderModel(
        attributed: NSAttributedString(),
        spans: []
    )
    @State private var cachedRenderMutation: SelectableTextMutation?
    @State private var renderRevision: UInt64 = 0
    @State private var renderCacheTask: Task<Void, Never>?

    private var selectedTextSelections: [TranscriptTextSelection] {
        cachedRenderModel.textSelections(overlapping: selectedRange)
    }

    private var hasSelectedTranscriptText: Bool {
        !selectedTextSelections.isEmpty
    }

    private var currentSnapshots: [TranscriptSegmentSnapshot] {
        cachedSortedSegments.map {
            TranscriptSegmentSnapshot(
                id: $0.id,
                speaker: $0.speaker,
                timestamp: $0.timestamp,
                text: $0.text,
                isFinal: $0.isFinal,
                confidence: $0.confidence,
                sourceRaw: $0.sourceRaw
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
                    cachedRenderModel.attributed,
                    mutation: cachedRenderMutation,
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
            Text("this will clear summary, sales, questions, and playbook insights. regenerate insights after trimming. undo restores transcript text only — it does not restore the old insights.")
        }
        .onAppear {
            rebuildRenderCache()
        }
        .onChange(of: meeting.segments.count) { _, _ in
            scheduleRenderCacheRebuild()
        }
        .onChange(of: meeting.transcriptRevision) { _, _ in
            scheduleRenderCacheRebuild()
        }
        .onChange(of: meeting.speakerNamesJSON) { _, _ in
            scheduleRenderCacheRebuild()
        }
        .onChange(of: meeting.selfSpeakerIDsJSON) { _, _ in
            scheduleRenderCacheRebuild()
        }
        .onChange(of: meeting.selfSpeakerID) { _, _ in
            scheduleRenderCacheRebuild()
        }
        .onChange(of: interfaceScale) { _, _ in
            scheduleRenderCacheRebuild()
        }
        .onDisappear {
            renderCacheTask?.cancel()
            renderCacheTask = nil
        }
    }

    private func scheduleRenderCacheRebuild() {
        renderCacheTask?.cancel()
        renderCacheTask = Task { @MainActor in
            // Coalesce SwiftData relationship/member notifications from one save.
            try? await Task.sleep(for: .milliseconds(75))
            guard !Task.isCancelled else { return }
            rebuildRenderCache()
        }
    }

    private func rebuildRenderCache() {
        renderCacheTask?.cancel()
        renderCacheTask = nil

        let segments = meeting.segments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp < $1.timestamp }
        let nextModel = SelectableAttributed.transcriptRenderModel(
            segments: segments.map {
                .init(id: $0.id, speaker: $0.speaker, timestamp: $0.timestamp, text: $0.text)
            },
            speakerNames: meeting.speakerNames,
            selfIDs: meeting.speakerLabelSelfIDs,
            bodyFontSize: interfaceScale.transcriptBodySize,
            headerFontSize: interfaceScale.transcriptHeaderSize,
            lineSpacing: interfaceScale.transcriptLineSpacing
        )

        renderRevision &+= 1
        cachedRenderMutation = SelectableTextMutation(
            revision: renderRevision,
            range: NSRange(location: 0, length: cachedRenderModel.attributed.length),
            replacement: nextModel.attributed
        )
        cachedSortedSegments = segments
        cachedRenderModel = nextModel
        if let selectedRange, NSMaxRange(selectedRange) > nextModel.attributed.length {
            self.selectedRange = nil
        }
    }

    private var trimToolbar: some View {
        HStack(spacing: 8) {
            Button {
                deleteSelectedText()
            } label: {
                Label("delete selection", systemImage: "scissors")
                    .font(.system(size: 10, weight: .semibold, design: .default))
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
                        .font(.system(size: 10, weight: .semibold, design: .default))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ColorPalette.Text.muted)
            }

            if let selectedRange, selectedRange.length > 0, selectedTextSelections.isEmpty {
                Text("selection includes only speaker labels")
                    .font(.system(size: 10, weight: .regular, design: .default))
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
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(ColorPalette.Text.primary)
                Text("summary, sales, questions, and playbook insights were cleared; regenerate after trimming")
                    .font(.system(size: 10, weight: .regular, design: .default))
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
            registerSystemUndo(for: snapshots)
        }
    }

    private func registerSystemUndo(for snapshots: [TranscriptSegmentSnapshot]) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: appState) { target in
            _ = target.restoreTranscriptSnapshots(snapshots, to: meeting)
        }
        undoManager.setActionName("Trim Transcript")
    }
}
