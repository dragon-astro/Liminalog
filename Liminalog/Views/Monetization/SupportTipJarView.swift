import StoreKit
import SwiftUI

/// 応援チップ専用画面。Pro のペイウォール（SupportLiminalogView）とは意図的に分離し、
/// 「一画面一決断」を守る。チップは機能を解放しない純粋な応援（docs/17 / docs/19）。
struct SupportTipJarView: View {
    let purchaseStore: PurchaseStore
    var purchaseConfiguration: PurchaseConfiguration
    var purchaseActivationPolicy: PurchaseActivationPolicy
    private let offeringCatalog = PurchaseOfferingCatalog()

    init(
        purchaseStore: PurchaseStore,
        purchaseConfiguration: PurchaseConfiguration = .current,
        purchaseActivationPolicy: PurchaseActivationPolicy? = nil
    ) {
        self.purchaseStore = purchaseStore
        self.purchaseConfiguration = purchaseConfiguration
        self.purchaseActivationPolicy = purchaseActivationPolicy ?? .current(configuration: purchaseConfiguration)
    }

    var body: some View {
        ZStack {
            LiminalTheme.canvasGradient.ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    tipJarContent
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .frame(minHeight: proxy.size.height)
                }
            }
        }
        .navigationTitle("開発を応援")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard surfacePolicy.allowsStoreKitOperations else { return }
            await purchaseStore.start()
            await purchaseStore.loadProductsIfNeeded()
        }
    }

    /// スクロール中身。レンダラテスト（SupportLiminalogRenderTests）からも直接参照する。
    /// カードは固有サイズのまま、画面中央にフロートさせる。
    var tipJarContent: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            tipCard

            if let userMessage = purchaseStore.userMessage {
                userMessageCard(userMessage)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Tip card（1枚の完成品）

    private var tipCard: some View {
        VStack(spacing: 22) {
            header
            tipBody
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .paywallOfferCard()
    }

    private var header: some View {
        VStack(spacing: 8) {
            Label {
                Text("応援チップ")
                    .font(.subheadline.weight(.bold))
            } icon: {
                Image(systemName: "heart.fill")
            }
            .foregroundStyle(LiminalTheme.reward)

            Text("この場所を、一緒に育てる。")
                .font(.title2.weight(.bold))
                .foregroundStyle(LiminalTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Liminalogは一人で作っています。チップで機能は変わりませんが、開発が続きます。")
                .font(.subheadline)
                .foregroundStyle(LiminalTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var tipBody: some View {
        switch surfacePolicy.productAvailability(
            hasLoadedProducts: !tipOfferings.isEmpty,
            isLoadingProducts: purchaseStore.isLoadingProducts,
            hasAttemptedProductLoad: purchaseStore.hasAttemptedProductLoad
        ) {
        case .disabled:
            Text("応援チップは現在準備中です。")
                .font(.footnote)
                .foregroundStyle(LiminalTheme.secondaryText)
                .multilineTextAlignment(.center)
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("商品情報を確認中")
                    .font(.footnote)
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
        case .available:
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    ForEach(tipOfferings) { offering in
                        tipRow(offering)
                    }
                }

                Text("チップは応援のための購入で、機能や特典は付きません。")
                    .font(.caption2)
                    .foregroundStyle(LiminalTheme.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        case .unavailable:
            VStack(spacing: 12) {
                Text(productUnavailableMessage)
                    .font(.footnote)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task {
                        guard surfacePolicy.allowsStoreKitOperations else { return }
                        await purchaseStore.loadProducts()
                    }
                } label: {
                    Label("もう一度確認", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                }
                .disabled(purchaseStore.isLoadingProducts)
            }
        }
    }

    private var tipOfferings: [PaywallPlanOffering] {
        let sections = offeringCatalog.sections(
            for: purchaseStore.entitlements,
            availableProductIDs: Set(purchaseStore.displayProducts.map(\.id))
        )
        return (sections.first { $0.kind == .support }?.products ?? [])
            .compactMap { product in
                guard let displayProduct = purchaseStore.displayProduct(for: product.id) else { return nil }
                return PaywallPlanOffering(id: product.id, badge: product.badge, priceText: displayProduct.displayPrice)
            }
    }

    private func tipRow(_ offering: PaywallPlanOffering) -> some View {
        Button {
            purchase(offering.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(LiminalTheme.reward.opacity(tipHeartOpacity(for: offering.id)))
                    .frame(width: 24)

                Text(tipTitle(for: offering.id))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(LiminalTheme.text)

                Spacer(minLength: 8)

                ZStack {
                    Text(offering.priceText)
                        .font(.body.weight(.bold))
                        .foregroundStyle(LiminalTheme.text)
                        .opacity(purchaseStore.purchaseInProgressProductID == offering.id.rawValue ? 0 : 1)
                    if purchaseStore.purchaseInProgressProductID == offering.id.rawValue {
                        ProgressView()
                    }
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(purchaseStore.purchaseInProgressProductID != nil)
    }

    private func tipTitle(for id: PurchaseProductID) -> String {
        switch id {
        case .supportTipSmall:
            "小さな応援"
        case .supportTipMedium:
            "しっかり応援"
        case .supportTipLarge:
            "大きな応援"
        default:
            id.displayName
        }
    }

    private func tipHeartOpacity(for id: PurchaseProductID) -> Double {
        switch id {
        case .supportTipSmall:
            0.55
        case .supportTipMedium:
            0.8
        default:
            1
        }
    }

    private func purchase(_ id: PurchaseProductID) {
        Task {
            guard surfacePolicy.allowsStoreKitOperations else { return }
            if let product = purchaseStore.product(for: id) {
                await purchaseStore.purchase(product)
            } else {
                #if DEBUG
                await MainActor.run {
                    purchaseStore.reportDebugDisplayProductTapped(id)
                }
                #endif
            }
        }
    }

    private func userMessageCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(LiminalTheme.accent)
            Text(message)
                .font(.footnote)
                .foregroundStyle(LiminalTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liminalSectionCard(padding: 14)
    }

    private var productUnavailableMessage: String {
        #if DEBUG
        "商品情報を取得できませんでした。App Store Connectの商品作成、またはXcodeのStoreKit設定を確認してください。"
        #else
        "商品情報を取得できませんでした。時間をおいてもう一度お試しください。"
        #endif
    }

    private var surfacePolicy: PurchaseSupportSurfacePolicy {
        PurchaseSupportSurfacePolicy(activationPolicy: purchaseActivationPolicy)
    }
}

#Preview("Support Tip Jar") {
    NavigationStack {
        SupportTipJarView(purchaseStore: .preview)
    }
    .liminalogPreviewEnvironment()
}
