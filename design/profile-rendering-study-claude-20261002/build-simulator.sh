#!/bin/zsh
# 独立した iOS シミュレータ用プレビューアプリをビルドする（本体プロジェクトには触れない）。
# 既存PNGは比較表示用としてバンドルへコピーするだけ（装飾本体には使わない）。
set -euo pipefail
study_dir="${0:A:h}"
repo_dir="${study_dir:h:h}"
build_dir="${TMPDIR:-/tmp}/liminalog-profile-study-claude-sim"
app_dir="$build_dir/ProfileDecorationStudyClaude.app"
rm -rf "$app_dir"; mkdir -p "$app_dir"
cp "$study_dir/PreviewInfo.plist" "$app_dir/Info.plist"
for f in Frames/profile_frame_free_leaf_corner Cards/profile_card_free_leaf_corner_panel Frames/profile_frame_free_constellation Cards/profile_card_free_constellation_panel; do
  cp "$repo_dir/decoration-masters/$f.png" "$app_dir/"
done
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun swiftc -parse-as-library -O -target arm64-apple-ios18.0-simulator -sdk "$sdk" -module-cache-path "$build_dir/module-cache" \
  "$study_dir"/{Core,Botanical,Celestial,LeafMotif,StarMotif,CodeViews,StudyViews,PreviewApp}.swift \
  -o "$app_dir/ProfileDecorationStudyClaude"
codesign --force --sign - --timestamp=none "$app_dir"
print "Built: $app_dir"
