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
    private let optionCenterDate: Date

    init(
        title: String = "期間を選択",
        granularity: PeriodRangeGranularity,
        anchorDate: Binding<Date>
    ) {
        self.title = title
        self.granularity = granularity
        self._anchorDate = anchorDate
        let periodStart = Self.periodStart(for: anchorDate.wrappedValue, granularity: granularity, calendar: .japanese)
        self._pendingDate = State(initialValue: periodStart)
        self.optionCenterDate = periodStart
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

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LiminalTheme.accent, lineWidth: 2)
                    .frame(height: 58)
                    .padding(.horizontal, 28)
                    .allowsHitTesting(false)

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

    private var options: [PeriodRangeOption] {
        (-optionWindow.past...optionWindow.future).compactMap { offset in
            guard let date = date(byAddingOffset: offset, to: optionCenterDate) else { return nil }
            return PeriodRangeOption(
                id: optionID(for: date),
                date: date,
                title: title(for: date)
            )
        }
    }

    private var optionWindow: (past: Int, future: Int) {
        switch granularity {
        case .day:
            (180, 30)
        case .week:
            (104, 12)
        case .month:
            (60, 12)
        case .year:
            (5, 1)
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
