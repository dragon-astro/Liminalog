import Foundation
import SwiftData
import Testing
@testable import Liminalog

@Suite("SortOrderNormalizer")
struct SortOrderNormalizerTests {
    @Test("上方向と下方向の移動を0始まりの連番へ正規化する")
    func movesUpAndDown() {
        let movingUp = makeItems()

        #expect(SortOrderNormalizer.reorder(
            movingUp,
            from: IndexSet(integer: 2),
            to: 0,
            sortOrder: \.sortOrder
        ))
        #expect(orderedIDs(movingUp) == ["C", "A", "B", "D"])
        #expect(orderedSortOrders(movingUp) == [0, 1, 2, 3])

        let movingDown = makeItems()

        #expect(SortOrderNormalizer.reorder(
            movingDown,
            from: IndexSet(integer: 1),
            to: 3,
            sortOrder: \.sortOrder
        ))
        #expect(orderedIDs(movingDown) == ["A", "C", "B", "D"])
        #expect(orderedSortOrders(movingDown) == [0, 1, 2, 3])
    }

    @Test("末尾移動と複数行移動で相対順序を保つ")
    func movesToEndAndMovesMultipleItems() {
        let movingToEnd = makeItems()

        #expect(SortOrderNormalizer.reorder(
            movingToEnd,
            from: IndexSet(integer: 0),
            to: movingToEnd.count,
            sortOrder: \.sortOrder
        ))
        #expect(orderedIDs(movingToEnd) == ["B", "C", "D", "A"])

        let movingMultiple = makeItems()

        #expect(SortOrderNormalizer.reorder(
            movingMultiple,
            from: IndexSet([0, 2]),
            to: movingMultiple.count,
            sortOrder: \.sortOrder
        ))
        #expect(orderedIDs(movingMultiple) == ["B", "D", "A", "C"])
        #expect(orderedSortOrders(movingMultiple) == [0, 1, 2, 3])
    }

    @Test("欠番・重複したsortOrderも表示順のまま0始まりへ詰め直す")
    func normalizesGapsAndDuplicates() {
        let items = [
            SortableTestItem(id: "A", sortOrder: -4),
            SortableTestItem(id: "B", sortOrder: 9),
            SortableTestItem(id: "C", sortOrder: 9),
            SortableTestItem(id: "D", sortOrder: 40)
        ]

        #expect(SortOrderNormalizer.reorder(
            items,
            from: IndexSet(integer: 1),
            to: 1,
            sortOrder: \.sortOrder
        ))
        #expect(orderedIDs(items) == ["A", "B", "C", "D"])
        #expect(orderedSortOrders(items) == [0, 1, 2, 3])
    }

    @Test("移動を伴わないseed再作成でも表示順を保って連番化する")
    func normalizesWithoutMoving() {
        let items = [
            SortableTestItem(id: "A", sortOrder: 4),
            SortableTestItem(id: "B", sortOrder: 12),
            SortableTestItem(id: "C", sortOrder: 12)
        ]

        #expect(SortOrderNormalizer.normalize(items, sortOrder: \.sortOrder))
        #expect(orderedIDs(items) == ["A", "B", "C"])
        #expect(orderedSortOrders(items) == [0, 1, 2])
        #expect(!SortOrderNormalizer.normalize(items, sortOrder: \.sortOrder))
    }

    @Test("空・範囲外sourceと範囲外destinationは全要素を変更しない")
    func rejectsInvalidMovesWithoutMutation() {
        let items = makeItems()
        let originalOrders = items.map(\.sortOrder)

        #expect(!SortOrderNormalizer.reorder(
            items,
            from: IndexSet(),
            to: 1,
            sortOrder: \.sortOrder
        ))
        #expect(items.map(\.sortOrder) == originalOrders)

        #expect(!SortOrderNormalizer.reorder(
            items,
            from: IndexSet(integer: items.count),
            to: 0,
            sortOrder: \.sortOrder
        ))
        #expect(items.map(\.sortOrder) == originalOrders)

        #expect(!SortOrderNormalizer.reorder(
            items,
            from: IndexSet(integer: 0),
            to: -1,
            sortOrder: \.sortOrder
        ))
        #expect(items.map(\.sortOrder) == originalOrders)

        #expect(!SortOrderNormalizer.reorder(
            items,
            from: IndexSet(integer: 0),
            to: items.count + 1,
            sortOrder: \.sortOrder
        ))
        #expect(items.map(\.sortOrder) == originalOrders)
    }

    private func makeItems() -> [SortableTestItem] {
        [
            SortableTestItem(id: "A", sortOrder: 10),
            SortableTestItem(id: "B", sortOrder: 20),
            SortableTestItem(id: "C", sortOrder: 30),
            SortableTestItem(id: "D", sortOrder: 40)
        ]
    }

    private func orderedIDs(_ items: [SortableTestItem]) -> [String] {
        items.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
    }

    private func orderedSortOrders(_ items: [SortableTestItem]) -> [Int] {
        items.sorted { $0.sortOrder < $1.sortOrder }.map(\.sortOrder)
    }
}

