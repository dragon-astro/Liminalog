# App Store Connect Product Setup

App Store Connect で Liminalog の課金商品を作る時の転記シート。作成作業中に商品名、ID、種別、価格、グループのズレを出さないためのもの。

このファイルは作成前の入力値を固定するために使う。実作業の順序は `AppStore/AppStoreConnectProductRunbook.md`、作成後の証跡は `AppStore/AppStoreConnectProductConfirmation.md` に残す。

## Safety Rules

- App Store Connect で商品を作成しても、確認表が埋まるまで `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` は `false` のままにする。
- Gate 1 では `purchaseEntryPointIsEnabled` と `featureRestrictionsAreEnabled` を `false` のままにする。
- 単品プレミアム装飾は別枠候補として温存し、初回の `PurchaseConfiguration.current.productIDs` と `liminalog.storekit` には入れない。
- 年額 Pro には 1週間無料体験を付ける。App Store Connect では `liminalog.pro.yearly` の Introductory Offer を Free Trial / 1 Week にする。
- 支援チップは権利付与なしの Consumable として扱う。

## Subscription Group

| Field | Value |
|---|---|
| Reference Name | `Liminalog Pro` |
| Purpose | Proサブと装飾パスを同じグループで管理する |
| Includes | `liminalog.pro.monthly`, `liminalog.pro.yearly`, `liminalog.decorations.monthly`, `liminalog.decorations.yearly` |
| Does Not Include | `liminalog.pro.onetime`, support tips, premium decoration single products |

### Subscription Relationship

同じ Subscription Group 内の商品は、App Store Connect / StoreKit 上では同時加入ではなく同じファミリー内の代替プランとして扱われる。Liminalog では Pro サブが「Pro機能 + プレミアム装飾レンタル」、装飾パスが「Pro機能 買い切り所有者向けのプレミアム装飾レンタルのみ」なので、この4商品を同じ `Liminalog Pro` group に置く。App Store Connect では、同じグループに入っていること、期間、表示順、レベル/アップグレード関係が意図と矛盾しないことを確認する。

## Products

この表の値を App Store Connect に作成する。転記元は `PurchaseProductID.appStoreConnectSpecifications`。

| Product ID | Reference Name | Type | Price | Group |
|---|---|---|---:|---|
| `liminalog.pro.monthly` | Liminalog Pro 月額 | Auto-Renewable Subscription | ¥400 | `Liminalog Pro` |
| `liminalog.pro.yearly` | Liminalog Pro 年額 | Auto-Renewable Subscription | ¥2,900 | `Liminalog Pro` |
| `liminalog.pro.onetime` | Pro機能 買い切り | Non-Consumable | ¥7,800 | - |
| `liminalog.decorations.monthly` | 装飾パス 月額 | Auto-Renewable Subscription | ¥200 | `Liminalog Pro` |
| `liminalog.decorations.yearly` | 装飾パス 年額 | Auto-Renewable Subscription | ¥1,500 | `Liminalog Pro` |
| `liminalog.support.small` | 開発応援チップ 小 | Consumable | ¥120 | - |
| `liminalog.support.medium` | 開発応援チップ 中 | Consumable | ¥600 | - |
| `liminalog.support.large` | 開発応援チップ 大 | Consumable | ¥1,000 | - |

## Product Notes

| Product ID | App Behavior | Creation Note |
|---|---|---|
| `liminalog.pro.monthly` | Pro機能とプレミアム装飾レンタルを有効化する | 月額の主要プラン |
| `liminalog.pro.yearly` | Pro機能とプレミアム装飾レンタルを有効化する | Introductory Offer: Free Trial / 1 Week |
| `liminalog.pro.onetime` | Pro機能を永続解放する | プレミアム装飾レンタルは付けない |
| `liminalog.decorations.monthly` | プレミアム装飾レンタルのみ有効化する | Pro機能 買い切り所有者向けに表示制御する |
| `liminalog.decorations.yearly` | プレミアム装飾レンタルのみ有効化する | Pro機能 買い切り所有者向けに表示制御する |
| `liminalog.support.small` | 権利を増やさず完了メッセージだけ出す | 開発応援チップ 小 |
| `liminalog.support.medium` | 権利を増やさず完了メッセージだけ出す | 開発応援チップ 中 |
| `liminalog.support.large` | 権利を増やさず完了メッセージだけ出す | 開発応援チップ 大 |

