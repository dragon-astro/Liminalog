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
