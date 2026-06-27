import Foundation

enum PurchaseProductKind: String, Codable, CaseIterable {
    case proSubscription
    case lifetime
    case decorationSubscription
    case supportTip
    case premiumDecoration

    var displayLabel: String {
        switch self {
        case .proSubscription, .decorationSubscription:
            return "サブスクリプション"
        case .lifetime, .premiumDecoration:
            return "買い切り"
        case .supportTip:
            return "支援"
        }
    }
}

enum PurchaseStoreKitProductKind: String, Codable, CaseIterable {
    case consumable
    case nonConsumable
    case autoRenewableSubscription

    var appStoreConnectProductTypeName: String {
        switch self {
        case .consumable:
            "Consumable"
        case .nonConsumable:
            "Non-Consumable"
        case .autoRenewableSubscription:
            "Auto-Renewable Subscription"
        }
    }
}

enum PurchaseSubscriptionGroup: String, Codable, CaseIterable {
    case liminalogPro = "Liminalog Pro"
}

struct PurchaseAppStoreConnectProductSpec: Equatable, Codable, Identifiable {
    var id: String { productID }
    var productID: String
    var displayName: String
    var productKind: PurchaseProductKind
    var storeKitProductKind: PurchaseStoreKitProductKind
    var referencePriceText: String
    var subscriptionGroup: PurchaseSubscriptionGroup?
}

enum PurchaseProductID: String, Codable, CaseIterable, Identifiable {
    case proMonthly = "liminalog.pro.monthly"
    case proYearly = "liminalog.pro.yearly"
    case lifetime = "liminalog.lifetime"
    case decorationMonthly = "liminalog.decorations.monthly"
    case decorationYearly = "liminalog.decorations.yearly"
    case supportTipSmall = "liminalog.support.small"
    case supportTipMedium = "liminalog.support.medium"
    case supportTipLarge = "liminalog.support.large"

    var id: String { rawValue }

    static let primaryDisplayOrder: [PurchaseProductID] = [
        .proMonthly,
        .proYearly,
        .lifetime,
        .decorationMonthly,
        .decorationYearly,
        .supportTipSmall,
        .supportTipMedium,
        .supportTipLarge
    ]

    static let storeKitProductIDs: [String] = primaryDisplayOrder.map(\.rawValue)
    static let premiumDecorationProductPrefix = "liminalog.decoration."

    static let appStoreConnectSpecifications: [PurchaseAppStoreConnectProductSpec] = primaryDisplayOrder.map(\.appStoreConnectSpecification)

    static func kind(for rawProductID: String) -> PurchaseProductKind? {
        if let knownProduct = PurchaseProductID(rawValue: rawProductID) {
            return knownProduct.kind
        }
        if rawProductID.hasPrefix(premiumDecorationProductPrefix) {
            return .premiumDecoration
        }
        return nil
    }

    static func expectedStoreKitProductKind(for rawProductID: String) -> PurchaseStoreKitProductKind? {
        guard let kind = kind(for: rawProductID) else { return nil }
        return kind.expectedStoreKitProductKind
    }

    static func acceptsStoreKitProductKind(_ actualKind: PurchaseStoreKitProductKind, for rawProductID: String) -> Bool {
        expectedStoreKitProductKind(for: rawProductID) == actualKind
    }

    var kind: PurchaseProductKind {
        switch self {
        case .proMonthly, .proYearly:
            .proSubscription
        case .lifetime:
            .lifetime
        case .decorationMonthly, .decorationYearly:
            .decorationSubscription
        case .supportTipSmall, .supportTipMedium, .supportTipLarge:
            .supportTip
        }
    }

    var appStoreConnectSpecification: PurchaseAppStoreConnectProductSpec {
        PurchaseAppStoreConnectProductSpec(
            productID: rawValue,
            displayName: displayName,
            productKind: kind,
            storeKitProductKind: kind.expectedStoreKitProductKind,
            referencePriceText: referencePriceText,
            subscriptionGroup: kind.usesSubscriptionGroup ? .liminalogPro : nil
        )
    }

    var displayName: String {
        switch self {
        case .proMonthly:
            "Liminalog Pro 月額"
        case .proYearly:
            "Liminalog Pro 年額"
        case .lifetime:
            "ライフタイム"
        case .decorationMonthly:
            "装飾パス 月額"
        case .decorationYearly:
            "装飾パス 年額"
        case .supportTipSmall:
            "小さく応援"
        case .supportTipMedium:
            "しっかり応援"
        case .supportTipLarge:
            "大きく応援"
        }
    }

