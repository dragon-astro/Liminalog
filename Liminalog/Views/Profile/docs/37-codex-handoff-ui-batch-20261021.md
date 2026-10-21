# 37. Codex への引き継ぎ：UI・動線バッチ（docs/36）

作成: 2026-10-21 / Claude

2026-10-21 Codex（第1段階）：優先項目1-1〜1-3を実装・検証。最初の依頼範囲はSimulatorまで。結果は §5。

同日の追加依頼：実機検証を行い、その後、蓄積した変更を保存して作業ツリーをクリーンにする。追加の結果は §6。

対象: `codex/ux3-timeline-performance` の作業ツリー（**すべて未コミット**。Codex の未コミット変更と同じファイルに混在）

分担はユーザー指定のとおり **見た目・画面の組み方＝Claude／機能・データ・ジェスチャ＝Codex**。設計の経緯と判断理由は [36](36-app-navigation-review.md) の §R。この文書は「何が変わったか」と「Codex がやること」だけをまとめる。

ユーザーの方針: 次のブランチから運用を整える。この作業ツリーの扱い（分けてコミットするか）は、ユーザーの指示に従う。

---

## 1. Codex への依頼（優先順・対応結果付き）

### 1-1. 週間はメイン予定だけを扱う — 実装・Simulator検証済み
ユーザー判断（2026-10-21）：週間は列が約50ptで、メモのカードは1文字しか読めない。点線の印も「ごちゃつく」として不採用。**週間ではメモを一切表示しない**。

- 週間の描画・軸・ヒット判定・移動の基準データからメモを除外。保存済みメモは維持し、日表示で編集する。Claudeの暫定 `hidesMemoInWeek` と操作中メモの表示分岐は撤去した。
- 空き時間の長押し作成はメインのみ。未選択の予定上の長押しは選択へ、選択後のドラッグは移動へ。選択済み予定の長押し削除は従来どおり。
- 横移動は日付の変更だけに使い、メイン／メモの切り替え・種類ガイド・メモ昇格確認を週間から撤去。
- メインの予定プリセットは列の左右によらずメインとして配置。固定時刻は保存時刻、長さ型はドロップ位置を使う。
- **メモ用の予定プリセットは週間では追加せず、日表示で使うよう案内する**（2026-10-21 ユーザー回答）。タップ・ドロップ・保存直前で防ぎ、登録したプリセットの種類は変えない。一日プリセット内のメモは登録内容を維持し、週間では非表示。
- 日表示・月から拡大したタイムライン・ホーム明日のメモ操作は変更していない。
- 旧仕様の週間メモUIテスト5本を、メインの作成・選択・横移動・プリセット配置・日表示でのメモ編集の確認へ置き換えた。メモプリセットの拒否、別日移動、長さ型配置も追加。詳細は §5。

### 1-2. ヘッダーのボタン範囲（当初は「＋」の22ptとして報告）
- 当初は `CalendarMonthDayDrawer.createButton` が22ptと報告されたが、失敗したテストは複数ボタンの高さを共通で調べていた。**2026-10-21 Codex が変更前のRelease Simulatorで再現し、対象は `calendar-open-presets`（上部しおり）のAX範囲14×22ptと特定**した。
- ＋は約42.25×42.25pt（シートの縮小後）で、下端タップも成功。しおりも中心から18pt下のタップは成功し、実際のタップ領域とAX範囲が不一致だった。
- しおりの44ptラベルに `contentShape(Rectangle())` を追加。アイコンの見た目・配置は維持し、44ptの領域が認識されるようにした。＋の変更は不要。テストの高さ条件は緩めず、失敗対象を示すメッセージと周縁タップの確認を追加した。

### 1-3. プリセット入口の統一後の動作確認（Claude 実装、操作の検証を依頼）
入口を1つにして、ドロワー内で「予定｜一日」を切り替える形にした（§2-3）。最初はユーザー指定によりRelease Simulatorで検証（§5）。追加依頼でRelease実機まで検証範囲を広げた（§6）。§3はClaude時点の履歴。
- 一日タブ → カード → 既存の `DayPresetApplySheet`（丸ごと追加）→ 置換確認 → 適用後にドロワーが閉じ、表示が更新される。月・週・日・拡大・ホーム明日の各入口で。
- 週間の一日タブで「追加する日」を変えたときに、置換の判定がその日で行われること（`TimelinePlanPresetLibrary.existingPlans(around:)` で取り直している）。
- 予定タブからの長押し配置（長さ型）・タップ追加（固定時刻）が、タブ付きのドロワーでも従来どおり動くこと。
- 月表示のマスを画面の下まで伸ばした（`CalendarMonthDayCell.cellHeight(forWeekCount:viewportHeight:)`）。iPhone SE など小さい画面と Pro Max で、マスの高さ・ドロワー表示中のスクロール・月をまたぐドラッグが崩れないこと。

