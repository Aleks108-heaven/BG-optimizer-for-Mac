import AppKit
import SwiftUI

/// Colors that follow light/dark. Text/background pairs were picked for at least 4.5:1 contrast (checked by hand, not by tool).
extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
    static let slowBg = dynamic(light: 0xFFF0D1, dark: 0x4A3708)     // slowed (amber)
    static let slowInk = dynamic(light: 0x6B4200, dark: 0xFFD98A)
    static let calmBg = dynamic(light: 0xE3F3E7, dark: 0x1E3B27)     // all good (green)
    static let calmInk = dynamic(light: 0x1B5E2B, dark: 0xA8E6B8)
    static let protBg = dynamic(light: 0xE6E9FA, dark: 0x2B3366)     // protected (indigo)
    static let protInk = dynamic(light: 0x27348A, dark: 0xC9D0FF)
    static let neuBg = dynamic(light: 0xECECF0, dark: 0x3A3A3F)      // neutral chips
    static let neuInk = dynamic(light: 0x45454C, dark: 0xD0D0D6)
    static let warnBg = dynamic(light: 0xFDE3DC, dark: 0x5A2118)     // needs attention (red-orange)
    static let warnInk = dynamic(light: 0x8A1F0B, dark: 0xFFC2B5)
}
