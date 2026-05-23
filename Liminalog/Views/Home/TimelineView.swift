import SwiftUI
import Combine

let currentTimeMarkerID = "current-time-marker"

struct TimelineView: View {
    @Environment(ChapterStore.self) private var store
    let date: Date
    let title: String
    var compactEmptyState = false
    @Binding var editingChapter: Chapter?
    var onAddChapter: ((Date) -> Void)?

    @State private var chapters: [Chapter] = []
    @State private var plans: [PlanBlock] = []
    @State private var now = Date()
    @State private var displayedRevision = 0

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let planLaneWidth: CGFloat = 96

    private var hourHeight: CGFloat {
        compactEmptyState ? 44 : 56
    }

    private var timelineHeight: CGFloat {
        hourHeight * 24
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                Spacer()
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            if plans.isEmpty && chapters.isEmpty {
                Text("まだ記録がありません")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compactEmptyState ? 10 : 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onAddChapter?(defaultChapterStart)
                    }
            } else {
                proportionalTimeline
            }
        }
        .id(displayedRevision)
        .onAppear { refresh() }
        .onChange(of: store.activeChapter?.id) { _, _ in refresh() }
        .onChange(of: store.revision) { _, _ in refresh() }
        .onChange(of: date) { _, _ in refresh() }
        .onReceive(timer) { date in
            now = date
            if store.activeChapter != nil {
                refresh()
            }
        }
    }

    private var proportionalTimeline: some View {
        HStack(alignment: .top, spacing: 10) {
            TimeAxis(hourHeight: hourHeight)

            ZStack(alignment: .topLeading) {
                HourGrid(hourHeight: hourHeight)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        onAddChapter?(date(at: location.y))
                    }

                ForEach(plans) { plan in
                    HStack {
                        Spacer(minLength: 0)
                        TimelinePlanLaneBlock(plan: plan, showsLabel: blockHeight(start: plan.startTime, end: plan.endTime) >= 34)
                            .frame(width: planLaneWidth)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: blockHeight(start: plan.startTime, end: plan.endTime))
                    .offset(y: yOffset(for: plan.startTime))
                    .padding(.trailing, 4)
                }

                ForEach(chapters) { chapter in
                    Button {
                        editingChapter = chapter
                    } label: {
                        TimelineActualBlock(
                            chapter: chapter,
                            matchedPlan: matchedPlan(for: chapter)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(height: blockHeight(start: chapter.startTime, end: chapter.endTime ?? now))
                    .offset(y: yOffset(for: chapter.startTime))
                    .padding(.leading, 4)
                    .padding(.trailing, planLaneWidth + 12)
                    .contextMenu {
                        Button {
                            editingChapter = chapter
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.deleteChapter(chapter)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }

                if Calendar.current.isDateInToday(date) {
                    CurrentTimeLine()
                        .offset(y: yOffset(for: now))
                        .id(currentTimeMarkerID)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: timelineHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private func yOffset(for start: Date) -> CGFloat {
        CGFloat(clippedMinutes(fromStartOfDay: start)) / 60 * hourHeight
    }

    private func blockHeight(start: Date, end: Date) -> CGFloat {
        let startMinute = clippedMinutes(fromStartOfDay: start)
        let endMinute = max(clippedMinutes(fromStartOfDay: end), startMinute + 1)
        let rawHeight = CGFloat(endMinute - startMinute) / 60 * hourHeight
        return max(rawHeight, 18)
    }

    private func clippedMinutes(fromStartOfDay target: Date) -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let clipped = min(max(target, startOfDay), endOfDay)
        return Int(clipped.timeIntervalSince(startOfDay) / 60)
    }

    private var defaultChapterStart: Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return Date()
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private func date(at yPosition: CGFloat) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let minutes = Int((max(0, min(yPosition, timelineHeight)) / hourHeight * 60).rounded())
        return calendar.date(byAdding: .minute, value: minutes, to: startOfDay) ?? defaultChapterStart
    }

    private func refresh() {
        chapters = timelineChapters()
        plans = store.plannedBlocks(on: date).filter { !$0.isAllDay }
        displayedRevision = store.revision
    }

    private func timelineChapters() -> [Chapter] {
        var fetched = store.chapters(on: date)
        if let active = store.activeChapter, intersectsDisplayDate(active), !fetched.contains(where: { $0.id == active.id }) {
            fetched.append(active)
        }
        return fetched.sorted { $0.startTime < $1.startTime }
    }

    private func intersectsDisplayDate(_ chapter: Chapter) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return chapter.startTime < endOfDay && (chapter.endTime ?? now) > startOfDay
    }

    private func matchedPlan(for chapter: Chapter) -> PlanBlock? {
        plans.first { plan in
            matches(chapter: chapter, plan: plan)
        }
    }

    private func matches(chapter: Chapter, plan: PlanBlock) -> Bool {
        guard chapter.category?.id == plan.category?.id else { return false }
        let chapterEnd = chapter.endTime ?? Date()
        return chapter.startTime < plan.endTime && chapterEnd > plan.startTime
    }
}

private struct TimeAxis: View {
    let hourHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(hour.isMultiple(of: 3) ? .secondary : .tertiary)
                    .frame(width: 42, height: hourHeight, alignment: .topTrailing)
            }
        }
        .padding(.top, 1)
    }
}

private struct HourGrid: View {
    let hourHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: hourHeight)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(hour.isMultiple(of: 3) ? Color(.separator).opacity(0.34) : Color(.separator).opacity(0.14))
                            .frame(height: 1)
                    }
            }
        }
    }
}

private struct CurrentTimeLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity)
        .shadow(color: Color.accentColor.opacity(0.25), radius: 3)
        .accessibilityLabel("現在時刻")
    }
}

private struct TimelinePlanLaneBlock: View {
    let plan: PlanBlock
    let showsLabel: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.58))
                .frame(width: 6)
                .padding(.vertical, 1)

            if showsLabel {
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.category?.name ?? plan.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text("\(plan.startTime.shortTime)-\(plan.endTime.shortTime)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(.top, 3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(showsLabel ? 0.08 : 0.05))
                .frame(maxWidth: showsLabel ? .infinity : 18)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(showsLabel ? 0.16 : 0.1), lineWidth: 1)
                .frame(maxWidth: showsLabel ? .infinity : 18)
        }
        .accessibilityLabel("\(plan.category?.name ?? plan.title) \(plan.startTime.shortTime)-\(plan.endTime.shortTime)")
        .contextMenu {
            Label(plan.title, systemImage: "calendar")
            Label("\(plan.startTime.shortTime)-\(plan.endTime.shortTime)", systemImage: "clock")
        }
        .padding(.vertical, 1)
    }

    private var color: Color {
        plan.category?.color ?? Color(.systemGray3)
    }
}

private struct TimelineActualBlock: View {
    let chapter: Chapter
    let matchedPlan: PlanBlock?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(chapter.category?.name ?? "未分類")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .lineLimit(1)

                    if matchedPlan != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color.opacity(0.72))
                            .accessibilityLabel("予定と一致")
                    }

                    Spacer(minLength: 4)

                    Text(timeText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let note = chapter.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 5)
                .padding(.vertical, 5)
                .padding(.leading, 4)
        }
    }

    private var color: Color {
        chapter.category?.color ?? Color(.systemGray3)
    }

    private var timeText: String {
        if let end = chapter.endTime {
            return "\(chapter.startTime.shortTime)-\(end.shortTime)"
        }
        return "\(chapter.startTime.shortTime)-"
    }
}
