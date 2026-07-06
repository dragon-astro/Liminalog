# App Store Connect Product Confirmation

App Store Connect で課金商品を作成した後に埋める確認表。すべて確認できるまで `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` は `true` にしない。

## Source Of Truth

- 商品ID、表示名、種別、価格、サブスクリプショングループの転記元は `PurchaseProductID.appStoreConnectSpecifications`。
- この表の構造は `Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-template` で検査する。
- App Store Connect 作成後、Gate 1 に進む直前に `Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-complete` を通す。
- 完了検査では `fill manually`、`TBD`、`TODO`、`未確定` が残っている確認表を未完了扱いにする。
- 単品プレミアム装飾は `AppStore/PurchaseProducts.md` の別表を使う。購入UIに入れない段階では `PurchaseConfiguration.current.productIDs` に追加しない。
- Missing Metadata 入力時の表示名、説明文、価格、Review Information は `AppStore/AppStoreConnectMetadataEntrySheet.md` を参照する。

## Confirmation Metadata

| Field | Value |
|---|---|
| Confirmed by | ryu |
| Confirmation date | 2026-07-06 |
| App Store Connect app | Liminalog |
| Notes | Product ID、価格、表示名、年額Proの1週間無料体験はユーザー確認済み。App Store Connect は Missing Metadata 状態のため、残りのメタデータとReview Informationは未完了。Review Information 用の候補画像は `AppStore/ReviewInformationScreenshots/` に準備済み。 |

## Subscription Group

| Check | Field | Expected |
|---|---|---|
| [x] | Group Reference Name | `Liminalog Pro` |
| [x] | Contains Products | Proサブと装飾パスが同じグループに入っている |
| [ ] | Subscription Relationship | 同じグループ内の代替プランとして、Proサブと装飾パスの期間、表示順、レベル/アップグレード関係が意図と矛盾しない |

## Products

| Check | Product ID | Reference Name | Type | Reference Price | Subscription Group | Notes |
|---|---|---|---|---:|---|---|
| [x] | `liminalog.pro.monthly` | Liminalog Pro 月額 | Auto-Renewable Subscription | ¥400 | Liminalog Pro |  |
| [x] | `liminalog.pro.yearly` | Liminalog Pro 年額 | Auto-Renewable Subscription | ¥2,900 | Liminalog Pro | Introductory Offer: Free Trial / 1 Week。アプリ内文言とQA表へ反映済み。 |
| [x] | `liminalog.pro.onetime` | Pro機能 買い切り | Non-Consumable | ¥7,800 | - |  |
| [x] | `liminalog.decorations.monthly` | 装飾パス 月額 | Auto-Renewable Subscription | ¥200 | Liminalog Pro | アプリ側ではPro機能 買い切り所有者向けに表示制御する。 |
| [x] | `liminalog.decorations.yearly` | 装飾パス 年額 | Auto-Renewable Subscription | ¥1,500 | Liminalog Pro | アプリ側ではPro機能 買い切り所有者向けに表示制御する。 |
| [x] | `liminalog.support.small` | 開発応援チップ 小 | Consumable | ¥120 | - | 機能解放ではなく任意支援。恒久権利を付けない。 |
| [x] | `liminalog.support.medium` | 開発応援チップ 中 | Consumable | ¥600 | - | 機能解放ではなく任意支援。恒久権利を付けない。 |
| [x] | `liminalog.support.large` | 開発応援チップ 大 | Consumable | ¥1,000 | - | 機能解放ではなく任意支援。恒久権利を付けない。 |

## Creation Metadata

| Check | Field | Expected |
|---|---|---|
| [x] | Product Edit Permission | The App Store Connect account used for setup can add and edit in-app purchase products |
| [ ] | Product Metadata | Display names, descriptions, durations, prices, and availability are filled for all App Store Connect products, using `AppStore/AppStoreConnectMetadataEntrySheet.md` |
| [x] | Introductory Offer Decision | 年額ProのIntroductory Offerを Free Trial / 1 Week として作成し、アプリ内文言とQA表へ反映している |
| [ ] | Legal Terms Approval | 利用規約本文とプライバシーポリシーURLを有料リリース前提で確認し、App Store Connect に登録するURLと一致している |
| [ ] | Review Information | Review screenshot and review notes are attached for products submitted to App Review |
| [ ] | Sandbox Propagation | After metadata edits, allow up to 1 hour before treating Sandbox product fetch failures as app bugs |

## Review Information Draft Assets

App Store Connect への添付は未完了。以下は審査情報用の候補であり、XcodeBuildMCP / CLI で StoreKit 商品が注入されない問題を避けるため、DEBUG 表示補助 `-LiminalogDebugStoreKitProducts loaded` で撮影した。Local StoreKit QA や購入証跡としては扱わない。

| Product IDs | Candidate Screenshot |
|---|---|
| `liminalog.pro.yearly`, `liminalog.pro.monthly` | `AppStore/ReviewInformationScreenshots/pro-subscriptions-free.jpg` |
| `liminalog.pro.onetime`, `liminalog.support.small`, `liminalog.support.medium` | `AppStore/ReviewInformationScreenshots/pro-onetime-and-support-free.jpg` |
| `liminalog.support.medium`, `liminalog.support.large` | `AppStore/ReviewInformationScreenshots/support-tips-medium-large-free.jpg` |
| `liminalog.decorations.yearly`, `liminalog.decorations.monthly` | `AppStore/ReviewInformationScreenshots/decoration-pass-lifetime.jpg` |

## Gate 1 App Code Change After Confirmation

この表をすべて確認し、利用規約本文も承認した後だけ Gate 1 に進める。Gate 1 では購入導線をまだ出さない。

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
