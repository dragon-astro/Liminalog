# Purchase Readiness Audit

最終更新日：2026-06-28

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
| Release安全状態 | Done | `Scripts/validate-purchase-readiness.sh` が 2026-06-27 に成功。通常時は `--validate-release-gate-state closed`、Gate 1/2/3 ready時は対応するGate状態を検査する | Gate 1 以降で値を変えたら対応する ready check を再実行 |
| Release build | Done | `Scripts/validate-purchase-readiness.sh --release-build` が 2026-06-27 に working tree after `8373462` で成功。Release safety、StoreKit設定、法務URL、商品ドキュメント、App Store Connect転記シート、Release build をまとめて確認済み | App Store提出前はArchive/exportで再検証 |
| LP 利用規約ページ | Done | LP repo の `5d46da9 feat: add terms page` を `origin/main` へpush済み。2026-06-28 に `Scripts/validate-purchase-legal-urls.sh` で `https://liminalog-lp.vercel.app/terms` の 200 応答を確認 | 本文承認後にApp Store Connectへ登録 |
| LP プライバシーポリシーURL | Done | 2026-06-28 に `Scripts/validate-purchase-legal-urls.sh` で `https://liminalog-lp.vercel.app/privacy` の 200 応答を確認。`PurchaseConfiguration.current.privacyPolicyURL` はこのURLを参照 | カスタムドメインを使う場合はコード・docs・App Store Connectを同時更新 |
| App Store Connect商品準備 | Prepared | `AppStore/PurchaseProducts.md`、`AppStore/AppStoreConnectProductSetup.md`、`AppStore/AppStoreConnectProductConfirmation.md`、`--app-store-connect-tsv`、`--app-store-connect-confirmation-md`、`--validate-app-store-connect-confirmation-complete`。`Scripts/validate-purchase-readiness.sh --release-build` が 2026-06-27 に working tree after `8373462` でTSV出力、作成前転記シート、確認表テンプレートの整合を確認済み。2026-06-28 に商品メタデータ、レビュー情報、Sandbox反映待ちもGate 1確認表へ追加 | App Store Connect で商品8件と `Liminalog Pro` group を実作成し、各行とCreation Metadataを確認表へ記録してから `Scripts/validate-purchase-readiness.sh --gate1-ready` を通す |
| 商品ドキュメント整合性 | Done | `Scripts/validate-purchase-readiness.sh --release-build` が 2026-06-27 に working tree after `8373462` で成功。`--validate-products-doc`、`AppStore/AppStoreConnectProductSetup.md` の商品表、`--validate-app-store-connect-confirmation-template`、`--validate-product-source`、`--validate-premium-decoration-products-doc` も含めて確認済み | 商品・価格・種別を変えたら再実行 |
| StoreKitローカル設定 | Prepared | repo 直下に `liminalog.storekit` を追加。Shared scheme の Run に `liminalog.storekit` を接続。2026-06-28 に `4b17284 chore: stabilize storekit local qa config` で未使用 `subscriptionOffersKeyPair` を外し、`Scripts/prepare-storekit-local-qa.sh` と Simulator Debug build が成功 | Xcode editorが `.storekit` や scheme を書き換えた場合は再検査 |
| StoreKitローカル購入テスト | Prepared | `liminalog.storekit`、`AppStore/StoreKitLocalTesting.md`、`AppStore/PurchaseUIQA.md` に手順と `Local StoreKit QA Evidence Sheet` あり。`xcodebuild test` + `SKTestSession(contentsOf:)` は 2026-06-27 に `app.YasudaRyuga.Liminalog is not installed for development` で商品取得不可だったため自動テスト化しない。DEBUG購入画面には `StoreKit商品取得診断` があり、2026-06-27 に XcodeBuildMCP で要求ID 8、取得 0、有効 0、未取得ID一覧の表示を確認済み。2026-06-28 のXcodeBuildMCP再試行でも `loadedCount=0` のため、MCP/CLI経路は購入QA合格条件にしない。証跡表の完了状態は `--validate-storekit-local-qa-complete` で検査する | Xcode通常RunのStoreKit設定、またはApp Store Connect Sandboxで購入、復元、期限切れ、キャンセルを確認し、証跡表を埋めて `Scripts/validate-purchase-readiness.sh --gate2-ready` を通す |
| Release課金導線準備 | Prepared | `PurchaseReleaseChecklist.md` の Gate 1 / Gate 2 / Gate 3、`PurchaseConfiguration.current` の段階フラグ | App Store Connect と利用規約確定後に Gate 1 へ進める |
| 課金UI QA | Prepared | `AppStore/PurchaseUIQA.md`。2026-06-27 に XcodeBuildMCP / iPhone 17 Pro Simulator で DEBUG の設定入口表示と課金画面遷移、統計Proプレビュー表示、Release の設定入口非表示を確認。DEBUG 起動引数 `-LiminalogDebugPurchaseState` で無料 / Pro / ライフタイム / ライフタイム＋装飾パス / 装飾パスのみの統計表示を確認。課金画面表示後の主要タブ表示スモークも確認 | Local StoreKit購入操作、実機QA、既存タブの編集・スクロールを含む広範囲スモークを実行して証跡を残す |
| 統計Pro化設計 | Prepared | `Liminalog/Views/Profile/docs/19-statistics-pro-gate.md`、`StatisticsProPreviewView`、`StatisticsTabAccessPolicy`、`RootTabView` 統計タブ入口分岐、DEBUGの `Pro制限を試す` 導線、DEBUG 起動時の疑似課金状態注入。2026-06-27 に `StatisticsTabAccessPolicyTests` を含む対象テスト48件が成功し、iPhone 17 Pro Simulatorで無料/Pro/ライフタイム/ライフタイム＋装飾パス/装飾パスのみの統計表示を目視確認。Gate 3 QA証跡は `--validate-statistics-pro-qa-complete` で検査する | `featureRestrictionsAreEnabled` はまだ false。実機QA、Gate変更時のReleaseスモークQA、`Scripts/validate-purchase-readiness.sh --gate3-ready` は未完了 |
| 装飾課金データ設計 | Prepared | `Liminalog/Views/Profile/docs/20-premium-decoration-data.md`、`AppStore/PurchaseProducts.md` の単品装飾候補、`PremiumDecorationAccessPolicy`、`PremiumDecorationCatalog`、`PremiumDecorationEquippingPolicy`、`DecorationAccessDisplayPolicy`。2026-06-27 に既存の `PremiumDecorationCatalogTests` を含む対象テスト47件が成功。表示状態統合ロジック追加後は `build-for-testing` と purchase readiness が成功。単品装飾候補表は `PremiumDecorationCatalog` との整合検査対象。`Scripts/validate-purchase-readiness.sh --release-build` が working tree after `8373462` で、単品装飾が現行 `liminalog.storekit` とプロフィール装飾UIに混ざっていないことも検査済み | UI接続、App Store Connect 単品商品作成、StoreKitローカル購入QA、表示時フォールバックの実画面適用は未実装 |
| 既存機能への影響抑制 | Prepared | Release安全状態は閉じている。`featureRestrictionsAreEnabled == false`。装飾カタログと表示状態統合ロジックは UI 未接続で、`Scripts/validate-purchase-readiness.sh --release-build` が working tree after `8373462` でその状態を検査した。購入まわりのユニットテスト69件と装飾課金対象テスト47件が成功済み。今回追加分は `build-for-testing` と Release build でコンパイル確認済み | Gate変更時に既存タブのスモークQAが必要 |

