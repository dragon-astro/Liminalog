# Purchase Release Checklist

課金導線を Release に出す前のチェックリスト。Liminalog は既にリリース済みなので、購入導線と機能制限は段階を分けて入れる。

現在の達成状況は `AppStore/PurchaseReadinessAudit.md` を見る。このチェックリストは次のGateへ進める時の手順、監査表は現時点で何が未完了かの証跡として使う。

## Current Safety State

`PurchaseConfiguration.current` は次の状態を維持する。

- `termsOfUseURL == https://liminalog-lp.vercel.app/terms`
- `productIDsAreConfirmedForAppStoreConnect == false`
- `subscriptionGroupName == nil`
- `purchaseEntryPointIsEnabled == false`
- `featureRestrictionsAreEnabled == false`
- `backgroundEntitlementRefreshIsEnabled == false`
- 単品プレミアム装飾は `PurchaseConfiguration.current.productIDs` / `liminalog.storekit` / プロフィール装飾UIへまだ接続しない

この状態では、Releaseビルドで購入導線、StoreKit商品取得、既存機能のPro制限、起動時権利更新は動かない。

## Gate 1: Metadata Ready

目的：App Store Connect と法務URLの準備だけ完了させる。ユーザーにはまだ購入導線を出さない。

必要条件：

- `AppStore/PurchaseProducts.md` の商品が App Store Connect に作成済み。
- `AppStore/AppStoreConnectProductSetup.md` を転記元として作成し、`Scripts/validate-purchase-readiness.sh` が成功している。
- `AppStore/AppStoreConnectProductRunbook.md` の Creation Order と Stop Conditions に沿って作成している。
- `Liminalog Pro` の Subscription Group が作成済み。
- `AppStore/AppStoreConnectProductConfirmation.md` の全チェックが埋まり、`swift Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-complete` が成功している。
- 利用規約本文が承認済み。
- `https://liminalog-lp.vercel.app/terms` が公開済み。
- `https://liminalog-lp.vercel.app/privacy` が公開済み。
- ローカル `liminalog.storekit` が作成済み。
- `swift Scripts/validate-storekit-config.swift liminalog.storekit` が成功。

アプリ側変更：

```swift
productIDsAreConfirmedForAppStoreConnect: true
subscriptionGroupName: "Liminalog Pro"
legalLinks: PurchaseLegalLinks(
    termsOfUseURL: URL(string: "https://liminalog-lp.vercel.app/terms"),
    privacyPolicyURL: URL(string: "https://liminalog-lp.vercel.app/privacy")
)
purchaseEntryPointIsEnabled: false
featureRestrictionsAreEnabled: false
backgroundEntitlementRefreshIsEnabled: false
```

期待状態：

- `PurchaseConfiguration.current.releaseReadinessSnapshot.state == .metadataReadyWaitingForGoLive`
- Releaseビルドで既存UIは変わらない。
- 統計タブ、カテゴリセット、カレンダー、友達、デイリーカードは既存通り。

検証：

```sh
Scripts/prepare-purchase-gate1-code-change.sh
Scripts/validate-purchase-readiness.sh --gate1-ready
xcodebuild -project Liminalog.xcodeproj -scheme Liminalog -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" build-for-testing -only-testing:LiminalogTests/PurchaseConfigurationTests
```

`prepare-purchase-gate1-code-change.sh` は、App Store Connect確認表が完了していて、コード変更前のRelease gateがまだclosedであることを確認する。`--gate1-ready` は `PurchaseConfiguration.current` が Gate 1 のメタデータ準備済み状態であることも検査する。通常時の closed 状態検査ではない。

## Gate 2: Purchase Entry Point

目的：設定内に購入導線を出し、StoreKit操作を可能にする。既存機能の制限はまだ入れない。

必要条件：

- Gate 1 が通っている。
- StoreKitローカル購入テストが成功している。
- `AppStore/PurchaseUIQA.md` の Gate 2 Purchase UI QA Evidence Sheet が埋まり、DEBUG / Release / Local StoreKit 確認が通っている。
- Product取得失敗時の文言が自然。
- 復元、サブスク管理、購入キャンセルの挙動を確認済み。

アプリ側変更：

```swift
purchaseEntryPointIsEnabled: true
featureRestrictionsAreEnabled: false
backgroundEntitlementRefreshIsEnabled: true
```

期待状態：

- `releaseReadinessSnapshot.state == .purchaseEntryPointReady`
- 設定に「Proと応援」が出る。
- 既存の無料機能はロックされない。
- 統計タブは既存通り表示される。

検証：

- Release build 成功。
- DEBUG StoreKit Configuration で商品取得成功。
- `AppStore/PurchaseUIQA.md` に沿った購入/復元/管理画面の手動QA。
- `Scripts/validate-purchase-readiness.sh --gate2-ready` が成功。
- 既存タブのスモーク確認。

`--gate2-ready` は Gate 1 条件に加えて、購入導線ON、機能制限OFF、起動時/復帰時の権利更新ON、Local StoreKit QA証跡、Purchase UI QA証跡を検査する。

## Gate 3: Feature Restrictions

目的：統計タブなど、Pro対象機能の制限を初めて有効化する。

必要条件：

- Gate 2 が通っている。
- `19-statistics-pro-gate.md` の設計に沿って、無料時に `DashboardPeriodContent` が構築されない。
- 無料ユーザーの過去データ閲覧、当日スコア、ストリーク、デイリーカード、友達、カレンダー閲覧が維持されている。
- Proサブ、ライフタイム、装飾パスのみ、無料の4状態で分岐確認済み。

アプリ側変更：

```swift
featureRestrictionsAreEnabled: true
```

期待状態：

- `releaseReadinessSnapshot.state == .featureRestrictionsReady`
- Proサブ/ライフタイムは統計タブを見られる。
- 無料/装飾パスのみは統計Pro案内になる。
- 購入導線は `SupportLiminalogView` に統一される。

検証：

- `PurchaseAccessPolicyTests`
- `PurchaseConfigurationTests`
- 統計タブ入口の回帰テスト
- `Scripts/validate-purchase-readiness.sh --gate3-ready` が成功。
- Release build
- 実機QA

`--gate3-ready` は Gate 2 条件に加えて、機能制限ONの状態を検査する。

## Rollback

問題が出た時は、機能制限から順に閉じる。

1. `featureRestrictionsAreEnabled = false`
2. `purchaseEntryPointIsEnabled = false`
3. `backgroundEntitlementRefreshIsEnabled = false`

メタデータ設定だけ残しても、購入導線が false なら Release の既存機能は変わらない。
