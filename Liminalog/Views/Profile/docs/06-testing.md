# 06. テスト方針

> 現状テスト 0 件。[03-architecture.md](03-architecture.md) で確定したアーキテクチャを守るためのテスト戦略を定義する。
> 目的は「カバレッジを稼ぐ」ではなく、「壊れたら困る部分を機械的に保証する」「設計の劣化を検知する」。

> Codexレビューあり: 実装前に [07-codex-plan-review.md](07-codex-plan-review.md) を必ず確認すること。
> `SeedCoordinatorTests`、`ActiveChapterResolutionTests`、Dashboard 期間切替、CloudKit unique 非使用時の重複統合テストを追加する。

---

## 0. 基本方針

1. **テストは投資。回収できる場所に書く** — 純粋ロジックと公開API（Store）には厚く、UI 末端には書かない
2. **SwiftData/CloudKit 依存はテスト用 in-memory コンテナで隔離**
3. **SwiftUI ビューは Preview を「動く仕様書」として扱い、E2E まではしない**
4. **テストは速さで判断される** — 1ファイル合計で 5秒以内に終わる粒度を維持
5. **CI を前提に書く** — マシン依存の Date 比較や時刻依存テストは `TestClock` 化

---

## 1. テストターゲット構成

```
Liminalog.xcodeproj
├── Liminalog              (App target)
├── LiminalogWidget        (Widget Extension)
├── LiminalogTests         (Unit Tests — App + Core)
│   ├── Logic/
│   │   ├─ ScoreCalculatorTests.swift
│   │   ├─ StreakCalculatorTests.swift
│   │   ├─ DayBoundaryTests.swift
│   │   ├─ CategorySlotResolverTests.swift
│   │   └─ UnlockRulesTests.swift
│   ├── Stores/
│   │   ├─ ChapterStoreTests.swift
│   │   ├─ CategoryStoreTests.swift
│   │   ├─ PlanStoreTests.swift
│   │   └─ ScoreStoreTests.swift
│   ├── Sync/
│   │   └─ CloudKitSyncCoordinatorTests.swift
│   └── Helpers/
│       ├─ SeedCoordinatorTests.swift
│       ├─ ActiveChapterResolutionTests.swift
│       ├─ DashboardPeriodQueryTests.swift
│       ├─ TestModelContainer.swift
│       └─ TestClock.swift
└── LiminalogUITests       (UI Tests — Phase 2 以降、最低限のみ)
    └── SmokeTests.swift
```

**Swift Package 化後** (Phase 1 完了時):
- `LiminalogCore` に独自のテストターゲット `LiminalogCoreTests` を内包
- `LiminalogTests` はアプリ固有の統合のみ扱う

---

## 2. テストフレームワーク選定

**Swift Testing (`import Testing`)** を採用。

理由:
- iOS 17+ 対応で本プロジェクトの最低ターゲットと整合
- `@Test` / `#expect` の宣言的 API、並列実行、パラメータ化テストが優秀
- XCTest との混在も可能（必要なら）

例:
```swift
import Testing
@testable import LiminalogCore

@Suite("ScoreCalculator")
struct ScoreCalculatorTests {
    @Test("完全一致なら100点")
    func perfectMatch() {
        let summary = ScoreCalculator.summary(/* ... */)
        #expect(summary.totalScore == 100)
    }

    @Test("カテゴリ部分超過は切り捨て", arguments: [(60, 120, 50.0), (180, 120, 100.0)])
    func categoryOverflow(actual: Int, planned: Int, expected: Double) {
        // ...
    }
}
```

---

## 3. レイヤー別テスト粒度

| レイヤー | テスト範囲 | 粒度 | 理由 |
|---------|-----------|------|------|
| **Logic（純粋関数）** | 全てのケース・境界値 | 厚い | バグの温床になりがち + テストが書きやすく速い |
| **Store（mutation）** | 主要パス + エラーケース | 中 | 副作用ありなので確認は必要 |
| **Coordinator（CloudKit/EventKit）** | 主要パス、モック化 | 薄い | 外部依存。E2E は手動 |
| **View** | 書かない | — | Preview と手動確認で代替 |
| **Widget** | AppIntent の perform のみ | 薄い | UI は Preview |

