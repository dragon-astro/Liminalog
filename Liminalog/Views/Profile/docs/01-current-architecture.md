# 01. 現状アーキテクチャの棚卸し

> このドキュメントは「現時点のコードがどう組まれているか」を実装ファイルから抽出して言語化したもの。
> 設計の善し悪しの評価はせず、**今こうなっている** という事実だけを記述する（評価は [02-gap-analysis.md](02-gap-analysis.md) で行う）。

---

## 1. 全体像

```
┌─────────────────────────────────────────────────────────────────┐
│  LiminalogApp.swift  (Entry / WindowGroup)                       │
│    └─ .modelContainer([Category, CategorySet, Chapter,           │
│                         PlanBlock, VisibilityPreset])            │
│                                                                  │
│  RootTabView                                                     │
│    ├─ .task { ChapterStore(modelContext) を生成・seed }          │
│    └─ TabView (5 tabs) ── .environment(store)                    │
│         ├─ HomeView                                              │
│         ├─ CalendarView                                          │
│         ├─ DashboardView                                         │
│         ├─ FriendsView   (プレースホルダー)                       │
│         └─ ProfileView                                           │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼ (環境注入)
┌─────────────────────────────────────────────────────────────────┐
│  ChapterStore  @Observable @MainActor  (Stores/)                 │
│    ├─ ModelContext を保持                                         │
│    ├─ 全てのCRUD・ビジネスロジックを集約                          │
│    └─ revision: Int でビューに変更を手動通知                      │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  SwiftData (Default Store)                                       │
│    Chapter / Category / CategorySet / PlanBlock /                │
│    VisibilityPreset                                              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  LiminalogWidget (Extension)                                     │
│    ├─ LiminalogStatusWidget  (静的ステータス表示のみ)             │
│    └─ LiminalogLiveActivityWidget  (Dynamic Island / Lock)       │
│                                                                  │
│  ※ App Groups 未設定 — SwiftDataストアの共有なし                  │
│  ※ Live Activity の状態はアプリから ActivityKit で push される   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. レイヤー構成

| レイヤー | ファイル | 責務 |
|---------|---------|------|
| **App** | `LiminalogApp.swift` | エントリ・ModelContainer 宣言 |
| **Root** | `Views/RootTabView.swift` | Store初期化・タブ構成・初回 seed |
| **Store** | `Stores/ChapterStore.swift` | 全 CRUD・スコア・ストリーク・シード |
| **Domain Logic** | `Stores/ScoreCalculator.swift` | スコア算出（純粋関数） |
| **Live Activity** | `Stores/LiveActivityManager.swift` | ActivityKit との橋渡し（singleton） |
| **Model** | `Models/*.swift` | SwiftData `@Model` クラス 5 つ |
| **View** | `Views/{Home,Calendar,Dashboard,Friends,Profile,Settings,ChapterEdit}/` | SwiftUI ビュー |
| **Component** | `Views/Home/{CategoryGrid,TimelineView,CurrentChapterCard,...}` | ホーム配下の共通部品 |
| **Extension** | `Extensions/{Color+Hex,Date+Formatting}.swift` | ユーティリティ |
| **Preview** | `PreviewSupport.swift` | プレビュー用 in-memory コンテナ・ダミーデータ |
| **Widget** | `LiminalogWidget/` | WidgetKit / ActivityKit |

---

## 3. データモデル現状

### Model 一覧（`Models/`）

| Model | フィールド | リレーション | 備考 |
|-------|-----------|-------------|------|
| **Chapter** | `id, category?, startTime, endTime?, note?, mood?, locationName?, isPublic, createdAt` | `category: Category?`（nullify） | `endTime == nil` で「記録中」 |
| **Category** | `id, name, colorHex, icon?, sortOrder, usageCount, isDefault, createdAt` | `chapters: [Chapter]`（inverse, nullify） | 削除時 Chapter 側は nullify |
| **CategorySet** | `id, name, sortOrder, categoryIDs: [UUID], createdAt` | なし（UUID参照） | 最大8件にトリム |
| **PlanBlock** | `id, category?, title, startTime, endTime, isAllDay, note?, isPublic, createdAt` | `category: Category?`（暗黙） | 予定ブロック・スコア計算に使用 |
| **VisibilityPreset** | `id, name, level: VisibilityLevel{all,partial,none}` | なし | 定義のみ・現状未使用 |

### `LiminalogActivityAttributes`（ActivityKit）
- `ContentState` は現在チャプター + カテゴリセット名 + 公開状態だけを保持
- 2026-05-28 に `ContentState.categories` / `IslandCategory` は削除済み。カテゴリ配列は Live Activity state に同梱しない

### モデル間の関連まとめ

```
Category ─┬─< Chapter        (Category.chapters / Chapter.category — 双方向)
          ├── CategorySet    (UUID参照 / 双方向リレーションなし)
          └── PlanBlock      (PlanBlock.category — 片方向 / inverse未定義)

VisibilityPreset            (孤立 — どのモデルとも未関連)
```

---

## 4. 状態管理パターン

### a. ChapterStore — 中央集権ストア

- `@Observable @MainActor final class ChapterStore`
- `RootTabView` で `@State private var store: ChapterStore?` として遅延生成
- `.environment(store)` で全ビューに注入
- 各ビューは `@Environment(ChapterStore.self) private var store`

### b. revision カウンタによる手動リアクティビティ

```swift
var revision = 0  // ChapterStore に1つ

// 全 mutating メソッドの末尾で
try? modelContext.save()
revision += 1
```

- SwiftData `@Query` を使わず、`ChapterStore` のメソッド経由でデータ取得するビューが多い
- ビュー側は `onChange(of: store.revision)` で再フェッチをトリガー
- 例外: `CategorySettingsView` のみ `@Query` を使用

### c. ビュー個別の `@State`

- 編集中のチャプター: `@State private var editingChapter: Chapter?`
- シート表示制御: `@State private var showingAddSheet = false`
- カレンダー表示月: `@State private var visibleMonth = Date()`
- タイムライン自己リフレッシュ: `@State private var chapters: [Chapter] = []` + 30秒タイマー

---

## 5. ChapterStore の責務（過剰集中）

`ChapterStore.swift` 378行が抱えているもの:

| 領域 | メソッド例 |
|------|-----------|
| Chapter CRUD | `startChapter`, `addChapter`, `endActiveChapter`, `saveChapter`, `deleteChapter`, `setChapterVisibility` |
| Chapter Query | `activeChapter`, `todaysChapters`, `chapters(on:)`, `chapters(from:to:)`, `recentChapters(limit:)` |
| Category CRUD | `addCategory`, `updateCategory`, `deleteCategory` |
| Category Query | `categoriesForGrid`, `categories(for:)`, `allCategories` |
| CategorySet CRUD | `addCategorySet`, `updateCategorySet`, `deleteCategorySet` |
| CategorySet Query | `categorySets` |
| PlanBlock CRUD | `addPlanBlock`, `deletePlanBlock` |
| PlanBlock Query | `plannedBlocks(on:)`, `plannedBlocks(from:to:)` |
| Score / Streak | `scoreSummary(on:)`, `streakCount(endingAt:)`, `totalScore(days:)` |
| Seed | `seedDefaultCategoriesIfNeeded`, `seedDefaultCategorySetsIfNeeded`, `seedPreviewPlansIfNeeded` |
| Live Activity 橋渡し | `updateLiveActivity(categorySet:)` |

→ Store 一つに **8 ドメイン × CRUD + 計算 + シード + 橋渡し** が同居している。

---

## 6. データフロー（代表 3 シナリオ）

### a. ホームでカテゴリボタンをタップ → 記録開始

```
CategoryGrid.button.tap
  → store.startChapter(category:, categorySet:)
        ├─ activeChapter チェック
        │   ├─ 1分未満なら delete
        │   └─ そうでなければ endTime = now
        ├─ category.usageCount += 1
        ├─ Chapter 新規 insert
        ├─ modelContext.save()
        ├─ revision += 1
        └─ updateLiveActivity(categorySet:)
              └─ LiveActivityManager.shared.update(...)
                    └─ Activity<...>.request または .update

HomeView の onChange(of: store.revision) でタイムライン再フェッチ
```

### b. カレンダータブで日付をタップ

```
CalendarView の NavigationLink
  → CalendarDayView(date:)
        ├─ store.chapters(on: date) でフェッチ
        ├─ store.plannedBlocks(on: date) でフェッチ
        └─ TimelineView を使用して描画
              └─ TimelineView 内部で再度 store.* を呼ぶ
                  (Store 経由なので reactive ではなく明示的 fetch)
```

### c. ダッシュボード期間切り替え

```
DashboardView の Picker.tap → period が変わる
  → 計算プロパティ chapters が再評価
        → store.chapters(from: start, to: end) でフェッチ
  → 各カード (TodayScoreDashboardCard, CategoryShareCard, ...) が再計算
```

---

## 7. ウィジェット境界

### 現状の境界線

| 項目 | 状態 |
|------|------|
| App Groups | **設定済** (`group.app.YasudaRyuga.Liminalog`) |
| App ↔ Widget の SwiftData 共有 | **土台あり**（App Group ModelContainer。Widget 側の本格読み込みは未実装） |
| WidgetKit のインタラクティブ記録グリッド | **未実装**（LiminalogStatusWidget は静的文言のみ） |
| Live Activity | **実装済** — Dynamic Island / Lock Screen 対応 |
| Live Activity への状態伝達 | アプリ側 `LiveActivityManager.update(...)` から `Activity.update(...)` で push |
| カテゴリデータの Live Activity への同梱 | **廃止済**。`ContentState` にカテゴリ配列は持たせない |

### Color(hex:) の重複

- `Liminalog/Extensions/Color+Hex.swift`（アプリ側）
- `LiminalogWidget/LiminalogLiveActivityWidget.swift` 内 private extension（ウィジェット側、独立実装）

→ App Groups もしくは共有フレームワークがないため、両側で別実装を保持。

---

## 8. 暗黙の依存・前提

実装を読んだ限り、以下が「コードには現れていないが前提として動いている」もの:

- **タイムゾーン**: `Calendar.current` を全箇所で使用。`Calendar.japanese` という未公開 extension が CalendarView で参照されている（要確認）
- **「1日」の定義**: 全て `Calendar.current.startOfDay(for:)` 固定（仕様書にある「1日の始まり時間設定」は未実装）
- **CloudKit**: ModelContainer は CloudKit URL 未指定 = ローカル専用ストア
- **EventKit**: 言及なし・権限取得もなし（仕様書のカレンダー連携は未着手）
- **DEBUG プレビューデータ**: `RootTabView.task` 内で `#if DEBUG` ガード付きで `seedPreviewPlansIfNeeded` を呼ぶ。**実機 DEBUG ビルドでも本データが入る** ため注意

---

## 9. ファイルツリー（実装ファイルのみ）

```
Liminalog/
├── LiminalogApp.swift
├── PreviewSupport.swift
├── Extensions/
│   ├── Color+Hex.swift
│   └── Date+Formatting.swift
├── Models/
│   ├── Category.swift
│   ├── CategorySet.swift
│   ├── Chapter.swift
│   ├── LiminalogActivityAttributes.swift
│   ├── PlanBlock.swift
│   └── VisibilityPreset.swift
├── Stores/
│   ├── ChapterStore.swift          (378行 — God Store)
│   ├── LiveActivityManager.swift
│   └── ScoreCalculator.swift
└── Views/
    ├── RootTabView.swift
    ├── Calendar/
    │   ├── CalendarDayView.swift
    │   └── CalendarView.swift
    ├── ChapterEdit/
    │   ├── ChapterCreateSheet.swift
    │   ├── ChapterEditSheet.swift
    │   └── MoodPicker.swift
    ├── Dashboard/
    │   └── DashboardView.swift     (340行 — 全カード同居)
    ├── Friends/
    │   └── FriendsView.swift       (プレースホルダー)
    ├── Home/
    │   ├── CategoryGrid.swift
    │   ├── CategoryGridButton.swift
    │   ├── CurrentChapterCard.swift
    │   ├── HomeView.swift
    │   ├── TimelineChapterCard.swift
    │   └── TimelineView.swift      (374行 — 描画ロジック集中)
    ├── Profile/
    │   └── ProfileView.swift
    └── Settings/
        ├── CategoryEditSheet.swift
        ├── CategorySettingsView.swift
        └── CategorySetEditSheet.swift

LiminalogWidget/
├── Info.plist
├── LiminalogLiveActivityWidget.swift
├── LiminalogStatusWidget.swift
├── LiminalogWidgetAttributes.swift  (LiminalogActivityAttributes と重複)
└── LiminalogWidgetBundle.swift
```

---

## 10. メトリクス（ざっくり）

| 指標 | 数値 |
|------|------|
| Swift ファイル数 | 32 |
| SwiftData モデル数 | 5 |
| ビュータブ数 | 5 |
| Storeメソッド数（CRUD/Query/Score/Seed） | 約 30 |
| 最大ファイル | `ChapterStore.swift` 378行 / `TimelineView.swift` 374行 / `DashboardView.swift` 340行 |
| Widget 種類 | 2 (Status / LiveActivity) |
| テストファイル数 | **0** |

---

## 次のドキュメント

→ [02-gap-analysis.md](02-gap-analysis.md): この現状と `liminalog_spec_v04.md` の差分・解釈ズレを洗い出す
