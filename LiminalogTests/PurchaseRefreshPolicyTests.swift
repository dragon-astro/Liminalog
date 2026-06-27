import Foundation
import Testing
@testable import Liminalog

@MainActor
struct PurchaseRefreshPolicyTests {
    @Test
    func entitlementsWithoutVerificationAreStale() {
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            initialEntitlements: PurchaseEntitlements()
        )

        #expect(store.shouldRefreshEntitlements(maxAge: 3600))
    }

    @Test
    func recentlyVerifiedEntitlementsAreNotStale() {
        let now = Date()
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            initialEntitlements: PurchaseEntitlements(lastVerifiedAt: now.addingTimeInterval(-60))
        )

        #expect(!store.shouldRefreshEntitlements(maxAge: 3600, now: now))
    }

    @Test
    func oldVerifiedEntitlementsAreStale() {
        let now = Date()
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            initialEntitlements: PurchaseEntitlements(lastVerifiedAt: now.addingTimeInterval(-7200))
        )

        #expect(store.shouldRefreshEntitlements(maxAge: 3600, now: now))
    }

    @Test
    func disabledStoreKitRuntimePreventsDirectStoreOperations() async {
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            runtimePolicy: PurchaseStoreRuntimePolicy(
                activationPolicy: PurchaseActivationPolicy(
                    configuration: .current,
                    buildMode: .release
                )
            ),
            initialEntitlements: PurchaseEntitlements()
        )

        await store.start()
        await store.loadProducts()
        await store.refreshEntitlements()
        await store.restorePurchases()

        #expect(!store.hasStarted)
        #expect(!store.hasAttemptedProductLoad)
        #expect(!store.isRefreshingEntitlements)
        #expect(!store.shouldRefreshEntitlements(maxAge: 0))
        #expect(store.entitlements == PurchaseEntitlements())
        #expect(store.userMessage == "Proと応援は現在準備中です。今使える無料機能はそのまま利用できます。")
    }

    #if DEBUG
    @Test
    func debugOverrideDoesNotRequestStoreKitRefresh() {
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            initialEntitlements: PurchaseEntitlements()
        )

        store.applyDebugEntitlementsOverride(.pro)

        #expect(!store.shouldRefreshEntitlements(maxAge: 0))
    }
    #endif
}
