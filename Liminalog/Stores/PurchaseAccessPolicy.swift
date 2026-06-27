import Foundation

enum PurchaseFeature: String, Codable, CaseIterable, Identifiable {
    case coreRecording
    case calendarSelfView
    case friendsAndSharing
    case dailyCards
    case todayScoreAndStreak
    case statisticsTab
    case unlimitedCategorySets
    case export
    case advancedWidgets
    case appLock
    case healthKitAutomation
    case premiumDecorationRental

    var id: String { rawValue }
}

enum PurchaseRequirement: String, Codable, Equatable {
    case free
    case pro
    case premiumDecorationRental
}

struct PurchaseAccessDecision: Equatable, Codable {
    var feature: PurchaseFeature
    var requirement: PurchaseRequirement
    var isAllowed: Bool
}

fileprivate struct PurchaseAccessPolicy: Equatable, Codable {
    static let defaultFreeCategorySetLimit = 2

    var freeCategorySetLimit = defaultFreeCategorySetLimit

    func decision(for feature: PurchaseFeature, entitlements: PurchaseEntitlements) -> PurchaseAccessDecision {
        let requirement = requirement(for: feature)
        return PurchaseAccessDecision(
            feature: feature,
            requirement: requirement,
            isAllowed: isAllowed(requirement: requirement, entitlements: entitlements)
        )
    }

    func categorySetLimit(entitlements: PurchaseEntitlements) -> Int? {
        entitlements.isProActive ? nil : freeCategorySetLimit
    }

    func ownsPremiumDecoration(productID: String, entitlements: PurchaseEntitlements) -> Bool {
        entitlements.ownedPremiumDecorationProductIDs.contains(productID)
    }

    private func requirement(for feature: PurchaseFeature) -> PurchaseRequirement {
        switch feature {
        case .coreRecording, .calendarSelfView, .friendsAndSharing, .dailyCards, .todayScoreAndStreak:
            return .free
        case .statisticsTab, .unlimitedCategorySets, .export, .advancedWidgets, .appLock, .healthKitAutomation:
            return .pro
        case .premiumDecorationRental:
            return .premiumDecorationRental
        }
    }

    private func isAllowed(requirement: PurchaseRequirement, entitlements: PurchaseEntitlements) -> Bool {
        switch requirement {
        case .free:
            return true
        case .pro:
            return entitlements.isProActive
        case .premiumDecorationRental:
            return entitlements.hasPremiumDecorationRental
        }
    }
}

struct PurchaseFeatureGate: Equatable {
    var activationPolicy: PurchaseActivationPolicy
    private var accessPolicy = PurchaseAccessPolicy()

    init(activationPolicy: PurchaseActivationPolicy) {
        self.activationPolicy = activationPolicy
    }

    func decision(for feature: PurchaseFeature, entitlements: PurchaseEntitlements) -> PurchaseAccessDecision {
        guard activationPolicy.shouldEnforceFeatureRestrictions else {
            return PurchaseAccessDecision(
                feature: feature,
                requirement: .free,
                isAllowed: true
            )
        }

        return accessPolicy.decision(for: feature, entitlements: entitlements)
    }

    func categorySetLimit(entitlements: PurchaseEntitlements) -> Int? {
        guard activationPolicy.shouldEnforceFeatureRestrictions else {
            return nil
        }

        return accessPolicy.categorySetLimit(entitlements: entitlements)
    }
}
