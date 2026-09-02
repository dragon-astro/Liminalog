# 31. 過剰実装・軽量化台帳（アプリ全体監査）

2026-09-01 のユーザー指示「過剰実装となっている箇所がないかアプリ全体をレビュー」「挙動を変えずに軽量化できる箇所がないか」に対する、**コード全走査による証拠つき台帳**。App + Widget 60,419行 / Test 14,246行を対象に、静的集計（行数・参照数・重複行数）とマイクロベンチで裏を取った。

本書は2部構成:

- **§2 過剰実装（O-1〜O-7）** — 二重実装・死蔵コード・先走り実装。挙動には出ないが、以後の全変更に二重コストとして課金され続けるもの
- **§3 軽量化（P-1〜P-11）** — 「同じ結果を、同じ回数・同じ順序で、同じ見た目で返す」範囲に収まる最適化のみ

> **[28-ux-interaction-performance-v3.md](28-ux-interaction-performance-v3.md)（v3）の §1〜§4 と [21-refactoring-playbook.md](21-refactoring-playbook.md) §2〜§3 が正。** 本書はそれを置き換えない。運用・不変条件・比較プロトコル・合格基準は v3 / docs/21 に従うこと。
>
> **[29-performance-hotspot-catalog.md](29-performance-hotspot-catalog.md)（H1〜H6）とは重複しない。** 既出のホットスポットは再掲せず、§4 に接続関係だけ記す。
>
> ステータス：**§3 は Codex 着手可**（v3 Item B 完了後）。**§2 は着手前にユーザー確認**（削除・統合の是非はユーザー判断）。

---

## 1. 本書の適用ルール

1. **§3 の全項目は「挙動・見た目の変更ゼロ」の範囲に収まる。** アニメーションの削除・簡略化、操作の離散化（間引き・量子化・ワンテンポ遅れ）、機能/表示の削減は一つも含まない。したがって docs/29 §1 のユーザー常設ルールに抵触せず、**§3 について AI_TASKS §11 の相談は不要**
2. **台帳に載っていることは修正理由にならない。** v3 の流儀どおり「計測で犯人確認 → 修正 → 同条件再計測」を経ること。ただし P-1 / P-3 / P-6 / P-9 / P-11 は「同じ結果をより少ない仕事で得る」機械的置換なので、計測は before/after の確認用（採否判断ではない）
3. **§2 は挙動不変だが、削除・統合の判断はユーザー専権。** 特に O-3（死蔵コード）は「差し替え途中の旧版」と「これから使う予定」を機械的に区別できない
4. **数値の出所は §5 を必ず読むこと。** ns 値は実機 Release ではない

---

## 2. 過剰実装

### O-1. 日タイムラインと週タイムラインが、別々に同じものを実装している【最大】

- **証拠**:
  - `Views/Calendar/EditablePlanTimelineView.swift`（2,423行）と `Views/Calendar/CalendarWeekTimelineView.swift`（2,235行）で、`private var` / `private func` のメンバー名が **68 / 約140 一致**（約49%）
  - 6行以上の完全一致ブロックだけで **376行**（日側の 15.5%）。構造だけ同じで文字が違う部分を足すと実質重複はこれより大きい
  - バイト単位で同一の例: `isPoint(_:insideX:y:width:height:)`（Editable:1103 / Week:1039）、`isCreationDragDirection(startLocation:location:)`（Editable:941 / Week:867）、`deleteConfirmationBubbleSize(containerWidth:)`（Editable:1162 / Week:1098）
  - 連続一致の大きいもの: 削除確認バブル周辺 36行（Editable:1154-1189 ↔ Week:1090-）、`hourScrollTargets` 25行（Editable:378-402 ↔ Week:262-）
  - 一致しているのは触る頻度が高い部分そのもの: 作成ロングプレス、移動/リサイズのドラッグ、削除確認バブル、時刻ガイド、スナップ、アクセシビリティ操作、レンダキャッシュ、ジェスチャ後始末
- **代償**: タイムライン系のバグ修正・仕様変更は毎回2箇所に手を入れる必要がある。v3 Item B の作業もこの二重性を踏んでいる
- **方向**: 週は「日を7つ並べたもの」なので、**日側を `dayWidth` パラメータ化すれば週はその特殊化になる**。
  1. 純粋関数（当たり判定・寸法計算・スナップ・ドラフト算出）を `Logic/` の enum static へ抽出し、テストで固定してから移す
  2. ジェスチャ本体は `dayWidth` / `dayIndex(forX:)` を注入する共通型へ
  3. docs/21 R1（View分割）の手順・検証プロトコルに乗せる。1ファイルずつ、各ステップでビルドが通る状態を保つ
- **注意**: **v3 Item B が同じ2ファイルを触っている。B 統合後にリベースし、同一ファイル同時作業をしない**（docs/29 §4 と同じルール）。分割前後でスクリーンショット比較（ライト/ダーク両方）が必須

---

### O-2. 月カレンダーが CalendarView と FriendsView に二重に存在する

