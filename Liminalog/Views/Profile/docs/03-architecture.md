# 03. アーキテクチャ方針

> [02-gap-analysis.md](02-gap-analysis.md) で抽出したギャップ・アーキ負債を踏まえ、Phase 1〜4 を見据えた設計方針を確定する。
> このドキュメントは「これからどう作るか」を決める意思決定文書。詳細設計は [04-data-model.md](04-data-model.md) / [05-screen-flow.md](05-screen-flow.md) に分離する。

> Codexレビューあり: 実装前に [07-codex-plan-review.md](07-codex-plan-review.md) を必ず確認すること。
> 特に SwiftData/CloudKit、CKShare、Widget 実装順、App Group ID は本ドキュメント初版から修正が必要。

---

## 0. 設計の原則

1. **ローカルファーストを徹底**: SwiftData がストアの主、CloudKit はその同期手段
2. **CloudKit 後付けは禁止**: Phase 1 から CloudKit 互換スキーマで構築する
3. **Apple 純正の力を信じる**: TCA や RxSwift のような重厚なフレームワークは入れず、Observation / SwiftData の標準機能で完結させる
4. **責務分割は「成長してから」ではなく「成長する前に」**: ChapterStore の God 化は今のうちに解体する
5. **ウィジェット拡張をファーストクラスに**: 記録導線はウィジェット起点が仕様なので、Day 1 から App Groups + 共有モデルで作る

---

## 1. ターゲット構成とコード共有

```
Liminalog.xcworkspace
├── Liminalog.xcodeproj
│   ├── Liminalog (App target)
│   │   └─ App/Views/ のみを抱える
│   └── LiminalogWidget (Widget Extension target)
│       └─ Widget専用UI のみを抱える
└── Packages/
    ├── LiminalogCore/         (Swift Package)
    │   ├── Sources/Models/    (@Model 群)
    │   ├── Sources/Stores/    (分割された各 Store)
    │   ├── Sources/Logic/     (ScoreCalculator, DayBoundary, StreakCalculator)
    │   ├── Sources/Sync/      (CloudKitSyncCoordinator, ShareCoordinator)
    │   ├── Sources/Activity/  (LiveActivityManager, ActivityAttributes)
    │   └── Sources/Extensions/(Color+Hex, Date+Formatting)
    └── LiminalogUI/           (Swift Package)
        ├── Sources/Components/(共通カード・ボタン・タイムライン)
        └── Sources/Theme/     (カラーシステム・タイポグラフィ)
```

**理由**
- ウィジェットとアプリの両方が `Models` `Logic` `Extensions` を必要とするので、共有が必須
- Swift Package にすると Xcode の依存解決が明示的になり、ビルド時間も改善
- UI コンポーネントを分離することで、`LiminalogCore` のテストにビュー依存を持ち込まずに済む

**段階移行**
- 記録グリッドウィジェットは Widget Extension 側から Models / Store 書き込みロジックを使うため、Widget 実装より先に最小 `LiminalogCore` を作る
- 最初に移すのは `Models` / `Logic` / `SharedModelContainer` / `ChapterWriter` 相当の最小セットだけでよい
- `LiminalogUI` の本格分離は後続。UI コンポーネント抽出を急いで Phase 1 の画面修正を重くしない

---

## 2. App Groups と共有 ModelContainer

### App Group 設定
- Group ID 候補: `group.app.YasudaRyuga.Liminalog` （現 Bundle ID `app.YasudaRyuga.Liminalog` ベース。最終確定はユーザー判断）
- CloudKit Container 候補: `iCloud.app.YasudaRyuga.Liminalog`
- アプリ・ウィジェット両方の Capability に追加

### ModelContainer の生成統一

