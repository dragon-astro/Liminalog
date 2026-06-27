import SwiftUI

struct StatisticsTabContent: View {
    let purchaseStore: PurchaseStore
    var accessPolicy = StatisticsTabAccessPolicy()
    #if DEBUG
    @AppStorage(StatisticsTabDebugAccess.enforceFeatureRestrictionsKey) private var debugEnforcesFeatureRestrictions = false
    #endif

    var body: some View {
        switch effectiveAccessPolicy.destination(entitlements: purchaseStore.entitlements) {
        case .dashboard:
            DashboardView()
        case .proPreview:
            StatisticsProPreviewView(purchaseStore: purchaseStore)
        }
    }

    private var effectiveAccessPolicy: StatisticsTabAccessPolicy {
        #if DEBUG
        if debugEnforcesFeatureRestrictions {
            return StatisticsTabDebugAccess.forcedFeatureRestrictionsPolicy
        }
        #endif
        return accessPolicy
    }
}

struct StatisticsProPreviewView: View {
    let purchaseStore: PurchaseStore

    var body: some View {
        ZStack {
            LiminalTheme.canvasGradient.ignoresSafeArea()

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        insightGrid
                        freeScopeNote
                        NavigationLink {
                            SupportLiminalogView(purchaseStore: purchaseStore)
                        } label: {
                            Label("Proと応援を見る", systemImage: "sparkles")
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(LiminalTheme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 96)
                }
                .scrollClipDisabled()
                .navigationTitle("統計")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Pro")
                    .font(.subheadline.weight(.bold))
            } icon: {
                Image(systemName: "sparkles")
            }
            .foregroundStyle(LiminalTheme.reward)

            Text("記録の流れを、もう少し深く見る。")
                .font(.title2.weight(.bold))
                .foregroundStyle(LiminalTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("週・月・年の傾向、カテゴリの偏り、時間帯のリズム、予定との差分をまとめて確認できます。")
                .font(.subheadline)
                .foregroundStyle(LiminalTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LiminalTheme.divider.opacity(0.55), lineWidth: 1)
        }
    }

    private var insightGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatisticsPreviewTile(title: "傾向", systemImage: "chart.line.uptrend.xyaxis", tint: LiminalTheme.accent)
            StatisticsPreviewTile(title: "カテゴリ", systemImage: "square.grid.2x2.fill", tint: Color(hex: "#5FE0A8"))
            StatisticsPreviewTile(title: "時間帯", systemImage: "clock.fill", tint: Color(hex: "#F2994A"))
            StatisticsPreviewTile(title: "予定差分", systemImage: "target", tint: Color(hex: "#8AB4FF"))
        }
    }

    private var freeScopeNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.headline)
                .foregroundStyle(LiminalTheme.accent)
            Text("今日のスコア、ストリーク、デイリーカード、カレンダーは無料のまま使えます。")
                .font(.footnote)
                .foregroundStyle(LiminalTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(LiminalTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LiminalTheme.divider.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct StatisticsPreviewTile: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: Circle())

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(LiminalTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LiminalTheme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LiminalTheme.divider.opacity(0.5), lineWidth: 1)
        }
    }
}

#Preview("Statistics Pro Preview") {
    StatisticsProPreviewView(purchaseStore: .preview)
        .liminalogPreviewEnvironment()
}
