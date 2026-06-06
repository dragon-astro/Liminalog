import SwiftUI
import UIKit

struct DailyReflectionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let date: Date
    let summary: ScoreSummary
    let chapters: [Chapter]
    let historyChapters: [Chapter]
    let plans: [PlanBlock]
    let dayBoundary: DayBoundary
    let categoryRows: [(category: Category, duration: TimeInterval)]
    let recordedDuration: TimeInterval
    let onPlanTomorrow: () -> Void
    @State private var shareItem: DailyCardShareItem?

    private var persona: DailyPersona {
        DailyPersona.make(
            summary: summary,
            chapters: chapters,
            historyChapters: historyChapters,
            categoryRows: categoryRows,
            recordedDuration: recordedDuration,
            dayBoundary: dayBoundary
        )
    }

    var body: some View {
        DailyReflectionCardSurface(
            date: date,
            summary: summary,
            planSegments: planSegments,
            actualSegments: actualSegments,
            persona: persona,
            categoryRows: categoryRows,
            onShare: {
                shareItem = renderShareImage()
            },
            onPlanTomorrow: onPlanTomorrow
        )
        .sheet(item: $shareItem) { item in
            DailyCardActivityView(activityItems: [item.url])
                .presentationDetents([.medium, .large])
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
                color: plan.category?.displayColor ?? LiminalTheme.accent
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
                color: chapter.category?.displayColor ?? LiminalTheme.accent
            )
        }
    }

    @MainActor
    private func renderShareImage() -> DailyCardShareItem? {
        let content = DailyShareCardView(
            date: date,
            summary: summary,
            planSegments: planSegments,
            actualSegments: actualSegments,
            persona: persona,
            categoryRows: categoryRows
        )
        .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("liminalog-\(Int(date.timeIntervalSince1970))-daily-card.png")
        do {
            try data.write(to: url, options: [.atomic])
            return DailyCardShareItem(url: url)
        } catch {
            return nil
        }
    }
}

