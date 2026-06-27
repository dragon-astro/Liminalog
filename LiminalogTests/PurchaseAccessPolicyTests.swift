import Foundation
import Testing
@testable import Liminalog

struct PurchaseAccessPolicyTests {
    @Test
    func coreFeaturesRemainFree() {
        let freeEntitlements = PurchaseEntitlements()
        let freeFeatures: [PurchaseFeature] = [
            .coreRecording,
            .calendarSelfView,
            .friendsAndSharing,
            .dailyCards,
            .todayScoreAndStreak
        ]

        for feature in freeFeatures {
            let decision = paidFeatureGate.decision(for: feature, entitlements: freeEntitlements)
            #expect(decision.requirement == .free)
            #expect(decision.isAllowed)
        }
    }

    @Test
    func statisticsAndPowerFeaturesRequirePro() {
        let freeEntitlements = PurchaseEntitlements()
        let proEntitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.proYearly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )
        let proFeatures: [PurchaseFeature] = [
            .statisticsTab,
            .unlimitedCategorySets,
            .export,
            .advancedWidgets,
            .appLock,
            .healthKitAutomation
        ]

        for feature in proFeatures {
            let freeDecision = paidFeatureGate.decision(for: feature, entitlements: freeEntitlements)
            let proDecision = paidFeatureGate.decision(for: feature, entitlements: proEntitlements)
            #expect(freeDecision.requirement == .pro)
            #expect(!freeDecision.isAllowed)
            #expect(proDecision.requirement == .pro)
            #expect(proDecision.isAllowed)
        }
    }

    @Test
    func lifetimeCountsAsProButDoesNotRentDecorations() {
        let lifetimeEntitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.lifetime.rawValue],
            ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
            lastVerifiedAt: Date()
        )

        #expect(paidFeatureGate.decision(for: .statisticsTab, entitlements: lifetimeEntitlements).isAllowed)
        #expect(!paidFeatureGate.decision(for: .premiumDecorationRental, entitlements: lifetimeEntitlements).isAllowed)
    }

    @Test
    func categorySetLimitIsTwoForFreeAndUnlimitedForPro() {
        let freeEntitlements = PurchaseEntitlements()
        let proEntitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.proMonthly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )

        #expect(paidFeatureGate.categorySetLimit(entitlements: freeEntitlements) == 2)
        #expect(paidFeatureGate.categorySetLimit(entitlements: proEntitlements) == nil)
    }

    @Test
    func permanentDecorationOwnershipIsSeparateFromRental() {
        let decorationID = "liminalog.decoration.theme.aurora"
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [decorationID],
            ownedNonConsumableProductIDs: [decorationID],
            lastVerifiedAt: Date()
        )

        #expect(entitlements.ownedPremiumDecorationProductIDs.contains(decorationID))
        #expect(!paidFeatureGate.decision(for: .premiumDecorationRental, entitlements: entitlements).isAllowed)
    }

    @Test
    func featureGateKeepsEverythingFreeUntilMonetizationIsActivated() {
        let gate = PurchaseFeatureGate(
            activationPolicy: PurchaseActivationPolicy(
                configuration: .current,
                buildMode: .release
            )
        )
        let freeEntitlements = PurchaseEntitlements()

        #expect(gate.decision(for: .statisticsTab, entitlements: freeEntitlements).isAllowed)
        #expect(gate.decision(for: .statisticsTab, entitlements: freeEntitlements).requirement == .free)
        #expect(gate.categorySetLimit(entitlements: freeEntitlements) == nil)
    }

    @Test
    func featureGateKeepsExistingFeaturesFreeWhenPurchaseSurfaceIsReadyButRestrictionsAreDisabled() throws {
        let termsURL = try #require(URL(string: "https://example.com/terms"))
        let privacyURL = try #require(URL(string: "https://example.com/privacy"))
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true
        )
        let gate = PurchaseFeatureGate(
            activationPolicy: PurchaseActivationPolicy(
                configuration: configuration,
                buildMode: .release
            )
        )
        let freeEntitlements = PurchaseEntitlements()

        let decision = gate.decision(for: .statisticsTab, entitlements: freeEntitlements)
        #expect(decision.requirement == .free)
        #expect(decision.isAllowed)
        #expect(gate.categorySetLimit(entitlements: freeEntitlements) == nil)
    }

    @Test
    func featureGateAppliesPaidPolicyOnlyAfterRestrictionsAreExplicitlyEnabled() {
        let gate = PurchaseFeatureGate(
            activationPolicy: PurchaseActivationPolicy(
                configuration: readyConfiguration(featureRestrictionsAreEnabled: true),
                buildMode: .release
            )
        )
        let freeEntitlements = PurchaseEntitlements()

        let decision = gate.decision(for: .statisticsTab, entitlements: freeEntitlements)
        #expect(decision.requirement == .pro)
        #expect(!decision.isAllowed)
        #expect(gate.categorySetLimit(entitlements: freeEntitlements) == 2)
    }

    private var paidFeatureGate: PurchaseFeatureGate {
        PurchaseFeatureGate(
            activationPolicy: PurchaseActivationPolicy(
                configuration: readyConfiguration(featureRestrictionsAreEnabled: true),
                buildMode: .release
            )
        )
    }

    private func readyConfiguration(featureRestrictionsAreEnabled: Bool) -> PurchaseConfiguration {
        PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: URL(string: "https://example.com/terms")!,
                privacyPolicyURL: URL(string: "https://example.com/privacy")!
            ),
            purchaseEntryPointIsEnabled: true,
            featureRestrictionsAreEnabled: featureRestrictionsAreEnabled
        )
    }
}
