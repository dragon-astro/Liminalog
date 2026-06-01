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
| [../Liminalog/Design/docs/theme-system.md](../Liminalog/Design/docs/theme-system.md) | テーマ定義型リファクタ 実装仕様（色＋扱い方を型化・§8.7） |
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

### 3.5.1 パフォーマンス確認ルール（Release で測る）

- **「重い・カクつく」の判断は必ず Release ビルドで行う。** Debug ビルド + シミュレータの SwiftUI は最適化が効かず、実機 Release の 5〜10倍遅いことがある。
- Debug シミュレータの体感だけで「重い」と判断して最適化を続けない（過剰最適化・回り道の原因になる）。
- Release ビルド: `xcodebuild -scheme Liminalog -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build`
- Release でも残る重さだけを本物のボトルネックとして追う。
- 2026-05-31 の実体験: 今日タブのカテゴリ切替の「重さ」を Debug で延々追ったが、Release にしただけで「全く気にならない」レベルになった（→ 完了ログ参照）。

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
- [!] CloudKit Container 作成（候補: `iCloud.app.YasudaRyuga.Liminalog`） <!-- 担当: Codex, entitlements / ModelConfiguration / coordinator 土台は実装済。Apple Developer 側の実コンテナ作成・実機署名・CloudKit Dashboard確認はローカルAI環境では完了不可 -->
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
- [x] 既存 `VisibilityPreset` を `docs/04 §4.5` の新設計で置換（`builtInKey` 重複統合ロジック必須） <!-- 担当: Codex, 完了: 2026-06-01 publishMode / hideMoodAndNote / hidePhoto / hideLocation / excludedCategoryIDs / freeTimeOnly / built-in seed（仲良し・知り合い・オフ）/ builtInKey重複統合を実装。旧levelは移行互換として維持 -->
- [x] `LiminalogActivityAttributes.ContentState.categories` を削除（App Groups経由で読むため不要）<!-- 担当: Codex, 完了: 2026-05-28。Live Activity の ContentState は現在カテゴリ/カテゴリセット名/公開状態だけを持ち、カテゴリ配列は Widget/App Group 側で読む前提へ寄せた -->
- [x] `VersionedSchema` + `SchemaMigrationPlan` の骨格を追加 <!-- 担当: Codex, 理由: SwiftData の作法・複雑, 完了: 2026-05-28 -->

### 5.6 DEBUG seed の隔離

- [x] `#if DEBUG seedPreviewPlansIfNeeded` を環境変数ゲート化（`-LiminalogSeedPreviewData YES` 等）<!-- 担当: Codex, 完了: 2026-05-28 -->
- [x] プレビュー専用シードを `PreviewSupport` に集約し、実機 DEBUG ビルドでは入らないようにする <!-- 担当: Codex, 完了: 2026-06-01: preview/dev runtime seed本体を `PreviewRuntimeSeedSupport` へ移し、`PreviewSupport.runtimeSeedRequest()` で UserDefaults / 起動引数 / 環境変数の明示フラグがある場合だけ投入する形へ集約。通常DEBUG起動では投入されないことをテスト化 -->

### 5.7 Swift Package 化（移行最終段）

- [ ] `Packages/LiminalogCore` を作成（Models / Stores / Logic / Sync / Activity / Extensions）<!-- 担当: Codex, 理由: 大規模再構成・ゼロベース -->
- [ ] `Packages/LiminalogUI` を作成（共通コンポーネント・Theme）<!-- 担当: Claude, 理由: UIコンポーネント抽出はSwiftUI整合性勝負 -->
- [ ] App / Widget 両ターゲットから Package を import 化 <!-- 担当: Codex -->
- [x] ウィジェット側の private な `Color(hex:)` 重複実装を削除 <!-- 担当: Codex, 完了: 2026-06-01: Live Activity / RecordingGridWidget のfile-private hex parserを削除し、Widget target内の共有 `WidgetColor+Hex.swift` + `Color.cachedHex` に統一 -->

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

- [ ] 装飾アイテムモデル設計（フレーム/バッジ/炎/アイコンセット/テーマ/バー/カード/月アート の8種類）<!-- 担当: Codex, 2026-06-01: UnlockItem / UnlockCatalog / UnlockKind の土台は実装済み。月アート/アイコンセットなど最終分類整理は残 -->
- [x] 装着状態の永続化（`UserSettings` または専用モデルで「装着中アイテムID」を保持）<!-- 担当: Codex, 完了: 2026-06-01: UserSettings の profileBadgeID/profileIconFrameID/profileStreakIconID/profileCardStyleID を保存元とし、ProfileDecorationUnlocks で未解放IDをdefaultへ戻す -->
- [x] 解放条件判定ロジック（累計時間/ストリーク/パターン達成）<!-- 担当: Codex, 完了: 2026-06-01: UnlockRequirementKind / UnlockMetrics を追加し、累計スコア・記録日数・累計記録時間・ストリーク・朝/深夜記録・カテゴリ種類数で解放判定できるようにした -->
- [ ] コレクションハブ UI（種類別タブ、解放済/未解放、装着切替）<!-- 担当: Claude, 理由: SwiftUI レイアウト勝負 -->
- [x] 「次に狙う解放」セクション（達成までの近さでソート）<!-- 担当: Codex, 完了: 2026-06-01: ProfileUnlockTargetCatalog で未解放アイテムを条件別進捗順に上位3件抽出し、プロフィールに進捗カードを表示 -->
- [x] プロフィール画像フレームの装着レンダリング<!-- 担当: Codex, 完了確認: 2026-06-01: ProfileHero/ProfilePhotoView が装着中 ProfileIconFrameStyle を受け取り、ProfileIconFrameView でプロフィール画像外周へ反映済み -->
- [x] 名前バッジの装着レンダリング<!-- 担当: Codex, 完了確認: 2026-06-01: ProfileHero の EquippedBadgePill が装着中 ProfileBadgeModel のアイコン/名称/色を表示済み -->
- [x] ストリーク炎バリエーションの装着レンダリング<!-- 担当: Codex, 完了確認: 2026-06-01: ProfileStatsRow が装着中 ProfileStreakIconStyle の systemImage/tintHex をストリーク統計へ反映済み -->
- [ ] テーマカラー解放と装着（標準8色は既存、拡張色を解放対象に）<!-- 担当: Claude -->
- [ ] 装着アイテムの両ビュー（自分/友達）反映<!-- 担当: Claude, 依存: Phase 3 友達機能 -->
- [x] 既存の Phase 1 バッジ表示を装飾アイテム経済データソースに差し替え<!-- 担当: Codex, 完了: 2026-06-01: ProfileBadgeCatalog を UnlockItem / unlockedAt ベースへ接続し、未解放バッジはロック表示に統一 -->

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
- [x] `DashboardCardKey` enum で全カードを識別子化 <!-- 担当: Codex, 完了: 2026-06-01: DashboardCardKey でカードIDを定義し、期間別default order / 保存順正規化を実装 -->
- [x] `UserSettings.dashboardCardOrder` から表示順を動的取得 <!-- 担当: Codex, 完了: 2026-06-01: DashboardPeriodContent が UserSettings.dashboardCardOrder を読み、無効/重複キーを除外して不足カードを補完して描画 -->
- [x] カード数値カウントアップアニメーション共通 ViewModifier <!-- 担当: Codex, 完了: 2026-06-01: DashboardCountUpModifier を追加し、スコア/時間/件数/割合/差分の主要数値へ適用。Reduce Motion時は即時表示 -->
- [x] `DashboardCustomizeSheet`（並び替え・表示切替）<!-- 担当: Codex, 完了: 2026-06-01: Dashboard上部からカード編集Sheetを開き、表示ON/OFF・並び替え・初期順リセットを UserSettings.dashboardCardOrder / dashboardHiddenCardKeys に保存 -->

#### 今日
- [ ] カテゴリ別アクティビティリング風グラフ <!-- 担当: Claude, 理由: 高度なSwiftUIレイアウト -->
- [ ] カテゴリ別ドーナツグラフ <!-- 担当: Claude -->
- [ ] 24時間ブロック色分け（現行ヒートマップを仕様意図に合わせて再設計）<!-- 担当: Claude -->

#### 週間
- [x] カテゴリ別トータル横棒グラフ（既存を週間期間用に調整）<!-- 担当: Codex, 完了: 2026-06-01: 既存のカテゴリ構成カードをカテゴリ別トータル表示へ寄せ、各カテゴリ行に期間内合計時間の横棒・時間・割合を表示 -->
- [ ] 日ごとの積み上げ棒グラフ <!-- 担当: Claude -->
- [x] 時間帯別傾向（朝/昼/夜の割合計算）<!-- 担当: Codex, 完了: 2026-06-01。`DashboardTimeOfDaySummary` で朝(5-12)/昼(12-18)/夜(18-翌5)の実績時間・割合・支配時間帯を算出。日跨ぎ/active/期間クリップをテスト済み -->
- [x] 時間帯別傾向の表示UI <!-- 担当: Codex, 完了: 2026-06-01: 週間Dashboardに朝/昼/夜の支配時間帯・比率・時間バーを表示 -->
- [x] 先週比差分バー（集計）<!-- 担当: Codex, 完了: 2026-06-01。`DashboardPeriodDeltaSummary` で現期間/前期間の平均スコア・実績時間・予定時間・一致時間・スコア対象日数の差分/増減率を算出。表示UIはClaudeタスクとして継続 -->
- [x] 先週比差分バーの表示UI <!-- 担当: Codex, 完了: 2026-06-01: 週間Dashboardに平均スコア/実績/予定/一致/スコア日の前週比と中央基準バーを表示 -->
- [ ] 友達比較 placeholder（Phase 3で本実装）<!-- 担当: Claude -->

#### 月間
- [ ] 月間カレンダーヒートマップ（GitHub風） <!-- 担当: Claude, 理由: GridLayout勝負 -->
- [ ] カテゴリ別折れ線グラフ（週単位推移）<!-- 担当: Claude -->
- [ ] 先月比差分バー <!-- 担当: Claude -->

#### 年間
- [ ] 年間カレンダーヒートマップ <!-- 担当: Claude -->
- [ ] 月ごとサマリー（テキスト+数値）<!-- 担当: Claude -->

### 7.3 アンロックシステム

- [x] `UnlockItem` モデル定義 <!-- 担当: Codex, 完了: 2026-06-01。CloudKit互換のdefault値つきSwiftDataモデルとして key/kindRawValue/requiredCumulativeScore/requirementKindRawValue/requiredValue/unlockedAt/targetID/sortOrder を保持 -->
- [x] `UnlockRules` 純粋関数（複数メトリクス → 解放判定）<!-- 担当: Codex, 完了: 2026-06-01。60pt/日を合格ラインとする累計スコア閾値に加え、記録日数/累計記録時間/ストリーク/朝・深夜記録/カテゴリ種類数の条件で解放key/次アイテム/進捗を算出 -->
- [x] マスターデータ seed（26件・解放スケジュール逆算）<!-- 担当: Codex, 完了: 2026-06-01。週1×12、隔週×6、6〜9ヶ月×5、9〜12ヶ月×3の26件を `UnlockCatalog` に固定。解放後は失効しない -->
- [x] `UnlockRulesTests` <!-- 担当: Codex, 完了: 2026-06-01。カタログ26件/閾値/条件種別/seed重複統合/ストリーク・朝記録・カテゴリ種類数解放/再評価で再解放・失効しないことを検証 -->
- [x] `UnlockStore` 実装（解放トリガー・状態管理）<!-- 担当: Codex, 完了: 2026-06-01。起動時seed、プロフィール集計時の UnlockMetrics refresh、重複key統合、最古unlockedAt保持を実装 -->
- [x] プロフィール画面のアンロック進捗カード <!-- 担当: Codex, 完了: 2026-06-01: 次の解放カードとして未解放アイテムの残り条件/進捗率/種類を表示。全解放時は完了状態カードへ切替 -->
- [ ] `UnlockGalleryView`（解放済みコレクション一覧）<!-- 担当: Claude -->
- [ ] アンロック解放時の通知・お祝い演出 <!-- 担当: Claude, 理由: SwiftUIアニメ -->

### 7.4 エクスポート・シェア

- [ ] タイムライン画像書き出し（縦長・Instagram向け）<!-- 担当: Claude, 理由: SwiftUI ImageRenderer の使い方 -->
- [ ] 週間サマリー画像書き出し <!-- 担当: Claude -->
- [-] CSV書き出し（Chapter / PlanBlock）<!-- 不要 (2026-06-01): ユーザー判断によりリリーススコープ外。データ持ち出し導線は当面画像シェア中心に寄せる -->
- [ ] `ExportView`（書き出しオプション選択画面）<!-- 担当: Claude -->

### 7.5 ストリーク UI

- [ ] プロフィール画面のストリーク表示（🔥アイコン + 連続日数）<!-- 担当: Claude -->
- [ ] ストリーク途切れ時の通知（Phase 2.5）<!-- 担当: Codex, 理由: UserNotifications 設定 -->

