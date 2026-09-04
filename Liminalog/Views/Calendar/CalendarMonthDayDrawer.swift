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
    @Environment(\.monthPlanTransfer) private var transfer
    @Environment(ChapterStore.self) private var store
    @Query private var queriedPlans: [PlanBlock]
    let date: Date
    let highlightedPlanID: UUID?
    let visibleCategoryIDs: Set<UUID>?
    let onClose: () -> Void
    let onExpand: () -> Void
    let onCreate: () -> Void
    let onEdit: (PlanBlock) -> Void
    let onDelete: (PlanBlock) -> Bool
    let onSelectionChanged: (Bool) -> Void
    @State private var selectedPlanID: UUID?
    @State private var pendingDeletion: DeletionRequest?

    private struct DeletionRequest {
        let id: UUID
        let title: String
        let spansDays: Bool
    }

    init(date: Date, highlightedPlanID: UUID?, visibleCategoryIDs: Set<UUID>?,
         onClose: @escaping () -> Void, onExpand: @escaping () -> Void,
         onCreate: @escaping () -> Void, onEdit: @escaping (PlanBlock) -> Void,
         onDelete: @escaping (PlanBlock) -> Bool,
         onSelectionChanged: @escaping (Bool) -> Void) {
        self.date = date
        self.highlightedPlanID = highlightedPlanID
        self.visibleCategoryIDs = visibleCategoryIDs
        self.onClose = onClose
        self.onExpand = onExpand
        self.onCreate = onCreate
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onSelectionChanged = onSelectionChanged
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
                if selectedPlanID != nil && transfer?.request == nil {
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
                if transfer?.request == nil {
                Button(action: onCreate) {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
                .accessibilityLabel("この日に予定を追加")
                .disabled(!CalendarPlanCreationPreset.allowsCreation(for: date))
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("日間タイムラインを開く")
                }
                Button {
                    if transfer?.request != nil { transfer?.cancel() }
                    else { onClose() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                .accessibilityLabel(transfer?.request == nil ? "当日の予定を閉じる" : "日付選択をキャンセル")
            }
            .buttonStyle(.plain)
            .foregroundStyle(LiminalTheme.accent)
            .frame(height: CalendarDrawerStyle.headerHeight)
            .padding(.horizontal, CalendarDrawerStyle.horizontalInset)
            Divider()
            ZStack(alignment: .topLeading) {
                    if let plan = plans.first(where: { $0.id == selectedPlanID }) {
                        ScrollView {
                            detail(plan)
                        }
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                transferButtons(plan)
                            }
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
                        List {
                            ForEach(plans) { plan in
                                    planButton(plan)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(CalendarDrawerStyle.background)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if !store.isPlanScheduleLocked(plan) {
                                            Button(role: .destructive) {
                                                pendingDeletion = DeletionRequest(
                                                    id: plan.id, title: plan.title,
                                                    spansDays: !Calendar.current.isDate(plan.startTime, inSameDayAs: plan.endTime.addingTimeInterval(-0.001))
                                                )
                                            } label: { Label("削除", systemImage: "trash") }
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.vertical, 0, for: .scrollContent)
                        .transition(contentTransition(from: .leading))
                    }
                }
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.24), value: selectedPlanID)
            .clipped()
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onChange(of: selectedPlanID, initial: true) { _, id in onSelectionChanged(id != nil) }
        .onChange(of: highlightedPlanID) { _, id in selectedPlanID = id }
        .onChange(of: plans.map(\.id)) { _, ids in
            if let selectedPlanID, !ids.contains(selectedPlanID) { self.selectedPlanID = nil }
        }
        .accessibilityIdentifier("calendar-month-day-drawer")
        .interactiveDismissDisabled(transfer?.request != nil)
        .alert("予定を削除しますか？", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { request in
            Button("削除", role: .destructive) { deletePlan(id: request.id) }
            Button("キャンセル", role: .cancel) { pendingDeletion = nil }
        } message: { request in
            Text("「\(request.title)」を削除します。\(request.spansDays ? "全日程が対象です。" : "")この操作は取り消せません。")
        }
        .alert("予定を変更できません", isPresented: Binding(
            get: { transfer?.error != nil && transfer?.request == nil }, set: { if !$0 { transfer?.error = nil } }
        )) {
            Button("閉じる", role: .cancel) { transfer?.error = nil }
        } message: { Text(transfer?.error ?? "") }
    }

    @ViewBuilder
    private func planButton(_ plan: PlanBlock) -> some View {
        planSurface(plan, onTap: { selectedPlanID = plan.id })
            .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private func planSurface(_ plan: PlanBlock, onTap: @escaping () -> Void) -> some View {
        if let transfer, !store.isPlanScheduleLocked(plan), plan.sourceEventID == nil {
            interactivePlanRow(plan, transfer: transfer, onTap: onTap)
                .accessibilityAction(.default) { onTap() }
                .accessibilityActions {
                    Button("複製") { transfer.begin(plan, mode: .copy) }
                    Button("別の日へ移動") { transfer.begin(plan, mode: .move) }
                }
        } else {
            Button(action: onTap) { row(plan, showsDisclosure: false) }
                .buttonStyle(.plain)
                .accessibilityAction(named: "複製") { transfer?.begin(plan, mode: .copy) }
        }
    }

    private func interactivePlanRow(_ plan: PlanBlock, transfer: CalendarMonthTransferInteraction,
                                    onTap: @escaping () -> Void) -> some View {
        row(plan, showsDisclosure: false)
            .overlay { dragSurface(plan, transfer: transfer, onTap: onTap) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    private func dragSurface(_ plan: PlanBlock, transfer: CalendarMonthTransferInteraction,
                             onTap: @escaping () -> Void) -> some View {
        let onBack: (() -> Void)? = selectedPlanID == nil ? nil : { returnToList() }
        return TimelinePlanPresetLongPressDragSurface(
            minimumDuration: monthDragMinimumDuration, maximumDistance: 12,
            onTap: onTap, onSwipeRight: onBack
        ) { event in
            switch event {
            case .began(let point):
                transfer.begin(plan, mode: .move, dragging: true)
                LiminalHaptics.selection()
                transfer.updateDrag(at: point)
            case .changed(let point): transfer.updateDrag(at: point)
            case .ended(let point): transfer.finishDrag(at: point)
            case .cancelled: transfer.finishDrag(at: nil)
            }
        }
    }

    /// Simulator automation cannot hold before dragging. Only bypass the recognition delay
    /// for opt-in Debug QA; all movement/retreat/drop handling remains the production path.
    private var monthDragMinimumDuration: TimeInterval {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LiminalogDebugImmediateMonthDrag") { return 0 }
        #endif
        return 0.28
    }

    private func deletePlan(id: UUID) {
        guard let plan = plans.first(where: { $0.id == id }) else {
            transfer?.error = "削除する予定が見つかりません。"
            return
        }
        guard !store.isPlanScheduleLocked(plan) else {
            transfer?.error = "今日以前の時間指定の予定は削除できません。"
            return
        }
        guard onDelete(plan) else {
            LiminalHaptics.failure()
            transfer?.error = "予定を削除できませんでした。時間をおいてもう一度試してください。"
            return
        }
        LiminalHaptics.commit()
    }

    private func row(_ plan: PlanBlock, showsDisclosure: Bool = true) -> some View {
        HStack(spacing: 10) {
            CategoryPreviewIcon(category: plan.category, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.title).font(.subheadline.weight(.semibold)).foregroundStyle(LiminalTheme.text)
                Text(timeLabel(plan)).font(.caption.monospacedDigit()).foregroundStyle(LiminalTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if plan.isImportant { Image(systemName: "star.fill").foregroundStyle(LiminalTheme.reward) }
            if showsDisclosure {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(LiminalTheme.tertiaryText)
            }
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
            planSurface(plan, onTap: { onEdit(plan) })
            VStack(alignment: .leading, spacing: 12) {
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
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                guard transfer?.request == nil else { return }
                if CalendarMonthDayDrawerNavigation.shouldReturnToList(
                    horizontal: value.translation.width, vertical: value.translation.height
                ) { returnToList() }
            })
        }
        .padding(16)
    }

    private func transferButtons(_ plan: PlanBlock) -> some View {
            HStack(spacing: 12) {
                Button { transfer?.begin(plan, mode: .copy) } label: {
                    Label("複製", systemImage: "doc.on.doc").frame(maxWidth: .infinity, minHeight: 36)
                }
                Button { transfer?.begin(plan, mode: .move) } label: {
                    Label("移動", systemImage: "arrow.up.right").frame(maxWidth: .infinity, minHeight: 36)
                }
                .disabled(store.isPlanScheduleLocked(plan) || plan.sourceEventID != nil)
            }
            .buttonStyle(.bordered).tint(LiminalTheme.accent)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(CalendarDrawerStyle.background)
    }

    private func timeLabel(_ plan: PlanBlock) -> String {
        let end = plan.isAllDay ? plan.endTime.addingTimeInterval(-1) : plan.endTime
        if !Calendar.current.isDate(plan.startTime, inSameDayAs: end) {
            return "\(plan.startTime.japaneseMonthDayShortWeekday)\(plan.isAllDay ? "" : " " + plan.startTime.shortTime) – \(end.japaneseMonthDayShortWeekday)\(plan.isAllDay ? " 終日" : " " + end.shortTime)"
        }
        return plan.isAllDay ? "終日" : "\(plan.startTime.shortTime) – \(plan.endTime.shortTime)"
    }
}