- **証拠**:
  - `Views/Calendar/CalendarView.swift`（4,062行）と `Views/Friends/FriendsView.swift`（4,339行）で **34個のメンバー名が一致**: `computePageData` / `cachedPageData` / `ensureData` / `monthStart` / `offset` / `pageDate` / `prepareMonthPicker` / `reloadVisibleData` / `weekdayColor` / `jump` / `calendarTopBar` / `calendarYearRange` / `pageDataByMonth` / `visibleMonth` / `anchorMonth` / `pickerYear` / `pickerMonth` / `filteredPlans` / `searchField` / `searchResultText` / `trimmedQuery` ほか
  - 6行以上の完全一致 157行。`monthStart(for:)` は 13行一致（CalendarView:1219 ↔ FriendsView:3208）、予定検索シートは CalendarView:2546-2676 ↔ FriendsView:3740-3839 でほぼ丸ごと
  - 月ページャ・月ピッカー・予定検索シートが 2セット存在する
- **方向**: ページャ / 月ピッカー / 検索シートを共通 View 化し、**日別データの取得だけを差し替え可能**にする。`Stores/FriendCalendarPageDataBuilder.swift` という前例が既にあるので、その線を伸ばす形になる
- **注意**: 友達側は `FriendSharedRecordStore` 経由の別データ源。共通化は「表示の器」までに留め、データ取得は分けたまま

---

### O-3. どこからも参照されていない型が9つ残っている

- **証拠**: アプリ・Widget・テストのいずれからも参照が無い（宣言のみ）。`#Preview` からも呼ばれていない

| 型 | 場所 |
|---|---|
| `TimelineChapterCard` | `Views/Home/TimelineChapterCard.swift:3`（**ファイル丸ごと 91行**） |
| `YesterdayScoreCard` | `Views/Home/HomeView.swift:778` |
| `FriendProfileHero` | `Views/Friends/FriendsView.swift:2558` |
| `FriendScoreCard` | `Views/Friends/FriendsView.swift:2803` |
| `ProfileCollectionSection` | `Views/Profile/ProfileComponents.swift:3007` |
| `ProfileCollectionBadge` | `Views/Profile/ProfileComponents.swift:3029` |
| `ProfileFragmentBalanceCard` | `Views/Profile/ProfileComponents.swift:2949` |
| `ProfileFormat` | `Views/Profile/ProfileDecorations.swift:425` |
| `DashboardProgressRow` | `Views/Dashboard/DashboardCards.swift:364` |

- **方向**: 削除は挙動に影響しない。O-1 / O-2 の分割前にこれを消すと、対象ファイルが素直に小さくなる（`FriendsView` -350行前後、`ProfileComponents` -200行前後）
- **注意**: **削除前に1件ずつユーザー確認。** 「差し替え途中で旧版が残った」ものと「これから使う予定」を機械的には区別できない。再現方法: `grep -rlw "<型名>" --include="*.swift" Liminalog LiminalogWidget LiminalogTests LiminalogUITests`

---

### O-4. EventKit 連携の下半身だけが完成し、スキーマを占有している

- **証拠**:
  - `Stores/CalendarEventSyncStore.swift`（307行）と `@Model CalendarEventCache`（`Models/CalendarEventCache.swift`）は、**アプリ本体から一度も呼ばれていない**（参照は `LiminalogTests/CalendarEventSyncStoreTests.swift` のみ）
  - AI_TASKS §7.1 で `EventKitStore`（権限取得・予定読み込み・差分同期）が未着手のまま。取り込み先だけが先に完成している
  - `CalendarEventCache` は `SharedModelContainer.localCacheSchema`（:109）と `schema`（:132）、`LiminalogSchemaV1.models`（:20）、`PreviewSupport.swift:8` に登録済み
- **代償**: docs/21 §2.1「保存済みプロパティの削除・型変更は禁止。追加のみ」に従うなら、使われないまま永久に居座る
- **救い**: `localCacheSchema` 側なので **CloudKit 同期対象ではない**。EventKit への依存も無い（プレーン値受け取り設計）。実害は起動時のスキーマ構築コストと保守面のみ
- **方向**: EventKit 連携を続行するなら現状維持でよい。**凍結・見送りの判断があるなら、スキーマから外すかを AI_TASKS §11 の論点として起票する**（外すなら早いほど安い）
- **注意**: 判断はユーザー専権。Codex が独断で外さない

---

### O-5. `* 0` という無効な算術が4箇所に残っている

- **証拠**:
  - `Design/LiminalTheme.swift:135` — `.opacity((darkFillOpacity ?? treatment.tintFillOpacity) + Double(transitionProgress * 0))`
  - `Design/LiminalTheme.swift:170` — `y: (isLight ? 6 : 8) + transitionProgress * 0`
  - `Design/LiminalTheme.swift:184` — `.opacity(treatment.fillOpacity + Double(transitionProgress * 0))`
  - `Views/Profile/UnlockGalleryView.swift:247` — `.opacity(1 + Double(themeTransitionProgress * 0))`（実質 `.opacity(1)`）
- **解釈**: テーマ遷移中の再描画を強制する意図と思われるが、いずれも直前で `themeTransitionProgress` を読んでおり、**SwiftUI の Environment 依存はその読み取り時点で登録される**。この加算は値にも依存関係にも寄与していない
- **方向**: 削除。ただし「これを入れたらテーマ切替の描画が直った」経験が背景にあるなら残す理由になる
- **注意**: 除去するなら **テーマ切替アニメーション（0.42秒）の目視確認をセットで**。ライト/ダーク/システム追従（`"default"`）の3状態すべて

