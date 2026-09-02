# 22. 予定プリセット / 一日プリセット 設計

作成: Claude / 2026-07-06
ステータス: Codexレビュー済み・段階実装中（2026-09-02）
前提docs: [03-architecture.md](03-architecture.md)（スキーマ規約）/ [10-today-tab-structure.md](10-today-tab-structure.md)（明日ページ）/ [21-refactoring-playbook.md](21-refactoring-playbook.md) §2 不変条件

---

## 1. 目的とユーザーストーリー

計画（PlanBlock）作成の反復コストを下げる。Liminalog は「予定と実績のあいだ」を見るアプリなので、**予定を立てるのが億劫だと成立しない**。定型の予定・定型の一日をワンタップで展開できるようにする。

- **予定プリセット**: 1件の予定テンプレート。「ジム（運動・90分・非公開）」を保存しておき、予定作成シートでチップをタップすると流し込まれる
- **一日プリセット**: 1日分の予定テンプレート束。「平日ルーティン」（9:00-18:00 仕事 / 19:00-20:30 ジム / 23:00-7:00 睡眠）を保存しておき、明日以降の日にまとめて展開する

2機能は**同じ適用パイプライン**（§4）に載る。一日プリセット = 予定テンプレートの配列、と捉える。

---

## 2. 全体像

```
PlanPreset (@Model)  ──┐
                       ├─→ PlanTemplateSnapshot（プレーン値・Codable）──→ 適用パイプライン
DayPreset (@Model)   ──┘         │                                          │
  itemsData: Data ←── JSON([PlanTemplateSnapshot])              DayPresetApplyPlanner (Logic/・純粋関数)
                                                                             │
                                                                 PlanStore.applyTemplates(...)
                                                                   （一括検証 → 一括insert → save 1回 → requestRefresh 1回）
```

---

## 3. データモデル

### 3.1 PlanTemplateSnapshot（プレーン値・Codable・@Model ではない）

予定1件分のテンプレート表現。PlanPreset からも DayPreset からも生成され、適用パイプラインの共通入力になる。

```swift
struct PlanTemplateSnapshot: Codable, Equatable {
    var title: String
    var categoryID: UUID?      // 適用時に解決。解決不能なら「カテゴリなし」フォールバック
    var startMinute: Int       // 0:00 からの分。0...1439
    var endMinute: Int         // startMinute < endMinute <= startMinute + 1440（日跨ぎは endMinute > 1440 で表現）
    var isAllDay: Bool         // true のとき start/endMinute は無視。単日終日のみ（複数日終日は v1 対象外）
    var isImportant: Bool
    var note: String?
    var isPublic: Bool
}
```

- 時刻は**その日の 0:00 からの分**で持つ（絶対 Date を持たない）。適用先日の年月日と時・分から壁時計時刻を組み立て、DST日でも 9:00 を 9:00 として維持する
- 日跨ぎ（睡眠 23:00→7:00）は `endMinute = 31 * 60` のように 1440 超で表現。**スパン上限は24時間**
- 公開範囲: `isPublic` のみ保存する。`audienceFriendIDs` は**保存しない**（§4.4）

### 3.2 PlanPreset（@Model・cloudSchema 同期対象）

```swift
@Model final class PlanPreset {
    var id: UUID = UUID()
    var name: String = ""            // チップ表示名。trim後空なら title を使う
    var title: String = ""
    var categoryID: UUID?            // CloudKitの関係追加を避け、適用/表示時に解決
    var startMinute: Int = 540       // 9:00
    var endMinute: Int = 600         // 10:00
    var isAllDay: Bool = false
    var isImportant: Bool = false
    var note: String?
    var isPublic: Bool = true
    var sortOrder: Int = 0
    var lastUsedAt: Date?            // v1 では記録のみ（並びは sortOrder 手動）
    var useCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}
```

### 3.3 DayPreset（@Model・cloudSchema 同期対象）

```swift
@Model final class DayPreset {
    var id: UUID = UUID()
    var name: String = ""
    var itemsData: Data = Data()     // JSON: DayPresetItemsEnvelope（下記）
    var itemCount: Int = 0           // 一覧表示用キャッシュ（デコードせずに件数表示）
    var sortOrder: Int = 0
    var lastUsedAt: Date?
    var useCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct DayPresetItemsEnvelope: Codable {
    var version: Int                 // 現行 1
    var items: [PlanTemplateSnapshot]
}
```

