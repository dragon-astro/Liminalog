import SwiftUI

struct CalendarView: View {
    @Environment(ChapterStore.self) private var store
    @State private var visibleMonth = Date()

    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 1), count: 7)
    private let calendar = Calendar.japanese
    private let weekdays = Calendar.japaneseShortWeekdaySymbols

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    monthHeader

                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(weekdays, id: \.self) { weekday in
                            Text(weekday)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(weekdayColor(weekday))
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(Color(.secondarySystemGroupedBackground))
                        }

                        ForEach(monthGridDates, id: \.self) { date in
                            NavigationLink {
                                CalendarDayView(date: date)
                            } label: {
                                CalendarMonthDayCell(
                                    date: date,
                                    visibleMonth: visibleMonth,
                                    chapters: store.chapters(on: date),
                                    plans: store.plannedBlocks(on: date)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color(.separator).opacity(0.32))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
                    )
                    .id(store.revision)
                }
                .padding(.horizontal, 0)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("カレンダー")
            .gesture(
                DragGesture(minimumDistance: 44)
                    .onEnded { value in
                        if value.translation.width < -60 {
                            shiftMonth(1)
                        } else if value.translation.width > 60 {
                            shiftMonth(-1)
                        }
                    }
            )
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(visibleMonth.japaneseYearMonth)
                    .font(.title2.bold())
                Text("\(visibleMonthChapters.count)件の記録 / \(visibleMonthPlans.count)件の予定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("今日") {
                visibleMonth = Date()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var monthGridDates: [Date] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)) ?? visibleMonth
        let weekdayOffset = calendar.component(.weekday, from: monthStart) - calendar.firstWeekday
        let normalizedOffset = (weekdayOffset + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -normalizedOffset, to: monthStart) ?? monthStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var visibleMonthChapters: [Chapter] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)) ?? visibleMonth
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return store.chapters(from: monthStart, to: monthEnd)
    }

    private var visibleMonthPlans: [PlanBlock] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)) ?? visibleMonth
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return store.plannedBlocks(from: monthStart, to: monthEnd)
    }

    private func shiftMonth(_ value: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func weekdayColor(_ weekday: String) -> Color {
        switch weekday {
        case "日": .red
        case "土": .blue
        default: .secondary
        }
    }
}

struct CalendarMonthDayCell: View {
    let date: Date
    let visibleMonth: Date
    let chapters: [Chapter]
    let plans: [PlanBlock]

    private var isToday: Bool {
        Calendar.japanese.isDateInToday(date)
    }

    private var isInVisibleMonth: Bool {
        Calendar.japanese.isDate(date, equalTo: visibleMonth, toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(Calendar.japanese.component(.day, from: date))")
                    .font(.caption.weight(isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? .white : dateNumberColor)
                    .frame(width: 22, height: 22)
                    .background {
                        if isToday {
                            Circle().fill(Color.accentColor)
                        }
                    }

                Spacer(minLength: 0)

                if chapters.contains(where: \.isActive) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(plans.prefix(2)) { plan in
                    CalendarPlanLabel(plan: plan)
                }

                ForEach(chapters.prefix(3)) { chapter in
                    CalendarEventLabel(chapter: chapter)
                }

                let overflow = max(chapters.count - 3, 0) + max(plans.count - 2, 0)
                if overflow > 0 {
                    Text("+\(overflow)件")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
        .background(
            Rectangle()
                .fill(isInVisibleMonth ? Color(.secondarySystemGroupedBackground) : Color(.tertiarySystemGroupedBackground).opacity(0.5))
        )
        .opacity(isInVisibleMonth ? 1 : 0.48)
    }

    private var dateNumberColor: Color {
        let weekday = Calendar.japanese.component(.weekday, from: date)
        if weekday == 1 {
            return .red
        }
        if weekday == 7 {
            return .blue
        }
        return .primary
    }
}

struct CalendarPlanLabel: View {
    let plan: PlanBlock

    var body: some View {
        Text(labelText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.72))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 15)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill((plan.category?.color ?? Color(.systemGray3)).opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke((plan.category?.color ?? Color(.systemGray3)).opacity(0.18), lineWidth: 1)
            )
    }

    private var labelText: String {
        "\(plan.startTime.shortTime) \(plan.title)"
    }
}

struct CalendarEventLabel: View {
    let chapter: Chapter

    var body: some View {
        Text(labelText)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 15)
            .padding(.horizontal, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill((chapter.category?.color ?? Color(.systemGray3)).opacity(0.12))
        )
    }

    private var labelText: String {
        let time = chapter.startTime.shortTime
        let category = chapter.category?.name ?? "未分類"
        if chapter.isActive {
            return "\(time) \(category)中"
        }
        return "\(time) \(category)"
    }
}

#Preview("Calendar") {
    CalendarView()
        .liminalogPreviewEnvironment()
}
