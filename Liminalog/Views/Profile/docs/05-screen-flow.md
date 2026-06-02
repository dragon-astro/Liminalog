# 05. 画面・状態遷移設計

> [03-architecture.md](03-architecture.md) で確定した `@Query` 主軸・`AppStores` 注入のもとで、各タブの画面遷移・シート階層・権限ハンドリング・エラー/空状態を設計する。

> Codexレビューあり: 実装前に [07-codex-plan-review.md](07-codex-plan-review.md) を必ず確認すること。
> 特に `@AppStorage` と `UserSettings` の使い分け、Dashboard の動的 `@Query`、active chapter 複数時の収束ルールは修正が必要。

---

## 0. 全体ナビゲーション原則

1. **タブ間遷移なし**: タブを跨ぐディープリンクは Phase 1 では設けない（友達タブ→デイビュー直行などは Phase 3 で）
2. **NavigationStack はタブごとに1本**: タブ切り替えで状態は保持
3. **シートは「現在の画面の延長」、フルスクリーンカバーは「新しい文脈」** を使い分ける
4. **空状態を機能の入口にする**: 「データがない」を伝えるだけで終わらせず、必ず CTA を置く
5. **権限要求は文脈直前に**: アプリ起動時に一気に許可ダイアログを出さない。機能を使おうとした時に出す

---

## 1. タブ構成（最終形）

```
RootTabView
├── Tab "ホーム"          → HomeView
├── Tab "カレンダー"      → CalendarView
├── Tab "統計"            → DashboardView
├── Tab "友達" (Phase 3)  → FriendsView
└── Tab "プロフィール"    → ProfileView
```

各 Tab は独立した `NavigationStack` を内包。

---

## 2. ホームタブ

### 2.1 画面構造

```
NavigationStack
└─ HomeView
    ├─ CurrentChapterCard         (現在のチャプター + 経過時間)
    │   └─ tap → 公開設定ボタン → VisibilitySheet
    ├─ CategoryGrid               (8件 + "もっと見る")
    │   ├─ button tap → store.chapter.start(category:)
    │   └─ "もっと見る" tap → CategorySetSwitcher (シート)
    ├─ Divider
    └─ TimelineView(today)
        ├─ chapter tap → ChapterEditSheet
        ├─ 空白 tap → ChapterCreateSheet
        ├─ chapter context menu → 編集/削除/公開設定
        └─ "今日" の現在時刻ライン (TickClock 駆動)
```

### 2.2 ツールバー

- **leading**: `+` → ChapterCreateSheet（手動追加）
- **trailing**: 設定アイコン → ProfileView の CategorySettings へ遷移 …**ではなく**、`SettingsView` を別途用意してそこへ。
  - 理由: Phase 2 でテーマ・表示・連携など設定が増える。ProfileView 経由は冗長。
  - Phase 1 では `SettingsView` の中身はカテゴリ管理だけでもOK。

### 2.3 シート階層

```
HomeView
├─ .sheet: ChapterEditSheet         (editingChapter != nil)
├─ .sheet: ChapterCreateSheet       (showingCreateSheet)
├─ .sheet: VisibilitySheet          (showingVisibilitySheet)
└─ .sheet: CategorySetSwitcher      (showingSetSwitcher)
```

**同時に複数シートを出さないルール**: シートが既に開いている場合は新規シート要求を破棄。

### 2.4 状態管理

```swift
struct HomeView: View {
    @Environment(AppStores.self) private var stores
    @Query(filter: #Predicate<Chapter> { $0.endTime == nil })
    private var activeChapters: [Chapter]
    @Query(sort: \CategorySet.sortOrder)
    private var categorySets: [CategorySet]

    @State private var editingChapter: Chapter?
    @State private var showingCreateSheet = false
    @State private var showingVisibilitySheet = false
    @State private var showingSetSwitcher = false
    @State private var clock = TickClock()
    @AppStorage("activeCategorySetID") private var activeSetIDString: String = ""
}
```

### 2.5 空状態

| 状況 | 表示 |
|------|------|
| 現在記録なし | CurrentChapterCard が「カテゴリをタップで記録開始」と表示 |
| 今日のチャプターゼロ | TimelineView が「最初の1分を記録してみよう」+ タップでカテゴリグリッドへスクロール |
| カテゴリ未作成 | グリッドに「カテゴリを追加」CTA |

---

## 3. カレンダータブ

### 3.1 役割

カレンダータブは「24時間予定を全部並べる場所」ではなく、**日付単位の俯瞰と計画の入口**にする。

