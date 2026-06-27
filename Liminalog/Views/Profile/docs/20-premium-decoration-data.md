# 20. プレミアム装飾データ設計

プレミアム装飾（単品購入・Pro/装飾パス中のレンタル）を既存の獲得装飾と混ぜずに扱うための設計メモ。`PremiumDecorationCatalog` と装着解決ポリシーは追加済みだが、まだ UI 接続や保存モデル追加はしない。

## ゴール

- 獲得装飾と課金装飾を別カタログにする。
- `UnlockItem.unlockedAt` は「継続や条件達成で獲得した事実」だけを表す。
- 課金の所有/レンタル状態を `UnlockItem` に書き込まない。
- 装着状態は既存の `UserSettings` の targetID 保存を使い、プロフィール表示の互換性を守る。
- サブスク失効時にレンタル装飾だけを静かに外せるようにする。

## 現状コードの前提

- `UnlockItem`
  - built-in / 獲得装飾のカタログ兼状態。
  - `unlockedAt != nil` なら獲得済み。
  - CloudKit 同期対象。
- `ProfileDecorationUnlocks`
  - `UnlockItem.unlockedAt` から装着可能な targetID を作る。
  - `UserSettings` に保存された targetID が未解放なら default へ戻す。
- `UserSettings`
  - `themeName`、`profileIconFrameID`、`profileCardStyleID`、`profileBadgeID`、`equippedUnlockItemKeys` で装着状態を持つ。
- `PremiumDecorationAccessPolicy`
  - `PremiumDecorationProduct(productID, kind, targetID, displayName)` と `PurchaseEntitlements` から `unavailable / rented / owned` を返す。
  - `liminalog.decoration.` prefix 以外は課金装飾として扱わない。
  - 単品所有は Pro/装飾パスのレンタルより優先する。
- `PremiumDecorationCatalog`
  - 現時点では既存の非表示 `legacyItems` から、アイコンフレーム4件・カードスタイル4件を単品候補として列挙する。
  - 既存の無料獲得カタログ `UnlockCatalog` とは targetID を衝突させない。
  - UI にはまだ合流していないため、既存の装飾画面・プロフィール表示は変えない。
  - `Scripts/validate-storekit-config.swift --validate-premium-decoration-ui-disconnected` で、プロフィール装飾UIへ誤って接続されていないことを検査する。
- `DecorationAccessDisplayState` / `DecorationAccessDisplayPolicy`
  - 獲得済み / 未獲得 / 課金未所持 / レンタル中 / 単品所有を、UI接続前の表示状態として統合する純粋ロジック。
  - まだ `UnlockGalleryView` には接続していない。
- `PremiumDecorationEquippingPolicy`
  - 保存済み targetID を、獲得済み / 単品所有 / レンタル中 / 権利なしの順に表示時解決するための純粋ロジック。
  - 現時点では UI 未接続。課金権利がない場合に default/none へ戻す挙動だけをテストで固定している。

## データ境界

### 獲得カタログ

既存の `UnlockCatalog` / `UnlockItem`。

用途：

- スコア、継続、条件達成で解放する装飾。
- 新着バッジ。
- 獲得条件・進捗表示。

禁止：

- 単品購入したから `unlockedAt` を入れる。
- Pro中だから `UnlockItem` を獲得済みにする。
- 課金装飾を獲得装飾一覧へ無条件に混ぜる。

### 課金カタログ

`PremiumDecorationCatalog`。

最小フィールド：

```swift
struct PremiumDecorationCatalogItem: Identifiable, Codable, Equatable {
    var productID: String
    var kind: UnlockKind
    var targetID: String
    var displayName: String
    var assetName: String?
    var sortOrder: Int
}
```

対応関係：

- `productID`: StoreKit の Non-Consumable ID。例: `liminalog.decoration.frame.aurora_wreath`
- `kind`: `iconFrame` / `cardStyle` / `theme` を中心に開始する。
- `targetID`: 既存の表示カタログが使う ID。装着保存もこの ID を使う。
- `assetName`: 必要な場合だけ。既存カタログの asset name で足りるなら持たない。

### 課金権利

`PurchaseEntitlements`。

用途：