```swift
// LiminalogCore/Sources/Sync/SharedModelContainer.swift
public enum SharedModelContainer {
    public static func make() -> ModelContainer {
        let schema = Schema([
            Category.self, CategorySet.self, Chapter.self,
            PlanBlock.self, VisibilityPreset.self,
            Friend.self, Reaction.self, /* Phase 3 で追加 */
        ])
        let configuration = ModelConfiguration(
            "Cloud",
            schema: schema,
            groupContainer: .identifier("group.app.YasudaRyuga.Liminalog"),
            cloudKitDatabase: .private("iCloud.app.YasudaRyuga.Liminalog")  // Phase 1 から有効
        )
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}
```

**ポイント**
- アプリ・ウィジェット両方で `SharedModelContainer.make()` を呼ぶ
- CloudKit 同期は Phase 1 から ON にする。マルチデバイス（自分の iPhone + iPad）対応に効くため
- Phase 1 の SwiftData CloudKit は本人の private DB 同期だけを担当する
- CKShare による友達共有 (Phase 3) は SwiftData managed sync と混ぜず、`ShareCoordinator` が CloudKit API で扱う（[04-data-model.md](04-data-model.md) で詳述）

---

## 3. ストア分割方針

現状の God `ChapterStore` を以下のように責務単位で分割する。

| 新Store | 旧Store からの移譲 |
|---------|------------------|
| **ChapterStore** | Chapter CRUD / Query / 1分ルール / activeChapter |
| **CategoryStore** | Category CRUD / Query / グリッド優先順位 / シード |
| **CategorySetStore** | CategorySet CRUD / Query / シード |
| **PlanStore** | PlanBlock CRUD / Query |
| **ScoreStore** | scoreSummary / streakCount / totalScore（内部で `ScoreCalculator` を呼ぶ） |
| **LiveActivityCoordinator** | updateLiveActivity 全般（旧 LiveActivityManager と統合） |
| **EventKitStore** | EventKit権限・予定の読み書き（Phase 2 で追加） |
| **CloudKitSyncCoordinator** | CloudKit アカウント状態・同期エラー監視（Phase 1 から最小実装） |
| **ShareCoordinator** | CKShare 作成・参加・受諾（Phase 3 で追加） |
| **UnlockStore** | UnlockItem 状態・解放判定（Phase 2 で追加） |

### 注入パターン

```swift
// LiminalogCore/Sources/Stores/AppStores.swift
@MainActor
@Observable
public final class AppStores {
    public let chapter: ChapterStore
    public let category: CategoryStore
    public let categorySet: CategorySetStore
    public let plan: PlanStore
    public let score: ScoreStore
    public let liveActivity: LiveActivityCoordinator
    public let sync: CloudKitSyncCoordinator
    // Phase 2/3 で追加
}

// LiminalogApp.swift
@main
struct LiminalogApp: App {
    @State private var stores: AppStores?
    var body: some Scene {
        WindowGroup {
            if let stores {
                RootTabView()
                    .environment(stores)
            } else {
                ProgressView().task { stores = AppStores.bootstrap() }
            }
        }
        .modelContainer(SharedModelContainer.shared)
    }
}
```

- 各ビューは `@Environment(AppStores.self).chapter` のように必要な Store だけ参照する
- 単一の `AppStores` を環境注入することで、ビューの宣言で全 Store を列挙する必要なし

---

## 4. 状態管理戦略

### 4.1 `@Query` を主軸にする

現状の `store.revision` 手動カウンタは廃止し、SwiftData の `@Query` を一級市民として使う。

```swift
struct HomeView: View {
    @Query(filter: #Predicate<Chapter> { $0.endTime == nil })
    private var activeChapters: [Chapter]

    @Environment(AppStores.self) private var stores
    // ChapterStore は mutation 用途のみ
}
```

**利点**
- SwiftData が変更を観察して自動で再描画
- CloudKit からの非同期更新も同じ経路で反映される
- 手動 revision の通知漏れ・無駄な再フェッチがなくなる

**Store の役割**
- Store はもう「読む」役割を持たない（ビュー直接 `@Query`）
- Store は「書く」役割 + 「複雑な集計（スコア計算等）」のみ
- 集計結果も可能なら `@Query` + computed property で済ませる