## Commands To Re-Run Before Each Gate

```sh
Scripts/validate-purchase-readiness.sh
```

未完了Gateの不足項目を失敗終了せず一覧化する場合：

```sh
Scripts/validate-purchase-readiness.sh --status
```

The aggregate command runs:

```sh
swift Scripts/validate-storekit-config.swift --validate-products-doc
swift Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-template
swift Scripts/validate-storekit-config.swift --validate-products-doc AppStore/AppStoreConnectProductSetup.md
swift Scripts/validate-storekit-config.swift --validate-product-source
swift Scripts/validate-storekit-config.swift --validate-premium-decoration-products-doc
swift Scripts/validate-storekit-config.swift --validate-premium-decoration-ui-disconnected
swift Scripts/validate-storekit-config.swift --validate-premium-decoration-inactive liminalog.storekit
swift Scripts/validate-storekit-config.swift --validate-release-gate-state closed
swift Scripts/validate-storekit-config.swift --validate-xcode-scheme-storekit
swift Scripts/validate-storekit-config.swift --app-store-connect-tsv
swift Scripts/validate-storekit-config.swift --app-store-connect-confirmation-md
Scripts/validate-purchase-legal-urls.sh
git diff --check
```

Release build まで含める場合：

```sh
Scripts/validate-purchase-readiness.sh --release-build
```