### 1-4. 既存タスク（AI_TASKS §8.17）
- 予定編集カテゴリ欄の表示時間を Release 実機で確認（Codex 集計に移行済み。Simulator まで確認済み）。
- インストール直後の初回起動で起動引数が無視される件（Codex 調査中。2026-10-16 の時点で元症状は未再現）。

### 1-5. 保留（ユーザー判断待ち）
- docs/36 X2：ドロワー拡大を「シートの重ね」でなく「同じシートが伸びる」形へ。C（入口の統一）が入ったので判断できる段階。
- docs/36 X3：公開設定の3層（カテゴリの既定／友達ごと／予定ごと）の整理。考え方をユーザーと先に決める。

---

## 2. Claude が変えたもの（ファイルと挙動）

### 2-1. A：小さな修正
| 内容 | ファイル |
|---|---|
| 週表示のアイコンを `rectangle.split.3x1` に（一日プリセットの `calendar.badge.clock` と区別）。統計の「週間」も同じ形に | `CalendarView.swift`（`CalendarDisplayMode.systemImage`）、`DashboardCards.swift` |
| プロフィール右上の設定アイコンを `line.3.horizontal` → `gearshape` | `ProfileView.swift` |
| 未来日の一日のまとめ：点数・一致・実績を「--」、見出しを「これから」に。リストは予定タブに固定し、実績タブは薄く押せない状態。**共有の保存値 `timelineSelectedTab` は書き換えない** | `CalendarDayView.swift`（`isUpcomingDay`）、`TimelineView.swift`（`plansOnly`、`TimelineTabInlineToggle.lockedTab`） |
| 取り消し済み（コードは元どおり）：ホーム上端のフェード、ホーム今日の右上アイコン変更 | `LiminalTheme.swift` と `HomeView.swift` の該当箇所は差分なし |

日／週／月メニューにチェックを付ける変更（A2）は、C で表示切替のメニュー自体を撤去したので残っていない。

### 2-2. B：予定編集・友達の見え方
| 内容 | ファイル |
|---|---|
| 予定編集のカテゴリ欄を `PlanCategoryInlinePicker` に置換：見出し行に選択中のチップ、開閉（`planEditor.categoryPickerExpanded`、前回を記憶）、ホームと同じ並びのテーブル（`CategoryGridPickCell(compact: true)`、private → internal に変更）、テーブル外は「その他」（`ChipFlowLayout`、並び順 `planEditor.otherCategoryOrder`）。テーブルの切替はホームの `activeCategorySetID` を**読むだけ**で書き戻さない。カテゴリが0件のときは従来の行とシート | 新規 `ChapterEdit/PlanCategoryInlinePicker.swift`、`PlanCreateSheet.swift` |
| よく使う順の集計：Claude の暫定版を Codex が置き換え済み | `Logic/CategoryUsageRanking.swift`（Claude 作成・Codex 改修） |
| 公開範囲：「友達に見せる」スイッチ＋「公開相手 …… カテゴリの既定（n人）›」→ シート上部に「カテゴリの既定｜自分で選ぶ」。一覧で選び直すと自動で custom。**シートを開いただけでは custom にしない**（従来は開いた時点で custom） | `PlanCreateSheet.swift`、`Shared/AudiencePickerSheet.swift`（`AudienceSnapshotPickerSheet` を `Header` 付きのジェネリックに。チャプター編集の呼び出しは変更なし） |
| 種類の切替を最上部へ移す案は取り消し（docs/34 の並び順を維持） | — |
| 友達ごとの見え方：カテゴリのスイッチ8行 → チップの複数選択。見え方「オフ」中はチップを薄く押せなくし、注記を出す（`publishMode == .none || level == .none`） | `FriendsView.swift`（`isSharingOff`）、新規 `Shared/ChipFlowLayout.swift` |

