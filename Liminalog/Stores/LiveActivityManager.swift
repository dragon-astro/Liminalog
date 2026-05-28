import Foundation
import ActivityKit

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private init() {}

    @available(iOS 16.2, *)
    func update(activeChapter: Chapter?, categorySetName: String, categories: [Category]) async {
        let state = makeState(
            activeChapter: activeChapter,
            categorySetName: categorySetName,
            categories: categories
        )

        let activities = Activity<LiminalogActivityAttributes>.activities
        if !activities.isEmpty {
            if state.isRecording {
                for activity in activities {
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                }
            } else {
                for activity in activities {
                    await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
                }
            }
            return
        }

        guard state.isRecording else { return }

        do {
            _ = try Activity<LiminalogActivityAttributes>.request(
                attributes: LiminalogActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            #if DEBUG
            print("Live Activity request failed: \(error)")
            #endif
        }
    }

    @available(iOS 16.2, *)
    private func makeState(activeChapter: Chapter?, categorySetName: String, categories: [Category]) -> LiminalogActivityAttributes.ContentState {
        let islandCategories = categories.prefix(CategorySet.slotCount).map {
            LiminalogActivityAttributes.IslandCategory(
                id: $0.id,
                name: $0.name,
                colorHex: $0.colorHex,
                icon: $0.icon
            )
        }

        guard let activeChapter, let category = activeChapter.category else {
            return LiminalogActivityAttributes.ContentState(
                activeCategoryID: nil,
                categoryName: nil,
                colorHex: "#8E8E93",
                icon: nil,
                startedAt: nil,
                isPublic: true,
                categorySetName: categorySetName,
                categories: islandCategories,
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
            categories: islandCategories,
            updatedAt: Date()
        )
    }
}
