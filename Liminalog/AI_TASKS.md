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
| [../Liminalog/Views/Profile/docs/09-profile-design.md](../Liminalog/Views/Profile/docs/09-profile-design.md) | プロフィール画面 情報設計（SNS準拠・実装裁量重視・05 上書き） |
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

### 5.2 0:00固定 DayBoundary 導入

- [x] `DayBoundary` struct を `LiminalogCore/Logic` 相当に追加（0:00-24:00 固定）<!-- 担当: Codex, 理由: 純粋ロジック・カレンダー計算, 完了: 2026-05-28 -->
- [-] `@AppStorage("dayStartHour")` / `UserSettings.dayStartHour` 基盤 <!-- 撤回: 現行仕様では1日を0:00-24:00固定にする。可変境界は数年単位の大型アップデートで再検討 -->
- [ ] `Calendar.current.startOfDay(for:)` 直接呼び出しを必要箇所から固定 `DayBoundary.dayStart(for:)` に集約 <!-- 担当: Claude, 理由: 全コードベース横断・既存パターン読解が必要 -->
- [x] `ScoreCalculator` の `dayStart`/`dayEnd` を固定 `DayBoundary` 経由に変更 <!-- 担当: Codex, 理由: ロジック改修, 完了: 2026-05-28 -->

### 5.3 ChapterStore 分割

> 既存 `ChapterStore` (378行・8ドメイン混在) を `docs/03 §3` の方針で分割する。
> **典型的な「Codex で実装」のタスク**: 大規模再構成・ゼロベース思考が要。

- [x] `CategoryStore` 切り出し（CRUD + Query + seedDefaultCategories）<!-- 担当: Codex, 理由: 既存God Storeの責務分離・大規模リファクタ, 完了: 2026-05-28 -->
- [x] `CategorySetStore` 切り出し <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `PlanStore` 切り出し <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `ScoreStore` 切り出し（scoreSummary / streakCount / totalScore）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `LiveActivityCoordinator` 切り出し（既存 LiveActivityManager と統合）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [~] `ChapterStore` は Chapter 専用に縮小（CRUD・activeChapter・カテゴリ切替時は削除しない）<!-- 担当: Codex, 進捗: 2026-05-28 外向きAPI互換の façade として残し、カテゴリ/予定/スコア/LiveActivity は分割Storeへ委譲。完全なChapter専用化はUIの@Query移行後 -->
- [x] `AppStores` 集約ハブを実装 <!-- 担当: Codex, 理由: 新規ボイラープレート, 完了: 2026-05-28 -->
- [x] `RootTabView` で `AppStores.bootstrap()` に切り替え <!-- 担当: Codex, 理由: Store基盤移行と一体で実施, 完了: 2026-05-28 -->

### 5.4 @Query 主軸への移行

> `store.revision` 手動カウンタを廃止し、SwiftData `@Query` に統一する。
> **典型的な「Claude で実装」のタスク**: 既存ビューを丁寧に書き換える整合性勝負。

- [ ] `HomeView` を `@Query` ベースに書き換え + revision 依存を除去 <!-- 担当: Claude, 理由: SwiftUI整合性 -->
- [ ] `TimelineView` を `@Query` ベースに書き換え（TickClock分離も）<!-- 担当: Claude -->
- [ ] `CategoryGrid` を `@Query` ベースに書き換え <!-- 担当: Claude -->
- [ ] `CurrentChapterCard` を `@Query` ベースに書き換え <!-- 担当: Claude -->
- [ ] `CalendarView` / `CalendarDayView` を `@Query` ベースに書き換え <!-- 担当: Claude -->
- [ ] `DashboardView` を `@Query` ベースに書き換え + 期間 filter 動的化 <!-- 担当: Claude -->
- [ ] `ProfileView` を `@Query` + `ScoreStore` 直接呼び出しに整理 <!-- 担当: Claude -->
- [ ] `TickClock` を `@Observable` で実装 <!-- 担当: Codex, 理由: 並行制御を含む独立ロジック -->
- [ ] `ChapterStore.revision` を削除 <!-- 担当: Claude, 理由: 全置換後の最後の掃除 -->

