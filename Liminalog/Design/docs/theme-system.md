# テーマ定義型リファクタ — 実装仕様（Codex向け）

担当: **Codex**（アーキテクチャ転換・既存パターン置換のため。`AI_TASKS.md §2.3` 決定木）
計画: Claude / 2026-06-02
ステータス: P0/P1 実装済み。P1.5 は曙の白馴染み+朝ライト再調整とDailyReflectionCardスクショ確認まで実装済み、全画面監査は継続。

---

## 1. 背景 — なぜやるか

ライトモードで「グラデ背景に直接乗った半透明要素」が地に溶けて見える問題を調査した結果、
**半透明の質感はダーク前提の作法**だと判明した。

- ダーク: 黒地に `color.opacity(0.12)` を敷くと「光るガラス」になり輪郭が立つ。
- ライト: 白〜淡い色のグラデ地に同じ半透明を敷くと、背後の色温度差で濁る・輪郭が消えて沈む。

つまり「色」だけでなく **塗りの不透明度・ソリッド下地の要否・輪郭(stroke)・文字の強調**といった
**“扱い方” そのものがテーマごとに変わる**。現状はこれを `colorScheme == .light` の場当たり分岐で
個別Viewに散らすしかなく、テーマを足す/調整するたびに分岐が増殖する。

### ゴール
- **1テーマ = 1つの値型**（色 + 扱い方を丸ごと保持）にする。新テーマ追加はインスタンスを1個作るだけ。
- ライト/ダークの**分岐は「どのテーマを選ぶか」の1関数だけ**に閉じる。
- 既存の `LiminalTheme.token` 呼び出し（約57箇所）は**無改修**で動き続ける。
- ダークモードの**見た目は1ピクセルも変えない**（リグレッション禁止）。
- **曙(daybreak)は宵(dusk)と同格の完成度まで再構成する**。宵の色使いは基準として維持し、曙だけが「薄い」「見づらい」「安い」印象にならないよう、パレット・面・文字・アクセントの関係を実機スクショで詰める。

### 非ゴール（このタスクでやらない）
- ユーザーが任意テーマを選べるUI（P3・将来）。今回は system の light/dark を2テーマにマップするだけ。

---

## 2. 後戻りしない決断（アーキテクチャ方針）

1. **facade 温存**: `enum LiminalTheme` の静的トークン（`LiminalTheme.primary` 等）と
   `canvasGradient` / `cardGradient` / `uiCanvas(for:)` は**シグネチャを変えない**。
   内部実装だけテーマ定義型から動的解決する。→ call site 無改修。

2. **動的 `UIColor { traits in ... }` を維持**: system の外観切替に自動追従させるため、
   色トークンは引き続き `Color(UIColor { traits in ... })` で組む。
   トークンの解決先を「固定パレット」から「`定義 = catalog.definition(for: traits.colorScheme)` のパレット」へ差し替えるだけ。

3. **トリートメントは `colorScheme` から定義を引いて解決**（P1〜P2）。
   新しい env キーは**導入しない**。modifier 内で `@Environment(\.colorScheme)` →
   `LiminalThemeCatalog.definition(for:)` を引き、その treatment を読む。
   （ユーザー選択テーマが必要になった時点で初めて `@Environment(\.liminalTheme)` を足す＝P3。今はやらない）

4. **段階導入**: P0 は純リファクタ（見た目不変）。P1 で treatment を型経由に。P2 で横展開。
   各フェーズ単独でビルド緑・スクショ確認できる粒度に切る。

---

## 3. 型定義（新規ファイル: `Liminalog/Design/LiminalThemeDefinition.swift`）