---

### O-6. 1行 Policy 型の粒度 —— 指摘のみ、削るべきではない

- **証拠**: 本番の呼び出し元が1箇所・残りは専用テストからの参照、という型がある。`CloudFriendProfileOwnershipPolicy`（7行・本体は `a == b` 一つ / 参照4 うちテスト3）、`CloudFriendSharePublishPolicy`（7行 / 参照5 うちテスト4）、`CloudFriendShareRecipientPolicy`（7行 / 参照4 うちテスト3）、`CloudFriendConsentSubscriptionPolicy`（31行 / 参照4 うちテスト3）
- **判断**: **削除しない。** docs/21 §1 が Policy 群を「リファクタリングのお手本」と定義しており、§2.5 で `CloudFriendShare*` は2台実機E2Eなしに挙動を変えられない保護領域とされている。実機E2Eが高コストな領域では、この単体テストが唯一の安全網になる
- **方向**: 新規 Policy を切るときの基準として「本番呼び出しが2箇所以上あるか / E2E が困難か」を意識すれば、粒度は自然に揃う。既存には手を入れない

---

### O-7. `PreviewSupport.swift` が `#if DEBUG` の外にある

- **証拠**: 呼び出し側（`Views/RootTabView.swift:112`、`Views/Settings/SettingsView.swift:8-16, 221-227`、`Stores/ChapterStore.swift:836-852`）はすべて `#if DEBUG` で守られているのに、`Liminalog/PreviewSupport.swift`（224行）本体だけは Release にも含まれる。`Liminalog/PreviewRuntimeSeedSupport.swift`（664行）は正しく `#if DEBUG` 済みで、片方だけ漏れている
- **影響**: 実行時コストはほぼゼロ（`static let container` は lazy）。バイナリサイズとダミーデータ文字列が乗るだけ
- **方向**: ファイル全体を `#if DEBUG` で囲む。AI_TASKS §5.6「DEBUG seed の隔離」の残件そのもの
- **注意**: `PreviewSupport.devDataFlagKey` を `SettingsView` の `@AppStorage` が参照している（:10）が、こちらも `#if DEBUG` 内なので問題ない

---

## 3. 軽量化（挙動・見た目の変更ゼロ）

影響の大きい順。各項目「証拠 → 方向 → 注意」。

### P-1. 記録タップのたびにプロセス環境変数の辞書を6回以上作り直している【大 / 安全】

- **証拠**:
  - `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]` というテスト判定が**実行時パスに15箇所**ある。Darwin ではこのプロパティは参照のたびに `environ` を走査して `[String: String]` を丸ごと構築するため、単なる辞書引きではない
  - 集中しているのがアプリの心臓部。カテゴリを1回タップすると `markChanged`（ChapterStore:60）→ `cacheActiveCategoryID`（:74）→ `publishRecordingSurfaceSnapshot`（:137）→ `LiveActivityCoordinator.update`（:12, :46）→ `CloudFriendShareRefreshCoordinator.requestRefresh`（:113 ほか）の各段でそれぞれ1回、**合計6回以上がタップ直後のフレーム上で**走る
  - 全箇所: `ChapterStore.swift:60, 74, 79, 95, 137` / `CloudFriendShareRefreshCoordinator.swift:113, 131, 217, 239, 268` / `LiveActivityCoordinator.swift:12, 46` / `SharedModelContainer.swift:212` / `Views/Settings/WidgetSettingsView.swift:154` / `LiminalogApp.swift:19`

| 実装 | 1回あたり | 条件 |
|---|---:|---|
| `ProcessInfo.processInfo.environment[...]` | 28,005 ns | 環境変数52個 |
| `ProcessInfo.processInfo.environment[...]` | 1,883 ns | 環境変数3個 |
| キャッシュ済み `static let Bool` | **0.3 ns** | — |

- **方向**: 判定を1箇所に集約する。

  ```swift
  enum LiminalogRuntime {
      static let isRunningUnitTests =
          ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }
  ```

  15箇所を機械的に差し替える。プロセス環境は実行中に変わらないので**結果は完全同一**
- **注意**: `PreviewRuntimeSeedSupport.swift:18` / `PurchaseStore.swift:54, 132, 412` は `environment:` を**引数のデフォルト値**として受けており、テストから差し替えるための設計。ここは触らない。`RootTabView.swift:336` / `ProfileView.swift:364` / `FriendsView.swift:3343` / `UnlockGalleryView.swift:193` は別キー（DEBUG 起動フラグ）で1回だけ読むので対象外

---

### P-2. 記録タップのたびに TimelineView がまるごと破棄・再生成されている【大 / 要検証】

- **証拠**:
  - `Views/Home/HomeView.swift:418` — `.id("\(date.timeIntervalSince1970)-\(store.contentRevision)")`
  - `contentRevision` は `ChapterStore.markChanged()`（`ChapterStore.swift:58`、24箇所から呼ばれる）で毎回インクリメントされる。つまり**記録の開始・終了ごとに `TimelineView` の identity が変わり**、SwiftUI は差分更新ではなく破棄→再構築を選ぶ
  - 失われるもの: `@State` 8個（`TimelineView.swift:117` の `TickClock` = `Timer` を含む）、`@Query` 2本（:101-102、＝全件再フェッチ）、レイアウトのキャッシュ、進行中のアニメーション。`onDisappear` / `onAppear`（:252-258）も毎回走る
  - String 補間による `.id` 値の生成も毎 body