### 4.2 例外: タイマー駆動の派生状態

タイムラインの「現在時刻バー」や「経過時間」は SwiftData の外。

```swift
// 専用 Observable
@Observable @MainActor
final class TickClock {
    private(set) var now = Date()
    private var task: Task<Void, Never>?
    func start(interval: Duration = .seconds(30)) {
        task?.cancel()
        task = Task { while !Task.isCancelled { try? await Task.sleep(for: interval); now = Date() } }
    }
    func stop() { task?.cancel(); task = nil }
}
```

→ `TimelineView` で `@State private var clock = TickClock()` を持ち、`.onAppear { clock.start() }`

### 4.3 シート/モーダルの状態管理

- 各画面ローカルの `@State` で完結させる（NavigationDestination + Sheet 制御）
- 横断的なナビゲーション（タブをまたぐ深いリンク）が必要になったら `NavigationCoordinator` を導入。Phase 1 では不要

---

## 5. ウィジェットの設計

### 5.1 静的ステータスウィジェット → 削除 or 退役
- 現状の `LiminalogStatusWidget` は情報量が薄いので、記録グリッドが完成したら廃止
- もしくは「ステータス + ミニグリッド」として Medium だけに集約

### 5.2 記録グリッドウィジェット（Phase 1 必達）

```swift
// LiminalogWidget/RecordingGridWidget.swift
struct RecordingGridWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "RecordingGridWidget",
            intent: SelectCategorySetIntent.self,
            provider: RecordingGridProvider()
        ) { entry in
            RecordingGridView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// AppIntent
struct StartChapterIntent: AppIntent {
    static var title: LocalizedStringResource = "カテゴリで記録開始"
    @Parameter(title: "カテゴリID") var categoryID: String
    func perform() async throws -> some IntentResult {
        let stores = AppStores.bootstrap()  // ModelContainer は App Groups で共有済
        try stores.chapter.startChapter(categoryID: UUID(uuidString: categoryID)!)
        return .result()
    }
}

// View 内
Button(intent: StartChapterIntent(categoryID: category.id.uuidString)) {
    CategoryGridButton(category: category)
}
```

**ポイント**
- iOS 17+ の Interactive Widget (AppIntent) を使う
- `StartChapterIntent.perform()` がウィジェット拡張側で動くため、App Groups 経由の SwiftData 書き込みが必要
- `WidgetCenter.shared.reloadAllTimelines()` をアプリ側 mutation 後に呼んで反映同期

### 5.3 Live Activity の改修
- `LiminalogActivityAttributes.ContentState` から `categories` 配列を削除
- カテゴリ一覧はウィジェット側で App Groups の SwiftData から読む
- ContentState は「現在のチャプター情報」のみに絞る（軽量化）

---

## 6. CloudKit 同期戦略

### 6.1 Phase 1 — 自分のデータのマルチデバイス同期
- `cloudKitDatabase: .private("iCloud.app.YasudaRyuga.Liminalog")` のみ
- iCloud アカウント未ログイン時はローカル動作にフォールバック
- 同期エラーは `CloudKitSyncCoordinator` で監視・通知（ユーザー向けバナー UI）

### 6.2 Phase 3 — 友達との CKShare 共有
詳細は [04-data-model.md](04-data-model.md) と将来の `cloudkit.md` に分離。原則だけここに記す:
- **実装境界**: SwiftData managed sync に任せず、`ShareCoordinator` が CKRecord / CKShare を明示的に扱う
- **シェア対象**: 公開設定された Chapter / PlanBlock をそのまま共有するか、SharedTimeline / DTO へ変換するか Phase 3 で検証
- **シェア方式**: 1対1の `CKShare` × 友達数（双方向）を第一候補
- **承認制**: CKShare のメタデータ受諾フローを使う
- **公開設定**: 「翌日公開」はバックグラウンドタスクでスナップショット化する
- **リアクション/コメント**: 保存先は Phase 3 の `cloudkit-sharing.md` で確定する

