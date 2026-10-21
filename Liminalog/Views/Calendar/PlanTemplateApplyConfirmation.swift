import SwiftUI

struct PlanTemplateApplyRequest: Identifiable {
    let id = UUID()
    let applications: [PlanStore.TemplateApplication]
    let targetDate: Date
    let onApplied: () -> Void
}

struct PlanTemplateApplyConfirmationSheet: View {
    let request: PlanTemplateApplyRequest
    let store: ChapterStore
    let close: () -> Void
    @State private var mode = PlanTemplateReplacementMode.keepRemainders
    @State private var previews: [PlanTemplateReplacementMode: PlanTemplateReplacement] = [:]
    @State private var error: String?

    private var preview: PlanTemplateReplacement? { previews[mode] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(request.targetDate.japaneseMonthDayShortWeekday)
                        .font(.subheadline.weight(.semibold))
                    if let partial = previews[.keepRemainders] {
                        PlanReplacementComparison(applications: request.applications, targetDate: request.targetDate, partial: partial, mode: $mode)
                    }
                    if let error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).foregroundStyle(.orange)
                            Button("内容を再確認", action: reload)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(12)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: apply) {
                    Text(mode == .keepRemainders ? "時間だけ入れ替える" : "予定ごと入れ替える")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview == nil || error != nil)
                .accessibilityIdentifier("replacement-apply")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.background)
            }
            .navigationTitle("予定を入れ替える")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル", action: close) }
            }
            .onAppear(perform: reload)
        }
        .presentationBackground(LiminalTheme.plainSheetBackground)
        .presentationDetents([.fraction(0.75)])
        .presentationDragIndicator(.visible)
        .presentationCompactAdaptation(.sheet)
        .accessibilityIdentifier("plan-replacement-confirmation")
    }

    private func reload() {
        guard let partial = store.templateReplacementPreview(request.applications, to: request.targetDate, mode: .keepRemainders) else {
            previews = [:]
            error = "確定済み・外部カレンダーの予定、または無効な時刻が含まれるため入れ替えできません。"
            return
        }
        // Both choices describe the same fetched revisions, including category appearance.
        previews = [
            .keepRemainders: partial,
            .replaceWholePlans: PlanTemplateReplacement(mode: .replaceWholePlans,
                changes: partial.changes.map(\.removingEntirePlan))
        ]
        error = nil
    }

    private func apply() {
        guard let preview, error == nil else { return }
        guard store.applyPlanTemplates(request.applications, to: request.targetDate, approvedReplacement: preview) else {
            error = "予定が変更されたか、保存できませんでした。内容を再確認してください。"
            return
        }
        LiminalHaptics.commit()
        close()
        request.onApplied()
    }
}

/// All affected plans and all incoming items share the same vertical time axis.
/// Empty stretches are compressed; short plans retain enough room for their actual labels.
struct PlanReplacementComparison: View {
    let targetDate: Date
    let incoming: [Entry]
    let partial: PlanTemplateReplacement
    @Binding var mode: PlanTemplateReplacementMode
    @ScaledMetric(relativeTo: .caption) private var regularSlotHeight = 78.0
    @ScaledMetric(relativeTo: .caption) private var expandedSlotHeight = 114.0
    @ScaledMetric(relativeTo: .caption) private var minimumColumnWidth = 108.0

    struct Entry: Identifiable {
        let id: String
        let title: String
        let colorHex: String?
        let icon: String?
        let interval: DateInterval
        var isAllDay = false
        var isIncoming = false
    }

    init(targetDate: Date, incoming: [Entry], partial: PlanTemplateReplacement, mode: Binding<PlanTemplateReplacementMode>) {
        self.targetDate = targetDate
        self.incoming = incoming
        self.partial = partial
        self._mode = mode
    }

    init(applications: [PlanStore.TemplateApplication], targetDate: Date,
         partial: PlanTemplateReplacement, mode: Binding<PlanTemplateReplacementMode>) {
        self.init(targetDate: targetDate, incoming: applications.enumerated().compactMap { index, application in
            guard let interval = application.snapshot.interval(on: targetDate) else { return nil }
            return Entry(id: "new-\(index)", title: application.snapshot.title.isEmpty
                ? (application.resolvedCategory?.name ?? "予定") : application.snapshot.title,
                colorHex: application.resolvedCategory?.colorHex, icon: application.resolvedCategory?.icon,
                interval: interval, isAllDay: application.snapshot.isAllDay, isIncoming: true)
        }, partial: partial, mode: mode)
    }

