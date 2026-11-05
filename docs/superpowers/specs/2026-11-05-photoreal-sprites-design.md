# Digital Age: the Age of AI photoreal sprite set in the 3D world

Date: 2026-11-05. Status: draft for approval.

## Intent

Digital Age (this repo, Godot 4.6, real 3D) and Age of AI
(`github.com/ultimAItechORG/age-of-ai`, Kotlin, 2D isometric) become one game.
Digital Age stays the game: its campaign, simulation, maps, HUD, audio and 3D
world remain. What it takes from Age of AI is the photoreal look that landed
there on 4 and 5 November 2026 (branch `claude/keen-lamport-xkem6m`): the
ElevenLabs-generated photoreal isometric sprite set under `art/` and the depth
cues drawn around it (sun-cast silhouette shadows, soft contact shadows, owner
colour as a ground disc rather than baked into the sprite).

The user's words: "Both together need to be one game. Digital Age should have
the photorealism that was added the last days in age-of-ai", and, asked what
is on screen, "Same sprites in 3D".

## What the player sees

The 3D world stays: heightmap terrain with the Polyhaven PBR layers, rivers,
HDRI sky, SDFGI/SSAO, fog of war, the ruined-city ring outside the map, the
Polyhaven trees and rocks scattered through it. Standing in that world, every
building, unit and resource deposit is a photoreal sprite card from the Age of
AI set: an upright image that always faces the camera, its feet on the
terrain, with a sun-cast shadow of its own silhouette sheared across the
ground towards the lower right and a soft contact shadow under it. Under each
owned unit and building sits a faction-coloured ground disc (cyan for the
player, red for the opponent), which is how ownership reads, exactly as in Age
of AI. Buildings under construction rise out of the ground as they complete.
Unit cards flip horizontally when the unit moves towards screen-left. The HUD
portrait of a selected entity is the same sprite, so the panel matches the
field.

The result should look like the Age of AI desktop renderer's photoreal mode
dropped into a lit 3D landscape, not like a 3D game with pictures stuck on it.
The terrain lighting, shadow direction and colour temperature must agree with
the sprites' baked lighting (soft overcast daylight, key light upper left).

## Goals

1. Every gameplay entity (6 buildings, 5 units, metal and data deposits) is
   drawn from a photoreal sprite card in the 3D world.
2. The Age of AI depth cues are reproduced: sun-cast silhouette shadow,
   contact shadow, owner disc, construction rise, facing flip.
3. Fog of war, selection rings, placement ghosts, attack and death effects,
   picking, portraits and all tests keep working.
4. The art, its generation recipe and the generation ids are carried over
   with attribution so the set can be extended with the same recipe.
5. Performance stays within the current budget on Forward+ and on the
   Compatibility renderer (packaged Linux and Windows builds).

## Non-goals

- Porting any Age of AI Kotlin code, its economy, ages, monetization or
  Android app. Different engine, different game.
- Replacing Digital Age's terrain with the Age of AI ground textures. The
  Godot terrain already has albedo, normal and ARM layers from Polyhaven and
  reads more photoreal than the 512 px albedo-only tiles. (My call.)
- Animated sprites. The set is one still per kind, as in Age of AI.
- Camera-rotation-correct sprites (eight-direction sets). Cards face the
  camera; rotating the view with Q/E keeps working but the baked 45-degree
  view of each building does not change. Same limitation Age of AI accepted
  by not allowing rotation at all.

## Anti-goals

- Cards that visibly float, sink into slopes, or clip through each other.
- Shadows that disagree with the terrain's own sun shadows in direction.
- Sprites squashed by the camera elevation (an upright card seen from 50
  degrees reads 36 percent too short). The cards must be shown unforeshortened.
- Losing the 3D models. They stay in `art/` and `assets/models/` as the
  fallback for any kind without a sprite, and for the ring scenery.

## The sprite set and its mapping

Source: 54 PNGs under `art/` in Age of AI (16 MB), with `art/README.md`
(prompt recipe, placement rules) and `art/generations.tsv` (ElevenLabs flow
`MK3BnnGfyEgxj9kHEFNi`, model `gpt-image-2.5-sunburst`, one generation id per
asset). They are copied into this repo under `assets/sprites/<group>/<name>.png`
with the README and TSV beside them, credited in `assets/CREDITS.md`.

