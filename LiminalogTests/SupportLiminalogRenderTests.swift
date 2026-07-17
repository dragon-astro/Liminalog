import SwiftUI
import Testing
@testable import Liminalog

/// 課金画面のデザイン確認用に、代表状態を PNG へ書き出す。
/// （プロダクトのテストではなく、目視レビュー用のレンダラ。）
@MainActor
struct SupportLiminalogRenderTests {
    private let outputDir = URL(fileURLWithPath: "/tmp/liminal_paywall_mockups")

    @Test(.disabled("Design review renderer; run manually when refreshing /tmp/liminal_paywall_mockups assets."))
    func renderPaywallStates() throws {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        try render(entitlements: PurchaseEntitlements(lastVerifiedAt: Date()), scheme: .dark, name: "paywall_free_dark")
        try render(entitlements: PurchaseEntitlements(lastVerifiedAt: Date()), scheme: .light, name: "paywall_free_light")
        try render(entitlements: PurchaseEntitlements(lastVerifiedAt: Date()), scheme: .dark, name: "tipjar_dark", screen: .tipJar)
        try render(entitlements: PurchaseEntitlements(lastVerifiedAt: Date()), scheme: .light, name: "tipjar_light", screen: .tipJar)
        try render(
            entitlements: PurchaseEntitlements(
                activeProductIDs: [PurchaseProductID.proYearly.rawValue],
                ownedNonConsumableProductIDs: [],
                lastVerifiedAt: Date()
            ),
            scheme: .dark,
            name: "paywall_pro_dark"
        )
        try render(
            entitlements: PurchaseEntitlements(
                activeProductIDs: [PurchaseProductID.lifetime.rawValue],
                ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
                lastVerifiedAt: Date()
            ),
            scheme: .dark,
            name: "paywall_lifetime_dark"
        )
    }

    private enum Screen {
        case paywall
        case tipJar
    }

    private func render(
        entitlements: PurchaseEntitlements,
        scheme: ColorScheme,
        name: String,
        screen: Screen = .paywall
    ) throws {
        let store = PurchaseStore.preview(entitlements: entitlements)
        store.applyDebugStoreKitProductDisplayOverrideIfRequested(
            arguments: ["-LiminalogDebugStoreKitProducts", "loaded"]
        )

        // 出荷時の見た目を確認するため、DEBUG限定の未設定カードが出ない構成にする。
        let readyConfiguration = PurchaseConfiguration(
            productIDs: PurchaseProductID.storeKitProductIDs,
            productIDsAreConfirmedForAppStoreConnect: true,
            subscriptionGroupName: "Liminalog Pro",
            legalLinks: PurchaseLegalLinks(
                termsOfUseURL: URL(string: "https://liminalog-lp.vercel.app/terms"),
                privacyPolicyURL: URL(string: "https://liminalog-lp.vercel.app/privacy")
            ),
            purchaseEntryPointIsEnabled: true,
            featureRestrictionsAreEnabled: false,
            backgroundEntitlementRefreshIsEnabled: true
        )

        // ImageRenderer は ScrollView 内を描画できないため、スクロール中身を直接レンダリングする。
        let inner: AnyView
        switch screen {
        case .paywall:
            inner = AnyView(
                SupportLiminalogView(purchaseStore: store, purchaseConfiguration: readyConfiguration).paywallContent
            )
        case .tipJar:
            inner = AnyView(
                SupportTipJarView(purchaseStore: store, purchaseConfiguration: readyConfiguration).tipJarContent
            )
        }

        let content = ZStack {
            LiminalTheme.canvasGradient
            inner
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
        }
        // 実機のナビゲーション下ビューポート相当の固定高さで、全画面レイアウトの伸びを確認する
        .frame(width: 390, height: 840)
        .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else {
            Issue.record("failed to render \(name)")
            return
        }
        let url = outputDir.appendingPathComponent("\(name).png")
        try data.write(to: url)
    }
}
