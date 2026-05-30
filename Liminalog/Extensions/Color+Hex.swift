import SwiftUI

extension Color {
    // hex文字列→Colorのパースは Scanner を使うため、ボタン等で毎描画ごとに呼ぶと
    // 積み重なって描画がカクつく。同じhexは結果をキャッシュして再パースを避ける。
    private static let hexCacheLock = NSLock()
    nonisolated(unsafe) private static var hexCache: [String: Color] = [:]

    static func cachedHex(_ hex: String) -> Color {
        hexCacheLock.lock()
        defer { hexCacheLock.unlock() }
        if let cached = hexCache[hex] {
            return cached
        }
        let color = Color(hex: hex)
        hexCache[hex] = color
        return color
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
