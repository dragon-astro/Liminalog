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
 '27-editor-main': '予定編集・先頭カードを1行に',
 '27-editor-memo': '予定編集・1行で重要とメモを切替',
 '27-preset-editor-main': '予定プリセット編集・先頭カードを1行に',
 '27-preset-editor-memo': '予定プリセット編集・1行でメモを切替',
 '27-editor-se-main': 'iPhone SE・予定編集の先頭カード',
 '27-editor-se-memo': 'iPhone SE・予定編集の重要とメモ',
 '27-preset-editor-se-main': 'iPhone SE・プリセット編集の先頭カード',
 '27-preset-editor-se-memo': 'iPhone SE・プリセット編集のメモ',
 '28-title-se-plan-input': 'iPhone SE・長い予定名の入力中',
 '28-title-se-plan-caret': 'iPhone SE・予定名の途中をタップして修正',
 '28-title-se-plan-reopened': 'iPhone SE・長い予定名を保存して再編集',
 '28-title-se-preset-input': 'iPhone SE・長いプリセット名の入力中',
 '28-title-se-preset-caret': 'iPhone SE・プリセット名の途中を修正',
 '28-title-se-preset-reopened': 'iPhone SE・プリセット名を保存して再編集',
 '29-editor-se-main': 'iPhone SE・先頭カードのアイコン間隔を調整',
 '29-editor-se-memo': 'iPhone SE・間隔調整後の重要とメモ',
 '29-preset-editor-se-main': 'iPhone SE・プリセットのアイコン間隔を調整',
 '29-preset-editor-se-memo': 'iPhone SE・間隔調整後のプリセットメモ',
 '29-title-se-plan-input': 'iPhone SE・間隔調整後の長い予定名の入力',
 '29-title-se-plan-caret': 'iPhone SE・間隔調整後の予定名の途中修正',
 '29-title-se-plan-reopened': 'iPhone SE・間隔調整後の予定名を再編集',
 '29-title-se-preset-input': 'iPhone SE・間隔調整後の長いプリセット名',
 '29-title-se-preset-caret': 'iPhone SE・間隔調整後のプリセット名の途中修正',
 '29-title-se-preset-reopened': 'iPhone SE・間隔調整後のプリセット名を再編集',
 '30-editor-se-main': 'iPhone SE・短い予定名は1行のまま',
 '30-editor-se-memo': 'iPhone SE・1行表示で重要とメモを切替',
 '30-preset-editor-se-main': 'iPhone SE・短いプリセット名は1行のまま',
 '30-preset-editor-se-memo': 'iPhone SE・1行表示のプリセットメモ',
 '30-title-se-plan-input': 'iPhone SE・長い予定名を折り返して入力',
 '30-title-se-plan-expanded': 'iPhone SE・さらに長い予定名も高さを広げる',
 '30-title-se-plan-caret': 'iPhone SE・折り返した予定名の途中を修正',
 '30-title-se-plan-reopened': 'iPhone SE・折り返した予定名を再編集',
 '30-title-se-preset-input': 'iPhone SE・長いプリセット名を折り返して入力',
 '30-title-se-preset-expanded': 'iPhone SE・さらに長いプリセット名も高さを広げる',
 '30-title-se-preset-caret': 'iPhone SE・折り返したプリセット名の途中を修正',
 '30-title-se-preset-reopened': 'iPhone SE・折り返したプリセット名を再編集',
 '30-title-plan-input': '予定編集・長い名前を折り返して入力',
 '30-title-plan-expanded': '予定編集・さらに長い名前も高さを広げる',
 '30-title-plan-caret': '予定編集・折り返した名前の途中を修正',
 '30-title-plan-reopened': '予定編集・折り返した名前を再編集',
 '30-title-preset-input': '予定プリセット・長い名前を折り返して入力',
 '30-title-preset-expanded': '予定プリセット・さらに長い名前も高さを広げる',
 '30-title-preset-caret': '予定プリセット・折り返した名前の途中を修正',
 '30-title-preset-reopened': '予定プリセット・折り返した名前を再編集',
 '31-palette-se-month': 'iPhone SE・月間からのタイムラインでカテゴリ左端を表示',
 '31-palette-se-tomorrow': 'iPhone SE・ホーム明日のカテゴリ左端を表示',
 '31-presets-se-kinds': 'iPhone SE・すべての白文字とプリセットの操作の印',
 '31-locked-se-empty-memo': 'iPhone SE・ロック日の空き時間からメモを重ねる',
 '31-locked-se-overlap-memo': 'iPhone SE・選択済みのロック予定にも短いメモを追加',
 '31-palette-month': '月間からのタイムラインでカテゴリ左端を表示',
 '31-palette-tomorrow': 'ホーム明日のカテゴリ左端を表示',
 '31-presets-kinds': '予定プリセット・固定時刻と長さ指定の操作の印',
 '31-locked-empty-memo': 'ロック日の空き時間からメモを重ねる',
 '31-locked-overlap-memo': '選択済みのロック予定にも短いメモを追加',
 '32-editor-toolbar-unchanged': '編集・変更なし',
 '32-editor-toolbar-changed': '編集・変更あり・保存を強調',
 '32-editor-toolbar-discard': '編集・破棄の確認',
 '32-editor-toolbar-menu': '編集・その他の操作',
 '32-editor-toolbar-preset-bottom': '編集・プリセット下部・削除カードを撤去',
 '33-preset-editor-upper': '予定プリセット編集・上半分',
 '33-preset-editor-lower': '予定プリセット編集・下半分',
 '34-month-past': '月間・過ぎた予定の薄さ',
 '34-month-time': '月間・開始時刻オン',
 '34-month-strike': '月間・時刻と打ち消し線',
 '32-editor-toolbar-se-unchanged': 'iPhone SE・編集・変更なし',
 '32-editor-toolbar-se-changed': 'iPhone SE・編集・変更あり・保存を強調',
 '32-editor-toolbar-se-discard': 'iPhone SE・編集・破棄の確認',
 '32-editor-toolbar-se-menu': 'iPhone SE・編集・その他の操作',
 '32-editor-toolbar-se-preset-bottom': 'iPhone SE・編集・プリセット下部・削除カードを撤去',
 '33-preset-editor-se-upper': 'iPhone SE・予定プリセット編集・上半分',
 '33-preset-editor-se-lower': 'iPhone SE・予定プリセット編集・下半分',
 '34-month-se-past': 'iPhone SE・月間・過ぎた予定の薄さ',
 '34-month-se-time': 'iPhone SE・月間・開始時刻オン',
 '34-month-se-strike': 'iPhone SE・月間・時刻と打ち消し線',
 '34-month-aurora-past': '極光・月間・過ぎた予定の薄さ',
 '34-month-aurora-time': '極光・月間・開始時刻オン',
 '34-month-aurora-strike': '極光・月間・時刻と打ち消し線',
 '33-preset-recent': '予定プリセット・最近の予定から選ぶ',
}
# docs/38 second batch; previous image records remain unchanged.
next_labels = {
    '32b-editor-toolbar': {'partial-unchanged': '半開き・変更なし', 'partial-changed': '半開き・変更あり', 'full-unchanged': '全開・変更なし', 'full-changed': '全開・変更あり'},
    '32c-editor-bookmark': {'saved': 'しおりで保存した反応', 'menu': 'プリセットから入れるメニュー'},
    '33b-preset-editor': {'upper': '予定プリセット・区切り線を外した時刻欄'},
    '35-actual': {'edit': '実績編集', 'active': '記録中の実績', 'new-empty': '実績追加・カテゴリ未選択', 'new-selected': '実績追加・カテゴリ選択後', 'delete': '実績を削除する確認', 'empty': '実績を削除した後の空状態'},
    '36-detail': {'title-input': '予定名の入力中・操作ボタンを畳む', 'preset-title-input': 'プリセット名の入力中', 'wheel': '行内の日付ホイール', 'narrow-memos': 'メモの幅に応じた文字・印・枠の表示'},
    '37-plan-extra': {'editor': '場所・URLの入力', 'drawer': '月間ドロワーの場所・URL', 'friend': '友達のカレンダーの場所・URL'},
}
for group, states in next_labels.items():
    for suffix, device in [('', ''), ('-se', 'iPhone SE・'), ('-aurora', '極光・')]:
        for state, label in states.items():
            labels[f'{group}{suffix}-{state}'] = device + label

