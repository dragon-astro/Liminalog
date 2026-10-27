"""Capture docs/38 §16 on the dedicated iPhone 17 Simulator via explicit launch args.

Usage: python3 capture_past_comparison.py OUTPUT_DIR [daybreak|aurora]
Install the Debug app first. Does not operate on the user's Simulator or physical device.
"""
import json
from pathlib import Path
import re
import subprocess
import sys
import time

device = '5DA1E432-0D01-42A6-8259-B59A9CEC7854'
bundle = 'app.YasudaRyuga.Liminalog'
output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
themes = [sys.argv[2]] if len(sys.argv) > 2 else ['daybreak', 'aurora']
assert all(theme in ('daybreak', 'aurora') for theme in themes)
manifest = []
if (output/'manifest.json').exists():
    manifest = json.loads((output/'manifest.json').read_text())
subprocess.run(['xcrun', 'simctl', 'ui', device, 'appearance', 'light'], check=True)
for theme in themes:
    cases = [(variant, '6') for variant in ['v0', 'past-55', 'past-50']]
    if theme == 'daybreak':
        cases += [(variant, '7.5') for variant in ['v0', 'past-55', 'past-50']]
    for variant, font in cases:
        stem = '46-past-opacity-' + variant + ('-large' if font == '7.5' else '') + ('-aurora' if theme == 'aurora' else '')
        arguments = ['-LiminalogMonthDrawerUITests', '-LiminalogPastPlanComparison', variant,
            '-LiminalogInitialRootTab', 'calendar', '-LiminalogInitialCalendarMode', 'month',
            '-LiminalogUITestTheme', theme, '-calendar.filter.usesCustomCategories', 'NO',
            '-calendarPlanTitleFontSize', font, '-calendarShowsPlanStartTime', 'YES',
            '-calendarDimPastPlans', 'YES', '-calendarStrikePastPlans', 'NO',
            '-calendarTimedPlanLabelStyle', 'background', '-calendarAllDayPlanLabelStyle', 'background',
            '-calendarMultiDayPlanLabelStyle', 'background']
        result = subprocess.check_output(['xcrun', 'simctl', 'launch', '--terminate-running-process', device, bundle] + arguments, text=True)
        pid = re.search(r': (\d+)', result).group(1)
        command = subprocess.check_output(['ps', '-p', pid, '-o', 'command='], text=True).strip()
        assert ' '.join(arguments) in command, command
        time.sleep(3)
        subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(output/(stem+'.png'))], check=True, capture_output=True)
        # Verified from full-size PNG grid dividers: last week begins at y=1971px,
        # with a 363px content row. Column positions follow SwiftUI pixel rounding.
        cells = {}
        for i, day in enumerate(range(25, 32)):
            left = round(i * 1209/7)
            right = round((i+1) * 1209/7) - 3
            cells[str(day)] = [left/3, 657, (right-left)/3, 121]
        meta = dict(variant=variant, theme=theme, fontSize=font, cells=cells,
                    referenceDate='2026-10-27T12:00:00+09:00', launchCommand=command,
                    geometrySource='Pixel-verified calendar grid, not an accessibility frame')
        (output/(stem+'-geometry.json')).write_text(json.dumps(meta, ensure_ascii=False, indent=2)+'\n')
        test_id = f'simctl/{theme}/{variant}/font-{font}'
        manifest = [m for m in manifest if m['testIdentifier'] != test_id]
        manifest.append(dict(testIdentifier=test_id, attachments=[
            dict(suggestedHumanReadableName=stem, exportedFileName=stem+'.png'),
            dict(suggestedHumanReadableName=stem+'-geometry', exportedFileName=stem+'-geometry.json')]))
        (output/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
        print(stem, 'captured; launch arguments verified', flush=True)
