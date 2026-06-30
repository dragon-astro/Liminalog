# StoreKit Local Testing

Liminalog のローカル課金テスト準備メモ。repo 直下に `liminalog.storekit` を置き、検査スクリプトで商品IDの抜けを確認する。Xcode の StoreKit editor がファイルを更新した場合は、必ず検査を再実行してからコミットする。

## 1. StoreKit Configuration を作成する

1. repo 直下の `liminalog.storekit` を使う。
2. Xcode で `Liminalog.xcodeproj` を開く。
3. Shared scheme の Run > Options > StoreKit Configuration に `liminalog.storekit` が設定されていることを確認する。
4. Xcode が `.storekit` を書き換えた場合は、差分を確認してから `Scripts/validate-purchase-readiness.sh` を実行する。

`xcrun storekit` は現在の開発環境では見つからないため、CLI生成は使わない。

## 2. 登録する商品

| Product ID | 種別 | 参照価格 | Subscription Group |
|---|---|---:|---|
| `liminalog.pro.monthly` | Auto-Renewable Subscription | ¥400 | `Liminalog Pro` |
| `liminalog.pro.yearly` | Auto-Renewable Subscription | ¥2,900 | `Liminalog Pro` / Introductory Offer: Free Trial / 1 Week |
| `liminalog.lifetime` | Non-Consumable | ¥7,800 | - |
| `liminalog.decorations.monthly` | Auto-Renewable Subscription | ¥200 | `Liminalog Pro` |
| `liminalog.decorations.yearly` | Auto-Renewable Subscription | ¥1,500 | `Liminalog Pro` |
| `liminalog.support.small` | Consumable | ¥120 | - |
| `liminalog.support.medium` | Consumable | ¥600 | - |
| `liminalog.support.large` | Consumable | ¥1,000 | - |

転記元は `PurchaseProductID.appStoreConnectSpecifications`。この表だけを先に変えない。

## 3. 作成後の検査

まず App Store Connect 用メモが期待商品リストと一致しているか確認する。

```sh
swift Scripts/validate-storekit-config.swift --validate-products-doc
```

`.storekit` を更新したら、repo root で次を実行する。

```sh
swift Scripts/validate-storekit-config.swift liminalog.storekit
```

Shared scheme が `liminalog.storekit` を参照しているかだけを確認する場合：

```sh
swift Scripts/validate-storekit-config.swift --validate-xcode-scheme-storekit
```

課金リリース前チェック一式として確認する場合：

```sh
Scripts/validate-purchase-readiness.sh
```

Xcode通常Runでローカル購入QAを始める直前のpreflight：

```sh
Scripts/prepare-storekit-local-qa.sh
```

クリーンな課金チェックポイントだけでQAする場合は、未コミット差分を失敗扱いにする。

```sh
Scripts/prepare-storekit-local-qa.sh --strict-clean
```

期待商品を確認したいだけなら次を使う。

```sh
swift Scripts/validate-storekit-config.swift --expected
```

スクリプトは、予定している商品ID、`Liminalog Pro` のサブスクリプショングループ、サブスク商品の `billingPlans` が StoreKit Configuration に含まれるか確認する。加えて readiness check では、shared scheme の Run 設定が `liminalog.storekit` を参照しているかも確認する。Xcode の内部表現が変わる可能性があるため、商品種別は確認できない場合に warning として扱う。

## 4. 自動テスト化について

2026-06-27 に `xcodebuild test` から `SKTestSession(contentsOf:)` を使う自動購入テストを試したが、Simulator の `storekitd` が `app.YasudaRyuga.Liminalog is not installed for development` を返し、`Product.products` が空になった。失敗するテストをリポジトリに残さないため、現時点ではXcode RunのStoreKit Configurationで手動QAする。

XcodeBuildMCP / CLI の build-install-launch 経路は、shared scheme に `liminalog.storekit` が設定されていても Xcode の StoreKit Configuration を実行時注入しない。MCPで課金画面まで開けても `Product.products(for:)` が `loadedCount=0` の場合は、アプリ側の商品種別フィルタではなく実行経路の問題として扱う。

2026-06-28 に `xcodebuild -help` を確認したが、Run 時の StoreKit Configuration をCLIから明示注入するオプションは見当たらなかった。Local StoreKit 購入QAは引き続き Xcode 通常 Run、または App Store Connect Sandbox を正規経路にする。

Simulator の Octane persistence へ `.storekit` を直コピーする検証は、通常商品だけなら読めることがあるが、サブスクリプションは Xcode の変換後形式と差が出る。ローカル購入QAの正規手順は Xcode 通常 Run とし、`subscriptionOffersKeyPair` は introductory / promotional / offer code / winback offer を実際に設定するまで `.storekit` に含めない。

