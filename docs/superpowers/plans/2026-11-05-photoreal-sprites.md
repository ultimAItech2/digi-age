# Age of AI Photoreal Sprites in Digital Age: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw every Digital Age building, unit and deposit as a camera-facing photoreal sprite card from the Age of AI set inside the existing Godot 3D world, with Age of AI's depth cues, then publish the repo to `ultimAItechORG/digital-age`.

**Architecture:** A new `scripts/sprite_cards.gd` (`class_name DASprites`) owns the kind-to-sprite table, texture loading, card construction (a bottom-pivoted `QuadMesh` on a `MeshInstance3D` with a billboard shader, a flat sheared shadow quad, and a ground quad for contact shadow plus owner disc) and sprite portraits. `scripts/battlefield.gd` builds cards instead of meshes for kinds that have a sprite, drives per-instance shader parameters (rise, flip, tint) from `sync()`, and gets a new sun yaw and camera elevation. Kinds without a sprite (walker, data archive) keep the `DAModels` 3D path untouched, so `model_assets_test.gd` keeps passing.

**Tech Stack:** Godot 4.6.3, typed GDScript, spatial shaders with `instance uniform`s, existing headless test scripts (`tools/test.sh`), Xvfb captures (`tools/render_scene.sh`, `tools/render_ui.sh`), `gh` CLI for the push.

**Spec:** `docs/superpowers/specs/2026-11-05-photoreal-sprites-design.md` (approved by the user on 2026-11-05).

## Context

Digital Age (this repo, Godot 4 real 3D RTS) and Age of AI (`github.com/ultimAItechORG/age-of-ai`, Kotlin 2D isometric RTS) are to become one game. The user chose: Digital Age stays the game and takes the photoreal look that landed in Age of AI on 4 and 5 November 2026 (branch `claude/keen-lamport-xkem6m`): 54 ElevenLabs-generated photoreal isometric PNG sprites under `art/` plus renderer depth cues (sun-cast silhouette shadow sheared across the ground, soft contact shadow, owner colour as a ground disc, construction rise, facing flip). The user answered "Same sprites in 3D". The Age of AI checkout is at `/tmp/claude-1000/-home-andre-Documents-ChatGPT-Digital-Age/c55e86af-31c5-431d-918d-581b16647134/scratchpad/aoa/repo` (branch `claude/keen-lamport-xkem6m` checked out). Pushing needs the user to run `gh auth login` first (gh logged out, SSH key rejected).

Facts from exploration that shape the plan:
- `battlefield.gd` `sync()` (lines 1001-1060) creates one Node3D per entity via `DAModels.entity()`, hides `get_child(0)` for owned units and draws them through 128-instance MultiMeshes, applies `model.scale.y` for construction and `model.rotation.y` for facing, places everything at y=0 (the map interior is flat).
- `main.gd` `pick_screen()` (487-512) hit-tests by projecting `get_aabb()` of every direct `MeshInstance3D` child of the model node; `interface_test.gd:64,142` clicks at `screen_at(worker.pos, 0.5)` and `screen_at(core.pos, 2.5)`.
- `DAModels.ring()` adds the selection ring as a direct child; `preview()` (1081-1095) overrides materials of every `MeshInstance3D` child of the ghost.
- Fog: `assets/shaders/fog_of_war.gdshaderinc` exposes `fog_level(vec3)` and `fog_tint(vec3,float)` through global uniforms already published by `make_fog_texture`.
- Sun: `SUN_ROTATION = Vector3(-48, -35, 0)`; `shared_sky()` rolls the HDRI from `SUN_ROTATION.y`; nothing exposes the sun ground direction. Light direction for `rotation_degrees (p, y, 0)` is `(-cos(p)·sin(y), sin(p), -cos(p)·cos(y))`, so the current sun throws shadows along the camera's forward vector at the default yaw -0.62. For shadows to fall lower-right on screen (toward the camera and right, `D = normalize(R - F)` with `R=(cos yaw, -sin yaw)`, `F=(sin yaw, cos yaw)`), the sun yaw must be about **-170.5 degrees**.
- Camera: `CAMERA_ELEVATION = 50.0`, `CAMERA_FOV = 32.0`, yaw changed by Q/E in `main.gd:346-351`.
- Portraits: `interface.gd` `portrait(kind)` (249-259) reads raw PNG bytes from `assets/ui/portraits/<asset>.png` (importer=keep) and resizes to 128; `thumb()` draws at 48 to 82 px. `interface.gd:972` places health bars at `screen_at(e.pos, 4.4 if building else 2.2)`.
- Tests: `tools/test.sh` runs simulation, production_foundation, campaign, audio, interface, model_assets, ui_production and soak headlessly; fails on `SCRIPT ERROR|^ERROR:|FAIL:`. `tools/render_scene.sh --gl` writes `builds/scene-gl.png` from `--demo --screenshot`; `tools/render_ui.sh` writes `builds/ui/*.png`.
- Working tree has uncommitted world-look work (terrain shader, PBR terrain, HDRI, battlefield rework, project.godot renderer forward_plus) and 150 MB untracked `assets/third_party/processed/` (no file over 20 MB; `.gitignore` does not exclude it). The user approved committing both first.

