import SwiftUI

struct DailyReflectionCard: View {
    let date: Date
    let summary: ScoreSummary
    let chapters: [Chapter]
    let plans: [PlanBlock]
    let dayBoundary: DayBoundary
    let categoryRows: [(category: Category, duration: TimeInterval)]
    let recordedDuration: TimeInterval
    let onPlanTomorrow: () -> Void

    private var persona: DailyPersona {
        DailyPersona.make(
            summary: summary,
            chapters: chapters,
            categoryRows: categoryRows,
            dayBoundary: dayBoundary
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            DailyTwentyFourHourRing(
                planSegments: planSegments,
                actualSegments: actualSegments,
                score: summary.totalScore,
                hasScore: summary.plannedDuration > 0,
                persona: persona
            )
            .frame(height: 238)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Text(persona.title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(LiminalPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(persona.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalPalette.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DailyFactStrip(
                score: summary.totalScore,
                hasScore: summary.plannedDuration > 0,
                recordedDuration: recordedDuration,
                chapterCount: chapters.count
            )

            if !categoryRows.isEmpty {
                DailyCategoryConstellation(rows: Array(categoryRows.prefix(4)))
            }

            Button(action: onPlanTomorrow) {
                HStack(spacing: 9) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.caption.weight(.bold))
                    Text("明日はどうする？")
                        .font(.subheadline.weight(.bold))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(LiminalPalette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(LiminalPalette.glow.opacity(0.16))
                        .overlay(Capsule(style: .continuous).stroke(LiminalPalette.glow.opacity(0.28), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("明日の予定へ移動")
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LiminalPalette.cardGradient)
                .overlay(LiminalGrainOverlay().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(LiminalPalette.dawn.opacity(0.26))
                        .frame(width: 180, height: 180)
                        .blur(radius: 46)
                        .offset(x: 62, y: -70)
                }
                .overlay(alignment: .bottomLeading) {
                    Circle()
                        .fill(LiminalPalette.dusk.opacity(0.24))
                        .frame(width: 220, height: 220)
                        .blur(radius: 56)
                        .offset(x: -88, y: 86)
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [LiminalPalette.glow.opacity(0.52), .white.opacity(0.08), LiminalPalette.dusk.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: LiminalPalette.dusk.opacity(0.2), radius: 24, y: 14)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Liminalog")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LiminalPalette.glow)
                    .textCase(.uppercase)
                Text(date.japaneseMonthDayWeekday)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(LiminalPalette.subtext)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: summary.plannedDuration > 0 ? "circle.dashed.inset.filled" : "circle.dashed")
                    .font(.caption.weight(.bold))
                Text(summary.plannedDuration > 0 ? "予定と実績" : "実績のみ")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(LiminalPalette.text.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.08), in: Capsule(style: .continuous))
        }
    }

    private var planSegments: [DailyRingSegment] {
        plans.compactMap { plan in
            guard !plan.isAllDay else { return nil }
            let start = max(plan.startTime, dayBoundary.dayStart)
            let end = min(plan.endTime, dayBoundary.dayEnd)
            guard end > start else { return nil }
            return DailyRingSegment(
                start: start.timeIntervalSince(dayBoundary.dayStart),
                duration: end.timeIntervalSince(start),
                color: plan.category?.color ?? LiminalPalette.glow
            )
        }
    }

    private var actualSegments: [DailyRingSegment] {
        chapters.compactMap { chapter in
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
            guard end > start else { return nil }
            return DailyRingSegment(
                start: start.timeIntervalSince(dayBoundary.dayStart),
                duration: end.timeIntervalSince(start),
                color: chapter.category?.color ?? LiminalPalette.glow
            )
        }
    }
}

private enum LiminalPalette {
    static let night = Color(hex: "#0D0B16")
    static let card = Color(hex: "#17132A")
    static let raised = Color(hex: "#1F1A38")
    static let text = Color(hex: "#ECE8F5")
    static let subtext = Color(hex: "#B5AECF")
    static let glow = Color(hex: "#C9A7FF")
    static let dawn = Color(hex: "#FFB3C7")
    static let dusk = Color(hex: "#6B3FA0")
    static let amber = Color(hex: "#FFE3A3")

    static let cardGradient = LinearGradient(
        colors: [
            night,
            card,
            raised,
            Color(hex: "#231B36")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct DailyTwentyFourHourRing: View {
    let planSegments: [DailyRingSegment]
    let actualSegments: [DailyRingSegment]
    let score: Double
    let hasScore: Bool
    let persona: DailyPersona

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [LiminalPalette.glow.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 128
                    )
                )
                .blur(radius: 8)

            DailyRingCanvas(planSegments: planSegments, actualSegments: actualSegments)
                .padding(8)

            VStack(spacing: 6) {
                Image(systemName: persona.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(LiminalPalette.amber)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))

                Text(hasScore ? "\(Int(score.rounded()))pt" : "-- pt")
                    .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(LiminalPalette.text)

                Text(hasScore ? "予定との重なり" : "予定なしの日")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(LiminalPalette.subtext)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct DailyRingCanvas: View {
    let planSegments: [DailyRingSegment]
    let actualSegments: [DailyRingSegment]
    private let secondsPerDay: TimeInterval = 24 * 60 * 60

    var body: some View {
        Canvas { context, size in
            let minSide = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let planRadius = minSide * 0.31
            let actualRadius = minSide * 0.42

            drawBaseRing(context: &context, center: center, radius: planRadius, lineWidth: 16)
            drawBaseRing(context: &context, center: center, radius: actualRadius, lineWidth: 18)

            for segment in planSegments {
                draw(segment, context: &context, center: center, radius: planRadius, lineWidth: 16, opacity: 0.86)
            }
            for segment in actualSegments {
                draw(segment, context: &context, center: center, radius: actualRadius, lineWidth: 18, opacity: 0.96)
            }
        }
        .accessibilityLabel("予定と実績の二重24時間リング")
    }

    private func drawBaseRing(context: inout GraphicsContext, center: CGPoint, radius: CGFloat, lineWidth: CGFloat) {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
        context.stroke(path, with: .color(.white.opacity(0.08)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    private func draw(
        _ segment: DailyRingSegment,
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        opacity: Double
    ) {
        let startDegrees = -90 + (segment.start / secondsPerDay) * 360
        let endDegrees = startDegrees + max(segment.duration / secondsPerDay * 360, 0.75)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        context.stroke(
            path,
            with: .color(segment.color.opacity(opacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
        )
    }
}

private struct DailyRingSegment {
    let start: TimeInterval
    let duration: TimeInterval
    let color: Color
}

private struct DailyPersona {
    let title: String
    let message: String
    let symbol: String

    static func make(
        summary: ScoreSummary,
        chapters: [Chapter],
        categoryRows: [(category: Category, duration: TimeInterval)],
        dayBoundary: DayBoundary
    ) -> DailyPersona {
        guard !chapters.isEmpty else {
            return DailyPersona(title: "ミステリアスな1日", message: "記録の余白が多い日。何も残っていないことも、ちゃんと今日の形です。", symbol: "moon.dust.fill")
        }

        if summary.plannedDuration > 0, summary.totalScore >= 88 {
            return DailyPersona(title: "有言実行の人", message: "予定と実績のリングがかなり近い日。思い描いた今日に、ちゃんと手が届いています。", symbol: "checkmark.seal.fill")
        }

        let longest = categoryRows.first
        let longestMinutes = Int((longest?.duration ?? 0) / 60)
        if longestMinutes >= 180, let category = longest?.category {
            return DailyPersona(title: "\(timeTone(for: chapters, dayBoundary: dayBoundary))スプリンター", message: "\(category.name)が\(formatDailyDuration(longest?.duration ?? 0))。ひとつのことにぐっと寄った、濃いめの1日です。", symbol: "bolt.fill")
        }

        if chapters.count >= 8 {
            return DailyPersona(title: "\(timeTone(for: chapters, dayBoundary: dayBoundary))ザッピング", message: "\(chapters.count)回の切り替え。細かく動きながら、1日の輪郭を作った日です。", symbol: "sparkles")
        }

        if summary.plannedDuration == 0 {
            return DailyPersona(title: "風まかせ", message: "予定なしで流れた日。自由に動いた実績だけが、今日の形を作っています。", symbol: "wind")
        }

        return DailyPersona(title: "\(timeTone(for: chapters, dayBoundary: dayBoundary))マラソナー", message: "大きく崩れず、少しずつ進んだ日。派手ではないけれど、ちゃんと積み上がっています。", symbol: "figure.run")
    }

    private static func timeTone(for chapters: [Chapter], dayBoundary: DayBoundary) -> String {
        let weighted = chapters.reduce((total: TimeInterval(0), weighted: TimeInterval(0))) { partial, chapter in
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
            let duration = max(end.timeIntervalSince(start), 0)
            let midpoint = start.timeIntervalSince(dayBoundary.dayStart) + duration / 2
            return (partial.total + duration, partial.weighted + midpoint * duration)
        }
        guard weighted.total > 0 else { return "今日の" }
        let hour = weighted.weighted / weighted.total / 3600
        switch hour {
        case 0..<5: return "深夜の"
        case 5..<11: return "朝の"
        case 11..<16: return "昼の"
        default: return "夜の"
        }
    }
}

private struct DailyFactStrip: View {
    let score: Double
    let hasScore: Bool
    let recordedDuration: TimeInterval
    let chapterCount: Int

    var body: some View {
        HStack(spacing: 9) {
            DailyFactPill(title: "スコア", value: hasScore ? "\(Int(score.rounded()))" : "--", suffix: "pt", systemImage: "star.fill")
            DailyFactPill(title: "実績", value: formatDailyDuration(recordedDuration), suffix: nil, systemImage: "clock.fill")
            DailyFactPill(title: "切替", value: "\(chapterCount)", suffix: "回", systemImage: "rectangle.2.swap")
        }
    }
}

private struct DailyFactPill: View {
    let title: String
    let value: String
    let suffix: String?
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                Text(title)
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(LiminalPalette.subtext)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.black).monospacedDigit())
                    .foregroundStyle(LiminalPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                if let suffix {
                    Text(suffix)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LiminalPalette.subtext)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

private struct DailyCategoryConstellation: View {
    let rows: [(category: Category, duration: TimeInterval)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("昨日の色")
                .font(.caption.weight(.black))
                .foregroundStyle(LiminalPalette.subtext)

            HStack(spacing: 8) {
                ForEach(rows, id: \.category.id) { row in
                    HStack(spacing: 6) {
                        Image(systemName: row.category.icon ?? "circle.fill")
                            .font(.caption2.weight(.bold))
                        Text(row.category.name)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(LiminalPalette.text)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(row.category.color.opacity(0.24), in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).stroke(row.category.color.opacity(0.42), lineWidth: 1))
                }
            }
        }
    }
}

private struct LiminalGrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<70 {
                let x = CGFloat((index * 47) % 101) / 100 * size.width
                let y = CGFloat((index * 83) % 103) / 102 * size.height
                let opacity = Double((index % 5) + 1) * 0.006
                let rect = CGRect(x: x, y: y, width: 1, height: 1)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private func formatDailyDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = max(Int(seconds / 60), 0)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0, minutes > 0 {
        return "\(hours)時間\(minutes)分"
    } else if hours > 0 {
        return "\(hours)時間"
    } else {
        return "\(minutes)分"
    }
}