Age of AI covers six historical ages; Digital Age is a machine civilization in
industrial ruins. Only the Digital-and-AI-age sprites fit. Mapping:

| Digital Age kind | Sprite | Note |
|---|---|---|
| core (5x5 cells) | buildings/ai_core | the wonder-sized core |
| fabricator (5x5) | buildings/mech_hangar | manufactures units |
| data_center (3x3) | buildings/data_center | |
| generator (3x3) | buildings/fusion_reactor | energy |
| depot (3x3) | buildings/factory | salvage processing, brick-industrial like the ruins |
| tower (3x3) | buildings/shield_generator | tripod emitter reads as an autonomous weapon |
| worker | units/drone | harvester and builder drone |
| scout | units/swarm | fast, light, wide vision |
| sentinel | units/mech | frontline guardian |
| disruptor | units/tank | electromagnetic artillery |
| walker | **none fits** | see gaps |
| metal deposit | props/gold | the README already calls it a golden salvage deposit |
| data archive (violet) | **none fits** | see gaps |
| tree (scatter) | props/tree | optional; Polyhaven trees already exist |
| rubble (scatter) | props/stone | optional |

Gaps: Siege Walker and the Archive have no photoreal sprite. The ElevenLabs
image flow is a web workflow; from this machine ElevenLabs is reachable only
through Composio, which exposes text-to-speech, so new sprites cannot be
generated here. The build therefore ships mixed from the start: Walker and
Archive keep their 3D models (with the team recolour, a matching cast shadow
and owner disc so they sit among the cards), and the mapping table accepts a
sprite for them the moment a PNG named `units/walker.png` or
`props/archive.png` is dropped into `assets/sprites/`. The user can generate
those two in the ElevenLabs flow with the recipe in `art/README.md`; the
prompts are in `assets/sprites/README.md`. Everything else in the mapping is
my call and can be swapped by editing one table.

Ownership is not in the sprite (neutral colours by design); it is the ground
disc. The `team` material recolouring of the 3D models therefore no longer
applies to sprite kinds.

## How the cards are placed (the rules a builder needs)

These follow Age of AI's `Art.kt` and `art/README.md`, translated to world
units where one map cell is one unit:

- Building card width = footprint width in cells × √2 × 1.05 (the sprite
  shows the footprint as a 2:1 diamond, i.e. the square rotated 45 degrees,
  so its width is the footprint diagonal). Height from the image aspect.
  Bottom edge of the card on the terrain (see anchor below).
- Unit card height = 1.4 cells (1.9 for walker, tank-like and mounted-like
  kinds: disruptor, walker). Width from the aspect. Feet on the terrain at the
  unit position. Builder tunes both factors against screenshots, as Age of AI
  did against headless frames.
- Prop (deposit) card width = 1.0 cell diagonal.
- Cards face the camera fully (not Y-locked), pivot at the bottom centre, so
  the image is never foreshortened. The builder may lower `CAMERA_ELEVATION`
  (currently 50) towards the 30 degrees the sprites were rendered at if that
  makes the ground and the cards agree better; 35 to 40 is the expected range.
- Cast shadow: the card's own silhouette drawn flat on the ground, sheared
  0.55 and squashed 0.25 of its height along the sun's ground direction, at
  38 percent black. The shear direction is taken from the sun, not hard-coded.
- Sun direction (my call): the sprites are baked with the key light upper
  left, so their cast shadows must fall lower right at the default view. The
  current `SUN_ROTATION` (-48, -35, 0) puts the sun behind the camera at the
  default yaw, with shadows falling straight down the screen, 45 degrees off.
  The sun yields: its yaw moves so that at the default camera yaw the ground
  shadow direction is lower right on screen. `shared_sky()` already rolls the
  HDRI to follow `SUN_ROTATION`, so the sky follows; the builder re-checks
  exposure and terrain shading after the move. With Q/E rotation the match
  drifts, which is accepted (see non-goals).
