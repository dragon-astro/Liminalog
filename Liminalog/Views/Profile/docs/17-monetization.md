# 17. マネタイズ方針 v0

Liminalog の課金設計の初版。**戦略・価格・機能ティア・packaging・接客・指標**を一望できる土台。
前提：[13-visual-identity.md](13-visual-identity.md)（世界観＝静謐・搾取的にしない）、[09-profile-design.md](09-profile-design.md)（装飾アイテム経済）、[16-collection-decoration-art.md](16-collection-decoration-art.md)（装飾の作り）。

> ステータス：**方針合意済み・一部実装中**。StoreKit2 の購入土台・権利判定・設定内導線は `codex/monetization-foundation` で着手済み。実際の機能制限、計測、利用規約URL、LP更新は別タスク。
> 開発者は学生・個人。固定費は実質 **ADP 年¥15,000前後のみ**（CloudKit/App Groups でサーバー代≒0）。まず ADP 回収、加えて“α”の収入を狙う。

---

## 0. 北極星（戦略）

**苦痛で払わせない。欲しさ（自己表現・見せる価値・深さ・支援）で払わせる。**

- **フリーの堀を広く**：記録・カレンダー・友達・シェアは無料で“使い勝手最高”に。**カレンダーアプリ置き換え→スタンダード化→市場拡大**を狙う。
- 市場が大きいほど **装飾の「人に見せる価値」が増す**＝装飾課金が伸びる。フリーユーザーは取りこぼしでなく「拡散＋装飾が映える観客」。
- 限界コスト≒0（デジタル装飾・Appleインフラ）。だから**サブに装飾“使い放題”を盛って入りたくさせる**のが合理的。
- 一行判断：**「締め出してないか？ 拡散とコア習慣を削ってないか？」**

---

## 1. 価格表（v0・日本／App Store価格帯）

| 商品 | 価格 | 備考 |
|---|---|---|
| 月額サブスク | **¥400** | 入口。×10アンカーで年が割安に見える |
| 年額サブスク | **¥2,900** | 入口。無料体験は未確定。付ける場合はApp Store Connect・アプリ内文言・QA表を同時更新。実質¥242/月・約40%off。**¥3,000未満の「ためらいの壁」を越えさせない**＝無名・初アプリは信用の壁が既に高いので価格の壁を重ねない |
| ライフタイム（買い切り） | **¥6,800** | 主力（高意欲層の永久回収）。年額約2.3年分。**機能のみ永久・装飾は完全分離（甘味なし）**。買う人は意思決定済み＝価格感度が低いのでここで正当な額を取る |
| 装飾サブ（**買い切り所有者限定**） | **¥200/月・¥1,500/年** | 機能は買い切り済みなので**装飾レンタル使い放題だけ**を格安で。二重課金回避＋買い切り勢から継続収益 |
| プレミアム装飾：フレーム/カード | **¥120** | 永久所有。衝動買い帯 |
| プレミアム装飾：テーマ | **¥500** | 永久所有。ワンコイン |
| バンドル（任意） | テーマ3個 **¥980** / 装飾セット **¥480** | ARPU↑ |
| 支援チップ | **¥250 / ¥600 / ¥1,200** | 「好きだから応援」 |

- **Apple Small Business Program 登録で手数料15%**（年商$1M未満）。
- 価格は出発点。**転換率と離脱を見て上下**（緩めるのは楽・上げるのは新規からのみ）。
- 損益分岐：年¥2,900→純≈¥2,465で**約6人/年**、ライフタイム¥6,800→純≈¥5,780で**約3人/年**で ADP 回収。

---

## 2. Packaging：所有 vs 使い放題で住み分け