### 7.6 日付またぎ・0:00固定境界

- [ ] 日付またぎチャプターのタイムライン表示（0:00-24:00 固定の `DayBoundary` 適用済前提）<!-- 担当: Claude -->
- [x] ScoreCalculator の日跨ぎ正常性検証テスト <!-- 担当: Codex, 完了: 2026-06-01。`ScoreCalculatorTests.crossDayEntriesAreClippedToTargetDay` で前日23:00→当日1:00の予定/実績を対象日0:00-1:00にクリップすることを検証済み -->

### 7.7 デイリーカード & コンテンツエンジン（docs/12）

> 設計: [docs/12-daily-card-engine.md](Views/Profile/docs/12-daily-card-engine.md)。1日の総括カード＝成長ループの中核。文章生成AIは使わない（決定論）。**この一連は「カード先行 → solo で出す → 拡散を測る → その後 友達インフラ」の戦略（§オープン論点参照）に沿って、Phase 3 友達より先に手を付ける候補。**

#### 7.7.1 【最優先・是正】カードの "中身" を本物のエンジン＋自虐の声にする

> 現状（2026-06-01）: `DailyReflectionCard.swift` の `DailyPersona.make` が**暫定スタブ**。カードの殻（ビジュアル）は完成したが中身が仮。Claude レビュー指摘:
> - ❌ ペルソナを `categoryRows.first`（時間1位＝大抵睡眠）の `longestMinutes>=180` で判定 → **「睡眠スプリンター」= docs/12 §5 原則2違反**（見出しが睡眠に支配される）。
> - ❌ message が優しいコーチ口調（「ちゃんと手が届いています」）。**選んだ自虐トーン（docs/12 §6/§7）になってない。**

- [x] **エンジン置換（STEP1）**：上記スタブを docs/12 §5.3（逸脱）/§5.4（睡眠=パターン検出で見出しから除外）/§6（クロノタイプ4×集中3＋レア＋活動スロット）に置換。<!-- 担当: Codex, 完了: 2026-06-01。`DailyPatternAnalysis` を追加し、28日履歴で休息/睡眠相当の長尺・高頻度ブロックをカテゴリ名非依存で降格。履歴7日未満では逸脱検出を抑え、床型メッセージへfallback -->
  - **受け入れ基準：睡眠が見出しペルソナにならない（濃紺/濃グレー睡眠でも）。最低履歴<7日はオフで床型に。**
- [x] **声の入れ替え（STEP2）**：全 message/fact 文言を自虐×あたたかいトーンへ（docs/12 §6/§7・「落ち着いて？」系）。<!-- 担当: Claude（ユーザー編集必須・製品の人格）, Codex実装: 2026-06-01。優しいコーチ口調を撤去し、「珍しくちゃんと出席」「小分けパック」など観察＋軽い自虐へ置換。最終コピー磨きは称号プール拡張時に継続 -->
  - **受け入れ基準：優しいコーチ口調が残ってない。**
- 注: §7.7 の StatsEngine / 逸脱 / 睡眠検出 / ペルソナ判定の各タスクの具体実体がこの是正。重複でなく "現状スタブの置換" としてここを起点にする。

#### 7.7.2 【是正・第2弾】2026-06-01 Claudeレビュー（妥協なし）

> 1回目の是正でエンジン/声/テーマ/共有まで実装され、カードの殻・核は合格。残るは「深さと掃除」。コピーとテーマhexは **Claude が具体指定**（docs参照）＝Codex は実装するだけ。

- [x] **A.【最重要・アーキ】エンジンを View から独立レイヤーへ抽出**：`DailyPatternAnalysis`・ペルソナ・睡眠検出・逸脱が `DailyReflectionCard.swift`（900行超 View）に埋まってる。**共有 `StatsEngine`/`PatternDetector` に抽出**し統計タブと再利用（docs/12 §4・二重実装回避）。 <!-- 担当: Codex, 完了: 2026-06-01 DailyCardEngine.swift に抽出し View から称号/睡眠検出/逸脱判定を分離 -->
- [x] **B. 称号タイトルと本文の不一致を解消**：例「有言実行の人」(予定一致) なのに本文が「趣味が主役」(逸脱)。**タイトルと message が同じ事を補強**するよう、signalMessage 採用時はタイトル選択もそれに整合させる。 <!-- 担当: Codex, 完了: 2026-06-01 高スコア予定一致は予定一致コピーに固定し、逸脱signalはsignal由来タイトルへ揃える。テスト追加 -->
- [x] **C. 「データはまだ少なめ」等のメタ文言を共有コピーから除去**：コールドスタートの内部事情が、シェアする1枚の表に出ない。床型は別の自虐コピーで埋める（docs/12 §6.7）。 <!-- 担当: Codex, 完了: 2026-06-01 history不足時はsignalを出さず、床型/形状コピーへフォールバック。テスト追加 -->
- [x] **D. 「実績 24時間」＝睡眠込み生集計を是正**：fact strip の実績は**主要休息ブロックを除いた裁量時間**にする or ラベルを「記録カバー」等に変更。生24hを見出し数字にしない。 <!-- 担当: Codex, 完了: 2026-06-01 主要休息検出時は「裁量時間」、休息除外なしは「記録カバー」に変更。スコアpillは削除。テスト追加 -->
- [x] **E. ペルソナを docs/12 §6 まで拡充**：現状約6種＝MVP下限以下ですぐ繰り返す。**§6.7 の称号コピー・カタログ（Claude指定）**を実装し、レア・活動スロット・signalMessage 変奏を入れて 15〜20+ へ。<!-- 担当: Codex（判定）＋ Claude（コピー＝docs/12 §6.7）, 完了: 2026-06-01: 4クロノタイプ×3集中形の12称号、予定一致/風まかせ/充電/行方不明/初記録/久々/増減signalをDailyCardCopyCatalogへ実装し、message配列を日付seedで安定選択 -->
- [ ] **F. 昨日ページの重複撤去**：カード下の旧 `YesterdayCategoryBreakdown`＋`YesterdayInsightCard` を、カードの**展開層（2層の裏）に畳む or 撤去**（docs/12 §3）。<!-- 担当: Claude -->
- [ ] **G.（軽微）リング中央の整理**：グリフ＋pt＋ラベルで詰まり気味。docs/13 §5.3「中央は余白基調」へ。<!-- 担当: Claude -->

- [ ] **StatsEngine / PatternDetector**（統計タブと共有の集計層・二重集計回避）<!-- 担当: Codex, 理由: 集計ロジック。↑A と統合 -->
- [x] **ルーティン逸脱エンジン**（docs/12 §5.3：28日窓・reg/μ/σ・σfloor15分・履歴<7日オフ・|z|≥1.5）<!-- 担当: Codex, 理由: 統計ロジック, 完了: 2026-06-01。DailyカードMVP内で実装。共通StatsEngine化は後続の保守タスク -->
- [x] **主要休息ブロック（睡眠）検出**（docs/12 §5.4：位相クラスタ・カテゴリ名非依存・自信度ゲート・昼夜逆転/無記録/カオス対応）<!-- 担当: Codex, 完了: 2026-06-01。長尺・頻度・平均尺によるMVP判定。カテゴリ名/色/デフォルトIDには依存しない -->
- [ ] **検出器カタログ実装**（docs/12 §5.1 中立12型）＋ 選抜ロジック（§5.2 パンチ×逸脱・型重複回避・床型保険）<!-- 担当: Codex, 2026-06-01進捗: A/B/D/F と床型の一部として、初記録・久々出現・いつもより増減・1日の形・予定一致・記録カバー/切替factをDailyCardEngineへ実装。H/J/K/L、体感換算、友達/気分/ユーザー宣言系、昨日と同型回避は後続 -->
- [x] **ペルソナ/称号判定**（docs/12 §6：クロノタイプ4×集中3＋レア＋活動スロット・§6.6 閾値）<!-- 担当: Codex, 理由: 分類ロジック, 完了: 2026-06-01: 深夜活動60分優先/活動重心による朝・昼・夜、最長90分スプリンター、8件以上かつ中央値25分未満ザッピング、それ以外マラソナーの判定と12称号表を実装。レア/床型は予定一致・風まかせ・充電・行方不明・初記録・久々・増減signalで補強 -->
- [ ] **称号・言い回しプール（実コピー）**（自虐×あたたかいトーン・MVP15〜20）<!-- 担当: Claude（ユーザー編集必須・製品の人格）, 2026-06-01進捗: docs/12 §6.7 の既存コピーはDailyCardCopyCatalogへ反映済み。最終のコピー温度・追加文言磨きはユーザー/Claude判断待ち -->
- [ ] **体感換算表（H）**（カテゴリ別あるある換算・手書き資産）<!-- 担当: Claude -->
- [x] **任意ユーザー宣言（増やしたい/減らしたい/中立）＋任意「これは睡眠」タグ**（カテゴリ作成/編集時の任意項目）→ データモデル追補 <!-- 担当: Codex, 理由: モデル + UI, 完了: 2026-06-01。Category に dailyCardIntentRawValue / isDailyCardSleepCategory を追加し、カテゴリ作成/編集UIとDailyCardEngineの逸脱コピー/休息除外へ接続。デフォルト「睡眠」は新規seed時に睡眠タグ付きにした -->
- [ ] **デイリーカード View**（昨日ページのホーム・2層＝シェア表面/展開詳細）<!-- 担当: Claude -->
- [ ] **「明日はどうする？」橋渡し CTA**（docs/12 §8.2：気づき→明日の予定へ1タップ・代替ブロックのプリフィル提案）<!-- 担当: Claude -->
- [x] **統計タブから単日モードを退避**（docs/12 §2：単日=カード/複数日=統計。統計は傾向・行動変容の鏡へ）<!-- 担当: Codex, 完了: 2026-06-01。UIの `DashboardPeriod.allCases` を週/月/年に限定し、単日の表現はToday昨日カードへ寄せた。内部 `today` case は既存テスト/互換のため保持 -->
- [ ] カードスナップショット保持（過去日カード再描画・持続タイプ・称号コレクション）→ docs/04 追補 <!-- 担当: Codex -->

### 7.7.3 情報設計の洗練（docs/15・横断 IA/UI）

> 設計: [docs/15-ia-refinement.md](Views/Profile/docs/15-ia-refinement.md)。「強すぎる情報を降格・不要を削除・UXのためUI洗練」の横断パス。判断基準＝スコア遍在させない/色は希少(chrome⇔data分離)/静けさ。**Codex は docs/15 §9 の優先度つき指示をそのまま実装。**

- [x] **P1-1 スコアの遍在を絞る**（§1.1）：カードfact stripのスコア削除・カレンダー全セルの**数値をアンビエント化**（§5 ミニリング/濃淡でスキャン・正確値は日詳細）。**プロフィール累計は削除せず longevity（続けた長さ）として残す**（成績と読ませない見せ方＝XP/レベル化 or 記録日数/累計時間とペア）。スコア数値の主役はカード中央/友達ランキング/統計トレンド。 <!-- 担当: Codex, 完了: 2026-06-01 Daily fact stripからスコア削除、月カレンダー日セルを数値badgeからミニリングへ変更 -->
- [x] **P1-2 統計タブをトレンド主役に**（§6）：単日モード(dayピッカー)削除・単期間breakdown降格/削除・期間は週/月/年・トレンド系を上へ。 <!-- 担当: Codex, 完了: 2026-06-01 DashboardPeriod.allCases は週/月/年のみ、日間はUIから外れ、期間ピッカー/横スワイプは維持 -->
- [x] **P1-3 昨日カード fact strip を意味ある2項へ＋中央を余白化**（§3）。 <!-- 担当: Codex, 完了: 2026-06-01 fact stripを「裁量時間/記録カバー」「切替」の2項へ整理 -->
- [~] **P2-4 自己説明ラベル削除**（§1.3：「24時間バー」見出し等）。<!-- 担当: Codex, 進捗: 2026-06-02。TimelineView / SharedTimelineReadOnlyView の DayOverviewBar から「24時間バー」見出しを撤去。自己説明ラベルの横断監査は継続 -->
- [x] **P2-5 今日ページの 実績/予定 segmented を控えめ inline トグルへ・リスト=実績デフォルト**（§2）。<!-- 担当: Codex, 完了: 2026-06-02。TimelineView と SharedTimelineReadOnlyView の segmented Picker を下線付き inline toggle に降格。TimelineTab.actual が先頭かつ保存値defaultも actual のためリストは実績デフォルトを維持 -->
- [x] **P2-6 カレンダー月グリッドをアンビエント化**（§5）：スコア数値→ミニ二重リング/濃淡でスキャン可・正確値は日詳細。重要予定ラベルも最小限。 <!-- 担当: Codex, 完了: 2026-06-01 CalendarScoreBadge を数値表示からミニリングへ変更。accessibilityには正確値を保持 -->
- [ ] **P2-7 昨日ページ重複ブロック撤去**（§3＝§7.7.2 F）。<!-- 担当: Claude -->
- [ ] **P3-8 色の希少・chrome/data分離の全画面洗い出し**（§1.2）。<!-- 担当: Claude -->
- [x] **P3-9 友達一覧の主役をステータスリストに・ランキング従・@handle非強調**（§7）。<!-- 担当: Codex, 完了: 2026-06-02。FriendsViewで「今の友達」リストを先頭へ移し、ランキング帯は後段の小さめカード/淡い面へ降格。@handleは一覧主情報に出さず、名前+現在ステータス+ひとことを主役に維持 -->
- [ ] **P3-10 プロフィールのコレクションを称号+テーマへ・装備/コレクション重複整理**（§8）。<!-- 担当: Claude -->