---

## 4. ロジック層のテスト

### 4.1 ScoreCalculatorTests

カバーすべきケース:

- 予定ゼロ → スコア 0
- 予定通りに記録 → スコア 100
- カテゴリ達成のみ（時間軸ズレ） → スコア 80
- 時間軸±15分以内 → ペナルティなし
- 時間軸±15分超 → 部分点
- 超過カテゴリ → 100%扱い（切り捨て）
- 複数カテゴリの混在
- 日付またぎチャプター → クリッピング正常動作
- 仕様書記載の計算例2件をそのまま再現

→ パラメータ化テストで仕様書の事例を全部入れる。

### 4.2 StreakCalculatorTests

- 連続30点以上 N 日 → N
- 1日でも30点未満 → リセット
- 今日が予定ゼロ → ストリーク 0（カウントしない）
- 過去30日のサンプルデータで境界確認

### 4.3 DayBoundaryTests

- 0:00-24:00 固定の dayStart/dayEnd が `Calendar.startOfDay` と一致する
- 前日 23:00〜当日 02:00 の Chapter が、当日表示では 0:00〜2:00 にクリップされる
- 当日 23:00〜翌日 02:00 の Chapter が、当日表示では 23:00〜24:00 にクリップされる
- DST/タイムゾーン変更時の挙動（日本固定なので保留）

### 4.4 CategorySlotResolverTests

- `CategorySet.slots` の index 順に Category が返る
- `nil` スロットは空きとして保持される
- 削除済みカテゴリIDは `nil` として扱う
- 同じカテゴリIDが複数スロットに入った場合の扱い（最初だけ残す or そのまま表示）を仕様化
- `slots` が 8 件未満 / 9 件以上のとき `CategorySet.normalize` が 8 件へ補正する

### 4.5 DashboardPeriodQueryTests

- 今日 / 週間 / 月間 / 年間の date range が 0:00-24:00 固定の `DayBoundary` に従う
- period 切替時に古い `@Query` predicate が残らない設計になっている
- SwiftData predicate で表現しづらい optional `endTime` は、広めに fetch して Store / Logic 側で絞る
- 日付またぎチャプターが期間境界にかかる場合も含まれる

### 4.6 UnlockRulesTests

- 累計スコアが閾値到達 → 該当アイテム解放
- 既に解放済みのアイテムは無視
- 同時に複数解放されるケース
- 解放スケジュール 26件の整合性検証（マスターデータテスト）

---

## 5. Store 層のテスト

### 5.1 TestModelContainer ヘルパー

```swift
// LiminalogTests/Helpers/TestModelContainer.swift
@MainActor
enum TestModelContainer {
    static func make() -> ModelContainer {
        let schema = Schema([Category.self, Chapter.self, /* ... */])
        let config = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
```

### 5.2 ChapterStoreTests

- `startChapter` で activeChapter が更新される
- 同じカテゴリで `startChapter` を再実行 → 既存 active を維持し、新規 Chapter を作らない
- A を記録中に B へ切替 → A は `endTime = B.startTime` で終了し、B が active になる
- A→B→C が短時間でも A/B/C が別 Chapter として残る
- A→B→A が短時間でも B は自動削除されず、A は新しい Chapter として開始される
- active chapter が複数ある状態で `startChapter` → 同カテゴリ active は維持し、他 active は終了する
- `endActiveChapter` を 30秒以内に実行 → 1分未満でも削除せず終了記録を残す
- `addChapter` / 編集保存で既存 Chapter と重なる場合は保存をブロックする
- 日付またぎ Chapter は DB では1件のまま、表示・集計時だけ 0:00-24:00 にクリップされる
- `deleteChapter` でリレーション切断
- 全 mutation 後に `try modelContext.save()` が成功する

### 5.3 SeedCoordinatorTests

