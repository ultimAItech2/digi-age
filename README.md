# Digital Age: Machine Civilizations

An original, offline, single-player desktop RTS built with Godot 4.6.3 and
typed GDScript. Lead the Origin Collective through an eight-mission campaign,
or play a skirmish on any of the eight maps as the Origin Collective, the
Foundry or the Lattice against an opponent at three difficulty levels.
Version 1.0.0-rc3. No network services are required to play.

## Play

- **Linux:** extract `DigitalAge-linux-x86_64.tar.gz`, then double-click
  `DigitalAge.x86_64` (or run `./DigitalAge.x86_64`). From this source workspace,
  run `./run.sh`. This always launches the current source; use `./run.sh --packaged`
  explicitly to launch the last Linux export.
- **Windows:** extract `DigitalAge-windows-x86_64.zip` and run `DigitalAge.exe`.
- **Launch Campaign** begins the selected mission; a win offers the next one.
  **Skirmish** opens a setup screen: map (with a preview), your faction, the
  rival faction, starting resources, start position and difficulty. Both sides
  open with a Core, four Workers and a Scout.
- **Difficulty** (Easy, Normal, Hard) changes how fast the opponent expands and
  attacks; Hard also gathers 15% faster. It never receives free resources.
- The in-game **Field Manual** (F1) explains the economy, ages, counters,
  abilities, terrain and controls. **Credits** shows the shipped credits file.

The desktop builds are self-contained; players do not need Godot installed.
Windows runtime testing status and measured performance are in
`docs/VALIDATION.md` in the source project (or `VALIDATION.md` in a desktop archive).

### Saving

Save Game and Load Game on the pause menu (and Load Game on the main menu) open
three manual slots and the three checkpoints the campaign saves automatically.
F5 and F9 quick-save and quick-load the first manual slot. A save holds the
match, the opponent's state, your control groups and the game speed; loading a
save from another mission or from a skirmish switches to it. Campaign unlocks
and settings are stored separately.

## The world

The world is seen from a fixed dimetric camera (orthographic, 30 degrees above
the ground, 45 degrees to the grid). Buildings, units, deposits, trees and
ruins are sprite cards standing in the 3D world, rendered from Blender models
into atlases (`assets/sprites/rendered/`; `assets/sprites/README.md` describes
the pipeline and `tools/render_sprites.sh` rebuilds them). Buildings go up in
three scaffolded stages, run a short idle loop when finished, smoke and burn
as they take damage and leave a wreck. Units have eight facings with idle,
move, attack and death frames. The parts painted in the faction colour are
recoloured per side, and every card casts a sun-sheared silhouette shadow.

The HUD is a top bar (resources with income, population, the current age and
clock, quick buttons) over a full-width bottom dock holding a diamond minimap,
the selection panel and a 5 x 3 command grid on the keys Q-T, A-G and Z-B. The
technology tree opens from the top bar. Panels and buttons use 9-slice plates
rendered in Blender (`assets/ui/frames/`, `tools/sprites/ui.py`).

The game tells you what happens off screen: an attack on your units or
buildings sounds an alarm, speaks, shows an alert and pings the minimap (N
jumps the camera there); finished buildings and units, completed research, a
full population cap, an exhausted deposit and a lost Core are announced too.

The desktop UI supports 1280×720 through 3840×2160, with 100%, 115%, 125% and
150% UI scale (a scale too large for the window is fitted down). Tab/Shift+Tab
navigate controls, Enter activates, and Escape closes the top overlay.
Settings, the manual and the credits scroll with the wheel, arrows, or Page
Up/Down. Restarting or leaving an unsaved match offers save-and-continue.
See `docs/UI_VERIFICATION.md` for the verification matrix.

## Start a civilization

1. Select Workers and right-click a golden salvage deposit. Metal pays for
   buildings and units. Workers carry 24 resources to a Core or Salvage Depot,
   and move on to the next deposit nearby when theirs runs out.
2. Explore with your Scout and assign some Workers to violet data archives.
   Data pays for ages, research and advanced units.
3. Build a Fabricator and additional Generators. Generators produce 3 energy/s.
4. Build Data Centers as your army grows. Each grants 20 population capacity,
   capped at 100.