### 7.8 ビジュアル・アイデンティティ（docs/13）

> 設計: [docs/13-visual-identity.md](Views/Profile/docs/13-visual-identity.md)。世界観＝liminal（予定と実績のあいだ）。**Codex は docs/13 の "なぜ"＋アンチパターン（§9）を必ず読んでから着手。** 最終 hex・和文Display書体はユーザーと確定。

- [x] **トワイライト・カラーシステム適用**（docs/13 §2）。`LiminalTheme` 共有化・dusk/daybreak セマンティックトークン化・system青撤去 <!-- 2026-06-01 Codex。初回は dark固定で実装、その後 docs/14 方針に合わせ `preferredColorScheme(.dark)` を撤去し、システム外観に応じて宵/曙へ解決するよう更新 -->
- [x] **テーマカラー/優先度システム**（§2.4：Primary紫/Reward金/中立・tint=primary）<!-- 2026-06-01 Codex -->
- [x] **視認性正規化**（§2.5：`liminalReadableDataColor` WCAGコントラスト≥3:1・色相保持で明度up）＋ `Category.displayColor` として全データviz（グリッド/リング/24hバー/カード/ピル）に配線 <!-- 2026-06-01 Codex -->
- [x] **二重24時間リング**（docs/13 §5：内=予定/外=実績・0:00上時計回り・glow）。draw-onアニメは後で <!-- 2026-06-01 Codex -->
- [x] **空気感レイヤー**（§4：グレイン・soft glow・グラデ）<!-- 2026-06-01 Codex -->
- [x] **全画面へ世界観適用**（§7：タブバー・シート・既存カード・24hバー・タイムライン restyle）。島問題解消 <!-- 2026-06-01 Codex -->
- [x] **デイリーカードの 9:16 書き出し画像**（§6：designed な1枚・Liminalogマーク・ImageRenderer）<!-- 担当: Claude。Codex実装: 2026-06-01。昨日カードから `ImageRenderer` で1080×1920 PNGを書き出し、共有シートへ渡す -->
- [ ] **タイポ役割の確定**（§3 Display/Body/Numeric）。和文Display書体は要ユーザー確定。現状は system rounded 暫定 <!-- 担当: Claude -->
- [ ] **draw-onアニメ等モーション**（§8）<!-- 担当: Claude -->
- [ ] **優先度の最終チェック**（§2.4：Primary紫を主役1要素に絞れてるか・カテゴリ色がchromeに漏れてないか）＋ アンチパターン（§9）セルフレビュー <!-- 担当: Claude -->

---

## 8. Phase 3 — 友達機能

### 8.1 CloudKit Sync 基盤

> Phase 0 で CloudKit Private DB を ON 済の前提。
> Phase 3 では CKShare による友達共有を追加。

- [x] `CloudKitSyncCoordinator` 実装（アカウント状態監視・同期エラー通知） <!-- 担当: Codex, 完了: 2026-06-01 CKContainer.accountStatus async 監視、AccountState、ユーザー向けメッセージ、lastError/lastCheckedAt を実装。実CloudKit同期の検証はApple Developer環境が必要 -->
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

- [x] `VisibilityPreset` モデル（新設計）<!-- 担当: Codex, 完了: 2026-06-01。Phase 0 §5.5で先行実装。publishMode/detail flags/built-in識別/並び順/旧level互換を追加 -->
- [x] ビルトインプリセット seed（仲良し/知り合い/オフ/カスタム）<!-- 担当: Codex, 完了: 2026-06-01。仲良し/知り合い/オフをSeedCoordinatorで作成し、カスタムはbuiltInKey nilのユーザー作成として同名でも統合しない。重複統合テスト更新済み -->
- [ ] `VisibilityPresetManagementView` <!-- 担当: Claude -->
- [ ] `VisibilitySheet` を多段（プリセット / カスタム / カテゴリ別）に拡張 <!-- 担当: Claude -->
- [ ] 翌日公開モードのバックグラウンドタスク（深夜に SharedTimeline へスナップショット書き出し）<!-- 担当: Codex, 理由: BGTaskScheduler + データ加工 -->
- [ ] `PublishMode.realtime` 時の即時 CKShare 反映 <!-- 担当: Codex -->

### 8.4 友達閲覧

- [x] `FriendDetailView`（友達のデイビュー閲覧）<!-- 担当: Codex, 完了: 2026-05-30。友達プロフィール/現在ステータス/短期スコア/お気に入り/削除/ブロックの詳細UIに加え、友達カレンダーの日別詳細で共有予定・共有実績の読み取り専用タイムラインを表示。自分のTodayタイムラインと同じく24時間バー、実績/予定セグメント、時間レール、カードリストで確認できる。編集・削除導線は出さない -->
- [x] 友達のタイムラインを公開設定でフィルター描画 <!-- 担当: Codex, 完了: 2026-06-01。`FriendSharedPlanSnapshot` / `FriendSharedActivitySnapshot` 生成時に `VisibilityPreset` を適用し、オフモード、カテゴリ除外、メモ/気分/場所の隠蔽、予定の空き時間のみ表示をテストで固定。CKShare実送受信と翌日公開のBGTaskは別タスクとして継続 -->
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

- [x] `FriendCategoryMapping` モデル <!-- 担当: Codex, 完了: 2026-06-01。友達ごとの myCategoryID / friendCategoryID / useUnifiedColor を保持するCloudKit互換SwiftDataモデルを追加し、比較用に友達スナップショットへ categoryID を付与 -->
- [x] 自動マッピングロジック（デフォルトカテゴリ同士）<!-- 担当: Codex, 完了: 2026-06-01。共有予定/実績スナップショットからカテゴリ記述子を抽出し、同名のデフォルトカテゴリだけを自動対応。既存手動マッピングとカスタムカテゴリは上書きしない -->
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

- [~] PlanBlock の CKShare 配信（公開設定に基づく）<!-- 担当: Codex, 進捗: 2026-06-01。Developer登録前のためCloudKit実送受信は未接続。先に `FriendSharedPlanSnapshot` を受信/表示用の安定スナップショットとして追加し、`PlanBlock.isPublic == true` に加えて `VisibilityPreset` の publishMode none / カテゴリ除外 / freeTimeOnly を適用する変換関数とテストを実装。CKShare接続時はこのスナップショットを送受信単位にする -->
- [x] FriendDetailView での予定・実績表示 <!-- 担当: Codex, 完了: 2026-05-30。友達プロフィールのカレンダーボタンから、友達専用の月カレンダーへ遷移。自分のカレンダータブと同じく年月ピッカー、曜日固定、42セルグリッド、スコア表示、重要予定ラベル、複数日バー、検索、読み取り専用の日別詳細を実装。月グリッドには重要/終日予定だけを表示し、日別詳細ではその日に公開された予定全体と共有実績タイムラインを表示する -->

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
- [x] スコア公平性のため、前日以前の実績は時間/カテゴリ/削除をロックし、メモ/場所/公開設定だけ編集可能にする <!-- 担当: Codex, 完了: 2026-05-26。2026-05-31: 気分UI廃止に伴い対象から除外 -->
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
- [x] 追記情報（メモ/写真/場所）は固定高さ内で要約表示 <!-- 担当: Codex, 完了: 2026-05-25。2026-05-31: 気分UI/表示は廃止 -->
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
- [~] 固定高さカード、短時間記録、日付またぎ、バー位置計算の Preview/Test を追加 <!-- 担当: Codex, 進捗: 2026-06-01。`TimelineDisplayTests` で読み取り専用Timeline表示モデルの日付またぎクリップ/継続メタデータ、短時間記録保持、5分未満gap抑制、24時間バーのx位置・最小幅・アイコン表示閾値を検証。固定高さカードの視覚Preview/320pt確認はClaude/UI検証として継続 -->
- [x] 日付またぎ Chapter は DB では1件のまま、表示・スコア・バーだけ 0:00-24:00 にクリップされるテストを追加 <!-- 担当: Codex, 完了: 2026-05-28。DayBoundary/ScoreCalculator のクリップをテスト済み -->
- [ ] 実機で 320pt 幅でも目盛り・カード文言が破綻しないか確認 <!-- 担当: Claude -->

---

## 8.7 テーマ定義型リファクタ（docs/theme-system）

> [Design/docs/theme-system.md](../Liminalog/Design/docs/theme-system.md) が実装仕様。**着手前に必読。**
> ライト/ダークの場当たり分岐をやめ、**1テーマ=1値型（色＋扱い方）**にする。分岐は選択1関数に集約。
> 既存 `LiminalTheme.token` 呼び出し（約57箇所）は無改修。**ダークの見た目は変えない（リグレッション禁止）。**
> 追加方針（2026-06-02）: **宵(dusk)は現状を基準として維持し、曙(daybreak)は宵と同格の見やすさ・リッチ感まで再構成する。** 曙だけ薄い/見づらい/平たい状態を許容しない。
> 優先順は docs §5 の P0→P3。P0 は純リファクタで見た目不変、各フェーズで §6 のスクショ検証必須。

### P0: 基盤型 + 選択の一元化（最優先）

- [x] `LiminalThemeDefinition.swift` 新規作成（型一式・docs §3）<!-- 担当: Codex, 完了: 2026-06-02。LiminalThemeDefinition / LiminalPalette / surface・glass・emphasis・effects treatment / LiminalThemeCatalog を追加 -->
- [x] `LiminalThemeCatalog` に dusk/daybreak を定義（docs §4 の値・dusk は現状値を1:1転記）<!-- 担当: Codex, 完了: 2026-06-02。duskは既存hex維持、daybreakはP1.5初期改善値へ更新 -->
- [x] `LiminalTheme` の token/gradient/uiCanvas をカタログ動的解決へ差し替え（シグネチャ不変）<!-- 担当: Codex, 完了: 2026-06-02。既存の LiminalTheme.primary 等の呼び出しは維持し、内部解決だけ LiminalThemeCatalog へ移行 -->
- [x] 旧 duskPalette/daybreakPalette/LiminalThemePalette/activePalette を撤去 <!-- 担当: Codex, 完了: 2026-06-02 -->

### P1: treatment を型経由に（ライトのみ改善・ダーク不変）

- [x] `liminalCanvasChip` のハードコード分岐を `definition(for:).surface` 読みへ書き換え（先行実装を整理）<!-- 担当: Codex, 完了: 2026-06-02。surface treatment の glass/solid を参照する形へ移行 -->
- [x] `liminalGlassFill(in:)` modifier 新設し `DailyReflectionCard` の `.white.opacity` ピル/パネルを置換（Canvas描画の意匠は対象外）<!-- 担当: Codex, 完了: 2026-06-02。共有ボタン/fact pill/share tile/リング中央アイコンなど背景+strokeペアを置換。Canvas上のリング下地・grainは意匠として維持 -->
- [x] プロフィールカードの白固定を解消し、同じ装飾IDでも light/dark で背景・文字が読める色へ解決する <!-- 担当: Codex, 完了: 2026-06-02。ProfileCardStyle に light/dark 背景とカード内文字色を持たせ、宵で白地+白文字になる事故を修正。P1.5 で曙パレットと一緒に最終色を詰める -->

### P1.5: 曙パレット再構成（ライトの見づらさ・リッチ感不足を解消）

- [~] `daybreak` の canvas/surface/elevated/divider/gradient を再構成し、宵に比べて曙だけ情報階層が薄い問題を解消する <!-- 担当: Codex, 進捗: 2026-06-02。ユーザー方針に合わせ、濃く輪郭を立てる方向から「白に馴染む薄い面 + 要所の朝ライト」へ再調整。Today/DailyReflectionCard のlight/darkスクショで破綻なしを確認。ProfileHero/Dashboard等の最終監査は継続 -->
- [~] `primary` / `reward` / `dawn` / `dusk` の曙用hexを詰め直し、黄土色化・ラベンダーと黄の温度割れ・彩度段差を潰す <!-- 担当: Codex, 進捗: 2026-06-02。primary/duskは白背景へ馴染む淡い紫へ、rewardは昨日カードのライトとして使える柔らかい金へ調整。`liminalAccentLight(in:)` を追加し、曙だけDailyReflectionCardのリング中心/metrics/fact周辺に朝ライトを差す -->
- [x] 曙スクショ監査: ProfileHero / DailyReflectionCard / CurrentChapterCard / Dashboard hero / 浮遊チップを light/dark 並列で確認し、曙だけ見づらい箇所を修正する <!-- 担当: Codex, 完了: 2026-06-02。Simulator iPhone 17 Proで `-LiminalogInitialTodayPage yesterday` / `-LiminalogInitialRootTab {profile,dashboard,calendar,friends}` を使い、DailyReflectionCard / CurrentChapterCard / ProfileHero / Dashboard hero / Calendar / Friends一覧を曙/宵で撮影確認。曙だけ文字が消える・面が沈む箇所はなし。P2の深い画面/モーダル監査は継続 -->

