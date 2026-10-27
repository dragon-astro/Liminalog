"""Measure original Simulator PNGs and assemble native-size week crops (docs/38 §16).

Run after export_evidence.py, passing successful xcresult attachment directories.
Requires Pillow. The full-screen PNGs are never modified or resampled.
"""
import colorsys
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parent
index = json.loads((root / 'screenshots.json').read_text())
variants = ['v0', 'past-55', 'past-50']
categories = [
    ('blue', '仕事', '#537BC5', 220, 25, 28),
    ('purple', '読書', '#995DC4', 280, 25, 28),
    ('orange', '用事（買い物）', '#C37A42', 28, 26, 29),
    ('green', '運動', '#389D70', 150, 26, 29),
    ('pink', '休み', '#D96996', 337, 26, 29),
]
metadata = {}
for folder in map(Path, sys.argv[1:]):
    for test in json.loads((folder / 'manifest.json').read_text()):
        for attachment in test['attachments']:
            name = attachment.get('suggestedHumanReadableName', '').split('_0_')[0]
            if name.startswith('46-past-opacity-') and name.endswith('-geometry'):
                metadata[name.removesuffix('-geometry')] = json.loads((folder / attachment['exportedFileName']).read_text())


def linear(v):
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    return sum(weight * linear(v) for weight, v in zip((0.2126, 0.7152, 0.0722), rgb))


def lightness(rgb):
    r, g, b = map(linear, rgb)
    x = (0.4122214708*r + 0.5363325363*g + 0.0514459929*b) ** (1/3)
    y = (0.2119034982*r + 0.6806995451*g + 0.1073969566*b) ** (1/3)
    z = (0.0883024619*r + 0.2817188376*g + 0.6299787005*b) ** (1/3)
    return 0.2104542553*x + 0.7936177850*y - 0.0040720468*z


def hex_color(rgb):
    return '#%02X%02X%02X' % rgb


def sample(im, cell, scale, hue):
    x, y, w, h = cell
    box = tuple(round(v * scale) for v in (x + 5, y + 28, x + w - 5, y + 90))
    counts = Counter(im.crop(box).get_flattened_data())
    candidates = []
    for rgb, count in counts.items():
        hsv = colorsys.rgb_to_hsv(*(v/255 for v in rgb))
        distance = abs((hsv[0]*360 - hue + 180) % 360 - 180)
        if hsv[1] > 0.13 and distance < 24:
            candidates.append((count, rgb))
    count, rgb = max(candidates)
    assert count >= 120, (box, hue, count, rgb)
    return rgb, {'regionPixels': list(box), 'matchingFillPixels': count}


measurements = []
geometry = {}
assert len(metadata) == 9, 'Expected six default and three 7.5pt captures'
capture_checks = []
for stem, meta in metadata.items():
    name = stem + '-light.png'
    im = Image.open(root / name).convert('RGB')
    scale = index[name]['scale']
    assert im.size == ((750, 1334) if '-se' in stem else (1206, 2622))
    checked = []
    for key, _, _, hue, past_day, future_day in categories:
        past, _ = sample(im, meta['cells'][str(past_day)], scale, hue)
        future, _ = sample(im, meta['cells'][str(future_day)], scale, hue)
        assert luminance(past) > luminance(future), (stem, key)
        checked.append(key)
    capture_checks.append(dict(image=name, verifiedPastAndFutureCategories=checked))
for theme in ('daybreak', 'aurora'):
    for variant in variants:
        stem = '46-past-opacity-' + variant + ('-aurora' if theme == 'aurora' else '')
        meta = metadata[stem]
        name = stem + '-light.png'
        im = Image.open(root / name).convert('RGB')
        scale = index[name]['scale']
        geometry[stem] = meta
        for key, label, source, hue, past_day, future_day in categories:
            past, past_sample = sample(im, meta['cells'][str(past_day)], scale, hue)
            future, future_sample = sample(im, meta['cells'][str(future_day)], scale, hue)
            future_contrast = 1.05 / (luminance(future) + 0.05)
            past_contrast = 1.05 / (luminance(past) + 0.05)
            baseline_name = '45-past-compare-v0' + ('-aurora' if theme == 'aurora' else '') + '-light.png'
            baseline = Image.open(root / baseline_name).convert('RGB')
            box = future_sample['regionPixels']
            assert im.crop(box).tobytes() == baseline.crop(box).tobytes(), (theme, variant, key, 'future changed')
            density = (1 - lightness(past)) / (1 - lightness(future))
            # Also retain encoded-sRGB density for comparison to the reference's alpha estimate.
            fw = [255 - v for v in future]
            pw = [255 - v for v in past]
            srgb_density = sum(a*b for a, b in zip(fw, pw)) / sum(a*a for a in fw)
            measurements.append(dict(theme=theme, variant=variant, category=key, label=label, sourceHex=source,
                futureHex=hex_color(future), pastHex=hex_color(past), futureWhiteContrast=round(future_contrast, 4),
                pastWhiteContrast=round(past_contrast, 4), perceptualDensity=round(density, 4),
                encodedSRGBDensity=round(srgb_density, 4), sourceImage=name,
                sample=dict(past=past_sample, future=future_sample)))

