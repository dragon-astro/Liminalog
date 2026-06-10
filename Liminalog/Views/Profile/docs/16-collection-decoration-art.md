# 16. コレクション装飾 アートディレクション（フレーム/カード）

コレクション（[UnlockGalleryView]）のアイコンフレーム・プロフィールカードの**装飾意匠**の決定版ブリーフ。
前提：[13-visual-identity.md](13-visual-identity.md)（世界観・トワイライト・パレット・優先度）、[09-profile-design.md](09-profile-design.md)（装飾アイテム経済）。

> **読み手（Codex）へ**：本書は「装飾の見た目」だけを対象とする。ID・解放スケジュール（[../../../Logic/UnlockRules.swift]）・装備中アイテム・テーマトークンの仕組みは**壊さない**。現行実装は `Assets.xcassets/ProfileDecorations` の生成PNGを正とし、`ProfileIconFrameView` / `ProfileDecoratedCardBackground` は画像がない場合だけベクター描画へフォールバックする。

---

## 0. 北極星（一言で）

**「暗めの余白」×「澄んだ差し色」×「控えめな報酬感」×「豊かなモチーフ」。**

- ベース（地・空気・色・静けさ）は **liminal/twilight**（doc 13）。
- そこに乗せる装飾は、**モチーフ自体は豊か**にする。ただし密度・発光・金属感を盛りすぎない。
- 参考素材の形をそのまま「Liminalog風」に変換しようとしすぎない。まず装飾単体として欲しくなる空気を作り、最後に色・密度・余白をLiminalogへ寄せる。
- 白地＋多色の「可愛い素材集」そのままは禁止。ただし植物リースのような構造は有効。**ポップな構造を、澄んだ夜空と発光色へ翻訳する**。

### 一行で判断基準
> 「**暗い余白の中に、澄んだ色で丁寧に描かれた報酬装飾**」に見えるか？
> 量産バッジでも、素材集の花枠でも、ファンタジー宝飾でもない。

---

## 0.1 2026-06 生成ナレッジ（コンテキスト復旧用）

装飾案の探索で分かった、次回以降の生成・実装判断のメモ。

### 掴めた好み

- 良い軸は **暗めの余白 + 澄んだ差し色 + 控えめな報酬感 + モチーフはちゃんと豊か**。
- 「Liminalogらしさ」を狭く見すぎると、既存UIの弱点（単調なグロー、少しダサい記号感、薄い装飾密度）だけを増幅してしまう。
- まず「装飾として欲しくなるか」を優先し、最後にLiminalogの色・余白・発光量へ調整する。
- 花モチーフは有効。ただし宝石フレームの星/月を花へ置き換えるだけでは違う。**植物の輪・蔓・葉・小花で余白を作る構造**をベースにする。
- 豪華すぎると浮く。密度と発光は抑え、色はくすませすぎない。**形は控えめ、色は澄ませる**。
- Liminalogらしい色は、くすんだセージ/オリーブよりも、クリアな violet / lavender / cyan-blue / emerald-teal / soft rose / dawn orange が合う。

### 避ける方向

- ❌ 既存Liminalogに囚われすぎた、単線リング + 小さい記号 + 紫グローだけの案。
- ❌ 星/月/宝石の位置だけを花に差し替える案。モチーフの構造が変わっていないため「位置を変えただけ」に見える。
- ❌ 立体感が強いガラス/鉱石/織物。中位装飾としては浮きやすい。
- ❌ 花を可愛い素材集、結婚式招待状、白地ポップベクターのまま扱うこと。
- ❌ 色を落ち着かせようとして、全体がくすみすぎること。Liminalogには澄んだ発光色が必要。
- ❌ 豪華さを金属・星・宝石だけに寄せること。単調になる。

### 当たりに近かった生成物

- `artifacts/collection-decoration-concepts/alternative-motifs/floral-calm-wreath-board-03-liminalog-color.png`
  - 現時点の花/植物リース方向の基準。
  - 植物の輪っか構造、控えめな装飾密度、Liminalogらしい澄んだ色のバランスが良い。