購入導線や機能制限の安全弁が開いていないことも確認する。

```sh
xcodebuild -project Liminalog.xcodeproj -scheme Liminalog -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" -derivedDataPath /private/tmp/LiminalogMonetizationStoreKitDerivedData -only-testing:LiminalogTests/PurchaseConfigurationTests -only-testing:LiminalogTests/PurchaseOfferingCatalogTests -only-testing:LiminalogTests/PurchaseAccessPolicyTests -only-testing:LiminalogTests/PurchaseEntitlementTests -only-testing:LiminalogTests/PurchaseRefreshPolicyTests test
```

### Xcode Normal Run 手順

ローカル購入QAはこの手順を正とする。

1. `git status --short` を確認し、課金QAと無関係なアプリコード差分がある場合は、証跡に dirty 状態を記録する。可能ならクリーンな課金チェックポイントで実施する。
2. `Scripts/prepare-storekit-local-qa.sh` を実行し、StoreKit設定、scheme参照、Release gate、未接続の単品装飾、差分の空白チェックが通ることを確認する。
3. Xcode で `Liminalog.xcodeproj` を開く。
4. Scheme を `Liminalog`、Run destination を購入QA用 Simulator にする。
5. Edit Scheme > Run > Options > StoreKit Configuration が `liminalog.storekit` であることを確認する。
6. Product > Run で起動する。
7. 設定 > Proと応援 を開く。
8. DEBUG の `StoreKit商品取得診断` が `要求ID 8 / 取得 8 / 有効 8` 相当で、未取得IDと型不一致が空であることを確認する。
9. `StoreKit商品取得診断` の `証跡` 行を `DEBUG Product Diagnostics` 欄へ貼る。期待値は `requestedCount=8 loadedCount=8 validCount=8 missingCount=0 rejectedCount=0`。
10. 取得が0件の時は、XcodeのRun経路か、StoreKit Configurationの選択状態を先に疑う。MCP/CLI起動の結果だけでアプリ側バグ扱いしない。

## 5. ローカル購入テストケース

- 商品取得成功：購入画面に Pro、Pro機能 買い切り、装飾パス、支援が表示される。
- DEBUG商品取得診断：購入画面の `StoreKit商品取得診断` で要求ID数、取得数、有効数、未取得ID、型不一致/未対応IDを確認する。
- Pro月額購入：`entitlements.isProActive == true` になり、サブスク状態として表示される。
- Pro年額購入：月額と同じ Pro 権利になる。
- Pro年額無料体験：購入確認画面またはStoreKitテスト上で、初回1週間無料体験が年額Proにだけ適用される。
- Pro機能 買い切り購入：`hasLifetime == true` になり、Pro権利は永続扱いになる。
- 装飾パス購入：`hasDecorationRental == true` になり、Pro機能権利とは分離される。
- 支援チップ購入：権利を恒久付与せず、購入完了メッセージだけ表示される。
- 復元なし：エラーではなく、復元できる購入がない状態として扱う。
- 復元あり：Pro機能 買い切りやサブスクの権利が再読込される。
- サブスク期限切れ：Pro/装飾レンタル権が外れる。
- 商品種別不一致：アプリ側の商品候補と権利キャッシュから外れる。

## 6. Local StoreKit QA Evidence Sheet

この表を埋めるまでは、`AppStore/PurchaseReadinessAudit.md` の `StoreKitローカル購入テスト` を `Done` にしない。
入力後は `swift Scripts/validate-storekit-config.swift --validate-storekit-local-qa-complete` を通す。Gate 2 へ進む直前は `Scripts/validate-purchase-readiness.sh --gate2-ready` を使う。
`fill manually`、`TBD`、`TODO`、空欄、`screenshot / note`、`command output`、`pass / fail` のようなテンプレ値が残っている場合は未完了として扱う。

### XcodeBuildMCP Attempt Log

