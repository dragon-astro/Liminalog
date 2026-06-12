# 20. 友達共有のスケーラブル化（全履歴 × 軽量）設計

「友達の過去の予定/実績を**全部**見たい、でも**軽い**」を実現するための、共有データモデルの作り直し設計。**Codex引き継ぎ**（CloudKit/SwiftDataコンテナの不変条件を握るのは Codex）。

> 関連：[11-friends-design.md](11-friends-design.md)（友達設計）、[18-cloudkit-friends-runbook.md](18-cloudkit-friends-runbook.md)（CloudKit運用）。

---

## 1. なぜ今のままだと「全履歴×軽量」が無理か

**現状（塊JSON方式）**：オーナーの全期間の予定・実績を `CloudFriendShareSnapshotBuilder` が**1つのJSON文字列**にまとめ、共有ルートレコードの1フィールドに入れて共有。受信側は `Friend.sharedActivitiesJSON` / `sharedPlansJSON`（1フィールド）に丸ごと保存。

問題：
- **CloudKit 1レコード ≒ 1MB 上限**。全履歴は入り切らない。
- 受信側で `@Query Friend` が**巨大JSONを全画面でメモリに載せる**→ iPhone13(RAM少)で全タブ重い。
- カレンダーが巨大配列を**42日×friendで毎回フィルタ**→ 数分ハング（2026-06に観測）。

→ **塊方式は「直近の小さな窓」専用**。期間を広げるほど肥大して破綻する。

**現在の応急処置（2026-06）**：共有を**過去365日／未来180日／最大2000件**にウィンドウ＋件数キャップ（`CloudFriendShareSnapshotBuilder`）。実用上ほぼ1年・最大2000件まで軽いまま。だが「本当に全履歴」は別物が要る。

---

## 2. 正しい作り（普通のカレンダー共有アプリと同じ）

**1予定/1実績＝1レコード（個別行）。日付でインデックス。見ている範囲だけ都度ロード。差分同期。**

これにより「全履歴を保持」しつつ「常にメモリには表示範囲だけ」＝軽い。自分の記録は既にこの作り（カレンダーがグリッド範囲だけ `modelContext.fetch`）。**友達データだけ塊方式という不整合**を解消する。

### 2.1 CloudKit 側（オーナーが共有）
- 共有ゾーン `LiminalogFriendShares`（既存）に、**ステータス用の軽量ルート**（現在地・スコア・streak＝友達一覧表示用）と、
- **`SharedChapter` / `SharedPlan` を1件1レコード**で置く。フィールド：`ownerUserRecordName`, `targetUserRecordName`(or 共有ゾーンで participant 制御), `startTime`(queryable/sortable index), `endTime`, `categoryTitle/icon/color`, `title`, `mood?`, `note?`(可視性次第), `updatedAt`, `sourceID`(元Chapter/PlanのUUID＝upsert/削除同期キー)。
- CKShare はゾーン（またはルート階層）に対して張り、参加者＝対象の友達のみ（既存の participant ロジック流用）。
- オーナー側の追加/編集/削除を、対応する Shared* レコードへ **upsert/delete 同期**（`sourceID` で突合）。可視性プリセットでフィルタ。

### 2.2 受信側（差分同期＆ローカル保存）
- `CKFetchRecordZoneChangesOperation` ＋**ゾーン変更トークン**で、共有ゾーンの**変わった分だけ**取得（毎回全件を取らない）。`CKDatabaseSubscription`/`CKRecordZoneSubscription` のプッシュで起動。
- 受信した Shared* を**ローカルの個別行**として保存：新規 `@Model FriendSharedChapter` / `FriendSharedPlan`（`friendID`＋`startTime` をインデックス）。
  - ⚠️ **SwiftDataコンテナがCloudKit同期している場合、この派生データを自分のCloudKitへ二重同期させない**こと（`@Attribute(.ephemeral)` 不可なので、別コンテナ/ストア or 同期対象外の設計が要る）。← ここが Codex 判断の肝。
- 削除・更新もトークン差分で反映（tombstone）。

### 2.3 表示側（範囲ロード）
- カレンダー友達オーバーレイ：`friend.sharedPlans`(塊デコード)をやめ、**`@Query`(or fetch) で `friendID==X && startTime in グリッド範囲`** を引く（自分の記録と同じ作り）。
- 友達デイビュー：同様に当日範囲だけ。
- `Friend.sharedPlansJSON/sharedActivitiesJSON` と `FriendShareSnapshotCache` は撤去（or ステータス専用に縮小）。