### 6.3 Phase 2/3 で詳細を詰める
このドキュメントでは「**Phase 1 から CloudKit ON にしておくことが重要**」というスタンスだけ確定。
SwiftData の private DB 同期と CKShare 友達共有の境界を守り、ゾーンや CKShare のスキーマ詳細は Phase 3 で検証してから確定する。

---

## 7. ドメインロジックの集約

### 7.1 純粋関数群（`LiminalogCore/Logic/`）

| ファイル | 責務 |
|---------|------|
| `ScoreCalculator.swift` | スコア算出（現状を移植） |
| `StreakCalculator.swift` | ストリーク算出（ChapterStore から抽出） |
| `DayBoundary.swift` | 0:00-24:00 固定の dayStart/dayEnd を一元化 |
| `CategorySlotResolver.swift` | CategorySet の 8 スロットを Category 配列へ解決 |
| `UnlockRules.swift` | 累計スコア → アンロックアイテムの判定 |

→ 全て `enum` の static method（インスタンス不要）。100% ユニットテスト可能。

### 7.2 DayBoundary は 0:00-24:00 固定

```swift
public struct DayBoundary {
    public let calendar: Calendar

    public func dayStart(for date: Date) -> Date { /* ... */ }
    public func dayEnd(for date: Date) -> Date { /* ... */ }
    public func enclosingDay(of date: Date) -> (start: Date, end: Date)
}
```

現行仕様では「1日」は 0:00-24:00 固定とする。
ユーザーが1日の始まり時間を変更する機能は、スコア・ランキング・共有・タイムラインの解釈を揺らすため Phase 0/2 の対象外。
数年単位の大きなアップデートで再検討する将来候補としてのみ扱う。
`Calendar.current.startOfDay(for:)` を直接使っている箇所は、必要に応じて固定境界の `DayBoundary` に集約する。

---

## 8. 権限・エラーハンドリング戦略

| 権限 | 取得タイミング | 失敗時UX |
|------|--------------|---------|
| Notification | アプリ初回起動の onboarding | バナーで「通知でリマインドできます」と促す |
| EventKit | カレンダータブ初回タップ時 | 「連携には許可が必要です」とインライン CTA |
| Location | 「場所を自動取得」をユーザーが ON にした時のみ | OFF にフォールバック |
| Photo Library | チャプターに写真添付時 | アクセス制限モードもサポート |
| iCloud | アプリ起動時に静かにチェック | 未ログインなら設定アプリへの誘導バナー |

→ 権限取得とエラー UI は `PermissionGate` ビューに集約する（再利用可能なラッパー）。

---

## 9. デザインシステム雛形

仕様書の「カラフル・エネルギッシュ」を具体化するため、最小限のトークンを定義しておく。

```swift
// LiminalogUI/Theme/LiminalogColor.swift
public enum LiminalogColor {
    public static let primary = Color("Primary")        // Asset Catalog
    public static let accent = Color("Accent")
    public static let surface = Color("Surface")
    // ...
}

public enum LiminalogTypography {
    public static let titleLarge = Font.system(size: 28, weight: .black, design: .rounded)
    public static let scoreNumeric = Font.system(size: 36, weight: .black, design: .rounded).monospacedDigit()
    // ...
}
```

- Phase 1 は最小限のトークンだけ定義
- テーマ着せ替え（Phase 4）は `EnvironmentValues` 経由で差し替え可能にしておく

---

## 10. 移行ロードマップ

現状から本アーキテクチャに到達するための段階移行プラン。

