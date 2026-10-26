import SwiftUI

/// Optional details share the same compact, growing input row in every editor.
struct EditorTextRow: View {
    let title: String
    let symbol: String
    @Binding var text: String
    let tint: Color
    var isURL = false

    var body: some View {
        PlanEditorCard(tint: tint) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint).padding(.top, 10).accessibilityHidden(true)
                TextField(title + "を追加", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .frame(minHeight: 44)
                    .keyboardType(isURL ? .URL : .default)
                    .textInputAutocapitalization(isURL ? .never : .sentences)
                    .autocorrectionDisabled(isURL)
                    .accessibilityLabel(title)
            }
        }
    }
}

struct ActualEditorIdentityCard: View {
    let category: Category?
    var isActive = false
    var isNew = false

    var body: some View {
        PlanEditorCard(tint: category?.displayColor ?? LiminalTheme.accent) {
            HStack(alignment: .top, spacing: 8) {
                CategoryPreviewIcon(category: category, size: 36).frame(height: 44)
                Text(category?.name ?? (isNew ? "カテゴリを選ぶ" : "カテゴリなしの実績"))
                    .font(.headline)
                    .foregroundStyle(category == nil ? LiminalTheme.secondaryText : LiminalTheme.text)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                Image(systemName: isActive ? "record.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(category?.displayColor ?? LiminalTheme.secondaryText)
                    .frame(width: 40, height: 44)
                    .accessibilityLabel(isActive ? "記録中" : "完了")
            }
        }
    }
}

@Observable
private final class EditorDateExpansion {
    var activeID: UUID?
    var activeBounds: CGRect = .zero
}

private struct EditorDateExpansionKey: EnvironmentKey {
    static let defaultValue: EditorDateExpansion? = nil
}

private extension EnvironmentValues {
    var editorDateExpansion: EditorDateExpansion? {
        get { self[EditorDateExpansionKey.self] }
        set { self[EditorDateExpansionKey.self] = newValue }
    }
}

private struct EditorDateSelectionScope: ViewModifier {
    @State private var expansion = EditorDateExpansion()
    func body(content: Content) -> some View {
        content.environment(\.editorDateExpansion, expansion)
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { event in
                if expansion.activeID != nil, !expansion.activeBounds.contains(event.location) { expansion.activeID = nil }
            })
    }
}

extension View {
    func editorDateSelectionScope() -> some View { modifier(EditorDateSelectionScope()) }
}

/// The time control stays native and compact in both date-selection modes.
struct EditorDateRow: View {
    let title: String
    @Binding var date: Date
    var range: ClosedRange<Date> = Date.distantPast...Date.distantFuture
    var showsTime = true
    @AppStorage("planEditor.datePickerStyle") private var style = "calendar"
    @Environment(\.editorDateExpansion) private var sharedExpansion
    @State private var localExpansion = EditorDateExpansion()
    @State private var id = UUID()
    @State private var bounds: CGRect = .zero

    private var expansion: EditorDateExpansion { sharedExpansion ?? localExpansion }
    private var isExpanded: Bool { expansion.activeID == id && style == "wheel" }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                if style == "wheel" {
                    Button {
                        expansion.activeBounds = bounds
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expansion.activeID = isExpanded ? nil : id
                        }
                    } label: {
                        Text(date, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                            .lineLimit(1).fixedSize()
                            .modifier(PlanValueCapsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title + "日")
                    .accessibilityValue(date.formatted(date: .abbreviated, time: .omitted))
                } else {
                    DatePicker(title + "日", selection: $date, in: range, displayedComponents: .date)
                        .labelsHidden().fixedSize().accessibilityIdentifier(title + "日")
                }
                if showsTime {
                    DatePicker(title + "時刻", selection: $date, in: range, displayedComponents: .hourAndMinute)
                        .labelsHidden().fixedSize().accessibilityIdentifier(title + "時刻")
                        .simultaneousGesture(TapGesture().onEnded { expansion.activeID = nil })
                }
            }
            .frame(minHeight: 34)
            if isExpanded {
                DatePicker(title + "日", selection: $date, in: range, displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                    .accessibilityIdentifier("editor-date-wheel")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(date.formatted(date: .abbreviated, time: showsTime ? .shortened : .omitted))
        .font(.subheadline)
        .datePickerStyle(.compact)
        .tint(LiminalTheme.text)
        .onGeometryChange(for: CGRect.self) { style == "wheel" ? $0.frame(in: .global) : .zero } action: { frame in
            bounds = frame
            if isExpanded { expansion.activeBounds = frame }
        }
        .onChange(of: style) { _, _ in expansion.activeID = nil }
        .onDisappear { if expansion.activeID == id { expansion.activeID = nil } }
    }
}