- 月表示: スコアと重要な予定だけを表示する
- 日別表示: 重要な予定 + 24時間タイムラインで詳細予定/実績を扱う
- 詳細な時間つき予定は月グリッドには出さない
- 「時間は未定だが、この日にやる大事なこと」は重要な予定として置き、近づいたら日別タイムラインで時間に割り付ける
- 時間が決まっている予定でも `isImportant == true` なら月カレンダーに表示し、開始時刻も見せる
- 外部カレンダー連携は将来対応。時間未指定/終日予定は重要な予定へ、時間指定予定はタイムラインの予定へ変換し、必要なら `isImportant` も付ける方針

### 3.2 画面構造

```
NavigationStack
└─ CalendarView (月カレンダー)
    ├─ 月ヘッダー (前後切替、"今日" ボタン)
    │   └─ 月内の重要予定数 + 平均スコア
    ├─ 月グリッド (6週 × 7曜日)
    │   ├─ 日付
    │   ├─ スコアバッジ
    │   └─ 重要な予定ラベルのみ
    │       └─ 日 tap → NavigationLink → CalendarDayView(date)
    └─ horizontal drag → 前後月切替

CalendarDayView (デイビュー / 全画面)
├─ 日ヘッダー
│   └─ 重要予定数 / 時間つき予定数
├─ スコアカード
│   └─ 日付と重要予定エリアの間に大きく表示
├─ 重要な予定エリア
│   ├─ important plan tap → PlanCreateSheet(plan:) で編集
│   ├─ context menu → 編集/削除
│   └─ 空なら "重要な予定を追加"
├─ TimelineView(date)
│   ├─ chapter tap → ChapterEditSheet
│   ├─ plan tap → PlanCreateSheet(plan:) で編集
│   ├─ 空白 tap → PlanCreateSheet（予定のみ。カレンダーからチャプター作成はしない）
│   └─ context menu → 編集/削除/公開設定
├─ horizontal swipe → 前後日切替
└─ ツールバー
    ├─ 公開設定ボタン (該当日の Chapter 一括公開設定)
    └─ + menu
        ├─ 重要な予定を追加
        └─ 時間つき予定を追加
```

### 3.3 重要な予定

現行実装では `PlanBlock.isImportant == true` を重要な予定として扱う。互換性のため `PlanBlock.isAllDay == true` も重要予定として表示するが、意味は分離する。

- 月グリッドに表示するのは重要な予定だけ
- `isAllDay == true`: 時間未指定の予定
- `isImportant == true`: カレンダー俯瞰に出す重要な予定
- 時間つき予定 (`isAllDay == false`) でも `isImportant == true` なら月グリッドに表示し、開始時刻をラベルに含める
- 重要な予定は複数日にまたがってよい
- DB上は分割せず、`startTime` から `endTime` まで1件で保存する
- 月表示では日ごとにクリップして表示し、開始日/終了日だけ角を丸めることで繋がりを表現する
- 友達機能では将来、選択した友達の重要な予定だけを重ねる方向で検討する。24時間予定全体の重ね表示は情報量が多すぎるため優先しない

### 3.4 状態管理

```swift
struct CalendarView: View {
    @Environment(ChapterStore.self) private var store
    @State private var visibleMonth = Date()
}

struct CalendarDayView: View {
    @Environment(ChapterStore.self) private var store
    @State private var date: Date
    @State private var editingChapter: Chapter?
    @State private var editingPlan: PlanBlock?
    @State private var pendingPlanStartsAsImportant = false
}
```

`CalendarDayView` から渡す `TimelineView` は `allowsChapterCreation: false` にする。既存チャプターの閲覧/編集は残すが、カレンダー画面を記録開始の入口にはしない。

### 3.5 EventKit 連携（将来）

外部カレンダーは、まず Liminalog の計画データへ変換して扱う方針。

| 外部予定の種類 | Liminalog 側の扱い |
|---|---|
| 終日 / 時間未指定 | 時間未指定の重要予定 (`isAllDay == true`, `isImportant == true`) |
| 時間指定 | 時間つき予定 (`isAllDay == false`)。重要なら `isImportant == true` を付けて月カレンダーにも表示 |

優先順位は友達機能より低い。実装時は `sourceEventID` / `sourceCalendarID` / `lastSyncedAt` / `isImported` 相当のメタデータを持たせ、二重取り込みと同期衝突を避ける。

### 3.6 予定作成のカテゴリ選択

`PlanCreateSheet` のカテゴリ選択は通常 Picker ではなく、CategorySet 別の色付きグリッドモーダルで行う。