---

## 3. 移行
- 既存の友達の塊JSONは破棄し、初回は対象友達の共有ゾーンを**全件取得→個別行へ展開**（以降は差分）。
- スキーマ追加（`FriendSharedChapter/Plan`）。CloudKit同期対象から外す方式を確定。

## 4. 受け入れ基準
- 友達の**任意の過去月**を開いても、その月の友達予定/実績が出る（全履歴保持）。
- カレンダー/デイの操作が、自分の記録と同等に**軽い**（メモリに全履歴を載せない）。
- 同期は**差分**（毎回全件取得しない）。CloudKit 1レコード上限に依存しない。
- iPhone13 でも全タブ軽快。

## 5. 段階・リスク
- **多日作業＋二台実機の反復検証が必須**（共有・差分・削除・可視性）。締切直前に盲目実装しない。
- **CloudKit/SwiftData コンテナの不変条件**（同期対象・ゾーン・participant）を握る Codex が主担当。
- v1は友達を後出し（[17-monetization.md](17-monetization.md) のソロ先行）にする方針と整合＝本改修は**友達を正式リリースする更新**で入れるのが安全。

---

## 6. それまでの暫定（実装済・2026-06 Claude）
- `CloudFriendShareSnapshotBuilder`：過去365/未来180日・最大2000件ウィンドウ＋キャップ。
- `Models/Friend.swift`：`FriendShareSnapshotCache`（塊デコードのメモ化）。
- `Stores/CalendarDayScoreCache.swift`：日スコアの署名キャッシュ（変化なければ再計算しない）。
- これらは塊方式の延命。**本設計（個別レコード化）が入ったら撤去/置換**。

---

## 7. 実装状況（2026-06-10 Claude・段階1完了）

### 7.1 決着した設計判断
- **§2.2の「Codex判断の肝」（派生データを自分のCloudKitへ二重同期させない方法）は解決済み**:
  既存の `LocalCache` ModelConfiguration（`cloudKitDatabase: .none`、`CalendarEventCache` と同居）に置く。
  別コンテナ不要。消えても再同期で復元できる純粋な派生キャッシュ。

### 7.2 実装済み（受信側の個別行キャッシュ土台）
| 部品 | 役割 |
|---|---|
| `Models/FriendSharedRecord.swift` | `FriendSharedPlanRecord` / `FriendSharedChapterRecord`（@Model・`#Index(friendID, startTime)`・snapshot相互変換） |
| `Stores/FriendSharedRecordReconcilePolicy.swift` | sourceID突合の純ロジック（insert/update/delete、updatedAt比較、重複除去）。CloudKit差分同期になってもそのまま使える |
| `Stores/FriendSharedRecordStore.swift` | reconcile（全量正の一致化）・範囲クエリ（overlapping）・deleteAll・purge |
| `CloudFriendShareSnapshotApplier` | ステータス専用 root snapshot を `Friend` へ反映。`clearCachedShare` でステータスと個別行キャッシュを削除 |
| `CloudFriendShareRefreshCoordinator` | リフレッシュ末尾で孤児行をpurge |
| スキーマ | `localCacheSchema` / `schema` / `LiminalogSchemaV1` / `TestModelContainer` に追加（軽量マイグレーションで追加されるだけ） |
| テスト | `FriendSharedRecordStoreTests`（policy / store / clearCachedShare / 大容量範囲クエリ） |

### 7.3 残り（着手順）
1. [Claude] UIの範囲クエリ移行 → **完了（2026-06-10・段階2）**。置換済み:
   - メインカレンダーの友達オーバーレイ（CalendarView）: グリッド範囲の行クエリ＋初回 backfill
   - `FriendCalendarView`: 月グリッド範囲の行クエリ＋`.task` で backfill
   - 友達デイビュー（`FriendSharedCalendarDayView`）: 当日範囲の行クエリ
   - 共有予定検索シート: `searchPlans(titleContains:)` / `hasAnyPlans` の行クエリ
   - 後方互換: `backfillFromBlobIfNeeded`（行が空＆塊にデータあり→一度だけ補填）。デバッグシードも行を併記
   - 注: `FriendShareSnapshotCache`（塊デコードのメモ化）は §7.3-4 の塊撤去時に一緒に消す
