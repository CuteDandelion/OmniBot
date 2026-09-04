import AppKit
import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    init(lightHex: String, darkHex: String) {
        let light = NSColor(Color(hex: lightHex))
        let dark = NSColor(Color(hex: darkHex))
        self.init(
            nsColor: NSColor(name: nil, dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
        )
    }
}

enum Tokens {
    static let cardRadius: CGFloat = 6
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 12)

    static let canvas = Color(lightHex: "#ffffff", darkHex: "#0d1117")
    static let subtle = Color(lightHex: "#f6f8fa", darkHex: "#161b22")
    static let border = Color(lightHex: "#d0d7de", darkHex: "#30363d")
    static let fg = Color(lightHex: "#1f2328", darkHex: "#e6edf3")
    static let muted = Color(lightHex: "#656d76", darkHex: "#8b949e")
    static let accent = Color(lightHex: "#0969da", darkHex: "#2f81f7")
}
