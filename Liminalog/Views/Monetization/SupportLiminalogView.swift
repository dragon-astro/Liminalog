import StoreKit
import SwiftUI
import UIKit

struct SupportLiminalogView: View {
    let purchaseStore: PurchaseStore
    var purchaseConfiguration: PurchaseConfiguration
    var purchaseActivationPolicy: PurchaseActivationPolicy
    private let offeringCatalog = PurchaseOfferingCatalog()
    @State private var selectedPlanID: PurchaseProductID?

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
                    paywallContent
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        // カードが画面の残り高さを吸収し、1画面を使い切るレイアウトにする
                        .frame(minHeight: proxy.size.height)
                }
                .refreshable {
                    guard surfacePolicy.allowsStoreKitOperations else { return }
                    await purchaseStore.loadProducts()
                    await purchaseStore.refreshEntitlements()
                }
            }
        }
        .navigationTitle("Liminalog Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard surfacePolicy.allowsStoreKitOperations else { return }
            await purchaseStore.start()
            await purchaseStore.loadProductsIfNeeded()
        }
    }

    /// スクロール中身。ImageRenderer が ScrollView 内を描画できないため、
    /// レンダラテスト（SupportLiminalogRenderTests）からも直接参照する。
    var paywallContent: some View {
        VStack(spacing: 16) {
            offerCard

            if let userMessage = purchaseStore.userMessage {
                userMessageCard(userMessage)
            }

            if availability != .disabled {
                tipJarLink
            }

            finePrint

            #if DEBUG
            if let diagnostics = purchaseStore.debugProductLoadDiagnostics {
                debugProductLoadDiagnosticsCard(diagnostics)
            }
            if !purchaseConfiguration.isReadyForPaidRelease {
                debugReadinessCard
            }
            #endif
        }
    }

    // MARK: - Offer card（1枚の完成品）

    private var offerCard: some View {
        VStack(spacing: 0) {
            cardHeader
            Spacer(minLength: 24)
            cardBody
            if availability != .available {
                Spacer(minLength: 24)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paywallOfferCard()
    }

    private var cardHeader: some View {
        VStack(spacing: 8) {
            Label {
                Text(heroEyebrow)
                    .font(.subheadline.weight(.bold))
            } icon: {
                Image(systemName: heroIcon)
            }
            .foregroundStyle(heroTint)

            Text(heroHeadline)
                .font(.title2.weight(.bold))
                .foregroundStyle(LiminalTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let heroSubtitle {
                Text(heroSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 6)
    }

    private var heroEyebrow: String {
        if purchaseStore.entitlements.hasLifetime { return "買い切り所有" }
        if purchaseStore.entitlements.isProActive { return "Pro有効" }
        return "Liminalog Pro"
    }

    private var heroIcon: String {
        purchaseStore.entitlements.isProActive ? "checkmark.seal.fill" : "sparkles"
    }

    private var heroTint: Color {
        purchaseStore.entitlements.isProActive ? LiminalTheme.accent : LiminalTheme.reward
    }

    private var heroHeadline: String {
        if purchaseStore.entitlements.hasLifetime { return "Pro機能を所有しています" }
        if purchaseStore.entitlements.isProActive { return "Proが有効です" }
        return "その日々を、もっと深く。"
    }

    private var heroSubtitle: String? {
        if purchaseStore.entitlements.hasLifetime { return "一度きりの応援を、ありがとうございます。" }
        if purchaseStore.entitlements.isProActive { return "いつもありがとうございます。" }
        return nil
    }

    // MARK: - Card body

    private var availability: PurchaseProductAvailability {
        surfacePolicy.productAvailability(
            hasLoadedProducts: !visibleOfferingSections.isEmpty,
            isLoadingProducts: purchaseStore.isLoadingProducts,
            hasAttemptedProductLoad: purchaseStore.hasAttemptedProductLoad
        )
    }

    @ViewBuilder
    private var cardBody: some View {
        switch availability {
        case .disabled:
            Text("Proと応援は現在準備中です。今使える記録、カレンダー、友達、シェアの機能はそのまま利用できます。")
                .font(.footnote)
                .foregroundStyle(LiminalTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("商品情報を確認中")
                    .font(.footnote)
                    .foregroundStyle(LiminalTheme.secondaryText)
            }
        case .available:
            availableBody
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

    @ViewBuilder
    private var availableBody: some View {
        // 余白は「見出し→機能」（offerCard側のSpacer）と「機能→プラン」の2箇所に分散して伸ばす
        VStack(spacing: 0) {
            if showsProFeatureIntro {
                featureChecklist
            }

            if showsDecorationPassIntro {
                checkRow("プレミアム装飾が契約中ずっと使い放題")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !planOfferings.isEmpty {
                Spacer(minLength: 22)

                VStack(spacing: 14) {
                    planList

                    VStack(spacing: 8) {
                        ctaButton

                        if let selectedID = effectiveSelectedPlanID, let terms = ctaTermsText(for: selectedID) {
                            Text(terms)
                                .font(.caption2)
                                .foregroundStyle(LiminalTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if showsProFeatureIntro {
                Text("記録・カレンダー・友達・シェアは、ずっと無料。")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
    }

    private static let proFeatures: [(icon: String, title: String)] = [
        ("chart.line.uptrend.xyaxis", "週・月・年の統計タブをまるごと"),
        ("square.grid.2x2.fill", "記録ボード無制限"),
        ("paintpalette.fill", "プレミアム装飾 使い放題"),
        ("sparkles", "エクスポートなど今後の機能もすべて")
    ]

    private var featureChecklist: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                PaywallStatsPreview()

                Text("時間の使い方が、ひと目で見える。")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LiminalTheme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.proFeatures, id: \.title) { feature in
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LiminalTheme.accent)
                            .frame(width: 26)

                        Text(feature.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(LiminalTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checkRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(LiminalTheme.accent)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(LiminalTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var visibleOfferingSections: [PurchaseOfferingSection] {
        offeringCatalog.sections(
            for: purchaseStore.entitlements,
            availableProductIDs: Set(purchaseStore.displayProducts.map(\.id))
        )
    }

    private var planOfferings: [PaywallPlanOffering] {
        visibleOfferingSections
            .filter { $0.kind != .support }
            .flatMap(\.products)
            .compactMap { product in
                guard let displayProduct = purchaseStore.displayProduct(for: product.id) else { return nil }
                return PaywallPlanOffering(id: product.id, badge: product.badge, priceText: displayProduct.displayPrice)
            }
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

    private var showsProFeatureIntro: Bool {
        visibleOfferingSections.contains { $0.kind == .pro }
    }

    private var showsDecorationPassIntro: Bool {
        visibleOfferingSections.contains { $0.kind == .decorationPass }
    }

    // MARK: - Plan list

    private var planList: some View {
        VStack(spacing: 2) {
            ForEach(planOfferings) { offering in
                PaywallPlanListRow(
                    title: planTitle(for: offering.id),
                    subText: planListSubtext(for: offering.id),
                    badgeText: planSavingText(for: offering.id),
                    priceText: offering.priceText,
                    priceSuffix: planPriceSuffix(for: offering.id),
                    isSelected: offering.id == effectiveSelectedPlanID
                ) {
                    selectedPlanID = offering.id
                }
            }
        }
    }

    private var effectiveSelectedPlanID: PurchaseProductID? {
        let ids = planOfferings.map(\.id)
        if let selectedPlanID, ids.contains(selectedPlanID) {
            return selectedPlanID
        }
        return planOfferings.first { $0.badge != nil }?.id ?? ids.first
    }

    @ViewBuilder
    private var ctaButton: some View {
        if let selectedID = effectiveSelectedPlanID {
            Button {
                purchase(selectedID)
            } label: {
                ZStack {
                    Text(ctaTitle(for: selectedID))
                        .font(.headline.weight(.bold))
                        .opacity(purchaseStore.purchaseInProgressProductID == selectedID.rawValue ? 0 : 1)
                    if purchaseStore.purchaseInProgressProductID == selectedID.rawValue {
                        ProgressView()
                            .tint(LiminalTheme.canvas)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                // ダークではaccentが淡色になるため、白固定でなくcanvas（暗地）を文字色に使いコントラストを確保する
                .foregroundStyle(LiminalTheme.canvas)
                .background(LiminalTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(purchaseStore.purchaseInProgressProductID != nil)
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

    private func planTitle(for id: PurchaseProductID) -> String {
        switch id {
        case .proYearly, .decorationYearly:
            "年ごと"
        case .proMonthly, .decorationMonthly:
            "月ごと"
        case .lifetime:
            "買い切り"
        default:
            id.displayName
        }
    }

    private func planListSubtext(for id: PurchaseProductID) -> String? {
        switch id {
        case .proYearly:
            perMonthEquivalentText(yearly: .proYearly) ?? "月々¥242"
        case .decorationYearly:
            perMonthEquivalentText(yearly: .decorationYearly) ?? "月々¥125"
        case .lifetime:
            "装飾の使い放題は含まれません"
        default:
            nil
        }
    }

    private func ctaTermsText(for id: PurchaseProductID) -> String? {
        guard let offering = planOfferings.first(where: { $0.id == id }) else { return nil }
        let price = offering.priceText
        switch id {
        case .proYearly:
            return "7日間の無料体験のあとは \(price)/年。いつでも解約できます。"
        case .proMonthly:
            return "\(price)/月。いつでも解約できます。"
        case .lifetime:
            return "一回払いの \(price)。装飾の使い放題は含まれません。"
        case .decorationYearly:
            return "\(price)/年。いつでも解約できます。"
        case .decorationMonthly:
            return "\(price)/月。いつでも解約できます。"
        default:
            return nil
        }
    }

    private func planSavingText(for id: PurchaseProductID) -> String? {
        switch id {
        case .proYearly:
            savingsText(yearly: .proYearly, monthly: .proMonthly, fallbackPercent: 40)
        case .decorationYearly:
            savingsText(yearly: .decorationYearly, monthly: .decorationMonthly, fallbackPercent: 38)
        default:
            nil
        }
    }

    private func savingsText(yearly: PurchaseProductID, monthly: PurchaseProductID, fallbackPercent: Int) -> String {
        if let percent = storeKitSavingsPercent(yearly: yearly, monthly: monthly) {
            return "\(percent)%オフ"
        }
        // StoreKit未取得時は参照価格（PurchaseProductID.referencePriceText）由来の値
        return "\(fallbackPercent)%オフ"
    }

    private func storeKitSavingsPercent(yearly: PurchaseProductID, monthly: PurchaseProductID) -> Int? {
        guard
            let yearlyProduct = purchaseStore.product(for: yearly),
            let monthlyProduct = purchaseStore.product(for: monthly)
        else { return nil }
        let annualizedMonthly = monthlyProduct.price * 12
        guard annualizedMonthly > 0, yearlyProduct.price < annualizedMonthly else { return nil }
        let ratio = NSDecimalNumber(decimal: yearlyProduct.price / annualizedMonthly).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded())
        return percent > 0 ? percent : nil
    }

    private func perMonthEquivalentText(yearly: PurchaseProductID) -> String? {
        guard let product = purchaseStore.product(for: yearly) else { return nil }
        var perMonth = product.price / 12
        var rounded = Decimal()
        NSDecimalRound(&rounded, &perMonth, 0, .plain)
        return "月々" + product.priceFormatStyle.format(rounded)
    }

    private func planPriceSuffix(for id: PurchaseProductID) -> String? {
        switch id {
        case .proYearly, .decorationYearly:
            "/年"
        case .proMonthly, .decorationMonthly:
            "/月"
        default:
            nil
        }
    }

    private func ctaTitle(for id: PurchaseProductID) -> String {
        switch id {
        case .proYearly:
            "7日間無料で試す"
        case .proMonthly:
            "Proを始める"
        case .lifetime:
            "購入する"
        case .decorationMonthly, .decorationYearly:
            "装飾パスを始める"
        default:
            "購入する"
        }
    }

    // MARK: - Below card

    private var tipJarLink: some View {
        NavigationLink {
            SupportTipJarView(
                purchaseStore: purchaseStore,
                purchaseConfiguration: purchaseConfiguration,
                purchaseActivationPolicy: purchaseActivationPolicy
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.reward)
                Text("開発を応援")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LiminalTheme.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiminalTheme.tertiaryText)
            }
        }
        .buttonStyle(.plain)
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

    private var finePrint: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                if surfacePolicy.showsStoreKitActionControls {
                    Button("復元") {
                        Task {
                            guard surfacePolicy.allowsStoreKitOperations else { return }
                            await purchaseStore.restorePurchases()
                        }
                    }
                    .disabled(purchaseStore.purchaseInProgressProductID != nil)

                    Button("サブスク管理") {
                        Task {
                            guard surfacePolicy.allowsStoreKitOperations else { return }
                            await purchaseStore.manageSubscriptions(in: activeWindowScene)
                        }
                    }
                    .disabled(purchaseStore.purchaseInProgressProductID != nil || purchaseStore.isManagingSubscriptions)
                }

                if let termsOfUseURL = purchaseConfiguration.legalLinks.termsOfUseURL {
                    Link("利用規約", destination: termsOfUseURL)
                }
                if let privacyPolicyURL = purchaseConfiguration.legalLinks.privacyPolicyURL {
                    Link("プライバシー", destination: privacyPolicyURL)
                }
            }
            .font(.caption)
            .foregroundStyle(LiminalTheme.secondaryText)
            .buttonStyle(.plain)

            if shouldShowSubscriptionDisclosure {
                Text("サブスクリプションはApp Storeで自動更新されます。解約はApp Storeの管理画面からいつでも。価格や無料体験は購入時の表示が優先されます。")
                    .font(.caption2)
                    .foregroundStyle(LiminalTheme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            #if DEBUG
            if let date = purchaseStore.entitlements.lastVerifiedAt {
                Text("購入状態の最終確認 \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(LiminalTheme.tertiaryText)
            }
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    // MARK: - DEBUG

    #if DEBUG
    private func debugCard(
        header: String,
        footer: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiminalTheme.secondaryText)

            content()

            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(LiminalTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liminalSectionCard(padding: 14)
    }

    private func debugProductLoadDiagnosticsCard(_ diagnostics: PurchaseProductLoadDiagnostics) -> some View {
        debugCard(
            header: "StoreKit商品取得診断",
            footer: "DEBUGビルド限定です。取得が0件の場合は、App Store Connect商品未作成か、XcodeのStoreKit Configurationが実行時に適用されていない可能性があります。"
        ) {
            LabeledContent("要求ID", value: "\(diagnostics.requestedProductIDs.count)")
            LabeledContent("取得", value: "\(diagnostics.loadedProducts.count)")
            LabeledContent("有効", value: "\(diagnostics.validProductIDs.count)")
            LabeledContent("確認時刻", value: diagnostics.recordedAt.formatted(date: .omitted, time: .standard))
            debugDiagnosticList(
                title: "証跡",
                values: [diagnostics.evidenceLine]
            )

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

    private var debugReadinessCard: some View {
        let snapshot = purchaseConfiguration.releaseReadinessSnapshot

        return debugCard(
            header: "課金リリース前の未設定",
            footer: "DEBUGビルド限定の確認です。未設定のままでも現在の無料機能には影響しません。"
        ) {
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
        }
    }
    #endif

    // MARK: - Helpers

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
}

// MARK: - Shared paywall pieces

struct PaywallPlanOffering: Equatable, Identifiable {
    var id: PurchaseProductID
    var badge: String?
    var priceText: String
}

/// 課金面の「1枚カード」共通背景。黄昏の空（dusk→surface）＋アクセントの微グロー。
/// ダークでは星を少し散らし、ライト（曙）では暖かいグローだけにする。
struct PaywallOfferCardShell: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    LiminalTheme.surface

                    LinearGradient(
                        colors: [
                            LiminalTheme.dusk.opacity(scheme == .dark ? 0.5 : 0.28),
                            Color.clear,
                            LiminalTheme.dawn.opacity(scheme == .dark ? 0.12 : 0.22)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    RadialGradient(
                        colors: [LiminalTheme.accent.opacity(scheme == .dark ? 0.2 : 0.14), .clear],
                        center: .init(x: 0.85, y: 0.05),
                        startRadius: 8,
                        endRadius: 300
                    )

                    if scheme == .dark {
                        PaywallStarField()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(LiminalTheme.divider.opacity(0.6), lineWidth: 1)
            }
    }
}

extension View {
    func paywallOfferCard() -> some View {
        modifier(PaywallOfferCardShell())
    }
}

/// Proの主役（統計）を示す最小限のモチーフ。データを主張しない抽象バー5本のみ
/// （ラベル・強調色・枠を持たせず、認知負荷を上げない）。
struct PaywallStatsPreview: View {
    private static let bars: [CGFloat] = [0.35, 0.6, 0.45, 0.75, 1.0]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LiminalTheme.accent.opacity(0.4 + 0.15 * Double(index)))
                    .frame(width: 22, height: 48 * height)
            }
        }
        .frame(height: 48, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// カード上部にだけ散らす小さな星。位置は固定（ちらつかせない）。
private struct PaywallStarField: View {
    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.10, 0.05, 2.1, 0.5),
        (0.22, 0.12, 1.4, 0.35),
        (0.36, 0.04, 1.7, 0.45),
        (0.55, 0.09, 1.3, 0.3),
        (0.68, 0.03, 2.0, 0.5),
        (0.80, 0.13, 1.4, 0.35),
        (0.92, 0.07, 1.6, 0.4)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                Circle()
                    .fill(Color.white.opacity(star.opacity))
                    .frame(width: star.size, height: star.size)
                    .position(x: proxy.size.width * star.x, y: proxy.size.height * star.y)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PaywallPlanListRow: View {
    let title: String
    let subText: String?
    let badgeText: String?
    let priceText: String
    let priceSuffix: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? LiminalTheme.accent : LiminalTheme.tertiaryText)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(LiminalTheme.text)
                        if let badgeText {
                            Text(badgeText)
                                .font(.caption.weight(.heavy))
                                // 一番効く情報なので、金の塗りカプセルで主張させる
                                .foregroundStyle(LiminalTheme.canvas)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule(style: .continuous).fill(LiminalTheme.reward))
                        }
                    }
                    if let subText {
                        Text(subText)
                            .font(.caption)
                            .foregroundStyle(LiminalTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 8)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(priceText)
                        .font(.body.weight(.bold))
                        .foregroundStyle(LiminalTheme.text)
                    if let priceSuffix {
                        Text(priceSuffix)
                            .font(.caption)
                            .foregroundStyle(LiminalTheme.secondaryText)
                    }
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LiminalTheme.accent.opacity(0.13))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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