### 2-3. C：プリセット入口の統一・カレンダー見出し
| 内容 | ファイル |
|---|---|
| 共通部品：`PresetDrawerKind`（最後のタブを `presetDrawer.kind` に保存）、`PresetEntryButton`、`PresetEntryDivider`、`PresetKindTabs`（ナビバー用 `compact`）、`PresetManageLink`、`DayPresetDrawerList`、`DayPresetApplyTarget` | 新規 `Calendar/PresetEntryComponents.swift` |
| `TimelinePlanPresetLibrary` に `dayPresets: TimelineDayPresetConfiguration?` と `onManage:` を追加。渡すと見出しが「予定｜一日」タブになる。渡さない呼び出し（一日プリセット編集画面）は従来の見た目。**`@Environment(ChapterStore.self)` を読むようになった**（新しい呼び出し元は環境に ChapterStore が必要） | `TimelinePlanPresetLibrary.swift` |
| カテゴリ列：左端にしおり（固定）＋縦線、右側がカテゴリ（スクロール）。API を `showsPresetEntry` / `onOpenPresets` に変更（旧 `showsPlanPresets` / `showsDayPresets` / `onOpenPlanPresets` / `onOpenDayPresets` は削除） | `CalendarTimelineCategoryPalette.swift`、`HomeView.swift`（`HomeTomorrowTimelineCategoryPalette`） |
| カレンダー見出し：`[⚙][しおり] 年月 [≡][🔍]`。表示切替メニュー（`カレンダー表示を切り替え`）を撤去。年月シート `CalendarMonthPickerSheet` の見出し直下に「日間・週間・月間」タブ（押すと切替えて閉じる。新パラメータ `modeTitles` / `selectedModeIndex` / `onSelectMode`。友達カレンダーからの呼び出しは従来どおり） | `CalendarView.swift` |
| 月表示：プリセット専用行を撤去。マスを画面の下まで伸ばす（環境値 `calendarMonthViewportHeight`。最小は従来の固定値）。月のプリセットは1枚のシートで、ナビバー中央に「予定｜一日」（`CalendarMonthPresetSheet`）。`CalendarMonthPresetRequest.Kind` と `CalendarTimelineDayPresetRequest` は削除 | `CalendarView.swift`、`MonthPlanPresetApplySheet.swift` / `DayPresetViews.swift`（`titleAccessory`、`initialPresetID`） |
| 日・週：入口は見出しのしおり。週の一日タブは「追加する日」を選べる（初期値は週内の今日、なければ週の初日） | `CalendarView.swift`（`timelineDayPresetConfiguration`）、`CalendarWeekTimelineView.swift` |
| ホーム明日・拡大タイムライン：カテゴリ列のしおりからドロワー。ホーム明日の右下の丸いしおりボタンは出さない（`EditablePlanTimelineView` / `CalendarDayTimelineContainer` に `presetDrawerPresentation` / `presetDayConfiguration` / `onPresetManage` を追加） | `HomeView.swift`、`CalendarExpandedDayTimeline.swift`、`EditablePlanTimelineView.swift`、`CalendarView.swift` |
| 管理リンク：ドロワー右上の小さな「管理」。カレンダー設定（`CalendarSettingsSheet`）を開くだけ。管理の正は設定（カレンダーの⚙ → プリセット） | 同上 |

### 2-4. 毎月 第◯曜日の画面（Codex のモデルに接続）
- 毎月のとき「日付で｜曜日で」（`plan-recurrence-monthly-mode`）。曜日で選ぶと、第1〜第4・最終（複数選択・最後の1つは外せない、ラベル `第1週`〜`第4週`・`最終週`）と曜日1つ（`monthlyWeekday`）。開始日の説明文に曜日方式を追記。
- ファイル：`PlanSchedulingControls.swift`（`monthlyControls` / `ordinalButtons` / `monthlyWeekdayButtons`）。

### 2-5. 週間の予定メモ
- Claude時点では `CalendarWeekTimelineView.swift` の `hidesMemoInWeek` で非表示化。Codexが操作経路も含めてメイン専用へ整理済み（§1-1・§5）。

---

## 3. テストへの影響と検証状況

### 3-1. UIテストで変わった識別子（テストは Claude が更新済み）
| 旧 | 新 |
|---|---|
| `カレンダー表示を切り替え` → メニューの `週間` など | `calendar-period-button` → タブの `日間`/`週間`/`月間`（ヘルパー `switchCalendarMode`） |
| `month-open-plan-presets` / `month-open-day-presets` | `calendar-open-presets` → `preset-kind-plan` / `preset-kind-day`（ヘルパー `openMonthPresets`） |
| カテゴリ列の `予定プリセットを開く` / `一日プリセットを適用` | カレンダータブの日・週は `calendar-open-presets`、拡大とホーム明日は `timeline-open-presets` → タブ（ヘルパー `openPresets`）。一日のカードは `day-preset-card-<id>` |
| 予定編集の `公開範囲` ボタン | `友達に見せる` スイッチ |

- **`presetDrawer.kind` は起動をまたいで残る**ため、テストでは開くたびにタブを押して選ぶ（ヘルパーがそうしている）。起動引数で値を入れると引数の値が優先され、タブを押しても切り替わらなくなるので使わない。
- 追加したテスト：`testMonthlyOrdinalWeekdayRecurrenceShowsSummaryAndSaves`。
- `LiminalogUITests/TimelineInitialPositionUITests.swift` も表示切替の手順だけ更新した。