```swift
import SwiftUI
import UIKit

/// 1テーマぶんの「色 + 扱い方」を丸ごと持つ値型。
/// 新テーマ追加 = このインスタンスを1つ作る、で完結させる。
struct LiminalThemeDefinition {
    let id: String
    let name: String
    /// 対応する system 外観。SwiftUI標準chrome(キーボード/.bar 等)を揃える +
    /// 可読性ロジックの明暗判定に使う。
    let appearance: ColorScheme
    let palette: LiminalPalette
    let surface: LiminalSurfaceTreatment   // グラデ地に直乗りするチップ/リボンの下地
    let glass: LiminalGlassTreatment       // 白フロスト系ピル（.white.opacity の置換）
    let emphasis: LiminalTextEmphasis      // 文字の強調（P2で配線）
    let effects: LiminalEffectTreatment    // 影・grain 強度（P2で配線）
}

/// 全色トークン。定義ごとに「解決済みの色」を持つ（動的化は facade 側の責務）。
struct LiminalPalette {
    let canvas, surface, elevated, divider: UIColor
    let text, secondaryText, tertiaryText: UIColor
    let primary, reward, dawn, dusk: UIColor
    let gradientTop, gradientMiddle, gradientBottom, cardBottom: UIColor

    /// 既存の duskPalette/daybreakPalette と同じ hex 文字列で初期化できるようにする。
    init(canvas: String, surface: String, /* …全トークン… */ cardBottom: String) {
        self.canvas = UIColor(liminalHex: canvas)
        // … 既存 LiminalThemeColor(hex:) と同じパース（UIColor(liminalHex:)）を流用 …
    }
}

/// グラデ地に直乗りする半透明チップの「下地の作り方」。
struct LiminalSurfaceTreatment {
    enum Style { case glass   // 色を薄く敷くだけ（ダーク。黒地で光る）
                 case solid } // 不透明下地＋淡い色＋色枠（ライト。輪郭を立てる）
    let style: Style
    /// solid時の不透明下地。nil なら palette.surface を使う。
    let baseColor: UIColor?
    /// 乗せる tint の量（glass=これだけ / solid=下地の上に乗せる量）
    let tintFillOpacity: Double
    /// 輪郭。<=0 で無し。色は呼び出し側 tint に opacity を掛ける。
    let strokeOpacity: Double
    let strokeWidth: CGFloat
}

/// 白フロスト系ピル/パネルの作り方（DailyReflectionCard の .white.opacity 群を一般化）。
struct LiminalGlassTreatment {
    let fillColor: UIColor      // dark=白 / light=surface(不透明)
    let fillOpacity: Double
    let strokeColor: UIColor    // dark=白 / light=divider
    let strokeOpacity: Double
    let strokeWidth: CGFloat
}

/// 文字強調の不透明度（.secondary を自前で薄める箇所などの基準値）。P2配線。
struct LiminalTextEmphasis {
    let secondaryOpacity: Double
    let tertiaryOpacity: Double
}

/// 影・grain の強度。ライトは影が重く出るので絞れるようにする。P2配線。
struct LiminalEffectTreatment {
    let shadowStrength: Double   // 乗算係数（dark=1.0）
    let grainOpacity: Double
}
```

### テーマカタログ（選択の一元化）

```swift
enum LiminalThemeCatalog {
    static let dusk: LiminalThemeDefinition = …      // 現 duskPalette + ダーク用 treatment
    static let daybreak: LiminalThemeDefinition = …  // 現 daybreakPalette + ライト用 treatment

    /// ★ ライト/ダーク分岐はここ1箇所だけ。将来ユーザー選択を足すならここに集約する。
    static func definition(for scheme: ColorScheme) -> LiminalThemeDefinition {
        scheme == .light ? daybreak : dusk
    }
    /// UITraitCollection 経由（動的 UIColor / uiCanvas 用）
    static func definition(for traits: UITraitCollection) -> LiminalThemeDefinition {
        traits.userInterfaceStyle == .light ? daybreak : dusk
    }
}
```

---

## 4. treatment の初期値（duskは現状維持、daybreakはP1.5で改善）