- `artifacts/collection-decoration-concepts/alternative-motifs/icon-frame-motif-genres-01.png`
  - 花以外のモチーフ展開の基準。
  - 雲/空気感、結晶、水紋、刺繍、金継ぎ、天文図、月桂冠、タイムライン軌道が候補。
- `artifacts/collection-decoration-concepts/luxury-levels/luxury-level-board-01.png`
  - 豪華度の段階比較として有用。
  - 1列目は低めランク、2列目は現時点の最上級くらい。今後さらに上位を追加する余地は残す。

### 生成プロンプトの方向

良かった方向の核：

```text
calm but polished profile icon frame decorations for an iOS profile collection/reward system,
deep midnight purple/navy background,
clean luminous Liminalog-like colors,
moderate decoration density,
refined reward feeling,
open empty center,
crisp vector-like illustration,
gentle app glow,
not overly luxurious,
not dusty,
not childish clipart
```

植物系なら：

```text
botanical wreaths with open empty centers,
sparse asymmetrical vines, leaves, small flowers, berries, soft pollen dots,
clear luminous violet, lavender, cyan-blue, emerald teal, soft rose, dawn orange,
avoid dusty gray-green, beige dominance, bright primary yellow, neon green, heavy gold, metal stars, moon symbols, gemstones
```

花以外のモチーフ候補：

- **雲/空気感**：soft cloud arcs, airy light strokes, dawn glow
- **結晶/雪**：delicate crystalline facets, frost lines, clear violet/blue
- **水紋/波**：circular wave rings, fluid teal-blue strokes
- **刺繍/糸**：fine woven arcs, tiny stitch details, textile reward feel
- **金継ぎ/漆**：dark lacquer ring, thin luminous repair veins, restrained amber
- **天文図**：orbit lines, calibration marks, tiny dots, no obvious star motif
- **月桂冠**：refined leaves, achievement wreath, not military
- **タイムライン軌道**：ticks, nodes, progress arcs, app-specific identity

### 実装へ落とす時の考え方

- ランク低め：雲、葉、水紋、細いタイムライン目盛り。密度は低く、色の鮮度で魅せる。
- 中位：花リース、刺繍、天文図、結晶。形の個性を出す。
- 上位：金継ぎ、複層タイムライン軌道、強めの結晶、植物リースの完成形。金/amberは微量。
- カード装飾は「右上アイコン」ではなく、**カードの縁・角・内側の薄い模様**で変化を出す。
- 装着ボタンの文言や色はアイテムごとに変えず、テーマカラーに統一する方が視認性が高い。

---

## 0.2 2026-06-05 実装メモ（重要）

ユーザー確認で、SwiftUI Path で再現した装飾は「生成した画像」ではなく、求める質感から外れると判断された。以後、フレーム/カード装飾の本体は**生成PNGアセット**を使う。

> ⚠️ **2026-06 更新（§11.4）**：この「生成PNG優先・ベクターはフォールバック」は**旧・全有機モチーフ前提**。獲得フレームを「達成メダル（金属/幾何）」へ転換したため、**獲得はベクター主（`EarnedEmblemFrame`）へ反転**した。本節は**プレミアム（自然作品）にのみ適用**。詳細は §11。

- フレーム画像：`Liminalog/Assets.xcassets/ProfileDecorations/Frames/profile_frame_*.imageset`
- カード画像：`Liminalog/Assets.xcassets/ProfileDecorations/Cards/profile_card_*.imageset`
- 旧生成元：`artifacts/collection-decoration-concepts/generated-assets/frame-sprite-source.png` / `card-sprite-source.png`
- 旧透明化後：`frame-sprite-alpha.png` / `card-sprite-alpha.png`
- 旧QA用一覧：`generated-frame-assets-preview.png` / `generated-card-assets-preview.png`
- フレーム新生成仕様：`artifacts/collection-decoration-concepts/generated-assets/highres-frames/frame-generation-manifest.json`
- フレーム取り込み：`artifacts/collection-decoration-concepts/generated-assets/highres-frames/process_icon_frame.py`
- フレーム新QA用一覧：`artifacts/collection-decoration-concepts/generated-assets/highres-frames/corrected-frame-preview-dark.png`

