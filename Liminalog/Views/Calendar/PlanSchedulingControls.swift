import SwiftUI
import UserNotifications

struct PlanRecurrenceControls: View {
    @Binding var rule: PlanRecurrenceRule?
    var initialDate: Date = Date()
    @State private var isEnabled: Bool
    @State private var scheduleExpanded = false
    @State private var occurrenceCountText = "10"
    @FocusState private var countIsFocused: Bool

    init(rule: Binding<PlanRecurrenceRule?>, initialDate: Date = Date()) {
        self._rule = rule
        self.initialDate = initialDate
        self._isEnabled = State(initialValue: rule.wrappedValue != nil)
    }

    private var value: Binding<PlanRecurrenceRule> {
        Binding(get: { rule ?? PlanRecurrenceRule(startDate: initialDate) }, set: {
            // Removed date/count controls can finish editing after the switch is off.
            guard isEnabled, rule != nil else { return }
            rule = $0
        })
    }
    private var ending: Binding<Int> {
        Binding(get: { rule?.occurrenceLimit != nil ? 2 : rule?.endDate != nil ? 1 : 0 }, set: { mode in
            var updated = value.wrappedValue
            let currentMode = updated.occurrenceLimit != nil ? 2 : updated.endDate != nil ? 1 : 0
            guard mode != currentMode else { return }
            updated.occurrenceLimit = mode == 2 ? 10 : nil
            updated.endDate = mode == 1 ? Calendar.current.date(byAdding: .month, value: 1, to: updated.startDate) : nil
            updated.endDateIncludesTime = mode == 1 ? true : nil
            value.wrappedValue = updated
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("繰り返し", systemImage: "repeat")
                Spacer()
                InformationButton(title: "繰り返し", explanation: "自動で入った予定は、その日ごとに自由に編集・削除できます。元の設定や他の日は変わりません。元の変更は未調整の今後の予定だけに反映し、オフにすると取り消します。\n\n日付指定では開始日と同じ日を使い、31日や2月29日など存在しない日は飛ばします。第2・第4のように複数選べます。「最終」はその月の最後の曜日です。")
                Toggle("繰り返し", isOn: $isEnabled)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("plan-recurrence-enabled")
            }
            if rule != nil {
                Picker("周期", selection: value.frequency) {
                    ForEach(PlanRecurrenceRule.Frequency.allCases) { frequency in
                        Text("毎\(frequency.title)").tag(frequency)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("plan-recurrence-frequency")
                switch value.wrappedValue.frequency {
                case .weekly: weekdayButtons
                case .monthly: monthlyControls
                case .yearly:
                    Text("毎年\(value.wrappedValue.startDate.japaneseMonthDay)（開始日と同じ日）")
                        .font(.caption).foregroundStyle(LiminalTheme.secondaryText)
                case .daily: EmptyView()
                }
                scheduleHeader
                if scheduleExpanded { scheduleControls }
            }
        }
        // Keep the native switch bound to stable Boolean state while its details
        // enter/leave the hierarchy, rather than rebuilding an optional-to-Bool binding.
        .onChange(of: isEnabled) { _, enabled in
            rule = enabled ? (rule ?? PlanRecurrenceRule(startDate: initialDate)) : nil
            if !enabled { scheduleExpanded = false }
        }
        .onChange(of: rule != nil) { _, enabled in
            if isEnabled != enabled { isEnabled = enabled }
        }
        .onChange(of: rule?.startDate) { _, _ in
            if let end = rule?.endDate, let start = rule?.startDate,
               Calendar.current.startOfDay(for: end) < Calendar.current.startOfDay(for: start) { rule?.endDate = start }
        }
    }

    private var scheduleSummary: String {
        let rule = value.wrappedValue
        return "\(rule.cadence) · \(rule.startDate.japaneseMonthDay)から · \(rule.endingSummary)"
    }

    private var scheduleHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { scheduleExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("間隔・開始日・終了").fixedSize()
                        Spacer(minLength: 12)
                        Text(scheduleSummary).foregroundStyle(LiminalTheme.secondaryText).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("間隔・開始日・終了")
                        Text(scheduleSummary).font(.caption).foregroundStyle(LiminalTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
                .foregroundStyle(LiminalTheme.text)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(scheduleExpanded ? 90 : 0))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("間隔・開始日・終了")
        .accessibilityValue(scheduleSummary)
        .accessibilityHint(scheduleExpanded ? "詳細を閉じる" : "詳細を開く")
        .accessibilityIdentifier("plan-recurrence-schedule-details")
    }

    private var scheduleControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Stepper(value: value.interval, in: 1...365) {
                HStack {
                    Text("間隔")
                    Spacer()
                    Text(value.wrappedValue.cadence).foregroundStyle(LiminalTheme.secondaryText)
                }
            }
            .accessibilityIdentifier("plan-recurrence-interval")
            DatePicker("開始日", selection: value.startDate, displayedComponents: .date)
            HStack {
                Text("終了")
                InformationButton(title: "繰り返しの終了", explanation: "回数は開始日から数え、一日プリセットは一日分で1回です。削除した日や重複で追加を見送った日も含みます。日時指定では、その日時までに始まる予定を用意します。")
                Spacer()
                Menu {
                    Picker("終了", selection: ending) {
                        Text("しない").tag(0)
                        Text("日時").tag(1)
                        Text("回数").tag(2)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(["しない", "日時", "回数"][ending.wrappedValue])
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundStyle(LiminalTheme.text)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("終了")
                .accessibilityValue(["しない", "日時", "回数"][ending.wrappedValue])
                .accessibilityIdentifier("plan-recurrence-ending")
            }
            if ending.wrappedValue == 1 {
                DatePicker("終了日時", selection: Binding(get: {
                    guard let end = value.wrappedValue.endDate else { return initialDate }
                    if value.wrappedValue.endDateIncludesTime == true { return end }
                    return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: end) ?? end
                }, set: { value.wrappedValue.endDate = $0; value.wrappedValue.endDateIncludesTime = true }),
                in: Calendar.current.startOfDay(for: value.wrappedValue.startDate)...,
                displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier("plan-recurrence-end-date")
            } else if ending.wrappedValue == 2 {
                HStack {
                    Text("繰り返す回数")
                    Spacer()
                    TextField("回数", text: $occurrenceCountText)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 75)
                        .focused($countIsFocused)
                        .onAppear { occurrenceCountText = String(value.wrappedValue.occurrenceLimit ?? 10) }
                        .onChange(of: occurrenceCountText) { _, text in
                            let digits = String(text.filter(\.isNumber).prefix(5))
                            if text != digits { occurrenceCountText = digits }
                            if let count = Int(digits), count > 0 {
                                value.wrappedValue.occurrenceLimit = min(10_000, count)
                            }
                        }
                        .onChange(of: countIsFocused) { _, focused in
                            if !focused { occurrenceCountText = String(value.wrappedValue.occurrenceLimit ?? 10) }
                        }
                        .accessibilityIdentifier("plan-recurrence-count")
                    Text("回")
                }
            }
        }
    }

    private var weekdayButtons: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let selected = selectedWeekdays.contains(weekday)
                Button {
                    var days = selectedWeekdays
                    if selected && days.count > 1 { days.removeAll { $0 == weekday } }
                    else if !selected { days.append(weekday) }
                    value.wrappedValue.weekdays = days.sorted()
                } label: {
                    Text(["日", "月", "火", "水", "木", "金", "土"][weekday - 1])
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .modifier(RecurrenceChoiceStyle(selected: selected, shape: Circle()))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(["日", "月", "火", "水", "木", "金", "土"][weekday - 1])曜日")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
    private var monthlyControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthlyOption(.dayOfMonth, title: "毎月\(Calendar.current.component(.day, from: value.wrappedValue.startDate))日", detail: "開始日と同じ日")
            monthlyOption(.ordinalWeekday, title: "曜日で指定")
            if value.wrappedValue.monthlyMode == .ordinalWeekday {
                VStack(spacing: 10) {
                    ordinalButtons
                    monthlyWeekdayButtons
                }
                .padding(.leading, 28)
                .padding(.top, 4)
            }
        }
    }

