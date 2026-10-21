# 32. カレンダー重点・アプリ全体の軽量化レビュー

レビュー日: 2026-09-07。対象: `codex/ux3-timeline-performance` / `5b609a6`。

**優先すべきなのは、フィルターの重複更新、予定の重複判定での履歴取得、表示していない月データの再構築。** 日・週タイムラインの大規模統合より先に、この3つの仕事量を減らすのが妥当。統計にも、既に別経路で改善した日別集計の旧方式が残っている。

これは静的レビューであり、以下のP1/P2は修正・計測の優先度を表す。余分な呼び出しや走査はコードから確認できるが、ユーザーの実機でどれが支配的か、何ms改善するかは未計測。操作の間引き、アニメーション削減、表示削減、状態破棄を改善策に含めない。

## 実装状況（2026-09-07追記）

ユーザーの実装指示を受け、以下を変更した。以降のレビュー本文とソース行番号は、変更前 `5b609a6` の記録として残す。

| 指摘 | 実装した内容 | 残る確認・変更 |
|------|--------------|----------------|
| R1 | フィルター全値を一つのスナップショットで監視。操作直後の同期更新を保持し、同じ値への観測通知では再構築しない | 実データでの呼び出し回数・反応時間 |
| R2 | 重複判定の終了側条件もDB述語へ。フォームは1回の検証結果をボタンと警告で共有。明日の空き時間は対象期間を1回取得して同じ15分刻みで探索 | 実機の取得時間。保存時の再検証・取得失敗時の安全側判定は維持 |
| R3（一部） | 日/週モードの再読込・タブ復帰では月スコアを生成せず、月へ戻る時に生成 | キャンセル時の更新省略、移動元/先だけの更新は未実装。プリセット・外部同期を含む失効経路の整理が必要 |
| R4 | 日タイムラインのキャッシュミスを非監視の一時キャッシュに保持し、同じ描画データの繰り返し生成を回避 | 実機でスクロール中心・move/resize/zoomの比較。旧軸は保持し中心復元に利用 |
| R5 | ScoreSnapshotLoaderの日別バケット関数を共通化し、StatsEngineも先に日別分類して集計 | 統計タブの実機計測 |
| R6・R7 | 未実装 | 友達の同期・時刻による失効を検証してからキャッシュ変更を行う |

単体テストは655件成功（104 suites）。別途XCTestは15件中1件成功・実CloudKit接続を要する14件は条件付きスキップ。追加回帰テストでは、重複判定の境界接触・自己除外・日跨ぎ・終日予定、空き枠が全て埋まった場合、統計のうるう日・夏時間・部分日の全スコアフィールドを従来の処理と比較した。

ログ: `/private/tmp/liminalog-lightweight-20260907-tests-v2.log`、結果: `/private/tmp/liminalog-lightweight-20260907-tests-v2.xcresult`。

Release Simulator（iPhone 17 / iOS 26.5）の月間ドロワーUI回帰17件がすべて成功。移動、枠外キャンセル、重複置換の取消/確定、詳細の高さ、長いメモ後のボタン表示、削除取消、月→週→日→月の往復を確認した。ログ: `/private/tmp/liminalog-lightweight-20260907-ui.log`、結果: `/private/tmp/liminalog-lightweight-20260907-ui.xcresult`。この時点では実機比較・実機更新は未実施。下記の実機検証追記で、同じメモリ内データの比較と通常Release導入まで実施した。描画完了時間・実データの性能合格は未確認。

最終コードのgeneric iOS / Release（署名なし）ビルドも成功。`error:` / `warning:` なし。ログ: `/private/tmp/liminalog-lightweight-20260907-release.log`。UIテスト後の最終差分は、日タイムラインの未使用引数削除のみ（挙動変更なし）。`git diff --check` 成功。

## Release実機検証（2026-09-07）

