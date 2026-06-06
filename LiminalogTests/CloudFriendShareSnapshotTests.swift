import Foundation
import Testing
@testable import Liminalog

struct CloudFriendShareSnapshotTests {
    @Test
    func snapshotPayloadRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_780_764_000)
        let plan = FriendSharedPlanSnapshot(
            title: "集中する",
            startTime: now,
            endTime: now.addingTimeInterval(3_600),
            isImportant: true,
            categoryTitle: "仕事",
            categoryIconName: "briefcase.fill",
            categoryColorHex: "#2F80ED",
            updatedAt: now
        )
        let activity = FriendSharedActivitySnapshot(
            title: "読書",
            startTime: now,
            endTime: now.addingTimeInterval(1_800),
            categoryTitle: "休憩",
            categoryIconName: "book.fill",
            categoryColorHex: "#34C759",
            note: "よかった",
            mood: "落ち着いた",
            updatedAt: now
        )
        let snapshot = CloudFriendShareSnapshot(
            ownerUsername: "ryu",
            ownerDisplayName: "Ryu",
            targetUserRecordName: "_target",
            currentStatusTitle: "読書",
            currentStatusIcon: "book.fill",
            currentStatusColorHex: "#34C759",
            currentMoodText: "落ち着いた",
            currentStatusStartedAt: now,
            todayScore: 82,
            yesterdayScore: 77,
            weekScore: 69,
            monthScore: 71,
            yearScore: 73,
            streakCount: 12,
            sharedPlans: [plan],
            sharedActivities: [activity],
            updatedAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CloudFriendShareSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.sharedPlans.first?.isImportant == true)
        #expect(decoded.sharedActivities.first?.mood == "落ち着いた")
    }
}
