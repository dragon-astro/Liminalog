import SwiftUI
import SwiftData

/// プリセットの入口は1つ（しおり）。開いた先で「予定／一日」を切り替える（docs/36 §R C v3）。
enum PresetDrawerKind: String, CaseIterable, Identifiable {
    case plan
    case day

    /// 最後に開いたタブ。次に開いた時もそのタブから始める。
    static let storageKey = "presetDrawer.kind"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "予定"
        case .day: "一日"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: "bookmark.fill"
        case .day: "calendar.badge.clock"
        }
    }
}

/// カテゴリ列の左端に固定するプリセットの入口。カテゴリと同じ高さのカプセル。
struct PresetEntryButton: View {
    var identifier = "timeline-open-presets"
    let action: () -> Void

    var body: some View {
        Button {
            LiminalHaptics.openSheet()
            action()
        } label: {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LiminalTheme.accent)
                .frame(width: 40, height: 30)
                .background(Capsule().fill(LiminalTheme.elevated))
                .overlay(Capsule().stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1))
                // カテゴリ列の高さ（30pt＋上下2pt）を変えずに、押せる幅だけ少し広げる。
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("プリセットを開く")
        .accessibilityIdentifier(identifier)
    }
}

/// 固定した入口とスクロールするカテゴリの境目。
struct PresetEntryDivider: View {
    var body: some View {
        Rectangle()
            .fill(LiminalTheme.divider.opacity(0.9))
            .frame(width: 1, height: 20)
            .accessibilityHidden(true)
    }
}

/// 「予定｜一日」の切替。実績/予定の切替と同じ下線のタブ。
struct PresetKindTabs: View {
    @Binding var selection: PresetDrawerKind
    /// ナビゲーションバーの中央に置く時は、左右のボタンに押されないよう文字だけにする。
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 18 : 22) {
            ForEach(PresetDrawerKind.allCases) { kind in
                let isSelected = kind == selection
                Button {
                    guard !isSelected else { return }
                    LiminalHaptics.selection()
                    selection = kind
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            if !compact {
                                Image(systemName: kind.systemImage)
                                    .font(.caption.weight(.semibold))
                            }
                            Text(kind.title)
                                .font(.subheadline.weight(isSelected ? .bold : .semibold))
                                .fixedSize()
                        }
                        .foregroundStyle(isSelected ? LiminalTheme.text : LiminalTheme.secondaryText.opacity(0.76))

                        Capsule()
                            .fill(isSelected ? LiminalTheme.accent : Color.clear)
                            .frame(width: 24, height: 2)
                    }
                    .frame(minWidth: compact ? 36 : 52, minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.title)プリセット")
                .accessibilityValue(isSelected ? "選択中" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("preset-kind-\(kind.rawValue)")
            }
        }
    }
}

/// プリセット画面の右上に置く、設定へ戻るための控えめな文字リンク。
/// 管理の正は設定（カレンダーの⚙→プリセット）で、ここは同じ画面を開くだけ。
struct PresetManageLink: View {
    let action: () -> Void

    var body: some View {
        Button("管理", action: action)
            .font(.caption)
            .foregroundStyle(LiminalTheme.secondaryText)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityLabel("プリセットを管理")
            .accessibilityIdentifier("preset-manage")
    }
}

struct DayPresetApplyTarget: Identifiable {
    let id = UUID()
    let presetID: UUID
    let date: Date
}

/// 一日タブ。追加する日と、一日プリセットの一覧。選ぶと従来の確認画面（丸ごと追加）へ進む。
struct DayPresetDrawerList: View {
    @Environment(PlanPresetStore.self) private var presetStore
    @Query(sort: [SortDescriptor(\DayPreset.sortOrder), SortDescriptor(\DayPreset.createdAt)])
    private var presets: [DayPreset]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @Binding var targetDate: Date
    let allowsDateSelection: Bool
    let onChoose: (DayPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            targetDateRow
                .padding(.horizontal, CalendarDrawerStyle.horizontalInset)

            if presets.isEmpty {
                ContentUnavailableView(
                    "一日プリセットはありません",
                    systemImage: "calendar.badge.plus",
                    description: Text("設定 ＞ カレンダー ＞ 一日プリセットで作成できます。")
                )
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 8) {
                        ForEach(presets) { preset in
                            Button {
                                LiminalHaptics.openSheet()
                                onChoose(preset)
                            } label: {
                                DayPresetDrawerCard(
                                    preset: preset,
                                    items: items(for: preset),
                                    categories: categories
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("day-preset-card-\(preset.id)")
                        }
                    }
                    .padding(.horizontal, CalendarDrawerStyle.horizontalInset)
                    .padding(.bottom, 14)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var targetDateRow: some View {
        if allowsDateSelection {
            DatePicker("追加する日", selection: $targetDate, displayedComponents: .date)
                .font(.subheadline)
                .foregroundStyle(LiminalTheme.secondaryText)
                .accessibilityIdentifier("day-preset-drawer-date")
        } else {
            HStack {
                Text("追加する日")
                    .foregroundStyle(LiminalTheme.secondaryText)
                Spacer()
                Text(targetDate.japaneseMonthDayShortWeekday)
                    .foregroundStyle(LiminalTheme.text)
            }
            .font(.subheadline)
            .frame(minHeight: 34)
            .accessibilityElement(children: .combine)
        }
    }

    private func items(for preset: DayPreset) -> [PlanTemplateSnapshot] {
        guard case let .success(items) = presetStore.items(for: preset) else { return [] }
        return items
    }
}

private struct DayPresetDrawerCard: View {
    let preset: DayPreset
    let items: [PlanTemplateSnapshot]
    let categories: [Category]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: CategoryIconCatalog.displaySymbol(for: preset.icon))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(hex: preset.colorHex).liminalReadableDataColor())
                    Text(preset.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                        .lineLimit(1)
                }
                Text("\(preset.itemCount)件")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                DayPresetMiniBar(items: items, categories: categories)
                    .frame(height: 6)
            }
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(LiminalTheme.accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LiminalTheme.elevated))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LiminalTheme.divider.opacity(0.72), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(preset.name)、\(preset.itemCount)件")
        .accessibilityHint("内容を確認して追加")
    }
}

/// 一日の形をひと目で見分けるための24時間の細い帯（時刻指定の予定だけ）。
private struct DayPresetMiniBar: View {
    let items: [PlanTemplateSnapshot]
    let categories: [Category]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(LiminalTheme.divider.opacity(0.6))
                ForEach(Array(timedItems.enumerated()), id: \.offset) { _, item in
                    let start = CGFloat(max(0, min(item.startMinute, 1440))) / 1440
                    let end = CGFloat(max(0, min(item.endMinute, 1440))) / 1440
                    Rectangle()
                        .fill(color(for: item))
                        .frame(width: max(1, (end - start) * proxy.size.width - 0.5))
                        .offset(x: start * proxy.size.width)
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityHidden(true)
    }

    private var timedItems: [PlanTemplateSnapshot] {
        items.filter { !$0.isAllDay && !$0.isMemo && $0.endMinute > $0.startMinute }
    }

    private func color(for item: PlanTemplateSnapshot) -> Color {
        guard let id = item.categoryID, let category = categories.first(where: { $0.id == id }) else {
            return LiminalTheme.secondaryText.opacity(0.5)
        }
        return category.displayColor
    }
}
