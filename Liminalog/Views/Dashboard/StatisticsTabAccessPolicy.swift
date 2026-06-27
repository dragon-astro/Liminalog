import Foundation

enum StatisticsTabDestination: Equatable {
    case dashboard
    case proPreview
}

struct StatisticsTabAccessPolicy: Equatable {
    var featureGate: PurchaseFeatureGate

    init(
        activationPolicy: PurchaseActivationPolicy = .current()
    ) {
        self.featureGate = PurchaseFeatureGate(activationPolicy: activationPolicy)
    }

    func destination(
        entitlements: PurchaseEntitlements
    ) -> StatisticsTabDestination {
        let decision = featureGate.decision(
            for: .statisticsTab,
            entitlements: entitlements
        )
        return decision.isAllowed ? .dashboard : .proPreview
    }
}

#if DEBUG
enum StatisticsTabDebugAccess {
    static let enforceFeatureRestrictionsKey = "debug.purchase.enforceFeatureRestrictions"

    static var forcedFeatureRestrictionsPolicy: StatisticsTabAccessPolicy {
        StatisticsTabAccessPolicy(
            activationPolicy: PurchaseActivationPolicy(
                configuration: PurchaseConfiguration(
                    productIDs: PurchaseProductID.storeKitProductIDs,
                    productIDsAreConfirmedForAppStoreConnect: true,
                    subscriptionGroupName: "Liminalog Pro",
                    legalLinks: PurchaseLegalLinks(
                        termsOfUseURL: URL(string: "https://example.com/terms")!,
                        privacyPolicyURL: URL(string: "https://example.com/privacy")!
                    ),
                    purchaseEntryPointIsEnabled: true,
                    featureRestrictionsAreEnabled: true
                ),
                buildMode: .release
            )
        )
    }
}
#endif
