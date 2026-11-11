# Production status

## Added in 1.0.0-rc3

- **Skirmish:** a setup screen (map with preview, both factions, resources,
  start position, difficulty) and symmetric openings on all eight maps.
- **Opponent:** three difficulty levels; scouts and attacks from what its side
  has seen (the rival start is the only map knowledge it uses before that);
  expands to unserved deposits, retreats when outnumbered two to one, answers
  the units it meets from the counter table, rebuilds a lost Core, fields its
  faction's unit and uses abilities. Works on every map without scripting.
- **Alerts:** under attack, unit and structure lost, construction and unit
  complete, research complete, population cap, deposit exhausted, Core lost:
  each with a toast, a minimap ping and its recorded voice line or sound.
- **Orders:** hold, patrol, stance (defensive/aggressive), cancel with refund;
  Workers move to the next deposit; unreachable destinations are refused.
- **Match rules:** a side without a Core has two minutes to rebuild while it
  has Workers; mission technology ceilings are enforced.
- **Combat:** counters and armour classes are catalog data; Disruptor, Walker
  and Mortar shells travel and splash; one ability per combat unit.
- **Factions:** rosters enforced; Warden (Origin), Mortar (Foundry) and
  Phantom (Lattice) with full rendered sprite sets.
- **Terrain:** roads speed units up, rough ground slows them, high ground adds
  sight and range; authored on all eight maps by `tools/author_terrain.py` and
  painted into the terrain and the minimap.
- **Fog memory:** buildings a side has scouted stay known in the fog.
- **Saving:** three manual and three checkpoint slots with a load screen;
  saves carry the opponent's state, control groups and speed, and switch
  mission or skirmish on load. Save schema 3 with migration from 1 and 2.
- **Campaign flow:** Next Mission after a win; the defeat screen names the cause.
- **Settings:** window mode, resolution, VSync, frame cap, shadows, mute and
  colour-blind side colours, all saved; UI scale up to 150%.
- **Credits screen** reading the shipped `CREDITS.md`.
- **Sound:** every recorded effect and alert line now has a trigger; interface
  buttons click; an ambient bed plays under a match.
- **Performance:** target search uses per-side spatial buckets and keeps its
  target between ticks; visibility stamps each occupied cell once.
- **Tests:** an integration suite driving the whole game through the real
  menu, HUD and input; a skirmish suite on every map; a determinism check.

## Implemented in 1.0.0-rc2

- Godot 4.6.3, Forward+ by default with the Compatibility renderer as the fallback; Linux and Windows export presets.
- Fixed dimetric camera, Blender-rendered sprite atlases for every kind, and the dock HUD with a technology tree (2026-11-10; see `README.md` and `assets/sprites/README.md`).
- Eight authored missions on eight distinct 72×72 maps, with dialogue, scripted
  waves, checkpoints, and faction-specific AI.
- Faction modifiers (`build_speed`, `unit_health`, `research_speed`,
  `vision_radius`) applied in simulation; Foundry and Lattice play differently.
- Deterministic mission controller with one-shot events, objective progress,
  failure, and serialized fired-event state.
- Versioned atomic mission saves plus `user://campaign.save` so unlocks survive
  a restart.
- Settings for graphics profile, reduced effects, volumes, subtitles, UI scale,
  and key rebinding. SOUND ON/OFF mutes the Master bus.
- Offline audio: Master / Music / Effects / Voice / UI buses. Voice, SFX, and
  music were generated with ElevenLabs via Composio and baked into
  `assets/audio/`.
- Headless suites: simulation, production foundation, campaign, audio, UI
  integration. CI runs tests and a Linux export smoke.
- Offline-safe Steam adapter surface. Depot templates remain placeholders until
  a Steamworks AppID exists.
- Production UI pass: responsive layout and hit testing, keyboard focus,
  modal input isolation, measured text wrapping, safe settings persistence,
  session-loss confirmations, queued captions, and Blender model integration.
- Desktop UI validation across five resolutions and three scales; real Godot
  captures under Xvfb/Mesa. See `UI_VERIFICATION.md` for evidence and limits.
- World look pass (presentation only, no gameplay cell changes): triplanar
  procedural ground materials, kit-scattered trees, shrubs and rubble, kit
  rubble/barriers/ruins and ruined towers on blocked cells, a perspective
  camera, the world continued 110 units past the map with rivers and a ruined
  skyline, fog of war as a smooth world-space tint, procedural sky ambient,
  AgX tonemap, depth fog and glow on emissive machine parts. `low` and reduced-effects profiles drop
  glow, fog, water animation and most of the scatter.

## Remaining gates (not claimed by this RC)

- GodotSteam verification on a real Steam client (achievements, overlay, Auto-Cloud).
- Windows runtime playtest on physical hardware.
- Outside usability playtests of the full eight-mission campaign.
- Performance sign-off at 200 units / 1080p on the documented recommended PC.
- Hands-on balance: faction win rates are measured only opponent against
  opponent (`tests/balance_test.gd`), not with human players.

## Out of scope

Three or more sides, allies, multiplayer, controller support and translations.

## Audio provenance

`tools/generate_audio.py` is the only generation path. The game never calls
ElevenLabs at runtime. Missing clips stay silent and do not break simulation or
tests.
