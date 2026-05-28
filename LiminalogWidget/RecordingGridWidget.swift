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
    static let widgetKind = "RecordingGridWidget"

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

    static let sharedContainer: Result<ModelContainer, Error> = Result {
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

    static func makeContainer() throws -> ModelContainer {
        try sharedContainer.get()
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

            let active = try fetchActiveChapter(context: context)

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
        var categoryDescriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.id == categoryID }
        )
        categoryDescriptor.fetchLimit = 1
        guard let category = try context.fetch(categoryDescriptor).first else {
            throw WidgetDataError.categoryNotFound
        }

        let now = Date()
        let activeChapters = try fetchActiveChapters(context: context, order: .forward)
        let sameCategoryActive = activeChapters.first { $0.category?.id == categoryID }

        for chapter in activeChapters where chapter.id != sameCategoryActive?.id {
            chapter.endTime = now
            chapter.updatedAt = now
        }

        if sameCategoryActive == nil {
            let chapter = Chapter(category: category, startTime: now)
            context.insert(chapter)
        }

        try context.save()
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)

        if #available(iOSApplicationExtension 16.2, *) {
            Task { @MainActor in
                await refreshLiveActivityFromStore()
            }
        }
    }

    private static func fetchActiveChapters(
        context: ModelContext,
        order: SortOrder = .reverse
    ) throws -> [Chapter] {
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: order)]
        )
        return try context.fetch(descriptor)
    }

    private static func fetchActiveChapter(context: ModelContext) throws -> Chapter? {
        var descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func normalizeSlots(_ slots: [UUID?]) -> [UUID?] {
        var result = Array(slots.prefix(CategorySet.slotCount))
        while result.count < CategorySet.slotCount { result.append(nil) }
        return result
    }

    @available(iOSApplicationExtension 16.2, *)
    @MainActor
    private static func refreshLiveActivityFromStore() async {
        do {
            let context = ModelContext(try makeContainer())
            let state = makeLiveActivityState(
                activeChapter: try fetchActiveChapter(context: context),
                context: context
            )
            await publishLiveActivity(state: state)
        } catch {
            #if DEBUG
            print("Widget Live Activity refresh failed: \(error)")
            #endif
        }
    }

    @available(iOSApplicationExtension 16.2, *)
    @MainActor
    private static func makeLiveActivityState(
        activeChapter: Chapter?,
        context: ModelContext
    ) -> LiminalogActivityAttributes.ContentState {
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
            .prefix(CategorySet.slotCount)
            .map {
                LiminalogActivityAttributes.IslandCategory(
                    id: $0.id,
                    name: $0.name,
                    colorHex: $0.colorHex,
                    icon: $0.icon
                )
            }
        return makeActivityState(
            activeChapter: activeChapter,
            categorySetName: selectedSet?.name ?? "カテゴリ",
            categories: Array(islandCategories)
        )
    }

    @available(iOSApplicationExtension 16.2, *)
    @MainActor
    private static func publishLiveActivity(state: LiminalogActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let activities = Activity<LiminalogActivityAttributes>.activities
        if !activities.isEmpty {
            for activity in activities {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            #if DEBUG
            print("Widget Live Activity updated: active=\(state.activeCategoryID?.uuidString ?? "nil"), activities=\(activities.count), categories=\(state.categories.count)")
            #endif
            return
        }

        do {
            _ = try Activity<LiminalogActivityAttributes>.request(
                attributes: LiminalogActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            #if DEBUG
            print("Widget Live Activity requested: active=\(state.activeCategoryID?.uuidString ?? "nil"), categories=\(state.categories.count)")
            #endif
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
                categories: categories,
                updatedAt: Date()
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
            categories: categories,
            updatedAt: Date()
        )
    }
}

struct StartChapterIntent: AppIntent, LiveActivityIntent {
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
    let kind = RecordingWidgetStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: RecordingGridProvider()
        ) { entry in
            RecordingGridView(entry: entry)
        }
        .configurationDisplayName("記録グリッド")
        .description("現在のテーブルからカテゴリをタップして記録を切り替えます。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RecordingGridView: View {
    let entry: RecordingGridEntry
    @Environment(\.widgetFamily) private var family

    private var visibleCells: [WidgetCategory?] {
        family == .systemSmall ? Array(entry.cells.prefix(4)) : entry.cells
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: family == .systemSmall ? 2 : 4)
    }

    private var gridSpacing: CGFloat {
        family == .systemSmall ? 6 : 8
    }

    private var contentPadding: CGFloat {
        family == .systemSmall ? 10 : 14
    }

    private var contentSpacing: CGFloat {
        family == .systemSmall ? 7 : 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            header

            if let message = entry.message {
                emptyState(message)
            } else {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(Array(visibleCells.enumerated()), id: \.offset) { _, category in
                        if let category {
                            Button(intent: StartChapterIntent(categoryID: category.id.uuidString)) {
                                RecordingGridCell(
                                    category: category,
                                    isActive: category.id == entry.activeCategoryID,
                                    isCompact: family == .systemSmall
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            RecordingGridEmptyCell(isCompact: family == .systemSmall)
                        }
                    }
                }
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font((family == .systemSmall ? Font.caption2 : Font.caption).weight(.bold))
                .foregroundStyle(.secondary)

            Text(entry.categorySetName)
                .font((family == .systemSmall ? Font.caption2 : Font.caption).weight(.semibold))
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
    let isCompact: Bool

    private var iconSize: CGFloat {
        isCompact ? 26 : 34
    }

    private var activeRingSize: CGFloat {
        isCompact ? 31 : 40
    }

    var body: some View {
        VStack(spacing: isCompact ? 3 : 6) {
            ZStack {
                Circle()
                    .fill(Color(liminalogHex: category.colorHex).opacity(isActive ? 1 : 0.18))
                    .frame(width: iconSize, height: iconSize)

                if isActive {
                    Circle()
                        .stroke(Color(liminalogHex: category.colorHex), lineWidth: 2.2)
                        .frame(width: activeRingSize, height: activeRingSize)
                }

                Image(systemName: category.icon ?? "circle.fill")
                    .font(.system(size: isCompact ? 12 : 15, weight: .semibold))
                    .foregroundStyle(isActive ? .white : Color(liminalogHex: category.colorHex))
            }

            Text(category.name)
                .font(.system(size: isCompact ? 9 : 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color(liminalogHex: category.colorHex) : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 48 : 62)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color(liminalogHex: category.colorHex).opacity(0.12) : Color.secondary.opacity(0.08))
        )
    }
}

private struct RecordingGridEmptyCell: View {
    let isCompact: Bool

    var body: some View {
        VStack(spacing: isCompact ? 3 : 6) {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                .frame(width: isCompact ? 26 : 34, height: isCompact ? 26 : 34)

            Text(" ")
                .font(.system(size: isCompact ? 9 : 11))
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 48 : 62)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
        .accessibilityHidden(true)
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