    private func entries(for option: PlanTemplateReplacementMode?) -> [Entry] {
        let previous = partial.changes.flatMap { change in
            let ranges: [DateInterval] = option == nil ? [change.original]
                : option == .keepRemainders ? change.remaining : []
            return ranges.enumerated().map { index, interval in
                Entry(id: "\(change.id)-\(index)", title: change.title.isEmpty ? (change.categoryName ?? "予定") : change.title,
                      colorHex: change.colorHex, icon: change.icon, interval: interval)
            }
        }
        return previous + (option == nil ? [] : incoming)
    }

    var body: some View {
        let before = entries(for: nil)
        let afterPartial = entries(for: .keepRemainders)
        let afterWhole = entries(for: .replaceWholePlans)
        let timed = (before + incoming).filter { !$0.isAllDay }
        let slotHeight = timed.contains { $0.title.count > 7
            || !Calendar.current.isDate($0.interval.start, inSameDayAs: targetDate)
            || !Calendar.current.isDate($0.interval.end, inSameDayAs: targetDate)
        } ? expandedSlotHeight : regularSlotHeight
        let boundaries = Array(Set(timed.flatMap { [$0.interval.start, $0.interval.end] })).sorted()
        let heights = zip(boundaries, boundaries.dropFirst()).map { start, end in
            timed.contains { $0.interval.start < end && $0.interval.end > start } ? slotHeight : 18
        }
        // All-day additions sit above the timed axis in both outcomes.
        let allDayHeight = Double(incoming.filter(\.isAllDay).count) * slotHeight
        let totalHeight = heights.reduce(allDayHeight, +)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 6) {
                column(title: "現在", option: nil, entries: before, boundaries: boundaries,
                       heights: heights, allDayHeight: allDayHeight, totalHeight: totalHeight, slotHeight: slotHeight)
                column(title: "時間だけ", option: .keepRemainders, entries: afterPartial, boundaries: boundaries,
                       heights: heights, allDayHeight: allDayHeight, totalHeight: totalHeight, slotHeight: slotHeight)
                column(title: "予定ごと", option: .replaceWholePlans, entries: afterWhole, boundaries: boundaries,
                       heights: heights, allDayHeight: allDayHeight, totalHeight: totalHeight, slotHeight: slotHeight)
            }
            .containerRelativeFrame(.horizontal) { width, _ in max(width, minimumColumnWidth * 3 + 12) }
        }
        .accessibilityIdentifier("replacement-comparison")
    }

    private func column(title: String, option: PlanTemplateReplacementMode?, entries: [Entry],
                        boundaries: [Date], heights: [Double], allDayHeight: Double, totalHeight: Double, slotHeight: Double) -> some View {
        let selected = option == mode
        return VStack(spacing: 8) {
            if let option {
                Button { mode = option } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        Text(title).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title)入れ替える")
                .accessibilityIdentifier("replacement-option-\(option.rawValue)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(title).font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            ZStack(alignment: .topLeading) {
                ForEach(boundaries.indices, id: \.self) { index in
                    Divider().offset(y: allDayHeight + heights.prefix(index).reduce(0, +))
                }
                ForEach(Array(entries.filter(\.isAllDay).enumerated()), id: \.element.id) { index, entry in
                    card(entry, column: option?.rawValue ?? "before")
                        .frame(height: slotHeight - 4, alignment: .top)
                        .offset(y: Double(index) * slotHeight)
                }
                ForEach(entries.filter { !$0.isAllDay }) { entry in
                    let start = boundaries.firstIndex(of: entry.interval.start) ?? 0
                    let end = boundaries.firstIndex(of: entry.interval.end) ?? start
                    card(entry, column: option?.rawValue ?? "before")
                        .frame(height: max(slotHeight - 4, heights[start..<end].reduce(0, +) - 4), alignment: .top)
                        .offset(y: allDayHeight + heights.prefix(start).reduce(0, +))
                }
            }
            .frame(height: totalHeight, alignment: .top)
            .padding(4)
            .background(selected ? Color.accentColor.opacity(0.04) : Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .frame(minWidth: minimumColumnWidth, maxWidth: .infinity)
    }

    private func card(_ entry: Entry, column: String) -> some View {
        PlanReplacementPlanCard(title: entry.title, colorHex: entry.colorHex, icon: entry.icon,
            time: entry.isAllDay ? "終日" : PlanReplacementPlanCard.time(entry.interval, targetDate: targetDate),
            isIncoming: entry.isIncoming)
            .accessibilityIdentifier("replacement-\(column)-\(entry.id)")
    }
}

/// Uses the same category appearance as calendar plans, including uncategorized plans.
struct PlanReplacementPlanCard: View {
    let title: String
    let colorHex: String?
    let icon: String?
    let time: String
    var isIncoming = false

    private var color: Color { colorHex.map { Color.cachedDisplayHex($0) } ?? LiminalTheme.secondaryText }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: CategoryIconCatalog.displaySymbol(for: icon ?? "calendar"))
                    .foregroundStyle(color)
                Spacer(minLength: 0)
                if isIncoming { Image(systemName: "plus.circle.fill").foregroundStyle(color) }
            }
            .font(.caption2)
            Text(title).font(.caption.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(time).font(.caption2.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.24), in: RoundedRectangle(cornerRadius: 6))
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6).fill(color).frame(width: 3) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)、\(time)")
    }

    static func time(_ interval: DateInterval, targetDate: Date) -> String {
        let calendar = Calendar.current
        func label(_ date: Date) -> String {
            let clock = String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
            guard !calendar.isDate(date, inSameDayAs: targetDate) else { return clock }
            return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date)) \(clock)"
        }
        return "\(label(interval.start))–\(label(interval.end))"
    }
}

