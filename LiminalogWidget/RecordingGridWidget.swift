import ActivityKit
import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

private enum WidgetDataError: LocalizedError {
    case invalidCategoryID
    case categoryNotFound

    var errorDescription: String? {
        switch self {
        case .invalidCategoryID:
            "カテゴリIDが正しくありません"
        case .categoryNotFound:
            "カテゴリが見つかりません"
        }
    }
}

struct WidgetCategory: Identifiable, Hashable {
    let id: UUID
    let name: String
    let colorHex: String
    let icon: String?
}

private enum RecordingWidgetStore {
    static let appGroupID = "group.app.YasudaRyuga.Liminalog"

    static var cloudSchema: Schema {
        Schema([
            Category.self,
            CategorySet.self,
            Chapter.self,
            PlanBlock.self,
            VisibilityPreset.self,
            UserSettings.self
        ])
    }

    static var localCacheSchema: Schema {
        Schema([CalendarEventCache.self])
    }

    static var schema: Schema {
        Schema([
            Category.self,
            CategorySet.self,
            Chapter.self,
            PlanBlock.self,
            VisibilityPreset.self,
            UserSettings.self,
            CalendarEventCache.self
        ])
    }

    static func makeContainer() throws -> ModelContainer {
        let cloudConfiguration = ModelConfiguration(
            "Cloud",
            schema: cloudSchema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .none
        )

        let localCacheConfiguration = ModelConfiguration(
            "LocalCache",
            schema: localCacheSchema,
            groupContainer: .identifier(appGroupID),
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [cloudConfiguration, localCacheConfiguration]
        )
    }

    static func entry() -> RecordingGridEntry {
        do {
            let context = ModelContext(try makeContainer())
            let categories = try context.fetch(FetchDescriptor<Category>(
                sortBy: [
                    SortDescriptor(\.sortOrder),
                    SortDescriptor(\.createdAt)
                ]
            ))
            let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

            let sets = try context.fetch(FetchDescriptor<CategorySet>(
                sortBy: [
                    SortDescriptor(\.sortOrder),
                    SortDescriptor(\.createdAt)
                ]
            ))
            let settings = try context.fetch(FetchDescriptor<UserSettings>()).first
            let requestedID = settings?.enabledCategorySetID
            let selectedSet = requestedID.flatMap { id in sets.first { $0.id == id } }
                ?? sets.first { $0.isDefault }
                ?? sets.first

            let active = try context.fetch(FetchDescriptor<Chapter>())
                .filter { $0.endTime == nil }
                .sorted { $0.startTime > $1.startTime }
                .first

            guard let selectedSet else {
                return RecordingGridEntry(
                    date: Date(),
                    categorySetID: nil,
                    categorySetName: "カテゴリ",
                    cells: Array(repeating: nil, count: CategorySet.slotCount),
                    activeCategoryID: active?.category?.id,
                    message: "カテゴリセットがありません"
                )
            }

            let normalizedSlots = normalizeSlots(selectedSet.slots)
            let cells: [WidgetCategory?] = normalizedSlots.map { id in
                guard let id, let category = categoryByID[id] else { return nil }
                return WidgetCategory(
                    id: category.id,
                    name: category.name,
                    colorHex: category.colorHex,
                    icon: category.icon
                )
            }

            return RecordingGridEntry(
                date: Date(),
                categorySetID: selectedSet.id,
                categorySetName: selectedSet.name,
                cells: cells,
                activeCategoryID: active?.category?.id,
                message: nil
            )
        } catch {
            return RecordingGridEntry(
                date: Date(),
                categorySetID: nil,
                categorySetName: "カテゴリ",
                cells: Array(repeating: nil, count: CategorySet.slotCount),
                activeCategoryID: nil,
                message: "データを読み込めません"
            )
        }
    }