| 層 | 機能 | 装飾 | 性質 |
|---|---|---|---|
| **無料** | コア＋友達＋シェア | 継続で得る装飾（所有） | 締め出さない |
| **Proサブ** | 広告オフ＋深さ機能 | **全プレミアム装飾 使い放題（契約中＝レンタル装着）** | 使い放題で入りたくさせる |
| **ライフタイム** | 広告オフ＋深さ機能を**永久** | **完全分離・含まない**（単品で所有 or サブでレンタル） | 機能の買い切り。装飾込みサブより安い“機能だけ”の道 |
| **装飾サブ（買い切り所有者限定）** | （買い切り済み＝所有） | **全プレミアム装飾 使い放題（レンタル）** | 機能ぶんを二重課金しない格安サブ。買い切り後の継続収益 |
| **単品購入** | — | プレミアム装飾を**永久所有**（解約後も残る） | 「この見た目だけ欲しい/お気に入りを残す」を回収 |
| **リワード広告** | 単発お試し（じらし） | — | 離脱させず欲しさを育てる |

**キモ＝「サブ＝全部レンタルし放題／単品＝欲しいものを永久所有」**。この対比で単品(¥120/¥500)がサブと共存する理由が立つ（ライフタイム勢・非課金者・“見た目だけ欲しい”層を回収）。

---

## 3. 機能ティア（v0）

### 無料死守（縛ると funnel／ネットワーク／習慣が死ぬ）
- チャプター記録（無制限）・カテゴリ記録・1分ルール
- ホーム/今日・**当日スコア・ストリーク**・自分のタイムライン
- カレンダー（月/デイ）で**過去含む自分の予定・記録の閲覧**（カレンダー置き換えの生命線）
- 記録ウィジェット（小/中）
- **友達 無制限**（フォロー・ランキング・友達タイムライン閲覧）
- **デイリーカード生成＋シェア**（拡散エンジン・絶対に縛らない）
- 継続で得る装飾・ストリーク通知
- **記録ボード（テーブル/カテゴリセット）：無料 2枚**（平日/休日の切替の便利さに気づかせる。3枚目からPro）
- **カスタムカテゴリ：20まで**（実効ゲートはボード枚数。20は整理目的の上限）

### Pro（深さ・便利・パワー＝高WTP×成長に無関係）
- **統計タブ 丸ごと**（集計・長期トレンド・複数指標）※当日スコア/ストリークは無料据え置き
- 複数人比較 / 2人比較 / シンクロハイライト（Phase4）
- **エクスポート**（CSV・画像）
- 追加ウィジェット種（友達系・Large ミックス）
- アプリロック（FaceID）
- HealthKit 自動検知（Phase4）
- **記録ボード 無制限**（平日/休日/試験期間…の切替）
- プレミアム装飾 レンタル使い放題

### 単品（永久所有・誰でも）
- プレミアム フレーム/カード ¥120・テーマ ¥500（**獲得装飾とは別カタログ**）

### リワード広告（任意・じらし運用）
- **統計タブを24時間解放／7日に1回**（代替でなく欲しさを育てる。ぼかし予告とセット）
- 単発エクスポート・凝ったシェアカード1枚・テーマ今日だけ試着 等

---

## 4. 装飾カタログ分離ルール（魂を守る）

- **獲得装飾（継続＝longevity）** と **プレミアム装飾（課金）** は**別カタログ**。
- 獲得装飾は**課金で売らない/混ぜない**（フレックス経済・継続インセンティブを壊さない）。
- プレミアム装飾＝「スタイル/支援」であって「実績」ではない見せ方（pay-to-win に見せない）。
- 作りの基準は doc 16（liminal×豪華・ランク連動）。

---

## 5. レンタル時の解約挙動＋接客（重要・離脱→課金機会に反転）

- **レンタルの明示必須**：サブ中のみ装着できる装飾は「**契約中のみ**」とUI明記。
- **解約/失効時**：装着中のプレミアム装飾は無料デフォルトへ静かに戻す＋優しい告知（「再開すれば戻ります」）。
- **“好きになった瞬間”に所有導線**：装着画面で「**このテーマを永久に持つ → ¥500**」。WTP最大の瞬間に出す。
- **解約時を“救う”に変える**：失効時「このテーマ、**¥500で残せます**」＝ウィンバック課金。
- **コレクションで状態バッジ**：所有／サブ中のみ／未所持(¥120・¥500)。所有の満足が離脱の罪悪感を下げる。

