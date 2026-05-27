# 07. Codex 計画レビュー

> Claude が作成した `01`〜`06` の設計を、実装者目線でレビューしたメモ。
> ここでは「問題点」「理由」「どう変更するか」を明確にし、Claude が次に設計・実装へ入るときの修正指針にする。

---

## 0. 総評

現行計画の方向性（App Groups、SwiftData/CloudKit、Store 分割、`@Query` 主軸）は妥当。
ただし、CloudKit 互換性とウィジェットの実行境界に関して、いくつか **そのまま実装するとコンパイル不可・同期不可・Phase 3 で作り直し** になる箇所がある。

最優先で直すべき点は次の 6 つ。

1. SwiftData + CloudKit 対象モデルから `@Attribute(.unique)` を外す
2. SwiftData 自動 CloudKit 同期と CKShare 共有を混同しない
3. ウィジェット実装より先に、最低限の共有 Core を作る
4. App Group / iCloud Container ID を現 Bundle ID ベースに修正する
5. `UserSettings` / `UnlockItem` など singleton・マスターデータの重複対策を書く
6. `@Query` で動的フィルタする画面は、View 分割または Store 集計に寄せる

---

## 1. CloudKit 対象モデルに `@Attribute(.unique)` を使っている

### 問題

[04-data-model.md](04-data-model.md) の `Category` / `Chapter` / `PlanBlock` / `CategorySet` / `UserSettings` / `UnlockItem` などが `@Attribute(.unique) public var id` を前提にしている。

### 理由

SwiftData の CloudKit 同期では unique 制約を前提にしない方がよい。
CloudKit は複数デバイスから非同期に同期されるため、ローカル SQLite の一意制約とリモート同期の競合が起きる。
Apple の SwiftData CloudKit 設定は private/automatic/none の managed sync を前提にしており、CloudKit 同期モデルでは「全プロパティにデフォルト値」「relationship は optional」に加えて、アプリ側で重複解決を持つ必要がある。