### 3-2. Claude時点の実行結果（すべてDebug・iOS 26.5 Simulator）

以下は引き継ぎ前の履歴。CodexのRelease結果は §5。Release UIテストでは `SWIFT_ACTIVE_COMPILATION_CONDITIONS=LIMINALOG_UI_TESTING ENABLE_TESTABILITY=YES` を明示する。
| 日付 | 範囲 | 結果 |
|---|---|---|
| 2026-10-16（C 実装後） | `CalendarMonthDrawerUITests` 全体 + `TimelineInitialPositionUITests` | 63本中62本成功。失敗は §1-2 の1本 |
| 2026-10-21（毎月の画面、週間メモを点線にした時点） | 新規の毎月テスト＋週間のメモ系6本 | 毎月テスト成功。週間6本のうち2本失敗（§1-1 の想定どおり） |
| 2026-10-21（週間メモを非表示に変更後） | ビルドのみ | UIテストは再実行していない |

- 単体テストは Claude 側では流していない。Release ビルド・実機の確認もしていない。
- 使った Simulator：Claude 専用の `Claude-C-mockups`（iPhone 17 / iOS 26.5、`95334A1A-…`）と `iPhone 17`（`AB3D87B5-…`）。Codex は自分の Simulator を使ってほしい。
- Simulator の操作ツール（MCP）ではスイッチ（`Toggle`）が反応しない。画面の確認は XCUITest で行った。

### 3-3. 画像
`design/app-navigation-review-20261005/`：`compare-A*` / `compare-B*` / `compare-C-*`、実装後の画面は `after-A/` `after-B/` `after-C/`（不採用案は `-rejected` / `-reverted` 付き）。

---

## 4. コミットを分けるときの目安
Claude だけで完結している新規ファイル：`PresetEntryComponents.swift`、`ChipFlowLayout.swift`、`PlanCategoryInlinePicker.swift`（集計部分は Codex 改修）、docs/36・37、`design/app-navigation-review-20261005/`。

それ以外の §2 のファイルは Codex の未コミット変更と同じファイルに混在している。分ける場合は §2 の表を目印に hunk 単位で選ぶ。


---

## 5. Codex 実装・検証結果（2026-10-21）

### 5-1. 変更範囲

| ファイル | 今回の変更 |
|---|---|
| `CalendarWeekTimelineView.swift` | §1-1のメイン専用化。描画前にメモを除外し、週間専用のメモ作成・種類切替・昇格・半幅レイアウトを撤去。既存メインの移動／リサイズは共通の押し出し処理を使う。日付見出し・予定に安定したテスト識別子を追加。 |
| `CalendarView.swift` | 上部しおりの44pt領域に `contentShape(Rectangle())`。月の縦スクロール領域を表示領域内に収め、最小マス高さを維持したまま、収まらない月はドロワーなしでも縦スクロール可能に。 |
| `CalendarMonthDrawerUITests.swift` | 旧週間メモテストの置換、プリセットの各入口／対象日／種類維持、周縁タップ、小型・大型画面の月末到達と翌月ドラッグを追加・強化。 |

**＋の22ptという報告の訂正**：変更前のReleaseテストで対象を特定したところ、上部しおりのアクセシビリティ範囲だった。ドロワーの＋は下端タップも成功しており、`CalendarMonthDayDrawer.swift` は今回変更していない。

**小型画面で追加修正**：SEでは、月表示の最終行が下部タブの後ろへはみ出していた。`isHittable` だけの検査はこれを見逃すため、実際のフレーム境界を比較するテストへ変更。最小マス高さとClaudeの配置を保ち、表示領域を制限してスクロールで到達できるようにした。ドロワーなしの月末全行、ドロワーありの最終行・月送り・翌月への予定移動をSE／Pro Maxで確認済み。

### 5-2. 検証

iOS 26.5の専用Simulator（iPhone 17、iPhone SE 第3世代、iPhone 17 Pro Max）を使用。実機はユーザー指定で対象外。変更に関係する回帰を段階実施し、月の表示領域修正後は影響するケースを再検証した。アプリ全テストの一括実行ではない。

- **単体112件／10スイート成功（Debug）**：予定押し出し・直接編集・メモ・一日プリセット置換／適用・月次繰り返し・通知と周期・ジェスチャ優先順位・カテゴリ集計。
- **Release UI 29種類の最新結果が成功**：週間のメイン専用操作とメモプリセット案内、日表示のメモ操作、プリセットの月／週／日／拡大／ホーム明日の入口、週間で変更した適用日の置換、月の固定時刻／長さ型配置、毎月第○曜日の画面と保存、ヘッダー周縁・大きい文字、初期7時表示とスクロール位置の維持を含む。同じケースの画面サイズ別実行は重複計上しない。
- 週間の一日プリセットテストでは、既定の「重ならない部分を残す」動作を検証。09:00–12:00を10:00–11:00の予定で置き換えると、09:00–10:00と11:00–12:00が残り、別の適用日も独立に判定される。
- **通常Release Simulatorビルド成功**（テスト用コンパイル条件なし）。codesign検証成功。fixture／計測専用シンボルが含まれないことを確認。通常版の実機起動・性能測定はしていない。

