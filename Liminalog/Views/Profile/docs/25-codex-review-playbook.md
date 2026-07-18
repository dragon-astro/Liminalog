# 25. Codex実装のレビュー手順書（別セッション引き継ぎ用）

CodexがAI_TASKSのタスクを実装した後、Claude（新セッションでも可）が単独でレビューを実行するための手順書。
2026-07-18のUXバッチ（§8.13 A〜G）レビューで確立したプロセスの一般化。

## 0. 現在地（2026-07-18時点・次セッションはここから）

- **§8.13 UXバッチ A〜G：実装済み・レビュー済み・修正適用済み**（ブランチ `codex/ux-improvements-v1`）。
  - レビュー指摘6件 → 3件修正コミット済み（`fdc9be2` キャンセル握り分け / `1e91bcd` ポーリング10秒上限 / `e58779a` updatedAt変更行限定）、1件誤報撤回、2件保留。
- **未決（ユーザー確認待ち）**：ピンチズームはカレンダーのデイ画面（`EditablePlanTimelineView`）のみ。ホームの `TimelineView` も対象だったか？
- **未実施**：テストの完走確認（このMacのシミュレータは runner hang 持ち。Xcodeで ⌘U 推奨）。任意clean-up＝`SortOrderNormalizer.reorder` の `move(fromOffsets:toOffset:)` 置換。
- **保留バックログ**：docs/24 追補の S1/S2/S3/C4/F1/F2/P1（ユーザー選定待ち）。
- 課金まわりの現在地は `AppStore/PurchaseReadinessAudit.md`（ASC Missing Metadata解消がGate 1のブロッカー、審査スクショは新UIで撮り直し）。

## 1. レビューのスコープ確定

```sh
git log --oneline -20                 # Codexのコミット列を確認（item単位のfeat+merge）
git diff --stat <base>..HEAD          # 規模把握。<base>=バッチ開始直前のコミット
git diff --name-only <base>..HEAD | sort
```

## 2. 制約チェック（機械的・最初にやる）

```sh
# 課金ファイル不可侵（UXバッチの絶対条件）
git diff --name-only <base>..HEAD | grep -E "Monetization|Purchase|storekit|AppStore/" && echo NG || echo OK
```

- **設計意図の保護**：docs/24 の見送り/意図記録（特にH2＝実行中カードの予定/実績同居）が改変されていないか、該当ファイルのdiffで確認。
- **テーマトークン**：diff内に hex直書き・`Color(red:...)` が増えていないか（`git diff <base>..HEAD | grep -E '^\+.*#[0-9A-Fa-f]{6}|Color\(red'`）。
- goalプロンプト（docs/24）の受け入れ基準と突き合わせ。

## 3. 観点別レビュー（インライン実行）

**セッション使用上限が逼迫している時はサブエージェント艦隊を使わない**（2026-07-18に9並列で上限を焼いた実績あり）。本体セッションでdiffを直接読む。優先順：

1. **CloudKit/データ整合系ファイルから**（実害が大きい順）：Stores/ → Logic/ → Views/。
2. 各hunkで問う：削除された行が守っていた不変条件はどこで再確立されたか／呼び出し元は全部追ったか／SwiftUIの定番（ForEach identity・onMoveのインデックス基準・@Queryとstoreフェッチのソートキー一致・Task キャンセル・@MainActor）。
3. **「計画時に見たコード」と「現行コード」を混同しない**：指摘を書く前に必ず現行ファイルをgrepで再確認（今回の誤報#1の教訓。Codexが実装中に先回りで直していることがある）。
4. ポリシー/コーディネータ型はactor隔離（`@MainActor`）とcontinuationのリーク（resume漏れ＝スピナー永久回転）を確認。

## 4. 検証コマンド

```sh
# ビルド（シミュレータはUDID直指定。名前指定は4台あって不安定）
xcodebuild -project Liminalog.xcodeproj -scheme Liminalog -configuration Debug \
  -destination "platform=iOS Simulator,id=DF2D682A-96E5-4084-8929-0DCFF6EDF658" \
  -derivedDataPath /private/tmp/LiminalogReviewDerivedData build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

- テスト実行は本機シミュレータが「Testing started」のまま黙ることがある（既知）。落ちたら `xcrun simctl shutdown all` → UDID直指定で再試行。それでもダメならユーザーのXcode ⌘U に委ねる（レビュー記録にその旨明記）。
- UI変更は実画面確認：`xcrun simctl install <UDID> <app>` → `simctl launch <UDID> app.YasudaRyuga.Liminalog -LiminalogSeedDevData 1 -LiminalogInitialRootTab <tab>` → `simctl io <UDID> screenshot`。

## 5. 修正の適用ルール（コンテキスト/上限対策）

- **1修正＝1コミット**。途中でセッションが切れても消えないように、直したらすぐコミット（メッセージは `fix: ...`＋Co-Authored-By: Claude Fable 5）。
- 修正は小さい順（文言・ガード追加→ロジック）。テストを回せない環境では、既存テストが挙動を固定している箇所の書き換え（例：SortOrderNormalizerの実装置換）は保留にする。
- 判断がユーザーに属するもの（仕様の解釈違い等）は直さずに「確認待ち」として記録。

## 6. 記録

- レビュー結果は `AI_TASKS.md` の完了ログへ1エントリ（指摘→対応→コミットハッシュ→未決）。§8.13の該当タスクにチェック。
- 誤報を出したら撤回も明記する（黙って消さない）。

## 7. 新セッションの開始プロンプト（コピペ用）

```
Liminalogのレビュー/継続作業。まず Liminalog/Views/Profile/docs/25-codex-review-playbook.md の §0（現在地）を読んで状況を把握して。
今回のタスク: <ここに指示>
```
