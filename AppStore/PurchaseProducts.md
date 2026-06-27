# App Store Connect Purchase Products

Liminalog の App Store Connect 商品作成用メモ。アプリ内の転記元は `PurchaseProductID.appStoreConnectSpecifications`。このファイルを先に変えず、コード側の商品ID・種別・価格方針を更新してから同期する。

## Subscription Group

| 項目 | 値 |
|---|---|
| Group Reference Name | `Liminalog Pro` |
| 用途 | Proサブと装飾パスを同一グループで管理する |
| 注意 | 装飾パスはアプリ側でライフタイム所有者向けに表示制御する |

## Products

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

## Review Notes Draft

App Review に課金の意図を説明する時の下書き。

> Liminalog offers optional in-app purchases for Pro features, lifetime support, decoration access, and voluntary support tips. Core logging, calendar browsing, friends, and daily card sharing remain available without purchase. The app does not use external payment links or unlock purchased content outside StoreKit.

## Required Before Confirmation

- App Store Connect 上の商品IDがこの表と一致している。
- 商品種別が `PurchaseProductID.expectedStoreKitProductKind(for:)` と一致している。
- サブスクリプション商品が `Liminalog Pro` グループに入っている。
- 年額Proの無料体験を付けるか確定している。
- 利用規約URLが公開済みで、App Store Connect とアプリ内設定の両方から参照できる。
- ローカル StoreKit Configuration で同じ商品IDを作り、`Scripts/validate-storekit-config.swift` を通している。

## Local Validation

このメモを編集したら、repo root で次を実行する。

```sh
swift Scripts/validate-storekit-config.swift --validate-products-doc
```

App Store Connect へ転記するためのTSVは、同じ期待商品リストから生成する。

```sh
swift Scripts/validate-storekit-config.swift --app-store-connect-tsv
```

StoreKit Configuration 作成後は、同じ期待商品リストで `.storekit` も検査する。

```sh
swift Scripts/validate-storekit-config.swift liminalog.storekit
```

## Confirmation Sheet

App Store Connect で作成した後、各行を確認する。すべて確認できるまで `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` は true にしない。

| Product ID | ID | Type | Price | Group | Notes |
|---|---|---|---|---|---|
| `liminalog.pro.monthly` | [ ] | [ ] | [ ] | [ ] |  |
| `liminalog.pro.yearly` | [ ] | [ ] | [ ] | [ ] | 7日無料体験の有無を確定 |
| `liminalog.lifetime` | [ ] | [ ] | [ ] | - |  |
| `liminalog.decorations.monthly` | [ ] | [ ] | [ ] | [ ] | ライフタイム所有者向け表示 |
| `liminalog.decorations.yearly` | [ ] | [ ] | [ ] | [ ] | ライフタイム所有者向け表示 |
| `liminalog.support.small` | [ ] | [ ] | [ ] | - | 権利付与なし |
| `liminalog.support.medium` | [ ] | [ ] | [ ] | - | 権利付与なし |
| `liminalog.support.large` | [ ] | [ ] | [ ] | - | 権利付与なし |
| `Liminalog Pro` subscription group | - | - | - | [ ] | Proサブと装飾パスを同一グループに入れる |

## After App Store Connect Confirmation

App Store Connect で商品を確認した後だけ、アプリ側で次を更新する。

- `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect = true`
- `PurchaseConfiguration.current.subscriptionGroupName = "Liminalog Pro"`
- `PurchaseConfiguration.current.legalLinks.termsOfUseURL = URL(string: "https://liminalog.vercel.app/terms")`

まだ購入導線を出さない場合は、`purchaseEntryPointIsEnabled` は false のままにする。