5. Research Network and Singularity at your Core, and upgrades at Research Labs.

### Units

| Unit | Role | Strong against | Ability |
|---|---|---|---|
| Worker | Gathers, builds, repairs | | |
| Scout | Fast, wide sight, hovers | | Sensor sweep: reveals a circle, cloaked units included |
| Sentinel | Frontline infantry | Armoured units (×2) | Overdrive: fires 50% faster for 6 s |
| Disruptor | Artillery, shells splash | Heavy units (×3) | EMP shell: stuns units for 3 s |
| Siege Walker | Heavy siege, shells splash | Buildings (×3) | Brace: +3 range, +50% to buildings, cannot move |
| Warden (Origin) | Shield carrier | | Units within 4 cells take 25% less damage |
| Mortar (Foundry) | Long-range launcher, wide splash | Buildings (×1.5) | |
| Phantom (Lattice) | Cloaked hover raider | Light units (×1.5) | Unseen unless an enemy is within 4 cells |

Each faction fields its own unit from the Network age. Counters, armour
classes, abilities and terrain effects are data in `data/catalog.tres` and
`scripts/catalog.gd`.

### Ground

Roads carry units 25% faster. Rough ground around ruins slows everything that
does not hover by 35% and costs more to path through. Units on high ground see
two cells farther and shoot one cell farther. Buildings you have scouted stay
marked in the fog; units do not.

### Winning and losing

Destroy the rival Core. A side that loses its Core but still has Workers has
two minutes to raise a new one (Workers can build a Core only then); with no
Workers the match ends at once. The opponent rebuilds too.

The opponent plays by the same economy and vision rules: it scouts, attacks
what it has seen, expands to new deposits, retreats when outnumbered, answers
the units it meets and uses its units' abilities.

## Controls

| Input | Action |
|---|---|
| Left click / drag | Select an entity / your units |
| Shift + select | Add to selection; click a selected entity to remove it |
| Double-click a unit | Select every unit of that type in view |
| Right click | Move, gather, attack, repair, or resume construction |
| Building selected + right click | Set production rally point |
| Command grid (Q-T, A-G, Z-B) | The selection's commands, in the order shown |
| A, then left click | Attack-move |
| S / D / F | Stop / hold position / patrol (then click the far end) |
| G | Switch stance: defensive or aggressive |
| Q (combat unit) | The unit's ability; aimed ones then take a click, also on the minimap |
| B (building with work queued) | Cancel the last queued item or the research, with a refund |
| Ctrl + 1–9 / 1–9 | Save / recall control group |
| . | Select the next idle Worker |
| Arrow keys / screen edges / middle drag | Pan camera |
| Mouse wheel | Zoom |
| Home | Select and focus your Core |
| N | Jump to the last alert |
| Left / right click minimap | Move camera / issue a move, attack-move or patrol order |
| Space / Escape | Pause / resume; Escape first cancels placement or an overlay |
| F1 / F2 | Field manual / cycle 1×, 2×, 4× speed |
| F5 / F9 | Quick save / quick load |
| M / F11 | Sound on or off / fullscreen (both remembered) |

Pause → Settings holds volumes, window mode, resolution, VSync, frame cap,
graphics profile, shadows, UI scale, reduced effects, subtitles, colour-blind
side colours and key rebinding. Right-click cancels placement; Shift-click
keeps the building tool active. Orders against enemy units require current
vision. Destroyed production buildings refund queued units and research.

## Development

The repository contains the complete editable game source. The shipped game
needs no API keys. Regenerating voice, SFX, or music requires the Composio CLI
with a connected ElevenLabs account: `python3 tools/generate_audio.py`.

```bash
./tools/setup.sh             # download pinned engine and matching export templates
./tools/godot.sh --editor    # open project in Godot
./tools/test.sh              # every suite below except the long ones
./tools/test.sh --soak       # also three bot-vs-bot matches and a skirmish on every map
./tools/build.sh             # Linux + Windows exports, archives and SHA-256 hashes
```

