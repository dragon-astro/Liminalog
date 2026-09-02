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

進行中の調査・実装（2026-07-19）:

- scroll geometryの生イベントごとに、描画へ直接使わない`latestScrollMinY`を`@State`へ書き、24時間timeline全体のView更新候補を作っていた。値は次回zoomの中央時刻アンカーにだけ必要なため、SwiftUI非監視のinteraction scratchへ移した。可視時刻の更新とzoom時のアンカー計算は従来どおり全イベントを受け取る。
- move/開始resize/終了resizeでは、pixel単位の生ドラッグごとに`TimelineDragSession`を`@State`へ再代入していた。sessionは累積delta計算専用で表示値ではないため、同じscratchへ移した。15/5/1分snap、指への連続追従、衝突解決、draft更新、guide、haptics、保存条件は変更していない。
- gesture中のwarning latchとresize hapticの前回minuteも描画へ使わないためscratchへ移した。moveの前回minuteは画面上の時刻guideが参照するので`@State`のまま維持した。
- `draftIntervals`は同値なら書き戻さない既存guardがあり、render cacheにも完全な入力比較があるため維持した。入力を間引くdebounce/throttle、animation停止、古いsnapshot表示は追加していない。
- `PlanTimelineRescheduler.resolveClamped`のsortを疑い、48 intervals × 50,000 resolve × 5 runsで単体計測したところ、平均約0.612秒（約12µs/call）だった。通常日の件数では支配的hotspotという証拠がなく、順序・衝突挙動を変える危険があるため書き換えを棄却した。

同一データSimulatorの互換性比較（Release / iOS 26.1）:

- Debug fixtureで390 plans / 219 chaptersを生成し、同じstore、同じRelease UIテスト、同じSimulatorでItem A統合地点のbinaryと変更後binaryを比較した。途中のApp Group entitlement不整合runと空store runは正準データから除外した。
- before: `/private/tmp/ux-interaction-performance-v3/item-b/equal-data-before-ui.xcresult`、after: `/private/tmp/ux-interaction-performance-v3/item-b/equal-data-after-ui.xcresult`。再利用fixtureは`/private/tmp/ux-interaction-performance-v3/item-b/seed-store/`へ保存した。

| 操作 | before median / p95 | after median / p95 | 判定 |
| --- | ---: | ---: | --- |
| category選択 | 1.009s / 1.022s | 1.015s / 1.021s | 固定waitを含み実質同等。選択挙動の回帰なし |
| 4段階pinch/zoom | 8.449s / 8.497s | 8.448s / 8.525s | 実質同等。4 scaleと永続化の回帰なし |
| scroll signpost | 0.701s / 0.718s | 0.701s / 0.714s | 実質同等。連続scrollの回帰なし |
| scroll UI test全体 | 5.306s / 5.332s | 5.376s / 5.567s | element探索と固定waitを含み、改善証拠には使わない |

- Simulatorのwall-clockは入力互換性の回帰確認には使えるが、SwiftUI再評価回数、FPS、hitch、main-thread stallの改善判定には不十分である。この結果だけで性能改善・Item B完了とはしない。
- 対象41 tests / 3 suites成功（`/private/tmp/ux-interaction-performance-v3/item-b/targeted-tests.xcresult`）。timeline表示等を加えた関連51 tests / 5 suites成功（`related-tests.xcresult`）。generic iOS Release build成功（`generic-release-derived/Build/Products/Release-iphoneos/Liminalog.app`）。
- Item A統合地点`7a7c006`を隔離worktreeへ固定し、beforeの署名付きReleaseを`before-device-derived/Build/Products/Release-iphoneos/Liminalog.app`へ作成した。変更後も同じXcode、Release、arm64、Team `7834TP2P53`、開発証明書・プロファイルで`after-device-derived/Build/Products/Release-iphoneos/Liminalog.app`へ作成し、両方のdeep/strict code signing検証に成功した。
- 一時UIハーネスも同じTeamで`device-harness-derived`へ署名付き`build-for-testing`済み。scroll/zoom/categoryのclock・scroll signpost・hitch、move/開始resize/終了resize/15・5・1分/4 zoomの機能回帰、Instruments用連続操作driverを同じtest binaryでbefore/afterへ適用する。ハーネスは`/private/tmp`だけに置き、製品repoへ含めない。
- 正準端末のiPhone 13（`00008110-00114DE01EB9801E` / iOS 26.5.2）へItem A統合地点の署名付きReleaseを、既存データを保持して導入した。beforeのpinchは3反復成功（clock平均9.113秒、app hitch 3回/run、hitch total約50ms/run、`before-device-pinch-v2.xcresult`）。scrollと1.5倍への変更→再起動後永続化→2倍への復元も3反復成功し、scroll signpost平均2.392秒、平均58.38fps、scroll signpost内hitch 0、app hitch平均0.67回/runだった（`before-device-scroll-v3.xcresult`）。
- 実機UIハーネスの固定日・offscreen element・後片付けに起因した失敗runは製品の合否証拠から除外した。現在は実データの09:00〜11:24付近と衝突しない将来日を選び、作成した一時予定を製品UIから削除するハーネスへ是正済み。ただしXCTest再開時に端末の「Enable UI Automation」パスコード入力が要求されており、final before category/move/開始resize/終了resize、after全操作、Time Profiler/SwiftUI Instrument、p95 frame time、100ms以上stall、SwiftUI View更新、60fps動画は未確認である。Item Bは進行中のまま統合しない。

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