| トークン/treatment | dusk（ダーク） | daybreak（ライト） |
|---|---|---|
| palette 全色 | 現 `duskPalette` の hex そのまま | P1.5で再構成した初期改善値 |
| `surface.style` | `.glass` | `.solid` |
| `surface.baseColor` | `nil` | `palette.surface` |
| `surface.tintFillOpacity` | `0.12` | `0.14` |
| `surface.strokeOpacity` | `0`（枠なし） | `0.42` |
| `surface.strokeWidth` | `1` | `1` |
| `glass.fillColor` / `fillOpacity` | 白 / `0.08` | `palette.surface` / `1.0` |
| `glass.strokeColor` / `strokeOpacity` | 白 / `0.12` | `palette.divider` / `0.6` |
| `glass.strokeWidth` | `1` | `1` |
| `emphasis.secondaryOpacity` / `tertiaryOpacity` | `1.0 / 1.0`（現状維持） | `1.0 / 1.0`（P2で詰める） |
| `effects.shadowStrength` / `grainOpacity` | `1.0 / 現状値` | `1.0 / 現状値`（P2で詰める） |

> `surface`/`glass` のライト値は §8 の先行実装（`liminalCanvasChip`）で実機確認済みの値。
> dusk 側は**現状の数値をそのまま**転記すること（変えると即リグレッション）。

---

## 5. 実装フェーズと優先順位

### P0 — 基盤型 + 選択の一元化（見た目変化ゼロ） ★実装済み
**受け入れ条件: ライト/ダーク両方でスクショが現状と一致（リファクタのみ）。**

- [x] `LiminalThemeDefinition.swift` 新規作成（§3 の型）。`UIColor(liminalHex:)` は
      現 `LiminalTheme.swift` 内の private extension をこのファイルへ移動 or 共有。
- [x] `LiminalThemeCatalog` に `dusk` / `daybreak` を §4 の値で定義。
- [x] `LiminalTheme` の `token(_:)` を「`activePalette(for:)`」から
      「`LiminalThemeCatalog.definition(for: traits).palette[keyPath:]`」解決に差し替え。
      **静的トークン名・型・gradient・`uiCanvas(for:)` のシグネチャは不変**。
- [x] 旧 `duskPalette`/`daybreakPalette`/`LiminalThemePalette`/`activePalette` を撤去
      （定義は `LiminalThemeCatalog` に一本化）。
- 検証: §6。

### P1 — treatment を型経由に（ライトのみ改善・ダーク不変） ★実装済み
**受け入れ条件: ダークは P0 と完全一致。ライトはグラデ直乗り半透明に輪郭が出る。**

- [x] `liminalCanvasChip` modifier（§8 で先行実装済み）を、ハードコードの light/dark 分岐から
      **`LiminalThemeCatalog.definition(for: scheme).surface` を読む形に書き換える**。
      `.glass` / `.solid` で分岐し §3 の擬似コード通りに描画。
- [x] `glass` treatment 用の modifier を新設:
      `func liminalGlassFill<S: Shape>(in shape: S) -> some View`（fill+stroke を treatment から）。
- [x] `DailyReflectionCard.swift` の `.white.opacity(...)` ピル/パネル（背景+stroke のペア）を
      `liminalGlassFill(in:)` へ置換。**Canvas描画(`context.fill`/`context.stroke`)の
      `.white.opacity` はリングチャート等の意匠なので対象外**（誤置換しないこと）。
- 検証: §6 + DailyReflectionCard をライトで確認（白ピルが溶けず縁が出る）。

### P1.5 — 曙パレット再構成（ライトの見づらさ・リッチ感不足を解消）
**受け入れ条件: 宵に比べて曙が情報密度・奥行き・可読性で劣らない。単に白く明るいだけにしない。**

- [~] `daybreak` の `canvas` / `surface` / `elevated` / `divider` / `gradient*` を再構成し、背景グラデ・カード面・区切り線の階層が見えるようにする。
      2026-06-02: 濃く輪郭を立てる方向から、白に馴染む薄い面 + 控えめなdividerへ再調整。
