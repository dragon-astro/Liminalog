import Foundation
import OSLog
import StoreKit
import UIKit

#if DEBUG
struct PurchaseProductLoadDiagnostics: Equatable {
    struct LoadedProduct: Equatable, Identifiable {
        var id: String
        var productTypeDescription: String
    }

    var requestedProductIDs: [String]
    var loadedProducts: [LoadedProduct]
    var validProductIDs: [String]
    var errorDescription: String?
    var recordedAt: Date

    var missingRequestedProductIDs: [String] {
        let loadedIDs = Set(loadedProducts.map(\.id))
        return requestedProductIDs.filter { !loadedIDs.contains($0) }
    }

    var rejectedLoadedProducts: [LoadedProduct] {
        let validIDs = Set(validProductIDs)
        return loadedProducts.filter { !validIDs.contains($0.id) }
    }

    var evidenceLine: String {
        [
            "requestedCount=\(requestedProductIDs.count)",
            "loadedCount=\(loadedProducts.count)",
            "validCount=\(validProductIDs.count)",
            "missingCount=\(missingRequestedProductIDs.count)",
            "rejectedCount=\(rejectedLoadedProducts.count)"
        ]
        .joined(separator: " ")
    }
}

enum DebugPurchaseEntitlementsOverride: String, CaseIterable, Identifiable {
    case system
    case pro
    case lifetime
    case lifetimeWithDecorationPass
    case decorationPassOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "実際の状態"
        case .pro:
            return "Proサブ"
        case .lifetime:
            return "Pro機能 買い切り"
        case .lifetimeWithDecorationPass:
            return "Pro機能 買い切り＋装飾パス"
        case .decorationPassOnly:
            return "装飾パスのみ"
        }
    }

    var entitlements: PurchaseEntitlements? {
        let now = Date()
        switch self {
        case .system:
            return nil
        case .pro:
            return PurchaseEntitlements(
                activeProductIDs: [PurchaseProductID.proYearly.rawValue],
                ownedNonConsumableProductIDs: [],
                lastVerifiedAt: now
            )
        case .lifetime:
            return PurchaseEntitlements(
                activeProductIDs: [PurchaseProductID.lifetime.rawValue],
                ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
                lastVerifiedAt: now
            )
        case .lifetimeWithDecorationPass:
            return PurchaseEntitlements(
                activeProductIDs: [
                    PurchaseProductID.lifetime.rawValue,
                    PurchaseProductID.decorationYearly.rawValue
                ],
                ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
                lastVerifiedAt: now
            )
        case .decorationPassOnly:
            return PurchaseEntitlements(
                activeProductIDs: [PurchaseProductID.decorationMonthly.rawValue],
                ownedNonConsumableProductIDs: [],
                lastVerifiedAt: now
            )
        }
    }

    static func launchOverride(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DebugPurchaseEntitlementsOverride? {
        if let environmentValue = environment["LiminalogDebugPurchaseState"] {
            return DebugPurchaseEntitlementsOverride(rawValue: environmentValue)
        }

        guard
            let flagIndex = arguments.firstIndex(of: "-LiminalogDebugPurchaseState"),
            arguments.indices.contains(arguments.index(after: flagIndex))
        else {
            return nil
        }

        return DebugPurchaseEntitlementsOverride(rawValue: arguments[arguments.index(after: flagIndex)])
    }
}
#endif

@MainActor
@Observable
final class PurchaseStore {
    @ObservationIgnored private static let cacheKey = "purchase.entitlements.cache.v1"
    #if DEBUG
    @ObservationIgnored private static let debugLogger = Logger(
        subsystem: "app.YasudaRyuga.Liminalog",
        category: "Purchase"
    )
    #endif
    @ObservationIgnored private let productIDs: [String]
    @ObservationIgnored private let userDefaults: UserDefaults?
    @ObservationIgnored private let runtimePolicy: PurchaseStoreRuntimePolicy
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored private var debugEntitlementsOverride: PurchaseEntitlements?
    @ObservationIgnored private var entitlementsBeforeDebugOverride: PurchaseEntitlements?
    private(set) var debugEntitlementsOverrideKind: DebugPurchaseEntitlementsOverride = .system
    private(set) var debugProductLoadDiagnostics: PurchaseProductLoadDiagnostics?
    #endif