証跡の基準ディレクトリ：`/private/tmp/liminalog-handoff-20261021/`。各行の名前に `.log` / `.xcresult` を付ける。

| 証跡 | 結果・位置づけ |
|---|---|
| `baseline-header` | 変更前にAX範囲の不具合を再現。失敗対象がしおりと判明。 |
| `week-and-hit-regions` | 8/8成功。週間操作、メモ拒否、周縁タップ。 |
| `logic-tests` | 112/112成功。 |
| `preset-regression` | 17/18成功。1件は「元予定が全消去される」という新規テストの誤った期待値。残る前後の時間を正しく検証するよう直し、下記で再実行成功。 |
| `small-screen` / `large-screen` | 各3/3成功。ただし修正前の弱い月末判定を含むため、最終行の表示保証には使わない。SE画像で実際のはみ出しを発見した。 |
| `final-small-and-presets` | SEで5/5成功。修正後の月末表示・週間の適用日と残存時間・長さ型・周縁タップ。ドロワー上のスクロール確認日は28日だったため、最終行は下記で改めて確認。 |
| `final-large` | Pro Maxで2/2成功。月末表示・ドロワー上のスクロールと翌月移動。ドロワー表示時の最終行は下記でも確認。 |
| `final-last-row-small` | SEで1/1成功。ドロワー上の確認日を月最終日の30日へ厳密化し、最終行全体が上へ出ること・翌月移動を確認。画像も目視確認済み。 |
| `final-last-row-large` / `final-last-row-large-ready` | 初回はSimulatorがテストランナーをBusyで起動拒否し、テスト未実行。`simctl bootstatus -b` で起動準備完了を確認後、同じバイナリの1ケースを再実行し1/1成功。Pro Maxでも最終行と翌月移動を確認。 |
| `final-month-drop` | 1/1成功。表示領域修正後も日付選択前のプリセットドロップが対象日に適用される。 |
| `normal-release-final.log` | 通常Release Simulatorビルド成功。 |

画面証跡：`artifacts/codex-handoff-20261021/`（ローカル・git除外）。`before-small-month.png`／`after-small-month.png` はSEの修正前後、`after-small-month-scroll.png` はドロワー上の月最終行、`after-small-next-month-drop.png` は翌月移動後、`week-main-only.png`／`week-preset-drop.png`／`week-day-preset-target.png` は週間操作。`after-large-month-scroll.png` はPro Maxのドロワー上の最終行。目視確認済み。実行別の集計は同じディレクトリの `verification.json`。専用Simulatorは検証後に停止した。

### 5-3. 残るもの

- 初回だけ起動引数が無視されるという元症状は今回も未再現。新規Pro Max Simulatorの初回Release UIテスト導入・起動では、再試行なしで指定のCalendar fixtureを開いた。症状そのものの解消は断定しない。
- 編集シートの実機Release表示時間・実際の指での操作感は未確認。今回はSimulatorまでというユーザー指定の範囲を守った。

  その後の実機自動操作・計測は §6。ユーザー本人の操作感の評価とは区別する。
- X2（同じシートが伸びる拡大）・X3（公開設定の整理）は保留のまま。
- この段階ではClaudeとCodexの変更が混在した未コミット作業ツリーを維持し、コミット・pushはしていない。その後の整理は §6。

## 6. 実機検証と作業ツリー整理（2026-10-21 追加依頼）

### 検証条件

- 接続された iPhone 16 / iOS 27.0.1。署名付きRelease UIテストを使用。
- UIテストは既存の `LiminalogRuntime.isRunningUITests` によるメモリ内ストアを使用し、CloudKit同期と通知送信を抑制する。実ユーザーの予定をテスト用fixtureで置き換えない。
- 今回の29ケースに、ドラッグ保存・拡大表示の計測、カテゴリ付き編集の3往復、任意日時通知、繰り返しの元と個別予定の分離を加えた34ケースを選択。
- カテゴリ付き編集の準備時間は、XCTestのタップ開始からカテゴリ見出しの操作可能判定まで。自動操作とAX問い合わせを含み、アプリ内部だけの描画時間や改善前後比較とは区別する。
- 証跡は `/private/tmp/liminalog-device-cleanup-20261021/`。実行結果は下記。

