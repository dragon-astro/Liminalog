import SwiftUI
import UIKit

struct DailyReflectionCard: View {
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

            Button {
                shareItem = renderShareImage()
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
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.075))
                        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("デイリーカードを画像で共有")

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
                        .fill(LiminalTheme.primary.opacity(0.16))
                        .overlay(Capsule(style: .continuous).stroke(LiminalTheme.primary.opacity(0.28), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("明日の予定へ移動")
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
                .stroke(
                    LinearGradient(
                        colors: [LiminalTheme.primary.opacity(0.52), .white.opacity(0.08), LiminalTheme.dusk.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: LiminalTheme.dusk.opacity(0.2), radius: 24, y: 14)
        .accessibilityElement(children: .contain)
        .sheet(item: $shareItem) { item in
            DailyCardActivityView(activityItems: [item.url])
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Liminalog")
                    .font(.caption.weight(.black))
                    .foregroundStyle(LiminalTheme.primary)
                    .textCase(.uppercase)
                Text(date.japaneseMonthDayWeekday)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: summary.plannedDuration > 0 ? "circle.dashed.inset.filled" : "circle.dashed")
                    .font(.caption.weight(.bold))
                Text(summary.plannedDuration > 0 ? "予定と実績" : "実績のみ")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(LiminalTheme.text.opacity(0.88))
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
                color: plan.category?.displayColor ?? LiminalTheme.primary
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
                color: chapter.category?.displayColor ?? LiminalTheme.primary
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
            categoryRows: Array(categoryRows.prefix(5))
        )
        .frame(width: 1080, height: 1920)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
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
                .overlay {
                    Circle()
                        .fill(LiminalTheme.dawn.opacity(0.18))
                        .frame(width: 720, height: 720)
                        .blur(radius: 110)
                        .offset(x: 330, y: -600)
                }
                .overlay {
                    Circle()
                        .fill(LiminalTheme.dusk.opacity(0.28))
                        .frame(width: 900, height: 900)
                        .blur(radius: 140)
                        .offset(x: -420, y: 610)
                }
                .overlay(LiminalGrainOverlay())

            VStack(alignment: .leading, spacing: 58) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Liminalog")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(LiminalTheme.primary)
                        Text(date.japaneseMonthDayWeekday)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(LiminalTheme.secondaryText)
                    }
                    Spacer()
                    Text(summary.plannedDuration > 0 ? "予定と実績" : "実績のみ")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(LiminalTheme.text)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                }

                DailyTwentyFourHourRing(
                    planSegments: planSegments,
                    actualSegments: actualSegments,
                    score: summary.totalScore,
                    hasScore: summary.plannedDuration > 0,
                    persona: persona
                )
                .frame(width: 760, height: 760)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 22) {
                    Text(persona.title)
                        .font(.system(size: 82, weight: .heavy, design: .rounded))
                        .foregroundStyle(LiminalTheme.text)
                        .minimumScaleFactor(0.55)
                        .lineLimit(2)

                    Text(persona.message)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 18) {
                    ForEach(persona.facts) { fact in
                        ShareMetricTile(title: fact.title, value: fact.value + (fact.suffix ?? ""))
                    }
                }

                if !categoryRows.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("昨日の色")
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .foregroundStyle(LiminalTheme.secondaryText)
                        FlowLikeCategoryRow(rows: categoryRows)
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    Text("予定と実績のあいだを、記録する。")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(LiminalTheme.secondaryText)
                    Spacer()
                    Text("liminalog")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(LiminalTheme.primary)
                }
            }
            .padding(.horizontal, 72)
            .padding(.top, 84)
            .padding(.bottom, 72)
        }
    }
}

private struct ShareMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(LiminalTheme.secondaryText)
            Text(value)
                .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(LiminalTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
    }
}

private struct FlowLikeCategoryRow: View {
    let rows: [(category: Category, duration: TimeInterval)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows, id: \.category.id) { row in
                HStack(spacing: 14) {
                    Image(systemName: row.category.icon ?? "circle.fill")
                        .font(.system(size: 21, weight: .bold))
                    Text(row.category.name)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .lineLimit(1)
                    Spacer()
                    Text(formatDailyDuration(row.duration))
                        .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(row.category.displayColor.liminalContrastingTextColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(row.category.displayColor, in: Capsule(style: .continuous))
            }
        }
    }
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
                        colors: [LiminalTheme.primary.opacity(0.22), .clear],
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
                    .foregroundStyle(LiminalTheme.reward)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))

                Text(hasScore ? "\(Int(score.rounded()))pt" : "-- pt")
                    .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(LiminalTheme.text)

                Text(hasScore ? "予定との重なり" : "予定なしの日")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(LiminalTheme.secondaryText)
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
