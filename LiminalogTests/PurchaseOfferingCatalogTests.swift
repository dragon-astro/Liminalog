import Foundation
import Testing
@testable import Liminalog

struct PurchaseOfferingCatalogTests {
    private let catalog = PurchaseOfferingCatalog()
    private let termsURL = URL(string: "https://example.com/terms")!
    private let privacyURL = URL(string: "https://example.com/privacy")!

    @Test
    func freeUsersSeeProLifetimeAndSupportButNotDecorationPass() {
        let sections = catalog.sections(for: PurchaseEntitlements())

        #expect(sections.map(\.kind) == [.pro, .lifetime, .support])
        #expect(productIDs(in: sections) == [
            .proYearly,
            .proMonthly,
            .lifetime,
            .supportTipSmall,
            .supportTipMedium,
            .supportTipLarge
        ])
    }

    @Test
    func lifetimeOwnersSeeDecorationPassAndSupportOnly() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.lifetime.rawValue],
            ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
            lastVerifiedAt: Date()
        )

        let sections = catalog.sections(for: entitlements)

        #expect(sections.map(\.kind) == [.decorationPass, .support])
        #expect(productIDs(in: sections) == [
            .decorationYearly,
            .decorationMonthly,
            .supportTipSmall,
            .supportTipMedium,
            .supportTipLarge
        ])
    }

    @Test
    func activeProUsersCanStillChooseLifetimeButDoNotSeeAnotherProOffer() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.proYearly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )

        let sections = catalog.sections(for: entitlements)

        #expect(sections.map(\.kind) == [.lifetime, .support])
        #expect(productIDs(in: sections) == [
            .lifetime,
            .supportTipSmall,
            .supportTipMedium,
            .supportTipLarge
        ])
    }

    @Test
    func lifetimeOwnersWithActiveDecorationPassDoNotSeeAnotherDecorationPassOffer() {
        let entitlements = PurchaseEntitlements(
            activeProductIDs: [
                PurchaseProductID.lifetime.rawValue,
                PurchaseProductID.decorationMonthly.rawValue
            ],
            ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
            lastVerifiedAt: Date()
        )

        let sections = catalog.sections(for: entitlements)

        #expect(sections.map(\.kind) == [.support])
    }

    @Test
    func sectionsFilterUnavailableStoreKitProductsAndDropEmptySections() {
        let sections = catalog.sections(
            for: PurchaseEntitlements(),
            availableProductIDs: [
                PurchaseProductID.proYearly.rawValue,
                PurchaseProductID.supportTipSmall.rawValue
            ]
        )

        #expect(sections.map(\.kind) == [.pro, .support])
        #expect(productIDs(in: sections) == [.proYearly, .supportTipSmall])
    }

    @Test
    func sectionsAreEmptyWhenNoCurrentOfferProductsAreAvailable() {
        let sections = catalog.sections(
            for: PurchaseEntitlements(),
            availableProductIDs: [PurchaseProductID.decorationMonthly.rawValue]
        )

        #expect(sections.isEmpty)
    }

    @Test
    func productAvailabilityStartsAsLoadingUntilFirstLoadAttemptFinishes() {
        #expect(
            PurchaseProductAvailability.current(
                hasLoadedProducts: false,
                isLoadingProducts: false,
                hasAttemptedProductLoad: false
            ) == .loading
        )
        #expect(
            PurchaseProductAvailability.current(
                hasLoadedProducts: false,
                isLoadingProducts: true,
                hasAttemptedProductLoad: true
            ) == .loading
        )
    }

    @Test
    func productAvailabilityIsDisabledWhenStoreKitRuntimeIsDisabled() {
        #expect(
            PurchaseProductAvailability.current(
                canUseStoreKitRuntime: false,
                hasLoadedProducts: true,
                isLoadingProducts: false,
                hasAttemptedProductLoad: true
            ) == .disabled
        )
    }

    @Test
    func productAvailabilitySeparatesAvailableFromUnavailable() {
        #expect(
            PurchaseProductAvailability.current(
                hasLoadedProducts: true,
                isLoadingProducts: false,
                hasAttemptedProductLoad: true
            ) == .available
        )
        #expect(
            PurchaseProductAvailability.current(
                hasLoadedProducts: false,
                isLoadingProducts: false,
                hasAttemptedProductLoad: true
            ) == .unavailable
        )
    }

    @Test
    func supportSurfacePolicyDisablesStoreKitControlsUntilReleaseIsReady() {
        let policy = PurchaseSupportSurfacePolicy(
            activationPolicy: PurchaseActivationPolicy(
                configuration: .current,
                buildMode: .release
            )
        )

        #expect(!policy.allowsStoreKitOperations)
        #expect(!policy.showsStoreKitActionControls)
        #expect(
            policy.productAvailability(
                hasLoadedProducts: true,
                isLoadingProducts: false,
                hasAttemptedProductLoad: true
            ) == .disabled
        )
    }

    @Test
    func supportSurfacePolicyAllowsDebugVerificationBeforeReleaseMetadataIsReady() {
        let policy = PurchaseSupportSurfacePolicy(
            activationPolicy: PurchaseActivationPolicy(
                configuration: .current,
                buildMode: .development
            )
        )

        #expect(policy.allowsStoreKitOperations)
        #expect(policy.showsStoreKitActionControls)
        #expect(
            policy.productAvailability(
                hasLoadedProducts: false,
                isLoadingProducts: false,
                hasAttemptedProductLoad: false
            ) == .loading
        )
    }

    @Test
    func supportSurfacePolicyAllowsStoreKitControlsWhenReleaseIsReady() {
        let policy = PurchaseSupportSurfacePolicy(
            activationPolicy: PurchaseActivationPolicy(
                configuration: readyConfiguration,
                buildMode: .release
            )
        )

        #expect(policy.allowsStoreKitOperations)
        #expect(policy.showsStoreKitActionControls)
        #expect(
            policy.productAvailability(
                hasLoadedProducts: true,
                isLoadingProducts: false,
                hasAttemptedProductLoad: true
            ) == .available
        )
    }

    private func productIDs(in sections: [PurchaseOfferingSection]) -> [PurchaseProductID] {
        sections.flatMap { section in
            section.products.map(\.id)
        }
    }

    private var readyConfiguration: PurchaseConfiguration {
        PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: termsURL,
                privacyPolicyURL: privacyURL
            ),
            purchaseEntryPointIsEnabled: true
        )
    }
}