@MainActor
@Suite("Sort order persistence")
struct SortOrderPersistenceTests {
    @Test("Categoryの正常moveは連番で保存しメタ情報を変更しない")
    func categoryMovePersistsOrderAndPreservesContent() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let friendSetID = UUID()
        let includedFriendID = UUID()
        let excludedFriendID = UUID()
        let study = Category(
            name: "勉強",
            colorHex: "#112233",
            icon: "book.fill",
            sortOrder: 10,
            isDefault: true,
            dailyCardIntent: .increase,
            analysisKind: .study
        )
        study.defaultAudienceFriendSetIDs = [friendSetID]
        study.defaultAudienceIncludedFriendIDs = [includedFriendID]
        study.defaultAudienceExcludedFriendIDs = [excludedFriendID]
        let work = Category(
            name: "仕事",
            colorHex: "#445566",
            icon: "briefcase.fill",
            sortOrder: 30,
            dailyCardIntent: .decrease,
            analysisKind: .work
        )
        let rest = Category(
            name: "休憩",
            colorHex: "#778899",
            icon: "cup.and.saucer.fill",
            sortOrder: 80
        )
        [study, work, rest].forEach(context.insert)
        try context.save()
        let contentBefore = Dictionary(uniqueKeysWithValues: [study, work, rest].map {
            ($0.id, CategoryContentSnapshot($0))
        })

        let store = CategoryStore(modelContext: context)
        #expect(store.moveCategories(from: IndexSet(integer: 0), to: 3))

