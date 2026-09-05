# Asset credits

All machine models, terrain, UI layouts, effects, and campaign data were created
for Digital Age. Their editable generators and contracts are in
`scripts/models.gd`, `scripts/battlefield.gd`, `scripts/interface.gd`, and the
typed resources under `data/`.

Voice, music, and sound effects were generated offline with ElevenLabs
(`eleven_multilingual_v2` for speech, `eleven_text_to_sound_v2` for effects,
ElevenLabs Music for scores) through the connected Composio account. Prompts,
voice IDs, and SHA-256 hashes are recorded in `assets/audio/manifest.json`.
Generation is commercial-licensed under that Creator-tier ElevenLabs account.
The shipped game plays the baked files only; it does not call ElevenLabs at
runtime.

Casting used premade ElevenLabs voices: River (Origin archivist), Daniel
(tactical system), Adam (Foundry), and Lily (Lattice).

The interface uses Rajdhani SemiBold and, as fallback, Godot's bundled font.
Rajdhani is licensed under the SIL Open Font License (see
`assets/fonts/Rajdhani-OFL.txt`). JetBrains Mono remains available under its OFL
for debug/tooling use.

Godot Engine and its bundled third-party components retain their respective
licenses. See:
https://godotengine.org/license/ and https://github.com/godotengine/godot/blob/4.6.3-stable/COPYRIGHT.txt

Age of Empires is an inspiration for the broad RTS genre conventions. This
project uses its own title, setting, machine designs, code, and presentation.
