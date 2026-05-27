# 04. データモデル詳細設計

> [03-architecture.md](03-architecture.md) で確定した「SwiftData + CloudKit Private DB を Phase 1 から使う」「Phase 3 で CKShare 友達共有」を前提に、各 `@Model` の最終形・関連・マイグレーション戦略を定義する。

> Codexレビューあり: 実装前に [07-codex-plan-review.md](07-codex-plan-review.md) を必ず確認すること。
> 特に `@Attribute(.unique)`、`UserSettings` の重複対策、`photoData`、CloudKit ゾーン設計は本ドキュメント初版から修正が必要。

---

## 0. 設計原則

1. **CloudKit 互換性を最優先**: 以下の制約を全モデルで守る
   - CloudKit 同期対象モデルでは `@Attribute(.unique)` を使わない（重複は seed / Store 層で統合）
   - `@Relationship` の `deleteRule` は `.nullify` のみ（`.cascade` は CloudKit と相性悪い）
   - 全プロパティに **デフォルト値** を持たせる（CloudKit の optional/default 要件）
   - リレーションは optional & to-many をデフォルトに
2. **マイグレーション破壊を避ける**: SwiftData の VersionedSchema を導入
3. **SwiftData managed sync と CKShare を分離**: Phase 1 は本人の private DB 同期、Phase 3 の友達共有は CloudKit API の専用 Coordinator で扱う
4. **時刻は全て `Date`（タイムゾーン非依存の絶対時刻）**: 表示時に `Calendar` / `DayBoundary` で変換

---

## 1. モデル一覧（Phase 別）

| Phase | モデル | 用途 |
|-------|--------|------|
| 1 | `Category` | カテゴリ |
| 1 | `CategorySet` | グリッドプリセット束（仕様超過・継続採用） |
| 1 | `Chapter` | 記録チャプター |
| 1 | `PlanBlock` | 予定ブロック |
| 1 | `UserSettings` | ユーザー設定（表示・公開・同期対象設定など） |
| 2 | `UnlockItem` | アンロックアイテム状態 |
| 2 | `CalendarEventCache` | EventKit予定の軽量キャッシュ |
| 3 | `Friend` | 友達 |
| 3 | `FriendCategoryMapping` | カテゴリマッピング |
| 3 | `Reaction` | リアクション |
| 3 | `Comment` | コメント |
| 3 | `SharedTimeline` | 友達向け公開済タイムラインスナップショット |
| 3 | `VisibilityPreset` | 公開設定プリセット（既存を作り直し） |

---

## 2. Phase 1 モデル詳細

### 2.1 Category

```swift
@Model
public final class Category {
    public var id: UUID = UUID()
    public var name: String = ""
    public var colorHex: String = "#8E8E93"
    public var icon: String? = nil
    public var sortOrder: Int = 0
    public var isDefault: Bool = false
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Chapter.category)
    public var chapters: [Chapter] = []

    @Relationship(deleteRule: .nullify, inverse: \PlanBlock.category)
    public var plans: [PlanBlock] = []

    public init() {}  // CloudKit互換のため引数なしを必須
    public init(name: String, colorHex: String, icon: String? = nil,
                sortOrder: Int = 0, isDefault: Bool = false) {
        self.name = name; self.colorHex = colorHex; self.icon = icon
        self.sortOrder = sortOrder; self.isDefault = isDefault
    }
}
```

**変更点（現状から）**
- 全プロパティにデフォルト値（CloudKit要件）
- `plans` への inverse relationship 追加（PlanBlock も逆参照可能に）
- `usageCount` は廃止済み。CategorySet の位置指定スロットで表示順を管理する
- `id` は論理識別子として使うが、CloudKit 同期対象なので `@Attribute(.unique)` は付けない

### 2.2 Chapter

```swift
@Model
public final class Chapter {
    public var id: UUID = UUID()
    public var category: Category? = nil       // nullify 対応のため optional
    public var startTime: Date = Date()
    public var endTime: Date? = nil            // nil = 進行中
    public var note: String? = nil
    public var mood: String? = nil
    public var photoLocalIdentifier: String? = nil  // Phase 1 では本体画像保存は保留
    public var thumbnailData: Data? = nil            // 軽量プレビューのみ。大きな画像は持たない
    public var locationName: String? = nil
    public var isPublic: Bool = true
    public var visibilityScope: VisibilityScope = .all  // Phase 3 で活躍
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init() {}
}

public enum VisibilityScope: String, Codable {
    case all          // 全友達に公開
    case preset       // VisibilityPreset 経由
    case none         // 非公開
}
```

