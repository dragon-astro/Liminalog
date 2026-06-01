import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var visibleMonth = CalendarView.currentMonthStart
    @State private var anchorMonth = CalendarView.currentMonthStart
    @State private var scrolledOffset: Int? = 0
    @State private var pageDataByMonth: [Date: CalendarMonthPageData] = [:]
    @State private var showingMonthPicker = false
    @State private var pickerYear = Calendar.japanese.component(.year, from: Date())
    @State private var pickerMonth = Calendar.japanese.component(.month, from: Date())
    @State private var showingCalendarSettings = false
    @State private var showingCalendarSearch = false
    @State private var selectedDay: CalendarDayPresentation?
    @State private var clock = TickClock(interval: 60)

    private let calendar = Calendar.japanese
    private let weekdays = Calendar.japaneseShortWeekdaySymbols
    /// 横スワイプで連続移動できる月の範囲（アンカー月からの相対オフセット）。LazyHStack で遅延描画するため広めでも軽い。
    private let monthOffsets = Array(-480...480)

    private static var currentMonthStart: Date {
        let cal = Calendar.japanese
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                calendarTopBar

                CalendarWeekdayHeader(
                    weekdays: weekdays,
                    weekdayColor: weekdayColor(_:)
                )

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(monthOffsets, id: \.self) { offset in
                            CalendarMonthGrid(
                                pageData: cachedPageData(for: month(forOffset: offset)),
                                onOpenDay: { date, planID in
                                    selectedDay = CalendarDayPresentation(date: date, planID: planID)
                                }
                            )
                            .padding(.vertical, 8)
                            .containerRelativeFrame(.horizontal)
                            .id(offset)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrolledOffset, anchor: .center)
                .defaultScrollAnchor(.center)
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity, alignment: .top)
                .onChange(of: scrolledOffset) { _, newValue in
                    handleScroll(to: newValue)
                }
            }
            .background(LiminalTheme.canvasGradient)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingMonthPicker) {
                CalendarMonthPickerSheet(
                    selectedYear: $pickerYear,
                    selectedMonth: $pickerMonth,
                    yearRange: calendarYearRange,
                    onCancel: {
                        showingMonthPicker = false
                    },
                    onDone: {
                        applyPickedMonth()
                        showingMonthPicker = false
                    }
                )
            }
            .sheet(isPresented: $showingCalendarSearch, onDismiss: reloadVisibleData) {
                CalendarPlanSearchSheet { plan in
                    jump(to: plan.startTime)
                    showingCalendarSearch = false
                    let target = CalendarDayPresentation(date: plan.startTime, planID: plan.id)
                    DispatchQueue.main.async {
                        selectedDay = target
                    }
                }
            }
            .sheet(isPresented: $showingCalendarSettings) {
                CalendarSettingsSheet()
            }
            .sheet(item: $selectedDay, onDismiss: reloadVisibleData) { target in
                NavigationStack {
                    CalendarDayPagerSheet(initialDate: target.date, highlightedPlanID: target.planID)
                }
                .presentationDetents([.large])
            }
            .onAppear {
                clock.start()
                reloadVisibleData()
            }
            .onDisappear {
                clock.stop()
            }
        }
    }

    private var calendarTopBar: some View {
        HStack(spacing: 12) {
            Button {
                showingCalendarSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)

            Button {
                prepareMonthPicker()
                showingMonthPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(visibleMonth.japaneseYearMonth)
                        .font(.title2.weight(.semibold))
                        .contentTransition(.numericText())

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(.tertiarySystemGroupedBackground))
                )
                .overlay(
                    Capsule()
                        .stroke(Color(.separator).opacity(0.34), lineWidth: 1)
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("表示月 \(visibleMonth.japaneseYearMonth)")

            Button {
                showingCalendarSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var calendarYearRange: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: Date())
        return (currentYear - 10)...(currentYear + 10)
    }

    private func prepareMonthPicker() {
        pickerYear = calendar.component(.year, from: visibleMonth)
        pickerMonth = calendar.component(.month, from: visibleMonth)
    }

    private func applyPickedMonth() {
        let components = DateComponents(year: pickerYear, month: pickerMonth, day: 1)
        jump(to: calendar.date(from: components) ?? visibleMonth)
    }

    private func monthGridDates(for month: Date) -> [Date] {
        let monthStart = monthStart(for: month)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let dayCount = calendar.dateComponents([.day], from: monthStart, to: monthEnd).day ?? 0
        let weekdayOffset = calendar.component(.weekday, from: monthStart) - calendar.firstWeekday
        let normalizedOffset = (weekdayOffset + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -normalizedOffset, to: monthStart) ?? monthStart
        let weekCount = max(5, min(6, Int(ceil(Double(normalizedOffset + dayCount) / 7.0))))
        return (0..<(weekCount * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    // MARK: - ページング / データ取得（遅延・月単位キャッシュ）

    private func month(forOffset offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: anchorMonth) ?? anchorMonth
    }

    private func offset(forMonth month: Date) -> Int {
        calendar.dateComponents([.month], from: anchorMonth, to: monthStart(for: month)).month ?? 0
    }

    /// スワイプで現在ページが変わったとき。表示月を更新し、隣接月を先読みする。
    private func handleScroll(to newValue: Int?) {
        guard let newValue else { return }
        let month = month(forOffset: newValue)
        if visibleMonth != month {
            visibleMonth = month
        }
        ensureData(around: newValue)
    }

    /// 月ピッカー・検索からの任意月ジャンプ。
    private func jump(to date: Date) {
        let targetMonth = monthStart(for: date)
        let targetOffset = offset(forMonth: targetMonth)
        visibleMonth = targetMonth
        ensureData(around: targetOffset)
        scrolledOffset = targetOffset
    }

    /// データ変更後（日編集シートを閉じた等）にキャッシュを破棄して現在月周辺を作り直す。
    private func reloadVisibleData() {
        pageDataByMonth.removeAll()
        ensureData(around: scrolledOffset ?? offset(forMonth: visibleMonth))
    }

    /// 指定オフセット周辺（±1）の月データを未計算なら計算してキャッシュする。
    private func ensureData(around offset: Int) {
        let now = clock.now
        for off in (offset - 1)...(offset + 1) {
            let key = monthStart(for: month(forOffset: off))
            if pageDataByMonth[key] == nil {
                pageDataByMonth[key] = computePageData(for: month(forOffset: off), now: now)
            }
        }
    }

    /// 描画時のフォールバック。未キャッシュ月でも即時に正しく描けるよう同期計算する。
    private func cachedPageData(for month: Date) -> CalendarMonthPageData {
        if let cached = pageDataByMonth[monthStart(for: month)] {
            return cached
        }
        return computePageData(for: month, now: clock.now)
    }

    /// 1ヶ月分のグリッドデータを、その月のグリッド範囲だけ自前で fetch して計算する。
    private func computePageData(for month: Date, now: Date) -> CalendarMonthPageData {
        let dates = monthGridDates(for: month)
        guard let gridStart = dates.first.map({ calendar.startOfDay(for: $0) }),
              let lastDate = dates.last,
              let gridEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDate))
        else {
            return CalendarMonthPageData(
                dates: dates,
                visibleMonth: month,
                importantPlansByDay: [:],
                scoreSummariesByDay: [:]
            )
        }

        let planDescriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < gridEnd && $0.endTime > gridStart },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let plansInGrid = ((try? modelContext.fetch(planDescriptor)) ?? []).sorted(by: planSort)

        let lookbackStart = calendar.date(byAdding: .day, value: -14, to: gridStart) ?? gridStart
        let chapterDescriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime >= lookbackStart && $0.startTime < gridEnd },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let activeDescriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime)]
        )
        var chapters = ((try? modelContext.fetch(chapterDescriptor)) ?? [])
            .filter { ($0.endTime ?? now) > gridStart }
        let activeChapters = ((try? modelContext.fetch(activeDescriptor)) ?? [])
            .filter { $0.startTime < gridEnd && ($0.endTime ?? now) > gridStart }
        let existingIDs = Set(chapters.map(\.id))
        chapters.append(contentsOf: activeChapters.filter { !existingIDs.contains($0.id) })
        let chaptersInGrid = chapters.sorted { $0.startTime < $1.startTime }

        var importantPlansByDay: [Date: [CalendarDisplayPlan]] = [:]
        var scoreSummariesByDay: [Date: CalendarDisplayScore] = [:]

        for date in dates {
            let boundary = DayBoundary(date: date, calendar: calendar)
            let dayPlans = plansInGrid.filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            let dayChapters = chaptersInGrid.filter {
                $0.startTime < boundary.dayEnd && ($0.endTime ?? now) > boundary.dayStart
            }
            // データのない日はスコアバッジも重要予定も出ないため、計算自体を省く。
            guard !dayPlans.isEmpty || !dayChapters.isEmpty else { continue }
            importantPlansByDay[boundary.dayStart] = dayPlans
                .filter(\.showsInCalendarAsImportant)
                .sorted(by: planSort)
                .map { CalendarDisplayPlan(plan: $0) }
            scoreSummariesByDay[boundary.dayStart] = CalendarDisplayScore(
                summary: ScoreCalculator.summary(
                    date: date,
                    plans: dayPlans,
                    chapters: dayChapters,
                    calendar: calendar,
                    now: now
                )
            )
        }

        return CalendarMonthPageData(
            dates: dates,
            visibleMonth: month,
            importantPlansByDay: importantPlansByDay,
            scoreSummariesByDay: scoreSummariesByDay
        )
    }

    private func planSort(_ lhs: PlanBlock, _ rhs: PlanBlock) -> Bool {
        if lhs.startTime == rhs.startTime {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.startTime < rhs.startTime
    }

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func weekdayColor(_ weekday: String) -> Color {
        switch weekday {
        case "日": .red
        case "土": .blue
        default: .secondary
        }
    }
}