2. [Codex→Claude] CloudKit輸送層の個別レコード化（§2.1）→ **実装完了（2026-06-11・段階3）**
3. [Codex→Claude] 受信の差分同期（§2.2）→ **実装完了（2026-06-11・段階3）**
4. [両者] 塊JSON撤去 → **完了（2026-06-11・段階3）**
5. **二台実機での反復検証（共有・差分・削除・可視性）— 自動E2Eは完了**。2026-06-12 に `CloudKitLiveDeviceSmokeTests` の二台E2E run `codex-20260612D/E/F/G` で初回共有、baseline token 後の更新/追加/削除、公開範囲OFF相当のroot赤字化＋子レコードtombstone、full fetch reconcile、cleanup まで確認済み。run G は iPhone 13=recipient / iPhone 16=owner で再実行し、初回 accept/fetch 89.51秒、差分取得 1.72秒、redaction/tombstone差分 2.26秒、保存済みtoken破棄→1回full fetch→replacement token保存→reconcile 87.62秒で成功。通常差分は1〜2秒台まで軽量化済みだが、初回共有とtoken喪失後の復旧full fetchは90秒級。大容量modifyはiPhone 13実機で360件 publish 5.20秒 / delete 12.45秒。Gate23 で `CKError.changeTokenExpired` 注入時に保存済みtokenからnil full fetchへ落ちるapp側fallbackも固定済み。可視性の手動UI確認、意図的 `changeTokenExpired` の実CloudKit再現はリリース前の最終確認として継続する。

---

## 8. 段階3 実装メモ（2026-06-11 Claude・Codexトークン切れのため代行）

### 8.1 構成
- **レコード**: 共有ゾーン `LiminalogFriendShares` 内
  - ルート `friend-share:{owner}:{target}`（型 `FriendShareSnapshot`）= ステータス専用（現在地/スコア/streak）。CKShare はここに張る（既存のまま）
  - アイテム `shared-plan:{target}:{sourceID}` / `shared-chapter:{target}:{sourceID}`（型 `SharedPlan`/`SharedChapter`）。**`parent` = ルート参照**で CKShare の階層共有に乗せる（共有相手にだけ見える）
- **送信（差分）**: `FriendSharePublishedItem`（LocalCache台帳: sourceID→内容のSHA256指紋）と可視セットを `FriendSharePublishDiffPolicy` で突合 → upsert/delete だけを `modifySharedItems`（300件チャンク・非アトミック・成功分のみ台帳反映）。ルート作り直し時は台帳クリア→全量再公開（孤児レコードは parent 再設定で再接続）
- **受信（差分）**: `CKFetchRecordZoneChangesOperation`＋ゾーン変更トークン（`FriendShareZoneSyncState` に永続化）。トークン失効→全件取得にフォールバックし**全量突合**（reconcile）で消えた行も回収。初回（共有未承認/zoneNotFound）は共有URL承認→全件取得
- **塊JSON撤去済み**: ルートの `sharedPlansJSON` フィールド、`Friend.sharedPlansJSON/sharedActivitiesJSON`、`FriendShareSnapshotCache`、backfill、シードの塊書き込み。スナップショット構造体はステータス専用化

### 8.2 主な新規ファイル
`FriendSharedItemRecordPolicy` / `FriendSharePublishDiffPolicy` / `FriendSharePublishStateStore` / `FriendShareSyncState`（@Model×2） / `CloudFriendShareItemTransport`（store拡張）