ユーザーの実機検証指示により、iPhone 16を使用。変更前は `5b609a6` を `/private/tmp/liminalog-device-before-20260907` に展開し、表示モード往復テストだけ現行と同じものをコピーした。作業ツリーの実装を巻き戻さず比較する。

両版とも `Liminalog-UIRegression` / Release / `LIMINALOG_UI_TESTING` / `ENABLE_TESTABILITY=YES`。翌月10日の12予定をメモリ内に生成し、実ユーザーデータやCloudKitの変更を伴わない。通常の永続ストアへのフォールバックなし。実データの大履歴負荷とは別条件である。

- 変更前ログ: `/private/tmp/liminalog-device-before-20260907.log`
- 変更前結果: `/private/tmp/liminalog-device-before-20260907.xcresult`
- 変更後ビルドログ: `/private/tmp/liminalog-device-after-build-20260907.log`

### 結果と限界

- iPhone 16 / iOS 26.6。変更前の移動計測・表示モード往復2件成功。変更後は全17件成功、0 failures。計測再試行時の表示モード往復も両版各1件成功。
- 変更後ログ: `/private/tmp/liminalog-device-after-20260907.log`、結果: `/private/tmp/liminalog-device-after-20260907.xcresult`。
- 同じ12予定での通常移動3回。全試行で長押し認識1回、native dismiss 0回。

| 指標（ms） | 変更前3回 | 変更後3回 | 中央値 前→後 |
|------------|----------|----------|---------------|
| 指を離すcallback→保存完了 | 58.176 / 57.200 / 57.411 | 58.469 / 57.775 / 60.488 | 57.411 → 58.469 |
| 指を離すcallback→復帰要求 | 61.828 / 60.341 / 60.643 | 61.574 / 61.001 / 63.546 | 60.643 → 61.574 |

この小データ条件では改善を確認できず、ほぼ同水準。3回だけなので統計的な同等性・悪化なしは断定しない。保存前後の既存計測点であり、フレームの描画完了、フィルター反応、大量履歴取得、日/週のmove/resize/zoomの性能を測った結果ではない。比較値: `/private/tmp/liminalog-device-comparison-20260907.json`。

画像を目視し、移動後の予定・復帰先・ドロワー配置が変更前と同じで、長文メモをスクロールした後の編集/複製/移動ボタンが下端で隠れないことを確認。

- 変更前画像: `/private/tmp/liminalog-device-before-20260907-evidence/04E00D82-9689-4687-A309-0A829CC66690.png`
- 変更後画像: `/private/tmp/liminalog-device-after-20260907-evidence/099F36A8-8D64-42D4-9098-04E7267A829D.png`
- 長文メモ: `/private/tmp/liminalog-device-after-20260907-evidence/26820EE0-AD7F-441F-BE05-E8856C2F5EAC.png`

**Instrumentsは未完了。** Animation HitchesとTime Profilerの両方で `Device got disconnected, ending recording...`。端末はdevicectl/xctraceの一覧で接続中、並行したUIテストは成功。保存された記録はそれぞれ1.614秒・1.766秒しかなく、操作区間の比較に使えない。原因は未特定。該当のxctraceプロセスだけSIGINTで終了し、残留させていない。ログ: `/private/tmp/liminalog-device-before-animation-20260907.log`、`/private/tmp/liminalog-device-after-cpu-20260907.log`。FPS・hitch・main-thread stall・60fps動画の合格判定は付けない。次回は実機プロファイル接続を切り分けてから、履歴多量条件とフィルター/日週操作の計測を行う。

**通常Releaseへ復帰済み。** 専用テスト条件なしで署名付きRelease build成功、署名検証成功。アプリ実行ファイルにfixture起動識別子/予定名がないことを確認。2026-09-07 14:33 JSTにiPhone 16へ上書き導入し、テスト引数なしの通常起動成功。アンインストール・実データ削除・リセットはしていない。通常版の実データ画面について、全操作の回帰を確認したわけではない。