### 5.5 モデル更新（CloudKit互換化）

> **注:** §8.5 Codexレビュー対応 で方針上書き済の項目あり。下記は最新方針に従うこと。

- [x] 全 `@Model` プロパティにデフォルト値を付与（CloudKit要件）<!-- 担当: Codex, 理由: モデル一括変更・機械作業, 完了: 2026-05-28 -->
- [-] 全 `@Model` の `id` を `@Attribute(.unique)` 化 <!-- 撤回 (2026-05-24, Codex §8.5): CloudKit managed sync では unique 制約は使わない。一意性は Store/seed 層で守る -->
- [-] `Chapter.photoData: Data?` を追加 <!-- 撤回 (2026-05-24, Codex §8.5): バイナリ直積みは同期コスト高。代わりに `photoLocalIdentifier` / `thumbnailData` を検討 -->
- [x] `Chapter.updatedAt`, `Chapter.visibilityScope` 追加 <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `PlanBlock.sourceEventID`, `PlanBlock.updatedAt`, `PlanBlock.visibilityScope` 追加 <!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] `UserSettings` モデル新規作成 + シード（`settingsKey` 重複統合ロジック必須）<!-- 担当: Codex, 理由: §8.5 BootstrapStore/SeedCoordinator と一体, 完了: 2026-05-28 -->
- [~] 既存 `VisibilityPreset` を `docs/04 §4.5` の新設計で置換（`builtInKey` 重複統合ロジック必須）<!-- 担当: Codex, 進捗: 2026-05-28 builtInKey/updatedAt/default init/重複統合のみ実装。publishMode 等の本格プリセット設計は未実装 -->
- [ ] `LiminalogActivityAttributes.ContentState.categories` を削除（App Groups経由で読むため不要）<!-- 担当: Codex -->
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

- [ ] テストターゲット `LiminalogTests` 追加（Swift Testing 採用）<!-- 担当: Codex, 理由: 構成作業 -->
- [ ] `TestModelContainer` ヘルパー実装 <!-- 担当: Codex -->
- [x] `Clock` プロトコル + `SystemClock` / `TestClock` 実装 <!-- 担当: Codex, 理由: 設計上の純粋抽象, 完了: 2026-05-28。Swift標準Clockとの衝突回避のため名称は `LiminalogClock` -->
- [x] `Clock` を `ChapterStore` 等に注入できるよう改修 <!-- 担当: Codex, 完了: 2026-05-28。現状は `ChapterStore` 注入 + `ScoreCalculator.summary(now:)` 対応 -->
- [ ] `ScoreCalculatorTests` 実装（仕様書の計算例を必ず含む）<!-- 担当: Codex, 理由: ロジックテストは Codex が書いたロジックのテスト -->
- [ ] `StreakCalculatorTests` 実装 <!-- 担当: Codex -->
- [ ] `DayBoundaryTests` 実装（0:00-24:00固定・日付またぎクリップ）<!-- 担当: Codex -->

---

## 6. Phase 1 — MVPコア（残タスク）

> 既存実装は Phase 0 移行後に「Phase 1 完了」となる前提。
> ここに残るのは「機能として未着手」のもの。

### 6.1 ウィジェット記録グリッド