## Global Constraints

- Godot 4.6.3, typed GDScript, no plugins, everything offline.
- Both renderers must work: Forward+ (source run) and gl_compatibility (packaged builds, CI captures). No Forward+-only feature without a visible fallback.
- `tools/test.sh` and the CI capture scripts keep passing; `DAModels.entity()` and `model_assets_test.gd` stay unchanged.
- Sprites are the PNGs as shipped by Age of AI (16 MB total), no raw renders; attribution and generation ids travel with them.
- Card sizes from the spec: building card width = cells × √2 × 1.05; unit card height 1.4 cells, 1.9 for disruptor and walker; prop width = 1.0 × √2; contact shadow 1.3 × footprint at 30 % black; cast shadow at 38 % black, sheared along the sun's ground direction; owner disc in `sim.faction_color(owner)`.
- Cards face the camera fully, bottom pivot, never foreshortened; building cards are anchored at the footprint centre plus half the footprint diagonal toward the camera (done inside the shader so the node, ring, disc and pick box stay at the footprint centre).
- Sun yields to the sprites: `SUN_ROTATION.y` becomes -170.5; camera elevation becomes 38 (tunable, 35 to 40).
- Repo destination: `ultimAItechORG/digital-age`; Age of AI's README gets a one-line pointer to it.

## Review Focus

1. A unit whose kind has a sprite walks toward screen-left under a rotated camera (Q/E): the card must flip based on the current yaw, not world x. Test in Task 4.
2. A building placed while an enemy card stands nearby: the ghost's tint must not leak into the shared kind material (instance uniform, not material edit). Test in Task 4.
3. Save/load (`main.gd:253`) frees and recreates all models: cards must rebuild with the right rise/flip and no leaked instance params. Test in Task 4.
4. Headless run on a clean clone before `--import`: `DASprites.texture()` must fall back to raw PNG loading, never print an error. Test in Task 2.
5. Shadow toggle (`main.gd:641`) and `--no-shadows`: card shadow quads are our own geometry and must still follow the toggle. Test in Task 3.

---

### Task 0: Commit the pending world-look work and the processed Polyhaven set

**Files:**
- Modify (commit as-is): `assets/shaders/fog_of_war.gdshaderinc`, `project.godot`, `scripts/battlefield.gd`, `scripts/main.gd`, `tools/process_cc0_models.py`, `tools/render_ui.sh`, `assets/shaders/terrain.gdshader`, `assets/third_party/processed/` (150 MB)
- Also commit: `docs/superpowers/specs/2026-11-05-photoreal-sprites-design.md`, `docs/superpowers/plans/2026-11-05-photoreal-sprites.md` (copy of this plan)

- [ ] **Step 1: Run the suite on the pending tree**

Run: `./tools/godot.sh --headless --editor --import --quit && ./tools/test.sh`
Expected: every log in `builds/*.log` free of `SCRIPT ERROR|^ERROR:|FAIL:`; test.sh exits 0. If it fails, fix only what the pending work broke and note it in the commit.

