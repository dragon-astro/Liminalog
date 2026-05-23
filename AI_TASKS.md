# Liminalog — AI タスクボード

ClaudeとCodexが連携してLiminalogを開発するための共有タスク管理ファイル。
実装したタスクは `[x]` に更新し、完了ログに記録すること。

---

## AI分担ルール

| タスク種別 | 担当 |
|---|---|
| 複雑なSwiftUIレイアウト・アニメーション | Claude |
| 複数ファイルにまたがるアーキテクチャ変更 | Claude |
| CloudKit / CKShare / CKSubscription 統合 | Claude |
| EventKit 統合 | Claude |
| アルゴリズム・計算ロジック | Codex |
| SwiftDataモデル追加・CRUD | Codex |
| Extension / Utilityメソッド | Codex |
| シンプルなビュー・単一コンポーネント | （どちらでも可） |
| ドキュメント・コメント整備 | （どちらでも可） |

> **担当欄の凡例**
> - `[Claude]` — Claudeが実施する意図があるタスク
> - `[Codex]` — Codexが実施する意図があるタスク
> - 空欄 — どちらでも可

---

## 新規タスクの追記ルール

実装を進める中で新たなタスクが発生した場合は、以下のルールに従って該当フェーズのリストに追記すること。

```
- [ ] タスクの説明（簡潔に） <!-- 担当: Claude / Codex / 空欄 -->
```

追記後、完了ログにも「新規タスク追加」として日付・担当・内容を記録すること。
仕様変更や設計変更によるタスクの削除・統合も、完了ログに理由とともに記録すること。

---

## Phase 1 — MVPコア（ソロ完結）

**目標:** ウィジェットでタップ記録して、タイムラインで振り返れる状態

### データ・ロジック層
- [x] SwiftDataモデル定義: Chapter <!-- 担当: Codex -->
- [x] SwiftDataモデル定義: Category <!-- 担当: Codex -->
- [x] SwiftDataモデル定義: CategorySet（カテゴリセット） <!-- 担当: Codex -->
- [x] SwiftDataモデル定義: PlanBlock（予定ブロック） <!-- 担当: Codex -->
- [x] デフォルトカテゴリのシード処理（勉強/仕事/趣味/休憩/移動/睡眠） <!-- 担当: Codex -->
- [x] デフォルトカテゴリセットのシード処理（平日/休日） <!-- 担当: Codex -->
- [x] チャプター記録ロジック（開始・終了・自動切り替え） <!-- 担当: Codex -->
- [x] 1分ルール（1分未満チャプターを誤タップとして削除） <!-- 担当: Codex -->
- [x] カテゴリ使用頻度カウント（usageCount インクリメント） <!-- 担当: Codex -->
- [x] チャプターCRUD（saveChapter / deleteChapter / addChapter） <!-- 担当: Codex -->
- [x] カテゴリCRUD（addCategory / updateCategory / deleteCategory） <!-- 担当: Codex -->
- [x] カテゴリセットCRUD（addCategorySet / updateCategorySet / deleteCategorySet） <!-- 担当: Codex -->

### ホーム画面
- [x] ホーム画面レイアウト（HomeView） <!-- 担当: Claude -->
- [x] 現在のチャプターカード（CurrentChapterCard） <!-- 担当: Claude -->
- [x] カテゴリグリッド（CategoryGrid — 最大8件・使用頻度順） <!-- 担当: Claude -->
- [x] カテゴリグリッドボタン（CategoryGridButton） <!-- 担当: Claude -->
- [x] 今日のタイムライン（TimelineView） <!-- 担当: Claude -->
- [x] タイムラインチャプターカード（TimelineChapterCard） <!-- 担当: Claude -->
- [x] 現在時刻マーカーの自動スクロール <!-- 担当: Claude -->

### チャプター編集UI
- [x] チャプター編集シート（ChapterEditSheet） <!-- 担当: Claude -->
- [x] チャプター新規追加シート（ChapterCreateSheet） <!-- 担当: Claude -->
- [x] 気分ピッカー（MoodPicker） <!-- 担当: Claude -->
- [x] 空白時間タップ → 新規チャプター追加 <!-- 担当: Claude -->

### カテゴリ設定UI
- [x] カテゴリ設定画面（CategorySettingsView） <!-- 担当: Claude -->
- [x] カテゴリ編集シート（CategoryEditSheet — 名前・カラー・アイコン） <!-- 担当: Claude -->
- [x] カテゴリセット編集シート（CategorySetEditSheet） <!-- 担当: Claude -->