**変更点**
- `photoData: Data?` の直接保存は保留。CloudKit 同期コストを避けるため `photoLocalIdentifier` / `thumbnailData` に分離
- `visibilityScope` を追加（Phase 3 への布石、Phase 1 では常に `.all`）
- `updatedAt` を追加（CloudKit競合解決とエクスポートに使う）

**インデックス指針** (将来 `@Attribute(.index)` 適用候補)
- `startTime`: 日付クエリで多用
- `endTime`: activeChapter 検索（`endTime == nil` filter）
- `category.id` 経由のクエリ（自動でリレーション最適化される）

### 2.3 PlanBlock

```swift
@Model
public final class PlanBlock {
    public var id: UUID = UUID()
    public var category: Category? = nil
    public var title: String = ""
    public var startTime: Date = Date()
    public var endTime: Date = Date()
    public var isAllDay: Bool = false
    public var isImportant: Bool = false
    public var note: String? = nil
    public var isPublic: Bool = true
    public var visibilityScope: VisibilityScope = .all
    public var sourceEventID: String? = nil    // EventKit由来の場合、EKEvent.eventIdentifier
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init() {}
}
```

**変更点**
- `sourceEventID` 追加: EventKit から取り込んだ予定の元 ID を保持し、再同期時に重複防止
- `updatedAt` 追加

**現行の重要予定ルール (2026-05-26)**
- `isImportant == true` は「重要な予定」としてカレンダーに表示する
- `isAllDay == true` は「時間未指定」の予定として扱う。既存データ互換のため `isAllDay == true` も重要予定として表示する
- 時間つき予定 (`isAllDay == false`) でも `isImportant == true` なら月カレンダーに表示し、開始時刻も表示する
- 複数日にまたがる重要予定もDBでは分割しない。表示時に対象日へクリップする
- 外部カレンダー連携時は、終日/時間未指定の予定を重要予定、時間指定の予定を時間つき予定に変換する方針
- 将来、より細かい種別が必要なら `PlanBlock.kind` / `displayInCalendar` などへ拡張する

### 2.4 CategorySet

```swift
@Model
public final class CategorySet {
    public var id: UUID = UUID()
    public var name: String = ""
    public var sortOrder: Int = 0
    public var slots: [UUID?] = Array(repeating: nil, count: 8)
    public var isDefault: Bool = false
    public var createdAt: Date = Date()

    public init() {}
}
```

**設計判断**
- 現実装に合わせて `slots: [UUID?]` を採用する。index 0...7 が Home の 4列×2行に対応し、`nil` は空きスロット
- 理由: 仕様変更により「使用頻度順」ではなく「ユーザーが位置を決めるグリッド」になったため
- 注意: CloudKit managed sync で optional UUID 配列が問題になる場合は `slot0...slot7: UUID?` または `[String]` + 空文字扱いへ移行する
- `categoryIDs` から `slots` への変更は開発中は DB リセットでよい。本番リリース後は VersionedSchema の migration が必要

### 2.5 UserSettings（新規）

```swift
@Model
public final class UserSettings {
    public var id: UUID = UUID()
    public var settingsKey: String = "default"     // 論理 singleton key
    public var defaultVisibility: VisibilityScope = .all
    public var themeName: String = "default"
    public var enabledCategorySetID: UUID? = nil   // 現在アクティブなグリッド
    public var calendarSyncEnabled: Bool = false
    public var showCalendarOverlay: Bool = true    // タイムラインに予定うっすら表示
    public var dashboardCardOrder: [String] = []   // ダッシュボードカードの並び
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init() {}
}
```

**日付境界:** 現行仕様では1日の範囲を 0:00-24:00 固定とするため、`dayStartHour` は `UserSettings` に持たせない。
ユーザーが1日の始まり時間を変更する機能は、スコア・ランキング・共有・タイムライン全体の前提を変えるため、数年単位の大きなアップデートで再検討する。

**シード戦略**
- 起動時に `settingsKey == "default"` を論理 singleton として取得する
- 複数デバイスがオフライン初回起動した場合、同期後に複数件へ増える可能性があるため、`BootstrapStore` / `SeedCoordinator` が最古の1件へ統合する
- 統合時は、明示変更された値を優先し、最後に `updatedAt` が新しい値を採用する

→ 現状 `@AppStorage` で持つか `UserSettings @Model` で持つかは判断が分かれる。
**判断**: 同期したい設定は `UserSettings`、デバイスローカル設定（プレビュー seed フラグ等）は `@AppStorage`。

---

## 3. Phase 2 モデル詳細