- [ ] **Step 2: Confirm no single file exceeds GitHub's 100 MB limit**

Run: `find assets/third_party/processed -size +50M`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add assets/shaders project.godot scripts tools assets/third_party/processed docs/superpowers
git commit -m "World look: PBR terrain layers, HDRI sky, Forward+ default, processed CC0 set"
```

### Task 1: Import the sprite set with attribution

**Files:**
- Create: `assets/sprites/buildings/*.png`, `assets/sprites/units/*.png`, `assets/sprites/props/*.png`, `assets/sprites/ground/*.png` (all 54, copied from the Age of AI checkout `art/`), `assets/sprites/README.md`, `assets/sprites/generations.tsv`
- Modify: `assets/CREDITS.md`, `README.md` (one paragraph on the sprite look)

**Interfaces:**
- Produces: files at `res://assets/sprites/<group>/<name>.png`.

- [ ] **Step 1: Copy the set**

```bash
mkdir -p assets/sprites
cp -r /tmp/claude-1000/-home-andre-Documents-ChatGPT-Digital-Age/c55e86af-31c5-431d-918d-581b16647134/scratchpad/aoa/repo/art/{buildings,units,props,ground} assets/sprites/
cp .../art/generations.tsv assets/sprites/
```
Then write `assets/sprites/README.md`: origin (Age of AI repo, branch, commit `c42b0f8`), the prompt preamble and recipe copied from Age of AI's `art/README.md`, the Digital Age mapping table from the spec, and two ready-to-paste prompts for the missing `units/walker.png` (Siege Walker: heavy four-legged siege platform, neutral colours) and `props/archive.png` (violet data archive monolith), with the rule that dropping those files in switches the kinds to cards automatically.

- [ ] **Step 2: Import and check Godot accepts them**

Run: `./tools/godot.sh --headless --editor --import --quit 2>&1 | grep -iE "error|sprites" | head`
Expected: no error lines; `.import` sidecars appear next to each PNG.

- [ ] **Step 3: Credit**

Add to `assets/CREDITS.md`: "Photoreal sprite set: generated for Age of AI (ultimAItechORG/age-of-ai) with ElevenLabs image generation, model gpt-image-2.5-sunburst, flow MK3BnnGfyEgxj9kHEFNi; ids in assets/sprites/generations.tsv." Add one README paragraph under the HUD description.

- [ ] **Step 4: Commit**

```bash
git add assets/sprites assets/CREDITS.md README.md
git commit -m "Add the Age of AI photoreal sprite set with its recipe and generation ids"
```

### Task 2: `DASprites` table, texture loading and portraits

**Files:**
- Create: `scripts/sprite_cards.gd` (`class_name DASprites`, `extends RefCounted`, static API)
- Create: `tests/sprite_cards_test.gd` (same `expect()` harness style as `tests/model_assets_test.gd`)
- Modify: `tools/test.sh` (add `sprite_cards`), `scripts/interface.gd:249-259`

**Interfaces:**
- Produces:
  - `const SPRITES: Dictionary` = `{"core": "buildings/ai_core", "fabricator": "buildings/mech_hangar", "data_center": "buildings/data_center", "generator": "buildings/fusion_reactor", "depot": "buildings/factory", "tower": "buildings/shield_generator", "worker": "units/drone", "scout": "units/swarm", "sentinel": "units/mech", "disruptor": "units/tank", "walker": "units/walker", "metal": "props/gold", "data": "props/archive"}`
  - `static func sprite_path(kind: String) -> String` (`""` if unmapped)
  - `static func has_sprite(kind: String) -> bool` (mapped and the PNG exists)
  - `static func texture(kind: String) -> Texture2D` (cached; `load()` when `DABattlefield.imported(path)`, else raw `Image.load_png_from_buffer` into an `ImageTexture`; null when absent)
  - `static func portrait(kind: String) -> Texture2D` (cached; sprite padded to a square on its longer side, resized to 128×128 Lanczos; null when no sprite)
  - `const LARGE_UNITS = ["disruptor", "walker"]`

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/sprite_cards_test.gd
for kind in ["core","fabricator","data_center","generator","depot","tower","worker","scout","sentinel","disruptor","metal"]:
	expect(DASprites.has_sprite(kind), kind + ": sprite present")
	expect(DASprites.texture(kind) != null and DASprites.texture(kind).get_width() > 0, kind + ": texture loads")
	var p = DASprites.portrait(kind)
	expect(p != null and p.get_width() == 128 and p.get_height() == 128, kind + ": 128px square portrait")
expect(DASprites.sprite_path("walker") == "res://assets/sprites/units/walker.png", "walker mapped")
expect(not DASprites.has_sprite("walker") or FileAccess.file_exists(DASprites.sprite_path("walker")), "walker only when file exists")
expect(DASprites.portrait("walker") == null or DASprites.has_sprite("walker"), "no portrait without sprite")
expect(DASprites.texture("core") == DASprites.texture("core"), "texture cached")
```

- [ ] **Step 2: Run to verify it fails**

Run: `./tools/godot.sh --headless --script tests/sprite_cards_test.gd`
Expected: `SCRIPT ERROR` (DASprites undefined).

- [ ] **Step 3: Implement `scripts/sprite_cards.gd` (table, `sprite_path`, `has_sprite`, `texture`, `portrait`)**

Portrait padding: new transparent `Image` of side `max(w, h)`, `blit_rect` centred, then `resize(128,128, INTERPOLATE_LANCZOS)`.

- [ ] **Step 4: Hook portraits into `interface.gd` `portrait(kind)`**

Before the file path branch: `var sprite = DASprites.portrait(kind); if sprite: portrait_cache[kind] = sprite; return sprite`.

- [ ] **Step 5: Run the new test and the interface test**

Run: `./tools/godot.sh --headless --script tests/sprite_cards_test.gd && ./tools/godot.sh --headless --script tests/interface_test.gd`
Expected: both logs without `FAIL:`.

- [ ] **Step 6: Add to `tools/test.sh`, commit**

```bash
git add scripts/sprite_cards.gd tests/sprite_cards_test.gd tools/test.sh scripts/interface.gd
git commit -m "Sprite catalogue: kind mapping, texture loading, sprite portraits"
```

### Task 3: Card, cast shadow and ground disc builders with their shaders

**Files:**
- Create: `assets/shaders/sprite_card.gdshader`, `assets/shaders/sprite_shadow.gdshader`, `assets/shaders/sprite_ground.gdshader`
- Modify: `scripts/sprite_cards.gd` (builders), `tests/sprite_cards_test.gd`

**Interfaces:**
- Consumes: Task 2 API; `sim.catalog.buildings[kind].radius`.
- Produces:
  - `static func card(kind: String, side: int, footprint_cells: int, accent: Color) -> Node3D`: root Node3D with child(0) = `MeshInstance3D` named `Card` (QuadMesh size `(w, h)`, `center_offset = Vector3(0, h/2, 0)`, `custom_aabb = AABB(Vector3(-hw, 0, -hw), Vector3(2hw, h, 2hw))` where `hw = max(w/2, footprint_cells/2)`, `cast_shadow = OFF`, `material_override` = the shared per-kind card material), child(1) = `Node3D` named `Fx` holding `Shadow` (MeshInstance3D, same QuadMesh, per-kind shadow material, `cast_shadow = OFF`) and `Ground` (MeshInstance3D, `PlaneMesh` size `(d, d)` with `d = 1.3 × footprint diagonal` for buildings/props and `1.3 × 1.0` for units, y = 0.03, per-side ground material).
  - `static func card_size(kind: String, footprint_cells: int) -> Vector2` (w, h in world units): buildings `w = cells × √2 × 1.05`, props `w = √2`, units `h = 1.4` or `1.9` for `LARGE_UNITS`; the other dimension from the texture aspect.
  - `static func bar_height(kind: String, footprint_cells: int) -> float` = card height + 0.3 (used by the HUD health bars).
  - `static func is_card(node: Node3D) -> bool` (child(0) named `Card`).
  - `static func set_rise(node, progress: float)`, `set_flip(node, flipped: bool)`, `set_tint(node, color: Color)` → `set_instance_shader_parameter` on `Card` (and `Shadow` for rise/flip).
  - `static func sun_ground_direction(sun_rotation_degrees: Vector3) -> Vector2` = normalized `(-cos(p)·sin(y), -cos(p)·cos(y))` in XZ; `static func shadow_length(sun_rotation_degrees) -> float` = `1/tan(-p)` (p = pitch, negative) clamped to [0.5, 1.6].
  - `static func set_sun(dir: Vector2, length: float)` → sets the `sun_dir`/`shadow_length` uniforms on every shadow material.
  - `static func set_shadows_enabled(on: bool)` → toggles visibility of all `Shadow` meshes (registered in a static array).
  - `static func ground_only(parent: Node3D, disc: Color, diameter: float) -> MeshInstance3D` → adds just the `Ground` quad (contact shadow plus owner disc) under a 3D-model entity (walker, archive), so mixed kinds share the depth cues.
- Shader contract (`sprite_card.gdshader`): `render_mode unshaded, cull_disabled, depth_draw_opaque; uniform sampler2D tex : source_color; uniform float anchor_offset = 0.0; instance uniform float rise = 1.0; instance uniform float flip = 0.0; instance uniform vec4 tint : source_color = vec4(1.0);` Vertex: full billboard preserving the quad's local size: `cam_right = INV_VIEW_MATRIX[0].xyz`, `cam_up = INV_VIEW_MATRIX[1].xyz`, `cam_fwd_ground = normalize(vec3(-INV_VIEW_MATRIX[2].x, 0.0, -INV_VIEW_MATRIX[2].z))`; `world = MODEL_MATRIX[3].xyz + cam_fwd_ground * (-anchor_offset) + cam_right * VERTEX.x + cam_up * VERTEX.y`, then `POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0)`. (Anchor moves the card toward the camera: `-cam_fwd_ground`.) Fragment: `uv.x = mix(UV.x, 1.0-UV.x, flip)`; `if (1.0 - UV.y > rise) discard;` sample; `ALPHA_SCISSOR_THRESHOLD = 0.5`; `ALBEDO = fog_tint(col.rgb * tint.rgb, fog_level(MODEL_MATRIX[3].xyz)); ALPHA = col.a * tint.a` (include `fog_of_war.gdshaderinc`).
- `sprite_shadow.gdshader`: same uniforms plus `uniform vec2 sun_dir = vec2(0.165, 0.986); uniform float shadow_length = 0.9;` Vertex: `base = MODEL_MATRIX[3].xyz - cam_fwd_ground * anchor_offset; world = base + cam_right_ground * VERTEX.x + vec3(sun_dir.x, 0.0, sun_dir.y) * VERTEX.y * shadow_length; world.y = 0.02;` where `cam_right_ground = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z))`. Fragment: `ALBEDO = vec3(0.0); ALPHA = col.a * 0.38 * tint.a` with the same rise/flip, `render_mode unshaded, depth_draw_never, blend_mix`.
- `sprite_ground.gdshader`: `uniform vec4 disc : source_color` (faction colour, alpha 0 for resources), `uniform float contact_alpha = 0.3;` radial falloff: contact ellipse `smoothstep(1.0, 0.55, r)` black, owner disc ring at `r ∈ [0.62, 0.72]` in `disc.rgb` at `disc.a × 0.55`, `depth_draw_never, blend_mix, unshaded`, fog-tinted.

- [ ] **Step 1: Write the failing tests (append to `tests/sprite_cards_test.gd`)**

```gdscript
var core = DASprites.card("core", 0, 5, Color("57ebd5"))
expect(core.get_child(0) is MeshInstance3D and core.get_child(0).name == "Card", "card child(0) is a MeshInstance3D")
expect(is_equal_approx(DASprites.card_size("core", 5).x, 5.0 * sqrt(2.0) * 1.05), "core card width = footprint diagonal x 1.05")
expect(is_equal_approx(DASprites.card_size("worker", 1).y, 1.4) and is_equal_approx(DASprites.card_size("disruptor", 1).y, 1.9), "unit heights 1.4 / 1.9")
var aabb: AABB = core.get_child(0).custom_aabb
expect(aabb.position.y == 0.0 and aabb.end.y >= 2.5 and aabb.size.x >= 5.0, "core pick box covers footprint and 2.5 units up")
var worker = DASprites.card("worker", 0, 1, Color.WHITE)
expect(worker.get_child(0).custom_aabb.end.y >= 0.5, "worker pick box covers 0.5 up")
expect(DASprites.is_card(core) and not DASprites.is_card(DAModels.entity("walker", 0)), "is_card")
DASprites.set_rise(core, 0.4)
expect(is_equal_approx(core.get_child(0).get_instance_shader_parameter("rise"), 0.4), "rise is per instance")
var other = DASprites.card("core", 1, 5, Color("ff795c"))
expect(other.get_child(0).material_override == core.get_child(0).material_override, "one card material per kind")
var d = DASprites.sun_ground_direction(Vector3(-48, -170.5, 0))
var yaw = -0.62
expect(d.dot(Vector2(cos(yaw), -sin(yaw))) > 0.0 and d.dot(Vector2(sin(yaw), cos(yaw))) < 0.0, "shadow falls lower-right at default yaw")
expect(absf(DASprites.shadow_length(Vector3(-48, -170.5, 0)) - 0.9) < 0.02, "shadow length from sun elevation")
DASprites.set_shadows_enabled(false)
expect(not core.get_node("Fx/Shadow").visible, "shadow toggle")
expect(core.get_node("Fx/Ground").mesh is PlaneMesh, "ground disc present")
```

- [ ] **Step 2: Run to verify it fails**

Run: `./tools/godot.sh --headless --script tests/sprite_cards_test.gd`
Expected: `SCRIPT ERROR` on `DASprites.card`.

- [ ] **Step 3: Write the three shaders and the builders in `sprite_cards.gd`**

Materials are cached per kind (card, shadow) and per side colour (ground) in static dictionaries; the shadow materials are also kept in a static array for `set_sun`/`set_shadows_enabled`.

- [ ] **Step 4: Run tests**

Run: `./tools/godot.sh --headless --script tests/sprite_cards_test.gd`
Expected: no `FAIL:`; shader compile produces no `ERROR:` lines (headless still parses shaders).

- [ ] **Step 5: Commit**

```bash
git add assets/shaders/sprite_*.gdshader scripts/sprite_cards.gd tests/sprite_cards_test.gd
git commit -m "Sprite cards: billboard card, sheared cast shadow and ground disc"
```

### Task 4: Battlefield integration (cards replace meshes, sun and camera retuned)

**Files:**
- Modify: `scripts/battlefield.gd` (`SUN_ROTATION`, `CAMERA_ELEVATION`, `build_sun`, `sync()` 1001-1060, `preview()` 1081-1095, `apply_settings` shadow branch 258-267)
- Modify: `scripts/main.gd:641-642` (shadow toggle also calls `DASprites.set_shadows_enabled`), `scripts/interface.gd:972` (bar height)
- Modify: `tests/interface_test.gd` (append the Review Focus cases), `tests/model_assets_test.gd` unchanged

**Interfaces:**
- Consumes: Task 3 API.
- Produces: `battlefield.gd` `func entity_node(e: Dictionary) -> Node3D` (card when `DASprites.has_sprite(e.kind)`, else `DAModels.entity(...)`, with a ground disc added under 3D kinds too via `DASprites.ground_only(side_color, diameter)`); `func camera_right_ground() -> Vector2` = `(cos(yaw), -sin(yaw))`.

- [ ] **Step 1: Write the failing tests (append to `tests/interface_test.gd`, using its existing `game`, `spawn` and `click` helpers)**

```gdscript
# Review Focus 1: flip follows camera yaw
var s = spawn("sentinel", 0, Vector2(20, 20)); game.sim.order_move([s.id], Vector2(10, 20))
game.field.yaw = -0.62; game.field.update_camera(); game.field.sync(0.1, [])
var card = game.field.models[s.id].get_child(0)
expect(card.get_instance_shader_parameter("flip") == 1.0, "moving to world -x flips at default yaw")
game.field.yaw = -0.62 + PI; game.field.update_camera(); game.field.sync(0.1, [])
expect(card.get_instance_shader_parameter("flip") == 0.0, "same move after half-turn does not flip")
# Review Focus 2: ghost tint does not leak
game.field.preview("generator", Vector2(30, 30), true)
expect(game.field.models.values()[0].get_child(0).get_instance_shader_parameter("tint") == null or Color(game.field.models.values()[0].get_child(0).get_instance_shader_parameter("tint")) == Color(1,1,1,1), "entity cards keep white tint while a ghost is shown")
# Review Focus 3: rebuild after load
var before = game.field.models.size(); game.save_game(); game.load_game(); game.field.sync(0.1, [])
expect(game.field.models.size() == before and DASprites.is_card(game.field.models[s.id]), "cards rebuilt after load")
# construction rise
var g = spawn("generator", 0, Vector2(40, 40), false); game.field.sync(0.1, [])
expect(game.field.models[g.id].get_child(0).get_instance_shader_parameter("rise") < 1.0 and game.field.models[g.id].scale == Vector3.ONE, "construction uses rise, not node scale")
```
(Adapt helper names to the ones `interface_test.gd` already defines; `click(screen_at(core.pos, 2.5))` at line 142 and `screen_at(worker.pos, 0.5)` at 64 stay as they are and must keep passing.)

- [ ] **Step 2: Run to verify it fails**

Run: `./tools/godot.sh --headless --script tests/interface_test.gd`
Expected: `FAIL:` on the flip and rise cases (cards not used yet).

- [ ] **Step 3: Integrate in `battlefield.gd`**

- `SUN_ROTATION = Vector3(-48, -170.5, 0)`, `CAMERA_ELEVATION = 38.0`; in `build_sun` after setting rotation: `DASprites.set_sun(DASprites.sun_ground_direction(SUN_ROTATION), DASprites.shadow_length(SUN_ROTATION))`; `sun.shadow_enabled` changes also call `DASprites.set_shadows_enabled`.
- `sync()`: creation uses `entity_node(e)`; the unit-batch branch and `get_child(0).visible = false` only when `not DASprites.is_card(n)`; construction: `DASprites.set_rise(model, clampf(progress, 0, 1))` for cards (node scale stays ONE), existing scale path for 3D kinds; facing: for cards `DASprites.set_flip(model, direction.dot(camera_right_ground()) < 0.0)` and no rotation; batch transforms only for non-card units. Resources (owner -1) with a sprite get a ground quad with `disc.a = 0`.
- Selection ring stays `DAModels.ring(n, radius, ...)` (direct child, keeps picking semantics).
- `preview()`: when `DASprites.has_sprite(kind)`, `ghost = DASprites.card(kind, 0, 2*radius+1, Color.WHITE)` and `DASprites.set_tint(ghost, Color(0.25,1,0.7,0.5) if valid else Color(1,0.2,0.15,0.5))` instead of the material override loop.
- `interface.gd:972`: `var h = DASprites.bar_height(e.kind, 2*radius+1) if DASprites.has_sprite(e.kind) else (4.4 if e.building else 2.2)`.
- `main.gd:641`: after toggling `field.sun.shadow_enabled`, call `DASprites.set_shadows_enabled(field.sun.shadow_enabled)`.

- [ ] **Step 4: Run the full suite**

Run: `./tools/test.sh`
Expected: exit 0; `builds/interface.log`, `builds/model_assets.log`, `builds/ui_production.log` without `FAIL:`.

- [ ] **Step 5: Commit**

```bash
git add scripts/battlefield.gd scripts/main.gd scripts/interface.gd tests/interface_test.gd
git commit -m "Draw buildings, units and deposits as photoreal sprite cards; sun and camera follow the sprites"
```

### Task 5: Visual tuning against real captures

**Files:**
- Modify: `scripts/sprite_cards.gd` (size factors, alphas), `scripts/battlefield.gd` (`CAMERA_ELEVATION`, exposure if needed), `docs/VALIDATION.md` (one paragraph), `README.md`

- [ ] **Step 1: Capture the demo scene on both renderers**

Run: `./tools/render_scene.sh --gl --zoom 30 && ./tools/render_scene.sh --vulkan --zoom 30`
Expected: `builds/scene-gl.png` and `builds/scene-vulkan.png` written, logs free of `SCRIPT ERROR|^ERROR:`. View both images.

- [ ] **Step 2: Judge against the spec's anti-goals and fix**

Check: cards stand on the ground (no float/sink), cast shadows fall lower-right and agree with Polyhaven tree shadows, contact shadow and owner disc visible but fainter than the selection ring, building cards cover their footprint (compare with the placement grid in a `--demo` capture with a ghost), unit cards neither tiny nor towering next to the 3D walker, fog dims cards like terrain. Adjust `CAMERA_ELEVATION` (35 to 40), `BUILDING_WIDTH_FACTOR`, unit heights, `contact_alpha`, disc alpha. Re-capture until clean; keep the final capture as `docs/images/sprite-look.png` (small JPEG, under 400 KB).

- [ ] **Step 3: Run the UI capture pass and the benchmark**

Run: `./tools/render_ui.sh && ./tools/godot.sh --rendering-method gl_compatibility --headless -- --benchmark 2>&1 | tail -5`
Expected: `render_ui.sh` exits 0; benchmark prints average CPU ms and fps; note the numbers in `docs/VALIDATION.md` next to the previous ones (no budget is committed, but a regression above 2× CPU ms must be investigated: per-instance uniforms, shadow quads).

- [ ] **Step 4: Full suite once more, commit**

```bash
./tools/test.sh
git add scripts docs README.md
git commit -m "Tune the sprite look: camera elevation, card sizes, shadow and disc strength"
```

### Task 6: Publish to GitHub and link from Age of AI

**Files:**
- Age of AI checkout (scratchpad): `README.md` (+1 line under "Status")

- [ ] **Step 1: Wait for auth**

Run: `gh auth status`
Expected: logged in as a member of `ultimAItechORG`. If not, stop and tell the user to run `gh auth login` (this is the only step that needs them).

- [ ] **Step 2: Create and push**

```bash
git remote add origin https://github.com/ultimAItechORG/digital-age.git 2>/dev/null || true
gh repo create ultimAItechORG/digital-age --private --source . --remote origin --push
```
Expected: repo exists, `master` pushed. (Private by default; the user can flip visibility.)

- [ ] **Step 3: Verify**

Run: `gh repo view ultimAItechORG/digital-age --json url,defaultBranchRef && git ls-remote --heads origin`
Expected: URL printed, `refs/heads/master` listed.

- [ ] **Step 4: Age of AI README pointer**

In the scratchpad checkout: `git checkout claude/android-aoe-game-design-zxg952`, append under "## Status": "* The photoreal sprite set under `art/` (branch `claude/keen-lamport-xkem6m`) is now also the look of **Digital Age** (`ultimAItechORG/digital-age`), the 3D game that carries this art forward." Commit with the attribution line and `git push origin claude/android-aoe-game-design-zxg952`.
Expected: push accepted; `gh api repos/ultimAItechORG/age-of-ai/contents/README.md` shows the line.

## Verification (end to end)

1. `./tools/test.sh` exits 0 (includes the new `sprite_cards` test and the extended `interface_test`).
2. `./tools/render_scene.sh --gl` and `--vulkan` produce captures showing sprite cards with lower-right cast shadows, contact shadows and faction discs on the PBR terrain; `./tools/render_ui.sh` exits 0 and the selection panel shows sprite portraits.
3. `./run.sh` on the desktop: start **First Signal**, select a Worker (drone card, cyan disc), build a Generator (ghost tinted green/red, rises on completion), rotate with Q/E (cards keep facing), toggle shadows in settings (card shadows follow), F5/F9 (cards rebuild), Foundry wave arrives as red-disc cards.
4. `git log --oneline` on `ultimAItechORG/digital-age` shows the six commits above; Age of AI's README links back.

## Execution recommendation

Native (this session implements every task, one fresh reviewer at the end): the tasks share `battlefield.gd` and `sprite_cards.gd` interfaces that are easiest to keep consistent in one context, there are six tasks, and the capture-driven tuning in Task 5 needs the visual judgement built up here.
