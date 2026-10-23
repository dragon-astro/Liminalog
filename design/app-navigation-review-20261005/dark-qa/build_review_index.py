"""Build a local comparison index from screenshots.json; original PNGs stay intact."""
import html
import json
from pathlib import Path

root = Path(__file__).resolve().parent
images = json.loads((root / 'screenshots.json').read_text())
labels = {
 '01-month': '月表示・日付未選択', '02-period': '年月と表示切替',
 '03-month-plan-presets': '月・予定プリセット', '03-month-day-presets': '月・一日プリセット',
 '04-week-plan-presets': '週・予定プリセット', '04-week-day-presets': '週・一日プリセット',
 '05-expanded-timeline': '月から開くタイムライン', '06-home-tomorrow': 'ホーム明日',
 '07-category-open': '予定編集・カテゴリを開く', '07-category-closed': '予定編集・カテゴリを閉じる',
 '08-public-audience-row': '予定編集・公開相手', '08-public-audience-sheet': '公開相手シート',
 '09-friend-limited': '友達詳細・控えめ', '09-friend-off': '友達詳細・オフ',
 '10-future-summary': '未来日のまとめ・時計とツールバー', '11-monthly-weekday': '毎月・第2／第4水曜',
 '12-chapter-category': 'チャプター編集・カテゴリ', '13-preset-category': '予定プリセット編集・カテゴリ',
 '14-summary-plan-presets': 'まとめ・予定プリセット（日付固定）',
 '14-summary-day-presets': 'まとめ・一日プリセット（日付固定）',
 '15-recurrence-selection': '繰り返し・選択中の枠と文字色',
 '16-friend-off': '友達詳細・オフ時の読みやすさ',
 '17-category-chevron-open': 'カテゴリ矢印・開いた状態',
 '17-category-chevron-closed': 'カテゴリ矢印・閉じた状態',
 '18-recurrence-weekly': '繰り返し・普段の毎週設定',
 '18-recurrence-monthly-collapsed': '繰り返し・毎月の詳細を閉じた状態',
 '20-recurrence-weekly': '繰り返し・毎週',
 '20-recurrence-monthly-date': '繰り返し・毎月10日',
 '20-recurrence-monthly-weekday': '繰り返し・毎月第2／第4水曜',
 '20-recurrence-yearly': '繰り返し・毎年',
 '20-recurrence-ending-count': '繰り返し・間隔／開始日／終了を開く',
 '21-underline-tabs-filter': '下線タブ・カレンダー表示フィルタ',
 '21-underline-tabs-profile': '下線タブ・プロフィール編集',
 '21-underline-tabs-ranking': '下線タブ・ランキングの期間',
 '22-recurrence-rows-weekly': '繰り返し・毎週／終了しない',
 '22-recurrence-rows-monthly-weekday': '繰り返し・毎月第2／第4水曜と設定行',
 '22-recurrence-rows-count': '繰り返し・回数で終了',
 '22-recurrence-rows-date': '繰り返し・日時で終了',
 '22-recurrence-rows-se-date': 'iPhone SE・12か月ごと／日時で終了',
 '23-editor-main': '予定編集・メイン予定',
 '23-editor-memo': '予定編集・メモと重要の切替',
 '23-editor-category-paging': '予定編集・カテゴリテーブルの横移動',
 '24-sample-plan-presets': '開発サンプル・予定プリセット',
 '24-sample-day-presets': '開発サンプル・一日プリセットの選択',
 '23-editor-se-main': 'iPhone SE・メイン予定',
 '23-editor-se-memo': 'iPhone SE・予定メモ',
 '23-editor-se-category-paging': 'iPhone SE・カテゴリの横移動',
 '24-sample-se-plan-presets': 'iPhone SE・予定プリセット',
 '24-sample-se-day-presets': 'iPhone SE・一日プリセットの選択',
 '25-editor-polish-memo': '予定メモ・破線の印と予定名のしおり',
 '25-editor-polish-category-before': 'カテゴリ横移動前・表にないその他',
 '25-editor-polish-category-after': 'カテゴリ横移動後・その他は共通',
 '25-editor-polish-values': '通知と繰り返し・灰色の入力欄',
 '25-editor-polish-custom-reminder': '通知・任意の分数と前後の指定',
 '25-editor-polish-se-memo': 'iPhone SE・予定メモとしおり',
 '25-editor-polish-se-values': 'iPhone SE・通知と繰り返しの入力欄',
 '26-preset-editor-upper': '予定プリセット編集・タイトルから通知',
 '26-preset-editor-lower': '予定プリセット編集・繰り返しからメモと削除',
 '26-preset-editor-public': '予定プリセット編集・公開オンでも文言は固定',
 '26-chapter-visibility': 'チャプター編集・友達に見せるをオフ',
 '26-preset-editor-se-lower': 'iPhone SE・予定プリセット編集の下半分',
}
body = []
for stem, label in labels.items():
    figures = []
    for phase in ('before', 'after') if stem.startswith(('10-', '12-', '13-')) else ('after',):
        for appearance, title in [('light', '曙'), ('dark', '宵')]:
            name = f'{stem}{"-before" if phase == "before" else ""}-{appearance}.png'
            if name not in images:
                continue
            caption = f'{"変更前・" if phase == "before" else ""}{title}'
            escaped = html.escape(name)
            width, height = images[name]['pixels']
            figures.append(f'<figure><figcaption>{caption}</figcaption><a href="{escaped}"><img loading="lazy" width="{width}" height="{height}" src="{escaped}" alt="{html.escape(label)}・{caption}"></a></figure>')
    if figures:
        body.append(f'<section id="{stem}"><h2>{stem[:2]} {label}</h2><div class="pairs">{"".join(figures)}</div></section>')
page = '''<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Liminalog 画面証跡 — 2026-10-23</title><style>
body{margin:24px auto;padding:0 24px;max-width:1320px;background:#eeeeef;color:#222;font:16px/1.7 system-ui,sans-serif}h1{font-size:24px}h2{font-size:19px;margin-top:36px}.pairs{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:18px;align-items:start}figure{margin:0}figcaption{margin:0 0 8px}img{width:100%;height:auto;border:1px solid #bbb;border-radius:12px;background:#fff}section{border-top:1px solid #ccc;margin-top:28px}p{max-width:900px}a{color:inherit}
</style><h1>ライト／ダーク画面の確認</h1><p>docs/37 §7・§12・§15・§17・§18・§22 — iOS 26.5 / Debug。システム追従テーマ。iPhone 17は原寸1206×2622px（3x）、SEは750×1334px（2x）。PNGの加工なし。クリックで原寸。10・12・13は変更前後、その他は指定状態の画面記録です。15〜20はこれまでの繰り返し欄、21は下線タブ、22は間隔・開始日・終了を常時表示する構成です。23はメモ切替とカテゴリ横移動、24は開発サンプル、25は編集画面の仕上げ（印・しおり・その他・灰色の入力欄）、26は公開スイッチの文言と予定プリセット編集の並びをそろえた状態です。</p>
'''
(root / 'index.html').write_text(page + '\n'.join(body) + '</html>\n')
print(f'Indexed {len(images)} screenshots')
