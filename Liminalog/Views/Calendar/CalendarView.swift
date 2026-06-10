import SwiftUI
import SwiftData
import UIKit

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.createdAt)]) private var categories: [Category]
    @Query(sort: [SortDescriptor(\Friend.displayName), SortDescriptor(\Friend.createdAt)]) private var friends: [Friend]

    @AppStorage("calendar.filter.usesCustomCategories") private var usesCustomCategoryFilter = false
    @AppStorage("calendar.filter.categoryIDs") private var storedCategoryFilterIDs = ""
    @AppStorage("calendar.filter.overlayFriendIDs") private var storedOverlayFriendIDs = ""

    @State private var visibleMonth = CalendarView.currentMonthStart
    @State private var anchorMonth = CalendarView.currentMonthStart
    @State private var scrolledOffset: Int? = 0
    @State private var pageDataByMonth: [Date: CalendarMonthPageData] = [:]
    @State private var showingMonthPicker = false
    @State private var pickerYear = Calendar.japanese.component(.year, from: Date())
    @State private var pickerMonth = Calendar.japanese.component(.month, from: Date())
    @State private var showingCalendarSettings = false
    @State private var showingCalendarSearch = false
    @State private var showingCalendarFilter = false
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

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(monthOffsets, id: \.self) { offset in
                            CalendarMonthPage(
                                weekdays: weekdays,
                                weekdayColor: weekdayColor(_:),
                                pageData: cachedPageData(for: month(forOffset: offset)),
                                onOpenDay: { date, planID in
                                    selectedDay = CalendarDayPresentation(date: date, planID: planID)
                                }
                            )
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
                .frame(height: currentMonthPageHeight)
                .background(LiminalTheme.divider.opacity(0.56))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LiminalTheme.divider.opacity(0.5), lineWidth: 1)
                )
                .padding(.top, 6)
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
            .sheet(isPresented: $showingCalendarFilter) {
                CalendarFilterSheet(
                    categories: categories,
                    friends: acceptedFriends,
                    isResetEnabled: isCalendarFilterActive,
                    isCategorySelected: { selectedCategoryIDs.contains($0.id) },
                    onToggleCategory: toggleCategoryFilter(_:),
                    isFriendSelected: { selectedOverlayFriendIDs.contains($0.id) },
                    onToggleFriend: toggleOverlayFriend(_:),
                    onReset: resetCalendarFilter
                )
            }
            .sheet(item: $selectedDay, onDismiss: reloadVisibleData) { target in
                NavigationStack {
                    CalendarDayPagerSheet(initialDate: target.date, highlightedPlanID: target.planID)
                }
                .presentationDetents([.large])
            }
            .onAppear {
                clock.start()
                pruneCalendarFilterStorage()
                reloadVisibleData()
            }
            .onDisappear {
                clock.stop()
            }
            .onChange(of: categories.map(\.id)) { _, _ in
                pruneCalendarFilterStorage()
            }
            .onChange(of: acceptedFriends.map(\.id)) { _, _ in
                pruneCalendarFilterStorage()
            }
            .onChange(of: usesCustomCategoryFilter) { _, _ in
                reloadVisibleData()
            }
            .onChange(of: storedCategoryFilterIDs) { _, _ in
                reloadVisibleData()
            }
            .onChange(of: storedOverlayFriendIDs) { _, _ in
                reloadVisibleData()
            }
        }
    }

    private var calendarTopBar: some View {
        ZStack {
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
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                .foregroundStyle(LiminalTheme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(LiminalTheme.elevated)
                )
                .overlay(
                    Capsule()
                        .stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("表示月 \(visibleMonth.japaneseYearMonth)")

            HStack {
                Button {
                    showingCalendarSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("カレンダー表示設定")

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Button {
                        showingCalendarFilter = true
                    } label: {
                        Image(systemName: isCalendarFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isCalendarFilterActive ? LiminalTheme.accent : LiminalTheme.accent.opacity(0.72))
                    .accessibilityLabel("カレンダー表示フィルタ")

                    Button {
                        showingCalendarSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("カレンダーを検索")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    private var calendarYearRange: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: Date())
        return (currentYear - 10)...(currentYear + 10)
    }

    private var currentMonthPageHeight: CGFloat {
        let weekCount = cachedPageData(for: visibleMonth).dates.count / 7
        return CalendarMonthPage.height(forWeekCount: weekCount)
    }

    private var allCategoryIDs: Set<UUID> {
        Set(categories.map(\.id))
    }

    private var selectedCategoryIDs: Set<UUID> {
        guard usesCustomCategoryFilter else { return allCategoryIDs }
        return decodedUUIDSet(storedCategoryFilterIDs).intersection(allCategoryIDs)
    }

    private var acceptedFriends: [Friend] {
        friends
            .filter { $0.status == .accepted }
            .sorted {
                if $0.isFavorite != $1.isFavorite {
                    return $0.isFavorite
                }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    private var selectedOverlayFriendIDs: Set<UUID> {
        decodedUUIDSet(storedOverlayFriendIDs).intersection(Set(acceptedFriends.map(\.id)))
    }

    private var selectedOverlayFriends: [Friend] {
        let selectedIDs = selectedOverlayFriendIDs
        return acceptedFriends.filter { selectedIDs.contains($0.id) }
    }

    private var isCalendarFilterActive: Bool {
        usesCustomCategoryFilter || !selectedOverlayFriendIDs.isEmpty
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

    private func toggleCategoryFilter(_ category: Category) {
        var selectedIDs = selectedCategoryIDs
        if selectedIDs.contains(category.id) {
            selectedIDs.remove(category.id)
        } else {
            selectedIDs.insert(category.id)
        }

        if selectedIDs == allCategoryIDs {
            usesCustomCategoryFilter = false
            storedCategoryFilterIDs = ""
        } else {
            usesCustomCategoryFilter = true
            storedCategoryFilterIDs = encodedUUIDSet(selectedIDs)
        }
        reloadVisibleData()
    }

    private func toggleOverlayFriend(_ friend: Friend) {
        var selectedIDs = selectedOverlayFriendIDs
        if selectedIDs.contains(friend.id) {
            selectedIDs.remove(friend.id)
        } else {
            selectedIDs.insert(friend.id)
        }
        storedOverlayFriendIDs = encodedUUIDSet(selectedIDs)
        reloadVisibleData()
    }

    private func resetCalendarFilter() {
        usesCustomCategoryFilter = false
        storedCategoryFilterIDs = ""
        storedOverlayFriendIDs = ""
        reloadVisibleData()
    }

    private func pruneCalendarFilterStorage() {
        let validCategoryIDs = allCategoryIDs
        let storedCategoryIDs = decodedUUIDSet(storedCategoryFilterIDs)
        let prunedCategoryIDs = storedCategoryIDs.intersection(validCategoryIDs)
        if usesCustomCategoryFilter {
            if !storedCategoryIDs.isEmpty && prunedCategoryIDs.isEmpty && !validCategoryIDs.isEmpty {
                usesCustomCategoryFilter = false
                storedCategoryFilterIDs = ""
            } else if prunedCategoryIDs == validCategoryIDs {
                usesCustomCategoryFilter = false
                storedCategoryFilterIDs = ""
            } else if prunedCategoryIDs != storedCategoryIDs {
                storedCategoryFilterIDs = encodedUUIDSet(prunedCategoryIDs)
            }
        } else if !storedCategoryIDs.isEmpty {
            storedCategoryFilterIDs = ""
        }

        let validFriendIDs = Set(acceptedFriends.map(\.id))
        let storedFriendIDs = decodedUUIDSet(storedOverlayFriendIDs)
        let prunedFriendIDs = storedFriendIDs.intersection(validFriendIDs)
        if prunedFriendIDs != storedFriendIDs {
            storedOverlayFriendIDs = encodedUUIDSet(prunedFriendIDs)
        }
    }

    private func decodedUUIDSet(_ rawValue: String) -> Set<UUID> {
        Set(rawValue.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private func encodedUUIDSet(_ ids: Set<UUID>) -> String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
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
                scoreSummariesByDay: [:],
                didFailToLoadRecords: false
            )
        }

        let planDescriptor = FetchDescriptor<PlanBlock>(
            predicate: #Predicate { $0.startTime < gridEnd && $0.endTime > gridStart },
            sortBy: [SortDescriptor(\.startTime)]
        )
        var didFailToLoadRecords = false
        let plansInGrid: [PlanBlock]
        do {
            plansInGrid = try modelContext.fetch(planDescriptor).sorted(by: planSort)
        } catch {
            NSLog("Liminalog: failed to fetch calendar plans: \(String(describing: error))")
            didFailToLoadRecords = true
            plansInGrid = []
        }
        let categoryFilterIsActive = usesCustomCategoryFilter
        let visibleCategoryIDs = selectedCategoryIDs
        let visiblePlansInGrid = categoryFilterIsActive
            ? plansInGrid.filter { plan in
                guard let categoryID = plan.category?.id else { return false }
                return visibleCategoryIDs.contains(categoryID)
            }
            : plansInGrid

        let lookbackStart = calendar.date(byAdding: .day, value: -14, to: gridStart) ?? gridStart
        let chapterDescriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.startTime >= lookbackStart && $0.startTime < gridEnd },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let activeDescriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime)]
        )
        var chapters: [Chapter]
        do {
            chapters = try modelContext.fetch(chapterDescriptor)
                .filter { ($0.endTime ?? now) > gridStart }
        } catch {
            NSLog("Liminalog: failed to fetch calendar chapters: \(String(describing: error))")
            didFailToLoadRecords = true
            chapters = []
        }
        let activeChapters: [Chapter]
        do {
            activeChapters = try modelContext.fetch(activeDescriptor)
                .filter { $0.startTime < gridEnd && ($0.endTime ?? now) > gridStart }
        } catch {
            NSLog("Liminalog: failed to fetch active calendar chapters: \(String(describing: error))")
            didFailToLoadRecords = true
            activeChapters = []
        }
        let existingIDs = Set(chapters.map(\.id))
        chapters.append(contentsOf: activeChapters.filter { !existingIDs.contains($0.id) })
        let chaptersInGrid = chapters
            .filter { chapter in
                guard categoryFilterIsActive else { return true }
                guard let categoryID = chapter.category?.id else { return false }
                return visibleCategoryIDs.contains(categoryID)
            }
            .sorted { $0.startTime < $1.startTime }

        // docs/20: 塊JSONの全件デコードをやめ、グリッド範囲だけを個別行キャッシュから引く。
        let friendRecordStore = FriendSharedRecordStore(modelContext: modelContext)
        var didBackfillFriendRecords = false
        for friend in selectedOverlayFriends where friendRecordStore.backfillFromBlobIfNeeded(friend: friend) {
            didBackfillFriendRecords = true
        }
        if didBackfillFriendRecords {
            try? modelContext.save()
        }
        let friendPlansInGrid = selectedOverlayFriends.map { friend in
            CalendarFriendPlanSource(
                friend: friend,
                plans: friendRecordStore.plans(friendID: friend.id, overlapping: gridStart..<gridEnd)
            )
        }

        var importantPlansByDay: [Date: [CalendarDisplayPlan]] = [:]
        var scoreSummariesByDay: [Date: CalendarDisplayScore] = [:]

        for date in dates {
            let boundary = DayBoundary(date: date, calendar: calendar)
            let dayPlans = visiblePlansInGrid.filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            let dayChapters = chaptersInGrid.filter {
                $0.startTime < boundary.dayEnd && ($0.endTime ?? now) > boundary.dayStart
            }
            let importantPlans = dayPlans
                .filter(\.showsInCalendarAsImportant)
                .sorted(by: planSort)
                .map { CalendarDisplayPlan(plan: $0) }
            let friendImportantPlans = friendPlansInGrid
                .flatMap { source in
                    source.plans
                        .filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart && $0.showsInCalendarAsImportant }
                        .sorted {
                            if $0.startTime == $1.startTime {
                                return $0.updatedAt < $1.updatedAt
                            }
                            return $0.startTime < $1.startTime
                        }
                        .map { CalendarDisplayPlan(friendPlan: $0, friendName: source.friend.displayName) }
                }
            let displayPlans = (importantPlans + friendImportantPlans).sorted {
                if $0.startTime == $1.startTime {
                    return $0.createdAt < $1.createdAt
                }
                return $0.startTime < $1.startTime
            }

            // データのない日はスコアバッジも重要予定も出ないため、計算自体を省く。
            guard !displayPlans.isEmpty || !dayPlans.isEmpty || !dayChapters.isEmpty else { continue }
            if !displayPlans.isEmpty {
                importantPlansByDay[boundary.dayStart] = displayPlans
            }
            scoreSummariesByDay[boundary.dayStart] = CalendarDisplayScore(
                summary: CalendarDayScoreCache.summary(
                    date: date,
                    dayStart: boundary.dayStart,
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
            scoreSummariesByDay: scoreSummariesByDay,
            didFailToLoadRecords: didFailToLoadRecords
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
    @State private var pendingPlanStartsAsAllDay = false
    @State private var showingPlanSheet = false
    @State private var operationError: String?

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
                HStack(spacing: 14) {
                    dayVisibilityMenu
                    Button {
                        preparePlanCreation()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(LiminalTheme.accent)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("予定を追加")
                }
            }
        }
        .sheet(isPresented: $showingPlanSheet) {
            PlanCreateSheet(initialDate: pendingCreateDate, startsAsAllDay: pendingPlanStartsAsAllDay)
        }
        .alert("反映できませんでした", isPresented: operationErrorPresented) {
            Button("OK", role: .cancel) {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
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

    private var operationErrorPresented: Binding<Bool> {
        Binding {
            operationError != nil
        } set: { isPresented in
            if !isPresented {
                operationError = nil
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
                    guard store.setChaptersVisibility(visibleDayChapters, isPublic: true) else {
                        operationError = "公開設定を変更できませんでした。時間をおいてもう一度試してください。"
                        return
                    }
                } label: {
                    Label("すべて公開", systemImage: "eye")
                }
                .disabled(allPublic)

                Button {
                    guard store.setChaptersVisibility(visibleDayChapters, isPublic: false) else {
                        operationError = "公開設定を変更できませんでした。時間をおいてもう一度試してください。"
                        return
                    }
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(LiminalTheme.accent)
        }
        .accessibilityLabel("この日の公開設定")
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

    private func preparePlanCreation() {
        if canCreateTimedPlansForDay {
            pendingCreateDate = defaultPlanStart
            pendingPlanStartsAsAllDay = false
        } else {
            pendingCreateDate = Calendar.japanese.startOfDay(for: anchorDate)
            pendingPlanStartsAsAllDay = true
        }
        showingPlanSheet = true
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

struct CalendarFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = CalendarFilterTab.categories

    let categories: [Category]
    let friends: [Friend]
    let isResetEnabled: Bool
    let isCategorySelected: (Category) -> Bool
    let onToggleCategory: (Category) -> Void
    let isFriendSelected: (Friend) -> Bool
    let onToggleFriend: (Friend) -> Void
    let onReset: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("表示対象", selection: $selectedTab) {
                    ForEach(CalendarFilterTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                TabView(selection: $selectedTab) {
                    CalendarCategoryFilterList(
                        categories: categories,
                        isResetEnabled: isResetEnabled,
                        isCategorySelected: isCategorySelected,
                        onToggleCategory: onToggleCategory,
                        onReset: onReset
                    )
                    .tag(CalendarFilterTab.categories)

                    CalendarFriendFilterList(
                        friends: friends,
                        isResetEnabled: isResetEnabled,
                        isFriendSelected: isFriendSelected,
                        onToggleFriend: onToggleFriend,
                        onReset: onReset
                    )
                    .tag(CalendarFilterTab.friends)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("表示フィルタ")
            .navigationBarTitleDisplayMode(.inline)
            .tint(LiminalTheme.accent)
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
        .presentationDetents([.medium, .large])
    }
}

private enum CalendarFilterTab: String, CaseIterable, Identifiable {
    case categories
    case friends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .categories:
            "カテゴリ"
        case .friends:
            "友達"
        }
    }

    var systemImage: String {
        switch self {
        case .categories:
            "square.grid.2x2"
        case .friends:
            "person.2"
        }
    }
}

private struct CalendarCategoryFilterList: View {
    let categories: [Category]
    let isResetEnabled: Bool
    let isCategorySelected: (Category) -> Bool
    let onToggleCategory: (Category) -> Void
    let onReset: () -> Void

    var body: some View {
        Form {
            Section {
                if categories.isEmpty {
                    Text("カテゴリがありません")
                        .foregroundStyle(LiminalTheme.secondaryText)
                } else {
                    ForEach(categories) { category in
                        CalendarCategoryFilterRow(
                            category: category,
                            isSelected: isCategorySelected(category),
                            onToggle: { onToggleCategory(category) }
                        )
                    }
                }
            } header: {
                Text("カテゴリ")
            } footer: {
                Text("オフにしたカテゴリの予定と実績はカレンダー上で非表示になります。")
            }

            Section {
                Button("すべて表示に戻す") {
                    onReset()
                }
                .disabled(!isResetEnabled)
            }
        }
    }
}

private struct CalendarFriendFilterList: View {
    let friends: [Friend]
    let isResetEnabled: Bool
    let isFriendSelected: (Friend) -> Bool
    let onToggleFriend: (Friend) -> Void
    let onReset: () -> Void

    var body: some View {
        Form {
            Section {
                if friends.isEmpty {
                    Text("選べる友達がいません")
                        .foregroundStyle(LiminalTheme.secondaryText)
                } else {
                    ForEach(friends) { friend in
                        CalendarFriendFilterRow(
                            friend: friend,
                            isSelected: isFriendSelected(friend),
                            onToggle: { onToggleFriend(friend) }
                        )
                    }
                }
            } header: {
                Text("友達")
            } footer: {
                Text("選んだ友達の予定を自分のカレンダーに重ねて表示します。")
            }

            Section {
                Button("すべて表示に戻す") {
                    onReset()
                }
                .disabled(!isResetEnabled)
            }
        }
    }
}

private struct CalendarCategoryFilterRow: View {
    let category: Category
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { _ in onToggle() }
        )) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(category.displayColor.opacity(0.18))
                    Image(systemName: category.icon ?? "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(category.displayColor)
                }
                .frame(width: 30, height: 30)

                Text(category.name)
                    .foregroundStyle(LiminalTheme.text)
            }
        }
    }
}

private struct CalendarFriendFilterRow: View {
    let friend: Friend
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { _ in onToggle() }
        )) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.cachedDisplayHex(friend.accentColorHex).opacity(0.18))
                    Image(systemName: friend.avatarSystemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cachedDisplayHex(friend.accentColorHex))
                }
                .frame(width: 30, height: 30)

                Text(friend.displayName)
                    .foregroundStyle(LiminalTheme.text)
            }
        }
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
                    fontSize: normalizedPlanTitleFontSize,
                    isBold: planTitleBold,
                    sampleTime: "9:30"
                )

                CalendarLabelStyleSettingRow(
                    title: "終日",
                    selectionRaw: $allDayPlanLabelStyleRaw,
                    fontSize: normalizedPlanTitleFontSize,
                    isBold: planTitleBold,
                    sampleTime: nil
                )

                CalendarLabelStyleSettingRow(
                    title: "複数日",
                    selectionRaw: $multiDayPlanLabelStyleRaw,
                    fontSize: normalizedPlanTitleFontSize,
                    isBold: planTitleBold,
                    sampleTime: nil
                )
            }

            Section("フォント") {
                CalendarFontSizeSlider(value: normalizedPlanTitleFontSizeBinding)
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
        .onAppear {
            normalizePlanTitleFontSize()
            normalizePlanLabelStyleRawValues()
        }
        .onChange(of: planTitleFontSize) { _, _ in
            normalizePlanTitleFontSize()
        }
        .onChange(of: timedPlanLabelStyleRaw) { _, _ in
            normalizePlanLabelStyleRawValues()
        }
        .onChange(of: allDayPlanLabelStyleRaw) { _, _ in
            normalizePlanLabelStyleRawValues()
        }
        .onChange(of: multiDayPlanLabelStyleRaw) { _, _ in
            normalizePlanLabelStyleRawValues()
        }
    }

    private var normalizedPlanTitleFontSize: Double {
        CalendarPlanTitleMetrics.clamped(planTitleFontSize)
    }

    private var normalizedPlanTitleFontSizeBinding: Binding<Double> {
        Binding {
            normalizedPlanTitleFontSize
        } set: { newValue in
            planTitleFontSize = CalendarPlanTitleMetrics.clamped(newValue)
        }
    }

    private func normalizePlanTitleFontSize() {
        let normalized = normalizedPlanTitleFontSize
        guard planTitleFontSize != normalized else { return }
        planTitleFontSize = normalized
    }

    private func normalizePlanLabelStyleRawValues() {
        let defaultRawValue = CalendarPlanLabelStyle.background.rawValue
        let normalizedTimed = CalendarPlanLabelStyle(rawValue: timedPlanLabelStyleRaw)?.rawValue ?? defaultRawValue
        let normalizedAllDay = CalendarPlanLabelStyle(rawValue: allDayPlanLabelStyleRaw)?.rawValue ?? defaultRawValue
        let normalizedMultiDay = CalendarPlanLabelStyle(rawValue: multiDayPlanLabelStyleRaw)?.rawValue ?? defaultRawValue

        if timedPlanLabelStyleRaw != normalizedTimed {
            timedPlanLabelStyleRaw = normalizedTimed
        }
        if allDayPlanLabelStyleRaw != normalizedAllDay {
            allDayPlanLabelStyleRaw = normalizedAllDay
        }
        if multiDayPlanLabelStyleRaw != normalizedMultiDay {
            multiDayPlanLabelStyleRaw = normalizedMultiDay
        }
    }
}

