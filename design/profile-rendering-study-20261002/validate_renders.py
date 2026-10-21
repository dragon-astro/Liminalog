"""Structural gates for this study, not an aesthetic approval or performance test."""
from pathlib import Path
import json
import math
from PIL import Image

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'renders'
results = []

def linear(v):
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

def luminance(rgb):
    return sum(linear(c) * w for c, w in zip(rgb, (0.2126, 0.7152, 0.0722)))

for motif in ('botanical', 'celestial'):
    for dim in (1024, 2048):
        path = OUT / f'{motif}-frame-{dim}.png'
        im = Image.open(path).convert('RGBA')
        assert im.size == (dim, dim), path
        a = im.getchannel('A')
        pixels = a.load()
        center = (dim - 1) / 2
        min_radius = dim
        central_alpha_max = 0
        edge_alpha_max = 0
        for y in range(dim):
            for x in range(dim):
                alpha = pixels[x, y]
                r = math.hypot(x-center, y-center)
                if r < dim*0.30:
                    central_alpha_max = max(central_alpha_max, alpha)
                if x < 4 or y < 4 or x >= dim-4 or y >= dim-4:
                    edge_alpha_max = max(edge_alpha_max, alpha)
                if alpha >= 16:
                    min_radius = min(min_radius, r)
        assert central_alpha_max == 0, (path, 'avatar intrusion')
        assert edge_alpha_max == 0, (path, 'clipped outer edge')
        # Continuous body must straddle the explicitly designed guide circle.
        radial_hits = 0
        for degree in range(360):
            angle = math.radians(degree)
            if any(pixels[round(center+math.cos(angle)*dim*r/1000),round(center+math.sin(angle)*dim*r/1000)] >= 32 for r in range(373,391)):
                radial_hits += 1
        assert radial_hits >= 356, (path, 'discontinuous ring guide', radial_hits)
        results.append(dict(file=path.name, size=list(im.size), central_clear_radius_fraction=0.30,
                            central_alpha_max=central_alpha_max, edge_alpha_max=edge_alpha_max,
                            visible_inner_radius_fraction=round(min_radius/dim,4),
                            guide_angular_coverage=radial_hits/360,
                            alpha_bbox=a.getbbox(), status='pass'))
    card = Image.open(OUT / f'{motif}-card.png').convert('RGBA')
    assert card.size == (2048, 1365)
    # Normal-size hero's text column, expressed as background fractions.
    region = card.crop((int(card.width*.40),int(card.height*.15),int(card.width*.93),int(card.height*.76)))
    max_luma = max(luminance(px[:3]) for px in region.getdata())
    body_luma = luminance((0xD3,0xDF,0xE1))
    contrast = (body_luma+.05)/(max_luma+.05)
    assert contrast >= 4.5, (motif, 'body contrast', contrast)
    results.append(dict(file=f'{motif}-card.png',size=list(card.size),text_safe_zone=[.40,.15,.93,.76],
                        body_color='#D3DFE1',min_static_background_contrast=round(contrast,2),status='pass'))
(OUT/'validation.json').write_text(json.dumps({'status':'pass','scope':'structural gates only; aesthetic adoption pending','checks':results},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':'pass','checks':len(results),'contrast':{r['file']:r['min_static_background_contrast'] for r in results if 'min_static_background_contrast' in r}},ensure_ascii=False))