private struct DailyReflectionCardSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    let date: Date
    let summary: ScoreSummary
    let planSegments: [DailyRingSegment]
    let actualSegments: [DailyRingSegment]
    let persona: DailyPersona
    let categoryRows: [(category: Category, duration: TimeInterval)]
    let onShare: (() -> Void)?
    let onPlanTomorrow: (() -> Void)?

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
                    .foregroundStyle(LiminalTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(persona.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DailyFactStrip(facts: persona.facts)

            if !categoryRows.isEmpty {
                DailyCategoryConstellation(rows: Array(categoryRows.prefix(4)))
            }

            if onShare != nil || onPlanTomorrow != nil {
                actionButtons
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LiminalTheme.cardGradient)
                .overlay(LiminalGrainOverlay().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(LiminalTheme.dawn.opacity(0.26))
                        .frame(width: 180, height: 180)
                        .blur(radius: 46)
                        .offset(x: 62, y: -70)
                }
                .overlay(alignment: .topTrailing) {
                    if colorScheme == .light {
                        Circle()
                            .fill(LiminalTheme.reward.opacity(0.2))
                            .frame(width: 128, height: 128)
                            .blur(radius: 36)
                            .offset(x: 42, y: -44)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Circle()
                        .fill(LiminalTheme.dusk.opacity(0.24))
                        .frame(width: 220, height: 220)
                        .blur(radius: 56)
                        .offset(x: -88, y: 86)
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cardBorderGradient, lineWidth: colorScheme == .light ? 1.2 : 1)
        )
        .liminalAccentLight(in: RoundedRectangle(cornerRadius: 26, style: .continuous), intensity: colorScheme == .light ? 0.5 : 0.42)
        .shadow(color: LiminalTheme.dusk.opacity(0.2), radius: 24, y: 14)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let onShare {
            Button {
                onShare()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.caption.weight(.bold))
                    Text("カードを共有")
                        .font(.subheadline.weight(.bold))
                    Spacer(minLength: 8)
                    Text("9:16")
                        .font(.caption.weight(.black).monospacedDigit())
                }
                .foregroundStyle(LiminalTheme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .liminalGlassFill(in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("デイリーカードを画像で共有")
        }

        if let onPlanTomorrow {
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
                .foregroundStyle(LiminalTheme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(LiminalTheme.accent.opacity(0.16))
                        .overlay(Capsule(style: .continuous).stroke(LiminalTheme.accent.opacity(0.28), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("明日の予定へ移動")
        }
    }

    // 縁取り = 光を受けた金属の稜線。
    // ダーク: 暗地で白の中間点が稜線として光る（従来通り・変更しない）。
    // ライト: 左上＝明るいハイライト → 金の反射 → 右下＝暖かい陰、で金属のベベルを再現。
    private var cardBorderGradient: LinearGradient {
        if colorScheme == .light {
            return LinearGradient(
                colors: [
                    .white.opacity(0.95),
                    LiminalTheme.reward.opacity(0.5),
                    LiminalTheme.text.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [LiminalTheme.accent.opacity(0.52), .white.opacity(0.08), LiminalTheme.dusk.opacity(0.28)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Liminalog")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LiminalTheme.accent)
                    .textCase(.uppercase)
                Text(date.japaneseMonthDayWeekday)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }

            Spacer()

            Image(systemName: summary.plannedDuration > 0 ? "circle.dashed.inset.filled" : "circle.dashed")
                .font(.caption.weight(.bold))
                .foregroundStyle(LiminalTheme.text.opacity(0.88))
                .frame(width: 30, height: 30)
                .liminalGlassFill(in: Circle())
                .accessibilityLabel(summary.plannedDuration > 0 ? "予定と実績あり" : "実績のみ")
        }
    }
}

private struct DailyCardShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DailyCardActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct DailyShareCardView: View {
    let date: Date
    let summary: ScoreSummary
    let planSegments: [DailyRingSegment]
    let actualSegments: [DailyRingSegment]
    let persona: DailyPersona
    let categoryRows: [(category: Category, duration: TimeInterval)]

    var body: some View {
        ZStack {
            LiminalTheme.canvasGradient
                .overlay(LiminalGrainOverlay())

            DailyReflectionCardSurface(
                date: date,
                summary: summary,
                planSegments: planSegments,
                actualSegments: actualSegments,
                persona: persona,
                categoryRows: categoryRows,
                onShare: nil,
                onPlanTomorrow: nil
            )
            .padding(.horizontal, 16)
        }
        .frame(width: 360, height: 640)
    }
}

private struct DailyTwentyFourHourRing: View {
    @Environment(\.colorScheme) private var colorScheme
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
                        colors: centerGlowColors,
                        center: .center,
                        startRadius: centerGlowStartRadius,
                        endRadius: centerGlowEndRadius
                    )
                )
                .blur(radius: centerGlowBlurRadius)

            DailyRingCanvas(planSegments: planSegments, actualSegments: actualSegments)
                .padding(8)

            VStack(spacing: 7) {
                Image(systemName: persona.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(LiminalTheme.reward)
                    .frame(width: 48, height: 48)
                    .liminalGlassFill(in: Circle())
                    .liminalAccentLight(in: Circle(), intensity: colorScheme == .light ? 0.38 : 0.95)

                Text(hasScore ? "\(Int(score.rounded()))pt" : "-- pt")
                    .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(LiminalTheme.text)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var centerGlowColors: [Color] {
        if colorScheme == .light {
            return [
                LiminalTheme.dusk.opacity(0.12),
                LiminalTheme.accent.opacity(0.06),
                Color(hex: "#F8F3FF").opacity(0.08),
                .clear
            ]
        }

        return [
            LiminalTheme.accent.opacity(0.22),
            .clear
        ]
    }

    private var centerGlowStartRadius: CGFloat {
        colorScheme == .light ? 28 : 20
    }

    private var centerGlowEndRadius: CGFloat {
        colorScheme == .light ? 104 : 128
    }

    private var centerGlowBlurRadius: CGFloat {
        colorScheme == .light ? 3 : 8
    }
}

private struct DailyRingCanvas: View {
    @Environment(\.colorScheme) private var colorScheme
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
        context.stroke(path, with: .color(baseRingColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    private var baseRingColor: Color {
        if colorScheme == .light {
            return LiminalTheme.secondaryText.opacity(0.26)
        }
        return .white.opacity(0.08)
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

private struct DailyFactStrip: View {
    let facts: [DailyCardFact]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(facts) { fact in
                DailyFactPill(
                    title: fact.title,
                    value: fact.value,
                    suffix: fact.suffix,
                    systemImage: fact.systemImage
                )
            }
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
            .foregroundStyle(LiminalTheme.secondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.black).monospacedDigit())
                    .foregroundStyle(LiminalTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                if let suffix {
                    Text(suffix)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .liminalGlassFill(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .liminalAccentLight(in: RoundedRectangle(cornerRadius: 14, style: .continuous), intensity: 0.26)
    }
}

private struct DailyCategoryConstellation: View {
    let rows: [(category: Category, duration: TimeInterval)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("昨日の色")
                .font(.caption.weight(.black))
                .foregroundStyle(LiminalTheme.secondaryText)

            HStack(spacing: 8) {
                ForEach(rows, id: \.category.id) { row in
                    HStack(spacing: 6) {
                        Image(systemName: row.category.icon ?? "circle.fill")
                            .font(.caption2.weight(.bold))
                        Text(row.category.name)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(LiminalTheme.text)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(row.category.displayColor.opacity(0.24), in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).stroke(row.category.displayColor.opacity(0.42), lineWidth: 1))
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