- 予定用カテゴリが増える前提で、全カテゴリの長いリストから探させない
- 「休日」「病院」「学校」など、用途別 CategorySet を横切替して選ぶ
- セット内はホームのカテゴリグリッドと同じ 4x2 スロット表示にする
- セット外カテゴリは「その他」として下部に出す
- 選択済みカテゴリは色・アイコン・チェックで示す

### 3.7 空状態

| 状況 | 表示 |
|------|------|
| 月に重要予定/スコアなし | カレンダーセルは日付だけ表示 |
| 日に重要予定なし | 重要な予定エリアに追加ボタン |
| 日に時間つき予定/実績なし | TimelineView の空白カードから追加 |
| EventKit 拒否（将来） | 連携部分のみ非表示 + 設定誘導 |

---

## 4. 統計タブ（ダッシュボード）

### 4.1 画面構造

```
NavigationStack
└─ DashboardView
    ├─ Picker: 今日 / 週間 / 月間 / 年間
    ├─ ScrollView
    │   ├─ PeriodHeader (期間表示)
    │   ├─ [今日] TodayScoreCard
    │   ├─ SummaryStrip
    │   ├─ CategoryActivityRings  (新規)
    │   ├─ CategoryDonutChart     (新規)
    │   ├─ HourHeatmap or 24時間ブロック (再設計)
    │   ├─ [週間/月間/年間] StackedBarChart
    │   ├─ [週間] TimeOfDayBreakdown
    │   ├─ [週間/月間] DiffBarChart (先週/先月比)
    │   ├─ [月間/年間] CalendarHeatmap
    │   ├─ [月間] CategoryLineChart
    │   └─ RecentTrendCard
    └─ ツールバー: 表示順カスタマイズ → DashboardCustomizeSheet (Phase 2 後半)
```

### 4.2 カード表示順のカスタマイズ

- `UserSettings.dashboardCardOrder: [String]` でカードのキーを並び順保持
- `DashboardView` は配列の順序通りにカードを描画
- `DashboardCustomizeSheet` で並び替え・表示/非表示を操作

### 4.3 アニメーション戦略

- カード初回表示時に数字が 0 → 実値へカウントアップ
- 横棒・リング・ドーナツも `0` から実値へアニメ
- 期間切替時はカードを差し替えるだけ（連続アニメは Phase 4）

### 4.4 状態管理

```swift
struct DashboardView: View {
    @Environment(AppStores.self) private var stores
    @State private var period: DashboardPeriod = .today
    @State private var showingCustomize = false
    @Query private var chapters: [Chapter]  // 期間で動的に絞る
}
```

`@Query` のフィルター式を動的に変える: `init(period:)` で `Query(filter:)` を構築するイニシャライザを用意。

### 4.5 空状態

| 期間 | 状況 | 表示 |
|------|------|------|
| 今日 | 記録ゼロ | 「最初の記録でスコアが表示されます」 |
| 週間 | 7日間ゼロ | 「1日でも記録があると比較できます」 |
| 月間/年間 | 同上 | 同上 |

---

## 5. 友達タブ（Phase 3）

### 5.1 画面構造

```
NavigationStack
└─ FriendsView
    ├─ RankingScrollStrip
    │   ├─ Picker: 今日 / 昨日 / 今週
    │   └─ 横スクロール: アイコン + 達成率 + 順位
    │       └─ tap → FriendDetailView (デイビュー)
    ├─ Section "お気に入り"
    │   └─ FriendListRow → tap → FriendDetailView
    └─ Section "友達"
        └─ FriendListRow (達成率・現在ステータス)

FriendDetailView
├─ ヘッダー: アイコン・名前・自己紹介
├─ Picker: 日付選択
├─ TimelineView(friend: friend, date:) (公開設定でフィルター済)
├─ ReactionBar (絵文字パレット)
└─ CommentSection

FriendsAddView (シート)
├─ 友達のメール/iCloud で検索
├─ "招待を送る" → CKShare 招待
└─ "受信した招待" リスト → 承諾/拒否

FriendCategoryMappingSheet
└─ 自分のカテゴリ × 友達のカテゴリ マッピング
```

### 5.2 CloudKit 権限ゲート

```
iCloud アカウント状態を確認
├─ .available → 通常表示
├─ .noAccount → 「iCloudにログインしてください」+ 設定誘導
├─ .restricted → 「親管理で制限されています」
└─ .couldNotDetermine → リトライUI
```

### 5.3 状態管理