- 通常ビルド: `/private/tmp/liminalog-device-normal-release-20260907.log`
- 導入: `/private/tmp/liminalog-device-normal-install-20260907.log`
- 起動: `/private/tmp/liminalog-device-normal-launch-20260907.log`


## レビュー時点の対象と確認方法

- App + Widget のSwiftファイル200件・68,875行を対象に、クエリ、タイマー、キャッシュ、保存・通知、参照数を横断検索した。全行の逐語精査ではなく、5タブと主要Storeの呼び出し経路を追う監査。
- 特に月・週・日カレンダー、予定編集、ドロワー、複製・移動、プリセットの描画・操作・保存経路を精査した。
- 過去のdocs/29・31の指摘を現在コードと照合し、解消済みのものを残件として再掲しない。
- 既存の未追跡 `.claude/` と `design-qa.md` は変更していない。今回の追加はこのレビュー文書のみ。アプリコード、スキーマ、設定、ユーザーデータは変更していない。
- generic iOS / Release / Xcode 26.6 (17F113) のビルド成功。UIテスト、Time Profiler、SwiftUI Instrument、実機FPS・操作遅延の再測定は未実施。

以下のソース位置はレビュー対象コミット時点の行番号。

## 優先して取り組む箇所

### R1 — P1: フィルター1操作から同じ全再構築が重複する

根拠: `Views/Calendar/CalendarView.swift:273–283,1248–1281`。

`toggleCategoryFilter` は `usesCustomCategoryFilter` と `storedCategoryFilterIDs` を更新した後、自分でも `reloadVisibleData()` を呼ぶ。両プロパティの `onChange` からも同じ更新を呼ぶため、全選択から1カテゴリを外す操作では、直接呼び出しに加えて2つの変更ハンドラが対象になる。友達フィルターも直接呼び出し＋`onChange`、リセットも最大3プロパティの監視と重複する。

1回の `reloadVisibleData()` はキャッシュを消し、前月・当月・翌月を作り直す。各月で予定、実績、進行中実績の3回の `ModelContext.fetch` があるため、友達オーバーレイなしでも1回の再構築につき9回のfetch呼び出しになる。これはディスクI/O回数や計測済みレイテンシを意味しない。

改善方向: フィルター値を一つの値スナップショットにまとめ、同じ値への更新につき再構築を1回にする。操作イベントを間引かず、AppStorageが別画面から変わる経路も保持する。関係のない時刻・予定データまで再取得する必要があるかも分けて検討する。

検証: カテゴリの全選択→一部→全選択、友達オン/オフ、リセットについて、最終表示と更新タイミングを維持し、各操作のreload/fetch回数が重複していないことを確認する。

### R2 — P1: 予定の重複チェックが過去の予定をまとめて読み込む

根拠: `Stores/PlanStore.swift:76–92`。呼び出し元は `Views/ChapterEdit/PlanCreateSheet.swift:135–147,445–484,501–536`、`Views/Home/HomeView.swift:290–305`、日・週タイムラインの予定作成・プリセット確定。

DB側の条件は `!isAllDay && startTime < endTime` のみ。候補を開始時刻でソートして全件取得し、取得後に `plan.endTime > startTime` を評価する。明日の予定を判定するだけでも、それ以前の時間指定予定が候補配列に入る。

予定編集では、保存ボタンとプリセット保存の `canSave`、時刻検証表示が同じ判定に入る。時間が妥当で重複のない未来予定では、これらの評価から複数回のfetchが起こり得る。予定名やメモの変更による描画更新にもDB処理が入り込む。

ホーム「明日」の空き枠探しは09:00から23:00まで15分刻みで同じ判定を呼ぶ。全候補が埋まっている通常の24時間日では最大57回の問い合わせになる。

改善方向:

1. 終了時刻側の重なり条件もDB述語に含める。既存編集IDの除外、境界が接するだけなら非重複、終日予定除外を維持する。
2. 編集画面では期間と既存予定の変更に依存する判定結果を一度計算し、ボタンと警告で共有する。保存時の再検証は残す。
3. 明日の空き枠探しは対象日の予定を1回取得し、同じ15分刻み・同じ順序で候補を判定する。