### P2: 横展開 + 文字/影

- [~] 全画面監査: グラデ直乗り＋不透明下地なしの半透明を洗い出し docs 末尾に表で追記してから `liminalCanvasChip`/`liminalGlassFill` 化（カード内の半透明は触らない）<!-- 担当: Codex, 進捗: 2026-06-02。docs/theme-system §8に主要タブ監査表を追加。Today/Profile/Dashboard/Calendar/Friendsの曙/宵スクショ確認済み。深い詳細画面/作成編集Sheet/友達詳細は継続 -->
- [ ] `emphasis`/`effects` を必要箇所へ配線し実機で値を詰める <!-- 担当: 未定 -->

### P3: ユーザー選択テーマ（将来・今回スコープ外）

- [ ] `@Environment(\.liminalTheme)` 注入 + 設定UI + `UserSettings` 保存 <!-- 担当: 未定, 依存: P2 -->

### 先行実装済み（Claude / 2026-06-02・巻き戻さない）

- [x] `liminalCanvasChip` modifier 追加 + `CurrentChapterCard` active リボンへ適用（実機でライト改善を確認）<!-- 担当: Claude, 完了: 2026-06-02。P1 で modifier 中身を型経由へ整理する前提。スクショ artifacts/{light,dark}-home-{before,after}.png -->

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
| 2026-06-01 | Codex | Phase0-3品質対応: DailyCardEngineをViewから抽出し、称号/本文整合・メタ文言除去・休息除外fact stripを実装。月カレンダーのスコア数値をミニリング化。VisibilityPresetをdocs/04 §4.5設計へ拡張し built-in seed/重複統合を実装。CloudKitSyncCoordinatorのアカウント状態監視土台を追加。追加品質対応としてVisibilityPreset seedの不要なupdatedAt更新を抑制し、built-in seed/重複統合/カスタム非統合テストへ更新。検証: `xcodebuild test -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（35 tests / 11 suites）。iOS実機向け `build-for-testing` も `CODE_SIGNING_ALLOWED=NO` で成功。 |

新規タスクの追加・実装完了・設計変更を時系列で記録。**日付は ISO 形式（YYYY-MM-DD）で。**

| 日付 | 担当 | 内容 |
|---|---|---|
| 2026-06-02 | Codex | P2-4/P2-5 今日タイムラインの静けさ調整を実施。`DayOverviewBar` から「24時間バー」見出しを削除し、今日ページ/友達読み取り専用タイムラインの `実績/予定` segmented Picker を下線付き inline toggle へ降格。リストは従来どおり `TimelineTab.actual` をデフォルトに維持。検証: `rg` で `TimelineView.swift` 内に `24時間バー` 表示文字列・`Picker("表示")`・`.pickerStyle(.segmented)` が残っていないことを確認、`git diff --check` 成功、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功、Simulator iPhone 17 Proで署名あり `xcodebuild ... build` 成功。`/private/tmp/liminalog-daybreak-timeline-inline-top.png` と `/private/tmp/liminalog-dusk-timeline-inline-top.png` を撮影し、light/darkとも文字消え・過度な主張なしを確認。CSV書き出しは不要・スコープ外を維持。 |
| 2026-06-02 | Codex | P3-9 友達タブIA調整を完了。`FriendsView` で「今の友達」ステータスリストをランキングより先に配置し、ランキングカードは幅・余白・スコア文字・面/枠線の強さを落として競争を従にした。友達行は @handle を主情報に出さず、名前・現在ステータス・ひとことを主役に維持。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功、Simulator iPhone 17 Proで署名あり `xcodebuild ... build` 成功。`/private/tmp/liminalog-daybreak-friends-p3-9.png` と `/private/tmp/liminalog-dusk-friends-p3-9.png` を撮影し、light/darkともリスト主役・ランキング従・文字消えなしを確認。CSV書き出しは不要・スコープ外を維持。 |
| 2026-06-02 | Codex | テーマP1.5/P2監査を主要タブへ拡張。Simulator iPhone 17 Proで `-LiminalogInitialRootTab profile/dashboard/calendar/friends` と `-LiminalogInitialTodayPage yesterday` を使い、曙/宵の ProfileHero・Dashboard hero・Calendar月表示・Friends一覧・Today/DailyReflectionCard を撮影確認。スクショ: `/private/tmp/liminalog-daybreak-profile.png`, `/private/tmp/liminalog-dusk-profile.png`, `/private/tmp/liminalog-daybreak-dashboard.png`, `/private/tmp/liminalog-dusk-dashboard.png`, `/private/tmp/liminalog-daybreak-calendar.png`, `/private/tmp/liminalog-dusk-calendar.png`, `/private/tmp/liminalog-daybreak-friends.png`, `/private/tmp/liminalog-dusk-friends.png`。主要タブでは曙だけ文字が消える/面が沈む問題は見つからず、P1.5の名指し監査は完了。P2全画面監査は深い詳細画面・作成編集Sheet・友達詳細を継続。検証: スクショ監査のみ、コード変更なし。CSV書き出しは不要・スコープ外を維持。 |
| 2026-06-02 | Codex | 曙の色設計をユーザー方針に合わせて「白に馴染む薄い面 + 要所の朝ライト」へ再調整。`LiminalThemeCatalog.daybreak` は白寄りの canvas/surface/gradient に戻しつつ divider/treatment を薄くし、`reward` を昨日カードのライト用の柔らかい金へ更新。`liminalAccentLight(in:)` を追加し、darkではno-op、lightだけ DailyReflectionCard のカード面/共有メトリック/fact pill/リング中央に控えめな朝ライトを差すようにした。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功、Simulator iPhone 17 Proで署名あり `xcodebuild ... build` 成功。`/private/tmp/liminalog-daybreak-yesterday.png` と `/private/tmp/liminalog-dusk-yesterday.png` を撮影し、DailyReflectionCardのlight/darkで文字消え・過剰な濁り・曙だけ平たい状態がないことを確認。CSV書き出しは不要・スコープ外を維持。 |
| 2026-06-02 | Codex | テーマ定義型リファクタ P0/P1 を実装。`LiminalThemeDefinition` / `LiminalPalette` / `LiminalThemeCatalog` と surface/glass treatment を追加し、既存 `LiminalTheme.primary` 等のfacadeは保ったまま内部解決をカタログ経由へ移行。`liminalCanvasChip` は treatment 読みに変更し、`liminalGlassFill(in:)` を新設して DailyReflectionCard の白フロスト系ピル/パネルを置換（Canvasリング下地・grainは意匠として維持）。曙は初期改善として canvas/surface/divider/gradient と primary/reward/dawn/dusk を更新し、黄土色化・黄×ラベンダーの温度割れを緩和。プロフィールカードは light/dark 背景とカード内文字色を持たせ、宵で白地+白文字になる事故を修正。DEBUG QA 用に `-LiminalogInitialRootTab profile` / `SIMCTL_CHILD_LiminalogInitialRootTab=profile` で初期タブを指定できる導線を追加。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。シミュレータはライトTodayのスクショを確認したが、途中でCoreSimulatorServiceが落ちたためProfileHeroのlight/dark並列スクショ監査は継続タスクとして残す。 |
| 2026-06-01 | Codex | デイリーカード用のカテゴリメタ情報を追加。`Category.dailyCardIntentRawValue` / `isDailyCardSleepCategory` をCloudKit互換のデフォルト付きプロパティとして持たせ、カテゴリ作成/編集UIから「増やしたい/減らしたい/中立」と「睡眠として扱う」を保存できるようにした。デフォルト「睡眠」カテゴリは新規seed時に睡眠タグ付きにし、DailyCardEngineでは明示睡眠タグを休息除外へ反映、増減宣言に応じて逸脱signalの称号/本文を切り替える。docs/04とDEBUG開発ストア世代も更新。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData -only-testing:LiminalogTests/DailyCardEngineTests -only-testing:LiminalogTests/CategoryMetadataTests` 成功（10 tests / 2 suites）、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（74 tests / 19 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | Phase 2 アンロック条件判定を累計スコア専用から `UnlockMetrics` ベースへ拡張。`UnlockItem` に `requirementKindRawValue` / `requiredValue` を追加し、マスターseedの条件更新、`UnlockStore.refresh(metrics:)`、プロフィール集計からの記録日数・累計記録時間・ストリーク・朝/深夜記録日数・カテゴリ種類数算出、「次の解放」カードの条件別残り表示へ接続した。DEBUG開発ストア世代も `2026060105` へ更新。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData -only-testing:LiminalogTests/UnlockRulesTests -only-testing:LiminalogTests/ProfileUnlockTargetsTests` 成功（8 tests / 2 suites）、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（69 tests / 18 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | Phase 0 DEBUG seed隔離を完了。`ChapterStore` に残っていた preview/dev runtime seed本体を `PreviewRuntimeSeedSupport` へ移し、`ChapterStore` はDEBUG専用の薄い入口だけに縮小。`RootTabView` の判定は `PreviewSupport.runtimeSeedRequest()` に集約し、UserDefaults / 起動引数 / 環境変数で `LiminalogSeedPreviewData` または `LiminalogSeedDevData` が明示された場合だけ投入する。通常の実機DEBUG起動ではデモ予定/実績が入らないことをテスト化し、docs/01〜03の該当記述も更新。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData -only-testing:LiminalogTests/ChapterStoreTests` 成功（10 tests / 1 suite）、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（68 tests / 18 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | Phase 0 Swift Package化前の小掃除として、Widget側に残っていた `Color(hex:)` のfile-private重複実装を削除。`LiminalogLiveActivityWidget` と `RecordingGridWidget` は新規 `WidgetColor+Hex.swift` の `Color.cachedHex` を使うようにし、Widget target内でhexパース/キャッシュを1箇所へ統一した。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（67 tests / 18 suites）。 |
| 2026-06-01 | Codex | DailyCardEngineのペルソナ/称号判定をdocs/12 §6へ拡張。4クロノタイプ×3集中形の12称号表、docs/12 §6.7コピーのmessage配列、予定一致/風まかせ/ガチ充電/行方不明の床・レア型、初記録/久々/いつもより増減signalとfact stripを実装し、日付seedで安定して文言を選ぶようにした。検出器カタログ全12型のうち、体感換算・気分・友達・ユーザー宣言・昨日と同型回避は後続に残す。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData -only-testing:LiminalogTests/DailyCardEngineTests` 成功（5 tests / 1 suite）、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（67 tests / 18 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | 週間Dashboardの既存カテゴリ構成カードを「カテゴリ別トータル」へ調整。期間内カテゴリ合計を上部の構成バーだけでなく、各カテゴリ行の横棒・時間・割合で比較できるようにした。`DashboardCardKey.categoryShare` の表示名もカスタマイズSheet上で実態に合う「カテゴリ別トータル」へ変更。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（65 tests / 18 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | `DashboardCustomizeSheet` を追加し、Dashboard上部のスライダーアイコンから現在期間のカードを編集できるようにした。カードは `DashboardCardKey` のtitle/iconを使って一覧化し、Toggleで表示ON/OFF、`EditButton` + `onMove` で並び替え、リセットボタンで期間別default orderへ戻せる。表示OFF状態は新規 `UserSettings.dashboardHiddenCardKeys` に保存し、`dashboardCardOrder` は表示/非表示を問わない順序として維持。`DashboardPeriodContent` は非表示キーを除外しつつサマリーカードだけは常に残すため、空Dashboardにはならない。開発ストアのスキーマ確認用に `SharedModelContainer.currentDevelopmentStoreVersion` と `ZUSERSETTINGS` 必須列も更新。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData -only-testing:LiminalogTests/DashboardCardKeyTests -only-testing:LiminalogTests/SeedCoordinatorTests` 成功（5 tests / 2 suites）、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（65 tests / 18 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | Dashboardカード数値用の共通 `DashboardCountUpModifier` を追加。`Animatable` な数値ラベルをhidden元テキストへoverlayすることで最終文字幅を保ち、スコアリング、ヒーローpill、メトリックタイル、スコア内訳、カテゴリ構成、時間帯別傾向、先週比、最近の記録の主要数値を0から現在値へカウントアップするようにした。アクセシビリティのReduce Motionでは即時表示へ切り替え、VoiceOverには最終値だけを渡す。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（64 tests / 18 suites）。 |
| 2026-06-01 | Codex | Dashboard共通基盤として `DashboardCardKey` を追加し、全カードID・期間別default order・保存順の正規化を実装。`DashboardPeriodContent` は `UserSettings.dashboardCardOrder` を読み、無効キー/重複キー/期間に存在しないカードを除外し、不足カードをdefault orderで補完して描画するようにした。`dashboardCardOrder` は既存モデル項目のため新規マイグレーションは不要。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData -only-testing:LiminalogTests/DashboardCardKeyTests -only-testing:LiminalogTests/SeedCoordinatorTests` 成功（4 tests / 2 suites）、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（64 tests / 18 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | 週間Dashboardに `DashboardTimeOfDayTrendCard` と `DashboardPeriodDeltaCard` を追加。既存の `DashboardTimeOfDaySummary` / `DashboardPeriodDeltaSummary` を表示へ接続し、朝/昼/夜の支配時間帯・比率・時間バー、平均スコア/実績時間/予定時間/一致時間/スコア日の先週比と中央基準の差分バーを表示するようにした。前週比較に必要な前期間の予定/実績も `DashboardPeriodContent` の Query 範囲へ含め、週/月の前期間境界をテストで固定。新規カードは `DashboardWeeklyInsightCards.swift` へ分離し、DashboardView肥大化を抑制。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData -only-testing:LiminalogTests/DashboardAnalyticsTests -only-testing:LiminalogTests/DashboardPeriodTests` 成功（7 tests / 2 suites）、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（62 tests / 17 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | 装飾アイテム経済のレンダリング未チェック項目を現在実装に照合。プロフィール画像フレームは `ProfilePhotoView` が `ProfileIconFrameView` を外周に重ね、名前バッジは `EquippedBadgePill`、ストリーク炎は `ProfileStatsRow` の装着中 `ProfileStreakIconStyle` で表示済みだったため、AI_TASKS上で完了へ整理。未解放IDのfallbackと装着可能IDの制御は直前の `ProfileDecorationUnlocksTests` とフルテストで検証済み。CSV書き出しは不要・スコープ外を維持。検証: `git diff --check` 成功。 |
| 2026-06-01 | Codex | プロフィール画面に「次の解放」セクションを追加。`ProfileUnlockTargetCatalog` で `UnlockItem.unlockedAt == nil` の装着対象アイテムを残り累計スコア昇順に並べ、上位3件を `ProfileView` に進捗カードとして表示するようにした。各カードは種類、残りpt、進捗率、アイコン色を表示し、全解放済みの場合は完了状態カードへ切り替える。CSV書き出しは不要・スコープ外のまま維持。検証: `git diff --check` 成功、`xcodebuild test -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData -only-testing:LiminalogTests/ProfileDecorationUnlocksTests -only-testing:LiminalogTests/ProfileUnlockTargetsTests` 成功（4 tests / 2 suites）、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（61 tests / 17 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | プロフィール装備UIを `UnlockItem.unlockedAt` ベースへ接続。`ProfileDecorationUnlocks` を追加し、`starter` / `halo` / `flame` / `clean` のdefault装備は常時利用可能、その他は解放済み `UnlockItem.targetID` のみ選択可能にした。プロフィール表示・編集初期値・保存時のいずれでもロック済み/古い装備IDをdefaultへ戻し、フレーム/ストリーク/カード選択UIはロック表示 + 選択不可に統一。Phase 1の実績直判定バッジ配列は `UnlockItem` マスターデータ由来の `ProfileBadgeCatalog` へ差し替え、進捗表示も `UnlockRules.progress` へ寄せた。CSV書き出しは引き続き不要・スコープ外。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功、`xcodebuild test -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData -only-testing:LiminalogTests/ProfileDecorationUnlocksTests` 成功（2 tests / 1 suite）、`xcodebuild test-without-building -scheme Liminalog -destination 'id=72181B45-004C-49C5-931F-AE873C13CD9C' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（59 tests / 16 suites）。 |
| 2026-06-01 | Codex | Phase 2 アンロック基盤を実装。`UnlockItem` を CloudKit 同期対象モデルに追加し、DEBUG開発ストア世代を `2026060103` へ更新。`UnlockCatalog` に装着可能アイテム26件をseedし、仕様書の1年解放ペースを「合格ライン60pt/日」から累計スコア閾値へ逆算。`UnlockRules` は累計スコアから解放key/次アイテム/進捗を算出し、`UnlockStore` は起動時seed、プロフィール集計時refresh、重複key統合、最古 `unlockedAt` 保持、解放後非失効を担う。docs/04 のモデル記述も実装に同期。プロフィール画面の進捗カード/Gallery/解放演出UIはClaude担当として残す。検証: `git diff --check` 成功、`xcodebuild test-without-building -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（57 tests / 15 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | Phase 2 Dashboard拡充の集計ロジックを追加。`DashboardTimeOfDaySummary` で朝(5:00-12:00)・昼(12:00-18:00)・夜(18:00-翌5:00)の実績時間割合と支配時間帯を算出し、日跨ぎ/active Chapter/期間クリップに対応。`DashboardPeriodDeltaSummary` で現期間と前期間の平均スコア、実績時間、予定時間、一致時間、スコア対象日数の差分と増減率を算出する。表示UI（時間帯別傾向/先週比差分バー）はClaude担当として残す。検証: `git diff --check` 成功、`xcodebuild test-without-building -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（52 tests / 14 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | ユーザー判断によりCSV書き出しをリリーススコープ外へ変更し、作成途中のCSVエクスポータ案は破棄。代わりにリリース品質の検証補強として `TimelineBarLayout` を追加し、24時間バーの位置/幅/アイコン閾値をテスト可能な純粋ロジックへ分離。`TimelineDisplayTests` で読み取り専用Timelineの前日跨ぎクリップ、短時間記録、5分未満gap抑制、バー位置計算を固定。既存のScoreCalculator日跨ぎテストもAI_TASKS上で完了扱いへ整理。検証: `git diff --check` 成功、`xcodebuild test-without-building -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（48 tests / 13 suites）、`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | Phase 3 カテゴリマッピング基盤を実装。`FriendCategoryMapping` SwiftDataモデルを追加し、`LiminalogSchemaV1` / `SharedModelContainer` / Preview schema に登録、DEBUG開発ストア世代を `2026060102` へ更新。友達共有スナップショットには任意の `categoryID` を追加し、通常公開時はカテゴリ対応に使えるようにしつつ、`freeTimeOnly` の予定では categoryID も nil にして匿名化を維持。`FriendCategoryMappingResolver` で共有予定/実績からカテゴリ記述子を抽出し、同名のデフォルトカテゴリだけを自動マッピングする。docs/04のスナップショット実装メモも同期。多対一モデル保存、カテゴリ記述子抽出、自動マッピングが既存手動設定/カスタムカテゴリを上書きしないことをテスト化。検証: `xcodebuild test -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（44 tests / 12 suites）。手動マッピングUI、比較表示時のカラー統一スイッチ、未マッピング促しはClaude/UIタスクとして継続。 |
| 2026-06-01 | Codex | Phase 3 公開設定フィルター品質対応。友達共有用の `FriendSharedPlanSnapshot.snapshots` / `FriendSharedActivitySnapshot.snapshots` に `VisibilityPreset` を任意指定できるようにし、既存の `isPublic` 境界に加えて publishMode none / 旧level none、カテゴリ除外、メモ・気分・場所の隠蔽、予定の空き時間のみ（タイトル/カテゴリ/色を「予定あり」へ匿名化）を適用。写真は共有スナップショットにフィールドがないため現時点で漏れない。`PublishMode.nextDay` の実配信タイミングと CKShare 実送受信は Developer/CloudKit 環境が必要な別タスクとして残す。検証: `xcodebuild test -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/LiminalogDerivedData` 成功（41 tests / 11 suites）。`xcodebuild -scheme Liminalog -destination generic/platform=iOS -derivedDataPath /private/tmp/LiminalogDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing` 成功。 |
| 2026-06-01 | Codex | liminal UI 着手（branch `codex/liminal-ui-overhaul`）。(1) `DailyReflectionCard`（二重24hリング・twilightカード・グレイン/glow・「明日はどうする？」CTA）を昨日ページに追加。(2) twilight 視覚システムを全画面適用：`LiminalTheme` 共有化＋`preferredColorScheme(.dark)`固定＋テーマトークン（Primary `#C9A7FF`/Reward `#FFE3A3`）＋視認性正規化 `liminalReadableDataColor`(WCAG≥3:1・色相保持) を `Category.displayColor` として全データvizに配線。island問題解消。**Claudeレビュー: ビジュアル/テーマ/視認性は docs/13 §2/§7 通りで合格。ただしカード中身（ペルソナ）が暫定スタブのまま＝睡眠が見出しに（§5原則2違反）＋声が優しいコーチ口調で自虐トーン未反映。是正は §7.7.1 に起票。** |
| 2026-05-31 | Claude | 設計フェーズ大幅前進。docs/12（デイリーカード&コンテンツエンジン）・docs/13（ビジュアル・アイデンティティ）を新規作成。コア論点を一気通貫で確定: (1)プロダクトの肝は「予定+スコア=moat」で薄めない。摩擦を消すのでなくコスト↓×payoff↑。(2)ターゲット=ショート漬けZ世代。気づき≠行動変容で、振り返り→明日の予定への1タップ橋渡しが核。(3)1日の総括「デイリーカード」を成長エンジン兼フックに据える(シェア→流入→比較)。単日=カード/複数日=統計の境界確定(統計タブは単日退避し傾向の鏡へ)。10 §3.4 DayDigest保留を解消(=カードに統合)。(4)楽しさはAIでなく「検出器×声×バリエーション」(決定論・ゼロコスト)。中立デフォルト(善悪判定しない)・見出し=ルーティン逸脱・カテゴリ意味非依存(睡眠もパターン検出)の3原則。逸脱エンジン/睡眠検出の計算仕様を昼夜逆転・無記録・カオスまでstress test。(5)ペルソナ称号(形ベース12×レア×活動スロット×2階建て×コレクション)・自虐トーン確定・ネーミング原則(面白い∧伝わる)。(6)世界観=liminal(予定と実績のあいだ)。トワイライト/ダークファースト・二重24時間リング(gap可視化)をsignatureに。戦略: カード先行→solo配布→拡散測定→その後 友達インフラ。タスクは §7.7/§7.8 に起票。 |
| 2026-05-31 | Claude | 今日タブ/カレンダーのパフォーマンス改善一式。原因と対処: (1) カレンダー横ページングが毎描画で42日×3ページ分のスコア再計算をしていた→ページデータをメモ化し refresh 時のみ計算。(2) カレンダー/今日タブの月・日ページングを `TabView(.page)`(UIPageViewController) から `ScrollView+LazyHStack/HStack+.scrollTargetBehavior(.paging)` に統一（横スワイプ三重ネストのジェスチャー競合を解消）。(3) `Color(hex:)` を `Color.cachedHex` でキャッシュ化（毎描画の Scanner パースを除去・アプリ全体に効く）。(4) `TimelineView` の `TickClock` を 1秒→60秒（24hバーの毎秒全再構築を停止。ライブ秒は CurrentChapterCard 担当）。(5) `TimelineView.body` のエントリ計算(フィルタ+gapマージ)を1描画1回に。(6) 日タブを `LazyHStack` 化し save カスケード再描画を表示中ページのみに限定。(7) カテゴリセット切替の `setEnabledCategorySetID`(WidgetCenter+ActivityKit+UserDefaults) をデバウンス、`defaults.synchronize()` 撤去、`startChapter` を `reloadAllTimelines`→`reloadRecordingGridWidget` に。**重要な学び: 体感パフォーマンスは Debug シミュレータでは実機Releaseの5〜10倍遅く判断を誤る。最終的に Release ビルドで「全く気にならない」レベルに。今後 perf は Release で確認すること。** |
| 2026-05-30 | Codex | 友達の日別詳細に、共有実績の読み取り専用タイムラインを追加。`Friend` に `sharedActivitiesJSON` を追加し、`Chapter.isPublic == true` の実績だけを `FriendSharedActivitySnapshot` として受け取る設計にした。友達カレンダーの日付セルを開くと、24時間バーは予定/実績の2段、下は実績/予定セグメント切替、時間レール付きカードリストで表示され、自分のTodayタイムラインに近い見た目で確認できる。編集・削除・追加はできない。DEBUG seedにはMika/Sora/Ren/Yuiの共有実績を追加し、シミュレータでMika 5/30の実績/予定タブ表示を確認済み。プロフィールカード右上でカード装飾マークがカレンダー/お気に入りボタンと重なっていたため、友達プロフィールヒーローからカード装飾マークだけ削除した。 |
| 2026-05-30 | Codex | 友達の日別詳細UIを微修正。下部に出していた「共有予定」は意味が曖昧で、実際には重要予定の俯瞰に近かったため削除し、`showsInCalendarAsImportant` の予定だけを「重要な予定」として日付ヘッダー直下に移動した。時間指定予定の詳細確認はタイムラインの予定タブに集約。24時間バーは背景だけだと囲いが弱くカード内で浮いて見えたため、薄い枠線を追加してひとまとまりのバーとして認識しやすくした。シミュレータでMika 5/30の日別画面を確認済み。 |
| 2026-05-30 | Codex | 友達の日別24時間バーをToday/カレンダー側の `DayOverviewBar` と見比べて再調整。友達側はタイムライン全体カードの中にバーだけを置いていたため、自分側と同じ「24時間バー」ヘッダー付きの独立カード構造に変更し、行間、ラベル幅、角丸、3時間目盛り、15分以上/幅24pt以上のアイコン表示ルールを合わせた。これに伴い、友達タイムライン全体の大きな白カード背景は外し、24時間バー・セグメント・リストが自分側と同じ階層感で並ぶようにした。友達詳細の現在ステータスカードは、アイコンだけでなくカード背景と枠線にも `currentStatusColorHex` を使い、カテゴリ色が画面上で明確に伝わるように変更。シミュレータでToday側バー、Mika詳細ステータス、Mika 5/30日別バーを確認済み。 |
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
| 2026-05-26 | Codex | 編集ロック実装。予定は明日以降のみ新規追加・内容/カテゴリ/時間/重要フラグ変更・削除可、今日以前はメモ/公開設定のみ可。実績は当日中のみ時間/カテゴリ/削除可、前日以前はメモ/場所/公開設定のみ可（2026-05-31に気分UI廃止へ更新）。`ChapterStore` 側にも保存/削除ガードを追加し、UIだけでなくデータ層でも公平性を守る |
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
| 2026-05-30 | Codex | カレンダー/友達カレンダーの日別詳細を、押し込み遷移ではなく下からのモーダル表示へ変更。月グリッドの日付セルと複数日バーは `NavigationLink` をやめ、親の `selectedDay` を更新して `.sheet(item:)` + `NavigationStack` で日別画面を開く構造にした。検索結果から開く場合は検索シートを閉じた次の runloop で日別モーダルを開き、二重 sheet を避ける。カレンダー側の日別画面は既存の左右スワイプ日付移動をモーダル内でも維持し、友達の日別画面にも同じ左右スワイプ日付移動を追加。カレンダータブの日別タイムラインは外側のカードラップを外し、友達タブと同じく `24時間バー` と下のタイムラインが別カードとして見える構造に変更 |
| 2026-05-30 | Codex | 日別モーダルの日付移動を TimeTree 風の横スライド体験へ調整。`CalendarDayPagerSheet` / `FriendSharedCalendarDayPagerSheet` を追加し、モーダル内に前日・当日・翌日の3ページだけを持つ `TabView(.page)` を配置。スワイプ中はカードが横にずれて切り替わり、切り替え完了後に基準日を更新して中央ページへ無アニメーションで再固定するため、日付をいくら進めてもView数は増えない。ページングと二重に反応しないよう、モーダル内の `CalendarDayView` / `FriendSharedCalendarDayView` では旧DragGestureの日付差し替えを無効化した |
| 2026-05-30 | Codex | 日別モーダルの横スライド中にナビゲーションバーが一瞬増える不具合を修正。原因は `TabView(.page)` の各ページ内に toolbar / navigationTitle が残っており、スワイプ途中に隣接ページのナビゲーション要素も同時評価されること。`CalendarDayView` はページャー内では `showsNavigationControls: false` にし、戻る・公開設定・追加メニューを `CalendarDayPagerSheet` 側の固定toolbarへ集約。友達日別もページ内の navigationTitle を無効化し、`FriendSharedCalendarDayPagerSheet` 側に1つだけタイトルを持たせた。これによりページカードだけが横に動き、上部バーは吸着時も増減しない構造になった |
| 2026-05-30 | Codex | 月カレンダーの左右移動も TimeTree 風の横スライドへ変更。カレンダータブ/友達カレンダーとも、月グリッド部分を前月・表示月・翌月の3ページを持つ `TabView(.page)` に変更し、スワイプ中は月のカード面だけが横に移動する。スワイプ完了後は `visibleMonth` を移動先の月初に更新し、`selectedMonthOffset` を無アニメーションで0へ戻すため、月を進め続けてもView数は増えない。上部の年月ラベルと曜日ヘッダーは固定にして、日別モーダルで対応したナビゲーションバー増殖と同種のヘッダー重複を避ける設計 |
| 2026-05-30 | Codex | 月カレンダーは縦の無限スクロールではなく「1ヶ月を一画面で見渡す」方針に寄せた。`CalendarMonthDayCell.cellHeight` を 120pt から 92pt へ縮小し、カレンダー/友達カレンダーの月グリッド上下余白も 12pt から 8pt へ圧縮。6週表示でもグリッド全体が画面内に収まりやすくなり、月スワイプ時に1枚のカレンダー面として把握しやすい。予定ラベルは6pt設定なら約4行程度残る想定で、過密日は従来通り `+N件` 表示に逃がす |
| 2026-05-30 | Codex | 月カレンダーの週数を可変化。これまでは常に42日/6週を描画していたが、5週で収まる月は35日/5週だけ描画し、不要な前後月の週を削るようにした。6週が必要な月は従来の42日/6週を維持。セル高さは6週月=92pt、5週月=110ptに分岐し、5週月では削った1週分を各日の縦幅へ配分する。カレンダータブと友達カレンダーの両方で同じ計算を使い、月全体の俯瞰性と予定ラベルの表示余地を両立する設計 |
| 2026-05-30 | Codex | 週数可変化に合わせて月カレンダーの縦スクロールを廃止。カレンダータブ/友達カレンダーの月ページ内で `ScrollView` を使わず、`TabView(.page)` の各ページは `VStack + Spacer` で月グリッドを上部固定表示する構造にした。これにより月の左右スワイプは維持しつつ、1ヶ月をスクロールせず固定面として見渡せる。友達カレンダー側の説明カードは固定月面の表示領域を圧迫するため削除し、カレンダー本体の視認性を優先 |
| 2026-05-31 | Codex | 友達カレンダー上部の左向き月移動ボタンを削除。友達側はプロフィールからカレンダーを開く文脈で左矢印が戻る操作と紛らわしく、月移動は横スワイプと年月ピッカーで足りるため表示しない方針。年月ラベルの中央配置は崩さないよう、左側には透明の44ptスペースだけ残し、検索ボタンとの左右バランスを維持 |
| 2026-05-31 | Codex | プロフィールカラー設定を体験から削除。反映範囲が少なく、友達カレンダーの今日枠など意味のあるUIが人によって色違いになる混乱があったため、編集画面のカラーSectionを撤去し、招待リンク/QRからも `color` query を送らないようにした。プロフィールカードの装飾色は独立したプロフィールカラーではなく、装備中アイコンフレームやカード装飾の色から派生。友達カレンダーの今日枠は共通の `Color.accentColor` に統一。`UserSettings.profileAccentColorHex` は既存DB互換のためモデル上は残すが、UI/共有フローでは使用しない |
| 2026-05-31 | Codex | 統計タブをリリース候補UIへ再設計。従来のシンプルな集計リストでは満足感が薄かったため、上部にスコアリング・期間・主役カテゴリ・記録時間をまとめたヒーローカードを置き、スコアリング、ミニ推移、リズムストリップ、メトリックタイル、スコア内訳、カテゴリ構成、24時間リズム、スコア推移、最近の記録へ再構成した。プロフィールで好評だった「見ていて楽しいカード体験」に寄せつつ、色だけでなくアイコン/テキスト/順位/数値で意味が取れるようにした。集計は `@Query` の Chapter/Plan から期間ごとに算出し、日/週/月/年の切替は独自のアイコン付きピッカーに変更。年スコア推移は表示負荷と密度を抑えるため最大24本程度に間引く。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功、同条件の `test` でSwift Testing 30件成功、シミュレータへinstall/launchして統計タブのヒーローカード・メトリック・内訳カードの表示をスクリーンショットで確認 |
| 2026-05-31 | Codex | 統計タブの追加FB反映。スコア内訳は2本の進捗バーではなく、`カテゴリ貢献点(80%) + 時間軸貢献点(20%) = 合計100点` が一目で分かる1本の積み上げバーへ変更。日間表示ではトップカード内のミニ推移を非表示にしつつ、週/月/年とカード高さが大きく変わらないよう透明スペースで余白を維持。日本語が潰れて見える箇所は `.black` を避けて `.bold` 寄りへ調整。統計もランキングと同じく対象期間を選べるよう、日/週は日付Wheel、月は年+月Wheel、年は年Wheelの期間選択シートを追加。週間は従来の直近7日ではなく、ランキングと合わせて選択日を含むカレンダー週に変更した。検証: `git diff --check` 成功、`xcodebuild ... build-for-testing` 成功、`xcodebuild ... test` でSwift Testing 30件成功、シミュレータ上で日間/週間の統計表示と一本化したスコア内訳を確認 |
| 2026-05-31 | Codex | 統計タブのスコア内訳FBを再反映。スコア計算の配点は従来仕様どおり `カテゴリ80% + 時間軸20%` に維持しつつ、内訳UIは「カテゴリ達成率」「時間軸一致率」をそれぞれ100%基準のバーで表示する形に変更。下部に `カテゴリxx%×80% + 時間軸xx%×20% = 合計pt` の小さな計算式を出し、バーが貢献点ではなく各指標そのものを示すことが分かるようにした。統計の期間切替はTodayタブと同じく `TabView(.page)` に載せ替え、日/週/月/年ボタンだけでなく横スワイプでも切り替え可能にした。検証: `git diff --check` 成功、`xcodebuild ... build-for-testing` 成功。`xcodebuild ... test -only-testing:LiminalogTests/ScoreCalculatorTests -only-testing:LiminalogTests/DashboardPeriodTests` はビルド後のシミュレータ実行待ちで返らなかったため中断。シミュレータへinstall/launchし、統計タブの日間表示で2本バー・80/20配点・計算式の表示をスクリーンショット確認 |
| 2026-05-31 | Codex | DEBUG用の実績ダミーデータがタイムラインを壊す問題を修正。原因は `seedDevSampleChaptersIfNeeded` が今日の固定実績サンプルを作った後、別途「30分前から記録中」の趣味Chapterを追加しており、深夜〜朝に起動すると `睡眠 0:00-7:00` と active 趣味が重なること。`LiminalogSeedDevData` が有効なDEBUG時だけ開発用Chapter seedに世代を持たせ、世代更新時は既存Chapterを作り直す方針へ変更。今日の実績は予定seedと同じ24時間テンプレートから、0:00〜現在時刻までを順に生成し、現在時刻を含む1件だけを `endTime == nil` にする。これにより未来の実績と重複実績が入らず、App Store説明画像用のデモデータも安定して再生成できる。検証: `git diff --check` 成功、`xcodebuild ... build-for-testing` 成功。`xcodebuild ... test -only-testing:LiminalogTests/ChapterStoreTests` はビルド後のシミュレータ実行待ちで返らず中断。修正済みアプリを `-LiminalogSeedDevData -LiminalogSeedPreviewData` で起動し、App Group SQLiteで Chapter 重複0件・未来Chapter0件・active1件を確認、Todayタイムラインの表示もスクリーンショット確認 |
| 2026-05-31 | Codex | App Store説明画像/講師レビュー用に、DEBUG seedを5月全日デモへ拡張。`seedPreviewPlansIfNeeded` は現在月に重なるPlanBlockを世代更新で作り直し、5月1日〜31日の各日を時間つき予定で0:00〜24:00まで埋める。さらに時間つき重要予定（中間発表、歯医者、デイリー共有など）と、月跨ぎ/週跨ぎの時間未指定重要予定（連休プロジェクト、集中制作週間、展示準備、リリース準備など）を追加し、月カレンダーの横長バーや重要予定表示を見せられる構成にした。`seedDevSampleChaptersIfNeeded` は開発用Chapter seed世代を3へ上げ、5月1日から当日現在までの実績を再生成する。睡眠はDB上でも日付跨ぎChapterとして1件で保持し、日中の実績は日ごとのテンプレートでカテゴリを変化させる。今日分は未来実績を作らず、現在時刻を含む1件だけ `endTime == nil` にするため、タイムライン重複やactive複数を避ける。`RootTabView` では `LiminalogSeedDevData` 指定時にも予定seedを先に走らせ、実績だけ入って予定が古いままになる事故を避ける。Claude向け注意: `LiminalogSeedPreviewData` / `LiminalogSeedDevData` を付けたDEBUG起動では5月に重なる既存予定/既存実績をスクショ用に作り直す。通常保存ロジックではなくデモseed専用の挙動。検証: `git diff --check` 成功、`xcodebuild ... build-for-testing` 成功。targeted test はシミュレータ実行待ちで返らず中断。修正済みアプリを `-LiminalogSeedDevData YES` で起動し、App Group SQLiteで5月31日分の時間つき予定が各日86400秒、時間つき予定重複0、実績重複0、未来実績0、active1、日跨ぎ実績30件、重要予定15件を確認。Today画面スクリーンショットでも予定バーが24時間、実績バーが現在時刻まで表示されることを確認 |
| 2026-05-31 | Codex | 月カレンダーが異常に重くなる問題を修正。原因は `CalendarView` が通常表示時点で全 `PlanBlock` / 全 `Chapter` を `@Query` し、3ページ分の月グリッド各日セルで重要予定抽出とスコア計算のために全件filterを繰り返していたこと。`CalendarView` は `ModelContext.fetch` で前月/表示月/翌月グリッドを覆う表示範囲だけを取得し、日付ごとの重要予定と `ScoreSummary` を辞書へ事前計算して `CalendarMonthGrid` へ渡す構成に変更した。検索は大量候補を扱う専用機能なので、全予定 `@Query` を `CalendarPlanSearchSheet` の中へ隔離し、月表示の通常レンダリングから外した。時計tickではDB再fetchせず、月移動・表示開始・日別編集/検索終了後だけ表示範囲を再取得する。Claude向け注意: 完了済みの長期日跨ぎ実績は14日前までをlookbackして拾い、現在進行中の実績は別fetchで必ず拾う設計。数週間以上続く完了済みChapterをカレンダー月スコアに含めたい場合は、別途専用クエリ/モデル設計が必要。検証: `xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功、修正済みアプリをシミュレータへinstall/launchし、5月デモデータ入りのカレンダータブが固まらず表示されることをスクリーンショット確認 |
| 2026-05-31 | Codex | Claude §10.6 レビュー対応。最重要の FriendsView 並行UIスタックは一気に全廃せず、docs/11 の段階移行どおりタイムラインから正準化した。`TimelineView.swift` に `TimelineDisplaySnapshot` と `SharedTimelineReadOnlyView` を追加し、友達の `FriendSharedActivitySnapshot` / `FriendSharedPlanSnapshot` を表示用スナップショットへ変換して正準Timelineの24時間バー・時間レール・カード・ギャップ表示を使うように変更。`FriendsView.swift` から `FriendTimelineOverviewBar` / `FriendTimelineBarRow` / `FriendTimelineEntryCard` など友達専用タイムライン描画を削除し、約550行を削減。`Friend` のスナップショットキャッシュ方式は docs/04 に追記し、`Friend.score(for: .day)` が暫定的に `yesterdayScore` を返す理由もコードコメント化した。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功。ビルド済みアプリを `-LiminalogSeedDevData -LiminalogSeedDevFriends` で install/launch し、起動後もLiminalogプロセスが生存することとToday画面描画をスクリーンショット確認。`xcodebuild ... test` はビルド後のシミュレータ実行フェーズで返らず中断。残タスク: 友達月カレンダーと友達プロフィールHero/Stats/Collectionの正準化は次段階で対応 |
| 2026-05-31 | Codex | Claude §10.6 追加対応として、友達月カレンダーの並行UIスタックを正準 `CalendarMonthGrid` へ移行。`CalendarView.swift` に `CalendarDisplayPlan` / `CalendarDisplayScore` を追加し、自分の `PlanBlock` と友達の `FriendSharedPlanSnapshot` を同じ表示用データへ変換して月グリッド・日付セル・複数日バー・予定ラベル・スコアバッジを共通描画する構成にした。`FriendsView.swift` から `FriendSharedCalendarMonthGrid` / `FriendSharedCalendarWeekRow` / `FriendSharedCalendarDayCell` / `FriendSharedPlanLabel` / `FriendSharedMultiDayPlanBar` / `FriendCalendarContinuationShape` を削除。友達プロフィールカード右上のカレンダー/お気に入りボタンは44ptの標準タップ領域に広げ、前面レイヤーに出して導線を安定化。自己レビュー: 表示差分はデータ変換層のみで、編集不可の友達カレンダーも正準グリッドのread-only導線で問題なし。友達プロフィールHero/Stats/Collectionは自分用プロフィールと操作差（編集/共有 vs カレンダー/お気に入り/管理）が大きいため今回は無理に統合しない。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功。ビルド済みアプリを `-LiminalogSeedDevData -LiminalogSeedDevFriends` で install/launch し、友達タブ→Mika詳細→プロフィールカード右上カレンダーから「Mikaのカレンダー」が開き、正準月グリッドで表示されることをスクリーンショット確認 |
| 2026-05-31 | Codex | 全タブ軽量化リファクタリング。保険として作業前の `codex/phase0-next` を `666435c` まで push 済み、その地点から `codex/perf-all-tabs-refactor` を作成して実装。UI/UXは変えず、内部処理だけを対象にした。共通の `ScoreSnapshotLoader` を追加し、スコア計算用の Plan/Chapter fetch を日・週・月・年など必要な `DateInterval` に限定。`TimelineView` / `CalendarDayView` / `CurrentChapterCard` は日付範囲または active のみの `@Query` に変更。`DashboardView` は親の全件Queryをやめ、期間ページごとに範囲Query + `DashboardPeriodSnapshot` で集計を1回化。`ProfileView` は全Chapter/Planの常時購読と毎分再集計を撤去し、表示時に `ProfilePerformanceSnapshot` を作る方式へ変更（累計バッジ判定は従来どおり全履歴、スコア/ストリークは従来どおり365日ベース）。`FriendsView` は自分スコア計算を `ScoreSnapshotLoader` に寄せ、active Chapterだけを購読。`HomeView` は明日タブのgap判定を全予定Queryから範囲fetchへ変更。`Calendar.japanese` と `.map(Type.init(...))` 由来のActor isolation警告も解消。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功。最新ビルドを `-LiminalogSeedDevData -LiminalogSeedDevFriends` でinstall/launchし、Today/カレンダー/統計はスクリーンショット確認、友達は `liminalog://friend-invite` 経由でFriendsView起動確認。`xcodebuild ... test` はビルド後のシミュレータ実行フェーズで出力が止まったため中断。未追跡の `icon-mockups/` と `名称未設定フォルダ/` は触らない |
| 2026-05-31 | Codex | 画面の満足感・見やすさ改善として、Todayタブの「昨日」、カレンダーの1日表示、新しい予定追加画面をUI磨き込み。昨日タブは単なる数値カードではなく、スコアリング＋24時間リズムバー＋メトリックタイル＋カテゴリ比率で1日を受け取れる振り返り構成に変更。カレンダー1日表示は日付カード、スコアカード、重要予定カードの角丸・アクセント・情報密度を統一し、予定/重要/実績時間が視線に入りやすいよう整理。予定追加画面は標準 `Form` から専用カード型エディタへ変更し、上部プレビュー、カテゴリ色、時間/重要/公開状態のチップで「どんな予定を作っているか」が保存前に見えるようにした。保存条件・スコア公平性ロック・予定作成可否などの業務ロジックは既存のまま維持。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功、シミュレータへinstall/launchしてToday画面が従来どおり表示されることをスクリーンショット確認 |
| 2026-05-31 | Codex | チャプターの気分設定を廃止。`ChapterCreateSheet` / `ChapterEditSheet` から気分Sectionと `MoodPicker` を削除し、新規チャプターは `mood: nil` で保存する。既存Chapterの `mood` はDB互換のためモデルには残し、編集保存時も `chapter.mood` を保持して勝手に消さない。タイムラインカード/メタデータ表示からも気分を外し、補助情報はメモ・場所・公開状態中心へ整理。`ChapterStore` のロック文言、docs/08・docs/11、`liminalog_spec_v04.md` も「メモ/場所/公開設定」に更新 |
| 2026-05-31 | Codex | 友達タブのランキングで自分のカードだけ薄く見える問題を修正。原因は横ランキングの自分カードが `Button.disabled` になってSwiftUIのdisabled表示を受けていたことと、自分カードだけ `tertiarySystemGroupedBackground` を使っていたこと。自分カードも他ユーザーと同じ白系カード背景に統一し、タップ反応は `allowsHitTesting(false)` で止める形へ変更。自分の識別は薄化ではなくカテゴリ/プロフィール色の縁線で表現し、詳細ランキング行にも同じ縁線を適用 |
| 2026-05-31 | Codex | 予定作成画面などで使っていた心電図/時間軸っぽい下線装飾を、意味を持つグラフに見えない短い斜めアクセントへ統一。`DecorativeAccentStrip` を共通部品として追加し、予定作成、昨日レビュー、カレンダー1日表示、統計ヒーロー、プロフィールカード、友達カードの旧 `*RhythmStrip` を置き換えた。実データの24時間バーやタイムラインとは別物だと分かるよう、連続した横バー表現は廃止。合わせてECG系SF Symbolの残りも、実績時間は `stopwatch.fill`、統計の24時間リズム見出しは `chart.bar.fill` に変更 |
| 2026-05-31 | Codex | `DecorativeAccentStrip` の主張がまだ強かったため、左右対称の小さなピル/点アクセントだけに再調整。カード内の主要情報や24時間バーを邪魔しないよう、全体に横切る装飾や斜め線をやめ、低透明度のコーナー寄り装飾にした。カレンダー1日表示のヘッダーでは、日付下の `重要` / `予定` と並んでいた実績総時間ピル（stopwatch）を削除。実績時間は下のスコア/タイムライン文脈で確認できるため、日付直下は予定系の要約に絞る |
| 2026-05-31 | Codex | カレンダー表示設定の「過去予定を薄くするかどうか」を明示。既存の `calendarDimPastPlans` AppStorage と表示ロジックは維持し、設定画面の文言を `過去の予定を薄くする` に変更。打ち消し線とは独立して選べることが分かるよう、過去予定Sectionに補足文を追加した。デフォルト値は従来通りONで、既存ユーザーの表示は急に変えない |
| 2026-05-31 | Codex | 月カレンダーの日付またぎ予定の表示位置を修正。従来は週内の日付またぎ予定を単純な配列順=段番号として扱い、重なっていない予定でも2段目に置かれたり、週内の全日セルに同じ段数の空白を予約していた。`CalendarMultiDayPlacement` を追加し、週内で重ならない日付またぎ予定は同じレーンを再利用するgreedy配置へ変更。各日セルの空白予約も「その日に実際に重なる表示中の日付またぎレーン」だけを見るようにした。単日予定は同じ日内で `日付またぎ（オーバーレイ） → 時間未指定 → 時間指定` の優先順位になるよう、日セル内の単日予定を `isAllDay` 優先でソート |
| 2026-06-01 | Codex | Todayタブの月跨ぎ対策。DEBUG/デモ用 seed が現在月だけを対象にしていたため、2026-06-01 の「昨日」では 2026-05-31 の実績が不足し、月末の「明日」でも翌月1日の予定が不足し得た。`seedPreviewPlansIfNeeded` は現在月 + 前後1日を24時間予定で埋めるよう seed version を7へ更新。`seedDevSampleChaptersIfNeeded` は seed version 4 + `LiminalogDevSampleChapterSeedAnchorDay` を導入し、日付が変わったら既存の開発用Chapterを作り直す。これにより月初は前月最終日の実績、月末は翌月初日の予定が Today の昨日/明日タブに必ず存在する。Claude向け注意: 通常保存ロジックではなく `LiminalogSeedPreviewData` / `LiminalogSeedDevData` 指定時のデモseed専用挙動。検証: `git diff --check` 成功、`xcodebuild ... test -only-testing:LiminalogTests/ChapterStoreTests` で9件成功。シミュレータを `-LiminalogSeedDevData YES -LiminalogSeedPreviewData YES` で起動し、App Group SQLite上で2026-05-31のChapter、2026-05-31/2026-06-01/2026-07-01の時間つきPlanが入ることを確認。 |
| 2026-06-01 | Codex | Todayタブ「昨日」のメトリックから公開数を撤去。昨日の振り返りでは共有状態より、記録した量と予定していた量の比較の方が体験に効くため、3つ目のタイルを `公開` から `予定`（予定合計時間、予定なしなら `なし`）へ差し替えた。公開/非公開の管理は編集・友達共有文脈に寄せ、昨日タブは1日のリズム理解に集中させる。 |
| 2026-06-01 | Codex | Todayタブ「明日」の残り時間カードの完了状態文言を変更。予定が24時間埋まっている時の `見通しあり` は抽象的だったため、`予定登録済み` + `checkmark.circle.fill` に差し替えた。空きがある時は従来どおりオレンジの `空きあり` 表示。アクセシビリティ値も同じ文言に更新。 |
| 2026-06-01 | Codex | 統計タブのメトリックから公開数を撤去。公開数は共有設定の確認としては意味があるが、統計タブでは「どう過ごしたか」の理解に寄与しにくいため、`公開` タイルを `予定`（期間内の予定合計時間、予定なしなら `なし`）へ差し替えた。公開/非公開の操作UIや友達共有用の内部フラグは維持し、統計表示だけから外した。 |
| 2026-06-01 | Codex | 上記の `予定` タイル案を再修正。予定合計時間は統計・昨日レビューの主役として優先度が低く、`合計` ラベルも「何の合計か」が曖昧だったため、Today昨日は `実績` / `件数` の2タイルへ整理。統計タブは `実績` / `件数` / `日数` の3タイルへ整理し、4分割による日数アイコンの窮屈さも避ける。公開数・予定合計時間はこのメトリック列には出さない。 |
| 2026-06-01 | Codex | Claude docs/12・13 の方針を受け、Today「昨日」ページの主役をデイリーカードMVPへ差し替え。`DailyReflectionCard` を追加し、内側=予定/外側=実績の二重24時間リング、twilight/dark-first 背景、低透明度グレイン、称号（有言実行の人/スプリンター/ザッピング/風まかせ等の決定論判定）、スコア/実績/切替、カテゴリ色チップ、明日ページへ移動する `明日はどうする？` CTA を実装。既存のカテゴリ内訳/インサイトはカード下の詳細層として維持し、単日の満足感と共有したくなる世界観を先頭で出す構成にした。大改修前の復元ポイントとして `e95e1e7 checkpoint before liminal UI overhaul` を作成し、作業ブランチ `codex/liminal-ui-overhaul` へ分岐済み。QA用に DEBUG 起動引数 `-LiminalogInitialTodayPage yesterday|today|tomorrow` を追加し、通常起動は従来どおり今日ページ。検証: `git diff --check` 成功、`xcodebuild ... build-for-testing` 成功、シミュレータで通常起動=今日、DEBUG引数起動=昨日カード表示をスクリーンショット確認。 |
| 2026-06-01 | Codex | Claude docs/13 追記（単一固定twilight、Primary/Reward/中立、カテゴリ色=データ層、視認性保証）を実装側へ反映。まず `d0f5e94 docs: capture twilight visual identity guidance` でClaude追記を復元点として記録。`LiminalTheme` を追加し、アプリ全体を `preferredColorScheme(.dark)` + Primary紫 tint + twilight canvas に固定。`DailyReflectionCard` のローカル色定義は共通Themeへ昇格し、主要画面/シート背景もtwilight canvasへ寄せた。カテゴリ保存色は変更せず、`Category.displayColor` / `Color.cachedDisplayHex` を追加して描画時だけダーク地で見える明度へ正規化（目標コントラスト3:1）する設計にした。Todayのカテゴリボタン、24時間バー/タイムライン、カレンダー予定ラベル、統計カテゴリ表示、友達共有ステータスなど主要データ表示を正規化色へ差し替え。Claude向け注意: `Category.color` は保存/編集用の生色、`Category.displayColor` はtwilight表示用。色Pickerや保存ロジックでは raw を使うこと。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功。シミュレータへinstall/launchし、通常Todayと `-LiminalogInitialTodayPage yesterday` の昨日カードをスクリーンショット確認。 |
| 2026-06-01 | Codex | 最優先〜高優先のリリース仕上げを実施。大きな変更前の復元点として `bb4aee9 docs: capture theme and card engine followups` を作成済み。デイリーカードは `DailyPatternAnalysis` を追加し、28日履歴・履歴7日未満の逸脱OFF・σ floor 15分・|z|≥1.5・主要休息ブロック降格で「睡眠が見出しになる」問題を解消。文言は優しいコーチ口調をやめ、自虐×観察トーンへ置換。カードには `ImageRenderer` による1080×1920 PNG共有を追加。docs/14に合わせ `LiminalTheme` をdusk/daybreakのセマンティックトークンへ拡張し、`preferredColorScheme(.dark)` 固定を撤去、カテゴリ表示色の正規化もライト地では暗くする経路を追加。統計タブは単日をUIから退避し、週/月/年だけにした。友達プロフィールは自分プロフィール寄りの小ボタン・装備/スタッツ体裁に揃え、月カレンダー/日別タイムライン正準化の残り負債を解消。検証: `git diff --check` 成功、`xcodebuild -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing` 成功、`xcodebuild ... test-without-building` でSwift Testing 32件成功。シミュレータへinstall/launchし、`-LiminalogSeedDevData -LiminalogSeedDevFriends -LiminalogInitialTodayPage yesterday` で明色/暗色の昨日カードをスクリーンショット確認。 |

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