- Anchor (my call, following Art.kt): a card tilted toward the camera shows
  the footprint as a diamond whose bottom vertex is the footprint's
  camera-nearest corner. The card's bottom centre is therefore placed at the
  footprint centre plus half the footprint diagonal toward the camera,
  recomputed from the camera yaw, so the drawn building covers its grid cells
  and the selection ring, owner disc, placement ghost and pick bounds line up
  with it. Units and props anchor at their position.
- Contact shadow: soft ellipse 1.3 × footprint, 30 percent black.
- Owner disc: flat ring/disc under the card in the faction colour, radius as
  the current selection ring, always visible but fainter than the selection
  highlight.
- Fog of war: cards are tinted by the same `fog_of_war.gdshaderinc` rule as
  terrain and kit meshes (explored = dim grey, unexplored = hidden).
- Lighting: cards are unlit (their lighting is baked) but receive the fog tint
  and the environment's tone mapping; the builder may add a small amount of
  terrain-matched ambient tint if cards look pasted-on against the SDFGI-lit
  ground.
- Construction: card clipped from the bottom up by build progress (rising
  clip), not scaled.
- Facing: flip the card horizontally when the unit's last movement had a
  negative screen-x component in the current camera yaw.
- Depth: cards are opaque with alpha scissor (no sorting artefacts) plus a
  thin alpha-to-coverage edge if the renderer supports it; the builder picks
  what looks clean on both renderers.

## Constraints

- Godot 4.6.3, typed GDScript, no plugins. Everything offline.
- Both renderers: Forward+ (desktop source run) and gl_compatibility (the
  packaged builds, `tools/render_ui.sh`). No feature may be Forward+-only
  without a visible fallback.
- Units are currently drawn through MultiMeshes (128 instances per kind and
  side). Sprite cards may be individual nodes (at most a few hundred) or a
  MultiMesh of quads per kind; the builder decides, keeping the 20-minute
  skirmish at the current frame time.
- Picking uses the entity node's first child; whatever replaces the mesh
  must keep `main.gd`'s `pick`/`pick_screen` working.
- `tests/model_assets_test.gd`, `rendered_match_test.gd`, `ui_production_test.gd`
  and the rest of `tools/test.sh` keep passing; portraits get a test that each
  sprite kind resolves to a texture.
- Keep the repo size sane: PNGs as shipped by Age of AI (already downscaled,
  16 MB total), no raw renders.

## Delivery

0. The pending world-look work in the working tree (terrain shader, Polyhaven
   PBR terrain, HDRI sky, battlefield rework) is committed first as its own
   commit once `tools/test.sh` passes, so the sprite commits sit on a known
   base. The processed Polyhaven set (`assets/third_party/processed/`, 150 MB,
   no file over 20 MB) goes into git (my call): the code falls back without
   it, but a clean clone would then not look like the game, and the raw
   downloads it is built from are not in the repo. The user can veto this in
   favour of regenerating it with `tools/process_cc0_models.py`.
1. The look lands on this repo's `master` as one or more commits.
2. The repo is pushed to GitHub under the `ultimAItechORG` organisation as
   `digital-age`, next to `age-of-ai`. This needs the user to run
   `gh auth login` first; no push happens before that.
3. Age of AI's `README.md` gets one line pointing at Digital Age as the game
   that now carries its art, in a separate small commit on its default branch
   (only if the user wants that; see open questions).

## Left to the builder

- Node structure for cards, shadows and discs; whether to use `Sprite3D`,
  `QuadMesh` + shader, or MultiMesh quads.
- Exact shader for fog tint, alpha handling and the rising clip.
- Tuning of card sizes, camera elevation, shadow alpha and disc brightness,
  done against `tools/render_ui.sh` captures.
- How portraits are produced from sprites (crop and scale at load, or a
  one-off tool that writes PNGs into `assets/ui/portraits/`).
- Whether the scatter trees and rubble switch to sprite cards or stay as
  Polyhaven meshes (both acceptable; the mixed look is fine as long as
  lighting agrees).

## Open questions for the user

1. Is `ultimAItechORG/digital-age` the right place and name for the upload?
2. Should Age of AI's README get a pointer to Digital Age?
3. Will you generate the Walker and Archive sprites in the ElevenLabs flow
   (the build does not wait for them)?
