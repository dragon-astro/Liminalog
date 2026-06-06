import CloudKit
import Testing
@testable import Liminalog

struct CloudKitRecordExistencePolicyTests {
    @Test
    func treatsCloudKitUnknownItemAsMissing() {
        #expect(CloudKitRecordExistencePolicy.shouldTreatFetchErrorAsMissing(CKError(.unknownItem)))
    }

    @Test
    func treatsStoreMissingRecordErrorsAsMissing() {
        #expect(CloudKitRecordExistencePolicy.shouldTreatFetchErrorAsMissing(CloudKitSocialError.profileNotFound))
        #expect(CloudKitRecordExistencePolicy.shouldTreatFetchErrorAsMissing(CloudFriendShareError.missingRootRecord))
    }

    @Test
    func doesNotTreatTransientCloudKitErrorAsMissing() {
        #expect(!CloudKitRecordExistencePolicy.shouldTreatFetchErrorAsMissing(CKError(.networkUnavailable)))
    }

    @Test
    func doesNotTreatAccountOrPayloadErrorsAsMissing() {
        #expect(!CloudKitRecordExistencePolicy.shouldTreatFetchErrorAsMissing(CloudKitSocialError.accountUnavailable))
        #expect(!CloudKitRecordExistencePolicy.shouldTreatFetchErrorAsMissing(CloudFriendShareError.invalidSnapshotPayload))
    }
}
