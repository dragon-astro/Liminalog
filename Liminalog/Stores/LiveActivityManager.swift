import Foundation
import ActivityKit

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private init() {}

    @available(iOS 16.2, *)
    func update(activeChapter: Chapter?, categorySetName: String) async {
        let state = makeState(
            activeChapter: activeChapter,
            categorySetName: categorySetName
        )

        if let activity = Activity<LiminalogActivityAttributes>.activities.first {
            if state.isRecording {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            } else {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
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
    private func makeState(activeChapter: Chapter?, categorySetName: String) -> LiminalogActivityAttributes.ContentState {
        guard let activeChapter, let category = activeChapter.category else {
            return LiminalogActivityAttributes.ContentState(
                categoryName: nil,
                colorHex: "#8E8E93",
                icon: nil,
                startedAt: nil,
                isPublic: true,
                categorySetName: categorySetName
            )
        }

        return LiminalogActivityAttributes.ContentState(
            categoryName: category.name,
            colorHex: category.colorHex,
            icon: category.icon,
            startedAt: activeChapter.startTime,
            isPublic: activeChapter.isPublic,
            categorySetName: categorySetName
        )
    }
}
