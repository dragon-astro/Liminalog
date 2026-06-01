import SwiftUI
import UIKit

extension Color {
    // hex文字列→Colorのパースは Scanner を使うため、ボタン等で毎描画ごとに呼ぶと
    // 積み重なって描画がカクつく。同じhexは結果をキャッシュして再パースを避ける。
    private static let hexCacheLock = NSLock()
    nonisolated(unsafe) private static var hexCache: [String: Color] = [:]
    nonisolated(unsafe) private static var displayHexCache: [String: Color] = [:]

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

    static func cachedDisplayHex(_ hex: String) -> Color {
        hexCacheLock.lock()
        defer { hexCacheLock.unlock() }
        if let cached = displayHexCache[hex] {
            return cached
        }
        let color = Color(hex: hex).liminalReadableDataColor()
        displayHexCache[hex] = color
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

    func liminalReadableDataColor(minContrast: CGFloat = 3.0) -> Color {
        Color(UIColor(self).liminalReadableDataColor(minContrast: minContrast))
    }

    var liminalContrastingTextColor: Color {
        let fill = UIColor(self)
        let white = UIColor(red: 0.925, green: 0.91, blue: 0.961, alpha: 1)
        let black = UIColor(red: 0.051, green: 0.043, blue: 0.086, alpha: 1)
        return fill.contrastRatio(against: white) >= fill.contrastRatio(against: black) ? Color(white) : Color(black)
    }
}

private extension UIColor {
    func liminalReadableDataColor(minContrast: CGFloat) -> UIColor {
        let source = self
        return UIColor { traits in
            let background = LiminalTheme.uiCanvas(for: traits)
            return source.adjustedForReadability(against: background, minContrast: minContrast)
        }
    }

    private func adjustedForReadability(against background: UIColor, minContrast: CGFloat) -> UIColor {
        let backgroundIsLight = background.relativeLuminance() > 0.5
        // ライト（白系カード）の上では色相で十分見分けられる。3:1 を強制すると鮮やかな中間色まで
        // 暗く潰れてくすむため、ライトでは "ほぼ白で消える色" だけを軽く暗くする（しきい値を大きく下げる）。
        // ダーク地は暗い色が本当に埋もれるので 3:1 を維持。
        let effectiveMin: CGFloat = backgroundIsLight ? 1.45 : minContrast
        guard contrastRatio(against: background) < effectiveMin else {
            return self
        }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return UIColor(red: 0.78, green: 0.65, blue: 1, alpha: 1)
        }

        let adjustedSaturation = max(saturation, backgroundIsLight ? 0.32 : 0.18)

        if backgroundIsLight {
            // 淡い色だけを救済。鮮やかな色はここに来ない（しきい値1.45で素通り）。
            var adjustedBrightness = brightness
            var candidate = UIColor(hue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness, alpha: alpha)
            while candidate.contrastRatio(against: background) < effectiveMin && adjustedBrightness > 0.34 {
                adjustedBrightness -= 0.05
                candidate = UIColor(hue: hue, saturation: adjustedSaturation, brightness: max(adjustedBrightness, 0.34), alpha: alpha)
            }
            return candidate
        } else {
            var adjustedBrightness = max(brightness, 0.52)
            var candidate = UIColor(hue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness, alpha: alpha)
            while candidate.contrastRatio(against: background) < effectiveMin && adjustedBrightness < 0.96 {
                adjustedBrightness += 0.04
                candidate = UIColor(hue: hue, saturation: adjustedSaturation, brightness: min(adjustedBrightness, 0.96), alpha: alpha)
            }
            return candidate
        }
    }

    func contrastRatio(against other: UIColor) -> CGFloat {
        let l1 = relativeLuminance()
        let l2 = other.relativeLuminance()
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func relativeLuminance() -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}