### Step 1: 安全な準備（影響範囲小）
- [ ] App Groups / CloudKit Container の正式 ID を確定（候補: `group.app.YasudaRyuga.Liminalog`, `iCloud.app.YasudaRyuga.Liminalog`）
- [ ] `#if DEBUG seedPreviewPlansIfNeeded` / `seedDevSampleChaptersIfNeeded` を起動引数または環境変数ゲート化
- [ ] `DayBoundary` を導入し、0:00-24:00 固定の dayStart/dayEnd を一元化する
- [ ] `BootstrapStore` / `SeedCoordinator` を用意し、UserSettings / UnlockItem / built-in VisibilityPreset の重複を統合

### Step 2: 最小 Core 化（Widget 前提）
- [ ] `Packages/LiminalogCore` Swift Package を作成
- [ ] Models / Logic / SharedModelContainer / ChapterWriter 相当だけを先に移植
- [ ] App / Widget 両ターゲットから Core を参照できるようにする
- [ ] `SharedModelContainer` を `groupContainer:` + CloudKit private DB で実装し `LiminalogApp.modelContainer(...)` を置換

### Step 3: ストア分割
- [ ] `ChapterStore` を 5〜6 個に分割（CategoryStore, PlanStore, ScoreStore, LiveActivityCoordinator）
- [ ] `AppStores` ハブ Observable を作成、`.environment(stores)` を一段化
- [ ] 各ビューで `@Environment(AppStores.self).xxx` に書き換え
- [ ] revision カウンタを段階的に削除し `@Query` へ移行

### Step 4: ウィジェット改修
- [x] `RecordingGridWidget` + `StartChapterIntent` 実装（2026-05-28 Codex）
- [x] `LiminalogStatusWidget` を退役（or グリッド統合）（2026-05-28 Codex: Bundle から外し RecordingGridWidget をメイン化）
- [x] `LiveActivityAttributes` から categories を削除し、ウィジェット側で SwiftData 読み込みに変更（2026-05-28 Codex: Live Activity は軽量化、RecordingGridWidget は App Group SwiftData を読む）

### Step 5: UI Package 化
- [ ] `LiminalogUI` Swift Package を作成、共通コンポーネント抽出
- [ ] App / Widget で共有したい UI 部品だけ移植

### Step 6: テスト基盤
- [ ] テストターゲット追加
- [ ] ScoreCalculator / StreakCalculator / DayBoundary（0:00固定）/ CategorySlotResolver の単体テスト
- [ ] 詳細は [06-testing.md](06-testing.md)

---

## 11. 確定した決断（後戻りしない）

| 決断 | 理由 |
|------|------|
| SwiftData + CloudKit Private DB を Phase 1 から使う | 後付け移行のコストが大きい |
| App Groups を Phase 1 から有効化 | 記録グリッドウィジェットの前提 |
| Swift Package で Core / UI を分離 | コード共有・ビルド時間・テスト容易性 |
| `@Query` 主軸 + Store は mutation 担当 | revision カウンタの破綻回避 |
| Interactive Widget (AppIntent) で記録 | iOS 17+ 公式パス。タッチ → アプリ起動を経由しない |
| TCA / RxSwift など第三者 FW を導入しない | Observation / SwiftData で十分・依存最小化 |
| God Store を Phase 1 完了前に分割 | Phase 3 で詰む |

---

## 12. 未確定の論点（後続ドキュメントで判断）

| 論点 | 扱う場所 |
|------|---------|
| CKShare のレコードゾーン設計・複製戦略 | [04-data-model.md](04-data-model.md) |
| Friend / Reaction / Comment の詳細スキーマ | [04-data-model.md](04-data-model.md) |
| 各画面の正確な遷移図・シート階層 | [05-screen-flow.md](05-screen-flow.md) |
| カレンダー予定とチャプターの混在表示 UX | [05-screen-flow.md](05-screen-flow.md) |
| ユニットテストの粒度・モック戦略 | [06-testing.md](06-testing.md) |
| デザイントークンの全体像（カラーシステム） | 別途 `design-system.md` を作るか検討 |

---

## 次のドキュメント

→ [04-data-model.md](04-data-model.md): 本方針を前提とした SwiftData / CloudKit スキーマ詳細
