import Foundation
import Testing
@testable import Liminalog

struct CloudFriendLocalStatePolicyTests {
    @Test
    func localInviteCanBeAcceptedWithoutCloudConsent() {
        #expect(CloudFriendLocalStatePolicy.canAcceptWithoutCloudConsent(userRecordID: ""))
        #expect(CloudFriendLocalStatePolicy.canAcceptWithoutCloudConsent(userRecordID: "   "))
    }

    @Test
    func cloudFriendRequiresCloudConsentBeforeLocalAccept() {
        #expect(!CloudFriendLocalStatePolicy.canAcceptWithoutCloudConsent(userRecordID: "_cloud-user-record"))
    }

    @Test
    func incomingShareIsKeptOnlyAfterAcceptance() {
        #expect(CloudFriendLocalStatePolicy.shouldKeepIncomingShare(
            status: .accepted,
            incomingShareURL: "https://example.com/share"
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(status: .accepted, incomingShareURL: nil))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(status: .accepted, incomingShareURL: "   "))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(
            status: .pendingIncoming,
            incomingShareURL: "https://example.com/share"
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(
            status: .pendingOutgoing,
            incomingShareURL: "https://example.com/share"
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldKeepIncomingShare(
            status: .blocked,
            incomingShareURL: "https://example.com/share"
        ))
    }

    @Test
    func outgoingRequestIsRejectedOnlyForLocalBlock() {
        #expect(CloudFriendLocalStatePolicy.shouldRejectOutgoingRequest(existingStatus: .blocked))
        #expect(!CloudFriendLocalStatePolicy.shouldRejectOutgoingRequest(existingStatus: .accepted))
        #expect(!CloudFriendLocalStatePolicy.shouldRejectOutgoingRequest(existingStatus: .pendingIncoming))
        #expect(!CloudFriendLocalStatePolicy.shouldRejectOutgoingRequest(existingStatus: .pendingOutgoing))
        #expect(!CloudFriendLocalStatePolicy.shouldRejectOutgoingRequest(existingStatus: nil))
    }

    @Test
    func acceptedCloudFriendDowngradesWhenAcceptedConsentIsMissing() {
        #expect(CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
            status: .accepted,
            userRecordID: "_friend",
            acceptedCloudFriendRecordNames: []
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
            status: .accepted,
            userRecordID: "_friend",
            acceptedCloudFriendRecordNames: ["_friend"]
        ))
    }

    @Test
    func localOrNonAcceptedFriendsDoNotDowngradeOnMissingConsent() {
        #expect(!CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
            status: .accepted,
            userRecordID: "   ",
            acceptedCloudFriendRecordNames: []
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
            status: .pendingOutgoing,
            userRecordID: "_friend",
            acceptedCloudFriendRecordNames: []
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldDowngradeAcceptedCloudFriend(
            status: .blocked,
            userRecordID: "_friend",
            acceptedCloudFriendRecordNames: []
        ))
    }

    @Test
    func automaticCloudRequestRefreshRunsOncePerLoadedUser() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(CloudFriendLocalStatePolicy.shouldRefreshCloudRequests(
            trigger: .automatic,
            currentUserRecordName: "_current",
            loadedUserRecordName: nil,
            lastAutomaticAttemptAt: nil,
            now: now
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldRefreshCloudRequests(
            trigger: .automatic,
            currentUserRecordName: "_current",
            loadedUserRecordName: "_current",
            lastAutomaticAttemptAt: nil,
            now: now
        ))
        #expect(CloudFriendLocalStatePolicy.shouldRefreshCloudRequests(
            trigger: .automatic,
            currentUserRecordName: "_other",
            loadedUserRecordName: "_current",
            lastAutomaticAttemptAt: nil,
            now: now
        ))
    }

    @Test
    func automaticCloudRequestRefreshThrottlesRecentFailedAttempts() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(!CloudFriendLocalStatePolicy.shouldRefreshCloudRequests(
            trigger: .automatic,
            currentUserRecordName: "_current",
            loadedUserRecordName: nil,
            lastAutomaticAttemptAt: now.addingTimeInterval(-30),
            now: now
        ))
        #expect(CloudFriendLocalStatePolicy.shouldRefreshCloudRequests(
            trigger: .automatic,
            currentUserRecordName: "_current",
            loadedUserRecordName: nil,
            lastAutomaticAttemptAt: now.addingTimeInterval(-121),
            now: now
        ))
    }

    @Test
    func manualAndEventCloudRequestRefreshBypassAutomaticGuards() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(CloudFriendLocalStatePolicy.shouldRefreshCloudRequests(
            trigger: .manual,
            currentUserRecordName: "_current",
            loadedUserRecordName: "_current",
            lastAutomaticAttemptAt: now,
            now: now
        ))
        #expect(CloudFriendLocalStatePolicy.shouldRefreshCloudRequests(
            trigger: .event,
            currentUserRecordName: "_current",
            loadedUserRecordName: "_current",
            lastAutomaticAttemptAt: now,
            now: now
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldRefreshCloudRequests(
            trigger: .manual,
            currentUserRecordName: "   ",
            loadedUserRecordName: nil,
            lastAutomaticAttemptAt: nil,
            now: now
        ))
    }

    @Test
    func outgoingLifecycleShareRefreshThrottlesRecentAutomaticRuns() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(CloudFriendLocalStatePolicy.shouldScheduleOutgoingLifecycleShareRefresh(
            hasPendingExplicitRefresh: false,
            lastAutomaticScheduledAt: nil,
            now: now
        ))
        #expect(!CloudFriendLocalStatePolicy.shouldScheduleOutgoingLifecycleShareRefresh(
            hasPendingExplicitRefresh: false,
            lastAutomaticScheduledAt: now.addingTimeInterval(-300),
            now: now
        ))
        #expect(CloudFriendLocalStatePolicy.shouldScheduleOutgoingLifecycleShareRefresh(
            hasPendingExplicitRefresh: false,
            lastAutomaticScheduledAt: now.addingTimeInterval(-601),
            now: now
        ))
    }

    @Test
    func outgoingLifecycleShareRefreshRunsWhenExplicitChangeIsPending() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(CloudFriendLocalStatePolicy.shouldScheduleOutgoingLifecycleShareRefresh(
            hasPendingExplicitRefresh: true,
            lastAutomaticScheduledAt: now,
            now: now
        ))
    }

    @MainActor
    @Test
    func outgoingRefreshPendingMarkerRoundTripsInUserDefaults() throws {
        let suiteName = "CloudFriendLocalStatePolicyTests.outgoingRefreshPendingMarker"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        #expect(!CloudFriendShareRefreshCoordinator.hasPendingOutgoingRefreshMarker(defaults: defaults))

        CloudFriendShareRefreshCoordinator.markPendingOutgoingRefresh(defaults: defaults)
        #expect(CloudFriendShareRefreshCoordinator.hasPendingOutgoingRefreshMarker(defaults: defaults))

        CloudFriendShareRefreshCoordinator.clearPendingOutgoingRefreshMarker(defaults: defaults)
        #expect(!CloudFriendShareRefreshCoordinator.hasPendingOutgoingRefreshMarker(defaults: defaults))
    }
}