---

## 6. 縛り方の原則・ガードレール

- 縛るのは **右下（高WTP×成長に無関係）** だけ。
- 縛り方は弱い順：**数量/期間の余裕枠 → リワード（じらし） → ハードロック**。
- ガードレール（外さない）：
  - **自分の生データを人質にしない**（過去の閲覧は無料）。
  - **シェア／友達入口は無料**（成長エンジン）。広告を置かない聖域＝デイリーカード・ホーム記録・友達タイムライン。
  - 無料単体で完結（ソロ完結・CLAUDE.md）。
  - 装飾/支援＝**離脱ゼロの収益**を主土台に。機能ゲートは控えめに。

---

## 7. 見張る指標と判断ルール

- 収益系：ペイウォール表示→転換率、ARPPU、課金者数、装飾売上。
- **反対側の見張り（締めすぎ検知）**：D1/D7/D30継続率・**招待率・シェア率**。←落ちたら縛りすぎ。
- ルール：**寛大に出して計測で締める**。締める時も**新コホート/新機能のみ**（既存はグランドファーザリング＝奪わない）。
- 計測は安く：StoreKit2 ＋ 軽量アナリティクス（TelemetryDeck 等・プライバシー配慮）。

---

## 8. 段階（順序）

1. **PMF優先**：友達ループ＋デイリーカード拡散で継続/招待が回るか。最大リスクは「課金漏れ」でなく「人が居着かない」。
2. **ローンチ最小課金**：StoreKit2 で **サブ＋ライフタイム＋単品装飾**だけ。広告SDKは入れない。
3. **リワード広告は後から**（DAUが育ってから・統計じらし等の上乗せ）。
4. 価格・閾値・じらし頻度を指標で調整。

---

## 9. 決定済み（2026-06 確定）/ 残課題

### 確定
- **無料の記録ボード：2枚**（平日/休日の切替の便利さに気づかせる。3枚目からPro）。
- **カテゴリ総数：20上限**（実効ゲートはボード枚数）。
- **統計リワード頻度：24h解放×週1**（じらし。きつければ後で緩める）。
- **ライフタイムの装飾：完全分離（甘味なし）**。「装飾込みで長期は高くつくサブ」vs「安く機能だけの買い切り」の対比自体が分離の対価。現在の参照価格は¥6,800。
- **グループチャレンジ：当面見送り**（ロードマップに温存・マネタイズの当てにしない）。
- **獲得テーマ：極光（7日）のみ**（2026-06-12）。テーマは「観客不要で売れる最強の単品」なので課金カタログの主力に。無料は教材として入口の1つだけ残し、暁・茜・朧・残照・月白はカタログから除外して課金候補に温存（定義・パレットはコードに残置）。ローンチ前に整理したのは §7 グランドファーザリング原則（既存から奪わない）を発動させないため。

### 残課題（ローンチ前 TODO）
- **法務**：プライバシーポリシーURLは `https://liminalog-lp.vercel.app/privacy`。利用規約URLは `https://liminalog-lp.vercel.app/terms` をアプリ側に設定済み。課金導線は App Store Connect 商品確定、サブスクリプショングループ確定、QA、Go Live スイッチが揃うまで閉じたままにする。
- **サポート窓口**：`yuhlab.dev@gmail.com`（SettingsView `supportEmailAddress`・お問い合わせ＋プライバシーポリシー連絡先で共用）。
- **将来レバー**：ロイヤル層LTVを伸ばすなら新規のみライフタイム¥7,800等へ／ローンチ記念で期間限定¥4,800セール（恒常値下げでなく演出。年額を食う注意）。価格は高めスタート＋セールで下げる（緩めるのは楽・上げるのは新規のみ＝§1）。

---

## 10. 実装メモ（将来・Codex引き継ぎ用）

