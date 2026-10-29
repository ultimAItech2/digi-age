# Desktop UI verification — 1.0.0-rc2

## Supported desktop matrix

1280×720, 1600×900, 1920×1080, 2560×1080, and 3440×1440 at 100%, 115%,
and 125% UI scale. The battlefield uses the full viewport; essential HUD
content is centered within a maximum 1920 logical pixels. Tests exercise
the underlying layout at each exact resolution, independently of OS scaling.

The interface remains immediate-mode. A shared layout model supplies stable
control IDs, hit regions, text bounds, clipping, and focus order before drawing.
Fonts and geometry scale together; the Control root is not enlarged. Cached
font measurement and style resources are reused. Content refreshes at 10 Hz;
input, viewport changes, and modal transitions force a fresh layout.

## HUD layout

- A 52 px translucent top bar: resource groups (icon, total, income per minute
  from `DASimulation.income_per_minute`), population, the centred display title
  (Cinzel, hidden when it would collide with the resource or navigation blocks),
  and TECH / UNITS / BUILD / OBJECTIVES navigation plus the ≡ pause button.
- The world fills everything below the top bar. Floating panels register as
  blocked regions: the minimap frame with a five-button side column
  (focus Core, speed, manual, settings, sound), the selection panel, the
  objectives panel (toggle), captions, and the order-mode notice strip.
- The selection panel (160 px tall, up to 980 px wide) shows a rendered
  portrait with a health bar, name, role, status and description, thumbnail
  production/build slots, a 2×2 icon command block (attack/stop, age and weapons
  research, rally) and an "active job" slot with progress. It has three tiers:
  A (≥ 960 px: full), B (≥ 800 px: no description, smaller slots) and
  C (< 800 px, e.g. 1280×720 at 125 %: no portrait). Numbers shrink or compact
  (`99.9K`, `1.2M`) and descriptions shrink before they would be truncated.
- Icons are 24 px SVGs rasterised at the physical size (`assets/ui/icons/`,
  `importer="keep"`); portraits are Blender renders in `assets/ui/portraits/`
  with an icon fallback when a render is missing.
- Palette constants are opaque so the contrast test measures them honestly;
  panel alpha is applied at draw time. Control borders use `LINE`; decorative
  separators use `LINE_SOFT` and are never a control boundary.

## Interaction and persistence

- Mouse buttons activate on release inside the pressed control. Tab/Shift+Tab
  navigate, Enter activates, and offscreen settings controls scroll into view.
- Settings, manual, pause, results, and confirmation dialogs block world input.
  Settings/manual suspend simulation without changing the previous game mode.
  Escape cancels rebinding before closing the top overlay, then cancels an
  order mode before pausing gameplay. Opening overlays cancels active drags.
- Settings and manual scroll by wheel, arrows, or Page Up/Down. Close controls
  remain accessible. Keyboard prompts use the currently saved bindings.
- Settings changes are validated and atomically committed. Failed writes
  restore the previously committed values. Invalid or older preferences merge
  with defaults. Categories can be reset separately; reset-all asks first.
- Conflicting bindings, modifiers alone, camera/group keys, and interface
  navigation keys are rejected with an explanation.
- Leaving an unsaved active session asks for confirmation. Save-and-continue
  only leaves after a successful save. Missing, malformed, and different-mission
  saves cannot partially replace the current simulation. To load a different
  mission's save, select and launch that mission first.
- Disabled actions describe their actual resource, age, compute, queue, or
  research requirement. Informative text meets the tested 4.5:1 contrast target;
  control boundaries meet 3:1 across the defined button states. Status labels
  accompany warning, completion, locked, and unavailable colors.
- Captions follow the voice queue and are split into readable pages. Muted or
  missing voice still advances the same caption queue using reading time.

## Reproduce the checks

```bash
./tools/test.sh
./tools/render_ui.sh
DA_TEST_HOME=/tmp/digital-age-ui-benchmark ./tools/godot.sh --headless --script tests/ui_benchmark.gd
./tools/build.sh
```

Tests and captures use isolated temporary user-data directories; player saves
and preferences are not used. The render command uses Xvfb and Mesa software
rendering, not the user's visible desktop. Install Xvfb or set `XVFB_BIN` to an
existing executable. On this workstation an official Ubuntu Xvfb package was
extracted under `.tools/virtual-display/runtime` without a system installation.

The production suite exercises 29 screens/states × 5 resolutions × 3 scales:
435 layout scenarios, plus two rendered fullscreen/windowed transition checks.
Checks cover control overlap, text bounds, clipping, minimum button height,
contrast, modal input, settings recovery, caption queueing, and failed saves.
Manual text and captions are explicitly checked for unwanted abbreviation.
Build, pause, resume, and minimap camera/order clicks are exercised at every
resolution and UI scale through the actual controller input route.

Actual renderer capture produces 189 PNGs: every state at all five resolutions
at 100%, plus 115% and 125% at 1280×720. The local `builds/ui/index.html` gallery
links the original PNGs. `layout-report.json` records the renderer results;
`layout-report-headless.json` records structural checks separately. CI runs both
suites and uploads the captures. Representative minimum-size, high-scale and
ultrawide screens were visually inspected in addition to automated checks.

## Evidence and release limits

Recorded on Linux with Godot 4.6.3, Xvfb and Mesa llvmpipe (LLVM 20.1.2).
The existing suites pass with 154 checks; the Blender model contract also passes.
The production matrix and rendered transition checks report zero failures.
Exact generated assertion totals are in the JSON reports; these totals are
geometry assertions, not counts of independent gameplay scenarios.

A 200-unit, 1600×900 headless process-time diagnostic measured 38.88 ms before
and 40.14 ms after the UI changes (about +3.2%). It includes engine processing,
is not an isolated UI profiler or GPU benchmark, and does not establish a
60-fps gameplay target. UI layout work is separately timed in the JSON reports.

Linux and Windows packages contain `BUILD_ID.json` with a runtime-source
SHA-256 identity. Archives have checksums in `builds/SHA256SUMS`. Linux package
verification launches the extracted executable and checks the menu and entry
into a mission with `--headless -- --ui-smoke` in isolated user data.

Windows export and archive validation do not constitute a Windows runtime
playtest. Physical Windows hardware, OS-specific DPI behavior, external
usability playtests and production-hardware performance remain release gates.
Controller support, localization and screen-reader support are not claimed.
