import AppKit

// Mockup renderer for docs/36 C1/C2. Works on 3x simulator screenshots, coordinates in points.
let scale: CGFloat = 3
let dir = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]

func hex(_ s: String, _ a: CGFloat = 1) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

let accent = hex("B77A4D")
let elevated = hex("FFFEFF")
let chipBorder = hex("EADFD6")
let textColor = hex("2A2440")
let secondary = hex("8B8290")

struct Cat { let name: String; let color: String; let icon: String }
let cats = [
    Cat(name: "勉強", color: "3393F0", icon: "book.closed.fill"),
    Cat(name: "仕事", color: "6C5CE7", icon: "briefcase.fill"),
    Cat(name: "移動", color: "F2994A", icon: "tram.fill"),
    Cat(name: "休憩", color: "27AE60", icon: "cup.and.saucer.fill"),
    Cat(name: "睡眠", color: "9B51E0", icon: "moon.fill"),
    Cat(name: "趣味", color: "EB5757", icon: "sparkles"),
    Cat(name: "自由時間", color: "E2B93B", icon: "gamecontroller.fill"),
    Cat(name: "家事", color: "3FB8E6", icon: "house.fill"),
]

final class Canvas {
    let base: CGImage
    let ctx: CGContext
    let w: Int, h: Int
    init(_ path: String) {
        let img = NSImage(contentsOfFile: path)!
        var r = CGRect(origin: .zero, size: img.size)
        base = img.cgImage(forProposedRect: &r, context: nil, hints: nil)!
        w = base.width; h = base.height
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Top-left origin in points.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
    }