- **StoreKit2 商品**：
  - フルサブ（月/年）＝機能＋装飾使い放題。無料体験の有無・期間はApp Store Connect確定後に反映する。
  - **装飾サブ（買い切り所有者限定・月¥200/年¥1,500）**＝装飾レンタルのみ
  - Non-Consumable：ライフタイム・各プレミアム装飾（永久所有）
  - Consumable：支援チップ
- **仮商品ID（2026-06-27）**：
  - `liminalog.pro.monthly` / `liminalog.pro.yearly`
  - `liminalog.lifetime`
  - `liminalog.decorations.monthly` / `liminalog.decorations.yearly`
  - `liminalog.support.small` / `liminalog.support.medium` / `liminalog.support.large`
- **App Store Connect 商品作成メモ（未確定）**：
  - 転記用の独立メモは `AppStore/PurchaseProducts.md`。
  - サブスクリプショングループ案：`Liminalog Pro`
  - Auto-Renewable Subscription：`liminalog.pro.monthly`（Liminalog Pro 月額 / ¥400）、`liminalog.pro.yearly`（Liminalog Pro 年額 / ¥2,900）
  - Auto-Renewable Subscription：`liminalog.decorations.monthly`（装飾パス 月額 / ¥200）、`liminalog.decorations.yearly`（装飾パス 年額 / ¥1,500）
  - Non-Consumable：`liminalog.lifetime`（ライフタイム / ¥6,800）
  - Consumable：`liminalog.support.small`（小さく応援 / ¥250）、`liminalog.support.medium`（しっかり応援 / ¥600）、`liminalog.support.large`（大きく応援 / ¥1,200）
  - 転記元は `PurchaseProductID.appStoreConnectSpecifications`。商品ID、表示名、参照価格、StoreKit商品種別、サブスクリプショングループをコード側で固定し、ドキュメントだけが先に変わらないようにする。
  - 無料体験：年額Proに7日無料を付けるかは未確定。App Store Connectで確定後、アプリ内文言へ反映する。
  - 注意：装飾パスは「買い切り所有者向け」にアプリ側で表示制御する。App Store Connect上では商品として作り、表示対象は `PurchaseOfferingCatalog` で絞る。
