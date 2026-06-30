import Foundation

enum PurchaseOfferingSectionKind: String, Codable, CaseIterable, Identifiable {
    case pro
    case lifetime
    case decorationPass
    case support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pro:
            return "Liminalog Pro"
        case .lifetime:
            return "Pro機能 買い切り"
        case .decorationPass:
            return "装飾パス"
        case .support:
            return "支援"
        }
    }

    var footer: String {
        switch self {
        case .pro:
            return "Proは統計タブ、深い分析、プレミアム装飾を支えるためのプランです。"
        case .lifetime:
            return "機能を一度だけ応援する道です。プレミアム装飾の使い放題はサブスクリプション側に分けます。"
        case .decorationPass:
            return "Pro機能 買い切り所有者向けに、装飾だけを契約中使い放題にするプランです。"
        case .support:
            return "機能解放ではなく、Liminalogを続けていくための応援です。"
        }
    }
}

struct PurchaseOfferingProduct: Equatable, Codable, Identifiable {
    var id: PurchaseProductID
    var badge: String?
}

struct PurchaseOfferingSection: Equatable, Codable, Identifiable {
    var kind: PurchaseOfferingSectionKind
    var products: [PurchaseOfferingProduct]

    var id: PurchaseOfferingSectionKind { kind }
}

enum PurchaseProductAvailability: Equatable {
    case disabled
    case loading
    case available
    case unavailable

    static func current(
        canUseStoreKitRuntime: Bool = true,
        hasLoadedProducts: Bool,
        isLoadingProducts: Bool,
        hasAttemptedProductLoad: Bool
    ) -> PurchaseProductAvailability {
        guard canUseStoreKitRuntime else {
            return .disabled
        }
        if hasLoadedProducts {
            return .available
        }
        if isLoadingProducts || !hasAttemptedProductLoad {
            return .loading
        }
        return .unavailable
    }
}

struct PurchaseSupportSurfacePolicy: Equatable {
    var activationPolicy: PurchaseActivationPolicy

    var allowsStoreKitOperations: Bool {
        activationPolicy.shouldUseStoreKitRuntime
    }

    var showsStoreKitActionControls: Bool {
        allowsStoreKitOperations
    }

    func productAvailability(
        hasLoadedProducts: Bool,
        isLoadingProducts: Bool,
        hasAttemptedProductLoad: Bool
    ) -> PurchaseProductAvailability {
        PurchaseProductAvailability.current(
            canUseStoreKitRuntime: allowsStoreKitOperations,
            hasLoadedProducts: hasLoadedProducts,
            isLoadingProducts: isLoadingProducts,
            hasAttemptedProductLoad: hasAttemptedProductLoad
        )
    }
}

struct PurchaseOfferingCatalog: Equatable, Codable {
    func sections(for entitlements: PurchaseEntitlements) -> [PurchaseOfferingSection] {
        var sections: [PurchaseOfferingSection] = []

        if entitlements.hasLifetime {
            if !entitlements.hasPremiumDecorationRental {
                sections.append(decorationPassSection)
            }
        } else {
            if !entitlements.isProActive {
                sections.append(proSection)
            }
            sections.append(lifetimeSection)
        }

        sections.append(supportSection)
        return sections
    }

    func sections(
        for entitlements: PurchaseEntitlements,
        availableProductIDs: Set<String>
    ) -> [PurchaseOfferingSection] {
        sections(for: entitlements).compactMap { section in
            let availableProducts = section.products.filter { product in
                availableProductIDs.contains(product.id.rawValue)
            }
            guard !availableProducts.isEmpty else { return nil }
            return PurchaseOfferingSection(kind: section.kind, products: availableProducts)
        }
    }

    private var proSection: PurchaseOfferingSection {
        PurchaseOfferingSection(
            kind: .pro,
            products: [
                PurchaseOfferingProduct(id: .proYearly, badge: "おすすめ"),
                PurchaseOfferingProduct(id: .proMonthly, badge: nil)
            ]
        )
    }

    private var lifetimeSection: PurchaseOfferingSection {
        PurchaseOfferingSection(
            kind: .lifetime,
            products: [
                PurchaseOfferingProduct(id: .lifetime, badge: "機能を永久に")
            ]
        )
    }

    private var decorationPassSection: PurchaseOfferingSection {
        PurchaseOfferingSection(
            kind: .decorationPass,
            products: [
                PurchaseOfferingProduct(id: .decorationYearly, badge: nil),
                PurchaseOfferingProduct(id: .decorationMonthly, badge: nil)
            ]
        )
    }

    private var supportSection: PurchaseOfferingSection {
        PurchaseOfferingSection(
            kind: .support,
            products: [
                PurchaseOfferingProduct(id: .supportTipSmall, badge: nil),
                PurchaseOfferingProduct(id: .supportTipMedium, badge: nil),
                PurchaseOfferingProduct(id: .supportTipLarge, badge: nil)
            ]
        )
    }
}