検証: 過去履歴の少量/多量、境界一致、日跨ぎ、編集対象自身の除外、取得失敗時の安全側判定。履歴だけ増やした場合に読み込む候補数が比例して増えないことを確認する。

### R3 — P1: 週・日表示や編集終了でも月用データを作り直す

根拠: `Views/Calendar/CalendarView.swift:173,203–225,847–857,873–885,1379–1435,1469–1483,1516–1667`。

`reloadVisibleData()` は表示モードにかかわらず月とタイムラインのキャッシュを全消去し、最初に3か月分の月データを作る。その後、週・日表示ならタイムライン予定も取得する。`performDeferredTabRefresh()` も週・日表示中に月データを更新してからタイムラインキャッシュを破棄する。

編集・検索・日間タイムラインのシートは変更の有無に関係なく `onDismiss` で再構築する。単純な月の日別ドロワーを閉じるだけの `didDismissMonthDrawer()` は、この問題の対象ではない。

月への移動確定は `applyMonthTransfer` 内で `reloadVisibleData()` が完了してから `finishMonthTransfer()` を呼ぶ。保存後も3か月分の取得・集計がドロワーを戻す処理より前にあるため、ドロップ後の待ち時間の有力候補になる。現在の `Task.yield()` は月ごとの実行機会を分けるだけで、1か月分の同期計算を細かく分けるものではない。

改善方向: 表示モード別に必要なデータだけを更新する。予定変更前後の期間、実績の影響日、カテゴリフィルター、友達共有の変更を使って、影響するページを無効化する。何も編集していないシート終了では、データ・外部更新・必要な時刻更新を確認して不要な再構築を省く。非表示データは次に必要になる前に整合させる。

注意: 全体revisionだけを見てスキップすると、他画面・同期・日跨ぎ・進行中実績の反映を失う可能性がある。現在月の結果を古いまま長く残して速く見せる変更は採用しない。

検証: 月/週/日での編集キャンセルと保存、同一日・別日・別月への移動、複数日コピー、重複置換、友達更新。最初の視覚反応、保存、ページ生成、ドロワー復帰を別々に計測する。

### R4 — P2: 日タイムラインのキャッシュミスが、その描画内で再利用されない

根拠: `Views/Calendar/EditablePlanTimelineView.swift:253–310,326–327,356–364,409–410,436–440,648–653`。比較対象: `CalendarWeekTimelineView.swift:2091–2104`。

日側の `currentRenderCache` はキー不一致なら `makeRenderCache` を返すだけで、その結果を保持しない。初回表示やキー変更時、`onAppear` / `onChange` がキャッシュを更新するまでの間は、`timelineAxisMap` など別の参照からも同じソート・区間生成・レイアウト生成へ入り得る。時刻アンカー等は軸マップを複数箇所で使っている。

週側は同じgetter内で非監視scratchへ結果を保存しており、構造上この重複を避けている。ただし週側もキー変更後に `refreshRenderCache` で再生成するため、更新時の二度仕事は計測対象にする。

改善方向: 一つの入力キーに対する純粋な描画計算を共有し、描画中の `@State` 書き換えを増やさない。日側の旧軸マップを使う中央時刻保持は必要なので、週側の実装をそのまま移植しない。

検証: 初回表示、カテゴリ変更、予定追加/保存、短い予定による軸伸縮ごとの `makeRenderCache` 呼び出し数。ズームの中央時刻、選択、スクロール位置、移動・リサイズの操作感を比較する。定常ドラッグの全フレームで常に再計算されるという指摘ではない。

### R5 — P1: 統計の日別集計には期間全体の反復走査が残る

根拠: `Logic/StatsEngine.swift:22–48`、`Views/Dashboard/DashboardView.swift:102–109,188–229`。改善済みの別実装: `Stores/ScoreStore.swift:242–313`。