- 単品プレミアム装飾は `liminalog.decoration.` prefix の権利モデルだけ実装済み。初期の商品取得リスト/購入UIにはまだ個別IDを列挙していないため、単品装飾を売る時は `PurchaseConfiguration.current.productIDs` と購入UI側の商品定義追加が必要。
- **本番課金設定の注入点**：`PurchaseConfiguration.current`。本番 Product ID 確認フラグ、サブスクリプショングループ名、利用規約URL、プライバシーポリシーURL、購入導線ON/OFF、機能制限ON/OFF、起動時StoreKit更新ON/OFFをここに集約し、未確定の間は有料リリース準備完了にならない。商品IDの空値/重複/未対応ID、法務URLの非HTTPSもRelease導線を開かない条件としてテストで固定済み。公開前の不足要件は `PurchasePaidReleaseRequirement` として型付きで保持し、DEBUG表示では `displayName` と `resolutionHint` を出す。StoreKitへ渡す商品IDは前後空白を除去してから使う。プライバシーポリシーURLは既存LPの `https://liminalog-lp.vercel.app/privacy` を設定済み。Product ID/法務URLが揃っても `purchaseEntryPointIsEnabled` を true にするまではReleaseの設定画面に購入導線を出さない。
- **リリース準備状態の確認**：`PurchaseConfiguration.releaseReadinessSnapshot` が `missingRequiredMetadata` / `metadataReadyWaitingForGoLive` / `purchaseEntryPointReady` / `featureRestrictionsReady` を返す。これにより、App Store Connect と法務URLの準備完了、購入導線の公開、既存機能へのPro制限適用を別チェックポイントとして扱える。`PurchaseActivationPolicy` はこの snapshot を通して Release の StoreKit 実行・機能制限・バックグラウンド権利更新を判定するため、メタデータだけ揃っても既存機能は自動で変わらない。
- **Release切り替え手順**：`AppStore/PurchaseReleaseChecklist.md`。メタデータ準備、購入導線公開、機能制限ONを3段階に分ける。
- **課金入口とStoreKitランタイムの露出**：`PurchaseActivationPolicy` で制御する。Releaseでは `PurchaseConfiguration.current.canExposePurchaseEntryPoint` が true になるまで設定内の「Proと応援」を出さず、`PurchaseStoreRuntimePolicy` 経由で起動時/復帰時のStoreKit権利確認も走らせない。購入画面でのStoreKit操作、既存機能のPro制限、起動時/復帰時のバックグラウンド権利確認は別スイッチに分ける。`PurchaseStore` 自体も同じランタイムポリシーを持ち、将来別の購入導線を追加しても未準備Releaseで商品取得・購入・復元・サブスク管理が直接走らないようにする。DEBUGでは未設定確認と表示検証のため購入画面のStoreKit操作だけ常に有効化する。
- **購入面のUI制御**：`SupportLiminalogView` は `PurchaseSupportSurfacePolicy` を通して商品、復元、サブスクリプション管理の表示/実行可否を判断する。未準備Releaseでは商品取得済みのように見える状態でも `.disabled` になり、StoreKit操作ボタンを出さないことをテストで固定済み。
- **機能制限の安全弁**：UIで実際に制限する時は `PurchaseFeatureGate` を通す。内部の生ポリシーは外から直接触れないようにし、課金未有効のRelease/DEBUGでは既存機能をロックしない。購入導線を開いた後も `PurchaseConfiguration.current.featureRestrictionsAreEnabled` を true にするまでは統計タブやカテゴリセット上限などのPro制限は適用しない。
- **統計タブPro化の実装方針（未適用）**：
  - 詳細設計は `19-statistics-pro-gate.md`。
  - タブ自体は消さない。無料ユーザーに「統計がある」ことは見せ、タブを開いた時にPro案内へ分岐する。
  - ただし無料ユーザーで制限が有効な時は `DashboardPeriodContent` を構築しない。統計の @Query / 集計を走らせず、データ漏れと重さを避ける。
  - 当日スコア、ストリーク、デイリーカード、カレンダー上の自分の過去データ閲覧は無料のまま。`statisticsTab` のゲートは「週/月/年の深い分析画面」だけにかける。
  - 実装時は `RootTabView` または `DashboardView` の入口で `PurchaseFeatureGate.decision(for: .statisticsTab, entitlements:)` を見て、未許可なら軽いPro案内ビューを表示する。購入導線は `SupportLiminalogView` に寄せ、別ペイウォール実装を増やさない。
  - `purchaseEntryPointIsEnabled == true` でも `featureRestrictionsAreEnabled == false` の間は既存の統計タブをそのまま表示する。制限ONは別リリースのチェックポイントにする。
- **StoreKit商品種別**：ローカルでは Pro/月額年額 と装飾パス/月額年額を自動更新サブスクリプション、ライフタイムと単品プレミアム装飾を非消耗型、支援を消耗型として扱う。StoreKitから返った商品IDまたは商品タイプが期待値と違う場合は購入候補・権利キャッシュの両方から外し、App Store Connect / StoreKit Configuration の設定ミスとしてログに出す。
- **ペイウォール出し分け**：**買い切り所有→装飾サブを表示／未所有→フルサブを表示**（買い切り勢にフルサブを見せない＝過払い防止）。
  - エッジケース：フルサブ中に買い切り購入→装飾サブへ乗換え提案（機能ぶんの払い続けを避ける）。
