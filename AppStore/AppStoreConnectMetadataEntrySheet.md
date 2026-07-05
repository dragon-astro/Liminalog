# App Store Connect Metadata Entry Sheet

App Store Connect の Missing Metadata を埋めるための入力表。商品ID、種別、参照価格、サブスクリプショングループは `PurchaseProductID.appStoreConnectSpecifications` と `AppStore/AppStoreConnectProductSetup.md` を正にする。

この表を埋めても、App Store Connect で実際に添付・保存・反映待ち確認が終わるまでは `AppStore/AppStoreConnectProductConfirmation.md` の Product Metadata / Review Information / Sandbox Propagation をチェックしない。

## Subscription Relationship

| Field | Expected |
|---|---|
| Subscription Group | `Liminalog Pro` |
| Group Products | `liminalog.pro.monthly`, `liminalog.pro.yearly`, `liminalog.decorations.monthly`, `liminalog.decorations.yearly` |
| Higher Service Level | Liminalog Pro 月額 / 年額。Pro機能とプレミアム装飾レンタルを含む。 |
| Lower Service Level | 装飾パス 月額 / 年額。Pro機能 買い切り所有者向けのプレミアム装飾レンタルのみ。 |
| Same Duration Relationship | 月額同士、年額同士は同じ期間の代替プランとして扱う。 |
| App Display Rule | 装飾パスは `PurchaseOfferingCatalog` により Pro機能 買い切り所有者にだけ表示する。 |
| Stop Condition | App Store Connect 上で Proサブと装飾パスを同じグループに置く意図を説明できない場合、Gate 1 へ進まない。 |

## Product Metadata

| Product ID | Reference Name | Type | Group | Duration | JP Price | US Price | Display Name ja-JP | Description ja-JP | Display Name en-US | Description en-US |
|---|---|---|---|---|---:|---:|---|---|---|---|
| `liminalog.pro.monthly` | Liminalog Pro 月額 | Auto-Renewable Subscription | Liminalog Pro | 1 Month | ¥400 | $3.99 | Liminalog Pro 月額 | 統計などのPro機能とプレミアム装飾を月ごとに利用できます。 | Liminalog Pro Monthly | Unlock Pro statistics and premium decorations month by month. |
| `liminalog.pro.yearly` | Liminalog Pro 年額 | Auto-Renewable Subscription | Liminalog Pro | 1 Year | ¥2,900 | $24.99 | Liminalog Pro 年額 | 統計などのPro機能とプレミアム装飾を年ごとに利用できます。 | Liminalog Pro Yearly | Unlock Pro statistics and premium decorations for a year. |
| `liminalog.pro.onetime` | Pro機能 買い切り | Non-Consumable | - | - | ¥7,800 | $59.99 | Pro機能 買い切り | 統計などのPro機能を一度だけの応援でずっと使えます。プレミアム装飾レンタルは含まれません。 | Pro Features One-Time | Unlock Pro features with a one-time purchase. Premium decoration rental is not included. |
| `liminalog.decorations.monthly` | 装飾パス 月額 | Auto-Renewable Subscription | Liminalog Pro | 1 Month | ¥200 | $1.99 | 装飾パス 月額 | Pro機能 買い切り所有者向けにプレミアム装飾を月ごとに利用できます。 | Decoration Pass Monthly | Use premium decorations month by month if you own Pro Features One-Time. |
| `liminalog.decorations.yearly` | 装飾パス 年額 | Auto-Renewable Subscription | Liminalog Pro | 1 Year | ¥1,500 | $12.99 | 装飾パス 年額 | Pro機能 買い切り所有者向けにプレミアム装飾を年ごとに利用できます。 | Decoration Pass Yearly | Use premium decorations for a year if you own Pro Features One-Time. |
| `liminalog.support.small` | 開発応援チップ 小 | Consumable | - | - | ¥120 | $0.99 | 開発応援チップ 小 | 機能解放はありません。Liminalogの開発を応援するチップです。 | Support Tip Small | A voluntary tip to support Liminalog development. This does not unlock features. |
| `liminalog.support.medium` | 開発応援チップ 中 | Consumable | - | - | ¥600 | $4.99 | 開発応援チップ 中 | 機能解放はありません。Liminalogの開発を応援するチップです。 | Support Tip Medium | A voluntary tip to support Liminalog development. This does not unlock features. |
| `liminalog.support.large` | 開発応援チップ 大 | Consumable | - | - | ¥1,000 | $8.99 | 開発応援チップ 大 | 機能解放はありません。Liminalogの開発を応援するチップです。 | Support Tip Large | A voluntary tip to support Liminalog development. This does not unlock features. |

## Introductory Offers

| Product ID | Offer | Notes |
|---|---|---|
| `liminalog.pro.yearly` | Free Trial / 1 Week | 年額Proだけに付ける。 |
| All other products | None | 月額Pro、買い切り、装飾パス、支援チップには無料体験を付けない。 |

## Review Information

Use `AppStore/ReviewNotes.md` の Paid Release Draft for the review note. Product-specific notes below are short labels for App Store Connect fields when a product-level explanation is useful.

| Product IDs | Screenshot | Product-Specific Review Note |
|---|---|---|
| `liminalog.pro.yearly`, `liminalog.pro.monthly` | `AppStore/ReviewInformationScreenshots/pro-subscriptions-free.jpg` | Pro subscriptions unlock deeper analysis features and premium decoration rental. The yearly product has a one-week free trial. |
| `liminalog.pro.onetime` | `AppStore/ReviewInformationScreenshots/pro-onetime-and-support-free.jpg` | One-time Pro unlocks Pro features permanently, but does not include premium decoration rental. |
| `liminalog.decorations.yearly`, `liminalog.decorations.monthly` | `AppStore/ReviewInformationScreenshots/decoration-pass-lifetime.jpg` | Decoration pass subscriptions are shown only to Pro Features One-Time owners and rent premium decorations while active. |
| `liminalog.support.small`, `liminalog.support.medium`, `liminalog.support.large` | `AppStore/ReviewInformationScreenshots/pro-onetime-and-support-free.jpg` or `AppStore/ReviewInformationScreenshots/support-tips-medium-large-free.jpg` | Support tips are voluntary consumables and do not grant feature access or permanent entitlements. |

## Availability And Sandbox

- Availability: enable in the same territories as the app unless App Store Connect pricing or legal state requires a narrower rollout.
- After saving product metadata or review information, wait up to 1 hour before treating Sandbox product fetch failures as an app bug.
- Do not use `-LiminalogDebugStoreKitProducts loaded` as StoreKit QA evidence. It is only for review screenshot candidates when CLI/MCP launches cannot inject StoreKit products.

## Completion Handoff

After App Store Connect is saved:

1. Confirm every product has display name, description, price, duration if subscription, and availability.
2. Confirm Review Information screenshot and notes are attached for submitted products.
3. Confirm the subscription relationship still matches the expected service levels above.
4. Wait for Sandbox propagation.
5. Update `AppStore/AppStoreConnectProductConfirmation.md`.
6. Run `Scripts/validate-purchase-readiness.sh --gate1-ready`.
