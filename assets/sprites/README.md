# Photoreal sprite set

Photoreal isometric sprites drawn in the 3D battlefield as camera-facing
cards (`scripts/sprite_cards.gd`). The set was generated for **Age of AI**
(`github.com/ultimAItechORG/age-of-ai`, branch `claude/keen-lamport-xkem6m`,
commit `c42b0f8`, 2026-11-05) and is carried over unchanged, together with
`generations.tsv`, which maps every file to its ElevenLabs flow node, session
and generation id (flow `MK3BnnGfyEgxj9kHEFNi` "Age of AI sprites", model
`gpt-image-2.5-sunburst`, 1280x720 PNG). The renders were cut out with rembg
(isnet, alpha matting) and downscaled: ground 512 px wide, props and units
256, buildings 384 to 896.

```
buildings/  30 buildings, one per Age of AI building type
units/      16 units, facing lower right, neutral colours
props/      tree, stone, gold, berries
ground/     grass, dirt, sand, water (seamless top-down, unused here)
```

## Mapping to Digital Age kinds

Only the Digital-and-AI-age sprites fit a machine civilization in industrial
ruins. The table lives in `DASprites.SPRITES`; a kind without a file keeps
its Blender model.

| Kind | Sprite | Kind | Sprite |
|---|---|---|---|
| core | buildings/ai_core | worker | units/drone |
| fabricator | buildings/mech_hangar | scout | units/swarm |
| data_center | buildings/data_center | sentinel | units/mech |
| generator | buildings/fusion_reactor | disruptor | units/tank |
| depot | buildings/factory | walker | units/walker (missing) |
| tower | buildings/shield_generator | metal | props/gold |
| | | data | props/archive (missing) |

Drop `units/walker.png` and `props/archive.png` into this folder (same
cut-out and downscale as the others: transparent background, trimmed, 256 px
wide for the unit, 256 for the prop) and both kinds switch to cards on the
next launch. No code change is needed.

## Recipe

Every image is a single take with one shared preamble, so the set stays
consistent:

> Isometric video game building asset for a real-time strategy game. Subject:
> *…era and subject…*. Projection: 2:1 isometric (dimetric) view, the building
> rotated 45 degrees so one corner points toward the camera, camera elevated
> about 30 degrees above the ground, orthographic, no perspective distortion.
> The building sits on a square footprint whose base forms a 2:1 diamond.
> Rendering: photorealistic 3D render, physically based materials, soft
> overcast daylight with the key light from the upper left, a subtle soft
> contact shadow baked onto the ground directly under and to the lower right
> of the building, nothing else on the ground. Object centred, filling about
> 85 percent of the frame, nothing cut off, no people, no text, no watermark,
> no ground plane beyond the small contact shadow. Fully transparent
> background (PNG alpha).

Units use the same light and camera with "the figure seen from the
front-right, facing toward the lower right of the frame, full body from head
to feet" and neutral colours; ownership is drawn by the game as a ground disc.

### Prompts for the two missing sprites

**units/walker.png** (Siege Walker): Isometric video game unit asset for a
real-time strategy game. Subject: a heavy four-legged autonomous siege walker
platform, dark gunmetal and weathered steel, a long-barrel electromagnetic
cannon on its back, hydraulic legs mid-stride, no pilot. The machine seen from
the front-right, facing toward the lower right of the frame, full body from
the top of the cannon to the feet. Projection and rendering as the preamble
(2:1 isometric, 30 degrees elevation, orthographic, photorealistic PBR, soft
overcast daylight, key light upper left, small contact shadow only, neutral
colours, no faction markings). Fully transparent background (PNG alpha).

**props/archive.png** (data archive): Isometric video game resource asset
for a real-time strategy game. Subject: a half-buried violet data archive
monolith, a tall obsidian server pillar with three glowing violet rings and
cracked concrete at its base, no people. Projection and rendering as the
preamble (2:1 isometric, 30 degrees elevation, orthographic, photorealistic
PBR, soft overcast daylight, key light upper left, small contact shadow only).
Fully transparent background (PNG alpha).

## Placement in Digital Age

One map cell is one world unit. Building cards are `cells × √2 × 1.05` wide
(the footprint diagonal, as the sprite shows the footprint as a diamond) and
anchored at the footprint centre plus half the diagonal toward the camera;
unit cards are 1.4 units tall (1.9 for disruptor and walker); deposits are
`√2` wide. Every card has a sun-cast silhouette shadow sheared along the sun
direction (38 % black), a soft contact shadow (1.3 × footprint, 30 % black)
and an owner disc in the faction colour. The HUD portrait of a kind with a
sprite is the sprite itself.