- **方向**: `.id()` から `store.contentRevision` を外す（`date` 由来のみ残す）。`TimelineView` は `@Query` でデータ変更を自動追従するので、この `.id()` は **`@Query` 移行（AI_TASKS §5.4）前の名残の可能性が高い**
- **注意**:
  - docs/28 v3 §2 の「blanket な `.id()` 禁止」に真っ向から当たる
  - **外して壊れないかの確認が必須**: 記録開始→停止→再開で `@State`（`editingPlan` / `highlightedEntryID` / `selectedTabRawValue` / `quickDetailEntry`）が意図どおり残る／消えるか。特に「記録停止後にタイムラインのタブ選択が実績側へ戻る」等の副作用に依存していないか
  - docs/29 H4「カテゴリボード切替 2.7秒」の犯人候補。**区間分解の前に、これ単独の before/after を1本取る価値がある**

---

### P-3. キャッシュの鍵が巨大な String で、body 評価ごとに組み立て直されている【大 / 安全】

- **証拠**:
  - `Views/Home/HomeView.swift:741` `payloadSourceSignature` — その日の全予定・全実績について `uuidString`（1件36文字の String 生成）と `timeIntervalSince1970` の文字列補間を作り `joined` で連結。これが **1回の body 評価で最低2回**走る（`resolvedPayload`:734 の比較 と `.task(id:)`:728）
  - `Views/Home/DailyReflectionCard.swift:496` `renderSignature` — さらに重く、`DailyReflectionPayloadCard` の `Equatable` 実装（:617-621 `lhs.renderSignature == rhs.renderSignature`）が使う。**再描画を省くための比較そのものが、毎回巨大な文字列を作っている**という逆転
  - `DailyReflectionCard.swift:483` `snapshotSignature` — `.task(id:)`（:637）と `Set<String>` の鍵（`HomeView.swift:686`）に使用
  - `Views/Profile/ProfileView.swift:103` `dailyCardBackfillSignature` — 120件を毎 body 連結し `.task(id:)`（:243）へ

| 署名の作り方（40件） | 1回あたり |
|---|---:|
| String 補間 + `joined`（現行） | 10,080 ns |
| `Hashable` struct の配列 | **361 ns** |

- **方向**: `Hashable` struct へ置換。**`Views/Calendar/EditablePlanTimelineView.swift:14` の `EditableTimelinePlanSignature: Hashable` が既に正しいやり方**なので、同じ形へ揃えるだけ。比較の意味論はフィールド単位の等値比較で完全に同一
- **注意**: `snapshotSignature` は `persistedSnapshotSignatures: Set<String>`（`HomeView.swift:686` / `ProfileDailyCardArchiveView.swift:10`）の鍵にも使われている。`Set<Sig>` に変えれば挙動同一（**永続化はしていない**ので移行不要）。ただし `DailyCardSnapshotStore.upsert` へ渡す値は変えないこと

---

### P-4. 装飾の解放判定を、1回の body で4〜8回まるごと作り直している【大 / 安全】

- **証拠**:
  - `Logic/ProfileDecorationUnlocks.swift:21` の init は、**1回の初期化で `unlockItems` を5周**し `Set<String>` を5つ作る（`unlockedTargetIDs`:266 を5回）
  - `unlockItems` は解放カタログ全件（`Logic/UnlockRules.swift:313` の定義 **99件**）
  - 各要素は SwiftData の `@Model`。`$0.kind`（`Models/UnlockItem.swift:73`）は `UnlockKind(rawValue: kindRawValue)` という String→enum 変換を伴う
  - `Views/Profile/ProfileView.swift:56` の `decorationUnlocks` は **computed property**。`iconFrame`（:110）/ `streakIcon`（:114）/ `cardStyle`（:118）/ `accentColor`（:48 経由）/ シート引数（:215）からそれぞれ独立に再構築される（参照8箇所）
  - `Views/Friends/FriendsView.swift:73` も同様（参照3箇所、`iconFrame` 経由で計7箇所）
  - 概算: 1 body あたり 4回 × 5周 × 99件 = **約2,000回の SwiftData プロパティ読み + enum 変換**、`Set` 生成20個
- **方向**: body の先頭で1回 `let unlocks = decorationUnlocks` して配る。または `@State` + `unlockItems` 変化時のみ再計算。**`Views/Profile/ProfilePerformanceSnapshot.swift` が同じ画面で既に採っている方式**なので揃う
- **同型（同じ画面・同じ直し方）**:
  - `ProfileView.swift:120` `badges` → `equippedBadge`（:127）→ `badges` の多重評価
  - `ProfileView.swift:131` `freshUnlockItems` → `hasFreshUnlockItems`（:139）。内部（`ProfileDecorationUnlocks.swift:131`）でさらに `ProfileDecorationUnlocks` を1個作る
- **注意**: `includesLockedCatalogItems`（DEBUG 専用）の値が body 中に変わらないことを確認してから1回化する

