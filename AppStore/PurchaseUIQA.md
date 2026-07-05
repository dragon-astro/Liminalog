# Purchase UI QA

Liminalog の課金UIを既存機能に影響させず確認するための手順。課金導線は段階的に開くため、今できる確認と StoreKit / App Store Connect 準備後の確認を分ける。

現時点でどのQAが未完了かは `AppStore/PurchaseReadinessAudit.md` に集約する。

## Safety Rules

- 既存ユーザーのリリースデータが入った実機にインストールして確認する場合は、事前に明示承認を取る。
- 手元確認はまず Simulator の DEBUG ビルドで行う。
- `.storekit` がない間は実購入フローを通さず、設定の DEBUG セクションにある「課金状態を試す」で表示状態だけを見る。
- 起動直後の画面を撮る時だけ、DEBUG 起動引数 `-LiminalogDebugPurchaseState pro|lifetime|lifetimeWithDecorationPass|decorationPassOnly` を使って疑似課金状態を入れてよい。これは実購入状態やキャッシュを保存しない。
- 審査用スクリーンショット候補を作る時だけ、DEBUG 起動引数 `-LiminalogDebugStoreKitProducts loaded` を使って参照価格の商品一覧を表示してよい。これは見た目確認専用であり、StoreKit商品取得・購入・復元QAの証跡には使わない。
- `PurchaseConfiguration.current.purchaseEntryPointIsEnabled == false` の間、Release では設定に「Proと応援」が出ないことを正とする。
- `featureRestrictionsAreEnabled == false` の間、統計、記録、カレンダー、友達、プロフィールカード、シェアの既存機能はロックしない。
- StoreKit の購入、復元、サブスクリプション管理を試すのは、`liminalog.storekit` 作成後、または App Store Connect Sandbox 準備後に限る。

## Current Pre-StoreKit QA

対象：`.storekit` がまだない状態。目的は、既存機能を変えずに課金UIの骨格だけ確認すること。

1. DEBUG ビルドで起動する。
2. 設定を開き、「Proと応援」が表示されることを確認する。
3. 「Proと応援」を開き、準備中の説明、規約リンク、未設定項目が表示されることを確認する。
4. 設定 > デバッグ > 課金状態を試す を `実際の状態` / `Proサブ` / `ライフタイム` / `ライフタイム＋装飾パス` / `装飾パスのみ` に切り替える。起動直後から特定状態を見たい時は `-LiminalogDebugPurchaseState` を使う。
5. 各状態で「Proと応援」のステータス文言と表示される購入候補が自然か確認する。
6. 設定 > デバッグ > Pro制限を試す をONにし、無料状態では統計タブが軽いPro案内になることを確認する。
7. Proサブ / ライフタイムでは統計タブが既存の統計画面になること、装飾パスのみではPro案内になることを確認する。
8. ホーム、カレンダー、統計、友達、プロフィールを一通り開き、既存UIの入口、スクロール、編集操作が変わっていないことを確認する。
9. `実際の状態` に戻し、`Pro制限を試す` をOFFにして、デバッグの疑似状態を残さない。

この段階では商品取得、購入、復元、サブスクリプション管理の成功は確認対象外。

## Release Hidden-Entry QA

対象：`purchaseEntryPointIsEnabled == false` の Release ビルド。目的は、アップデートしても既存体験が変わらないことを確認すること。

1. Release ビルドで起動する。
2. 設定に「Proと応援」が表示されないことを確認する。
3. 起動直後、バックグラウンド復帰時に StoreKit 商品取得や権利更新由来のメッセージが出ないことを確認する。
4. ホーム、カレンダー、統計、友達、プロフィールカード、設定の既存項目を開く。
5. 統計タブが現行通り表示され、Pro案内やロック画面に変わっていないことを確認する。
6. カレンダーの月間、日間タイムライン、週間タイムラインの切り替え、横スワイプ、予定編集が現行通り動くことを確認する。

ビルド前に、Release の課金入口がソース上で閉じていることも確認する。

```sh
swift Scripts/validate-storekit-config.swift --validate-release-gate-state closed
```

## Local StoreKit QA

対象：`liminalog.storekit` 作成後。目的は、購入画面とローカル権利反映を確認すること。