2. ~~**DEBUG seed が実機 DEBUG にも入る**~~ ✅ 解決 (2026-06-01)
   - `PreviewRuntimeSeedSupport` へ runtime seed 本体とフラグ判定を集約済み。
   - 通常の実機 DEBUG 起動では投入されず、`LiminalogSeedPreviewData` / `LiminalogSeedDevData` の明示指定時だけデモ seed が走る。

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
- ~~DEBUG seed 隔離は Codex 向き。Phase 0 前に小さく直せる。~~ ✅ 2026-06-01 完了

---

## 10.6 Claude コードレビュー — 2026-05-31（友達/プロフィール/カレンダー/統計 実装）

`codex/phase0-next` の友達タブ・プロフィール装飾・カレンダー・ダッシュボード実装をレビュー。
**結論: マージ可。** ビルド green、テスト 32件/10スイート全パス。前回レビュー（§10.5 / 旧コードレビュー）の重い構造指摘は解消済み。

### 解消を確認した項目（記録のみ・対応不要）

- ✅ ChapterStore の substore 二重生成 → AppStores が共有インスタンスを注入する形に修正済み。
- ✅ StartChapterIntent と ChapterStore のロジック重複 → `RecordingSwitchLogic` に集約、App/Intent/Widget が同一コアを共有＋テスト有。
- ✅ revision counter → ChapterStore から撤去済み。
- 🟢 ProfileView 集計 → 手動 `recentChapters(limit:10_000)` から `@Query` に置換（集計自体は View 内のまま）。
- 🟢 hasChapterOverlap → `startTime < endTime` で上限を絞る形に改善（下限未絞りは残るが perf 軽微）。