```swift
struct FriendsView: View {
    @Environment(AppStores.self) private var stores
    @Query(filter: #Predicate<Friend> { $0.status == .accepted })
    private var friends: [Friend]
    @State private var rankingPeriod: RankingPeriod = .today
    @State private var showingAdd = false
}
```

### 5.4 空状態

| 状況 | 表示 |
|------|------|
| 友達ゼロ | 「友達を招待してスコアで競おう」+ 招待 CTA |
| 受信招待あり | 上部に「N件の招待があります」バナー |

---

## 6. プロフィールタブ

### 6.1 画面構造（再設計）

現状は `ProfileView` に設定リンクが押せないラベルで並んでいる。再設計:

```
NavigationStack
└─ ProfileView
    ├─ HeaderCard: アイコン・名前・自己紹介
    │   └─ tap → ProfileEditSheet
    ├─ Section "アンロック"
    │   └─ UnlockProgressGrid → tap → UnlockGalleryView
    ├─ Section "サマリー"
    │   ├─ 今日のスコア
    │   ├─ ストリーク (🔥アイコン付き)
    │   ├─ 累計スコア
    │   ├─ 総チャプター
    │   ├─ 記録継続日数
    │   └─ 友達数 (Phase 3)
    └─ Section "設定"
        ├─ NavigationLink → SettingsView
        └─ (他にメニュー不要 — SettingsView 配下に集約)

SettingsView
├─ Section "記録"
│   ├─ NavigationLink → CategorySettingsView
│   ├─ NavigationLink → CategorySetManagementView
│   └─ 日付境界は 0:00-24:00 固定（Picker は置かない）
├─ Section "表示"
│   ├─ NavigationLink → ThemePickerView
│   ├─ Toggle: タイムラインに予定を薄く表示
│   └─ NavigationLink → DashboardCustomizeView
├─ Section "連携"
│   ├─ Toggle: カレンダー連携
│   ├─ Toggle: 通知
│   └─ Toggle: 位置情報の自動取得
├─ Section "友達" (Phase 3)
│   ├─ NavigationLink → VisibilityPresetManagementView
│   ├─ NavigationLink → WidgetFriendsView
│   └─ NavigationLink → FriendCategoryMappingsView
├─ Section "データ"
│   ├─ NavigationLink → ExportView
│   └─ Button: キャッシュをクリア
└─ Section "アプリ情報"
    ├─ バージョン
    ├─ プライバシーポリシー
    └─ お問い合わせ
```

### 6.2 状態管理

```swift
struct ProfileView: View {
    @Environment(AppStores.self) private var stores
    @Query private var settings: [UserSettings]
    @State private var showingEditProfile = false
}
```

---

## 7. シート vs フルスクリーンカバー 使い分け

| 種類 | 使用シーン | 例 |
|------|----------|-----|
| `.sheet` | データ編集・短時間入力 | ChapterEditSheet, CategoryEditSheet, VisibilitySheet |
| `.sheet (.large detent)` | リスト選択・複雑入力 | CategorySetSwitcher, CategorySetEditSheet |
| `.fullScreenCover` | 没入体験・モード変更 | カレンダーの月→デイビュー…ではなく NavigationLink でOK |
| `NavigationLink` | 階層的なドリルダウン | CalendarView → CalendarDayView, SettingsView 配下全て |

**判断基準**: 「閉じたら元の文脈に戻る」がシート、「次の場所に進む」が NavigationLink。

---

## 8. 公開設定 UI のフロー（Phase 1 で最低限実装）

### 8.1 アクセスポイント

```
ホーム画面 CurrentChapterCard の公開アイコン
   → VisibilitySheet (現在のチャプター)

タイムラインの chapter context menu "公開設定"
   → VisibilitySheet (該当チャプター)

カレンダーデイビューのツールバー
   → VisibilitySheet (該当日全体)

設定画面 → VisibilityPresetManagementView (Phase 3 で本格化)
```

### 8.2 VisibilitySheet の内容（Phase 1 最小版）

```
- 公開トグル (isPublic)
- "プリセットを使う" (Phase 3 で展開)
```

Phase 3 で「プリセット選択」「カスタム」「翌日公開」「カテゴリ別」を追加していく。

---

## 9. エラー・ローディング表現

### 9.1 ローディング

| 場面 | 表現 |
|------|------|
| アプリ初回起動 (Store 生成中) | `ProgressView()` を中央表示 |
| CloudKit 初回同期 | 各画面の右上に小さなスピナー (バナーは出さない) |
| 写真の読み込み | サムネイル枠内 `ProgressView()` |

### 9.2 エラー

