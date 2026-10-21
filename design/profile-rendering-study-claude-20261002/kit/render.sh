#!/bin/zsh
# 装飾キット（コード描画）の確認用PNGを書き出す。
#   ./render.sh motif [id…]   各モチーフの確認シート（宵／曙・実寸・既存PNG参考）
#   ./render.sh lineup        セット全体のヒーロー一覧・一覧サイズ
#   ./render.sh masters [id…] 原寸（フレーム1024・カード2048）
#   ./render.sh timing [id…]  描画時間の目安（macOS）
set -euo pipefail
kit_dir="${0:A:h}"
mode="${1:-all}"
shift || true
build_dir="${TMPDIR:-/tmp}/liminalog-deco-kit"
mkdir -p "$build_dir"
sources=(${(f)"$(ls "$kit_dir"/Kit*.swift "$kit_dir"/Motif*.swift | grep -v KitPreviewApp.swift)"})
xcrun swiftc -parse-as-library -O -module-cache-path "$build_dir/module-cache" "${sources[@]}" -o "$build_dir/render"
"$build_dir/render" "$kit_dir" "$mode" "$@"
