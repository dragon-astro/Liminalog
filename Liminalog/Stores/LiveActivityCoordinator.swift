import Foundation

@MainActor
final class LiveActivityCoordinator {
    private let categorySetStore: CategorySetStore

    init(categorySetStore: CategorySetStore) {
        self.categorySetStore = categorySetStore
    }

    func update(activeChapter: Chapter?, categorySet: CategorySet?) {
        guard #available(iOS 16.2, *) else { return }

        let gridCategories = categorySet.map { categorySetStore.assignedCategories(for: $0) } ?? []
        Task {
            await LiveActivityManager.shared.update(
                activeChapter: activeChapter,
                categorySetName: categorySet?.name ?? "カテゴリ",
                categories: gridCategories
            )
        }
    }
}
