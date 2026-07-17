# 21. 全体リファクタリング・最適化プレイブック

作成: Claude / 2026-07-06
目的: **このドキュメントだけを読めば、どのエージェント（Claude / Codex / 他）でも安全にリファクタリングへ着手できる**状態を作る。
性格: 意思決定文書 + 作業手順書。個々の作業は本書の「カタログ」から1件選び、AI_TASKS.md にタスク化してから着手する。

> 前提docs: [03-architecture.md](03-architecture.md)（方針・後戻りしない決断）は必読。対象領域に応じて 04/08/10/20 を参照。

---

## 0. ゴール / 非ゴール

### ゴール
1. **可読性**: 4,000行級のViewファイルを解体し、1ファイル≦800行目安に揃える
2. **テスト容易性**: View内に埋まったロジックを `Logic/` の純粋関数 or `Stores/` の Policy 型へ出し、ユニットテストで固定する
3. **実行効率**: 常駐する全件 `@Query` / fetch→メモリフィルタの監査と範囲クエリ化
4. **一貫性**: 日付境界・保存パイプライン・スキーマ規約など「既に決めた作法」への収束

### 非ゴール（やらないこと）
- 挙動変更・機能追加（気づいたバグは**直さず** AI_TASKS.md に別タスクとして起票する）
- TCA / RxSwift 等サードパーティFWの導入（docs/03 §11 で確定済み・不変）
- 友達共有（CloudKit輸送層）の挙動変更 — §2 の不変条件参照
- UIデザインの変更（ピクセル単位で不変。分割前後でスクリーンショット比較できること）

---

## 1. 現状スナップショット（2026-07-06 時点）

App + Widget 合計 **57,374行**。行数上位（`find Liminalog LiminalogWidget -name "*.swift" -exec wc -l {} + | sort -rn` で再計測すること）:

| 行数 | ファイル | 分類 |
|---|---|---|
| 4,167 | Views/Friends/FriendsView.swift | View巨大 |
| 4,018 | Views/Calendar/CalendarView.swift | View巨大 |
| 3,171 | Views/Profile/ProfileComponents.swift | View巨大 |
| 2,235 | Views/Calendar/CalendarWeekTimelineView.swift | View巨大 |
| 2,087 | Views/Calendar/EditablePlanTimelineView.swift | View巨大 |
| 1,625 | Views/Home/TimelineView.swift | View巨大 |
| 1,598 | Views/Profile/UnlockGalleryView.swift | View巨大 |
| 1,578 | Stores/CloudFriendShareRefreshCoordinator.swift | Store巨大・高リスク |
| 1,192 | Views/Profile/ProfileEditSheet.swift | View巨大 |
| 1,014 | Views/Home/HomeView.swift | View巨大 |

健全な既存パターン（＝リファクタリングの**お手本**であり、到達点）:
- `Stores/CloudFriend*Policy.swift` 群: 判断ロジックを小さな Policy 型に切り出し、1型=1ファイル=専用テスト
- `Logic/` の enum static 純粋関数群（`TimelineBarLayout`, `DayBoundary`, `UnlockRules`, `AudienceResolver` など）
- `PlanStore.saveChanges(...)`: save → `CloudFriendShareRefreshCoordinator.requestRefresh` → 失敗時 rollback の保存パイプライン

---

## 2. 不変条件（違反したらリファクタリング失敗。レビューで最初に見る）

過去の実障害（AI_TASKS.md §10 完了ログ 2026-06-11 前後）から抽出した規約。**理由ごと覚えること。**

### 2.1 SwiftData / CloudKit スキーマ規約
- `@Model` の全プロパティは**デフォルト値を持つか Optional**（CloudKit 互換の必須条件）
- enum は直接保存せず **`xxxRawValue: String` + computed accessor**（`Chapter.audienceSource` の形）
- **to-many のモデル関係は作らない**。既存精神は「UUID配列で参照」（`CategorySet.slots: [UUID?]`、`audienceFriendIDs: [UUID]`）。to-one 関係（`PlanBlock.category`）は可
- スキーマ変更は**追加のみ**。保存済みプロパティのリネーム・削除・型変更は禁止
- 新モデル追加時は3箇所同時に登録: `LiminalogSchemaV1.models` / `SharedModelContainer.cloudSchema`（同期対象）or `localCacheSchema`（ローカル限定）/ `SharedModelContainer.schema`
- `#Predicate` で **UUID配列への `contains` は使えない**（実機クラッシュ実績あり）。メモリ内フィルタで代替

