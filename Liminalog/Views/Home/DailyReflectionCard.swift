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

            DailyFactStrip(
                score: summary.totalScore,
                hasScore: summary.plannedDuration > 0,
                recordedDuration: recordedDuration,
                chapterCount: chapters.count
            )

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
            categoryRows: Array(categoryRows.prefix(5)),
            recordedDuration: recordedDuration,
            chapterCount: chapters.count
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
    let recordedDuration: TimeInterval
    let chapterCount: Int

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
                    ShareMetricTile(title: "スコア", value: summary.plannedDuration > 0 ? "\(Int(summary.totalScore.rounded()))pt" : "--")
                    ShareMetricTile(title: "実績", value: formatDailyDuration(recordedDuration))
                    ShareMetricTile(title: "切替", value: "\(chapterCount)回")
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

private struct DailyPersona {
    let title: String
    let message: String
    let symbol: String

    static func make(
        summary: ScoreSummary,
        chapters: [Chapter],
        historyChapters: [Chapter],
        categoryRows: [(category: Category, duration: TimeInterval)],
        dayBoundary: DayBoundary
    ) -> DailyPersona {
        let analysis = DailyPatternAnalysis(
            chapters: chapters,
            historyChapters: historyChapters,
            categoryRows: categoryRows,
            dayBoundary: dayBoundary
        )

        guard !chapters.isEmpty else {
            return DailyPersona(title: "行方不明の1日", message: "記録が薄い日。たぶん何かはしてた、という人類共通の強い気持ちだけ残りました。", symbol: "moon.dust.fill")
        }

        if summary.plannedDuration > 0, summary.totalScore >= 88 {
            let signal = analysis.signalMessage ?? "未来の自分が置いた予定に、現在の自分が珍しくちゃんと出席しました。えらい、これは事件。"
            return DailyPersona(title: "有言実行の人", message: signal, symbol: "checkmark.seal.fill")
        }

        if let focus = analysis.focusCategory, analysis.shape == .sprinter {
            return DailyPersona(
                title: "\(analysis.chronoPrefix)スプリンター",
                message: analysis.signalMessage ?? "\(focus.category.name)に\(formatDailyDuration(focus.duration))。寄り道する脳をなんとか椅子に縛った日です。",
                symbol: "bolt.fill"
            )
        }

        if analysis.shape == .zapping {
            return DailyPersona(
                title: "\(analysis.chronoPrefix)ザッピング",
                message: analysis.signalMessage ?? "\(chapters.count)回の切り替え。集中力は小分けパックでしたが、ちゃんと1日は組み上がっています。",
                symbol: "sparkles"
            )
        }

        if summary.plannedDuration == 0 {
            return DailyPersona(title: "風まかせ", message: analysis.signalMessage ?? "予定なしで流れた日。地図はなかったけど、足跡だけは妙にリアルです。", symbol: "wind")
        }

        return DailyPersona(
            title: "\(analysis.chronoPrefix)マラソナー",
            message: analysis.signalMessage ?? "派手な爆発はなし。代わりに、地味な前進をちゃんと積んだ日です。地味、でも強い。",
            symbol: "figure.run"
        )
    }
}

private struct DailyPatternAnalysis {
    enum Shape {
        case sprinter
        case marathon
        case zapping
    }

    let focusCategory: (category: Category, duration: TimeInterval)?
    let shape: Shape
    let chronoPrefix: String
    let signalMessage: String?

    init(
        chapters: [Chapter],
        historyChapters: [Chapter],
        categoryRows: [(category: Category, duration: TimeInterval)],
        dayBoundary: DayBoundary
    ) {
        let restCategoryIDs = Self.majorRestCategoryIDs(
            chapters: chapters,
            historyChapters: historyChapters,
            dayBoundary: dayBoundary
        )
        let nonRestRows = categoryRows.filter { !restCategoryIDs.contains($0.category.id) }
        let nonRestChapters = chapters.filter { chapter in
            guard let id = chapter.category?.id else { return true }
            return !restCategoryIDs.contains(id)
        }
        let effectiveChapters = nonRestChapters.isEmpty && !restCategoryIDs.isEmpty ? [] : (nonRestChapters.isEmpty ? chapters : nonRestChapters)

        self.focusCategory = nonRestRows.first ?? (restCategoryIDs.isEmpty ? categoryRows.first : nil)
        self.shape = Self.shape(for: effectiveChapters, focusCategory: focusCategory, dayBoundary: dayBoundary)
        self.chronoPrefix = Self.chronoPrefix(for: effectiveChapters, dayBoundary: dayBoundary)
        self.signalMessage = Self.signalMessage(
            focusCategory: focusCategory,
            categoryRows: categoryRows,
            historyChapters: historyChapters,
            dayBoundary: dayBoundary,
            excludedCategoryIDs: restCategoryIDs
        )
    }

