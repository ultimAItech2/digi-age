# Validation

Recorded against source `1.0.0-rc2` on Linux (Godot 4.6.3.stable).

## Automated suites

Results for `1.0.0-rc3` (2026-11-11), `./tools/test.sh --soak`:

| Suite | What it covers | Result |
|---|---|---|
| `tests/simulation_test.gd` | Each rule on its own: economy, construction, navigation, research, combat, alerts, orders, abilities, shells, stances, terrain, faction units, saves, determinism | 169 checks, 0 failures |
| `tests/production_foundation_test.gd` | Missions, factions, objectives, corrupt saves, settings recovery | 21 checks, 0 failures |
| `tests/campaign_test.gd` | All eight missions load and run their events | 41 checks, 0 failures |
| `tests/audio_test.gd` | Buses, manifest, every sound and spoken alert has a trigger | 48 checks, 0 failures |
| `tests/interface_test.gd` | Real input route for selection, orders, building, training | 62 checks, 0 failures |
| `tests/integration_test.gd` | The whole game together through the real menu, HUD, input, opponent, audio and saves: alerts, save slots, campaign flow, skirmish, settings, credits, abilities, faction units | 88 checks, 0 failures |
| `tests/model_assets_test.gd` | Mesh and icon contract | 0 failures |
| `tests/sprite_cards_test.gd` | Sprite cards, both material paths | 0 failures |
| `tests/ui_production_test.gd` | 42 screens × 6 resolutions × 4 UI scales | 1,008 layouts, 411,589 checks, 0 failures |
| `tests/soak_test.gd` | Three opponent-against-opponent matches on the default map | 3 of 3 reach a winner (1,141 to 1,674 s of game time) |
| `tests/skirmish_test.gd` | Two opponents play a symmetric skirmish on each of the eight maps | 8 of 8 reach a winner; both sides scout, attack, field their faction unit and use abilities |

`tools/render_ui.sh` draws the same screens through the real renderer
(Xvfb, Mesa llvmpipe): 412,947 checks, 0 failures, 1,010 layouts, 378 captures.

`tests/rendered_match_test.gd` plays a whole skirmish through the real scene,
HUD and OpenGL renderer with an opponent on the player's side: it reached the
result screen at 1,239 s with all three ages seen and no renderer errors.
This run found that the Compatibility renderer supports only about 256
instances with per-instance shader parameters, so cards beyond roughly 128
entities lost their frame and colour; each card now owns its material on that
renderer (`DASprites.own_materials`).

`tests/balance_test.gd` (run by hand) plays every faction pairing on three
maps; its result is recorded under "Balance" below.

`./tools/test.sh` is the gate used by CI.

## World look

The battlefield presentation (`scripts/battlefield.gd`, `scripts/models.gd`,
`tools/create_industrial_assets.py`) was reworked without touching simulation
cells: the 72×72 grid, road bands, obstacles and pathing are read, never
written. Everything runs on the Compatibility renderer and the headless Dummy
renderer; no SSAO, SSR or volumetrics are used. Ground and water textures are
generated synchronously at mission start from `FastNoiseLite` (no imported
textures) and cached for the process, which keeps restarts cheap and avoids
leaking worker-thread textures on exit. One `Sky` is shared for the process
because the GL backend reports its radiance textures as leaked whenever a Sky
is released mid-session.