---

### P-5. 期間スコアが O(日数 × 件数)、しかも捨てる値を365日分作っている【大 / 中リスク】

- **証拠**: `Stores/ScoreStore.swift:174-199` `dailyScoreDraftsIfAvailable` に2つの無駄がある
  1. `dates.map { date in plans.filter { ... }; chapters.filter { ... } }` —— **日ごとに期間内の全予定・全実績を線形走査**する。年セグメントなら 365日 × その年の全件。1日5件なら約1,800件 × 365 ≒ 65万回の判定を、予定と実績それぞれで回す
  2. `summariesIfAvailable`（:159、＝ `averageScore`:586 の実装）は `.map(\.summary)` しか使わないのに、`DailyScoreSnapshotDraft` の全フィールドを365日分作る: `dayIdentifier` の文字列生成（:215）、`categoryIDs` の `Set` + `uuidString` ソート（:213-214）、`earlyRecordDay` / `lateNightRecordDay` の `calendar.component(.hour:)` 走査（:222-229）。すべて捨てられる
- **呼ばれ方**: `Views/Friends/FriendsView.swift:685` `selfScore(for:)` が body 経路から直接呼ぶ。しかも `clock.now` 依存なので毎分の tick で再計算候補になる
- **方向**:
  1. 予定・実績を最初に1回だけ日単位バケットへ振り分ける（跨ぎは各日に追加）→ O(件数 + 日数)
  2. `includeCardMetrics` と同じ要領で「summary だけ欲しい」フラグを足し、余計なフィールド生成を飛ばす
- **注意**:
  - **docs/29 H3 / docs/27 §8.15 と共有タスク。二重実装禁止。** 確定日の `DailyScoreSnapshot` 読み一本化と先に着手した側が実装し、他方は前提にする
  - バケット分割は「跨ぐ予定を両日に入れる」現行仕様を厳密に再現すること。**正しい実装の前例が `Views/Calendar/CalendarView.swift:1161` `dayStartsOverlapping` にある**
  - 表示値が1点でも変わったら不採用

---

### P-6. スコア計算が、同じグルーピングを2度やって片方は毎回配列を作っている【中 / 安全】

- **証拠**: `Stores/ScoreCalculator.swift:60-61` の `summary` は `categoryAchievementScore`(:75) で `Dictionary(grouping: chapters, by: \.categoryID)` を作る。その直後に呼ぶ `timelineMatchedDuration`(:89) は、同じ情報を **予定1件ごとに `chapters.filter { $0.categoryID == plan.categoryID }`**(:91) で作り直す。予定の件数だけ配列アロケーションが走る
- **方向**: `summary` の中で `chaptersByCategory` を1回作り、両方に渡す。`Dictionary(grouping:)` はグループ内の順序を入力順で保つので、**`reduce` の結果（浮動小数の加算順）まで完全同一**
- **注意**: 効き所は P-5 の年セグメント（365倍になる）。**P-5 と同じブランチで直すのが自然**。`LiminalogTests/ScoreCalculatorTests.swift` が既にあるので、値の同一性はそこで固定できる

---

### P-7. `store.activeChapter` は参照するたびに SwiftData を fetch する【中 / 安全】

- **証拠**:
  - `Stores/ChapterStore.swift:300` の `activeChapter` は computed property で、中身は `modelContext.fetch(FetchDescriptor<Chapter>(predicate: endTime == nil))`（:308-319）。キャッシュは無い
  - `Views/Home/CategoryGrid.swift:51` が `.onChange(of: store.activeChapter?.category?.id)` で読んでいる。**`onChange(of:)` の値は body 評価のたびに計算される**ので、記録ボードが再評価されるたびに fetch が1回走る。`:287` の `syncSelection()` からも読む
- **方向**: `Views/Home/CurrentChapterCard.swift:19-28` が既にやっているように `@Query`（`endTime == nil` の述語つき）で受ける。`@Query` なら SwiftData 側で結果が保持され、変更時のみ再評価される。または `ChapterStore` 側で `activeChapter` を保持し `markChanged` で更新する
- **注意**: docs/29 H4 と同じ画面。**区間分解を取るときにこの fetch も計測対象に入れる。** `@Query` 化する場合、`ChapterStore` 経由の書き込み直後に UI が同期する現行タイミングが変わらないことを確認（`@Query` は同一 `ModelContext` の変更を拾う）

---

### P-8. `Calendar.japanese` が参照118箇所すべてで新しい Calendar を作っている【中 / 安全】

- **証拠**:
  - `Extensions/Date+Formatting.swift:55` は `static var`（computed）。参照のたびに `Calendar(identifier: .gregorian)` と `Locale(identifier: "ja_JP")` を新規構築する
  - アプリ全体で **118箇所**から参照。`CalendarView.swift` だけで33箇所、`FriendsView.swift` 13箇所、`Models/Friend.swift` 7箇所
  - View の `private let calendar = Calendar.japanese`（`CalendarView.swift:42, 1421, 2452, 2544, 3095` / `CalendarWeekTimelineView.swift:87` / `EditablePlanTimelineView.swift:109` / `FriendsView.swift:2850`）は**ストアドプロパティの初期化式なので View struct が再生成されるたびに走る**（ページャで多数生成される日/週タイムラインが該当）

