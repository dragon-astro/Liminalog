# StoreKit Local Testing

Liminalog のローカル課金テスト準備メモ。repo 直下に `liminalog.storekit` を置き、検査スクリプトで商品IDの抜けを確認する。Xcode の StoreKit editor がファイルを更新した場合は、必ず検査を再実行してからコミットする。

## 1. StoreKit Configuration を作成する

1. repo 直下の `liminalog.storekit` を使う。
2. Xcode で `Liminalog.xcodeproj` を開く。
3. Shared scheme の Run > Options > StoreKit Configuration に `liminalog.storekit` を設定する。
4. Xcode が `.storekit` を書き換えた場合は、差分を確認してから `Scripts/validate-purchase-readiness.sh` を実行する。

`xcrun storekit` は現在の開発環境では見つからないため、CLI生成は使わない。

## 2. 登録する商品

| Product ID | 種別 | 参照価格 | Subscription Group |
|---|---|---:|---|
| `liminalog.pro.monthly` | Auto-Renewable Subscription | ¥400 | `Liminalog Pro` |
| `liminalog.pro.yearly` | Auto-Renewable Subscription | ¥2,900 | `Liminalog Pro` |
| `liminalog.lifetime` | Non-Consumable | ¥6,800 | - |
| `liminalog.decorations.monthly` | Auto-Renewable Subscription | ¥200 | `Liminalog Pro` |
| `liminalog.decorations.yearly` | Auto-Renewable Subscription | ¥1,500 | `Liminalog Pro` |
| `liminalog.support.small` | Consumable | ¥250 | - |
| `liminalog.support.medium` | Consumable | ¥600 | - |
| `liminalog.support.large` | Consumable | ¥1,200 | - |

転記元は `PurchaseProductID.appStoreConnectSpecifications`。この表だけを先に変えない。

## 3. 作成後の検査

まず App Store Connect 用メモが期待商品リストと一致しているか確認する。

```sh
swift Scripts/validate-storekit-config.swift --validate-products-doc
```

`.storekit` を更新したら、repo root で次を実行する。

```sh
swift Scripts/validate-storekit-config.swift liminalog.storekit
```

課金リリース前チェック一式として確認する場合：

```sh
Scripts/validate-purchase-readiness.sh
```

期待商品を確認したいだけなら次を使う。

```sh
swift Scripts/validate-storekit-config.swift --expected
```

スクリプトは、予定している商品IDと `Liminalog Pro` のサブスクリプショングループが StoreKit Configuration に含まれるか確認する。Xcode の内部表現が変わる可能性があるため、商品種別は確認できない場合に warning として扱う。

購入導線や機能制限の安全弁が開いていないことも確認する。

```sh
xcodebuild -project Liminalog.xcodeproj -scheme Liminalog -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" -derivedDataPath /private/tmp/LiminalogMonetizationStoreKitDerivedData -only-testing:LiminalogTests/PurchaseConfigurationTests -only-testing:LiminalogTests/PurchaseOfferingCatalogTests -only-testing:LiminalogTests/PurchaseAccessPolicyTests -only-testing:LiminalogTests/PurchaseEntitlementTests -only-testing:LiminalogTests/PurchaseRefreshPolicyTests test
```

## 4. ローカル購入テストケース

- 商品取得成功：購入画面に Pro、ライフタイム、装飾パス、支援が表示される。
- Pro月額購入：`entitlements.isProActive == true` になり、サブスク状態として表示される。
- Pro年額購入：月額と同じ Pro 権利になる。
- ライフタイム購入：`hasLifetime == true` になり、Pro権利は永続扱いになる。
- 装飾パス購入：`hasDecorationRental == true` になり、Pro機能権利とは分離される。
- 支援チップ購入：権利を恒久付与せず、購入完了メッセージだけ表示される。
- 復元なし：エラーではなく、復元できる購入がない状態として扱う。
- 復元あり：ライフタイムやサブスクの権利が再読込される。
- サブスク期限切れ：Pro/装飾レンタル権が外れる。
- 商品種別不一致：アプリ側の商品候補と権利キャッシュから外れる。

## 5. Release への接続条件

StoreKit ローカル購入テストが通っても、次が揃うまでは Release の購入導線は開かない。

- App Store Connect の商品IDと商品種別を確認する。
- `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` を true にする。
- `PurchaseConfiguration.current.subscriptionGroupName` に `Liminalog Pro` を設定する。
- 利用規約本文を承認し、`termsOfUseURL` に HTTPS URL を設定する。
- その後で初めて `purchaseEntryPointIsEnabled` を true にする。
- 既存機能のPro制限はさらに別チェックポイントで `featureRestrictionsAreEnabled` を true にする。