**なぜ items を blob（JSON in Data）にするか — 子 @Model 案の棄却理由:**
- 本コードベースは **to-many のモデル関係を避けるのが確立済みの作法**（`CategorySet.slots: [UUID?]`、`audienceFriendIDs: [UUID]`。docs/21 §2.1）。CloudKit 同期下の to-many は重複統合・inverse・部分同期の実績リスクがある
- プリセットは≦24件の小データで、原子的に読み書きされ、Last-Writer-Wins で十分。フィールド単位マージの恩恵がない
- 代償として category は UUID 参照になる → 適用/表示時に解決し、解決不能なら「カテゴリなし」として扱う（§8-1）

**スキーマ登録**（docs/21 §2.1 の3箇所ルール）: `LiminalogSchemaV1.models` / `SharedModelContainer.cloudSchema` / `SharedModelContainer.schema` に `PlanPreset.self` と `DayPreset.self` を追加。**追加のみ**なのでマイグレーション不要。

**シードしない**: ビルトインプリセットは作らない（v1）。各端末シードによる CloudKit 重複増殖問題（完了ログ 2026-06-11）の発生源を持ち込まないため。`CloudDuplicateMergeStore` への統合ルール追加も不要。

### 3.4 バリデーション（モデル共通）

| 項目 | 規則 |
|---|---|
| name | trim後 1〜20文字。空なら既定名（PlanPreset は title、DayPreset は「一日プリセット」+連番） |
| 時刻 | `0 <= startMinute < 1440`、`startMinute < endMinute <= startMinute + 1440` |
| DayPreset items | 1〜24件。**時間指定 item 同士はプリセット内で重複禁止**（日跨ぎの折り返し含む）。終日 item は重複判定対象外・最大3件 |
| note | 200文字（PlanBlock の現行運用に合わせる。差異があれば実装時に PlanCreateSheet に揃える） |

---

## 4. 適用パイプライン（コア仕様）

### 4.1 既存ルールの完全継承

適用は**手で1件ずつ作るのと同じ制約**に従う。抜け道を作らない:

- 時間指定の予定は**明日以降の日**にのみ作成可（`PlanStore.canCreate`: `dayStart(startTime) > dayStart(now)`）
- 終日予定はいつでも作成可
- 時間指定の予定同士は重複不可（`hasTimedPlanOverlap` と同等の判定）
- EventKit 取り込み由来の既存予定（`sourceEventID != nil`）も通常の重複対象

→ **時間指定 item を含むプリセットの適用先は明日以降**。UI で日付を制限し（防御1層目）、Planner でも `lockedDay` として弾く（防御2層目）。

### 4.2 DayPresetApplyPlanner（Logic/・enum static・純粋関数）

適用前の判定を担う。**SwiftData に触れない**（テスト容易性と await 跨ぎ回避。docs/21 §2.2）。

```swift
enum DayPresetApplyPlanner {
    struct ExistingInterval: Equatable {   // 既存予定のプレーン値表現
        let id: UUID
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    enum ItemVerdict: Equatable {
        case insertable
        case conflictsWithExisting([UUID])   // 既存予定と重複
        case conflictsWithinPreset([Int])    // プリセット内の他 item と重複（index）
        case lockedDay                       // 時間指定 item × 適用先が今日以前
        case invalidTime                     // 3.4 の時刻規則違反
    }

    static func plan(
        items: [PlanTemplateSnapshot],
        targetDate: Date,
        existing: [ExistingInterval],   // フェッチ窓: [dayStart(target), dayStart(target) + 48h)
        now: Date
    ) -> [ItemVerdict]
}
```

判定仕様:
1. 各 item を絶対時刻に変換（`DayBoundary.dayStart(for: targetDate)` 基準）
2. `invalidTime` → `lockedDay` → `conflictsWithinPreset` → `conflictsWithExisting` の順に評価し、最初に該当したものを返す
3. **フェッチ窓は対象日 + 翌日（48時間）**: 日跨ぎ item（23:00→7:00）が翌日の既存予定と重複し得るため
4. 終日 item は重複判定を行わない（`insertable` / `lockedDay` 対象外 / `invalidTime` のみあり得る）
5. `conflictsWithinPreset` は**選択状態に依存しない静的判定**とし、ユーザーが片方のチェックを外した後の再判定は選択済み item のみで再実行する（§5.2 プレビューUI）

