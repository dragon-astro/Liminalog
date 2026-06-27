import Foundation
import Testing
@testable import Liminalog

struct PremiumDecorationAccessPolicyTests {
    @Test
    func freeUsersCannotEquipPremiumDecorations() {
        let decision = policy.decision(
            for: auroraFrame,
            entitlements: PurchaseEntitlements()
        )

        #expect(decision.state == .unavailable)
        #expect(!decision.canEquip)
    }

    @Test
    func permanentOwnershipAllowsPremiumDecorationWithoutRental() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [auroraFrame.productID],
            ownedNonConsumableProductIDs: [auroraFrame.productID],
            lastVerifiedAt: Date()
        )
        let decision = policy.decision(for: auroraFrame, entitlements: entitlements)

        #expect(decision.state == .owned)
        #expect(decision.canEquip)
        #expect(decision.state.isPermanent)
    }

    @Test
    func proSubscriptionRentsPremiumDecorations() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.proYearly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )
        let decision = policy.decision(for: auroraFrame, entitlements: entitlements)

        #expect(decision.state == .rented)
        #expect(decision.canEquip)
        #expect(!decision.state.isPermanent)
    }

    @Test
    func decorationSubscriptionRentsPremiumDecorations() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.decorationMonthly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )
        let decision = policy.decision(for: auroraFrame, entitlements: entitlements)

        #expect(decision.state == .rented)
        #expect(decision.canEquip)
    }

    @Test
    func lifetimeDoesNotRentPremiumDecorations() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.lifetime.rawValue],
            ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
            lastVerifiedAt: Date()
        )
        let decision = policy.decision(for: auroraFrame, entitlements: entitlements)

        #expect(decision.state == .unavailable)
        #expect(!decision.canEquip)
    }

    @Test
    func ownershipTakesPrecedenceOverActiveRental() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [
                PurchaseProductID.proMonthly.rawValue,
                auroraFrame.productID
            ],
            ownedNonConsumableProductIDs: [auroraFrame.productID],
            lastVerifiedAt: Date()
        )
        let decision = policy.decision(for: auroraFrame, entitlements: entitlements)

        #expect(decision.state == .owned)
        #expect(decision.state.isPermanent)
    }

    @Test
    func unsupportedProductIDsDoNotBecomeEquippableThroughRental() {
        let supportTipProduct = PremiumDecorationProduct(
            productID: PurchaseProductID.supportTipSmall.rawValue,
            kind: .iconFrame,
            targetID: "support_tip_frame",
            displayName: "支援チップ風フレーム"
        )
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.proMonthly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )
        let decision = policy.decision(for: supportTipProduct, entitlements: entitlements)

        #expect(decision.state == .unavailable)
        #expect(!decision.canEquip)
    }

    private var policy: PremiumDecorationAccessPolicy {
        PremiumDecorationAccessPolicy()
    }

    private var auroraFrame: PremiumDecorationProduct {
        PremiumDecorationProduct(
            productID: "\(PurchaseProductID.premiumDecorationProductPrefix)aurora_frame",
            kind: .iconFrame,
            targetID: "aurora_frame",
            displayName: "極光フレーム"
        )
    }
}
