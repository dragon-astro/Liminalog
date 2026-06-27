import Foundation
import Testing
@testable import Liminalog

struct StatisticsTabAccessPolicyTests {
    @Test
    func currentReleaseConfigurationKeepsDashboardVisibleForFreeUsers() {
        let policy = StatisticsTabAccessPolicy(
            activationPolicy: PurchaseActivationPolicy(
                configuration: .current,
                buildMode: .release
            )
        )

        #expect(policy.destination(entitlements: PurchaseEntitlements()) == .dashboard)
    }

    @Test
    func purchaseEntryPointAloneDoesNotLockStatistics() {
        let policy = StatisticsTabAccessPolicy(
            activationPolicy: PurchaseActivationPolicy(
                configuration: readyConfiguration(purchaseEntryPointIsEnabled: true),
                buildMode: .release
            )
        )

        #expect(policy.destination(entitlements: PurchaseEntitlements()) == .dashboard)
    }

    @Test
    func freeUsersSeeProPreviewOnlyAfterFeatureRestrictionsAreEnabled() {
        let policy = StatisticsTabAccessPolicy(
            activationPolicy: PurchaseActivationPolicy(
                configuration: readyConfiguration(
                    purchaseEntryPointIsEnabled: true,
                    featureRestrictionsAreEnabled: true
                ),
                buildMode: .release
            )
        )

        #expect(policy.destination(entitlements: PurchaseEntitlements()) == .proPreview)
    }

    @Test
    func proAndLifetimeUsersKeepDashboardWhenRestrictionsAreEnabled() {
        let policy = StatisticsTabAccessPolicy(
            activationPolicy: PurchaseActivationPolicy(
                configuration: readyConfiguration(
                    purchaseEntryPointIsEnabled: true,
                    featureRestrictionsAreEnabled: true
                ),
                buildMode: .release
            )
        )
        let pro = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.proYearly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )
        let lifetime = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.lifetime.rawValue],
            ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
            lastVerifiedAt: Date()
        )

        #expect(policy.destination(entitlements: pro) == .dashboard)
        #expect(policy.destination(entitlements: lifetime) == .dashboard)
    }

    @Test
    func decorationPassAloneDoesNotUnlockStatistics() {
        let policy = StatisticsTabAccessPolicy(
            activationPolicy: PurchaseActivationPolicy(
                configuration: readyConfiguration(
                    purchaseEntryPointIsEnabled: true,
                    featureRestrictionsAreEnabled: true
                ),
                buildMode: .release
            )
        )
        let decorationPassOnly = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.decorationMonthly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )

        #expect(policy.destination(entitlements: decorationPassOnly) == .proPreview)
    }

    @Test
    func developmentBuildKeepsDashboardVisibleEvenWithReadyRestrictionConfiguration() {
        let policy = StatisticsTabAccessPolicy(
            activationPolicy: PurchaseActivationPolicy(
                configuration: readyConfiguration(
                    purchaseEntryPointIsEnabled: true,
                    featureRestrictionsAreEnabled: true
                ),
                buildMode: .development
            )
        )

        #expect(policy.destination(entitlements: PurchaseEntitlements()) == .dashboard)
    }

    #if DEBUG
    @Test
    func debugForcedFeatureRestrictionsAllowVisualQaOfStatisticsPreview() {
        let policy = StatisticsTabDebugAccess.forcedFeatureRestrictionsPolicy
        let pro = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.proMonthly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )

        #expect(policy.destination(entitlements: PurchaseEntitlements()) == .proPreview)
        #expect(policy.destination(entitlements: pro) == .dashboard)
    }
    #endif

    private func readyConfiguration(
        purchaseEntryPointIsEnabled: Bool = false,
        featureRestrictionsAreEnabled: Bool = false
    ) -> PurchaseConfiguration {
        PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: URL(string: "https://example.com/terms")!,
                privacyPolicyURL: URL(string: "https://example.com/privacy")!
            ),
            purchaseEntryPointIsEnabled: purchaseEntryPointIsEnabled,
            featureRestrictionsAreEnabled: featureRestrictionsAreEnabled
        )
    }
}
