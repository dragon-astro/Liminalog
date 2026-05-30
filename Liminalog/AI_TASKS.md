# Liminalog — AI タスクボード

ClaudeとCodexが連携してLiminalogを開発するための共有タスク管理ファイル。
**両AIが作業の前後に必ずこのファイルを読み、担当決定・進捗・追記を行う前提で運用する。**

---

## 0. 関連ドキュメント（着手前に必ず確認）

| ファイル | 役割 |
|---------|------|
| [../Liminalog/Views/Profile/docs/README.md](../Liminalog/Views/Profile/docs/README.md) | 設計ドキュメント目次 |
| [../Liminalog/Views/Profile/docs/01-current-architecture.md](../Liminalog/Views/Profile/docs/01-current-architecture.md) | 現状アーキテクチャの棚卸し |
| [../Liminalog/Views/Profile/docs/02-gap-analysis.md](../Liminalog/Views/Profile/docs/02-gap-analysis.md) | 仕様と実装のギャップ |
| [../Liminalog/Views/Profile/docs/03-architecture.md](../Liminalog/Views/Profile/docs/03-architecture.md) | アーキテクチャ方針（後戻りしない決断） |
| [../Liminalog/Views/Profile/docs/04-data-model.md](../Liminalog/Views/Profile/docs/04-data-model.md) | データモデル詳細 |
| [../Liminalog/Views/Profile/docs/05-screen-flow.md](../Liminalog/Views/Profile/docs/05-screen-flow.md) | 画面遷移・シート階層 |
| [../Liminalog/Views/Profile/docs/06-testing.md](../Liminalog/Views/Profile/docs/06-testing.md) | テスト方針 |
| [../Liminalog/Views/Profile/docs/07-codex-plan-review.md](../Liminalog/Views/Profile/docs/07-codex-plan-review.md) | Codex 計画レビュー（修正指示） |
| [../Liminalog/Views/Profile/docs/08-timeline-redesign.md](../Liminalog/Views/Profile/docs/08-timeline-redesign.md) | タイムライン UX 再設計（05 上書き） |
| [../Liminalog/Views/Profile/docs/09-profile-design.md](../Liminalog/Views/Profile/docs/09-profile-design.md) | プロフィール画面 情報設計 v2（二面性・装飾アイテム経済・05 上書き） |
| [../Liminalog/liminalog_spec_v04.md](../Liminalog/liminalog_spec_v04.md) | プロダクト仕様書 |
| [../Liminalog/CLAUDE_v04.md](../Liminalog/CLAUDE_v04.md) | Claude向けプロジェクト概要 |

実装着手前に **最低限 `Liminalog/Views/Profile/docs/03-architecture.md` と該当機能の `04-` `05-`** を読むこと。

---

## 1. AIの特性まとめ（出典: 連携記事）

両AIの強み・弱みを共通認識として持つ。**自分の弱みを認識したうえで作業すること。**

### Claude Code
| 観点 | 内容 |
|------|------|
| 強み (What) | プランモードで「何を作るか」を引き出すのが上手い。AskUserQuestion で要件・スコープの共通認識を作る。ユーザーが気づいていない要件を引き出す |
| 強み (実装) | 既存コードベースの**スタイル・命名規則・ディレクトリ構成を読み取り、馴染むコード**を書く |
| 弱み (プラン) | 実装の詳細（エラー時挙動・条件分岐・セキュリティ）が**ふんわり**になりがち |
| 弱み (実装) | 既存実装に**引っ張られすぎ**、大幅な方向転換が必要なときに中途半端な修正になる。複雑な条件分岐ではスパゲッティ化しやすい |

### Codex
| 観点 | 内容 |
|------|------|
| 強み (レビュー) | プランの曖昧さを見逃さない。「条件分岐」「エラーハンドリング」「セキュリティ・エッジケース」「APIの曖昧さ」を**実装者視点で鋭く指摘** |
| 強み (実装) | 既存コードに引きずられず、**プランに従ってゼロベース**で考え直せる。複雑なアルゴリズム・ロジックでスマートな実装 |
| 弱み (プラン) | 最初から実装詳細（bcryptラウンド数、JWT有効期限）を聞きがちで、Vibe段階の依頼には噛み合わない |
| 弱み (実装) | コードベース全体から見ると**浮いた実装**になることがある（可読性面） |

---

## 2. 分担の原則

### 2.1 プランニングフェーズ — 常にClaude

新規・大きな実装タスクは **Claudeのプランモードで開始** する。

理由: AskUserQuestionとWhat引き出しは Claude が圧倒的に上手い。

- ユーザーから「Vibeで」「ふんわり」な依頼を受けた場合 → Claudeで開く
- 要件があらかじめ明確で実装詳細まで決まっている場合 → Codexで開いてもよい

### 2.2 プランレビューフェーズ — 常にCodex

Claudeがプランをまとめたら、**Codexでレビュー** する。

レビューでCodexに見てもらう観点:
- 条件分岐の網羅性
- エラーハンドリング・エッジケース
- セキュリティ上の懸念
- APIの仕様・URL形式の曖昧さ
- 並行性・同期問題
- データ整合性・トランザクション境界
- パフォーマンス上の落とし穴

Codexの指摘に基づき、プランに加筆修正する。

### 2.3 実装フェーズ — 決定木に従う

```
プランレビューでロジックレベルの誤りが見つかった？
├── YES → Codex で実装
│         (見つけた本人が直すのが筋。+期待値も高い)
│
└── NO → 次の質問へ ↓

既存コードベースに大きな影響を与える変更？
(ファイル数多数 / アーキテクチャ転換 / 既存パターンを置き換える)
├── YES → Codex で実装
│         (Claudeは既存に引きずられて中途半端になる)
│
└── NO → 次の質問へ ↓

複雑なアルゴリズム・条件分岐ロジックが主体？
(スコア計算 / 重なり判定 / 並び替えロジック / マージ処理)
├── YES → Codex で実装
│         (Opusはスパゲッティ化しやすい)
│
└── NO → Claude で実装
          (コードベース整合性が活きる)
```

### 2.4 担当表記の凡例（タスクリスト中）

| 表記 | 意味 |
|------|------|
| `[Claude]` | Claudeが実装することが望ましい（理由を併記） |
| `[Codex]` | Codexが実装することが望ましい（理由を併記） |
| `[未定]` | プラン段階。プラン後に決定木で判断する |
| 空欄 | どちらでも可（軽微な改善・ドキュメントなど） |

---

## 3. ワークフロー

### 3.1 新規実装タスクが発生したとき

```
1. Claude プランモード起動
     AskUserQuestion で What を確定 → 仕様確認
     ↓
2. Claude が `docs/` に設計を書く（または更新）
     ↓
3. Claude が AI_TASKS.md にタスクを追記
     担当は [未定] でOK。プラン本体は docs/ 側に置く
     ↓
4. Codex がプランをレビュー
     エッジケース・エラーハンドリング・セキュリティを指摘
     → docs/ を加筆修正
     ↓
5. レビュー結果に基づき決定木で担当を確定
     AI_TASKS.md の [未定] を [Claude] or [Codex] に更新
     ↓
6. 担当AIが実装
     ↓
7. 実装完了 → AI_TASKS.md のチェックを入れる + 完了ログに記録
```

### 3.2 既存タスクに着手するとき

```
1. AI_TASKS.md を読む
     ↓
2. 担当が自分なら → 着手前に「進行中」と書いて作業開始
   担当が相手なら → 別タスクへ
   担当が空欄/未定なら → 決定木で判定し、自分が適切なら担当を書いて着手
     ↓
3. 関連 docs/ を確認
     ↓
4. 実装 → チェック付け + 完了ログ
```

### 3.3 新規タスクの追記ルール

実装中に追加タスクが発生したら、該当 Phase セクションに追記する。

**フォーマット:**
```markdown
- [ ] タスクタイトル <!-- 担当: [Claude/Codex/未定/空欄], 理由: ..., 依存: #N -->
```

**例:**
```markdown
- [ ] ChapterStore を CategoryStore / PlanStore / ScoreStore に分割 <!-- 担当: Codex, 理由: 既存コードベースの大規模再構成・ゼロベース思考が必要 -->
- [ ] HomeView を新Store構成へ移行 <!-- 担当: Claude, 理由: 既存SwiftUIの整合性維持 -->
- [ ] カラーパレットの調整 <!-- 担当: 空欄 -->
```

**追記後の手順:**
1. 完了ログに「新規タスク追加」として日付・追記者・内容を記録
2. 仕様変更や設計変更を伴う場合は `docs/` 側も更新
3. 削除・統合する場合も完了ログに理由を残す

### 3.4 「フェーズ間越境」の扱い

例: Phase 1 実装中に Phase 2 のタスクが先に必要になった場合。

- そのまま先に実装してOK（過剰実装でないなら）
- AI_TASKS.md の該当 Phase 2 タスクを [x] にする
- 完了ログに「Phase 2 先行実装」と明記

### 3.5 タスクの不確実性が高い場合

- 仕様書だけで判断できない → §9 オープン論点 セクションに追加してユーザーに確認
- 設計方針が docs/ にない → 先に docs/ を更新してからタスク追記

### 3.6 Git 安全運用ルール

このプロジェクトでは、Gitを「後から戻れる復元ポイント」として扱う。Claude / Codex ともに、実装前後で以下を守る。

#### 基本方針

- `main` は安定版・復元ポイント用。直接作業しない
- 普段の作業はブランチ上で行う
- 大きな変更前には必ずコミットして、戻れる地点を作る
- 作業後は **ビルド確認 → AI_TASKS.md 記録 → コミット → push** を基本セットにする
- ビルドが通らない、UIが大きく壊れている、仕様が仮の状態は `main` に入れない

#### ブランチ運用

| ブランチ | 役割 |
|---|---|
| `main` | 発表・復元用の安定版。壊れていない確認済み状態だけを置く |
| `codex/*` | Codexの基盤改修・ロジック改修用 |
| `claude/*` | ClaudeのUI調整・画面実装用 |
| `release/demo-YYYYMMDD` | 発表前に固定するデモ版 |

現在の復元ポイント:
- commit: `4b2c838 chore: save phase0 baseline`
- remote: `origin https://github.com/dragon-astro/Liminalog.git`
- pushed branches: `main`, `codex/phase0-next`

#### コミットのタイミング

- Phase開始前 / Phase完了後
- Store分割、CloudKit切替、Package化など大きな構造変更の前
- UI大改修の前後
- バグ修正が一区切りついた時
- Claude / Codex の担当を切り替える前

#### コミットメッセージ例

```text
chore: save phase0 baseline
feat: add calendar search
fix: prevent chapter loss on category switch
docs: record phase0 progress
refactor: split plan store
```

#### Claude / Codex 並行作業時の注意

- 同じファイルを同時に大きく触らない
- 着手前に AI_TASKS.md で担当・進行中を明記する
- ClaudeがUIを触っている間、CodexはStore/Logic/Docs中心にする
- CodexがStore分割中は、Claudeは同じStoreに依存するUIの大改修を避ける
- 競合しそうな場合は、先にコミット・pushしてから相手に渡す

#### 禁止・確認必須の操作

以下はデータを失う可能性があるため、ユーザー確認なしに実行しない。

- `git reset --hard`
- `git clean`
- ブランチ削除
- コミット履歴を書き換える操作
- ファイル削除を伴う大きな整理

戻したい場合は、まず現在の状態・戻したい地点・影響範囲を確認してから実行する。

---

## 4. タスクのステータス凡例

| マーク | 意味 |
|------|------|
| `[ ]` | 未着手 |
| `[~]` | 進行中（担当AI名を必ず併記） |
| `[x]` | 完了 |
| `[!]` | ブロック中（理由をコメント） |
| `[-]` | 廃止（理由をコメント） |

---

## 5. Phase 0 — アーキテクチャ移行（最優先）

> 既存のPhase 1〜2 実装は「動くMVP」として価値があるが、`docs/03-architecture.md` の決断を反映するために**移行作業が必要**。
> Phase 1 残タスクと Phase 2 本格実装の前に、ここを通すことで後戻り工数を抑える。

### 5.1 基盤準備

- [x] App Group ID を確定（候補: `group.app.YasudaRyuga.Liminalog`）<!-- 担当: Codex, 完了: 2026-05-28 ユーザーの「さっきの方針で進めて」を受け候補IDで確定 -->
- [~] CloudKit Container 作成（候補: `iCloud.app.YasudaRyuga.Liminalog`）<!-- 担当: Codex, 進捗: 2026-05-28 entitlements / ModelConfiguration は設定済。Apple Developer 側の実体確認は実機署名時に必要 -->
- [x] Xcode Capability: App Groups を App / Widget 両方に追加 <!-- 担当: Codex, 理由: Xcode 設定の機械作業, 完了: 2026-05-28 -->
- [x] Xcode Capability: iCloud (CloudKit) を App に追加 <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `SharedModelContainer` を実装（App Group URL + CloudKit Private DB）<!-- 担当: Codex, 理由: 既存 ModelContainer の置換・ボイラープレート, 完了: 2026-05-28 -->
- [x] `LiminalogApp.modelContainer` を `SharedModelContainer.shared` に差し替え <!-- 担当: Codex, 理由: 既存実装の機械置換, 完了: 2026-05-28 -->
- [x] `CalendarEventCache` 用に第2の `ModelConfiguration`（ローカル限定）を追加 <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] DEBUGビルド用の開発ストア世代管理を追加（モデル変更時の古いApp Group SwiftData storeを自動リセット）<!-- 担当: Codex, 完了: 2026-05-29。本番移行はVersionedSchemaで別途対応。世代を上げる時は `currentDevelopmentStoreVersion` を更新。CloudKit補助ディレクトリ `.Cloud_SUPPORT` も一緒に削除する。2026-05-29追記: 世代キーが一致していても実体DBが古いケースを検出するため、DEBUGでは必須カラムマーカー（例: `ZPROFILEACCENTCOLORHEX`）が `Cloud.store` にない場合もリセットする -->

### 5.2 0:00固定 DayBoundary 導入

- [x] `DayBoundary` struct を `LiminalogCore/Logic` 相当に追加（0:00-24:00 固定）<!-- 担当: Codex, 理由: 純粋ロジック・カレンダー計算, 完了: 2026-05-28 -->
- [-] `@AppStorage("dayStartHour")` / `UserSettings.dayStartHour` 基盤 <!-- 撤回: 現行仕様では1日を0:00-24:00固定にする。可変境界は数年単位の大型アップデートで再検討 -->
- [x] `Calendar.current.startOfDay(for:)` 直接呼び出しを必要箇所から固定 `DayBoundary.dayStart(for:)` に集約 <!-- 担当: Codex, 完了: 2026-05-29。スコア/タイムライン/編集制約/期間集計など日付境界の意味を持つ箇所は `DayBoundary` 経由へ移行。カレンダー月表示・終日予定ラベルなど純UI/日付表示の `Calendar.startOfDay` は用途が別なので維持 -->
- [x] `ScoreCalculator` の `dayStart`/`dayEnd` を固定 `DayBoundary` 経由に変更 <!-- 担当: Codex, 理由: ロジック改修, 完了: 2026-05-28 -->

### 5.3 ChapterStore 分割

> 既存 `ChapterStore` (378行・8ドメイン混在) を `docs/03 §3` の方針で分割する。
> **典型的な「Codex で実装」のタスク**: 大規模再構成・ゼロベース思考が要。

- [x] `CategoryStore` 切り出し（CRUD + Query + seedDefaultCategories）<!-- 担当: Codex, 理由: 既存God Storeの責務分離・大規模リファクタ, 完了: 2026-05-28 -->
- [x] `CategorySetStore` 切り出し <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `PlanStore` 切り出し <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `ScoreStore` 切り出し（scoreSummary / streakCount / totalScore）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `LiveActivityCoordinator` 切り出し（既存 LiveActivityManager と統合）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `ChapterStore` は Chapter 専用に縮小（CRUD・activeChapter・カテゴリ切替時は削除しない）<!-- 担当: Codex, 完了: 2026-05-29。カテゴリ/予定/スコア読み取り façade を撤去し、ビューは `@Query`、テストは `CategorySetStore` / `ScoreStore` を直接使う形へ移行。Category/Plan mutation の互換入口はリリース前の画面導線維持のため残す -->
- [x] `AppStores` 集約ハブを実装 <!-- 担当: Codex, 理由: 新規ボイラープレート, 完了: 2026-05-28 -->
- [x] `RootTabView` で `AppStores.bootstrap()` に切り替え <!-- 担当: Codex, 理由: Store基盤移行と一体で実施, 完了: 2026-05-28 -->

### 5.4 @Query 主軸への移行

> `store.revision` 手動カウンタを廃止し、SwiftData `@Query` に統一する。
> **典型的な「Claude で実装」のタスク**: 既存ビューを丁寧に書き換える整合性勝負。

- [x] `HomeView` を `@Query` ベースに書き換え + revision 依存を除去 <!-- 担当: Codex, 完了: 2026-05-29。Home本体は mutation導線のみ `ChapterStore` を持ち、子Viewの読み取りは `@Query` 側へ移行 -->
- [x] `TimelineView` を `@Query` ベースに書き換え（TickClock分離も）<!-- 担当: Codex, 完了: 2026-05-29。Chapter/Plan は `@Query`、現在時刻更新は `TickClock` -->
- [x] `CategoryGrid` を `@Query` ベースに書き換え <!-- 担当: Codex, 完了: 2026-05-29。カテゴリ/セット読み取りは `@Query`、選択保存・記録開始だけ `ChapterStore` -->
- [x] `CurrentChapterCard` を `@Query` ベースに書き換え <!-- 担当: Codex, 完了: 2026-05-29。active Chapter を `@Query` で検出し、経過時間は `TickClock` -->
- [x] `CalendarView` / `CalendarDayView` を `@Query` ベースに書き換え <!-- 担当: Codex, 完了: 2026-05-29。Plan/Chapter を `@Query` で読み、重要予定・スコアをView側で算出 -->
- [x] `DashboardView` を `@Query` ベースに書き換え + 期間 filter 動的化 <!-- 担当: Codex, 完了: 2026-05-29。期間切替は `@Query` 配列をView内でフィルタし、今日スコアは `ScoreCalculator` で算出 -->
- [x] `ProfileView` を `@Query` + `ScoreStore` 直接呼び出しに整理 <!-- 担当: Codex, 完了: 2026-05-29。プロフィール統計/バッジ/連続記録は `@Query` 配列 + `ScoreCalculator` で算出し、`ChapterStore` 読み取り依存を撤去 -->
- [x] `TickClock` を `@Observable` で実装 <!-- 担当: Codex, 完了: 2026-05-29。Timeline / CurrentChapterCard / Calendar / Dashboard / Profile の現在時刻更新を集約 -->
- [x] `ChapterStore.revision` を削除 <!-- 担当: Codex, 完了: 2026-05-29。手動カウンタを完全撤去し、SwiftData `@Query` と `TickClock` に再描画責務を移譲 -->

### 5.5 モデル更新（CloudKit互換化）

> **注:** §8.5 Codexレビュー対応 で方針上書き済の項目あり。下記は最新方針に従うこと。

