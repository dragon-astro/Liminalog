import CloudKit
import Foundation

/// 友達共有の個別アイテム（予定/実績）を CloudKit レコードへ載せ替えるための変換規約（docs/20 §2.1）。
/// - レコードは共有ゾーン内で、対象友達のルート（`friend-share:{owner}:{target}`）を `parent` に持つ。
///   CKShare はルート階層に張られているため、parent を張った子レコードだけが対象友達に見える。
/// - recordName に target を含めるのは、同じ予定を複数の友達に共有する際に
///   友達ごとの可視性フィルタ済みレコードを別物として持つため。
enum FriendSharedItemRecordPolicy {
    static let planRecordType = "SharedPlan"
    static let chapterRecordType = "SharedChapter"
    static let scoreRecordType = "SharedDailyScore"

    enum Field {
        static let sourceID = "sourceID"
        static let title = "title"
        static let startTime = "startTime"
        static let endTime = "endTime"
        static let isAllDay = "isAllDay"
        static let isImportant = "isImportant"
        static let categoryID = "categoryID"
        static let categoryTitle = "categoryTitle"
        static let categoryIconName = "categoryIconName"
        static let categoryColorHex = "categoryColorHex"
        static let note = "note"
        static let mood = "mood"
        static let locationName = "locationName"
        static let dayIdentifier = "dayIdentifier"
        static let score = "score"
        static let plannedDuration = "plannedDuration"
        static let recordedDuration = "recordedDuration"
        static let hasData = "hasData"
        static let updatedAt = "updatedAt"
    }

    // MARK: - recordName

    static func planRecordName(targetUserRecordName: String, sourceID: UUID) -> String {
        "shared-plan:\(targetUserRecordName):\(sourceID.uuidString)"
    }

    static func chapterRecordName(targetUserRecordName: String, sourceID: UUID) -> String {
        "shared-chapter:\(targetUserRecordName):\(sourceID.uuidString)"
    }

    static func scoreRecordName(targetUserRecordName: String, sourceID: UUID) -> String {
        "shared-score:\(targetUserRecordName):\(sourceID.uuidString)"
    }

    /// recordName から sourceID を取り出す（削除通知の反映用）。対象外のレコード名は nil。
    static func planSourceID(fromRecordName recordName: String) -> UUID? {
        sourceID(fromRecordName: recordName, prefix: "shared-plan:")
    }

    static func chapterSourceID(fromRecordName recordName: String) -> UUID? {
        sourceID(fromRecordName: recordName, prefix: "shared-chapter:")
    }

    static func scoreSourceID(fromRecordName recordName: String) -> UUID? {
        sourceID(fromRecordName: recordName, prefix: "shared-score:")
    }

    private static func sourceID(fromRecordName recordName: String, prefix: String) -> UUID? {
        guard recordName.hasPrefix(prefix) else { return nil }
        guard let lastColon = recordName.lastIndex(of: ":") else { return nil }
        return UUID(uuidString: String(recordName[recordName.index(after: lastColon)...]))
    }

    // MARK: - snapshot → CKRecord

    static func apply(
        _ snapshot: FriendSharedPlanSnapshot,
        to record: CKRecord,
        parentRecordID: CKRecord.ID
    ) {
        record.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
        record[Field.sourceID] = snapshot.id.uuidString as CKRecordValue
        record[Field.title] = snapshot.title as CKRecordValue
        record[Field.startTime] = snapshot.startTime as CKRecordValue
        record[Field.endTime] = snapshot.endTime as CKRecordValue
        record[Field.isAllDay] = snapshot.isAllDay as CKRecordValue
        record[Field.isImportant] = snapshot.isImportant as CKRecordValue
        record[Field.categoryID] = snapshot.categoryID?.uuidString as CKRecordValue?
        record[Field.categoryTitle] = snapshot.categoryTitle as CKRecordValue
        record[Field.categoryIconName] = snapshot.categoryIconName as CKRecordValue
        record[Field.categoryColorHex] = snapshot.categoryColorHex as CKRecordValue
        record[Field.updatedAt] = snapshot.updatedAt as CKRecordValue
    }

