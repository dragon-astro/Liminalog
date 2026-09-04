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
    @State private var preview: PlanTemplateReplacement?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("追加する予定") {
                    ForEach(request.applications.indices, id: \.self) { index in
                        let application = request.applications[index]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(application.snapshot.title.isEmpty ? (application.resolvedCategory?.name ?? "予定") : application.snapshot.title)
                                .font(.headline)
                            if application.snapshot.isAllDay {
                                Text("終日").foregroundStyle(.secondary)
                            } else if let interval = application.snapshot.interval(on: request.targetDate) {
                                Text(time(interval)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Picker("置き換え方", selection: $mode) {
                        ForEach(PlanTemplateReplacementMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                } footer: {
                    Text(mode == .keepRemainders
                         ? "新しい予定が優先されます。重ならない時間は残し、途中に入る場合は前後2つに分けます。"
                         : "重なる既存予定は、重ならない時間も含めて削除します。")
                }
                if let preview {
                    Section("変更される既存予定（\(preview.changes.count)件）") {
                        ForEach(preview.changes, id: \.id) { change in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(change.title).font(.headline)
                                Text(time(change.original)).foregroundStyle(.secondary)
                                if change.remaining.isEmpty {
                                    Label("削除", systemImage: "trash").foregroundStyle(.red)
                                } else {
                                    ForEach(change.remaining, id: \.start) { part in
                                        Label(time(part), systemImage: "arrow.turn.down.right")
                                    }
                                }
                            }
                            .font(.subheadline.monospacedDigit())
                        }
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.orange)
                        Button("内容を再確認") { reload() }
                    }
                }
            }
            .navigationTitle("置換の確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル", action: close) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("置換して適用", role: .destructive) { apply() }
                        .disabled(preview == nil || error != nil)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: mode) { _, _ in reload() }
        }
    }

    private func time(_ interval: DateInterval) -> String {
        let format: Date.FormatStyle = .dateTime.month().day().hour().minute().locale(Locale(identifier: "ja_JP"))
        return "\(interval.start.formatted(format)) → \(interval.end.formatted(format))"
    }

    private func reload() {
        preview = store.templateReplacementPreview(request.applications, to: request.targetDate, mode: mode)
        error = preview == nil ? "確定済みの予定・外部カレンダーの予定、または無効な時刻が含まれるため置換できません。" : nil
    }

    private func apply() {
        guard let preview else { return }
        guard store.applyPlanTemplates(request.applications, to: request.targetDate, approvedReplacement: preview) else {
            error = "予定が変更されたか、保存できませんでした。内容を再確認してください。"
            return
        }
        LiminalHaptics.commit()
        close()
        request.onApplied()
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
    final class Coordinator {
        var requestID: UUID?
        weak var host: UIViewController?

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
                }).environment(\.locale, Locale(identifier: "ja_JP")))
            host.modalPresentationStyle = .fullScreen
            host.view.backgroundColor = .systemBackground
            host.isModalInPresentation = true
            self.host = host
            presenter.present(host, animated: true)
        }
    }
}
