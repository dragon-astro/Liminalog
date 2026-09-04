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
    var placementModeRawValue: String = "duration" // duration / fixedTime
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
    var colorHex: String = "#2F80ED"
    var icon: String = "calendar"
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
5. 一日プリセットは全件を一つのスケジュールとして扱う。`canApplyWholePreset` は非空かつ全 verdict が `insertable` のときだけ真を返し、UIで一部の予定だけを除外しない

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

予定プリセット単体の適用は一括 API を使わない。PlanCreateSheet ではフォームに流し込み、タイムラインでは対象日時へ1件の PlanBlock を生成して従来の保存経路へ載せる。一括 API を使うのは一日プリセットのみ。

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
- 予定プリセットには配置方式を持たせる。`duration` は所要時間だけを再利用し、`fixedTime` は保存時の開始・終了時刻を再利用する。終日予定は常に `fixedTime` として扱う
- チップ tap: フォームへ流し込み — `title` / `category` / `note` / `isAllDay` / `isImportant` / `isPublic` を上書きする。`duration` は**開始時刻を維持**して終了だけを開始 + duration にし、`fixedTime` は開始・終了を保存時刻に合わせる。audience はカテゴリ既定に再解決（既存 `onChange(of: selectedCategory)` の挙動に乗る）
- チップ長押し（contextMenu）: `duration` では「開始時刻もプリセットに合わせる」、`fixedTime` では「長さだけを使う」を選べる
- 適用時に `lastUsedAt` / `useCount` を更新（保存はプリセット側のみ・軽量）

**適用（実際のタイムライン）**
- ホームの明日タイムライン、カレンダーの日・週タイムラインには小さなブックマークボタンだけを常設する。押した時だけ予定ライブラリが下から出て、タブバーの領域まで覆う。閉じればタブバーを戻す
- ライブラリ上段はよく使う予定の横棚、下段は全幅の検索欄、その下に全幅の「カテゴリアイコン＋カテゴリ名」横スクロールピル列、続けて3列の高密度一覧を置く。検索と絞り込みを同じ行へ押し込まない。ピルは枠線を含めて上下が切れない余白を持たせ、色だけ・アイコンだけに判別を依存させない。カード内に「タップ」「長押し」の説明文は置かず、固定時刻型は `＋`、長さ型は手のアイコンと破線枠で区別する
- ホーム明日・カレンダー日/週のすべてでOS標準のボトムシートとして表示する。通常高は上端余白込みで一覧が見える264pt、拡大時はシステム標準の半画面（`.medium`）の2段だけとし、角丸・ホームインジケータまでのセーフエリア・上下移動はシステムへ任せる。背景は半透明素材を使わず `systemBackground`（ライトは白、ダークは黒）にする。独自の高さ計算、背景延長、ドラッグハンドルは持たない。シート表示中も背面操作を許可し、見えているタイムライン部分はスクロールできるようにする。カレンダー上部の既存設定ボタンを押した場合はドロワーを自動で閉じ、続けてカレンダー設定を開く
- `fixedTime` / 終日プリセットはタップで対象日へ追加する。ドロワー見出しには内部的な追加先日付を常時表示しない
- `duration` は長押しして任意の日時へドラッグする。UIKitの長押し認識が成立した瞬間から指の `UIWindow` 座標を追跡し、シートの表示コンテナ全体を画面下へ退避させる。指がタイムラインへ入った時点から通常予定と同じ幅・実時間長のカードへ切り替える。プレビューカードはスクロール内容ではなく画面側のオーバーレイへ描画し、カードの下端を指より8pt上に置いて下端付近を掴んでいる配置で1pt単位に直接追従させる。表示時刻と確定位置だけを設定中の移動幅へスナップし、刻みを越えた時にハプティックを返す。24時側ではプリセットの長さを含めて最終開始時刻とプレビュー上端を制限し、カード全体を表示領域内へ保つ。ドラッグ中はカード内の時刻だけを残し、外側の開始・終了時刻ガイドは表示しない。日間・週間とも対象タイムライン枠とスクロール中のタイムライン本体を `UIWindow` 座標で直接計測し、拡大率やスクロール位置に依存せず指と同じ座標系から時刻へ変換する。配置成功・失敗・キャンセル後は同じシートコンテナを元位置へ戻し、失敗時は復帰後に理由を表示する
- 日間・週間の左時刻軸はすべて正時のため `:00` を省き、`0`〜`23` の整数だけを共通32pt幅で表示する。日間はタイムライン本体だけでなく日付・終日予定ヘッダー左端も同じ共通幅にそろえる。縮小時は日間・週間とも、短い予定がある時間帯だけ非均一時間軸で局所的に広げ、予定カードの最低可読高さ18ptを保つ。週間は7日分の予定を同じ時間軸へ集約し、目盛り・カード・作成・移動・長さ調整・ピンチの位置復元をその座標へ統一する。カレンダーの日間・週間のドロワー起動はタイムライン上へ浮かせず、上部の横スクロールカテゴリ列に「予定プリセット」チップとして置く。夜の予定・時刻ラベル・予定カードとは重ねず、ドロワー表示を理由にタイムラインのスクロール範囲も伸ばさない
- 閉じている時はブックマークボタン以外を描画せず、タイムラインのスクロール・予定移動・長さ調整を妨げない

