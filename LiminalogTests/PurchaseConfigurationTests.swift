import Foundation
import Testing
@testable import Liminalog

struct PurchaseConfigurationTests {
    private let termsURL = URL(string: "https://example.com/terms")!
    private let privacyURL = URL(string: "https://example.com/privacy")!

    @Test
    func currentConfigurationUsesKnownProductIDs() {
        #expect(PurchaseConfiguration.current.productIDs == PurchaseProductID.storeKitProductIDs)
        #expect(PurchaseConfiguration.current.storeKitProductIDs == PurchaseProductID.storeKitProductIDs)
    }

    @Test
    func currentConfigurationIsNotMarkedReadyUntilReleaseMetadataIsConfirmed() {
        let missing = PurchaseConfiguration.current.missingPaidReleaseRequirementItems

        #expect(!PurchaseConfiguration.current.isReadyForPaidRelease)
        #expect(!PurchaseConfiguration.current.canExposePurchaseEntryPoint)
        #expect(PurchaseConfiguration.current.legalLinks.termsOfUseURL == URL(string: "https://liminalog-lp.vercel.app/terms"))
        #expect(PurchaseConfiguration.current.legalLinks.privacyPolicyURL == URL(string: "https://liminalog-lp.vercel.app/privacy"))
        #expect(!PurchaseConfiguration.current.purchaseEntryPointIsEnabled)
        #expect(!PurchaseConfiguration.current.featureRestrictionsAreEnabled)
        #expect(!PurchaseConfiguration.current.backgroundEntitlementRefreshIsEnabled)
        #expect(missing.contains(.confirmedAppStoreConnectProductIDs))
        #expect(missing.contains(.subscriptionGroupName))
        #expect(!missing.contains(.termsOfUseURL))
        #expect(!missing.contains(.privacyPolicyURL))
        #expect(!missing.contains(.storeKitProductID))
    }

    @Test
    func paidReleaseRequirementsExposeStableDisplayNames() {
        #expect(PurchasePaidReleaseRequirement.storeKitProductID.displayName == "StoreKitの商品ID")
        #expect(PurchasePaidReleaseRequirement.duplicateProductID.displayName == "商品IDの重複")
        #expect(PurchasePaidReleaseRequirement.unsupportedProductID.displayName == "未対応の商品ID")
        #expect(PurchasePaidReleaseRequirement.confirmedAppStoreConnectProductIDs.displayName == "本番Product ID確認")
        #expect(PurchasePaidReleaseRequirement.subscriptionGroupName.displayName == "サブスクリプショングループ名")
        #expect(PurchasePaidReleaseRequirement.termsOfUseURL.displayName == "利用規約URL")
        #expect(PurchasePaidReleaseRequirement.httpsTermsOfUseURL.displayName == "利用規約URL（HTTPS）")
        #expect(PurchasePaidReleaseRequirement.privacyPolicyURL.displayName == "プライバシーポリシーURL")
        #expect(PurchasePaidReleaseRequirement.httpsPrivacyPolicyURL.displayName == "プライバシーポリシーURL（HTTPS）")
    }

    @Test
    func paidReleaseRequirementsExposeActionableResolutionHints() {
        #expect(PurchasePaidReleaseRequirement.storeKitProductID.resolutionHint == "App Store Connect または StoreKit Configuration に作る商品IDを設定する。")
        #expect(PurchasePaidReleaseRequirement.duplicateProductID.resolutionHint == "同じ商品IDが重複していないか確認する。")
        #expect(PurchasePaidReleaseRequirement.unsupportedProductID.resolutionHint == "アプリ側で扱える購入種別に紐づく商品IDへ直す。")
        #expect(PurchasePaidReleaseRequirement.confirmedAppStoreConnectProductIDs.resolutionHint == "本番の商品IDと商品種別を App Store Connect で確認してから有効化する。")
        #expect(PurchasePaidReleaseRequirement.subscriptionGroupName.resolutionHint == "App Store Connect のサブスクリプショングループ名を設定する。")
        #expect(PurchasePaidReleaseRequirement.termsOfUseURL.resolutionHint == "課金導入前に利用規約ページを公開し、HTTPS URL を設定する。")
        #expect(PurchasePaidReleaseRequirement.httpsTermsOfUseURL.resolutionHint == "利用規約URLを https:// で始まる公開URLへ変更する。")
        #expect(PurchasePaidReleaseRequirement.privacyPolicyURL.resolutionHint == "プライバシーポリシーの HTTPS URL を設定する。")
        #expect(PurchasePaidReleaseRequirement.httpsPrivacyPolicyURL.resolutionHint == "プライバシーポリシーURLを https:// で始まる公開URLへ変更する。")
    }