- [x] 全 `@Model` プロパティにデフォルト値を付与（CloudKit要件）<!-- 担当: Codex, 理由: モデル一括変更・機械作業, 完了: 2026-05-28 -->
- [-] 全 `@Model` の `id` を `@Attribute(.unique)` 化 <!-- 撤回 (2026-05-24, Codex §8.5): CloudKit managed sync では unique 制約は使わない。一意性は Store/seed 層で守る -->
- [-] `Chapter.photoData: Data?` を追加 <!-- 撤回 (2026-05-24, Codex §8.5): バイナリ直積みは同期コスト高。代わりに `photoLocalIdentifier` / `thumbnailData` を検討 -->
- [x] `Chapter.updatedAt`, `Chapter.visibilityScope` 追加 <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `PlanBlock.sourceEventID`, `PlanBlock.updatedAt`, `PlanBlock.visibilityScope` 追加 <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `UserSettings` モデル新規作成 + シード（`settingsKey` 重複統合ロジック必須）<!-- 担当: Codex, 理由: §8.5 BootstrapStore/SeedCoordinator と一体, 完了: 2026-05-28 -->
- [~] 既存 `VisibilityPreset` を `docs/04 §4.5` の新設計で置換（`builtInKey` 重複統合ロジック必須）<!-- 担当: Codex, 進捗: 2026-05-28 builtInKey/updatedAt/default init/重複統合のみ実装。publishMode 等の本格プリセット設計は未実装 -->
- [x] `LiminalogActivityAttributes.ContentState.categories` を削除（App Groups経由で読むため不要）<!-- 担当: Codex, 完了: 2026-05-28。Live Activity の ContentState は現在カテゴリ/カテゴリセット名/公開状態だけを持ち、カテゴリ配列は Widget/App Group 側で読む前提へ寄せた -->
- [x] `VersionedSchema` + `SchemaMigrationPlan` の骨格を追加 <!-- 担当: Codex, 理由: SwiftData の作法・複雑, 完了: 2026-05-28 -->

### 5.6 DEBUG seed の隔離

- [x] `#if DEBUG seedPreviewPlansIfNeeded` を環境変数ゲート化（`-LiminalogSeedPreviewData YES` 等）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [~] プレビュー専用シードを `PreviewSupport` に集約し、実機 DEBUG ビルドでは入らないようにする <!-- 担当: Codex, 進捗: 2026-05-28 実機 DEBUG ではフラグなしに seedPreviewPlansIfNeeded が走らないようゲート化済。PreviewSupport への完全集約は未完了 -->

### 5.7 Swift Package 化（移行最終段）

- [ ] `Packages/LiminalogCore` を作成（Models / Stores / Logic / Sync / Activity / Extensions）<!-- 担当: Codex, 理由: 大規模再構成・ゼロベース -->
- [ ] `Packages/LiminalogUI` を作成（共通コンポーネント・Theme）<!-- 担当: Claude, 理由: UIコンポーネント抽出はSwiftUI整合性勝負 -->
- [ ] App / Widget 両ターゲットから Package を import 化 <!-- 担当: Codex -->
- [ ] ウィジェット側の private な `Color(hex:)` 重複実装を削除 <!-- 担当: Codex -->

### 5.8 テスト基盤

- [x] テストターゲット `LiminalogTests` 追加（Swift Testing 採用）<!-- 担当: Codex, 理由: 構成作業, 完了: 2026-05-28 -->
- [x] `TestModelContainer` ヘルパー実装 <!-- 担当: Codex, 完了: 2026-05-28。in-memory + CloudKit none でテスト実行 -->
- [x] `Clock` プロトコル + `SystemClock` / `TestClock` 実装 <!-- 担当: Codex, 理由: 設計上の純粋抽象, 完了: 2026-05-28。Swift標準Clockとの衝突回避のため名称は `LiminalogClock` -->
- [x] `Clock` を `ChapterStore` 等に注入できるよう改修 <!-- 担当: Codex, 完了: 2026-05-28。現状は `ChapterStore` 注入 + `ScoreCalculator.summary(now:)` 対応 -->
- [x] `ScoreCalculatorTests` 実装（仕様書の計算例を必ず含む）<!-- 担当: Codex, 理由: ロジックテストは Codex が書いたロジックのテスト, 完了: 2026-05-28 -->
- [x] `StreakCalculatorTests` 実装 <!-- 担当: Codex, 完了: 2026-05-28。現実装では独立 `StreakCalculator` ではなく `ScoreStore.streakCount` を対象にテスト -->
- [x] `DayBoundaryTests` 実装（0:00-24:00固定・日付またぎクリップ）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `ActiveChapterResolutionTests` 相当を追加（同カテゴリ再タップ・複数 active 収束）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `SeedCoordinatorTests` 実装（UserSettings / builtIn VisibilityPreset の重複統合）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `CategorySlotResolverTests` 相当を追加（CategorySet のスロット順・空きスロット保持）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `DashboardPeriodQueryTests` 相当を追加（today/week/month/year の期間境界）<!-- 担当: Codex, 完了: 2026-05-28 -->

---

## 6. Phase 1 — MVPコア（残タスク）

> 既存実装は Phase 0 移行後に「Phase 1 完了」となる前提。
> ここに残るのは「機能として未着手」のもの。

### 6.1 ウィジェット記録グリッド

- [x] `RecordingGridWidget` の Provider / Entry 設計 <!-- 担当: Codex, 完了: 2026-05-28。App Group SwiftData を読む `RecordingGridProvider` / `RecordingGridEntry` を追加 -->
- [x] `StartChapterIntent` (AppIntent) 実装 <!-- 担当: Codex, 理由: AppIntent + 並行制御 + 共有ストア書き込み, 完了: 2026-05-28。Widget 側で active Chapter を収束し、同カテゴリは継続・別カテゴリは直前を終了して新規開始 -->
- [x] `SelectCategorySetIntent` (configurable widget) 実装 <!-- 担当: Codex, 完了: 2026-05-28。`CategorySetEntity` / `EntityQuery` で Widget 設定からカテゴリセットを選べる -->
- [x] `RecordingGridView` (Widget UI) 実装 <!-- 担当: Codex, 完了: 2026-05-28。systemSmall は4枠、systemMedium は8枠を表示。アプリ側 CategoryGrid に近いアイコン/色/active ハイライトで構成 -->
- [x] アプリ側 mutation 後の `WidgetCenter.shared.reloadAllTimelines()` 呼び出し統一 <!-- 担当: Codex, 理由: 副作用の差し込み箇所が多い・抜け漏れ防止, 完了: 2026-05-28。`ChapterStore.markChanged()` に集約し、テスト実行中は Widget reload を抑制 -->
- [x] `LiminalogStatusWidget` の退役（または記録グリッドへ統合）<!-- 担当: Codex, 完了: 2026-05-28。Bundle から外し、`RecordingGridWidget` をメインWidgetに変更。ファイルは履歴参照用に残置 -->

### 6.2 公開設定 UI（Phase 1 最小版）

> Phase 3 で本格化する前に、最低限のトグルを Phase 1 で入れる。
> 詳細仕様は `docs/05 §8` 参照。

- [-] `VisibilitySheet` の最小版実装 <!-- 不要 (2026-05-24): isPublic 単純トグルなら CurrentChapterCard / ChapterEditSheet / contextMenu / 日単位メニュー で十分。専用シートは Phase 3 でプリセット選択導入時に再検討 -->
- [x] `CurrentChapterCard` に公開設定アイコン追加 <!-- 担当: Claude, 完了: 2026-05-23 (実装済を確認) -->
- [x] タイムラインの chapter context menu に「公開設定」追加 <!-- 担当: Claude, 完了: 2026-05-24 -->
- [x] `CalendarDayView` のツールバーに日単位公開設定メニュー追加 <!-- 担当: Claude, 完了: 2026-05-24 (全公開/全非公開/混在状態のアイコン分岐) -->
- [x] `ChapterStore.setChaptersVisibility(_:isPublic:)` 一括ヘルパー追加 <!-- 担当: Claude, 完了: 2026-05-24 -->

### 6.3 グリッドの「もっと見る」展開

- [-] グリッドが9件以上のときの展開UI <!-- 廃止 (2026-05-24): CategorySet スワイプ切替で代替するため不要 -->
- [-] グリッド優先度ロジックを `CategoryGridSelector` に切り出し <!-- 廃止 (2026-05-24): 自動ソート廃止のため不要 -->
- [-] `CategoryGridSelectorTests` <!-- 廃止 (2026-05-24): 同上 -->

### 6.3.1 CategorySet 位置指定グリッド（実装済）

- [x] `CategorySet.slots: [UUID?]` 固定長8 への移行 <!-- 担当: Claude, 完了: 2026-05-24 -->
- [x] `CategorySetEditSheet` を位置指定 UX に再設計 <!-- 担当: Claude, 完了: 2026-05-24 -->
- [x] `CategoryGrid` を 8 スロット固定描画 + 空きスロット placeholder <!-- 担当: Claude, 完了: 2026-05-24 -->
- [x] 選択中 CategorySet の `@AppStorage` 永続化 <!-- 担当: Claude, 完了: 2026-05-24 -->
- [x] `Category.usageCount` 削除 <!-- 担当: Claude, 完了: 2026-05-24 -->
- [x] CategorySet の並び替え UI（ドラッグでソート）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] スロットのドラッグ&ドロップ並び替え（現状はタップで配置）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] 空きスロットを Home 画面からタップして即割り当て（UX改善案）<!-- 担当: Codex, 完了: 2026-05-28 -->

### 6.4 プロフィール画面再設計 + 設定画面切り出し

> 現状 `ProfileView` の中に雑多に並んでいる情報・設定を、SNS準拠の自己表現プロフィール + ☰ ハンバーガー隔離の設定画面に分離する。
> 情報設計は `docs/09-profile-design.md`。具体的なUIは実装裁量。

- [x] `ProfileView` 再設計（docs/09 の情報設計に従う・UI最適化は実装側裁量）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] アイデンティティゾーン実装（プロフィール画像 + ニックネーム + bio + 主要スタッツ 連続/累計/友達数）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] 解放コレクション表示（ハイライト風・docs/09 §3.2）<!-- 担当: Codex, 2026-05-28: Phase 1 最小版として実績/継続/累計時間から解放状態を算出するバッジ表示へ更新。Phase 2 の本格アンロック実装後にデータソースを差し替える -->
- [x] 日記カードグリッド表示（DayDigest アーカイブ・docs/09 §3.3）<!-- 担当: Codex, 2026-05-28: Phase 1 最小版として記録済みChapterから日別カードを自動生成し、タップで当日の記録一覧を表示。Phase 2 のDayDigest生成後に永続カードへ差し替える -->
- [x] `SettingsView` 新規作成 + プロフィール右上 ☰ から開く（docs/09 §6 参照）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [-] 友達ビュー対応（同レイアウト・read-only・公開設定フィルタ・docs/09 §7）<!-- Phase 3 友達機能へ移動: ユーザーモデル/公開フィルタ未実装のため -->
- [-] 1日の始まり時間 Picker を `SettingsView` に追加 <!-- 撤回: 現行仕様では 0:00-24:00 固定。可変境界は超低優先度の将来検討 -->

### 6.4.1 装飾アイテム経済への移行（docs/09 v2 対応）

> docs/09 が v2 に更新され、コレクションの位置づけが「達成バッジ表示」から「**装着可能な装飾アイテム経済**」に変わった。
> 既存の Phase 1 最小版バッジ（§6.4 で実装済）は **暫定表示** として残し、Phase 2 で本格的な装着システムに置き換える。

- [ ] 装飾アイテムモデル設計（フレーム/バッジ/炎/アイコンセット/テーマ/バー/カード/月アート の8種類）<!-- 担当: Codex, 理由: モデル + マスターデータ設計、docs/09 §4.1 参照 -->
- [ ] 装着状態の永続化（`UserSettings` または専用モデルで「装着中アイテムID」を保持）<!-- 担当: Codex -->
- [ ] 解放条件判定ロジック（累計時間/ストリーク/パターン達成）<!-- 担当: Codex, 理由: docs/09 §4.2 のルール表とロジック -->
- [ ] コレクションハブ UI（種類別タブ、解放済/未解放、装着切替）<!-- 担当: Claude, 理由: SwiftUI レイアウト勝負 -->
- [ ] 「次に狙う解放」セクション（達成までの近さでソート）<!-- 担当: Claude -->
- [ ] プロフィール画像フレームの装着レンダリング<!-- 担当: Claude -->
- [ ] 名前バッジの装着レンダリング<!-- 担当: Claude -->
- [ ] ストリーク炎バリエーションの装着レンダリング<!-- 担当: Claude -->
- [ ] テーマカラー解放と装着（標準8色は既存、拡張色を解放対象に）<!-- 担当: Claude -->
- [ ] 装着アイテムの両ビュー（自分/友達）反映<!-- 担当: Claude, 依存: Phase 3 友達機能 -->
- [ ] 既存の Phase 1 バッジ表示を装飾アイテム経済データソースに差し替え<!-- 担当: Codex -->

---

## 7. Phase 2 — 振り返りの充実

### 7.0 カレンダー計画ハブ

> 方針: 月カレンダーは「スコア + 重要な予定」の俯瞰に絞る。24時間分の詳細予定や実績は日別タイムラインで扱う。現行実装では `PlanBlock.isImportant == true` を重要な予定として扱い、`isAllDay == true` は時間未指定を表す。既存データ互換のため `isAllDay == true` も重要予定として表示する。

- [x] `CalendarView` の月セルを、全予定/全実績の詰め込み表示から「スコアバッジ + 重要な予定のみ」へ変更 <!-- 担当: Codex, 完了: 2026-05-26, 理由: 表示ルール転換とスコア連携 -->
- [x] 複数日にまたがる重要予定を、日ごとにクリップしつつ開始/終了側だけ角丸にして繋がりが分かる表示にする <!-- 担当: Codex, 完了: 2026-05-26 -->
- [x] `CalendarDayView` の「終日・時間未指定」を「重要な予定」へ変更し、重要予定の追加/編集/削除導線を実装 <!-- 担当: Codex, 完了: 2026-05-26 -->
- [x] `PlanCreateSheet` を新規作成/編集兼用にし、重要な予定は開始日〜終了日の複数日入力に対応 <!-- 担当: Codex, 完了: 2026-05-26 -->
- [x] `TimelineView` の予定カード tap/contextMenu から `PlanCreateSheet(plan:)` を開けるようにし、未来の予定編集不能問題を修正 <!-- 担当: Codex, 完了: 2026-05-26 -->
- [x] active Chapter が未来日のカレンダー/スコアに継続中として出ないよう、`ChapterStore.chapters(on:)` / `chapters(from:to:)` の active 終端を `Date()` として判定 <!-- 担当: Codex, 完了: 2026-05-26 -->
- [x] `CalendarDayView` のスコアを日付下の薄字から独立した大型カードへ移動し、日付と重要予定の間で強く見せる <!-- 担当: Codex, 完了: 2026-05-26 -->
- [x] `PlanCreateSheet` のカテゴリ選択を色なし Picker から、CategorySet を横切替しながら色付き 4x2 グリッドで選ぶモーダルへ変更 <!-- 担当: Codex, 完了: 2026-05-26, 理由: 予定用セット/休日セット/特殊予定セットが増えた時の選択負荷を下げる -->
- [x] `PlanBlock.isImportant` を追加し、「重要な予定としてカレンダーに表示」と「時間未指定 (`isAllDay`)」を分離 <!-- 担当: Codex, 完了: 2026-05-26, 理由: 時間つき予定でも重要なら月カレンダーに開始時刻付きで出すため -->
- [x] `CalendarDayView` からチャプター新規作成導線を撤去し、日別タイムラインは既存実績の閲覧/編集 + 予定作成に限定 <!-- 担当: Codex, 完了: 2026-05-26, 理由: カレンダーは記録開始の場所にしない -->
- [ ] 友達の重要予定を月カレンダーに重ねる仕様を設計 <!-- 担当: 未定, 理由: Phase 3 友達機能と連動 -->
- [ ] 外部カレンダー取り込み時の変換ルールを実装（終日/時間未指定→重要予定、時間指定→時間つき予定）<!-- 担当: 未定, 理由: EventKit 連携は友達機能より低優先 -->

### 7.1 EventKit 連携

- [ ] `EventKitStore` 実装（権限取得・予定読み込み・差分同期）<!-- 担当: 未定, 理由: プラン必要 — Claude で API調査 → Codex でエラーケース詰め -->
- [ ] `PermissionGate` 共通コンポーネント実装 <!-- 担当: Claude, 理由: 全機能で再利用するUI抽象化 -->
- [ ] `CalendarEventCache` モデル + 同期ロジック <!-- 担当: Codex, 理由: EKEventStore の change notification 差分処理 -->
- [ ] `CalendarDayView` の終日エリアに EventKit 予定を表示 <!-- 担当: Claude -->
- [ ] `CalendarDayView` のタイムラインに EventKit 予定をうっすら表示 <!-- 担当: Claude -->
- [ ] `CalendarEventCreateSheet` / `CalendarEventDetailSheet`（EventKit 書き込み）<!-- 担当: Claude, 理由: シートUI -->
- [ ] EventKit 拒否時の PermissionGate 表示 <!-- 担当: Claude -->

### 7.2 ダッシュボード拡充

> 仕様書の§3全項目を実装。`docs/05 §4` 参照。

#### 共通基盤
- [ ] `DashboardCardKey` enum で全カードを識別子化 <!-- 担当: Codex, 理由: 一括設計 -->
- [ ] `UserSettings.dashboardCardOrder` から表示順を動的取得 <!-- 担当: Claude -->
- [ ] カード数値カウントアップアニメーション共通 ViewModifier <!-- 担当: Claude, 理由: SwiftUIアニメ -->
- [ ] `DashboardCustomizeSheet`（並び替え・表示切替）<!-- 担当: Claude -->

#### 今日
- [ ] カテゴリ別アクティビティリング風グラフ <!-- 担当: Claude, 理由: 高度なSwiftUIレイアウト -->
- [ ] カテゴリ別ドーナツグラフ <!-- 担当: Claude -->
- [ ] 24時間ブロック色分け（現行ヒートマップを仕様意図に合わせて再設計）<!-- 担当: Claude -->

#### 週間
- [ ] カテゴリ別トータル横棒グラフ（既存を週間期間用に調整）<!-- 担当: Claude -->
- [ ] 日ごとの積み上げ棒グラフ <!-- 担当: Claude -->
- [ ] 時間帯別傾向（朝/昼/夜の割合計算）<!-- 担当: Codex, 理由: 集計ロジック -->
- [ ] 時間帯別傾向の表示UI <!-- 担当: Claude -->
- [ ] 先週比差分バー（集計）<!-- 担当: Codex -->
- [ ] 先週比差分バーの表示UI <!-- 担当: Claude -->
- [ ] 友達比較 placeholder（Phase 3で本実装）<!-- 担当: Claude -->

#### 月間
- [ ] 月間カレンダーヒートマップ（GitHub風） <!-- 担当: Claude, 理由: GridLayout勝負 -->
- [ ] カテゴリ別折れ線グラフ（週単位推移）<!-- 担当: Claude -->
- [ ] 先月比差分バー <!-- 担当: Claude -->

#### 年間
- [ ] 年間カレンダーヒートマップ <!-- 担当: Claude -->
- [ ] 月ごとサマリー（テキスト+数値）<!-- 担当: Claude -->

### 7.3 アンロックシステム