font_path = '/System/Library/Fonts/Hiragino Sans GB.ttc'
font = ImageFont.truetype(font_path, 27)
small = ImageFont.truetype(font_path, 18)
sheets = []
for theme, title in [('daybreak', '曙'), ('aurora', '極光')]:
    crops = []
    for variant in variants:
        stem = '46-past-opacity-' + variant + ('-aurora' if theme == 'aurora' else '')
        name = stem + '-light.png'
        cells = metadata[stem]['cells']
        x, y, w, h = cells['25']
        last = cells['31']
        box = (0, round(y*3), 1206, round((y+h)*3))
        assert all(abs(c[1] - y) < 0.5 for c in cells.values())
        im = Image.open(root / name).convert('RGB')
        crop = im.crop(box)
        crops.append((variant, name, box, crop))
    assert len({crop.size for _, _, _, crop in crops}) == 1
    left, top, gap = 225, 95, 16
    row_h = crops[0][3].height
    sheet = Image.new('RGB', (left+1206+24, top+(row_h+gap)*len(variants)+20), '#F0F0F2')
    draw = ImageDraw.Draw(sheet)
    draw.text((24, 18), title + '  元の予定の濃さを固定', font=font, fill='#24242B')
    draw.text((left, 57), '25・26日：過去　／　28-31日：未来　　文字6pt・原寸表示', font=small, fill='#52525A')
    crop_records = []
    for i, (variant, name, box, crop) in enumerate(crops):
        y = top+i*(row_h+gap)
        label = {'v0': '現行', 'past-55': '背景55%', 'past-50': '背景50%'}[variant]
        draw.text((24, y+26), label, font=font, fill='#24242B')
        detail = ['全体65%', '白文字も透過'] if variant == 'v0' else ['背景のみ透過', '白文字は維持']
        for j, line in enumerate(detail):
            draw.text((24, y+72+j*30), line, font=small, fill='#52525A')
        sheet.paste(crop, (left, y))
        assert sheet.crop((left, y, left+crop.width, y+crop.height)).tobytes() == crop.tobytes()
        crop_records.append(dict(source=name, sourceBox=box, destination=[left, y], sourceSHA256=index[name]['sha256']))
    name = '46-past-opacity-sheet-' + theme + '.png'
    sheet.save(root / name)
    sheets.append(dict(file=name, pixels=list(sheet.size), sha256=hashlib.sha256((root/name).read_bytes()).hexdigest(),
                       crops=crop_records, resampled=False))

output = dict(schemaVersion=1, scope='DEBUG comparison only; production opacity/defaults unchanged',
    referenceDate='2026-10-27T12:00:00+09:00', devices=['iPhone 17 / iOS 26.5'],
    futurePixelsMatchOriginal=True, defaultFontSize=6, largeFontSize=7.5,
    method=dict(colors='Modal flat-fill RGB pixels, excluding neutral pixels and category hues outside ±24 degrees',
                contrast='WCAG relative luminance in linear sRGB; white=(1,1,1); 1.05/(Y+0.05)',
                density='(1-OKLab L_past)/(1-OKLab L_future); diagnostic only, no color conversion in app',
                encodedSRGBDensity='projection of white-minus-past on white-minus-future (reference alpha estimate)',
                border='Past fill and edge composited together then faded; text remains white; future unchanged',
                sources=['https://bottosson.github.io/posts/oklab/',
                         'https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html']),
    measurements=measurements, sheets=sheets, captureGeometry=metadata, captureChecks=capture_checks)
(root / 'past-opacity-compare.json').write_text(json.dumps(output, ensure_ascii=False, indent=2)+'\n')
print(f'{len(metadata)} captures; {len(measurements)} color measurements; {len(sheets)} original-pixel comparison sheets')
