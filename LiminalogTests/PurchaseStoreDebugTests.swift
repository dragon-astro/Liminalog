#if DEBUG
import Foundation
import Testing
@testable import Liminalog

@MainActor
struct PurchaseStoreDebugTests {
    @Test
    func debugLaunchOverrideReadsEnvironmentValue() {
        let override = DebugPurchaseEntitlementsOverride.launchOverride(
            arguments: ["Liminalog"],
            environment: ["LiminalogDebugPurchaseState": "lifetime"]
        )

        #expect(override == .lifetime)
    }

    @Test
    func debugLaunchOverrideReadsLaunchArgumentValue() {
        let override = DebugPurchaseEntitlementsOverride.launchOverride(
            arguments: ["Liminalog", "-LiminalogDebugPurchaseState", "decorationPassOnly"],
            environment: [:]
        )

        #expect(override == .decorationPassOnly)
    }

    @Test
    func debugLaunchOverrideIgnoresMissingOrUnknownValues() {
        #expect(DebugPurchaseEntitlementsOverride.launchOverride(arguments: ["Liminalog"], environment: [:]) == nil)
        #expect(DebugPurchaseEntitlementsOverride.launchOverride(
            arguments: ["Liminalog", "-LiminalogDebugPurchaseState", "unknown"],
            environment: [:]
        ) == nil)
    }

    @Test
    func debugStoreKitProductDisplayOverrideReadsEnvironmentValue() {
        let override = DebugStoreKitProductDisplayOverride.launchOverride(
            arguments: ["Liminalog"],
            environment: ["LiminalogDebugStoreKitProducts": "loaded"]
        )

        #expect(override == .loaded)
    }

    @Test
    func debugStoreKitProductDisplayOverrideReadsLaunchArgumentValue() {
        let override = DebugStoreKitProductDisplayOverride.launchOverride(
            arguments: ["Liminalog", "-LiminalogDebugStoreKitProducts", "loaded"],
            environment: [:]
        )

        #expect(override == .loaded)
    }

    @Test
    func debugStoreKitProductDisplayOverrideIgnoresMissingOrUnknownValues() {
        #expect(DebugStoreKitProductDisplayOverride.launchOverride(arguments: ["Liminalog"], environment: [:]) == nil)
        #expect(DebugStoreKitProductDisplayOverride.launchOverride(
            arguments: ["Liminalog", "-LiminalogDebugStoreKitProducts", "unknown"],
            environment: [:]
        ) == nil)
    }

    @Test
    func productLoadDiagnosticsReportsMissingAndRejectedProducts() {
        let diagnostics = PurchaseProductLoadDiagnostics(
            requestedProductIDs: [
                PurchaseProductID.proMonthly.rawValue,
                PurchaseProductID.proYearly.rawValue,
                PurchaseProductID.lifetime.rawValue
            ],
            loadedProducts: [
                PurchaseProductLoadDiagnostics.LoadedProduct(
                    id: PurchaseProductID.proMonthly.rawValue,
                    productTypeDescription: "autoRenewable"
                ),
                PurchaseProductLoadDiagnostics.LoadedProduct(
                    id: PurchaseProductID.lifetime.rawValue,
                    productTypeDescription: "consumable"
                )
            ],
            validProductIDs: [PurchaseProductID.proMonthly.rawValue],
            errorDescription: nil,
            recordedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(diagnostics.missingRequestedProductIDs == [PurchaseProductID.proYearly.rawValue])
        #expect(diagnostics.rejectedLoadedProducts == [
            PurchaseProductLoadDiagnostics.LoadedProduct(
                id: PurchaseProductID.lifetime.rawValue,
                productTypeDescription: "consumable"
            )
        ])
        #expect(diagnostics.evidenceLine == "requestedCount=3 loadedCount=2 validCount=1 missingCount=1 rejectedCount=1")
    }

    @Test
    func productLoadDiagnosticsKeepsStoreKitErrorContext() {
        let diagnostics = PurchaseProductLoadDiagnostics(
            requestedProductIDs: PurchaseProductID.storeKitProductIDs,
            loadedProducts: [],
            validProductIDs: [],
            errorDescription: "StoreKit failed",
            recordedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(diagnostics.missingRequestedProductIDs == PurchaseProductID.storeKitProductIDs)
        #expect(diagnostics.rejectedLoadedProducts.isEmpty)
        #expect(diagnostics.errorDescription == "StoreKit failed")
        #expect(diagnostics.evidenceLine == "requestedCount=8 loadedCount=0 validCount=0 missingCount=8 rejectedCount=0")
    }

    @Test
    func productLoadDiagnosticsEvidenceLineMatchesLocalQATemplate() {
        let diagnostics = PurchaseProductLoadDiagnostics(
            requestedProductIDs: PurchaseProductID.storeKitProductIDs,
            loadedProducts: PurchaseProductID.storeKitProductIDs.map {
                PurchaseProductLoadDiagnostics.LoadedProduct(
                    id: $0,
                    productTypeDescription: "matching"
                )
            },
            validProductIDs: PurchaseProductID.storeKitProductIDs,
            errorDescription: nil,
            recordedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(diagnostics.evidenceLine == "requestedCount=8 loadedCount=8 validCount=8 missingCount=0 rejectedCount=0")
    }

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
    func debugStoreKitProductDisplayOverrideShowsReferenceProductsWithoutStoreKitDiagnostics() {
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            initialEntitlements: PurchaseEntitlements()
        )

        let didApply = store.applyDebugStoreKitProductDisplayOverrideIfRequested(
            arguments: ["Liminalog", "-LiminalogDebugStoreKitProducts", "loaded"],
            environment: [:]
        )

        #expect(didApply)
        #expect(store.hasAttemptedProductLoad)
        #expect(store.products.isEmpty)
        #expect(store.debugProductLoadDiagnostics == nil)
        #expect(store.displayProducts.map(\.id) == PurchaseProductID.storeKitProductIDs)
        #expect(store.displayProducts.allSatisfy { !$0.isStoreKitBacked })
        #expect(store.displayProduct(for: .proYearly)?.displayPrice == PurchaseProductID.proYearly.referencePriceText)
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
