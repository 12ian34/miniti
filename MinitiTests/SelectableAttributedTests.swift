import XCTest
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

    func testMergeTurnsKeepsTurnsWhenPreviousEndsSentence() {
        let turns = [
            Turn(speaker: 0, timestamp: 0, text: "Hello there."),
            Turn(speaker: 0, timestamp: 1, text: "How are you"),
        ]
        let merged = SelectableAttributed.mergeTurns(turns, speakerNames: nil, selfIDs: nil)
        XCTAssertEqual(merged.count, 2)
    }

    func testMergeTurnsTreatsClosingQuoteBeforeTerminatorAsSentenceEnd() {
        let turns = [
            Turn(speaker: 0, timestamp: 0, text: "He said \"hi.\""),
            Turn(speaker: 0, timestamp: 1, text: "Then he left"),
        ]
        let merged = SelectableAttributed.mergeTurns(turns, speakerNames: nil, selfIDs: nil)
        XCTAssertEqual(merged.count, 2)
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
}
