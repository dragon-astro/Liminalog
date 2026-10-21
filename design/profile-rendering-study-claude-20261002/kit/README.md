# 装飾キット（コード描画・試作）— 個性カード／フレーム 20対

2026-10-02 / **試作・採用未定**。本体のコード・画像・カタログ・ID・解放条件・課金・設計方針は変更していない。追加したのはこのフォルダだけ。

## 何を作ったか

- 無料の個性装飾 20 対（`ProfileDecorations.swift` の暁線〜夜花。ID・名前・色は本体のまま）を、カードとアバターフレームの両方で SwiftUI Canvas だけで描いた。
- 本体のテーマ（宵＝ダーク／曙＝ライト、`LiminalThemeDefinition.swift` の値）に追従する。宵は発光と加算合成、曙は同じ色相の深い墨色と暖色の影（golden hour）で描く。
- 全モチーフで同じ文法を使う：テーマの地をアイテム色で染める → 角の空気 → 粒 → 二重罫と頂部／底部の飾り → 角と縁だけに装飾 → 本文列の「読む場所」。
- `DecoFrameView(id:size:scheme:)` は本体の `ProfileIconFrameView(size:)` と同じ寸法規則（size×1.12、リング中心線＝アバター境界）。`DecoCardView` は渡された矩形にそのまま描く。

## 見てほしいもの

| | ファイル |
|---|---|
| 20種のヒーロー一覧（宵／曙） | [renders/lineup-dusk.png](renders/lineup-dusk.png) / [renders/lineup-daybreak.png](renders/lineup-daybreak.png) |
| 既存PNG（参考）と並べた一覧サイズ比較 | [renders/compare-grid-1.png](renders/compare-grid-1.png) / [renders/compare-grid-2.png](renders/compare-grid-2.png) |
| 1種ずつの確認（ヒーロー・24/32/48pt・一覧・既存PNG） | `renders/motif-*.png` |
| iOSシミュレータ | [renders/ios/](renders/ios/) |
| 数値検査 / 描画時間 | [renders/validation.json](renders/validation.json) / [renders/timing.txt](renders/timing.txt) |

## 確認できたこと

- **数値検査**（40フレーム・40カード）：フレーム外周の切れ 0。中心の透過は最小 0.79（墨縁の起筆。既存PNGは 0.70〜0.74 なので顔の隠れは少ない）。カード本文列のコントラスト（5パーセンタイル）は主文字 ≥ 10.9、副文字 ≥ 4.5（全40枚）。
  - 途中で、一覧での見分けのために地を染めた結果、宵の副文字が全カードで 3:1 を割った（最低 1.3）。本文列の背後だけテーマの地に戻す「読む場所」を足して直した。数値検査で見つかった実例。
- **大きな文字**：カードが Dynamic Type を読み、読む場所を本文の大きさに合わせて伸ばす（画像ではできない調整）。AX1 の波端で、本文と波頭の衝突は「読める」まで改善。ただし模様はまだ薄く透けて見える。
- **描画時間**（macOS・ImageRenderer。実機ではない）：フレーム 82pt@3x 中央値 0.9ms（最大 葉隅 9.6ms）、カード 350pt 中央値 2.8ms（最大 5.4ms）。表示サイズごとに一度ラスタライズして使い回す簡易キャッシュ（`DecoRasterCache`）で 2回目以降 0.1ms。
- **環境**：macOS 書き出しと iPhone 17 / iOS 27.0 シミュレータ（`simctl` で起動・撮影）で一致。**実機は未確認**。

## 残った課題（率直に）

1. **一覧サムネイルの識別性は既存PNGに負ける**。PNGはカード全面が鮮やかな一色の世界で、120×75 でも一目で分かる。コード版はテーマの地（宵＝暗、曙＝クリーム）に従うため、地を染めても控えめ。同系色のもの（水縁・雨粒・波端／糸枠・織目・霧面）は小さいと見分けにくい。霧面は小さいと特に弱い。
2. **筆致**：葉・花・雲・炎は「上質なイラスト」止まりで、生成画像の水彩・箔・質感の豊かさには届かない。拡大表示（詳細 228×142、フレーム 164pt）ほど差が出る。
3. 葉隅のフレームは描画が重め。実用にはキャッシュが前提。
4. フレームの外接枠の中心は、意図した非対称（房・垂れ玉・太陽）で最大 42px（1024px換算）ずれる。リング自体は構造上ちょうど中心。旧規格の ±2px は満たさない。
5. 輪が一周しないもの（墨縁・夜花・花隅・石径）は意図的。
6. 未確認：実機、他のアバター色、AX1 より大きい文字、本体への組み込み（友達画面・コレクション）。`renders/compare-grid-*` は「読む場所」を足す前の描画（一覧サイズでは読む場所を描かないので見た目は同じ）。

## 判断（試作としての所見）

- **カード：有望**。テーマ追従・文字の読みやすさ・文字サイズへの追従は、画像より確実にできる。ただし「一枚の絵として欲しくなる」華やかさと、一覧での一目の識別は既存PNGが上。
- **フレーム：有望**。24〜82pt では形がはっきり読め、20種が別物として見分けられる。拡大時の質感は画像が上。
- 全面置換より、「テーマ追従と可読性はコード、絵としての華は画像」という役割分担の検討材料になる。

## 再現

```sh
zsh design/profile-rendering-study-claude-20261002/kit/render.sh motif      # 1種ずつの確認シート（id 指定可）
zsh design/profile-rendering-study-claude-20261002/kit/render.sh lineup     # 一覧
zsh design/profile-rendering-study-claude-20261002/kit/render.sh grid       # 既存PNGとの比較
zsh design/profile-rendering-study-claude-20261002/kit/render.sh plain      # 検査用
python3 design/profile-rendering-study-claude-20261002/kit/validate.py
zsh design/profile-rendering-study-claude-20261002/kit/build-simulator.sh  # iOSプレビュー（-scheme / -page / -bigText / -start / -motif）
```

ファイル：`KitCore`（土台）、`KitTheme`（宵／曙・アイテム色）、`KitCardBase`（カードの共通文法・読む場所）、`KitViews`（公開ビュー・キャッシュ）、`KitCatalog`（ID→描画）、`KitBotanical` / `KitCelestial`（部品）、`Motif*.swift`（20種）、`KitStudyViews` / `KitRender` / `KitPreviewApp`（確認用）。