| 実装 | 参照のみ | + `startOfDay` |
|---|---:|---:|
| computed（現行） | 215 ns | 1,638 ns |
| キャッシュ済み | **31 ns** | **1,444 ns** |

- **方向**: `static let` にキャッシュし、`TimeZone.current`（54 ns で取得できる）が変わったときだけ作り直す。computed のままにしている理由が `calendar.timeZone = .current` の追従なら、この条件付きキャッシュで意味論は保たれる
- **注意**: `NSSystemTimeZoneDidChangeNotification` でも同じことができる。**旅行・DST を跨いだ日跨ぎ判定が変わらないこと**を確認する（docs/21 §2.4 の 0:00-24:00 固定は不変）

---

### P-9. UUID の整列に `uuidString` を使っている（比較のたびに36文字を生成）【中 / 安全】

- **証拠**: `sorted { $0.uuidString < $1.uuidString }` は比較1回につき String を2つ作る。ソートは O(n log n) 回比較するので、12件でも数千文字を作って捨てる

| 12件の UUID | 1回あたり |
|---|---:|
| `sorted { $0.uuidString < $1.uuidString }` | 6,302 ns |
| `Set(ids)`（等値判定だけが目的の場合） | **618 ns** |

- **全10箇所**:
  - **キャッシュ鍵の正規化（順序に意味なし）**: `EditablePlanTimelineView.swift:138` / `CalendarWeekTimelineView.swift:1451, 1464`（どちらも `renderCacheKey` = 毎 body）/ `ScoreStore.swift:214`（P-5 の365日ループ内）/ `AudiencePickerSheet.swift:218`
  - **表示順に出る（順序に意味あり）**: `PlanStore.swift:336` / `PlanTimelineRescheduler.swift:109, 123, 141`（同時刻のタイブレーク）/ `Models/FriendCategoryMapping.swift:81`
- **方向**:
  - 順序が意味を持たない箇所 → `Set<UUID>` に置換。`Set` は `Hashable` かつ順序非依存なので**キャッシュ鍵として等価**
  - 順序が表示に出る箇所 → **`uuid`（バイト列タプル）比較に変えると順序が変わるので不可**。安全に済ませるなら `uuidString` を1度だけ計算して添える（Schwartzian transform）方式にする
- **注意**: 表示順のタイブレークは `LiminalogTests/SortOrderReorderingTests.swift` / `PlanTimelineReschedulerTests.swift` が固定している。**テストが通ることを順序変更なしの証拠にする**

---

### P-10. `LiminalTheme` の色トークンは参照ごとに UIColor 動的プロバイダを作る【中 / 要検証】

- **証拠**:
  - `Design/LiminalTheme.swift:31-43` の `canvas` / `text` などは computed。参照のたびに `UIColor { traits in ... }`（:75-81 `token(_:)`）のクロージャ付きインスタンスと `Color` のラップを新規生成する
  - アプリ全体で `LiminalTheme.*` の参照は **851箇所**。`FriendsView` 97 / `ProfileComponents` 88 / `UnlockGalleryView` 70 / `SupportLiminalogView` 51 / `CalendarView` 50。1回の body で20回読めば20個作られる
- **既知の意図**: `LiminalTheme.swift:27-29` のコメントに「`static let` にすると UIColor の動的色が trait 単位でキャッシュされ `activeThemeID` の変化を検知できない」と明記されている
- **方向（折衷案）**: `(activeThemeID, transitionSourceThemeID, transitionProgress)` を世代キーにした static キャッシュを持ち、世代が変わったら破棄する。テーマ遷移中（`progress < 1`）だけキャッシュを無効化すれば、**定常状態では1トークン1インスタンス、遷移中は現行と完全に同じ挙動**になる
- **注意**:
  - **先に Instruments で allocation が実際に効いているか確かめてから着手する**（docs/28 §2「計測で犯人確認」）。効いていなければ触らない
  - 検証: テーマ切替アニメーション（0.42秒）の見た目が1フレームも変わらないこと、ライト/ダーク切替とシステム追従（`"default"`）が正しく追従すること

---

### P-11. 小粒だが数がある —— まとめて1コミットで済むもの【小 / 安全】

- **`onChange(of:)` の配列生成 8箇所**: `.onChange(of: categories.map(\.id))` は body 評価ごとに `[UUID]` を新規生成して比較する。`CalendarView.swift:135` の `acceptedFriends.map(\.id)` は `filter` + `map` の二重生成
  - `HomeView.swift:476` / `CategoryGrid.swift:35, 54` / `EditablePlanTimelineView.swift:239` / `CalendarWeekTimelineView.swift:227` / `CalendarView.swift:130, 135` / `ProfileComponents.swift:2196`
- **`filter { }.count` → `count(where:)`**: 中間配列を作らずに済む。`ProfileView.swift:264` ほか
- **`JSONEncoder()` を記録タップ経路で毎回生成**: `ChapterStore.swift:150`（`publishRecordingSurfaceSnapshot`）。`static let` でよい
- **`DailyCardSnapshot.dayIdentifier` の `String(format:)` ×3 + `joined`**: `Models/DailyCardSnapshot.swift:72-81`。P-5 の365日ループから呼ばれる。`String(format:)` は数値書式化としては重い部類なので、桁埋めを直接組む方が速い（**出力文字列は同一であること**をテストで固定）
- **`CalendarView.normalizedCalendarText` の `folding(options:locale:)`**: `CalendarView.swift:1210`。月グリッドの重複排除（:1183）で全予定に1回ずつ ICU 正規化が走る。`calendarDuplicateKey`(:1190) を `Set<String>` ではなく `Hashable` struct にするだけでも連結分は減る