private enum CalendarPlanTitleMetrics {
    static let defaultSize = 6.0
    static let minSize = 5.0
    static let maxSize = 9.0
    static let step = 0.5

    static var stepCount: Int {
        Int(((maxSize - minSize) / step).rounded()) + 1
    }

    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return defaultSize }
        return min(max(value, minSize), maxSize)
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
                                .foregroundStyle(LiminalTheme.text)

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

    var body: some View {
        HStack(spacing: 12) {
            Text("A")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 0) {
                Slider(value: $value, in: CalendarPlanTitleMetrics.minSize...CalendarPlanTitleMetrics.maxSize, step: CalendarPlanTitleMetrics.step)

                HStack {
                    ForEach(0..<CalendarPlanTitleMetrics.stepCount, id: \.self) { index in
                        Circle()
                            .fill(index == selectedStepIndex ? LiminalTheme.accent : LiminalTheme.secondaryText.opacity(0.42))
                            .frame(width: index == selectedStepIndex ? 5 : 3, height: index == selectedStepIndex ? 5 : 3)

                        if index < CalendarPlanTitleMetrics.stepCount - 1 {
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
        let normalized = CalendarPlanTitleMetrics.clamped(value)
        let rawIndex = Int(((normalized - CalendarPlanTitleMetrics.minSize) / CalendarPlanTitleMetrics.step).rounded())
        return min(max(rawIndex, 0), CalendarPlanTitleMetrics.stepCount - 1)
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
                    .font(.system(size: max(4, displayFontSize - 1), weight: .medium, design: .rounded))
                    .foregroundStyle(timeColor)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Text("予定")
                .font(.system(size: displayFontSize, weight: isBold ? .bold : .regular))
                .foregroundStyle(titleColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(9, CGFloat(displayFontSize) + 3))
        .padding(.horizontal, 3)
        .offset(y: textVerticalOffset)
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
        max(2, CGFloat(displayFontSize) * 0.32)
    }

    private var markerBottomPadding: CGFloat {
        max(0.5, CGFloat(displayFontSize) * 0.05)
    }

    private var textVerticalOffset: CGFloat {
        style == .underline ? -max(0.5, CGFloat(displayFontSize) * 0.1) : 0
    }

    private var displayFontSize: Double {
        CalendarPlanTitleMetrics.clamped(fontSize)
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
                            if plans.isEmpty {
                                ContentUnavailableView(
                                    "検索できる予定がありません",
                                    systemImage: "calendar",
                                    description: Text("予定を作成すると、ここから探せます")
                                )
                                .padding(.top, 72)
                            } else if trimmedQuery.isEmpty {
                                ContentUnavailableView(
                                    "予定名を入力",
                                    systemImage: "magnifyingglass",
                                    description: Text("検索欄に入力すると候補を表示します")
                                )
                                .padding(.top, 72)
                            } else if filteredPlans.isEmpty {
                                ContentUnavailableView(
                                    "該当する予定はありません",
                                    systemImage: "magnifyingglass",
                                    description: Text("別の予定名で検索してください")
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
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LiminalTheme.surface)
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
        if plans.isEmpty { return "検索できる予定はありません" }
        if trimmedQuery.isEmpty { return "予定名を入力してください" }
        if filteredPlans.isEmpty { return "該当する予定はありません" }
        return "\(filteredPlans.count)件見つかりました"
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(LiminalTheme.secondaryText)

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
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(
            Capsule()
                .fill(LiminalTheme.surface)
        )
        .overlay(
            Capsule()
                .stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1)
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
                    .foregroundStyle(LiminalTheme.secondaryText)

                Text(monthDayText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isPast ? LiminalTheme.secondaryText : Color.red)
                    .monospacedDigit()

                Text(weekdayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPast ? LiminalTheme.secondaryText : Color.red)
            }
            .frame(width: 88, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(timeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .monospacedDigit()

                HStack(spacing: 6) {
                    Circle()
                        .fill(plan.category?.displayColor ?? LiminalTheme.accent)
                        .frame(width: 6, height: 6)

                    Text(plan.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(1)
                        .strikethrough(isPast && strikePastPlans, color: LiminalTheme.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(LiminalTheme.elevated)
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
            return "終日"
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

private struct CalendarMonthPage: View {
    let weekdays: [String]
    let weekdayColor: (String) -> Color
    let pageData: CalendarMonthPageData
    let onOpenDay: (Date, UUID?) -> Void

    private let spacing: CGFloat = 1

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: spacing) {
                CalendarWeekdayHeader(
                    weekdays: weekdays,
                    weekdayColor: weekdayColor
                )

                CalendarMonthGrid(
                    pageData: pageData,
                    onOpenDay: onOpenDay
                )
            }

            if pageData.didFailToLoadRecords {
                Text("一部を読み込めませんでした")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiminalTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(LiminalTheme.elevated.opacity(0.94))
                    )
                    .overlay(
                        Capsule()
                            .stroke(LiminalTheme.divider.opacity(0.7), lineWidth: 0.5)
                    )
                    .padding(.top, 30)
            }
        }
        .frame(height: Self.height(forWeekCount: weekCount), alignment: .top)
        .background(LiminalTheme.divider.opacity(0.56))
    }

    static func height(forWeekCount weekCount: Int) -> CGFloat {
        let clampedWeekCount = max(5, min(6, weekCount))
        let gridHeight = CGFloat(clampedWeekCount) * CalendarMonthDayCell.cellHeight(forWeekCount: clampedWeekCount)
        let gridSpacing = CGFloat(clampedWeekCount - 1)
        return 28 + 1 + gridHeight + gridSpacing
    }

    private var weekCount: Int {
        pageData.dates.count / 7
    }
}

private struct CalendarFriendPlanSource {
    let friend: Friend
    let plans: [FriendSharedPlanSnapshot]
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
                    .background(LiminalTheme.surface)
            }
        }
        .background(LiminalTheme.divider.opacity(0.56))
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

    init(friendPlan plan: FriendSharedPlanSnapshot, friendName: String) {
        self.init(
            id: plan.id,
            title: "\(friendName): \(plan.title)",
            startTime: plan.startTime,
            endTime: plan.endTime,
            isAllDay: plan.isAllDay,
            categoryColorHex: plan.categoryColorHex,
            createdAt: plan.updatedAt
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
    let didFailToLoadRecords: Bool
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
        .background(gridDividerColor)
    }

    private var weekDates: [[Date]] {
        stride(from: 0, to: pageData.dates.count, by: 7).map { start in
            Array(pageData.dates[start..<min(start + 7, pageData.dates.count)])
        }
    }

    private var cellHeight: CGFloat {
        CalendarMonthDayCell.cellHeight(forWeekCount: weekDates.count)
    }

    private var gridDividerColor: Color {
        LiminalTheme.divider.opacity(0.58)
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
        max(9, CGFloat(displayPlanTitleFontSize) + 3)
    }

    private var planRowSpacing: CGFloat {
        2
    }

    private var rowStride: CGFloat {
        labelHeight + planRowSpacing
    }

    private var displayPlanTitleFontSize: Double {
        CalendarPlanTitleMetrics.clamped(planTitleFontSize)
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
                            Circle().fill(LiminalTheme.accent)
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
                        .foregroundStyle(LiminalTheme.secondaryText)
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
                .fill(isInVisibleMonth ? LiminalTheme.surface : LiminalTheme.elevated.opacity(0.5))
        )
        .overlay(
            Rectangle()
                .inset(by: isToday ? 0.75 : 0)
                .strokeBorder(isToday ? LiminalTheme.accent : Color.clear, lineWidth: isToday ? 2.25 : 0)
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
        return LiminalTheme.text
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
        max(9, CGFloat(displayPlanTitleFontSize) + 3)
    }

    private var planRowSpacing: CGFloat {
        2
    }

    private var rowStride: CGFloat {
        labelHeight + planRowSpacing
    }

    private var displayPlanTitleFontSize: Double {
        CalendarPlanTitleMetrics.clamped(planTitleFontSize)
    }
}

private struct CalendarScoreBadge: View {
    let summary: CalendarDisplayScore

    var body: some View {
        ZStack {
            Circle()
                .stroke(scoreColor.opacity(summary.hasData ? 0.18 : 0.12), lineWidth: 2)

            if summary.hasData {
                Circle()
                    .trim(from: 0, to: scoreProgress)
                    .stroke(
                        scoreColor.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(accessibilityText)
    }

    private var scoreProgress: Double {
        min(max(summary.value / 100, 0), 1)
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
    @Environment(\.colorScheme) private var colorScheme

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
                    .shadow(color: textShadowColor, radius: 0.5, x: 0, y: 0.5)
            }

            clippedTitle
        }
            .offset(y: textVerticalOffset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: labelHeight)
            .padding(.horizontal, 3)
            .background(backgroundShape)
            .overlay(borderShape)
            .padding(.leading, continuesFromPreviousDay ? -3 : 0)
            .padding(.trailing, continuesToNextDay ? -3 : 0)
            .opacity(labelOpacity)
            .accessibilityLabel("\(plan.title) 重要な予定")
    }

    private var clippedTitle: some View {
        Color.clear
            .overlay(alignment: .leading) {
                Text(plan.title)
                    .font(.system(size: displayTitleFontSize, weight: titleBold ? .bold : .regular))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(shouldStrikePastPlan, color: titleColor)
                    .shadow(color: textShadowColor, radius: 0.5, x: 0, y: 0.5)
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
            .fill(backgroundFillColor)
        }
    }

    @ViewBuilder
    private var borderShape: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: !continuesFromPreviousDay,
                roundsTrailing: !continuesToNextDay
            )
            .stroke(borderColor, lineWidth: 0.8)
        } else if labelStyle == .underline {
            Rectangle()
                .fill(markerColor)
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
        if labelStyle == .background {
            return .white
        }
        return color
    }

    private var timeColor: Color {
        if labelStyle == .background {
            return .white.opacity(0.76)
        }
        return color
    }

    private var backgroundFillColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.82, alpha: 0.68)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 0.72 : 0.84
        )
    }

    private var borderColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.9, alpha: 0.84)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 0.98 : 0.96
        )
    }

    private var markerColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.86, alpha: 0.76)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 1 : 0.98
        )
    }

    private var textShadowColor: Color {
        labelStyle == .background ? .black.opacity(usesLightPastDimStyle ? 0.28 : (colorScheme == .dark ? 0.24 : 0.18)) : .clear
    }

    private var labelOpacity: Double {
        usesLightPastDimStyle ? 1 : (isPastDimmed ? 0.38 : 1)
    }

    private var isPastDimmed: Bool {
        isPastPlan && dimPastPlans
    }

    private var usesLightPastDimStyle: Bool {
        colorScheme != .dark && isPastDimmed
    }

    private var timeFontSize: Double {
        max(4, displayTitleFontSize - 1)
    }

    private var labelHeight: CGFloat {
        max(9, CGFloat(displayTitleFontSize) + 3)
    }

    private var markerHeight: CGFloat {
        max(2, CGFloat(displayTitleFontSize) * 0.32)
    }

    private var markerBottomPadding: CGFloat {
        max(0.5, CGFloat(displayTitleFontSize) * 0.05)
    }

    private var textVerticalOffset: CGFloat {
        labelStyle == .underline ? -max(0.5, CGFloat(displayTitleFontSize) * 0.1) : 0
    }

    private var displayTitleFontSize: Double {
        CalendarPlanTitleMetrics.clamped(titleFontSize)
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
    @Environment(\.colorScheme) private var colorScheme

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
                    .font(.system(size: displayTitleFontSize, weight: titleBold ? .bold : .regular))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(isPastPlan && strikePastPlans, color: titleColor)
                    .shadow(color: textShadowColor, radius: 0.5, x: 0, y: 0.5)
                    .offset(y: textVerticalOffset)
            }
            .background(backgroundShape)
            .overlay(decorationOverlay)
            .clipped()
            .opacity(labelOpacity)
            .accessibilityLabel("\(plan.title) 複数日に跨る重要な予定")
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: roundsLeading,
                roundsTrailing: roundsTrailing
            )
            .fill(backgroundFillColor)
        }
    }

    @ViewBuilder
    private var decorationOverlay: some View {
        if labelStyle == .background {
            CalendarContinuationShape(
                roundsLeading: roundsLeading,
                roundsTrailing: roundsTrailing
            )
            .stroke(borderColor, lineWidth: 0.8)
        } else if labelStyle == .underline {
            Rectangle()
                .fill(markerColor)
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
        if labelStyle == .background {
            return .white
        }
        return color
    }

    private var backgroundFillColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.82, alpha: 0.68)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 0.72 : 0.84
        )
    }

    private var borderColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.9, alpha: 0.84)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 0.98 : 0.96
        )
    }

    private var markerColor: Color {
        if usesLightPastDimStyle {
            return CalendarPlanColorRendering.lightPastSurface(from: color, sourceAmount: 0.86, alpha: 0.76)
        }
        return CalendarPlanColorRendering.surface(
            from: color,
            colorScheme: colorScheme,
            intensity: colorScheme == .dark ? 1 : 0.98
        )
    }

    private var textShadowColor: Color {
        labelStyle == .background ? .black.opacity(usesLightPastDimStyle ? 0.28 : (colorScheme == .dark ? 0.24 : 0.18)) : .clear
    }

    private var labelOpacity: Double {
        usesLightPastDimStyle ? 1 : (isPastDimmed ? 0.38 : 1)
    }

    private var isPastDimmed: Bool {
        isPastPlan && dimPastPlans
    }

    private var usesLightPastDimStyle: Bool {
        colorScheme != .dark && isPastDimmed
    }

    private var markerHeight: CGFloat {
        max(2, CGFloat(displayTitleFontSize) * 0.32)
    }

    private var markerBottomPadding: CGFloat {
        max(0.5, CGFloat(displayTitleFontSize) * 0.05)
    }

    private var textVerticalOffset: CGFloat {
        labelStyle == .underline ? -max(0.5, CGFloat(displayTitleFontSize) * 0.1) : 0
    }

    private var displayTitleFontSize: Double {
        CalendarPlanTitleMetrics.clamped(titleFontSize)
    }

    private var isPastPlan: Bool {
        plan.endTime <= Date()
    }
}

