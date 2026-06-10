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

### 7.2 実装済み（受信側の土台＋二重書き）
| 部品 | 役割 |
|---|---|
| `Models/FriendSharedRecord.swift` | `FriendSharedPlanRecord` / `FriendSharedChapterRecord`（@Model・`#Index(friendID, startTime)`・snapshot相互変換） |
| `Stores/FriendSharedRecordReconcilePolicy.swift` | sourceID突合の純ロジック（insert/update/delete、updatedAt比較、重複除去）。CloudKit差分同期になってもそのまま使える |
| `Stores/FriendSharedRecordStore.swift` | reconcile（全量正の一致化）・範囲クエリ（overlapping）・deleteAll・purge |
| `CloudFriendShareSnapshotApplier` | 塊JSON反映と同時に個別行へも**二重書き**。`clearCachedShare` で行も削除 |
| `CloudFriendShareRefreshCoordinator` | リフレッシュ末尾で孤児行をpurge |
| スキーマ | `localCacheSchema` / `schema` / `LiminalogSchemaV1` / `TestModelContainer` に追加（軽量マイグレーションで追加されるだけ） |
| テスト | `FriendSharedRecordStoreTests`（policy 3件＋store 4件、applier二重書き含む） |

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
5. **二台実機での反復検証（共有・差分・削除・可視性）— 未実施・リリース前必須**。§5の通り友達正式リリースの更新に同梱が安全。`CloudKitLiveDeviceSmokeTests` と docs/18 のランブックを使うこと。

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

### 8.3 ⚠️ 未検証事項（実機2台が必要）
ロジックはユニットテスト（CKRecord往復・差分・台帳・行反映）で担保したが、以下は**CloudKit実環境での動作未確認**:
1. `parent` 参照による階層共有の継承（子レコードが参加者に見えるか）
2. ゾーン変更トークンの差分取得・失効フォールバック
3. 初回接続（URL承認→zoneNotFound→全件取得）の流れ
4. CloudKit Dashboard 上の新レコード型 `SharedPlan`/`SharedChapter` のスキーマ自動作成（development環境で初回保存時に生成される想定）
5. 大量アイテム（数千件）の初回公開のチャンク送信挙動
