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
    @State private var selectedPlanID: UUID?
    @State private var pendingDeletion: DeletionRequest?
    @State private var revealedDeletionID: UUID?

    private struct DeletionRequest {
        let id: UUID
        let title: String
        let spansDays: Bool
    }

    init(date: Date, highlightedPlanID: UUID?, visibleCategoryIDs: Set<UUID>?,
         onClose: @escaping () -> Void, onExpand: @escaping () -> Void,
         onCreate: @escaping () -> Void, onEdit: @escaping (PlanBlock) -> Void,
         onDelete: @escaping (PlanBlock) -> Bool) {
        self.date = date
        self.highlightedPlanID = highlightedPlanID
        self.visibleCategoryIDs = visibleCategoryIDs
        self.onClose = onClose
        self.onExpand = onExpand
        self.onCreate = onCreate
        self.onEdit = onEdit
        self.onDelete = onDelete
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
                    .accessibilityIdentifier("calendar-drawer-date")
                    .accessibilityValue(DailyCardSnapshot.dayIdentifier(for: date, calendar: .current))
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
            ScrollView {
                drawerContent
                    .padding(.bottom, 16)
            }
            .scrollDisabled(transfer?.isDragging == true)
            .accessibilityIdentifier("calendar-drawer-scroll")
            .scrollEdgeEffectHidden(true, for: .bottom)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        // Extend the scroll viewport itself to the sheet bottom. No fixed footer or
        // opaque safe-area band may cover the last editor/transfer controls.
        .ignoresSafeArea(.container, edges: .bottom)
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

    private var drawerContent: some View {
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
                        swipeRow(plan)
                        Divider().padding(.leading, 50)
                    }
                }
                .transition(contentTransition(from: .leading))
            }
        }
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.24), value: selectedPlanID)
    }

    private func swipeRow(_ plan: PlanBlock) -> some View {
        let revealed = revealedDeletionID == plan.id
        let canDelete = !store.isPlanScheduleLocked(plan)
        let reveal: (() -> Void)? = canDelete ? { revealedDeletionID = plan.id } : nil
        return ZStack(alignment: .trailing) {
            if canDelete && revealed {
                Button(role: .destructive) {
                    pendingDeletion = DeletionRequest(id: plan.id, title: plan.title,
                        spansDays: !Calendar.current.isDate(plan.startTime, inSameDayAs: plan.endTime.addingTimeInterval(-0.001)))
                } label: {
                    Label("削除", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 76, height: 52)
                        .foregroundStyle(.white)
                        .background(Color.red)
                }
                .buttonStyle(.plain).tint(.red)
                .accessibilityIdentifier("calendar-drawer-delete-\(plan.id)")
            }
            planSurface(plan, onTap: {
                if revealed { revealedDeletionID = nil }
                else { selectedPlanID = plan.id }
            }, onSwipeLeft: reveal, onSwipeRight: { revealedDeletionID = nil },
               insets: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                .background(CalendarDrawerStyle.background)
                .offset(x: revealed ? -76 : 0)
        }
        .clipped()
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.2), value: revealed)
    }

    @ViewBuilder
    private func planSurface(_ plan: PlanBlock, onTap: @escaping () -> Void,
                             onSwipeLeft: (() -> Void)? = nil, onSwipeRight: (() -> Void)? = nil,
                             insets: EdgeInsets = EdgeInsets()) -> some View {
        if let transfer {
            interactivePlanRow(plan, transfer: transfer, onTap: onTap,
                               onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight, insets: insets)
                .accessibilityAction(.default) { onTap() }
                .accessibilityActions {
                    Button("複製") { transfer.begin(plan, mode: .copy) }
                    if !store.isPlanScheduleLocked(plan), plan.sourceEventID == nil {
                        Button("別の日へ移動") { transfer.begin(plan, mode: .move) }
                    }
                }
        } else {
            Button(action: onTap) { row(plan, showsDisclosure: false).padding(insets) }
                .buttonStyle(.plain)
                .accessibilityAction(named: "複製") { transfer?.begin(plan, mode: .copy) }
        }
    }

    private func interactivePlanRow(_ plan: PlanBlock, transfer: CalendarMonthTransferInteraction,
                                    onTap: @escaping () -> Void, onSwipeLeft: (() -> Void)?,
                                    onSwipeRight: (() -> Void)?, insets: EdgeInsets) -> some View {
        row(plan, showsDisclosure: false)
            // The visible row padding is part of the touch surface, not dead space
            // where the ancestor ScrollView can consume the user's hold.
            .padding(insets)
            .overlay { dragSurface(plan, transfer: transfer, onTap: onTap,
                                   onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("calendar-drawer-plan-\(plan.id)")
    }

    private func dragSurface(_ plan: PlanBlock, transfer: CalendarMonthTransferInteraction,
                             onTap: @escaping () -> Void, onSwipeLeft: (() -> Void)?,
                             onSwipeRight: (() -> Void)?) -> some View {
        return TimelinePlanPresetLongPressDragSurface(
            minimumDuration: 0.28, maximumDistance: 12,
            onTap: onTap, onSwipeRight: onSwipeRight, onSwipeLeft: onSwipeLeft,
            dragEnabled: !store.isPlanScheduleLocked(plan) && plan.sourceEventID == nil
        ) { event in
            switch event {
            case .began(let point):
                transfer.begin(plan, mode: .move, dragging: true)
                revealedDeletionID = nil
                LiminalHaptics.selection()
                transfer.updateDrag(at: point)
            case .changed(let point): transfer.updateDrag(at: point)
            case .ended(let point): transfer.finishDrag(at: point)
            case .cancelled: transfer.finishDrag(at: nil)
            }
        }
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
            planSurface(plan, onTap: { onEdit(plan) }, onSwipeRight: returnToList)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(plan.category?.name ?? "カテゴリ未設定")
                    Spacer()
                    Label(plan.isPublic ? "友達に公開" : "自分だけ", systemImage: plan.isPublic ? "person.2" : "lock")
                }
                .font(.caption).foregroundStyle(LiminalTheme.secondaryText)
                if let note = plan.note, !note.isEmpty {
                    Text(note).font(.subheadline).foregroundStyle(LiminalTheme.text)
                }
                Button { onEdit(plan) } label: {
                    Label("予定を編集", systemImage: "pencil")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .background(LiminalTheme.accent.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain).foregroundStyle(LiminalTheme.accent)
                .accessibilityIdentifier("calendar-drawer-edit")
                transferButtons(plan)
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
            .accessibilityIdentifier("calendar-drawer-copy")
            Button { transfer?.begin(plan, mode: .move) } label: {
                Label("移動", systemImage: "arrow.up.right").frame(maxWidth: .infinity, minHeight: 36)
            }
            .disabled(store.isPlanScheduleLocked(plan) || plan.sourceEventID != nil)
            .accessibilityIdentifier("calendar-drawer-move")
        }
        .buttonStyle(.bordered).tint(LiminalTheme.accent)
    }

    private func timeLabel(_ plan: PlanBlock) -> String {
        let end = plan.isAllDay ? plan.endTime.addingTimeInterval(-1) : plan.endTime
        if !Calendar.current.isDate(plan.startTime, inSameDayAs: end) {
            return "\(plan.startTime.japaneseMonthDayShortWeekday)\(plan.isAllDay ? "" : " " + plan.startTime.shortTime) – \(end.japaneseMonthDayShortWeekday)\(plan.isAllDay ? " 終日" : " " + end.shortTime)"
        }
        return plan.isAllDay ? "終日" : "\(plan.startTime.shortTime) – \(plan.endTime.shortTime)"
    }
}