body = []
for stem, label in labels.items():
    figures = []
    for phase in ('before', 'after') if stem.startswith(('10-', '12-', '13-')) else ('after',):
        for appearance, title in [('light', '曙'), ('dark', '宵')]:
            name = f'{stem}{"-before" if phase == "before" else ""}-{appearance}.png'
            if name not in images:
                continue
            caption = f'{"変更前・" if phase == "before" else ""}{"極光" if "-aurora-" in stem else title}'
            escaped = html.escape(name)
            width, height = images[name]['pixels']
            figures.append(f'<figure><figcaption>{caption}</figcaption><a href="{escaped}"><img loading="lazy" width="{width}" height="{height}" src="{escaped}" alt="{html.escape(label)}・{caption}"></a></figure>')
    if figures:
        body.append(f'<section id="{stem}"><h2>{stem[:2]} {label}</h2><div class="pairs">{"".join(figures)}</div></section>')
page = '''<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Liminalog 画面証跡 — 2026-10-26</title><style>
body{margin:24px auto;padding:0 24px;max-width:1320px;background:#eeeeef;color:#222;font:16px/1.7 system-ui,sans-serif}h1{font-size:24px}h2{font-size:19px;margin-top:36px}.pairs{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:18px;align-items:start}figure{margin:0}figcaption{margin:0 0 8px}img{width:100%;height:auto;border:1px solid #bbb;border-radius:12px;background:#fff}section{border-top:1px solid #ccc;margin-top:28px}p{max-width:900px}a{color:inherit}
</style><h1>ライト／ダーク画面の確認</h1><p>docs/37 §7・§12・§15・§17・§18・§22・§24・§25・§26・§27・§28 — iOS 26.5 / Debug。システム追従テーマ。iPhone 17は原寸1206×2622px（3x）、SEは750×1334px（2x）。PNGの加工なし。クリックで原寸。10・12・13は変更前後、その他は指定状態の画面記録です。15〜20はこれまでの繰り返し欄、21は下線タブ、22は間隔・開始日・終了を常時表示する構成です。23はメモ切替とカテゴリ横移動、24は開発サンプル、25は編集画面の仕上げ（印・しおり・その他・灰色の入力欄）、26は公開スイッチの文言と予定プリセット編集の並びをそろえた状態、27は先頭カードを1行にまとめた状態、28はSEで長い予定名を入力・修正した検証画面、29は先頭カードのアイコン間隔を少し詰めた状態、30は長い予定名を折り返して入力欄が縦に広がる状態、31はカテゴリ左端・ロック日のメモ追加・プリセットの印を直した状態です。32〜34はdocs/38の初回実装、32b・32c・33b・35〜37は追加仕様の実装後（2026-10-26）。以前の画像は比較用にそのまま残しています。</p>
'''
(root / 'index.html').write_text(page + '\n'.join(body) + '</html>\n')
print(f'Indexed {len(images)} screenshots')
