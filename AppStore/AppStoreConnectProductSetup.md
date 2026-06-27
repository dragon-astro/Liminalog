# App Store Connect Product Setup

App Store Connect で Liminalog の課金商品を作る時の転記シート。作成作業中に商品名、ID、種別、価格、グループのズレを出さないためのもの。

このファイルは作成前の入力値を固定するために使う。作成後の証跡は `AppStore/AppStoreConnectProductConfirmation.md` に残す。

## Safety Rules

- App Store Connect で商品を作成しても、確認表が埋まるまで `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` は `false` のままにする。
- Gate 1 では `purchaseEntryPointIsEnabled` と `featureRestrictionsAreEnabled` を `false` のままにする。
- 単品プレミアム装飾は別枠候補として温存し、初回の `PurchaseConfiguration.current.productIDs` と `liminalog.storekit` には入れない。
- 年額 Pro の無料体験は未確定。付ける場合は App Store Connect、アプリ内文言、QA表を同時に更新する。
- 支援チップは権利付与なしの Consumable として扱う。

## Subscription Group

| Field | Value |
|---|---|
| Reference Name | `Liminalog Pro` |
| Purpose | Proサブと装飾パスを同じグループで管理する |
| Includes | `liminalog.pro.monthly`, `liminalog.pro.yearly`, `liminalog.decorations.monthly`, `liminalog.decorations.yearly` |
| Does Not Include | `liminalog.lifetime`, support tips, premium decoration single products |

## Products

この表の値を App Store Connect に作成する。転記元は `PurchaseProductID.appStoreConnectSpecifications`。

| Product ID | Reference Name | Type | Price | Group |
|---|---|---|---:|---|
| `liminalog.pro.monthly` | Liminalog Pro 月額 | Auto-Renewable Subscription | ¥400 | `Liminalog Pro` |
| `liminalog.pro.yearly` | Liminalog Pro 年額 | Auto-Renewable Subscription | ¥2,900 | `Liminalog Pro` |
| `liminalog.lifetime` | ライフタイム | Non-Consumable | ¥6,800 | - |
| `liminalog.decorations.monthly` | 装飾パス 月額 | Auto-Renewable Subscription | ¥200 | `Liminalog Pro` |
| `liminalog.decorations.yearly` | 装飾パス 年額 | Auto-Renewable Subscription | ¥1,500 | `Liminalog Pro` |
| `liminalog.support.small` | 小さく応援 | Consumable | ¥250 | - |
| `liminalog.support.medium` | しっかり応援 | Consumable | ¥600 | - |
| `liminalog.support.large` | 大きく応援 | Consumable | ¥1,200 | - |

## Product Notes

| Product ID | App Behavior | Creation Note |
|---|---|---|
| `liminalog.pro.monthly` | Pro機能とプレミアム装飾レンタルを有効化する | 月額の主要プラン |
| `liminalog.pro.yearly` | Pro機能とプレミアム装飾レンタルを有効化する | 無料体験の有無を別途決める |
| `liminalog.lifetime` | Pro機能を永続解放する | プレミアム装飾レンタルは付けない |
| `liminalog.decorations.monthly` | プレミアム装飾レンタルのみ有効化する | ライフタイム所有者向けに表示制御する |
| `liminalog.decorations.yearly` | プレミアム装飾レンタルのみ有効化する | ライフタイム所有者向けに表示制御する |
| `liminalog.support.small` | 権利を増やさず完了メッセージだけ出す | 任意支援 |
| `liminalog.support.medium` | 権利を増やさず完了メッセージだけ出す | 任意支援 |
| `liminalog.support.large` | 権利を増やさず完了メッセージだけ出す | 任意支援 |

## Premium Decoration Single Products

単品プレミアム装飾は今後の候補。初回の購入導線には入れない。

- 候補表は `AppStore/PurchaseProducts.md` の `Premium Decoration Single Products` を見る。
- 作成しても UI 接続までは `PurchaseConfiguration.current.productIDs` に入れない。
- `Scripts/validate-purchase-readiness.sh` は、単品装飾が `liminalog.storekit` とプロフィール装飾UIへ混ざっていないことを検査する。

## Before Gate 1

App Store Connect で作成した後にやること。

1. `AppStore/AppStoreConnectProductConfirmation.md` を埋める。
2. `Scripts/validate-purchase-readiness.sh --gate1-ready` を通す。
3. 利用規約本文が承認済みであることを確認する。
4. Gate 1 のコード変更では、購入導線と機能制限をまだ開かない。

## Local Validation

このファイルを編集したら、repo root で次を実行する。

```sh
swift Scripts/validate-storekit-config.swift --validate-products-doc AppStore/AppStoreConnectProductSetup.md
Scripts/validate-purchase-readiness.sh
```
