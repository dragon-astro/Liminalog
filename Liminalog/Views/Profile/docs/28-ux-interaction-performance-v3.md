# 28. UXフィードバック v3 — 選択状態と操作性能

`26-ux-feedback-v2.md` 完了後のユーザーフィードバックを正準化する。目的は機能や常駐UIを増やすことではなく、**カテゴリの選択状態を瞬時に判別でき、日常操作が見た目にも計測上にも滑らかで、既存の連続操作・状態・同期を一切弱体化しない**状態へ仕上げること。

## 1. 運用

- 開始地点: `codex/ux-feedback-v2`
- 統合ブランチ: `codex/ux-interaction-performance-v3`
- 実行順: A → B → C → D
- Item専用ブランチ: `codex/ux3-category-selection` / `codex/ux3-timeline-performance` / `codex/ux3-tab-performance` / `codex/ux3-interaction-performance-sweep`
- Itemごとに調査、改善前計測、設計、実装、回帰、改善後計測、専用コミット、no-ff統合を行う。
- 未検証・失敗中・原因未特定の変更は統合しない。
- `codex/ux-feedback-v2`、`codex/monetization-foundation`、`main`へはユーザー承認なしにマージしない。

## 2. 不変条件

- debounce / throttle / event dropで軽く見せない。
- scroll、move、resize、zoomの連続追従とアニメーションを弱体化しない。
- タブのView破棄、状態・navigation・scroll位置の喪失で軽量化しない。
- 表示内容の削減、古いsnapshotの長時間表示、CloudKit/SwiftData更新の省略をしない。
- 根拠のない`Task.detached`、blanketな`.id()`、巨大View全体の固定化をしない。
- 15/5/1分、4段階zoom、日付境界、カテゴリ作成→即選択、予定/実績同居を維持する。
- 課金、CloudKit、SwiftData schema、公開範囲、既読化のポリシーを変更しない。
- LiminalThemeのセマンティックトークンだけを使い、hexを直書きしない。

## 3. 比較プロトコル

改善前後は同じ端末・データ・Release build条件・操作スクリプトで比較する。基準端末はiPhone 13 / 60Hz。計測用データはユーザー実データを破壊せず、隔離fixtureまたは一時的な検証データを使う。

対象操作:

- 5タブを初回表示後に20往復し、初回・warm・反復後を比較
- 日間timelineのscroll、カテゴリ選択、予定move、開始/終了resize、0.75/1/1.5/2倍zoom
- category board、月/週/日、sheet/context menu、記録開始/停止/公開設定

最低記録:

- tapから最初の視覚反応までのp50/p95
- 平均FPS、p95 frame time、animation hitch、100ms以上のmain-thread stall
- CPU、SwiftUI View更新、SwiftData fetch/save、Widget/Live Activity/App Group/CloudKit発行回数
- 20往復前後のmemoryと遅延
- 60fps動画と画面状態

使用可能な証拠はTime Profiler、SwiftUI Instrument、Core Animation、Points of Interest、XCTest performance、Release実機動画。`/private/tmp/ux-interaction-performance-v3/`へ保存し、個人データをコミットしない。

## 4. 性能合格基準

- 固定操作に100ms以上のmain-thread stallがない。
- tapから最初の視覚反応がp95 100ms以内。
- iPhone 13の連続操作は平均58fps以上、p95 frame timeは原則20ms以内。
- animation hitchが改善前より増えない。
- 20往復後に遅延・memory・副作用発行回数が悪化しない。
- 数値上合格しても60fps動画で視認できるカクツキがあれば不合格。
- OSノイズを理由に失敗を無視せず、複数runの中央値/p95と生データを残す。

## 5. Item A — カテゴリ選択状態

