# Digital Age: Machine Civilizations

An original, offline, single-player desktop RTS built with Godot 4.6.3 and
typed GDScript. Lead the Origin Collective through an eight-mission campaign,
three technological ages, and a war against the Foundry and Lattice machine
factions. Version 1.0.0-rc2 ships eight distinct maps, authored encounters,
offline voice, music, and effects. No network services are required to play.

## Play

- **Linux:** extract `DigitalAge-linux-x86_64.tar.gz`, then double-click
  `DigitalAge.x86_64` (or run `./DigitalAge.x86_64`). From this source workspace,
  run `./run.sh`. This always launches the current source; use `./run.sh --packaged`
  explicitly to launch the last Linux export.
- **Windows:** extract `DigitalAge-windows-x86_64.zip` and run `DigitalAge.exe`.
- Choose **Launch Campaign** to begin **First Signal**. The in-game **Field
  Manual** explains the economy, age progression, unit counters, and controls.
  F5 saves and F9 loads the current mission; checkpoints rotate through three
  autosave slots. Campaign unlocks persist across launches. Settings (volumes,
  subtitles, UI scale, key bindings) are stored separately. Everything runs
  offline, including the Steam fallback path.

The desktop builds are self-contained; players do not need Godot installed.
Windows runtime testing status and measured performance are in
`docs/VALIDATION.md` in the source project (or `VALIDATION.md` in a desktop archive).

The in-game HUD is a translucent top bar (resources with income per minute,
population, the AGE OF AI title, TECH / UNITS / BUILD / OBJECTIVES and the
pause menu), a floating minimap with quick-action buttons, and a selection
panel with a rendered portrait, health bar, build/production thumbnails, icon
commands (attack, stop, age and weapons research, rally) and the active job.
Icons are SVGs in `assets/ui/icons/`; portraits are Blender renders in
`assets/ui/portraits/` (`tools/render_thumbnails.py`).

The desktop UI supports 1280×720 through 3440×1440, with 100%, 115%, and 125%
UI scale. Tab/Shift+Tab navigate controls, Enter activates, and Escape closes
the top overlay. Settings and the manual scroll with the wheel, arrows, or
Page Up/Down; Tab also reveals offscreen controls. Settings pause gameplay.
Restarting or leaving an unsaved mission offers save-and-continue. Loading asks
before replacing unsaved progress and preserves the existing save file.
See `docs/UI_VERIFICATION.md` for the complete verification matrix.

## Start a civilization

1. Select Workers and right-click a golden salvage deposit. Metal pays for
   buildings and units. Workers carry 24 resources to a Core or Salvage Depot.
2. Explore with your Scout and assign some Workers to violet data archives.
   Data pays for ages, weapon research, and advanced units.
3. Build a Fabricator and additional Generators. Generators produce 3 energy/s.
4. Build Data Centers as your army grows. Each grants 20 population capacity,
   capped at 100. Losing capacity blocks further production; living units remain.
5. Research Network and Singularity at your Core. Sentinels counter Disruptors,
   Disruptors counter Siege Walkers, and Walkers destroy structures.

The opponent plays by the same economy and vision rules. Early raids precede
larger late-game attacks. Aggressive play can finish sooner than the intended
roughly 20-minute skirmish pacing.

The campaign is driven by authored mission, map, faction, and objective
resources. Each of the eight missions uses its own 72×72 map, starting layout,
dialogue, and scripted waves. Foundry and Lattice apply different modifiers and
AI profiles.

## Controls

| Input | Action |
|---|---|
| Left click / drag | Select an entity / your units |
| Shift + select | Add to selection; click a selected entity to remove it |
| Right click | Move, gather, attack, repair, or resume construction |
| Building selected + right click | Set production rally point |
| A, then left click | Attack-move |
| S | Stop |
| Ctrl + 1–9 / 1–9 | Save / recall control group |
| Arrow keys / screen edges / middle drag | Pan camera |
| Mouse wheel / Q and E | Zoom / rotate |
| Home | Select and focus your Core |
| Left / right click minimap | Move camera / issue movement order |
| Space / Escape | Pause / resume; Escape first cancels placement or help |
| F1 / F2 | Field manual / cycle 1×, 2×, 4× speed |
| M / F11 | Toggle sound / fullscreen |
| Pause → Settings | Volumes, subtitles, UI scale, key rebinding |

A and S are reserved for RTS orders; camera keyboard movement uses arrows to
avoid conflicting shortcuts. Right-click cancels placement; Shift-click keeps
the building tool active. Orders involving enemies require current vision.
Destroyed production buildings refund paid queued units and unfinished research.

## Development

