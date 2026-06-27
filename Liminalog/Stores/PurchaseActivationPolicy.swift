import Foundation

enum PurchaseRuntimeBuildMode: Equatable {
    case development
    case release
}

struct PurchaseActivationPolicy: Equatable {
    var configuration: PurchaseConfiguration
    var buildMode: PurchaseRuntimeBuildMode

    static func current(configuration: PurchaseConfiguration = .current) -> PurchaseActivationPolicy {
        #if DEBUG
        PurchaseActivationPolicy(configuration: configuration, buildMode: .development)
        #else
        PurchaseActivationPolicy(configuration: configuration, buildMode: .release)
        #endif
    }

    var shouldShowSettingsEntryPoint: Bool {
        switch buildMode {
        case .development:
            return true
        case .release:
            return configuration.canExposePurchaseEntryPoint
        }
    }

    var shouldUseStoreKitRuntime: Bool {
        switch buildMode {
        case .development:
            return true
        case .release:
            return configuration.canExposePurchaseEntryPoint
        }
    }

    var shouldEnforceFeatureRestrictions: Bool {
        switch buildMode {
        case .development:
            return false
        case .release:
            return configuration.canExposePurchaseEntryPoint && configuration.featureRestrictionsAreEnabled
        }
    }

    var shouldRefreshEntitlementsInBackground: Bool {
        shouldUseStoreKitRuntime
            && (configuration.backgroundEntitlementRefreshIsEnabled || shouldEnforceFeatureRestrictions)
    }
}

struct PurchaseStoreRuntimePolicy: Equatable {
    var activationPolicy: PurchaseActivationPolicy
    var sceneActivationRefreshMaxAge: TimeInterval = 6 * 60 * 60

    static func current(
        activationPolicy: PurchaseActivationPolicy = .current()
    ) -> PurchaseStoreRuntimePolicy {
        PurchaseStoreRuntimePolicy(activationPolicy: activationPolicy)
    }

    var shouldStartStoreKitOnAppLaunch: Bool {
        activationPolicy.shouldRefreshEntitlementsInBackground
    }

    var shouldRefreshEntitlementsOnSceneActivation: Bool {
        activationPolicy.shouldRefreshEntitlementsInBackground
    }

    var allowsStoreKitOperations: Bool {
        activationPolicy.shouldUseStoreKitRuntime
    }
}
