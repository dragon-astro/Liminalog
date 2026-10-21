#!/bin/zsh
set -euo pipefail
study_dir="${0:A:h}"
build_dir="${TMPDIR:-/tmp}/liminalog-profile-render-study"
mkdir -p "$build_dir"
xcrun swiftc -parse-as-library -O -module-cache-path "$build_dir/module-cache" "$study_dir/NativeDecorations.swift" "$study_dir/RenderStudy.swift" -o "$build_dir/render"
"$build_dir/render" "$study_dir"
python3 "$study_dir/validate_renders.py"
