import StoreKit
import SwiftUI
import UIKit

struct SupportLiminalogView: View {
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
        List {
            statusSection
            if shouldShowSubscriptionDisclosure {
                subscriptionDisclosureSection
            }
            productOfferContent
            legalLinksSection

            if surfacePolicy.showsStoreKitActionControls {
                restoreSection
                subscriptionManagementSection
            }

            #if DEBUG
            if let diagnostics = purchaseStore.debugProductLoadDiagnostics {
                debugProductLoadDiagnosticsSection(diagnostics)
            }
            if !purchaseConfiguration.isReadyForPaidRelease {
                debugReadinessSection
            }
            #endif
        }
        .navigationTitle("Proと応援")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard surfacePolicy.allowsStoreKitOperations else { return }
            await purchaseStore.start()
            await purchaseStore.loadProductsIfNeeded()
        }
        .refreshable {
            guard surfacePolicy.allowsStoreKitOperations else { return }
            await purchaseStore.loadProducts()
            await purchaseStore.refreshEntitlements()
        }
    }

    private var statusSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: purchaseStore.entitlements.isProActive ? "checkmark.seal.fill" : "sparkles")
                    .font(.title3)
                    .foregroundStyle(purchaseStore.entitlements.isProActive ? LiminalTheme.accent : LiminalTheme.reward)

                VStack(alignment: .leading, spacing: 4) {
                    Text(purchaseStore.entitlements.isProActive ? "Proが有効です" : "無料で利用中")
                        .font(.headline)
                        .foregroundStyle(LiminalTheme.text)
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            }
            .padding(.vertical, 4)

            if let userMessage = purchaseStore.userMessage {
                Text(userMessage)
                    .font(.footnote)
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
        } footer: {
            Text("記録、カレンダー、友達、シェアは無料のまま使えます。Proは深い分析と装飾でLiminalogを支えるための入口です。")
        }
    }

    @ViewBuilder
    private var productOfferContent: some View {
        switch surfacePolicy.productAvailability(
            hasLoadedProducts: !visibleOfferingSections.isEmpty,
            isLoadingProducts: purchaseStore.isLoadingProducts,
            hasAttemptedProductLoad: purchaseStore.hasAttemptedProductLoad
        ) {
        case .disabled:
            productDisabledSection
        case .loading:
            productLoadingSection
        case .available:
            offeringSections
        case .unavailable:
            productUnavailableSection
        }
    }

    private var productDisabledSection: some View {
        Section {
            Text("Proと応援は現在準備中です。今使える記録、カレンダー、友達、シェアの機能はそのまま利用できます。")
                .font(.footnote)
                .foregroundStyle(LiminalTheme.secondaryText)
        }
    }

    private var productLoadingSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text("商品情報を確認中")
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
            .padding(.vertical, 4)
        }
    }

    private var productUnavailableSection: some View {
        Section {
            Text(productUnavailableMessage)
                .font(.footnote)
                .foregroundStyle(LiminalTheme.secondaryText)

            Button {
                Task {
                    guard surfacePolicy.allowsStoreKitOperations else { return }
                    await purchaseStore.loadProducts()
                }
            } label: {
                Label("もう一度確認", systemImage: "arrow.clockwise")
            }
            .disabled(purchaseStore.isLoadingProducts)
        }
    }

    private var subscriptionDisclosureSection: some View {
        Section {
            Text("月額・年額のサブスクリプションはApp Storeで自動更新されます。解約や更新停止はApp Storeのサブスクリプション管理からいつでも行えます。価格、期間、無料体験の有無は購入確認画面に表示される条件が優先されます。")
                .font(.footnote)
                .foregroundStyle(LiminalTheme.secondaryText)
        } header: {
            Text("サブスクリプション")
        }
    }

    private var offeringSections: some View {
        ForEach(visibleOfferingSections) { section in
            Section {
                ForEach(section.products) { offering in
                    productButton(for: offering.id, badge: offering.badge)
                }
            } header: {
                Text(section.kind.title)
            } footer: {
                Text(section.kind.footer)
            }
        }
    }

    private var visibleOfferingSections: [PurchaseOfferingSection] {
        offeringCatalog.sections(
            for: purchaseStore.entitlements,
            availableProductIDs: Set(purchaseStore.products.map(\.id))
        )
    }

    private var shouldShowSubscriptionDisclosure: Bool {
        visibleOfferingSections.contains { section in
            section.products.contains { product in
                switch product.id.kind {
                case .proSubscription, .decorationSubscription:
                    return true
                case .lifetime, .supportTip, .premiumDecoration:
                    return false
                }
            }
        }
    }

    @ViewBuilder
    private var legalLinksSection: some View {
        let legalLinks = purchaseConfiguration.legalLinks
        if legalLinks.termsOfUseURL != nil || legalLinks.privacyPolicyURL != nil {
            Section {
                if let termsOfUseURL = legalLinks.termsOfUseURL {
                    Link(destination: termsOfUseURL) {
                        Label("利用規約", systemImage: "doc.text")
                    }
                }
                if let privacyPolicyURL = legalLinks.privacyPolicyURL {
                    Link(destination: privacyPolicyURL) {
                        Label("プライバシーポリシー", systemImage: "hand.raised")
                    }
                }
            } header: {
                Text("規約")
            }
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                Task {
                    guard surfacePolicy.allowsStoreKitOperations else { return }
                    await purchaseStore.restorePurchases()
                }
            } label: {
                Label("購入状態を復元", systemImage: "arrow.clockwise")
            }
            .disabled(purchaseStore.purchaseInProgressProductID != nil)

            if let date = purchaseStore.entitlements.lastVerifiedAt {
                LabeledContent("最終確認", value: date.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
        }
    }

    private var subscriptionManagementSection: some View {
        Section {
            Button {
                Task {
                    guard surfacePolicy.allowsStoreKitOperations else { return }
                    await purchaseStore.manageSubscriptions(in: activeWindowScene)
                }
            } label: {
                Label("サブスクリプションを管理", systemImage: "creditcard")
            }
            .disabled(purchaseStore.purchaseInProgressProductID != nil || purchaseStore.isManagingSubscriptions)
        } footer: {
            Text("解約、更新、プラン変更はApp Storeの管理画面で行います。")
        }
    }

    #if DEBUG
    private func debugProductLoadDiagnosticsSection(_ diagnostics: PurchaseProductLoadDiagnostics) -> some View {
        Section {
            LabeledContent("要求ID", value: "\(diagnostics.requestedProductIDs.count)")
            LabeledContent("取得", value: "\(diagnostics.loadedProducts.count)")
            LabeledContent("有効", value: "\(diagnostics.validProductIDs.count)")
            LabeledContent("確認時刻", value: diagnostics.recordedAt.formatted(date: .omitted, time: .standard))

            if !diagnostics.missingRequestedProductIDs.isEmpty {
                debugDiagnosticList(
                    title: "未取得ID",
                    values: diagnostics.missingRequestedProductIDs
                )
            }

            if !diagnostics.rejectedLoadedProducts.isEmpty {
                debugDiagnosticList(
                    title: "型不一致/未対応",
                    values: diagnostics.rejectedLoadedProducts.map { "\($0.id) (\($0.productTypeDescription))" }
                )
            }

            if let errorDescription = diagnostics.errorDescription {
                debugDiagnosticList(
                    title: "エラー",
                    values: [errorDescription]
                )
            }
        } header: {
            Text("StoreKit商品取得診断")
        } footer: {
            Text("DEBUGビルド限定です。取得が0件の場合は、App Store Connect商品未作成か、XcodeのStoreKit Configurationが実行時に適用されていない可能性があります。")
        }
    }

    private func debugDiagnosticList(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LiminalTheme.text)
            Text(values.joined(separator: "\n"))
                .font(.caption.monospaced())
                .foregroundStyle(LiminalTheme.secondaryText)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var debugReadinessSection: some View {
        let snapshot = purchaseConfiguration.releaseReadinessSnapshot

        return Section {
            HStack(spacing: 10) {
                Image(systemName: snapshot.hasRequiredMetadata ? "checkmark.seal" : "hourglass")
                    .font(.footnote)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.state.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                    Text("購入導線、機能制限、起動時の権利確認は別スイッチで管理しています。")
                        .font(.caption)
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
            }

            if snapshot.missingRequirements.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .frame(width: 18)

                    Text("未設定項目はありません。")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                }
            } else {
                ForEach(snapshot.missingRequirements) { requirement in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(LiminalTheme.secondaryText)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(requirement.displayName)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(LiminalTheme.text)
                            Text(requirement.resolutionHint)
                                .font(.caption)
                                .foregroundStyle(LiminalTheme.secondaryText)
                        }
                    }
                }
            }
        } header: {
            Text("課金リリース前の未設定")
        } footer: {
            Text("DEBUGビルド限定の確認です。未設定のままでも現在の無料機能には影響しません。")
        }
    }
    #endif

    private var statusDetail: String {
        if purchaseStore.entitlements.hasLifetime {
            return "ライフタイムを所有しています。"
        }
        if purchaseStore.entitlements.isProActive {
            return "サブスクリプションの購入状態を確認済みです。"
        }
        return "Proや応援は、必要になった時にいつでも確認できます。"
    }

    private var surfacePolicy: PurchaseSupportSurfacePolicy {
        PurchaseSupportSurfacePolicy(activationPolicy: purchaseActivationPolicy)
    }

    private var productUnavailableMessage: String {
        #if DEBUG
        "商品情報を取得できませんでした。App Store Connectの商品作成、またはXcodeのStoreKit設定を確認してください。"
        #else
        "商品情報を取得できませんでした。時間をおいてもう一度お試しください。"
        #endif
    }

    private var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    @ViewBuilder
    private func productButton(for id: PurchaseProductID, badge: String?) -> some View {
        if let product = purchaseStore.product(for: id) {
            Button {
                Task {
                    guard surfacePolicy.allowsStoreKitOperations else { return }
                    await purchaseStore.purchase(product)
                }
            } label: {
                productRow(
                    title: id.displayName,
                    subtitle: id.shortDescription,
                    productKind: id.kind,
                    priceText: product.displayPrice,
                    badge: badge,
                    isLoading: purchaseStore.purchaseInProgressProductID == id.rawValue
                )
            }
            .disabled(purchaseStore.purchaseInProgressProductID != nil)
        }
    }

    private func productRow(
        title: String,
        subtitle: String,
        productKind: PurchaseProductKind,
        priceText: String,
        badge: String?,
        isLoading: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LiminalTheme.text)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(LiminalTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(LiminalTheme.accent.opacity(0.12))
                            )
                    }
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(LiminalTheme.secondaryText)
                Text(productKind.displayLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
            }

            Spacer(minLength: 12)

            if isLoading {
                ProgressView()
            } else {
                Text(priceText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Support Liminalog") {
    NavigationStack {
        SupportLiminalogView(purchaseStore: .preview)
    }
    .liminalogPreviewEnvironment()
}

#Preview("Support Liminalog - Lifetime") {
    NavigationStack {
        SupportLiminalogView(
            purchaseStore: .preview(
                entitlements: PurchaseEntitlements(
                    activeProductIDs: [PurchaseProductID.lifetime.rawValue],
                    ownedNonConsumableProductIDs: [PurchaseProductID.lifetime.rawValue],
                    lastVerifiedAt: Date()
                )
            )
        )
    }
    .liminalogPreviewEnvironment()
}

#Preview("Support Liminalog - Pro") {
    NavigationStack {
        SupportLiminalogView(
            purchaseStore: .preview(
                entitlements: PurchaseEntitlements(
                    activeProductIDs: [PurchaseProductID.proYearly.rawValue],
                    ownedNonConsumableProductIDs: [],
                    lastVerifiedAt: Date()
                )
            )
        )
    }
    .liminalogPreviewEnvironment()
}
