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

    func testMEDDPICCColorForKnownLetters() {
        XCTAssertEqual(ColorPalette.MEDDPICC.color(for: "M"), "3B82F6")
        XCTAssertEqual(ColorPalette.MEDDPICC.color(for: "E"), "A78BFA")
        XCTAssertEqual(ColorPalette.MEDDPICC.color(for: "D"), "EC4899")
        XCTAssertEqual(ColorPalette.MEDDPICC.color(for: "P"), "F59E0B")
        XCTAssertEqual(ColorPalette.MEDDPICC.color(for: "I"), "EF4444")
        XCTAssertEqual(ColorPalette.MEDDPICC.color(for: "C"), "22C55E")
    }

    func testMEDDPICCColorDefaultUnknown() {
        XCTAssertEqual(ColorPalette.MEDDPICC.color(for: "X"), "3B82F6")
    }

    func testMEDDPICCColorCaseInsensitive() {
        XCTAssertEqual(ColorPalette.MEDDPICC.color(for: "m"), "3B82F6")
        XCTAssertEqual(ColorPalette.MEDDPICC.color(for: "e"), "A78BFA")
    }

    // MARK: - Design-system contracts

    func testCompactControlMetricsStayAligned() {
        XCTAssertEqual(MinitiDesignSystem.Control.compactHeight, 30)
        XCTAssertEqual(MinitiDesignSystem.Control.horizontalPadding, 10)
        XCTAssertEqual(MinitiDesignSystem.Control.modeHorizontalPadding, 10)
        XCTAssertEqual(MinitiDesignSystem.Control.modeSpacing, 4)
        XCTAssertEqual(MinitiDesignSystem.Radius.control, 6)
    }

    func testInsightModesUseTheirSemanticAccents() {
        XCTAssertEqual(MinitiDesignSystem.Accent.insightMode(.standard), ColorPalette.Accent.blueGitHub)
        XCTAssertEqual(MinitiDesignSystem.Accent.insightMode(.questions), ColorPalette.Accent.purpleLight)
        XCTAssertEqual(MinitiDesignSystem.Accent.insightMode(.training), ColorPalette.Accent.amber)
        XCTAssertEqual(MinitiDesignSystem.Accent.insightMode(.meddpicc), ColorPalette.Accent.pink)
        XCTAssertEqual(MinitiDesignSystem.Accent.insightMode(.docs), ColorPalette.Accent.purpleSoft)
    }
}
