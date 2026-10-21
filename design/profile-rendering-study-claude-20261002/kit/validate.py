#!/usr/bin/env python3
"""装飾キットの数値検査（Pillow のみ）。./render.sh plain の出力を測る。

測るのは事故の有無だけで、審美判断の代わりにはならない。
  フレーム（1024px・透過）: 中心の透過半径 / 外周4pxの非透明画素 / bbox中心のずれ / 輪の途切れ / 帯の平均α
  カード（350×226pt @3x）: 本文列の背景に対する、テーマの文字色（主・副）のコントラスト比
"""
import json, math, os, glob
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PLAIN = os.path.join(HERE, "renders", "plain")
UNIT = 383.0

THEME = {
    "dusk": {"page": (13, 11, 22), "surface": (23, 19, 42), "text": (236, 232, 245), "secondary": (154, 147, 181)},
    "daybreak": {"page": (250, 245, 238), "surface": (255, 253, 249), "text": (47, 42, 48), "secondary": (107, 97, 102)},
}

def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def lum(rgb):
    return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])

def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def frame_metrics(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    a = im.getchannel("A").load()
    cx, cy = (w - 1) / 2, (h - 1) / 2
    min_r, edge = 1e9, 0
    minx, miny, maxx, maxy = w, h, -1, -1
    sectors = [0] * 360
    band, band_n = 0.0, 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            v = a[x, y]
            r = math.hypot(x - cx, y - cy)
            ru = r / UNIT
            if 0.88 <= ru <= 1.12:
                band += v / 255; band_n += 1
            if v <= 8:
                continue
            min_r = min(min_r, r)
            if x < 4 or y < 4 or x >= w - 4 or y >= h - 4:
                edge += 1
            minx, miny, maxx, maxy = min(minx, x), min(miny, y), max(maxx, x), max(maxy, y)
    # 輪の途切れ：帯（0.85〜1.15）の中は1画素ずつ見る（細い線の取りこぼしを防ぐ）
    for y in range(h):
        for x in range(w):
            ru = math.hypot(x - cx, y - cy) / UNIT
            if 0.85 <= ru <= 1.15 and a[x, y] > 32:
                sectors[int((math.degrees(math.atan2(y - cy, x - cx)) + 360) % 360)] = 1
    return {
        "clear_radius_unit": round(min_r / UNIT, 3),
        "edge_pixels": edge,
        "bbox_center_offset_px": [round((minx + maxx) / 2 - cx, 1), round((miny + maxy) / 2 - cy, 1)],
        "ring_sectors_of_360": sum(sectors),
        "band_mean_alpha": round(band / max(1, band_n), 3),
    }

def card_metrics(path, scheme):
    t = THEME[scheme]
    im = Image.open(path).convert("RGBA")
    s = im.size[0] / 350.0
    x0, y0, x1, y1 = [int(v * s) for v in (144, 34, 302, 172)]
    px = im.load()
    prim, sec = [], []
    for y in range(y0, y1, 2):
        for x in range(x0, x1, 2):
            p = px[x, y]
            al = p[3] / 255
            bg = tuple(p[i] * al + t["page"][i] * (1 - al) for i in range(3))
            prim.append(ratio(t["text"], bg))
            sec.append(ratio(t["secondary"], bg))
    prim.sort(); sec.sort()
    n = len(prim)
    return {
        "text_min": round(prim[0], 2), "text_p5": round(prim[int(n * 0.05)], 2),
        "secondary_min": round(sec[0], 2), "secondary_p5": round(sec[int(n * 0.05)], 2),
        "baseline_secondary_on_plain_surface": round(ratio(t["secondary"], t["surface"]), 2),
    }

def main():
    out = {"frames": {}, "cards": {}}
    for path in sorted(glob.glob(os.path.join(PLAIN, "frame-*.png"))):
        out["frames"][os.path.basename(path)[6:-4]] = frame_metrics(path)
    for path in sorted(glob.glob(os.path.join(PLAIN, "card-*.png"))):
        name = os.path.basename(path)[5:-4]
        scheme = name.rsplit("-", 1)[1]
        out["cards"][name] = card_metrics(path, scheme)
    with open(os.path.join(HERE, "renders", "validation.json"), "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    # 要約
    fr = out["frames"]; cd = out["cards"]
    print("frames:", len(fr), "cards:", len(cd))
    print("min clear radius:", min(v["clear_radius_unit"] for v in fr.values()),
          "| edge pixels total:", sum(v["edge_pixels"] for v in fr.values()),
          "| ring gaps:", [k for k, v in fr.items() if v["ring_sectors_of_360"] < 360])
    worst = sorted(fr.items(), key=lambda kv: -max(abs(kv[1]["bbox_center_offset_px"][0]), abs(kv[1]["bbox_center_offset_px"][1])))[:6]
    print("largest bbox offsets:", [(k, v["bbox_center_offset_px"]) for k, v in worst])
    print("cards text p5 min:", min(v["text_p5"] for v in cd.values()), "| secondary p5 min:", min(v["secondary_p5"] for v in cd.values()))
    low = sorted(cd.items(), key=lambda kv: kv[1]["secondary_p5"])[:6]
    print("lowest secondary p5:", [(k, v["secondary_p5"], v["secondary_min"]) for k, v in low])

if __name__ == "__main__":
    main()
