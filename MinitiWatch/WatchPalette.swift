import SwiftUI

/// The watch app's slice of the shared design tokens (`Miniti/Models/ColorPalette.swift`).
/// Kept as a separate file so view code never carries hex literals.
enum WatchPalette {
    static let background = Color(red: 0x09 / 255, green: 0x09 / 255, blue: 0x0B / 255)
    static let surface = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1F / 255)
    static let textPrimary = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255)
    static let textDim = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xAA / 255)
    static let recording = Color(red: 0xF8 / 255, green: 0x51 / 255, blue: 0x49 / 255)
    static let success = Color(red: 0x3F / 255, green: 0xB9 / 255, blue: 0x50 / 255)
    static let warning = Color(red: 0xD2 / 255, green: 0x99 / 255, blue: 0x22 / 255)
}