    @Test
    func releaseBuildPolicyStaysClosedWhenOnlyTermsAreMissing() {
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: nil,
                privacyPolicyURL: URL(string: "https://liminalog-lp.vercel.app/privacy")
            )
        )
        let policy = PurchaseActivationPolicy(
            configuration: configuration,
            buildMode: .release
        )

        #expect(configuration.missingPaidReleaseRequirementItems == [.termsOfUseURL])
        #expect(!configuration.canExposePurchaseEntryPoint)
        #expect(!policy.shouldShowSettingsEntryPoint)
        #expect(!policy.shouldUseStoreKitRuntime)
        #expect(!policy.shouldEnforceFeatureRestrictions)
    }

    @Test
    func configurationIsReadyWhenProductsAndLegalLinksArePresent() {
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            )
        )

        #expect(configuration.isReadyForPaidRelease)
        #expect(!configuration.canExposePurchaseEntryPoint)
        #expect(configuration.missingPaidReleaseRequirementItems.isEmpty)
    }

    @Test
    func purchaseEntryPointRequiresExplicitGoLiveSwitchEvenAfterMetadataIsReady() {
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true
        )

        #expect(configuration.isReadyForPaidRelease)
        #expect(configuration.canExposePurchaseEntryPoint)
        #expect(configuration.missingPaidReleaseRequirementItems.isEmpty)
    }

    @Test
    func currentReleaseReadinessSnapshotKeepsPurchaseClosed() {
        let snapshot = PurchaseConfiguration.current.releaseReadinessSnapshot

        #expect(snapshot.state == .missingRequiredMetadata)
        #expect(!snapshot.hasRequiredMetadata)
        #expect(!snapshot.canExposePurchaseEntryPoint)
        #expect(!snapshot.shouldEnforceFeatureRestrictions)
        #expect(!snapshot.shouldRefreshEntitlementsInBackground)
        #expect(snapshot.missingRequirements == PurchaseConfiguration.current.missingPaidReleaseRequirementItems)
    }

    @Test
    func releaseReadinessSnapshotWaitsForExplicitGoLiveAfterMetadataIsReady() {
        let configuration = readyConfiguration()
        let snapshot = configuration.releaseReadinessSnapshot

        #expect(snapshot.state == .metadataReadyWaitingForGoLive)
        #expect(snapshot.hasRequiredMetadata)
        #expect(!snapshot.canExposePurchaseEntryPoint)
        #expect(!snapshot.shouldEnforceFeatureRestrictions)
        #expect(!snapshot.shouldRefreshEntitlementsInBackground)
        #expect(configuration.isReadyForPaidRelease)
        #expect(!configuration.canExposePurchaseEntryPoint)
    }

    @Test
    func releaseReadinessSnapshotSeparatesPurchaseEntryPointFromFeatureRestrictions() {
        let configuration = readyConfiguration(purchaseEntryPointIsEnabled: true)
        let snapshot = configuration.releaseReadinessSnapshot

        #expect(snapshot.state == .purchaseEntryPointReady)
        #expect(snapshot.canExposePurchaseEntryPoint)
        #expect(!snapshot.shouldEnforceFeatureRestrictions)
        #expect(!snapshot.shouldRefreshEntitlementsInBackground)
        #expect(configuration.canExposePurchaseEntryPoint)
    }

    @Test
    func releaseReadinessSnapshotReportsFeatureRestrictionsAfterPurchaseEntryPointIsReady() {
        let configuration = readyConfiguration(
            purchaseEntryPointIsEnabled: true,
            featureRestrictionsAreEnabled: true
        )
        let snapshot = configuration.releaseReadinessSnapshot

        #expect(snapshot.state == .featureRestrictionsReady)
        #expect(snapshot.canExposePurchaseEntryPoint)
        #expect(snapshot.shouldEnforceFeatureRestrictions)
        #expect(snapshot.shouldRefreshEntitlementsInBackground)
    }

    @Test
    func releaseReadinessSnapshotDoesNotLetBackgroundRefreshBypassGoLive() {
        let configuration = readyConfiguration(backgroundEntitlementRefreshIsEnabled: true)
        let snapshot = configuration.releaseReadinessSnapshot

        #expect(snapshot.state == .metadataReadyWaitingForGoLive)
        #expect(snapshot.hasRequiredMetadata)
        #expect(!snapshot.canExposePurchaseEntryPoint)
        #expect(!snapshot.shouldEnforceFeatureRestrictions)
        #expect(!snapshot.shouldRefreshEntitlementsInBackground)
    }

    @Test
    func purchaseEntryPointCannotBypassMissingReleaseMetadata() {
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: false,
            subscriptionGroupName: nil,
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true,
            backgroundEntitlementRefreshIsEnabled: true
        )
        let snapshot = configuration.releaseReadinessSnapshot
        let policy = PurchaseActivationPolicy(
            configuration: configuration,
            buildMode: .release
        )
        let runtimePolicy = PurchaseStoreRuntimePolicy(activationPolicy: policy)

        #expect(snapshot.state == .missingRequiredMetadata)
        #expect(!snapshot.hasRequiredMetadata)
        #expect(!snapshot.canExposePurchaseEntryPoint)
        #expect(!snapshot.shouldRefreshEntitlementsInBackground)
        #expect(!configuration.canExposePurchaseEntryPoint)
        #expect(!policy.shouldShowSettingsEntryPoint)
        #expect(!policy.shouldUseStoreKitRuntime)
        #expect(!runtimePolicy.allowsStoreKitOperations)
        #expect(!runtimePolicy.shouldStartStoreKitOnAppLaunch)
    }

    @Test
    func featureRestrictionsCannotBypassPurchaseEntryPointReadiness() {
        let configuration = readyConfiguration(
            purchaseEntryPointIsEnabled: false,
            featureRestrictionsAreEnabled: true,
            backgroundEntitlementRefreshIsEnabled: true
        )
        let snapshot = configuration.releaseReadinessSnapshot
        let policy = PurchaseActivationPolicy(
            configuration: configuration,
            buildMode: .release
        )

        #expect(snapshot.state == .metadataReadyWaitingForGoLive)
        #expect(snapshot.hasRequiredMetadata)
        #expect(!snapshot.canExposePurchaseEntryPoint)
        #expect(!snapshot.shouldEnforceFeatureRestrictions)
        #expect(!snapshot.shouldRefreshEntitlementsInBackground)
        #expect(!policy.shouldShowSettingsEntryPoint)
        #expect(!policy.shouldUseStoreKitRuntime)
        #expect(!policy.shouldEnforceFeatureRestrictions)
        #expect(!policy.shouldRefreshEntitlementsInBackground)
    }

    @Test
    func storeKitProductIDsAreTrimmedBeforeRuntimeUse() {
        let configuration = PurchaseConfiguration(
            productIDs: [
                "  \(PurchaseProductID.proMonthly.rawValue)  ",
                "\n\(PurchaseProductID.lifetime.rawValue)\t"
            ],
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true
        )

        #expect(configuration.storeKitProductIDs == [
            PurchaseProductID.proMonthly.rawValue,
            PurchaseProductID.lifetime.rawValue
        ])
        #expect(configuration.isReadyForPaidRelease)
        #expect(configuration.canExposePurchaseEntryPoint)
    }

    @Test
    func blankSubscriptionGroupNameIsMissingReleaseMetadata() {
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "  ",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true
        )

        #expect(!configuration.isReadyForPaidRelease)
        #expect(!configuration.canExposePurchaseEntryPoint)
        #expect(configuration.missingPaidReleaseRequirementItems == [.subscriptionGroupName])
    }

    @Test
    func duplicateProductIDsBlockPaidRelease() {
        let configuration = PurchaseConfiguration(
            productIDs: [
                PurchaseProductID.proMonthly.rawValue,
                PurchaseProductID.proMonthly.rawValue
            ],
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true
        )

        #expect(!configuration.isReadyForPaidRelease)
        #expect(!configuration.canExposePurchaseEntryPoint)
        #expect(configuration.missingPaidReleaseRequirementItems == [.duplicateProductID])
    }

    @Test
    func unsupportedProductIDsBlockPaidRelease() {
        let configuration = PurchaseConfiguration(
            productIDs: [
                PurchaseProductID.proMonthly.rawValue,
                "liminalog.unknown.product"
            ],
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true
        )

        #expect(!configuration.isReadyForPaidRelease)
        #expect(!configuration.canExposePurchaseEntryPoint)
        #expect(configuration.missingPaidReleaseRequirementItems == [.unsupportedProductID])
    }

    @Test
    func premiumDecorationProductIDsAreAcceptedByReleaseChecks() {
        let configuration = PurchaseConfiguration(
            productIDs: [
                PurchaseProductID.proMonthly.rawValue,
                "\(PurchaseProductID.premiumDecorationProductPrefix)aurora_frame"
            ],
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            )
        )

        #expect(configuration.isReadyForPaidRelease)
        #expect(configuration.missingPaidReleaseRequirementItems.isEmpty)
    }

    @Test
    func blankProductIDsBlockPaidRelease() {
        let configuration = PurchaseConfiguration(
            productIDs: ["  "],
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            )
        )

        #expect(!configuration.isReadyForPaidRelease)
        #expect(!configuration.canExposePurchaseEntryPoint)
        #expect(configuration.missingPaidReleaseRequirementItems == [.storeKitProductID])
    }

    @Test
    func legalLinksMustBeHTTPSBeforePaidRelease() throws {
        let httpTermsURL = try #require(URL(string: "http://example.com/terms"))
        let customPrivacyURL = try #require(URL(string: "liminalog://privacy"))
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: httpTermsURL,
                privacyPolicyURL: customPrivacyURL
            )
        )

        #expect(!configuration.isReadyForPaidRelease)
        #expect(!configuration.canExposePurchaseEntryPoint)
        #expect(configuration.missingPaidReleaseRequirementItems == [
            .httpsTermsOfUseURL,
            .httpsPrivacyPolicyURL
        ])
    }

    @Test
    func releaseBuildPolicyDisablesPurchaseSurfaceUntilReady() {
        let policy = PurchaseActivationPolicy(
            configuration: .current,
            buildMode: .release
        )
        let runtimePolicy = PurchaseStoreRuntimePolicy(activationPolicy: policy)

        #expect(!policy.shouldShowSettingsEntryPoint)
        #expect(!policy.shouldUseStoreKitRuntime)
        #expect(!policy.shouldEnforceFeatureRestrictions)
        #expect(!runtimePolicy.allowsStoreKitOperations)
        #expect(!runtimePolicy.shouldStartStoreKitOnAppLaunch)
        #expect(!runtimePolicy.shouldRefreshEntitlementsOnSceneActivation)
        #expect(runtimePolicy.sceneActivationRefreshMaxAge == 6 * 60 * 60)
    }

    @Test
    func releaseBuildPolicyShowsReadyPurchaseEntryPoint() {
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true
        )
        let policy = PurchaseActivationPolicy(
            configuration: configuration,
            buildMode: .release
        )
        let runtimePolicy = PurchaseStoreRuntimePolicy(activationPolicy: policy)

        #expect(policy.shouldShowSettingsEntryPoint)
        #expect(policy.shouldUseStoreKitRuntime)
        #expect(!policy.shouldEnforceFeatureRestrictions)
        #expect(!policy.shouldRefreshEntitlementsInBackground)
        #expect(runtimePolicy.allowsStoreKitOperations)
        #expect(!runtimePolicy.shouldStartStoreKitOnAppLaunch)
        #expect(!runtimePolicy.shouldRefreshEntitlementsOnSceneActivation)
    }

    @Test
    func readyReleasePolicyCanEnableFeatureRestrictionsSeparatelyFromPurchaseSurface() {
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true,
            featureRestrictionsAreEnabled: true
        )
        let policy = PurchaseActivationPolicy(
            configuration: configuration,
            buildMode: .release
        )
        let runtimePolicy = PurchaseStoreRuntimePolicy(activationPolicy: policy)

        #expect(policy.shouldShowSettingsEntryPoint)
        #expect(policy.shouldUseStoreKitRuntime)
        #expect(policy.shouldEnforceFeatureRestrictions)
        #expect(policy.shouldRefreshEntitlementsInBackground)
        #expect(runtimePolicy.allowsStoreKitOperations)
        #expect(runtimePolicy.shouldStartStoreKitOnAppLaunch)
        #expect(runtimePolicy.shouldRefreshEntitlementsOnSceneActivation)
    }

    @Test
    func readyReleasePolicyCanEnableBackgroundRefreshWithoutFeatureRestrictions() {
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true,
            backgroundEntitlementRefreshIsEnabled: true
        )
        let policy = PurchaseActivationPolicy(
            configuration: configuration,
            buildMode: .release
        )
        let runtimePolicy = PurchaseStoreRuntimePolicy(activationPolicy: policy)

        #expect(policy.shouldShowSettingsEntryPoint)
        #expect(policy.shouldUseStoreKitRuntime)
        #expect(!policy.shouldEnforceFeatureRestrictions)
        #expect(policy.shouldRefreshEntitlementsInBackground)
        #expect(runtimePolicy.allowsStoreKitOperations)
        #expect(runtimePolicy.shouldStartStoreKitOnAppLaunch)
        #expect(runtimePolicy.shouldRefreshEntitlementsOnSceneActivation)
    }

    @Test
    func developmentBuildPolicyShowsPurchaseEntryPointForVerification() {
        let policy = PurchaseActivationPolicy(
            configuration: .current,
            buildMode: .development
        )
        let runtimePolicy = PurchaseStoreRuntimePolicy(activationPolicy: policy)

        #expect(policy.shouldShowSettingsEntryPoint)
        #expect(policy.shouldUseStoreKitRuntime)
        #expect(!policy.shouldEnforceFeatureRestrictions)
        #expect(!policy.shouldRefreshEntitlementsInBackground)
        #expect(runtimePolicy.allowsStoreKitOperations)
        #expect(!runtimePolicy.shouldStartStoreKitOnAppLaunch)
        #expect(!runtimePolicy.shouldRefreshEntitlementsOnSceneActivation)
    }

    @Test
    func developmentBuildPolicyDoesNotEnforceFeatureRestrictionsEvenWhenReady() {
        let configuration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            )
        )
        let policy = PurchaseActivationPolicy(
            configuration: configuration,
            buildMode: .development
        )

        #expect(policy.shouldShowSettingsEntryPoint)
        #expect(policy.shouldUseStoreKitRuntime)
        #expect(!policy.shouldEnforceFeatureRestrictions)
    }

    @Test
    func currentActivationPolicyKeepsInjectedConfiguration() {
        let configuration = PurchaseConfiguration(
            productIDs: [],
            productIDsAreConfirmedForAppStoreConnect: false,
            subscriptionGroupName: nil,
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: nil,
                privacyPolicyURL: nil
            )
        )

        let policy = PurchaseActivationPolicy.current(configuration: configuration)

        #expect(policy.configuration == configuration)
    }

    private func readyConfiguration(
        purchaseEntryPointIsEnabled: Bool = false,
        featureRestrictionsAreEnabled: Bool = false,
        backgroundEntitlementRefreshIsEnabled: Bool = false
    ) -> PurchaseConfiguration {
        PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: purchaseEntryPointIsEnabled,
            featureRestrictionsAreEnabled: featureRestrictionsAreEnabled,
            backgroundEntitlementRefreshIsEnabled: backgroundEntitlementRefreshIsEnabled
        )
    }
}
