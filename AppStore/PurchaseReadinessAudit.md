# Purchase Readiness Audit

最終更新日：2026-06-27

Liminalog の課金基盤 v0 を、現時点の証拠ベースで監査するための表。完了していない項目を完了扱いにしないため、`Done` / `Prepared` / `Blocked` / `Not Started` を分ける。

## Status Legend

| Status | Meaning |
|---|---|
| Done | 現在のファイルまたは検証コマンドで完了を確認済み |
| Prepared | 実装・手順はあるが、外部作業や手動QAが未完了 |
| Blocked | 外部状態または明示承認がないと進められない |
| Not Started | 設計だけ、またはまだ実装していない |

## Audit Matrix

| Area | Status | Evidence | Remaining Work |
|---|---|---|---|
| 課金基盤 v0 | Done | `PurchaseStore`, `PurchaseProductID`, `PurchaseConfiguration`, `PurchaseActivationPolicy`, `PurchaseFeatureGate`, `SupportLiminalogView` が追加済み | StoreKit実購入での権利反映確認 |
| Release安全状態 | Done | `Scripts/validate-purchase-readiness.sh` が 2026-06-27 に成功。`--validate-release-safety` も含めて確認済み | Gate 1 以降で値を変えたら再実行 |
| Release build | Done | `xcodebuild -project Liminalog.xcodeproj -scheme Liminalog -configuration Release -destination "generic/platform=iOS" -derivedDataPath /private/tmp/LiminalogMonetizationReleaseDerivedData build` が成功 | App Store提出前はArchive/exportで再検証 |
| LP 利用規約ページ | Done | LP repo の `5d46da9 feat: add terms page` を `origin/main` へpush済み。`https://liminalog-lp.vercel.app/terms` は 200 応答 | 本文承認後にApp Store Connectへ登録 |
| LP プライバシーポリシーURL | Done | `https://liminalog-lp.vercel.app/privacy` は 200 応答。`PurchaseConfiguration.current.privacyPolicyURL` はこのURLを参照 | カスタムドメインを使う場合はコード・docs・App Store Connectを同時更新 |
| App Store Connect商品準備 | Prepared | `AppStore/PurchaseProducts.md`、`--app-store-connect-tsv`、Confirmation Sheet。`Scripts/validate-purchase-readiness.sh` でTSV出力を確認済み | App Store Connect で商品8件と `Liminalog Pro` group を実作成し、各行を確認 |
| 商品ドキュメント整合性 | Done | `Scripts/validate-purchase-readiness.sh` が 2026-06-27 に成功。`--validate-products-doc` も含めて確認済み | 商品・価格・種別を変えたら再実行 |
| StoreKitローカル設定 | Blocked | repo 内に `liminalog.storekit` は未存在。`xcrun storekit` も現在の環境にない | Xcode GUI で `liminalog.storekit` を作成し、scheme に設定 |
| StoreKitローカル購入テスト | Blocked | `AppStore/StoreKitLocalTesting.md` と `AppStore/PurchaseUIQA.md` に手順あり | `.storekit` 作成後に購入、復元、期限切れ、キャンセルを確認 |
| Release課金導線準備 | Prepared | `PurchaseReleaseChecklist.md` の Gate 1 / Gate 2 / Gate 3、`PurchaseConfiguration.current` の段階フラグ | App Store Connect と利用規約確定後に Gate 1 へ進める |
| 課金UI QA | Prepared | `AppStore/PurchaseUIQA.md` | Simulator DEBUG、Release hidden-entry、Local StoreKit、実機QAを実行して証跡を残す |
| 統計Pro化設計 | Prepared | `Liminalog/Views/Profile/docs/19-statistics-pro-gate.md` | `StatisticsProPreviewView` と `RootTabView` 分岐は未実装 |
| 装飾課金データ設計 | Prepared | `Liminalog/Views/Profile/docs/20-premium-decoration-data.md`、`PremiumDecorationAccessPolicy` | `PremiumDecorationCatalog`、UI接続、単品商品ID列挙、失効時フォールバックは未実装 |
| 既存機能への影響抑制 | Prepared | Release安全状態は閉じている。`featureRestrictionsAreEnabled == false` | Gate変更時に既存タブのスモークQAが必要 |

## Commands To Re-Run Before Each Gate

```sh
Scripts/validate-purchase-readiness.sh
```

The aggregate command runs:

```sh
swift Scripts/validate-storekit-config.swift --validate-products-doc
swift Scripts/validate-storekit-config.swift --validate-release-safety
swift Scripts/validate-storekit-config.swift --app-store-connect-tsv
Scripts/validate-purchase-legal-urls.sh
git diff --check
```

Release build まで含める場合：

```sh
Scripts/validate-purchase-readiness.sh --release-build
```

`liminalog.storekit` 作成後：

```sh
Scripts/validate-purchase-readiness.sh --storekit=liminalog.storekit
swift Scripts/validate-storekit-config.swift liminalog.storekit
```

## Known Non-Completion Items

- `PurchaseConfiguration.current.termsOfUseURL` は nil のまま。本文承認と公開確認が終わるまで変更しない。
- `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` は false のまま。App Store Connect で商品作成後だけ true にする。
- `purchaseEntryPointIsEnabled` は false のまま。Releaseでは購入画面を出さない。
- `featureRestrictionsAreEnabled` は false のまま。統計タブやカテゴリセット上限をまだロックしない。
- `backgroundEntitlementRefreshIsEnabled` は false のまま。起動時や復帰時にStoreKit権利更新を走らせない。
- `.storekit` がないためローカル購入テストは未完了。
- 実機QAは、既存リリースデータへ触れる可能性があるため明示承認後に行う。
- Release build 成功時点のワークツリーには、課金作業と無関係な `Liminalog/Stores/CategoryStore.swift` の未コミット差分が残っていた。この差分は課金コミットには含めない。

## Next Best Steps

1. Xcode GUI で `liminalog.storekit` を作成し、8商品と `Liminalog Pro` group を登録する。
2. `swift Scripts/validate-storekit-config.swift liminalog.storekit` を通す。
3. Simulator DEBUG で `AppStore/PurchaseUIQA.md` の Local StoreKit QA を実施する。
4. App Store Connect で商品を作成し、`AppStore/PurchaseProducts.md` の Confirmation Sheet を埋める。
5. 利用規約本文を承認し、LP の `/terms` を App Store Connect に登録する。
6. Gate 1 のコード変更だけを入れ、Releaseで購入導線がまだ出ないことを確認する。