### 公開設定UI
- [ ] ホーム画面の公開設定トグル（今日分をその場で変更） <!-- 担当: Claude -->
- [ ] チャプター個別の公開/非公開切り替え <!-- 担当: Claude -->

### ウィジェット
- [x] Live Activityウィジェット（LiminalogLiveActivityWidget） <!-- 担当: Codex -->
- [x] Live Activityステータス表示ウィジェット（LiminalogStatusWidget） <!-- 担当: Codex -->
- [x] Live Activity更新マネージャー（LiveActivityManager） <!-- 担当: Codex -->
- [ ] WidgetKit記録グリッドウィジェット（カテゴリタップ → 即記録） <!-- 担当: Claude -->
- [ ] App Groupsセットアップ（ウィジェット↔アプリ間データ共有） <!-- 担当: Codex -->

---

## Phase 2 — 振り返りの充実

**目標:** ソロで「使い続けたい」と思えるレベルにする

### カレンダー
- [x] 月カレンダー画面（CalendarView — チャプターカラードット表示） <!-- 担当: Claude -->
- [x] デイビュー（CalendarDayView — 左右スワイプ対応） <!-- 担当: Claude -->
- [x] PlanBlockのタイムライン表示（デイビュー内） <!-- 担当: Claude -->
- [ ] EventKit連携: iOSカレンダー予定の読み込み・表示 <!-- 担当: Claude -->
- [ ] EventKit連携: カレンダー予定の追加・編集・削除 <!-- 担当: Claude -->
- [ ] カレンダー予定の終日/時間指定エリア分離表示 <!-- 担当: Claude -->
- [ ] 日付またぎチャプターのタイムライン表示（設定区切り時間に従う） <!-- 担当: Claude -->

### スコア・ストリーク
- [x] スコア計算ロジック（ScoreCalculator — カテゴリ80%+時間軸20%・±15分許容） <!-- 担当: Codex -->
- [x] ストリーク計算（ChapterStore.streakCount — 60%閾値） <!-- 担当: Codex -->
- [ ] 1日の始まり時間設定（設定画面に追加・タイムライン表示に反映） <!-- 担当: Codex -->

### ダッシュボード
- [x] ダッシュボード基本構造（今日/週間/月間/年間セグメント） <!-- 担当: Claude -->
- [x] 予定達成スコアカード（TodayScoreDashboardCard） <!-- 担当: Claude -->
- [x] カテゴリ別横棒グラフ（CategoryShareCard） <!-- 担当: Claude -->
- [x] 24時間ヒートマップ（HourHeatmapCard） <!-- 担当: Claude -->
- [x] 最近の記録リスト（RecentTrendCard） <!-- 담当: Claude -->
- [ ] カテゴリ別アクティビティリング風グラフ <!-- 担当: Claude -->
- [ ] カテゴリ別ドーナツグラフ <!-- 担当: Claude -->
- [ ] 週間: 日ごとの積み上げ棒グラフ <!-- 担当: Claude -->
- [ ] 週間: 時間帯別傾向（朝/昼/夜の割合） <!-- 担当: Claude -->
- [ ] 週間: 先週比差分バー <!-- 担当: Claude -->
- [ ] 月間: 月間カレンダーヒートマップ（GitHub風） <!-- 担当: Claude -->
- [ ] 月間: カテゴリ別折れ線グラフ（週単位推移） <!-- 担当: Claude -->
- [ ] 年間: 年間カレンダーヒートマップ <!-- 担当: Claude -->
- [ ] グラフアニメーション（数字が育っていく演出） <!-- 担当: Claude -->
- [ ] グラフ表示順・表示非表示のカスタマイズ <!-- 担当: Claude -->

### アンロックシステム
- [ ] UnlockItemモデル定義 <!-- 担当: Codex -->
- [ ] UnlockManagerロジック（累計スコアに基づくアイテム解放） <!-- 担当: Codex -->
- [ ] アンロック解放スケジュール（約26個・1年で全解放） <!-- 担当: Codex -->
- [ ] プロフィール画面のアンロック進捗表示 <!-- 担当: Claude -->
- [ ] アンロック通知・お祝い演出 <!-- 担当: Claude -->

### エクスポート・シェア
- [ ] タイムライン画像書き出し（Instagram向け縦長フォーマット） <!-- 担当: Claude -->
- [ ] 週間サマリー書き出し <!-- 担当: Claude -->
- [ ] CSV書き出し <!-- 担当: Codex -->

