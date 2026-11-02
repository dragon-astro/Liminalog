"""Copy original XCTAttachments into the docs/37 review set (no resizing).

Usage: python3 export_evidence.py ATTACHMENTS_DIR light|dark before|after [MIN_NUMBER]
Export attachments first with xcrun xcresulttool export attachments.
last-export.json lists only this invocation. Do not archive the entire gallery.
"""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import sys

source = Path(sys.argv[1])
appearance, phase = sys.argv[2:4]
minimum_number = int(sys.argv[4]) if len(sys.argv) > 4 else 0
assert appearance in ('light', 'dark') and phase in ('before', 'after')
destination = Path(__file__).resolve().parent
index_path = destination / 'screenshots.json'
index = json.loads(index_path.read_text()) if index_path.exists() else {}
batch = {}
for test in json.loads((source / 'manifest.json').read_text()):
    for attachment in test['attachments']:
        name = attachment.get('suggestedHumanReadableName', '').split('_0_')[0]
        if not re.fullmatch(r'\d\d[a-z]?-[a-z0-9-]+', name):
            continue
        if int(name[:2]) < minimum_number:
            continue
        if name == '10-future-summary-tabs':
            continue  # The top view already contains the disabled actual tab.
        original = source / attachment['exportedFileName']
        if original.suffix != '.png':
            continue
        suffix = '-before' if phase == 'before' and name.startswith(('10-', '12-', '13-')) else ''
        output = destination / f'{name}{suffix}-{appearance}.png'
        data = original.read_bytes()
        width, height = struct.unpack('>II', data[16:24])
        is_se = '-se-' in name or name.endswith('-se')
        expected_pixels, scale = ((750, 1334), 2) if is_se else ((1206, 2622), 3)
        assert (width, height) == expected_pixels, (output.name, width, height)
        digest = hashlib.sha256(data).hexdigest()
        changed = not output.exists() or hashlib.sha256(output.read_bytes()).hexdigest() != digest
        if changed:
            shutil.copy2(original, output)
        index[output.name] = dict(
            phase=phase, appearance=appearance, pixels=[width, height], scale=scale,
            sha256=digest, bytes=len(data),
            test=test['testIdentifier'], attachments=str(source),
            original=attachment['exportedFileName'],
        )
        batch[output.name] = dict(sha256=digest, bytes=len(data), changed=changed)
index_path.write_text(json.dumps(dict(sorted(index.items())), indent=2, ensure_ascii=False) + '\n')
(destination / 'last-export.json').write_text(json.dumps(dict(
    exportedAt=datetime.now(timezone.utc).isoformat(),
    screenshots=batch,
    copiedBytes=sum(item['bytes'] for item in batch.values() if item['changed']),
), indent=2, ensure_ascii=False) + '\n')
print(f'{len(index)} original PNGs indexed in {destination}')
print(f'{len(batch)} screenshots in this invocation; see last-export.json')
