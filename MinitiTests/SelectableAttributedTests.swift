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
    #endif
}
