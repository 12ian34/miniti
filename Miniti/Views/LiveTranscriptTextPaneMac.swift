#if os(macOS)
import AppKit
import SwiftUI
import os

private let liveTranscriptPaneLog = Logger(
    subsystem: "com.miniti.app",
    category: "LiveTranscriptTextPane"
)

struct LiveTranscriptInterimSnapshot {
    let revision: UInt64
    let text: String
    let speaker: Int
    let startsNewTurn: Bool
    let hasFinalizedContent: Bool
    let speakerNames: [String: String]
    let selfIDs: Set<Int>?
    let bodyFontSize: CGFloat
    let headerFontSize: CGFloat
    let lineSpacing: CGFloat
}

enum LiveTranscriptSelectionPolicy {
    static func adjustedRange(
        _ selection: NSRange,
        replacing range: NSRange,
        replacementLength: Int,
        resultingLength: Int
    ) -> NSRange {
        guard selection.location != NSNotFound else { return selection }

        let selectionEnd = NSMaxRange(selection)
        let replacementEnd = NSMaxRange(range)
        let delta = replacementLength - range.length
        let adjusted: NSRange

        if selectionEnd <= range.location {
            adjusted = selection
        } else if selection.location >= replacementEnd {
            adjusted = NSRange(
                location: max(0, selection.location + delta),
                length: selection.length
            )
        } else {
            // The changing live tail intersects the selection. Collapse at the
            // first affected character rather than selecting unrelated replacement text.
            adjusted = NSRange(location: min(selection.location, range.location), length: 0)
        }

        let clampedLocation = min(max(0, adjusted.location), resultingLength)
        let clampedLength = min(max(0, adjusted.length), resultingLength - clampedLocation)
        return NSRange(location: clampedLocation, length: clampedLength)
    }
}