### フォローアップ・タスク

- [x] **【最重要】FriendsView の並行 UI スタックを正準ビューへ寄せる**（担当: Codex / 設計: Claude）
  - 現状 `FriendsView.swift`（3356行）に `FriendProfileHero`/`FriendProfileStatsRow`/`FriendProfileCollectionSection`（ProfileView 複製）、`FriendSharedCalendarMonthGrid`/`WeekRow`/`DayCell`（CalendarView 複製）、`FriendSharedTimelineView`/`TimelineOverviewBar`/`EntryCard`/`GapCard`（TimelineView 複製）が存在。約2000行の重複 UI。
  - docs/11 の「友達詳細＝他人ビュー再利用／別画面を作らない」「比較・デイビュー＝今日タブのビュー再利用」に反する。
  - 根本原因: 友達データが生 `Chapter`/`PlanBlock` ではなく JSON スナップショット（`FriendSharedActivitySnapshot`/`FriendSharedPlanSnapshot`）のため、既存ビューに直接流せず fork した。
  - **方針**: タイムライン/カレンダー/プロフィールの正準ビューを「生モデルでも友達スナップショットでも食える表示用 ViewModel / protocol」に一段抽象化し、自分・友達の両方が同一ビューを使う。これでタイムライン UI 改善を1箇所で済ませ、ドリフトを防ぐ。
  - マージ阻止要因ではないが、放置すると複利で効く保守債務。重い場合は最低限「意図的に fork した理由」を docs/11 に注記して負債を可視化する。
  - 2026-05-31 Codex進捗: `TimelineDisplaySnapshot` + `SharedTimelineReadOnlyView` を正準Timeline側に追加し、友達デイビューの `FriendSharedTimelineView` はスナップショット変換だけに縮小。友達専用の24時間バー/時間レール/カード/ギャップ描画（`FriendTimeline*` 群）を削除し、Timeline UI 改善が友達デイビューにも反映される経路へ寄せた。
  - 2026-05-31 Codex追加進捗: `CalendarDisplayPlan` / `CalendarDisplayScore` を追加し、友達月カレンダーも正準 `CalendarMonthGrid` を使う形へ移行。友達専用の月グリッド/週行/日セル/予定ラベル/複数日バーを削除。
  - 2026-06-01 Codex追加進捗: 残っていた友達プロフィールHero/Stats/Collectionは、自分プロフィールと同じ装飾カード・装備4列・`ProfileStatTile` 系の見た目に寄せたうえで、操作差（自分=編集/シェア、友達=カレンダー/お気に入り）は注入ボタンとして分離。カレンダー/タイムラインは既に正準表示用ViewModel経由のため、リリース前に問題になる重複UIは解消済み。

