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
| StoreKitローカル設定 | Prepared | repo 直下に `liminalog.storekit` を追加。Shared scheme の Run に `liminalog.storekit` を接続。`Scripts/validate-purchase-readiness.sh` が 2026-06-27 に `billingPlans` 検査込みで成功 | Xcode editorが `.storekit` を書き換えた場合は再検査 |
| StoreKitローカル購入テスト | Prepared | `liminalog.storekit`、`AppStore/StoreKitLocalTesting.md`、`AppStore/PurchaseUIQA.md` に手順あり。`xcodebuild test` + `SKTestSession(contentsOf:)` は 2026-06-27 に `app.YasudaRyuga.Liminalog is not installed for development` で商品取得不可だったため自動テスト化しない | Xcode Run のStoreKit設定、またはApp Store Connect Sandboxで購入、復元、期限切れ、キャンセルを確認 |
| Release課金導線準備 | Prepared | `PurchaseReleaseChecklist.md` の Gate 1 / Gate 2 / Gate 3、`PurchaseConfiguration.current` の段階フラグ | App Store Connect と利用規約確定後に Gate 1 へ進める |
| 課金UI QA | Prepared | `AppStore/PurchaseUIQA.md`。2026-06-27 に XcodeBuildMCP / iPhone 17 Pro Simulator で DEBUG の設定入口表示と課金画面遷移、Release の設定入口非表示を確認 | Local StoreKit購入操作、実機QA、既存タブの広範囲スモークを実行して証跡を残す |
| 統計Pro化設計 | Prepared | `Liminalog/Views/Profile/docs/19-statistics-pro-gate.md`、`StatisticsProPreviewView`、`StatisticsTabAccessPolicy`、`RootTabView` 統計タブ入口分岐。2026-06-27 に `StatisticsTabAccessPolicyTests` を含む対象テスト40件が成功 | `featureRestrictionsAreEnabled` はまだ false。ロック画面の実機/シミュレータ目視QAと、Gate変更時のReleaseスモークQAは未完了 |
| 装飾課金データ設計 | Prepared | `Liminalog/Views/Profile/docs/20-premium-decoration-data.md`、`PremiumDecorationAccessPolicy`、`PremiumDecorationCatalog`、`PremiumDecorationEquippingPolicy`。2026-06-27 に `PremiumDecorationCatalogTests` を含む対象テスト47件が成功 | UI接続、App Store Connect 単品商品作成、StoreKitローカル購入QA、表示時フォールバックの実画面適用は未実装 |
| 既存機能への影響抑制 | Prepared | Release安全状態は閉じている。`featureRestrictionsAreEnabled == false`。装飾カタログは UI 未接続。購入まわりのユニットテスト69件と装飾課金対象テスト47件が成功 | Gate変更時に既存タブのスモークQAが必要 |

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

購入基盤の安全弁だけを再確認する場合：

```sh
xcodebuild -project Liminalog.xcodeproj -scheme Liminalog -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" -derivedDataPath /private/tmp/LiminalogMonetizationStoreKitDerivedData -only-testing:LiminalogTests/PurchaseConfigurationTests -only-testing:LiminalogTests/PurchaseOfferingCatalogTests -only-testing:LiminalogTests/PurchaseAccessPolicyTests -only-testing:LiminalogTests/PurchaseEntitlementTests -only-testing:LiminalogTests/PurchaseRefreshPolicyTests test
```

## Known Non-Completion Items

- `PurchaseConfiguration.current.termsOfUseURL` は nil のまま。本文承認と公開確認が終わるまで変更しない。
- `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` は false のまま。App Store Connect で商品作成後だけ true にする。
- `purchaseEntryPointIsEnabled` は false のまま。Releaseでは購入画面を出さない。
- `featureRestrictionsAreEnabled` は false のまま。統計タブやカテゴリセット上限をまだロックしない。
- `backgroundEntitlementRefreshIsEnabled` は false のまま。起動時や復帰時にStoreKit権利更新を走らせない。
- `liminalog.storekit` は追加・検査済みで、Xcode scheme の Run へ接続済み。ただしローカル購入操作そのもののQAは未完了。
- 2026-06-27 に `xcodebuild test` で `SKTestSession(contentsOf:)` による自動購入テストを試したが、Simulator の `storekitd` が `app.YasudaRyuga.Liminalog is not installed for development` を返した。失敗するテストを残さないため、現時点では手動StoreKit QAへ戻す。
- 2026-06-27 に XcodeBuildMCP の DEBUG 起動で「Proと応援」入口と画面遷移は確認済み。ただし XcodeBuildMCP 起動では StoreKit Configuration が適用されず商品取得は失敗表示だったため、Local StoreKit購入QAは未完了。
- 2026-06-27 に XcodeBuildMCP の Release 起動で、設定画面に「Proと応援」が表示されないことを確認済み。
- 2026-06-27 に購入基盤のユニットテスト69件は成功。ただしこれはStoreKit購入操作そのもののQAではない。
- 2026-06-27 に統計Pro入口分岐を含む対象テスト40件は成功。現行Release設定では無料ユーザーも `dashboard` のまま、将来の制限ON + 無料時だけ `proPreview` になることを確認済み。
- 2026-06-27 に装飾課金カタログ/アクセス判定を含む対象テスト47件は成功。ただし UI 接続と StoreKit 単品購入QAは未完了。
- 実機QAは、既存リリースデータへ触れる可能性があるため明示承認後に行う。
- Release build 成功時点のワークツリーには、課金作業と無関係な `Liminalog/Stores/CategoryStore.swift` の未コミット差分が残っていた。この差分は課金コミットには含めない。

## Next Best Steps

1. Simulator DEBUG を Xcode からRunし、`AppStore/PurchaseUIQA.md` の Local StoreKit QA を実施する。
2. App Store Connect で商品を作成し、`AppStore/PurchaseProducts.md` の Confirmation Sheet を埋める。
3. 利用規約本文を承認し、LP の `/terms` を App Store Connect に登録する。
4. Gate 1 のコード変更だけを入れ、Releaseで購入導線がまだ出ないことを確認する。
5. 統計Proプレビューをシミュレータで目視QAし、ロック状態でも `DashboardPeriodContent` の重い集計を作らないことを実機に近い経路で確認する。
6. プレミアム装飾を `UnlockGalleryView` へ合流する前に、表示モデルとフォールバック適用点を小さく実装する。