### 8.3 実機検証の状況（2026-06-11〜12 実機2台で実施）
| 項目 | 状態 |
|---|---|
| 1. `parent` 参照付き子レコードの保存・削除（階層構造） | ✅ ライブスモークテスト `testSharedItemRecordsRoundTripOnRealCloudKit` がiPhone 13実機+実CloudKitでパス。二台E2Eでも recipient が共有ゾーンから SharedPlan/SharedChapter を取得できることを確認。2026-06-12 Gate22 で最新差分後も iPhone 16 実機 3.98秒 / iPhone 13 実機 3.72秒で再成功 |
| 4. 新レコード型のスキーマ自動作成 | ✅ 同テストで確認（development環境） |
| 2. ゾーン差分 | ✅ 二台E2E run `codex-20260612B/C/D/E/F/G` で baseline token 後の更新・追加・削除を差分取得し、recipient の行キャッシュへ反映確認。run D では差分取得 2.52秒、公開範囲OFF相当の赤字化/tombstone差分 2.10秒。run E では差分取得 2.28秒、redaction/tombstone差分 1.31秒。run G では差分取得 1.72秒、redaction/tombstone差分 2.26秒 |
| 3. 初回接続 | ✅ 二台E2E run `codex-20260612A/B/C/D/E/F/G` で recipient announce → owner share publish → recipient accept/fetch が成功。run D の初回 accept/fetch は 90.54秒、run E は 91.52秒、run G は 89.51秒 |
| 5. 大量初回公開 | ✅ 送信側は sourceID 指定時でもルート新規作成時に fullSharedItems へフォールバックする実装へ変更。Release build / full sim test / 実機2台E2Eで通常初回公開は確認済み。2026-06-12 に iPhone 13 実機 `testBulkSharedItemModifyPerformanceOnRealCloudKit` で 240 plans + 120 chapters（360 child records）の publish 5.20秒 / delete 12.45秒 / テスト全体19.38秒で成功 |
| トークン失効 | 🟡 `changeTokenExpired` は全件取得 + `reconcile` へフォールバックする実装済み。`FriendSharedRecordStoreTests.fullZoneReconcileAfterExpiredTokenDeletesMissingRows` で full fetch 後に欠落した行が tombstone なしでも削除され、フルリロード通知になることを確認済み。`FriendSharedRecordChangeImpactTests.fullReloadNotificationInvalidatesAllCalendarPagesForOnlyThatFriend` で対象友達だけ全カレンダーページ再読込へ落ちることも固定済み。2026-06-12 の二台E2E run `codex-20260612D/E/F/G` では、owner が削除済みの shared item を recipient が shared zone full fetch（tokenなし）+ reconcile でローカルから回収することを実CloudKitで確認。run G では保存済み token を明示的に破棄し、1回のfull fetchで replacement token を保存し直すアプリ側復旧パスも実CloudKitで確認（87.62秒）。さらに production の `CloudFriendShareRefreshCoordinator` が呼ぶ適用処理を `FriendShareZoneChangeApplier` に切り出し、fullZone fetch が欠落行を削除し root snapshot も反映すること、root 差分だけならfull reloadではなく今日/昨日範囲通知になることをテスト化。iPhone 16 / iPhone 13 実機で `FriendShareZoneChangeApplierTests` 2件が成功。Gate23 では `FriendShareZoneChangeFetchRecoveryPolicy` を追加し、保存済みtokenで `changeTokenExpired` 相当のエラーを受けた時にnil tokenで1回だけfull fetchへ落ち、非token系CKErrorではretryしないことを `FriendShareZoneChangeFetchRecoveryPolicyTests` 3件で固定。Simulator / iPhone 16 / iPhone 13 実機で成功。意図的 `changeTokenExpired` の実CloudKit再現は未実施 |
| 可視性 | ✅ 二台E2E run `codex-20260612C/D/E/F/G` で公開範囲OFF相当の root 赤字化（status/mood/score/streak を空/0）と shared item tombstone を recipient が差分取得し、行キャッシュから削除されることを確認。2026-06-12 に `devicectl` で iPhone 13 / iPhone 16 の両方へアプリを前面起動し、起動後プロセス生存も確認。友達カレンダーの目視操作確認は継続 |

