# Rendered sprite atlases

Buildings, units, deposits and scenery are drawn in the 3D battlefield as
camera-facing cards (`scripts/sprite_cards.gd`) from the atlases in
`rendered/`, one colour atlas and one faction mask per kind, rendered from
original Blender models by `tools/sprites/`. `scripts/sprite_atlas_data.gd`
(generated) describes each atlas. A kind without an atlas keeps its 3D model
from `DAModels.entity()`.

The earlier set of single AI-generated stills (and its `generations.tsv`) was
removed once every kind had an atlas; it is in the git history up to `902aec6`.

## Placement

One map cell is one world unit and atlases are rendered at 96 pixels per cell
(less for the largest units, see `ppu` in the atlas data), so a card is its
frame at that scale. The picture's origin row sits on the entity's ground
point. Every card has a sun-cast silhouette shadow sheared along the sun
direction, a soft contact shadow and an owner disc in the faction colour; the
masked parts of the picture are painted in the faction colour. The HUD
portrait of a kind is cut from its atlas.

## Pipeline

- `tools/sprites/rig.py`: the shared stage. Orthographic camera at the game's
  fixed view (30 degrees above the ground, 45 degrees to the grid), a sun
  travelling along `DABattlefield.SUN_ROTATION`, and the game's own sky
  photograph (`processed/hdri`) turned so its sun agrees, for fill and
  reflections. AgX tone response; exposure was set so a grey card matches the
  earlier look. Transparent film, 96 pixels per map cell. Cast shadows are
  drawn in the game, not baked.
- `tools/sprites/kit.py`: PBR surfaces over the Poly Haven CC0 texture sets in
  `assets/third_party/polyhaven/raw` (run `tools/fetch_cc0_assets.py` first on
  a clean clone), with rounded edges and layers of use: paint chipped to steel
  and rust, streaks down walls, dust on upward faces, dirt near the ground,
  grime in corners. Primitives: boxes clad in panels with raised joints, drums
  with weld seams, rounded tapered shells and limbs for cast and pressed
  parts. The `team` and `team_coat` surfaces are worn grey paint that also
  writes the mask the game recolours per faction (chips and dirt are left out
  of the mask, so they keep their own colour).
- `tools/sprites/models.py`: one builder per kind. Buildings stand on a gravel
  apron that fades out toward the edge of the footprint, and have three
  scaffolded build stages, a six-frame idle loop when finished and a wreck.
  Units are built from shells, limbs, drums and spheres, never bare boxes,
  and have eight facings of idle, move (8 frames), attack (6 frames) and
  death (6 frames). The eight unit kinds are the five shared ones and
  one per faction (Warden, Mortar, Phantom); a new unit needs a builder here,
  an entry in `BUILDERS` and in the unit tuple of `build()`, and its stats in
  `data/catalog.tres`. Deposits have three
  depletion states. Trees and shrubs are the Poly Haven photoscans in
  `assets/third_party/processed`; ruins and gutted towers are procedural.
- `tools/sprites/ui.py` and `grade_ui.py`: render and grade the HUD's 9-slice
  plates into `assets/ui/frames/`.
- `tools/sprites/pack.py`: builds the colour and mask atlases and writes
  `scripts/sprite_atlas_data.gd` (frame grid, scale, anchor, animations).

Rebuild everything, or only some kinds:

```bash
tools/render_sprites.sh
tools/render_sprites.sh --kinds core,worker
```

Rendering uses the GPU through Cycles when one is available (about one second
a frame on an RTX 3070; the first run compiles kernels for a minute or two).
`python3 tools/sprites/sheet.py` writes a contact sheet to `builds/sprites/`.
Run `tools/godot.sh --headless --import` afterwards so Godot imports the new
textures.
