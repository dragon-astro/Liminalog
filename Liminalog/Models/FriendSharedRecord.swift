import Foundation
import SwiftData

/// 友達から共有された予定の「個別行」キャッシュ（docs/20 §2.2）。
/// 塊JSON（`Friend.sharedPlansJSON`）と違い、カレンダー等は表示範囲だけを fetch できる。
/// LocalCache ストア（CloudKit同期なし）に置く派生データなので、消えても再同期で復元できる。
@Model
final class FriendSharedPlanRecord {
    #Index<FriendSharedPlanRecord>([\.friendID, \.startTime])

    var friendID: UUID = UUID()
    /// オーナー側 PlanBlock の UUID。upsert・削除同期の突合キー。
    var sourceID: UUID = UUID()
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date = Date()
    var isAllDay: Bool = false
    var isImportant: Bool = false
    var categoryID: UUID?
    var categoryTitle: String = ""
    var categoryIconName: String = "calendar"
    var categoryColorHex: String = "#2F80ED"
    var updatedAt: Date = Date()

    init() {}

    convenience init(friendID: UUID, snapshot: FriendSharedPlanSnapshot) {
        self.init()
        self.friendID = friendID
        self.sourceID = snapshot.id
        apply(snapshot)
    }

    func apply(_ snapshot: FriendSharedPlanSnapshot) {
        title = snapshot.title
        startTime = snapshot.startTime
        endTime = snapshot.endTime
        isAllDay = snapshot.isAllDay
        isImportant = snapshot.isImportant
        categoryID = snapshot.categoryID
        categoryTitle = snapshot.categoryTitle
        categoryIconName = snapshot.categoryIconName
        categoryColorHex = snapshot.categoryColorHex
        updatedAt = snapshot.updatedAt
    }

    var snapshot: FriendSharedPlanSnapshot {
        FriendSharedPlanSnapshot(
            id: sourceID,
            categoryID: categoryID,
            title: title,
            startTime: startTime,
            endTime: endTime,
            isAllDay: isAllDay,
            isImportant: isImportant,
            categoryTitle: categoryTitle,
            categoryIconName: categoryIconName,
            categoryColorHex: categoryColorHex,
            updatedAt: updatedAt
        )
    }
}

/// 友達から共有された実績（チャプター）の個別行キャッシュ。`FriendSharedPlanRecord` と対。
@Model
final class FriendSharedChapterRecord {
    #Index<FriendSharedChapterRecord>([\.friendID, \.startTime])

    var friendID: UUID = UUID()
    /// オーナー側 Chapter の UUID。upsert・削除同期の突合キー。
    var sourceID: UUID = UUID()
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date = Date()
    var categoryID: UUID?
    var categoryTitle: String = ""
    var categoryIconName: String = "circle.fill"
    var categoryColorHex: String = "#2F80ED"
    var note: String?
    var mood: String?
    var locationName: String?
    var updatedAt: Date = Date()

    init() {}

    convenience init(friendID: UUID, snapshot: FriendSharedActivitySnapshot) {
        self.init()
        self.friendID = friendID
        self.sourceID = snapshot.id
        apply(snapshot)
    }

    func apply(_ snapshot: FriendSharedActivitySnapshot) {
        title = snapshot.title
        startTime = snapshot.startTime
        endTime = snapshot.endTime
        categoryID = snapshot.categoryID
        categoryTitle = snapshot.categoryTitle
        categoryIconName = snapshot.categoryIconName
        categoryColorHex = snapshot.categoryColorHex
        note = snapshot.note
        mood = snapshot.mood
        locationName = snapshot.locationName
        updatedAt = snapshot.updatedAt
    }

    var snapshot: FriendSharedActivitySnapshot {
        FriendSharedActivitySnapshot(
            id: sourceID,
            categoryID: categoryID,
            title: title,
            startTime: startTime,
            endTime: endTime,
            categoryTitle: categoryTitle,
            categoryIconName: categoryIconName,
            categoryColorHex: categoryColorHex,
            note: note,
            mood: mood,
            locationName: locationName,
            updatedAt: updatedAt
        )
    }
}

/// 友達から共有された日別スコアの個別行キャッシュ。
/// 予定/実績から受信側で毎回再計算せず、送信側で確定した軽量な値だけを読む。
@Model
final class FriendSharedScoreRecord {
    #Index<FriendSharedScoreRecord>([\.friendID, \.dayStart])

    var friendID: UUID = UUID()
    /// 日付から決まる安定ID。upsert・削除同期の突合キー。
    var sourceID: UUID = UUID()
    var dayStart: Date = Date.distantPast
    var dayIdentifier: String = ""
    var score: Int = 0
    var plannedDuration: TimeInterval = 0
    var recordedDuration: TimeInterval = 0
    var hasData: Bool = false
    var updatedAt: Date = Date()

    init() {}

    convenience init(friendID: UUID, snapshot: FriendSharedDailyScoreSnapshot) {
        self.init()
        self.friendID = friendID
        self.sourceID = snapshot.id
        apply(snapshot)
    }

    func apply(_ snapshot: FriendSharedDailyScoreSnapshot) {
        dayStart = snapshot.dayStart
        dayIdentifier = snapshot.dayIdentifier
        score = snapshot.score
        plannedDuration = snapshot.plannedDuration
        recordedDuration = snapshot.recordedDuration
        hasData = snapshot.hasData
        updatedAt = snapshot.updatedAt
    }

    var snapshot: FriendSharedDailyScoreSnapshot {
        FriendSharedDailyScoreSnapshot(
            id: sourceID,
            dayStart: dayStart,
            dayIdentifier: dayIdentifier,
            score: score,
            plannedDuration: plannedDuration,
            recordedDuration: recordedDuration,
            hasData: hasData,
            updatedAt: updatedAt
        )
    }
}