private struct CalendarDayPagerSheet: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let highlightedPlanID: UUID?

    @State private var anchorDate: Date
    @State private var selectedOffset = 0
    @State private var pendingCreateDate: Date
    @State private var pendingPlanStartsAsImportant = false
    @State private var showingPlanSheet = false

    init(initialDate: Date, highlightedPlanID: UUID?) {
        self.initialDate = Calendar.japanese.startOfDay(for: initialDate)
        self.highlightedPlanID = highlightedPlanID
        _anchorDate = State(initialValue: Calendar.japanese.startOfDay(for: initialDate))
        _pendingCreateDate = State(initialValue: Calendar.japanese.startOfDay(for: initialDate))
    }

    var body: some View {
        TabView(selection: $selectedOffset) {
            ForEach([-1, 0, 1], id: \.self) { offset in
                CalendarDayView(
                    date: pageDate(offset),
                    highlightedPlanID: highlightedPlanID(for: pageDate(offset)),
                    showsNavigationControls: false,
                    allowsDayNavigation: false
                )
                .id(pageDate(offset).timeIntervalSince1970)
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: selectedOffset) { _, newValue in
            guard newValue != 0 else { return }
            settlePageShift(newValue)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                dayVisibilityMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        pendingCreateDate = Calendar.japanese.startOfDay(for: anchorDate)
                        pendingPlanStartsAsImportant = true
                        showingPlanSheet = true
                    } label: {
                        Label("重要な予定を追加", systemImage: "star")
                    }

                    if canCreateTimedPlansForDay {
                        Button {
                            pendingCreateDate = defaultPlanStart
                            pendingPlanStartsAsImportant = false
                            showingPlanSheet = true
                        } label: {
                            Label("時間つき予定を追加", systemImage: "calendar.badge.plus")
                        }
                    } else {
                        Label("今日以前の時間つき予定は追加できません", systemImage: "lock.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingPlanSheet) {
            PlanCreateSheet(initialDate: pendingCreateDate, startsAsAllDay: pendingPlanStartsAsImportant)
        }
    }

    private func pageDate(_ offset: Int) -> Date {
        Calendar.japanese.date(byAdding: .day, value: offset, to: anchorDate) ?? anchorDate
    }

    private func highlightedPlanID(for date: Date) -> UUID? {
        Calendar.japanese.isDate(date, inSameDayAs: initialDate) ? highlightedPlanID : nil
    }

    private func settlePageShift(_ offset: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            anchorDate = pageDate(offset)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedOffset = 0
            }
        }
    }

    private var dayVisibilityMenu: some View {
        let visibleDayChapters = dayChapters
        let allPublic = !visibleDayChapters.isEmpty && visibleDayChapters.allSatisfy(\.isPublic)
        let allPrivate = !visibleDayChapters.isEmpty && visibleDayChapters.allSatisfy { !$0.isPublic }
        let isMixed = !visibleDayChapters.isEmpty && !allPublic && !allPrivate

        return Menu {
            if visibleDayChapters.isEmpty {
                Text("この日にチャプターはありません")
            } else {
                if isMixed {
                    Text("公開/非公開が混在しています")
                        .font(.caption)
                }
                Button {
                    store.setChaptersVisibility(visibleDayChapters, isPublic: true)
                } label: {
                    Label("すべて公開", systemImage: "eye")
                }
                .disabled(allPublic)

                Button {
                    store.setChaptersVisibility(visibleDayChapters, isPublic: false)
                } label: {
                    Label("すべて非公開", systemImage: "eye.slash")
                }
                .disabled(allPrivate)

                Divider()
                Text("\(visibleDayChapters.count)件のチャプター")
                    .font(.caption)
            }
        } label: {
            Image(systemName: allPrivate ? "eye.slash" : (isMixed ? "eye.fill" : "eye"))
                .foregroundStyle(isMixed ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel("この日の公開設定")
        .disabled(visibleDayChapters.isEmpty)
    }

    private var dayChapters: [Chapter] {
        let boundary = DayBoundary(date: anchorDate, calendar: .japanese)
        return ScoreSnapshotLoader.chapters(
            in: DateInterval(start: boundary.dayStart, end: boundary.dayEnd),
            modelContext: modelContext,
            now: Date(),
            calendar: .japanese
        )
    }

    private var canCreateTimedPlansForDay: Bool {
        store.canCreatePlan(startTime: anchorDate, isAllDay: false)
    }

    private var defaultPlanStart: Date {
        if Calendar.japanese.isDateInToday(anchorDate) {
            return Date()
        }
        return Calendar.japanese.date(bySettingHour: 9, minute: 0, second: 0, of: anchorDate) ?? anchorDate
    }
}

private struct CalendarDayPresentation: Identifiable, Hashable {
    let date: Date
    let planID: UUID?

    var id: String {
        let day = Calendar.japanese.startOfDay(for: date).timeIntervalSince1970
        return "\(day)-\(planID?.uuidString ?? "day")"
    }
}

enum CalendarPlanLabelStyle: String, CaseIterable, Identifiable {
    case background
    case textOnly
    case underline

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .background:
            return "背景色"
        case .textOnly:
            return "文字色"
        case .underline:
            return "下線＋文字色"
        }
    }
}

