# 29. 性能ホットスポット台帳（docs/28 v3 Item C/D への入力）

2026-07-20 のユーザー指示を明文化し、コード監査で特定した**証拠つきホットスポット候補**を [28-ux-interaction-performance-v3.md](28-ux-interaction-performance-v3.md)（以下 v3）の Item C/D へ供給する。**計測プロトコル・合格基準・不変条件・ブランチ運用は v3 §1〜§4 が正**であり、本書はそれを置き換えない。各候補は v3 の流儀どおり「計測で犯人確認 → 修正 → 同条件再計測」を経ること（台帳に載っていることは修正理由にならない）。

> ステータス：**Codex 着手可**（v3 Item B 完了後、C/D の計測対象に組み込む）。

---

## 1. ユーザー指示の明文化（2026-07-20・v3 と以後の全性能作業に適用）

1. **操作感の変更なしにカクツキ・重さを解消する。** アニメーションの削除・簡略化、連続的な操作の離散化（間引き・量子化・ワンテンポ遅れの導入）、機能・表示の削減は禁止（v3 §2 と同旨。以後も常設ルール）
2. **毎日頻繁に使うアプリなので妥協しない。** 「少し残ったが体感は良くなった」で完了にしない。v3 §4 の数値基準+60fps動画確認を満たすまで追う
3. **機能を維持したままではどうしても軽くできず、何かを変える必要がある場合は、勝手に変えずユーザーに相談する。** AI_TASKS §11 へ「何を・なぜ・どう変えれば・どれだけ軽くなるか」を起票し、判断を仰ぐ。トレードオフの実行はユーザー専権

---

## 2. ホットスポット台帳（証拠つき候補）

各項目: 証拠 → 修正の方向（見た目・挙動完全同一の範囲）→ 供給先。

### H1. 記録タップ経路の同期副作用【供給先: Item D「記録」】

- **証拠**: `ChapterStore` の保存経路にタップと同期で App Group への `RecordingSurfaceSnapshot` publish（JSON encode + 書き込み）、`WidgetCenter.shared.reloadAllTimelines()`（ChapterStore.swift:61。kind 限定でない全量）、Live Activity 更新が連なる。アプリの心臓であるカテゴリタップの初動フレームに乗る
- **方向**: 画面に映る状態反映だけをタップ直後フレームで行い、不可視副作用は次フレーム以降へ遅延・統合（順序・回数・最終結果は維持 = v3 Item B と同じ作法）。`reloadAllTimelines` の kind 限定は機能差ゼロを確認できる場合のみ
- **注意**: docs/21 §2.3 の保存パイプライン（save → requestRefresh → 失敗時 rollback）は迂回しない

### H2. TickClock による周期的な全ツリー再評価【供給先: Item C（timer監査）+ D】

- **証拠**: 各タブのルート View が `@State private var clock = TickClock(interval: 60)` を持ち（HomeView:73 / TimelineView:117,491 / CalendarView:34 / CalendarDayView:16 / DashboardView:9 / FriendsView:25。実装は `Logic/LiminalogClock.swift` の @Observable + Timer）、`clock.now` をルート階層の計算（HomeView.dayID:235、CalendarDayView:476 のフィルタ等）で読むため、**毎分、表示中タブのツリー全体が再評価候補になる**。`CurrentChapterCard` は1秒周期（CurrentChapterCard.swift:21）
- **方向**: ①`clock.now` を読む場所を末端の小さな View へ隔離（tick で再評価されるのは残り時間ラベル等の葉だけ）②経過/残り時間の表示だけが目的の箇所は `Text(timerInterval:)` / `SwiftUI.TimelineView(.periodic)` へ置換（表示は完全同一のまま View 再評価自体が消える）③日跨ぎ切替は毎分 now を配らず次の 0:00 に1回発火へ
- **注意**: v3 Item B が `EditablePlanTimelineView` 系の @State 隔離を進行中。TimelineView（Home側）の clock を触る場合は B の統合後にリベースし、同一ファイル同時作業をしない

### H3. スコアのライブ計算がホットパスに載っている【供給先: Item C/D「Friends・Statistics・Calendar mode」】

- **証拠**:
  - FriendsView:685-707 `selfScore(for:)` が body 計算経路で `ScoreSnapshotLoader.summary / averageScore` を直接実行。**年セグメントは365日分のフェッチ+ScoreCalculator をその場で回す**うえ、`clock.now` 依存で毎分再計算候補になる
  - 月カレンダーは `CalendarDayScoreCache`（署名キャッシュ）で緩和済みだが、署名計算のための全日分フェッチ+グルーピングは開くたび・オーバーレイ切替のたびに走る（同ファイル冒頭コメント）