- [ ] `UnlockItem` モデル定義 <!-- 担当: Codex, 理由: モデル + マスターデータ設計 -->
- [ ] `UnlockRules` 純粋関数（累計スコア → 解放判定）<!-- 担当: Codex, 理由: ルール表とロジック -->
- [ ] マスターデータ seed（26件・解放スケジュール逆算）<!-- 担当: Codex, 理由: 数値計算と整合性検証 -->
- [ ] `UnlockRulesTests` <!-- 担当: Codex -->
- [ ] `UnlockStore` 実装（解放トリガー・状態管理）<!-- 担当: Codex -->
- [ ] プロフィール画面のアンロック進捗カード <!-- 担当: Claude -->
- [ ] `UnlockGalleryView`（解放済みコレクション一覧）<!-- 担当: Claude -->
- [ ] アンロック解放時の通知・お祝い演出 <!-- 担当: Claude, 理由: SwiftUIアニメ -->

### 7.4 エクスポート・シェア

- [ ] タイムライン画像書き出し（縦長・Instagram向け）<!-- 担当: Claude, 理由: SwiftUI ImageRenderer の使い方 -->
- [ ] 週間サマリー画像書き出し <!-- 担当: Claude -->
- [ ] CSV書き出し（Chapter / PlanBlock）<!-- 担当: Codex, 理由: 文字列フォーマット・エスケープ処理 -->
- [ ] `ExportView`（書き出しオプション選択画面）<!-- 担当: Claude -->

### 7.5 ストリーク UI

- [ ] プロフィール画面のストリーク表示（🔥アイコン + 連続日数）<!-- 担当: Claude -->
- [ ] ストリーク途切れ時の通知（Phase 2.5）<!-- 担当: Codex, 理由: UserNotifications 設定 -->

### 7.6 日付またぎ・0:00固定境界

- [ ] 日付またぎチャプターのタイムライン表示（0:00-24:00 固定の `DayBoundary` 適用済前提）<!-- 担当: Claude -->
- [ ] ScoreCalculator の日跨ぎ正常性検証テスト <!-- 担当: Codex -->

---

## 8. Phase 3 — 友達機能

### 8.1 CloudKit Sync 基盤

> Phase 0 で CloudKit Private DB を ON 済の前提。
> Phase 3 では CKShare による友達共有を追加。

- [ ] `CloudKitSyncCoordinator` 実装（アカウント状態監視・同期エラー通知）<!-- 担当: Codex, 理由: CKContainer の async API + エラー分岐 -->
- [ ] iCloud 未ログイン時のフォールバック UI <!-- 担当: Claude -->
- [ ] 同期エラーバナー <!-- 担当: Claude -->
- [ ] `MyRecordsZone` への移行（Chapter / PlanBlock を専用ゾーンへ）<!-- 担当: Codex, 理由: CloudKitゾーン操作 -->
- [ ] `SharedTimelineZone` の用意 <!-- 担当: Codex -->

### 8.2 CKShare 友達関係

- [x] `Friend` モデル定義 <!-- 担当: Codex, 完了: 2026-05-30。CloudKit実共有前のローカル関係モデルとして、pendingIncoming/pendingOutgoing/accepted/blocked、現在ステータス、今の気持ち/ひとこと、短期スコア、招待コード、favoriteを保持 -->
- [ ] `ShareCoordinator` 実装（CKShare 作成・参加・受諾）<!-- 担当: Codex, 理由: CloudKit 複雑async -->
- [x] 招待リンク生成・送信 UI <!-- 担当: Codex, 完了: 2026-05-30。11-friends-designに合わせ、ID検索ではなくリンク/QRベースに変更。`liminalog://friend-invite` URL、QR表示、ShareLinkを実装。2026-05-30追記: Instagram/BeRealに倣い、主導線をプロフィール画面の「シェア」へ移動 -->
- [x] プロフィール画面からのプロフィール共有導線 <!-- 担当: Codex, 完了: 2026-05-30。`ProfileShareSheet` を共通化し、プロフィール画面から自分の招待QR/リンクを共有できるようにした。友達タブは「友達を探す」ではなく、空状態の共有CTAと受信導線に限定 -->
- [~] 招待受信時のディープリンクハンドリング <!-- 担当: Codex, 進捗: 2026-05-30。URL Scheme登録とRootTab→FriendsViewへの受け渡しを実装。Universal Link/CKShare受諾はDeveloper登録後のShareCoordinatorで追加 -->
- [x] `FriendsAddView`（受け取った招待入力版）<!-- 担当: Codex, 完了: 2026-05-30。初期仕様のメール/iCloud検索は11-friends-designで廃止。プロフィール共有は `ProfileShareSheet` に分離し、FriendsAddView は受け取ったリンク/コードを pendingIncoming 化する入力に限定 -->
- [ ] `CKSubscription` 設定（友達のレコード更新監視）<!-- 担当: Codex -->
- [ ] バックグラウンド通知ハンドラ <!-- 担当: Codex -->

### 8.3 公開設定（本格実装）

- [ ] `VisibilityPreset` モデル（新設計）<!-- 担当: Codex -->
- [ ] ビルトインプリセット seed（仲良し/知り合い/オフ/カスタム）<!-- 担当: Codex -->
- [ ] `VisibilityPresetManagementView` <!-- 担当: Claude -->
- [ ] `VisibilitySheet` を多段（プリセット / カスタム / カテゴリ別）に拡張 <!-- 担当: Claude -->
- [ ] 翌日公開モードのバックグラウンドタスク（深夜に SharedTimeline へスナップショット書き出し）<!-- 担当: Codex, 理由: BGTaskScheduler + データ加工 -->
- [ ] `PublishMode.realtime` 時の即時 CKShare 反映 <!-- 担当: Codex -->

### 8.4 友達閲覧

- [~] `FriendDetailView`（友達のデイビュー閲覧）<!-- 担当: Codex, 進捗: 2026-05-30。友達プロフィール/現在ステータス/短期スコア/お気に入り/削除/ブロックの詳細UIまで実装。公開済みデイビュー閲覧はSharedTimeline/VisibilityPreset本実装後に接続 -->
- [ ] 友達のタイムラインを公開設定でフィルター描画 <!-- 担当: Codex, 理由: フィルターロジック -->
- [ ] `Reaction` モデル + 絵文字パレットUI <!-- 担当: Claude -->
- [ ] `Comment` モデル + コメント投稿UI <!-- 担当: Claude -->
- [ ] リアクション/コメントの CKShare 同期 <!-- 担当: Codex -->

### 8.5 ランキング

- [~] ランキング集計ロジック（今日/昨日/今週・タイブレーク仕様要確認）<!-- 担当: Codex, 進捗: 2026-05-30。自分は既存ScoreCalculator、友達はFriendスナップショットのtoday/yesterday/weekScoreでソート。CKShare経由の友達スコア更新は未接続 -->
- [x] `RankingScrollStrip`（横スクロール）<!-- 担当: Codex, 完了: 2026-05-30。FriendsView内に今日/昨日/今週セグメント付き横スクロールランキングを実装 -->
- [x] 友達プロフィールリスト（今の気持ち・現在ステータス）<!-- 担当: Codex, 完了: 2026-05-30。accepted friendsをカード行で表示し、名前横の現在ステータスピル、@handleの代わりになる今の気持ち/ひとこと、詳細遷移を実装。スコアはランキング側に寄せ、友達行では主役にしない。2026-05-30追記: 名前長でステータス開始位置が揺れないよう、名前列を固定幅化。ひとことはcaption2/薄めのsecondaryで控えめに表示 -->
- [x] お気に入り友達の上部固定 <!-- 担当: Codex, 完了: 2026-05-30。accepted friendsのソートでfavoriteを先頭固定し、詳細からtoggle可能 -->
- [x] DEBUG用の架空フレンドseed <!-- 担当: Codex, 完了: 2026-05-30。`LiminalogSeedDevFriends` UserDefaults または `-LiminalogSeedDevFriends` 起動引数が有効なDEBUGビルドだけ、Mika/Sora/Ren/Yui の4人をローカルに生成。今の気持ち/ひとこともseedし、既存debug友達にもbackfillする。友達0人状態を壊さず、UI確認時だけ利用する -->

### 8.6 カテゴリマッピング

- [ ] `FriendCategoryMapping` モデル <!-- 担当: Codex -->
- [ ] 自動マッピングロジック（デフォルトカテゴリ同士）<!-- 担当: Codex -->
- [ ] `FriendCategoryMappingSheet`（手動マッピング・多対一）<!-- 担当: Claude -->
- [ ] 比較表示時のカラー統一スイッチ <!-- 担当: Claude -->
- [ ] 未マッピング時の促し UI <!-- 担当: Claude -->

### 8.7 友達ウィジェット

- [ ] `FriendStatusWidget` (Small, 1人)<!-- 担当: Codex, 理由: WidgetKit + Provider 設計 -->
- [ ] `FriendsListWidget` (Medium, 複数人)<!-- 担当: Codex -->
- [ ] `MixedWidget` (Large, 自分+友達)<!-- 担当: Codex -->
- [ ] お気に入り友達設定 UI（`WidgetFriendsView`）<!-- 担当: Claude -->

### 8.8 グループチャレンジ

- [ ] `GroupChallenge` モデル設計（要詳細プラン）<!-- 担当: 未定 -->
- [ ] グループ作成・参加フロー <!-- 担当: 未定 -->
- [ ] 目標設定 UI <!-- 担当: 未定 -->
- [ ] 達成度ダッシュボード <!-- 担当: 未定 -->

### 8.9 友達のカレンダー予定共有

- [~] PlanBlock の CKShare 配信（公開設定に基づく）<!-- 担当: Codex, 進捗: 2026-05-30。Developer登録前のためCloudKit実送受信は未接続。先に `FriendSharedPlanSnapshot` を受信/表示用の安定スナップショットとして追加し、`PlanBlock.isPublic == true` の予定だけを書き出せる変換関数とテストを実装。CKShare接続時はこのスナップショットを送受信単位にする -->
- [x] FriendDetailView での予定表示 <!-- 担当: Codex, 完了: 2026-05-30。友達プロフィールのカレンダーボタンから、友達専用の月カレンダーへ遷移。自分のカレンダータブと同じく年月ピッカー、曜日固定、42セルグリッド、スコア表示、重要予定ラベル、複数日バー、検索、読み取り専用の日別詳細を実装。月グリッドには重要/終日予定だけを表示し、日別詳細ではその日に公開された予定全体を表示する -->

---

## 8.5 Codex プランレビュー対応（最優先）

> [docs/07-codex-plan-review.md](../Liminalog/Views/Profile/docs/07-codex-plan-review.md) で挙がった 12 項目の修正指示。
> **Phase 0 移行に着手する前に、まずここを完了させて docs を最新化する。**

### ドキュメント更新

- [x] `04-data-model.md`: `@Attribute(.unique)` を全モデルから削除 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [x] `04-data-model.md`: `UserSettings.settingsKey` / `UnlockItem.key` / `VisibilityPreset.builtInKey` の重複整理方針追記 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [x] `04-data-model.md`: `Chapter.photoData` を未確定 or `photoLocalIdentifier` + `thumbnailData` 案へ変更 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [x] `04-data-model.md`: CloudKit ゾーン設計を「Phase 3 検証タスク」に格下げ + SwiftData自動同期と CKShare の境界を明示 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [x] `03-architecture.md`: App Group / CloudKit ID 候補を `app.YasudaRyuga.Liminalog` ベースに修正 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [x] `03-architecture.md`: 移行ロードマップを「最小 Core 化 → Widget」順に変更 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [x] `03-architecture.md`: SwiftData managed sync と CKShare 手動共有を分離 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [x] `03-architecture.md`: `ModelConfiguration` を `groupContainer:` ベースのサンプルに修正 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [ ] `05-screen-flow.md`: `@AppStorage` 設定のうち同期したいものは `UserSettings` に寄せる方針整理 <!-- 担当: Claude (07 §5) -->
- [ ] `05-screen-flow.md`: Dashboard の動的 `@Query` を子 View 化 or `ScoreStore.summary(period:)` 集計へ変更 <!-- 担当: Claude (07 §7) -->
- [ ] `05-screen-flow.md`: active chapter が複数存在する場合の UI/Store 収束ルール追記 <!-- 担当: Claude (07 §8) -->
- [x] `06-testing.md`: `SeedCoordinatorTests` / `ActiveChapterResolutionTests` / `DashboardPeriodQueryTests` / CloudKit unique 非使用の重複統合テストを追加 <!-- 担当: Codex, 完了: 2026-05-24 -->

### Phase 0 実装側への波及（既存 §5 タスクを上書き）

- [ ] §5.1 `SharedModelContainer` 実装時は `groupContainer:` イニシャライザ + Bundle ID ベースの ID を使う <!-- 担当: Codex -->
- [x] §5.5 全モデルから `@Attribute(.unique)` を入れない（既存ドラフト案を撤回）<!-- 担当: Codex, 完了: 2026-05-24 -->
- [x] §5.5 `Chapter.photoData` の追加は保留。代わりに `photoLocalIdentifier`/`thumbnailData` を検討 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [~] `BootstrapStore` / `SeedCoordinator` の追加（singleton / master データの重複統合）<!-- 担当: Codex, 理由: 競合・重複ロジック, 進捗: 2026-05-28 SeedCoordinator 追加。UserSettings と builtInKey 付き VisibilityPreset の重複統合を起動時に実行。BootstrapStore は未実装 -->
- [x] `ChapterStore.startChapter` の冒頭で active chapter 複数件を収束させるロジック追加 <!-- 担当: Codex, 完了: 2026-05-24 -->

### Codex FB 2026-05-24 追加分（§10.5 より）

- [x] `04-data-model.md` の CategorySet 設計を現実装の `slots: [UUID?]` 方針に合わせて更新 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [x] `CategorySet.slots: [UUID?]` の CloudKit managed sync 互換性を検証 + 必要なら代替案（`slot0...slot7: UUID?` 個別フィールド / `[String]` で空文字扱い 等）を docs/04 で提案 <!-- 担当: Codex, 理由: SwiftData/CloudKit 制約の実装者視点 (10.5 #3), 完了: 2026-05-28。現時点は破壊的移行を避けて維持、TestFlight前に実機CloudKitで再検証 -->
- [ ] TestFlight 前に `CategorySet.slots: [UUID?]` を実機 CloudKit 同期で検証し、失敗する場合は `slot0...slot7` または `[String]` 案へ移行する <!-- 担当: Codex, 理由: 実同期はシミュレータ/単体テストだけでは確定できない -->

---

## 8.6 タイムライン UI 再設計 v2（docs/08）

> [docs/08-timeline-redesign.md](../Liminalog/Views/Profile/docs/08-timeline-redesign.md) で確定した方針の実装タスク。
> 旧「縦方向タイムライン + 実績/比較/予定」方針を撤回し、24時間バー + 固定高さカードリストへ再設計する。優先順は docs/08 §9 参照。

**現行仕様の注意:** タイムラインのタブは **実績 / 予定の 2 タブのみ**。旧ログにある `実績 / 比較 / 予定`、`予定 / 実績 / 両方`、左右分割比較は v1 履歴であり、現行実装対象ではない。比較は常時表示の 24時間バー 2 段で行う。

### 課題1: 保存仕様の固定

- [x] `ChapterStore.startChapter` からカテゴリ切替時の自動削除/自動リザレクトを撤去 <!-- 担当: Codex, 完了: 2026-05-24 -->
- [x] スコア公平性のため、今日以前の時間つき予定は時間/カテゴリ/内容/削除をロックし、重要フラグ/メモ/公開設定だけ編集可能にする <!-- 担当: Codex, 完了: 2026-05-26 -->
- [x] 時間未指定の重要予定 (`isAllDay == true`) はスコア対象外のため、過去日・今日・複数日またぎでも追加/編集/削除できる例外を追加 <!-- 担当: Codex, 完了: 2026-05-26 -->
- [x] スコア公平性のため、前日以前の実績は時間/カテゴリ/削除をロックし、メモ/気分/場所/公開設定だけ編集可能にする <!-- 担当: Codex, 完了: 2026-05-26 -->
- [x] 実績の手動追加を今日の範囲に限定し、予定の新規追加を明日以降に限定する <!-- 担当: Codex, 完了: 2026-05-26 -->
- [x] A→B→C の短時間切替でも A/B/C が別 Chapter として残るテストを追加 <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] 手動追加・編集時に既存 Chapter と重複する実績を保存ブロックするロジックを追加 <!-- 担当: Codex, 理由: 時間範囲の重複判定, 完了: 2026-05-28 -->
- [x] 重複保存ブロック時の警告 UI を追加 <!-- 担当: Codex, 完了: 2026-05-28。最小警告UIまで実装。文言/見た目の磨き込みは Claude が必要に応じて継続 -->
- [ ] 明示削除/統合 UX を別導線として設計する（保存時には削除しない）<!-- 担当: Claude -->

### 課題2: 表示モデル導入

- [x] `TimelineEntry` / `TimelineEntryKind` / `TimelineEntryMetadata` を定義 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] `TimelineEntryBuilder` 相当の変換処理で対象日の 0:00-24:00 クリップを実装 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] Chapter / PlanBlock からカード用・バー用の共通 entry を生成 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] 予定・実績それぞれの gap entry（空白カード）を生成 <!-- 担当: Codex, 完了: 2026-05-25 -->

### 課題3: 24時間バー

- [x] `DayOverviewBar` を追加し、予定/実績 2 段を常時表示 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] 0:00-24:00 の時間比例でセグメント位置・幅を算出 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] 0/3/6/9/12/15/18/21/24 の目盛り表示 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] 15分未満はカラーのみ、15分以上でも狭い場合はアイコン省略 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] active Chapter の右端を現在時刻まで伸ばして timer 更新 <!-- 担当: Codex, 完了: 2026-05-25 -->

### 課題4: カードリスト

- [x] 旧 `TimelineDisplayMode`（実績/比較/予定）を撤去し、`TimelineTab`（実績/予定）へ置換 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] `@AppStorage("timelineSelectedTab")` を追加し、初期値は実績 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] `TimelineEntryCard` を固定高さで実装（左外時刻レール、アイコン、カテゴリ名、予定通り表示、右側経過時間）<!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] カード左端にカテゴリカラーの細いバーを表示 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] 追記情報（メモ/気分/写真/場所）は固定高さ内で要約表示 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] `TimelineGapCard` を空白時間カードとして追加。タップで `ChapterCreateSheet`（実績タブ時）/ `PlanCreateSheet`（予定タブ時）を開く。ギャップ先頭時刻をシートに渡す。`plus.circle` アイコンで追加可能を示す <!-- 担当: Codex→Claude, 完了: 2026-05-26 (方針変更: 2026-05-25 の「タップなし」から「タップで追加」へ変更) -->

### 課題5: バーとカードの連動

- [x] タイムライン内部スクロール撤去に伴い、バーセグメントタップ時の `ScrollViewReader.scrollTo` は廃止 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] 対応カードを一時ハイライト <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] バータップ時の quick detail（カテゴリ名・時間・経過時間）を表示 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] バー空白タップで追加画面を開く導線を撤去。追加は画面上部 `+` / カテゴリ記録導線へ集約 <!-- 担当: Codex, 完了: 2026-05-25 -->

### 課題6: 旧タイムライン撤去・検証

- [x] 縦方向の時間比例ブロック描画を撤去 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] 左右分割レーン / 横カラム割当ロジックを撤去 <!-- 担当: Codex, 完了: 2026-05-25 -->
- [x] 旧 `timelineDisplayMode` から新 `timelineSelectedTab` への扱いを決める（新 UI では参照しない）<!-- 担当: Codex, 完了: 2026-05-25 -->
- [ ] 固定高さカード、短時間記録、日付またぎ、バー位置計算の Preview/Test を追加 <!-- 担当: Codex -->
- [x] 日付またぎ Chapter は DB では1件のまま、表示・スコア・バーだけ 0:00-24:00 にクリップされるテストを追加 <!-- 担当: Codex, 完了: 2026-05-28。DayBoundary/ScoreCalculator のクリップをテスト済み -->
- [ ] 実機で 320pt 幅でも目盛り・カード文言が破綻しないか確認 <!-- 担当: Claude -->

