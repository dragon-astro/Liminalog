import SwiftUI
import UIKit

/// Opaque, separate toolbar circles keep their geometry when the draft changes.
private struct EditorToolbarIcon: View {
    @Environment(\.isEnabled) private var isEnabled
    let name: String
    var emphasized = false

    var body: some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(emphasized ? LiminalTheme.accentFilledText : LiminalTheme.text)
            .frame(width: 44, height: 44)
            .background(emphasized ? LiminalTheme.accent : LiminalTheme.elevated, in: Circle())
            .overlay(Circle().strokeBorder(emphasized ? Color.clear : LiminalTheme.divider, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct EditorCancelButton: View {
    let hasChanges: Bool
    @Binding var showingConfirmation: Bool
    let discard: () -> Void

    var body: some View {
        Button {
            if hasChanges { showingConfirmation = true } else { discard() }
        } label: { EditorToolbarIcon(name: "xmark") }
        .buttonStyle(.plain)
        .accessibilityLabel("キャンセル")
        .confirmationDialog("編集中の内容を破棄してよろしいですか？",
                            isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("破棄する", role: .destructive, action: discard)
        }
    }
}

struct EditorSaveButton: View {
    let isEmphasized: Bool
    let canSave: Bool
    let save: () -> Void

    var body: some View {
        Button(action: save) { EditorToolbarIcon(name: "checkmark", emphasized: isEmphasized) }
            .buttonStyle(.plain)
            .accessibilityLabel("保存")
            .disabled(!canSave)
    }
}

struct EditorActionsMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) { EditorToolbarIcon(name: "ellipsis") }
            .buttonStyle(.plain)
            .accessibilityLabel("その他")
    }
}

extension View {
    func editorDismissGuard(hasChanges: Bool, showingConfirmation: Binding<Bool>) -> some View {
        interactiveDismissDisabled(hasChanges)
            .background(EditorDismissAttemptObserver(hasChanges: hasChanges) {
                showingConfirmation.wrappedValue = true
            }.frame(width: 0, height: 0))
    }
}

/// Keep SwiftUI's presentation delegate in the chain, so an unchanged swipe
/// still updates the presenting sheet's binding and nested sheets stay independent.
private struct EditorDismissAttemptObserver: UIViewControllerRepresentable {
    let hasChanges: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> ObserverController { ObserverController() }
    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.hasChanges = hasChanges
        controller.onAttempt = onAttempt
        controller.install()
        DispatchQueue.main.async { [weak controller] in controller?.install() }
    }
    static func dismantleUIViewController(_ controller: ObserverController, coordinator: ()) {
        controller.restore()
    }

    final class ObserverController: UIViewController, UIAdaptivePresentationControllerDelegate {
        var hasChanges = false
        var onAttempt: (() -> Void)?
        weak var observed: UIPresentationController?
        weak var previousDelegate: UIAdaptivePresentationControllerDelegate?

        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); install() }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); install() }

        func install() {
            // Child controllers inherit presentingViewController. Use the outer
            // presented container, whose delegate receives sheet swipe attempts.
            var candidate: UIViewController? = parent
            var sheet: UIPresentationController?
            while let controller = candidate {
                if controller.presentingViewController != nil {
                    sheet = controller.presentationController
                }
                candidate = controller.parent
            }
            guard let presentation = sheet else { return }
            if observed !== presentation { restore(); observed = presentation }
            if presentation.delegate !== self {
                previousDelegate = presentation.delegate
                presentation.delegate = self
            }
        }

        func restore() {
            if observed?.delegate === self { observed?.delegate = previousDelegate }
            observed = nil
            previousDelegate = nil
        }
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !hasChanges && (previousDelegate?.presentationControllerShouldDismiss?(presentationController) ?? true)
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if hasChanges { onAttempt?() }
            else { previousDelegate?.presentationControllerDidAttemptToDismiss?(presentationController) }
        }
        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            previousDelegate?.presentationControllerWillDismiss?(presentationController)
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            previousDelegate?.presentationControllerDidDismiss?(presentationController)
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if previousDelegate?.responds(to: selector) == true { return previousDelegate }
            return super.forwardingTarget(for: selector)
        }
    }
}

extension PlanTemplateSnapshot {
    var editorComparison: PlanTemplateSnapshot {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        copy.note = trimmedNote.isEmpty ? nil : trimmedNote
        copy.locationName = PlanExtraDetails.normalized(locationName)
        copy.urlString = PlanExtraDetails.normalized(urlString)
        return copy
    }
}