完了証跡は `AppStore/StoreKitLocalTesting.md` の `Local StoreKit QA Evidence Sheet` に残す。証跡表が埋まるまでは `AppStore/PurchaseReadinessAudit.md` の `StoreKitローカル購入テスト` を `Done` にしない。

事前条件：

- `swift Scripts/validate-storekit-config.swift --validate-products-doc` が成功している。
- `swift Scripts/validate-storekit-config.swift --validate-premium-decoration-products-doc` が成功している。
- `swift Scripts/validate-storekit-config.swift liminalog.storekit` が成功している。
- Xcode scheme の Run > Options > StoreKit Configuration に `liminalog.storekit` が設定されている。

確認項目：

- 商品取得成功時、Pro、Pro機能 買い切り、装飾パス、支援が意図した順で表示される。
- 価格表示が `AppStore/PurchaseProducts.md` の参照価格と大きくずれていない。
- 年額Proに初回1週間無料体験が表示され、月額Proや装飾パスには無料体験が付かない。
- Pro月額 / Pro年額購入後、ステータスが Pro 有効になる。
- Pro機能 買い切り購入後、ステータスがPro機能 買い切り所有になる。
- Pro機能 買い切り所有後だけ装飾パスが表示される。
- 装飾パスのみでは Pro 機能権利にならない。
- 支援チップ購入後、恒久権利は増えず、完了メッセージだけ表示される。
- 購入キャンセルでエラー表示にならない。
- 復元なしは「復元できる購入は見つかりませんでした。」として扱われる。
- 復元ありで権利が再読込される。
- サブスクリプション管理ボタンが StoreKit 管理画面を開ける。

## Real Device QA

実機で確認する時は、Simulator での確認が終わってから行う。

1. 使用端末、OS、Apple ID / Sandbox Account、ビルド種別、git SHA を記録する。
2. リリース済みデータが入った個人端末に上書きする場合は、ユーザーに確認してから実行する。
3. 可能なら確認用端末か、データを失ってもよい Simulator / Sandbox 環境を使う。
4. 最初に既存機能のスモーク確認を行う。
5. 課金UIを開いた後、戻った画面で既存のタブ、ナビゲーションバー、タブバー、スクロールが変わっていないことを確認する。
6. 購入テスト後は、App Store の Sandbox 購入履歴とアプリ内表示が一致することを確認する。

## Gate 2 Purchase UI QA Evidence Sheet

Gate 2 で `purchaseEntryPointIsEnabled` と `backgroundEntitlementRefreshIsEnabled` を true にする直前に埋める。入力後は `swift Scripts/validate-storekit-config.swift --validate-purchase-ui-qa-complete` を通す。Gate 2 へ進む直前は `Scripts/validate-purchase-readiness.sh --gate2-ready` を使う。
`fill manually`、`TBD`、`TODO`、空欄、`screenshot / note`、`command output`、`DEBUG / Release`、`local .storekit / Sandbox` のようなテンプレ値が残っている場合は未完了として扱う。

Gate 2 のコード状態で購入UI QAを始める直前は、次を実行して App Store Connect 確認、Local StoreKit QA 証跡、Gate 2 状態、StoreKit 設定、法務URLが揃っていることを確認する。

```sh
Scripts/prepare-purchase-ui-qa.sh
```

| 項目 | 記録 |
|---|---|
| Git SHA |  |
| Build | DEBUG / Release |
| Device / OS |  |
| StoreKit Source | local `.storekit` / Sandbox |
| Purchase Entry | visible |
| Feature Restrictions | off |
| Tester |  |
| Date |  |

| Case | Required Result | Evidence | Result | Notes |
|---|---|---|---|---|
| Release購入入口 | Gate 2設定のReleaseで設定に「Proと応援」が表示される | screenshot / note |  |  |
| 商品取得と診断 | 商品が表示される。失敗時はDEBUG診断で原因を切り分けられる | screenshot / note |  |  |
| 購入画面表示 | Pro、Pro機能 買い切り、装飾パス、支援、規約、復元、管理が意図した位置に出る。年額Proの初回1週間無料体験が分かる | screenshot / note |  |  |
| 復元とサブスク管理 | 復元とサブスクリプション管理がStoreKit操作として実行できる | screenshot / note |  |  |
| 既存タブスモーク | 購入画面から戻ってもホーム、カレンダー、統計、友達、プロフィールの入口とスクロールが変わらない | screenshot / note |  |  |
| 既存機能の無料維持 | `featureRestrictionsAreEnabled == false` では統計、記録、カレンダー、友達、シェアがロックされない | screenshot / note |  |  |
| 疑似課金状態リセット | DEBUGの疑似課金状態やPro制限テストを実際の状態/OFFへ戻せる | screenshot / note |  |  |
| 実機データ安全 | リリース済みデータが入った実機で確認する場合は事前承認を記録し、未実施なら安全なSimulator/Sandboxで確認したことを記録する | screenshot / note |  |  |