    /// Copy a rect of the ORIGINAL image (points) to a destination (points), optionally resized.
    func copy(_ src: CGRect, to dst: CGRect) {
        let px = CGRect(x: src.minX * scale, y: src.minY * scale, width: src.width * scale, height: src.height * scale)
        guard let piece = base.cropping(to: px) else { return }
        ctx.saveGState()
        ctx.translateBy(x: dst.minX, y: dst.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(piece, in: CGRect(x: 0, y: 0, width: dst.width, height: dst.height))
        ctx.restoreGState()
    }

    /// Erase a horizontal band by repeating the strip just above it (keeps gradient + grain).
    func eraseBand(y: CGFloat, height: CGFloat, x: CGFloat = 0, width: CGFloat = 402, strip: CGFloat = 6, sourceY: CGFloat? = nil) {
        let src = sourceY ?? (y - strip - 1)
        var cy = y
        while cy < y + height {
            let hh = min(strip, y + height - cy)
            copy(CGRect(x: x, y: src, width: width, height: hh), to: CGRect(x: x, y: cy, width: width, height: hh))
            cy += hh
        }
    }

    func withNS(_ body: () -> Void) {
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    func capsule(_ r: CGRect, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
        let p = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
        ctx.addPath(p); ctx.setFillColor(fill.cgColor); ctx.fillPath()
        if let stroke {
            let inset = r.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            ctx.addPath(CGPath(roundedRect: inset, cornerWidth: inset.height / 2, cornerHeight: inset.height / 2, transform: nil))
            ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(lineWidth); ctx.strokePath()
        }
    }

    /// Monochrome tint like SwiftUI foregroundStyle: knocked-out parts (e.g. the check) stay transparent.
    func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, center: CGPoint) {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else {
            print("missing symbol", name); return
        }
        let tinted = NSImage(size: img.size, flipped: false) { rect in
            img.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        withNS {
            tinted.draw(in: CGRect(x: center.x - img.size.width / 2, y: center.y - img.size.height / 2,
                                   width: img.size.width, height: img.size.height))
        }
    }

    @discardableResult
    func text(_ s: String, size: CGFloat, weight: String = "W6", color: NSColor, at p: CGPoint, centerY: Bool = true) -> CGFloat {
        let font = NSFont(name: "HiraginoSans-\(weight)", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
        let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let sz = attr.size()
        withNS { attr.draw(at: CGPoint(x: p.x, y: centerY ? p.y - sz.height / 2 : p.y)) }
        return sz.width
    }

    func textWidth(_ s: String, size: CGFloat) -> CGFloat {
        let font = NSFont(name: "HiraginoSans-W6", size: size)!
        return NSAttributedString(string: s, attributes: [.font: font]).size().width
    }

    /// Same metrics as TimelineCategoryChip.
    @discardableResult
    func categoryChip(_ c: Cat, selected: Bool, x: CGFloat, centerY: CGFloat) -> CGFloat {
        let tw = textWidth(c.name, size: 11)
        let w = 8 + 11 + 4 + tw + 8
        let r = CGRect(x: x, y: centerY - 15, width: w, height: 30)
        let col = hex(c.color)
        capsule(r, fill: elevated)
        capsule(r, fill: col.withAlphaComponent(selected ? 0.2 : 0.08), stroke: col.withAlphaComponent(selected ? 0.86 : 0.3), lineWidth: selected ? 2 : 1)
        symbol(selected ? "checkmark.circle.fill" : c.icon, size: 10, weight: .bold, color: col, center: CGPoint(x: x + 8 + 5.5, y: centerY))
        text(c.name, size: 11, color: textColor, at: CGPoint(x: x + 8 + 11 + 4, y: centerY))
        return w
    }

    func createChip(x: CGFloat, centerY: CGFloat) -> CGFloat {
        let tw = textWidth("新しいカテゴリ", size: 11)
        let w = 9 + 10.5 + 5 + tw + 9
        let r = CGRect(x: x, y: centerY - 15, width: w, height: 30)
        capsule(r, fill: elevated, stroke: accent.withAlphaComponent(0.5))
        symbol("plus", size: 10.5, weight: .bold, color: accent, center: CGPoint(x: x + 9 + 5.25, y: centerY))
        text("新しいカテゴリ", size: 11, color: accent, at: CGPoint(x: x + 9 + 10.5 + 5, y: centerY))
        return w
    }

    /// The proposed shared preset entry: same capsule as the month bar, sized to the chip row.
    func presetPair(x: CGFloat, centerY: CGFloat, height: CGFloat = 30, segment: CGFloat = 40, includesDay: Bool = true, iconSize: CGFloat = 15) -> CGFloat {
        let n: CGFloat = includesDay ? 2 : 1
        let r = CGRect(x: x, y: centerY - height / 2, width: segment * n, height: height)
        capsule(r, fill: elevated, stroke: chipBorder)
        symbol("bookmark.fill", size: iconSize, weight: .semibold, color: accent, center: CGPoint(x: x + segment / 2, y: centerY))
        if includesDay {
            symbol("calendar.badge.clock", size: iconSize, weight: .semibold, color: accent, center: CGPoint(x: x + segment * 1.5, y: centerY))
        }
        return r.width
    }

    func vline(x: CGFloat, centerY: CGFloat, height: CGFloat) {
        ctx.setFillColor(hex("D9CFCB").cgColor)
        ctx.fill(CGRect(x: x, y: centerY - height / 2, width: 1, height: height))
    }

    /// Pinned preset pair + hairline + categories (scrolling part clipped at the screen edge).
    func paletteRow(centerY: CGFloat, includesDay: Bool, selected: Int = 0) {
        var x: CGFloat = 12
        x += presetPair(x: x, centerY: centerY, includesDay: includesDay)
        x += 8
        vline(x: x, centerY: centerY, height: 20)
        x += 9
        ctx.saveGState()
        ctx.clip(to: CGRect(x: x - 1, y: centerY - 18, width: 402 - x + 1, height: 36))
        for (i, c) in cats.enumerated() {
            x += categoryChip(c, selected: i == selected, x: x, centerY: centerY) + 8
            if x > 420 { break }
        }
        if x < 420 { _ = createChip(x: x, centerY: centerY) }
        ctx.restoreGState()
    }

    func save(_ name: String) {
        let img = ctx.makeImage()!
        let rep = NSBitmapImageRep(cgImage: img)
        let small = NSImage(size: NSSize(width: 414, height: 900))
        small.addRepresentation(rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }
}

// MARK: - C1

// Home tomorrow: one-day chip + floating bookmark → pinned pair. Row center 176.5pt.
do {
    let c = Canvas("\(dir)/raw_home_tomorrow.png")
    c.eraseBand(y: 160, height: 33)
    c.paletteRow(centerY: 176.5, includesDay: true)
    // Remove the floating preset button (bottom-right of the timeline) using the same block's fill to its left.
    c.copy(CGRect(x: 266, y: 722, width: 58, height: 62), to: CGRect(x: 326, y: 722, width: 58, height: 62))
    c.save("c1-home-tomorrow")
}

// Week: plan presets only (no target day) → single bookmark. Row center 156.8pt.
do {
    let c = Canvas("\(dir)/raw_cal_week.png")
    c.eraseBand(y: 140, height: 34)
    c.paletteRow(centerY: 156.8, includesDay: false)
    c.save("c1-calendar-week")
}

// Day: two text chips → pair.
do {
    let c = Canvas("\(dir)/raw_cal_day.png")
    c.eraseBand(y: 140, height: 34)
    c.paletteRow(centerY: 156.8, includesDay: true)
    c.save("c1-calendar-day")
}

// Expanded timeline sheet: two text chips → pair. Row center 164.8pt (white sheet).
do {
    let c = Canvas("\(dir)/raw_expanded.png")
    c.eraseBand(y: 148, height: 34)
    c.paletteRow(centerY: 164.8, includesDay: true)
    c.save("c1-expanded-timeline")
}

// MARK: - C2 (month)

// A: keep the row, give its right side a job (jump to today) so the row is symmetric, not half-empty.
do {
    let c = Canvas("\(dir)/raw_cal_month.png")
    let cy: CGFloat = 155.8
    let tw = c.textWidth("今日", size: 15)
    let w = tw + 32
    let r = CGRect(x: 402 - 12 - w, y: cy - 17, width: w, height: 34)
    c.capsule(r, fill: elevated)
    c.text("今日", size: 15, color: accent, at: CGPoint(x: r.minX + 16, y: cy))
    c.save("c2a-month-today")
}

// B: slim row. Pair 28pt tall, row height 48 → 34pt; grid gets the 14pt back.
do {
    let c = Canvas("\(dir)/raw_cal_month.png")
    let gridTop: CGFloat = 180      // weekday header top
    let gridBottom: CGFloat = 795   // calendar card bottom
    let saved: CGFloat = 14
    // Stretch the calendar card upward into the saved space.
    c.copy(CGRect(x: 0, y: gridTop, width: 402, height: gridBottom - gridTop),
           to: CGRect(x: 0, y: gridTop - saved, width: 402, height: gridBottom - gridTop + saved))
    c.eraseBand(y: 136, height: gridTop - saved - 136, sourceY: 128)
    _ = c.presetPair(x: 12, centerY: 136 + (gridTop - saved - 136) / 2, height: 28, segment: 40, includesDay: true, iconSize: 14)
    c.save("c2b-month-slim")
}

// MARK: - C2-C: presets take the header's left pair; mode + settings move into the title sheet.

extension Canvas {
    /// Replace the header's left two icons (settings, display mode) with the preset pair, same tint/size as the right side.
    func headerPresetPair(centerY: CGFloat = 98) {
        eraseBand(y: centerY - 22, height: 44, x: 8, width: 104, strip: 5, sourceY: centerY - 29)
        let tint = accent.withAlphaComponent(0.72)
        symbol("bookmark.fill", size: 19, weight: .semibold, color: tint, center: CGPoint(x: 34, y: centerY))
        symbol("calendar.badge.clock", size: 19, weight: .semibold, color: tint, center: CGPoint(x: 82, y: centerY))
    }

    func paletteRowCategoriesOnly(centerY: CGFloat, selected: Int = 0) {
        var x: CGFloat = 12
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: centerY - 18, width: 402, height: 36))
        for (i, c) in cats.enumerated() {
            x += categoryChip(c, selected: i == selected, x: x, centerY: centerY) + 8
            if x > 420 { break }
        }
        ctx.restoreGState()
    }
}

do {
    let c = Canvas("\(dir)/raw_cal_month.png")
    c.headerPresetPair()
    // Remove the dedicated preset row: the calendar card takes its 48pt.
    c.copy(CGRect(x: 0, y: 183, width: 402, height: 593), to: CGRect(x: 0, y: 135, width: 402, height: 641))
    c.save("c2c-month-header")
}

do {
    let c = Canvas("\(dir)/raw_cal_week.png")
    c.headerPresetPair()
    c.eraseBand(y: 140, height: 34)
    c.paletteRowCategoriesOnly(centerY: 156.8)
    c.save("c2c-week-header")
}

// Title sheet: period + display mode + a link to display settings, on a plain sheet.
do {
    let c = Canvas("\(dir)/raw_cal_month.png")
    c.headerPresetPair()
    c.copy(CGRect(x: 0, y: 183, width: 402, height: 593), to: CGRect(x: 0, y: 135, width: 402, height: 641))
    // Dim like a presented sheet.
    c.ctx.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
    c.ctx.fill(CGRect(x: 0, y: 0, width: 402, height: 874))
    let top: CGFloat = 470
    let sheet = CGRect(x: 8, y: top, width: 386, height: 874 - top - 8)
    c.ctx.addPath(CGPath(roundedRect: sheet, cornerWidth: 38, cornerHeight: 38, transform: nil))
    c.ctx.setFillColor(hex("FBF8F6").cgColor); c.ctx.fillPath()
    // Header
    c.capsule(CGRect(x: 24, y: top + 16, width: 104, height: 40), fill: hex("F1ECEA"))
    c.text("キャンセル", size: 16, weight: "W3", color: accent, at: CGPoint(x: 36, y: top + 36))
    let titleW = c.textWidth("表示", size: 17)
    c.text("表示", size: 17, color: textColor, at: CGPoint(x: 201 - titleW / 2, y: top + 36))
    c.capsule(CGRect(x: 318, y: top + 16, width: 60, height: 40), fill: hex("F1ECEA"))
    c.text("完了", size: 16, color: accent, at: CGPoint(x: 332, y: top + 36))
    // Segmented 月|週|日
    let seg = CGRect(x: 24, y: top + 72, width: 354, height: 34)
    c.capsule(seg, fill: hex("ECE7E5"))
    let segW = seg.width / 3
    let selRect = CGRect(x: seg.minX + 2, y: seg.minY + 2, width: segW - 4, height: seg.height - 4)
    c.capsule(selRect, fill: .white)
    for (i, t) in ["月", "週", "日"].enumerated() {
        let tw = c.textWidth(t, size: 14)
        c.text(t, size: 14, weight: i == 0 ? "W6" : "W3", color: textColor, at: CGPoint(x: seg.minX + segW * CGFloat(i) + segW / 2 - tw / 2, y: seg.midY))
    }
    // Wheel picker (year / month) drawn simply.
    let wheelTop = top + 122
    let rowH: CGFloat = 32
    let years = ["2024年", "2025年", "2026年", "2027年", "2028年"]
    let months = ["8月", "9月", "10月", "11月", "12月"]
    c.capsule(CGRect(x: 24, y: wheelTop + rowH * 2, width: 354, height: rowH), fill: hex("ECE7E5"))
    for i in 0..<5 {
        let d = abs(i - 2)
        let col = textColor.withAlphaComponent(d == 0 ? 1 : (d == 1 ? 0.45 : 0.22))
        let size: CGFloat = d == 0 ? 21 : 19
        let y = wheelTop + rowH * CGFloat(i) + rowH / 2
        let yw = c.textWidth(years[i], size: size)
        c.text(years[i], size: size, weight: "W3", color: col, at: CGPoint(x: 112 - yw / 2, y: y))
        let mw = c.textWidth(months[i], size: size)
        c.text(months[i], size: size, weight: "W3", color: col, at: CGPoint(x: 290 - mw / 2, y: y))
    }
    // Link row to the calendar display settings (moved from the header gear).
    let rowY = wheelTop + rowH * 5 + 20
    c.ctx.setFillColor(hex("E6DFDC").cgColor); c.ctx.fill(CGRect(x: 24, y: rowY - 4, width: 354, height: 1))
    c.symbol("gearshape", size: 16, weight: .regular, color: secondary, center: CGPoint(x: 36, y: rowY + 20))
    c.text("カレンダーの表示設定", size: 15, weight: "W3", color: textColor, at: CGPoint(x: 52, y: rowY + 20))
    c.symbol("chevron.right", size: 13, weight: .semibold, color: secondary, center: CGPoint(x: 368, y: rowY + 20))
    c.save("c2c-title-sheet")
}

// MARK: - v3 (2026-10-16): single preset button, header [⚙][🔖] title [≡][🔍], mode tabs in the title sheet.

extension Canvas {
    /// Swap only the display-mode icon (2nd from left) for the preset bookmark. Settings stays.
    func headerPresetButton(centerY: CGFloat = 98) {
        eraseBand(y: centerY - 22, height: 44, x: 60, width: 52, strip: 5, sourceY: centerY - 29)
        symbol("bookmark.fill", size: 19, weight: .semibold, color: accent.withAlphaComponent(0.72), center: CGPoint(x: 82, y: centerY))
    }

    func singlePresetRow(centerY: CGFloat) {
        var x: CGFloat = 12
        x += presetPair(x: x, centerY: centerY, includesDay: false)
        x += 8
        vline(x: x, centerY: centerY, height: 20)
        x += 9
        ctx.saveGState()
        ctx.clip(to: CGRect(x: x - 1, y: centerY - 18, width: 402 - x + 1, height: 36))
        for (i, c) in cats.enumerated() {
            x += categoryChip(c, selected: i == 0, x: x, centerY: centerY) + 8
            if x > 420 { break }
        }
        ctx.restoreGState()
    }

    /// Same look as Home's 昨日/今日/明日 and the timeline 実績/予定 toggle.
    func textTabs(_ titles: [String], selected: Int, centerX: CGFloat, centerY: CGFloat, spacing: CGFloat = 28, size: CGFloat = 16, icons: [String]? = nil) {
        let widths = titles.enumerated().map { i, t in textWidth(t, size: size) + (icons == nil ? 0 : 18) }
        let total = widths.reduce(0, +) + spacing * CGFloat(titles.count - 1)
        var x = centerX - total / 2
        for (i, t) in titles.enumerated() {
            let on = i == selected
            let col = on ? textColor : secondary.withAlphaComponent(0.8)
            var tx = x
            if let icons {
                symbol(icons[i], size: 12, weight: .semibold, color: col, center: CGPoint(x: x + 6, y: centerY))
                tx += 18
            }
            text(t, size: size, weight: on ? "W6" : "W3", color: col, at: CGPoint(x: tx, y: centerY))
            if on {
                capsule(CGRect(x: x + widths[i] / 2 - 12, y: centerY + 13, width: 24, height: 2.5), fill: accent)
            }
            x += widths[i] + spacing
        }
    }

    func roundedRect(_ r: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(fill.cgColor); ctx.fillPath()
        if let stroke {
            ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(1); ctx.strokePath()
        }
    }

    /// Preset drawer header with the shared title, a quiet 管理 link, and the 予定/一日 tabs.
    func drawerHeader(selectedTab: Int) {
        eraseBand(y: 160, height: 33)
        singlePresetRow(centerY: 176.5)
        ctx.setFillColor(hex("FFFEFF").cgColor)
        ctx.fill(CGRect(x: 12, y: 592, width: 383, height: 88))
        symbol("bookmark.fill", size: 15, weight: .semibold, color: textColor, center: CGPoint(x: 30, y: 608))
        text("プリセット", size: 15, color: textColor, at: CGPoint(x: 44, y: 608))
        text("管理", size: 12, weight: "W3", color: secondary, at: CGPoint(x: 314, y: 608))
        symbol("xmark.circle.fill", size: 20, weight: .regular, color: secondary.withAlphaComponent(0.8), center: CGPoint(x: 367, y: 608))
        textTabs(["予定", "一日"], selected: selectedTab, centerX: 201, centerY: 644, spacing: 36, size: 14,
                 icons: ["bookmark.fill", "calendar.badge.clock"])
        ctx.setFillColor(hex("EFE8E4").cgColor)
        ctx.fill(CGRect(x: 26, y: 666, width: 350, height: 1))
    }

    func dayPresetCard(y: CGFloat, name: String, sub: String, segments: [(Double, Double, String)]) {
        let r = CGRect(x: 26, y: y, width: 350, height: 62)
        roundedRect(r, radius: 12, fill: hex("FBF7F4"), stroke: hex("EFE6E0"))
        text(name, size: 15, color: textColor, at: CGPoint(x: 40, y: y + 18))
        text(sub, size: 12, weight: "W3", color: secondary, at: CGPoint(x: 40, y: y + 36))
        let bar = CGRect(x: 40, y: y + 46, width: 296, height: 6)
        roundedRect(bar, radius: 3, fill: hex("EEE8E4"))
        for seg in segments {
            let x0 = bar.minX + bar.width * CGFloat(seg.0 / 24)
            let x1 = bar.minX + bar.width * CGFloat(seg.1 / 24)
            ctx.setFillColor(hex(seg.2).cgColor)
            ctx.fill(CGRect(x: x0, y: bar.minY, width: max(1, x1 - x0 - 0.6), height: bar.height))
        }
        symbol("plus.circle.fill", size: 20, weight: .regular, color: accent, center: CGPoint(x: 356, y: y + 22))
    }
}

let purple = "9B51E0", green = "27AE60", orange = "F2994A", blue = "3393F0", work = "6C5CE7", red = "EB5757", yellow = "E2B93B"

do {
    let c = Canvas("\(dir)/raw_cal_month.png")
    c.headerPresetButton()
    c.copy(CGRect(x: 0, y: 183, width: 402, height: 593), to: CGRect(x: 0, y: 135, width: 402, height: 641))
    c.save("v3-month")
}

do {
    let c = Canvas("\(dir)/raw_cal_week.png")
    c.headerPresetButton()
    c.eraseBand(y: 140, height: 34)
    c.paletteRowCategoriesOnly(centerY: 156.8)
    c.save("v3-week")
}

do {
    let c = Canvas("\(dir)/raw_cal_month.png")
    c.headerPresetButton()
    c.copy(CGRect(x: 0, y: 183, width: 402, height: 593), to: CGRect(x: 0, y: 135, width: 402, height: 641))
    c.ctx.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
    c.ctx.fill(CGRect(x: 0, y: 0, width: 402, height: 874))
    let top: CGFloat = 486
    c.roundedRect(CGRect(x: 8, y: top, width: 386, height: 874 - top - 8), radius: 38, fill: hex("FBF8F6"))
    c.capsule(CGRect(x: 24, y: top + 16, width: 104, height: 40), fill: hex("F1ECEA"))
    c.text("キャンセル", size: 16, weight: "W3", color: accent, at: CGPoint(x: 36, y: top + 36))
    c.capsule(CGRect(x: 318, y: top + 16, width: 60, height: 40), fill: hex("F1ECEA"))
    c.text("完了", size: 16, color: accent, at: CGPoint(x: 332, y: top + 36))
    let tw = c.textWidth("表示", size: 17)
    c.text("表示", size: 17, color: textColor, at: CGPoint(x: 201 - tw / 2, y: top + 36))
    // Mode tabs right under the header: one tap switches and closes.
    c.textTabs(["日間", "週間", "月間"], selected: 2, centerX: 201, centerY: top + 86, spacing: 36, size: 16)
    c.ctx.setFillColor(hex("EDE6E2").cgColor)
    c.ctx.fill(CGRect(x: 24, y: top + 112, width: 354, height: 1))
    let wheelTop = top + 122
    let rowH: CGFloat = 32
    let years = ["2024年", "2025年", "2026年", "2027年", "2028年"]
    let months = ["8月", "9月", "10月", "11月", "12月"]
    c.capsule(CGRect(x: 24, y: wheelTop + rowH * 2, width: 354, height: rowH), fill: hex("ECE7E5"))
    for i in 0..<5 {
        let d = abs(i - 2)
        let col = textColor.withAlphaComponent(d == 0 ? 1 : (d == 1 ? 0.45 : 0.22))
        let size: CGFloat = d == 0 ? 21 : 19
        let y = wheelTop + rowH * CGFloat(i) + rowH / 2
        let yw = c.textWidth(years[i], size: size)
        c.text(years[i], size: size, weight: "W3", color: col, at: CGPoint(x: 112 - yw / 2, y: y))
        let mw = c.textWidth(months[i], size: size)
        c.text(months[i], size: size, weight: "W3", color: col, at: CGPoint(x: 290 - mw / 2, y: y))
    }
    c.save("v3-title-sheet")
}

do {
    let c = Canvas("\(dir)/raw_home_tomorrow.png")
    c.eraseBand(y: 160, height: 33)
    c.singlePresetRow(centerY: 176.5)
    c.copy(CGRect(x: 266, y: 722, width: 58, height: 62), to: CGRect(x: 326, y: 722, width: 58, height: 62))
    c.save("v3-home-tomorrow")
}

do {
    let c = Canvas("\(dir)/raw_plan_drawer.png")
    // Push the existing content down to make room for the tabs.
    c.copy(CGRect(x: 0, y: 628, width: 402, height: 246), to: CGRect(x: 0, y: 680, width: 402, height: 246))
    c.drawerHeader(selectedTab: 0)
    c.save("v3-drawer-plan")
}

do {
    let c = Canvas("\(dir)/raw_plan_drawer.png")
    c.ctx.setFillColor(hex("FFFEFF").cgColor)
    c.ctx.fill(CGRect(x: 12, y: 620, width: 378, height: 254))
    c.drawerHeader(selectedTab: 1)
    // Target day: fixed on Home tomorrow / a chosen day; changeable on week or month without a selected day.
    c.text("追加する日", size: 13, weight: "W3", color: secondary, at: CGPoint(x: 28, y: 688))
    let pill = CGRect(x: 268, y: 675, width: 108, height: 26)
    c.capsule(pill, fill: hex("F1ECEA"))
    c.text("10月17日(土)", size: 13, color: textColor, at: CGPoint(x: pill.minX + 10, y: pill.midY))
    c.dayPresetCard(y: 708, name: "平日の基本", sub: "8件 · 0:00–24:00", segments: [
        (0, 7, purple), (7, 8, green), (8, 9, orange), (9, 12, blue), (12, 13, green), (13, 16, work), (16, 18, blue), (18, 19, orange), (19, 22, red), (22, 24, purple)])
    c.dayPresetCard(y: 780, name: "休日のんびり", sub: "5件 · 0:00–24:00", segments: [
        (0, 9, purple), (9, 12, yellow), (12, 13, green), (13, 18, red), (18, 22, yellow), (23, 24, purple)])
    c.dayPresetCard(y: 852, name: "試験前", sub: "6件", segments: [(0, 6, purple), (7, 12, blue), (12, 13, green), (13, 18, blue), (19, 22, blue), (23, 24, purple)])
    c.save("v3-drawer-day")
}
print("done")