`StatsEngine.dailyScoreSummaries` は日ごとに `plans.filter` と `chapters.filter` を呼ぶ。年表示は当年と前年の両方でこの処理を行い、通常年同士なら合計730日分の処理になる。予定配列には比較期間を含むクエリ結果を渡している。

さらに `DashboardPeriodSnapshot` をbody内で毎回作るため、60秒の `clock.now` 更新や表示設定変更でも集計へ戻る。前期間比較を非表示にしていても、前年側の集計を生成する。

docs/31の期間集計改善は `ScoreSnapshotLoader` には反映済みだが、統計で使うこの経路には届いていない。**同じ役割の集計が分かれているため、片方だけ最適化されている具体例。**

改善方向: `ScoreSnapshotLoader` の日別バケット生成と共通の純粋関数を使い、各レコードを重なる日に振り分ける。表示されるカードが必要とする派生値だけを生成し、データが変わらない過去日の結果を再利用する。

検証: 当年/前年、うるう年、日跨ぎ、進行中実績、0件、カテゴリなし、短時間実績について、日付と全 `ScoreSummary` フィールド・加算順序を維持する。日を跨ぐデータを開始日だけに入れる最適化は不可。

### R6 — P2: 友達カレンダーは描画中にDBを読み、訪問月を保持し続ける

根拠: `Views/Friends/FriendsView.swift:2855–2871,2891–2892,3060–3066,3185–3199`、`Stores/FriendCalendarPageDataBuilder.swift:11–49`。

友達カレンダーの `cachedPageData` はミスするとbody経路から `computePageData` を呼び、予定・実績・スコアを取得する。その結果自体はgetterでは保存しないため、初回や未準備ページの描画でDB取得と集計が繰り返される余地がある。自分の月カレンダーは既にbodyでの重い計算を避けている。

また `ensureData` は訪問した月を辞書へ追加し続け、通常の月送りでは自分側のような前月・当月・翌月へのpruneがない。全消去またはView破棄まで訪問月が残る。全961ページが最初から生成されるという意味ではない。

改善方向: 自分側と同じキャッシュ取得・準備・保持範囲の原則へ揃える。次ページは表示前に用意し、スワイプ時に空の月が見える回帰を避ける。共有データの変更通知と取得エラー表示は維持する。CloudKit輸送層の統合は不要。

検証: 初回、連続20か月送り、20往復、共有更新中の閲覧。キャッシュ数、メモリ、body中fetch回数、初回/再訪の表示時間を記録する。

### R7 — P2: 友達ランキングとプロフィールで長期間のスコアを再計算する

根拠: `Views/Friends/FriendsView.swift:644–725`、`Views/Profile/ProfilePerformanceSnapshot.swift:31–60`、`Views/Profile/ProfileView.swift:270–295`。

友達の自分スコアはランキング生成の描画経路から直接 `ScoreSnapshotLoader` を呼ぶ。期間内データ取得のバケット化は済んでいるが、年のスコア計算自体をbody外へ保持する仕組みはない。プロフィールも120秒のキャッシュ更新時に365日分を再計算する。

改善方向: 当日や変更日だけ更新する集計を再利用する。プロフィールのTTLを長くして軽く見せる方法は避ける。確定スコアを読む変更はdocs/27の透明化モデルと意味を合わせる必要があり、単にライブ計算を保存スコアへ置き換えない。まずは同一入力の計算再利用から始める。

検証: 当日実績の更新、過去日補正、期間選択、カテゴリ変更、公開データ更新で表示値が遅れないこと。友達数0ではランキング部分自体が表示されない点も条件に含める。

## スクロール・ドラッグで追加計測する候補

以下は構造上の候補であり、今回のレビューだけでホットスポットとは確定しない。