    var shortDescription: String {
        switch self {
        case .proMonthly:
            "深い統計とプレミアム装飾を、月ごとに。"
        case .proYearly:
            "Proを長く使う人向け。年ごとに更新します。"
        case .lifetime:
            "機能を一度だけ応援して、ずっと使う道。"
        case .decorationMonthly:
            "ライフタイム所有者向けの装飾使い放題。"
        case .decorationYearly:
            "装飾使い放題を年単位で。"
        case .supportTipSmall:
            "Liminalogを少し支える。"
        case .supportTipMedium:
            "これからの開発を支える。"
        case .supportTipLarge:
            "大きめに応援する。"
        }
    }

    var referencePriceText: String {
        switch self {
        case .proMonthly:
            "¥400"
        case .proYearly:
            "¥2,900"
        case .lifetime:
            "¥6,800"
        case .decorationMonthly:
            "¥200"
        case .decorationYearly:
            "¥1,500"
        case .supportTipSmall:
            "¥250"
        case .supportTipMedium:
            "¥600"
        case .supportTipLarge:
            "¥1,200"
        }
    }

    var grantsProAccess: Bool {
        switch self {
        case .proMonthly, .proYearly, .lifetime:
            true
        case .decorationMonthly, .decorationYearly, .supportTipSmall, .supportTipMedium, .supportTipLarge:
            false
        }
    }

    var grantsDecorationRental: Bool {
        switch self {
        case .proMonthly, .proYearly, .decorationMonthly, .decorationYearly:
            true
        case .lifetime, .supportTipSmall, .supportTipMedium, .supportTipLarge:
            false
        }
    }

    var purchaseSuccessMessage: String {
        switch kind {
        case .supportTip:
            "応援ありがとうございます。Liminalogの開発に使わせてもらいます。"
        case .proSubscription, .lifetime, .decorationSubscription, .premiumDecoration:
            "応援ありがとうございます。購入状態を更新しました。"
        }
    }

    static func purchaseSuccessMessage(for rawProductID: String) -> String {
        if let knownProduct = PurchaseProductID(rawValue: rawProductID) {
            return knownProduct.purchaseSuccessMessage
        }
        if kind(for: rawProductID) == .premiumDecoration {
            return "応援ありがとうございます。購入状態を更新しました。"
        }
        return "応援ありがとうございます。購入状態を確認しました。"
    }

    static func sortIndex(for rawProductID: String) -> Int {
        primaryDisplayOrder.firstIndex { $0.rawValue == rawProductID } ?? Int.max
    }
}

private extension PurchaseProductKind {
    var expectedStoreKitProductKind: PurchaseStoreKitProductKind {
        switch self {
        case .proSubscription, .decorationSubscription:
            return .autoRenewableSubscription
        case .lifetime, .premiumDecoration:
            return .nonConsumable
        case .supportTip:
            return .consumable
        }
    }

    var usesSubscriptionGroup: Bool {
        switch self {
        case .proSubscription, .decorationSubscription:
            return true
        case .lifetime, .premiumDecoration, .supportTip:
            return false
        }
    }
}

struct PurchaseEntitlements: Equatable, Codable {
    var activeProductIDs: Set<String> = []
    var ownedNonConsumableProductIDs: Set<String> = []
    var lastVerifiedAt: Date?

    var isProActive: Bool {
        hasLifetime || activeProductIDs.contains(PurchaseProductID.proMonthly.rawValue) || activeProductIDs.contains(PurchaseProductID.proYearly.rawValue)
    }

    var hasLifetime: Bool {
        ownedNonConsumableProductIDs.contains(PurchaseProductID.lifetime.rawValue)
    }

    var hasPremiumDecorationRental: Bool {
        activeProductIDs.contains(PurchaseProductID.proMonthly.rawValue)
            || activeProductIDs.contains(PurchaseProductID.proYearly.rawValue)
            || activeProductIDs.contains(PurchaseProductID.decorationMonthly.rawValue)
            || activeProductIDs.contains(PurchaseProductID.decorationYearly.rawValue)
    }

    var ownedPremiumDecorationProductIDs: Set<String> {
        ownedNonConsumableProductIDs.filter { rawID in
            PurchaseProductID.kind(for: rawID) == .premiumDecoration
        }
    }

    var activeKnownProducts: [PurchaseProductID] {
        PurchaseProductID.primaryDisplayOrder.filter { activeProductIDs.contains($0.rawValue) || ownedNonConsumableProductIDs.contains($0.rawValue) }
    }

    var restorableKnownProducts: [PurchaseProductID] {
        activeKnownProducts.filter { productID in
            productID.kind != .supportTip
        }
    }
}
