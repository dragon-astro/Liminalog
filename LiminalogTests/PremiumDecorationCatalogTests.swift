import Foundation
import Testing
@testable import Liminalog

@MainActor
struct PremiumDecorationCatalogTests {
    @Test
    func productIDsAreUniqueAndUsePremiumDecorationProductKind() {
        let productIDs = PremiumDecorationCatalog.productIDs

        #expect(productIDs.count == Set(productIDs).count)
        for productID in productIDs {
            #expect(productID.hasPrefix(PurchaseProductID.premiumDecorationProductPrefix))
            #expect(PurchaseProductID.kind(for: productID) == .premiumDecoration)
            #expect(PurchaseProductID.expectedStoreKitProductKind(for: productID) == .nonConsumable)
        }
    }

    @Test
    func catalogTargetsOnlyExistingHiddenDecorationStyles() {
        let frameIDs = Set(ProfileIconFrameCatalog.items.map(\.id))
        let visibleFrameIDs = Set(ProfileIconFrameCatalog.visibleItems.map(\.id))
        let cardIDs = Set(ProfileCardStyleCatalog.items.map(\.id))
        let visibleCardIDs = Set(ProfileCardStyleCatalog.visibleItems.map(\.id))

        for item in PremiumDecorationCatalog.items {
            switch item.kind {
            case .iconFrame:
                #expect(frameIDs.contains(item.targetID))
                #expect(!visibleFrameIDs.contains(item.targetID))
                #expect(item.assetName == "profile_frame_\(item.targetID)")
            case .cardStyle:
                #expect(cardIDs.contains(item.targetID))
                #expect(!visibleCardIDs.contains(item.targetID))
                #expect(item.assetName == "profile_card_\(item.targetID)")
            case .theme, .nameBadge, .streakIcon, .iconSet, .barStyle, .monthArt:
                Issue.record("Premium decoration catalog should not expose \(item.kind.rawValue) yet.")
            }
        }
    }

    @Test
    func catalogTargetsDoNotCollideWithEarnedUnlockCatalog() {
        let earnedTargets = Set(UnlockCatalog.items.map { "\($0.kind.rawValue):\($0.targetID)" })
        let premiumTargets = Set(PremiumDecorationCatalog.items.map { "\($0.kind.rawValue):\($0.targetID)" })

        #expect(earnedTargets.isDisjoint(with: premiumTargets))
    }

    @Test
    func catalogLookupIsStableByProductIDAndKindedTargetID() throws {
        let auroraFrame = try #require(PremiumDecorationCatalog.item(forProductID: "liminalog.decoration.frame.aurora_wreath"))
        let auroraCard = try #require(PremiumDecorationCatalog.item(forProductID: "liminalog.decoration.card.aurora_panel"))

        #expect(PremiumDecorationCatalog.item(forTargetID: "aurora_wreath", kind: .iconFrame)?.productID == auroraFrame.productID)
        #expect(PremiumDecorationCatalog.item(forTargetID: "aurora_panel", kind: .cardStyle)?.productID == auroraCard.productID)
        #expect(PremiumDecorationCatalog.item(forTargetID: "aurora_panel", kind: .iconFrame) == nil)
    }

    @Test
    func catalogProductsFollowPremiumDecorationAccessPolicy() throws {
        let item = try #require(PremiumDecorationCatalog.items.first)
        let policy = PremiumDecorationAccessPolicy()
        let free = PurchaseEntitlements()
        let rented = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.proMonthly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )
        let owned = PurchaseEntitlements(
            activeProductIDs: [item.productID],
            ownedNonConsumableProductIDs: [item.productID],
            lastVerifiedAt: Date()
        )

