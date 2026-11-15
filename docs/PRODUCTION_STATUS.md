# Production status

## Added after 1.0.0-rc3 (unreleased)

- **Save safety:** saves carry a checked header, are verified before they
  replace the previous file, and keep that file as a backup that is used when
  the main file is damaged. Campaign progress is written the same way; a damaged
  progress file is set aside and reported. Unreadable slots are shown as such
  and ask before being overwritten. A load is validated before the running
  match is touched and never re-locks missions.
- **Mission fixes:** gather objectives count delivered resources (Salvage
  Rights no longer completes its first objective on the starting stock); First
  Signal's survival clock starts with the counterattack; Ghost Protocol's wave
  cannot arrive in the first four minutes; the opponent builds a Generator
  first when it has no power.
- **Release hardening:** development switches are ignored by release builds;
  the match pauses when the window loses focus; the menu shows the version; key
  labels follow the keyboard layout; grid keys cannot be rebound away.
- **Tutorial:** a guided seven-step match outside the campaign, with separate
  instructions for mouse and for gamepad.
- **Gamepad:** full play on a pad with a virtual cursor, a command-grid layer,
  control groups, menu navigation, rebinding and per-family button names;
  first launch on a Steam Deck starts fullscreen at 125% scale; 1280 x 800 is
  in the resolution list and the layout matrix.
- **Languages:** French, Italian, German and Spanish text and subtitles
  (machine drafts, marked for native review); voices remain English.
- **Release pipeline:** one version source; builds carry the font, engine and
  Poly Haven licences and a build identity; packages are verified, including
  that development switches do nothing; CI builds both platforms and a tag
  drafts a release; the long suites run nightly.
- **Tests:** mission completion by the computer player (seven of eight
  missions on Easy), localisation, gamepad and tutorial suites; the layout
  matrix in a pseudo-language and four languages.

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

## Remaining gates (not claimed)

- **Steam:** no AppID or depot IDs, GodotSteam is not integrated, and
  `scripts/platform_service.gd` is a stub that no export enables. Achievements
  are requested by id but defined nowhere. Store assets do not exist.
- **Windows:** the build is produced, hashed and its contents verified, but it
  has never been run on Windows, and it is not code-signed.
- **Playtesting:** nobody has played this build by hand. No outside playtest of
  the campaign or the tutorial.
- **The Foundry (mission 6):** not proven winnable by the automated player; it
  needs a human playtest. Balance elsewhere is measured only computer against
  computer.
- **Performance:** measured on one workstation (RTX 3070); no minimum-spec
  measurement and no published system requirements.
- **Translations:** drafted by machine; not reviewed by native speakers.
- **Gamepad:** verified with synthetic input only. Real pad names, stick feel
  and legibility on a physical Steam Deck are untested. Button names are text
  ("A", "Cross"), not glyph images.
- **Legal:** a named copyright holder; whether MIT is intended for the art and
  audio; evidence of the ElevenLabs commercial licence; an EULA or privacy
  statement if the store requires one; the Age of Empires mention in the
  credits.
- **Support:** no support contact or bug-report path for players.

## Out of scope

Three or more sides, allies, multiplayer, and translated voices.

## Audio provenance

`tools/generate_audio.py` is the only generation path. The game never calls
ElevenLabs at runtime. Missing clips stay silent and do not break simulation or
tests.