        let verificationContext = ModelContext(container)
        let fetched = try verificationContext.fetch(FetchDescriptor<Liminalog.Category>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        #expect(fetched.map(\.id) == [work.id, rest.id, study.id])
        #expect(fetched.map(\.sortOrder) == [0, 1, 2])
        #expect(Dictionary(uniqueKeysWithValues: fetched.map {
            ($0.id, CategoryContentSnapshot($0))
        }) == contentBefore)
    }

    @Test("CategorySetの正常moveは連番で保存しスロットを変更しない")
    func categorySetMovePersistsOrderAndPreservesSlots() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let categoryIDs = (0..<6).map { _ in UUID() }
        let weekday = CategorySet(
            name: "平日",
            sortOrder: 10,
            slots: [categoryIDs[0], nil, categoryIDs[1]],
            isDefault: true
        )
        let holiday = CategorySet(
            name: "休日",
            sortOrder: 30,
            slots: [categoryIDs[2], categoryIDs[3]],
            isDefault: true
        )
        let custom = CategorySet(
            name: "集中日",
            sortOrder: 90,
            slots: [categoryIDs[4], nil, categoryIDs[5]]
        )
        [weekday, holiday, custom].forEach(context.insert)
        try context.save()
        let contentBefore = Dictionary(uniqueKeysWithValues: [weekday, holiday, custom].map {
            ($0.id, CategorySetContentSnapshot($0))
        })

        let store = CategorySetStore(
            modelContext: context,
            categoryStore: CategoryStore(modelContext: context)
        )
        #expect(store.moveCategorySets(from: IndexSet(integer: 0), to: 3))

        let verificationContext = ModelContext(container)
        let fetched = try verificationContext.fetch(FetchDescriptor<CategorySet>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        #expect(fetched.map(\.id) == [holiday.id, custom.id, weekday.id])
        #expect(fetched.map(\.sortOrder) == [0, 1, 2])
        #expect(Dictionary(uniqueKeysWithValues: fetched.map {
            ($0.id, CategorySetContentSnapshot($0))
        }) == contentBefore)
    }

    @Test("default CategorySetのユーザー順はbootstrap再実行後も保持する")
    func bootstrapPreservesReorderedDefaultCategorySets() throws {
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9)))
        let container = try TestModelContainer.make()
        let stores = AppStores(modelContext: container.mainContext, clock: MutableTestClock(now: now))

        stores.bootstrapStore.bootstrap(now: now)
        let original = stores.categorySetStore.categorySets()
        #expect(original.map(\.name) == ["平日", "休日"])
        let contentBefore = Dictionary(uniqueKeysWithValues: original.map {
            ($0.id, CategorySetContentSnapshot($0))
        })
        #expect(stores.categorySetStore.moveCategorySets(
            from: IndexSet(integer: 0),
            to: original.count
        ))

        stores.bootstrapStore.bootstrap(now: now.addingTimeInterval(60))

        let verificationContext = ModelContext(container)
        let fetched = try verificationContext.fetch(FetchDescriptor<CategorySet>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        #expect(fetched.map(\.name) == ["休日", "平日"])
        #expect(fetched.map(\.sortOrder) == [0, 1])
        #expect(fetched.allSatisfy { $0.isDefault })
        #expect(Dictionary(uniqueKeysWithValues: fetched.map {
            ($0.id, CategorySetContentSnapshot($0))
        }) == contentBefore)
    }

    @Test("並び替え後に削除したdefault Categoryは末尾へ再seedされ連番を保つ")
    func categoryReseedAfterDeletePreservesSurvivorOrder() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let store = CategoryStore(modelContext: context)

        #expect(store.seedDefaultCategoriesIfNeeded())
        let custom = Category(name: "カスタム", colorHex: "#123456", sortOrder: 99)
        context.insert(custom)
        try context.save()

        let beforeMove = store.allCategories()
        let studyIndex = try #require(beforeMove.firstIndex { $0.name == "勉強" })
        #expect(store.moveCategories(
            from: IndexSet(integer: studyIndex),
            to: 4
        ))

        let study = try #require(store.allCategories().first { $0.name == "勉強" })
        #expect(store.deleteCategory(study))
        let survivorNames = store.allCategories().map(\.name)
        #expect(store.seedDefaultCategoriesIfNeeded())

        let verificationContext = ModelContext(container)
        let fetched = try verificationContext.fetch(FetchDescriptor<Liminalog.Category>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        #expect(fetched.dropLast().map(\.name) == survivorNames)
        #expect(fetched.last?.name == "勉強")
        #expect(fetched.map(\.sortOrder) == Array(fetched.indices))
        #expect(fetched.filter { $0.name == "勉強" }.count == 1)
        #expect(fetched.contains { $0.id == custom.id })
    }

    @Test("並び替え後に削除したdefault CategorySetは末尾へ再seedされ連番を保つ")
    func categorySetReseedAfterDeletePreservesSurvivorOrder() throws {
        let calendar = Calendar.liminalogTest
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 10)))
        let container = try TestModelContainer.make()
        let stores = AppStores(modelContext: container.mainContext, clock: MutableTestClock(now: now))

        stores.bootstrapStore.bootstrap(now: now)
        #expect(stores.categorySetStore.addCategorySet(name: "集中日", slots: []))
        let beforeMove = stores.categorySetStore.categorySets()
        let weekdayIndex = try #require(beforeMove.firstIndex { $0.name == "平日" })
        #expect(stores.categorySetStore.moveCategorySets(
            from: IndexSet(integer: weekdayIndex),
            to: 2
        ))

        let weekday = try #require(stores.categorySetStore.categorySets().first { $0.name == "平日" })
        #expect(stores.categorySetStore.deleteCategorySet(weekday))
        let survivorNames = stores.categorySetStore.categorySets().map(\.name)
        stores.bootstrapStore.bootstrap(now: now.addingTimeInterval(60))

        let verificationContext = ModelContext(container)
        let fetched = try verificationContext.fetch(FetchDescriptor<CategorySet>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        #expect(fetched.dropLast().map(\.name) == survivorNames)
        #expect(fetched.last?.name == "平日")
        #expect(fetched.last?.filledCount == CategorySet.slotCount)
        #expect(fetched.map(\.sortOrder) == Array(fetched.indices))
        #expect(fetched.filter { $0.name == "平日" }.count == 1)
    }

    @Test("built-in VisibilityPresetのユーザー順と内容はseed再実行後も保持する")
    func visibilitySeedPreservesReorderedBuiltIns() throws {
        let calendar = Calendar.liminalogTest
        let firstSeedDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9)))
        let reorderedAt = firstSeedDate.addingTimeInterval(30)
        let container = try TestModelContainer.make()
        let context = container.mainContext

        SeedCoordinator.consolidateBuiltInVisibilityPresets(in: context, now: firstSeedDate)
        let presets = try context.fetch(FetchDescriptor<VisibilityPreset>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        #expect(presets.compactMap(\.builtInKey) == ["close_friends", "acquaintances", "off"])
        let contentBefore = Dictionary(uniqueKeysWithValues: presets.map {
            ($0.id, VisibilityPresetContentSnapshot($0))
        })
        #expect(SortOrderNormalizer.reorder(
            presets,
            from: IndexSet(integer: 0),
            to: presets.count,
            sortOrder: \.sortOrder
        ))
        presets.forEach { $0.updatedAt = reorderedAt }
        try context.save()

        SeedCoordinator.consolidateBuiltInVisibilityPresets(
            in: context,
            now: firstSeedDate.addingTimeInterval(60)
        )

        let verificationContext = ModelContext(container)
        let fetched = try verificationContext.fetch(FetchDescriptor<VisibilityPreset>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        #expect(fetched.compactMap(\.builtInKey) == ["acquaintances", "off", "close_friends"])
        #expect(fetched.map(\.sortOrder) == [0, 1, 2])
        #expect(fetched.allSatisfy { $0.isBuiltIn })
        #expect(Dictionary(uniqueKeysWithValues: fetched.map {
            ($0.id, VisibilityPresetContentSnapshot($0))
        }) == contentBefore)
    }

    @Test("FriendSetの共通並び替えは別ModelContextでも順序と更新日時を保持する")
    func friendSetReorderPersistsAcrossModelContexts() throws {
        let calendar = Calendar.liminalogTest
        let createdAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 9)))
        let reorderedAt = createdAt.addingTimeInterval(3_600)
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let friendIDs = (0..<4).map { _ in UUID() }
        let family = FriendSet(name: "家族", memberFriendIDs: [friendIDs[0]], sortOrder: 4, now: createdAt)
        let school = FriendSet(name: "学校", memberFriendIDs: [friendIDs[1], friendIDs[2]], sortOrder: 18, now: createdAt)
        let team = FriendSet(name: "チーム", memberFriendIDs: [friendIDs[3]], sortOrder: 18, now: createdAt)
        let sets = [family, school, team]
        sets.forEach(context.insert)
        try context.save()
        let contentBefore = Dictionary(uniqueKeysWithValues: sets.map {
            ($0.id, FriendSetContentSnapshot($0))
        })

        #expect(SortOrderNormalizer.reorder(
            sets,
            from: IndexSet(integer: 0),
            to: sets.count,
            sortOrder: \.sortOrder
        ))
        sets.forEach { $0.updatedAt = reorderedAt }
        try context.save()

        let verificationContext = ModelContext(container)
        let fetched = try verificationContext.fetch(FetchDescriptor<FriendSet>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        #expect(fetched.map(\.name) == ["学校", "チーム", "家族"])
        #expect(fetched.map(\.sortOrder) == [0, 1, 2])
        #expect(fetched.allSatisfy { $0.updatedAt == reorderedAt })
        #expect(Dictionary(uniqueKeysWithValues: fetched.map {
            ($0.id, FriendSetContentSnapshot($0))
        }) == contentBefore)
    }

    @Test("VisibilityPresetの共通並び替えは別ModelContextでも順序と更新日時を保持する")
    func visibilityPresetReorderPersistsAcrossModelContexts() throws {
        let calendar = Calendar.liminalogTest
        let createdAt = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 10)))
        let reorderedAt = createdAt.addingTimeInterval(7_200)
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let detailed = VisibilityPreset(
            name: "家族向け",
            level: .all,
            sortOrder: 8,
            publishMode: .realtime,
            hideMoodAndNote: false,
            hidePhoto: false,
            hideLocation: false,
            excludedCategoryIDs: [UUID()],
            freeTimeOnly: false,
            now: createdAt
        )
        let limited = VisibilityPreset(
            name: "学校向け",
            level: .partial,
            sortOrder: 20,
            publishMode: .nextDay,
            hideMoodAndNote: true,
            hidePhoto: true,
            hideLocation: true,
            excludedCategoryIDs: [UUID(), UUID()],
            freeTimeOnly: true,
            now: createdAt
        )
        let off = VisibilityPreset(
            name: "共有しない",
            level: .none,
            sortOrder: 70,
            publishMode: .none,
            hideMoodAndNote: true,
            hidePhoto: true,
            hideLocation: true,
            freeTimeOnly: true,
            now: createdAt
        )
        let presets = [detailed, limited, off]
        presets.forEach(context.insert)
        try context.save()
        let contentBefore = Dictionary(uniqueKeysWithValues: presets.map {
            ($0.id, VisibilityPresetContentSnapshot($0))
        })

        #expect(SortOrderNormalizer.reorder(
            presets,
            from: IndexSet(integer: 0),
            to: presets.count,
            sortOrder: \.sortOrder
        ))
        presets.forEach { $0.updatedAt = reorderedAt }
        try context.save()

        let verificationContext = ModelContext(container)
        let fetched = try verificationContext.fetch(FetchDescriptor<VisibilityPreset>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        #expect(fetched.map(\.name) == ["学校向け", "共有しない", "家族向け"])
        #expect(fetched.map(\.sortOrder) == [0, 1, 2])
        #expect(fetched.allSatisfy { $0.updatedAt == reorderedAt })
        #expect(Dictionary(uniqueKeysWithValues: fetched.map {
            ($0.id, VisibilityPresetContentSnapshot($0))
        }) == contentBefore)
    }
}

