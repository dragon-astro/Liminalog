import Foundation
import SwiftData

@Model
final class FriendSet {
    var id: UUID = UUID()
    var name: String = ""
    var memberFriendIDs: [UUID] = []
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    init(
        name: String,
        memberFriendIDs: [UUID] = [],
        sortOrder: Int = 0,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.memberFriendIDs = memberFriendIDs
        self.sortOrder = sortOrder
        self.createdAt = now
        self.updatedAt = now
    }
}