The second pass replaced the island with a world to the horizon. Fog of war is
no longer a mesh: a 74×74 `R8` texture (one texel per cell plus an explored
border) is rebuilt from `sim.explored`/`sim.visible` on every `refresh_fog()`,
blurred once and sampled bilinearly by world XZ in the ground, water and baked
model shaders (`DAModels.FOG_SHADER`). Unexplored ground drops to roughly 45%
and desaturates, explored-but-unseen to about 75%, visible is untouched, and
scenery is tinted in place rather than hidden; entity visibility still comes
from `sim.known()`. The camera is perspective (32° FOV, 50° elevation) with its
distance derived from the former orthographic `zoom`, so the zoom limits,
edge-pan speed, `ground_at()`/`screen_at()` and the minimap frustum (now a
trapezoid) are unchanged. Outside the 72×72 grid a 2-unit height grid
continues 110 units on every side, carved by three rivers (`RIVERS`), with the
map's road bands extended until they meet a bank; it is built once per map per
process and cached. The three `highrise_*` kit kinds cluster there (low-poly
exports, MultiMesh) and stand on solid 3×3 obstacle blocks inside the map.
Nothing in the simulation grid, obstacles, camera limits or pathing changed.

Two colour-space corrections ship with the pass: the kit now converts its sRGB
palette to linear before writing Blender base colours (glTF stores linear), and
the shared vertex-colour shader converts baked sRGB colours to linear. Before
these, every model rendered roughly two gamma lifts too pale. Portraits rendered
by `tools/render_thumbnails.py` pick up the corrected palette on their next run.

Verification: `./tools/test.sh` (all seven suites, 0 failures) and
`./tools/render_ui.sh` (203 captures, no error lines) after each pass. Low
profile and reduced effects were rendered and inspected at 1920×1080, as was
`builds/ui/1920x1080-100-core.png` for the smooth fog, perspective, rivers and
towers.

## Campaign contracts

All eight missions load, each with a unique map, authored events, and dialogue.
First Signal still completes from its required objectives in the campaign suite.
Salvage Rights prebuilds a Foundry outpost. Blackout starts without player
generators. Campaign unlocks write to `user://campaign.save` and reload.

## Audio

Voice lines, SFX, and four music beds were generated through Composio →
ElevenLabs and written under `assets/audio/`. Character usage for the generation
pass was 4,322 against a 202,489 Creator-tier monthly allotment. Headless tests
use the Dummy audio driver and must not fail if a clip is absent.

## Exports

`./tools/build.sh` produces Linux and Windows binaries plus archives. Recorded
hashes live in `builds/SHA256SUMS` after each packaging run (that directory is
gitignored except `.gitkeep`). Linux `DigitalAge.x86_64 --headless --quit`
exits 0. The extracted Linux package also passes `--headless -- --ui-smoke`,
which verifies menu startup and entry into a mission. Windows is produced and hashed only; no Windows machine signed off
this RC.

## Photoreal sprite cards

Buildings, units, deposits and scenery are drawn as camera-facing sprite
cards from the Blender-rendered atlases (`assets/sprites/README.md`), with
sheared cast shadows, contact shadows and faction discs. The earlier
AI-generated stills and their fallback code path are removed. `tests/sprite_cards_test.gd` covers the catalogue, card
geometry, pick boxes and the sun helpers; `tests/interface_test.gd` covers
facing rows, construction stages, ghost tint isolation,
rebuild after load, the low-profile shadow toggle and picking a card by its
drawn base. Reference capture: `docs/images/sprite-look.jpg`
(gl_compatibility, `--demo --zoom 24`); the same scene was captured on
Forward+ (lavapipe) and inspected. Exported packages ship the imported
textures rather than the PNGs, so `--ui-smoke` on the exported binary now
asserts that a Worker is drawn as a card with its sprite portrait
(`UI_EXPORT_SMOKE sprites: PASS` on the Linux export of this commit).
Headless `--benchmark` (188 sentinels, dummy renderer, this workstation):
39.9 ms CPU per frame before the sprite work, 37.9 ms after, so the cards do
not add CPU cost; GPU cost on the recommended PC is not measured.

## Not claimed

Steamworks live integration, a Windows runtime test, and external playtests
are still open. Nobody has played rc3 by hand: every result above comes from
automated runs. Prior GT 710 benchmark notes remain
indicative, not a release certificate.

## Presentation overhaul (2026-11-10)

