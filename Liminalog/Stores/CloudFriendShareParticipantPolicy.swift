import Foundation

enum CloudFriendShareParticipantPolicy {
    struct ParticipantState: Equatable {
        let userRecordName: String?
        let isReadOnly: Bool
        let isOwner: Bool

        init(userRecordName: String?, isReadOnly: Bool, isOwner: Bool = false) {
            self.userRecordName = userRecordName
            self.isReadOnly = isReadOnly
            self.isOwner = isOwner
        }
    }

    static func needsReadOnlyTargetParticipant(
        targetUserRecordName: String,
        participants: [ParticipantState]
    ) -> Bool {
        !participants.contains {
            $0.userRecordName == targetUserRecordName && $0.isReadOnly
        }
    }

    static func shouldRemoveParticipant(
        targetUserRecordName: String,
        participant: ParticipantState
    ) -> Bool {
        guard !participant.isOwner else { return false }
        return participant.userRecordName != targetUserRecordName
    }
}