- [x] **Friend モデルの非正規化を docs/04 に反映 or 乖離を注記**（担当: Codex / 設計: Claude, 完了: 2026-05-31）
  - docs/04 は SharedTimeline / Reaction / Comment を別エンティティとしていたが、実装は `today/yesterday/week/month/yearScore`・`streakCount`・`sharedPlansJSON`/`sharedActivitiesJSON` を `Friend` に集約（スナップショットキャッシュ方式）。
  - スコア各期間フィールドの**再計算・同期の所有者が未定**（現状 debug seed と FriendsView が書くのみ）。Phase 3 の CloudKit 共有実装時に同期ポリシーを定義する。
  - docs/04 を現実装の方針へ更新するか、乖離点を注記する。

- [ ] **DashboardView(1192行) / ProfileView(1058行) のサブビュー外出し**（担当: Codex）
  - FriendsView ほどではない（単一タブ内で凝集・他タブの複製ではない）が、ナビゲーション性のためファイル分割したい。優先度は上記2件より低。

- [x] **軽微: `Friend.score(for:)` の `.day`/`.yesterday` 二重マッピング**（担当: Codex, 完了: 2026-05-31）
  - 両者が `yesterdayScore` を返す。意図的だが紛らわしい。enum 整理 or コメント補足。

- [x] **軽微: ProfileView `@Query queriedChapters` が述語なし＝全 Chapter 読み**（担当: Codex, 完了: 2026-05-31）
  - `ProfileView` から全Chapter/Planの常時 `@Query` と毎分再集計を撤去。プロフィール表示時に `ProfilePerformanceSnapshot` を作成し、スコア/ストリークは365日範囲fetch、累計バッジ判定は従来の意味を維持するため全履歴fetchを1回だけ行う方式へ変更。