### 4.3 PlanStore.applyTemplates（一括作成 API）

```swift
// PlanStore に追加
struct TemplateApplication {
    let snapshot: PlanTemplateSnapshot
    let resolvedCategory: Category?   // 呼び出し側（MainActor）で解決済み
}

@discardableResult
func applyTemplates(_ applications: [TemplateApplication], to targetDate: Date) -> Bool
```

仕様:
1. **全件を再検証**（Planner と同等の判定を保存直前にもう一度行う。プレビュー表示中に日付が変わる・別端末から予定が同期される競合への防御）
2. 1件でも不合格なら**全件不成立**（部分適用しない）。`false` を返し、UI は「予定が変わったため適用できませんでした。もう一度お試しください」を表示
3. 全件合格なら PlanBlock を生成して insert し、**save は1回**。`saveChanges` パターンに従い、`requestRefresh` へ全 `changedPlanSourceIDs` + 影響日（日跨ぎ含む）をまとめて1回通知。失敗時 rollback（`savePlanScheduleChanges` が実装の模範）
4. タイトル正規化は既存 `normalizedTitle`（空なら category 名 or「予定」）を通す

予定プリセット単体の適用は API を使わず、**PlanCreateSheet のフォームに流し込むだけ**（保存は従来の `addPlanBlock` 経路）。一括 API を使うのは一日プリセットのみ。

### 4.4 公開範囲（audience）の扱い

プリセットは `isPublic` だけを保存し、**友達IDスナップショットは保存しない**。友達構成は変化するため、保存時点の凍結リストを適用すると古い相手に公開される事故になる。

適用時に PlanCreateSheet の save と**同一の経路**で解決する:
- `AudienceResolver.categoryDefaultAudience(for:friendSets:friends:)` でカテゴリ既定の audience を算出
- `audienceSource = .categoryDefaultSnapshot`
- `hasAudienceSnapshot = AudienceSnapshotPolicy.shouldSaveSnapshot(...)`（既存 Policy をそのまま使う）

→ 実装時、この解決ロジックは PlanCreateSheet と適用パイプラインの**2箇所から呼ばれる共通ヘルパー**に寄せること（すでに `AudienceResolver` / `AudienceSnapshotPolicy` として分離済みなので呼ぶだけでよい）。

---

## 5. UI 設計

### 5.1 予定プリセット

**適用（PlanCreateSheet 内）**
- プリセットが1件以上あるとき、`planPreviewCard` の直下に横スクロールのチップ行「プリセット」を表示（0件なら行ごと非表示。空状態の説明は出さない）
- チップ tap: フォームへ流し込み — `title` / `category` / `note` / `isAllDay` / `isImportant` / `isPublic` を上書きし、**開始時刻はユーザーが開いた時刻を維持**、終了時刻 = 開始 + プリセットの duration。audience はカテゴリ既定に再解決（既存 `onChange(of: selectedCategory)` の挙動に乗る）
- チップ長押し（contextMenu）:「開始時刻もプリセットに合わせる」（対象日の startMinute へ移動）/「プリセットを編集」
- 適用時に `lastUsedAt` / `useCount` を更新（保存はプリセット側のみ・軽量）

**保存導線**
- PlanCreateSheet のツールバーに「プリセットとして保存」メニュー項目（現在のフォーム内容から生成。名前入力の小シートを挟む）。編集モード（既存予定を開いた状態）でも使える

**管理**
- SettingsView に「予定プリセット」行 → `PlanPresetSettingsView`: 一覧（名前・カテゴリ色・時刻/長さ）、並び替え（sortOrder）、スワイプ削除、tap で編集フォーム（PlanCreateSheet と同系のカードUI・時刻は「時刻」ピッカーのみで日付なし）

### 5.2 一日プリセット