    private static func majorRestCategoryIDs(
        chapters: [Chapter],
        historyChapters: [Chapter],
        dayBoundary: DayBoundary
    ) -> Set<UUID> {
        let calendar = Calendar.japanese
        let historyStart = calendar.date(byAdding: .day, value: -28, to: dayBoundary.dayStart) ?? dayBoundary.dayStart
        let historical = historyChapters.filter { chapter in
            chapter.startTime >= historyStart && chapter.startTime < dayBoundary.dayStart
        }
        let historicalDays = Set(historical.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) }).count
        let source = historicalDays >= 7 ? historical : chapters
        guard !source.isEmpty else { return [] }

        struct RestCandidate {
            var category: Category
            var totalLongBlocks = 0
            var presenceDays = Set<Date>()
            var longestTotal: TimeInterval = 0
            var blockCount = 0
        }

        var candidates: [UUID: RestCandidate] = [:]
        for chapter in source {
            guard let category = chapter.category else { continue }
            let duration = max(0, (chapter.endTime ?? dayBoundary.dayEnd).timeIntervalSince(chapter.startTime))
            guard duration >= 3 * 60 * 60 else { continue }
            let day = DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
            var candidate = candidates[category.id] ?? RestCandidate(category: category)
            candidate.totalLongBlocks += 1
            candidate.presenceDays.insert(day)
            candidate.longestTotal += duration
            candidate.blockCount += 1
            candidates[category.id] = candidate
        }

        return Set(candidates.compactMap { id, candidate in
            let averageLongBlock = candidate.longestTotal / Double(max(candidate.blockCount, 1))
            let dayBase = max(historicalDays, 1)
            let frequency = Double(candidate.presenceDays.count) / Double(dayBase)
            if historicalDays >= 7 {
                return frequency >= 0.42 && averageLongBlock >= 4 * 60 * 60 ? id : nil
            } else {
                return candidate.totalLongBlocks >= 1 && averageLongBlock >= 6 * 60 * 60 ? id : nil
            }
        })
    }

    private static func shape(
        for chapters: [Chapter],
        focusCategory: (category: Category, duration: TimeInterval)?,
        dayBoundary: DayBoundary
    ) -> Shape {
        let durations = chapters.map { chapter -> TimeInterval in
            let start = max(chapter.startTime, dayBoundary.dayStart)
            let end = min(chapter.endTime ?? dayBoundary.dayEnd, dayBoundary.dayEnd)
            return max(end.timeIntervalSince(start), 0)
        }
        let total = durations.reduce(0, +)
        let longest = max(durations.max() ?? 0, focusCategory?.duration ?? 0)
        let meaningfulSwitchCount = durations.filter { $0 >= 5 * 60 }.count
        let average = total / Double(max(meaningfulSwitchCount, 1))

        if meaningfulSwitchCount >= 8 || average <= 35 * 60 {
            return .zapping
        }
        if longest >= 150 * 60 && (total == 0 || longest / total >= 0.42) {
            return .sprinter
        }
        return .marathon
    }

    private static func chronoPrefix(for chapters: [Chapter], dayBoundary: DayBoundary) -> String {
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

    private static func signalMessage(
        focusCategory: (category: Category, duration: TimeInterval)?,
        categoryRows: [(category: Category, duration: TimeInterval)],
        historyChapters: [Chapter],
        dayBoundary: DayBoundary,
        excludedCategoryIDs: Set<UUID>
    ) -> String? {
        let calendar = Calendar.japanese
        let historyStart = calendar.date(byAdding: .day, value: -28, to: dayBoundary.dayStart) ?? dayBoundary.dayStart
        let historical = historyChapters.filter { chapter in
            chapter.startTime >= historyStart && chapter.startTime < dayBoundary.dayStart
        }
        let historyDays = Set(historical.map { DayBoundary.dayStart(for: $0.startTime, calendar: calendar) }).count
        guard historyDays >= 7 else {
            if let focusCategory {
                return "\(focusCategory.category.name)が\(formatDailyDuration(focusCategory.duration))。データはまだ少なめ、でも今日の主張だけはもう強いです。"
            }
            return nil
        }

        let todayRows = categoryRows.filter { !excludedCategoryIDs.contains($0.category.id) }
        var best: (category: Category, duration: TimeInterval, z: Double, mean: Double, daysSinceLast: Int?)?

        for row in todayRows where !excludedCategoryIDs.contains(row.category.id) {
            var dailyTotals: [Date: TimeInterval] = [:]
            var lastSeen: Date?
            for chapter in historical where chapter.category?.id == row.category.id {
                let day = DayBoundary.dayStart(for: chapter.startTime, calendar: calendar)
                let duration = max(0, (chapter.endTime ?? dayBoundary.dayStart).timeIntervalSince(chapter.startTime))
                dailyTotals[day, default: 0] += duration
                lastSeen = max(lastSeen ?? day, day)
            }

            let values = (0..<28).compactMap { offset -> TimeInterval? in
                guard let day = calendar.date(byAdding: .day, value: -offset - 1, to: dayBoundary.dayStart) else { return nil }
                return dailyTotals[day, default: 0]
            }
            let mean = values.reduce(0, +) / Double(max(values.count, 1))
            let variance = values.reduce(0) { partial, value in
                partial + pow(value - mean, 2)
            } / Double(max(values.count, 1))
            let std = max(sqrt(variance), 15 * 60)
            let z = (row.duration - mean) / std
            let daysSinceLast: Int? = lastSeen.map { calendar.dateComponents([.day], from: $0, to: dayBoundary.dayStart).day ?? 0 }
            let isSignal = abs(z) >= 1.5 || (daysSinceLast ?? 0) >= 10
            if isSignal, abs(z) > abs(best?.z ?? 0) || best == nil {
                best = (row.category, row.duration, z, mean, daysSinceLast)
            }
        }

        guard let best else { return nil }
        if let days = best.daysSinceLast, days >= 10 {
            return "\(days)日ぶりの\(best.category.name)。急に帰ってきたので、今日のカードが少しざわついています。"
        }
        if best.z > 0 {
            return "\(best.category.name)がいつもより多め。今日の自分、そこだけ急にボリューム上げてきました。"
        } else {
            return "\(best.category.name)はいつもより控えめ。空いた余白に、別の今日が入り込んでいます。"
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
