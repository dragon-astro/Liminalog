import SwiftUI
import SwiftData

enum CalendarMonthDayDrawerNavigation {
    static func shouldReturnToList(horizontal: CGFloat, vertical: CGFloat) -> Bool {
        horizontal > 70 && horizontal > abs(vertical) * 1.5
    }
}

/// 月間を操作可能なまま残す当日一覧。日付ごとの狭いQueryだけを持つ。
struct CalendarMonthDayDrawer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var queriedPlans: [PlanBlock]
    let date: Date
    let highlightedPlanID: UUID?
    let visibleCategoryIDs: Set<UUID>?
    let onClose: () -> Void
    let onExpand: () -> Void
    let onCreate: () -> Void
    let onEdit: (PlanBlock) -> Void
    @State private var selectedPlanID: UUID?

    init(date: Date, highlightedPlanID: UUID?, visibleCategoryIDs: Set<UUID>?,
         onClose: @escaping () -> Void, onExpand: @escaping () -> Void,
         onCreate: @escaping () -> Void, onEdit: @escaping (PlanBlock) -> Void) {
        self.date = date
        self.highlightedPlanID = highlightedPlanID
        self.visibleCategoryIDs = visibleCategoryIDs
        self.onClose = onClose
        self.onExpand = onExpand
        self.onCreate = onCreate
        self.onEdit = onEdit
        _selectedPlanID = State(initialValue: highlightedPlanID)
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _queriedPlans = Query(filter: #Predicate<PlanBlock> {
            $0.startTime < end && $0.endTime > start
        }, sort: [SortDescriptor(\PlanBlock.startTime), SortDescriptor(\PlanBlock.createdAt)])
    }

    private var plans: [PlanBlock] {
        queriedPlans.filter { plan in
            guard let visibleCategoryIDs else { return true }
            return plan.category.map { visibleCategoryIDs.contains($0.id) } ?? false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if selectedPlanID != nil {
                    Button(action: returnToList) {
                        Image(systemName: "chevron.left").frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("当日の予定一覧に戻る")
                }
                Text(date.japaneseMonthDayShortWeekday)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LiminalTheme.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onCreate) {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
                .accessibilityLabel("この日に予定を追加")
                .disabled(!CalendarPlanCreationPreset.allowsCreation(for: date))
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("日間タイムラインを開く")
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                .accessibilityLabel("当日の予定を閉じる")
            }
            .buttonStyle(.plain)
            .foregroundStyle(LiminalTheme.accent)
            .frame(height: CalendarDrawerStyle.headerHeight)
            .padding(.horizontal, CalendarDrawerStyle.horizontalInset)
            Divider()
            ScrollView {
                ZStack(alignment: .topLeading) {
                    if let plan = plans.first(where: { $0.id == selectedPlanID }) {
                        detail(plan)
                            .accessibilityAction(named: "当日の予定一覧に戻る", returnToList)
                            .transition(contentTransition(from: .trailing))
                    } else if plans.isEmpty {
                        VStack(spacing: 10) {
                            Text("予定はありません").foregroundStyle(LiminalTheme.secondaryText)
                            Button("予定を追加", systemImage: "plus", action: onCreate)
                                .disabled(!CalendarPlanCreationPreset.allowsCreation(for: date))
                        }
                        .frame(maxWidth: .infinity).padding(24)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(plans) { plan in
                                Button { selectedPlanID = plan.id } label: {
                                    row(plan).padding(.horizontal, 14).padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 50)
                            }
                        }
                        .transition(contentTransition(from: .leading))
                    }
                }
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.24), value: selectedPlanID)
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                guard selectedPlanID != nil else { return }
                if CalendarMonthDayDrawerNavigation.shouldReturnToList(
                    horizontal: value.translation.width, vertical: value.translation.height
                ) { returnToList() }
            })
        }
        .onChange(of: highlightedPlanID) { _, id in selectedPlanID = id }
        .onChange(of: plans.map(\.id)) { _, ids in
            if let selectedPlanID, !ids.contains(selectedPlanID) { self.selectedPlanID = nil }
        }
        .accessibilityIdentifier("calendar-month-day-drawer")
    }

    private func row(_ plan: PlanBlock) -> some View {
        HStack(spacing: 10) {
            CategoryPreviewIcon(category: plan.category, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.title).font(.subheadline.weight(.semibold)).foregroundStyle(LiminalTheme.text)
                Text(timeLabel(plan)).font(.caption.monospacedDigit()).foregroundStyle(LiminalTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if plan.isImportant { Image(systemName: "star.fill").foregroundStyle(LiminalTheme.reward) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(LiminalTheme.tertiaryText)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }

    private func returnToList() {
        LiminalHaptics.selection()
        selectedPlanID = nil
    }

    private func contentTransition(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    private func detail(_ plan: PlanBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            row(plan)
            HStack {
                Text(plan.category?.name ?? "カテゴリ未設定")
                Spacer()
                Label(plan.isPublic ? "友達に公開" : "自分だけ", systemImage: plan.isPublic ? "person.2" : "lock")
            }
            .font(.caption).foregroundStyle(LiminalTheme.secondaryText)
            if let note = plan.note, !note.isEmpty { Text(note).font(.subheadline).foregroundStyle(LiminalTheme.text) }
            Button { onEdit(plan) } label: {
                Label("予定を編集", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    .background(LiminalTheme.accent.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain).foregroundStyle(LiminalTheme.accent)
        }
        .padding(16)
    }

    private func timeLabel(_ plan: PlanBlock) -> String {
        let end = plan.isAllDay ? plan.endTime.addingTimeInterval(-1) : plan.endTime
        if !Calendar.current.isDate(plan.startTime, inSameDayAs: end) {
            return "\(plan.startTime.japaneseMonthDayShortWeekday)\(plan.isAllDay ? "" : " " + plan.startTime.shortTime) – \(end.japaneseMonthDayShortWeekday)\(plan.isAllDay ? " 終日" : " " + end.shortTime)"
        }
        return plan.isAllDay ? "終日" : "\(plan.startTime.shortTime) – \(plan.endTime.shortTime)"
    }
}