### 2.2 並行性
- **`await` を跨いで SwiftData モデル（`@Model` インスタンス）を保持しない**。Task境界はプレーン値スナップショットに変換して渡す（`LiveActivityChapterSnapshot` が前例）。CloudKitインポート/重複統合が await 中にモデルを無効化しクラッシュした実績あり
- ストアの寿命管理（リセット・削除）は**本体プロセスのみ**。Widget拡張は読み取り専用の消費者

### 2.3 データ書き込み
- PlanBlock / Chapter への書き込みは必ず Store 経由。save 成功後に `CloudFriendShareRefreshCoordinator.requestRefresh(...)` へ変更IDと影響日を通知、失敗時 `modelContext.rollback()`。この経路を迂回する書き込みを作らない
- 複数件の書き込みは**1回の save + 1回の requestRefresh** にまとめる（`savePlanScheduleChanges` が前例）

### 2.4 ドメイン規約
- 1日の境界は **0:00–24:00 固定**（`DayBoundary`）。ユーザー可変にする改修は禁止（docs/03 §7.2）
- 時間指定の予定は「明日以降の日」のみ作成・変更可（`PlanStore.canCreate` / `isScheduleLocked`）。この規則を緩める変更はリファクタリングでは行わない

### 2.5 触ってはいけない領域
- **友達共有の輸送層**（`CloudFriendShare*` / `FriendShare*` / `CloudKit*` 群）は、2台実機E2E（AI_TASKS §7.0 の検証run参照）を伴わない限り**挙動を変えない**。内部のファイル分割すら §5 R5 の条件下でのみ許可

---

## 3. 検証プロトコル（全リファクタリング共通・省略不可）

作業完了ごとに以下を**この順で**実行し、結果を AI_TASKS.md §10 完了ログに記録する:

