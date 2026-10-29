# Digital Age Blender assets

Created with Blender (the bundled `.tools/blender-4.5.3-linux-x64` build;
`manifest.json` records the version used for the last export). This kit
contains 24 original asset types, each saved as an editable `.blend` and a GLB
in `assets/models/`. The `_low` variants remove bevels, reduce cylinder segments,
and omit small details. Simple road and cable meshes have identical geometry
at both levels. Triangle counts are recorded in `manifest.json`.

The game uses the detailed models for all 5 unit types, 6 buildings, metal and
data resources, and authored ruins. Data resources use the Archive model.
Tree, bush and rubble are scenery kinds scattered by `scripts/battlefield.gd`
through MultiMeshes; rubble, barrier and ruin also stand in for blocked cells.
The three `highrise_*` kinds are ruined towers (7-14 m, broken tops, lit window
strips): they cluster in the world outside the map and stand on solid 3x3
obstacle blocks inside it, so they never cover a passable cell. Road, cable,
and substation exports are available for further map authoring. The `_low`
variants are used for the dense scatter outside the playable map; the current
graphics profile does not otherwise select them.

Meshes use metres, grounded origins, and +Z forward in Godot. Blender sources
use Z up and -Y forward. Named parts and materials remain individually
editable. The `team` material is recolored to the faction color at runtime;
amber and violet details retain their authored colors and are emissive in the
game so the environment glow picks them up. Palette entries are sRGB hex and
are converted to linear before they reach Blender base colours, so the GLB
colours match the hex values on screen. These are static models, without
skeletal animation or texture maps.

The runtime combines all imported parts into one vertex-colored surface per
asset/faction and retains the existing MultiMesh unit rendering. The editable
source directory is excluded from Godot's importer with `.gdignore`; Blender
is only required to regenerate or edit art, not to play the game.

From the project root:

```bash
.tools/blender-4.5.3-linux-x64/blender -b -noaudio --factory-startup --python-exit-code 1 --python tools/create_industrial_assets.py
.tools/blender-4.5.3-linux-x64/blender -b -noaudio --factory-startup --threads 4 --python-exit-code 1 --python tools/render_asset_gallery.py
.tools/blender-4.5.3-linux-x64/blender -b -noaudio --factory-startup --python-exit-code 1 --python tools/render_thumbnails.py
./tools/godot.sh --headless --editor --import --quit
./tools/test.sh
```

The first command regenerates all 48 asset sources and exports. The second
saves `asset_gallery.blend` and renders `asset_gallery.png`. Small units are
enlarged in the gallery for legibility; gameplay uses their authored dimensions.
The third renders one transparent 256×256 HUD portrait per kind into
`assets/ui/portraits/` (Cycles CPU, player team colour, orthographic camera at
the in-game viewing angle) together with `manifest.json` and an
`importer="keep"` sidecar per PNG so headless tests need no import step.

Validation: all 153 existing automated checks passed after integration. The
additional model contract verifies imports, reduced variants, triangle
preservation, grounded orientation, faction colors, cache separation, and
shared batch geometry with zero failures. The Blender gallery was visually
inspected. A native game screenshot was unavailable in the sandbox because
the display server could not be opened.