### 8.4 ローカル表示キャッシュ検証（2026-06-12）
- `FriendSharedRecordStoreTests.rangeQueriesStayScopedWithLargeHistory` を追加。対象友達の予定1,200件＋実績1,200件＋別友達の予定1,200件（計3,600行）をLocalCacheへ投入し、カレンダーグリッド相当の42日範囲だけを取得する。
- 結果: 42 plans + 42 chapters を 0.016秒で取得、`FriendSharedRecordStoreTests` 全9件は 1.014秒で成功。2026-06-12 に `FriendCalendarPageDataBuilder` を切り出し、同じ3,600行級LocalCacheから友達カレンダー月ページを生成する回帰テストも追加。iPhone 13実機では月ページ生成 0.0101秒、iPhone 16実機では 0.0058秒で成功。別友達・範囲外履歴を混ぜず、表示側が全履歴をメモリへ載せない前提を回帰テスト化済み。
- 共有停止・ブロック・共有URL失効などで `clearCachedShare` した場合も、`CloudFriendShareRefreshCoordinator.sharedRecordsDidChange` を full reload として投げる。これにより、友達がまだフィルタ選択中でも月カレンダーのキャッシュが古い行を表示し続けない。Friends画面の手動クリア経路も同じ通知ヘルパーを使うように揃えた。`FriendSharedRecordChangeImpactTests.notificationEndingAtMidnightDoesNotInvalidateNextDay` と `postSharedRecordsDidChangeHelperPostsFullReloadForFriend` を追加し、月初0:00終端の境界で翌日を誤って汚さないこと、UI経路用ヘルパーが対象友達だけのfull reload通知になることを固定。さらに `FriendCalendarCacheInvalidationPolicy` を切り出し、full reload / 見えている月だけ即再取得 / 遠い月はキャッシュ削除だけ、という画面キャッシュ無効化判断をテスト可能にした。`CalendarView` の友達overlay更新も同じpolicyへ統一し、アンカー月から離れた月を表示中でも現在オフセット基準で再補充する回帰テストを追加。2026-06-12 に iPhone 13 実機で `FriendSharedRecordChangeImpactTests` 10件、`FriendSharedRecordStoreTests` 10件が成功し、大容量範囲クエリは3,600行から42 plans + 42 chaptersを0.0027秒、友達カレンダー月ページ生成は3,600行から35 important plansを0.0101秒で完了。iPhone 16 実機でも同20件が成功し、大容量範囲クエリは0.0018秒、月ページ生成は0.0058秒。Release build Gate16 も成功済み。
- 受信した zone changes の適用は `FriendShareZoneChangeApplier` へ切り出し、`CloudFriendShareRefreshCoordinator` から同じ経路を呼ぶ。fullZone fetch は差分適用ではなく reconcile で欠落行を削除し、root record も同時に Friend へ反映する。incremental root change はfull reloadにせず、今日/昨日の表示範囲だけを通知する。2026-06-12 に iPhone 16 / iPhone 13 実機で `FriendShareZoneChangeApplierTests` 2件が成功。
- 既存カレンダー共有アプリとの照合: iCloud Calendar は private/public 共有、read-only/edit 権限、共有更新通知を持つ（Apple Support: https://support.apple.com/guide/icloud/share-a-calendar-mm6b1a9479/icloud）。Google Calendar も free/busy・詳細表示・編集・共有管理の段階権限と共有停止を持つ（Google Calendar Help: https://support.google.com/calendar/answer/37082）。Liminalog では編集権限は持たせず「閲覧+公開範囲制御」に寄せる代わりに、非公開化・共有停止・削除が受信側のローカル行と画面キャッシュから確実に消えることをリリース条件にする。
- 新ビルド初回起動時に、ストア準備/マイグレーション中の最初の数フェッチが "couldn't be opened" で失敗する可能性への対策として、アプリ本体の初回 `bootstrap` だけ `bootstrapWithStoreReadinessRetry` を使う。通常の同期 `bootstrap` は維持し、UserSettings fetch が失敗した場合のみ 150ms / 350ms / 750ms の短い再試行を行う。2026-06-12 に simulator `BootstrapStoreTests` 3件、iPhone 16 実機で `BootstrapStoreTests` + `FriendSharedRecordChangeImpactTests` 12件、Release build が成功。
- CloudKitの現在ユーザーID取得は `CloudKitCurrentUserRecordResolver` へ集約し、`CloudKitSocialStore` と `CloudFriendShareStore` で共有する。これにより同一プロセス中の `accountStatus()` + `fetchUserRecordID()` 多重往復を避けつつ、`Notification.Name.CKAccountChanged` でキャッシュを破棄する。2026-06-12 に iPhone 16 実機で `CloudKitCurrentUserRecordResolverTests` 3件、実CloudKit smoke `testRealDeviceCanReachCloudKitFriendInfrastructure` 1件（3.297秒）が成功し、Release build Gate12 も警告なしで成功。
- 2026-06-12 Gate22 で、最新差分後の実CloudKit smoke を iPhone 16 / iPhone 13 の両方で再実行。`testRealDeviceCanReachCloudKitFriendInfrastructure` は iPhone 16 2.04秒 / iPhone 13 2.58秒、`testSharedItemRecordsRoundTripOnRealCloudKit` は iPhone 16 3.98秒 / iPhone 13 3.72秒で成功。Release build Gate22、Simulator full test 289件、`git diff --check` と合わせて、CloudKit到達・parent付き子レコード保存削除・広い回帰テストは最新差分で通過済み。
- 2026-06-12 Gate23 で、zone change fetch のtoken失効fallbackを `FriendShareZoneChangeFetchRecoveryPolicy` として切り出した。保存済みtokenで失効した場合はnil tokenのfull fetchへ落ち、成功時は `didFetchFullZone` を立てる。非token系 `CKError` はretryせず呼び出し元へ返す。`FriendShareZoneChangeFetchRecoveryPolicyTests` 3件を Simulator、iPhone 16実機、iPhone 13実機で成功確認。実CloudKitサーバーから自然発生する `changeTokenExpired` 自体の強制再現は未実施のまま。
- `FriendsView` の友達申請refreshは `CloudFriendLocalStatePolicy.shouldRefreshCloudRequests` へ判断を集約し、自動refreshは同一ユーザーでは一度だけ、失敗直後の再表示は120秒抑制、push通知/手動更新は即時にした。2026-06-12 に iPhone 16 実機で `CloudFriendLocalStatePolicyTests` 9件が成功し、Release build Gate13 も成功。
- アプリ起動/復帰時の送信側full publishは `CloudFriendLocalStatePolicy.shouldScheduleOutgoingLifecycleShareRefresh` で10分クールダウンし、通常の予定/実績保存から来る明示refreshは `cloudFriendShare.pendingOutgoingRefresh` マーカーで次回起動/復帰でも必ず拾う。これにより「画面復帰だけで全履歴fetch + CloudKit差分照合」が連発しない一方、直前にアプリが落ちた変更は失わない。2026-06-12 に iPhone 13実機で `CloudFriendLocalStatePolicyTests` 12件、実CloudKit smoke 1件（1.989秒）、Release build Gate16、`git diff --check` が成功。

