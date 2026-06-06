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
    private let latestSelectableDate: Date

    init(
        title: String = "期間を選択",
        granularity: PeriodRangeGranularity,
        anchorDate: Binding<Date>
    ) {
        self.title = title
        self.granularity = granularity
        self._anchorDate = anchorDate
        let periodStart = Self.periodStart(for: anchorDate.wrappedValue, granularity: granularity, calendar: .japanese)
        let latestSelectableDate = Self.periodStart(for: Date(), granularity: granularity, calendar: .japanese)
        self._pendingDate = State(initialValue: min(periodStart, latestSelectableDate))
        self.latestSelectableDate = latestSelectableDate
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

            pickerArea
                .padding(.horizontal, 18)

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

    @ViewBuilder
    private var pickerArea: some View {
        switch granularity {
        case .month:
            monthPickerArea
        case .day, .week, .year:
            rangePickerArea
        }
    }

    private var rangePickerArea: some View {
        Picker("", selection: $pendingDate) {
            ForEach(options) { option in
                Text(option.title)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(LiminalTheme.text)
                    .tag(option.date)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(height: 230)
        .clipped()
    }

    private var monthPickerArea: some View {
        HStack(spacing: 0) {
            Picker("", selection: monthYearSelection) {
                ForEach(Array(monthYearRange), id: \.self) { year in
                    Text(verbatim: "\(year)年")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(LiminalTheme.text)
                        .tag(year)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Picker("", selection: monthSelection) {
                ForEach(Array(selectableMonths), id: \.self) { month in
                    Text("\(month)月")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(LiminalTheme.text)
                        .tag(month)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .frame(height: 230)
        .clipped()
    }

    private var monthYearSelection: Binding<Int> {
        Binding(
            get: {
                calendar.component(.year, from: pendingDate)
            },
            set: { newYear in
                updatePendingMonthDate(
                    year: newYear,
                    month: min(calendar.component(.month, from: pendingDate), latestSelectableMonth(for: newYear))
                )
            }
        )
    }

    private var monthSelection: Binding<Int> {
        Binding(
            get: {
                calendar.component(.month, from: pendingDate)
            },
            set: { newMonth in
                updatePendingMonthDate(year: calendar.component(.year, from: pendingDate), month: newMonth)
            }
        )
    }

    private var monthYearRange: ClosedRange<Int> {
        let latestYear = calendar.component(.year, from: latestSelectableDate)
        return (latestYear - 5)...latestYear
    }

    private var selectableMonths: ClosedRange<Int> {
        1...latestSelectableMonth(for: calendar.component(.year, from: pendingDate))
    }

    private func latestSelectableMonth(for year: Int) -> Int {
        let latestYear = calendar.component(.year, from: latestSelectableDate)
        guard year >= latestYear else { return 12 }
        return calendar.component(.month, from: latestSelectableDate)
    }

    private func updatePendingMonthDate(year: Int, month: Int) {
        pendingDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? pendingDate
    }

    private var options: [PeriodRangeOption] {
        (-optionWindowPastCount...0).compactMap { offset in
            guard let date = date(byAddingOffset: offset, to: latestSelectableDate) else { return nil }
            return PeriodRangeOption(
                id: optionID(for: date),
                date: date,
                title: title(for: date)
            )
        }
    }

    private var optionWindowPastCount: Int {
        switch granularity {
        case .day:
            180
        case .week:
            104
        case .month:
            60
        case .year:
            5
        }
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
            return weekTitle(start: interval.start, end: end)
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

    private func weekTitle(start: Date, end: Date) -> String {
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        guard startYear == endYear else {
            return "\(startYear)年\(twoDigitMonthDay(start))-\(endYear)年\(twoDigitMonthDay(end))"
        }
        return "\(startYear)年\(twoDigitMonthDay(start))-\(twoDigitMonthDay(end))"
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