App Store Connect 商品作成と確認表記入後、Gate 1 へ進む直前：

```sh
Scripts/validate-purchase-readiness.sh --gate1-ready
```

このコマンドは `AppStore/AppStoreConnectProductConfirmation.md` の全チェック済み状態と Release build まで確認する。利用規約本文の承認自体は人間が確認する。

StoreKit購入QAと課金UI QA証跡記入後、Gate 2 へ進む直前：

```sh
Scripts/validate-purchase-readiness.sh --gate2-ready
```

このコマンドは Gate 1 条件に加えて `AppStore/StoreKitLocalTesting.md` と `AppStore/PurchaseUIQA.md` のGate 2証跡が `pass` になっていることを確認する。

統計Pro制限QA証跡記入後、Gate 3 へ進む直前：

```sh
Scripts/validate-purchase-readiness.sh --gate3-ready
```

このコマンドは Gate 2 条件に加えて `Liminalog/Views/Profile/docs/19-statistics-pro-gate.md` のGate 3 QA証跡が `pass` になっていることを確認する。

`liminalog.storekit` 作成後：

```sh
Scripts/validate-purchase-readiness.sh --storekit=liminalog.storekit
swift Scripts/validate-storekit-config.swift liminalog.storekit
swift Scripts/validate-storekit-config.swift --validate-xcode-scheme-storekit
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
- `liminalog.storekit` は追加・検査済みで、Xcode scheme の Run へ接続済み。ただしローカル購入操作そのもののQAと `AppStore/StoreKitLocalTesting.md` の証跡表記入は未完了。
- 2026-06-27 に `xcodebuild test` で `SKTestSession(contentsOf:)` による自動購入テストを試したが、Simulator の `storekitd` が `app.YasudaRyuga.Liminalog is not installed for development` を返した。失敗するテストを残さないため、現時点では手動StoreKit QAへ戻す。
- 2026-06-27 と 2026-06-28 に XcodeBuildMCP の DEBUG 起動で「Proと応援」入口と画面遷移は確認済み。ただし XcodeBuildMCP 起動では StoreKit Configuration が適用されず商品取得は失敗表示だったため、Local StoreKit購入QAは未完了。DEBUG OSLog 診断で `Product.products(for:)` が `loadedCount=0` を返すことを確認し、アプリ側の商品種別フィルタではなくローカルStoreKit商品未注入が原因と切り分けた。
- 2026-06-27 に XcodeBuildMCP の Release 起動で、設定画面に「Proと応援」が表示されないことを確認済み。
- 2026-06-27 に購入基盤のユニットテスト69件は成功。ただしこれはStoreKit購入操作そのもののQAではない。
- 2026-06-27 に統計Pro入口分岐を含む対象テスト41件は成功。現行Release設定では無料ユーザーも `dashboard` のまま、将来の制限ON + 無料時だけ `proPreview` になることを確認済み。
- 2026-06-27 に XcodeBuildMCP / iPhone 17 Pro Simulator / Debug で `debug.purchase.enforceFeatureRestrictions = true`、`-LiminalogInitialRootTab dashboard` を指定して起動し、無料状態の統計タブが `StatisticsProPreviewView` になることを確認済み。確認後、同フラグは false に戻した。
- 2026-06-27 に DEBUG 限定の `-LiminalogDebugPurchaseState` / `LiminalogDebugPurchaseState` を追加。起動直後の疑似課金状態を目視QAしやすくする入口で、Release にはコンパイルされず実購入キャッシュにも保存しない。
- 2026-06-27 に XcodeBuildMCP / iPhone 17 Pro Simulator / Debug で `-LiminalogDebugPurchaseState pro` なら統計本体、`decorationPassOnly` なら `StatisticsProPreviewView` になることを確認済み。確認後、`debug.purchase.enforceFeatureRestrictions` は false に戻した。
- 2026-06-27 に XcodeBuildMCP / iPhone 17 Pro Simulator / Debug で `-LiminalogDebugPurchaseState lifetime` と `lifetimeWithDecorationPass` でも統計本体になることを確認済み。確認後、`debug.purchase.enforceFeatureRestrictions` は false に戻した。
- 2026-06-27 に装飾課金カタログ/アクセス判定を含む対象テスト47件は成功。ただし UI 接続と StoreKit 単品購入QAは未完了。
- 2026-06-27 に `DecorationAccessDisplayPolicy` と表示状態テストを追加。`xcodebuild build-for-testing` と `Scripts/validate-purchase-readiness.sh` は成功。Simulator の対象テスト実行は `The test runner hung before establishing connection.` と install/launch 待ちで完走しなかったため、実行成功としては扱わない。
- 2026-06-27 に `AppStore/PurchaseProducts.md` へ単品プレミアム装飾の商品候補を別枠で追加。まだ `PurchaseConfiguration.current.productIDs`、`liminalog.storekit`、購入UIには含めない。同日、`--validate-premium-decoration-products-doc` を追加して `PremiumDecorationCatalog` と候補表のズレを検出するようにした。
- 2026-06-27 に `Scripts/validate-purchase-readiness.sh --release-build` が成功。実行時点は working tree after `8373462` で、App Store Connect転記シート整合、Release safety、StoreKit設定、単品装飾の未接続状態、法務URL、Release build をまとめて確認した。課金作業と無関係な `Liminalog/Stores/CategoryStore.swift` の未コミット差分は残っていた。
- 2026-06-27 に `AppStore/AppStoreConnectProductConfirmation.md` を追加。App Store Connect で商品を作成した後に埋める専用確認表で、`--validate-app-store-connect-confirmation-template` により商品定義とのズレを検査する。
- 2026-06-27 に `--validate-app-store-connect-confirmation-complete` と `Scripts/validate-purchase-readiness.sh --gate1-ready` を追加。現時点では確認表が未記入のため、Gate 1 ready check は失敗するのが正しい。
- 2026-06-27 に `--validate-storekit-local-qa-complete`、`--validate-purchase-ui-qa-complete`、`Scripts/validate-purchase-readiness.sh --gate2-ready` を追加。現時点ではLocal StoreKit QA証跡表とPurchase UI QA証跡表が未記入のため、Gate 2 ready check は失敗するのが正しい。
- 2026-06-27 に `--validate-statistics-pro-qa-complete` と `Scripts/validate-purchase-readiness.sh --gate3-ready` を追加。現時点ではGate 3 QA証跡表が未記入のため、Gate 3 ready check は失敗するのが正しい。
- 2026-06-28 に App Store Connect 商品作成後の確認表へ Creation Metadata セクションを追加。商品ID/価格だけでなく、作成権限、表示名/説明/期間/販売状態、レビュー情報、Sandbox反映待ちも `--validate-app-store-connect-confirmation-complete` の未完了チェック対象にした。
- 実機QAは、既存リリースデータへ触れる可能性があるため明示承認後に行う。
- Release build 成功時点のワークツリーには、課金作業と無関係な `Liminalog/Stores/CategoryStore.swift` の未コミット差分が残っていた。この差分は課金コミットには含めない。

## Next Best Steps

1. Simulator DEBUG を Xcode からRunし、`AppStore/PurchaseUIQA.md` の Local StoreKit QA を実施する。
2. App Store Connect で商品を作成し、`swift Scripts/validate-storekit-config.swift --app-store-connect-confirmation-md` の Confirmation Sheet と Creation Metadata を埋め、`Scripts/validate-purchase-readiness.sh --gate1-ready` を通す。
3. 利用規約本文を承認し、LP の `/terms` を App Store Connect に登録する。
4. Gate 1 のコード変更だけを入れ、Releaseで購入導線がまだ出ないことを確認する。
5. Local StoreKit購入操作ができる環境で、Pro / ライフタイム / 装飾パス / 支援の購入・復元・期限切れを確認し、`Scripts/validate-purchase-readiness.sh --gate2-ready` を通す。
6. 統計Pro制限をReleaseでONにする前に、Gate 3 QA証跡を埋めて `Scripts/validate-purchase-readiness.sh --gate3-ready` を通す。
7. プレミアム装飾を `UnlockGalleryView` へ合流する前に、表示モデルとフォールバック適用点を小さく実装する。
