import CloudKit
import Testing
@testable import Liminalog

struct CloudFriendRecordAuthenticityPolicyTests {
    private let owner = "_ownerRecordName"
    private let attacker = "_attackerRecordName"

    @Test
    func acceptsRecordCreatedByClaimedOwner() {
        #expect(CloudFriendRecordAuthenticityPolicy.isAuthentic(
            claimedOwnerUserRecordName: owner,
            creatorUserRecordName: owner,
            currentUserRecordName: "_someoneElse"
        ))
    }

    @Test
    func rejectsRecordForgedByThirdParty() {
        // 攻撃者が ownerUserRecordName フィールドだけ他人名義にして作成したレコード。
        #expect(!CloudFriendRecordAuthenticityPolicy.isAuthentic(
            claimedOwnerUserRecordName: owner,
            creatorUserRecordName: attacker,
            currentUserRecordName: owner
        ))
    }

    @Test
    func acceptsOwnRecordWithDefaultOwnerCreator() {
        // 自分が作成したレコードは creator が __defaultOwner__ で返ることがある。
        #expect(CloudFriendRecordAuthenticityPolicy.isAuthentic(
            claimedOwnerUserRecordName: owner,
            creatorUserRecordName: CKCurrentUserDefaultName,
            currentUserRecordName: owner
        ))
    }

    @Test
    func rejectsDefaultOwnerCreatorClaimingSomeoneElse() {
        #expect(!CloudFriendRecordAuthenticityPolicy.isAuthentic(
            claimedOwnerUserRecordName: attacker,
            creatorUserRecordName: CKCurrentUserDefaultName,
            currentUserRecordName: owner
        ))
    }

    @Test
    func missingCreatorIsTrustedOnlyForOwnRecords() {
        #expect(CloudFriendRecordAuthenticityPolicy.isAuthentic(
            claimedOwnerUserRecordName: owner,
            creatorUserRecordName: nil,
            currentUserRecordName: owner
        ))
        #expect(!CloudFriendRecordAuthenticityPolicy.isAuthentic(
            claimedOwnerUserRecordName: owner,
            creatorUserRecordName: nil,
            currentUserRecordName: attacker
        ))
        #expect(!CloudFriendRecordAuthenticityPolicy.isAuthentic(
            claimedOwnerUserRecordName: owner,
            creatorUserRecordName: nil,
            currentUserRecordName: nil
        ))
    }

    @Test
    func emptyCreatorBehavesLikeMissingCreator() {
        #expect(!CloudFriendRecordAuthenticityPolicy.isAuthentic(
            claimedOwnerUserRecordName: owner,
            creatorUserRecordName: "",
            currentUserRecordName: attacker
        ))
    }
}