private enum CalendarPlanColorRendering {
    static func surface(from color: Color, colorScheme: ColorScheme, intensity: CGFloat) -> Color {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: style)
        let source = UIColor(color).resolvedColor(with: traits)
        let base = LiminalThemeCatalog.resolvedDefinition(for: colorScheme).palette.surface

        return Color(uiColor: source.mixed(with: base, sourceAmount: intensity))
    }

    static func lightPastSurface(from color: Color, sourceAmount: CGFloat, alpha: CGFloat) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let source = UIColor(color).resolvedColor(with: traits)
        let darkened = source.mixed(with: .black, sourceAmount: sourceAmount)
        return Color(uiColor: darkened.withAlphaComponent(min(max(alpha, 0), 1)))
    }
}

private extension UIColor {
    func mixed(with base: UIColor, sourceAmount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var baseRed: CGFloat = 0
        var baseGreen: CGFloat = 0
        var baseBlue: CGFloat = 0
        var baseAlpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              base.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha) else {
            return withAlphaComponent(1)
        }

        let clampedAmount = min(max(sourceAmount, 0), 1)
        let baseAmount = 1 - clampedAmount

        return UIColor(
            red: red * clampedAmount + baseRed * baseAmount,
            green: green * clampedAmount + baseGreen * baseAmount,
            blue: blue * clampedAmount + baseBlue * baseAmount,
            alpha: 1
        )
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