| 候補 | 根拠 | 操作感を保つ方向 |
|---|---|---|
| ドロワー高さの変化が月ページャ全体へ伝わる | `CalendarView.swift:846` の連続heightを、`:519–520,727–784` がページ高さ・paddingへ渡す。月の週行はbody内で配置・セルモデルを生成する（`:3725–3727,3815–3865`） | 高さに依存しない予定配置を再利用し、連続的な高さ追従は維持する |
| 月ドラッグの当たり判定が毎回全登録セルの座標変換を行う | `CalendarMonthTransferInteraction.swift:81–111` と `TimelinePlanPresetLibrary.swift:749–757`。`compactMap` 後に当たり判定する | 画面内候補の絞り込み・一時配列削減。スクロールやsheet退避中に古い座標を固定しない |
| 日タイムラインのドラフト変更時に全可視区間のレイアウトを再計算する | `EditablePlanTimelineView.swift:382–393` | 実測で支配的な場合だけ変更区間に限定する。連鎖押し出し・衝突・短い予定の軸伸縮を維持 |
| 日詳細とHomeの実績クエリが対象日＋14日前まで取得する | `CalendarDayView.swift:47–61,511–515`、`Home/TimelineView.swift:149–163` | 長期間チャプターの仕様を維持できる重なり述語を検証する。単純に開始日だけ絞らない |
| 記録操作の同期副作用 | `ChapterStore.swift:51–71,127–155,894–900` | UI反映、保存、App Group snapshot、Widget、Live Activityを区間分解。保存保証やウィジェット反映を省略しない |

月移動の `transferDayStatuses` は既にsource1回＋期間1回の取得にまとめている（`PlanStore.swift:502–521`）。ドラッグ毎フレームのDB問い合わせとして扱うのは誤り。ただし警告計算は日数×期間内予定の走査なので、予定が多い月で長押し開始直後の時間を計測する価値はある。

## 過剰実装・保守面の整理

### O1: 日・週の類似実装は大きいが、統合だけで速くなるとは限らない

- 日側2,692行、週側2,912行。Python `difflib.SequenceMatcher(autojunk=False)` で6行以上の完全一致ブロックを抽出すると48ブロック・498行。空白や宣言も含む機械集計であり、削除可能行数ではない。
- 現在は軸変換、ドラッグsession、プリセット配置、削除、スクロール後始末などの二重保守が残る。
- 共通化は純粋な区間処理、座標変換、表示部品から進める。週側には日跨ぎsegment identityや複数日の移動があり、「日を7つ並べるだけ」の置換は適切でない。
- 自分と友達の月表示は `CalendarMonthGrid` と `CalendarMonthPickerSheet` を既に共有している。月表示全体が未共通化という過去の記述はそのまま採用しない。残るページ準備・キャッシュ方針の差をR3/R6として解消する方が有効。

### O2: 参照のない表示型が9つ残る

App・Widget・Unit/UI Tests内で単語境界付き検索を行い、以下は各1回、宣言のみを確認した。

| 型 | 場所 |
|---|---|
| TimelineChapterCard | `Views/Home/TimelineChapterCard.swift:3` |
| YesterdayScoreCard | `Views/Home/HomeView.swift:916` |
| FriendProfileHero | `Views/Friends/FriendsView.swift:2577` |
| FriendScoreCard | `Views/Friends/FriendsView.swift:2822` |
| ProfileFragmentBalanceCard | `Views/Profile/ProfileComponents.swift:2949` |
| ProfileCollectionSection | `Views/Profile/ProfileComponents.swift:3007` |
| ProfileCollectionBadge | `Views/Profile/ProfileComponents.swift:3029` |
| ProfileFormat | `Views/Profile/ProfileDecorations.swift:425` |
| DashboardProgressRow | `Views/Dashboard/DashboardCards.swift:364` |

整理候補だが、実行されない表示コードの削除はカレンダーの操作遅延対策としては後順位。今回は削除していない。

### O3: EventKit取り込み基盤とテーマ再生成は別枠