### 蓄積分の単体回帰

`full-unit.xcresult` の正式集計は **738件中721件成功、17件スキップ、失敗0**。スキップは実CloudKit接続を必要とする14件と、手動実行用のデザインレンダラ3件。予定メモ・繰り返しの移行、共有データ、スコア・集計も含めて確認した。Swift Testingのログにある723件はスキップを含むため、成功件数として使用しない。

### 保存・整理の方針

- アプリ・テスト・設計資料と、アプリとは別の `design/` の試作コード／生成スクリプトを保存する。試作の保存は製品への採用を意味しない。
- 比較用PNG 281枚（約355 MiB）は元のパスに残し、Gitから除外。`design/generated-images-manifest.json` にサイズとSHA-256を記録する。
- Mac固有のXcode表示順とClaudeのローカル起動設定は手元に残してGit管理から分離。共有schemeは維持する。
- `project.pbxproj` は旧版と現状を `plutil` で構造比較し、内容が同一で並び順だけの差分を除去した。
- 整理前の全未追跡ファイルと差分を `artifacts/device-cleanup-20261021/untracked-before.tar.gz`、`before.patch`、`before-inventory.json` にバックアップ済み。作業の削除やstashによる隠蔽でクリーンにする方式は使わない。


### Release実機での計測値（一時fixture）

| 区間 | 3回の範囲 | 中央値 |
|---|---|---|
| 月間ドラッグ：指を離してから保存完了 | 45.29〜48.56ms | 47.81ms |
| 月間ドラッグ：指を離してからドロワー復帰要求 | 48.83〜52.12ms | 51.62ms |
| 一日のまとめ：タップから内容のonAppear | 19.20〜25.09ms | 23.66ms |
| 一日のまとめ：タップから表示完了（アニメーション込み） | 733.73〜767.60ms | 734.15ms |
| 拡大タイムライン：タップから内容のonAppear | 23.26〜45.57ms | 35.35ms |
| 拡大タイムライン：タップから表示完了（アニメーション込み） | 650.78〜717.42ms | 666.95ms |
| カテゴリ付き編集：XCTestのタップ開始から操作可能判定 | 1899.36〜1961.66ms | 1905.44ms |

前6行は既存のアプリ内計測、最終行はUI自動操作全体の計測で、同じ種類の時間ではない。編集シート内部だけの描画時間、実ユーザーの大量データでの時間、改善前後の速度差はこの結果から主張しない。ドラッグは3回ともドロワーのdismissなし。拡大は前後を含む3日だけを構築し、離れた月までの全日構築は起きていない。


### 実機の最終結果

- **34種類のUIケースを実機で確認済み**。初回 `device-ui.xcresult` は31成功・3失敗。原因を切り分け、`device-ui-targeted.xcresult` で該当3件と共通日付選択の回帰1件がすべて成功。重複を除く最新結果は34成功・失敗0。
- 日付選択：`PopoverDismissRegion` への汎用タップが背後の「予定」タブに当たり、「一日」のカードが消えた。日付欄の**現在のフレーム**内で閉じるテストへ修正。月表示の日付選択も再確認した。
- 長さ型配置：「読書」の文字が画面下端にあるままドラッグしていた。通常のスクロールでカードを操作可能な範囲へ出してからドラッグするテストへ修正。
- メモ用プリセット：初回はSpringBoardの通知バナー（y=56〜122pt）が入口ボタン（y=73〜117pt）を覆った。XCTestログに `NotificationShortLookView` による未処理の割り込みが残る。同じシナリオを割り込み終了後に実行し、タップ／ドラッグとも追加せず案内することを確認。端末の通知設定は変更していない。
- この追加検証でアプリの動作コードは変更していない（既存Swiftの末尾の空行のみ整理）。テストの操作と検証記録を補正した。
- 通常Release実機ビルド・codesign検証に成功。fixture／計測専用シンボルが含まれないことを確認後、通常版をiPhoneへ再導入し、テスト引数なしで起動。画面も目視確認。
- 原本の実行ログ・結果バンドルは `/private/tmp/liminalog-device-cleanup-20261021/`。集計と代表画面は `artifacts/device-cleanup-20261021/verification.json`、`screenshots/`。旧結果と再検証結果を分けて保存した。
- 保存対象はアプリ・テスト・文書・試作ソース。個人設定と比較画像はローカルに保持したまま除外し、残る差分をこの検証記録と同じチェックポイントに保存する。リモートへのpushは今回の対象外。

---

## 7. 次のバッチ：仕上げ（2026-10-21 Claude 指示）

ブランチ：`codex/ui-polish-dark-qa`（`854e763` から作成済み）。ユーザー方針：**手を動かす作業は Codex、見た目の判断・仕様決めは Claude**。Claude は §7-1 の画像を見て直す点を指定し、§7-3 で最終の画像を確認する。