struct CalendarSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CalendarSettingsContent()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

struct CalendarSettingsContent: View {
    @AppStorage("calendarTimedPlanLabelStyle") private var timedPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarAllDayPlanLabelStyle") private var allDayPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarMultiDayPlanLabelStyle") private var multiDayPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = 6.0
    @AppStorage("calendarPlanTitleBold") private var planTitleBold = false
    @AppStorage("calendarDimPastPlans") private var dimPastPlans = true
    @AppStorage("calendarStrikePastPlans") private var strikePastPlans = false

    var body: some View {
        Form {
            Section("予定") {
                CalendarLabelStyleSettingRow(
                    title: "時刻指定",
                    selectionRaw: $timedPlanLabelStyleRaw,
                    fontSize: planTitleFontSize,
                    isBold: planTitleBold,
                    sampleTime: "9:30"
                )

                CalendarLabelStyleSettingRow(
                    title: "終日",
                    selectionRaw: $allDayPlanLabelStyleRaw,
                    fontSize: planTitleFontSize,
                    isBold: planTitleBold,
                    sampleTime: nil
                )

                CalendarLabelStyleSettingRow(
                    title: "複数日",
                    selectionRaw: $multiDayPlanLabelStyleRaw,
                    fontSize: planTitleFontSize,
                    isBold: planTitleBold,
                    sampleTime: nil
                )
            }

            Section("フォント") {
                CalendarFontSizeSlider(value: $planTitleFontSize)
                Toggle("太字", isOn: $planTitleBold)
            }

            Section {
                Toggle("過去の予定を薄くする", isOn: $dimPastPlans)
                Toggle("打ち消し線を入れる", isOn: $strikePastPlans)
            } header: {
                Text("過去の予定")
            } footer: {
                Text("薄くしない場合も、打ち消し線は個別に選べます。")
            }
        }
        .navigationTitle("表示形式")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CalendarLabelStyleSettingRow: View {
    let title: String
    @Binding var selectionRaw: String
    let fontSize: Double
    let isBold: Bool
    let sampleTime: String?

    private let sampleColor = Color.blue
    private var selectedStyle: CalendarPlanLabelStyle {
        CalendarPlanLabelStyle(rawValue: selectionRaw) ?? .background
    }

    var body: some View {
        NavigationLink {
            CalendarLabelStyleSelectionView(
                title: title,
                selectionRaw: $selectionRaw,
                fontSize: fontSize,
                isBold: isBold,
                sampleTime: sampleTime,
                sampleColor: sampleColor
            )
        } label: {
            HStack(spacing: 16) {
                Text(title)
                    .font(.body.weight(.medium))

                Spacer(minLength: 12)

                CalendarLabelStylePreview(
                    style: selectedStyle,
                    color: sampleColor,
                    fontSize: previewFontSize,
                    isBold: true,
                    timeText: sampleTime
                )
                .frame(width: 128, height: 22, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private var previewFontSize: Double {
        sampleTime == nil ? 9 : 8
    }
}

private struct CalendarLabelStyleSelectionView: View {
    let title: String
    @Binding var selectionRaw: String
    let fontSize: Double
    let isBold: Bool
    let sampleTime: String?
    let sampleColor: Color

    var body: some View {
        Form {
            Section {
                ForEach(CalendarPlanLabelStyle.allCases) { style in
                    Button {
                        selectionRaw = style.rawValue
                    } label: {
                        HStack(spacing: 14) {
                            if selectionRaw == style.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .frame(width: 22)
                            } else {
                                Color.clear
                                    .frame(width: 22)
                            }

                            Text(style.label)
                                .foregroundStyle(.primary)

                            Spacer(minLength: 16)

                            CalendarLabelStylePreview(
                                style: style,
                                color: sampleColor,
                                fontSize: previewFontSize,
                                isBold: true,
                                timeText: sampleTime
                            )
                            .frame(width: 160, height: 24, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewFontSize: Double {
        sampleTime == nil ? 10 : 9
    }
}

private struct CalendarFontSizeSlider: View {
    @Binding var value: Double

    private let stepCount = 9

    var body: some View {
        HStack(spacing: 12) {
            Text("A")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 0) {
                Slider(value: $value, in: 5...9, step: 0.5)

                HStack {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Circle()
                            .fill(index == selectedStepIndex ? Color.accentColor : Color.secondary.opacity(0.42))
                            .frame(width: index == selectedStepIndex ? 5 : 3, height: index == selectedStepIndex ? 5 : 3)

                        if index < stepCount - 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, -2)
                .allowsHitTesting(false)
            }

            Text("A")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
        }
    }

    private var selectedStepIndex: Int {
        min(max(Int(((value - 5) / 0.5).rounded()), 0), stepCount - 1)
    }
}

private struct CalendarLabelStylePreview: View {
    let style: CalendarPlanLabelStyle
    let color: Color
    let fontSize: Double
    let isBold: Bool
    let timeText: String?

    var body: some View {
        HStack(spacing: 3) {
            if let timeText {
                Text(timeText)
                    .font(.system(size: max(4, fontSize - 1), weight: .medium, design: .rounded))
                    .foregroundStyle(timeColor)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Text("予定")
                .font(.system(size: fontSize, weight: isBold ? .bold : .regular))
                .foregroundStyle(titleColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(12, CGFloat(fontSize) + 5))
        .padding(.horizontal, 3)
        .background {
            if style == .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.18))
            }
        }
        .overlay {
            if style == .background {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color.opacity(0.34), lineWidth: 0.8)
            }
        }
        .overlay(alignment: .bottom) {
            if style == .underline {
                Rectangle()
                    .fill(color.opacity(0.28))
                    .frame(height: markerHeight)
                    .padding(.bottom, markerBottomPadding)
            }
        }
        .clipped()
    }

    private var titleColor: Color {
        style == .background ? .primary : color
    }

    private var timeColor: Color {
        style == .background ? .secondary : color.opacity(0.75)
    }

    private var markerHeight: CGFloat {
        max(4, CGFloat(fontSize) * 0.48)
    }

    private var markerBottomPadding: CGFloat {
        max(1, CGFloat(fontSize) * 0.08)
    }
}

struct CalendarMonthPickerSheet: View {
    @Binding var selectedYear: Int
    @Binding var selectedMonth: Int
    let yearRange: ClosedRange<Int>
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("年", selection: $selectedYear) {
                    ForEach(Array(yearRange), id: \.self) { year in
                        Text(verbatim: "\(year)年").tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("月", selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text("\(month)月").tag(month)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .navigationTitle("年月を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完了", action: onDone)
                }
            }
        }
        .presentationDetents([.height(280)])
    }
}

private struct CalendarPlanSearchSheet: View {
    let onOpenDay: (PlanBlock) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\PlanBlock.startTime)]) private var plans: [PlanBlock]
    @State private var query = ""
    @State private var editingPlan: PlanBlock?

    private let calendar = Calendar.japanese

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if trimmedQuery.isEmpty {
                                ContentUnavailableView(
                                    "予定名を入力",
                                    systemImage: "magnifyingglass",
                                    description: Text("検索欄に入力すると候補を表示します")
                                )
                                .padding(.top, 72)
                            } else {
                                ForEach(filteredPlans) { plan in
                                    CalendarPlanSearchRow(
                                        plan: plan,
                                        now: Date(),
                                        onEdit: {
                                            editingPlan = plan
                                        }
                                    )
                                        .id(plan.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            onOpenDay(plan)
                                        }
                                        .contextMenu {
                                            Button {
                                                editingPlan = plan
                                            } label: {
                                                Label("編集", systemImage: "pencil")
                                            }
                                        }

                                    Divider()
                                        .padding(.leading, 20)
                                }
                            }
                        }
                    }
                    .onAppear {
                        scrollToNearestFuture(using: proxy)
                    }
                    .onChange(of: query) {
                        scrollToNearestFuture(using: proxy)
                    }
                }

                Text(searchResultText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
            .navigationTitle("予定を検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(item: $editingPlan) { plan in
            PlanCreateSheet(plan: plan)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchResultText: String {
        trimmedQuery.isEmpty ? "検索ワードを入力してください" : "検索結果: \(filteredPlans.count)件"
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)

            TextField("予定名で検索", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.title3.weight(.medium))

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(
            Capsule()
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            Capsule()
                .stroke(Color(.separator).opacity(0.45), lineWidth: 1)
        )
    }

    private var filteredPlans: [PlanBlock] {
        guard !trimmedQuery.isEmpty else { return [] }

        let sortedPlans = plans.sorted {
            let lhsDate = searchSortDate(for: $0)
            let rhsDate = searchSortDate(for: $1)
            if lhsDate == rhsDate {
                return $0.createdAt < $1.createdAt
            }
            return lhsDate < rhsDate
        }

        return sortedPlans.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private func scrollToNearestFuture(using proxy: ScrollViewProxy) {
        guard let target = filteredPlans.first(where: { searchSortDate(for: $0) >= Date() }) else { return }
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.25)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    private func searchSortDate(for plan: PlanBlock) -> Date {
        guard plan.isAllDay else { return plan.startTime }
        let dayStart = calendar.startOfDay(for: plan.startTime)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? plan.startTime
    }
}

private struct CalendarPlanSearchRow: View {
    let plan: PlanBlock
    let now: Date
    let onEdit: () -> Void

    @AppStorage("calendarDimPastPlans") private var dimPastPlans = true
    @AppStorage("calendarStrikePastPlans") private var strikePastPlans = false

    private var isPast: Bool {
        sortDate < now
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.startTime.japaneseYear)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(monthDayText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isPast ? Color.secondary : Color.red)
                    .monospacedDigit()

                Text(weekdayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPast ? Color.secondary : Color.red)
            }
            .frame(width: 88, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(timeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                HStack(spacing: 6) {
                    Circle()
                        .fill(plan.category?.displayColor ?? Color.accentColor)
                        .frame(width: 6, height: 6)

                    Text(plan.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .strikethrough(isPast && strikePastPlans, color: .primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(plan.title)を編集")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .opacity(isPast && dimPastPlans ? 0.38 : 1)
        .accessibilityLabel("\(plan.title) \(plan.startTime.japaneseMonthDayShortWeekday)")
    }

    private var sortDate: Date {
        guard plan.isAllDay else { return plan.startTime }
        let dayStart = Calendar.japanese.startOfDay(for: plan.startTime)
        return Calendar.japanese.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? plan.startTime
    }

    private var monthDayText: String {
        let month = Calendar.japanese.component(.month, from: plan.startTime)
        let day = Calendar.japanese.component(.day, from: plan.startTime)
        return "\(month)月\(day)日"
    }

    private var weekdayText: String {
        let weekdayIndex = Calendar.japanese.component(.weekday, from: plan.startTime) - 1
        let weekday = Calendar.japaneseShortWeekdaySymbols[max(0, min(weekdayIndex, Calendar.japaneseShortWeekdaySymbols.count - 1))]
        return "\(weekday)曜日"
    }

    private var timeText: String {
        if plan.isAllDay {
            return "時間未指定"
        }
        return "\(plan.startTime.shortTime) - \(plan.endTime.shortTime)"
    }
}

private extension PlanBlock {
    var showsInCalendarAsImportant: Bool {
        isAllDay || isImportant
    }

    var spansMultipleCalendarDays: Bool {
        let calendar = Calendar.japanese
        let startDay = calendar.startOfDay(for: startTime)
        let endReference = isAllDay ? endTime.addingTimeInterval(-1) : endTime.addingTimeInterval(-0.001)
        return !calendar.isDate(startDay, inSameDayAs: endReference)
    }

    func overlaps(day: Date) -> Bool {
        let calendar = Calendar.japanese
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return startTime < dayEnd && endTime > dayStart
    }
}

struct CalendarWeekdayHeader: View {
    let weekdays: [String]
    let weekdayColor: (String) -> Color

    private let spacing: CGFloat = 1

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(weekdays, id: \.self) { weekday in
                Text(weekday)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(weekdayColor(weekday))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .background(Color(.separator).opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
        )
        .padding(.top, 6)
    }
}

struct CalendarDisplayScore: Hashable {
    let value: Double
    let hasData: Bool

    init(value: Double, hasData: Bool) {
        self.value = value
        self.hasData = hasData
    }

    init(summary: ScoreSummary) {
        self.value = summary.totalScore
        self.hasData = summary.plannedDuration > 0
    }
}

struct CalendarDisplayPlan: Identifiable, Hashable {
    let id: UUID
    let title: String
    let startTime: Date
    let endTime: Date
    let isAllDay: Bool
    let categoryColorHex: String
    let createdAt: Date

    init(
        id: UUID,
        title: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool,
        categoryColorHex: String,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.categoryColorHex = categoryColorHex
        self.createdAt = createdAt
    }

    init(plan: PlanBlock) {
        self.init(
            id: plan.id,
            title: plan.title,
            startTime: plan.startTime,
            endTime: plan.endTime,
            isAllDay: plan.isAllDay,
            categoryColorHex: plan.category?.colorHex ?? "#2F80ED",
            createdAt: plan.createdAt
        )
    }

    var color: Color {
        Color.cachedDisplayHex(categoryColorHex)
    }

    var spansMultipleCalendarDays: Bool {
        let calendar = Calendar.japanese
        let startDay = calendar.startOfDay(for: startTime)
        let endReference = isAllDay ? endTime.addingTimeInterval(-1) : endTime.addingTimeInterval(-0.001)
        return !calendar.isDate(startDay, inSameDayAs: endReference)
    }

    func overlaps(day: Date) -> Bool {
        let calendar = Calendar.japanese
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return startTime < dayEnd && endTime > dayStart
    }
}

struct CalendarMonthPageData {
    let dates: [Date]
    let visibleMonth: Date
    let importantPlansByDay: [Date: [CalendarDisplayPlan]]
    let scoreSummariesByDay: [Date: CalendarDisplayScore]
}

struct CalendarMonthGrid: View {
    let pageData: CalendarMonthPageData
    let onOpenDay: (Date, UUID?) -> Void

    private let spacing: CGFloat = 1

    var body: some View {
        VStack(spacing: spacing) {

            ForEach(Array(weekDates.enumerated()), id: \.offset) { _, dates in
                CalendarMonthWeekRow(
                    dates: dates,
                    visibleMonth: pageData.visibleMonth,
                    importantPlansByDay: pageData.importantPlansByDay,
                    scoreSummariesByDay: pageData.scoreSummariesByDay,
                    onOpenDay: onOpenDay,
                    spacing: spacing,
                    cellHeight: cellHeight
                )
            }
        }
        .background(Color(.separator).opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
        )
    }

    private var weekDates: [[Date]] {
        stride(from: 0, to: pageData.dates.count, by: 7).map { start in
            Array(pageData.dates[start..<min(start + 7, pageData.dates.count)])
        }
    }

    private var cellHeight: CGFloat {
        CalendarMonthDayCell.cellHeight(forWeekCount: weekDates.count)
    }
}

private struct CalendarMonthWeekRow: View {
    let dates: [Date]
    let visibleMonth: Date
    let importantPlansByDay: [Date: [CalendarDisplayPlan]]
    let scoreSummariesByDay: [Date: CalendarDisplayScore]
    let onOpenDay: (Date, UUID?) -> Void
    let spacing: CGFloat
    let cellHeight: CGFloat

    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = 6.0

    private let calendar = Calendar.japanese

    var body: some View {
        let placements = visibleMultiDayPlacements

        ZStack(alignment: .topLeading) {
            HStack(spacing: spacing) {
                ForEach(dates, id: \.self) { date in
                    Button {
                        onOpenDay(date, nil)
                    } label: {
                        CalendarMonthDayCell(
                            date: date,
                            visibleMonth: visibleMonth,
                            importantPlans: importantPlans(on: date),
                            reservedPlanRows: reservedPlanRows(on: date, placements: placements),
                            scoreSummary: scoreSummary(on: date),
                            cellHeight: cellHeight
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            GeometryReader { proxy in
                ForEach(placements) { placement in
                    if let frame = segmentFrame(for: placement, in: proxy.size) {
                        Button {
                            onOpenDay(placement.plan.startTime, placement.plan.id)
                        } label: {
                            CalendarMultiDayPlanBar(
                                plan: placement.plan,
                                roundsLeading: roundsLeadingEdge(for: placement.plan),
                                roundsTrailing: roundsTrailingEdge(for: placement.plan)
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: frame.width, height: labelHeight)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: cellHeight)
        }
        .frame(height: cellHeight)
    }

    private var visibleMultiDayPlacements: [CalendarMultiDayPlacement] {
        let capacity = maxVisiblePlanRows
        guard capacity > 0 else { return [] }
        return multiDayPlacements.filter { $0.lane < capacity }
    }

    private var multiDayPlacements: [CalendarMultiDayPlacement] {
        let orderedPlans = multiDayPlans.compactMap { plan -> CalendarMultiDayPlacementSeed? in
            guard let span = clippedSpan(for: plan) else { return nil }
            return CalendarMultiDayPlacementSeed(plan: plan, startIndex: span.startIndex, endIndex: span.endIndex)
        }
        .sorted { lhs, rhs in
            if lhs.startIndex != rhs.startIndex {
                return lhs.startIndex < rhs.startIndex
            }
            if lhs.endIndex != rhs.endIndex {
                return lhs.endIndex > rhs.endIndex
            }
            if lhs.plan.startTime != rhs.plan.startTime {
                return lhs.plan.startTime < rhs.plan.startTime
            }
            return lhs.plan.createdAt < rhs.plan.createdAt
        }

        var laneEndIndices: [Int] = []
        return orderedPlans.map { seed in
            let lane = laneEndIndices.firstIndex { $0 <= seed.startIndex } ?? laneEndIndices.count
            if lane == laneEndIndices.count {
                laneEndIndices.append(seed.endIndex)
            } else {
                laneEndIndices[lane] = seed.endIndex
            }
            return CalendarMultiDayPlacement(
                plan: seed.plan,
                lane: lane,
                startIndex: seed.startIndex,
                endIndex: seed.endIndex
            )
        }
    }

    private var multiDayPlans: [CalendarDisplayPlan] {
        var seenIDs = Set<UUID>()
        return dates
            .flatMap { importantPlans(on: $0) }
            .filter(\.spansMultipleCalendarDays)
            .filter { plan in
                guard !seenIDs.contains(plan.id) else { return false }
                seenIDs.insert(plan.id)
                return true
            }
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.createdAt < $1.createdAt
                }
                return $0.startTime < $1.startTime
            }
    }

    private func reservedPlanRows(on date: Date, placements: [CalendarMultiDayPlacement]) -> Int {
        guard let weekStart = dates.first.map(calendar.startOfDay(for:)) else { return 0 }
        let dayIndex = calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: date)).day ?? 0
        return (placements
            .filter { $0.startIndex <= dayIndex && dayIndex < $0.endIndex }
            .map(\.lane)
            .max() ?? -1) + 1
    }

    private func importantPlans(on date: Date) -> [CalendarDisplayPlan] {
        importantPlansByDay[calendar.startOfDay(for: date)] ?? []
    }

    private func scoreSummary(on date: Date) -> CalendarDisplayScore {
        scoreSummariesByDay[calendar.startOfDay(for: date)] ?? CalendarDisplayScore(value: 0, hasData: false)
    }

    private func segmentFrame(for placement: CalendarMultiDayPlacement, in size: CGSize) -> CGRect? {
        let columnWidth = (size.width - spacing * 6) / 7
        let columnCount = placement.endIndex - placement.startIndex
        guard columnCount > 0 else { return nil }
        let x = CGFloat(placement.startIndex) * (columnWidth + spacing) + 3
        let width = CGFloat(columnCount) * columnWidth + CGFloat(columnCount - 1) * spacing - 6
        let y = planListTop + CGFloat(placement.lane) * rowStride
        return CGRect(x: x, y: y, width: max(width, 2), height: labelHeight)
    }

    private func clippedSpan(for plan: CalendarDisplayPlan) -> (startIndex: Int, endIndex: Int)? {
        guard let weekStart = dates.first.map(calendar.startOfDay(for:)),
              let lastDate = dates.last,
              let weekEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDate))
        else {
            return nil
        }

        let clippedStart = max(calendar.startOfDay(for: plan.startTime), weekStart)
        let clippedEnd = min(plan.endTime, weekEnd)
        let startIndex = max(0, calendar.dateComponents([.day], from: weekStart, to: clippedStart).day ?? 0)
        let endIndex = min(7, exclusiveDayIndex(for: clippedEnd, from: weekStart))
        guard endIndex > startIndex else { return nil }
        return (startIndex, endIndex)
    }

    private func exclusiveDayIndex(for end: Date, from weekStart: Date) -> Int {
        let endDay = calendar.startOfDay(for: end)
        let exclusiveEndDay: Date
        if abs(end.timeIntervalSince(endDay)) < 0.001 {
            exclusiveEndDay = endDay
        } else {
            exclusiveEndDay = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        }
        return calendar.dateComponents([.day], from: weekStart, to: exclusiveEndDay).day ?? 0
    }

    private func roundsLeadingEdge(for plan: CalendarDisplayPlan) -> Bool {
        guard let weekStart = dates.first.map(calendar.startOfDay(for:)) else { return true }
        return plan.startTime >= weekStart
    }

    private func roundsTrailingEdge(for plan: CalendarDisplayPlan) -> Bool {
        guard let lastDate = dates.last,
              let weekEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDate))
        else {
            return true
        }
        return plan.endTime <= weekEnd
    }

    private var maxVisiblePlanRows: Int {
        let verticalPadding: CGFloat = 8
        let headerHeight: CGFloat = 22
        let headerToPlansSpacing: CGFloat = 4
        let availableHeight = cellHeight - verticalPadding - headerHeight - headerToPlansSpacing
        return max(Int((availableHeight + planRowSpacing) / rowStride), 0)
    }

    private var planListTop: CGFloat {
        4 + 22 + 4
    }

    private var labelHeight: CGFloat {
        max(11, CGFloat(planTitleFontSize) + 5)
    }

    private var planRowSpacing: CGFloat {
        2
    }

    private var rowStride: CGFloat {
        labelHeight + planRowSpacing
    }
}

private struct CalendarMultiDayPlacementSeed {
    let plan: CalendarDisplayPlan
    let startIndex: Int
    let endIndex: Int
}

private struct CalendarMultiDayPlacement: Identifiable {
    var id: UUID { plan.id }
    let plan: CalendarDisplayPlan
    let lane: Int
    let startIndex: Int
    let endIndex: Int
}

struct CalendarMonthDayCell: View {
    static func cellHeight(forWeekCount weekCount: Int) -> CGFloat {
        weekCount <= 5 ? 110 : 92
    }

    let date: Date
    let visibleMonth: Date
    let importantPlans: [CalendarDisplayPlan]
    let reservedPlanRows: Int
    let scoreSummary: CalendarDisplayScore
    let cellHeight: CGFloat

    @AppStorage("calendarPlanTitleFontSize") private var planTitleFontSize = 6.0

    private var isToday: Bool {
        Calendar.japanese.isDateInToday(date)
    }

    private var isInVisibleMonth: Bool {
        Calendar.japanese.isDate(date, equalTo: visibleMonth, toGranularity: .month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

                CalendarScoreBadge(summary: scoreSummary)
            }

            VStack(alignment: .leading, spacing: 2) {
                if reservedPlanRows > 0 {
                    Color.clear
                        .frame(height: CGFloat(reservedPlanRows) * rowStride)
                }

                ForEach(visibleImportantPlans) { plan in
                    CalendarImportantPlanLabel(plan: plan, date: date)
                }

                let overflow = max(singleDayImportantPlans.count - visibleImportantPlans.count, 0)
                if overflow > 0 {
                    Text("+\(overflow)件")
                        .font(.system(size: 6, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .topLeading)
        .background(
            Rectangle()
                .fill(isInVisibleMonth ? Color(.secondarySystemGroupedBackground) : Color(.tertiarySystemGroupedBackground).opacity(0.5))
        )
        .overlay(
            Rectangle()
                .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: isToday ? 2.5 : 0)
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

    private var singleDayImportantPlans: [CalendarDisplayPlan] {
        importantPlans
            .filter { !$0.spansMultipleCalendarDays }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return lhs.isAllDay
                }
                if lhs.startTime != rhs.startTime {
                    return lhs.startTime < rhs.startTime
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private var visibleImportantPlans: [CalendarDisplayPlan] {
        let capacity = maxVisiblePlanRows
        guard capacity > 0 else { return [] }
        guard singleDayImportantPlans.count > capacity else {
            return singleDayImportantPlans
        }

        return Array(singleDayImportantPlans.prefix(max(capacity - 1, 0)))
    }

    private var maxVisiblePlanRows: Int {
        let verticalPadding: CGFloat = 8
        let headerHeight: CGFloat = 22
        let headerToPlansSpacing: CGFloat = 4
        let availableHeight = cellHeight - verticalPadding - headerHeight - headerToPlansSpacing
        return max(Int((availableHeight + planRowSpacing) / rowStride) - reservedPlanRows, 0)
    }

    private var labelHeight: CGFloat {
        max(11, CGFloat(planTitleFontSize) + 5)
    }

    private var planRowSpacing: CGFloat {
        2
    }

    private var rowStride: CGFloat {
        labelHeight + planRowSpacing
    }
}

private struct CalendarScoreBadge: View {
    let summary: CalendarDisplayScore

    @ViewBuilder
    var body: some View {
        Text(scoreText)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(scoreColor)
            .monospacedDigit()
            .frame(minWidth: 21, minHeight: 17)
            .padding(.horizontal, 3)
            .background(
                Capsule()
                    .fill(scoreColor.opacity(summary.hasData ? 0.12 : 0.08))
            )
            .overlay(
                Capsule()
                    .stroke(scoreColor.opacity(summary.hasData ? 0.24 : 0.14), lineWidth: 1)
            )
            .accessibilityLabel(accessibilityText)
    }

    private var scoreText: String {
        guard summary.hasData else { return "-" }
        return "\(Int(summary.value.rounded()))"
    }

    private var accessibilityText: String {
        guard summary.hasData else { return "スコアなし" }
        return "スコア \(Int(summary.value.rounded()))"
    }

    private var scoreColor: Color {
        guard summary.hasData else {
            return .secondary
        }
        switch summary.value {
        case 85...:
            return .green
        case 65..<85:
            return .teal
        case 40..<65:
            return .orange
        case 1..<40:
            return .red
        default:
            return .secondary
        }
    }
}

private struct CalendarImportantPlanLabel: View {
    let plan: CalendarDisplayPlan
    let date: Date

    @AppStorage("calendarTimedPlanLabelStyle") private var timedPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarAllDayPlanLabelStyle") private var allDayPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarPlanTitleFontSize") private var titleFontSize = 6.0
    @AppStorage("calendarPlanTitleBold") private var titleBold = false
    @AppStorage("calendarDimPastPlans") private var dimPastPlans = true
    @AppStorage("calendarStrikePastPlans") private var strikePastPlans = false

    var body: some View {
        HStack(spacing: 3) {
            if let timePrefix {
                Text(timePrefix)
                    .font(.system(size: timeFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(timeColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(shouldStrikePastPlan, color: timeColor)
            }

            clippedTitle
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: labelHeight)
            .padding(.horizontal, 3)
            .background(backgroundShape)
            .overlay(borderShape)
            .padding(.leading, continuesFromPreviousDay ? -3 : 0)
            .padding(.trailing, continuesToNextDay ? -3 : 0)
            .opacity(isPastPlan && dimPastPlans ? 0.38 : 1)
            .accessibilityLabel("\(plan.title) 重要な予定")
    }

    private var clippedTitle: some View {
        Color.clear
            .overlay(alignment: .leading) {
                Text(plan.title)
                    .font(.system(size: titleFontSize, weight: titleBold ? .bold : .regular))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(shouldStrikePastPlan, color: titleColor)
            }
            .clipped()
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: !continuesFromPreviousDay,
                roundsTrailing: !continuesToNextDay
            )
            .fill(color.opacity(0.14))
        }
    }

    @ViewBuilder
    private var borderShape: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: !continuesFromPreviousDay,
                roundsTrailing: !continuesToNextDay
            )
            .stroke(color.opacity(0.24), lineWidth: 0.7)
        } else if labelStyle == .underline {
            Rectangle()
                .fill(color.opacity(0.28))
                .frame(height: markerHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, markerBottomPadding)
        }
    }

    private var color: Color {
        plan.color
    }

    private var labelStyle: CalendarPlanLabelStyle {
        let rawValue = plan.isAllDay ? allDayPlanLabelStyleRaw : timedPlanLabelStyleRaw
        return CalendarPlanLabelStyle(rawValue: rawValue) ?? .background
    }

    private var titleColor: Color {
        labelStyle == .background ? .primary : color
    }

    private var timeColor: Color {
        labelStyle == .background ? .secondary : color.opacity(0.75)
    }

    private var timeFontSize: Double {
        max(4, titleFontSize - 1)
    }

    private var labelHeight: CGFloat {
        max(11, CGFloat(titleFontSize) + 5)
    }

    private var markerHeight: CGFloat {
        max(4, CGFloat(titleFontSize) * 0.5)
    }

    private var markerBottomPadding: CGFloat {
        max(1, CGFloat(titleFontSize) * 0.08)
    }

    private var isPastPlan: Bool {
        min(plan.endTime, dayEnd) <= Date()
    }

    private var shouldStrikePastPlan: Bool {
        isPastPlan && strikePastPlans
    }

    private var dayStart: Date {
        Calendar.japanese.startOfDay(for: date)
    }

    private var dayEnd: Date {
        Calendar.japanese.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    private var continuesFromPreviousDay: Bool {
        plan.startTime < dayStart
    }

    private var continuesToNextDay: Bool {
        plan.endTime > dayEnd
    }

    private var timePrefix: String? {
        if plan.isAllDay || continuesFromPreviousDay {
            return nil
        }
        return plan.startTime.shortTime
    }
}

private struct CalendarMultiDayPlanBar: View {
    let plan: CalendarDisplayPlan
    let roundsLeading: Bool
    let roundsTrailing: Bool

    @AppStorage("calendarMultiDayPlanLabelStyle") private var multiDayPlanLabelStyleRaw = CalendarPlanLabelStyle.background.rawValue
    @AppStorage("calendarPlanTitleFontSize") private var titleFontSize = 6.0
    @AppStorage("calendarPlanTitleBold") private var titleBold = false
    @AppStorage("calendarDimPastPlans") private var dimPastPlans = true
    @AppStorage("calendarStrikePastPlans") private var strikePastPlans = false

    var body: some View {
        Color.clear
            .overlay {
                Text(plan.title)
                    .font(.system(size: titleFontSize, weight: titleBold ? .bold : .regular))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(isPastPlan && strikePastPlans, color: titleColor)
            }
            .background(backgroundShape)
            .overlay(decorationOverlay)
            .clipped()
            .opacity(isPastPlan && dimPastPlans ? 0.38 : 1)
            .accessibilityLabel("\(plan.title) 複数日に跨る重要な予定")
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: roundsLeading,
                roundsTrailing: roundsTrailing
            )
            .fill(color.opacity(0.14))
        }
    }

    @ViewBuilder
    private var decorationOverlay: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: roundsLeading,
                roundsTrailing: roundsTrailing
            )
            .stroke(color.opacity(0.24), lineWidth: 0.7)
        } else if labelStyle == .underline {
            Rectangle()
                .fill(color.opacity(0.28))
                .frame(height: markerHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, markerBottomPadding)
        }
    }

    private var labelStyle: CalendarPlanLabelStyle {
        CalendarPlanLabelStyle(rawValue: multiDayPlanLabelStyleRaw) ?? .background
    }

    private var color: Color {
        plan.color
    }

    private var titleColor: Color {
        labelStyle == .background ? .primary : color
    }

    private var markerHeight: CGFloat {
        max(4, CGFloat(titleFontSize) * 0.5)
    }

    private var markerBottomPadding: CGFloat {
        max(1, CGFloat(titleFontSize) * 0.08)
    }

    private var isPastPlan: Bool {
        plan.endTime <= Date()
    }
}

private struct CalendarContinuationShape: Shape {
    let roundsLeading: Bool
    let roundsTrailing: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height / 2, 4)
        let leadingRadius = roundsLeading ? radius : 0
        let trailingRadius = roundsTrailing ? radius : 0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + leadingRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - trailingRadius, y: rect.minY))
        if trailingRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + trailingRadius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - trailingRadius))
        if trailingRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - trailingRadius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + leadingRadius, y: rect.maxY))
        if leadingRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - leadingRadius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + leadingRadius))
        if leadingRadius > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + leadingRadius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Calendar") {
    CalendarView()
        .liminalogPreviewEnvironment()
}
