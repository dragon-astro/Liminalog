# App Store Connect Product Confirmation

App Store Connect で課金商品を作成した後に埋める確認表。すべて確認できるまで `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` は `true` にしない。

## Source Of Truth

- 商品ID、表示名、種別、価格、サブスクリプショングループの転記元は `PurchaseProductID.appStoreConnectSpecifications`。
- この表の構造は `Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-template` で検査する。
- 単品プレミアム装飾は `AppStore/PurchaseProducts.md` の別表を使う。購入UIに入れない段階では `PurchaseConfiguration.current.productIDs` に追加しない。

## Confirmation Metadata

| Field | Value |
|---|---|
| Confirmed by |  |
| Confirmation date |  |
| App Store Connect app | Liminalog |
| Notes |  |

## Subscription Group

| Check | Field | Expected |
|---|---|---|
| [ ] | Group Reference Name | `Liminalog Pro` |
| [ ] | Contains Products | Proサブと装飾パスが同じグループに入っている |

## Products

| Check | Product ID | Reference Name | Type | Reference Price | Subscription Group | Notes |
|---|---|---|---|---:|---|---|
| [ ] | `liminalog.pro.monthly` | Liminalog Pro 月額 | Auto-Renewable Subscription | ¥400 | Liminalog Pro |  |
| [ ] | `liminalog.pro.yearly` | Liminalog Pro 年額 | Auto-Renewable Subscription | ¥2,900 | Liminalog Pro | 7日無料体験は未確定。確定後にアプリ内文言へ反映する。 |
| [ ] | `liminalog.lifetime` | ライフタイム | Non-Consumable | ¥6,800 | - |  |
| [ ] | `liminalog.decorations.monthly` | 装飾パス 月額 | Auto-Renewable Subscription | ¥200 | Liminalog Pro | アプリ側ではライフタイム所有者向けに表示制御する。 |
| [ ] | `liminalog.decorations.yearly` | 装飾パス 年額 | Auto-Renewable Subscription | ¥1,500 | Liminalog Pro | アプリ側ではライフタイム所有者向けに表示制御する。 |
| [ ] | `liminalog.support.small` | 小さく応援 | Consumable | ¥250 | - | 機能解放ではなく任意支援。恒久権利を付けない。 |
| [ ] | `liminalog.support.medium` | しっかり応援 | Consumable | ¥600 | - | 機能解放ではなく任意支援。恒久権利を付けない。 |
| [ ] | `liminalog.support.large` | 大きく応援 | Consumable | ¥1,200 | - | 機能解放ではなく任意支援。恒久権利を付けない。 |

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
