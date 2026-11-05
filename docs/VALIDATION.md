# Validation

Recorded against source `1.0.0-rc2` on Linux (Godot 4.6.3.stable).

## Automated suites

| Suite | Result |
|---|---|
| `tests/simulation_test.gd` | 49 checks, 0 failures |
| `tests/production_foundation_test.gd` | 15 checks, 0 failures |
| `tests/campaign_test.gd` | 41 checks, 0 failures |
| `tests/audio_test.gd` | 16 checks, 0 failures |
| `tests/interface_test.gd` | 33 checks, 0 failures |
| `tests/model_assets_test.gd` | Blender asset contract, 0 failures |
| `tests/ui_production_test.gd` | 405 layout scenarios, 0 failures |

Rendered UI verification adds fullscreen/windowed transitions and 189 PNG
captures using the real Godot renderer on Xvfb/Mesa llvmpipe. See
`UI_VERIFICATION.md` and the generated `builds/ui/index.html` gallery.

`./tools/test.sh` is the gate used by CI. `--soak` remains available for three
bot-versus-bot matches on the default map.

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

Buildings, units and deposits are drawn as camera-facing sprite cards from
the Age of AI set (`assets/sprites/README.md`), with sheared cast shadows,
contact shadows and faction discs; Siege Walker and the data archive keep
their Blender models. `tests/sprite_cards_test.gd` covers the catalogue, card
geometry, pick boxes and the sun helpers; `tests/interface_test.gd` covers
facing flip against the camera yaw, construction rise, ghost tint isolation,
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

Steamworks live integration, extended 200-unit 1080p performance targets, and
external playtests are still open. Prior GT 710 benchmark notes remain
indicative, not a release certificate.
