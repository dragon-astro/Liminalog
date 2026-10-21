#!/bin/zsh
# 独立した iOS シミュレータ用プレビューアプリをビルドする（本体プロジェクトには触れない）。
set -euo pipefail
kit_dir="${0:A:h}"
build_dir="${TMPDIR:-/tmp}/liminalog-deco-kit-sim"
app_dir="$build_dir/DecorationKitPreview.app"
rm -rf "$app_dir"; mkdir -p "$app_dir"
cp "$kit_dir/PreviewInfo.plist" "$app_dir/Info.plist"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
sources=(${(f)"$(ls "$kit_dir"/Kit*.swift "$kit_dir"/Motif*.swift | grep -v KitRender.swift)"})
xcrun swiftc -parse-as-library -O -target arm64-apple-ios18.0-simulator -sdk "$sdk" -module-cache-path "$build_dir/module-cache" \
  "${sources[@]}" -o "$app_dir/DecorationKitPreview"
codesign --force --sign - --timestamp=none "$app_dir"
print "Built: $app_dir"