**保存導線**
- PlanCreateSheet のツールバーに「プリセットとして保存」メニュー項目（現在のフォーム内容と予定名から直接生成）。標準の三点メニュー直下にButtonを置き、入れ子のMenuにはしない。編集モード（既存予定を開いた状態）でも使える

**管理**
- 検索・カテゴリ選択は `PlanPresetFilterControls` を設定一覧/ドロワーで共用する。上段は薄い無彩色下地のカプセル検索欄、下段はアイコン＋名称の横スクロール選択肢。カテゴリをメニューから選ぶ方式にはしない。選択肢の上下は枠線が切れない余白を確保する。
- 設定 > カレンダーの「予定プリセット」行 → `PlanPresetSettingsView`: 背景は `systemBackground` とし、実際のタイムライン用ライブラリと同じカードを共有して「よく使う」横棚 + 3列の全件一覧で表示する。名前・カテゴリ・メモの検索と、使用中カテゴリによる絞り込みを備える。全カード共通の編集アイコンや操作説明文は置かない。通常時はtapで編集、長押しで編集・削除。ツールバーの鉛筆から同じ画面のまま編集モードへ入り、各カード右上の×で削除する。編集モードへ入る際は検索・絞り込みを解除し、全件の `sortOrder` を扱う。編集モードでは長押しを不要にし、カードを少し動かした時点からドラッグ並び替えを開始する。掴んだカードは余計なシステム背景を付けず元の角丸のまま浮かせ、侵入位置に応じて周囲を `snappy` でリアルタイム再配置する。SwiftData の `sortOrder` 更新は指を離した時の1回だけ行う
- 予定プリセットの表示名と予定名は分けず、UIでは予定名だけを編集・表示する。旧 `name` は既存データ互換のフォールバックとしてのみ保持する。PlanCreateSheetから保存する時も別名入力を挟まない
- 編集フォームは `PlanCreateSheet` と同じプレビュー・カテゴリ色・セクションカードを使う。時刻入力はメニュー一覧ではなく、同じボトムシートのホイールUIを使う。固定時刻型は開始 `00:00`〜`23:59` と終了 `00:00`〜`47:59` を直接指定し、終了が開始以下または24時間超なら赤いエラーを表示して保存不可にする（暗黙の翌日変換はしない）。長さ型では開始・終了を表示せず、「長さ」1項目だけを1分〜24時間で指定し、保存値は `startMinute = 0` / `endMinute = duration` に正規化する。固定時刻/長さ型と公開状態をプレビュー上にも表示する
- カテゴリ選択シートは `systemBackground` に全カテゴリを一覧表示し、カテゴリセットは上段チップによる任意フィルタとして残す。空きスロットを含むセット単位の表は主表示にしない