### 3.1 UnlockItem

```swift
@Model
public final class UnlockItem {
    public var id: UUID = UUID()
    public var key: String = ""                    // "theme.spring" など識別子
    public var kind: UnlockKind = .theme
    public var requiredCumulativeScore: Int = 0
    public var unlockedAt: Date? = nil             // nil = 未解放
    public var displayName: String = ""
    public var thumbnailName: String? = nil
    public var sortOrder: Int = 0

    public init() {}
}

public enum UnlockKind: String, Codable {
    case theme         // 着せ替え
    case iconFrame     // アイコンフレーム
    case stamp         // スタンプ
    case appIcon       // アプリアイコン
}
```

**運用**
- 初回起動時にマスター26件を seed
- 累計スコア計算時に「未解放で `requiredCumulativeScore` を超えたもの」を `unlockedAt = Date()` で更新
- 解放スケジュール（仕様書）は seed データで `requiredCumulativeScore` を逆算してハードコード

**マスターデータ管理**
- `UnlockItem` は CloudKit 同期する（解放済み状態はデバイス横断で一貫）
- 新規マスター追加時は、起動時に「既存 key 以外」を追記 seed
- `key` は論理一意キーだが `@Attribute(.unique)` は付けない。重複が同期された場合は `SeedCoordinator` が同じ `key` を1件に統合し、`unlockedAt` は最古の値を保持する

### 3.2 CalendarEventCache

```swift
@Model
public final class CalendarEventCache {
    public var id: UUID = UUID()
    public var eventIdentifier: String = ""        // EKEvent.eventIdentifier
    public var calendarIdentifier: String = ""
    public var title: String = ""
    public var startTime: Date = Date()
    public var endTime: Date = Date()
    public var isAllDay: Bool = false
    public var colorHex: String? = nil
    public var lastSyncedAt: Date = Date()

    public init() {}
}
```

**運用**
- EventKit は読むたびに API 叩くと遅いので、表示範囲（前後3ヶ月）をキャッシュ
- EventStore の change notification で差分更新
- **CloudKit 同期しない**（デバイスローカル限定キャッシュ）→ 別の `ModelConfiguration` で隔離

---

## 4. Phase 3 モデル詳細

### 4.1 Friend

```swift
@Model
public final class Friend {
    public var id: UUID = UUID()
    public var userRecordID: String = ""           // CKRecord.ID の文字列表現
    public var displayName: String = ""
    public var iconURL: String? = nil
    public var bio: String? = nil
    public var status: FriendStatus = .pending
    public var isFavorite: Bool = false
    public var shareURL: String? = nil             // CKShare URL
    public var visibilityPresetID: UUID? = nil     // 自分から見るときのフィルター
    public var lastSeenAt: Date? = nil
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify)
    public var mappings: [FriendCategoryMapping] = []

    public init() {}
}

public enum FriendStatus: String, Codable {
    case pending     // 承認待ち（自分→相手）
    case accepted    // 双方向承認済
    case blocked
}
```

### 4.2 FriendCategoryMapping

```swift
@Model
public final class FriendCategoryMapping {
    public var id: UUID = UUID()
    public var friend: Friend? = nil
    public var myCategoryID: UUID = UUID()
    public var friendCategoryID: UUID = UUID()
    public var useUnifiedColor: Bool = true        // 比較時に自分のカラーで上書き
    public var createdAt: Date = Date()

    public init() {}
}
```

**多対一の表現**: 同じ `friendCategoryID` を持つ `mappings` を複数持てる構造。

### 4.3 Reaction / Comment

```swift
@Model
public final class Reaction {
    public var id: UUID = UUID()
    public var targetChapterID: UUID = UUID()
    public var fromFriendID: UUID? = nil           // nil = 自分
    public var emoji: String = ""
    public var createdAt: Date = Date()

    public init() {}
}

@Model
public final class Comment {
    public var id: UUID = UUID()
    public var targetChapterID: UUID = UUID()
    public var fromFriendID: UUID? = nil
    public var text: String = ""
    public var createdAt: Date = Date()
    public var editedAt: Date? = nil

    public init() {}
}
```

**設計判断**
- `targetChapterID: UUID` で参照（直接 `Chapter?` リレーションを張らない）
- 理由: 友達の Chapter は別 CKShare ゾーンにあり、SwiftData の `@Relationship` で跨げない
- 表示時に「自分のChapter or 友達のChapter」を ID で引く

### 4.4 SharedTimeline

