import XCTest
import SwiftUI
#if IOS_TEST_TARGET
@testable import MinitiMobile
#else
@testable import miniti
#endif

#if canImport(UIKit)
import UIKit
private func colorComponents(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b, a)
}
#else
import AppKit
private func colorComponents(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    NSColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b, a)
}
#endif

final class ColorPaletteTests: XCTestCase {

    // MARK: - Color(hex:) init

    func testHex6Digit() {
        let c = colorComponents(Color(hex: "FF0000"))
        XCTAssertEqual(c.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(c.g, 0.0, accuracy: 0.01)
        XCTAssertEqual(c.b, 0.0, accuracy: 0.01)
    }

    func testHex6DigitGreen() {
        let c = colorComponents(Color(hex: "00FF00"))
        XCTAssertEqual(c.r, 0.0, accuracy: 0.01)
        XCTAssertEqual(c.g, 1.0, accuracy: 0.01)
    }

    func testHex3Digit() {
        let c = colorComponents(Color(hex: "F00"))
        XCTAssertEqual(c.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(c.g, 0.0, accuracy: 0.01)
        XCTAssertEqual(c.b, 0.0, accuracy: 0.01)
    }

    func testHex8DigitWithAlpha() {
        let c = colorComponents(Color(hex: "80FF0000"))
        XCTAssertEqual(c.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(c.a, 128.0 / 255.0, accuracy: 0.02)
    }

    func testHexStripsHashPrefix() {
        let c = colorComponents(Color(hex: "#22C55E"))
        XCTAssertEqual(c.r, 0x22 / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.g, 0xC5 / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.b, 0x5E / 255.0, accuracy: 0.01)
    }

    // MARK: - Speaker colors

    func testSpeakerColorMic() {
        let color = ColorPalette.Speaker.color(for: DeepgramService.micSpeakerID, micSpeakerID: DeepgramService.micSpeakerID)
        XCTAssertEqual(color, ColorPalette.Speaker.mic)
    }

    func testSpeakerColorRemote() {
        let color = ColorPalette.Speaker.color(for: 0, micSpeakerID: DeepgramService.micSpeakerID)
        XCTAssertEqual(color, ColorPalette.Speaker.remote[0])
    }

    func testSpeakerColorCycles() {
        let count = ColorPalette.Speaker.remote.count
        let color = ColorPalette.Speaker.color(for: count, micSpeakerID: DeepgramService.micSpeakerID)
        XCTAssertEqual(color, ColorPalette.Speaker.remote[0])
    }

    // MARK: - MEDDPICC colors

    @MainActor
    func testProductionSalesHeadersUseTheSameBuyerAndCompetitionColors() throws {
        let state = AppState()
        state.liveEconomicBuyer = "Buyer fixture"
        state.liveCompetition = "Competition fixture"
        let meeting = Meeting(meddpiccEconomicBuyer: "Buyer fixture", meddpiccCompetition: "Competition fixture")
        var renderers: [(String, AnyView)] = [
            ("shared live", AnyView(MEDDPICCContent().environmentObject(state))),
        ]
        #if os(macOS)
        renderers += [
            ("Mac live", AnyView(LiveMEDDPICCSections().environmentObject(state))),
            ("Mac saved", AnyView(SavedMEDDPICCBlocks(meeting: meeting))),
        ]
        #else
        renderers += [
            ("iOS live", AnyView(LiveMEDDPICCContent_iOSPlain().environmentObject(state))),
            ("iOS saved", AnyView(SavedMEDDPICCContent(meeting: meeting))),
        ]
        #endif
        for (name, view) in renderers {
            let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 16) { view }
                .minitiInterfaceScale(.compact).frame(width: 420).padding(16)
                .background(ColorPalette.Background.primary))
            renderer.scale = 2
            let raster = try XCTUnwrap(renderer.cgImage)
            XCTAssertGreaterThan(try pixelCount(ColorPalette.MEDDPICC.economicBuyer, in: raster), 10, name)
            XCTAssertGreaterThan(try pixelCount(ColorPalette.MEDDPICC.competition, in: raster), 10, name)
            XCTAssertEqual(try pixelCount(Color(hex: "8B5CF6"), in: raster), 0, name)
            XCTAssertEqual(try pixelCount(Color(hex: "6366F1"), in: raster), 0, name)
        }
    }

    func testStandardSectionsKeepOrderedContentAndDistinctAccents() {
        let sections = StandardInsightSection.entries(
            summary: "  Original summary\n", discussion: ["", "same", "same"],
            actions: ["Action\r\ncontinuation"], decisions: ["null"], topics: ["Mixed_Case", "Mixed_Case"])
        XCTAssertEqual(sections, [
            .summary("  Original summary\n"), .discussion(["", "same", "same"]),
            .actions(["Action\r\ncontinuation"]), .decisions(["null"]), .topics(["Mixed_Case", "Mixed_Case"])
        ])
        XCTAssertEqual(sections.map(\.title), ["summary", "discussion", "actions", "decisions", "topics"])
        XCTAssertEqual(Set(sections.map(\.id)).count, 5)
        XCTAssertEqual(sections.map(\.color), [ColorPalette.Insights.summary, ColorPalette.Insights.discussion,
                                               ColorPalette.Insights.actions, ColorPalette.Insights.decisions,
                                               ColorPalette.Insights.topics])
    }

    func testStandardSectionsPreserveEachScreensSummaryPresencePolicy() {
        XCTAssertTrue(StandardInsightSection.entries(summary: nil, includesEmptySummary: true).isEmpty)
        XCTAssertTrue(StandardInsightSection.entries(summary: "").isEmpty)
        XCTAssertEqual(StandardInsightSection.entries(summary: "", includesEmptySummary: true), [.summary("")])
        for value in [" ", "\n", "null", "N/A", "none"] {
            XCTAssertEqual(StandardInsightSection.entries(summary: value), [.summary(value)],
                           "Standard summaries must not adopt the Sales sentinel filter")
        }
        XCTAssertEqual(StandardInsightSection.entries(summary: nil, actions: [""], topics: ["topic"]),
                       [.actions([""]), .topics(["topic"])],
                       "Omit only empty sections, preserving the supplied content and field coverage")
    }

    func testNamedSalesFieldsPreserveOrderAndDistinguishRepeatedLetters() {
        XCTAssertEqual(SalesInsightField.allCases.map(\.title), [
            "metrics", "economic buyer", "decision criteria", "decision process",
            "paper process", "identified pain", "champion", "competition",
        ])
        XCTAssertEqual(Set(SalesInsightField.allCases.map(\.id)).count, 8)
        XCTAssertEqual(SalesInsightField.decisionCriteria.color, ColorPalette.MEDDPICC.decisionCriteria)
        XCTAssertEqual(SalesInsightField.decisionProcess.color, ColorPalette.MEDDPICC.decisionProcess)
        XCTAssertEqual(SalesInsightField.paperProcess.color, ColorPalette.MEDDPICC.paperProcess)
        XCTAssertEqual(SalesInsightField.champion.color, ColorPalette.MEDDPICC.champion)
        XCTAssertEqual(SalesInsightField.competition.color, ColorPalette.MEDDPICC.competition)
    }

    @MainActor
    func testSalesProjectionKeepsLiveAndSavedValuesInTheirOwnNamedFields() {
        let state = AppState()
        state.liveMetrics = "live metrics"
        state.liveEconomicBuyer = "live economic buyer"
        state.liveDecisionCriteria = "live decision criteria"
        state.liveDecisionProcess = "live decision process"
        state.livePaperProcess = "live paper process"
        state.liveIdentifiedPain = "live identified pain"
        state.liveChampion = "live champion"
        state.liveCompetition = "live competition"
        let meeting = Meeting(
            meddpiccMetrics: "saved metrics",
            meddpiccEconomicBuyer: "saved economic buyer",
            meddpiccDecisionCriteria: "saved decision criteria",
            meddpiccDecisionProcess: "saved decision process",
            meddpiccPaperProcess: "saved paper process",
            meddpiccIdentifiedPain: "saved identified pain",
            meddpiccChampion: "saved champion",
            meddpiccCompetition: "saved competition")
        let live = SalesInsightField.entries(from: state)
        let saved = SalesInsightField.entries(from: meeting)
        XCTAssertEqual(live.map(\.field), SalesInsightField.allCases)
        XCTAssertEqual(saved.map(\.field), SalesInsightField.allCases)
        for entry in live { XCTAssertEqual(entry.value, "live " + entry.field.title) }
        for entry in saved { XCTAssertEqual(entry.value, "saved " + entry.field.title) }
        // Filtering is case/whitespace insensitive; meaningful values remain byte-identical.
        for sentinel in [String?.none, "", "  \n", " NULL ", "N/A", "none"] {
            state.liveEconomicBuyer = sentinel
            meeting.meddpiccEconomicBuyer = sentinel
            XCTAssertFalse(SalesInsightField.entries(from: state).contains { $0.field == .economicBuyer })
            XCTAssertFalse(SalesInsightField.entries(from: meeting).contains { $0.field == .economicBuyer })
            XCTAssertEqual(SalesInsightField.entries(from: state).count, 7)
            XCTAssertEqual(SalesInsightField.entries(from: meeting).count, 7)
        }
        state.liveEconomicBuyer = "  Budget owner; CFO\nsecond line  "
        meeting.meddpiccEconomicBuyer = state.liveEconomicBuyer
        XCTAssertEqual(SalesInsightField.entries(from: state)[1].value, state.liveEconomicBuyer)
        XCTAssertEqual(SalesInsightField.entries(from: meeting)[1].value, state.liveEconomicBuyer)
    }

    // MARK: - Design-system contracts

    func testCompactControlMetricsStayAligned() {
        XCTAssertEqual(MinitiDesignSystem.Control.compactHeight, 30)
        XCTAssertEqual(MinitiDesignSystem.Control.horizontalPadding, 10)
        XCTAssertEqual(MinitiDesignSystem.Control.modeHorizontalPadding, 10)
        XCTAssertEqual(MinitiDesignSystem.Control.modeSpacing, 4)
        XCTAssertEqual(MinitiDesignSystem.Radius.control, 6)
    }

    func testInsightContentAccentsUseSemanticTokens() {
        XCTAssertEqual(MinitiDesignSystem.ContentAccent.summary, ColorPalette.Accent.blueGitHub)
        XCTAssertEqual(MinitiDesignSystem.ContentAccent.questions, ColorPalette.Accent.purpleLight)
        XCTAssertEqual(MinitiDesignSystem.ContentAccent.sales, ColorPalette.Accent.pink)
        XCTAssertEqual(MinitiDesignSystem.ContentAccent.playbook, ColorPalette.Accent.purpleSoft)
    }

    func testControlRolesUseActionSemanticsInsteadOfContentCategories() {
        XCTAssertEqual(MinitiControlRole.primary.accent, ColorPalette.Accent.blueGitHub)
        XCTAssertEqual(MinitiControlRole.positive.accent, ColorPalette.Accent.greenGitHub)
        XCTAssertEqual(MinitiControlRole.recording.accent, ColorPalette.Accent.redGitHub)
        XCTAssertEqual(MinitiControlRole.destructive.accent, ColorPalette.Accent.redGitHub)
        XCTAssertEqual(MinitiControlRole.warning.accent, ColorPalette.Accent.amber)
    }

    func testProductTabTitlesAreLowercase() {
        XCTAssertEqual(MinitiDesignSystem.NavigationCopy.tabTitle("Summary"), "summary")
        XCTAssertEqual(MinitiDesignSystem.NavigationCopy.tabTitle("Questions"), "questions")
        XCTAssertEqual(MinitiDesignSystem.NavigationCopy.tabTitle("Coaching"), "coaching")
        XCTAssertEqual(CoachingOverviewTab.allCases.map(\.rawValue), ["focus", "stats", "history"])
    }

    func testCoachingReadingTypeAdaptsByPlatform() {
        #if IOS_TEST_TARGET
        XCTAssertEqual(MinitiDesignSystem.CoachingTypography.size(12), 12)
        #else
        XCTAssertEqual(MinitiDesignSystem.CoachingTypography.size(12), 14)
        #endif
    }

    func testCoachingLayoutUsesSharedColumnBounds() {
        XCTAssertEqual(MinitiDesignSystem.CoachingLayout.trendColumnMaxWidth, 720)
        XCTAssertEqual(MinitiDesignSystem.CoachingLayout.compactColumnMaxWidth, 480)
        XCTAssertEqual(MinitiDesignSystem.CoachingLayout.statsColumnMaxWidth, 720)
        #if IOS_TEST_TARGET
        XCTAssertEqual(MinitiDesignSystem.CoachingLayout.statsChartHeight, 108)
        #else
        XCTAssertEqual(MinitiDesignSystem.CoachingLayout.statsChartHeight, 116)
        #endif
    }

    func testCoachingMetricsUseStableNonCTAAccents() {
        let metricColors = CoachingMetric.allCases.map(MinitiDesignSystem.ContentAccent.coachingMetric)
        let controlColors = [
            MinitiControlRole.primary.accent,
            MinitiControlRole.secondary.accent,
            MinitiControlRole.positive.accent,
            MinitiControlRole.recording.accent,
            MinitiControlRole.destructive.accent,
            MinitiControlRole.warning.accent,
        ]

        XCTAssertEqual(MinitiDesignSystem.ContentAccent.coachingMetric(.fillers), ColorPalette.Coaching.fillers)
        XCTAssertEqual(MinitiDesignSystem.ContentAccent.coachingMetric(.pace), ColorPalette.Coaching.pace)
        XCTAssertEqual(MinitiDesignSystem.ContentAccent.coachingMetric(.clarity), ColorPalette.Coaching.clarity)
        XCTAssertEqual(MinitiDesignSystem.ContentAccent.coachingMetric(.questions), ColorPalette.Coaching.questions)

        for (index, metricColor) in metricColors.enumerated() {
            for otherColor in metricColors.dropFirst(index + 1) {
                XCTAssertNotEqual(metricColor, otherColor)
            }
            for controlColor in controlColors {
                XCTAssertNotEqual(metricColor, controlColor)
            }
        }
    }
    // These are resolved sRGB role pairs used by the migrated surfaces. They
    // measure contrast, rather than pinning a particular palette hex value.
    func testMeaningfulTextAndRecordingLabelsMeetOrdinaryTextContrast() {
        let pairs: [(String, Color, Color)] = [
            ("question context", ColorPalette.Text.meta, ColorPalette.Background.primary),
            ("coaching units", ColorPalette.Text.meta, ColorPalette.Background.panel),
            ("coaching headers", ColorPalette.Text.dim, ColorPalette.Background.tertiary),
            ("copy", ColorPalette.Text.dim, ColorPalette.Border.primary),
            ("copied", ColorPalette.Status.success, ColorPalette.Border.primary),
            ("placeholder", ColorPalette.Text.placeholder, ColorPalette.Background.panel),
            ("recording and ending", ColorPalette.OnAccent.recording, ColorPalette.Status.recording),
        ]
        for (name, foreground, background) in pairs {
            XCTAssertEqual(colorComponents(foreground).a, 1, accuracy: 0.001, name)
            XCTAssertEqual(colorComponents(background).a, 1, accuracy: 0.001, name)
            XCTAssertGreaterThanOrEqual(contrast(foreground, background), 4.5, name)
        }
    }

    func testContrastCheckRejectsTheSupersededLowContrastPairs() {
        XCTAssertLessThan(contrast(Color(hex: "484F58"), ColorPalette.Background.primary), 4.5)
        XCTAssertLessThan(contrast(Color(hex: "52525B"), ColorPalette.Border.primary), 4.5)
        XCTAssertLessThan(contrast(.white, ColorPalette.Status.recording), 4.5)
    }

    @MainActor
    func testRenderedQuestionCardUsesReadableContextAndCopyRoles() throws {
        let view = QuestionsContent(questions: [SuggestedQuestion(
            question: "What would make the pilot useful?", type: "deeper",
            context: "The team has not agreed on a success measure.")])
            .minitiInterfaceScale(.compact)
            .frame(width: 420)
            .padding(12)
            .background(ColorPalette.Background.primary)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let raster = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(try pixelCount(ColorPalette.Text.meta, in: raster), 10, "Actual context text must use its readable role")
        XCTAssertGreaterThan(try pixelCount(ColorPalette.Text.dim, in: raster), 10, "Actual copy label must use its readable role")
    }

    @MainActor
    func testInsightUpdateLabelUsesNeutralChromeAtPlatformMinimum() throws {
        #if os(macOS)
        let shortcut: String? = "⌘⇧I"
        let minimum: CGFloat = 24
        #else
        let shortcut: String? = nil
        let minimum: CGFloat = 44
        #endif
        let labels = [
            AnyView(MinitiInsightUpdateLabel(title: "update", shortcut: shortcut)),
            AnyView(MinitiInsightUpdateLabel(title: "regenerate") { Text("sales") }),
            AnyView(MinitiInsightUpdateLabel(title: "finishing")),
        ]
        for label in labels {
            let renderer = ImageRenderer(content: label.background(ColorPalette.Background.primary))
            renderer.scale = 2
            let raster = try XCTUnwrap(renderer.cgImage)
            XCTAssertGreaterThanOrEqual(CGFloat(raster.width), minimum * 2)
            XCTAssertGreaterThanOrEqual(CGFloat(raster.height), minimum * 2)
            XCTAssertGreaterThan(try pixelCount(ColorPalette.Background.panel, in: raster), raster.width * raster.height / 5)
            XCTAssertGreaterThan(try pixelCount(ColorPalette.Text.muted, in: raster), 10)
        }
    }

    @MainActor
    func testLiveAndSavedInsightSectionsSharePlatformGeometry() throws {
        #if os(macOS)
        let live = AnyView(LiveInsightSection(title: "actions", color: ColorPalette.Insights.actions) {
            Text("Body fixture").foregroundStyle(ColorPalette.Text.secondary)
        })
        let saved = AnyView(DetailInsightBlock(title: "actions", color: ColorPalette.Insights.actions) {
            Text("Body fixture").foregroundStyle(ColorPalette.Text.secondary)
        }.padding(.horizontal, 16))
        #else
        let live = AnyView(InsightsPlainBlock_iOS(title: "actions", color: ColorPalette.Insights.actions) {
            Text("Body fixture").foregroundStyle(ColorPalette.Text.secondary)
        })
        let saved = AnyView(HistoricalDetailBlock_iOS(title: "actions", color: ColorPalette.Insights.actions) {
            Text("Body fixture").foregroundStyle(ColorPalette.Text.secondary)
        })
        #endif
        func render(_ view: AnyView) throws -> CGImage {
            let renderer = ImageRenderer(content: view.frame(width: 420)
                .background(ColorPalette.Background.primary))
            renderer.scale = 2
            return try XCTUnwrap(renderer.cgImage)
        }
        let liveImage = try render(live)
        let savedImage = try render(saved)
        XCTAssertEqual(liveImage.width, savedImage.width)
        XCTAssertEqual(liveImage.height, savedImage.height)
        let livePixels = try XCTUnwrap(liveImage.dataProvider?.data) as Data
        let savedPixels = try XCTUnwrap(savedImage.dataProvider?.data) as Data
        XCTAssertTrue(livePixels == savedPixels,
                      "Live and saved section type, accent bar, indent and spacing must match within a platform")
    }

    #if os(macOS)
    @MainActor
    func testSavedStandardSectionsUseCanonicalAccents() throws {
        let fixtures: [(Meeting, Color)] = [
            (Meeting(summaryText: "Summary fixture"), ColorPalette.Insights.summary),
            (Meeting(actionItems: ["Action fixture"]), ColorPalette.Insights.actions),
            (Meeting(topics: ["Topic fixture"]), ColorPalette.Insights.topics),
            (Meeting(discussionFlow: ["Discussion fixture"]), ColorPalette.Insights.discussion),
        ]
        for (meeting, color) in fixtures {
            // Isolate the first 16pt: body text, action arrows and topic tags
            // must not satisfy the header's accent assertion (review ST1).
            let renderer = ImageRenderer(content: SavedStandardInsightBlocks(meeting: meeting)
                .minitiInterfaceScale(.compact).frame(width: 420, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 16, alignment: .top).clipped()
                .background(ColorPalette.Background.primary))
            renderer.scale = 2
            let raster = try XCTUnwrap(renderer.cgImage)
            // Exclude the left 6pt too: the 3pt accent bar must not mask
            // a text-only heading-colour regression (review GE2).
            let titleRaster = try XCTUnwrap(raster.cropping(to: CGRect(
                x: 12, y: 0, width: raster.width - 12, height: raster.height)))
            XCTAssertGreaterThan(try pixelCount(color, in: titleRaster), 10)
        }
    }

    @MainActor
    func testRenderedLiveSectionCopyLabelsUseReadableRole() throws {
        let headers = [
            ("notes", AnyView(SectionHeader(title: "notes", icon: "✎", onCopy: { "Synthetic notes" }))),
            ("insights", AnyView(InsightsSectionHeader(onCopyInsights: { "Synthetic insights" })
                .environmentObject(AppState()))),
        ]
        for (name, header) in headers {
            // Only the header row: exclude the native Menu's renderer placeholder below it.
            let renderer = ImageRenderer(content: header.frame(width: 420)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 48, alignment: .top).clipped()
                .background(ColorPalette.Background.primary))
            renderer.scale = 2
            let raster = try XCTUnwrap(renderer.cgImage)
            XCTAssertGreaterThan(try pixelCount(ColorPalette.Text.dim, in: raster), 10,
                                 "Actual live \(name) Copy text must use its readable role")
        }
    }