**適用起点**
1. `CalendarDayView`（明日以降の日）のツールバーメニュー「一日プリセットを適用」
2. 今日タブ・明日ページ（docs/10）の予定が空のときの空状態ボタン「プリセットから一日をつくる」

**適用フロー（`DayPresetApplySheet`）**
1. プリセット選択（一覧: 名前・件数・代表カテゴリ色のドット列）
2. プレビュー: 対象日のタイムライン風リストに item を時刻順で表示。各行 = 時刻・タイトル・カテゴリ色 + 状態バッジ
   - `insertable` → チェックON・「追加」
   - `conflictsWithExisting` → **チェックOFF既定**・「既存の予定と重なるためスキップ」+ 相手の予定名
   - `lockedDay` / `invalidTime` → チェック不可・理由表示
3. チェックの取捨後「n件を追加」→ `applyTemplates`。成功で haptic `commit` + dismiss、失敗（競合再検証NG）はエラー文言で留まる
- **既存予定を削除して置き換えるオプションは v1 スコープ外**（破壊的操作のため。§10 未確定論点）

**作成導線**
1. **既存の日から**: `CalendarDayView` メニュー「この日の予定を一日プリセットとして保存」。その日の PlanBlock を snapshot 化（時刻→分に変換）。**その日の 0:00 より前に開始する予定・24時間超の予定・複数日終日は除外**し、除外があれば「n件はプリセットに含められませんでした」と通知
2. **手動**: `DayPresetEditSheet` — 名前 + item リスト（追加/編集/削除）。item 編集は時刻2つ+タイトル+カテゴリ+トグルのミニフォーム。保存時に §3.4 のプリセット内重複を検証し、違反行を赤示
3. 保存済み予定プリセットを item として取り込むボタン（「予定プリセットから追加」）

**管理**
- SettingsView に「一日プリセット」行 → 一覧（`DayPresetEditSheet` 再利用）

### 5.3 文言トーン

docs/19-monetization-voice の精神に合わせ、禁止・機械的表現を避ける:
- ○「既存の予定と重なるため、この項目はスキップします」 ×「エラー: 重複」
- ○「時間指定の予定は明日からの日に置けます」 ×「本日には適用できません」

---

## 6. ストア構成

```swift
@MainActor
final class PlanPresetStore {
    init(modelContext: ModelContext, clock: any LiminalogClock = SystemClock())

    // PlanPreset CRUD（fetch は sortOrder 順。save 失敗時 rollback + NSLog。requestRefresh は呼ばない — プリセットは共有対象外）
    // DayPreset CRUD + itemsData encode/decode（envelope version 検査）
    func makeDayPresetDraft(from date: Date, plans: [PlanBlock]) -> DayPresetDraft  // §5.2 作成導線1（除外判定込み）
}
```

- `AppStores` に `planPresetStore` を追加（`PlanStore` と同様に modelContext + clock 注入）
- **適用（PlanBlock 生成）は `PlanStore.applyTemplates` が担う**。PresetStore は PlanBlock を書かない（書き込み経路の一本化。docs/21 §2.3）
- View からの参照: PlanCreateSheet は現状 `@Environment(ChapterStore.self)` で書き込みしている。プリセット読み取りは `@Query(sort: \PlanPreset.sortOrder)` を直接使い（@Query 主軸の方針・docs/03 §4.1）、書き込みのみ Store 経由

---

## 7. プリセットと CloudKit

- PlanPreset / DayPreset は private DB 同期対象（自分の複数端末で共有される）。**友達共有の対象ではない** — `CloudFriendShareRefreshCoordinator` への通知不要
- シードなし・ユーザー作成のみなので `CloudDuplicateMergeStore` の統合ルール追加は不要。同名プリセットの重複はユーザー操作由来としてそのまま許容
- `itemsData` のデコード失敗（将来バージョンの envelope / 破損）: 一覧に「このプリセットは開けません（新しいバージョンで作成された可能性）」バッジを出し適用不可にする。**削除はしない**（他端末の新バージョンが正しく読めるデータかもしれないため）

---

## 8. エッジケース一覧（Codex レビュー観点の先回り）

