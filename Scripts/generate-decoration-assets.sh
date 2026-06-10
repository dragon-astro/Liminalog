#!/bin/zsh
# decoration-masters/ の原寸マスターPNGから、出荷用の縮小PNGを
# Liminalog/Assets.xcassets/ProfileDecorations/ の imageset に書き出す。
#
# 使い方:
#   Scripts/generate-decoration-assets.sh          # 全マスターを処理（冪等）
#   Scripts/generate-decoration-assets.sh <name>   # ファイル名に <name> を含むものだけ処理
#
# ルール（詳細は decoration-masters/README.md）:
#   - マスターは decoration-masters/Cards|Frames に原寸のまま置く（リサイズ禁止）
#   - imageset 内の PNG は本スクリプトの生成物。手で編集しない
#   - 出荷解像度: Cards=幅1280px / Frames=512x512px（表示サイズ@3xに余裕を持たせた値）
#   - imageset が無いマスターは Contents.json ごと新規作成する

set -eu

cd "$(dirname "$0")/.."

MASTERS_DIR="decoration-masters"
ASSETS_DIR="Liminalog/Assets.xcassets/ProfileDecorations"
CARD_TARGET_WIDTH=1280
FRAME_TARGET_WIDTH=512
FILTER="${1:-}"

write_contents_json() {
    local imageset_dir="$1" png_name="$2"
    cat > "$imageset_dir/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "$png_name",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
}

process_group() {
    local group="$1" target_width="$2"
    local master png_name base imageset_dir out master_width

    for master in "$MASTERS_DIR/$group"/*.png(N); do
        png_name="${master:t}"
        base="${png_name%.png}"
        if [[ -n "$FILTER" && "$png_name" != *"$FILTER"* ]]; then
            continue
        fi

        imageset_dir="$ASSETS_DIR/$group/$base.imageset"
        out="$imageset_dir/$png_name"

        if [[ ! -d "$imageset_dir" ]]; then
            mkdir -p "$imageset_dir"
            write_contents_json "$imageset_dir" "$png_name"
            echo "created imageset: $imageset_dir"
        fi

        master_width=$(sips -g pixelWidth "$master" | awk '/pixelWidth/ {print $2}')
        if (( master_width <= target_width )); then
            # マスターが目標以下なら拡大せずそのままコピーする。
            cp "$master" "$out"
            echo "copied (<= ${target_width}px): $png_name (${master_width}px)"
        else
            sips --resampleWidth "$target_width" "$master" --out "$out" > /dev/null
            echo "resized ${master_width}px -> ${target_width}px: $png_name"
        fi
    done
}

process_group "Cards" "$CARD_TARGET_WIDTH"
process_group "Frames" "$FRAME_TARGET_WIDTH"

echo "---"
echo "masters:  $(du -sh "$MASTERS_DIR" | cut -f1)"
echo "shipped:  $(du -sh "$ASSETS_DIR" | cut -f1)"
