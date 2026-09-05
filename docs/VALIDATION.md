# Validation

Recorded against source `1.0.0-rc1` on Linux (Godot 4.6.3.stable).

## Automated suites

| Suite | Result |
|---|---|
| `tests/simulation_test.gd` | 49 checks, 0 failures |
| `tests/production_foundation_test.gd` | 15 checks, 0 failures |
| `tests/campaign_test.gd` | 41 checks, 0 failures |
| `tests/audio_test.gd` | 16 checks, 0 failures |
| `tests/interface_test.gd` | 32 checks, 0 failures |

`./tools/test.sh` is the gate used by CI. `--soak` remains available for three
bot-versus-bot matches on the default map.

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
exits 0. Windows is produced and hashed only; no Windows machine signed off
this RC.

## Not claimed

Steamworks live integration, extended 200-unit 1080p performance targets, and
external playtests are still open. Prior GT 710 benchmark notes remain
indicative, not a release certificate.