実装上の原則：

- `ProfileIconFrameStyle.artworkAssetName` / `ProfileCardStyle.artworkAssetName` の画像を優先表示する。
- ベクター装飾は欠損時のフォールバックに留める。
- カードは右上アイコンで差を出さず、生成カードの縁・角・内側模様で差を出す。
- 解像度基準は **フレーム 1024x1024px**、**カードは横2048px以上**。
- フレームは **1アイテムにつき1枚の単体生成画像**を使う。小さいスプライトシートから切り出して拡大する運用は禁止。
- 生成時は `#00ff00` の単色クロマキー背景にし、`process_icon_frame.py <frame_id> <source.png>` で透明化・1024正規化・asset catalog反映まで行う。
- 2026-06-06時点で全21個のフレームを単体生成から1024化済み。`audit_icon_frames.py` で `OK 21 / BAD 0` を確認する。
- 直近の指摘として、植物系に寄りすぎないこと。今後の追加・差し替えでも、空気/水/霜/糸/天文図/金継ぎ/漆/陶器/潮硝子/時刻軌道/オーロラ/プリズム/雪/熱/控えめな月桂光のように、ジャンルを分散させる。

---

## 0.3 フレーム生成の共通規格（無料/有料を問わない）

獲得装飾（無料）/ プレミアム装飾（有料）に関係なく、プロフィール画像フレームを生成・差し替えする時は本節を優先する。狙いは、**サイズの安定・透過品質・再現性・同一デザインファミリー維持**。

### 最終アセット規格

- 最終フレームは **1アイテム = 1枚の 1024x1024px 透過PNG**。
- 中央のアバター領域は完全透過。四隅も完全透過。
- フレームはアバター境界の**内外にまたがる**。太いフレームでも「内径をアバター円に合わせる」のではなく、**フレーム太さの中心線をアバター境界ガイドに合わせる**。
- 見かけ外径はデザインごとに調整するが、アプリ表示で小さく見えないことを優先する。細い装飾は外径を大きめに取り、太い装飾は内側を侵食しすぎない範囲で中心線を合わせる。
- `alpha bbox` の中心はキャンバス中心から大きくズレないこと。目安は ±2px 以内。意図的な非対称装飾でも、主リングの中心は揃える。

### 生成手順の原則

1. **親画像は方向確認用、最終素材は個別生成**にする。
   - 親画像・一覧画像から切り抜いて最終アセットにすると、解像度低下、切り抜き位置ミス、隣接素材の混入、透過ノイズが起きやすい。
   - 親画像を使う場合も、最終は各ランク/各アイテムを単体で再生成する。
2. 背景は可能な限り **完全な単色クロマキー `#00ff00`** で生成する。
   - 外側だけでなく、開いた中心穴も同じ単色背景にする。
   - 黒背景の親画像から抜く運用は、影・暗い塗り・背景ノイズが混ざりやすいので最終素材には向かない。
3. プロンプトには、参照デザインを守る制約を必ず入れる。
   - `no crop from the board`
   - `no simplified flat vector redraw`
   - `same design family`
   - `do not invent a new variant`
   - `open avatar center`
   - `flat chroma-key background`
4. ランク差分は色だけでなく、**素材感・密度・太さ・宝飾量・ハイライト量**で定義する。
   - ただし下位より上位が細く/軽く見えるのは禁止。
   - 特に銀は銅より細く見えやすいので、`silver must not be visually thinner, weaker, or lower density than bronze` を明示する。
5. 生成が別デザインへ逸れたら、後処理で救おうとしない。
   - 色補正・透過補正で直せるのは素材品質だけ。
   - シルエット、宝石位置、破損パターン、装飾密度が変わった場合は、プロンプトを再固定して再生成する。

### プロンプトテンプレート

単体フレーム生成時の基本形：