    private(set) var products: [Product] = []
    private(set) var entitlements: PurchaseEntitlements
    private(set) var isLoadingProducts = false
    private(set) var hasAttemptedProductLoad = false
    private(set) var isRefreshingEntitlements = false
    private(set) var isManagingSubscriptions = false
    private(set) var purchaseInProgressProductID: String?
    private(set) var hasStarted = false
    var userMessage: String?

    init(
        productIDs: [String],
        userDefaults: UserDefaults?,
        runtimePolicy: PurchaseStoreRuntimePolicy? = nil,
        initialEntitlements: PurchaseEntitlements? = nil
    ) {
        self.productIDs = productIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.userDefaults = userDefaults
        self.runtimePolicy = runtimePolicy ?? .current()
        self.entitlements = initialEntitlements ?? Self.cachedEntitlements(from: userDefaults)
    }

    static var preview: PurchaseStore {
        preview(entitlements: PurchaseEntitlements(lastVerifiedAt: Date()))
    }

    static func preview(entitlements: PurchaseEntitlements) -> PurchaseStore {
        let store = PurchaseStore(
            productIDs: PurchaseProductID.storeKitProductIDs,
            userDefaults: nil,
            initialEntitlements: entitlements
        )
        store.hasStarted = true
        return store
    }

    func start() async {
        guard canUseStoreKitRuntime() else { return }
        guard !hasStarted else { return }
        hasStarted = true
        startTransactionUpdatesIfNeeded()
        await refreshEntitlements()
    }

    func loadProductsIfNeeded() async {
        guard canUseStoreKitRuntime() else { return }
        guard products.isEmpty else { return }
        await loadProducts()
    }