```swift
@Model
public final class SharedTimeline {
    public var id: UUID = UUID()
    public var ownerUserRecordID: String = ""      // 友達 or 自分
    public var date: Date = Date()                 // 対象日
    public var publishedAt: Date = Date()
    public var snapshotJSON: Data = Data()         // タイムライン全データを JSON 化
    public var visibility: VisibilityScope = .all

    public init() {}
}
```

**用途**
- 「翌日公開」モードのスナップショット保存
- リアルタイム公開時は使わず、Chapter を直接共有

### 4.5 VisibilityPreset（作り直し）

```swift
@Model
public final class VisibilityPreset {
    public var id: UUID = UUID()
    public var builtInKey: String? = nil       // built-in の論理キー。ユーザー作成は nil
    public var name: String = ""
    public var isBuiltIn: Bool = false
    public var sortOrder: Int = 0

    // 公開ルール
    public var publishMode: PublishMode = .realtime
    public var hideMoodAndNote: Bool = false
    public var hidePhoto: Bool = true
    public var hideLocation: Bool = true
    public var excludedCategoryIDs: [UUID] = []    // 除外するカテゴリ
    public var freeTimeOnly: Bool = false           // カレンダー予定: 空き時間のみ
    public var createdAt: Date = Date()

    public init() {}
}

public enum PublishMode: String, Codable {
    case realtime    // 切り替えた瞬間に反映
    case nextDay     // 翌日0時に反映
}
```

**ビルトインプリセット**: 起動時に seed
- `仲良し`: 全公開・リアルタイム
- `知り合い`: 一部カテゴリ除外・mood/note 隠す
- `オフモード`: publishMode = none 相当 → 全 Chapter `visibilityScope = .none`
- `カスタム`: ユーザー作成

**重複整理**
- built-in は `builtInKey` で論理一意に扱う
- CloudKit 同期後に同じ `builtInKey` が複数件になった場合、`SeedCoordinator` が最古の1件へ統合する
- ユーザー作成プリセットは `builtInKey == nil` のため、名前が同じでも別プリセットとして扱う

---

## 5. リレーション全体図

```
                    ┌──────────────┐
                    │  Category    │◄────────┐
                    └──────┬───────┘         │ inverse
                           │                  │
              ┌────────────┼────────────┐    │
              ▼            ▼            ▼    │
         Chapter       PlanBlock    CategorySet
              │            │       (UUID参照)
              │            │
              ▼            ▼
        Reaction       (sourceEventID)
        Comment             │
        (UUID参照)          ▼
                      CalendarEventCache
                       (ローカル限定)

         Friend ─────< FriendCategoryMapping

         SharedTimeline (UUID参照のみ)
         UnlockItem (孤立)
         UserSettings (孤立・singleton)
         VisibilityPreset (UUID参照のみ)
```

---

## 6. ModelContainer の分割

CloudKit同期するモデルとローカルのみのモデルを分離する。

```swift
public enum SharedModelContainer {
    public static let shared: ModelContainer = {
        let cloudSchema = Schema([
            Category.self, Chapter.self, PlanBlock.self, CategorySet.self,
            UserSettings.self, UnlockItem.self,
            Friend.self, FriendCategoryMapping.self,
            Reaction.self, Comment.self, SharedTimeline.self,
            VisibilityPreset.self,
        ])
        let cloudConfig = ModelConfiguration(
            "Cloud",
            schema: cloudSchema,
            groupContainer: .identifier("group.app.YasudaRyuga.Liminalog"),
            cloudKitDatabase: .private("iCloud.app.YasudaRyuga.Liminalog")
        )

        let localSchema = Schema([CalendarEventCache.self])
        let localConfig = ModelConfiguration(
            "LocalCache",
            schema: localSchema,
            groupContainer: .identifier("group.app.YasudaRyuga.Liminalog"),
            cloudKitDatabase: .none
        )

        return try! ModelContainer(
            for: Schema(cloudSchema.entities + localSchema.entities),
            configurations: [cloudConfig, localConfig]
        )
    }()
}
```

---

## 7. CloudKit 共有設計（Phase 3 検証タスク）

Phase 1 の CloudKit は SwiftData managed sync に限定し、本人の複数デバイス同期だけを扱う。
Phase 3 の友達共有は `ShareCoordinator` が CloudKit API を直接使う別レイヤーとして設計する。
SwiftData managed sync の private database 設定だけで、友達ごとの公開範囲が異なる `CKShare` を実現する前提にはしない。

### 7.1 Phase 1: SwiftData managed sync