        #expect(policy.decision(for: item.product, entitlements: free).state == .unavailable)
        #expect(policy.decision(for: item.product, entitlements: rented).state == .rented)
        #expect(policy.decision(for: item.product, entitlements: owned).state == .owned)
    }

    @Test
    func equippingPolicyFallsBackWhenPremiumAccessExpires() throws {
        let policy = PremiumDecorationEquippingPolicy()
        let premiumItem = try #require(PremiumDecorationCatalog.item(forTargetID: "aurora_wreath", kind: .iconFrame))
        let ownedEntitlements = PurchaseEntitlements(
            activeProductIDs: [premiumItem.productID],
            ownedNonConsumableProductIDs: [premiumItem.productID],
            lastVerifiedAt: Date()
        )
        let rentedEntitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.decorationYearly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )
        let earnedID = "free_instrument_iron"
        let fallbackID = ProfileDecorationUnlocks.defaultIconFrameID

        #expect(
            policy.resolvedTargetID(
                requestedTargetID: earnedID,
                kind: .iconFrame,
                earnedTargetIDs: [earnedID],
                entitlements: PurchaseEntitlements(),
                fallbackTargetID: fallbackID
            ) == earnedID
        )
        #expect(
            policy.resolvedTargetID(
                requestedTargetID: premiumItem.targetID,
                kind: .iconFrame,
                earnedTargetIDs: [earnedID],
                entitlements: ownedEntitlements,
                fallbackTargetID: fallbackID
            ) == premiumItem.targetID
        )
        #expect(
            policy.resolvedTargetID(
                requestedTargetID: premiumItem.targetID,
                kind: .iconFrame,
                earnedTargetIDs: [earnedID],
                entitlements: rentedEntitlements,
                fallbackTargetID: fallbackID
            ) == premiumItem.targetID
        )
        #expect(
            policy.resolvedTargetID(
                requestedTargetID: premiumItem.targetID,
                kind: .iconFrame,
                earnedTargetIDs: [earnedID],
                entitlements: PurchaseEntitlements(),
                fallbackTargetID: fallbackID
            ) == fallbackID
        )
        #expect(
            policy.resolvedTargetID(
                requestedTargetID: "missing_frame",
                kind: .iconFrame,
                earnedTargetIDs: [earnedID],
                entitlements: ownedEntitlements,
                fallbackTargetID: fallbackID
            ) == fallbackID
        )
    }

    @Test
    func displayPolicyCombinesEarnedLockedAndPremiumUnavailableStates() throws {
        let earnedFrames = Array(UnlockCatalog.items.filter { $0.kind == .iconFrame }.prefix(2))
        let unlockedEarnedFrame = try #require(earnedFrames.first)
        let lockedEarnedFrame = try #require(earnedFrames.dropFirst().first)
        let premiumFrame = try #require(PremiumDecorationCatalog.items(kind: .iconFrame).first)
        let policy = DecorationAccessDisplayPolicy()

        let displayItems = policy.displayItems(
            kind: .iconFrame,
            earnedCatalogItems: earnedFrames,
            unlockedEarnedTargetIDs: [unlockedEarnedFrame.targetID],
            entitlements: PurchaseEntitlements()
        )

        let earnedItem = try #require(displayItems.first { $0.targetID == unlockedEarnedFrame.targetID })
        let lockedItem = try #require(displayItems.first { $0.targetID == lockedEarnedFrame.targetID })
        let premiumItem = try #require(displayItems.first { $0.targetID == premiumFrame.targetID })

        #expect(earnedItem.state == .earned)
        #expect(earnedItem.canEquip)
        #expect(earnedItem.productID == nil)
        #expect(lockedItem.state == .locked)
        #expect(!lockedItem.canEquip)
        #expect(lockedItem.productID == nil)
        #expect(premiumItem.state == .premiumUnavailable)
        #expect(!premiumItem.canEquip)
        #expect(premiumItem.productID == premiumFrame.productID)
    }

    @Test
    func displayPolicyMapsPremiumRentalAndOwnershipStates() throws {
        let premiumCard = try #require(PremiumDecorationCatalog.items(kind: .cardStyle).first)
        let policy = DecorationAccessDisplayPolicy()
        let rentedEntitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.proYearly.rawValue],
            ownedNonConsumableProductIDs: [],
            lastVerifiedAt: Date()
        )
        let ownedEntitlements = PurchaseEntitlements(
            activeProductIDs: [premiumCard.productID],
            ownedNonConsumableProductIDs: [premiumCard.productID],
            lastVerifiedAt: Date()
        )
        let lifetimeOnlyEntitlements = PurchaseEntitlements(
            activeProductIDs: [PurchaseProductID.lifetime.rawValue],
            ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
            lastVerifiedAt: Date()
        )

        let rentedItem = try #require(policy.displayItems(
            kind: .cardStyle,
            earnedCatalogItems: [],
            unlockedEarnedTargetIDs: [],
            entitlements: rentedEntitlements
        ).first)
        let ownedItem = try #require(policy.displayItems(
            kind: .cardStyle,
            earnedCatalogItems: [],
            unlockedEarnedTargetIDs: [],
            entitlements: ownedEntitlements
        ).first)
        let lifetimeOnlyItem = try #require(policy.displayItems(
            kind: .cardStyle,
            earnedCatalogItems: [],
            unlockedEarnedTargetIDs: [],
            entitlements: lifetimeOnlyEntitlements
        ).first)

        #expect(rentedItem.targetID == premiumCard.targetID)
        #expect(rentedItem.state == .premiumRented)
        #expect(rentedItem.canEquip)
        #expect(ownedItem.targetID == premiumCard.targetID)
        #expect(ownedItem.state == .premiumOwned)
        #expect(ownedItem.canEquip)
        #expect(lifetimeOnlyItem.targetID == premiumCard.targetID)
        #expect(lifetimeOnlyItem.state == .premiumUnavailable)
        #expect(!lifetimeOnlyItem.canEquip)
    }
}