/// The drawer is itself a sheet. Present confirmation above the current sheet,
/// rather than asking its obscured timeline to present a competing SwiftUI sheet.
struct PlanTemplateApplyConfirmationPresenter: UIViewControllerRepresentable {
    @Binding var request: PlanTemplateApplyRequest?
    let store: ChapterStore

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let request, context.coordinator.requestID != request.id else { return }
        context.coordinator.requestID = request.id
        let binding = $request
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            context.coordinator.present(request, from: controller, binding: binding, store: store)
        }
    }
    final class Coordinator: NSObject, UISheetPresentationControllerDelegate {
        var requestID: UUID?
        weak var host: UIViewController?
        var activeBinding: Binding<PlanTemplateApplyRequest?>?

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            activeBinding?.wrappedValue = nil
            activeBinding = nil
            requestID = nil
            host = nil
        }

        func present(_ request: PlanTemplateApplyRequest, from controller: UIViewController,
                     binding: Binding<PlanTemplateApplyRequest?>, store: ChapterStore, attempt: Int = 0) {
            guard binding.wrappedValue?.id == request.id else { requestID = nil; return }
            guard attempt < 40 else { binding.wrappedValue = nil; requestID = nil; return }
            // Fixed-time taps close the drawer; duration drops restore it. Wait
            // until that specific transition has finished in either direction.
            let retry = { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.present(request, from: controller, binding: binding, store: store, attempt: attempt + 1)
            }
            guard var presenter = controller.view.window?.rootViewController else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: retry)
                return
            }
            while let presented = presenter.presentedViewController {
                if presented.isBeingDismissed || presented.isBeingPresented || presented.viewIfLoaded?.window == nil {
                    if let transition = presented.transitionCoordinator {
                        transition.animate(alongsideTransition: nil) { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: retry)
                        }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: retry)
                    }
                    return
                }
                presenter = presented
            }
            let host = UIHostingController(rootView: PlanTemplateApplyConfirmationSheet(
                request: request, store: store, close: {
                    self.host?.dismiss(animated: true)
                    binding.wrappedValue = nil
                    self.requestID = nil
                    self.host = nil
                    self.activeBinding = nil
                }).environment(\.locale, Locale(identifier: "ja_JP")))
            host.modalPresentationStyle = .pageSheet
            if let sheet = host.sheetPresentationController {
                sheet.detents = [.custom(identifier: .init("replacementCompact")) { $0.maximumDetentValue * 0.75 }]
                sheet.prefersGrabberVisible = true
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.delegate = self
            }
            activeBinding = binding
            host.view.backgroundColor = .systemBackground
            self.host = host
            presenter.present(host, animated: true)
        }
    }
}