- `ModelConfiguration(..., cloudKitDatabase: .private("iCloud.app.YasudaRyuga.Liminalog"))` を使う
- ゾーン名や CKRecord の詳細は SwiftData に任せる
- 対象は本人の `Category` / `CategorySet` / `Chapter` / `PlanBlock` / `UserSettings` / `UnlockItem` など
- iCloud 未ログイン時はローカル動作にフォールバックする

### 7.2 Phase 3: CKShare 友達共有

Phase 3 では以下を検証してから確定する。

- 公開対象の `Chapter` / `PlanBlock` をそのまま共有するか、`SharedTimeline` / DTO に変換して共有するか
- 友達ごとに異なる公開設定をどう反映するか
- `CKShare` の単位を「友達ごと」「日付スナップショットごと」「公開プリセットごと」のどれにするか
- Reaction / Comment をどちらのユーザーの共有領域に保存するか

### 7.3 暫定方針

- SwiftData モデルそのものを `CKShare` 対象にする前提では進めない
- `ShareCoordinator` が `CKRecord` / `CKShare` を明示的に保存する
- 公開設定が友達ごとに異なるため、共有単位は 1対1 を第一候補にする
- 詳細は Phase 3 開始時に `cloudkit-sharing.md` を別途作る

---

## 8. マイグレーション戦略

### 8.1 SwiftData VersionedSchema を採用

```swift
public enum LiminalogSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Category.self, Chapter.self, PlanBlock.self, CategorySet.self]
    }
}

public enum LiminalogSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Category.self, Chapter.self, PlanBlock.self, CategorySet.self,
         UserSettings.self, UnlockItem.self]
    }
}

public enum LiminalogMigrationPlan: SchemaMigrationPlan {
    public static let schemas: [any VersionedSchema.Type] = [
        LiminalogSchemaV1.self, LiminalogSchemaV2.self
    ]
    public static let stages: [MigrationStage] = [
        .lightweight(fromVersion: LiminalogSchemaV1.self, toVersion: LiminalogSchemaV2.self)
    ]
}
```

### 8.2 現状実装からの初回マイグレーション

現状の `Liminalog.sqlite`（DEBUGビルドで作られたもの）は、開発フェーズなので **完全リセットでOK**。
本番リリース前の最後のマイグレーションが「初回 V1」になる前提で、以下の方針:

1. 開発中の SwiftData ストアは破棄前提
2. Phase 1 リリース時のスキーマを `V1` として固定
3. 以降は VersionedSchema で追記

### 8.3 CloudKit スキーマアップロード

- Xcode の CloudKit Dashboard で開発スキーマを編集
- アプリ起動時に `modelContext.save()` するとスキーマが自動 push される
- 本番デプロイ前に「Deploy Schema Changes」で Production へ昇格

---

## 9. インデックス・パフォーマンス指針

`@Attribute(.index)` を Phase 2 完了時点で適用検討:

| モデル | インデックス候補 | 理由 |
|--------|-----------------|------|
| Chapter | `startTime` | 日範囲クエリで頻出 |
| Chapter | `endTime` | activeChapter 検索 |
| PlanBlock | `startTime` | 同上 |
| Reaction | `targetChapterID` | チャプター毎の取得 |
| Comment | `targetChapterID` | 同上 |
| SharedTimeline | `date` + `ownerUserRecordID` | 日付・友達フィルター |

→ Phase 1 では未指定でOK（データ量が少ない）。Phase 2 で測定して必要に応じて追加。

---

## 10. 廃止・改名するもの（現状から）

| 現行 | 扱い | 理由 |
|------|------|------|
| `VisibilityPreset` (現状の薄実装) | 廃止 → 4.5 の新設計に置換 | 仕様と乖離 |
| `LiminalogActivityAttributes.ContentState.categories` | 廃止 | App Groups 経由で SwiftData から読むため不要 |
| `LiminalogActivityAttributes.ContentState.categorySetName` | 廃止 | 同上 |
| `ChapterStore.revision` | 廃止 | `@Query` 主軸への移行 |

---

## 11. オープン論点

- **写真データの本体保存**: Phase 1 では `photoLocalIdentifier` / `thumbnailData` に留める。本体画像を PhotoKit / file storage / CKAsset 相当のどれで扱うかは Phase 2 以降で判断
- **オフライン CKShare 受諾**: ネットワークなし環境での挙動
- **同期競合解決**: 同じ Chapter を 2 デバイスで同時編集した時、`updatedAt` で last-write-wins か、より高度な戦略か

→ Phase 1 → Phase 2 への移行時に判断する。

---

## 次のドキュメント

→ [05-screen-flow.md](05-screen-flow.md): このデータモデルを使った各画面の遷移と状態管理