### 8.5 2026-06-12 実機E2Eで追加検出・修正した問題
1. **recipient から owner 作成の public marker へ書けない**: E2E補助レコードの設計ミス。baseline token は recipient 自身が作った marker に保存するよう修正。
2. **差分削除後に SwiftData 行キャッシュへ即時反映されないケース**: `ModelContext.delete(model:where:)` 後、同じ context 内の既存インスタンスが直後の fetch に残るケースを実機E2Eで検出。削除対象を fetch して `modelContext.delete(record)` する方式へ変更し、チャプター削除の回帰テストを追加。

### 8.6 実機検証で見つかった重大バグ（修正済み）
1. **CloudKit同期コンテナが実機で一度もロードできていなかった**: `FriendCategoryMapping.friend` リレーションに inverse が無く、`NSPersistentCloudKitContainer` がロード拒否（"CloudKit integration requires that all relationships have an inverse"）→ 常にローカルフォールバックで動作していた。`Friend.categoryMappings` に inverse を追加して解消。**昨日入れた起動時フォールバック告知がこの問題を可視化した**
2. **CloudKit同期モデルのプロパティ削除は禁止**: 段階3で `Friend.sharedPlansJSON` 等を物理削除したが、CloudKit統合スキーマは追記専用。未使用のまま残置する形に修正（コメントで読み書き禁止を明示）
3. **migrationPlan（ステージ0）は開発中は配線しない**: V1のモデル構成が変わるたびにハッシュ不一致でロード拒否される。リリース時スキーマ固定の時点で配線し直す（`SharedModelContainer` にコメント）
4. CloudKit `zoneBusy` はサーバー指定の待ち時間でリトライ（`CloudKitTransientRetryPolicy`）
5. 新ビルド初回起動時、ストアのマイグレーション中に最初の数フェッチが "couldn't be opened" で失敗することがある問題は、アプリ本体の初回 `bootstrapWithStoreReadinessRetry` で短く再試行するように緩和済み。通常の同期 `bootstrap` はWidget/Intent等の既存経路向けに維持する。