| 種類 | 表現 |
|------|------|
| ネットワーク断 | バナーなし（CloudKit は静かにキューに溜める） |
| iCloud 容量不足 | バナー: 「iCloud容量が不足しています」 + 設定誘導 |
| 同期エラー（恒久的） | バナー: 「同期に問題があります」 + 詳細リンク |
| EventKit 拒否 | カレンダー画面のインライン CTA |
| Live Activity 起動失敗 | サイレント (DEBUG のみ print) |
| ウィジェット記録失敗 | ウィジェット内で `❌` 表示 + アプリ起動で詳細 |

### 9.3 PermissionGate コンポーネント

```swift
struct PermissionGate<Content: View>: View {
    let permission: Permission
    let onRequest: () async -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch permission.state {
        case .granted: content()
        case .notDetermined:
            ContentUnavailableView("...", systemImage: "...", description: ...)
                .overlay { Button("許可する") { Task { await onRequest() } } }
        case .denied:
            ContentUnavailableView("...", systemImage: "...", description: ...)
                .overlay { Button("設定を開く") { openSettings() } }
        }
    }
}
```

---

## 10. シート/NavigationLink の状態遷移図（ホーム例）

```
HomeView (Root)
  │
  ├─ tap カテゴリボタン → store.chapter.start()
  │   (画面遷移なし、CurrentChapterCard が即更新)
  │
  ├─ tap "+" → showingCreateSheet = true
  │   └─ ChapterCreateSheet
  │       ├─ "保存" → store.chapter.add() → dismiss
  │       └─ "キャンセル" → dismiss
  │
  ├─ tap chapter (タイムライン) → editingChapter = chapter
  │   └─ ChapterEditSheet
  │       ├─ "保存" → store.chapter.save() → dismiss
  │       ├─ "削除" → confirmation → store.chapter.delete() → dismiss
  │       └─ "キャンセル" → dismiss
  │
  ├─ tap 公開設定 (CurrentChapterCard) → showingVisibilitySheet = true
  │   └─ VisibilitySheet
  │       └─ トグル → 即保存 (dismiss は手動)
  │
  └─ tap "もっと見る" → showingSetSwitcher = true
      └─ CategorySetSwitcher
          ├─ select set → activeSetIDString = id → dismiss
          └─ "新規セット" → CategorySetEditSheet (シート on シート は NG → 一度 dismiss してから push)
```

**シート on シートの回避**: `CategorySetSwitcher` 内で「新規セット」を選んだら、`CategorySetSwitcher` を dismiss 後 0.3秒待って `CategorySetEditSheet` を出す。または `CategorySetSwitcher` 内で `NavigationStack` を持ち、push 遷移にする。

---

## 11. 通知ハンドリング

| 通知 | タップ時挙動 |
|------|------------|
| 「今日のスコアが出ました」 | ProfileView または DashboardView の「今日」を表示 |
| 「ストリーク◯日達成」 | ProfileView |
| 「ストリークが途切れそうです」 | ProfileView |
| 「友達から招待」 (Phase 3) | FriendsView の招待リスト |
| 「翌日公開しました」 (Phase 3) | CalendarDayView (前日) |

→ Deep link は `liminalog://` URLスキーム + `Onenter URL Handler` で実装。Phase 1 では通知自体なし。
→ 2026-06-02: 「ストリークが途切れそうです」は、通知許可済みの場合のみ起動時に `streak-break-warning` を1件差し替える。前日までに60点以上ストリークがあり、今日の予定があり、今日が60点未満の夜だけ対象。初回許可UI/設定Toggleは別タスク。

---

## 12. 画面ごとの責任 Store マップ

| 画面 | 主に使う Store | 補助 |
|------|--------------|------|
| HomeView | ChapterStore (start) | CategoryStore, CategorySetStore (read via @Query) |
| ChapterEditSheet | ChapterStore (save/delete) | CategoryStore |
| CategoryGrid | (read via @Query) | ChapterStore (start) |
| CalendarView | (read via @Query) | — |
| CalendarDayView | ChapterStore, PlanStore | EventKitStore |
| DashboardView | ScoreStore | (read via @Query) |
| FriendsView (Phase 3) | ShareCoordinator | (read via @Query) |
| ProfileView | ScoreStore | (read via @Query for stats) |
| SettingsView | UserSettings 直接 | 全 Store |
| Widget | (App Groups 経由で SwiftData read) | StartChapterIntent → ChapterStore |

---

## 次のドキュメント

→ [06-testing.md](06-testing.md): ここまでの設計をどう守るかのテスト方針