```bash
# 1. 空白・コンフリクトマーカー検査
git diff --check

# 2. ユニットテスト（シミュレータ）
xcodebuild test -scheme Liminalog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /private/tmp/LiminalogDerivedData

# 3. フルビルド（実機向け・署名なし）
xcodebuild -scheme Liminalog -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/LiminalogDerivedData \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

追加ルール:
- **View分割**は上記に加え、対象画面をシミュレータで開き分割前後のスクリーンショット比較（ライト/ダーク両方）
- **パフォーマンス判断は必ず Release ビルド**で行う。Debug の SwiftUI は5〜10倍遅く、Debugで感じたジャンクを根拠に最適化しない
- 完了ログ書式: `| 日付 | 担当 | 何をしたか + 検証コマンドとその結果 |`

---

## 4. 作業ルール

1. **1テーマ = 1タスク = 1ブランチ**。ブランチ名は `codex/*`（ロジック・大規模再構成）/ `claude/*`（UI・分割）。`main` は復元ポイント専用
2. **リファクタリングと挙動変更を同一ブランチに混ぜない**。機械的な移動（ファイル分割）と編集を伴う変更はコミットも分ける
3. 着手前に AI_TASKS.md へタスク追記: `- [ ] タイトル <!-- 担当: X, 理由: ..., 依存: docs/21 Rn -->`、着手時 `[~]` + 担当名、完了時 `[x]` + 完了ログ
4. リファクタリング中に発見したバグ・怪しい挙動は**その場で直さず**、AI_TASKS.md に別タスクとして起票（挙動不変の原則を守るため）
5. 大きい分割は**1ファイルずつ**進め、各ステップでビルドが通る状態を保つ

---

## 5. リファクタリングカタログ

各項目は独立に着手可能。**推奨順: R1 → R2 → R4 → R3 → R8**。R5/R6 は個別判断（着手前にユーザー確認）。

---

### R1. 巨大Viewファイルの分割 【優先度: 高 / リスク: 低 / 担当推奨: Claude】

**目的**: 1ファイル≦800行目安。§1 の View巨大ファイル9本が対象。

**手順（1ファイルずつ）**:
1. 対象ファイル内の `private struct`（サブビュー）と、親Viewの `private var xxxCard/Section: some View` を列挙する
2. 意味のまとまり（画面上のセクション）単位で、**同じフォルダ**に新ファイルを切る。命名は `<親画面名><セクション名>.swift`（例: `FriendsRankingSection.swift`, `CalendarMonthGrid.swift`）。既存の `DashboardCards.swift` / `TimelineChapterCard.swift` のような分割粒度に合わせる
3. 抽出したサブビューへは **値 + `@Binding` + クロージャで渡す**。`@Environment` の参照は必要な子にだけ移す。親の `@State` を丸ごと渡すために ObservableObject 化するような**構造変更はしない**
4. computed property の抽出で済む場合は、まず同ファイル内 `extension` へ整理 → それでも800行を超えるならファイル分割
5. 各ファイル分割ごとにビルド確認。全体完了後に §3 のフルプロトコル + スクショ比較

**着手順**（依存が薄い順）: `UnlockGalleryView` → `ProfileEditSheet` → `ProfileComponents` → `TimelineView` → `HomeView` → `CalendarWeekTimelineView` → `EditablePlanTimelineView` → `CalendarView` → `FriendsView`
（Calendar/Friends は行数最大だが状態が複雑なので、パターンを他で確立してから）

**完了条件**: 対象ファイルが800行以下 / 挙動・見た目不変 / 新ファイルの各Viewが private でなく同モジュール内アクセスの場合、名前衝突がない

**注意**: SwiftUIの型チェック時間対策にもなる（長大な `body` は分割で改善）。ただし分割自体はメモ化ではないので、パフォーマンス目的の `EquatableView` 化などはここではやらない

---

### R2. View内ロジックの純粋関数化 【優先度: 高 / リスク: 低 / 担当推奨: Codex（テスト付きロジック抽出）】

**目的**: View の `private func` に埋まった計算（日付演算・集計・整形・判定）を `Logic/` の enum static 関数へ移し、テストで固定する。

**対象の見つけ方**:
```bash
# Viewファイル内で Date/集計計算をしている private func を洗う
grep -rn "private func" Liminalog/Views --include="*.swift" | grep -iv "body\|sheet\|button\|tap\|dismiss\|haptic"
```

**作法**（既存の模範: `TimelineBarLayout`, `AudienceResolver`, `DayBoundary`, `PlanCoverageSummary`）:
- `Logic/<責務名>.swift` に `enum <責務名> { static func ... }`。インスタンス不要・入出力はプレーン値
- `@Model` を引数に取らず、必要フィールドだけ受ける（§2.2 の await 跨ぎ問題の予防にもなる）
- 移した関数には必ず `LiminalogTests/<責務名>Tests.swift` を追加

**完了条件**: 移設した関数がテストで覆われ、元Viewは呼び出しだけになっている

---

### R3. 日付境界の統一 【優先度: 中 / リスク: 中 / 担当推奨: Codex（境界条件の判断）】

**目的**: `Calendar.current.startOfDay` / `Calendar.japanese` 直呼び（約20ファイル）を `DayBoundary` に集約する（docs/03 §7.2 の未了タスク）。

**手順**:
1. `grep -rn "startOfDay\|Calendar.japanese" Liminalog --include="*.swift"` で全箇所を列挙
2. **分類する**: (a) 日境界計算（dayStart/dayEnd）→ `DayBoundary` へ置換対象 / (b) 週・月・曜日・表示フォーマット用途 → **対象外**（`Calendar.japanese` は firstWeekday / locale のためにあり、これは残す）
3. (a) を1ファイルずつ置換。`PlanStore.affectedScoreDayStarts` のように `Calendar.japanese.startOfDay` と `DayBoundary.dayStart` が混在している箇所は挙動同値を確認してから揃える
4. 置換前に該当ロジックのテストが無ければ**先にテストを書いて現挙動を固定**してから置換する

**リスク**: タイムゾーン・DST 跨ぎの微妙な差。テスト先行を必須とする

---

### R4. フェッチ効率の監査 【優先度: 高 / リスク: 中 / 担当推奨: Codex】

**目的**: 「友達タブを開くとアプリ全体が重くなる」事件（完了ログ 2026-06-11: 全期間 Chapter/PlanBlock の常駐 `@Query` が全保存で再評価）の再発防止と横展開。

**手順**:
1. 監査①: 全 `@Query` を列挙し、**filterなし・全期間**のものを洗う。TabView はタブのビューを生かし続けるため、常駐画面の全件 `@Query` は禁止。範囲付き `#Predicate` か、表示時のみのオンデマンド fetch に置換
2. 監査②: `fetch → メモリ内 filter` のパターンを洗い、`#Predicate` の範囲条件に押し込めるものを移す（ただし §2.1 の `#Predicate` 制約に注意）
3. 監査③: `PlanStore.allPlannedBlocks()` / `allPlannedBlocksIfAvailable()` の呼び出し元を確認し、日付範囲版で置換できるものを置換
4. 効果測定は **Release ビルド + Instruments (Time Profiler / SwiftData)**。体感報告だけで完了にしない

**完了条件**: 常駐画面の全期間 `@Query` ゼロ / 置換箇所ごとに計測値（before/after）を完了ログに記録

---

### R5. CloudFriendShareRefreshCoordinator の内部整理 【優先度: 低 / リスク: **高** / 担当推奨: Codex + ユーザー承認必須】

**目的**: 1,578行の Coordinator を既存の Policy 切り出しパターンで整理する。

**条件（全部満たさない限り着手禁止）**:
- 挙動・公開API完全不変（内部分割のみ）
- 単独ブランチ・単独PR
- §3 プロトコルに加え、実CloudKit smoke テスト（`CloudKitLiveDeviceSmokeTests`）を実機で実行
- 着手前にユーザーへ着手可否を確認（輸送層は §2.5 の保護領域のため）

**判断**: 急がない。Phase 3 の友達機能が安定稼働している間は現状維持が最も安全。「次に輸送層へ機能追加が必要になったとき」に併せて実施するのが費用対効果最良

---

### R6. Swift Package 化（LiminalogCore / LiminalogUI） 【優先度: 保留 / 担当: ユーザー判断】

docs/03 §1 / §10 Step2・Step5 の未了項目。ただし**当初の主目的（Widget とのコード共有）は App Groups + 共有ターゲットメンバーシップで既に達成済み**。

- 今やる利点: ビルド時間の分離・依存の明示化・`LiminalogCore` の純粋テスト
- 今やる欠点: xcodeproj 大手術・全 import 書き換え・進行中の機能開発（マネタイズ/プリセット）と衝突
- **推奨: 保留**。機能開発が一段落したリリース後の閑期に、`LiminalogCore`（Models/Logic のみ）の最小構成から。着手判断はユーザーに委ねる

---

### R7. ビルド時間・型チェック対策 【優先度: 低 / R1 に実質包含】

- 長大な `body` / ViewBuilder は R1 の分割で解消される
- 計測したい場合: Build Settings に `OTHER_SWIFT_FLAGS = -Xfrontend -warn-long-function-bodies=500` を一時追加し、500ms超の関数を特定 → R1/R2 の対象に足す（フラグはコミットしない）

---

### R8. 死蔵物の整理 【優先度: 低 / リスク: 低 / 担当: どちらでも】

1. リポジトリ直下の `名称未設定フォルダ/`（アプリアイコンPNG 8枚）: `icon-mockups/` へ移動 or 削除。**削除はユーザー確認必須**
2. `build/` ディレクトリが git 管理下にないか確認、`.gitignore` 整備
3. docs/README.md のステータス表を最新化（本書・docs/22 追加時に更新済みか確認）
4. `PreviewSupport` / `PreviewRuntimeSeedSupport`（664行）内の未使用シードを棚卸し（削除ではなくコメントで由来を残す判断も可）

---

## 6. 完了の定義（このプレイブック全体）

- View ファイル最大行数 ≦ 800（R1）
- `Logic/` 移設関数のテストカバー（R2）
- 常駐全件 `@Query` ゼロ + 計測記録（R4）
- 日境界の `DayBoundary` 集約（R3）
- 各作業が AI_TASKS.md §10 完了ログに検証結果付きで記録されている

## 7. 未確定の論点（ユーザー判断待ち）

| 論点 | 選択肢 | 推奨 |
|---|---|---|
| R5 輸送層整理の着手時期 | 今 / 次の輸送層改修と同時 / やらない | 次の改修と同時 |
| R6 Swift Package 化 | 今 / リリース後 / 取りやめ | リリース後に最小構成 |
| R8-1 `名称未設定フォルダ` の処分 | icon-mockups へ移動 / 削除 | 移動 |
