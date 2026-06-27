#if DEBUG
import Foundation
import Testing
@testable import Liminalog

@MainActor
struct PurchaseStoreDebugTests {
    @Test
    func debugOverrideChangesEntitlementsWithoutStoreKitRefresh() {
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            initialEntitlements: PurchaseEntitlements()
        )

        store.applyDebugEntitlementsOverride(.pro)

        #expect(store.debugEntitlementsOverrideKind == .pro)
        #expect(store.entitlements.isProActive)
        #expect(store.entitlements.hasPremiumDecorationRental)
    }

    @Test
    func clearingDebugOverrideReturnsToCachedEntitlements() {
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            initialEntitlements: PurchaseEntitlements()
        )

        store.applyDebugEntitlementsOverride(.lifetime)
        store.applyDebugEntitlementsOverride(.system)

        #expect(store.debugEntitlementsOverrideKind == .system)
        #expect(!store.entitlements.isProActive)
        #expect(!store.entitlements.hasPremiumDecorationRental)
    }

    @Test
    func clearingDebugOverrideRestoresPreviousLiveEntitlements() {
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            initialEntitlements: PurchaseEntitlements(
                activeProductIDs: [PurchaseProductID.proYearly.rawValue],
                ownedNonConsumableProductIDs: [],
                lastVerifiedAt: Date()
            )
        )

        store.applyDebugEntitlementsOverride(.lifetime)
        store.applyDebugEntitlementsOverride(.decorationPassOnly)
        store.applyDebugEntitlementsOverride(.system)

        #expect(store.debugEntitlementsOverrideKind == .system)
        #expect(store.entitlements.activeProductIDs == [PurchaseProductID.proYearly.rawValue])
        #expect(store.entitlements.isProActive)
        #expect(store.entitlements.hasPremiumDecorationRental)
    }

    @Test
    func manageSubscriptionsWithoutWindowSceneShowsRecoverableMessage() async {
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            initialEntitlements: PurchaseEntitlements()
        )

        await store.manageSubscriptions(in: nil)

        #expect(!store.isManagingSubscriptions)
        #expect(store.userMessage == "サブスクリプション管理を開けませんでした。時間をおいてもう一度お試しください。")
    }
}
#endif