---

## 9. Phase 4 — UX向上・ソーシャル深化

- [ ] ダッシュボード 2 人比較 UI（24時間バー + カード要約の新タイムライン仕様に合わせる）<!-- 担当: Claude, 理由: SwiftUI レイアウト -->
- [ ] 複数人比較画像書き出し（人数横並び・名前・アイコン）<!-- 担当: Claude -->
- [ ] シンクロハイライト（同時刻行動を強調）<!-- 担当: Codex, 理由: 重なり検出アルゴリズム -->
- [ ] シンクロハイライト表示UI <!-- 担当: Claude -->
- [ ] Siri ショートカット拡充（App Intents）<!-- 担当: Codex, 理由: AppIntent + Donation -->
- [ ] HealthKit 連携（就寝・起床自動検知 → Chapter自動生成）<!-- 担当: Codex, 理由: HealthKit + ロジック -->
- [ ] HealthKit 権限ゲートUI <!-- 担当: Claude -->
- [ ] テーマ着せ替え追加（カラーパターン拡充）<!-- 担当: Claude -->
- [ ] テーマ切替の `EnvironmentValues` 差し替え機構 <!-- 担当: Codex, 理由: SwiftUI Environment 設計 -->
- [ ] チャプタータイマー表示（常時経過時間）<!-- 担当: Claude -->

---

## 10. 完了ログ

新規タスクの追加・実装完了・設計変更を時系列で記録。**日付は ISO 形式（YYYY-MM-DD）で。**

