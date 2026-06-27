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