- `ownedNonConsumableProductIDs`: ライフタイムや単品装飾の永久所有。
- `activeProductIDs`: Proサブ / 装飾パスのレンタル権。
- `ownedPremiumDecorationProductIDs`: `liminalog.decoration.` prefix の所有だけを抽出する読み取りプロパティ。

保存方針：

- 初期は StoreKit2 の `Transaction.currentEntitlements` を正とする。
- 端末内キャッシュは表示高速化だけ。課金状態の真実はStoreKit。
- 独自サーバーは使わない。

## 表示モデル

プロフィール装飾画面では、表示前に2系統を合流する。

1. 獲得装飾：`UnlockItem.unlockedAt` で装着可否を決める。
2. 課金装飾：`PremiumDecorationAccessPolicy` で `unavailable / rented / owned` を決める。

表示状態：

| 状態 | 装着 | 表示 |
|---|---|---|
| 獲得済み | 可 | 獲得済み |
| 未獲得 | 不可 | 条件/進捗 |
| 課金未所持 | 不可 | 価格またはPro案内 |
| Pro/装飾パス中 | 可 | 契約中のみ |
| 単品所有 | 可 | 所有 |

注意：

- `rented` は「契約中のみ」と明記する。
- `owned` はサブスク失効後も装着可。
- ライフタイムは機能の買い切りであり、課金装飾レンタル権は付けない。
- UI接続前は、`UnlockGalleryView` / `ProfileDecorations` 側に `PremiumDecorationCatalog` 系を参照させない。接続する時はこの検査を外すのではなく、表示/装着/失効時フォールバックのQAゲートに置き換える。

## 装着保存

装着時は既存の `UserSettings` に targetID を保存する。

理由：

- プロフィール表示コンポーネントを大きく変えずに済む。
- 友達共有時も既存の profile targetID を流用できる。
- 課金権利が失効しても、targetID自体は残せるので、再加入/単品購入時に戻しやすい。

ただし、表示時には必ず現在のアクセス権で再解決する。

- 獲得済みならそのまま。
- 単品所有ならそのまま。
- レンタル中ならそのまま。
- どれでもなければ default/none にフォールバック。

## 失効時の扱い

サブスク失効時にやること：

1. 現在装着中の targetID が課金装飾か確認する。
2. 単品所有していれば維持する。
3. Pro/装飾パスのレンタルだけで装着していた場合は default/none に見た目を戻す。
4. `UserSettings` の元 targetID はすぐ消さず、将来の「再開すれば戻ります」導線に使えるようにするか検討する。

初期実装では、安全優先で表示時フォールバックだけでもよい。永続的なリセットは別タスクにする。

## 実装順

1. [x] `PremiumDecorationCatalog` を静的カタログとして追加する。
2. [x] 既存カタログIDと衝突しない productID / targetID 命名を決める。
3. [x] 表示用の `DecorationAccessDisplayState` を作り、獲得/課金/未所持を統合する。
4. `UnlockGalleryView` の対象タブに課金装飾を合流する。
5. 装着時に `PremiumDecorationAccessPolicy` を通す。
6. [x] 失効時フォールバックのテストを追加する。
7. StoreKitローカル購入テストで単品所有とレンタルの両方を確認する。
8. UI接続前は `Scripts/validate-purchase-readiness.sh` で未接続状態を維持する。

## テスト観点

- 獲得装飾は購入状態に関係なく装着できる。
- 未獲得の獲得装飾は、Proでも勝手に解放されない。
- 課金装飾は Pro/装飾パス中に `rented` になる。
- 単品所有は `owned` になり、サブスク失効後も装着できる。
- ライフタイムのみでは課金装飾は `unavailable` のまま。
- StoreKit商品IDが `liminalog.decoration.` prefix でなければ課金装飾として扱わない。
- 課金権利がない状態で課金装飾 targetID が `UserSettings` に残っていても、表示は default/none へ戻る。

## やらないこと

- 課金購入を `UnlockItem.unlockedAt` に変換する。
- 獲得装飾をStoreKit商品として売る。
- ライフタイムにプレミアム装飾レンタルを含める。
- 友達に見える装飾IDを、権利確認なしにそのまま信用する。
- 失効時にユーザーの保存状態を即座に破壊する。
