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
Rajdhani is licensed under the SIL Open Font License. The HUD title uses Cinzel
(variable weight) by Natanael Gama, also under the SIL Open Font License; it
falls back to Rajdhani when absent. Both licence texts ship in the `licenses`
folder beside the game (`assets/fonts/` in the source). JetBrains Mono is used
by development tooling only and is not part of the game build.

HUD icons are original 24×24 SVG glyphs in `assets/ui/icons/`, rasterised at
runtime. Unit and building portraits in `assets/ui/portraits/` are rendered from
the project's own Blender kit by `tools/render_thumbnails.py`.

Godot Engine and its bundled third-party components retain their respective
licenses. See:
https://godotengine.org/license/ and https://github.com/godotengine/godot/blob/4.6.3-stable/COPYRIGHT.txt

Age of Empires is an inspiration for the broad RTS genre conventions. This
project uses its own title, setting, machine designs, code, and presentation.

## Photoreal sprite set

`assets/sprites/rendered/`: original work, rendered with Blender (Cycles) from the procedural models in `tools/sprites/`, using the Poly Haven CC0 textures and photoscans in `assets/third_party/polyhaven`. See `assets/sprites/README.md`.

## Poly Haven

The terrain textures, the sky and the photoscanned plants, rocks and props used
to render the sprites come from Poly Haven (https://polyhaven.com) and are in
the public domain under CC0 1.0. Thank you to their authors:

- Aerial Grass Rock (texture): Rob Tuytel
- Asphalt 02 (texture): Rob Tuytel
- Bark Willow (texture): Dario Barresi, Dimitrios Savva
- Boulder 01 (model): Rico Cilliers
- Brown Mud Leaves 01 (texture): Rob Tuytel
- Concrete Road Barrier (model): Amal Kumar
- Concrete Wall 006 (texture): Charlotte Baglioni, Dario Barresi
- Container Side (texture): Dimitrios Savva
- Corrugated Iron (texture): Dimitrios Savva, Jenelle van Heerden
- Covered Car (model): MP
- Cracked Concrete Wall (texture): Dimitrios Savva, Rico Cilliers
- Dead Tree Trunk (model): Rob Tuytel
- Fern 02 (model): Rico Cilliers, Rob Tuytel
- Forest Floor (texture): eye-candy.xyz
- Grass Medium 01 (model): Rico Cilliers, Rob Tuytel
- Gravel Ground 01 (texture): Rob Tuytel
- Island Tree 01 (model): Rico Cilliers, Rob Tuytel
- Island Tree 02 (model): Rico Cilliers, Rob Tuytel
- Island Tree 03 (model): Rico Cilliers, Rob Tuytel
- Jacaranda Tree (model): Rico Cilliers, Rob Tuytel
- Kloofendal 48d Partly Cloudy (Pure Sky) (hdri): Greg Zaal, Jarod Guest
- Metal Plate (texture): Rob Tuytel
- Metal Plate 02 (texture): Rob Tuytel
- Modular Industrial Pipes 01 (model): Jorge Camacho
- Mossy Rock (texture): Rob Tuytel
- Painted Metal Shutter (texture): Charlotte Baglioni, Dario Barresi, Rico Cilliers
- Rock Face (texture): Dario Barresi, Greg Zaal
- Rock Moss Set 01 (model): Kless Gyzen
- Rubber Tiles (texture): Amal Kumar
- Rubberized Track (texture): Charlotte Baglioni
- Rusty Metal 02 (texture): Rob Tuytel
- Rusty Metal 04 (texture): Amal Kumar
- Rusty Metal Sheet (texture): Amal Kumar
- Rusty Painted Metal (texture): Amal Kumar
- Shrub 01 (model): Rico Cilliers
- Shrub 02 (model): Rico Cilliers
- Shrub 03 (model): Rico Cilliers
- Shrub 04 (model): Rico Cilliers
- Tree Small 02 (model): Rico Cilliers
- Wood Planks Grey (texture): Rob Tuytel
