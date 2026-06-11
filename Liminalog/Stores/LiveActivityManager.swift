import ActivityKit
import Foundation
import SwiftData

/// Live Activity へ渡すアクティブチャプターのプレーン値。
/// SwiftData モデルを async 境界へ持ち込むと、削除/統合後に backing data 喪失でクラッシュするため、
/// MainActor 上で同期的にスナップショット化してから渡す（実機クラッシュで観測済み）。
struct LiveActivityChapterSnapshot: Sendable {
    let categoryID: UUID
    let categoryName: String
    let categoryColorHex: String
    let categoryIcon: String?
    let startTime: Date
    let isPublic: Bool

    /// モデルが既に削除/無効化されている場合は nil（Live Activity 上は「記録なし」扱い）。
    init?(activeChapter: Chapter?) {
        guard let activeChapter,
              activeChapter.modelContext != nil,
              !activeChapter.isDeleted,
              let category = activeChapter.category,
              category.modelContext != nil,
              !category.isDeleted
        else { return nil }
        self.categoryID = category.id
        self.categoryName = category.name
        self.categoryColorHex = category.colorHex
        self.categoryIcon = category.icon
        self.startTime = activeChapter.startTime
        self.isPublic = activeChapter.isPublic
    }
}

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private init() {}

    @available(iOS 16.2, *)
    func update(
        chapterSnapshot: LiveActivityChapterSnapshot?,
        categorySetName: String,
        islandCategories: [LiminalogActivityAttributes.IslandCategory]
    ) async {
        let state = makeState(
            chapterSnapshot: chapterSnapshot,
            categorySetName: categorySetName,
            islandCategories: islandCategories
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
            NSLog("Liminalog: Live Activity request failed: \(String(describing: error))")
        }
    }

    @available(iOS 16.2, *)
    private func makeState(
        chapterSnapshot: LiveActivityChapterSnapshot?,
        categorySetName: String,
        islandCategories: [LiminalogActivityAttributes.IslandCategory]
    ) -> LiminalogActivityAttributes.ContentState {
        guard let chapterSnapshot else {
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
            activeCategoryID: chapterSnapshot.categoryID,
            categoryName: chapterSnapshot.categoryName,
            colorHex: chapterSnapshot.categoryColorHex,
            icon: chapterSnapshot.categoryIcon,
            startedAt: chapterSnapshot.startTime,
            isPublic: chapterSnapshot.isPublic,
            categorySetName: categorySetName,
            categories: islandCategories,
            updatedAt: Date()
        )
    }
}
