# Production status

## Implemented in 1.0.0-rc1

- Godot 4.6.3 Compatibility renderer with Linux and Windows export presets.
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

## Remaining gates (not claimed by this RC)

- GodotSteam verification on a real Steam client (achievements, overlay, Auto-Cloud).
- Windows runtime playtest on physical hardware.
- Outside usability playtests of the full eight-mission campaign.
- Performance sign-off at 200 units / 1080p on the documented recommended PC.

## Audio provenance

`tools/generate_audio.py` is the only generation path. The game never calls
ElevenLabs at runtime. Missing clips stay silent and do not break simulation or
tests.