private final class SortableTestItem {
    let id: String
    var sortOrder: Int

    init(id: String, sortOrder: Int) {
        self.id = id
        self.sortOrder = sortOrder
    }
}

private struct CategoryContentSnapshot: Equatable {
    let name: String
    let colorHex: String
    let icon: String?
    let isDefault: Bool
    let dailyCardIntentRawValue: String
    let analysisKindRawValue: String
    let isDailyCardSleepCategory: Bool
    let defaultAudienceFriendSetIDs: [UUID]
    let defaultAudienceIncludedFriendIDs: [UUID]
    let defaultAudienceExcludedFriendIDs: [UUID]
    let createdAt: Date

    init(_ category: Liminalog.Category) {
        name = category.name
        colorHex = category.colorHex
        icon = category.icon
        isDefault = category.isDefault
        dailyCardIntentRawValue = category.dailyCardIntentRawValue
        analysisKindRawValue = category.analysisKindRawValue
        isDailyCardSleepCategory = category.isDailyCardSleepCategory
        defaultAudienceFriendSetIDs = category.defaultAudienceFriendSetIDs
        defaultAudienceIncludedFriendIDs = category.defaultAudienceIncludedFriendIDs
        defaultAudienceExcludedFriendIDs = category.defaultAudienceExcludedFriendIDs
        createdAt = category.createdAt
    }
}

