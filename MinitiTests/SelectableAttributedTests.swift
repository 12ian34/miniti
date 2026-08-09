import XCTest
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

    func testBodyBuilderHandlesEmptyString() {
        let attr = SelectableAttributed.body("")
        XCTAssertEqual(attr.length, 0)
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
