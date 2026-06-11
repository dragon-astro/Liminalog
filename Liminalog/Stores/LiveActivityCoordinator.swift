import Foundation

@MainActor
final class LiveActivityCoordinator {
    private let categorySetStore: CategorySetStore

    init(categorySetStore: CategorySetStore) {
        self.categorySetStore = categorySetStore
    }

    func update(activeChapter: Chapter?, categorySet: CategorySet?) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard #available(iOS 16.2, *) else { return }

        // SwiftDataモデルは Task に持ち込まず、ここ（MainActor・同期）でプレーン値へ変換する。
        let chapterSnapshot = LiveActivityChapterSnapshot(activeChapter: activeChapter)
        let categorySetName = categorySet?.name ?? "カテゴリ"
        let islandCategories: [LiminalogActivityAttributes.IslandCategory]
        if let categorySet {
            guard let assignedCategories = categorySetStore.assignedCategoriesIfAvailable(for: categorySet) else {
                NSLog("Liminalog: skipped Live Activity update because category set categories could not be fetched")
                return
            }
            islandCategories = assignedCategories.prefix(CategorySet.slotCount).map {
                LiminalogActivityAttributes.IslandCategory(
                    id: $0.id,
                    name: $0.name,
                    colorHex: $0.colorHex,
                    icon: $0.icon
                )
            }
        } else {
            islandCategories = []
        }

        Task {
            await LiveActivityManager.shared.update(
                chapterSnapshot: chapterSnapshot,
                categorySetName: categorySetName,
                islandCategories: islandCategories
            )
        }
    }

    func update(activeChapter: Chapter?, snapshot: RecordingSurfaceSnapshot) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard #available(iOS 16.2, *) else { return }

        let chapterSnapshot = LiveActivityChapterSnapshot(activeChapter: activeChapter)
        let categorySetName = snapshot.categorySetName
        let islandCategories = Array(snapshot.categories.prefix(CategorySet.slotCount).map {
            LiminalogActivityAttributes.IslandCategory(
                id: $0.id,
                name: $0.name,
                colorHex: $0.colorHex,
                icon: $0.icon
            )
        })

        Task {
            await LiveActivityManager.shared.update(
                chapterSnapshot: chapterSnapshot,
                categorySetName: categorySetName,
                islandCategories: islandCategories
            )
        }
    }
}
