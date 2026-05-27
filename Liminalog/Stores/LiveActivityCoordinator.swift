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

        Task {
            let categories = categorySet.map { categorySetStore.assignedCategories(for: $0) } ?? []
            await LiveActivityManager.shared.update(
                activeChapter: activeChapter,
                categorySetName: categorySet?.name ?? "カテゴリ",
                categories: categories
            )
        }
    }
}