---

## 11. オープン論点（ユーザー確認が必要）

実装前に確定したい仕様の曖昧点。両AIが新タスク着手時に該当論点があれば、まずここに追加してユーザーに確認する。

| # | 論点 | 影響範囲 | 優先度 |
|---|------|---------|------|
| 1 | App Group ID / CloudKit Container ID の正式名称 | Phase 0 全体 | 🔴 高 |
| 2 | グリッドの「もっと見る」展開 UI（インライン / シート / フルスクリーン）| Phase 1 グリッド | 🟠 中 |
| 3 | 公開設定「リアルタイム/翌日公開」の選択粒度（チャプター毎/日毎/プリセット毎）| Phase 3 公開設定 | 🟠 中 |
| 4 | 「翌日公開」の配信タイミング（深夜0時固定 / ユーザーの1日始まり時間に従う）| Phase 3 公開設定 | 🟠 中 |
| ~~5~~ | ~~アンロックシステムの累計スコア閾値（解放スケジュール表から逆算でOK？）~~ | ~~Phase 2 アンロック~~ | ✅ 解決 (2026-06-01): 60pt/日を合格ラインとして、仕様書の1年解放ペースから26件の累計スコア閾値を逆算 |
| ~~6~~ | ~~アンロックアイテムの失効・離脱者の扱い~~ | ~~Phase 2 アンロック~~ | ✅ 解決 (2026-06-01): 解放後は失効させず、離脱後も `unlockedAt` を保持する |
| 7 | ストリーク途切れの猶予（1日でも60%未満で即リセット？）| Phase 2 ストリーク | 🟠 中 |
| 8 | リアクション絵文字パレットのカスタマイズ可否 | Phase 3 リアクション | 🟢 低 |
| 9 | ランキング同点時のタイブレーク仕様 | Phase 3 ランキング | 🟢 低 |
| 10 | カテゴリマッピング「多対一」の UI 表現・優先順位 | Phase 3 マッピング | 🟢 低 |
| 11 | カテゴリカラーのカスタム範囲（任意Hex / プリセット選択）| 設定UI | 🟢 低 |
| ~~12~~ | ~~使用頻度の集計範囲~~ | ~~Phase 1 グリッド~~ | ✅ 解決 (2026-05-24): 使用頻度ソート廃止 |
| 13 | デザインシステム本体（カラー・タイポ）の定義 | 全画面 | 🟠 中 |
| 14 | カレンダー予定「中身公開/空き時間のみ」のチャプター混在表示 | Phase 3 予定共有 | 🟢 低 |
| 15 | Chapter.photoData の保存戦略（SwiftData直 / CKAsset別管理）| Phase 1 写真添付 | 🟠 中 |
| 16 | **フェーズ順の戦略判断**：デイリーカード(§7.7)+ビジュアル(§7.8)を、Phase 3 友達インフラより先にやるか。docs/12/13 の戦略は「カード先行→solo配布→拡散測定→その後 友達」。現状 Codex は友達まわりを進行中。カード拡散を証明する前に重い友達インフラ(CKShare等)に投資するリスクをどう取るか | Phase順全体 | 🔴 高 |
| 17 | 称号の実コピー温度・和文Display書体・最終hex（docs/12 §6 / docs/13 §2-3）＝ユーザーの編集/美的判断待ち | カード/ビジュアル | 🟠 中 |