- `UserSettings(settingsKey: "default")` が 0 件なら作成される
- 同じ `settingsKey` が複数ある場合、1 件へ統合される
- `UnlockItem.key` が重複した場合、`unlockedAt` は最古を保持する
- built-in `VisibilityPreset.builtInKey` が重複した場合、1 件へ統合される
- CloudKit 同期対象モデルに `@Attribute(.unique)` を使わなくても、seed 後に論理一意性が保たれる

### 5.4 ScoreStoreTests

- `scoreSummary(on:)` が `ScoreCalculator` の結果を返す（薄いラッパーテスト）
- `streakCount(endingAt:)` の境界値

### 5.5 Coordinator のテスト

- `CloudKitSyncCoordinator`: モック `CKContainer` で `accountStatus` 各パターン
- `EventKitStore`: モック `EKEventStore` 不要（Apple純正でテストしにくいので手動確認）
- `LiveActivityCoordinator`: ActivityKit はテスト不可 → スキップ

---

## 6. TestClock 戦略

時刻依存テストは `Date()` を直接呼ばず、`Clock` プロトコルを注入する。

```swift
public protocol Clock {
    func now() -> Date
}

public struct SystemClock: Clock {
    public func now() -> Date { Date() }
}

public struct TestClock: Clock {
    public var fixedDate: Date
    public func now() -> Date { fixedDate }
}
```

`ChapterStore` 等が `Clock` を受け取る形に改修:

```swift
public init(modelContext: ModelContext, clock: any Clock = SystemClock()) {
    self.clock = clock
    // ...
}

func startChapter(category: Category) {
    let now = clock.now()
    // ...
}
```

テスト側:
```swift
let clock = TestClock(fixedDate: Date(timeIntervalSince1970: 0))
let store = ChapterStore(modelContext: ctx, clock: clock)
```

---

## 7. SwiftUI Preview 戦略

### 7.1 Preview を「動く仕様書」として整備

- 全ての主要ビューに最低1つの Preview
- 重要ビューには「空状態」「データあり」「エラー」「権限拒否」の最低3パターン

例:
```swift
#Preview("Home — データあり") {
    HomeView().liminalogPreviewEnvironment(seed: .standard)
}

#Preview("Home — 空状態") {
    HomeView().liminalogPreviewEnvironment(seed: .empty)
}

#Preview("Home — 記録中") {
    HomeView().liminalogPreviewEnvironment(seed: .activeChapter)
}
```

### 7.2 PreviewSupport の seed バリエーション

現状の `PreviewSupport` を拡張:

```swift
@MainActor
enum PreviewSeed {
    case empty       // データなし
    case standard    // 1日分の通常データ
    case activeChapter  // 現在記録中
    case heavy       // 1ヶ月分のヘビーユーザー
    case errorState  // エラー再現
}

extension View {
    func liminalogPreviewEnvironment(seed: PreviewSeed = .standard) -> some View {
        modelContainer(PreviewContainer.make(seed: seed))
            .environment(PreviewStores.make(seed: seed))
    }
}
```

### 7.3 Snapshot テストはしない（Phase 2 までは）

- 理由: SwiftUI のスナップショットは iOS/Xcode バージョンに脆弱で運用負荷が高い
- Phase 3 で「友達比較画像書き出し」が出てきたら、画像生成部分だけ snapshot 検討

---

## 8. CloudKit のテスト

### 8.1 CloudKit 本物との接続テストは書かない

- 理由: iCloud アカウント・ネットワーク・Apple ID 依存
- 代わりに `CloudKitSyncCoordinator` のロジックだけテスト

### 8.2 モック CKContainer

```swift
protocol CloudKitContainer {
    func accountStatus() async throws -> CKAccountStatus
    func subscribe(to: String) async throws
}

struct MockCloudKitContainer: CloudKitContainer {
    var statusToReturn: CKAccountStatus = .available
    func accountStatus() async throws -> CKAccountStatus { statusToReturn }
    // ...
}
```

`CloudKitSyncCoordinator` のテスト:
- アカウント未ログイン時のフォールバック
- 同期エラー時の retry 動作
- CKShare 受諾フロー（モックで結果のみ確認）

