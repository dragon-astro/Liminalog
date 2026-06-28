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
    func storeKitProductKindsExposeAppStoreConnectTypeNames() {
        #expect(PurchaseStoreKitProductKind.autoRenewableSubscription.appStoreConnectProductTypeName == "Auto-Renewable Subscription")
        #expect(PurchaseStoreKitProductKind.nonConsumable.appStoreConnectProductTypeName == "Non-Consumable")
        #expect(PurchaseStoreKitProductKind.consumable.appStoreConnectProductTypeName == "Consumable")
    }

    @Test
    func appStoreConnectSpecificationsCoverAllPrimaryProductsInDisplayOrder() {
        let specs = PurchaseProductID.appStoreConnectSpecifications

        #expect(specs.map(\.productID) == PurchaseProductID.primaryDisplayOrder.map(\.rawValue))
        #expect(Set(specs.map(\.productID)).count == specs.count)
        #expect(specs.map(\.displayName) == PurchaseProductID.primaryDisplayOrder.map(\.displayName))
        #expect(specs.map(\.referencePriceText) == PurchaseProductID.primaryDisplayOrder.map(\.referencePriceText))
    }

    @Test
    func appStoreConnectSpecificationsMatchPlannedProductTypesAndGroups() {
        let specsByID = Dictionary(uniqueKeysWithValues: PurchaseProductID.appStoreConnectSpecifications.map { ($0.productID, $0) })

        #expect(specsByID[PurchaseProductID.proMonthly.rawValue]?.storeKitProductKind == .autoRenewableSubscription)
        #expect(specsByID[PurchaseProductID.proYearly.rawValue]?.storeKitProductKind == .autoRenewableSubscription)
        #expect(specsByID[PurchaseProductID.decorationMonthly.rawValue]?.storeKitProductKind == .autoRenewableSubscription)
        #expect(specsByID[PurchaseProductID.decorationYearly.rawValue]?.storeKitProductKind == .autoRenewableSubscription)
        #expect(specsByID[PurchaseProductID.lifetime.rawValue]?.storeKitProductKind == .nonConsumable)
        #expect(specsByID[PurchaseProductID.supportTipSmall.rawValue]?.storeKitProductKind == .consumable)
        #expect(specsByID[PurchaseProductID.supportTipMedium.rawValue]?.storeKitProductKind == .consumable)
        #expect(specsByID[PurchaseProductID.supportTipLarge.rawValue]?.storeKitProductKind == .consumable)

        #expect(specsByID[PurchaseProductID.proMonthly.rawValue]?.subscriptionGroup == .liminalogPro)
        #expect(specsByID[PurchaseProductID.proYearly.rawValue]?.subscriptionGroup == .liminalogPro)
        #expect(specsByID[PurchaseProductID.decorationMonthly.rawValue]?.subscriptionGroup == .liminalogPro)
        #expect(specsByID[PurchaseProductID.decorationYearly.rawValue]?.subscriptionGroup == .liminalogPro)
        #expect(specsByID[PurchaseProductID.lifetime.rawValue]?.subscriptionGroup == nil)
        #expect(specsByID[PurchaseProductID.supportTipSmall.rawValue]?.subscriptionGroup == nil)
        #expect(specsByID[PurchaseProductID.supportTipMedium.rawValue]?.subscriptionGroup == nil)
        #expect(specsByID[PurchaseProductID.supportTipLarge.rawValue]?.subscriptionGroup == nil)
    }

    @Test
    func productDescriptionsReflectConfirmedYearlyIntroductoryOfferOnly() {
        let descriptionsByID = Dictionary(uniqueKeysWithValues: PurchaseProductID.allCases.map { ($0, $0.shortDescription) })

        #expect(descriptionsByID[.proYearly]?.contains("初回1週間無料") == true)
        #expect(descriptionsByID[.proMonthly]?.contains("無料") == false)
        #expect(descriptionsByID[.decorationMonthly]?.contains("無料") == false)
        #expect(descriptionsByID[.decorationYearly]?.contains("無料") == false)
        #expect(!descriptionsByID.values.contains { $0.contains("想定") })
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