```text
Generate one standalone 1024x1024 circular profile icon frame asset matching the provided reference design.
Preserve the same design family, silhouette, ornament density, material treatment, and node/gem placement.
The main ring stroke center must align to the avatar guide circle; the rim may extend equally inward and outward around that line.
Use a perfectly flat #00ff00 chroma-key background, including the open avatar center.
No text, no logo, no crop from the board, no simplified flat vector redraw, no invented variant, no dark background, no shadow bed.
Sharp high-resolution ornament detail suitable for extraction into a transparent PNG asset.
```

ランク指定はこのテンプレートに追加する：

```text
Material/rank: <iron/bronze/silver/gold/platinum or premium material>.
Relative weight: <how much heavier/lighter/denser than previous rank>.
Accent/gems: <gem color and count>.
Important comparison: <e.g. silver must not be visually thinner than bronze>.
```

### 透過・後処理のチェック

- 白背景、チェッカー背景、実際のアバター色背景の3種類で確認する。
- 背景由来の薄い矩形、粒状ノイズ、黒い影ベタ、中心穴の残り塗りが見えたらNG。
- 黒背景から抜いた素材を明るくすると、影だった部分が「薄い塗り残り」として見えやすい。これは色補正ではなく、生成/抽出工程の問題として扱う。
- 低アルファを切るだけで外径が小さく見える場合があるため、透過cleanup後にもう一度見かけ外径を検証する。
- 検証値の最低ライン：
  - `1024x1024`
  - center alpha = 0
  - corner alpha = 0
  - alpha bbox center offset が小さい
  - 実アプリのアバター径に対してフレームが小さく見えない

### 親画像・切り出しを使ってよい場面

- 方向性比較、ランク構成の確認、ユーザーに雰囲気を見せるラフ用途。
- 参照デザインの座標・宝石位置・破損パターンを読む用途。

最終アセットとしては原則使わない。やむを得ず使う場合は、切り抜き後に以下を必ず確認する：

- 隣接ランクの破片が混入していない。
- 外周/内周がマスクや中心クリア処理で削れていない。
- 黒背景由来の影がフレーム本体に残っていない。
- 白背景で見ても塗り残りがない。
- 解像度が他フレームより低く見えない。

---

## 1. 何を融合するのか（参考と翻訳）

参考にしたのは magnific の「丸枠ベクター」群（金フィリグリー / ボタニカルリース / 水彩 / 星付き極細枠 / 月桂樹）。**形は借りる、色と質感は twilight に翻訳する。**

| 参考の要素 | そのまま使う？ | Liminalへの翻訳 |
|---|---|---|
| 金箔・ゴールドの輝き | 翻訳して使う | 純金ではなく **warm amber `#FFE3A3`（Reward）＋微発光**。希少資源として上位だけ（doc 13 §2.4） |
| 唐草・フィリグリー（極細曲線装飾） | 使う | 主役モチーフ。`#C9A7FF`系の細線＋淡発光。左右/上下対称で品よく |
| ボタニカル（葉・花のリース） | 控えめに | 写実花は避ける。**抽象化した小枝/月桂の弧**として。多色フローラルにしない |
| 水彩のにじみ | 質感として使う | カード地の**twilightグラデ＋ソフト発光ブロブ**で代替（ベタ塗り禁止・doc 13 §4） |
| 星屑・スパークル | 使う | 上位の象徴。4点星＋細点を環上に散らす（既存 `tsukishiro` フレーム参照） |
| 純白背景・パステル多色 | ❌使わない | 地は `#0D0B16`〜twilightグラデ。多色乱立は静けさを壊す（doc 13 §9） |

---

## 2. パレット（必ずこの範囲で。doc 13 準拠）

