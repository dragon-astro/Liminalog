import Foundation

struct PremiumDecorationProduct: Equatable, Codable, Identifiable {
    var productID: String
    var kind: UnlockKind
    var targetID: String
    var displayName: String

    var id: String { productID }

    var isSupportedPremiumDecorationProduct: Bool {
        PurchaseProductID.kind(for: productID) == .premiumDecoration
    }
}

enum PremiumDecorationAccessState: String, Codable, Equatable {
    case unavailable
    case rented
    case owned

    var canEquip: Bool {
        self != .unavailable
    }

    var isPermanent: Bool {
        self == .owned
    }
}

struct PremiumDecorationAccessDecision: Equatable, Codable {
    var product: PremiumDecorationProduct
    var state: PremiumDecorationAccessState

    var canEquip: Bool {
        state.canEquip
    }
}

struct PremiumDecorationAccessPolicy: Equatable {
    func decision(
        for product: PremiumDecorationProduct,
        entitlements: PurchaseEntitlements
    ) -> PremiumDecorationAccessDecision {
        PremiumDecorationAccessDecision(
            product: product,
            state: state(for: product, entitlements: entitlements)
        )
    }

    func state(
        for product: PremiumDecorationProduct,
        entitlements: PurchaseEntitlements
    ) -> PremiumDecorationAccessState {
        guard product.isSupportedPremiumDecorationProduct else {
            return .unavailable
        }
        if entitlements.ownedPremiumDecorationProductIDs.contains(product.productID) {
            return .owned
        }
        if entitlements.hasPremiumDecorationRental {
            return .rented
        }
        return .unavailable
    }
}