| 日付 | 担当 | 内容 |
|---|---|---|
| 2026-05-30 | Codex | 友達との予定共有をリリース可能ラインへ近づけるため、`Friend` に共有予定スナップショットJSONを追加し、公開された予定を `FriendSharedPlanSnapshot` として受け取る設計に変更。自分側の `PlanBlock.isPublic == true` だけをスナップショット化する変換関数とテストを追加し、公開/非公開の境界をコードで担保。友達カレンダーは自分のカレンダータブと同じ月表示に寄せ、年月ピッカー、曜日ヘッダー、42セルグリッド、スコアバッジ、重要予定ラベル、複数日バー、検索、読み取り専用の日別詳細を実装。Developer登録前のためCloudKit/CKShareの実送受信は未接続だが、CKShare接続時の受信データ契約とUIの器を先に固定した。 |
| 2026-05-30 | Codex | 友達プロフィール詳細を自分のプロフィール画面に寄せて再設計。ヒーローをプロフィールカード装飾・大きめアバター・装備バッジ・ひとこと中心の構成に変更し、カード右上に小さな「カレンダー」ボタンとお気に入りボタンを配置。プロフィール直下にはストリーク/昨日/今週のスタッツ、現在ステータス、装備とコレクションの4列サマリーを置く。カレンダーはプロフィール下へ無理に埋め込まず、ボタンから友達専用カレンダー画面へ遷移する方針で実装。現時点ではCloudKit履歴同期前のため、友達カレンダーは今日/昨日の受信済みスコアのみ表示し、共有予定は同期後に表示する器として用意した。 |
| 2026-05-30 | Codex | 期間別ランキング詳細シートを暦期間選択型に変更。詳細ランキングに「日間」を追加し、タブを日間/週間/月間/年間に拡張。タブ下に対象期間ラベル（例: `2026年5月30日` / `2026 5/24-5/30` / `2026年5月` / `2026年`）を表示し、ラベルタップでホイール式の期間選択シートを開けるようにした。自分の週間/月間/年間スコアは直近日数ではなく、選択した暦週・暦月・暦年内の予定あり日スコア平均へ変更。友達側は履歴同期前のため、現時点では期間ごとのDEBUG代表スコアを表示する。 |
| 2026-05-30 | Codex | 期間別ランキング詳細シートの自分行表示を調整。友達行だけ右端に矢印があり、自分行には矢印がないことでスコア列の位置がズレていたため、矢印領域を常に固定幅で確保し、自分行では透明表示に変更。あわせて自分行を disabled にして全体が薄く見える状態も解除し、リスト内の位置揃えを統一した。 |
| 2026-05-30 | Codex | 友達タブのランキング構成を変更。メイン画面上部のランキングは昨日のランキングだけを表示し、期間切替セグメントは廃止。ラベルと右上の「もっと見る」ボタンを同じ高さに揃えた。「もっと見る」から週間・月間・年間ランキングをリスト形式で確認できるシートを開く方針に変更。友達データには月間/年間スコアを追加し、開発ストア世代を `2026053006` に更新。 |
| 2026-05-30 | Codex | 友達リスト行のストリーク位置を微調整。名前横に置いていた小さな炎+数字を、名前の下段にあるつぶやきテキストの左側へ移動。ストリークをプロフィール名の装飾ではなく、ひとこと/近況に近い補足情報として読める配置にした。 |
| 2026-05-30 | Codex | 友達リスト行のストリーク表示を再調整。右側の正方形タイルからストリークを外し、名前横に小さな炎アイコン + 数字だけのインライン表示として配置。右側タイルは現在ステータス専用に戻し、リストの情報密度を下げつつストリークは常に名前と一緒に確認できる形にした。 |
| 2026-05-30 | Codex | ストリーク装飾の方向性を調整。ストリークは「別モチーフのアイコン」ではなく、基本的に炎アイコンの色違いとして統一する方針に変更。既存ID（`flame` / `bolt` / `sun` / `spark`）はデータ互換のため維持しつつ、表示アイコンはすべて `flame.fill` に揃え、赤・金・橙・紫の炎としてプロフィール/友達リスト/ランキング/詳細で一貫して見えるようにした。 |
| 2026-05-30 | Codex | 友達リスト行の右側情報配置を再設計。現在ステータスを名前横のピルから外し、右矢印の左に正方形タイルとして配置。上にアイコン、下に短い文字を置くTodayカテゴリボタン風の見た目にした。あわせて `Friend.streakCount` を追加し、同じ右側タイル群にストリーク日数も表示。DEBUG友達seedにもストリーク値を設定し、開発ストア世代を `2026053005` に更新。 |
| 2026-05-30 | Codex | 友達タブの装飾反映方針を調整。ランキング/友達リストは一覧性を優先し、カード背景・枠線・下部リズムバーのプロフィールカード装飾を外して通常カードへ戻した。アバターフレームは本人識別の個性として一覧にも残し、タップ後の友達詳細ヒーローのみプロフィールカード装飾をしっかり反映する設計に変更。 |
| 2026-05-30 | Codex | 友達タブにもプロフィール装備を反映。`Friend` に `profileBadgeID` / `profileIconFrameID` / `profileStreakIconID` / `profileCardStyleID` を追加し、DEBUG友達seedにも各装備を設定。ランキングカード・友達リスト・友達詳細ヒーローで、アバターフレームとプロフィールカード装飾（背景/枠線/下部リズムバー）を表示するよう変更。プロフィール側の装飾カタログ/Viewは友達タブからも使えるよう内部共有化し、開発ストア世代を `2026053004` に更新。 |
| 2026-05-30 | Codex | プロフィールカード下のスタッツ表記を調整。左カードのラベルは「連続」から「ストリーク」へ、中央カードのラベルは「累計獲得」から「累計スコア」へ変更し、指標の意味がユーザーに直感的に伝わる文言に統一。 |
| 2026-05-30 | Codex | プロフィールの「装備とコレクション」上部サマリーで、フレーム/カードが抽象的なSF Symbolsだけに見えていた問題を修正。フレームは実際にプロフィール画像へ重ねている `ProfileIconFrameView` をミニ表示し、カードは実際のプロフィールカードと同じ背景色・右上マーク・下部リズムバー・枠線を使う `ProfileMiniCardStyleView` に置き換えた。4列サマリー内で潰れすぎないよう、実物表現を保ったまま小型プレビュー化。 |
| 2026-05-30 | Codex | プロフィールカード下の中央スタッツを「累計時間」から「累計獲得スコア」へ変更。直近365日分の `ScoreCalculator.totalScore` を合算し、`pt` 表示にした。中央カードのアイコンは時計から星へ変更し、ラベルは狭いカード内で読みやすいよう「累計獲得」として表示。 |
| 2026-05-30 | Codex | プロフィールカードの操作ボタンと余白を再調整。編集/シェアボタンが本文横で視線を邪魔していたため、カード右上の端へ寄せて操作エリアとして独立させた。あわせてヒーローカードの縦padding、内部spacing、つぶやきの最小高さを増やし、プロフィールカード全体の詰まり感を軽減。 |
| 2026-05-30 | Codex | プロフィールの「装備とコレクション」最下部に表示していたカード装飾一覧（Clean/Glass/Dawn/Mint）を削除。装着中カードは4列サマリーの「カード」で確認し、カード装飾の選択・一覧確認はプロフィール編集画面に集約する方針に整理。不要になった `ProfileCollectionCardStyle` View も削除。 |
| 2026-05-30 | Codex | プロフィールカード内のつぶやき表示が右側に余白を残したまま早く折り返す問題を修正。名前/バッジ/つぶやきのテキスト列に `maxWidth: .infinity` と `layoutPriority(1)` を付与。さらに編集/シェアボタンをHStackの幅計算から外してカード右上overlayへ移動し、名前だけボタンぶつかり防止の右余白を持たせつつ、つぶやきは横幅を最大限使えるよう調整。 |
| 2026-05-30 | Codex | プロフィールの「装備とコレクション」内にある現在装着中サマリーを4列表示へ変更。バッジ/フレーム/カード/連続を1行で確認できるようにし、横幅の余りを減らした。4列化に合わせてタイルの余白と最小高さを少しだけ圧縮し、下のコレクション一覧との役割差が出る軽いサマリー表示に調整。 |
| 2026-05-30 | Codex | プロフィールカードの余白と装飾要素を拡張。ヒーローカードの縦padding/spacingを増やし、詰まり感を軽減。`UserSettings.profileCardStyleID` を追加し、プロフィールカード自体を装備アイテムとして扱えるようにした。装備とコレクションの上部サマリーは2列グリッドへ変更し、バッジ/フレーム/カード/連続アイコンを表示。コレクション一覧にもカード装飾行を追加し、現在装着中のカードをチェック表示。編集画面にもプロフィールカード選択UIを追加し、Clean/Glass/Dawn/Mint のカード装飾を切り替え可能にした。開発ストア世代と必須カラムも更新。 |
| 2026-05-30 | Codex | プロフィール装備UIを再調整。プロフィールカード内のフレーム/バッジ説明チップ削除とアイコンフレーム前面描画は維持しつつ、「装備とコレクション」セクションは前回の一覧表示に戻した。プロフィールカードは装着結果を見せる場、下部コレクションは解放/装着状況を俯瞰する場として役割を分離。 |
| 2026-05-30 | Codex | プロフィール装備UIを整理。プロフィールカード内のフレーム/バッジ説明チップと「装備とコレクション」セクションを削除し、表示画面は装着済みの見た目だけに集中させた。バッジ/フレーム/ストリークの一覧と選択は編集画面に集約。アイコンフレームはプロフィール画像より前面レイヤーで描画するように変更し、装着効果が隠れないよう修正。プロフィールカード装飾も今後の解放要素候補として扱える方針を確認。 |
| 2026-05-30 | Codex | プロフィールタブの満足感を高めるため、自己表現要素を「装備」として再設計。編集/シェアの横長ボタンをヒーローカード右上の小型アイコンボタンへ縮小し、`UserSettings` に `profileBadgeID` / `profileIconFrameID` / `profileStreakIconID` を追加。プロフィール画像フレーム、装着中バッジ、ストリークアイコンを保存・表示できるようにし、編集シートにバッジ/アイコンフレーム/ストリーク選択UIを追加。開発ストア必須カラムと世代番号も更新した。検証: `xcodebuild test` で Swift Testing 26件成功、シミュレータでプロフィール表示と装着反映を確認。 |
| 2026-05-30 | Codex | AppIconをユーザー修正版へ差し替え。Default/Dark/Tinted の1024px PNGを `AppIcon.appiconset` に追加し、`Contents.json` で参照。`xcodebuild build/test` とシミュレータホーム画面スクリーンショットで小サイズ表示を確認した。 |
| 2026-05-30 | Codex | 友達タブUI再調整: ランキング上位1〜3位のカード自体を派手にする方針を撤回。カードサイズ/背景/余白は全順位で揃え、豪華さは順位アイコン/ラベルだけで表現する形に変更。色の面積を減らし、ランキング横スクロール時の視線移動を安定させた。 |
| 2026-05-30 | Codex | 友達タブUI調整: 最上部の「つながり」ラベルと「今」横スライドを削除し、ランキングをファーストビューの主役に整理。ランキングカードはステータス表示をやめ、アイコン/名前/スコア/順位に絞った。1〜3位はリッチな上位カード、4位以下はグレー基調の控えめカードに分けた。友達カードは右側スコアを削除し、名前横に現在ステータスの細いピルを表示。右端にchevronを置き、プロフィールへ遷移できる押せるカードとして識別しやすくした。 |
| 2026-05-30 | Codex | 友達追加導線をInstagram/BeRealに近い「プロフィール → プロフィールをシェア」中心に変更。`ProfileShareSheet` を新設してQR/招待コード/ShareLinkを共通化し、プロフィール画面のシェアボタンと友達タブ空状態から同じ共有カードを開く。友達タブ右上は受け取った招待入力専用にした。DEBUGでは `LiminalogSeedDevFriends` フラグで4人の架空フレンドをseedし、ランキング/現在ステータス/友達リストの見え方をシミュレータ確認できるようにした。 |
| 2026-05-28 | Codex | Phase 1: `RecordingGridWidget` を追加。Widget Extension 側に最小の SwiftData 共有モデルと App Group 用 ModelContainer を置き、`RecordingGridProvider` がカテゴリセット/カテゴリ/active Chapter を読む。systemSmall は4枠、systemMedium は8枠表示。 |
| 2026-05-28 | Codex | Phase 1: `StartChapterIntent` / `SelectCategorySetIntent` を実装。Widget 設定でカテゴリセットを選択でき、カテゴリボタンから App Group SwiftData に直接 Chapter を書き込む。書き込み時は active Chapter を収束し、同カテゴリは継続、別カテゴリは直前を終了して新規開始する。 |
| 2026-05-28 | Codex | Phase 1: `LiminalogWidgetBundle` のメインWidgetを静的な `LiminalogStatusWidget` から `RecordingGridWidget` へ変更。`CategoryGrid` の選択セットは `UserSettings.enabledCategorySetID` にも保存し、Widget 側のデフォルト表示セットとアプリ側の普段使いセットが揃うようにした。 |
| 2026-05-28 | Codex | Phase 0/1 bridge: `LiminalogActivityAttributes.ContentState.categories` と Widget 側の `IslandCategory` を削除し、Live Activity は現在カテゴリ・カテゴリセット名・公開状態だけを渡す形へ整理。Dynamic Island 下段はカテゴリ配列ではなくセット名/公開状態の軽い情報表示に変更した。 |
| 2026-05-28 | Codex | Phase 1: `ChapterStore.markChanged()` を追加し、Chapter/Category/Plan 系 mutation 後の `revision` 更新と `WidgetCenter.shared.reloadAllTimelines()` を一箇所に集約。Widget 記録グリッド本体は未実装だが、アプリ側変更を Widget Timeline に反映する土台は完了。XCTest 中は reload を抑制する。 |
| 2026-05-28 | Codex | Phase 0: テスト網を拡張。active Chapter 複数件の収束、同カテゴリ再タップ継続、CategorySet スロット順解決、`SeedCoordinator` の UserSettings / built-in VisibilityPreset 重複統合、`ScoreStore.streakCount`、Dashboard 期間境界を Swift Testing で検証。Dashboard の期間計算は `DashboardPeriod.dateInterval(containing:)` に切り出し、UI 表示は維持した。 |
| 2026-05-28 | Codex | Phase 0: `LiminalogTests` ターゲットを追加し、Swift Testing で `DayBoundaryTests` / `ScoreCalculatorTests` / `ChapterStoreTests` を実装。テストホスト起動時は `SharedModelContainer.inMemory()` を使い、Live Activity 更新を XCTest 中だけ無効化して、Cloud/AppGroup 初期化に依存しないロジックテストを走らせる構成にした。 |
| 2026-05-28 | Codex | Phase 0: 実績 Chapter 同士の重複保存を Store 層でブロック。手動追加・編集は `start < end`、未来終了禁止、既存 Chapter との重複禁止を満たす場合だけ保存し、`ChapterCreateSheet` / `ChapterEditSheet` でも保存不可理由を警告表示するようにした。カテゴリ短時間切替は A/B/C が別 Chapter として残ることをテスト済み。 |
| 2026-05-28 | Codex | Phase 0: `CategorySet.slots: [UUID?]` の CloudKit 互換リスクを docs/04 に整理。現時点ではリリース前の破壊的移行を避けて維持し、TestFlight 前に実機 CloudKit 同期で再検証、失敗時は `slot0...slot7` または `[String]` スロットへ移行する方針にした。 |
| 2026-05-28 | Codex | Phase 0: App Group / CloudKit 基盤を本番構成へ移行。`Liminalog.entitlements` と Widget entitlements を追加し、App Groups (`group.app.YasudaRyuga.Liminalog`) と CloudKit (`iCloud.app.YasudaRyuga.Liminalog`) を Xcode Capability に設定。`LiminalogApp` は `SharedModelContainer.shared` を使う構成へ差し替え。 |
| 2026-05-28 | Codex | Phase 0: `SharedModelContainer` を Cloud 同期対象 (`Category` / `CategorySet` / `Chapter` / `PlanBlock` / `VisibilityPreset` / `UserSettings`) とローカル限定 `CalendarEventCache` の2設定に分離。CloudKit初期化に失敗した場合は local-only にフォールバックする。 |
| 2026-05-28 | Codex | Phase 0: `CategoryStore` / `CategorySetStore` / `PlanStore` / `ScoreStore` / `LiveActivityCoordinator` / `AppStores` を追加。`ChapterStore` は既存UI互換の façade として残し、カテゴリ・予定・スコア・LiveActivity処理を分割Storeへ委譲する段階移行にした。 |
| 2026-05-28 | Codex | Phase 0: `RootTabView` を `AppStores.bootstrap()` 経由に変更。既存ビューへは従来通り `ChapterStore` を environment 注入するため、UI側の大規模変更なしでStore分割を導入。 |
| 2026-05-28 | Codex | 検証: App Group / CloudKit entitlement 追加後、および Store 分割後に `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功。起動中の iPhone 17 Pro シミュレータへ install + launch も成功（pid: 62989）。 |
| 2026-05-28 | User/Codex | クラッシュ修正: `SharedModelContainer.shared` の Cloud/AppGroup 初期化失敗時に `assertionFailure` が Debug で即クラッシュしていた。`assertionFailure` をやめ、ログ出力後に local-only ModelContainer へフォールバックするよう変更。`xcodebuild` 成功、simulator install + launch 成功（pid: 63689）。 |
| 2026-05-28 | User/Codex | クラッシュ追加対応: local-only ModelContainer 作成失敗時に残っていた `fatalError` が Debug で `EXC_BREAKPOINT` になっていた。Cloud/AppGroup → local-only → in-memory の3段階フォールバックに変更し、起動不能よりも原因ログ取得とUI確認継続を優先する。local-only は `cloudKitDatabase: .none` を明示。 |
| 2026-05-28 | Codex | CloudKit互換追加対応: 起動ログで `Category.chapters` / `Category.plans` が非optional relationshipとして拒否されていたため optional 配列へ変更。CloudKit push 通知警告に対応するため App の `Info.plist` を `Config/LiminalogInfo.plist` として明示ファイル化し、`UIBackgroundModes = remote-notification` を追加。 |
| 2026-05-28 | User/Codex | UI細部修正: タイムラインの隣接エントリで境界時刻が重複表示されないよう、前行の終了分と同じ開始時刻は非表示化。`CurrentChapterCard` は `store.revision` を購読してカテゴリタップ直後に記録中表示へ切り替わるよう修正。カレンダー曜日ヘッダーを月グリッドから分離し、スクロールしても上部に固定される構成へ変更。 |
| 2026-05-28 | User/Codex | UI細部修正: タイムライン時刻をカード上下の補助表示ではなく境界ラベルとして再調整。連続するチャプター/未記録では次行の開始時刻を隠し、前行の終了時刻を境界の1表示として扱う。左レールは連続時に上下接続し、未記録は薄いレール、実績/予定はカテゴリ色レールでつながる見た目へ変更。日末の 0:00 は `24:00` 表示にする例外を追加。 |
| 2026-05-28 | User/Codex | UI細部修正: タイムライン日末の `24:00` 表示を撤去。時間幅を持たないカードUIでは終端だけ急に時間が飛ぶ印象が出るため、最後の終端ラベルは非表示にした。時刻テキストはレール端点の中心に合うよう絶対配置へ変更し、上下の丸印と視覚中心を揃えた。 |
| 2026-05-28 | User/Codex | UIデバッグ方針反映: タイムライン時刻位置をシミュレータスクショで確認しながら再調整。時刻/丸印/縦レールを行全体ではなくカード本体の上下端基準で同一座標に配置し、カード境界と時刻ラベルのズレを抑える構成に変更。以後UI調整は build だけでなく simulator screenshot 目視確認を基本フローに含める。 |
| 2026-05-28 | Codex | Git安全運用ルールを §3.6 に追加。`main` を安定版・復元ポイント、作業は `codex/*` / `claude/*` ブランチで進める方針、コミット/pushのタイミング、禁止操作、現在の復元ポイント `4b2c838` と remote を明記。 |
| 2026-05-28 | Codex | Phase 0 safe scope: `DayBoundary` を追加し、`ScoreCalculator` / `ChapterStore` の日付境界を 0:00-24:00 固定に寄せた。日付またぎはDB分割せず、表示・集計側でクリップする方針を崩さない。 |
| 2026-05-28 | Codex | Phase 0 safe scope: SwiftDataモデルのCloudKit互換下準備として全 `@Model` にデフォルト値/空initを追加し、`Chapter` / `PlanBlock` に `visibilityScope` / `updatedAt` 等を追加。`UserSettings` / `CalendarEventCache` / `VisibilityScope` / `VersionedSchema` 骨格も追加。 |
| 2026-05-28 | Codex | Phase 0 safe scope: `SeedCoordinator` を追加し、`UserSettings.settingsKey == default` と `VisibilityPreset.builtInKey` の重複統合を起動時に実行。DEBUG preview plan seed は `LiminalogSeedPreviewData` フラグなしでは実機DEBUGで走らないようゲート化。 |
| 2026-05-28 | Codex | Phase 0 safe scope: `SharedModelContainer` helper を追加。ただし `LiminalogApp.modelContainer` の本番差し替え、App Groups / CloudKit Capability 追加、Store分割、Package化は既存アーキテクチャへの影響が大きいため、ユーザー確認後に着手する。 |
| 2026-05-28 | Codex | Phase 0 safe scope: Swift標準 `Clock` との衝突を避けるため `LiminalogClock` / `SystemClock` / `TestClock` として実装し、`ChapterStore` と `ScoreCalculator.summary(now:)` に時刻注入を導入。 |
| 2026-05-28 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功。 |
| 2026-05-24 | Codex | Phase 1: SwiftDataモデル（Chapter/Category/CategorySet/PlanBlock）実装 |
| 2026-05-24 | Codex | Phase 1: チャプター記録ロジック（ChapterStore）・1分ルール・カテゴリCRUD実装 |
| 2026-05-24 | Codex | Phase 2: スコア計算ロジック（ScoreCalculator）・ストリーク計算実装（Phase 2先行） |
| 2026-05-24 | Codex | Phase 1: Live Activity対応（LiveActivityManager・WidgetBundle） |
| 2026-05-24 | Claude | Phase 1: ホーム画面・タイムライン・カテゴリグリッド・チャプター編集UI実装 |
| 2026-05-24 | Claude | Phase 1: カテゴリ設定画面・カテゴリセット管理UI実装 |
| 2026-05-24 | Claude | Phase 2: カレンダー画面（CalendarView・CalendarDayView）・PlanBlock表示実装（Phase 2先行） |
| 2026-05-24 | Claude | Phase 2: ダッシュボード基本版（スコアカード・カテゴリ別グラフ・24時間ヒートマップ）実装（Phase 2先行） |
| 2026-05-24 | Claude | AI_TASKS.md 作成（タスクボード初期セットアップ・Sonnet版） |
| 2026-05-24 | Claude | docs/ 設計ドキュメント6本作成（01〜06）— アーキテクチャ移行方針確定 |
| 2026-05-24 | Claude | AI_TASKS.md 全面改訂（Opus版）— 連携記事の知見を分担ルールに反映 + Phase 0 アーキ移行追加 |
| 2026-05-24 | User | 仕様変更: カテゴリグリッドを「使用頻度自動ソート」から「8スロット位置指定 + CategorySet スワイプ切替」へ。`Category.usageCount` 廃止 |
| 2026-05-24 | Claude | Phase 1: 上記仕様変更を実装。`CategorySet.slots: [UUID?]` 固定長8 化、`CategorySetEditSheet` を 4×2 位置指定グリッド + Menu ピッカーに再設計、`CategoryGrid` を 8 スロット固定描画 + `@AppStorage` で選択中セット永続化、`Category.usageCount` 削除、`CategorySettingsView` から使用回数表示削除 |
| 2026-05-24 | Claude | Phase 1: DEBUG ビルド用に `ChapterStore.seedDevSampleChaptersIfNeeded` 追加（今日+過去4日分の Chapter サンプル）。スキーマ変更で実機データが消えても再生成される |
| 2026-05-24 | Codex | docs/07-codex-plan-review.md 追加（01〜06 への計画レビュー・12項目の修正指示） |
| 2026-05-24 | User | UX修正依頼: CategorySetEditSheet で「先にセット名を入れないとグリッドに配置できないように見える」問題 |
| 2026-05-24 | Claude | Phase 1: CategorySetEditSheet を「グリッド優先 → セット名を下に配置」に並び替え、`@FocusState` + キーボード「完了」ボタン + `.scrollDismissesKeyboard(.interactively)` 追加 |
| 2026-05-24 | Claude | Phase 1: 公開設定UI最小版実装。タイムライン chapter contextMenu に「公開/非公開」トグル、CalendarDayView ツールバーに日単位の公開設定メニュー（全公開/全非公開/混在表示）、ChapterStore に `setChaptersVisibility(_:isPublic:)` ヘルパー追加 |
| 2026-05-24 | User | UX修正依頼: ①セット名を上に戻す ②タイムラインヘッダー固定+独立スクロール ③カレンダーから予定追加 ④日付英語表記の日本語化 ⑤月表示ラベル統一+テキスト最低幅確保 |
| 2026-05-24 | Claude | Phase 1 UX改善 (5項目): ①CategorySetEditSheet 名前を上段に戻す ②TimelineView に `selfScrolling` モード追加、HomeView は CurrentChapterCard+CategoryGrid を固定ヘッダー化しタイムラインのみ自動センタリングで独立スクロール ③PlanCreateSheet 新規作成・CalendarDayView "+" を Menu に変更・タイムラインタップで confirmationDialog（予定/チャプター選択） ④Date+Formatting に japaneseYear/MonthDay/MonthDayShortWeekday/ShortDateTime 追加、`shortTime` を ja_JP 24h 固定、RootTabView に `.environment(\\.locale, ja_JP)` で DatePicker 全体を日本語化、Dashboard と TimelineView の英語日付を置換 ⑤CalendarPlanLabel と CalendarEventLabel を同サイズ・同装飾に統一（border 削除）、`minimumScaleFactor(0.45)` + `allowsTightening(true)` でテキスト収まり改善 |
| 2026-05-24 | Codex | §10.5 進捗FB（7項目）追加: 古いPhase 0タスク残り / DEBUG seed隔離 / slots CloudKit互換 / docs/04整合 / canSave緩和 / 混在公開アイコン確認 / ビルド確認 |
| 2026-05-24 | Claude | Codex FB #1, #2, #5, #6 対応: ①§5.5 撤回タスクを `[-]` 化 + 文言修正 ②DEBUG seed を `UserDefaults.bool(forKey: "LiminalogSeedDevData")` ゲート化（Scheme 引数 `-LiminalogSeedDevData YES` で有効化）③CategorySetEditSheet の `canSave` を `assignedCount > 0` のみに緩和（空名は Store が自動命名）④混在公開アイコンを `eye.fill` + accentColor に変更（SF Symbols 互換性懸念回避）。FB #3, #4（CloudKit 互換検証・docs/04 整合）は §8.5 に Codex 担当タスクとして追記 |
| 2026-05-24 | User | UX変更依頼: タイムラインの独立スクロールはやめて、CategoryGrid をトグルで折りたためるようにして縦スペースを確保する |
| 2026-05-24 | Claude | Phase 1: HomeView を外側 ScrollView + ScrollViewReader に戻し（現在時刻に自動センタリング）、CategoryGrid を `@AppStorage("homeCategoryGridExpanded")` で折りたたみ可能に。トグルバー（Divider 兼任）にチェブロン + 「カテゴリを表示/隠す」ラベル。TimelineView の `selfScrolling` パラメータと内部 ScrollView 処理を削除（未使用化） |
| 2026-05-24 | User | UX微調整依頼: 「7/8」表示は不要、トグルはセット名の横にアイコンのみで配置（文字なしでスッキリ） |
| 2026-05-24 | Claude | Phase 1: CategoryGrid 内に headerBar を新設（セット名 + chevron トグルボタン、アイコンのみ）。`set.filledCount/8` 表示を削除。HomeView の `categoryToggleBar`（Divider+カプセルボタン）を撤去し、折りたたみ操作を CategoryGrid 自体に内包 |
| 2026-05-24 | User | UX微調整依頼: タイムラインの活動記録カードが白背景白カードで埋もれるので色を付けてほしい |
| 2026-05-24 | Claude | Phase 1: TimelineActualBlock の背景にカテゴリ色を淡く重ね（通常 opacity 0.15、記録中 0.22）、shadow もカテゴリ色に変更。記録中チャプターには pulse 付き `record.circle.fill` バッジを追加 |
| 2026-05-24 | User | UX修正依頼: ①同じカテゴリ再タップで記録が消えるバグ → 継続させたい ②切替時 stop 不要で自動終了 ③1分以内なら同カテゴリに戻したら継続（リザレクト）④違うカテゴリ間で 1 分以内なら誤タップとして削除（仕様書通り）|
| 2026-05-24 | Claude | Phase 1: `ChapterStore.startChapter` を全面書き換え（Codex の `closeActiveChapters` 抽象を活かしつつ）。同カテゴリ active は維持・他カテゴリ active は閉じる・直前終了が同カテゴリ + 1分未満ならリザレクト（endTime を nil に戻して active 化）・該当なしなら新規。`lastCompletedChapter` ヘルパー追加 |
| 2026-05-24 | User | 実機テスト後の UX 課題提起 (4件): ①カテゴリ切替で直前記録が消える ②短時間複数切替で視覚重なり ③1日終わりに現在地点が見えない ④予定/実績同時表示の UI/UX |
| 2026-05-24 | Claude | docs/08-timeline-redesign.md 作成。AskUserQuestion 経由で 4 課題への方針を確定: ①1分ルール仕様維持 ②視覚衝突検出+グループ化描画 ③Now フローティングボタン ④3タブ切替（予定/実績/両方）+ 両方モード洗練。AI_TASKS §8.6 に実装タスク 11 件を追加（旧 v1 案。2026-05-25 の v2 で撤回済み） |
| 2026-05-24 | Codex | §8.5 docs更新タスク実施: `03-architecture.md` を Bundle ID ベース ID / `groupContainer:` / 最小 Core → Widget 順 / SwiftData managed sync と CKShare 分離へ更新。`04-data-model.md` から `@Attribute(.unique)` 前提を削除し、`UserSettings`/`UnlockItem`/`VisibilityPreset` の論理キー重複統合、`photoLocalIdentifier` + `thumbnailData`、CloudKit 共有設計を Phase 3 検証タスクへ変更。`06-testing.md` に SeedCoordinator / ActiveChapterResolution / DashboardPeriodQuery / CategorySlotResolver テスト観点を追加 |
| 2026-05-24 | Codex | `ChapterStore` に active chapter 複数件収束ロジックを追加。カテゴリ切替時は `endTime == nil` の Chapter 全件を削除せず終了し、1分未満削除は明示停止 `endActiveChapter` に限定 |
| 2026-05-24 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功。最初の `iPhone 16` 指定は該当シミュレータがなく失敗したため、利用可能な `iPhone 17` で再実行 |
| 2026-05-24 | User | バグ報告: カテゴリ切替時に、記録中の記録が消えて新しい記録だけが始まってしまう |
| 2026-05-24 | Codex | バグ修正: `ChapterStore.startChapter` から短時間リザレクト/削除分岐を撤去。同じカテゴリ再タップは継続、別カテゴリ切替は前 active を 1分未満でも `endTime = now` で保存し、新カテゴリを開始する。カテゴリ切替経由では記録を削除しない。`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-24 | User | 再報告: まだカテゴリ切替時に記録が消える |
| 2026-05-24 | Codex | 追加対応: Claude向け仕様ログとテスト計画に残っていた「1分以内なら削除/リザレクト」記述を修正。今後の実装方針は「カテゴリ切替では削除しない」「明示停止だけ1分未満削除」に統一 |
| 2026-05-24 | User | 仕様 clarification: A→B では A の終了を記録して B 開始。A→B→C が 1分以内なら B だけ削除して C を記録。A→B→A が 1分以内なら B を削除し、A の終了を撤回して継続 |
| 2026-05-24 | Codex | `ChapterStore.startChapter` を clarification に合わせて再調整。いったん DB 上の時刻境界検出で実装したが、後続の追加修正で撤去済み |
| 2026-05-24 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-24 | User | 再報告: まだカテゴリ切替で直前記録が消える |
| 2026-05-24 | Codex | 追加修正: DB上の `endTime == startTime` 境界検索は過去データや連続操作を拾いすぎるため撤去。`ChapterStore` 内に直前切替の `SwitchContext` を保持し、その context の active だけを1分以内補正対象に限定。通常の A→B は必ず A を終了保存して B を開始する |
| 2026-05-24 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-24 | User | 再報告: まだ消える |
| 2026-05-24 | Codex | 追加調査・修正: データ削除ではなく TimelineView が分単位丸め + 最小高さ 18pt で短い連続 Chapter を同じ Y 座標に重ね、新しい記録が前の記録を覆って「消えた」ように見える可能性を確認。TimelineView を秒精度配置に変更し、Chapter ブロック同士が重なる場合は下へずらす `TimelineChapterPlacement` を追加 |
| 2026-05-24 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-24 | User | 追加報告: 長く続けた記録のあとでも直前の記録が見えなくなる |
| 2026-05-24 | Codex | 追加修正: 長時間 Chapter はラベルが開始位置にしかなく、HomeView が現在時刻へスクロールすると終了位置付近ではカテゴリ名が画面外になる。非activeかつ高さ72pt以上の Chapter に終了位置側の bottom label（カテゴリ名 + 時刻）を追加し、直前までの活動が現在時刻付近でも見えるようにした |
| 2026-05-24 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-24 | User | 表示改善方針決定: カレンダー系アプリのように、同じ時間帯に複数ブロックがある場合は左右に分けて重ならないようにしたい。予定は既に横分割レーンなので、予定・実績それぞれの扱いを相談 |
| 2026-05-24 | Codex | TimelineView を「予定レーン」「実績レーン」別々の横カラム分割へ変更。実績同士は左側レーン内で、予定同士は右側レーン内で、表示上の `yOffset + height` が重なるグループごとにカラム割当。下方向にずらす応急処置は廃止し、`TimelineChapterPlacement` / `TimelinePlanPlacement` に `column` と `columnCount` を追加 |
| 2026-05-24 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-24 | User | 追加要望: 予定と実績をUIで見分けやすくしたい。カテゴリ切替で消える問題もまだ未解決 |
| 2026-05-24 | Codex | 追加修正: `ChapterStore.startChapter` からカテゴリ切替時の削除/リザレクト補正を完全撤去。カテゴリ切替では active を `endTime = now` で閉じて新規開始するだけにし、`modelContext.delete(active)` は明示停止 `endActiveChapter` の1分未満削除に限定 |
| 2026-05-24 | Codex | UI改善: TimelineView の予定レーン背景を淡く分離し、予定ブロックはカレンダーアイコン + 点線枠 + 右アクセント、実績ブロックは check/record アイコン + 塗りカード + 左アクセントに変更。予定と実績の視覚言語を分離 |
| 2026-05-24 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-24 | User | 方針確定: 一旦実装から離れてタイムライン仕様を練る。記録タブで「実績」「予定」「左右分割の比較」を切り替えられるようにする。他は「記録は消さない」「短時間切替は表示でまとめる」「現在時刻周辺を優先」「予定と実績は別レーン・別ビジュアル」で概ね確定（旧 v1 方針。2026-05-25 の v2 で撤回済み） |
| 2026-05-24 | Codex | docs/08-timeline-redesign.md を v1 仕様として全面更新。旧「1分未満は削除維持」方針を撤回し、カテゴリ切替では Chapter を削除しない、実績/予定/比較の表示モード、短時間切替グループ、現在時刻周辺表示、予定/実績の視覚言語分離をClaude向けに明文化（旧 v1 方針。2026-05-25 の v2 で撤回済み） |
| 2026-05-24 | Codex | TimelineView に `TimelineDisplayMode`（実績 / 予定 / 比較）と `@AppStorage("timelineDisplayMode")` を追加。実績モードは Chapter のみ全幅、予定モードは PlanBlock のみ全幅、比較モードは左: 実績 / 右: 予定の左右分割として表示（後続の v2 実装で撤去済み） |
| 2026-05-24 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | タイムライン周りを大改修する方針を提示。縦方向タイムラインを廃止し、24時間バーで正確な時間幅を俯瞰、固定高さカードリストで予定/実績をタブ切替表示する仕様へ変更 |
| 2026-05-25 | Codex | docs/08-timeline-redesign.md を v2 として全面更新。旧「実績/比較/予定 + 左右分割タイムライン」方針を撤回し、24時間バー、予定/実績タブ、固定高さカード、空白カード、バーとカードの連動、表示モデル分離、実装優先順位をClaude向けに再設計 |
| 2026-05-25 | Codex | AI_TASKS §8.6 を新仕様の実装タスクへ差し替え。`TimelineEntry` 導入、`DayOverviewBar`、固定高さ `TimelineEntryCard`、`TimelineGapCard`、scrollTo 連動、旧タイムライン撤去をタスク化（scrollTo は後続修正で撤去済み） |
| 2026-05-25 | Codex | TimelineView を新仕様へ実装変更。旧縦タイムライン/左右分割/比較モードを撤去し、`TimelineTab`（予定/実績）、`@AppStorage("timelineSelectedTab")`、24時間バー、固定高さカード、空白カード、バータップ quick detail + scrollTo + ハイライトを追加（scrollTo は後続修正で撤去済み） |
| 2026-05-25 | Codex | HomeView / CalendarDayView から予定追加 callback を TimelineView へ接続。予定タブの空白カード・予定バー空白タップは `PlanCreateSheet`、実績側は既存の `ChapterCreateSheet` / 追加メニューへ遷移（後続修正でタイムラインからの追加導線は撤去済み） |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | ホーム画面では予定/実績タブの順番が逆の方がよさそうと指摘。予定のダミーデータも24時間の隙間がない状態にしたいと依頼 |
| 2026-05-25 | Codex | TimelineTab の表示順を実績→予定へ変更。`seedPreviewPlansIfNeeded` と PreviewSupport の今日の予定 seed を 0:00-24:00 まで途切れない予定に更新 |
| 2026-05-25 | User | 再報告: 予定のダミーデータがうまく動いていない |
| 2026-05-25 | Codex | `seedPreviewPlansIfNeeded` を修正。seed version だけで return せず、今日の予定が 0:00-24:00 を実際に覆っているか検査し、不完全なら今日分の予定だけ 24時間 seed に差し替える。起動引数も `-LiminalogSeedDevData YES` と `-LiminalogSeedDevData` 単独の両方に対応 |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | 再報告: まだダミーデータが表示されない |
| 2026-05-25 | Codex | RootTabView の DEBUG 起動時に `seedPreviewPlansIfNeeded` を常時呼ぶよう変更。Chapter の大量サンプルだけ起動引数ゲートを維持。既存予定が旧ダミーなら24時間 seed に差し替え、ユーザー作成予定が混じる場合は削除せず空白だけ `予定調整` で補完するよう修正 |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | 24時間は埋まったが、予定ダミーに色々なカテゴリを使ってほしいと依頼 |
| 2026-05-25 | Codex | preview plan seed version を 4 に更新。旧 `予定調整` で埋まった seed は差し替え対象にし、ユーザー予定を残して空白補完する場合も標準予定テンプレートをクリップ挿入して、睡眠/移動/勉強/仕事/休憩/趣味など複数カテゴリが出るよう修正 |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | タイムラインを押してチャプター/予定を追加できる機能は不要と方針変更 |
| 2026-05-25 | Codex | TimelineView からバー空白タップ・空白カードタップによる追加導線を撤去。HomeView / CalendarDayView の TimelineView 呼び出しから追加 callback を削除し、CalendarDayView の旧 confirmationDialog も撤去。追加は既存の画面上部 `+` やカテゴリ記録導線に集約 |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | 24時間バーはカテゴリごとに角丸にせず、長い長方形の中で色の境目だけ見えればよいと方針変更 |
| 2026-05-25 | Codex | `TimelineBarSegmentView` のカテゴリセグメントを `Rectangle` に変更し、個別セグメントの角丸を撤去。バー全体のみ `clipShape(RoundedRectangle(cornerRadius: 6))` で外枠を整え、内部境界は直線の色切替になるよう修正 |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | 実際の記録UIがごちゃついているためミニマル化、開始/終了時刻はカード左外へ移動、`実績`/`記録中`/`継続` 文字表示を削減、予定通りカテゴリで記録中かは分かるようにしたいと依頼。記録もカテゴリ切替時に即時反映されず、前の記録が消える問題があるため、設計段階から正確性優先で見直したいと依頼 |
| 2026-05-25 | Codex | TimelineView を実績カード左外の時刻レール + ミニマルカードへ変更。カード内の `実績`/`記録中`/`継続` バッジを撤去し、記録中は枠・背景・時刻レールでハイライト。Chapter と同カテゴリの PlanBlock が時間重複する場合に `予定通り` を表示する `plannedMatchTitle` を表示モデルへ追加 |
| 2026-05-25 | Codex | 記録設計を正確性優先へ寄せ、`ChapterStore.endActiveChapter` の1分未満自動削除を撤去。カテゴリ切替・手動停止のどちらでも短時間 Chapter を削除/結合せず、`endTime = now` で閉じて履歴を残す方針へ統一 |
| 2026-05-25 | Codex | TimelineView の30秒タイマーを1秒更新へ変更し、`displayedRevision` による `.id(...)` 再生成を撤去。`store.revision` 変更時に即時再フェッチし、アクティブ記録の表示は `now` 更新で追従する設計に変更 |
| 2026-05-25 | Codex | 1分未満の Chapter 表示は `1分` に丸めず `1分未満` と表示するよう変更。短時間記録を残す方針と表示の正確性を合わせた |
| 2026-05-25 | Codex | docs/08-timeline-redesign.md に今回のUI/記録仕様を反映。空白タップ追加なし、カード左外時刻レール、記録中はハイライト、短時間記録は削除しない、予定通り表示を明記 |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | まだカテゴリ切替時に直前の記録が消えると報告 |
| 2026-05-25 | Codex | TimelineView のデータ取得を `ChapterStore.chapters(on:)` + `store.revision` 手動同期から SwiftData `@Query` に変更。`Chapter` / `PlanBlock` を日付範囲 predicate で直接追跡し、カテゴリ切替で閉じた直前 Chapter が保存後に表示から落ちる経路を潰した。表示モデル変換は維持 |
| 2026-05-25 | Codex | docs/08-timeline-redesign.md に TimelineView は `@Query` をデータソースにする方針を追記 |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | 記録中のものすら表示されなくなった。カテゴリボタン押下で開始、別カテゴリ押下で直前終了 + 新規開始のはずなのに、なぜ直前カテゴリのデータが消えるのか確認 |
| 2026-05-25 | Codex | 原因候補をデータ削除ではなく表示取得の取りこぼしと判断。`startChapter` に削除処理はなく、`Chapter.endTime` の optional 複合 predicate が SwiftData fetch で記録中/終了直後 Chapter を落としていた可能性が高い。TimelineView の `@Query` から日付範囲 predicate を外し、全 Chapter を追跡して Swift 側で `startTime < dayEnd && (endTime ?? now) > dayStart` によりフィルタするよう変更 |
| 2026-05-25 | Codex | `ChapterStore.chapters(on:)` / `chapters(from:to:)` も同様に optional `endTime` 判定を predicate から外し、`startTime < end` で取得後 Swift 側で `endTime ?? .distantFuture` により日付交差判定するよう修正 |
| 2026-05-25 | Codex | docs/08-timeline-redesign.md に、optional `endTime` を含む日付交差判定を `#Predicate` に直接書かない方針と理由を追記 |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | カード左外に開始/終了時刻があるため、カード内に時間の幅/経過時間を表示しなくてよい。カード縦幅を短くし、`予定通り` インジケータをカテゴリ名の横に置いてスタイリッシュにしたいと依頼 |
| 2026-05-25 | Codex | TimelineEntryCard から右側の経過時間表示と、補助行 fallback の時刻範囲表示を撤去。`予定通り` はカテゴリ名横の小さな `TimelineMatchIndicator` ピルに変更。カード高を 76 -> 62、空白カード高を 60 -> 48 に圧縮 |
| 2026-05-25 | Codex | docs/08-timeline-redesign.md に、カード内はカテゴリ名・状態インジケータ・補助情報へ絞り、経過時間は quick detail / 詳細画面で確認する方針を追記 |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User | カード右側にそのカテゴリを何分やったかは表示したい。タイムライン内部スクロールで二重スクロールになっているため、タイムライン側のスクロールは不要と依頼 |
| 2026-05-25 | Codex | TimelineEntryCard 右側に `durationText` を再配置し、開始/終了時刻は左外レール、経過時間は右側という役割分担に変更。TimelineEntryList から内部 `ScrollView` / `ScrollViewReader` / 固定高さを撤去し、ホーム画面全体の ScrollView に統合 |
| 2026-05-25 | Codex | docs/08-timeline-redesign.md を更新し、カード右側に経過時間を表示、カード内に時刻範囲は重複表示しない方針を明記 |
| 2026-05-25 | User | 24時間バーとタイムラインは別物に感じるため、`今日のタイムライン` ラベルをタブ上に移し、24時間バーとラベル位置を入れ替えたい。日付も目立たないためホームと同列くらいに強めたいと依頼 |
| 2026-05-25 | Codex | TimelineView の表示順を 24時間バー -> quick detail -> 日付つき `今日のタイムライン` 見出し -> 実績/予定タブ -> カードリストへ変更。日付は calendar アイコン付き headline に上げ、見出しと同じ行で表示 |
| 2026-05-25 | Codex | docs/08-timeline-redesign.md の画面構成を更新。24時間バーはタイムライン見出しではなく1日の俯瞰UIとして独立、カードリストはホーム画面全体のスクロールに統合する方針を明記 |
| 2026-05-25 | Codex | 検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-25 | User/Claude | 指摘: タイムラインのタブ構成が実装済み 2 タブ仕様なのに、旧ログに 3 タブで作る記述が残っていて混乱する |
| 2026-05-25 | Codex | docs/08-timeline-redesign.md と AI_TASKS §8.6 を整理。現行タブは `実績 / 予定` の 2 タブのみ、旧 `実績 / 比較 / 予定` と `予定 / 実績 / 両方` は v1 履歴で撤回済み、比較は 24時間バー 2 段で行うと明記。併せて旧 `scrollTo` と空白タップ追加導線も撤回済みに更新 |
| 2026-05-26 | User | スコア計算の観点から 1 分未満の完了チャプターが残るのは問題と判断。前日以前のノイズ自動削除とスコア除外を実装するよう依頼 |
| 2026-05-26 | Claude | `ScoreCalculator.summary` に完了済み 1 分未満 Chapter をスコア対象外にするフィルタを追加（`endTime != nil && duration < 60` は除外）。記録中 Chapter（`endTime == nil`）は常に対象 |
| 2026-05-26 | Claude | `ChapterStore.pruneShortChapters()` を追加。前日以前の完了済み 1 分未満 Chapter を起動時に一括削除。当日分は除外し手動削除に委ねる |
| 2026-05-26 | Claude | `RootTabView.task` 内で起動時に `pruneShortChapters()` を呼ぶよう変更 |
| 2026-05-26 | User | 仕様変更: タイムラインの未記録/未予定カードをタップして記録・予定を追加できるようにしたい |
| 2026-05-26 | Claude | `TimelineGapCard` をタップ可能に変更。`TimelineView` に `showingChapterCreate` / `showingPlanCreate` / `gapStartDate` state を追加し、`handleGapTap` でタブに応じてシートを振り分け。`TimelineEntryList` に `onGapTap` パラメータを追加し空白カードを Button でラップ。右端に `plus.circle` アイコンを追加。docs/08 §5 空白カードの仕様を更新 |
| 2026-05-26 | User | 日付表示をタイムラインの見出し横から、ナビゲーションバー直下（ダイナミックアイランド直下）中央に移動したい |
| 2026-05-26 | Claude | `TimelineView.timelineHeader` から日付ラベルを削除（タイトルのみ残す）。`HomeView` の ScrollView に `.safeAreaInset(edge: .top)` で日付 Text を固定表示。スクロールに関係なくナビゲーションバー直下に常時表示される |
| 2026-05-26 | Claude | docs/08-timeline-redesign.md を更新。空白カードのタップ仕様・1分未満ガベージコレクション仕様・スコア除外ルール・§11 の注意事項を最新状態に更新 |
| 2026-05-26 | User | ホーム上部の日付が下に寄り、`ホーム` ラベルが隠れると報告 |
| 2026-05-26 | Codex | `HomeView` の `.safeAreaInset(edge: .top)` 日付表示と旧タイムライン用の `ScrollViewReader.scrollTo(currentTimeMarkerID)` 自動スクロールを撤去。日付は `ToolbarItem(placement: .principal)` に移し、ナビゲーションタイトル `ホーム` と重ならない構成に変更。docs/08 の画面構成も更新 |
| 2026-05-26 | User | ホームタブは今日に関することだけを扱う場所なので、タブ名を `Today` にしたいと依頼 |
| 2026-05-26 | Codex | UI構成は維持し、`RootTabView` の先頭タブ表示名のみ `ホーム` から `Today` に変更。`HomeView` のナビゲーションタイトルは現状維持 |
| 2026-05-26 | User | タブ名は英語 `Today` ではなく日本語 `今日` にし、アイコンも時計マーク系にしたいと依頼 |
| 2026-05-26 | Codex | `RootTabView` の先頭タブを `今日` / `clock.fill` に変更。画面上部の UI 構成は維持 |
| 2026-05-26 | User | 日付切り替わり仕様を確定。コア機能の根幹が揺らぐため、1日の範囲は基本 0:00-24:00 固定。可変の1日始まり時間は数年単位の大型アップデートで再検討する超低優先度に下げる |
| 2026-05-26 | Codex | docs/03/04/05/06/08 と liminalog_spec_v04、AI_TASKS を更新。`dayStartHour` / 1日の始まり Picker / 可変 DayBoundary 前提を撤回し、0:00-24:00 固定の DayBoundary と日付またぎクリップ仕様に統一 |
| 2026-05-26 | User | 日付またぎチャプターと重複チャプターの仕様を確定。日付またぎは許可してDB分割しない。実績 Chapter 同士の重複は原則禁止する |
| 2026-05-26 | Codex | docs/08、docs/06、liminalog_spec_v04、AI_TASKS を更新。日付またぎは表示・スコア・バーだけ 0:00-24:00 にクリップ、手動追加・編集で既存実績と重なる場合は保存前に警告してブロックする方針を明記 |
| 2026-05-26 | User | カレンダータブの方針を確定。月表示はスコアと重要な予定だけ、重要予定をためて近くなったら日別タイムラインで24時間予定へ落とし込む。外部カレンダーは将来、終日/時間未指定→重要予定、時間指定→時間つき予定へ変換する |
| 2026-05-26 | Codex | カレンダー計画ハブ実装。`CalendarView` をスコアバッジ + 重要予定のみの月表示へ変更、複数日重要予定の連続表示、`CalendarDayView` の重要予定エリア、`PlanCreateSheet` の編集/複数日重要予定対応、Timeline の予定編集、未来日に active Chapter が出る問題の修正を実施。`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-26 | Codex | カレンダー/予定作成UI改善。日別スコアを大型カード化し、`PlanCreateSheet` のカテゴリ選択を CategorySet 別の色付きグリッドモーダルへ変更。予定カテゴリが増えても休日/特殊予定などのセットから選べる方針に寄せた。`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功 |
| 2026-05-26 | User | 方針変更: カレンダーからチャプターを記録できる必要はない。重要な予定は、時間未指定予定だけでなくタイムラインに入れる時間つき予定にも設定でき、時間が決まっている重要予定はカレンダーでも開始時間が見えるようにしたい |
| 2026-05-26 | Codex | `PlanBlock.isImportant` を追加して `isAllDay` と分離。`PlanCreateSheet` に「重要な予定としてカレンダーに表示」トグルを追加し、時間つき重要予定は月カレンダー/日別重要予定エリアで開始時刻付き表示に変更。`CalendarDayView` からチャプター新規作成導線を撤去し、`TimelineView(allowsChapterCreation: false)` でカレンダー経由の記録作成を止めた |
| 2026-05-26 | User | スコア公平性の方針確認: 前日までに組んだ予定と当日の実績でスコアを見るため、今日以前の予定や前日以前の実績時間は自由に変更できないようにしたい。メモ/振り返りは後から編集可。実績時間を後から修正するなら変更履歴が見える必要がある |
| 2026-05-26 | Codex | 編集ロック実装。予定は明日以降のみ新規追加・内容/カテゴリ/時間/重要フラグ変更・削除可、今日以前はメモ/公開設定のみ可。実績は当日中のみ時間/カテゴリ/削除可、前日以前はメモ/気分/場所/公開設定のみ可。`ChapterStore` 側にも保存/削除ガードを追加し、UIだけでなくデータ層でも公平性を守る |
| 2026-05-26 | User | 日付をまたいで未来まで続く重要予定は、開始日が過ぎていると変更できないのが不便。時間未指定の重要予定はスコアに影響しないため、後から追加/削除できるようにしたい |
| 2026-05-26 | Codex | 時間未指定の重要予定 (`isAllDay == true`) を編集ロックの例外に変更。過去日・今日・複数日またぎでも追加/編集/削除可能。時間つき予定はスコア対象なので従来通り今日以前はロックし、時間未指定予定を時間つきへ変換する場合も明日以降の日付でないと保存できない |
| 2026-05-26 | User | 上記に伴い、時間指定の予定についても重要かどうかは後から切り替えられるようにしたい |
| 2026-05-26 | Codex | 今日以前の時間つき予定でも `isImportant` の切替を許可。時間/カテゴリ/内容はスコア公平性のため固定したまま、重要フラグは月カレンダーへの表示制御だけなので編集可能にした |
| 2026-05-26 | User | プロフィール画面の方針確定。インスタ・X・BeReal的なSNSプロフィールに倣う。統計タブと役割を分け、プロフィールは「分析」ではなく「自己表現」の場とする。設定系は右上 ☰ に隔離。各要素は独立した意図を持つ（重複なし）。UI は実装側が柔軟に最適化 |
| 2026-05-26 | Claude | docs/09-profile-design.md を新規作成。プロフィール情報設計を規範化し、UIは実装裁量に委ねる方針を明記。MVP 構成: プロフィール画像 + ニックネーム + bio + 主要スタッツ(🔥連続/⏱累計/👥友達数) + 解放コレクション + 日記カードグリッド。月アート・365日マップ・テーマカラーは Phase 2 以降の検討候補として §5 に保留。README.md と AI_TASKS の docs 一覧・§6.4 タスクも更新 |
| 2026-05-26 | User | プロフィール画像の解釈確認: キャラクター/イラスト的なアバターではなく、Instagram/X 同様の単純なプロフィール画像（ユーザーが選ぶ写真）を想定 |
| 2026-05-26 | Claude | docs/09 と AI_TASKS の「アバター」表記を「プロフィール画像」へ統一。未設定時はニックネーム頭文字フォールバック、Memoji等のキャラクターアバターは前提としない旨を docs/09 §3.1 に追記 |
| 2026-05-28 | Codex | 今日のタイムラインに表示される実績が、開始日が前日以前という理由で編集ロックされる問題を修正。`ChapterStore.isChapterTimeLocked` を「開始日 < 今日」判定から「今日 0:00-24:00 に重なっていない実績だけロック」へ変更し、DBを日付分割しない日付またぎ Chapter でも今日に重なる間は時間/カテゴリ/削除を編集可能にした。docs/08 の編集ロック仕様にも同ルールを追記 |
| 2026-05-28 | Codex | 今日の未記録カードから `ChapterCreateSheet` を開いた際、ギャップが現在時刻に接していると開始=終了になり保存不可/ロックに見える問題を修正。未記録ギャップの実績追加は保存可能な開始時刻へ補正し、上部 `+` からの手動追加も初期値を「現在までの直近30分」に変更。追加シートの常時ロック文言をやめ、保存不可理由だけ警告表示するようにした。docs/08 の空白カード仕様にも補正ルールを追記 |
| 2026-05-28 | Codex | Phase 1 Widget を実装。`RecordingGridWidget` を追加し、Small は4枠・Medium は8枠で選択中 CategorySet のスロットを表示。`StartChapterIntent` からアプリを開かず記録開始/カテゴリ切替ができるようにし、Widget 側は App Group の SwiftData store を最小モデルで読む。既存 `LiminalogStatusWidget` は Bundle から外し、Widget は記録開始のための実用UIへ置き換え |
| 2026-05-28 | Codex | CategorySet 操作の残タスクを実装。`CategorySettingsView` でセット並び替え、`CategorySetEditSheet` でスロット同士のドラッグ&ドロップ交換、Home の空きスロット tap から該当セット編集を開く導線を追加。選択中 CategorySet は `@AppStorage` に加えて `UserSettings.enabledCategorySetID` にも保存し、Widget の初期表示と同期する |
| 2026-05-28 | Codex | Profile/Settings の Phase 1 最小再設計を実装。`ProfileView` からスコア・カテゴリ管理など分析/設定要素を外し、プロフィール画像フォールバック、ニックネーム、bio、連続日数、累計記録時間、友達数の自己表現画面へ変更。右上 ☰ から `SettingsView` を開き、カテゴリ管理・カレンダー表示・公開系プレースホルダー・アプリ情報へ隔離。解放コレクションと日記カードは UI 枠のみ実装し、実データ接続はアンロック/DayDigest 実装後に行う |
| 2026-05-28 | Codex | Widget / Dynamic Island の見切れとカテゴリ操作の重さに対応。`RecordingGridWidget` は systemSmall 用に余白・アイコン・文字サイズ・セル高さを圧縮し、Dynamic Island expanded 下段には最大4カテゴリの `StartChapterIntent` ボタンを表示してアプリを開かず切替可能にした。`CategoryGrid` は `@Query` のカテゴリ/セットを直接使ってスワイプ中の再fetchを避け、セット選択保存時の Widget reload を抑制。`CategorySettingsView` もカテゴリセット行のカテゴリ解決を Store fetch ではなく既存 `@Query` から行うようにした |
| 2026-05-28 | Codex | Widget/Live Activity の追従仕様を調整。`RecordingGridWidget` は個別設定で固定する方式をやめ、`UserSettings.enabledCategorySetID` の「現在選択中テーブル」を常に表示する Static Widget に変更。テーブル切替時は全Widgetではなく `RecordingGridWidget` の timeline だけを reload する。Widget の `StartChapterIntent` から記録を開始した場合も Widget extension 側で Live Activity を request/update し、アプリ起動時にも active chapter から Live Activity を同期する。カテゴリセット並び替え/スロット編集の説明テキストはUIから削除 |
| 2026-05-28 | Codex | Widget の角丸見切れ対策と Dynamic Island 更新を追加。`RecordingGridWidget` は Medium で8枠が収まるようにセル高・余白・アイコンサイズを再調整し、Large family も追加して8枠を余裕表示できるようにした。Live Activity 更新は最初の1件だけでなく存在する全 Activity に最新 state を流す形にして、Dynamic Island 内ボタン押下後に現在ステータスが押したカテゴリへ更新されやすいようにした |
| 2026-05-28 | Codex | 直前修正の認識違いを補正。見切れ対象は Widget ではなく Dynamic Island だったため、`RecordingGridWidget` のサイズ/large family 変更は元の Small/Medium 構成へ戻した。Dynamic Island は expanded 下段のカテゴリ操作を文字付きカプセルからアイコン円形ボタンへ変更し、compact 表示もアイコン/タイマー幅を縮めて左右の角丸に干渉しにくくした。Live Activity の `ContentState` に `updatedAt` を追加し、Widget/Dynamic Island の AppIntent 押下ごとに別 state として ActivityKit へ流れるようにしてリアルタイム反映を強めた |
| 2026-05-28 | Codex | Dynamic Island の再修正。前回の円形ボタンは収まりが悪かったため、expanded 下段は文字付きカプセル型ボタンへ戻しつつ `LazyVGrid` 4列×2段で現在テーブル8枠を表示する構成へ変更。現在アクティビティのアイコン/継続時間は左右角で見切れやすい leading/trailing から center region にまとめ、compact 表示はさらに小さいアイコン/タイマー幅に調整。`StartChapterIntent` は `LiveActivityIntent` にも適合させ、Dynamic Island 内ボタン押下時に app process 経由で実行されやすい形へ寄せた。Live Activity 更新ログも DEBUG に追加 |
| 2026-05-28 | Codex | Dynamic Island ボタン更新経路の補強。`Liminalog/Intents/StartChapterIntent.swift` を追加し、Widget extension 側だけでなくアプリ本体側にも同名の `StartChapterIntent: LiveActivityIntent` を認識させる構成にした。Dynamic Island のボタン押下時にアプリを開かず app process でカテゴリ切替・SwiftData保存・Live Activity更新を実行できるようにする狙い。Widget側のIntentはホームWidget用に残す |
| 2026-05-28 | Codex | Widget / Dynamic Island の反映遅延を短縮。カテゴリ切替Intentでは Live Activity の state 更新を SwiftData save より先に行う楽観更新へ変更し、表示だけ先に切り替わるようにした。Widget extension 側は `ModelContainer` を static cache 化し、毎タップのコンテナ生成コストを削減。Widget 内 AppIntent では `reloadAllTimelines()` を削除し、Intent完了後にWidgetKitが行う即時reloadへ任せる。Dynamic Island 側のアプリIntentでは保存後に `RecordingGridWidget` のみ reload してホームWidgetとの整合を保つ |
| 2026-05-28 | Codex | Widget と Dynamic Island の即時性/信頼性を再調整。楽観更新は実体保存前の表示先行になり得るため撤回し、`StartChapterIntent` は SwiftData save 成功後に `RecordingGridWidget` の timeline reload と Live Activity update を行う順序へ変更。Widget 側 AppIntent でも `reloadTimelines(ofKind:)` を復活させ、全Widget reloadではなく記録グリッドだけを即時再読込する。表示の正は保存済みChapterに寄せ、保存失敗時にWidget/Islandだけ切り替わる状態を避ける |
| 2026-05-28 | Codex | Widget 自身の反映遅延をさらに改善。Widget 内 `StartChapterIntent` は保存後すぐ `RecordingGridWidget` の timeline reload を要求してIntentを完了できるようにし、Live Activity への publish は保存済みデータから作った state を後続 `Task` で送る構成へ変更。これにより Widget の再描画を ActivityKit update の待ち時間から切り離しつつ、表示内容は保存済みChapter由来に保つ |
| 2026-05-28 | Codex | Widget タップ時の処理を追加軽量化。カテゴリ取得は対象IDの `fetchLimit = 1`、active Chapter 取得は `endTime == nil` のpredicate付きfetchへ変更し、Widget entry側も全Chapter取得後filterをやめてactive 1件だけ読むようにした。Live Activity用state生成のカテゴリ/セット再fetchもWidget reload前から外し、保存後の後続Taskで保存済みstoreから再読込する |
| 2026-05-28 | Codex | Widget active表示の即時性改善として App Group `UserDefaults` に保存成功後の `activeCategoryID` キャッシュを追加。Widget は active表示だけこの軽量キャッシュを優先して読み、SwiftData active fetch はキャッシュ欠落/不正時のfallbackにした。Widget内Intent、Dynamic Island用アプリIntent、アプリ本体の `ChapterStore.start/end/save/delete` でキャッシュを更新/クリアし、表示だけ未保存先行にならないよう「SwiftData保存成功後にキャッシュ更新」の順序を維持 |
| 2026-05-28 | Codex | Widget→Widget の反映だけ約3秒遅い原因候補を切り分け。Dynamic Island はアプリ本体側Intent/ActivityKit更新で即時pushされる一方、ホームWidgetはWidget extension内Intentが App Group `UserDefaults` に書いた値を別WidgetKit描画プロセスが再読込するため、defaultsの非同期flush待ちが発生し得る。保存成功後キャッシュ更新時に `defaults.synchronize()` を追加し、timeline reload前に軽量active cacheを共有コンテナへ明示反映させる |
| 2026-05-28 | Codex | Widget→Widget の3秒待ちはflush後も残るため、原因をWidgetKit Buttonのtimeline更新待ちと判断。Dynamic IslandはActivityKitのlive state更新、ホームWidgetはsnapshot/timeline再提示なので原理的に更新経路が違う。`RecordingGridWidget` のカテゴリグリッドへ `invalidatableContent()` を追加し、タップ後から新timeline提示まで古いactive表示をそのまま信じさせず、更新待ちコンテンツとして扱わせる |
| 2026-05-28 | Codex | Widget のカテゴリセルを `Button(intent:)` から `Toggle(isOn:intent:)` + custom `ToggleStyle` へ変更。WidgetKit の楽観的な一時状態を使って、タップしたカテゴリを即時に仮active表示し、保存済みactiveと一時状態が食い違う間は右上に小さな同期中バッジを表示する。SwiftData保存後のtimeline更新で一致すればバッジが消えて本反映、不一致なら保存済みactive表示へ戻る設計 |
| 2026-05-28 | Codex | Widget仮反映中のチカチカを抑制。楽観表示用Toggleと `invalidatableContent()` の併用で更新待ち中の無効化表示が目立つため、カテゴリグリッドの `invalidatableContent()` を削除。同期中バッジも回転矢印アイコンから静かなオレンジ点に変更し、仮反映は伝えるが警告/点滅の印象を弱めた |
| 2026-05-28 | Codex | Widget同期待ち中の二重ハイライトを修正。各Toggleセルが独立した仮状態を持つと、変更前カテゴリは保存済みactive、新カテゴリは仮activeとして同時に強調されるため、`RecordingGridView` にグリッド全体の `optimisticCategoryID` を持たせた。仮選択がある間はそのカテゴリだけをactive表示し、保存済みactiveに追いついたら同期点だけ消える方針 |
| 2026-05-28 | Codex | 上記 `@State optimisticCategoryID` はWidgetKitの即時楽観描画に乗らず、Widget→Widget が再びtimeline更新待ちになったため撤回。`Toggle` の `configuration.isOn` による即時表示を復活させ、仮選択カテゴリは App Group `UserDefaults` の `recording.pendingCategoryID` でグリッド全体に共有する構成へ変更。仮選択中は旧activeを抑制し、保存済み `recording.activeCategoryID` に追いつくと同期点だけ消える |
| 2026-05-28 | Codex | Widget の新旧カテゴリ二重表示が残ったため、pending共有をBinding任せから明示flushへ補強。タップ時に `RecordingWidgetStore.cachePendingCategoryID(_:)` で App Group `UserDefaults` へ直接 `recording.pendingCategoryID` を書き込み `synchronize()` する。狙いは、押したToggleセルだけでなく親/他セルが同じpendingカテゴリを読み、旧activeを即時に抑制すること |
| 2026-05-28 | Codex | WidgetKitの複数Toggleでは旧activeセルを同時に消すのが難しいため、現時点では新旧二重表示を許容して即時性を優先する判断に戻した。嫌だった保存済みcurrentの控えめ表示案は撤回。あわせて `RecordingGridWidget` のテーブル名を上端から離し、カテゴリボタンとの間隔を詰めた。Dynamic Island compact leading のカテゴリアイコンは 12pt→15pt に拡大 |
| 2026-05-28 | Codex | Dynamic Island がアプリ内の現在テーブルを参照できていない問題を修正。`setEnabledCategorySetID` は `UserSettings.enabledCategorySetID` 保存と `RecordingGridWidget` reload だけで Live Activity state を更新していなかったため、保存成功後に `updateLiveActivity()` を呼ぶようにした。カテゴリ/カテゴリセットの編集・削除・並び替え後も Island のカテゴリ配列が古くならないよう Live Activity 更新を追加 |
| 2026-05-28 | Codex | Profile Phase 1 をリリース候補レベルへ更新。`UserSettings` に `profileDisplayName` / `profileBio` / `profileImageData` / `profileAccentColorHex` を追加し、プロフィール編集シートで名前・bio・写真・アクセントカラーを保存可能にした。プロフィール本体は設定項目を出さず、自己紹介ヘッダー・主要スタッツ・実データ由来バッジ・Chapter由来の日記カードグリッドに整理。日記カードはタップで当日の記録一覧を表示し、友達ビューへ転用しやすいカード/ヘッダー構成へ寄せた |
| 2026-05-28 | Codex | Profile右上の設定表示を sheet から `navigationDestination` に変更。設定画面は下からのモーダルではなく、プロフィール内の通常ページとして右からpush遷移する。これに伴い `SettingsView` の「閉じる」ボタンを削除し、標準の戻る導線に統一 |
| 2026-05-28 | Codex | 今日タブの CategorySet 横切替が重い問題を軽量化。テーブル切替は記録データ変更ではないため `setEnabledCategorySetID` で `ChapterStore.revision` を更新しないようにし、Home/Timeline 全体の再描画を避ける。Widget / Dynamic Island 連携が切れないよう、SwiftData保存・Widget reload・Live Activity更新は選択変更時に即時実行する |
| 2026-05-28 | Codex | 日記カードの役割を「カレンダーの再掲」から「SNSに投稿しても映える1日の表紙」へ変更。Profile の日記グリッドを2列のビジュアルカードにし、自動タイトル、代表カテゴリ、24時間リズム模様、合計記録時間、短い要約を表示する。詳細シート先頭にも同じ表紙カードを出し、記録一覧は補足情報として下に置く構成にした |
| 2026-05-28 | Codex | 日記カード機能の目的を再検討し、MVPではプロフィールに常設グリッドを置かない方針へ変更。カレンダー/Todayと競合する一覧表示では価値が薄く、重いビジュアルがアプリ全体の体感速度を落とすため、`ProfileView` から日記カード一覧・詳細シート・日別Digest生成・リズム描画を撤去。生成画像アセットも削除。将来的な日記カードは「閲覧画面」ではなく、1日を振り返ってSNS/友達へ共有するための画像生成・共有成果物として再設計する |
| 2026-05-28 | User/Claude | 役割分担を明確化。今後 Claude = コードレビュー + 設計、Codex = 実装担当。バグ修正の軽重で振り分け。あれからの Codex 進捗をレビュー要求 |
| 2026-05-28 | Claude | Codex 直近実装のレビュー: Phase 0 アーキ移行 (Split Stores / SharedModelContainer / SeedCoordinator / Test target) + Phase 1 Widget + Profile Phase 1 のビルド成功確認。主な指摘: ①AppStores と ChapterStore でサブストアを二重インスタンス化している（DI 化推奨）②ChapterStore.startChapter と StartChapterIntent.perform でロジック重複（同値テスト要）③`revision` カウンター残存 → Phase 0 完了条件か Phase 1 暫定併用かを明文化要 ④hasChapterOverlap が広めに fetch するパフォーマンス懸念 ⑤ProfileView の集計を ScoreStore API に寄せたい。MERGE推奨だがこれらは次の Codex タスクに追加が望ましい |
| 2026-05-28 | User | プロフィールの設計意図を再整理。①プロフィール画面は「他人に見せる場」と「自分のアプリ機能を総覧する場」の二面性を持つ ②コレクションは他人に見せず、自分の活動総括 + モチベ装置として配置 ③解放要素は全部見せるショーケースではなく、バッジ/アイコンフレームのような部分的な着せ替え要素として実装する ④「解放した」だけでは動機にならず、「装着したい」「欲しい」と思える具体的なアイテムを作る方針 |
| 2026-05-28 | Claude | docs/09-profile-design.md を v2 に全面改訂。プロフィールの二面性（自分ビュー/友達ビュー）と装飾アイテム経済を中核に再設計。装飾アイテム種類（フレーム/バッジ/炎/アイコンセット/テーマ/バー/カード/月アート）を §4.1 に列挙。「解放しただけ」の設計を明示的に禁止し、「装着して見た目が変わる」「ユーザーが能動的に欲しいと思える」原則を §1.2 / §10 に明記。コレクション全体は自分ビュー専用、装着アイテムは両ビューに反映の差分テーブルを §7 に追加。README.md と AI_TASKS の docs 一覧・§6.4.1 に装飾アイテム経済への移行タスク（11件）を追加 |
| 2026-05-28 | Codex | Claudeレビュー指摘のうち高リスクな2点を修正。`AppStores` が生成した `CategoryStore` / `CategorySetStore` / `PlanStore` / `ScoreStore` / `LiveActivityCoordinator` を `ChapterStore` に注入し、同一 `ModelContext` 内でサブストアを二重生成しない構成に変更。さらに記録開始/カテゴリ切替のアルゴリズムを `RecordingSwitchLogic.switchToCategory` に切り出し、アプリ内 `ChapterStore.startChapter` と Live Activity/AppIntent の `StartChapterIntent.perform`、Widget側の `RecordingWidgetStore.startChapter` で同じ挙動に寄せた。Widget target は app target の `Chapter.swift` を参照していないため、現段階では `WidgetSharedModels.swift` に同名ヘルパーを置く暫定対応。将来は shared package 化で完全な単一ソースにするのが望ましい。`revision` は SwiftUI再描画ブリッジとして残存、Phase 1 以降で Observation/Store購読整理時に撤去判断。検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功。`test-without-building` は出力なしで停止したため中断 |
| 2026-05-29 | Codex | テーブル切替が Widget / Dynamic Island に反映されない問題を修正。原因は Home の `@AppStorage("activeCategorySetID")` と SwiftData `UserSettings.enabledCategorySetID` の二重管理が残り、外部表示側が `UserSettings` を読むため同期経路が途切れる可能性があったこと。`CategoryGrid.syncSelection/persistSelection` から必ず `ChapterStore.setEnabledCategorySetID` を呼ぶようにし、`setEnabledCategorySetID` は `SeedCoordinator.ensureUserSettings` で default 設定を固定して更新する。さらに App Group UserDefaults に `recording.enabledCategorySetID` を即時キャッシュし、Widget entry / Widget LiveActivity更新 / AppIntent側のカテゴリセット解決はこのキャッシュを優先して読む。これにより SwiftData 反映待ちや重複 `UserSettings` の揺れがあっても、外部表示は直近選択テーブルを使う。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功 |
| 2026-05-29 | Codex | 上記修正後もテーブル反映が不安定だったため、根本設計を変更。Widget / Dynamic Island が `UserSettings.enabledCategorySetID` と SwiftData の CategorySet を毎回推測する構造をやめ、アプリ本体が `RecordingSurfaceSnapshot`（選択中セットID・セット名・8スロット分のカテゴリ表示情報）を App Group UserDefaults `recording.surfaceSnapshot` に発行する方式へ変更した。`ChapterStore.updateLiveActivity` はこのスナップショットを発行し、`LiveActivityCoordinator` はスナップショットから Dynamic Island のボタン配列を生成する。`RecordingGridWidget.entry` と Widget側 Live Activity 更新もスナップショットを最優先で描画し、SwiftData はスナップショットがない初回・fallback 用に限定。これにより App/Widget の ModelContainer 差異、SwiftData 保存反映待ち、重複 UserSettings に依存しない外部表示同期へ寄せた。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功 |
| 2026-05-29 | Codex | テーブル切替がまだ反映されない原因をシミュレータログで追加調査。実際の詰まりは `UserSettings` のSwiftData保存時に既存ストア側の `ZUSERSETTINGS` テーブルへ新しい `ZPROFILEACCENTCOLORHEX` カラムがなく、保存が失敗して `setEnabledCategorySetID` が早期returnし、スナップショット発行・Widget reload・Live Activity更新まで到達していなかったこと。`ChapterStore.setEnabledCategorySetID` は外部表示用の `RecordingSurfaceSnapshot` 発行、`RecordingGridWidget` reload、Dynamic Island更新をSwiftData保存より先に必ず実行し、`UserSettings.enabledCategorySetID` 保存はbest-effortへ降格。保存失敗後はその起動中の再試行を止め、壊れたローカルDBスキーマが外部表示同期を止めない設計にした。加えて `CategoryGrid` は `TabView` のページ復元が起動直後に選択を戻すケースを避けるため、表示確定後の次runloopでも選択同期を再実行する。Claude向け注意: 根本的なDB移行/リセット戦略は別タスクとして残るが、Widget/Dynamic Islandのテーブル反映はSwiftData保存に依存させないのが今回の確定方針 |
| 2026-05-29 | Codex | 最優先残タスクのうち、開発中のSwiftDataスキーマ不整合対策を実装。`SharedModelContainer` と `RecordingWidgetStore` に DEBUG限定の `currentDevelopmentStoreVersion` を追加し、世代不一致時は App Group 内の `Cloud.store` / `Local.store` / `LocalCache.store` と `-shm` / `-wal`、`.Cloud_SUPPORT`、外部表示キャッシュを起動前に削除してから `ModelContainer` を作る。これにより `UserSettings` などのモデル変更後に古いSQLiteスキーマが残っても、開発ビルドではクラッシュ/保存失敗を引きずらない。本番リリース後のデータ維持はこの仕組みではなく `VersionedSchema` / `SchemaMigrationPlan` で対応する。あわせて `CategoryGrid` の `store.revision` 監視を1箇所削除し、activeカテゴリ表示は `store.activeChapter?.category?.id` の変化だけで更新するよう軽量化 |
| 2026-05-29 | Codex | Phase 0 掃除を一括実施。`TickClock` を `@Observable` として実装し、`TimelineView` / `CurrentChapterCard` / `CalendarView` / `CalendarDayView` / `DashboardView` / `ProfileView` の現在時刻更新を `Timer.publish` や `Date()` 直呼び出しから分離した。`CurrentChapterCard` は active Chapter を `@Query` で読むように変更し、`CalendarView` / `CalendarDayView` / `DashboardView` / `ProfileView` は Chapter / Plan を `@Query` で読み、スコアや集計は `ScoreCalculator` に渡す構成へ移行。これにより `ChapterStore.revision` を完全削除し、手動カウンタによる `.id(...)` 再生成も撤去した。さらに `ChapterStore` からカテゴリ・予定・スコア読み取り façade を外し、編集シートは Category / CategorySet を `@Query` で取得、テストは `CategorySetStore` / `ScoreStore` 直接呼び出しへ更新。日付境界の意味を持つ箇所は `DayBoundary` 経由に寄せ、カレンダー表示用の `Calendar.startOfDay` だけ用途別に維持。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功、`test-without-building` でSwift Testing 16件成功、シミュレータ起動確認済（iCloud未ログインによるCloudKit同期警告のみ） |
| 2026-05-29 | Codex | Phase 0 掃除後の従来機能追加検証で、古い App Group `Cloud.store` が残っていると `ZUSERSETTINGS has no column named ZPROFILEACCENTCOLORHEX` が再発することを確認。原因は開発ストア世代キーだけでリセット済み判定しており、世代キーと実体SQLiteのスキーマがズレた状態を検出できなかったこと。`SharedModelContainer` / `RecordingWidgetStore` のDEBUGリセット判定を強化し、世代不一致に加えて `Cloud.store` 内に必須カラムマーカーが存在しない場合も起動前にストアを削除する。世代番号も `2026052903` に更新し、現在のシミュレータ環境では次回起動時に必ず再作成されるようにした。Claude向け注意: これは開発中の安全網で、本番リリース後の既存ユーザーデータ維持は引き続き `VersionedSchema` / `SchemaMigrationPlan` で設計する |
| 2026-05-29 | Codex | 上記修正後の退行確認を実施。`git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功、`test-without-building` はSwift Testing 16件成功。修正済みアプリをシミュレータへinstall/launchし、App Group の `development.storeVersion` が `2026052903` へ更新され、`Cloud.store` の `ZUSERSETTINGS` に `ZPROFILEACCENTCOLORHEX` が存在することをSQLiteで確認。Today / カレンダー / 統計 / 友達 / プロフィールの主要タブへ遷移し、各遷移後ログに fatal / SwiftData / `ZPROFILEACCENTCOLORHEX` エラーが出ないことを確認した |
| 2026-05-29 | Codex | Claude とユーザーが確定した `docs/10-today-tab-structure.md` に基づき、今日タブを「振り返り / 記録 / 予定」の3ページ固定構成へ改修。`HomeView` は上部ナビゲーションバー内の文字タブ + 横ページング `TabView` になり、タブ復帰時は必ず「記録」ページへ戻る。記録ページは既存の CurrentChapterCard / CategoryGrid / TimelineView を維持。振り返りページは昨日のスコア、インサイト、記録数/合計/公開数、カテゴリ別時間を読み取り専用で表示し、過去編集導線は置かない。予定ページは `CalendarDayView` を埋め込み再利用し、Today内では日送り・戻るボタンを出さない設定を追加。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功、`test-without-building` でSwift Testing 16件成功、シミュレータ起動と記録ページ表示確認、直後ログに fatal / SwiftUI error なし |
| 2026-05-29 | Codex | 今日タブ完成パス。上部テキストタブ名を「昨日 / 今日 / 明日」に変更し、タブ内の大見出しは削除。明日の予定づくりは `PlanCoverageSummary` で24時間の入力率・30分以上の空き gap・最初の gap を計算し、`CalendarDayView(showsPlanningStatus:)` の予定づくりカードに残り時間、空きインジケータ、入力率バー、「空きに追加」導線を表示する形にした。下部タブバーの赤 badge は記録体験への主張が強いため撤去し、未予定の通知は上部「明日」横の小さなオレンジ点に集約。`PlanCoverageSummaryTests` を追加し、24時間充足/短い gap の無視/終日予定除外を検証。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` でSwift Testing 19件成功、シミュレータ install/launch と今日ページスクリーンショット確認、直近ログに fatal / error / SwiftUI 警告なし |
| 2026-05-29 | Codex | 明日タブのUIを軽量化。左上に出ていた白い謎ボタンは、Today以外で toolbar leading に置いていた透明 `Color.clear` プレースホルダーが丸背景だけ表示されていたため、Todayページでのみ追加ボタンの `ToolbarItem` を出す構造に変更。明日の予定づくりカードは説明過多だったため撤去し、残り時間は日付直下の色付きピルに移動。専用の「空きに追加」ボタンと入力率バーも削除し、予定追加は既存の通常導線に一本化した。Claude向け注意: `PlanCoverageSummary` は上部「明日」ドットや将来のgapフォーカス用に残すが、v1 UIでは説明カード化しない |
| 2026-05-29 | Codex | ユーザー意図の補正: 残り時間はカード不要ではなく「細いカードでよい」という意味だったため、明日ページの日付下表示をピルから細い横長ステータスカードへ変更。説明文や専用追加ボタンは引き続き出さず、カード内はタイマーアイコン、残り時間、空きあり/見通しありの短い状態表示だけに絞った |
| 2026-05-29 | Codex | 明日ページの残り時間カードを日付カード内から外へ出し、日付カードの上に配置。残り時間は「明日までの締切」であり、日付そのものの情報とは分けた方が視線の流れが明確になるため。表示内容は細いカードのまま、タイマー/残り時間/空き状態だけに限定 |
| 2026-05-30 | Codex | 今日タブの日付切り替わり不具合を修正。原因は `HomeView` が `Date()` 直読みで昨日/今日/明日を組み立てており、0:00を跨いでも親Viewの観測状態が変わらず、タスクキルや別の再描画まで基準日が古いまま残ることだった。`HomeView` に `TickClock(interval: 30)` を持たせ、`clock.now` から日本カレンダーの当日0:00を `todayDate` として導出し、昨日/明日/明日の予定gap計算もすべてその日付境界から作るように変更。さらに `YesterdayReviewPage` / `TodayRecordPage` / `TomorrowPlanPage` を dayStart の `.id(...)` で再生成し、内部に `@State date` を持つ `CalendarDayView` も日付跨ぎで古い状態を保持しないようにした。`TodayRecordPage` は `TimelineView(date:)` に親から受け取った今日の日付を渡し、`Date()` 直指定を撤去。Claude向け注意: 今日タブの3ページはアプリ起動中でも最大30秒程度で新しい「昨日/今日/明日」へ切り替わる設計。より厳密な0:00即時切替が必要なら、30秒タイマーではなく次の0:00に合わせた単発Timerを追加する余地あり |
| 2026-05-30 | Codex | 上記検証中に、古い `Cloud.store` の `ZUSERSETTINGS` 実カラムが不足しているのにDEBUGリセット判定が見逃すケースを再確認。原因はDBファイルのバイナリ文字列検索で `ZPROFILEACCENTCOLORHEX` の有無を見ていたため、実カラムがなくてもSQL文字列などにマーカーが含まれると false negative になること。`SharedModelContainer` のDEBUG判定を SQLite の `PRAGMA table_info(ZUSERSETTINGS)` で実スキーマを読む方式へ変更し、必須カラムが存在しない場合は確実に開発ストアをリセットするようにした。これは本番移行ではなく開発中の安全網で、ユーザーデータの移行方針は引き続き `VersionedSchema` / `SchemaMigrationPlan` で扱う |
| 2026-05-30 | Codex | CategorySet編集UXを改善。従来は各スロットのMenuからカテゴリを探して選ぶ必要があり、カテゴリ数が増えるほど探索コストが上がるため、`CategorySetEditSheet` のグリッド下にカテゴリパレットを追加した。カテゴリは色付きアイコン+名前で一覧表示し、ドラッグ&ドロップで任意スロットへ配置できる。既に割り当て済みのカテゴリはチェック表示し、別スロットへドロップした場合は元スロットを空けて重複を防ぐ。補助操作として、パレット項目タップで最初の空き枠へ追加、割り当て済み項目タップで解除できる。既存のスロットMenuとスロット同士のドラッグ入れ替えは互換操作として維持 |
| 2026-05-30 | Codex | CategorySet編集パレットの実操作不具合を修正。前回実装はスロット全体を `Menu` で包んだままドロップ先にしていたため、ドラッグ/ドロップ gesture が Menu に吸われ、ユーザー操作で配置できない可能性が高かった。スロットは通常View + `contextMenu` に変更し、ドロップ先を直接スロットセルへ付与。payload も `String` 直渡しから `Transferable` な `CategorySetDragPayload` に変更した。さらにドラッグが環境差で不安定でも編集不能にならないよう、カテゴリをタップして選択 → スロットをタップして配置する補助操作を追加。スロット編集ロジックは `CategorySetSlotDraft` に切り出し、ドロップでの割り当て・重複除去・スロット入れ替え・不正payload拒否を `CategorySetSlotDraftTests` で自動検証済み。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LiminalogTests/CategorySetSlotDraftTests` で4件成功、シミュレータへ install/launch して今日タブ起動確認済 |
| 2026-05-30 | Codex | CategorySet編集パレットの追加修正。ユーザー検証で「ドラッグ&ドロップしようとすると土台のカードが選ばれる」問題が残っていたため、原因になり得る `Form` / `List` 行選択、パレット項目タップ選択、スロット自体の draggable を撤去。編集画面を `ScrollView` + 通常カード構成に変更し、ドラッグ開始点はカテゴリの丸アイコンだけに限定した。ドロップは `onDrop` + `NSItemProvider` の plain text payload へ寄せ、スロットカードは受け皿に専念する。これにより、土台カードが選択状態になる UI ではなく、アイコンを持ち上げてスロットへ落とす操作に整理。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LiminalogTests/CategorySetSlotDraftTests` 成功 |
| 2026-05-30 | Codex | CategorySet編集の配置方式を再整理。標準 Drag & Drop はiOS側の長押し開始・リフト時プレビューに依存し、白い背景や即時移動の制御が難しいため、ユーザー指定の代替仕様へ切り替えた。`onDrag` / `onDrop` をUIから撤去し、スロットをタップして青枠で選択 → カテゴリをタップして配置する方式に変更。スロット未選択時にカテゴリを押した場合は従来どおり最初の空きスロットへ追加し、割り当て済みカテゴリなら解除できる互換挙動を残す。これにより長押し不要・白いドラッグ背景なし・タップ即反応の編集体験にした。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LiminalogTests/CategorySetSlotDraftTests` 成功 |
| 2026-05-30 | Codex | CategorySet編集画面のセット名まわりを簡略化。セット名欄の小見出しと「空のままだと自動命名」説明文は編集画面の情報量を増やすため削除し、入力欄だけを残した。空名時の自動命名仕様自体はStore側の既存挙動として維持 |
| 2026-05-30 | Codex | 友達タブ/友達追加フローのMVP実装。`Friend` モデルを追加し、FriendsViewを「つながり」一覧、空状態の招待CTA、リンク/QR招待シート、受け取った招待のpending化、承認待ち、横スクロールランキング（今日/昨日/今週）、現在ステータスカード、友達リスト、友達詳細（ステータス/スコア/favorite/block/delete）へ刷新。`liminalog://friend-invite` URL SchemeとRootTabの受け渡しも追加。CloudKit/CKShareの実共有はDeveloper登録後の `ShareCoordinator` で接続する前提で、UIとローカル状態遷移を先に固めた。開発DBリセット判定も `ZFRIEND` 必須カラム確認へ更新 |

---

## 10.5 Codex FB — 2026-05-24 現在進捗確認

Claude 作業中のため、Codex は読み取り中心で進捗確認。ファイル編集はこの記録追記のみ。

### 進捗評価

- CategorySet の 8 スロット固定化、Home の固定ヘッダー + タイムライン独立スクロール、カレンダーからの予定/チャプター追加導線、日本語日付表記は方向性よし。
- 公開設定 UI 最小版は、Phase 1 の「isPublic を触れる」要件としては十分。Phase 3 のプリセット設計までは専用 `VisibilitySheet` を急がなくてよい。
- `AI_TASKS.md` の完了ログが細かく残っているのはよい。Claude/Codex の引き継ぎに効く。

### Claude への次回 FB / 注意点

1. **古い Phase 0 タスクの上書き漏れに注意**
   - §5.5 にまだ「全 `@Model` の `id` を `@Attribute(.unique)` 化」「`Chapter.photoData` を追加」が残っている。
   - §8.5 で撤回タスクは追加済みだが、拾い間違いを防ぐため、古いタスク側も `[-]` にするか文言を差し替えるのが安全。

2. **DEBUG seed が実機 DEBUG にも入る**
   - `RootTabView.task` で `seedPreviewPlansIfNeeded()` と `seedDevSampleChaptersIfNeeded()` が `#if DEBUG` だけで走る。
   - これは docs/02 で既にアーキ負債として挙げた問題。Preview 専用、起動引数、または環境変数ゲートへ寄せること。

3. **`CategorySet.slots: [UUID?]` は CloudKit 互換性を要検証**
   - ローカル SwiftData では自然だが、CloudKit managed sync 前提では optional UUID 配列が将来詰まる可能性あり。
   - Phase 0 の CloudKit 互換化前に、`slot0...slot7: UUID?` または `[String]` + 空文字扱いなど代替案も検討する。

4. **`CategorySet.categoryIDs` → `slots` は破壊的変更**
   - 開発中リセット前提なら OK。ただし本番前の VersionedSchema では移行ルールが必要。
   - `04-data-model.md` を更新するときに、CategorySet は現実装の `slots` 方針へ合わせること。

5. **CategorySet 作成時の保存条件**
   - Store 側は空名なら自動名を付ける設計だが、`CategorySetEditSheet.canSave` は名前必須。
   - UX 的に「カテゴリを1つ置けば保存可能、空名なら Store が `セット N` を付ける」方が自然なら、`assignedCount > 0` のみに緩める。

6. **混在公開アイコンは実機/Preview確認**
   - `eye.trianglebadge.exclamationmark` が対象OSで表示されるか要確認。
   - 欠ける場合は `eye` + `exclamationmark.triangle.fill` など、既存シンボルの組み合わせに変更。

7. **新UIはビルド確認が必要**
   - `PlanCreateSheet` 新規追加、`TimelineView.selfScrolling`、`Date+Formatting` 追加が入ったので、Claude 側の一区切りで `xcodebuild` を走らせること。
   - Codex は現時点では Claude 作業中のため未実行。

### Codex 側で後で拾う候補

- §8.5 の docs 更新タスク（CloudKit/SwiftData 境界、unique撤回、photoData保留）は Codex 担当のまま。
- `CategorySet.slots` の CloudKit 互換判断は Codex で再確認する価値あり。
- DEBUG seed 隔離は Codex 向き。Phase 0 前に小さく直せる。

---

## 11. オープン論点（ユーザー確認が必要）

実装前に確定したい仕様の曖昧点。両AIが新タスク着手時に該当論点があれば、まずここに追加してユーザーに確認する。

| # | 論点 | 影響範囲 | 優先度 |
|---|------|---------|------|
| 1 | App Group ID / CloudKit Container ID の正式名称 | Phase 0 全体 | 🔴 高 |
| 2 | グリッドの「もっと見る」展開 UI（インライン / シート / フルスクリーン）| Phase 1 グリッド | 🟠 中 |
| 3 | 公開設定「リアルタイム/翌日公開」の選択粒度（チャプター毎/日毎/プリセット毎）| Phase 3 公開設定 | 🟠 中 |
| 4 | 「翌日公開」の配信タイミング（深夜0時固定 / ユーザーの1日始まり時間に従う）| Phase 3 公開設定 | 🟠 中 |
| 5 | アンロックシステムの累計スコア閾値（解放スケジュール表から逆算でOK？）| Phase 2 アンロック | 🟠 中 |
| 6 | アンロックアイテムの失効・離脱者の扱い | Phase 2 アンロック | 🟢 低 |
| 7 | ストリーク途切れの猶予（1日でも60%未満で即リセット？）| Phase 2 ストリーク | 🟠 中 |
| 8 | リアクション絵文字パレットのカスタマイズ可否 | Phase 3 リアクション | 🟢 低 |
| 9 | ランキング同点時のタイブレーク仕様 | Phase 3 ランキング | 🟢 低 |
| 10 | カテゴリマッピング「多対一」の UI 表現・優先順位 | Phase 3 マッピング | 🟢 低 |
| 11 | カテゴリカラーのカスタム範囲（任意Hex / プリセット選択）| 設定UI | 🟢 低 |
| ~~12~~ | ~~使用頻度の集計範囲~~ | ~~Phase 1 グリッド~~ | ✅ 解決 (2026-05-24): 使用頻度ソート廃止 |
| 13 | デザインシステム本体（カラー・タイポ）の定義 | 全画面 | 🟠 中 |
| 14 | カレンダー予定「中身公開/空き時間のみ」のチャプター混在表示 | Phase 3 予定共有 | 🟢 低 |
| 15 | Chapter.photoData の保存戦略（SwiftData直 / CKAsset別管理）| Phase 1 写真添付 | 🟠 中 |