    @MainActor
    static func startChapter(categoryIDString: String) async throws {
        guard let categoryID = UUID(uuidString: categoryIDString) else {
            throw WidgetDataError.invalidCategoryID
        }

        let context = ModelContext(try makeContainer())
        let categories = try context.fetch(FetchDescriptor<Category>())
        guard let category = categories.first(where: { $0.id == categoryID }) else {
            throw WidgetDataError.categoryNotFound
        }

        let now = Date()
        let activeChapters = try context.fetch(FetchDescriptor<Chapter>())
            .filter { $0.endTime == nil }
            .sorted { $0.startTime < $1.startTime }
        let sameCategoryActive = activeChapters.first { $0.category?.id == categoryID }
        var activeAfterChange = sameCategoryActive

        for chapter in activeChapters where chapter.id != sameCategoryActive?.id {
            chapter.endTime = now
            chapter.updatedAt = now
        }

        if sameCategoryActive == nil {
            let chapter = Chapter(category: category, startTime: now)
            context.insert(chapter)
            activeAfterChange = chapter
        }

        try context.save()
        if #available(iOSApplicationExtension 16.2, *) {
            await updateLiveActivity(activeChapter: activeAfterChange, context: context)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func normalizeSlots(_ slots: [UUID?]) -> [UUID?] {
        var result = Array(slots.prefix(CategorySet.slotCount))
        while result.count < CategorySet.slotCount { result.append(nil) }
        return result
    }

    @available(iOSApplicationExtension 16.2, *)
    @MainActor
    private static func updateLiveActivity(activeChapter: Chapter?, context: ModelContext) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let categories = (try? context.fetch(FetchDescriptor<Category>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        ))) ?? []
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let sets = (try? context.fetch(FetchDescriptor<CategorySet>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        ))) ?? []
        let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first
        let selectedSet = settings?.enabledCategorySetID.flatMap { id in sets.first { $0.id == id } }
            ?? sets.first { $0.isDefault }
            ?? sets.first
        let islandCategories = normalizeSlots(selectedSet?.slots ?? [])
            .compactMap { id in id.flatMap { categoryByID[$0] } }
            .prefix(4)
            .map {
                LiminalogActivityAttributes.IslandCategory(
                    id: $0.id,
                    name: $0.name,
                    colorHex: $0.colorHex,
                    icon: $0.icon
                )
            }
        let state = makeActivityState(
            activeChapter: activeChapter,
            categorySetName: selectedSet?.name ?? "カテゴリ",
            categories: Array(islandCategories)
        )

        let activities = Activity<LiminalogActivityAttributes>.activities
        if !activities.isEmpty {
            for activity in activities {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            return
        }

        do {
            _ = try Activity<LiminalogActivityAttributes>.request(
                attributes: LiminalogActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            #if DEBUG
            print("Widget Live Activity request failed: \(error)")
            #endif
        }
    }

    @available(iOSApplicationExtension 16.2, *)
    private static func makeActivityState(
        activeChapter: Chapter?,
        categorySetName: String,
        categories: [LiminalogActivityAttributes.IslandCategory]
    ) -> LiminalogActivityAttributes.ContentState {
        guard let activeChapter, let category = activeChapter.category else {
            return LiminalogActivityAttributes.ContentState(
                activeCategoryID: nil,
                categoryName: nil,
                colorHex: "#8E8E93",
                icon: nil,
                startedAt: nil,
                isPublic: true,
                categorySetName: categorySetName,
                categories: categories
            )
        }

        return LiminalogActivityAttributes.ContentState(
            activeCategoryID: category.id,
            categoryName: category.name,
            colorHex: category.colorHex,
            icon: category.icon,
            startedAt: activeChapter.startTime,
            isPublic: activeChapter.isPublic,
            categorySetName: categorySetName,
            categories: categories
        )
    }
}

struct StartChapterIntent: AppIntent {
    static let title: LocalizedStringResource = "記録開始"
    static let description = IntentDescription("選んだカテゴリで記録を開始します。")
    static let openAppWhenRun = false

    @Parameter(title: "カテゴリID")
    var categoryID: String

    init() {
        self.categoryID = ""
    }

    init(categoryID: String) {
        self.categoryID = categoryID
    }

    func perform() async throws -> some IntentResult {
        try await RecordingWidgetStore.startChapter(categoryIDString: categoryID)
        return .result()
    }
}

struct RecordingGridEntry: TimelineEntry {
    let date: Date
    let categorySetID: UUID?
    let categorySetName: String
    let cells: [WidgetCategory?]
    let activeCategoryID: UUID?
    let message: String?
}

struct RecordingGridProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordingGridEntry {
        RecordingGridEntry(
            date: Date(),
            categorySetID: nil,
            categorySetName: "いつものセット",
            cells: [
                WidgetCategory(id: UUID(), name: "勉強", colorHex: "#3478F6", icon: "book.fill"),
                WidgetCategory(id: UUID(), name: "作業", colorHex: "#30B0C7", icon: "desktopcomputer"),
                WidgetCategory(id: UUID(), name: "休憩", colorHex: "#34C759", icon: "cup.and.saucer.fill"),
                WidgetCategory(id: UUID(), name: "移動", colorHex: "#FF9F0A", icon: "tram.fill"),
                WidgetCategory(id: UUID(), name: "運動", colorHex: "#FF375F", icon: "figure.run"),
                WidgetCategory(id: UUID(), name: "趣味", colorHex: "#BF5AF2", icon: "sparkles"),
                nil,
                nil
            ],
            activeCategoryID: nil,
            message: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordingGridEntry) -> Void) {
        completion(RecordingWidgetStore.entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordingGridEntry>) -> Void) {
        completion(Timeline(
            entries: [RecordingWidgetStore.entry()],
            policy: .after(Date().addingTimeInterval(60))
        ))
    }
}