- [ ] `RecordingGridWidget` の Provider / Entry 設計 <!-- 担当: 未定, 理由: プラン必要 — Claude プラン → Codex レビュー -->
- [ ] `StartChapterIntent` (AppIntent) 実装 <!-- 担当: Codex, 理由: AppIntent + 並行制御 + 共有ストア書き込み -->
- [ ] `SelectCategorySetIntent` (configurable widget) 実装 <!-- 担当: Codex -->
- [ ] `RecordingGridView` (Widget UI) 実装 <!-- 担当: Claude, 理由: SwiftUI / アプリ側 CategoryGrid との視覚整合性 -->
- [ ] アプリ側 mutation 後の `WidgetCenter.shared.reloadAllTimelines()` 呼び出し統一 <!-- 担当: Codex, 理由: 副作用の差し込み箇所が多い・抜け漏れ防止 -->
- [ ] `LiminalogStatusWidget` の退役（または記録グリッドへ統合）<!-- 担当: Claude, 理由: 既存ウィジェットUIの判断 -->

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
- [ ] CategorySet の並び替え UI（ドラッグでソート）<!-- 担当: Claude, 理由: 既存設定UIの整合性 -->
- [ ] スロットのドラッグ&ドロップ並び替え（現状はタップで配置）<!-- 担当: Claude, 理由: SwiftUI ジェスチャ -->
- [ ] 空きスロットを Home 画面からタップして即割り当て（UX改善案）<!-- 担当: 未定 -->

### 6.4 プロフィール画面再設計 + 設定画面切り出し

> 現状 `ProfileView` の中に雑多に並んでいる情報・設定を、SNS準拠の自己表現プロフィール + ☰ ハンバーガー隔離の設定画面に分離する。
> 情報設計は `docs/09-profile-design.md`。具体的なUIは実装裁量。

- [ ] `ProfileView` 再設計（docs/09 の情報設計に従う・UI最適化は実装側裁量）<!-- 担当: Claude, 理由: SwiftUI整合性 -->
- [ ] アイデンティティゾーン実装（プロフィール画像 + ニックネーム + bio + 主要スタッツ 🔥連続/⏱累計/👥友達数）<!-- 担当: Claude -->
- [ ] 解放コレクション表示（ハイライト風・docs/09 §3.2）<!-- 担当: Claude, 依存: アンロックシステム実装 -->
- [ ] 日記カードグリッド表示（DayDigest アーカイブ・docs/09 §3.3）<!-- 担当: Claude, 依存: DayDigest 機能 -->
- [ ] `SettingsView` 新規作成 + プロフィール右上 ☰ から開く（docs/09 §6 参照）<!-- 担当: Claude, 理由: プロフィール本体から設定項目を隔離 -->
- [ ] 友達ビュー対応（同レイアウト・read-only・公開設定フィルタ・docs/09 §7）<!-- 担当: Claude, 依存: Phase 3 友達機能 -->
- [-] 1日の始まり時間 Picker を `SettingsView` に追加 <!-- 撤回: 現行仕様では 0:00-24:00 固定。可変境界は超低優先度の将来検討 -->

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

- [ ] `Friend` モデル定義 <!-- 担当: Codex -->
- [ ] `ShareCoordinator` 実装（CKShare 作成・参加・受諾）<!-- 担当: Codex, 理由: CloudKit 複雑async -->
- [ ] 招待リンク生成・送信 UI <!-- 担当: Claude -->
- [ ] 招待受信時のディープリンクハンドリング <!-- 担当: Codex, 理由: URL Scheme + Universal Link + 状態遷移 -->
- [ ] `FriendsAddView`（メール/iCloud検索）<!-- 担当: Claude -->
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

- [ ] `FriendDetailView`（友達のデイビュー閲覧）<!-- 担当: Claude -->
- [ ] 友達のタイムラインを公開設定でフィルター描画 <!-- 担当: Codex, 理由: フィルターロジック -->
- [ ] `Reaction` モデル + 絵文字パレットUI <!-- 担当: Claude -->
- [ ] `Comment` モデル + コメント投稿UI <!-- 担当: Claude -->
- [ ] リアクション/コメントの CKShare 同期 <!-- 担当: Codex -->

### 8.5 ランキング

- [ ] ランキング集計ロジック（今日/昨日/今週・タイブレーク仕様要確認）<!-- 担当: Codex, 理由: 集計+ソート -->
- [ ] `RankingScrollStrip`（横スクロール）<!-- 担当: Claude -->
- [ ] 友達プロフィールリスト（達成率・現在ステータス）<!-- 担当: Claude -->
- [ ] お気に入り友達の上部固定 <!-- 担当: Claude -->

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