## Creation Metadata

App Store Connect で商品を作成する時は、商品IDと価格だけでなく次も埋める。メタデータ変更後、Sandbox に反映されるまで最大1時間程度待つ必要があるため、反映待ちの間に `Product.products(for:)` が空でもアプリ側バグとして扱わない。

- App Store Connect で商品を追加・編集できる権限のアカウントで作業する。
- Auto-Renewable Subscription は先に `Liminalog Pro` の Subscription Group を作り、Proサブと装飾パスを同じグループへ入れる。
- Product Metadata は、表示名、説明、期間、価格、販売状態を確認する。
- Subscription Relationship は、Pro月額/年額と装飾パス月額/年額が同じ `Liminalog Pro` group 内で代替プランとして扱われることを確認する。
- Review Information は、提出対象の商品にレビュー用スクリーンショットとメモを付ける。
- Introductory Offer は、年額Proだけ Free Trial / 1 Week にする。月額Pro、装飾パス、支援チップ、ライフタイムには無料体験を付けない。

## App Store Localization

初期ローカライズ案。最終文言を変える場合は、アプリ内の購入画面文言と `AppStore/PurchaseProducts.md` も同時に見直す。

| Product ID | Display Name | Description |
|---|---|---|
| `liminalog.pro.monthly` | Liminalog Pro 月額 | 統計などのPro機能とプレミアム装飾を月ごとに利用できます。 |
| `liminalog.pro.yearly` | Liminalog Pro 年額 | 統計などのPro機能とプレミアム装飾を年ごとに利用できます。 |
| `liminalog.pro.onetime` | Pro機能 買い切り | 統計などのPro機能を一度だけの応援でずっと使えます。プレミアム装飾レンタルは含まれません。 |
| `liminalog.decorations.monthly` | 装飾パス 月額 | Pro機能 買い切り所有者向けにプレミアム装飾を月ごとに利用できます。 |
| `liminalog.decorations.yearly` | 装飾パス 年額 | Pro機能 買い切り所有者向けにプレミアム装飾を年ごとに利用できます。 |
| `liminalog.support.small` | 開発応援チップ 小 | 機能解放はありません。Liminalogの開発を応援するチップです。 |
| `liminalog.support.medium` | 開発応援チップ 中 | 機能解放はありません。Liminalogの開発を応援するチップです。 |
| `liminalog.support.large` | 開発応援チップ 大 | 機能解放はありません。Liminalogの開発を応援するチップです。 |

## Premium Decoration Single Products

単品プレミアム装飾は今後の候補。初回の購入導線には入れない。

- 候補表は `AppStore/PurchaseProducts.md` の `Premium Decoration Single Products` を見る。
- 作成しても UI 接続までは `PurchaseConfiguration.current.productIDs` に入れない。
- `Scripts/validate-purchase-readiness.sh` は、単品装飾が `liminalog.storekit` とプロフィール装飾UIへ混ざっていないことを検査する。

## Before Gate 1

App Store Connect で作成した後にやること。

1. `AppStore/AppStoreConnectProductRunbook.md` の Stop Conditions に該当しないことを確認する。
2. `AppStore/AppStoreConnectProductConfirmation.md` を埋める。
3. `Scripts/validate-purchase-readiness.sh --gate1-ready` を通す。
4. 利用規約本文が承認済みであることを確認する。
5. Gate 1 のコード変更では、購入導線と機能制限をまだ開かない。

## Local Validation

このファイルを編集したら、repo root で次を実行する。

```sh
Scripts/prepare-app-store-connect-products.sh
swift Scripts/validate-storekit-config.swift --validate-products-doc AppStore/AppStoreConnectProductSetup.md
Scripts/validate-purchase-readiness.sh
```
