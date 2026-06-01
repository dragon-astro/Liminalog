import SwiftUI

extension Color {
    private static let widgetHexCacheLock = NSLock()
    nonisolated(unsafe) private static var widgetHexCache: [String: Color] = [:]

    static func cachedHex(_ hex: String) -> Color {
        widgetHexCacheLock.lock()
        defer { widgetHexCacheLock.unlock() }
        if let cached = widgetHexCache[hex] {
            return cached
        }
        let color = Color(widgetHex: hex)
        widgetHexCache[hex] = color
        return color
    }

    private init(widgetHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch cleaned.count {
        case 6:
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        default:
            red = 0x8E
            green = 0x8E
            blue = 0x93
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }
}