| 役割 | hex | 使い所 |
|---|---|---|
| Primary（主役・発光） | `#C9A7FF` luminous violet | 装飾の主線・主モチーフ |
| Primary highlight | `#C9A7FF`を白へ50%寄せ | 線のハイライト・煌めき（コードは `Color.liminalLuminous`） |
| Reward（特別・金） | `#FFE3A3` warm amber | **上位のみ**・微量。金枠/宝石/王冠的要素 |
| dawn グラデ | `#FFB3C7`→`#C4A5E8`→`#FFE3A3` | ライト寄り上位カードの地 |
| dusk グラデ | `#2B3A8F`→`#6B3FA0`→`#E8995A` | ダーク寄り上位カードの地 |
| 地（canvas/surface） | `#0D0B16` / `#17132A` | 装飾が浮かぶ夜空 |

- **各アイテムの色アイデンティティ**は catalog（`ProfileDecorations.swift`）の `primaryHex`/`markHex` を維持。上の Primary/Reward は「chrome的な発光・金の使いどころ」の規律であって、アイテム固有色を消す意味ではない。
- **多色は最大2色＋ハイライト**まで。3色以上の乱立は禁止（prism/aurora の薄明スペクトルだけ例外）。

---

## 3. リミナログらしさの3要素（必須・全装飾共通）

1. **発光（glow）**：主モチーフの背後に柔らかいblur発光を1枚。**ただし量を増やしすぎない**（ユーザー指示：グローはこれ以上増やさない）。`blur(radius: 6)` 前後・`opacity 0.35〜0.45` を上限の目安に。発光は「下支え」、主役は形。
2. **twilightグラデ**：ベタ塗り禁止。線・面ともに同系の明度差グラデ（`AngularGradient`/`LinearGradient`）で奥行きを出す。
3. **静けさ＝余白と対称**：要素を詰め込まない。対称・等間隔・整列で「精度」を感じさせる。賑やかさで豪華を出さない。

---

## 4. 豪華さの作り方（量でなく密度と階層）

「豪華＝要素を増やす」ではない。**作り込みの密度・多層構造・素材の質感**で出す。

- **多層化**：地グラデ → 主モチーフ → ハイライト → 微発光 → 小装飾（星/点/宝石）の重ね。各層は薄く。
- **対称オーナメント**：四隅・上下・四方位に**呼応する装飾**を置く（バラバラに置かない）。
- **質感の格上げ**：単線 → グラデ線 → 二重線 → 唐草曲線、と上位ほど手が込む。
- **金は最後の一刺し**：上位のみ amber を点で効かせる（縁・宝石・王冠）。全面金は安っぽい。

---

## 5. ランク連動（最重要・ユーザー指示）

**解放スコアが高いほど豪華に。** 現状の見た目は「下位〜中位」に位置づけ、**上位はさらに格上**にする。解放スコアは `UnlockRules.swift`（フレーム 300〜21,900 / カード 450〜21,600）。

| ティア | 解放スコア目安 | フレームの作り | カードの作り | 手段 |
|---|---|---|---|---|
| **T1 静（低位）** | 〜2,400 | 単色グラデ環＋1ジェスチャ（波/目盛/弧） | 罫線/方眼/レール等の素朴な紋様＋ソフト発光 | **ベクター** |
| **T2 整（中位）** | 〜7,200 | 環＋呼応する標（四方位/星）＋二重線 | 図表/織り/結晶＋twilightグラデ地 | **ベクター** |
| **T3 麗（高位）** | 〜16,200 | 二重環＋唐草曲線＋小宝石＋微発光 | 唐草コーナー＋金の差し色＋水彩風グラデ | **ベクター（必要なら画像）** |
| **T4 極（最上位）** | 16,200〜 | 金フィリグリー/月桂/星冠＋amberの一刺し＋発光 | 金箔質感/水彩/星屑の作り込み | **画像アート推奨** |

- **落差が報酬**：T1とT4が同じ作り込みでは特別感が死ぬ。**上ほど明確に密度を上げる**。
- 新体系の代表は、T1=`cloud_veil`/`cloud_panel`、T2=`petal_wreath`/`thread_panel`、T4寄り=`horizon_wreath`/`horizon_panel`。

---

## 6. ベクター vs 画像の方針（現行は生成PNG優先）

