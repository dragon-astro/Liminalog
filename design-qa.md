# Day preset editor design QA

This is the original design comparison record. The app now has a UI-test target;
current calendar interaction results are recorded in
`Liminalog/Views/Profile/docs/37-codex-handoff-ui-batch-20261021.md`.

- source visual truth: `/Users/ryu/.codex/generated_images/01a05b1c-af5d-7cb1-bcfa-579e6203eba7/exec-38551215-c8ff-42b5-8dd5-465fcdf88e3f.png`
- implementation screenshots: `/private/tmp/liminalog-day-preset-editor-expanded-3.png`, `/private/tmp/liminalog-day-preset-editor-collapsed-2.png`
- full-view comparison: `/private/tmp/liminalog-day-preset-comparison.png`
- focused drawer comparison: `/private/tmp/liminalog-day-preset-drawer-comparison.png`
- viewport: iPhone 17 simulator, 402 x 874 points
- pixels and normalization: source 853 x 1844 px; implementation 1206 x 2622 px at 3x. The source was proportionally scaled to 1212 x 2622 px before horizontal comparison; the 6 px width difference was retained rather than distorting either image.
- state: new day preset, empty timeline, library drawer checked both collapsed and expanded. The source contains sample timeline items, so content-density differences above the drawer are not treated as layout mismatches.

## Findings

No actionable P0/P1/P2 visual differences remain.

- Fonts and typography: implementation uses the app's existing SwiftUI type hierarchy. Header, tile title, time, and action copy preserve the source hierarchy and remain legible at the real device scale.
- Spacing and layout rhythm: the drawer, grabber, quick shelf, filter row, search, and two-column library follow the source composition. Tiles are intentionally slightly larger to preserve Liminalog's touch targets and avoid truncating Japanese action labels.
- Colors and visual tokens: the implementation uses `LiminalTheme` surfaces, text, divider, accent, and category colors rather than sampling hard-coded mock colors. The warm canvas and translucent elevated surfaces remain consistent with the surrounding app.
- Image and icon fidelity: the mock's functional iconography is represented with existing SF Symbols and category icons. No new raster asset, custom SVG, emoji, or placeholder graphic was introduced.
- Copy and content: fixed-time cards say `タップで追加`; duration cards say `長押しして配置`. The expanded drawer retains category filters, search, sorting, and the complete library.

## Comparison history

1. Initial simulator capture found a P1 layout issue: the 00:00 rail began near the middle of the empty timeline because the timeline content frame centered its child stack.
2. Fixed the timeline content frame to fill its width and align its content to `.topLeading`.
3. Revised collapsed and expanded captures show 00:00 at the timeline top, with the placement area readable in both drawer states. The combined full-view and focused drawer comparisons show no remaining P0/P1/P2 mismatch.

## Interaction checks

- Collapsed and expanded drawer states render from the same production view.
- Fixed-time and duration placement behavior is covered by model/store tests, including preserved duration, fixed-time mode persistence, overlap rejection, and atomic day application.
- Automated pointer-level long-press/drag coverage remains unavailable because this project has no UI-test target; final physical interaction feel should still be checked on device.

## Follow-up polish

- P3: after device use, the full-library tile height can be reduced slightly if the two-column grid feels too spacious. Do not reduce the long-press hit area below the current size.

final result: passed

## Local design evidence checkpoint (2026-10-21)

The 281 generated PNG comparisons under `design/` (about 355 MiB) remain at their
original local paths and are excluded from Git. Design notes, generation scripts,
Swift prototypes, validation data, and `design/generated-images-manifest.json`
are versioned. The manifest records each image's size and SHA-256 so the local
evidence can be checked without placing all comparison renders in the source
history. These prototypes and images do not imply adoption in the app.

Before cleanup, all untracked files were backed up to
`artifacts/device-cleanup-20261021/untracked-before.tar.gz`. Tracked changes and
the file inventory are beside it as `before.patch` and `before-inventory.json`.
The archive is local and ignored by Git; no comparison images were deleted.