| Date | Git SHA | Build | Device / OS | StoreKit Source | Result | Notes |
|---|---|---|---|---|---|---|
| 2026-06-27 | `4230b478` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | scheme expects `liminalog.storekit` | blocked | XcodeBuildMCP でビルド・起動し、設定の `Proと応援` から課金画面へ遷移できることは確認。商品取得は `商品情報を取得できませんでした` 表示になったため、購入操作QAは未完了のまま。Xcode の通常 Run で StoreKit Configuration を適用して再確認する。 |
| 2026-06-27 | working tree after `8373462` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | scheme expects `liminalog.storekit` | blocked | DEBUG OSLog 診断を追加して XcodeBuildMCP で再確認。`LiminalogPurchaseDebug productLoad ... loadedCount=0 ... validCount=0` だったため、商品種別フィルタではなく `Product.products(for:)` 自体にローカルStoreKit商品が入っていない。XcodeBuildMCP 起動では StoreKit Configuration が適用されないため、Xcode通常RunまたはSandboxで購入操作QAを行う。 |
| 2026-06-27 | working tree after `084ddd5` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | scheme expects `liminalog.storekit` | blocked | DEBUG購入画面の `StoreKit商品取得診断` で、要求ID 8、取得 0、有効 0、未取得ID一覧が表示されることを XcodeBuildMCP で確認。XcodeBuildMCP 起動では商品注入がないため購入操作QAは未完了だが、手動QA時の切り分け表示は確認済み。Releaseには出ない。 |
| 2026-06-28 | `3925ef7` + dirty `CategoryStore.swift` | DEBUG | iPhone 17 Pro Simulator / iOS 26.5 | scheme expects `liminalog.storekit` | blocked | XcodeBuildMCP `build_run_sim` で設定 > `Proと応援` へ遷移。OSLog は `LiminalogPurchaseDebug productLoad requested=[8 ids] loadedCount=0 loaded=[] validCount=0 valid=[]`。MCP/CLI経路ではStoreKit Configurationが注入されないため、ローカル購入操作QAは未完了。 |

| 項目 | 記録 |
|---|---|
| Git SHA |  |
| Build | DEBUG |
| Device / OS |  |
| Run Path | Xcode normal Run |
| Xcode |  |
| StoreKit Configuration | `liminalog.storekit` |
| StoreKit Config Validation | pass / fail |
| DEBUG Product Diagnostics | fill manually with the StoreKit商品取得診断 > 証跡 line |
| Tester |  |
| Date |  |

| Case | Required Result | Evidence | Result | Notes |
|---|---|---|---|---|
| 商品取得 | Pro、Pro機能 買い切り、装飾パス、支援が意図した順で表示される。ただし装飾パスはPro機能 買い切り所有時だけ表示される | screenshot / note |  |  |
| Pro月額購入 | ステータスがPro有効になり、統計Pro権利が有効になる | screenshot / note |  |  |
| Pro年額購入 | 月額と同じPro権利になる | screenshot / note |  |  |
| Pro年額無料体験 | `liminalog.pro.yearly` の購入確認で初回1週間無料体験が表示/適用され、月額Proや装飾パスには無料体験が付かない | screenshot / note |  |  |
| Pro機能 買い切り購入 | ステータスがPro機能 買い切り所有になり、Pro権利が永続扱いになる | screenshot / note |  |  |
| Pro機能 買い切り後の装飾パス表示 | Pro機能 買い切り所有後だけ装飾パスが購入候補に出る | screenshot / note |  |  |
| 装飾パス購入 | `hasDecorationRental == true` 相当の表示になり、Pro機能権利にはならない | screenshot / note |  |  |
| 支援チップ購入 | 恒久権利は増えず、購入完了メッセージだけ表示される | screenshot / note |  |  |
| 購入キャンセル | エラー扱いのメッセージや壊れた進行状態が残らない | screenshot / note |  |  |
| 復元なし | 「復元できる購入は見つかりませんでした。」として扱われる | screenshot / note |  |  |
| 復元あり | Pro機能 買い切りや有効サブスクの権利が再読込される | screenshot / note |  |  |
| サブスク期限切れ | Pro/装飾レンタル権が外れる | screenshot / note |  |  |
| サブスク管理 | StoreKitの管理画面を開ける | screenshot / note |  |  |
| 既存機能スモーク | 購入後にホーム、カレンダー、統計、友達、プロフィールの既存操作が変わらない | screenshot / note |  |  |
| 商品種別不一致防止 | `Scripts/validate-purchase-readiness.sh` が成功している | command output |  |  |

失敗した行が1つでもある場合は、購入導線をReleaseで開かない。

## 7. Release への接続条件

StoreKit ローカル購入テストが通っても、次が揃うまでは Release の購入導線は開かない。

- App Store Connect の商品IDと商品種別を確認する。
- `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` を true にする。
- `PurchaseConfiguration.current.subscriptionGroupName` に `Liminalog Pro` を設定する。
- 利用規約本文を承認し、`termsOfUseURL` に HTTPS URL を設定する。
- その後で初めて `purchaseEntryPointIsEnabled` を true にする。
- 既存機能のPro制限はさらに別チェックポイントで `featureRestrictionsAreEnabled` を true にする。
