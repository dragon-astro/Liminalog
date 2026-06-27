import Foundation
import Testing
@testable import Liminalog

struct PurchaseEntitlementTests {
    @Test
    func productKindsExposeStableDisplayLabels() {
        #expect(PurchaseProductKind.proSubscription.displayLabel == "サブスクリプション")
        #expect(PurchaseProductKind.decorationSubscription.displayLabel == "サブスクリプション")
        #expect(PurchaseProductKind.lifetime.displayLabel == "買い切り")
        #expect(PurchaseProductKind.premiumDecoration.displayLabel == "買い切り")
        #expect(PurchaseProductKind.supportTip.displayLabel == "支援")
    }

    @Test
    func productIDsStayUniqueAndDisplayOrderCoversAllProducts() {
        let allIDs = PurchaseProductID.allCases.map(\.rawValue)

        #expect(Set(allIDs).count == allIDs.count)
        #expect(PurchaseProductID.primaryDisplayOrder == PurchaseProductID.allCases)
        #expect(PurchaseProductID.storeKitProductIDs == allIDs)
    }

    @Test
    func productIDsDeclareExpectedStoreKitProductTypes() {
        #expect(PurchaseProductID.expectedStoreKitProductKind(for: PurchaseProductID.proMonthly.rawValue) == .autoRenewableSubscription)
        #expect(PurchaseProductID.expectedStoreKitProductKind(for: PurchaseProductID.proYearly.rawValue) == .autoRenewableSubscription)
        #expect(PurchaseProductID.expectedStoreKitProductKind(for: PurchaseProductID.decorationMonthly.rawValue) == .autoRenewableSubscription)
        #expect(PurchaseProductID.expectedStoreKitProductKind(for: PurchaseProductID.decorationYearly.rawValue) == .autoRenewableSubscription)
        #expect(PurchaseProductID.expectedStoreKitProductKind(for: PurchaseProductID.lifetime.rawValue) == .nonConsumable)
        #expect(PurchaseProductID.expectedStoreKitProductKind(for: PurchaseProductID.supportTipSmall.rawValue) == .consumable)
        #expect(PurchaseProductID.expectedStoreKitProductKind(for: "liminalog.decoration.theme.aurora") == .nonConsumable)
        #expect(PurchaseProductID.expectedStoreKitProductKind(for: "liminalog.unknown") == nil)
    }

    @Test
    func productIDsOnlyAcceptMatchingStoreKitProductTypes() {
        #expect(PurchaseProductID.acceptsStoreKitProductKind(.autoRenewableSubscription, for: PurchaseProductID.proMonthly.rawValue))
        #expect(PurchaseProductID.acceptsStoreKitProductKind(.nonConsumable, for: PurchaseProductID.lifetime.rawValue))
        #expect(PurchaseProductID.acceptsStoreKitProductKind(.consumable, for: PurchaseProductID.supportTipSmall.rawValue))
        #expect(PurchaseProductID.acceptsStoreKitProductKind(.nonConsumable, for: "liminalog.decoration.theme.aurora"))

        #expect(!PurchaseProductID.acceptsStoreKitProductKind(.nonConsumable, for: PurchaseProductID.proMonthly.rawValue))
        #expect(!PurchaseProductID.acceptsStoreKitProductKind(.autoRenewableSubscription, for: PurchaseProductID.lifetime.rawValue))
        #expect(!PurchaseProductID.acceptsStoreKitProductKind(.nonConsumable, for: PurchaseProductID.supportTipSmall.rawValue))
        #expect(!PurchaseProductID.acceptsStoreKitProductKind(.nonConsumable, for: "liminalog.unknown"))
    }

    @Test
    func productDescriptionsDoNotPromiseUnconfirmedIntroductoryOffers() {
        let descriptions = PurchaseProductID.allCases.map(\.shortDescription)

        #expect(!descriptions.contains { $0.contains("想定") })
        #expect(!descriptions.contains { $0.contains("無料体験") })
    }

    @Test
    func proSubscriptionActivatesProAndDecorationRental() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.proMonthly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )

        #expect(entitlements.isProActive)
        #expect(!entitlements.hasLifetime)
        #expect(entitlements.hasPremiumDecorationRental)
    }

    @Test
    func lifetimeActivatesProWithoutRentingDecorations() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.lifetime.rawValue],
            ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
            lastVerifiedAt: Date()
        )

        #expect(entitlements.isProActive)
        #expect(entitlements.hasLifetime)
        #expect(!entitlements.hasPremiumDecorationRental)
    }

    @Test
    func decorationSubscriptionDoesNotActivatePro() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.decorationYearly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )

        #expect(!entitlements.isProActive)
        #expect(!entitlements.hasLifetime)
        #expect(entitlements.hasPremiumDecorationRental)
    }

    @Test
    func supportTipsDoNotGrantFeatureEntitlements() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.supportTipLarge.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )

        #expect(!entitlements.isProActive)
        #expect(!entitlements.hasLifetime)
        #expect(!entitlements.hasPremiumDecorationRental)
    }

    @Test
    func supportTipPurchaseMessageDoesNotClaimEntitlementUpdate() {
        #expect(
            PurchaseProductID.purchaseSuccessMessage(for: PurchaseProductID.supportTipSmall.rawValue)
                == "応援ありがとうございます。Liminalogの開発に使わせてもらいます。"
        )
    }

    @Test
    func entitlementProductsUsePurchaseStateUpdateMessage() {
        #expect(
            PurchaseProductID.purchaseSuccessMessage(for: PurchaseProductID.proYearly.rawValue)
                == "応援ありがとうございます。購入状態を更新しました。"
        )
        #expect(
            PurchaseProductID.purchaseSuccessMessage(for: PurchaseProductID.lifetime.rawValue)
                == "応援ありがとうございます。購入状態を更新しました。"
        )
        #expect(
            PurchaseProductID.purchaseSuccessMessage(for: "liminalog.decoration.theme.aurora")
                == "応援ありがとうございます。購入状態を更新しました。"
        )
    }

    @Test
    func premiumDecorationProductsAreRecognizedByStablePrefix() {
        let decorationID = "liminalog.decoration.theme.aurora"
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [decorationID],
            ownedNonConsumableProductIDs: [decorationID],
            lastVerifiedAt: Date()
        )

        #expect(!entitlements.isProActive)
        #expect(!entitlements.hasPremiumDecorationRental)
        #expect(entitlements.ownedPremiumDecorationProductIDs == [decorationID])
    }

    @Test
    func activeKnownProductsUseProductDisplayOrder() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [
                PurchaseProductID.supportTipMedium.rawValue,
                PurchaseProductID.proYearly.rawValue,
                PurchaseProductID.decorationMonthly.rawValue
            ],
            ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
            lastVerifiedAt: Date()
        )

        #expect(entitlements.activeKnownProducts == [
            .proYearly,
            .lifetime,
            .decorationMonthly,
            .supportTipMedium
        ])
    }

    @Test
    func restorableKnownProductsExcludeSupportTips() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [
                PurchaseProductID.supportTipMedium.rawValue,
                PurchaseProductID.proYearly.rawValue,
                PurchaseProductID.decorationYearly.rawValue
            ],
            ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
            lastVerifiedAt: Date()
        )

        #expect(entitlements.restorableKnownProducts == [
            .proYearly,
            .lifetime,
            .decorationYearly
        ])
    }

    @Test
    func onlySupportTipsAreNotRestorableProducts() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.supportTipSmall.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )

        #expect(entitlements.activeKnownProducts == [.supportTipSmall])
        #expect(entitlements.restorableKnownProducts.isEmpty)
    }
}
