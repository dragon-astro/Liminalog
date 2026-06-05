import Foundation
import SwiftData

@Model
final class Chapter {
    var id: UUID = UUID()
    var category: Category?
    var startTime: Date = Date()
    var endTime: Date?
    var note: String?
    var mood: String?
    var photoLocalIdentifier: String?
    var thumbnailData: Data?
    var locationName: String?
    var isPublic: Bool = true
    var visibilityScope: VisibilityScope = VisibilityScope.all
    var audienceFriendIDs: [UUID] = []
    var audienceSourceRawValue: String = AudienceSource.categoryDefaultSnapshot.rawValue
    var hasAudienceSnapshot: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var isActive: Bool { endTime == nil }

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    var durationLive: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    init() {}

    init(category: Category, startTime: Date = Date()) {
        self.id = UUID()
        self.category = category
        self.startTime = startTime
        self.endTime = nil
        self.note = nil
        self.mood = nil
        self.photoLocalIdentifier = nil
        self.thumbnailData = nil
        self.locationName = nil
        self.isPublic = true
        self.visibilityScope = .all
        self.audienceFriendIDs = []
        self.audienceSourceRawValue = AudienceSource.categoryDefaultSnapshot.rawValue
        self.hasAudienceSnapshot = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var audienceSource: AudienceSource {
        get { AudienceSource(rawValue: audienceSourceRawValue) ?? .categoryDefaultSnapshot }
        set { audienceSourceRawValue = newValue.rawValue }
    }
}

struct RecordingSwitchResult {
    let activeChapter: Chapter?
    let didCreateChapter: Bool
    let closedChapterCount: Int
}

enum RecordingSwitchLogic {
    @discardableResult
    static func switchToCategory(
        _ category: Category,
        at now: Date,
        activeChapters: [Chapter],
        insert: (Chapter) -> Void
    ) -> RecordingSwitchResult {
        let sameCategoryActive = activeChapters.first { $0.category?.id == category.id }
        var activeAfterChange = sameCategoryActive
        var closedChapterCount = 0

        for chapter in activeChapters where chapter.id != sameCategoryActive?.id {
            chapter.endTime = now
            chapter.updatedAt = now
            closedChapterCount += 1
        }

        guard sameCategoryActive == nil else {
            return RecordingSwitchResult(
                activeChapter: activeAfterChange,
                didCreateChapter: false,
                closedChapterCount: closedChapterCount
            )
        }

        let chapter = Chapter(category: category, startTime: now)
        insert(chapter)
        activeAfterChange = chapter

        return RecordingSwitchResult(
            activeChapter: activeAfterChange,
            didCreateChapter: true,
            closedChapterCount: closedChapterCount
        )
    }
}
