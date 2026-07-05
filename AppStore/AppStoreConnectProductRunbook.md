# App Store Connect Product Runbook

App Store Connect で課金商品を実作成する時の手順。目的は、商品メタデータを確定しても Release の購入導線や既存機能を勝手に変えないこと。

## Source Of Truth

- 商品ID、表示名、種別、参照価格、サブスクリプショングループは `AppStore/AppStoreConnectProductSetup.md` と `PurchaseProductID.appStoreConnectSpecifications` を正とする。
- 転記前に `Scripts/validate-purchase-readiness.sh` を通す。
- 作成後の確認証跡は `AppStore/AppStoreConnectProductConfirmation.md` に残す。
- Confirmation が完了するまで `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` は `false` のままにする。

## Non-Goals

- この作業では `purchaseEntryPointIsEnabled` を開かない。
- この作業では `featureRestrictionsAreEnabled` を開かない。
- 単品プレミアム装飾は作成候補として温存し、初回の購入導線・`liminalog.storekit`・`PurchaseConfiguration.current.productIDs` には入れない。
- 年額Proには1週間無料体験を付ける。App Store Connect では `liminalog.pro.yearly` の Introductory Offer を Free Trial / 1 Week にする。

## Before Opening App Store Connect

1. Current branch が `codex/monetization-foundation` で、課金作業以外の差分が混ざっていないことを確認する。別ブランチで行う場合は `Scripts/prepare-app-store-connect-products.sh --allow-other-branch` を使い、理由を確認表の Notes に残す。
2. `Scripts/prepare-app-store-connect-products.sh` を実行し、商品表、確認表テンプレート、Review Notes、Release gate、法務URLが揃っていることを確認する。
3. `swift Scripts/validate-storekit-config.swift --app-store-connect-tsv` を実行し、転記用TSVを手元に置く。
4. `AppStore/AppStoreConnectProductSetup.md` の Products / App Store Localization / Product Notes を開いておく。
5. `AppStore/ReviewNotes.md` の Paid Release Draft を開いておく。

## Creation Order

### 1. Subscription Group

Create one subscription group:

| Field | Value |
|---|---|
| Reference Name | `Liminalog Pro` |
| Contains | Pro monthly, Pro yearly, Decoration monthly, Decoration yearly |
| Does Not Contain | Lifetime, support tips, premium decoration single products |

確認すること：

- Proサブと装飾パスが同じ subscription group に入っている。
- Proサブは「Pro機能 + プレミアム装飾レンタル」。
- 装飾パスは「Pro機能 買い切り所有者向けのプレミアム装飾レンタルのみ」。
- App Store Connect 上の表示順やレベル/アップグレード関係が、アプリ内の表示制御と矛盾しない。

### 2. Pro Subscriptions

Create these as Auto-Renewable Subscriptions inside `Liminalog Pro`:

| Product ID | Reference Name | Price | Duration | Note |
|---|---|---:|---|---|
| `liminalog.pro.monthly` | Liminalog Pro 月額 | ¥400 | Monthly | Pro機能とプレミアム装飾レンタル |
| `liminalog.pro.yearly` | Liminalog Pro 年額 | ¥2,900 | Yearly | Introductory Offer: Free Trial / 1 Week |

年額Proの無料体験はこのチェックポイントで確定済み。次が同時に更新されていることを確認する：

- App Store Connect の Introductory Offer: Free Trial / 1 Week
- アプリ内の購入画面文言
- `AppStore/AppStoreConnectProductConfirmation.md`
- `AppStore/StoreKitLocalTesting.md`
- `AppStore/PurchaseUIQA.md`
- `Liminalog/Views/Profile/docs/17-monetization.md`

### 3. Lifetime Product

Create this as Non-Consumable:

| Product ID | Reference Name | Price | Note |
|---|---|---:|---|
| `liminalog.pro.onetime` | Pro機能 買い切り | ¥7,800 | Pro機能の買い切り。プレミアム装飾レンタルは付けない |

### 4. Decoration Pass Subscriptions

Create these as Auto-Renewable Subscriptions inside `Liminalog Pro`:

| Product ID | Reference Name | Price | Duration | Note |
|---|---|---:|---|---|
| `liminalog.decorations.monthly` | 装飾パス 月額 | ¥200 | Monthly | Pro機能 買い切り所有者向け表示 |
| `liminalog.decorations.yearly` | 装飾パス 年額 | ¥1,500 | Yearly | Pro機能 買い切り所有者向け表示 |

App Store Connect 上では商品として存在するが、アプリ内では `PurchaseOfferingCatalog` によりPro機能 買い切り所有者向けにだけ表示する。

### 5. Support Tips

Create these as Consumable:

| Product ID | Reference Name | Price | Note |
|---|---|---:|---|
| `liminalog.support.small` | 開発応援チップ 小 | ¥120 | 権利付与なし |
| `liminalog.support.medium` | 開発応援チップ 中 | ¥600 | 権利付与なし |
| `liminalog.support.large` | 開発応援チップ 大 | ¥1,000 | 権利付与なし |

支援チップは任意支援であり、Pro機能、Pro機能 買い切り権利、装飾レンタル、単品所有を付与しない。

## Review Information

App Store Connect の各商品に Review Information が必要な場合は、次を使う。

- Review Notes: `AppStore/ReviewNotes.md` の Paid Release Draft。
- Screenshot: Gate 2 の購入導線を開く直前またはDEBUG確認用ビルドで、設定 > Proと応援 の購入画面を撮る。個人データ、友達情報、メールアドレス、未公開のデバッグ情報が写らない状態にする。
- XcodeBuildMCP / CLI 経由で StoreKit 商品が注入されない場合、審査用スクリーンショット候補の作成に限って DEBUG 起動引数 `-LiminalogDebugStoreKitProducts loaded` を使ってよい。この表示は参照価格ベースの見た目確認専用で、Local StoreKit QA や購入証跡としては扱わない。
- 購入導線のスクリーンショットがまだ用意できない場合は、`AppStore/AppStoreConnectProductConfirmation.md` の Review Information を未チェックのままにし、Gate 1 へ進まない。

## After Creation

1. `AppStore/AppStoreConnectProductConfirmation.md` の Confirmation Metadata を埋める。
2. Subscription Group の3行を確認済みにする。
3. Products の全8商品について、ID、Reference Name、Type、Price、Subscription Group を確認済みにする。
4. Creation Metadata の5行を確認済みにする。
5. 年額ProのNotesとIntroductory Offerが Free Trial / 1 Week になっていることを確認する。`未確定` を残したまま Gate 1 へ進まない。
6. App Store Connect 反映待ちとして最大1時間程度待ってから、Sandbox / StoreKit 商品取得QAを行う。
7. `Scripts/validate-purchase-readiness.sh --gate1-ready` を実行する。

## Stop Conditions

次のどれかが起きたら、Gate 1 のコード変更をしない。

- 商品ID、種別、価格、グループが `AppStore/AppStoreConnectProductSetup.md` と一致しない。
- 年額ProのIntroductory Offerが Free Trial / 1 Week になっていない。
- 装飾パスがPro機能 買い切り所有者向け表示であることを説明できない。
- 支援チップが権利付与なしであることを確認できない。
- Review Information のスクリーンショットまたはメモが用意できない。
- `Scripts/validate-purchase-readiness.sh --gate1-ready` が失敗する。