- Camera: orthographic, fixed at 30 degrees elevation and 45 degrees yaw; Q/E
  rotation removed. Zoom is the view height, 14 to 46 cells.
- Buildings, units, deposits and scenery are atlases rendered from Blender
  (`assets/sprites/README.md`).
- The terrain's photo textures now load: `DABattlefield.imported()` only
  accepted a `path=` line, which array textures do not write, so the
  procedural fallback had been drawn instead.
- `tools/test.sh`: all eight suites pass. `tools/render_ui.sh`: 173,498
  checks, 0 failures over 482 layouts.
- Headless `--benchmark` (188 sentinels, dummy renderer, this workstation):
  43.0 ms CPU per frame, against 37.9 ms before. GPU cost is still unmeasured
  on real hardware.

## Presentation follow-up (2026-11-11)

- Added: unit death frames, building idle loops, smoke and fire on damaged
  buildings, impact sparks, a rally flag card, eased fog of war, shoreline
  foam and wet banks, 9-slice HUD plates rendered in Blender.
- `tools/test.sh`: all eight suites pass (interface 62 checks, production UI
  172,213 checks). `tools/render_ui.sh`: 173,533 checks, 0 failures.
- `./run.sh -- --benchmark` on the RTX 3070, Forward+, 1920x1080, 188
  sentinels: 55.1 fps over 17 s, 1,201 draw calls. With `--profile low`:
  58.3 fps, 964 draw calls. Vsync was on, so these are close to the 60 Hz cap
  rather than a ceiling; an uncapped run has not been made.
- `tools/render_scene.sh` writes the capture but exits non-zero on Godot's
  "1 resources still in use at exit" line, as it did before this work.
- Unit atlases are capped at 6,144 px wide; the Siege Walker and Disruptor
  are scaled down to fit (72 and 90 px per cell instead of 96).

## Release candidate 3 (2026-11-11)

- Scope: see `PRODUCTION_STATUS.md`, "Added in 1.0.0-rc3".
- `./run.sh --resolution 1920x1080 -- --benchmark` on the RTX 3070, 188
  Sentinels, map revealed, vsync off (the benchmark now disables it):
  70.6 fps on Forward+ (1,193 draw calls) and 65.2 fps on the Compatibility
  renderer (959 draw calls), both without renderer errors. The 60 fps target
  at about 200 units is met on this card; slower cards are not measured.
- Simulation cost in a 200-unit fight (headless, this workstation): 12.8 ms
  per tick at its worst before, 5.2 ms after (per-side target buckets, targets
  kept between ticks, one visibility stamp per occupied cell).
- `tools/build.sh`: Linux and Windows exports, archives and `SHA256SUMS`
  rebuilt; `tools/verify_packages.py` passes; the extracted Linux build passes
  `--ui-smoke`. The Windows executable carries the product name and version
  1.0.0.3 (no rcedit needed with Godot 4.6.3) and `assets/icon.ico`; it has
  not been run on Windows.
- Differences from the approved plan: cancelling is a command-grid button
  (the queue's small slots are below the 36 px minimum control height, so
  they are not clickable), and Escape keeps its pause meaning rather than
  cancelling production.

## Balance

`tests/balance_test.gd`: the opponent on both sides, nine faction pairings on
three maps (27 matches, 26 decided inside the limit). In the 18 mixed-faction
matches the Foundry won 8 of 12 (67%), Origin 5 of 12 (42%), the Lattice 4 of
12 (33%); the limit set for this pass was 70% for any faction. The side placed
at the map's first start won 17 of 26, so position matters about as much as
faction. These are opponent-against-opponent figures only; the Lattice in
particular is likely weaker in the opponent's hands than in a player's,
because the opponent does not exploit the Phantom's cloak.

The terrain painting (mud on rough ground, rock on high ground) is covered by
tests of the data and the minimap, but was not confirmed by eye: the captures
taken show those areas under trees.