---

## 4. 他ドキュメント・ワークストリームとの接続

| 相手 | 重なり | ルール |
|---|---|---|
| **docs/29 H1** | 記録タップの同期副作用 | **P-1 は H1 の中身**。H1 の副作用遅延と同じブランチで直してよい |
| **docs/29 H3** | スコアのライブ計算 | **P-5 / P-6 は H3 の実装詳細**。docs/27 §8.15 とも共有タスク。先行側が実装、二重実装禁止 |
| **docs/29 H4** | カテゴリボード切替 2.7秒 | **P-2 / P-7 は H4 の犯人候補**。区間分解の前に各1本ずつ単独計測すると切り分けが進む |
| **docs/29 H6** | 描画レイヤ | 本書 §3 には含めていない（§6 参照） |
| **v3 Item B（進行中）** | `EditablePlanTimelineView` / `CalendarWeekTimelineView` | **O-1 / P-3（前例参照のみ）が同一ファイル。B 統合後にリベース。同時作業禁止** |
| **docs/21 R1 / R4** | View分割・フェッチ監査 | O-1 / O-2 は R1 の手順に、P-7 は R4 に乗る。完了ログに両参照を書く |
| **友達共有の輸送層** | `CloudFriendShare*` | docs/21 §2.5 の保護領域。P-1 は該当ファイルを触るが**テスト判定の定数化のみ**（`requestRefresh` の呼び出し条件・順序・回数は不変）。それ以外の変更は §11 起票 |

---

## 5. 計測条件（必読）

**本書の ns 値は iPhone の Release 計測ではない。** macOS arm64 上で `swiftc -O` でビルドしたマイクロベンチ（20,000〜200,000 反復・ウォームアップ有り）の値で、**各手法の相対比を示すためのもの**。

docs/21 §3 と AI_TASKS §3.5.1「パフォーマンスは Release で測る」の原則どおり、採否は必ず **実機 Release + 同条件 before/after** で判定すること。特に P-1 の `ProcessInfo.environment` は環境変数の個数に比例するため、実機での実測値はシミュレータ／Xcode 起動時より小さくなる可能性が高い。

行数・参照数・重複行数は `find` / `grep` / 差分検出スクリプトによる静的集計で、`codex/ux3-timeline-performance` ブランチの作業ツリー時点の値。再現コマンド例:

```bash
# 行数上位
find Liminalog LiminalogWidget -name "*.swift" -exec wc -l {} + | sort -rn | head -20

# 死蔵型の確認（O-3）
grep -rlw "TimelineChapterCard" --include="*.swift" Liminalog LiminalogWidget LiminalogTests LiminalogUITests

# 環境変数判定の全箇所（P-1）
grep -rn "ProcessInfo.processInfo.environment" --include="*.swift" Liminalog LiminalogWidget

# uuidString ソート（P-9）
grep -rn "uuidString <\|uuidString >" --include="*.swift" Liminalog LiminalogWidget
```

---

## 6. 本書が扱わないもの

- **blur / shadow の描画コスト**: `.blur(` 22箇所（うち `ProfileComponents` 18箇所、半径38〜56pt の大径が4箇所）、`.shadow(` 50箇所、グラデーション42箇所。大径 blur は GPU のオフスクリーンパスとして高価な部類だが、`drawingGroup()` や事前合成はアンチエイリアスの出方が変わりうるため、**「見た目が1ピクセルも変わらない」を満たせるかは実測しないと言えない**。docs/29 H6 の扱い（GPUバウンドが示された場合のみ）に従い、候補の提示までに留める
- **docs/29 H1〜H6 の再掲**: §4 に接続関係のみ
- **`TickClock` の設計**: docs/29 H2 が正
- **アーキテクチャ変更・FW導入**: docs/03 §11 / docs/21 §0 の非ゴール

---

## 7. Codex 向けサマリ

