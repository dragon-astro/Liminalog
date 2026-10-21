#!/bin/zsh
set -euo pipefail
study_dir="${0:A:h}"
build_dir="${TMPDIR:-/tmp}/liminalog-profile-study-build"
app_dir="$build_dir/ProfileDecorationStudy.app"
mkdir -p "$app_dir"
cp "$study_dir/PreviewInfo.plist" "$app_dir/Info.plist"
study_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun swiftc -parse-as-library -O -target arm64-apple-ios18.0-simulator -sdk "$study_sdk" -module-cache-path "$build_dir/module-cache" "$study_dir/NativeDecorations.swift" "$study_dir/PreviewApp.swift" -o "$app_dir/ProfileDecorationStudy"
codesign --force --sign - --timestamp=none "$app_dir"
printf 'Built: %s\n' "$app_dir"