- [~] `primary` / `reward` / `dawn` / `dusk` をライト背景で濁らない値へ調整する。特に reward が黄土色に沈む、dusk/primary の彩度差で安っぽく見える、下端の黄がラベンダーと割れる問題を潰す。
      2026-06-02: `reward` は曙の朝ライトとして使える柔らかい金へ寄せ、`liminalAccentLight(in:)` でDailyReflectionCardの要所だけに差す。
- [x] `text` / `secondaryText` / `tertiaryText` を曙専用に再確認し、淡い背景・プロフィールカード・チップ上で薄すぎないことを確認する。
      2026-06-02: 主要タブの曙/宵スクショで本文・副本文・チップ文字の可読性を確認。
- [x] `ProfileHero` / 装備カード / DailyReflectionCard / CurrentChapterCard / Dashboard hero をライトで撮影し、宵スクショと並べて「曙だけ読みにくい」「曙だけ平たい」箇所を潰す。
      2026-06-02: 主要タブの曙/宵スクショを確認。名指し範囲では追加修正不要。
- [x] プロフィールカードはテーマ非連動の白固定に戻さない。カード背景・文字・プレビューは light/dark の両方で同じ装飾IDを保ちつつ、各テーマで読める色へ解決する。
      2026-06-02: ProfileHero light/darkで白固定・文字消え再発なしを確認。

### P2 — 横展開 + 文字/影
**受け入れ条件: 全画面でグラデ直乗りの「輪郭なし半透明」が解消。**

- [~] 全画面監査: 「`canvasGradient` 上に直接置かれ、かつ内側に不透明カードを持たない」
      半透明要素を洗い出す。**カード内（不透明 `Color(.secondarySystemGroupedBackground)` 等の上）の
      半透明はセーフなので触らない**（白地と同じ理屈で綺麗に出る）。
      - 確定済み対象: `CurrentChapterCard` の active リボン（§8 で対応済み）。
      - 要監査: `Dashboard` / `Calendar(DayView)` / `Profile` / `Friends` の浮遊チップ・丸ボタン
        （`.ultraThinMaterial` / `.thinMaterial` の Circle はライトでは標準materialが効くので、
        まず実機で沈むか確認 → 沈むものだけ `liminalGlassFill` 化）。
  - 洗い出し結果を本docの末尾に表で追記してから着手すること。
  - 2026-06-02: 主要タブ監査表を §8 に追加。深い詳細画面・作成編集Sheet・共有プレビューは継続。
- [ ] `emphasis` / `effects` を必要箇所に配線（自前 `.opacity` で薄めている文字・影）。
      まずライトで「濃すぎ/薄すぎ」を実機判断 → treatment 値を詰める。

### P3 — ユーザー選択テーマ（将来・今回スコープ外）
- [ ] `@Environment(\.liminalTheme)` を導入し、root で system 外観 or ユーザー設定から
      `definition` を注入。`LiminalThemeCatalog.definition(for:)` をその入口に集約。
- [ ] 設定画面でテーマ選択UI。`UserSettings` に保存。
- > P0〜P2 を「`colorScheme` 起点」で組んでおけば、P3 は注入元を差し替えるだけで載る設計になっている。

---

## 6. 検証手順（各フェーズ必須）

```bash
SIM=<booted iPhone sim id>   # xcrun simctl list devices booted
xcodebuild -project Liminalog.xcodeproj -scheme Liminalog -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath build build
xcrun simctl install $SIM build/Build/Products/Debug-iphonesimulator/Liminalog.app
# ライト
xcrun simctl ui $SIM appearance light
xcrun simctl launch $SIM app.YasudaRyuga.Liminalog
xcrun simctl io $SIM screenshot artifacts/<phase>-light.png
# ダーク
xcrun simctl ui $SIM appearance dark
xcrun simctl io $SIM screenshot artifacts/<phase>-dark.png
```

- **P0**: `artifacts/light-home-after.png` / `dark-home-after.png`（§8時点）と一致すること。
- パフォーマンス判定が要る変更は **Release ビルドで確認**（`AI_TASKS.md §3.5.1`。Debug SwiftUI は5–10倍遅い）。
- `Color+Hex.swift` の `liminalReadableDataColor` は `LiminalTheme.uiCanvas(for:)` に依存。
  P0 でシグネチャを保てば動くが、念のためカテゴリ色の可読性（統計バー等）も1枚撮って確認。