- **Small Business Program** 登録（手数料15%）。
- **レンタル判定**：サブ（フル/装飾どちらか）有効中のみプレミアム装飾を装着可能にするゲート。失効時の装着リセット＋単品所有の永続を両立。
- **プレミアム装飾のデータ設計（v0）**：
  - 詳細設計は `20-premium-decoration-data.md`。
  - `PremiumDecorationProduct` は StoreKit 商品ID、対象 `UnlockKind`、装着先 `targetID`、表示名を持つ。商品IDは `liminalog.decoration.` prefix の非消耗型だけをプレミアム単品として扱う。
  - `PremiumDecorationAccessPolicy` は `unavailable / rented / owned` の3状態を返す。単品所有がある場合は、同時にProサブや装飾サブが有効でも `owned` を優先する。
  - Proサブまたは装飾サブは `rented`。ライフタイム単体は機能の買い切りであり、装飾レンタル権は付けない。
  - 獲得装飾（継続・スコア・交換で解放）と課金装飾は別の軸にする。既存 `UnlockItem.unlockedAt` は獲得解放の事実として残し、課金所有/レンタルをそこへ混ぜない。
  - UI接続時は、課金装飾カタログを既存コレクションの表示モデルへ合流させるだけにし、既存の獲得済み装飾・装着済み装飾の保存形式は変更しない。失効時のリセットは後続タスクで別ポリシー化する。
- 既存の装飾解放機構（`UnlockRules`/`ProfileDecorationUnlocks`/`UnlockGalleryView`）に**課金所有/レンタルの軸を追加**（獲得とは別系統）。
- 計測：ペイウォール露出・転換・継続/招待を最小イベントで。
- **サーバー方針（初期）**：独自サーバーなし。StoreKit2 の `Transaction.currentEntitlements` と `Transaction.updates` を正とし、端末には表示高速化用キャッシュだけを持つ。App Store Server API / Server Notifications は、独自アカウント横断同期・返金/解約イベントのサーバー保管・詳細な課金分析が必要になってから検討。
- **購入状態更新**：起動時はキャッシュを即時表示する。StoreKit確認は購入画面表示時に行い、`backgroundEntitlementRefreshIsEnabled` または機能制限を明示的にONにした後だけ、起動時/復帰時のバックグラウンド確認を行う。復帰時は最終確認から6時間以上経っている場合だけ再確認し、既存画面の操作を待たせない。
- **サブスク管理**：アプリ内の「Proと応援」から StoreKit の管理画面を開く。解約・更新・プラン変更はApp Store側に寄せ、Liminalog側で独自サーバーや独自解約UIは持たない。
- **利用規約**：LP 側に `/terms` を追加済み。App Store Connect とアプリ内導線から参照するURLは `https://liminalog-lp.vercel.app/terms`。このURLだけを設定しても、App Store Connect 商品確定、サブスクリプショングループ、購入導線ONが揃うまではRelease導線を開かない。
- **ローカル課金テスト**：`liminalog.storekit` は repo 直下へ追加済みで、shared scheme の Run 設定も `liminalog.storekit` を参照している。`Scripts/validate-purchase-readiness.sh` は商品ID、サブスクリプショングループ、サブスク商品の `billingPlans`、scheme 参照を検査する。
  - 詳細手順と検査コマンドは `AppStore/StoreKitLocalTesting.md`。
  - 検証ケース：商品取得成功、Pro月額/年額購入、ライフタイム購入、装飾パス購入、支援チップ購入、復元なし、復元あり、サブスク期限切れ、非消耗型の永続保持、StoreKit商品種別不一致時に購入候補/権利キャッシュから外れること。
  - `xcodebuild test` + `SKTestSession(contentsOf:)` での自動購入テストは、2026-06-27 時点の Simulator が `app.YasudaRyuga.Liminalog is not installed for development` を返したため採用しない。失敗するテストを残さず、Xcode Run の StoreKit Configuration または App Store Connect Sandbox で手動QAする。
- **DEBUG表示検証**：設定 > デバッグ > 課金状態を試す、または `-LiminalogDebugPurchaseState` から無料/Pro/ライフタイム/装飾パスありの表示状態を一時確認できる。これは DEBUG ビルド限定・非永続・実購入の代替ではない。
- **未決確認**：本番 Product ID、サブスクリプショングループ名、App Store Connect の価格帯、年額Proの無料体験有無はユーザー確認後に確定する。LPは `/Users/ryu/Documents/X-code/LP/liminalog_lp` にあり、`/privacy`、`/support`、`/terms` は公開済み。