    private func monthlyOption(_ mode: PlanRecurrenceRule.MonthlyMode, title: String, detail: String? = nil) -> some View {
        let selected = value.wrappedValue.monthlyMode == mode
        return Button {
            value.wrappedValue.monthlyMode = mode
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(selected ? LiminalTheme.accent : LiminalTheme.divider, lineWidth: selected ? 5 : 1.5)
                    .frame(width: 18, height: 18)
                Text(title).font(.subheadline).foregroundStyle(LiminalTheme.text)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(LiminalTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(mode == .dayOfMonth ? "plan-recurrence-monthly-mode" : "plan-recurrence-monthly-weekday-option")
    }

    /// 週の指定は複数選べる（第2・第4 など）。最後の1つは外せない。
    private var ordinalButtons: some View {
        HStack(spacing: 6) {
            ForEach(PlanRecurrenceRule.MonthlyOrdinal.allCases) { ordinal in
                let selected = value.wrappedValue.monthlyOrdinals.contains(ordinal)
                Button {
                    var ordinals = value.wrappedValue.monthlyOrdinals
                    if selected && ordinals.count > 1 { ordinals.removeAll { $0 == ordinal } }
                    else if !selected { ordinals.append(ordinal) }
                    value.wrappedValue.monthlyOrdinals = PlanRecurrenceRule.MonthlyOrdinal.allCases.filter { ordinals.contains($0) }
                } label: {
                    Text(ordinal.title)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .modifier(RecurrenceChoiceStyle(selected: selected, shape: Capsule()))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ordinal == .last ? "最終週" : "\(ordinal.title)週")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityIdentifier("plan-recurrence-monthly-ordinals")
    }

    /// 曜日は1つだけ選ぶ。見た目は毎週の曜日ボタンと同じ。
    private var monthlyWeekdayButtons: some View {
        let current = value.wrappedValue.selectedMonthlyWeekday()
        return HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let selected = weekday == current
                Button {
                    value.wrappedValue.monthlyWeekday = weekday
                } label: {
                    Text(["日", "月", "火", "水", "木", "金", "土"][weekday - 1])
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .modifier(RecurrenceChoiceStyle(selected: selected, shape: Circle()))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(["日", "月", "火", "水", "木", "金", "土"][weekday - 1])曜日")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityIdentifier("plan-recurrence-monthly-weekday")
    }

    private var selectedWeekdays: [Int] {
        let days = value.wrappedValue.weekdays
        return days.isEmpty ? [Calendar.current.component(.weekday, from: value.wrappedValue.startDate)] : days
    }
}

private struct RecurrenceChoiceStyle<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let selected: Bool
    let shape: S

    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(selected ? .bold : .semibold))
            .foregroundStyle(selected ? LiminalTheme.accent : LiminalTheme.text)
            .background(selected ? LiminalTheme.accent.opacity(colorScheme == .dark ? 0.30 : 0.18) : LiminalTheme.elevated, in: shape)
            .overlay {
                shape.strokeBorder(
                    selected ? LiminalTheme.accent.opacity(0.75) : LiminalTheme.divider.opacity(0.7),
                    lineWidth: selected ? 1.5 : 1
                )
            }
    }
}

struct PlanReminderControls: View {
    @Binding var minutesBefore: Int?
    var absoluteDate: Binding<Date?> = .constant(nil)
    let isAllDay: Bool
    var startDate: Date? = nil
    @State private var denied = false
    @State private var customOffset = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("通知", systemImage: "bell")
                Spacer()
                Menu {
                    Button("なし") { select(nil) }
                    Section("よく使うタイミング") {
                        ForEach([0, 5, 10, 15, 30, 60], id: \.self) { choice($0) }
                    }
                    Menu("数時間前") { ForEach([120, 180, 360, 720], id: \.self) { choice($0) } }
                    Menu("数日・数週間前") { ForEach([1440, 2880, 10080, 20160, 40320], id: \.self) { choice($0) } }
                    if let startDate {
                        Button("日時を指定…") {
                            minutesBefore = nil
                            absoluteDate.wrappedValue = absoluteDate.wrappedValue ?? max(Date().addingTimeInterval(300), startDate.addingTimeInterval(-1800))
                        }
                    } else {
                        Button("時間を指定…") { customOffset = true; if minutesBefore == nil { minutesBefore = 90 } }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(PlanReminderTiming.label(minutes: minutesBefore, date: absoluteDate.wrappedValue, isAllDay: isAllDay))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }.font(.subheadline)
                }
                .accessibilityLabel("通知のタイミング")
                .accessibilityIdentifier("plan-reminder-picker")
            }
            if absoluteDate.wrappedValue != nil {
                DatePicker("通知する日時", selection: Binding(get: { absoluteDate.wrappedValue ?? Date() },
                    set: { absoluteDate.wrappedValue = $0 }), displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("plan-reminder-date")
                Text("予定を動かしても、この日時に通知します。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if customOffset || (minutesBefore.map { !PlanReminderTiming.presets.contains($0) } ?? false) {
                HStack {
                    Text("開始の")
                    TextField("分数", value: Binding(get: { abs(minutesBefore ?? 90) }, set: {
                        minutesBefore = min(5_256_000, max(0, $0)) * ((minutesBefore ?? 0) < 0 ? -1 : 1)
                    }), format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("plan-reminder-custom-minutes")
                    Picker("前後", selection: Binding(get: { (minutesBefore ?? 0) < 0 }, set: {
                        minutesBefore = abs(minutesBefore ?? 90) * ($0 ? -1 : 1)
                    })) { Text("分前").tag(false); Text("分後").tag(true) }
                }
            }
            if denied && (minutesBefore != nil || absoluteDate.wrappedValue != nil) {
                Text("通知が許可されていません。設定で許可すると通知を受け取れます。")
                    .font(.caption).foregroundStyle(.orange)
                Button("通知設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
        .onChange(of: minutesBefore) { _, _ in updateAuthorization() }
        .onChange(of: absoluteDate.wrappedValue) { _, _ in updateAuthorization() }
        .task {
            guard (minutesBefore != nil || absoluteDate.wrappedValue != nil), !LiminalogRuntime.isRunningUITests else { return }
            denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
        }
    }
    private func choice(_ minute: Int) -> some View {
        Button(PlanReminderTiming.label(minutes: minute, isAllDay: isAllDay)) { select(minute) }
    }
    private func select(_ minute: Int?) {
        absoluteDate.wrappedValue = nil; minutesBefore = minute; customOffset = false
    }
    private func updateAuthorization() {
        guard (minutesBefore != nil || absoluteDate.wrappedValue != nil), !LiminalogRuntime.isRunningUITests else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                denied = !((try? await center.requestAuthorization(options: [.alert, .sound])) ?? false)
            } else { denied = settings.authorizationStatus == .denied }
            if !denied { NotificationCenter.default.post(name: .planSchedulingChanged, object: nil) }
        }
    }
}