private struct CategorySetContentSnapshot: Equatable {
    let name: String
    let slots: [UUID?]
    let isDefault: Bool
    let createdAt: Date

    init(_ set: CategorySet) {
        name = set.name
        slots = set.slots
        isDefault = set.isDefault
        createdAt = set.createdAt
    }
}

private struct FriendSetContentSnapshot: Equatable {
    let name: String
    let memberFriendIDs: [UUID]
    let createdAt: Date

    init(_ set: FriendSet) {
        name = set.name
        memberFriendIDs = set.memberFriendIDs
        createdAt = set.createdAt
    }
}

private struct VisibilityPresetContentSnapshot: Equatable {
    let name: String
    let level: VisibilityLevel
    let builtInKey: String?
    let isBuiltIn: Bool
    let publishModeRawValue: String
    let hideMoodAndNote: Bool
    let hidePhoto: Bool
    let hideLocation: Bool
    let excludedCategoryIDs: [UUID]
    let freeTimeOnly: Bool
    let createdAt: Date

    init(_ preset: VisibilityPreset) {
        name = preset.name
        level = preset.level
        builtInKey = preset.builtInKey
        isBuiltIn = preset.isBuiltIn
        publishModeRawValue = preset.publishModeRawValue
        hideMoodAndNote = preset.hideMoodAndNote
        hidePhoto = preset.hidePhoto
        hideLocation = preset.hideLocation
        excludedCategoryIDs = preset.excludedCategoryIDs
        freeTimeOnly = preset.freeTimeOnly
        createdAt = preset.createdAt
    }
}