参考:
- Apple: [Syncing model data across a person’s devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- Apple: [ModelConfiguration.CloudKitDatabase](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct)

### どう変更するか

CloudKit 同期対象モデルでは `@Attribute(.unique)` を削除する。

```swift
@Model
public final class Category {
    public var id: UUID = UUID()
    public var name: String = ""
    // ...
}
```

一意性が必要なものは Store / seed 層で守る。

| 対象 | 変更案 |
|------|--------|
| `Category.id` / `Chapter.id` | UUID は識別子として使うが DB unique 制約は付けない |
| `UserSettings` | `settingsKey = "default"` のような固定キーを持たせ、起動時に複数件あれば 1 件へ統合 |
| `UnlockItem` | `key` を論理キーにし、seed 時に既存 `key` を fetch してなければ追加。重複があれば古い方へ統合 |
| `VisibilityPreset` built-in | `builtInKey` を持たせ、同じ key の重複を seed 後に整理 |

`04-data-model.md` のコード例はすべてこの方針へ修正する。

---

## 2. SwiftData 自動同期と CKShare 共有の境界が曖昧

### 問題

[03-architecture.md](03-architecture.md) と [04-data-model.md](04-data-model.md) は、Phase 1 の SwiftData managed CloudKit sync と、Phase 3 の `CKShare` 友達共有を同じ設計線上で扱っている。
特に `MyRecordsZone` / `SharedTimelineZone` などのカスタムゾーン名を SwiftData 側で直接制御できる前提に読める。

### 理由

SwiftData の `ModelConfiguration.CloudKitDatabase` は managed sync 用で、選択肢は `automatic` / `private(container)` / `none`。
一方、`CKShare` は CloudKit の低レベル API で、共有対象レコード・ゾーン・参加者・受諾フローを明示的に扱う。
SwiftData の自動同期だけで「友達ごとの公開範囲が異なる CKShare」を実現する前提は危険。

Apple の CKShare ドキュメントでも、共有データは private database の custom zone または record hierarchy を `CKShare` で共有する形と説明されている。
これは SwiftData managed sync の private database 設定とは別の実装責務になる。

参考:
- Apple: [CKShare](https://developer.apple.com/documentation/cloudkit/ckshare)
- Apple: [Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing_core_data_objects_between_icloud_users)

### どう変更するか

Phase 1 と Phase 3 を明確に分ける。

| Phase | 方針 |
|-------|------|
| Phase 1 | SwiftData + CloudKit private DB は「本人の複数デバイス同期」だけを扱う |
| Phase 3 | 友達共有は `ShareCoordinator` が CloudKit API を直接使う。SwiftData の自動同期に任せない |

`04-data-model.md` の「CloudKit ゾーン設計」は、現時点では確定設計ではなく **Phase 3 の検証タスク** に下げる。

変更後の記述案:

```markdown
Phase 3 の友達共有は SwiftData managed sync とは別レイヤーにする。
公開対象の Chapter / PlanBlock は `SharedTimeline` または専用 DTO に変換し、
`ShareCoordinator` が CloudKit API で CKRecord / CKShare を保存する。
SwiftData モデルそのものを CKShare 対象にする前提では進めない。
```

---

## 3. ウィジェット実装より Package 化が後になっている

### 問題

[03-architecture.md](03-architecture.md) のロードマップでは、Step 3 で `RecordingGridWidget` を作り、Step 4 で `LiminalogCore` Swift Package 化を行う順番になっている。
しかし `RecordingGridWidget` の `StartChapterIntent` は `AppStores.bootstrap()` / `ChapterStore` / `Category` / `CategorySet` をウィジェット拡張側から使う前提。

### 理由

Widget Extension は App target の型を直接 import できない。
ウィジェットから SwiftData モデルや Store を使うには、先に共有モジュール化するか、最低限のファイルを App / Widget 両 target に所属させる必要がある。
今の順番だと Claude が Widget 実装に入った時点で依存関係が破綻する。

### どう変更するか

ロードマップを次の順番へ変更する。

1. 最小 `LiminalogCore` を先に作る
2. `Models` / `Logic` / `SharedModelContainer` / `ChapterWriter` だけを移す
3. App target を Core 参照へ切り替える
4. Widget target から Core を参照する
5. `RecordingGridWidget` / `StartChapterIntent` を実装する
6. UI コンポーネントの `LiminalogUI` 分離は後でよい

つまり、Package 化を「Phase 1 完了後」ではなく「ウィジェット記録グリッドの前提作業」に移動する。

---

## 4. App Group / CloudKit ID が現プロジェクトの Bundle ID と合っていない

### 問題

計画では仮 ID として以下が使われている。

- App Group: `group.com.ryu.liminalog`
- CloudKit Container: `iCloud.com.ryu.liminalog`

一方、Xcode project の現 Bundle ID は以下。

- App: `app.YasudaRyuga.Liminalog`
- Widget: `app.YasudaRyuga.Liminalog.LiminalogWidgetExtension`

### 理由

Capability 設定は Bundle ID / Team ID / Apple Developer Portal と結びつく。
仮 ID のままドキュメントが残ると、Claude が entitlements や Xcode 設定を誤った識別子で作る可能性が高い。

### どう変更するか

ユーザーが最終判断する前提で、ドキュメント上の候補を現 Bundle ID ベースに寄せる。

```markdown
App Group 候補: `group.app.YasudaRyuga.Liminalog`
CloudKit Container 候補: `iCloud.app.YasudaRyuga.Liminalog`
```

`AI_TASKS.md` の「Bundle ID 確定が前提」は維持しつつ、docs 側ではこの候補を使う。

---

## 5. `UserSettings` と `@AppStorage` の方針が揺れている

> **2026-05-26 更新:** `dayStartHour` をユーザー設定として持つ方針は撤回済み。
> 現行仕様では 1 日を 0:00-24:00 固定とし、可変の1日始まり時間は数年単位の大型アップデートで再検討する。
> この節の `dayStartHour` / 可変 `DayBoundary` に関する指摘は履歴として扱い、実装対象にしない。

### 問題

ドキュメント間で設定保存先が揺れている。

- ~~[03-architecture.md](03-architecture.md): `DayBoundary` の設定値は `@AppStorage("dayStartHour")`~~（撤回済み。0:00-24:00 固定）
- [04-data-model.md](04-data-model.md): 同期したい設定は `UserSettings`
- [05-screen-flow.md](05-screen-flow.md): `activeCategorySetID` は `@AppStorage`
- ~~`AI_TASKS.md`: `@AppStorage("dayStartHour")` を `UserSettings.dayStartHour` に置換する基盤~~（撤回済み）

### 理由

`enabledCategorySetID` はユーザー体験に直結し、複数デバイスで同期したい設定。
一方で、Widget の quick action や preview seed flag など、デバイスローカルでよい設定もある。
ここが曖昧だと `DayBoundary`、Widget 表示、スコア計算がデバイスごとにズレる。

### どう変更するか

設定を 2 種類に分ける。

| 保存先 | 用途 |
|--------|------|
| `UserSettings @Model` | `defaultVisibility`, `enabledCategorySetID`, `themeName`, `showCalendarOverlay`, `dashboardCardOrder` |
| `@AppStorage` | preview/debug seed flag、最後に開いたタブ、デバイス限定 UI 状態 |

`DayBoundary` は 0:00-24:00 固定の境界ヘルパーとして扱う。

```swift
let boundary = DayBoundary(calendar: .current)
```

Widget も App Group の SwiftData から `UserSettings` を読み、同じ `enabledCategorySetID` を使う。

---

## 6. Singleton / master seed の重複対策が足りない

### 問題

`UserSettings` は「0件なら1件挿入」、`UnlockItem` は「既存 key 以外を追記」と書かれているが、CloudKit 同期時の重複に対する処理が未定義。

### 理由

複数デバイスがオフラインで初回起動すると、それぞれ `UserSettings` や built-in master を seed する。
その後 CloudKit 同期されると同じ意味のレコードが複数件になる。
`@Attribute(.unique)` を外すなら、重複解決は必須。

### どう変更するか

`BootstrapStore` または `SeedCoordinator` を追加し、起動時に重複整理を行う。

```swift
@MainActor
func ensureUserSettings() throws -> UserSettings {
    let settings = try context.fetch(FetchDescriptor<UserSettings>())
    if let primary = settings.sorted(by: { $0.createdAt < $1.createdAt }).first {
        for duplicate in settings.dropFirst() {
            primary.merge(from: duplicate)
            context.delete(duplicate)
        }
        return primary
    }

    let created = UserSettings()
    created.settingsKey = "default"
    context.insert(created)
    return created
}
```

`UnlockItem` / built-in `VisibilityPreset` も `key` 単位で同様に統合する。

---

## 7. `@Query` の動的フィルタ設計が雑

### 問題

[05-screen-flow.md](05-screen-flow.md) の Dashboard 設計では、`@State private var period` と `@Query private var chapters` を同じ View に置き、「`init(period:)` で `Query(filter:)` を構築」としている。

### 理由

`period` が `@State` として同じ View 内で変わっても、`@Query` の predicate は自然には差し替わらない。
また、`DayBoundary` や `UserSettings` に依存する日付範囲は `#Predicate` に直接閉じ込めにくい。
このままだと期間切替後に古い query のまま描画する、または View の初期化設計が崩れる。

### どう変更するか

動的 query が必要な画面は子 View に分ける。

```swift
struct DashboardView: View {
    @State private var period: DashboardPeriod = .today

    var body: some View {
        DashboardPeriodView(period: period)
            .id(period)
    }
}

struct DashboardPeriodView: View {
    @Query private var chapters: [Chapter]

    init(period: DashboardPeriod, boundary: DayBoundary) {
        let range = period.dateRange(using: boundary)
        _chapters = Query(filter: #Predicate<Chapter> {
            $0.startTime < range.end && ($0.endTime ?? $0.startTime) >= range.start
        })
    }
}
```

ただし SwiftData predicate で optional fallback が書きにくい場合は、広めに fetch して `ScoreStore` / pure logic 側で絞る。
スコア計算の正確性を優先するなら、Dashboard は `ScoreStore.summary(period:)` に寄せる方が安全。

---

## 8. active chapter の整合性がマルチデバイスで壊れる

### 問題

現計画では active chapter は `endTime == nil` で判定されるが、複数デバイス・Widget から同時に記録開始した場合の競合処理がない。

### 理由

CloudKit 同期は非同期。
iPhone と Widget、または 2 台の端末で同時に `startChapter` すると、`endTime == nil` の Chapter が複数残る可能性がある。
`@Query(filter: endTime == nil)` も配列を返す設計なので、複数 active は起こり得る前提で扱うべき。

### どう変更するか

`ChapterStore.startChapter` の先頭で active chapter を全件 fetch し、1 件へ収束させる。

方針:

1. 同カテゴリ active がすでにある場合はそれを維持し、新しい Chapter を作らない
2. 別カテゴリへ切り替える場合は、既存 active を `endTime = now` で閉じ、新カテゴリを active にする
3. `ChapterStore` は直前に作った切替だけを `SwitchContext` として保持する
4. `SwitchContext.activeChapterID` と現在 active が一致し、その active が 1分未満でさらに別カテゴリへ切り替えられた場合は、短い active だけを削除して新カテゴリを開始する
5. `SwitchContext.activeChapterID` と現在 active が一致し、その active が 1分未満で元カテゴリへ戻された場合は、短い active を削除し、元カテゴリ Chapter の `endTime` を `nil` に戻して継続する
6. 保存後に Widget timeline reload を呼ぶ

`HomeView` 側も `activeChapters.first` ではなく、Store/logic の `resolvedActiveChapter(from:)` を使う。

---

## 9. `photoData: Data?` を CloudKit 同期モデルに直接入れるのは危険

### 問題

[04-data-model.md](04-data-model.md) は `Chapter.photoData: Data?` を Phase 1 モデルに追加している。

### 理由

写真のバイナリを SwiftData + CloudKit managed sync に直接載せると、同期容量・初回同期速度・Widget 読み込み・将来の共有範囲制御が重くなる。
計画のオープン論点にも「写真データのサイズ」が残っているが、モデル例では既に `photoData` 採用済みのように見える。

### どう変更するか

Phase 1 では `photoData` を実装しないか、最低限 `photoLocalIdentifier` / `thumbnailData` に分ける。

推奨:

```swift
public var photoLocalIdentifier: String? = nil
public var thumbnailData: Data? = nil
```

本体画像は Phase 2/3 で PhotoKit / file storage / CKAsset 相当の手段を検討する。
仕様書の `photoData` は「写真添付機能の要件」と読み替え、保存形式は未確定にする。

---

## 10. `ModelConfiguration` は App Group 専用 initializer を優先する

### 問題

[03-architecture.md](03-architecture.md) と [04-data-model.md](04-data-model.md) のサンプルは App Group URL を手動で作り、`ModelConfiguration(schema:url:cloudKitDatabase:)` に渡している。

### 理由

現在の SwiftData には App Group 用の `groupContainer` パラメータがある。
手動 URL でも動く可能性はあるが、App Group の意図がコード上で見えにくく、将来の Store 分割時に設定漏れを生みやすい。

### どう変更するか

サンプルは `groupContainer` を使う形へ寄せる。

```swift
let cloudConfig = ModelConfiguration(
    "Cloud",
    schema: cloudSchema,
    groupContainer: .identifier("group.app.YasudaRyuga.Liminalog"),
    cloudKitDatabase: .private("iCloud.app.YasudaRyuga.Liminalog")
)

let cacheConfig = ModelConfiguration(
    "LocalCache",
    schema: cacheSchema,
    groupContainer: .identifier("group.app.YasudaRyuga.Liminalog"),
    cloudKitDatabase: .none
)
```

Widget が同じ ModelContainer を開くなら、Widget target にも App Groups と iCloud capability が必要かを Xcode 上で確認する。
もし Widget 側の CloudKit entitlement が不安定なら、Widget Intent は App Group local store に書き込み、アプリ起動時に CloudKit 同期へ寄せる fallback を検討する。

---

## 11. 次に Claude が直すべきドキュメント

優先順:

1. [04-data-model.md](04-data-model.md)
   - `@Attribute(.unique)` 削除
   - `UserSettings.settingsKey` / `UnlockItem.key` の重複整理方針追加
   - `photoData` を未確定または `thumbnailData` 案へ変更
   - CloudKit ゾーン設計を Phase 3 検証タスクへ格下げ

2. [03-architecture.md](03-architecture.md)
   - App Group / CloudKit ID 候補を現 Bundle ID ベースへ修正
   - ロードマップを「最小 Core 化 → Widget」の順に変更
   - SwiftData managed sync と CKShare 手動共有を分離

3. [05-screen-flow.md](05-screen-flow.md)
   - `@AppStorage` 設定を `UserSettings` に寄せる
   - Dashboard の動的 `@Query` を子 View 化または `ScoreStore` 集計へ変更
   - active chapter 複数時の UI/Store 収束ルールを追記

4. [06-testing.md](06-testing.md)
   - `SeedCoordinatorTests`
   - `ActiveChapterResolutionTests`
   - `DashboardPeriodQueryTests`
   - CloudKit unique 非使用の重複統合テスト

---

## 12. 担当判断

このレビューで見つかった修正は、ロジック・同期境界・アーキテクチャ順序の問題なので、実装修正は Codex 向き。
ただし、ドキュメントの言い換えや画面フローの整合は Claude が得意。

推奨分担:

| 作業 | 担当 | 理由 |
|------|------|------|
| `04-data-model.md` の CloudKit 互換修正 | Codex | SwiftData/CloudKit 制約の実装者視点が必要 |
| `03-architecture.md` のロードマップ修正 | Codex | 依存順序の破綻を直すため |
| `05-screen-flow.md` の UX 表現整理 | Claude | 既存 SwiftUI フローとの整合を取りやすい |
| `06-testing.md` のテストケース追記 | Codex | エッジケース・重複・競合を機械的に詰めるため |