### 7-1. ダーク／ライトの画面証跡を撮る（優先1・Codex）
新しく入れた画面は、ライト（曙）でしか目視していない。下の状態を**宵（ダーク）と曙（ライト）の両方**で撮り、`design/app-navigation-review-20261005/dark-qa/` に `<番号>-<名前>-dark.png` / `-light.png` で保存する（iPhone 17 / iOS 26.5、等倍の3x PNG）。撮るだけで、見た目の修正はしない。UIテストの `keepScreenshot` を使ってよい。外観は `xcrun simctl ui <udid> appearance dark|light`。テーマはシステム追従（default）のまま。

| # | 画面と状態 | データ |
|---|---|---|
| 01 | カレンダー月表示（日付未選択） | `-LiminalogSeedDevData YES` |
| 02 | 年月を押したシート（日間・週間・月間タブ） | 同上 |
| 03 | 月表示のプリセット（予定タブ／一日タブの2枚） | fixture `-LiminalogUITestTemplateReplacement` |
| 04 | 週表示のドロワー（予定タブ／一日タブ＝追加する日の選択あり） | 同上 |
| 05 | 月から拡大したタイムライン（カテゴリ列のしおり＋縦線が見える状態） | fixture `-LiminalogUITestPlanMemos` |
| 06 | ホーム明日（カテゴリ列のしおり＋縦線） | `-LiminalogSeedDevData YES` |
| 07 | 予定編集：カテゴリ欄を開いた状態（テーブル＋その他）／閉じた状態 | `-LiminalogUITestPlanMemos` |
| 08 | 予定編集：友達に見せる ON（公開相手の行）＋公開相手シート上部 | 同上 |
| 09 | 友達詳細の見え方（控えめ／オフの2枚） | `-LiminalogSeedDevData YES -LiminalogSeedDevFriends YES` |
| 10 | 未来日の一日のまとめ（-- pt・これから・実績タブが薄い） | `-LiminalogSeedDevData YES` |
| 11 | 繰り返し：毎月・曜日で（第2・第4・水曜を選んだ状態） | `-LiminalogUITestPlanMemos` |

### 7-2. 見た目の小さな残り（優先2・Codex が実装。仕様は Claude が決定済み）
1. **一日のまとめの「予定 n」ラベルのアイコン**：`CalendarDayView.swift` の `DayHeaderPill(systemImage: "calendar.badge.clock", text: "予定 …")` を `clock` に変更。`calendar.badge.clock` は一日プリセットの記号に限定する。ここで数えているのは時刻指定の予定（`timedPlans`）なので時計が合う。
2. **カテゴリ選択をそろえる**：チャプター編集（`ChapterEditSheet.swift` L71）と予定プリセット編集（`PlanPresetSettingsView.swift` L584）のカテゴリ行＋`PlanCategoryPickerSheet` を、予定編集と同じ `PlanCategoryInlinePicker` に置き換える。開閉の保存キーは共通の `planEditor.categoryPickerExpanded` でよい。カテゴリ0件のときは従来の行とシートのまま（予定編集と同じ分岐）。チャプター（実績の記録）でも「よく使う順」は予定の作成数のまま使ってよい。
3. **一日のまとめの入口をそろえる**：`CalendarDayView.swift` のツールバーの「＋」メニュー（予定を追加／一日プリセットを適用）を、**しおりボタン＋＋ボタンの2つ**に分ける。＋はメニューを挟まず予定を追加。しおりは月表示と同じプリセットのシート（`CalendarMonthPresetSheet` 相当：ナビバー中央に「予定｜一日」、対象日はこの日で固定＝日付選択なし）を開く。まとめにはタイムラインがないので、予定プリセットは月表示と同じくタップ→時刻指定で追加。並びは `[公開範囲の目] [しおり] [＋]`。

完了条件：各変更の前後をライト／ダークで撮って `dark-qa/` に追加。関係する既存 UI テストが通ること（`-configuration Debug`、自分の Simulator を使う）。

### 7-3. Claude の確認（優先1・2のあと）
Claude が `dark-qa/` の画像を見て、見づらい色・コントラスト・余白を具体値（hex・不透明度・pt）で指定する。直すのは Codex。

### 7-4. ユーザーに確認してもらうこと（Codex・Claude は待つ）
- 実機で、カテゴリ付きの予定編集を手で開いた時の速さ（自動操作では約1.9秒。自動操作の時間を含む）。遅く感じたら Codex の性能タスクにする。
- 週間にメモ用プリセットを置こうとした時の案内文（Codex が実装した文言）。
- X2（同じシートが伸びる拡大）・X3（公開設定の整理）を進めるか。