/// A single native scrolling text document for the macOS live transcript.
///
/// The NSTextView owns its NSScrollView, so SwiftUI never measures the full
/// transcript height and never creates per-row SelectionOverlay bridges.
struct LiveTranscriptTextPaneMac: NSViewRepresentable {
    let finalizedAttributed: NSAttributedString
    let finalizedMutation: SelectableTextMutation?
    let finalizedRevision: UInt64
    let interim: LiveTranscriptInterimSnapshot?
    let isAutoScrollEnabled: Bool
    let reduceMotion: Bool
    let onScrolledAwayFromBottom: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableDocumentContentTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            assertionFailure("NSTextView scrollable document did not contain an NSTextView")
            return scrollView
        }

        Self.configure(scrollView: scrollView, textView: textView)
        context.coordinator.attach(scrollView: scrollView, textView: textView)
        context.coordinator.apply(parent: self)
        return scrollView
    }

    static func configure(scrollView: NSScrollView, textView: NSTextView) {
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerKnobStyle = .light
        scrollView.postsFrameChangedNotifications = true

        textView.isEditable = false
        textView.isSelectable = true
        // The document still accepts attributed storage updates when rich-text
        // editing is disabled. Turning off both rich text and the inspector bar
        // prevents AppKit from installing its formatting toolbar when selected.
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesInspectorBar = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isRulerVisible = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.usesRolloverButtonForSelection = false
        textView.allowsImageEditing = false
        textView.allowsUndo = false
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(ColorPalette.Accent.green),
            .foregroundColor: NSColor(ColorPalette.Background.primary),
        ]
        textView.insertionPointColor = NSColor(ColorPalette.Accent.green)
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.isAutomaticTextCompletionEnabled = false
        textView.allowsCharacterPickerTouchBarItem = false
        textView.inlinePredictionType = .no
        textView.usesFindPanel = false
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = false
        if #available(macOS 15.0, *) {
            textView.mathExpressionCompletionType = .no
            textView.writingToolsBehavior = .none
        }
        textView.usesAdaptiveColorMappingForDarkAppearance = false
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.apply(parent: self)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        private var parent: LiveTranscriptTextPaneMac
        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private var finalizedLength = 0
        private var lastFinalizedRevision: UInt64?
        private var lastInterimKey: InterimKey?
        private var lastAutoScrollEnabled = true
        private var scrollRequestGeneration: UInt64 = 0
        private var cursorTimer: Timer?
        private var cursorVisible = true
        private var cursorRange: NSRange?
        private var cursorColor: NSColor?

        private struct InterimKey: Equatable {
            let runtimeRevision: UInt64
            let styleRevision: UInt64
            let reduceMotion: Bool
        }

        init(parent: LiveTranscriptTextPaneMac) {
            self.parent = parent
            self.lastAutoScrollEnabled = parent.isAutoScrollEnabled
        }

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            detach()
            self.scrollView = scrollView
            self.textView = textView

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didLiveScroll(_:)),
                name: NSScrollView.didLiveScrollNotification,
                object: scrollView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewFrameDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: scrollView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(textViewDidFallBackToTextKit1(_:)),
                name: NSTextView.didSwitchToNSLayoutManagerNotification,
                object: textView
            )

            if textView.textLayoutManager == nil {
                liveTranscriptPaneLog.error("Live transcript NSTextView was not created with TextKit 2")
            }
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            cursorTimer?.invalidate()
            cursorTimer = nil
            cursorRange = nil
            cursorColor = nil
            scrollView = nil
            textView = nil
        }

        func apply(parent: LiveTranscriptTextPaneMac) {
            self.parent = parent
            guard let textView, let storage = textView.textStorage else { return }

            if lastFinalizedRevision != parent.finalizedRevision {
                removeInterimIfNeeded(storage: storage, textView: textView)
                applyFinalizedContent(storage: storage, textView: textView)
                lastFinalizedRevision = parent.finalizedRevision
            }

            let interimKey = parent.interim.map {
                InterimKey(
                    runtimeRevision: $0.revision,
                    styleRevision: parent.finalizedRevision,
                    reduceMotion: parent.reduceMotion
                )
            }
            if interimKey != lastInterimKey {
                replaceInterim(storage: storage, textView: textView)
                lastInterimKey = interimKey
            }

            if parent.isAutoScrollEnabled && !lastAutoScrollEnabled {
                scheduleScrollToEnd()
            }
            lastAutoScrollEnabled = parent.isAutoScrollEnabled
        }

        private func applyFinalizedContent(storage: NSTextStorage, textView: NSTextView) {
            if let mutation = parent.finalizedMutation,
               NSMaxRange(mutation.range) <= finalizedLength,
               storage.length == finalizedLength {
                replace(
                    range: mutation.range,
                    with: mutation.replacement,
                    storage: storage,
                    textView: textView
                )
            } else {
                replace(
                    range: NSRange(location: 0, length: storage.length),
                    with: parent.finalizedAttributed,
                    storage: storage,
                    textView: textView
                )
            }
            finalizedLength = storage.length
            if parent.isAutoScrollEnabled {
                scheduleScrollToEnd()
            }
        }

        private func replaceInterim(storage: NSTextStorage, textView: NSTextView) {
            removeInterimIfNeeded(storage: storage, textView: textView)
            guard let interim = parent.interim else { return }

            let rendered = renderInterim(interim)
            let insertionRange = NSRange(location: finalizedLength, length: 0)
            replace(
                range: insertionRange,
                with: rendered.attributed,
                storage: storage,
                textView: textView
            )
            cursorRange = rendered.cursorLocalRange.map {
                NSRange(location: finalizedLength + $0.location, length: $0.length)
            }
            cursorColor = rendered.cursorColor
            cursorVisible = true
            updateCursorTimer()

            if parent.isAutoScrollEnabled {
                scheduleScrollToEnd()
            }
        }

        private func removeInterimIfNeeded(storage: NSTextStorage, textView: NSTextView) {
            guard storage.length > finalizedLength else {
                cursorRange = nil
                updateCursorTimer()
                lastInterimKey = nil
                return
            }
            replace(
                range: NSRange(location: finalizedLength, length: storage.length - finalizedLength),
                with: NSAttributedString(),
                storage: storage,
                textView: textView
            )
            cursorRange = nil
            cursorColor = nil
            updateCursorTimer()
            lastInterimKey = nil
        }

        private func replace(
            range: NSRange,
            with replacement: NSAttributedString,
            storage: NSTextStorage,
            textView: NSTextView
        ) {
            guard NSMaxRange(range) <= storage.length else { return }
            let oldSelection = textView.selectedRange()
            let resultingLength = storage.length - range.length + replacement.length
            let adjustedSelection = LiveTranscriptSelectionPolicy.adjustedRange(
                oldSelection,
                replacing: range,
                replacementLength: replacement.length,
                resultingLength: resultingLength
            )

            storage.beginEditing()
            storage.replaceCharacters(in: range, with: replacement)
            storage.endEditing()

            if adjustedSelection != oldSelection {
                textView.setSelectedRange(adjustedSelection)
            }
        }

        private struct RenderedInterim {
            let attributed: NSAttributedString
            let cursorLocalRange: NSRange?
            let cursorColor: NSColor
        }

        private func renderInterim(_ interim: LiveTranscriptInterimSnapshot) -> RenderedInterim {
            let result = NSMutableAttributedString()
            let speakerNSColor = NSColor(speakerColor(for: interim.speaker, selfIDs: interim.selfIDs))
            let bodyFont = NSFont.systemFont(ofSize: interim.bodyFontSize, weight: .regular)
            let headerFont = NSFont.systemFont(ofSize: interim.headerFontSize, weight: .semibold)
            let bodyParagraph = NSMutableParagraphStyle()
            bodyParagraph.lineSpacing = interim.lineSpacing
            bodyParagraph.paragraphSpacingBefore = interim.hasFinalizedContent && !interim.startsNewTurn ? 6 : 0
            let headerParagraph = NSMutableParagraphStyle()
            headerParagraph.paragraphSpacingBefore = interim.hasFinalizedContent ? 10 : 0
            headerParagraph.paragraphSpacing = 2

            if interim.startsNewTurn {
                let label = speakerDisplayName(
                    for: interim.speaker,
                    names: interim.speakerNames,
                    selfIDs: interim.selfIDs
                )
                let header = "\(interim.hasFinalizedContent ? "\n" : "")▎ \(label) • listening...\n"
                result.append(NSAttributedString(string: header, attributes: [
                    .font: headerFont,
                    .foregroundColor: speakerNSColor.withAlphaComponent(0.72),
                    .paragraphStyle: headerParagraph,
                ]))
            } else if interim.hasFinalizedContent {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: bodyFont,
                    .paragraphStyle: bodyParagraph,
                ]))
            }

            result.append(NSAttributedString(string: interim.text, attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor(ColorPalette.Text.muted),
                .paragraphStyle: bodyParagraph,
            ]))
            let cursorLocation = result.length
            result.append(NSAttributedString(string: "▊", attributes: [
                .font: bodyFont,
                .foregroundColor: speakerNSColor,
                .paragraphStyle: bodyParagraph,
            ]))
            return RenderedInterim(
                attributed: result,
                cursorLocalRange: NSRange(location: cursorLocation, length: 1),
                cursorColor: speakerNSColor
            )
        }

        private func updateCursorTimer() {
            cursorTimer?.invalidate()
            cursorTimer = nil
            guard cursorRange != nil, !parent.reduceMotion else {
                setCursorVisible(true)
                return
            }
            let timer = Timer(
                timeInterval: 0.5,
                target: self,
                selector: #selector(toggleCursorVisibility),
                userInfo: nil,
                repeats: true
            )
            RunLoop.main.add(timer, forMode: .common)
            cursorTimer = timer
        }

        @objc private func toggleCursorVisibility() {
            setCursorVisible(!cursorVisible)
        }

        private func setCursorVisible(_ visible: Bool) {
            guard let storage = textView?.textStorage,
                  let cursorRange,
                  NSMaxRange(cursorRange) <= storage.length,
                  let cursorColor else { return }
            cursorVisible = visible
            storage.addAttribute(
                .foregroundColor,
                value: visible ? cursorColor : cursorColor.withAlphaComponent(0),
                range: cursorRange
            )
        }

        private func scheduleScrollToEnd() {
            guard parent.isAutoScrollEnabled else { return }
            scrollRequestGeneration &+= 1
            let generation = scrollRequestGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      generation == self.scrollRequestGeneration,
                      self.parent.isAutoScrollEnabled,
                      let textView = self.textView,
                      let storage = textView.textStorage else { return }
                textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
            }
        }

        @objc private func didLiveScroll(_ notification: Notification) {
            guard parent.isAutoScrollEnabled,
                  let scrollView,
                  let documentView = scrollView.documentView else { return }
            let documentMaxY = documentView.bounds.maxY
            let visibleMaxY = scrollView.documentVisibleRect.maxY
            if documentMaxY - visibleMaxY > 30 {
                scrollRequestGeneration &+= 1
                parent.onScrolledAwayFromBottom()
            }
        }

        @objc private func scrollViewFrameDidChange(_ notification: Notification) {
            if parent.isAutoScrollEnabled {
                scheduleScrollToEnd()
            }
        }

        @objc private func textViewDidFallBackToTextKit1(_ notification: Notification) {
            liveTranscriptPaneLog.fault("Live transcript NSTextView unexpectedly fell back to TextKit 1")
        }
    }
}
#endif
