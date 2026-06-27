# 19. 統計タブ Pro 化設計

統計タブを Pro 対象にする時の設計メモ。`StatisticsProPreviewView` と `RootTabView` の入口分岐は追加済み。ただし `featureRestrictionsAreEnabled == false` の間は既存ユーザー体験を変えず、統計タブは従来通り表示する。

## ゴール

- 統計タブは **タブとして残す**。無料ユーザーにも「統計がある」ことは見える。
- 無料ユーザーで制限が有効な時は、統計の重い集計を走らせず、軽い Pro 案内だけを表示する。
- 当日スコア、ストリーク、デイリーカード、カレンダー上の自分の過去データ閲覧は無料のままにする。
- `purchaseEntryPointIsEnabled` と `featureRestrictionsAreEnabled` を別チェックポイントにし、購入導線を開いただけで既存統計をロックしない。

## 現状コードの前提

- `RootTabView` は `StatisticsTabContent` を統計タブに置き、許可時だけ `DashboardView()` を構築する。
- `DashboardView` は選択中の期間だけ `DashboardPeriodContent` を構築する。これは過去のタブ切り替え重さ対策なので維持する。
- `DashboardPeriodContent` は `@Query` で `Chapter` / `PlanBlock` / `UserSettings` を読む。ロック画面でこれを構築すると、無料ユーザーにも統計集計コストが発生する。
- `StatisticsTabAccessPolicy` が `PurchaseFeatureGate.decision(for: .statisticsTab, entitlements:)` を使い、`dashboard / proPreview` を決める。
- `PurchaseActivationPolicy.shouldEnforceFeatureRestrictions` が false の間は、すべての機能判定が無料扱いになる。

## 推奨構造

### 1. RootTabView で入口を分岐する

`DashboardView` の内部でロックするのではなく、`RootTabView` の統計タブ入口で分岐する。

実装済み：

- `StatisticsTabContent(purchaseStore:)`
- `StatisticsTabAccessPolicy`
- `StatisticsProPreviewView`

理由：

- ロック時に `DashboardPeriodContent` の `@Query` を作らない。
- 統計側のカード構成やカスタマイズUIに課金分岐を混ぜない。
- 将来、無料プレビューや24時間解放を足す時も入口だけ差し替えられる。

擬似コード：

```swift
let gate = PurchaseFeatureGate(activationPolicy: .current())
let decision = gate.decision(
    for: .statisticsTab,
    entitlements: appStores.purchaseStore.entitlements
)

if decision.isAllowed {
    DashboardView()
} else {
    StatisticsProPreviewView()
}
```

### 2. ロック画面は軽くする

`StatisticsProPreviewView` は SwiftData の `@Query` を持たない。表示内容は固定文言と購入導線だけにする。

置くもの：

- Liminalog の静かな背景。
- 「統計」タブの価値が一目でわかる短い見出し。
- Proで見られるもの：週/月/年の傾向、カテゴリ比率、時間帯リズム、計画との差分。
- 主要アクション：`SupportLiminalogView` へ遷移。
- 補助：無料のまま残るものを短く明示する。

置かないもの：

- 実データのぼかし表示。
- 重いチャートのダミー生成。
- デイリーカードや過去データ閲覧を人質に見せる文言。
- 別のペイウォール実装。

### 3. 購入導線との接続

購入画面は `SupportLiminalogView` に寄せる。統計タブ専用の購入ロジックを増やさない。

- `purchaseEntryPointIsEnabled == false` の Release では、そもそも `featureRestrictionsAreEnabled` も false にしておく。
- `featureRestrictionsAreEnabled == true` にする時は、同じリリースで `purchaseEntryPointIsEnabled == true`、利用規約URL、App Store Connect 商品確定が揃っていることを前提にする。
- DEBUG では設定の「Pro制限を試す」と「課金状態を試す」を組み合わせ、無料/Pro/ライフタイム/装飾パスの表示を確認する。起動直後の統計タブを確認したい時は `-LiminalogDebugPurchaseState pro|lifetime|lifetimeWithDecorationPass|decorationPassOnly` を使う。

### 4. カスタマイズUIの扱い

統計がロックされている時は、統計カード編集ボタンを出さない。

理由：

- カード編集は統計画面の一部であり、ロック中に編集できても意味が薄い。
- `DashboardCustomizeSheet` が `UserSettings` を読むため、ロック時の軽量化と矛盾する。

### 5. リワード広告は後回し

統計24時間解放は方針として残すが、最初のPro化実装には入れない。

入れる時は別の権利状態を足す。

- `PurchaseEntitlements` に混ぜない。
- `StatisticsPreviewEntitlement` のような短期ローカル権利を別で持つ。
- 期限切れ時に過去データそのものへアクセスできなくなるような見せ方はしない。

## テスト観点

- Release未準備：`PurchaseConfiguration.current` のままなら統計タブは既存通り表示される。
- 購入導線ONのみ：`purchaseEntryPointIsEnabled == true` でも `featureRestrictionsAreEnabled == false` なら統計タブは既存通り表示される。
- 機能制限ON + 無料：統計タブはロック画面になり、`DashboardPeriodContent` は構築されない。
- 機能制限ON + Proサブ：統計タブは既存通り表示される。
- 機能制限ON + ライフタイム：統計タブは既存通り表示される。
- 機能制限ON + 装飾パスのみ：統計タブはロック画面になる。
- ロック画面から購入画面に遷移しても、購入導線が無効なReleaseではStoreKit操作が走らない。

## 実装順

1. [x] `StatisticsProPreviewView` を軽量な独立Viewとして作る。
2. [x] `RootTabView` の統計タブ入口で `PurchaseFeatureGate` を見る。
3. [x] ロック時の入口が `proPreview` になり、現行Releaseでは `dashboard` のままであることをテストする。
4. [x] DEBUG で `Pro制限を試す` をONにできる確認導線を作る。
5. [x] DEBUG の課金状態を起動時に注入できる確認導線を作る。
6. DEBUG の課金状態切替で無料/Pro/ライフタイム/装飾パスを目視確認する。
7. Release build で `featureRestrictionsAreEnabled == false` の時に既存統計が変わらないことを確認する。

## QAメモ

- 2026-06-27: XcodeBuildMCP / iPhone 17 Pro Simulator / Debug で `debug.purchase.enforceFeatureRestrictions = true`、`-LiminalogInitialRootTab dashboard` を指定して起動し、無料状態で `StatisticsProPreviewView` が表示されることを確認した。確認後、同フラグは `false` に戻した。
- 2026-06-27: DEBUG 限定で `-LiminalogDebugPurchaseState` / `LiminalogDebugPurchaseState` を追加。設定画面の手動メニューと同じ `applyDebugEntitlementsOverride` を起動時に呼ぶだけなので、Release や実購入キャッシュには影響しない。
- 2026-06-27: XcodeBuildMCP / iPhone 17 Pro Simulator / Debug で `debug.purchase.enforceFeatureRestrictions = true`、`-LiminalogInitialRootTab dashboard` と `-LiminalogDebugPurchaseState pro` を指定して統計本体、`decorationPassOnly` を指定して `StatisticsProPreviewView` が表示されることを確認した。確認後、同フラグは `false` に戻した。

## やらないこと

- 統計タブを非表示にする。
- 既存のデータ閲覧をロックする。
- `DashboardPeriodContent` 内に課金分岐を散らす。
- StoreKit商品取得や復元処理を統計タブ専用に持つ。
- 利用規約未確定、App Store Connect未確定の状態でRelease導線を開く。