- v2の軽い半透明表現を維持し、選択状態を色以外も含む2つ以上の手掛かりで示す。
- 候補は背景tint、枠、check/icon、weight、微細な立体感。2〜3案を画面上で比較する。
- 選択でframeを変えず、淡色/濃色カテゴリ、曙/宵、ホーム明日、Calendar日間/週間で判別可能にする。
- 未選択は静かなままにし、カテゴリ作成→即選択とcustom filterを維持する。
- 明確な優位案がなければスクリーンショットとtrade-offを提示してユーザー確認する。

比較案（2026-07-19）:

1. tint＋枠強調: 最も静かだが淡色カテゴリでは色差への依存が残るため不採用。
2. 末尾check枠を全chipへ常設: 明確だが全chipの幅と横スクロール量を増やすため不採用。
3. 既存の先頭icon領域だけを選択時にcheckへ切り替え、枠を1pt→2ptへ強める: frameと横密度を変えず、記号＋線幅の色非依存な2手掛かりを追加できるため採用。通常iconとcheckを同じ11pt固定slotへ重ねてView identityとlayoutを維持し、背景tint 20%とテーマ本文色はv2のまま維持する。

検証結果（2026-07-19）:

- `TimelineDisplayTests`と`CategoryMetadataTests`の12件/2 suites成功。選択/未選択style、カテゴリ作成後のquery待ち、custom filter保持、既存icon文字列の永続化を確認（`/private/tmp/ux-interaction-performance-v3/item-a/final-unit-ios261.xcresult`）。
- 選択前後の実layout診断では、後続chipの`minX`が309.8333pt、幅が52.6667ptで完全一致した。選択chip自身についてXCUIが返す可視境界は2pt stroke分だけ外側へ約0.5pt広がるが、HStackのlayout frameと横スクロール密度は不変（`ui-frame-diagnosis.xcresult`）。
- Home明日とCalendar日間/週間を、曙/宵、淡い黄/濃い紫で横断したUIテスト1件と12枚の画像が成功。作成した黄カテゴリの即時選択、画面/テーマ遷移後の選択保持、`.isSelected`も確認（`ui-full-final.xcresult`）。Calendarの淡色選択を中央に収めた曙/宵×日間/週間4枚も追加監査した（`ui-calendar-focused.xcresult`）。
- generic iOS Release build成功（`/private/tmp/ux-interaction-performance-v3/item-a/release-derived/Build/Products/Release-iphoneos/Liminalog.app`）。

## 6. Item B — Timeline性能

- `EditablePlanTimelineView`のView更新、render cache、collision/draft配列、Geometry/Preference、日付/文字列/ソート、Query、gesture state、副作用を計測する。
- 不変データをgesture frameごとに再計算せず、変更対象だけを更新する。
- persistenceとWidget/Live Activity/App Group等の副作用を描画経路から分離するが、順序・回数・最終結果は維持する。
- cacheは完全なinvalidation keyを持ち、stale表示を許さない。

## 7. Item C — Tab性能

- `RootTabView`と各タブの常駐Query、非表示中task/timer/notification、lifecycle refresh、Environment/store伝播、初回View構築を計測する。
- タップ直後の選択表示を重い処理から分離しつつ、必要な自動更新・データ・状態を維持する。
- 同一処理の重複だけを除去し、navigation/scroll/入力状態を失わない。

## 8. Item D — 横断監査

- A〜C統合後に主要画面を再計測し、証拠のあるhotspotだけを直す。
- category board、Calendar mode、Friends、Statistics、Profile、Settings、記録、予定sheet、context menu、theme changeを対象にする。
- 原因が独立する大規模案件は実装せず、AI_TASKSへ証拠付きで分離する。

## 9. 最終合格

- A〜Dの受け入れ基準、LiminalogTests全件、課金9 suites、generic iOS Release、purchase readinessが成功する。
- 曙/宵、通常/多量データ、再起動永続化、timeline全操作、5タブ20往復を確認する。
- iPhone 13 Release実機の同条件before/afterと60fps動画が残る。
- 課金禁止パス差分0、AI_TASKSとGit履歴が一致し、worktreeがcleanである。
- 一部改善や体感だけで完了扱いにしない。
