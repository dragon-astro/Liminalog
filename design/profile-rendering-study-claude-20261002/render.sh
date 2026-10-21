#!/bin/zsh
# macOS で描画して renders/ に PNG を書き出す。
#   ./render.sh [masters|sheets|plain|timing|all] … 既存PNGとこの試作の比較・検査用出力・描画時間
#   ./render.sh codex                  … 先行Codex試作も同じ擬似UIに並べた3者比較（Codex側のファイルは読むだけ）
set -euo pipefail
study_dir="${0:A:h}"
mode="${1:-all}"
build_dir="${TMPDIR:-/tmp}/liminalog-profile-study-claude"
mkdir -p "$build_dir"
sources=("$study_dir"/{Core,Botanical,Celestial,LeafMotif,StarMotif,CodeViews,StudyViews,ThreeWay,RenderMain}.swift)
flags=()
if [[ "$mode" == "codex" ]]; then
  sources+=("${study_dir:h}/profile-rendering-study-20261002/NativeDecorations.swift")
  flags+=(-D WITH_CODEX)
fi
xcrun swiftc -parse-as-library -O -module-cache-path "$build_dir/module-cache" "${flags[@]}" "${sources[@]}" -o "$build_dir/render-$mode"
"$build_dir/render-$mode" "$study_dir" "$mode"