    @MainActor
    func testRenderedRecordingAndEndingCapsulesUseTheirOnAccentForeground() throws {
        for remaining in [Int?.none, 5] {
            let view = MenuBarIcon(isRecording: true, elapsedText: "00:12",
                                  graceRemainingSeconds: remaining, nextEventTitle: nil, nextEventTime: nil)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let raster = try XCTUnwrap(renderer.cgImage)
            XCTAssertGreaterThan(try pixelCount(ColorPalette.Status.recording, in: raster), 50)
            XCTAssertGreaterThan(try pixelCount(ColorPalette.OnAccent.recording, in: raster), 10,
                                 "Actual REC/ENDING text must use the solid-red foreground pair")
        }
    }
    #endif

    /// Sample opaque interior pixels, ignoring antialiased text edges. Render
    /// into sRGB explicitly so the assertion is independent of display gamut.
    private func pixelCount(_ color: Color, in image: CGImage) throws -> Int {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                                                 bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let expected = colorComponents(color)
        let red = Int((expected.r * 255).rounded())
        let green = Int((expected.g * 255).rounded())
        let blue = Int((expected.b * 255).rounded())
        var count = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            guard bytes[offset + 3] == 255 else { continue }
            let matchesRed = abs(Int(bytes[offset]) - red) <= 5
            let matchesGreen = abs(Int(bytes[offset + 1]) - green) <= 5
            let matchesBlue = abs(Int(bytes[offset + 2]) - blue) <= 5
            if matchesRed && matchesGreen && matchesBlue { count += 1 }
        }
        return count
    }

    private func contrast(_ foreground: Color, _ background: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            let c = colorComponents(color)
            func linear(_ channel: CGFloat) -> Double {
                let value = Double(channel)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
        }
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

}