- **方向**: ①自分スコアを body から追い出し、データ変更/日跨ぎ/表示時のみ再計算して保持（§10.6 の `ProfilePerformanceSnapshot` 方式が前例）②**確定日（一昨日以前）は docs/27 §5.3「DailyScoreSnapshot 読み」へ一本化**（下の調整事項参照）。表示値は完全同一が条件
- **注意**: **§8.15（docs/27）と共有タスク。二重実装禁止**。先に着手した側が実装し、他方は前提にする

### H4. カテゴリボード切替の残存 2.7 秒【供給先: Item D「category board」・既知の最重症】

- **証拠**: AI_TASKS §8.14 F 完了ログ（2026-07-18 iPhone 13 Release 実測）。副作用集約後も「確定ボード単発メニュー 2789ms / 横スワイプ hitch ratio 39.9ms/s / 同一ボード再表示 5.67s・hitch 10.8回」。**原因未特定のまま残る唯一の計測済み重症箇所**
- **方向**: os_signpost で区間分解（メニュー構築 / CategoryGrid 再構築 / snapshot 組み立て / フェッチ / レイアウト）→ 最大区間から見た目不変の技法で潰す。View 再構築幅が犯人なら identity 安定化・Equatable 化・ページ遅延構築を優先候補に（v3 §2 の「blanketな.id()禁止」に注意）
- **注意**: 推測修正禁止。分解結果と数値目標案を AI_TASKS §11 へ報告してから本修正

### H5. 常駐フェッチ監査の未消化分【供給先: Item C（常駐Query計測）】

- **証拠**: docs/21 R4（全期間 `@Query` 常駐・fetch→メモリフィルタの監査）が未消化のまま。過去に「友達タブを開くと全体が重くなる」実害あり（完了ログ 2026-06-11）
- **方向**: R4 の手順どおり範囲述語化 / オンデマンド化。`#Predicate` の UUID 配列 contains 禁止（docs/21 §2.1）に注意

### H6. 描画レイヤ・巨大 body【供給先: Item D・計測が示した場合のみ】

- **証拠**: ProfileComponents.swift に `.shadow` 24箇所。CalendarView 4,018行 / FriendsView 4,167行の body 評価コスト（docs/21 §1）
- **方向**: GPU バウンドが示された場合のみ、見た目が1ピクセルも変わらない合成（事前合成・選択的 `compositingGroup`）。変わるなら不採用 or §11 相談。body コストが示された画面は docs/21 R1 の分割を先行実施してよい（挙動不変の原則で両立）

---

## 3. 追加計測シナリオ（v3 §3 の対象操作への追加提案)

- **放置 tick 跨ぎ**: 各画面を開いたまま1〜2分放置し、毎分 tick 時の SwiftUI View 更新回数と hitch を記録（H2 の before/after 判定用）
- **友達タブの期間セグメント切替**: 今日/昨日/週/月/年を往復（H3。特に「年」の初回と2回目）
- **月カレンダーのオーバーレイ切替**を単独計測（H3 の署名パス）
- ボード切替は v3 対象操作に含まれるが、H4 の**区間分解ログ付き run** を1本残す

---

## 4. 他ワークストリームとの調整（着手前に確認）

| 相手 | 重なり | ルール |
|---|---|---|
| v3 Item B（進行中） | TimelineView / EditablePlanTimelineView の @State・副作用 | B 統合後にリベース。同一ファイル同時作業禁止 |
| §8.15 / docs/27 | 確定日スコアのスナップショット読み（docs/27 §5.3）・ScoreStore | 共有タスク。先行側が実装、二重実装禁止 |
| docs/21 R1/R4 | フェッチ監査・View分割 | docs/21 の手順・不変条件に従い、完了ログに両参照を書く |
| 友達共有の輸送層 | `CloudFriendShare*` 群 | docs/21 §2.5 の保護領域。計測で犯人と出ても勝手に触らず §11 起票 |

---

## 5. Codex 向けサマリ

```text
[Codex goal — docs/29 ホットスポット台帳の消化（v3 Item C/D の一部として）]
前提: docs/28 v3 の運用・不変条件・比較プロトコル・合格基準に完全準拠。
ユーザー常設ルール: 操作感を変える軽量化は禁止。それなしで不可能なら AI_TASKS §11 に
起票してユーザー相談（勝手に変えない)。
手順: Item C/D の計測対象に docs/29 §2 の H1〜H6 と §3 の追加シナリオを含める →
計測で犯人確認できたものだけ、各項目の「方向」に沿って見た目・挙動完全同一で修正 →
同条件 before/after。H3 は §8.15 と、H2 は Item B と、§4 の調整ルールで衝突回避。
H4 は区間分解の報告を §11 へ出してから本修正。
```