| | ベクター（SwiftUI Path/Canvas） | 画像アート（透過PNG/SVG） |
|---|---|---|
| 得意 | 幾何・抽象・対称（環/目盛/弧/星/宝石/グリッド/折れ線/唐草の単純曲線） | 有機形（花葉リース）・水彩にじみ・金箔粒子・極細フィリグリー |
| テーマ追従 | ◎ アクセント色・明暗に自動追従 | △ 多色アートは固定見た目になる |
| 推奨ティア | **T1〜T3** | **T4（最上位）**、T3の一部 |

- **現行のフレーム/カード本体は全ティア生成PNG優先**。ベクターは欠損時のフォールバック。
- 生成PNGを使う理由は、花・雲・水・結晶・金継ぎなどの有機的な質感を、SwiftUIの単線/グローだけで作ると「Liminalogの弱点を増幅した感じ」になりやすいため。
- 画像化アイテムは「色追従を捨てる代わりに、固定の決め打ちアート＝強い個性」と割り切る。これは「各装飾が固有アイデンティティを持つ」目的に合致。

### 画像アートを作る場合の仕様（Codexが生成/手配する際）
- **フレーム**：透過PNG、**1024x1024px**、中央に円。リング外形はキャンバスの大半を使い、アプリ表示時に縮小される前提でディテールを持たせる。リングの内側は完全透過（アバターが見える）。小さいスプライトシートから切って拡大しない。
- **カード**：横長の生成PNG。**横2048px以上**を基準にし、プロフィールカードの縁・角・内側模様として使う。地は透過 or twilightグラデ。カードは別途デザイン再検討中なので、フレーム確定後に扱う。
- **明暗対応**：`#0D0B16` のダーク地でも `#FBF3E7` 系のライト地でも破綻しないこと。発光寄り＝透過＋加算的な光で作ると両対応しやすい。難しければ light/dark 2枚持ち。
- **生成プロンプトの核**（AI生成なら強めに指定）：
  > "circular ornamental frame, transparent background, twilight/liminal palette (deep indigo night, luminous violet `#C9A7FF`, warm amber `#FFE3A3`), delicate gold filigree and tiny stars, soft inner glow, symmetrical, elegant, restrained, NOT white background, NOT pastel multicolor, NOT cute, high-end emblem"
- **ライセンス必須確認**：既成素材は商用可否・クレジット要否を必ず確認。AI生成でも素性を確認。

---

## 7. アンチパターン（これをやったら台無し）

- ❌ 純白背景・パステル多色の「招待状」そのまま（地は夜空/twilight）
- ❌ 全面ベタ金・ギラギラ（金は点で効かせる）
- ❌ 写実的な花葉の多色フローラル（抽象化・単色寄りに）
- ❌ 要素の詰め込み・非対称な散らかし（静けさ＝対称と余白）
- ❌ グローを増やして誤魔化す（発光は下支え・主役は形。doc 13 §4 の抑制）
- ❌ T1〜T4が同じ密度（落差＝報酬を消す）
- ❌ アイテム固有色を消して全部 `#C9A7FF` に統一（色アイデンティティは維持）

---

## 8. 受け入れ基準

1. **個体識別**：色を無視しても、形だけで各装飾が別物と分かる（量産バッジ脱却）。
2. **ランク落差**：T1とT4を並べて、明確に「格上」が分かる。
3. **両モード**：ライト/ダーク両方で体裁・視認性が同品質（[[verify-perf-in-release]] の通りRelease/実機で確認）。
4. **liminal整合**：「twilightの空に浮かぶ発光する宝飾」に見える。生産性バッジにも白い招待状にも見えない。
5. **非破壊**：ID・解放条件・装備中・テーマ追従の仕組みが壊れていない。

---

## 9. 現状（着手時点のコード状態）