---

## 8. 仕上げバッチ：Codex 実装と画面証跡（2026-10-21）

### 8-1. 実装

- 一日のまとめの「予定 n」は `clock` に変更。
- チャプター編集・予定プリセット編集で `PlanCategoryInlinePicker` を再利用。開閉は予定編集と同じ保存キー。カテゴリ0件の従来行／シート、チャプターの編集ロックと「カテゴリを外す」は維持した。
- 一日のまとめを `[公開範囲の目] [しおり] [＋]` に統一。＋は編集画面へ直接進む。**月から開くまとめは `CalendarDayPagerSheet` がツールバーを持つため、`CalendarDayView` と両方に反映した。**
- 月のプリセットシートを `CalendarPresetSheet.swift` に切り出して共有。まとめでは対象日を表示中の日に固定し、予定／一日タブを使う。日付を横スワイプしてから開いても、その日へ追加・置換する。取得範囲は日付の先頭へ正規化した。
- まとめには配置先のカレンダーがないため、予定プリセットのドラッグ案内を出さず、タップから時刻指定・追加へ進む。月表示の長押し配置は従来どおり。
- 日ごとに常時取得していた一日プリセットの `@Query` と、旧メニュー専用の状態・取得処理を削除。必要な一覧はプリセットシート内で取得する。

### 8-2. Claude が確認する画面

保存先: `design/app-navigation-review-20261005/dark-qa/`。**全46枚**（全状態をライト／ダークで揃え、変更前後を含む）。**`index.html` が比較一覧**。PNGは iPhone 17 / iOS 26.5 / Debug / 1206×2622px（3x）の原寸。システム追従テーマのまま `simctl ui ... appearance` で切替えた。PNGのリサイズや色加工はしていない。

- `01`〜`11`: §7-1の全状態。予定／一日タブ、カテゴリ開／閉、公開相手行／シート、友達の控えめ／オフは別画像。
- `10`・`12`・`13`: まとめ・チャプター編集・予定プリセット編集の変更前後。変更前は `-before-light.png` / `-before-dark.png`、変更後は `-light.png` / `-dark.png`。
- `14`: まとめの予定／一日プリセットシート（固定日付）の追加画像。
- `screenshots.json`: 各画像の元XCTest添付、撮影段階、寸法、SHA-256。比較画像は既存の方針どおりGit対象外で、ローカルの原本を保持する。画像・索引のバックアップは `artifacts/ui-polish-dark-qa-20261021/dark-qa.tar.gz`。
- `export_evidence.py` / `build_review_index.py`: 原寸添付の取り出しと比較一覧の再生成。撮影テストは `LIMINALOG_CAPTURE_UI=1` 指定時だけ実行し、実機ではスキップする。

**色・不透明度・余白の再設計はしていない。§7-3のClaude確認へ渡せる状態として保存する。**

### 8-3. 検証と残る境界

実行条件は §7 指定のDebug Simulator。実行ログ・xcresult は `/private/tmp/liminalog-polish-20261021/`。通常操作の回帰と、撮影用の操作を分けて記録する。集計は `design/app-navigation-review-20261005/dark-qa/verification.json`。

**Debugビルド成功。UI回帰11種類の最新結果がすべて成功**（`regression`: 10成功／テスト側ラベル指定による1失敗、補正後の `regression-category-final`: 1成功）。最終撮影 `final-capture-light` / `final-capture-dark` は各3件成功。画像46枚の寸法・SHA-256と外観の対を確認し、主要な変更前後を目視した。単体テスト全体の再実行や性能の再計測ではない。

- 既存の月プリセット（固定・長さ・終日・ドラッグ・適用日の変更）、一日プリセット置換、年月／日付からの入口、毎月第○曜日、予定編集の開閉を確認。
- 新規確認: まとめの＋が直接編集を開く、日付移動後の長さプリセットが表示中の日にだけ保存される、一日プリセットの置換も固定日にだけ反映される、予定プリセット編集のカテゴリ保存と予定編集との開閉設定共有。
- 初回の撮影・新規テストでは、アクセシビリティラベルの仮定（`休憩` と実際の `休憩を編集`、`仕事` と実際の `仕事、仕事` など）を補正した。アプリの動作変更でテストを通したものではない。
- Xcodeの新しいテストセッションの初回で、指定した起動先ではなくホーム今日になる既知の症状を再確認した（`before-light-retry` / `after-dark` / `after-light`）。再起動後の起動と、通常の「明日の予定」ボタン経由で必要な画面を撮影した。**起動引数の問題自体の修正完了は主張しない。**
- 今回の実機検証・Release性能測定は実施していない。§7-4の手動の体感確認、X2・X3の判断待ちは維持する。
