# Asset credits

All machine models, terrain, UI layouts, effects, and campaign data were created
for Digital Age. The 18-type industrial mesh kit was authored using Blender's
Python interface; editable sources are in `art/`, exports in `assets/models/`,
and its generator is `tools/create_industrial_assets.py`. Runtime mesh batching
is in `scripts/models.gd`. Terrain, UI, and campaign generators and contracts
are in `scripts/battlefield.gd`, `scripts/interface.gd`, and the typed resources
under `data/`.

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
`assets/fonts/Rajdhani-OFL.txt`). The HUD title uses Cinzel (variable weight)
by Natanael Gama, also under the SIL Open Font License (see
`assets/fonts/Cinzel-OFL.txt`); it falls back to Rajdhani when absent.
JetBrains Mono remains available under its OFL for debug/tooling use.

HUD icons are original 24×24 SVG glyphs in `assets/ui/icons/`, rasterised at
runtime. Unit and building portraits in `assets/ui/portraits/` are rendered from
the project's own Blender kit by `tools/render_thumbnails.py`.

Godot Engine and its bundled third-party components retain their respective
licenses. See:
https://godotengine.org/license/ and https://github.com/godotengine/godot/blob/4.6.3-stable/COPYRIGHT.txt

Age of Empires is an inspiration for the broad RTS genre conventions. This
project uses its own title, setting, machine designs, code, and presentation.