### 5.2 一日プリセット

**一覧からの削除**
- 横スワイプでは削除ボタンだけを表示し、フルスワイプでの即時削除は無効にする。ボタンを押した後、対象名と取り消せない旨を確認し、明示的に「削除」を押した場合だけ保存する。確認待ちの対象はIDで保持し、一覧の検索・並び順が変わっても別のプリセットを削除しない。適用済みの実予定は削除しない。

**適用起点**
1. カレンダー日タイムラインとホームの明日タイムラインのカテゴリ棚先頭に、省スペースな「一日プリセット」チップを表示する
2. `CalendarDayView`（明日以降の日）のツールバーメニュー「一日プリセットを適用」も詳細画面用の補助導線として残す

**適用フロー（`DayPresetApplySheet`）**
1. プリセット選択（一覧: 名前・件数・代表カテゴリ色のドット列）
2. プレビュー: 一日分の全 item を時刻順で表示し、全件追加可能かを確認する。個別チェック・自動スキップは行わない
3. 「丸ごと追加」→ 全 items を `applyTemplates` へ渡す。1件でも重複・無効時刻・日付ロックがある場合はボタンを無効にし、問題の予定を表示する。成功で haptic `commit` + dismiss、失敗（競合再検証NG）はエラー文言で留まる
- **2026-09-04 追加要件**: 既存予定と重なる場合も確認画面へ進める。初期選択は「重なる部分だけ置換」（既存の前後を保持、内部挿入なら分割）。「重なる予定を丸ごと置換」も明示選択できる。終日予定は置換対象外。過去/今日から続くロック済み予定・外部カレンダー由来予定は置換不可。確認画面で既存名/元時刻/残る時刻/削除を表示する。確認した既存ID・時刻・updatedAtと保存直前の結果が違えば再確認が必要。全変更と追加を一度のsaveで確定し、失敗はrollbackする。予定プリセットの通常日間/週間タイムライン適用でも同じ確認画面/Store経路を使う。

**作成導線**
1. 作成・編集は **設定 > カレンダー > 一日プリセット** に集約する。カレンダーやホームのタイムラインには作成操作を置かない
2. **手動**: `DayPresetEditSheet` — 日間タイムラインと同じ構成の全画面で「仮想の一日」を編集する。上部は `TimelineCategoryChip` の横スクロール選択欄で、新規予定のカテゴリに反映する。名前欄は日間の日付ヘッダーに当たる46ptの位置に置く。予定カード/調整ハンドルは `EditablePlanBlock`、罫線/時刻は `DayTimelineGrid`、終日行は `CalendarDayTimelineAllDayRow` を通常の日間と共用する。カードの文字サイズ/太さ・ズーム・移動幅も同じ設定を使う
3. ライブラリは独自実装を廃止し、日間・週間と同じ `TimelinePlanPresetLibrary` を使用する。閉じている間は棚を残さず、上部カテゴリ列の「予定プリセット」チップから出し入れする。検索・カテゴリ絞り込み・よく使う項目・3列カード・長押し成立時の退避と配置後の復帰は通常画面と同じ部品に任せる
4. `fixedTime` / 終日はタップ、`duration` は長押しで配置する。追加済み item は本体のドラッグで移動、選択後の上下ハンドルで長さ調整、長押しで削除確認を表示する。編集は `PlanTemplateSnapshot` の配列上だけで行い、実際の日付の `PlanBlock` を書き換えない。保存時に §3.4 のプリセット内重複を再検証する
5. 空き時間は日間と同じ `TimelineCreationLongPressOverlay`（0.28秒）で長押し→上下ドラッグ→離して作成。作成範囲は日間と共通の `PlanTimelineCreationPolicy` で隣接予定/0〜24時へ制限し、キャンセルやピンチへ移った操作は保存しない。カテゴリは上部の選択を使う。単なる空き時間タップは選択解除、名前欄の＋はフォームによる追加。日間と同じく予定の1回タップで選択、選択中の予定をもう一度タップすると編集する。予定本体の長押しは画面全体の削除確認、終日カードのタップは編集
   - 入力フォームは通常予定の `PlanCreateSheet` そのものをsnapshotモードで使う。予定名・カテゴリ・重要/終日・メモ・公開切替・削除・予定プリセット呼び出し/保存は通常フォームを共用する
   - 一日プリセット固有の差分は、日付を持たない `PlanTemplateTimeFields`（開始0〜23時、終了24〜47時も入力可能、終了≤開始を自動補正せずエラー）と、公開相手を適用時のカテゴリ既定値から決める点。友達IDはsnapshotに固定しない
   - フォーム保存/削除は仮想日のsnapshot配列だけへ反映し、実際の日付の予定は変更しない。旧 `PlanPresetEditSheet` のsnapshot編集分岐は廃止した