    func loadProducts() async {
        guard canUseStoreKitRuntime(userVisibleAction: true) else { return }
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        hasAttemptedProductLoad = true
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await Product.products(for: productIDs)
            let validProducts = loadedProducts.filter { product in
                acceptsStoreKitProduct(productID: product.id, productType: product.type)
            }
            logProductLoadResult(loadedProducts: loadedProducts, validProducts: validProducts)
            products = validProducts.sorted {
                PurchaseProductID.sortIndex(for: $0.id) < PurchaseProductID.sortIndex(for: $1.id)
            }
            if !loadedProducts.isEmpty, validProducts.count != loadedProducts.count {
                userMessage = "一部の商品設定を確認できませんでした。App Store Connect または StoreKit 設定を確認してください。"
            }
            if products.isEmpty {
                userMessage = "商品情報を取得できませんでした。App Store Connect または StoreKit 設定を確認してください。"
            }
        } catch {
            userMessage = "商品情報を取得できませんでした。時間をおいてもう一度試してください。"
            logProductLoadError(error)
            NSLog("Liminalog: failed to load StoreKit products: \(String(describing: error))")
        }
    }

    func refreshEntitlements() async {
        guard canUseStoreKitRuntime() else { return }
        guard !isRefreshingEntitlements else { return }
        isRefreshingEntitlements = true
        defer { isRefreshingEntitlements = false }

        #if DEBUG
        if let debugEntitlementsOverride {
            entitlements = debugEntitlementsOverride
            return
        }
        #endif

        var activeProductIDs: Set<String> = []
        var ownedNonConsumableProductIDs: Set<String> = []
        let now = Date()

        for await result in Transaction.currentEntitlements {
            guard let transaction = verifiedTransaction(from: result),
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > now }) ?? true
            else { continue }
            guard acceptsStoreKitProduct(productID: transaction.productID, productType: transaction.productType) else { continue }

            activeProductIDs.insert(transaction.productID)
            if transaction.productType == .nonConsumable {
                ownedNonConsumableProductIDs.insert(transaction.productID)
            }
        }

        entitlements = PurchaseEntitlements(
            activeProductIDs: activeProductIDs,
            ownedNonConsumableProductIDs: ownedNonConsumableProductIDs,
            lastVerifiedAt: now
        )
        persistEntitlements()
    }

    func refreshEntitlementsIfStale(maxAge: TimeInterval) async {
        guard shouldRefreshEntitlements(maxAge: maxAge) else { return }
        await refreshEntitlements()
    }

    func shouldRefreshEntitlements(maxAge: TimeInterval, now: Date = Date()) -> Bool {
        guard canUseStoreKitRuntime() else { return false }

        #if DEBUG
        if debugEntitlementsOverride != nil {
            return false
        }
        #endif

        guard let lastVerifiedAt = entitlements.lastVerifiedAt else {
            return true
        }

        return now.timeIntervalSince(lastVerifiedAt) >= maxAge
    }

    func purchase(_ product: Product) async {
        guard canUseStoreKitRuntime(userVisibleAction: true) else { return }
        guard purchaseInProgressProductID == nil else { return }
        purchaseInProgressProductID = product.id
        userMessage = nil
        defer { purchaseInProgressProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = verifiedTransaction(from: verification) else {
                    userMessage = "購入を確認できませんでした。もう一度お試しください。"
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                userMessage = PurchaseProductID.purchaseSuccessMessage(for: transaction.productID)
            case .userCancelled:
                break
            case .pending:
                userMessage = "購入は保留中です。承認が完了すると自動で反映されます。"
            @unknown default:
                userMessage = "購入状態を確認しています。しばらくしてからもう一度開いてください。"
            }
        } catch {
            userMessage = "購入を完了できませんでした。時間をおいてもう一度試してください。"
            NSLog("Liminalog: StoreKit purchase failed: \(String(describing: error))")
        }
    }

    func restorePurchases() async {
        guard canUseStoreKitRuntime(userVisibleAction: true) else { return }
        userMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            userMessage = entitlements.restorableKnownProducts.isEmpty
                ? "復元できる購入は見つかりませんでした。"
                : "購入状態を復元しました。"
        } catch {
            userMessage = "購入状態を復元できませんでした。時間をおいてもう一度試してください。"
            NSLog("Liminalog: StoreKit restore failed: \(String(describing: error))")
        }
    }

    func manageSubscriptions(in scene: UIWindowScene?) async {
        guard canUseStoreKitRuntime(userVisibleAction: true) else { return }
        guard !isManagingSubscriptions else { return }
        guard let scene else {
            userMessage = "サブスクリプション管理を開けませんでした。時間をおいてもう一度お試しください。"
            return
        }

        isManagingSubscriptions = true
        userMessage = nil
        defer { isManagingSubscriptions = false }

        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            userMessage = "サブスクリプション管理を開けませんでした。時間をおいてもう一度お試しください。"
            NSLog("Liminalog: failed to show subscription management: \(String(describing: error))")
        }
    }

    func product(for id: PurchaseProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    #if DEBUG
    func applyDebugLaunchEntitlementsOverrideIfRequested() {
        guard let override = DebugPurchaseEntitlementsOverride.launchOverride(),
              override != .system
        else { return }

        applyDebugEntitlementsOverride(override)
    }

    func applyDebugEntitlementsOverride(_ override: DebugPurchaseEntitlementsOverride) {
        if override == .system {
            debugEntitlementsOverrideKind = .system
            debugEntitlementsOverride = nil
            entitlements = entitlementsBeforeDebugOverride ?? Self.cachedEntitlements(from: userDefaults)
            entitlementsBeforeDebugOverride = nil
            userMessage = "デバッグ用の課金状態を解除しました。"
            return
        }

        if debugEntitlementsOverride == nil {
            entitlementsBeforeDebugOverride = entitlements
        }
        debugEntitlementsOverrideKind = override
        debugEntitlementsOverride = override.entitlements
        entitlements = debugEntitlementsOverride ?? entitlements
        userMessage = "デバッグ用の課金状態を適用しました。"
    }
    #endif

    private func startTransactionUpdatesIfNeeded() {
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = self.verifiedTransaction(from: result) {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    private func canUseStoreKitRuntime(userVisibleAction: Bool = false) -> Bool {
        guard runtimePolicy.allowsStoreKitOperations else {
            if userVisibleAction {
                userMessage = "Proと応援は現在準備中です。今使える無料機能はそのまま利用できます。"
            }
            return false
        }
        return true
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(let transaction, let error):
            NSLog("Liminalog: unverified StoreKit transaction \(transaction.productID): \(String(describing: error))")
            return nil
        }
    }

    private func acceptsStoreKitProduct(productID: String, productType: Product.ProductType) -> Bool {
        guard let actualProductKind = productType.purchaseProductKind,
              PurchaseProductID.acceptsStoreKitProductKind(actualProductKind, for: productID)
        else {
            NSLog("Liminalog: StoreKit product \(productID) has an unsupported product ID or type: \(String(describing: productType))")
            return false
        }
        return true
    }

    private func logProductLoadResult(loadedProducts: [Product], validProducts: [Product]) {
        #if DEBUG
        let loadedDiagnosticProducts = loadedProducts.map {
            PurchaseProductLoadDiagnostics.LoadedProduct(
                id: $0.id,
                productTypeDescription: "\($0.type)"
            )
        }
        debugProductLoadDiagnostics = PurchaseProductLoadDiagnostics(
            requestedProductIDs: productIDs,
            loadedProducts: loadedDiagnosticProducts,
            validProductIDs: validProducts.map(\.id),
            errorDescription: nil,
            recordedAt: Date()
        )

        let requestedIDs = productIDs.joined(separator: ",")
        let loadedSummary = loadedProducts
            .map { "\($0.id):\($0.type)" }
            .joined(separator: ",")
        let validIDs = validProducts
            .map(\.id)
            .joined(separator: ",")
        print(
            "LiminalogPurchaseDebug productLoad",
            "requested=[\(requestedIDs)]",
            "loadedCount=\(loadedProducts.count)",
            "loaded=[\(loadedSummary)]",
            "validCount=\(validProducts.count)",
            "valid=[\(validIDs)]"
        )
        Self.debugLogger.info(
            "LiminalogPurchaseDebug productLoad requested=[\(requestedIDs, privacy: .public)] loadedCount=\(loadedProducts.count, privacy: .public) loaded=[\(loadedSummary, privacy: .public)] validCount=\(validProducts.count, privacy: .public) valid=[\(validIDs, privacy: .public)]"
        )
        #endif
    }

    private func logProductLoadError(_ error: Error) {
        #if DEBUG
        let errorDescription = String(describing: error)
        debugProductLoadDiagnostics = PurchaseProductLoadDiagnostics(
            requestedProductIDs: productIDs,
            loadedProducts: [],
            validProductIDs: [],
            errorDescription: errorDescription,
            recordedAt: Date()
        )
        print("LiminalogPurchaseDebug productLoadError \(errorDescription)")
        Self.debugLogger.error("LiminalogPurchaseDebug productLoadError \(errorDescription, privacy: .public)")
        #endif
    }

    private static func cachedEntitlements(from userDefaults: UserDefaults?) -> PurchaseEntitlements {
        guard
            let data = userDefaults?.data(forKey: cacheKey),
            let entitlements = try? JSONDecoder().decode(PurchaseEntitlements.self, from: data)
        else {
            return PurchaseEntitlements()
        }
        return entitlements
    }

    private func persistEntitlements() {
        guard let data = try? JSONEncoder().encode(entitlements) else { return }
        userDefaults?.set(data, forKey: Self.cacheKey)
    }
}

private extension Product.ProductType {
    var purchaseProductKind: PurchaseStoreKitProductKind? {
        if self == .consumable {
            return .consumable
        }
        if self == .nonConsumable {
            return .nonConsumable
        }
        if self == .autoRenewable {
            return .autoRenewableSubscription
        }
        return nil
    }
}