    static func apply(
        _ snapshot: FriendSharedActivitySnapshot,
        to record: CKRecord,
        parentRecordID: CKRecord.ID
    ) {
        record.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
        record[Field.sourceID] = snapshot.id.uuidString as CKRecordValue
        record[Field.title] = snapshot.title as CKRecordValue
        record[Field.startTime] = snapshot.startTime as CKRecordValue
        record[Field.endTime] = snapshot.endTime as CKRecordValue
        record[Field.categoryID] = snapshot.categoryID?.uuidString as CKRecordValue?
        record[Field.categoryTitle] = snapshot.categoryTitle as CKRecordValue
        record[Field.categoryIconName] = snapshot.categoryIconName as CKRecordValue
        record[Field.categoryColorHex] = snapshot.categoryColorHex as CKRecordValue
        record[Field.note] = snapshot.note as CKRecordValue?
        record[Field.mood] = snapshot.mood as CKRecordValue?
        record[Field.locationName] = snapshot.locationName as CKRecordValue?
        record[Field.updatedAt] = snapshot.updatedAt as CKRecordValue
    }

    static func apply(
        _ snapshot: FriendSharedDailyScoreSnapshot,
        to record: CKRecord,
        parentRecordID: CKRecord.ID
    ) {
        record.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
        record[Field.sourceID] = snapshot.id.uuidString as CKRecordValue
        record[Field.startTime] = snapshot.dayStart as CKRecordValue
        record[Field.dayIdentifier] = snapshot.dayIdentifier as CKRecordValue
        record[Field.score] = snapshot.score as CKRecordValue
        record[Field.plannedDuration] = snapshot.plannedDuration as CKRecordValue
        record[Field.recordedDuration] = snapshot.recordedDuration as CKRecordValue
        record[Field.hasData] = snapshot.hasData as CKRecordValue
        record[Field.updatedAt] = snapshot.updatedAt as CKRecordValue
    }

    // MARK: - CKRecord → snapshot

    static func planSnapshot(from record: CKRecord) -> FriendSharedPlanSnapshot? {
        guard record.recordType == planRecordType,
              let sourceIDString = record[Field.sourceID] as? String,
              let sourceID = UUID(uuidString: sourceIDString),
              let title = record[Field.title] as? String,
              let startTime = record[Field.startTime] as? Date,
              let endTime = record[Field.endTime] as? Date,
              let updatedAt = record[Field.updatedAt] as? Date
        else { return nil }

        return FriendSharedPlanSnapshot(
            id: sourceID,
            categoryID: (record[Field.categoryID] as? String).flatMap(UUID.init(uuidString:)),
            title: title,
            startTime: startTime,
            endTime: endTime,
            isAllDay: (record[Field.isAllDay] as? Bool) ?? false,
            isImportant: (record[Field.isImportant] as? Bool) ?? false,
            categoryTitle: (record[Field.categoryTitle] as? String) ?? "",
            categoryIconName: (record[Field.categoryIconName] as? String) ?? "calendar",
            categoryColorHex: (record[Field.categoryColorHex] as? String) ?? "#2F80ED",
            updatedAt: updatedAt
        )
    }

    static func activitySnapshot(from record: CKRecord) -> FriendSharedActivitySnapshot? {
        guard record.recordType == chapterRecordType,
              let sourceIDString = record[Field.sourceID] as? String,
              let sourceID = UUID(uuidString: sourceIDString),
              let title = record[Field.title] as? String,
              let startTime = record[Field.startTime] as? Date,
              let endTime = record[Field.endTime] as? Date,
              let updatedAt = record[Field.updatedAt] as? Date
        else { return nil }

        return FriendSharedActivitySnapshot(
            id: sourceID,
            categoryID: (record[Field.categoryID] as? String).flatMap(UUID.init(uuidString:)),
            title: title,
            startTime: startTime,
            endTime: endTime,
            categoryTitle: (record[Field.categoryTitle] as? String) ?? "",
            categoryIconName: (record[Field.categoryIconName] as? String) ?? "circle.fill",
            categoryColorHex: (record[Field.categoryColorHex] as? String) ?? "#2F80ED",
            note: record[Field.note] as? String,
            mood: record[Field.mood] as? String,
            locationName: record[Field.locationName] as? String,
            updatedAt: updatedAt
        )
    }

    static func scoreSnapshot(from record: CKRecord) -> FriendSharedDailyScoreSnapshot? {
        guard record.recordType == scoreRecordType,
              let sourceIDString = record[Field.sourceID] as? String,
              let sourceID = UUID(uuidString: sourceIDString),
              let dayStart = record[Field.startTime] as? Date,
              let dayIdentifier = record[Field.dayIdentifier] as? String,
              let score = record[Field.score] as? Int,
              let plannedDuration = record[Field.plannedDuration] as? Double,
              let recordedDuration = record[Field.recordedDuration] as? Double,
              let hasData = record[Field.hasData] as? Bool,
              let updatedAt = record[Field.updatedAt] as? Date
        else { return nil }

        return FriendSharedDailyScoreSnapshot(
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