## Evidence Template

| 項目 | 記録 |
|---|---|
| Git SHA |  |
| Build | DEBUG / Release |
| Device |  |
| OS |  |
| StoreKit Source | none / local `.storekit` / Sandbox |
| DEBUG Product Diagnostics | not shown / loaded / empty / mismatch |
| Purchase Entry | hidden / visible |
| Feature Restrictions | off / on |
| Result | pass / fail |
| Notes |  |

## Evidence Log

| Date | Git SHA | Build | Device | StoreKit Source | Purchase Entry | Feature Restrictions | Result | Notes |
|---|---|---|---|---|---|---|---|---|
| 2026-06-27 | working tree after `6007e98` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | none | visible | DEBUG forced on | pass | `debug.purchase.enforceFeatureRestrictions = true` と `-LiminalogInitialRootTab dashboard` で起動し、無料状態の統計タブが `StatisticsProPreviewView` になることを確認。確認後フラグはOFFへ戻した。 |
| 2026-06-27 | working tree after `497ca6a` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | none | visible | DEBUG forced on | pass | `-LiminalogDebugPurchaseState pro` で統計本体、`decorationPassOnly` で `StatisticsProPreviewView` が表示されることを確認。確認後フラグはOFFへ戻した。 |
| 2026-06-27 | working tree after `a2c3b34` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | none | visible | DEBUG forced on | pass | `-LiminalogDebugPurchaseState lifetime` と `lifetimeWithDecorationPass` で統計本体が表示されることを確認。確認後フラグはOFFへ戻した。 |
| 2026-06-27 | `4230b478` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | scheme expects local `.storekit` | visible | off | blocked | XcodeBuildMCP で設定の `Proと応援` から課金画面へ遷移できることは確認。商品取得は失敗表示のため、Local StoreKit購入操作QAはXcode通常Run待ち。 |
| 2026-06-27 | working tree after `8373462` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | scheme expects local `.storekit` | visible | off | blocked | DEBUG OSLog 診断で `Product.products(for:)` の戻りが `loadedCount=0` であることを確認。アプリ側の商品種別フィルタではなく、XcodeBuildMCP 起動にローカル StoreKit Configuration が適用されていない状態。 |
| 2026-06-27 | working tree after `084ddd5` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | scheme expects local `.storekit` | visible | off | pass | XcodeBuildMCP で設定の `Proと応援` へ遷移し、`StoreKit商品取得診断` に要求ID 8、取得 0、有効 0、未取得ID一覧が出ることを確認。商品注入がないため購入操作QAは未完了だが、DEBUG診断表示は確認済み。Releaseには出ない。 |
| 2026-06-27 | `6c055a6c` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | failed local `.storekit` attempt | visible | off | pass | 課金画面表示後にホーム、カレンダー、統計、友達、プロフィールへ移動できることを確認。統計はPro案内ではなく既存ダッシュボード表示。編集や購入操作は未実施。 |
| 2026-06-28 | `3925ef7` + dirty `CategoryStore.swift` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | scheme expects local `.storekit` | visible | off | blocked | XcodeBuildMCP `build_run_sim` で課金画面まで遷移できるが、OSLog は `loadedCount=0` / `validCount=0`。MCP/CLI経路ではStoreKit Configurationが注入されないため、Local StoreKit購入操作QAはXcode通常Run待ち。 |

## Stop Conditions

次のどれかが起きたら、購入導線を開く前に修正する。

- Release で `purchaseEntryPointIsEnabled == false` なのに「Proと応援」が出る。
- Release で既存機能がPro向け表示やロック表示に変わる。
- 課金UIを開いただけでホーム、カレンダー、統計、友達、プロフィールの操作が重くなる。
- DEBUG の疑似課金状態が `実際の状態` に戻しても残る。
- Product ID、商品種別、サブスクリプショングループが `AppStore/PurchaseProducts.md` と一致しない。
