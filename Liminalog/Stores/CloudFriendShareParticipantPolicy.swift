import Foundation

enum CloudFriendShareParticipantPolicy {
    struct ParticipantState: Equatable {
        let userRecordName: String?
        let isReadOnly: Bool
    }

    static func needsReadOnlyTargetParticipant(
        targetUserRecordName: String,
        participants: [ParticipantState]
    ) -> Bool {
        !participants.contains {
            $0.userRecordName == targetUserRecordName && $0.isReadOnly
        }
    }
}