`setup.sh` downloads official engine binaries and the export template bundle
(about 1.3 GB total); tools and caches remain under `.tools/` and are ignored by
Git. You can set `GODOT_BIN` to an existing Godot 4.6.3 executable.

### Tests

- `tests/simulation_test.gd`: each rule on its own (economy, construction,
  navigation, research, combat, alerts, orders, abilities, terrain, factions,
  saves, determinism).
- `tests/integration_test.gd`: the whole game together, driven through the
  real menu, HUD, input handler, opponent, audio and save code.
- `tests/interface_test.gd`, `tests/ui_production_test.gd`: input routing and
  every screen laid out at six resolutions and four UI scales.
- `tests/campaign_test.gd`, `tests/production_foundation_test.gd`,
  `tests/audio_test.gd`, `tests/model_assets_test.gd`,
  `tests/sprite_cards_test.gd`: missions, persistence, sound and art contracts.
- `tests/skirmish_test.gd` (with `--soak`): two opponents play each of the
  eight maps to a result. `tests/balance_test.gd` (run by hand) plays every
  faction pairing and reports win rates.

### Project structure

- `data/catalog.tres` and `scripts/catalog.gd`: unit and building stats, costs,
  counters, abilities, terrain effects and research.
- `data/maps/`, `data/missions/`, `data/factions/`: maps (obstacles, deposits,
  roads, rough and high ground), missions and faction rosters.
  `tools/author_terrain.py` writes each map's rough and high ground.
- `scripts/simulation.gd`: fixed 100 ms ticks; command validation, economy,
  construction, A* navigation, vision and fog memory, combat, shells,
  abilities, production, alerts and victory.
- `scripts/opponent.gd`: computer strategy issuing the same commands as the player.
- `scripts/battlefield.gd`, `scripts/sprite_cards.gd`, `scripts/models.gd`:
  camera, terrain, sprite cards, fog, placement preview and effects.
- `scripts/interface.gd`, `scripts/main.gd`: HUD, menus, skirmish setup, save
  slots, settings, credits, and the input controller.
- `scripts/mission_definition.gd`, `scripts/mission_controller.gd`,
  `scripts/mission_catalog.gd`: campaign contracts and objective flow.
- `scripts/save_game.gd`, `scripts/settings_service.gd`,
  `scripts/platform_service.gd`: versioned atomic saves, separate settings,
  and offline-safe Steam integration points.
- `scripts/audio.gd`: offline mixer with Master/Music/Effects/Voice/UI buses,
  manifest-driven clips, a dialogue queue, spoken alerts and an ambient bed.
- `tools/sprites/`: the Blender models and the renderer that produces the atlases.

### Simulation interface

`DASimulation.command(side, action, entity_ids, payload)` returns an empty string
on success or a user-readable reason for rejection. Actions: `move`,
`attack_move`, `patrol`, `hold`, `stop`, `attack`, `gather`, `repair`, `build`,
`train`, `research`, `cancel`, `rally`, `stance` and `ability`. Payloads carry
`pos`, `target`, `kind`, `index` or `stance` as appropriate. The `shot`,
`impact`, `destroyed`, `alert` and `notice` signals drive presentation. Only
the simulation owns resource accounting and unit/building state. The same
commands in the same order always produce the same state. No network API is
exposed.

### Diagnostics

```bash
./tools/godot.sh --resolution 1920x1080 -- --benchmark
./tools/godot.sh --resolution 1920x1080 -- --benchmark --no-shadows
./tools/godot.sh -- --autoplay
./tools/godot.sh -- --demo --screenshot
```

Benchmark mode creates 200 units and reveals the map **only for diagnostics**;
it reports measured frame rate and GPU. Demo mode creates a presentation scene.
A screenshot is saved under `builds/screenshot.png`. These switches are
development tools, not game rules.

## Boundaries

The simulation has two sides: there are no allies or three-way matches.
Multiplayer, campaign co-op, mod tools, mobile, controller support,
translations, GodotSteam verification and Windows runtime sign-off remain
outside this release candidate. Voice, music and effects ship as offline MP3s
and fall back to silence if a clip is missing. See
`docs/PRODUCTION_STATUS.md`, `assets/CREDITS.md`, and `LICENSE`.
