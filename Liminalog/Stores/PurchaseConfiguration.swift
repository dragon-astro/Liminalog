import Foundation

struct PurchaseLegalLinks: Equatable, Codable {
    var termsOfUseURL: URL?
    var privacyPolicyURL: URL?
}

enum PurchasePaidReleaseRequirement: String, Codable, CaseIterable, Identifiable, Equatable {
    case storeKitProductID
    case duplicateProductID
    case unsupportedProductID
    case confirmedAppStoreConnectProductIDs
    case subscriptionGroupName
    case termsOfUseURL
    case httpsTermsOfUseURL
    case privacyPolicyURL
    case httpsPrivacyPolicyURL

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .storeKitProductID:
            "StoreKitの商品ID"
        case .duplicateProductID:
            "商品IDの重複"
        case .unsupportedProductID:
            "未対応の商品ID"
        case .confirmedAppStoreConnectProductIDs:
            "本番Product ID確認"
        case .subscriptionGroupName:
            "サブスクリプショングループ名"
        case .termsOfUseURL:
            "利用規約URL"
        case .httpsTermsOfUseURL:
            "利用規約URL（HTTPS）"
        case .privacyPolicyURL:
            "プライバシーポリシーURL"
        case .httpsPrivacyPolicyURL:
            "プライバシーポリシーURL（HTTPS）"
        }
    }

    var resolutionHint: String {
        switch self {
        case .storeKitProductID:
            "App Store Connect または StoreKit Configuration に作る商品IDを設定する。"
        case .duplicateProductID:
            "同じ商品IDが重複していないか確認する。"
        case .unsupportedProductID:
            "アプリ側で扱える購入種別に紐づく商品IDへ直す。"
        case .confirmedAppStoreConnectProductIDs:
            "本番の商品IDと商品種別を App Store Connect で確認してから有効化する。"
        case .subscriptionGroupName:
            "App Store Connect のサブスクリプショングループ名を設定する。"
        case .termsOfUseURL:
            "課金導入前に利用規約ページを公開し、HTTPS URL を設定する。"
        case .httpsTermsOfUseURL:
            "利用規約URLを https:// で始まる公開URLへ変更する。"
        case .privacyPolicyURL:
            "プライバシーポリシーの HTTPS URL を設定する。"
        case .httpsPrivacyPolicyURL:
            "プライバシーポリシーURLを https:// で始まる公開URLへ変更する。"
        }
    }
}

enum PurchaseReleaseReadinessState: String, Codable, CaseIterable, Identifiable, Equatable {
    case missingRequiredMetadata
    case metadataReadyWaitingForGoLive
    case purchaseEntryPointReady
    case featureRestrictionsReady

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .missingRequiredMetadata:
            "未設定あり"
        case .metadataReadyWaitingForGoLive:
            "本番メタデータ準備済み"
        case .purchaseEntryPointReady:
            "購入導線ON"
        case .featureRestrictionsReady:
            "機能制限ON"
        }
    }
}

struct PurchaseReleaseReadinessSnapshot: Equatable, Codable {
    var missingRequirements: [PurchasePaidReleaseRequirement]
    var purchaseEntryPointIsEnabled: Bool
    var featureRestrictionsAreEnabled: Bool
    var backgroundEntitlementRefreshIsEnabled: Bool

    var hasRequiredMetadata: Bool {
        missingRequirements.isEmpty
    }

    var state: PurchaseReleaseReadinessState {
        guard hasRequiredMetadata else {
            return .missingRequiredMetadata
        }
        guard canExposePurchaseEntryPoint else {
            return .metadataReadyWaitingForGoLive
        }
        if shouldEnforceFeatureRestrictions {
            return .featureRestrictionsReady
        }
        return .purchaseEntryPointReady
    }

    var canExposePurchaseEntryPoint: Bool {
        hasRequiredMetadata && purchaseEntryPointIsEnabled
    }

    var shouldEnforceFeatureRestrictions: Bool {
        canExposePurchaseEntryPoint && featureRestrictionsAreEnabled
    }

    var shouldRefreshEntitlementsInBackground: Bool {
        canExposePurchaseEntryPoint
            && (backgroundEntitlementRefreshIsEnabled || shouldEnforceFeatureRestrictions)
    }
}

struct PurchaseConfiguration: Equatable, Codable {
    var productIDs: [String]
    var productIDsAreConfirmedForAppStoreConnect: Bool
    var subscriptionGroupName: String?
    var legalLinks: PurchaseLegalLinks
    var purchaseEntryPointIsEnabled = false
    var featureRestrictionsAreEnabled = false
    var backgroundEntitlementRefreshIsEnabled = false

    static let current = PurchaseConfiguration(
        productIDs: PurchaseProductID.storeKitProductIDs,
        productIDsAreConfirmedForAppStoreConnect: false,
        subscriptionGroupName: nil,
        legalLinks: PurchaseLegalLinks(
            termsOfUseURL: nil,
            privacyPolicyURL: URL(string: "https://liminalog.vercel.app/privacy")
        ),
        purchaseEntryPointIsEnabled: false,
        featureRestrictionsAreEnabled: false,
        backgroundEntitlementRefreshIsEnabled: false
    )

    var storeKitProductIDs: [String] {
        productIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var missingPaidReleaseRequirementItems: [PurchasePaidReleaseRequirement] {
        var missing: [PurchasePaidReleaseRequirement] = []
        let normalizedProductIDs = productIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if normalizedProductIDs.isEmpty || normalizedProductIDs.contains(where: \.isEmpty) {
            missing.append(.storeKitProductID)
        }
        if Set(normalizedProductIDs).count != normalizedProductIDs.count {
            missing.append(.duplicateProductID)
        }
        let nonEmptyProductIDs = normalizedProductIDs.filter { !$0.isEmpty }
        if nonEmptyProductIDs.contains(where: { PurchaseProductID.expectedStoreKitProductKind(for: $0) == nil }) {
            missing.append(.unsupportedProductID)
        }
        if !productIDsAreConfirmedForAppStoreConnect {
            missing.append(.confirmedAppStoreConnectProductIDs)
        }
        if subscriptionGroupName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            missing.append(.subscriptionGroupName)
        }
        if let termsOfUseURL = legalLinks.termsOfUseURL {
            if !Self.isHTTPSURL(termsOfUseURL) {
                missing.append(.httpsTermsOfUseURL)
            }
        } else {
            missing.append(.termsOfUseURL)
        }
        if let privacyPolicyURL = legalLinks.privacyPolicyURL {
            if !Self.isHTTPSURL(privacyPolicyURL) {
                missing.append(.httpsPrivacyPolicyURL)
            }
        } else {
            missing.append(.privacyPolicyURL)
        }

        return missing
    }

    var missingPaidReleaseRequirements: [String] {
        missingPaidReleaseRequirementItems.map(\.displayName)
    }

    var isReadyForPaidRelease: Bool {
        missingPaidReleaseRequirementItems.isEmpty
    }

    var releaseReadinessSnapshot: PurchaseReleaseReadinessSnapshot {
        PurchaseReleaseReadinessSnapshot(
            missingRequirements: missingPaidReleaseRequirementItems,
            purchaseEntryPointIsEnabled: purchaseEntryPointIsEnabled,
            featureRestrictionsAreEnabled: featureRestrictionsAreEnabled,
            backgroundEntitlementRefreshIsEnabled: backgroundEntitlementRefreshIsEnabled
        )
    }

    var canExposePurchaseEntryPoint: Bool {
        releaseReadinessSnapshot.canExposePurchaseEntryPoint
    }

    private static func isHTTPSURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }
}
