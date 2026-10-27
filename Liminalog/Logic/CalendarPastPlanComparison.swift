#if DEBUG
import SwiftUI
import UIKit

/// Screenshot experiment for docs/38 §14. No production defaults or stored colors change.
enum CalendarPastPlanComparison {
    static let argument = "-LiminalogPastPlanComparison"
    static let variant: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-LiminalogMonthDrawerUITests"),
              let index = args.firstIndex(of: argument), args.indices.contains(index + 1),
              ["v0", "v1", "v2-45", "v2-50", "v2-55"].contains(args[index + 1]) else { return nil }
        return args[index + 1]
    }()

    // Freeze only comparison rendering/fixtures, so later captures use the same past/future split.
    static let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!

    static func isEnabled(in scheme: ColorScheme) -> Bool { variant != nil && scheme == .light }
    static var strikesPast: Bool { variant != "v0" }
    static var pastOpacity: Double { variant == "v0" ? 0.65 : variant == "v1" ? 0.5 : 1 }

    static func fill(from color: Color, past: Bool) -> Color? {
        guard let variant, variant != "v0" else { return nil }
        let source = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        guard source.getRed(&r, green: &g, blue: &b, alpha: &alpha) else { return nil }
        let rgb = RGB(r: Double(r), g: Double(g), b: Double(b))
        let lab = rgb.lab
        // Start at the current 84%-on-white lightness, keeping the category's hue/chroma.
        let baseline = RGB(r: rgb.r * 0.84 + 0.16, g: rgb.g * 0.84 + 0.16, b: rgb.b * 0.84 + 0.16)
        var low = 0.0, high = baseline.lab.l
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if gamutMapped(Lab(l: middle, a: lab.a, b: lab.b)).whiteContrast >= 3.35 { low = middle }
            else { high = middle }
        }
        let future = gamutMapped(Lab(l: low, a: lab.a, b: lab.b))
        let result: RGB
        if past, variant.hasPrefix("v2-"), let percent = Double(variant.suffix(2)) {
            let futureLab = future.lab
            result = gamutMapped(Lab(l: 1 - (1 - futureLab.l) * percent / 100,
                                    a: futureLab.a * 0.7, b: futureLab.b * 0.7))
        } else {
            result = future
        }
        return Color(.sRGB, red: result.r, green: result.g, blue: result.b, opacity: 1)
    }

    // Keep L and hue while reducing chroma only if the requested color is outside sRGB.
    private static func gamutMapped(_ lab: Lab) -> RGB {
        if lab.rgb.inGamut { return lab.rgb }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if Lab(l: lab.l, a: lab.a * middle, b: lab.b * middle).rgb.inGamut { low = middle }
            else { high = middle }
        }
        return Lab(l: lab.l, a: lab.a * low, b: lab.b * low).rgb
    }

    // Björn Ottosson's public-domain Oklab matrices: https://bottosson.github.io/posts/oklab/
    private struct Lab {
        let l: Double, a: Double, b: Double
        var rgb: RGB {
            let x = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
            let y = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
            let z = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
            func encode(_ value: Double) -> Double {
                value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
            }
            return RGB(r: encode(4.0767416621 * x - 3.3077115913 * y + 0.2309699292 * z),
                       g: encode(-1.2684380046 * x + 2.6097574011 * y - 0.3413193965 * z),
                       b: encode(-0.0041960863 * x - 0.7034186147 * y + 1.7076147010 * z))
        }
    }
    private struct RGB {
        let r: Double, g: Double, b: Double
        var inGamut: Bool { [r, g, b].allSatisfy { (0...1).contains($0) } }
        private func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        var whiteContrast: Double { 1.05 / (0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) + 0.05) }
        var lab: Lab {
            let r = linear(r), g = linear(g), b = linear(b)
            let x = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let y = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let z = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            return Lab(l: 0.2104542553 * x + 0.7936177850 * y - 0.0040720468 * z,
                       a: 1.9779984951 * x - 2.4285922050 * y + 0.4505937099 * z,
                       b: 0.0259040371 * x + 0.7827717662 * y - 0.8086757660 * z)
        }
    }
}
#endif