1. **カテゴリ削除後の適用**: DayPreset item の categoryID が解決不能 → 「カテゴリなし」として適用（PlanBlock.category = nil は正常系）。プレビュー行にも「カテゴリなし」表示。PlanPreset は関係なので自動 nil
2. **日跨ぎ item**: スパン≦24hなので影響は翌日まで。Planner のフェッチ窓 48h と `affectedScoreDayStarts`（複数日対応済み）でカバー
3. **23:59 にプレビューを開き 0:00 に確定**: `applyTemplates` 内の再検証で `lockedDay` になり全件不成立 → エラー文言（§4.3-2）
4. **別端末からの同期で予定が増えた直後の適用**: 同じく再検証で検出。部分適用しないので不整合は起きない
5. **終日のみのプリセット**: 今日にも適用可（canCreate の終日規則どおり）
6. **プリセット内重複 + 片方チェックOFF**: 選択集合で再判定し、残った方は insertable になる
7. **保存中のキル/クラッシュ**: save 1回なので中間状態なし（全件 or ゼロ件）
8. **note/title の空**: 既存 `normalizedTitle` 経路と `note.flatMap { $0.isEmpty ? nil : $0 }` を踏襲
9. **時刻の DST**: 分→絶対時刻変換は対象日の年月日と時・分を `DateComponents` で組み立てる。経過秒加算による1時間ずれを避け、変換ヘルパーを1箇所に置いてテストで固定する

## 9. テスト計画

| テスト | 内容 |
|---|---|
| `PlanTemplateSnapshotTests` | codec round-trip / envelope version（未知version・破損データ→エラー） |
| `DayPresetApplyPlannerTests` | verdict 判定マトリクス（重複/日跨ぎ/終日/lockedDay/invalidTime/プリセット内重複/選択後再判定） |
| `PlanStoreApplyTemplatesTests` | 全件成功・1件不合格で全ロールバック・save/requestRefresh が各1回・影響日集合 |
| `PlanPresetStoreTests` | CRUD / makeDayPresetDraft の除外規則（前日開始・24h超・複数日終日）/ カテゴリ削除 fallback |

## 10. 未確定の論点（ユーザー判断）

| # | 論点 | 推奨 |
|---|---|---|
| 1 | **Pro ゲート**: プリセット数上限（例: 無料は予定プリセット5・一日プリセット2、Pro無制限）をどうするか。docs/17 の「機能はティア、装飾はサブ」の線引きに関わる | 無料は少数上限 + Pro 無制限。ただし v1 は上限なしで出し、利用状況を見てから絞る選択肢もある |
| 2 | 一日プリセット適用時の「既存予定を削除して置き換える」オプション | v1 では見送り（破壊的） |
| 3 | チップ適用の既定挙動（duration のみ vs 時刻ごと） | duration のみ（§5.1）。長押しで時刻適用 |
| 4 | ビルトインサンプルプリセット | なし。空状態の文言で作成へ誘導 |
| 5 | AppIntent「一日プリセットを適用」（ショートカット/ウィジェット連携） | 将来。v1 対象外 |

## 11. タスク分解と担当推奨（AI_TASKS.md へ転記済み）

決定木（AI_TASKS §2.3）適用: モデル + Planner + 一括適用 = 複雑な条件分岐ロジック → **Codex**。シートUI・チップ・設定画面 = 既存パターンへの馴染み → **Claude**。

| 順 | タスク | 担当推奨 | 依存 |
|---|---|---|---|
| 1 | モデル追加（PlanPreset/DayPreset/Snapshot/envelope）+ スキーマ3箇所登録 + codec テスト | Codex | — |
| 2 | `DayPresetApplyPlanner` + テスト | Codex | 1 |
| 3 | `PlanStore.applyTemplates` + テスト | Codex | 2 |
| 4 | `PlanPresetStore` + `AppStores` 配線 + テスト | Codex | 1 |
| 5 | PlanCreateSheet チップ行 + 「プリセットとして保存」 | Claude | 4 |
| 6 | `PlanPresetSettingsView`（管理） | Claude | 4 |
| 7 | `DayPresetEditSheet`（手動作成/編集・内部重複の赤示） | Claude | 4 |
| 8 | `DayPresetApplySheet`（プレビュー・取捨・適用） | Claude | 3, 7 |
| 9 | 適用起点（CalendarDayView メニュー / 明日ページ空状態）+「この日から保存」 | Claude | 8 |
