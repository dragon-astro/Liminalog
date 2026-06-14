import SwiftData
import SwiftUI
import WidgetKit

struct WidgetSettingsView: View {
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \CategorySet.sortOrder) private var categorySets: [CategorySet]

    @AppStorage("recording.widget.smallCategoryID.0", store: UserDefaults(suiteName: SharedModelContainer.appGroupID))
    private var smallWidgetCategoryID0 = ""
    @AppStorage("recording.widget.smallCategoryID.1", store: UserDefaults(suiteName: SharedModelContainer.appGroupID))
    private var smallWidgetCategoryID1 = ""
    @AppStorage("recording.widget.smallCategoryID.2", store: UserDefaults(suiteName: SharedModelContainer.appGroupID))
    private var smallWidgetCategoryID2 = ""
    @AppStorage("recording.widget.smallCategoryID.3", store: UserDefaults(suiteName: SharedModelContainer.appGroupID))
    private var smallWidgetCategoryID3 = ""
    @AppStorage("recording.widget.mediumCategorySetMode", store: UserDefaults(suiteName: SharedModelContainer.appGroupID))
    private var mediumWidgetCategorySetMode = "current"
    @AppStorage("recording.widget.mediumCategorySetID", store: UserDefaults(suiteName: SharedModelContainer.appGroupID))
    private var mediumWidgetCategorySetID = ""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("小さいウィジェット")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                    Text("4枠を指定します。未設定の枠は現在のテーブル順で補完されます。")
                        .font(.caption)
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)

                ForEach(0..<4, id: \.self) { index in
                    Picker("枠\(index + 1)", selection: smallWidgetCategoryBinding(for: index)) {
                        Text("自動").tag("")
                        ForEach(selectableSmallWidgetCategories(for: index)) { category in
                            Text(category.name).tag(category.id.uuidString)
                        }
                    }
                }
            } header: {
                Text("小さいウィジェット")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("大きいウィジェット")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                    Text("8枠の表示元を選びます。")
                        .font(.caption)
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)

                Picker("表示元", selection: mediumWidgetModeBinding) {
                    Text("現在のテーブル").tag("current")
                    Text("固定テーブル").tag("fixed")
                }

                if mediumWidgetCategorySetMode == "fixed" {
                    Picker("テーブル", selection: mediumWidgetCategorySetBinding) {
                        Text("自動").tag("")
                        ForEach(categorySets) { set in
                            Text(set.name).tag(set.id.uuidString)
                        }
                    }
                }
            } header: {
                Text("大きいウィジェット")
            } footer: {
                Text("カテゴリやテーブル自体の追加・編集はカテゴリ管理から行えます。")
            }
        }
        .navigationTitle("ウィジェット")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var mediumWidgetModeBinding: Binding<String> {
        Binding {
            mediumWidgetCategorySetMode == "fixed" ? "fixed" : "current"
        } set: { newValue in
            mediumWidgetCategorySetMode = newValue
            if newValue == "current" {
                mediumWidgetCategorySetID = ""
            } else if mediumWidgetCategorySetID.isEmpty, let firstSet = categorySets.first {
                mediumWidgetCategorySetID = firstSet.id.uuidString
            }
            reloadRecordingWidget()
        }
    }

    private var mediumWidgetCategorySetBinding: Binding<String> {
        Binding {
            guard categorySets.contains(where: { $0.id.uuidString == mediumWidgetCategorySetID }) else {
                return ""
            }
            return mediumWidgetCategorySetID
        } set: { newValue in
            mediumWidgetCategorySetID = newValue
            reloadRecordingWidget()
        }
    }

    private func smallWidgetCategoryBinding(for index: Int) -> Binding<String> {
        Binding {
            let value = smallWidgetCategoryID(for: index)
            guard categories.contains(where: { $0.id.uuidString == value }) else { return "" }
            return value
        } set: { newValue in
            setSmallWidgetCategoryID(newValue, for: index)
            reloadRecordingWidget()
        }
    }

    private func selectableSmallWidgetCategories(for index: Int) -> [Category] {
        let currentValue = smallWidgetCategoryID(for: index)
        let selectedElsewhere = Set((0..<4).compactMap { slot -> String? in
            guard slot != index else { return nil }
            let value = smallWidgetCategoryID(for: slot)
            return value.isEmpty ? nil : value
        })
        return categories.filter { category in
            let value = category.id.uuidString
            return value == currentValue || !selectedElsewhere.contains(value)
        }
    }

    private func smallWidgetCategoryID(for index: Int) -> String {
        switch index {
        case 0: smallWidgetCategoryID0
        case 1: smallWidgetCategoryID1
        case 2: smallWidgetCategoryID2
        case 3: smallWidgetCategoryID3
        default: ""
        }
    }

    private func setSmallWidgetCategoryID(_ value: String, for index: Int) {
        switch index {
        case 0: smallWidgetCategoryID0 = value
        case 1: smallWidgetCategoryID1 = value
        case 2: smallWidgetCategoryID2 = value
        case 3: smallWidgetCategoryID3 = value
        default: break
        }
    }

    private func reloadRecordingWidget() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "RecordingGridWidget")
    }
}

#Preview("Widget Settings") {
    NavigationStack {
        WidgetSettingsView()
    }
    .liminalogPreviewEnvironment()
}
