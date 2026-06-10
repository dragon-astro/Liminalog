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
