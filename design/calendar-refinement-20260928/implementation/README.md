# 当日ドロワーの入口整理 — 実装画面

2026-09-28。ユーザーが承認した文章ベースの仕様を、既存のSwiftUI画面へ反映した記録。隣接する初回3案の生成画像とは別で、その案は採用していない。

| 画面 | 内容 |
| --- | --- |
| [当日ドロワー](01-drawer.png) | 日付からまとめ、時間軸アイコンからタイムライン。予定／一日プリセットは見出しのアイコン |
| [一日のまとめ](02-summary.png) | Homeと共通の既存デザインを維持 |
| [タイムライン](03-timeline.png) | 表示切替を挟まず直接開く |
| [文字拡大](04-accessibility-text.png) | 日付と操作列を分け、重なりを避ける |
| [実機の当日ドロワー](05-device-drawer.png) | iPhone 16 / iOS 26.6.2 / Releaseのダーク表示 |
| [実機のタイムライン](06-device-timeline.png) | 月の上に直接開いたタイムライン |

01〜04はiPhone 17 / iOS 26.5 Simulator、05〜06はiPhone 16実機の隔離fixture。実データや速度の測定結果ではない。

検証ログ: `/private/tmp/liminalog-calendar-entry-20260928/`。
`regression.xcresult`の10件と`header-final.xcresult`の3件が成功（重複を除き12種類）。入口、文字拡大、詳細の高さ・見出し／余白からの戻り、タイムラインで作成・移動・伸縮、日付移動後のプリセット適用、一覧から別日移動、月間で長さ型・終日・一日プリセットを確認した。

`device-retry.xcresult`で実機Releaseの8件も成功。通常Releaseへ戻し、テスト引数なしで起動を確認した。詳しくは [仕様と検証記録](../../../Liminalog/Views/Profile/docs/35-calendar-interaction-refinement.md)。実指での操作感と自動UI検証は区別する。
