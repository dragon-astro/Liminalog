#!/usr/bin/env python3
"""数値検査（Pillow のみ）。既存PNGとコード描画を同じ指標で測る。

審美判断の代わりにはならない。測るのは「事故が無いか」だけ：
  フレーム: 中心の透過半径 / 外周の切れ / 重心・bbox のずれ / リングの途切れ / 帯の面積
  カード  : 文字列（本文が載る矩形）の背景の明るさのばらつきと、本体の差分合成文字とのコントラスト
"""
import json, math, os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
R = os.path.join(HERE, "renders")
UNIT = 383.0  # 1024px マスターでのアバター半径

def frame_metrics(path):
    im = Image.open(path).convert("RGBA")
    if im.size != (1024, 1024):
        im = im.resize((1024, 1024), Image.LANCZOS)
    w, h = im.size
    a = im.getchannel("A").load()
    cx, cy = (w - 1) / 2, (h - 1) / 2
    min_r = 1e9; edge = 0; sx = sy = st = 0
    minx, miny, maxx, maxy = w, h, -1, -1
    sectors = [0] * 360
    annulus = 0.0; annulus_n = 0
    for y in range(h):
        for x in range(w):
            v = a[x, y]
            r = math.hypot(x - cx, y - cy)
            ru = r / UNIT
            if 0.88 <= ru <= 1.12:
                annulus += v / 255; annulus_n += 1
            if v <= 8:
                continue
            min_r = min(min_r, r)
            if x < 4 or y < 4 or x >= w - 4 or y >= h - 4:
                edge += 1
            sx += x * v; sy += y * v; st += v
            minx, miny, maxx, maxy = min(minx, x), min(miny, y), max(maxx, x), max(maxy, y)
            if v > 32 and 0.85 <= ru <= 1.15:
                sectors[int((math.degrees(math.atan2(y - cy, x - cx)) + 360) % 360)] = 1
    return {
        "clear_radius_px": round(min_r, 1),
        "clear_radius_unit": round(min_r / UNIT, 3),
        "edge_pixels_in_4px_border": edge,
        "alpha_centroid_offset_px": [round(sx / st - cx, 1), round(sy / st - cy, 1)],
        "bbox": [minx, miny, maxx, maxy],
        "bbox_center_offset_px": [round((minx + maxx) / 2 - cx, 1), round((miny + maxy) / 2 - cy, 1)],
        "ring_sectors_covered_of_360": sum(sectors),
        "mean_alpha_in_band_0.88_1.12": round(annulus / annulus_n, 3),
    }

def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def lum(rgb):
    r, g, b = rgb[:3]
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)

def card_metrics(path):
    im = Image.open(path).convert("RGBA")
    s = im.size[0] / 350.0
    # ProfileHero の本文列（ID〜自己紹介2行）に相当する矩形（pt）
    x0, y0, x1, y1 = [int(v * s) for v in (144, 34, 302, 172)]
    px = im.load()
    ls, ratios = [], []
    for y in range(y0, y1, 2):
        for x in range(x0, x1, 2):
            p = px[x, y]
            a = p[3] / 255
            # 透過部分は明るいページ背景(#F6F1E7)の上にあると仮定
            bg = tuple(p[i] * a + (246, 241, 231)[i] * (1 - a) for i in range(3))
            L = lum(bg)
            Lt = lum(tuple(255 - c for c in bg))  # 本体は白文字 + blendMode(.difference)
            hi, lo = max(L, Lt), min(L, Lt)
            ls.append(L); ratios.append((hi + 0.05) / (lo + 0.05))
    ls.sort(); ratios.sort()
    n = len(ls)
    mean = sum(ls) / n
    sd = (sum((v - mean) ** 2 for v in ls) / n) ** 0.5
    return {
        "text_zone_luminance_mean": round(mean, 3),
        "text_zone_luminance_sd": round(sd, 4),
        "difference_text_contrast_min": round(ratios[0], 2),
        "difference_text_contrast_p5": round(ratios[int(n * 0.05)], 2),
    }

def main():
    out = {"frames": {}, "cards": {}}
    pairs = {
        "leaf": os.path.join(REPO, "decoration-masters/Frames/profile_frame_free_leaf_corner.png"),
        "star": os.path.join(REPO, "decoration-masters/Frames/profile_frame_free_constellation.png"),
    }
    for m, orig in pairs.items():
        out["frames"][f"original-{m}"] = frame_metrics(orig)
        out["frames"][f"code-{m}"] = frame_metrics(os.path.join(R, f"code-{m}-frame-1024.png"))
        for v in ("original", "code"):
            out["cards"][f"{v}-{m}"] = card_metrics(os.path.join(R, f"plain-card-{v}-{m}.png"))
    with open(os.path.join(R, "validation.json"), "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(json.dumps(out, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
