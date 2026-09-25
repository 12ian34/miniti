import XCTest
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

/// Client side of the managed Jev classifier (docs/jev-system-one-plan.md, slice 1).
final class JevClassifierTests: XCTestCase {

    private func segment(_ speaker: Int, _ text: String, final: Bool = true) -> AppState.LiveSegment {
        AppState.LiveSegment(id: UUID(), text: text, speaker: speaker, timestamp: 0, isFinal: final, source: speaker >= 1000 ? .microphone : .system)
    }

    // MARK: - Sales nudge decision

    func testSalesNudgeNeedsTwoConsecutiveTicksOverThreshold() {
        XCTAssertFalse(AppState.shouldFireJevSalesNudge(scores: []))
        XCTAssertFalse(AppState.shouldFireJevSalesNudge(scores: [0.95]))
        XCTAssertFalse(AppState.shouldFireJevSalesNudge(scores: [0.95, 0.4]))
        XCTAssertFalse(AppState.shouldFireJevSalesNudge(scores: [0.4, 0.95]))
        XCTAssertTrue(AppState.shouldFireJevSalesNudge(scores: [0.2, 0.72, 0.9]))
        XCTAssertTrue(AppState.shouldFireJevSalesNudge(scores: [0.7, 0.7]))
        XCTAssertEqual(AppState.jevSalesThreshold, 0.7)
        XCTAssertEqual(AppState.jevSalesConsecutiveTicks, 2)
    }

    func testPhraseHeuristicYieldsOnlyToAHealthyClassifier() {
        XCTAssertTrue(AppState.phraseHeuristicSuppressed(classifierActive: true, classifierHealthy: true))
        XCTAssertFalse(AppState.phraseHeuristicSuppressed(classifierActive: true, classifierHealthy: false))
        XCTAssertFalse(AppState.phraseHeuristicSuppressed(classifierActive: false, classifierHealthy: true))
    }

    func testSalesWindowKeepsTheNewestFinalsInOrder() {
        var segments: [AppState.LiveSegment] = []
        for i in 0..<50 { segments.append(segment(i % 2 == 0 ? 1000 : 0, "turn \(i)")) }
        segments.append(segment(0, "interim", final: false))
        segments.append(segment(0, "   "))
        let window = AppState.jevSalesWindow(from: segments, limit: 40)
        let lines = window.split(separator: "\n")
        XCTAssertEqual(lines.count, 40)
        XCTAssertEqual(lines.first, "Mic0: turn 10")
        XCTAssertEqual(lines.last, "Remote0: turn 49")
        XCTAssertFalse(window.contains("interim"))
    }

    // MARK: - Speaker naming inputs

    func testUnresolvedSpeakerIDsSkipSelfNamedAndOverridden() {
        let segments = [segment(1000, "hello"), segment(0, "hi"), segment(1, "hey"), segment(2, "   "), segment(3, "yo")]
        let ids = AppState.unresolvedSpeakerIDs(in: segments, named: ["0": "Priya"], overrides: ["1"], selfIDs: [1000])
        XCTAssertEqual(ids, [3])
        XCTAssertEqual(AppState.unresolvedSpeakerIDs(in: segments, named: [:], overrides: [], selfIDs: []), [0, 1, 3, 1000])
    }

    func testNamingPrefilterKeepsOpeningNameMentionsIntroductionsAndNeighbours() {
        var segments: [AppState.LiveSegment] = []
        for i in 0..<30 { segments.append(segment(i % 2, "filler line \(i)")) }
        segments[15] = segment(1, "Thanks Priya, that's helpful.")
        segments[24] = segment(0, "Hi all, this is Tom from Northwind.")
        let kept = AppState.jevSpeakerNamingSegments(segments, candidateNames: ["Priya Natarajan", "Tom Becker"])
        let keptTexts = kept.map(\.text)
        XCTAssertEqual(kept.count, 13)  // first 6 and their neighbour 6, plus 14/15/16 and 23/24/25
        XCTAssertTrue(keptTexts.contains("filler line 0"))
        XCTAssertTrue(keptTexts.contains("filler line 5"))
        XCTAssertTrue(keptTexts.contains("Thanks Priya, that's helpful."))
        XCTAssertTrue(keptTexts.contains("filler line 14"))
        XCTAssertTrue(keptTexts.contains("filler line 16"))
        XCTAssertTrue(keptTexts.contains("Hi all, this is Tom from Northwind."))
        XCTAssertFalse(keptTexts.contains("filler line 10"))
        // Short first names never match inside other words
        let noMatch = AppState.jevSpeakerNamingSegments([segment(0, "the priyanka report"), segment(0, "x"), segment(0, "y"), segment(0, "z"), segment(0, "w"), segment(0, "v"), segment(0, "priyanka again")], candidateNames: ["Priya"])
        XCTAssertEqual(noMatch.count, 6 + 1)  // the opening six plus the neighbour of the sixth; no name match past that
    }

    // MARK: - Response decoding

    func testClassifyResultsDecodeAndDropUnknown() throws {
        let sales = try JSONDecoder().decode(MinitiAPIService.ClassifySalesResult.self, from: Data(#"{"kind":"sales_nudge","isSales":0.83,"stage":2.5,"meta":{}}"#.utf8))
        XCTAssertEqual(sales.isSales, 0.83)
        XCTAssertEqual(sales.stage, 2.5)
        let speakers = try JSONDecoder().decode(MinitiAPIService.ClassifySpeakerNamesResult.self, from: Data(#"{"kind":"speaker_names","speakers":{"0":{"choice":"Priya Natarajan","confidence":0.9},"1":{"choice":"unknown","confidence":0.6}}}"#.utf8))
        XCTAssertEqual(speakers.namedSpeakers, ["0": "Priya Natarajan"])
    }
}