The repository contains the complete editable game source. The shipped game
needs no API keys. Regenerating voice, SFX, or music requires the Composio CLI
with a connected ElevenLabs account: `python3 tools/generate_audio.py`.

```bash
./tools/setup.sh             # download pinned engine and matching export templates
./tools/godot.sh --editor    # open project in Godot
./tools/test.sh              # simulation, campaign, audio, and UI checks
./tools/test.sh --soak       # also run three full bot-vs-bot matches
./tools/build.sh             # Linux + Windows exports, archives and SHA-256 hashes
```

`setup.sh` downloads official engine binaries and the export template bundle
(about 1.3 GB total); tools and caches remain under `.tools/` and are ignored by
Git. You can set `GODOT_BIN` to an existing Godot 4.6.3 executable. On other host
platforms, open `project.godot` in Godot 4.6.3, install matching export templates,
and clear or replace the Linux-local custom template paths in the export presets.

### Project structure

- `data/catalog.tres`: unit/building stats, costs, prerequisites and descriptions.
  The resource script also exports economy parameters and research defaults.
- `scripts/simulation.gd`: fixed 100 ms ticks; authoritative command validation,
  economy, construction, A* navigation, vision, combat, production and victory.
- `scripts/opponent.gd`: computer strategy issuing the same commands as the player.
- `scripts/battlefield.gd` and `scripts/models.gd`: camera, procedural scenery,
  imported Blender models combined into cached meshes, fog, placement preview and effects.
- `art/`: editable Blender sources, a rendered asset gallery, and triangle counts.
  `assets/models/` contains the corresponding game-ready GLB exports.
- `scripts/interface.gd`, `scripts/main.gd`: HUD, campaign briefing/objectives,
  save/load controls, menus, and input/controller.
- `scripts/mission_definition.gd`, `scripts/mission_controller.gd`,
  `scripts/mission_catalog.gd`: authored campaign contracts and deterministic
  objective/checkpoint flow.
- `scripts/map_definition.gd`, `scripts/faction_definition.gd`,
  `scripts/campaign_progress.gd`: editable world, faction, and campaign data.
- `scripts/save_game.gd`, `scripts/settings_service.gd`,
  `scripts/platform_service.gd`: versioned atomic saves, separate settings,
  and offline-safe Steam integration points.
- `scripts/audio.gd`: offline mixer with Master/Music/Effects/Voice/UI buses,
  manifest-driven clips, voice queue, and combat music ducking.
- `data/audio/`: source prompts and voice lines. `tools/generate_audio.py`
  rebuilds `assets/audio/` through Composio → ElevenLabs.
- `tests/`: independent simulation scenarios, real input-handler integration,
  and complete unattended matches.

### Simulation interface

`DASimulation.command(side, action, entity_ids, payload)` returns an empty string
on success or a user-readable reason for rejection. Actions: `move`,
`attack_move`, `attack`, `gather`, `repair`, `stop`, `build`, `train`, `research`,
and `rally`. Payloads carry `pos`, `target`, or `kind` as appropriate. Public
`shot`, `destroyed`, and `notice` signals drive presentation. Only the simulation
owns resource accounting and unit/building state. No network API is exposed.

Balancing definitions are Godot Resources. Changing their costs, health,
production times, age requirements, ranges, and counter damage behavior does
not require modifying the HUD. New roster entries may require model and menu
additions. Map terrain and spawn layout are intentionally handcrafted in code.

### Diagnostics

```bash
./tools/godot.sh --resolution 1920x1080 -- --benchmark
./tools/godot.sh --resolution 1920x1080 -- --benchmark --no-shadows
./tools/godot.sh -- --autoplay
./tools/godot.sh -- --demo --screenshot
```

Benchmark mode creates 200 units and reveals the map **only for diagnostics**;
it reports measured frame rate and GPU. Demo mode creates a presentation scene
and is also separate from a normal skirmish. A screenshot is saved under
`builds/screenshot.png`. These switches are development tools, not game rules.

## Milestone boundaries

The Low profile disables long-range shadows and reduces camera draw distance;
Normal keeps the detailed compatibility-renderer presentation. Reduced-effects,
subtitle, UI scale, and independent volume preferences persist in
`user://settings.cfg` and are intentionally separate from campaign saves.

Voice, music, and effects ship as offline MP3s. `DAAudio` still emits semantic
events (`order`, `shot`, `objective_updated`, `dialogue_started`) and falls
back to silence if a clip is missing. Subtitles follow spoken lines.

Multiplayer, campaign co-op, mod tools, mobile, GodotSteam verification, and
Windows runtime sign-off remain outside this release candidate. See
`docs/PRODUCTION_STATUS.md`, `assets/CREDITS.md`, and `LICENSE`.