- [ ] PlanBlock の CKShare 配信（公開設定に基づく）<!-- 担当: Codex -->
- [ ] FriendDetailView での予定表示 <!-- 担当: Claude -->

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
- [ ] `CategorySet.slots: [UUID?]` の CloudKit managed sync 互換性を検証 + 必要なら代替案（`slot0...slot7: UUID?` 個別フィールド / `[String]` で空文字扱い 等）を docs/04 で提案 <!-- 担当: Codex, 理由: SwiftData/CloudKit 制約の実装者視点 (10.5 #3) -->

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
- [ ] A→B→C の短時間切替でも A/B/C が別 Chapter として残るテストを追加 <!-- 担当: Codex -->
- [ ] 手動追加・編集時に既存 Chapter と重複する実績を保存ブロックするロジックを追加 <!-- 担当: Codex, 理由: 時間範囲の重複判定 -->
- [ ] 重複保存ブロック時の警告 UI を追加 <!-- 担当: Claude, 理由: シートUI/文言設計 -->
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
- [ ] 日付またぎ Chapter は DB では1件のまま、表示・スコア・バーだけ 0:00-24:00 にクリップされるテストを追加 <!-- 担当: Codex -->
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
| 2026-05-28 | Codex | Phase 0: App Group / CloudKit 基盤を本番構成へ移行。`Liminalog.entitlements` と Widget entitlements を追加し、App Groups (`group.app.YasudaRyuga.Liminalog`) と CloudKit (`iCloud.app.YasudaRyuga.Liminalog`) を Xcode Capability に設定。`LiminalogApp` は `SharedModelContainer.shared` を使う構成へ差し替え。 |
| 2026-05-28 | Codex | Phase 0: `SharedModelContainer` を Cloud 同期対象 (`Category` / `CategorySet` / `Chapter` / `PlanBlock` / `VisibilityPreset` / `UserSettings`) とローカル限定 `CalendarEventCache` の2設定に分離。CloudKit初期化に失敗した場合は local-only にフォールバックする。 |
| 2026-05-28 | Codex | Phase 0: `CategoryStore` / `CategorySetStore` / `PlanStore` / `ScoreStore` / `LiveActivityCoordinator` / `AppStores` を追加。`ChapterStore` は既存UI互換の façade として残し、カテゴリ・予定・スコア・LiveActivity処理を分割Storeへ委譲する段階移行にした。 |
| 2026-05-28 | Codex | Phase 0: `RootTabView` を `AppStores.bootstrap()` 経由に変更。既存ビューへは従来通り `ChapterStore` を environment 注入するため、UI側の大規模変更なしでStore分割を導入。 |
| 2026-05-28 | Codex | 検証: App Group / CloudKit entitlement 追加後、および Store 分割後に `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 成功。起動中の iPhone 17 Pro シミュレータへ install + launch も成功（pid: 62989）。 |
| 2026-05-28 | User/Codex | クラッシュ修正: `SharedModelContainer.shared` の Cloud/AppGroup 初期化失敗時に `assertionFailure` が Debug で即クラッシュしていた。`assertionFailure` をやめ、ログ出力後に local-only ModelContainer へフォールバックするよう変更。`xcodebuild` 成功、simulator install + launch 成功（pid: 63689）。 |
| 2026-05-28 | User/Codex | クラッシュ追加対応: local-only ModelContainer 作成失敗時に残っていた `fatalError` が Debug で `EXC_BREAKPOINT` になっていた。Cloud/AppGroup → local-only → in-memory の3段階フォールバックに変更し、起動不能よりも原因ログ取得とUI確認継続を優先する。local-only は `cloudKitDatabase: .none` を明示。 |
| 2026-05-28 | Codex | CloudKit互換追加対応: 起動ログで `Category.chapters` / `Category.plans` が非optional relationshipとして拒否されていたため optional 配列へ変更。CloudKit push 通知警告に対応するため App の `Info.plist` を `Config/LiminalogInfo.plist` として明示ファイル化し、`UIBackgroundModes = remote-notification` を追加。 |
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