- 2026-06-06時点で、フレームは生成PNG優先。全21個を単体生成の1024px版へ差し替え済み。
- フレーム/カードは旧IDから新IDへ総入れ替え済み。旧 `halo`/`clean` は移行互換上だけ残り、新規データの標準は `clear_air` / `quiet_sky`。
- レビュー用レンダラ：`LiminalogTests/CollectionMockupRenderTests.swift`（`/tmp/liminal_mockups/` にPNG出力）。残り展開時の比較に流用する。

---

## 10. 次アクション（Codexへ）

1. フレームは全種、単体生成または十分な解像度の素材から **1024x1024px透過PNG** として作り直す。
2. カードはデザイン再検討後、横2048px以上の生成PNGとして作り直す。
3. 各idの「モチーフ一行定義」を本書に追記してから実装する。

---

## 11. 獲得（無料開放）vs プレミアム（課金）の設計思想 ★2026-06 決定

> §0〜§10 は「装飾の見た目」共通規律。本節は **無料で得る装飾と課金で得る装飾を、
> 見た目で"別の種類"に分ける**ための上位方針。マネタイズ思想（[17-monetization.md](17-monetization.md)・
> [19-monetization-voice.md](19-monetization-voice.md)）と対で読む。Codex への生成/実装指示の起点。

### 11.0 一行で

> **獲得＝現代的な"達成メダル"（金で買えない勲章）。プレミアム＝自然/大気のテーマ世界を拡張した"作品"。**
> 縦に「課金が上位」ではなく、横に「別の車線」。種類が違うから両立する。

### 11.1 なぜ分けるのか（マネタイズ論理）

- 課金装飾は **操作性に無影響・任意・買わなくても支障なし＝pay-to-win ではない**。豪華にして良い（若者の"見た目買い"の入口）。
- ただし **獲得装飾は「金で買えないからこそ価値がある」実績**にしたい（doc 17 §4 の継続インセンティブ）。
- 課金と獲得が**同じモチーフ**だと「俺の継続、¥500で買えたじゃん」＝**実績の希釈**が起きる（pay-to-win とは別問題）。
- → 解：**語彙そのものを分ける**。課金がどれだけ豪華でも、獲得は別語彙の「勝ち取った証」として希釈されない。
- **dual entry**：若者＝見た目で買う（プレミアムの画が自力で売れる）／大人＝思想で支援し装飾は"お礼"。**面で住み分け**、メッセージを混ぜない（doc 19）。

### 11.2 二車線の対比

| | **獲得（無料開放・継続で得る `free_*`）** | **プレミアム（課金）** |
|---|---|---|
| 性質 | 現代的な**達成メダル/勲章**。勝ち取った証 | 自然/大気のテーマ世界を拡張した**作品** |
| 語彙 | 金属・幾何・精密（同心環/刻線/月桂冠/クレスト宝石/ランク） | 有機・絵画的（オーロラ/金継ぎ/漆/花/空/結晶/潮硝子） |
| 色 | **金属の escalation が達成度の signal**：銀→白金→薄金→**金**。amber/金は獲得の専用シグナル | 冷たい liminal 自然色（violet/teal/lavender/rose/dawn）。**金メダル語彙は使わない** |
| 豪華さの出し方 | 金属の質感・月桂の密度・刻線・放射光（ティアで増す） | 塗り・箔・大気・粒子の作り込み |
| 「買えない」感 | エンジニアされた精度＋金属＝「続けた人のやつ」と一目で分かる | （課金なので不要） |
| 生成手段 | **ベクター（SwiftUI Canvas/Path）パラメトリック系**（§11.4） | **画像生成**（有機アート）＋"生きてる層"のオーバーレイ |
| 動き（将来） | **あなたのデータで動く**（ストリーク→粒子/発光）＝複製・購入不可能な自慢 | 装飾的な大気のループ（演出） |

**鉄則：プレミアムは「獲得最上位を超える上位ティア」を作らない。** 差は密度（盛り）でなく**種類**（金属メダル vs 自然作品）で出す。

### 11.3 獲得（メダル）側の詳細方針

