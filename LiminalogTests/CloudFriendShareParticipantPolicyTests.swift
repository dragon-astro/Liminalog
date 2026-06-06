import Foundation
import Testing
@testable import Liminalog

struct CloudFriendShareParticipantPolicyTests {
    @Test
    func doesNotNeedRepairWhenTargetParticipantIsReadOnly() {
        let participants = [
            CloudFriendShareParticipantPolicy.ParticipantState(
                userRecordName: "_target",
                isReadOnly: true
            )
        ]

        #expect(!CloudFriendShareParticipantPolicy.needsReadOnlyTargetParticipant(
            targetUserRecordName: "_target",
            participants: participants
        ))
    }

    @Test
    func needsRepairWhenTargetParticipantIsMissing() {
        let participants = [
            CloudFriendShareParticipantPolicy.ParticipantState(
                userRecordName: "_other",
                isReadOnly: true
            )
        ]

        #expect(CloudFriendShareParticipantPolicy.needsReadOnlyTargetParticipant(
            targetUserRecordName: "_target",
            participants: participants
        ))
    }

    @Test
    func needsRepairWhenTargetParticipantIsNotReadOnly() {
        let participants = [
            CloudFriendShareParticipantPolicy.ParticipantState(
                userRecordName: "_target",
                isReadOnly: false
            )
        ]

        #expect(CloudFriendShareParticipantPolicy.needsReadOnlyTargetParticipant(
            targetUserRecordName: "_target",
            participants: participants
        ))
    }
}
