import XCTest
import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

final class SelectableAttributedTests: XCTestCase {

    typealias Turn = SelectableAttributed.TranscriptTurn

    // MARK: - mergeTurns

    func testMergeTurnsCollapsesSameSpeakerWithoutTerminator() {
        let turns = [
            Turn(speaker: 0, timestamp: 0, text: "Hello there"),
            Turn(speaker: 0, timestamp: 1, text: "how are you"),
        ]
        let merged = SelectableAttributed.mergeTurns(turns, speakerNames: nil, selfIDs: nil)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "Hello there how are you")
    }

    func testMergeTurnsKeepsCompletedSentencesInOneSpeakerTurn() {
        let turns = [
            Turn(speaker: 0, timestamp: 0, text: "Hello there."),
            Turn(speaker: 0, timestamp: 1, text: "How are you"),
        ]
        let merged = SelectableAttributed.mergeTurns(turns, speakerNames: nil, selfIDs: nil)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "Hello there. How are you")
    }

    func testMergeTurnsKeepsQuotedSentenceInOneSpeakerTurn() {
        let turns = [
            Turn(speaker: 0, timestamp: 0, text: "He said \"hi.\""),
            Turn(speaker: 0, timestamp: 1, text: "Then he left"),
        ]
        let merged = SelectableAttributed.mergeTurns(turns, speakerNames: nil, selfIDs: nil)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "He said \"hi.\" Then he left")
    }

    func testMergeTurnsGroupsAllSelfIDs() {
        // Two different speaker IDs both marked as self — should merge.
        let turns = [
            Turn(speaker: DeepgramService.micSpeakerID, timestamp: 0, text: "first part"),
            Turn(speaker: 42, timestamp: 1, text: "second part"),
        ]
        let merged = SelectableAttributed.mergeTurns(
            turns,
            speakerNames: nil,
            selfIDs: [DeepgramService.micSpeakerID, 42]
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "first part second part")
    }

    func testMergeTurnsGroupsIDsSharingInferredName() {
        // Two IDs, both mapped to "Alice" — diarization drift should collapse.
        let turns = [
            Turn(speaker: 1, timestamp: 0, text: "part one"),
            Turn(speaker: 2, timestamp: 1, text: "part two"),
        ]
        let merged = SelectableAttributed.mergeTurns(
            turns,
            speakerNames: ["1": "Alice", "2": "Alice"],
            selfIDs: nil
        )
        XCTAssertEqual(merged.count, 1)
    }

    func testMergeTurnsKeepsDifferentSpeakersSeparate() {
        let turns = [
            Turn(speaker: 1, timestamp: 0, text: "Alice speaking"),
            Turn(speaker: 2, timestamp: 1, text: "Bob speaking"),
        ]
        let merged = SelectableAttributed.mergeTurns(turns, speakerNames: nil, selfIDs: nil)
        XCTAssertEqual(merged.count, 2)
    }

    func testMergeTurnsNoLeadingSpaceBeforePunctuation() {
        let turns = [
            Turn(speaker: 0, timestamp: 0, text: "Hello"),
            Turn(speaker: 0, timestamp: 1, text: ", world"),
        ]
        let merged = SelectableAttributed.mergeTurns(turns, speakerNames: nil, selfIDs: nil)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "Hello, world")
    }

    func testMergeTurnsEmptyInput() {
        let merged = SelectableAttributed.mergeTurns([], speakerNames: nil, selfIDs: nil)
        XCTAssertTrue(merged.isEmpty)
    }

    // MARK: - displayGroupKey

    func testDisplayGroupKeySelfCollapses() {
        let key1 = SelectableAttributed.displayGroupKey(
            speaker: DeepgramService.micSpeakerID,
            names: nil,
            selfIDs: [DeepgramService.micSpeakerID, 99]
        )
        let key2 = SelectableAttributed.displayGroupKey(
            speaker: 99,
            names: nil,
            selfIDs: [DeepgramService.micSpeakerID, 99]
        )
        XCTAssertEqual(key1, key2)
    }

    func testDisplayGroupKeyDefaultSelfIsMic() {
        // Empty/nil selfIDs should treat micSpeakerID as self.
        let key = SelectableAttributed.displayGroupKey(
            speaker: DeepgramService.micSpeakerID,
            names: nil,
            selfIDs: nil
        )
        XCTAssertEqual(key, "self")
    }

    func testDisplayGroupKeyNameCollisionIsCaseInsensitive() {
        let a = SelectableAttributed.displayGroupKey(speaker: 1, names: ["1": "Alice"], selfIDs: nil)
        let b = SelectableAttributed.displayGroupKey(speaker: 2, names: ["2": "ALICE"], selfIDs: nil)
        XCTAssertEqual(a, b)
    }

    func testDisplayGroupKeyFallsBackToIDWhenNoName() {
        let key = SelectableAttributed.displayGroupKey(speaker: 7, names: [:], selfIDs: nil)
        XCTAssertEqual(key, "id:7")
    }

    // MARK: - builders don't crash on edge inputs

    func testTranscriptBuilderHandlesEmpty() {
        let attr = SelectableAttributed.transcript(turns: [], speakerNames: nil, selfIDs: nil)
        XCTAssertEqual(attr.length, 0)
    }

    func testTranscriptBuilderHandlesManyTurns() {
        // Sanity check that building a long attributed string is safe (this is the
        // kind of input that drove the recursive-constraint crash in v1.23.0).
        let turns = (0..<500).map {
            Turn(speaker: $0 % 3, timestamp: TimeInterval($0), text: "segment \($0)")
        }
        let attr = SelectableAttributed.transcript(turns: turns, speakerNames: nil, selfIDs: nil)
        XCTAssertGreaterThan(attr.length, 0)
    }

    func testTranscriptTailReplacementMatchesFullRebuild() {
        let initialTurns = [
            Turn(speaker: 1, timestamp: 0, text: "First speaker."),
            Turn(speaker: 2, timestamp: 4, text: "Second speaker begins"),
        ]
        let appendedTurns = [
            Turn(speaker: 2, timestamp: 7, text: ", and continues."),
            Turn(speaker: 3, timestamp: 10, text: "Third speaker."),
        ]
        let initial = SelectableAttributed.transcriptDocument(
            turns: initialTurns,
            speakerNames: nil,
            selfIDs: nil
        )
        let allTurns = SelectableAttributed.mergeTurns(
            initialTurns + appendedTurns,
            speakerNames: nil,
            selfIDs: nil
        )
        let tailStartIndex = initial.turns.count - 1
        let tail = SelectableAttributed.transcriptDocument(
            turns: Array(allTurns[tailStartIndex...]),
            speakerNames: nil,
            selfIDs: nil,
            startsAtDocumentBeginning: false
        )
        let incrementallyUpdated = NSMutableAttributedString(attributedString: initial.attributed)
        let replacementStart = initial.turnStartOffsets[tailStartIndex]
        incrementallyUpdated.replaceCharacters(
            in: NSRange(
                location: replacementStart,
                length: incrementallyUpdated.length - replacementStart
            ),
            with: tail.attributed
        )
        let fullyRebuilt = SelectableAttributed.transcript(
            turns: initialTurns + appendedTurns,
            speakerNames: nil,
            selfIDs: nil
        )

        XCTAssertTrue(incrementallyUpdated.isEqual(to: fullyRebuilt))
    }

    func testTranscriptRenderModelMapsSelectionAcrossSegmentBodies() {
        let firstID = UUID()
        let secondID = UUID()
        let renderModel = SelectableAttributed.transcriptRenderModel(
            segments: [
                .init(id: firstID, speaker: 1, timestamp: 0, text: "first segment"),
                .init(id: secondID, speaker: 2, timestamp: 3, text: "second segment"),
            ],
            speakerNames: nil,
            selfIDs: nil
        )

        let firstSpan = renderModel.spans[0]
        let secondSpan = renderModel.spans[1]
        let selectionStart = firstSpan.bodyRange.location + 6
        let selectionEnd = secondSpan.bodyRange.location + 6
        let selections = renderModel.textSelections(overlapping: NSRange(location: selectionStart, length: selectionEnd - selectionStart))

        XCTAssertEqual(selections.count, 2)
        XCTAssertEqual(selections[0], TranscriptTextSelection(segmentID: firstID, lowerUTF16Offset: 6, upperUTF16Offset: 13))
        XCTAssertEqual(selections[1], TranscriptTextSelection(segmentID: secondID, lowerUTF16Offset: 0, upperUTF16Offset: 6))
    }

    func testTranscriptRenderModelShowsOneHeaderForConsecutiveSpeakerSegments() {
        let renderModel = SelectableAttributed.transcriptRenderModel(
            segments: [
                .init(id: UUID(), speaker: 1, timestamp: 0, text: "First sentence."),
                .init(id: UUID(), speaker: 1, timestamp: 2, text: "Second sentence."),
                .init(id: UUID(), speaker: 2, timestamp: 4, text: "Different speaker."),
            ],
            speakerNames: nil,
            selfIDs: nil
        )

        XCTAssertGreaterThan(renderModel.spans[0].headerRange.length, 0)
        XCTAssertEqual(renderModel.spans[1].headerRange.length, 0)
        XCTAssertGreaterThan(renderModel.spans[2].headerRange.length, 0)
        XCTAssertTrue(renderModel.attributed.string.contains("First sentence. Second sentence."))
    }

    func testBulletListBuilderHandlesEmpty() {
        let attr = SelectableAttributed.bulletList(
            items: [],
            prefix: "→",
            prefixColor: .blue
        )
        XCTAssertEqual(attr.length, 0)
    }

    func testListWrappingAlignsWithTheFirstWordAtReadingSizes() throws {
        for points: CGFloat in [13, 17, 36] {
            for prefix in ["→", "->", "•"] {
                let text = SelectableAttributed.bulletList(
                    items: [String(repeating: "readable words ", count: 12)],
                    prefix: prefix, prefixColor: ColorPalette.Status.success,
                    fontSize: points, lineSpacing: 5)
                let storage = NSTextStorage(attributedString: text)
                let layout = NSLayoutManager()
                let container = NSTextContainer(size: CGSize(width: 260, height: 4000))
                container.lineFragmentPadding = 0
                storage.addLayoutManager(layout)
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                let firstWord = layout.glyphIndexForCharacter(at: (prefix + " ").utf16.count)
                var line = NSRange()
                let firstRect = layout.lineFragmentRect(forGlyphAt: firstWord, effectiveRange: &line)
                let firstX = firstRect.minX + layout.location(forGlyphAt: firstWord).x
                let nextLine = NSMaxRange(line)
                XCTAssertLessThan(nextLine, layout.numberOfGlyphs)
                let nextRect = layout.lineFragmentRect(forGlyphAt: nextLine, effectiveRange: nil)
                let wrappedX = nextRect.minX + layout.location(forGlyphAt: nextLine).x
                XCTAssertEqual(firstX, wrappedX, accuracy: 0.5, "\(prefix), \(points) pt")
            }
        }
    }

    func testBodyBuilderHandlesEmptyString() {
        let attr = SelectableAttributed.body("")
        XCTAssertEqual(attr.length, 0)
    }

    func testNumberedListAlignsSingleAndDoubleDigitItemsAndPreservesParagraphs() throws {
        let items = (1...12).map { "Item \($0) " + String(repeating: "readable words ", count: 8) }
        for points: CGFloat in [13, 36] {
            let text = SelectableAttributed.list(items: items, marker: .numbered,
                markerColor: ColorPalette.Text.muted, fontSize: points, lineSpacing: 5)
            XCTAssertEqual(text.string, items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
            let storage = NSTextStorage(attributedString: text)
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 280, height: 20000))
            container.lineFragmentPadding = 0
            storage.addLayoutManager(layout); layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            var bodyColumn: CGFloat?
            for index in 1...12 {
                let range = (text.string as NSString).range(of: "Item \(index) ")
                let glyph = layout.glyphIndexForCharacter(at: range.location)
                var line = NSRange()
                let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &line)
                let x = rect.minX + layout.location(forGlyphAt: glyph).x
                if let bodyColumn { XCTAssertEqual(x, bodyColumn, accuracy: 0.5) }
                bodyColumn = x
                let next = NSMaxRange(line)
                let nextRect = layout.lineFragmentRect(forGlyphAt: next, effectiveRange: nil)
                XCTAssertEqual(x, nextRect.minX + layout.location(forGlyphAt: next).x, accuracy: 0.5)
            }
        }
        let content = "First 👩🏽‍💻 line\r\nSecond paragraph\nThird paragraph"
        let text = SelectableAttributed.bulletList(items: [content, "Last item"], prefix: "→",
            prefixColor: ColorPalette.Status.success, fontSize: 17, lineSpacing: 5)
        XCTAssertEqual(text.string, "→ " + content + "\n→ Last item")
        let first = try XCTUnwrap(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 280, height: 2000))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        func glyphX(at character: Int) -> CGFloat {
            let glyph = layout.glyphIndexForCharacter(at: character)
            return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX
                + layout.location(forGlyphAt: glyph).x
        }
        let firstWordX = glyphX(at: 2)
        for word in ["Second", "Third"] {
            let range = (text.string as NSString).range(of: word)
            let continuation = try XCTUnwrap(text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
            XCTAssertEqual(continuation.firstLineHeadIndent, first.headIndent)
            XCTAssertEqual(continuation.headIndent, first.headIndent)
            XCTAssertEqual(glyphX(at: range.location), firstWordX, accuracy: 0.5,
                           "Explicit paragraph continuations must align in actual layout")
        }
    }

    @MainActor
    func testInsightListUsesOneSelectableNativeDocumentAtEveryReadingScale() async throws {
        for scale in InterfaceScale.allCases {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let root = InsightList(items: ["First action", "Second action"], markerColor: ColorPalette.Status.success)
                    .minitiInterfaceScale(scale, systemSize: size)
                #if os(macOS)
                let host = NSHostingView(rootView: root)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host; window.orderFront(nil)
                defer { window.orderOut(nil); window.close() }
                #else
                let host = UIHostingController(rootView: root)
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let previousWindow = scene.windows.first(where: \.isKeyWindow)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                window.rootViewController = host; window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
                #endif
                try await TestSupport.waitUntil {
                    Self.nativeReadingTextViews(in: host.viewForReadingTest).contains {
                        Self.readingText($0).string.contains("Second action")
                    }
                }
                let views = Self.nativeReadingTextViews(in: host.viewForReadingTest)
                XCTAssertEqual(views.count, 1, "Selection must span the whole list")
                let view = try XCTUnwrap(views.first)
                let text = Self.readingText(view)
                XCTAssertEqual(text.string, "→ First action\n→ Second action")
                XCTAssertTrue(view.isSelectable)
                XCTAssertFalse(view.isEditable)
                let metrics = ReadingMetrics(interfaceScale: scale, systemDynamicTypeSize: size)
                let font = try XCTUnwrap(text.attribute(.font, at: 2, effectiveRange: nil) as? ReadingNativeFont)
                let paragraph = try XCTUnwrap(text.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle)
                XCTAssertEqual(font.pointSize, metrics.insightBodySize, accuracy: 0.01)
                XCTAssertEqual(paragraph.lineSpacing, metrics.insightLineSpacing, accuracy: 0.01)
                let selection = NSRange(location: 2, length: text.length - 2)
                #if os(macOS)
                view.setSelectedRange(selection)
                XCTAssertEqual(view.selectedRange(), selection)
                #else
                view.selectedRange = selection
                XCTAssertEqual(view.selectedRange, selection)
                XCTAssertFalse(view.adjustsFontForContentSizeCategory)
                #endif
                XCTAssertEqual(Self.readingText(view).string, text.string)
            }
        }
    }

    func testBodyBuilderUsesReadableProportionalSystemFont() {
        let attr = SelectableAttributed.body("Readable meeting notes")
        #if os(macOS)
        let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertFalse(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? true)
        #else
        let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertFalse(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? true)
        #endif
    }

    func testConsentReadingBaselinesAndPlatformScaling() {
        #if os(macOS)
        let body: [CGFloat] = [13, 14, 15]
        let headings: [CGFloat] = [17, 18, 19]
        let secondary: [CGFloat] = [12, 13, 14]
        #else
        let body: [CGFloat] = [13, 15, 17]
        let headings: [CGFloat] = [17, 19, 21]
        let secondary: [CGFloat] = [12, 14, 16]
        #endif
        for scale in InterfaceScale.allCases {
            let normal = ReadingMetrics(interfaceScale: scale, systemDynamicTypeSize: .large)
            let largest = ReadingMetrics(interfaceScale: scale, systemDynamicTypeSize: .accessibility5)
            XCTAssertEqual(normal.consentBodySize, body[scale.rawValue])
            XCTAssertEqual(normal.consentHeadingSize, headings[scale.rawValue])
            XCTAssertEqual(normal.consentSecondarySize, secondary[scale.rawValue])
            #if os(macOS)
            XCTAssertEqual(normal, largest)
            #else
            XCTAssertGreaterThan(largest.consentBodySize, normal.consentBodySize)
            XCTAssertGreaterThan(largest.consentHeadingSize, normal.consentHeadingSize)
            XCTAssertGreaterThan(largest.consentSecondarySize, normal.consentSecondarySize)
            #endif
        }
    }

    func testCompactInterfaceScalePreservesOriginalTranscriptMetrics() {
        XCTAssertEqual(InterfaceScale.compact.transcriptBodySize, 13)
        XCTAssertEqual(InterfaceScale.compact.transcriptHeaderSize, 10)
        XCTAssertEqual(InterfaceScale.compact.transcriptLineSpacing, 2)
        XCTAssertEqual(InterfaceScale.compact.dynamicTypeSize(from: .accessibility2), .accessibility2)
        XCTAssertEqual(InterfaceScale.standard.dynamicTypeSize(from: .large), .xLarge)
        XCTAssertEqual(InterfaceScale.large.dynamicTypeSize(from: .large), .xxLarge)

        #if os(macOS)
        XCTAssertEqual(InterfaceScale.standard.transcriptBodySize, 14)
        #else
        XCTAssertEqual(InterfaceScale.standard.transcriptBodySize, 15)
        #endif
    }

    func testInsightTypographyMatchesTranscriptAtEveryInterfaceScale() {
        for scale in InterfaceScale.allCases {
            XCTAssertEqual(scale.insightBodySize, scale.transcriptBodySize)
            XCTAssertEqual(scale.insightSecondarySize, scale.transcriptBodySize)
            XCTAssertEqual(scale.insightLineSpacing, scale.transcriptLineSpacing)
        }
    }

    func testResolvedReadingMetricsPreserveBaselinesAndPlatformScaling() {
        for scale in InterfaceScale.allCases {
            let normal = ReadingMetrics(interfaceScale: scale, systemDynamicTypeSize: .large)
            XCTAssertEqual(normal.transcriptBodySize, scale.transcriptBodySize)
            XCTAssertEqual(normal.transcriptHeaderSize, scale.transcriptHeaderSize)
            XCTAssertEqual(normal.transcriptLineSpacing, scale.transcriptLineSpacing)
            for size in DynamicTypeSize.allCases {
                let resolved = ReadingMetrics(interfaceScale: scale, systemDynamicTypeSize: size)
                XCTAssertEqual(resolved.insightBodySize, resolved.transcriptBodySize)
                XCTAssertEqual(resolved.insightLineSpacing, resolved.transcriptLineSpacing)
                #if os(macOS)
                XCTAssertEqual(resolved, normal, "Mac has no system text-size multiplier")
                #else
                if size.isAccessibilitySize {
                    XCTAssertGreaterThan(resolved.transcriptBodySize, normal.transcriptBodySize)
                    XCTAssertGreaterThan(resolved.notesBodySize, normal.notesBodySize)
                }
                #endif
            }
        }
        let compact = ReadingMetrics(interfaceScale: .compact, systemDynamicTypeSize: .large)
        XCTAssertEqual(compact.transcriptBodySize, 13)
        #if os(macOS)
        XCTAssertEqual(compact.notesBodySize, 12)
        #else
        XCTAssertEqual(compact.notesBodySize, 14)
        #endif
    }

    func testNotesMetricsPreserveTheirOwnBaselineAtEveryInterfaceScale() {
        #if os(macOS)
        let expected: [CGFloat] = [12, 13, 14]
        #else
        let expected: [CGFloat] = [14, 16, 18]
        #endif
        for (scale, points) in zip(InterfaceScale.allCases, expected) {
            XCTAssertEqual(ReadingMetrics(interfaceScale: scale, systemDynamicTypeSize: .large).notesBodySize, points)
            let accessible = ReadingMetrics(interfaceScale: scale, systemDynamicTypeSize: .accessibility5)
            #if os(macOS)
            XCTAssertEqual(accessible.notesBodySize, points)
            #else
            let expectedAccessible = UIFontMetrics(forTextStyle: .body).scaledValue(
                for: points, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
            XCTAssertEqual(accessible.notesBodySize, expectedAccessible, accuracy: 0.01)
            let small = ReadingMetrics(interfaceScale: scale, systemDynamicTypeSize: .xSmall)
            XCTAssertLessThan(small.notesBodySize, points, "Respect a deliberately smaller system text setting too")
            #endif
        }
    }

    /// The production root modifier supplies the original system category, even
    /// though semantic controls see InterfaceScale's shifted category. Inspect
    /// actual native fonts, not just the values handed to a builder.
    @MainActor
    func testReadingMetricsReachSwiftUIAndAttributedRenderersExactlyOnce() async throws {
        for scale in InterfaceScale.allCases {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let root = ReadingRendererFixture()
                    .minitiInterfaceScale(scale, systemSize: size)
                #if os(macOS)
                let host = NSHostingView(rootView: root)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.orderFront(nil)
                defer { window.orderOut(nil); window.close() }
                let expected = scale.transcriptBodySize
                #else
                let host = UIHostingController(rootView: root)
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let previousWindow = scene.windows.first(where: \.isKeyWindow)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
                let category: UIContentSizeCategory = size == .large ? .large : .accessibilityExtraExtraExtraLarge
                let expected = UIFontMetrics(forTextStyle: .body).scaledValue(
                    for: scale.transcriptBodySize,
                    compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
                #endif
                let markers = ["SwiftUI prose", "Sales prose", "Transcript prose"]
                try await TestSupport.waitUntil {
                    markers.allSatisfy { marker in
                        Self.nativeReadingTextViews(in: host.viewForReadingTest).contains {
                            Self.readingText($0).string.contains(marker)
                        }
                    }
                }
                for marker in markers {
                    let view = try XCTUnwrap(Self.nativeReadingTextViews(in: host.viewForReadingTest).first {
                        Self.readingText($0).string.contains(marker)
                    })
                    let text = Self.readingText(view)
                    let range = (text.string as NSString).range(of: marker)
                    let font = try XCTUnwrap(text.attribute(.font, at: range.location, effectiveRange: nil) as? ReadingNativeFont)
                    XCTAssertEqual(font.pointSize, expected, accuracy: 0.01, "\(marker), \(scale), \(size)")
                    #if os(iOS)
                    if marker != "SwiftUI prose" {
                        XCTAssertFalse(view.adjustsFontForContentSizeCategory)
                    }
                    #endif
                }
            }
        }
    }

    @MainActor
    private static func nativeReadingTextViews(in view: ReadingNativeView) -> [ReadingNativeTextView] {
        (view as? ReadingNativeTextView).map { [$0] } ?? view.subviews.flatMap { nativeReadingTextViews(in: $0) }
    }

    #if os(macOS)
    @MainActor
    func testProductionLiveAndSavedNotesUseTheNotesRole() async throws {
        let state = AppState()
        state.liveNotes = "Live notes fixture"
        let meeting = Meeting(notes: "Saved notes fixture")
        for (scale, expected) in zip(InterfaceScale.allCases, [CGFloat(12), 13, 14]) {
            let root = VStack {
                NotesEditor()
                SavedNotesView(meeting: meeting)
            }.environmentObject(state)
                .minitiInterfaceScale(scale, systemSize: .accessibility5)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil); window.close() }
            for marker in [state.liveNotes, meeting.notes] {
                try await TestSupport.waitUntil {
                    Self.nativeReadingTextViews(in: host).contains { $0.string == marker }
                }
                let view = try XCTUnwrap(Self.nativeReadingTextViews(in: host).first { $0.string == marker })
                XCTAssertEqual(view.font?.pointSize, expected)
            }
        }
    }
    #endif

    #if os(iOS)
    @MainActor
    func testLiveTranscriptReflowsOnSystemSizeChangeAndKeepsFinalAndInterimWords() async throws {
        let state = AppState()
        let sentence = "A longer synthetic turn wraps across several lines in the live transcript. "
        state.liveSegments = (0..<10).map {
            .init(id: UUID(), text: sentence + "Turn \($0).", speaker: $0 % 2, timestamp: Double($0 * 10), isFinal: true)
        }
        state.transcriptRuntime.update(interimText: "Current interim words", currentSpeaker: 1, interimSpeaker: 1)
        let original = state.liveSegments
        let preferences = ReadingFixturePreferences()
        var rebuilds = 0
        let host = UIHostingController(rootView: LiveReadingFixture(preferences: preferences) { event, _, _ in
            if event == "rebuilt" { rebuilds += 1 }
        }.environmentObject(state))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        func scrollViews(_ view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        func contentHeight() -> CGFloat {
            host.view.layoutIfNeeded()
            return scrollViews(host.view).map { $0.contentSize.height }.max() ?? 0
        }
        try await TestSupport.waitUntil { rebuilds > 0 && contentHeight() > 400 }
        let originalHeight = contentHeight()
        let initialRebuilds = rebuilds
        preferences.systemSize = .accessibility5
        try await TestSupport.waitUntil { rebuilds > initialRebuilds && contentHeight() > originalHeight * 1.5 }
        XCTAssertGreaterThan(contentHeight(), originalHeight * 1.5, "Real SwiftUI transcript rows must reflow")
        XCTAssertEqual(state.liveSegments, original)
        XCTAssertEqual(state.transcriptRuntime.snapshot.interimText, "Current interim words")
    }

    @MainActor
    func testOpenSavedTranscriptRespondsToSystemSizeWithoutChangingTextOrSelection() async throws {
        let container = try TestSupport.makeInMemoryContainer()
        let marker = "Saved transcript prose remains selectable."
        let meeting = Meeting(segments: [.init(text: marker, speaker: 1, timestamp: 0, isFinal: true)])
        container.mainContext.insert(meeting)
        let state = AppState()
        let preferences = ReadingFixturePreferences()
        let host = UIHostingController(rootView: SavedReadingFixture(preferences: preferences, meeting: meeting)
            .environmentObject(state).modelContainer(container))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        host.view.layoutIfNeeded()
        try await TestSupport.waitUntil {
            Self.nativeReadingTextViews(in: host.view).contains { $0.text.contains(marker) }
        }
        let view = try XCTUnwrap(Self.nativeReadingTextViews(in: host.view).first { $0.text.contains(marker) })
        let initial = view.attributedText!.copy() as! NSAttributedString
        let range = (initial.string as NSString).range(of: "prose")
        let initialFont = try XCTUnwrap(initial.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(initialFont.pointSize, 15)
        view.selectedRange = range
        preferences.systemSize = .accessibility5
        let expected = UIFontMetrics(forTextStyle: .body).scaledValue(
            for: 15, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        try await TestSupport.waitUntil {
            (view.attributedText?.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont)?.pointSize == expected
        }
        XCTAssertEqual(view.text, initial.string)
        XCTAssertEqual(view.selectedRange, range)
        XCTAssertEqual(meeting.segments.first?.text, marker)
        XCTAssertEqual(meeting.transcriptRevision, 0)
    }
    #endif

    @MainActor
    private static func readingText(_ view: ReadingNativeTextView) -> NSAttributedString {
        #if os(macOS)
        view.attributedString()
        #else
        view.attributedText ?? NSAttributedString()
        #endif
    }

    func testLiveAndSavedTranscriptBuildersUseMatchingTypographyMetrics() throws {
        let live = SelectableAttributed.transcript(
            turns: [Turn(speaker: 1, timestamp: 0, text: "Matching transcript body")],
            speakerNames: nil,
            bodyFontSize: 15,
            headerFontSize: 11,
            lineSpacing: 5
        )
        let saved = SelectableAttributed.transcriptRenderModel(
            segments: [.init(id: UUID(), speaker: 1, timestamp: 0, text: "Matching transcript body")],
            speakerNames: nil,
            bodyFontSize: 15,
            headerFontSize: 11,
            lineSpacing: 5
        ).attributed

        let liveBodyIndex = try XCTUnwrap(live.string.range(of: "Matching transcript body"))
        let savedBodyIndex = try XCTUnwrap(saved.string.range(of: "Matching transcript body"))
        let liveOffset = live.string.utf16.distance(from: live.string.utf16.startIndex, to: liveBodyIndex.lowerBound.samePosition(in: live.string.utf16)!)
        let savedOffset = saved.string.utf16.distance(from: saved.string.utf16.startIndex, to: savedBodyIndex.lowerBound.samePosition(in: saved.string.utf16)!)

        #if os(macOS)
        let liveFont = try XCTUnwrap(live.attribute(.font, at: liveOffset, effectiveRange: nil) as? NSFont)
        let savedFont = try XCTUnwrap(saved.attribute(.font, at: savedOffset, effectiveRange: nil) as? NSFont)
        #else
        let liveFont = try XCTUnwrap(live.attribute(.font, at: liveOffset, effectiveRange: nil) as? UIFont)
        let savedFont = try XCTUnwrap(saved.attribute(.font, at: savedOffset, effectiveRange: nil) as? UIFont)
        #endif
        let liveParagraph = try XCTUnwrap(live.attribute(.paragraphStyle, at: liveOffset, effectiveRange: nil) as? NSParagraphStyle)
        let savedParagraph = try XCTUnwrap(saved.attribute(.paragraphStyle, at: savedOffset, effectiveRange: nil) as? NSParagraphStyle)

        XCTAssertEqual(liveFont.pointSize, savedFont.pointSize)
        XCTAssertEqual(liveFont.pointSize, 15)
        XCTAssertEqual(liveParagraph.lineSpacing, savedParagraph.lineSpacing)
        XCTAssertEqual(liveParagraph.lineSpacing, 5)
    }

    #if os(macOS)
    @MainActor
    func testTranscriptMeasurementRejectsTransientNarrowerProposal() {
        let container = _SelectableTextContainer(
            attributed: NSAttributedString(string: "Transcript"),
            mutation: nil,
            onSelectionChange: nil,
            onDeleteSelection: nil
        )
        container.frame = NSRect(x: 0, y: 0, width: 480, height: 100)

        XCTAssertEqual(container.reliableMeasurementWidth(for: 220), 480)
        XCTAssertEqual(container.reliableMeasurementWidth(for: 479), 480)
        XCTAssertEqual(container.reliableMeasurementWidth(for: 620), 620)
        XCTAssertEqual(container.reliableMeasurementWidth(for: nil), 480)

        container.frame = NSRect(x: 0, y: 0, width: 320, height: 100)
        XCTAssertEqual(container.reliableMeasurementWidth(for: 320), 320)
    }

    @MainActor
    func testLongTranscriptHeightStaysAccurateAcrossIncrementalTailUpdates() {
        var turns: [Turn] = []
        var document = SelectableAttributed.transcriptDocument(
            turns: turns,
            speakerNames: nil
        )
        let container = _SelectableTextContainer(
            attributed: document.attributed,
            mutation: nil,
            onSelectionChange: nil,
            onDeleteSelection: nil
        )

        for index in 0..<320 {
            let appendedTurn = Turn(
                speaker: (index / 4) % 2,
                timestamp: TimeInterval(index * 3),
                text: "Finalized transcript sentence \(index) with enough words to wrap naturally."
            )
            let mergedTurns = SelectableAttributed.mergeTurns(
                turns + [appendedTurn],
                speakerNames: nil,
                selfIDs: nil
            )
            let replacementTurnIndex = max(0, document.turns.count - 1)
            let replacementStart = document.turnStartOffsets.indices.contains(replacementTurnIndex)
                ? document.turnStartOffsets[replacementTurnIndex]
                : 0
            let replacementDocument = SelectableAttributed.transcriptDocument(
                turns: Array(mergedTurns.dropFirst(replacementTurnIndex)),
                speakerNames: nil,
                startsAtDocumentBeginning: replacementTurnIndex == 0
            )
            let next = SelectableAttributed.transcriptDocument(
                turns: turns + [appendedTurn],
                speakerNames: nil
            )
            container.apply(
                next.attributed,
                mutation: SelectableTextMutation(
                    revision: UInt64(index + 1),
                    range: NSRange(
                        location: replacementStart,
                        length: document.attributed.length - replacementStart
                    ),
                    replacement: replacementDocument.attributed
                ),
                onSelectionChange: nil,
                onDeleteSelection: nil
            )
            turns.append(appendedTurn)
            document = next
            _ = container.measuredHeight(for: 420)
        }

        let freshContainer = _SelectableTextContainer(
            attributed: document.attributed,
            mutation: nil,
            onSelectionChange: nil,
            onDeleteSelection: nil
        )
        let incrementalHeight = container.measuredHeight(for: 420)
        let freshHeight = freshContainer.measuredHeight(for: 420)

        XCTAssertEqual(incrementalHeight, freshHeight, accuracy: 1)
        XCTAssertLessThan(incrementalHeight, 30_000)
        XCTAssertEqual(container.reliableMeasurementWidth(for: 1), 420)
        XCTAssertEqual(container.reliableMeasurementWidth(for: nil), 420)
    }

    func testLiveTranscriptSelectionBeforeTailMutationIsPreserved() {
        let adjusted = LiveTranscriptSelectionPolicy.adjustedRange(
            NSRange(location: 12, length: 18),
            replacing: NSRange(location: 80, length: 20),
            replacementLength: 35,
            resultingLength: 115
        )

        XCTAssertEqual(adjusted, NSRange(location: 12, length: 18))
    }

    func testLiveTranscriptSelectionAfterTailMutationTracksCharacterDelta() {
        let adjusted = LiveTranscriptSelectionPolicy.adjustedRange(
            NSRange(location: 120, length: 10),
            replacing: NSRange(location: 80, length: 20),
            replacementLength: 35,
            resultingLength: 145
        )

        XCTAssertEqual(adjusted, NSRange(location: 135, length: 10))
    }

    func testLiveTranscriptSelectionIntersectingVolatileTailCollapsesSafely() {
        let adjusted = LiveTranscriptSelectionPolicy.adjustedRange(
            NSRange(location: 75, length: 20),
            replacing: NSRange(location: 80, length: 20),
            replacementLength: 35,
            resultingLength: 115
        )

        XCTAssertEqual(adjusted, NSRange(location: 75, length: 0))
    }

    func testLiveTranscriptCaretAtInterimInsertionPointDoesNotMove() {
        let adjusted = LiveTranscriptSelectionPolicy.adjustedRange(
            NSRange(location: 80, length: 0),
            replacing: NSRange(location: 80, length: 0),
            replacementLength: 12,
            resultingLength: 92
        )

        XCTAssertEqual(adjusted, NSRange(location: 80, length: 0))
    }

    func testLocalizedLiveTranscriptMutationReconstructsMiddleInsertion() throws {
        let previous = SelectableAttributed.transcriptDocument(
            turns: [
                Turn(speaker: 1, timestamp: 0, text: "First speaker."),
                Turn(speaker: 2, timestamp: 10, text: "Third speaker."),
            ],
            speakerNames: nil
        ).attributed
        let next = SelectableAttributed.transcriptDocument(
            turns: [
                Turn(speaker: 1, timestamp: 0, text: "First speaker."),
                Turn(speaker: 3, timestamp: 5, text: "Second speaker."),
                Turn(speaker: 2, timestamp: 10, text: "Third speaker."),
            ],
            speakerNames: nil
        ).attributed

        let mutation = try XCTUnwrap(
            LiveTranscriptDocumentMutation.localizedReplacement(
                previous: previous,
                next: next,
                revision: 2
            )
        )
        let reconstructed = NSMutableAttributedString(attributedString: previous)
        reconstructed.replaceCharacters(in: mutation.range, with: mutation.replacement)

        XCTAssertTrue(reconstructed.isEqual(to: next))
        XCTAssertLessThan(mutation.range.length, previous.length)
        XCTAssertLessThan(mutation.replacement.length, next.length)
    }

    func testLocalizedLiveTranscriptMutationHandlesChangedSpeakerGrouping() throws {
        let previous = SelectableAttributed.transcriptDocument(
            turns: [
                Turn(speaker: 1, timestamp: 0, text: "Opening sentence."),
                Turn(speaker: 2, timestamp: 10, text: "Closing sentence."),
            ],
            speakerNames: nil
        ).attributed
        let next = SelectableAttributed.transcriptDocument(
            turns: [
                Turn(speaker: 1, timestamp: 0, text: "Opening sentence."),
                Turn(speaker: 2, timestamp: 7, text: "Earlier part"),
                Turn(speaker: 2, timestamp: 10, text: "Closing sentence."),
            ],
            speakerNames: nil
        ).attributed

        let mutation = try XCTUnwrap(
            LiveTranscriptDocumentMutation.localizedReplacement(
                previous: previous,
                next: next,
                revision: 3
            )
        )
        let reconstructed = NSMutableAttributedString(attributedString: previous)
        reconstructed.replaceCharacters(in: mutation.range, with: mutation.replacement)

        XCTAssertTrue(reconstructed.isEqual(to: next))
    }

    func testLocalizedMiddleInsertionPreservesSelectionBeforeChange() throws {
        let previous = SelectableAttributed.transcriptDocument(
            turns: [
                Turn(speaker: 1, timestamp: 0, text: "Stable selected sentence."),
                Turn(speaker: 2, timestamp: 10, text: "Later sentence."),
            ],
            speakerNames: nil
        ).attributed
        let next = SelectableAttributed.transcriptDocument(
            turns: [
                Turn(speaker: 1, timestamp: 0, text: "Stable selected sentence."),
                Turn(speaker: 3, timestamp: 5, text: "Inserted sentence."),
                Turn(speaker: 2, timestamp: 10, text: "Later sentence."),
            ],
            speakerNames: nil
        ).attributed
        let mutation = try XCTUnwrap(
            LiveTranscriptDocumentMutation.localizedReplacement(
                previous: previous,
                next: next,
                revision: 4
            )
        )
        let stableText = previous.string as NSString
        let stableSelection = stableText.range(of: "Stable selected")

        let adjusted = LiveTranscriptSelectionPolicy.adjustedRange(
            stableSelection,
            replacing: mutation.range,
            replacementLength: mutation.replacement.length,
            resultingLength: next.length
        )

        XCTAssertEqual(adjusted, stableSelection)
    }

    func testLocalizedMutationStaysBoundedInLongTranscript() throws {
        let previousTurns = (0..<500).map { index in
            Turn(
                speaker: index % 3,
                timestamp: TimeInterval(index * 2),
                text: "Finalized sentence \(index)."
            )
        }
        var nextTurns = previousTurns
        nextTurns.insert(
            Turn(speaker: 8, timestamp: 499, text: "Chronologically delayed sentence."),
            at: 250
        )
        let previous = SelectableAttributed.transcriptDocument(
            turns: previousTurns,
            speakerNames: nil
        ).attributed
        let next = SelectableAttributed.transcriptDocument(
            turns: nextTurns,
            speakerNames: nil
        ).attributed

        let mutation = try XCTUnwrap(
            LiveTranscriptDocumentMutation.localizedReplacement(
                previous: previous,
                next: next,
                revision: 5
            )
        )
        let reconstructed = NSMutableAttributedString(attributedString: previous)
        reconstructed.replaceCharacters(in: mutation.range, with: mutation.replacement)

        XCTAssertTrue(reconstructed.isEqual(to: next))
        XCTAssertLessThan(mutation.range.length, previous.length / 10)
        XCTAssertLessThan(mutation.replacement.length, next.length / 10)
    }

    @MainActor
    func testMacInterimPromotionIsOneDocumentEditAndBrightensOnlyNewWords() async throws {
        let prefix = NSAttributedString(string: "Existing words.", attributes: [.foregroundColor: NSColor(ColorPalette.Text.secondary)])
        let tail = NSAttributedString(string: " New words.", attributes: [.foregroundColor: NSColor(ColorPalette.Text.secondary)])
        let full = NSMutableAttributedString(attributedString: prefix); full.append(tail)
        let interim = LiveTranscriptInterimSnapshot(revision: 1, text: "New words", speaker: 1, startsNewTurn: false,
            hasFinalizedContent: true, speakerNames: [:], selfIDs: [], bodyFontSize: 17, headerFontSize: 13, lineSpacing: 3)
        let initial = LiveTranscriptTextPaneMac(finalizedAttributed: prefix, finalizedMutation: nil, finalizedRevision: 1,
            interim: interim, isAutoScrollEnabled: false, reduceMotion: false, onScrolledAwayFromBottom: {})
        let scroll = NSTextView.scrollableDocumentContentTextView()
        let view = try XCTUnwrap(scroll.documentView as? NSTextView)
        LiveTranscriptTextPaneMac.configure(scrollView: scroll, textView: view)
        let coordinator = LiveTranscriptTextPaneMac.Coordinator(parent: initial)
        coordinator.attach(scrollView: scroll, textView: view); coordinator.apply(parent: initial)
        defer { coordinator.detach() }
        let storage = try XCTUnwrap(view.textStorage)
        XCTAssertEqual(storage.string, "Existing words. New words▊", "Same-speaker interim stays in the final paragraph")
        var publishedDocuments: [String] = []
        let token = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { _ in
            MainActor.assumeIsolated { publishedDocuments.append(storage.string) }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        view.setSelectedRange(NSRange(location: 0, length: 8))
        let final = LiveTranscriptTextPaneMac(finalizedAttributed: full,
            finalizedMutation: .init(revision: 2, range: NSRange(location: prefix.length, length: 0), replacement: tail),
            finalizedRevision: 2, interim: nil, isAutoScrollEnabled: false, reduceMotion: false, onScrolledAwayFromBottom: {})
        coordinator.apply(parent: final)
        XCTAssertEqual(publishedDocuments, [full.string], "Never publish the blank gap or duplicate words")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 8))
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor(ColorPalette.Text.secondary))
        XCTAssertNotEqual(storage.attribute(.foregroundColor, at: prefix.length, effectiveRange: nil) as? NSColor, NSColor(ColorPalette.Text.secondary))
        try await TestSupport.waitUntil {
            (storage.attribute(.foregroundColor, at: prefix.length, effectiveRange: nil) as? NSColor) == NSColor(ColorPalette.Text.secondary)
        }
        XCTAssertEqual(storage.string, full.string)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: prefix.length, effectiveRange: nil) as? NSColor, NSColor(ColorPalette.Text.secondary))
        XCTAssertTrue(publishedDocuments.allSatisfy { $0 == full.string })
    }

    @MainActor
    func testReduceMotionCommitsImmediatelyWithoutFadeOrLaterAttributeEdits() async throws {
        let color = NSColor(ColorPalette.Text.secondary)
        let prefix = NSAttributedString(string: "Existing words.", attributes: [.foregroundColor: color])
        let tail = NSAttributedString(string: " New words.", attributes: [.foregroundColor: color])
        let full = NSMutableAttributedString(attributedString: prefix); full.append(tail)
        let initial = LiveTranscriptTextPaneMac(finalizedAttributed: prefix, finalizedMutation: nil, finalizedRevision: 1,
            interim: .init(revision: 1, text: "New words", speaker: 1, startsNewTurn: false,
                hasFinalizedContent: true, speakerNames: [:], selfIDs: [], bodyFontSize: 17, headerFontSize: 13, lineSpacing: 3),
            isAutoScrollEnabled: false, reduceMotion: true, onScrolledAwayFromBottom: {})
        let scroll = NSTextView.scrollableDocumentContentTextView()
        let view = try XCTUnwrap(scroll.documentView as? NSTextView)
        LiveTranscriptTextPaneMac.configure(scrollView: scroll, textView: view)
        let coordinator = LiveTranscriptTextPaneMac.Coordinator(parent: initial)
        coordinator.attach(scrollView: scroll, textView: view); coordinator.apply(parent: initial)
        defer { coordinator.detach() }
        let storage = try XCTUnwrap(view.textStorage)
        coordinator.apply(parent: .init(finalizedAttributed: full,
            finalizedMutation: .init(revision: 2, range: NSRange(location: prefix.length, length: 0), replacement: tail),
            finalizedRevision: 2, interim: nil, isAutoScrollEnabled: false, reduceMotion: true, onScrolledAwayFromBottom: {}))
        XCTAssertEqual(storage.attribute(.foregroundColor, at: prefix.length, effectiveRange: nil) as? NSColor, color)
        let unwantedEdit = expectation(description: "Reduce Motion must not schedule fade edits")
        unwantedEdit.isInverted = true
        let token = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { _ in unwantedEdit.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }
        await fulfillment(of: [unwantedEdit], timeout: 0.6)
        XCTAssertEqual(storage.string, full.string)
    }

    @MainActor
    func testSelectionInsideLocalizedReplacementRestoresAfterBatchProcessing() throws {
        let previous = NSAttributedString(string: "Before.\nOld middle words.\nFinal paragraph.")
        let next = NSAttributedString(string: "Before.\nA corrected middle sentence.\nFinal paragraph.")
        func pane(_ document: NSAttributedString, revision: UInt64, mutation: SelectableTextMutation? = nil) -> LiveTranscriptTextPaneMac {
            .init(finalizedAttributed: document, finalizedMutation: mutation, finalizedRevision: revision,
                interim: .init(revision: revision, text: "Live tail", speaker: 1, startsNewTurn: false,
                    hasFinalizedContent: true, speakerNames: [:], selfIDs: [], bodyFontSize: 17, headerFontSize: 13, lineSpacing: 3),
                isAutoScrollEnabled: false, reduceMotion: true, onScrolledAwayFromBottom: {})
        }
        let scroll = NSTextView.scrollableDocumentContentTextView()
        let view = try XCTUnwrap(scroll.documentView as? NSTextView)
        LiveTranscriptTextPaneMac.configure(scrollView: scroll, textView: view)
        let coordinator = LiveTranscriptTextPaneMac.Coordinator(parent: pane(previous, revision: 1))
        coordinator.attach(scrollView: scroll, textView: view); coordinator.apply(parent: pane(previous, revision: 1))
        defer { coordinator.detach() }
        let storage = try XCTUnwrap(view.textStorage)
        let selection = (previous.string as NSString).range(of: "middle words")
        view.setSelectedRange(selection)
        let mutation = try XCTUnwrap(LiveTranscriptDocumentMutation.localizedReplacement(previous: previous, next: next, revision: 2))
        var processedEdit = false
        var selectionChangedBeforeProcessing = false
        let did = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { _ in MainActor.assumeIsolated { processedEdit = true } }
        let selected = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: view, queue: nil) { _ in MainActor.assumeIsolated { selectionChangedBeforeProcessing = selectionChangedBeforeProcessing || !processedEdit } }
        defer { [did, selected].forEach(NotificationCenter.default.removeObserver) }
        coordinator.apply(parent: pane(next, revision: 2, mutation: mutation))
        XCTAssertEqual(storage.string, next.string + " Live tail▊")
        XCTAssertEqual(view.selectedRange(), NSRange(location: mutation.range.location, length: 0))
        XCTAssertFalse(selectionChangedBeforeProcessing)
    }

    @MainActor
    func testParagraphBoundaryKeepsSameSpeakerInterimAndCommittedWordsInPlace() throws {
        let prefixText = String(repeating: "ordinary words ", count: 66).trimmingCharacters(in: .whitespaces)
        let tailText = "these words cross the paragraph boundary without disappearing"
        let prefix = SelectableAttributed.transcriptDocument(turns: [.init(speaker: 1, timestamp: 0, text: prefixText)], speakerNames: nil).attributed
        let full = SelectableAttributed.transcriptDocument(turns: [.init(speaker: 1, timestamp: 0, text: prefixText), .init(speaker: 1, timestamp: 1, text: tailText)], speakerNames: nil).attributed
        let pane = LiveTranscriptTextPaneMac(finalizedAttributed: prefix, finalizedMutation: nil, finalizedRevision: 1,
            interim: .init(revision: 1, text: tailText, speaker: 1, startsNewTurn: false, hasFinalizedContent: true,
                speakerNames: [:], selfIDs: [], bodyFontSize: 17, headerFontSize: 13, lineSpacing: 3),
            isAutoScrollEnabled: false, reduceMotion: true, onScrolledAwayFromBottom: {})
        let scroll = NSTextView.scrollableDocumentContentTextView()
        let view = try XCTUnwrap(scroll.documentView as? NSTextView)
        LiveTranscriptTextPaneMac.configure(scrollView: scroll, textView: view)
        let coordinator = LiveTranscriptTextPaneMac.Coordinator(parent: pane)
        coordinator.attach(scrollView: scroll, textView: view); coordinator.apply(parent: pane)
        defer { coordinator.detach() }
        let storage = try XCTUnwrap(view.textStorage)
        XCTAssertEqual(storage.string, full.string + "▊", "The live phrase must use exactly the final paragraph breaks")
        XCTAssertTrue(full.string.hasPrefix(prefix.string))
        let suffix = full.attributedSubstring(from: NSRange(location: prefix.length, length: full.length - prefix.length))
        coordinator.apply(parent: .init(finalizedAttributed: full,
            finalizedMutation: .init(revision: 2, range: NSRange(location: prefix.length, length: 0), replacement: suffix),
            finalizedRevision: 2, interim: nil, isAutoScrollEnabled: false, reduceMotion: true, onScrolledAwayFromBottom: {}))
        XCTAssertEqual(storage.string, full.string)
    }

    @MainActor
    func testSingleSpeakerFortyMinuteTranscriptKeepsEditedParagraphsBounded() throws {
        // 6,000 words, about 40 minutes at 150 words/minute, one speaker and no source newlines.
        let source = String(repeating: "These are ordinary spoken meeting words ", count: 1_000).trimmingCharacters(in: .whitespaces)
        let document = SelectableAttributed.transcriptDocument(turns: [.init(speaker: 1, timestamp: 0, text: source)], speakerNames: nil)
        XCTAssertEqual(document.turns.count, 1, "Paragraph boundaries must not invent speaker changes")
        let body = document.attributed.string.components(separatedBy: "\n").dropFirst()
        XCTAssertEqual(body.joined(separator: " "), source, "Display breaks must preserve all words")
        XCTAssertLessThan(body.map { $0.utf16.count }.max() ?? Int.max, 1_020)
        func pane(_ revision: UInt64) -> LiveTranscriptTextPaneMac {
            .init(finalizedAttributed: document.attributed, finalizedMutation: nil, finalizedRevision: 1,
                interim: .init(revision: revision, text: "The current phrase \(revision)", speaker: 1,
                    startsNewTurn: false, hasFinalizedContent: true, speakerNames: [:], selfIDs: [], bodyFontSize: 17, headerFontSize: 13, lineSpacing: 3),
                isAutoScrollEnabled: false, reduceMotion: false, onScrolledAwayFromBottom: {})
        }
        let scroll = NSTextView.scrollableDocumentContentTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        let view = try XCTUnwrap(scroll.documentView as? NSTextView)
        LiveTranscriptTextPaneMac.configure(scrollView: scroll, textView: view)
        let coordinator = LiveTranscriptTextPaneMac.Coordinator(parent: pane(0))
        coordinator.attach(scrollView: scroll, textView: view); coordinator.apply(parent: pane(0))
        defer { coordinator.detach() }
        let storage = try XCTUnwrap(view.textStorage)
        var largestParagraphEdit = 0
        let token = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { _ in
            MainActor.assumeIsolated {
                largestParagraphEdit = max(largestParagraphEdit, (storage.string as NSString).paragraphRange(for: storage.editedRange).length)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let started = CFAbsoluteTimeGetCurrent()
        for revision in 1...240 {
            coordinator.apply(parent: pane(UInt64(revision)))
            if let manager = view.textLayoutManager { manager.ensureLayout(for: manager.documentRange) }
        }
        print("TRANSCRIPT_PERF: 40-minute single-speaker fixture, 240 interim layouts: \(CFAbsoluteTimeGetCurrent() - started)s; largest edited paragraph \(largestParagraphEdit)")
        XCTAssertLessThan(largestParagraphEdit, 1_100)
    }

    @MainActor
    func testTranscriptViewPrebuildsBeforeClearingInterimAndSkipsDuplicateSourceRebuild() async throws {
        let state = AppState()
        state.liveSegments = [.init(id: UUID(), text: "First words.", speaker: 1, timestamp: 0, isFinal: true)]
        state.transcriptRuntime.update(interimText: "Next phrase", currentSpeaker: 1, interimSpeaker: 1)
        var events: [(String, Int, String)] = []
        let host = NSHostingView(rootView: TranscriptView(cacheEventForTesting: { events.append(($0, $1, $2)) })
            .environmentObject(state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        try await TestSupport.waitUntil { events.contains { $0.0 == "rebuilt" } && events.contains { $0.0 == "runtime" && $0.2 == "Next phrase" } }
        events.removeAll()
        state.liveSegments.append(.init(id: UUID(), text: "Next phrase.", speaker: 1, timestamp: 2, isFinal: true))
        state.transcriptRuntime.clearInterim(through: state.transcriptRuntime.snapshot.revision)
        try await TestSupport.waitUntil { events.contains { $0.0 == "sourceChanged" } }
        let clears = events.filter { $0.0 == "runtime" && $0.2.isEmpty }
        XCTAssertFalse(clears.isEmpty)
        XCTAssertTrue(clears.allSatisfy { $0.1 == 2 }, "Final cache must exist before any interim clear is presented")
        XCTAssertEqual(events.filter { $0.0 == "rebuilt" }.count, 1, "onChange must not rebuild what the clear publisher already prepared")
    }

    @MainActor
    func testLongTranscriptInterimEditsStayBoundedToTheTail() throws {
        let text = String(repeating: "A completed turn with stable selected words.\n", count: 5_000)
        let document = NSAttributedString(string: text, attributes: [.foregroundColor: NSColor(ColorPalette.Text.secondary)])
        func pane(_ revision: UInt64) -> LiveTranscriptTextPaneMac {
            .init(finalizedAttributed: document, finalizedMutation: nil, finalizedRevision: 1,
                interim: .init(revision: revision, text: "The current phrase \(revision)", speaker: 1,
                    startsNewTurn: false, hasFinalizedContent: true, speakerNames: [:], selfIDs: [],
                    bodyFontSize: 17, headerFontSize: 13, lineSpacing: 3),
                isAutoScrollEnabled: false, reduceMotion: true, onScrolledAwayFromBottom: {})
        }
        let scroll = NSTextView.scrollableDocumentContentTextView()
        let view = try XCTUnwrap(scroll.documentView as? NSTextView)
        LiveTranscriptTextPaneMac.configure(scrollView: scroll, textView: view)
        let coordinator = LiveTranscriptTextPaneMac.Coordinator(parent: pane(0))
        coordinator.attach(scrollView: scroll, textView: view); coordinator.apply(parent: pane(0))
        defer { coordinator.detach() }
        let storage = try XCTUnwrap(view.textStorage)
        var largestEdit = 0
        let token = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { _ in
            MainActor.assumeIsolated { largestEdit = max(largestEdit, storage.editedRange.length) }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        view.setSelectedRange(NSRange(location: 20, length: 10))
        let started = CFAbsoluteTimeGetCurrent()
        for revision in 1...100 { coordinator.apply(parent: pane(UInt64(revision))) }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        print("TRANSCRIPT_PERF: 5000 lines, 100 interim edits: \(elapsed)s; largest edited range \(largestEdit)")
        XCTAssertLessThan(largestEdit, 100)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 20, length: 10))
        XCTAssertTrue(storage.string.hasPrefix(text))
    }

    @MainActor
    func testMacLiveTranscriptUsesOneTextKit2DocumentAndPreservesStableSelection() throws {
        let initialString = "stable selected text\nvolatile tail"
        let initialAttributed = NSAttributedString(
            string: initialString,
            attributes: [
                .font: NSFont.systemFont(ofSize: 17),
                .foregroundColor: NSColor.systemGreen,
            ]
        )
        let initialPane = LiveTranscriptTextPaneMac(
            finalizedAttributed: initialAttributed,
            finalizedMutation: nil,
            finalizedRevision: 1,
            interim: nil,
            isAutoScrollEnabled: false,
            reduceMotion: true,
            onScrolledAwayFromBottom: {}
        )
        let scrollView = NSTextView.scrollableDocumentContentTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        LiveTranscriptTextPaneMac.configure(scrollView: scrollView, textView: textView)
        let coordinator = LiveTranscriptTextPaneMac.Coordinator(parent: initialPane)
        coordinator.attach(scrollView: scrollView, textView: textView)
        coordinator.apply(parent: initialPane)
        defer { coordinator.detach() }

        XCTAssertNotNil(textView.textLayoutManager)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.isEditable)
        XCTAssertFalse(textView.isRichText)
        XCTAssertFalse(textView.usesInspectorBar)
        XCTAssertFalse(textView.usesFontPanel)
        XCTAssertFalse(textView.usesRuler)
        XCTAssertFalse(textView.usesRolloverButtonForSelection)
        XCTAssertFalse(textView.allowsImageEditing)
        XCTAssertFalse(textView.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(textView.isGrammarCheckingEnabled)
        XCTAssertFalse(textView.smartInsertDeleteEnabled)
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(textView.isAutomaticDataDetectionEnabled)
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(textView.isAutomaticSpellingCorrectionEnabled)
        XCTAssertEqual(textView.enabledTextCheckingTypes, 0)
        XCTAssertFalse(textView.isAutomaticTextCompletionEnabled)
        XCTAssertFalse(textView.allowsCharacterPickerTouchBarItem)
        XCTAssertEqual(textView.inlinePredictionType, .no)
        XCTAssertFalse(textView.usesFindPanel)
        XCTAssertFalse(textView.usesFindBar)
        XCTAssertFalse(textView.isIncrementalSearchingEnabled)
        if #available(macOS 15.0, *) {
            XCTAssertEqual(textView.mathExpressionCompletionType, .no)
            XCTAssertEqual(textView.writingToolsBehavior, .none)
        }
        XCTAssertEqual(
            textView.selectedTextAttributes[.backgroundColor] as? NSColor,
            NSColor(ColorPalette.Accent.green)
        )
        XCTAssertEqual(
            textView.selectedTextAttributes[.foregroundColor] as? NSColor,
            NSColor(ColorPalette.Background.primary)
        )
        XCTAssertEqual(
            (textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize,
            17
        )
        let stableSelection = NSRange(location: 7, length: initialAttributed.length - 7)
        textView.setSelectedRange(stableSelection)

        let insertionRange = NSRange(location: initialAttributed.length, length: 0)
        let replacement = NSAttributedString(string: " plus appended final text")
        let updated = NSMutableAttributedString(attributedString: initialAttributed)
        updated.replaceCharacters(in: insertionRange, with: replacement)
        let updatedPane = LiveTranscriptTextPaneMac(
            finalizedAttributed: updated,
            finalizedMutation: SelectableTextMutation(
                revision: 2,
                range: insertionRange,
                replacement: replacement
            ),
            finalizedRevision: 2,
            interim: nil,
            isAutoScrollEnabled: false,
            reduceMotion: true,
            onScrolledAwayFromBottom: {}
        )
        coordinator.apply(parent: updatedPane)

        XCTAssertEqual(textView.string, updated.string)
        XCTAssertEqual(textView.selectedRange(), stableSelection)
    }
    #endif
}

private struct ReadingRendererFixture: View {
    @Environment(\.readingMetrics) private var metrics
    @State private var text = "SwiftUI prose"

    var body: some View {
        VStack {
            TextEditor(text: $text)
                .font(.system(size: metrics.insightBodySize))
                .frame(height: 120)
            MEDDPICCBulletText("Sales prose")
            SelectableTextView(SelectableAttributed.transcript(
                turns: [.init(speaker: 1, timestamp: 0, text: "Transcript prose")],
                speakerNames: nil,
                bodyFontSize: metrics.transcriptBodySize,
                headerFontSize: metrics.transcriptHeaderSize,
                lineSpacing: metrics.transcriptLineSpacing))
        }
    }
}

#if os(iOS)
private final class ReadingFixturePreferences: ObservableObject {
    @Published var systemSize: DynamicTypeSize = .large
}

private struct SavedReadingFixture: View {
    @ObservedObject var preferences: ReadingFixturePreferences
    let meeting: Meeting

    var body: some View {
        TranscriptTrimView(meeting: meeting)
            .minitiInterfaceScale(.standard)
            .environment(\.dynamicTypeSize, preferences.systemSize)
    }
}

private struct LiveReadingFixture: View {
    @ObservedObject var preferences: ReadingFixturePreferences
    let cacheEvent: (String, Int, String) -> Void

    var body: some View {
        TranscriptView(cacheEventForTesting: cacheEvent)
            .minitiInterfaceScale(.standard)
            .environment(\.dynamicTypeSize, preferences.systemSize)
    }
}
#endif

#if os(macOS)
private typealias ReadingNativeView = NSView
private typealias ReadingNativeTextView = NSTextView
private typealias ReadingNativeFont = NSFont
private extension NSHostingView {
    var viewForReadingTest: NSView { self }
}
#else
private typealias ReadingNativeView = UIView
private typealias ReadingNativeTextView = UITextView
private typealias ReadingNativeFont = UIFont
private extension UIHostingController {
    var viewForReadingTest: UIView { view }
}
#endif
