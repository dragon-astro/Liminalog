import SwiftUI

enum PeriodRangeGranularity {
    case day
    case week
    case month
    case year
}

struct PeriodRangeSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let granularity: PeriodRangeGranularity
    @Binding var anchorDate: Date

    @State private var pendingDate: Date

    private let calendar = Calendar.japanese
    private let pastOptionCount = 18
    private let futureOptionCount = 3

    init(
        title: String = "期間を選択",
        granularity: PeriodRangeGranularity,
        anchorDate: Binding<Date>
    ) {
        self.title = title
        self.granularity = granularity
        self._anchorDate = anchorDate
        self._pendingDate = State(initialValue: Self.periodStart(for: anchorDate.wrappedValue, granularity: granularity, calendar: .japanese))
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule(style: .continuous)
                .fill(LiminalTheme.secondaryText.opacity(0.55))
                .frame(width: 44, height: 5)
                .padding(.top, 10)

            ZStack {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(LiminalTheme.text)

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(LiminalTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(LiminalTheme.elevated.opacity(0.8)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("閉じる")

                    Spacer()
                }
            }
            .padding(.horizontal, 18)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(options) { option in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    pendingDate = option.date
                                }
                            } label: {
                                PeriodRangeOptionRow(
                                    title: option.title,
                                    isSelected: isSelected(option.date)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(option.id)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                }
                .frame(maxHeight: 260)
                .onAppear {
                    proxy.scrollTo(optionID(for: pendingDate), anchor: .center)
                }
                .onChange(of: pendingDate) { _, newValue in
                    withAnimation(.snappy(duration: 0.22)) {
                        proxy.scrollTo(optionID(for: newValue), anchor: .center)
                    }
                }
            }

            Button {
                anchorDate = pendingDate
                dismiss()
            } label: {
                Text("確認")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule(style: .continuous).fill(LiminalTheme.accent))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 56)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.hidden)
    }

    private var selectedPeriodStart: Date {
        Self.periodStart(for: pendingDate, granularity: granularity, calendar: calendar)
    }

    private var options: [PeriodRangeOption] {
        (-pastOptionCount...futureOptionCount).compactMap { offset in
            guard let date = date(byAddingOffset: offset, to: selectedPeriodStart) else { return nil }
            return PeriodRangeOption(
                id: optionID(for: date),
                date: date,
                title: title(for: date)
            )
        }
    }

    private func isSelected(_ date: Date) -> Bool {
        optionID(for: date) == optionID(for: pendingDate)
    }

    private func optionID(for date: Date) -> String {
        let start = Self.periodStart(for: date, granularity: granularity, calendar: calendar)
        let year = calendar.component(.year, from: start)
        switch granularity {
        case .day:
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: start) ?? 0
            return "day-\(year)-\(dayOfYear)"
        case .week:
            let week = calendar.component(.weekOfYear, from: start)
            return "week-\(year)-\(week)-\(Int(start.timeIntervalSinceReferenceDate))"
        case .month:
            return "month-\(year)-\(calendar.component(.month, from: start))"
        case .year:
            return "year-\(year)"
        }
    }

    private func date(byAddingOffset offset: Int, to date: Date) -> Date? {
        switch granularity {
        case .day:
            return calendar.date(byAdding: .day, value: offset, to: date)
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: offset, to: date)
        case .month:
            return calendar.date(byAdding: .month, value: offset, to: date)
        case .year:
            return calendar.date(byAdding: .year, value: offset, to: date)
        }
    }

    private func title(for date: Date) -> String {
        switch granularity {
        case .day:
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            return "\(year)年\(month)月\(day)日"
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 24 * 60 * 60)
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(twoDigitMonthDay(interval.start))-\(twoDigitMonthDay(end))"
        case .month:
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            return "\(year)年\(month)月"
        case .year:
            return "\(calendar.component(.year, from: date))年"
        }
    }

    private func twoDigitMonthDay(_ date: Date) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%02d/%02d", month, day)
    }

    private static func periodStart(
        for date: Date,
        granularity: PeriodRangeGranularity,
        calendar: Calendar
    ) -> Date {
        switch granularity {
        case .day:
            return DayBoundary.dayStart(for: date, calendar: calendar)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? DayBoundary.dayStart(for: date, calendar: calendar)
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        case .year:
            return calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        }
    }
}

private struct PeriodRangeOption: Identifiable {
    let id: String
    let date: Date
    let title: String
}

private struct PeriodRangeOptionRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.title3.weight(isSelected ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(isSelected ? LiminalTheme.text : LiminalTheme.secondaryText.opacity(0.62))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? LiminalTheme.surface.opacity(0.78) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? LiminalTheme.accent : Color.clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