6. ドロワーと時間軸/スナップは共通化しているが、仮想日のsnapshot更新処理は別。現段階の移動/長さ調整は他の予定と重なる変更を止める方式で、通常タイムラインの玉突き/入れ替えまでは共通化していない

**管理**
- 設定 > カレンダーの「一日プリセット」行 → 一覧（`DayPresetEditSheet` 再利用）
- 一日プリセットに `colorHex`（既定青）/ `icon`（既定calendar）を持たせ、名前欄左のアイコンから編集。カテゴリのアイコン選択部品を共用する。設定一覧/適用選択にも反映。予定プリセットの色・アイコンは従来どおり参照カテゴリに従う。未設定/失われたカテゴリはカテゴリ未設定と表示し、予定名と区別する。既存データへカテゴリの推測割当はしない。

### 5.3 文言トーン

docs/19-monetization-voice の精神に合わせ、禁止・機械的表現を避ける:
- ○「既存の予定と重なるため、一日分を追加できません」 ×「エラー: 重複」
- ○「時間指定の予定は明日からの日に置けます」 ×「本日には適用できません」

### 5.4 周期的な自動適用（2026-09-04 ユーザー追加要件・設計段階）

- 一日プリセット全体、または予定プリセット1件を、毎週の曜日指定などの周期で自動適用できるようにする。初期段階は「毎週・曜日複数選択・開始日・任意の終了日・有効/無効」を想定する
- 長さ型の予定プリセットを自動適用する場合は、ルール側で開始時刻を指定する。固定時刻型はプリセットの時刻を使う
- 自動適用ルールはプリセット本体と分離する。同じプリセットを異なる曜日・時刻で使えるようにする
- 「当日になった瞬間のバックグラウンド実行」を前提にせず、将来の一定期間を先行生成して、ルール保存時・アプリ起動時に不足分を補充する。補充範囲と実行契機は実装前に確定する
- `ruleID + 対象日` の適用履歴を永続化し、再起動・再試行・複数端末同期でも同じ一日を重複生成しない。予定を手動削除しても履歴は残し、自動で復活させない
- 生成後の予定は通常予定として編集可能にする。ルール変更時に手動変更済みの予定や過去予定を上書きしない。既存の将来生成分へ変更を反映する操作は別途明示する
- 既存予定と重なる日は、一日プリセット全体を保留する。既存予定の自動削除・一部だけの適用は行わない。単体プリセットも重複する回は保留する
- CloudKit同時生成・日跨ぎ・DST・ルール停止/削除・元プリセット削除・保存失敗の挙動をテストで固定してから有効化する。現時点では自動適用機能は未実装

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
6. **プリセット内/既存予定との重複**: 1件でも追加不能なら一日分全体を保留し、一部だけを適用しない
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
