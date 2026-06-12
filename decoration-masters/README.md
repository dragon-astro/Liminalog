# decoration-masters — 装飾アートのマスター管理

プロフィール装飾（カードパネル・アイコンフレーム）の**原寸マスターPNG**置き場。
アプリに出荷されるのはここから縮小生成した画像で、このフォルダ自体はビルドに含まれない。

## なぜ分けているか

- 生成時は 2048px 等の大きい解像度で作るのが安定する（位置調整・透過処理もしやすい）
- しかし原寸のまま `Assets.xcassets` に入れると DL サイズが 90MB 超になる
- iPhone の実表示は最大でもカード幅 ≒ 1224px(@3x) なので、出荷は縮小版で画質劣化ゼロ
- 将来 iPad などで高解像度が必要になったら、マスターから出荷解像度を上げるだけで対応できる

## ディレクトリ構成と命名

| フォルダ | 内容 | マスター解像度 | 出荷解像度 | 命名 |
|---|---|---|---|---|
| `Cards/` | プロフィールカードのパネル背景 | 2048×1365 | 幅1280px | `profile_card_<id>_panel.png` |
| `Frames/` | アイコンフレーム | 1024×1024 | 1024×1024 | `profile_frame_<id>.png` |

- ファイル名は imageset 名・アセット名と完全一致させる（コード側は
  [ProfileDecorations.swift](../Liminalog/Views/Profile/ProfileDecorations.swift) の
  `artworkAssetName` が `profile_card_<id>` / `profile_frame_<id>` を参照）
- 課金/無料の語彙ルールは `Liminalog/Views/Profile/docs/09-profile-design.md` を参照

## 新しい装飾を追加する手順（AI向け・人間向け共通)

1. **生成**: 既存マスターと同じ解像度・透過仕様で画像を作る
2. **配置**: 完成したPNGを `decoration-masters/Cards/` または `Frames/` に置く
   - ⚠️ `Assets.xcassets/ProfileDecorations/` 配下に直接置かない
3. **変換**: リポジトリルートで実行

   ```bash
   Scripts/generate-decoration-assets.sh                # 全件（冪等・既存は上書き）
   Scripts/generate-decoration-assets.sh aurora_trace   # 名前を含むものだけ
   ```

   imageset が無ければ Contents.json ごと自動生成される
4. **コード登録**: `ProfileDecorations.swift` のカタログに id を追加（既存項目に倣う）
5. **確認**: ギャラリー画面（プロフィール → コレクション）で表示確認

## 禁止事項

- `Assets.xcassets/ProfileDecorations/**/*.png` を直接編集・差し替えしない
  （スクリプトの生成物。次回実行で上書きされる）
- マスターを縮小して置かない（原寸のまま置く。縮小はスクリプトの仕事）
- マスターの削除は imageset 側の削除・コード側のカタログ削除とセットで行う

## 既存装飾を差し替える場合

同名のPNGをマスターに上書き → スクリプト実行、の2手で終わり。
