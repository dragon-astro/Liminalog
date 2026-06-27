import Foundation

struct PremiumDecorationCatalogItem: Equatable, Codable, Identifiable {
    var productID: String
    var kind: UnlockKind
    var targetID: String
    var displayName: String
    var assetName: String?
    var sortOrder: Int

    var id: String { productID }

    var product: PremiumDecorationProduct {
        PremiumDecorationProduct(
            productID: productID,
            kind: kind,
            targetID: targetID,
            displayName: displayName
        )
    }
}

enum DecorationAccessDisplayState: String, Codable, Equatable {
    case earned
    case locked
    case premiumUnavailable
    case premiumRented
    case premiumOwned

    var canEquip: Bool {
        switch self {
        case .earned, .premiumRented, .premiumOwned:
            return true
        case .locked, .premiumUnavailable:
            return false
        }
    }

    var isPremium: Bool {
        switch self {
        case .premiumUnavailable, .premiumRented, .premiumOwned:
            return true
        case .earned, .locked:
            return false
        }
    }
}

struct DecorationAccessDisplayItem: Equatable, Codable, Identifiable {
    var kind: UnlockKind
    var targetID: String
    var displayName: String
    var sortOrder: Int
    var state: DecorationAccessDisplayState
    var productID: String?

    var id: String {
        "\(kind.rawValue):\(targetID)"
    }

    var canEquip: Bool {
        state.canEquip
    }
}

enum PremiumDecorationCatalog {
    static let items: [PremiumDecorationCatalogItem] = [
        .iconFrame(
            productID: "liminalog.decoration.frame.aurora_wreath",
            targetID: "aurora_wreath",
            displayName: "極光環フレーム",
            sortOrder: 100
        ),
        .iconFrame(
            productID: "liminalog.decoration.frame.kintsugi_ring",
            targetID: "kintsugi_ring",
            displayName: "金継ぎフレーム",
            sortOrder: 110
        ),
        .iconFrame(
            productID: "liminalog.decoration.frame.porcelain_halo",
            targetID: "porcelain_halo",
            displayName: "白磁フレーム",
            sortOrder: 120
        ),
        .iconFrame(
            productID: "liminalog.decoration.frame.tideglass_ring",
            targetID: "tideglass_ring",
            displayName: "潮硝子フレーム",
            sortOrder: 130
        ),
        .cardStyle(
            productID: "liminalog.decoration.card.aurora_panel",
            targetID: "aurora_panel",
            displayName: "極光幕カード",
            sortOrder: 200
        ),
        .cardStyle(
            productID: "liminalog.decoration.card.kintsugi_panel",
            targetID: "kintsugi_panel",
            displayName: "金継ぎカード",
            sortOrder: 210
        ),
        .cardStyle(
            productID: "liminalog.decoration.card.porcelain_panel",
            targetID: "porcelain_panel",
            displayName: "白磁カード",
            sortOrder: 220
        ),
        .cardStyle(
            productID: "liminalog.decoration.card.tide_panel",
            targetID: "tide_panel",
            displayName: "潮目カード",
            sortOrder: 230
        )
    ]

    static var products: [PremiumDecorationProduct] {
        items.map(\.product)
    }

    static var productIDs: [String] {
        items.map(\.productID)
    }

    static func item(forProductID productID: String) -> PremiumDecorationCatalogItem? {
        items.first { $0.productID == productID }
    }

    static func item(forTargetID targetID: String, kind: UnlockKind) -> PremiumDecorationCatalogItem? {
        items.first { $0.targetID == targetID && $0.kind == kind }
    }

    static func items(kind: UnlockKind) -> [PremiumDecorationCatalogItem] {
        items
            .filter { $0.kind == kind }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.productID < $1.productID
                }
                return $0.sortOrder < $1.sortOrder
            }
    }
}

struct PremiumDecorationEquippingPolicy: Equatable {
    var catalogItems: [PremiumDecorationCatalogItem] = PremiumDecorationCatalog.items
    var accessPolicy = PremiumDecorationAccessPolicy()

    func resolvedTargetID(
        requestedTargetID: String?,
        kind: UnlockKind,
        earnedTargetIDs: Set<String>,
        entitlements: PurchaseEntitlements,
        fallbackTargetID: String
    ) -> String {
        guard let requestedTargetID, !requestedTargetID.isEmpty else {
            return fallbackTargetID
        }
        if earnedTargetIDs.contains(requestedTargetID) {
            return requestedTargetID
        }
        guard let premiumItem = catalogItem(forTargetID: requestedTargetID, kind: kind) else {
            return fallbackTargetID
        }
        let decision = accessPolicy.decision(
            for: premiumItem.product,
            entitlements: entitlements
        )
        return decision.canEquip ? requestedTargetID : fallbackTargetID
    }

    private func catalogItem(forTargetID targetID: String, kind: UnlockKind) -> PremiumDecorationCatalogItem? {
        catalogItems.first { $0.targetID == targetID && $0.kind == kind }
    }
}

struct DecorationAccessDisplayPolicy: Equatable {
    var premiumCatalogItems: [PremiumDecorationCatalogItem] = PremiumDecorationCatalog.items
    var accessPolicy = PremiumDecorationAccessPolicy()

    func displayItems(
        kind: UnlockKind,
        earnedCatalogItems: [UnlockCatalogItem],
        unlockedEarnedTargetIDs: Set<String>,
        entitlements: PurchaseEntitlements
    ) -> [DecorationAccessDisplayItem] {
        let earnedItems = earnedCatalogItems
            .filter { $0.kind == kind }
            .map { item in
                DecorationAccessDisplayItem(
                    kind: item.kind,
                    targetID: item.targetID,
                    displayName: item.displayName,
                    sortOrder: item.sortOrder,
                    state: unlockedEarnedTargetIDs.contains(item.targetID) ? .earned : .locked,
                    productID: nil
                )
            }

        let premiumItems = premiumCatalogItems
            .filter { $0.kind == kind }
            .map { item in
                DecorationAccessDisplayItem(
                    kind: item.kind,
                    targetID: item.targetID,
                    displayName: item.displayName,
                    sortOrder: item.sortOrder,
                    state: displayState(for: item, entitlements: entitlements),
                    productID: item.productID
                )
            }

        return (earnedItems + premiumItems).sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.id < $1.id
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private func displayState(
        for item: PremiumDecorationCatalogItem,
        entitlements: PurchaseEntitlements
    ) -> DecorationAccessDisplayState {
        switch accessPolicy.state(for: item.product, entitlements: entitlements) {
        case .unavailable:
            return .premiumUnavailable
        case .rented:
            return .premiumRented
        case .owned:
            return .premiumOwned
        }
    }
}

private extension PremiumDecorationCatalogItem {
    static func iconFrame(
        productID: String,
        targetID: String,
        displayName: String,
        sortOrder: Int
    ) -> PremiumDecorationCatalogItem {
        PremiumDecorationCatalogItem(
            productID: productID,
            kind: .iconFrame,
            targetID: targetID,
            displayName: displayName,
            assetName: "profile_frame_\(targetID)",
            sortOrder: sortOrder
        )
    }

    static func cardStyle(
        productID: String,
        targetID: String,
        displayName: String,
        sortOrder: Int
    ) -> PremiumDecorationCatalogItem {
        PremiumDecorationCatalogItem(
            productID: productID,
            kind: .cardStyle,
            targetID: targetID,
            displayName: displayName,
            assetName: "profile_card_\(targetID)",
            sortOrder: sortOrder
        )
    }
}