### 8.3 実機 CloudKit 確認はチェックリスト化

`docs/cloudkit-manual-checks.md` などに手動テスト手順を記載:
- 2台のデバイスで同じ iCloud アカウント → 自動同期確認
- iCloud オフライン → ログ確認
- 容量不足エラー再現

---

## 9. UI テスト（最小限）

`LiminalogUITests` には以下のみ書く（Phase 2 以降）:

| テスト | 目的 |
|--------|------|
| `launchTest` | アプリが crash せず起動する |
| `tabSwitch` | 5タブ全てに切り替えられる |
| `recordSmoke` | カテゴリタップ → 記録ができる |
| `deleteSmoke` | チャプター削除ができる |

> UI テストは遅く脆いので、重要なリグレッションだけ。詳細な挙動は Preview と Unit テストで保証。

---

## 10. テスト実行戦略

### 10.1 ローカル

```bash
xcodebuild test -scheme Liminalog -destination 'platform=iOS Simulator,name=iPhone 16'
```

開発中は Xcode の `Cmd+U` または `Cmd+Ctrl+Option+G`（直前のテストだけ実行）。

### 10.2 CI（将来）

GitHub Actions で push 時に:
- `xcodebuild test -scheme Liminalog -destination ...` を走らせる
- 失敗時に PR コメント

→ Phase 2 完了時に導入検討。Phase 1 中は手動でOK。

---

## 11. テスト導入ロードマップ

### Step 1: 基盤（Phase 1 移行中）
- [x] LiminalogTests ターゲット追加
- [x] Swift Testing 採用
- [x] TestModelContainer / TestClock ヘルパー作成
- [x] ScoreCalculatorTests を最初に書く（既存ロジックの仕様確定）

### Step 2: ロジック層完備（Phase 1 完了時）
- [x] StreakCalculator / DayBoundary / CategorySlotResolver のテスト（現実装では `ScoreStore.streakCount` と CategorySet 解決を対象）
- [~] ChapterStore の主要 mutation テスト（カテゴリ短時間切替・重複保存ブロック・active 収束は実装済み）
- [x] ActiveChapterResolutionTests
- [x] SeedCoordinatorTests
- [x] DashboardPeriodQueryTests

### Step 3: Preview 整備（Phase 1 完了時）
- [ ] 全画面に最低1つ Preview
- [ ] 重要画面に 3 バリエーション Preview
- [ ] PreviewSeed enum 導入

### Step 4: CloudKit / EventKit Coordinator テスト（Phase 2）
- [ ] モック化と境界テスト
- [ ] 手動チェックリスト作成

### Step 5: UI テスト（Phase 2 完了時）
- [ ] SmokeTests 4本
- [ ] CI 導入

---

## 12. 「書かない」ものの明文化

以下はテストを書かない:

- ❌ SwiftUI View の見た目（→ Preview）
- ❌ Color/Font/Padding の値（→ Preview / Design Review）
- ❌ NavigationLink の遷移先（→ UI テストで minimum smoke のみ）
- ❌ AppStorage の値（→ Apple純正）
- ❌ SwiftData の `@Query` 自体（→ Apple純正）
- ❌ EventKit / ActivityKit / CloudKit の Apple API そのもの

---

## 13. テスト品質の指標

カバレッジ率は **追わない**。代わりに以下を維持指標にする:

- ✅ 全 Logic 関数にテストがある（追跡: ファイル数 vs テストファイル数）
- ✅ 全 Store の mutation メソッドにテストがある
- ✅ 全 Preview がビルド可能（Xcode が自動チェック）
- ✅ テスト suite 全体の実行時間が 30 秒以内
- ✅ Flaky テストはゼロ（出たら即修正 or 削除）

---

## 関連ドキュメント

- [01-current-architecture.md](01-current-architecture.md) — 現状（テスト 0 件）
- [03-architecture.md](03-architecture.md) — テストしやすい設計の前提
- [04-data-model.md](04-data-model.md) — TestModelContainer で扱うスキーマ