`CalendarEventSyncStore` は本番の呼び出し元を確認できず、`CalendarEventCache` はスキーマに登録済み。機能の採用判断と永続データ互換性の問題であり、重い操作の直接原因とする根拠はない。

`RootTabView.swift:321–328` はテーマ切替後にプロフィール以外の4タブのidentityを変える。カレンダーのページ・状態・キャッシュを作り直す広い回避策なので、テーマ依存表示を修正できれば縮小候補になる。ただし通常の月送りの原因ではなく、テーマ切替の描画を直す目的があるため一律削除はしない。

CloudKitの小さいPolicy型、保存時の再検証、置換承認後の変更検出、rollback、課金の権利確認は、コード量だけを根拠に削らない。今回確認した予定保存経路は既にStoreのsaveと変更通知を通し、ChapterStore側は二重の共有通知を避けている。

## 解消済み・再掲しない指摘

docs/31の環境変数参照、Homeタイムラインの記録revisionによるidentity再生成、巨大String署名、`ScoreSnapshotLoader` の日別バケット化、ScoreCalculatorのカテゴリgrouping共有、CategoryGridのactive query、Calendarの生成キャッシュ、PreviewSupportのDEBUG隔離は現在コードへ反映済み。

月のページ候補が961個あることだけでは、961か月分を同時に描画している証拠にならない。ページャはLazyHStackであり、自分側の月データ保持は3か月に制限される。同様に、現在のCalendarViewの `clock.now` 読み取りはページ生成関数側にあり、古い台帳にある「月カレンダー全体が毎分必ず再評価される」という説明は現在コードからは断定しない。

## 実装に進む場合の順序と合格条件

1. 現在HEADで同じRelease実機・同じデータ・同じ操作の基準値を採る。まずR1〜R3の呼び出し回数と区間時間を収集する。
2. R1の重複更新、R2の取得範囲・共有検証、R3の必要ページ限定を一件ずつ実装・比較する。
3. 日・週の選択/作成/保存に遅さが残るならR4、連続操作なら座標変換・レイアウトを測る。
4. R5の統計集計、R6の友達カレンダー、R7の長期間スコアへ展開する。
5. 死蔵コード整理と純粋関数の共通化は別変更にし、性能改善の証拠と混ぜない。

最低比較: タブ20往復、月20か月送り、フィルター切替、編集キャンセル/保存、ドロワー上下、月への移動/複製、週/日のscroll・move・両端resize・4段階zoom・15/5/1分。少量と履歴多量のデータ、日跨ぎと友達更新も含める。

既存の `TabPerformanceDiagnostics` を使い、fetch/キャッシュ生成/保存/復帰を分けて記録する。`CalendarMonthDrawerUITests.testDropLatencyMetric`（55–70行）は現状、計測文字列とdismiss回数を検証するだけで遅延上限をassertしない。またcommitは月再構築前、restoreは復帰要求時の記録で、実描画完了ではない。このテストの成功だけでは「ドロップが滑らか」の証拠にならない。

性能合格はdocs/28の同条件比較を使う。p95の視覚反応100ms以内、100ms以上のmain-thread stallなし、基準60Hz実機で平均58fps以上・原則p95 frame time 20ms以内、hitch悪化なし。さらに60fps動画で選択・追従・アニメーション・保存後の表示とスクロール位置を確認する。

## レビュー時点の検証記録

```sh
xcodebuild -project Liminalog.xcodeproj -scheme Liminalog \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/liminalog-review-20260907-derived \
  CODE_SIGNING_ALLOWED=NO build
```

結果: `BUILD SUCCEEDED`、ビルドログ内の `error:` / `warning:` 該当なし。

ログ: `/private/tmp/liminalog-review-20260907-build.log`。これはコンパイル確認であり、実機性能・UI回帰の合格を意味しない。Simulator一覧の読み出しはサンドボックス内でCoreSimulatorへの接続に失敗した。今回はUI実行を行わず、実機へのインストールも行っていない。