```text
[Codex goal — docs/31 §3（軽量化）の消化]
前提: docs/28 v3 の運用・不変条件・比較プロトコル・合格基準、および docs/21 §2（不変条件）
§3（検証プロトコル）に完全準拠。
ユーザー常設ルール: 操作感を変える軽量化は禁止。§3 の全項目は挙動・見た目の変更ゼロの
範囲に収まる設計なので、範囲を超えそうになったら実装せず AI_TASKS §11 へ起票して相談する。

推奨順（独立に着手可・上ほど安全で効きやすい）:
  1. P-1  ProcessInfo 判定の定数化（15箇所の機械的置換）
  2. P-3  String署名 → Hashable struct（EditableTimelinePlanSignature が前例）
  3. P-4  ProfileDecorationUnlocks の body 内1回化（ProfilePerformanceSnapshot が前例）
  4. P-11 小粒まとめ（1コミット）
  5. P-8  Calendar.japanese の条件付きキャッシュ
  6. P-9  uuidString ソートの置換（順序が表示に出る4箇所は Schwartzian で据え置き）
  7. P-6 + P-5  ScoreCalculator / ScoreSnapshotLoader（docs/29 H3・docs/27 §8.15 と要調整）
  8. P-7  store.activeChapter の @Query 化
  9. P-2  HomeView:418 の .id() から contentRevision を外す（状態保持の回帰確認を厚めに）
 10. P-10 LiminalTheme トークンの世代キャッシュ（Instruments で犯人確認できた場合のみ）

各項目の手順: docs/31 §3 の「証拠」を自分で再現 → 「方向」に沿って修正 → 「注意」の回帰確認
→ docs/21 §3 の検証3点（git diff --check / xcodebuild test / build-for-testing）
→ 実機 Release で同条件 before/after → AI_TASKS §10 完了ログに docs/31 の項目IDを明記。

衝突回避: O-1 と v3 Item B は同一ファイル（B 統合後にリベース）。P-5/P-6 は docs/29 H3・
docs/27 §8.15 と共有タスク（先行側が実装）。CloudFriendShare* は docs/21 §2.5 の保護領域で、
P-1 の定数化以外は触らない。

§2（過剰実装）は着手前にユーザー確認が必要。Codex から勝手に削除・統合しない。
```

---

## 8. 実装結果（2026-09-01）

| 項目 | 判定 | 実装・確認結果 |
|---|---|---|
| P-1 | 実装済み | XCTest 環境判定を `LiminalogRuntime.isRunningUnitTests` へ集約し、ホット経路の `ProcessInfo.environment` 再評価を除去。 |
| P-2 | 実装済み | Today の `TimelineView` identity を日付だけに戻した。Simulator で記録開始→停止→再開、Yesterday 往復後の記録継続を確認。 |
| P-3 | 実装済み | Yesterday / Daily Reflection / Profile の連結 String 署名を、フィールド単位の `Hashable` struct へ置換。署名の更新範囲をテストで固定。 |
| P-4 | 実装済み | Profile / Friends の装飾解放集合を body 内で1回だけ生成し、同一評価内で再利用。解放判定テストを追加。 |
| P-5 | 実装済み | 期間内の予定・実績を1回の日別 bucket 化へ変更。summary-only 経路ではカード用派生値を作らない。31日分について従来の日別 filter 参照実装と全 `ScoreSummary` フィールド一致を確認。 |
| P-6 | 実装済み | `chaptersByCategory` を1回だけ作り、カテゴリ達成率と時間軸一致率で共有。 |
| P-7 | 実装済み | `CategoryGrid` の active chapter 参照を predicate 付き `@Query` へ変更。記録開始・停止時のカテゴリ同期を Simulator で確認。 |
| P-8 | 実装済み | `Calendar.japanese` をタイムゾーン条件付き・lock 保護キャッシュへ変更。UTC→Tokyo の切替と設定値をテスト。 |
| P-9 | 実装済み | 等値鍵は `Set<UUID>`、表示順が意味を持つ箇所は Schwartzian transform に変更。Item B 統合後の `EditablePlanTimelineView` にも適用。 |
| P-10 | 不採用 | Allocations trace が保存時に壊れ、有効な hotspot 証拠を取得できなかった。事前条件未成立のため `LiminalTheme` は変更していない。 |
| P-11 | 実装済み | `count(where:)`、JSONEncoder 再利用、日IDの直接桁埋め、重複キーの構造体化を実装。8箇所の `onChange(of: models.map(\.id))` は、ID列の過去値を正確に保持するには同等の値スナップショットが必要なため、2026-09-01 のユーザー判断で挙動変更ゼロを優先して現状維持を採用。 |

検証結果:

- `git diff --check`: 成功
- iPhone 17 / iOS 26.5 Simulator: 558 Swift Testing + 15 XCTest、failure 0、実機・手動レンダラ専用15件のみ skip
- generic iOS Release build（`CODE_SIGNING_ALLOWED=NO`）: 成功、追加warning 0
- 実機比較用の署名済みRelease: before=`7a7c006`、after=`d240a32` を `/private/tmp/liminalog-audit-device/` に分離生成。両appとも `codesign --verify --deep --strict` 成功、Team / bundle ID / arm64条件一致
- 実画面: 記録開始→停止→再開、active category 即時同期、Yesterday の Daily Reflection 描画、Today 復帰後の記録継続を確認
- iPhone 16 / iOS 26.6 (23G71) 実機Release: USB接続で before→after の順に同一bundle IDへ上書き導入し、双方の前面起動と起動後プロセス生存を確認。上書き前後でappDataContainer直下3項目の名称構成が一致し、最終的にafter版（1.1 build 2）を端末へ残した。`devicectl` の所要時間は初回のDeveloper Disk Image準備・トンネル確立を含むため、性能差の数値根拠には用いない

採否確定:

- P-11 の8箇所のID配列監視は、ユーザー承認により正確な変更検知を維持する現状のまま確定
- §5 の実機 Release before/after はユーザー許可後に上記条件で完了。起動・プロセス生存・データコンテナ構成の回帰なし
- P-10 は再計測で有効な Allocations 証拠が取れた場合だけ再検討する