### プロフィール
- [x] プロフィール画面基本レイアウト（ProfileView） <!-- 担当: Claude -->
- [ ] 累計スコア・アンロック進捗の表示 <!-- 担当: Claude -->
- [ ] ストリーク表示 <!-- 担当: Claude -->
- [ ] 統計サマリー（記録継続日数・チャプター数など） <!-- 担当: Claude -->

---

## Phase 3 — 友達機能

**目標:** CloudKitでサーバーレスの友達共有を実現

- [x] 友達タブ プレースホルダー（FriendsView） <!-- 담当: Claude -->
- [ ] CloudKit Container セットアップ <!-- 担当: Claude -->
- [ ] CKShare による友達承認制フォロー関係の構築 <!-- 担当: Claude -->
- [ ] CKSubscription によるリアルタイム同期 <!-- 担当: Claude -->
- [ ] Friendモデル定義 <!-- 担当: Codex -->
- [ ] PublicSettingsモデル定義（公開設定プリセット） <!-- 担当: Codex -->
- [ ] 友達タイムライン閲覧（デイビュー形式） <!-- 担当: Claude -->
- [ ] リアクション（絵文字）・コメント（テキスト） <!-- 担当: Claude -->
- [ ] ランキング画面（今日/昨日/今週切り替え・横スクロール） <!-- 担当: Claude -->
- [ ] 友達プロフィールリスト（達成率・現在ステータス） <!-- 担当: Claude -->
- [ ] 公開設定・プリセットの本格実装（仲良し/知り合い/オフ/カスタム） <!-- 担当: Claude -->
- [ ] 友達ウィジェット（1人用Small・複数人Medium・ミックスLarge） <!-- 担当: Claude -->
- [ ] グループチャレンジ <!-- 担当: Claude -->
- [ ] 友達のカレンダー予定の共有（公開設定に基づく） <!-- 担当: Claude -->
- [ ] カテゴリマッピング設定（デフォルト自動対応・カスタム手動対応） <!-- 担当: Codex -->

---

## Phase 4 — UX向上・ソーシャル深化

**目標:** 体験の気持ちよさと友達機能を磨く

- [ ] ダッシュボード2人比較UI（縦長タイムライン横2列） <!-- 担当: Claude -->
- [ ] 複数人比較画像の書き出し（名前・アイコン付き） <!-- 担当: Claude -->
- [ ] シンクロハイライト（友達との同時刻行動を強調） <!-- 担当: Claude -->
- [ ] Siriショートカット（App Intents） <!-- 担当: Claude -->
- [ ] HealthKit連携（就寝・起床自動検知） <!-- 担当: Claude -->
- [ ] テーマ着せ替え追加（カラーパターン拡充） <!-- 担当: Claude -->
- [ ] チャプタータイマー表示（現在のチャプターの経過時間を常時表示） <!-- 担当: Claude -->

---

## 完了ログ

新規タスクの追加・実装完了・設計変更を時系列で記録すること。

| 日付 | 担当 | 内容 |
|---|---|---|
| 2026-05-24 | Codex | Phase 1: SwiftDataモデル（Chapter/Category/CategorySet/PlanBlock）実装 |
| 2026-05-24 | Codex | Phase 1: チャプター記録ロジック（ChapterStore）・1分ルール・カテゴリCRUD実装 |
| 2026-05-24 | Codex | Phase 2: スコア計算ロジック（ScoreCalculator）・ストリーク計算実装（Phase 2先行） |
| 2026-05-24 | Codex | Phase 1: Live Activity対応（LiveActivityManager・WidgetBundle） |
| 2026-05-24 | Claude | Phase 1: ホーム画面・タイムライン・カテゴリグリッド・チャプター編集UI実装 |
| 2026-05-24 | Claude | Phase 1: カテゴリ設定画面・カテゴリセット管理UI実装 |
| 2026-05-24 | Claude | Phase 2: カレンダー画面（CalendarView・CalendarDayView）・PlanBlock表示実装（Phase 2先行） |
| 2026-05-24 | Claude | Phase 2: ダッシュボード基本版（スコアカード・カテゴリ別グラフ・24時間ヒートマップ）実装（Phase 2先行） |
| 2026-05-24 | Claude | AI_TASKS.md 作成（タスクボード初期セットアップ） |