- Hex パースキャッシュ（`Color.cachedHex`/`cachedDisplayHex`）には**手を入れない**。

---

## 7. パレット色調整（P1.5で必ず扱う）

型ができた後に差し替える、ライトの色味の懸案:
- 曙は「濃くして見せる」より、白に近い薄い面に馴染ませ、昨日カードなど重要な場所だけ朝ライトを差す。
- グラデ下端の黄はラベンダーと割れやすいので、白に近いピーチへ寄せる。
- `reward` は黄土色ではなく、面を汚さずライトに使える柔らかい金へ。
- `dusk`/`primary` は白背景で主張しすぎない紫へ抑え、可読性は文字色と面設計で担保する。
- プロフィールカードや浮遊チップが曙では白っぽく平板、宵では文字だけ追従して消える事故。

→ これらは `LiminalThemeCatalog.daybreak.palette` と treatment 値を変えるだけで効くように、P0/P1で型へ寄せてから P1.5 で実施する。局所的な朝ライトは `liminalAccentLight(in:)` を使い、darkではno-opにして宵の見た目を保つ。

---

## 8. 主要タブ監査ログ（P1.5/P2）

| 画面 | 曙スクショ | 宵スクショ | 判定 |
|---|---|---|---|
| Today / CurrentChapterCard | `/private/tmp/liminalog-daybreak-today.png` | `/private/tmp/liminalog-dusk-today.png` | OK。activeリボン、カテゴリ、Timelineで曙だけ沈む箇所なし |
| Yesterday / DailyReflectionCard | `/private/tmp/liminalog-daybreak-yesterday.png` | `/private/tmp/liminalog-dusk-yesterday.png` | OK。曙は白面+朝ライト、宵は黒面+ライトで成立 |
| Profile / ProfileHero | `/private/tmp/liminalog-daybreak-profile.png` | `/private/tmp/liminalog-dusk-profile.png` | OK。プロフィールカード白固定/文字消えの再発なし |
| Dashboard / hero | `/private/tmp/liminalog-daybreak-dashboard.png` | `/private/tmp/liminalog-dusk-dashboard.png` | OK。hero枠、period selector、metric tileの可読性に破綻なし |
| Calendar / month grid | `/private/tmp/liminalog-daybreak-calendar.png` | `/private/tmp/liminalog-dusk-calendar.png` | OK。月グリッド、予定ラベル、選択枠の可読性に破綻なし |
| Friends / list + ranking | `/private/tmp/liminalog-daybreak-friends.png` | `/private/tmp/liminalog-dusk-friends.png` | OK。一覧カード、カテゴリチップ、ランキングカードの可読性に破綻なし |

未監査として残す範囲: 深い詳細画面（友達詳細/日別詳細）、作成編集Sheet、カスタマイズSheet、共有プレビュー。P2ではここを追加で洗い出す。

---

## 9. 先行実装済みの差分（このdocの起点・残すこと）

Claude が P1 の一部を実機確認のため先行実装済み。**巻き戻さず、P1 で型経由に整理する**。

- `Liminalog/Design/LiminalTheme.swift`: `liminalCanvasChip(tint:in:darkFillOpacity:)` modifier を追加。
  現状は `@Environment(\.colorScheme)` でハードコード分岐（dark=glass / light=solid+stroke）。
  → **P1 でこの分岐を `LiminalThemeCatalog.definition(for:).surface` 読みに置換**。
- `Liminalog/Views/Home/CurrentChapterCard.swift`: active リボンを
  `RoundedRectangle.fill(displayColor.opacity(0.12))` から `liminalCanvasChip` 適用へ変更済み。
  → この適用自体は維持。modifier の中身だけ P1 で差し替わる。
- 確認用スクショ: `artifacts/{light,dark}-home-{before,after}.png`。
```