struct RecordingGridWidget: Widget {
    let kind = "RecordingGridWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: RecordingGridProvider()
        ) { entry in
            RecordingGridView(entry: entry)
        }
        .configurationDisplayName("記録グリッド")
        .description("現在のテーブルからカテゴリをタップして記録を切り替えます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct RecordingGridView: View {
    let entry: RecordingGridEntry
    @Environment(\.widgetFamily) private var family

    private var visibleCells: [WidgetCategory?] {
        family == .systemSmall ? Array(entry.cells.prefix(4)) : entry.cells
    }

    private var metrics: RecordingGridMetrics {
        RecordingGridMetrics(family: family)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.contentSpacing) {
            header

            if let message = entry.message {
                emptyState(message)
            } else {
                LazyVGrid(columns: metrics.columns, spacing: metrics.gridSpacing) {
                    ForEach(Array(visibleCells.enumerated()), id: \.offset) { _, category in
                        if let category {
                            Button(intent: StartChapterIntent(categoryID: category.id.uuidString)) {
                                RecordingGridCell(
                                    category: category,
                                    isActive: category.id == entry.activeCategoryID,
                                    metrics: metrics
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            RecordingGridEmptyCell(metrics: metrics)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(metrics.headerFont.weight(.bold))
                .foregroundStyle(.secondary)

            Text(entry.categorySetName)
                .font(metrics.headerFont.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct RecordingGridCell: View {
    let category: WidgetCategory
    let isActive: Bool
    let metrics: RecordingGridMetrics

    var body: some View {
        VStack(spacing: metrics.cellSpacing) {
            ZStack {
                Circle()
                    .fill(Color(liminalogHex: category.colorHex).opacity(isActive ? 1 : 0.18))
                    .frame(width: metrics.iconSize, height: metrics.iconSize)

                if isActive {
                    Circle()
                        .stroke(Color(liminalogHex: category.colorHex), lineWidth: 2.2)
                        .frame(width: metrics.activeRingSize, height: metrics.activeRingSize)
                }

                Image(systemName: category.icon ?? "circle.fill")
                    .font(.system(size: metrics.iconFontSize, weight: .semibold))
                    .foregroundStyle(isActive ? .white : Color(liminalogHex: category.colorHex))
            }

            Text(category.name)
                .font(.system(size: metrics.labelFontSize, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color(liminalogHex: category.colorHex) : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color(liminalogHex: category.colorHex).opacity(0.12) : Color.secondary.opacity(0.08))
        )
    }
}

private struct RecordingGridEmptyCell: View {
    let metrics: RecordingGridMetrics

    var body: some View {
        VStack(spacing: metrics.cellSpacing) {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                .frame(width: metrics.iconSize, height: metrics.iconSize)

            Text(" ")
                .font(.system(size: metrics.labelFontSize))
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
        .accessibilityHidden(true)
    }
}

private struct RecordingGridMetrics {
    let family: WidgetFamily

    var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: family == .systemSmall ? 2 : 4)
    }

    var gridSpacing: CGFloat {
        switch family {
        case .systemSmall:
            6
        case .systemMedium:
            6
        default:
            10
        }
    }

    var horizontalPadding: CGFloat {
        switch family {
        case .systemSmall:
            12
        case .systemMedium:
            16
        default:
            18
        }
    }

    var verticalPadding: CGFloat {
        switch family {
        case .systemSmall:
            10
        case .systemMedium:
            10
        default:
            16
        }
    }

    var contentSpacing: CGFloat {
        switch family {
        case .systemSmall:
            7
        case .systemMedium:
            7
        default:
            12
        }
    }

    var headerFont: Font {
        family == .systemLarge ? .caption : .caption2
    }

    var iconSize: CGFloat {
        switch family {
        case .systemLarge:
            38
        default:
            26
        }
    }

    var activeRingSize: CGFloat {
        switch family {
        case .systemLarge:
            44
        default:
            31
        }
    }

    var iconFontSize: CGFloat {
        switch family {
        case .systemLarge:
            16
        default:
            12
        }
    }

    var labelFontSize: CGFloat {
        switch family {
        case .systemLarge:
            12
        default:
            9
        }
    }

    var cellSpacing: CGFloat {
        family == .systemLarge ? 6 : 3
    }

    var cellHeight: CGFloat {
        family == .systemLarge ? 68 : 48
    }
}

private extension Color {
    init(liminalogHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch cleaned.count {
        case 6:
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        default:
            red = 0x8E
            green = 0x8E
            blue = 0x93
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }
}