- **ティア＝解放スコア順の4段**（`ProfileIconFrameCatalog.earnedTier(for:)`／`UnlockRules` 準拠）。**落差そのものが報酬**（§5）。簡単なものは質素でいい、難しいものは課金に劣らない自慢に。
  - T1（300〜2,400pt・〜40日）：白金のベベル環＋細い刻線＋小クレスト宝石（質素だが安っぽくない＝"上げた底"）
  - T2（〜7,200・〜120日）：白金＋二重環（コイン縁）＋月桂の芽
  - T3（〜16,200・〜270日）：薄金＋月桂冠（半周）＋面取りクレスト＋副石
  - T4（18,600〜21,900・〜365日）：豪奢な金＋ほぼ全周の金月桂＋放射光＋強い署名グロー（自慢の頂点）
- **金属＝達成度・クレスト宝石＝アイテム固有色**（tintHex を残し個体識別＝§7）。
- **liminal ガードレール（最重要）**：Duolingo的なギラギラ生産性バッジに**しない**。洗練された発光メダル。密度でなく精度・対称・余白で報酬感を出す（§3）。
- **違和感を出さない具体ルール**（実装知見）：月桂は放射状の棘でなく**接線方向に寝かせて冠**にする／浮いた星でなく頂点の**台座付きクレスト宝石**／計器っぽい目盛でなく**低コントラストの彫り**／色グローは薄く締めて**金属を主役**に。

### 11.4 生成手段の分岐（★重要）

§0.2 で「全ティア生成PNG優先・ベクターはフォールバック」としたが、**それは旧・全有機モチーフ前提**。獲得をメダル/幾何へ変えた今、**獲得はベクター主・生成フォールバックへ反転**する。

- **獲得＝ベクター（パラメトリック系）が正**。理由：①ティアの金属 escalation を変数で制御＝**落差が保証**され「365日のが10日より地味」事故が起きない ②`tintHex` 入力でテーマ/明暗に自動追従 ③20個が同じ作図文法＝**ランクシステムに見える** ④将来のデータ駆動モーション（買えない自慢）はコードでしか作れない ⑤精密な描画は**AI安売り感ゼロ**。
  - 現状の実装：[`EarnedEmblemFrame`](../ProfileComponents.swift)（金属 escalation・二重環・接線月桂・放射光・クレスト宝石）。`ProfileIconFrameView` が獲得idをこのベクターへルーティング（生成PNGは温存・バイパス）。
- **プレミアム＝画像生成が正**（有機的リッチさが要る。固定見た目でテーマ追従不要）。"生きてる層"は生成PNGの上に Canvas/シェーダで重ねる。
- **もし Codex に獲得をPNG生成させる場合**でも本節の語彙を厳守：金属メダル・金escalation・ティア格差・**自然モチーフ禁止**・プレミアムに金メダル語彙を混ぜない。

### 11.5 既存アセットの被り解消（差し替え方針）

獲得から自然モチーフを退け、メダル語彙へ。被っていたものはプレミアム側へ寄せる：

| 旧・獲得（自然） | 処理 |
|---|---|
| `free_aurora_thread`・`free_night_bloom`・`free_constellation_orbit` 等の自然モチーフ | **メダル/勲章へ差し替え**（語彙を放棄）。`targetID`/imageset名は据え置き＝移行ゼロ、displayName/tint/見た目のみ差し替え |
| オーロラ/星座/花の作品性 | **プレミアム側**（自然作品の車線）で展開 |

### 11.6 プレミアム（作品）側の方針

- **A＋B＋C** で「ランクが上」でなく「種類が違う」を作る：
  - **A 作品シリーズ化**：季節/情景ごとのキュレーション・アート集
  - **B 生きてる**：アニメ/パララックス/粒子/光の揺らぎ（静止AIに見せない署名・若者の審美バー超え）
  - **C 物語**：1ドロップ＝存在理由の短い物語（doc 19「なぜを先に語る」）。「限定」は希少性煽りでなく物語側で
- 冷たい liminal 自然色。**金メダル語彙・獲得の軌跡モチーフは使わない**。
- 画像生成＋"生きてる層"オーバーレイ。固定見た目で割り切る（§6）。
