"""Render one transparent 256x256 portrait per model kind for the in-game HUD.

Run from the project root with the bundled Blender:
    .tools/blender-4.5.3-linux-x64/blender -b -noaudio --factory-startup \
        --python-exit-code 1 --python tools/render_thumbnails.py

Each kind is built from the same procedural kit as the game models
(tools/create_industrial_assets.py) with the team material set to the player
faction colour, lit like the asset gallery, and framed by an orthographic
camera from roughly the in-game viewing angle. Output goes to
assets/ui/portraits/<kind>.png with a Godot `importer="keep"` sidecar so the
headless test runner never needs an editor import step.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import create_industrial_assets as kit  # noqa: E402

KINDS = ['core', 'worker', 'scout', 'sentinel', 'disruptor', 'walker',
         'generator', 'depot', 'data_center', 'fabricator', 'tower', 'metal',
         'archive', 'ruin', 'road', 'cable', 'substation', 'barrier']
PLAYER_TEAM = '#57ebd5'          # DAModels.CYAN / faction 0 primary colour
SIZE = 256
SAMPLES = 64
ELEVATION = math.degrees(math.atan2(43, 40))   # in-game camera offset (.., 43, 40)
YAW = 25.0
FIT = 1.25
MARGIN = 1.16                   # floor on the projected box so nothing touches the edge
OUT = kit.ROOT / 'assets' / 'ui' / 'portraits'
LIGHTS = [
    ('Key', (0, -10, 28), 16000, 25, (.78, .89, 1)),
    ('Fill', (-20, 8, 18), 11000, 20, (.3, .65, 1)),
    ('Rim', (20, 15, 22), 19000, 18, (1, .65, .3)),
]
SIDECAR = '[remap]\n\nimporter="keep"\n'

kit.LOW = False
kit.PALETTE['team'] = PLAYER_TEAM


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.lights, bpy.data.cameras):
        for datum in list(block):
            if datum.users == 0:
                block.remove(datum)


def add_lights():
    for name, location, energy, size, color in LIGHTS:
        bpy.ops.object.light_add(type='AREA', location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = 'DISK'
        light.data.size = size
        light.data.color = color
        light.rotation_euler = (Vector((0, 0, 0)) - light.location).to_track_quat('-Z', 'Y').to_euler()


def world_bounds(objects):
    corners = [obj.matrix_world @ Vector(corner)
               for obj in objects if obj.type == 'MESH'
               for corner in obj.bound_box]
    low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    return low, high


def mesh_points(objects):
    """World-space vertices of the evaluated meshes (bevels applied)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in objects:
        if obj.type != 'MESH':
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        points.extend(obj.matrix_world @ v.co for v in mesh.vertices)
        evaluated.to_mesh_clear()
    return points


def fit_camera(low, high, points):
    centre = (low + high) / 2
    extent = high - low
    # Blender: Z up, -Y is the model's front. The game camera sits in front
    # (+Z in Godot) and above, swung 25 degrees so two faces are visible.
    el, yaw = math.radians(ELEVATION), math.radians(YAW)
    direction = Vector((math.sin(yaw) * math.cos(el), -math.cos(yaw) * math.cos(el), math.sin(el)))
    distance = extent.length * 2 + 20
    bpy.ops.object.camera_add(location=centre + direction * distance)
    camera = bpy.context.object
    camera.name = 'Portrait camera'
    camera.rotation_euler = (-direction).to_track_quat('-Z', 'Y').to_euler()
    camera.data.type = 'ORTHO'
    camera.data.clip_start = .1
    camera.data.clip_end = distance * 2 + extent.length
    scale = FIT * max(extent.x, extent.y, 1.1 * extent.z, .5)
    # Centre the frame on the projected silhouette rather than the box centre
    # (a thin mast leaves the box's top corners empty) and never let the
    # oblique projection leave the frame.
    bpy.context.view_layer.update()
    view = camera.matrix_world.inverted()
    projected = [view @ p for p in points]
    xs, ys = [p.x for p in projected], [p.y for p in projected]
    shift = Vector(((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, 0))
    camera.location += camera.matrix_world.to_3x3() @ shift
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    clamped = span * MARGIN > scale
    camera.data.ortho_scale = max(scale, span * MARGIN)
    return camera, clamped


def configure_render(scene):
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.world.color = (.16, .16, .16)
    scene.view_settings.view_transform = 'AgX'
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'


def render(kind):
    clear_scene()
    before = set(bpy.context.scene.objects)
    kit.asset(kind)
    bpy.context.view_layer.update()
    parts = [obj for obj in bpy.context.scene.objects if obj not in before]
    low, high = world_bounds(parts)
    points = mesh_points(parts)
    add_lights()
    camera, clamped = fit_camera(low, high, points)
    scene = bpy.context.scene
    scene.camera = camera
    configure_render(scene)
    path = OUT / f'{kind}.png'
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    (OUT / f'{kind}.png.import').write_text(SIDECAR)
    size = high - low
    print(f'DIGITAL AGE portrait: {kind} bbox {size.x:.2f}x{size.y:.2f}x{size.z:.2f} '
          f'ortho {camera.data.ortho_scale:.2f}{" (clamped to fit)" if clamped else ""}')
    return {'kind': kind, 'file': path.name, 'parts': len(parts),
            'bounds': [round(v, 3) for v in size],
            'ortho_scale': round(camera.data.ortho_scale, 3),
            'fit_clamped': clamped}


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    report = [render(kind) for kind in KINDS]
    (OUT / 'manifest.json').write_text(json.dumps({
        'blender': bpy.app.version_string,
        'generator': 'tools/render_thumbnails.py',
        'kit': 'tools/create_industrial_assets.py',
        'kinds': KINDS,
        'team_color': PLAYER_TEAM,
        'render': {'engine': 'CYCLES', 'device': 'CPU', 'samples': SAMPLES,
                   'denoise': True, 'view_transform': 'AgX', 'film_transparent': True,
                   'resolution': [SIZE, SIZE], 'format': 'PNG RGBA 8-bit',
                   'camera': {'type': 'ORTHO', 'elevation_deg': round(ELEVATION, 2),
                              'yaw_deg': YAW, 'fit': FIT},
                   'lights': [{'name': n, 'location': list(l), 'energy': e, 'size': s,
                               'color': list(c)} for n, l, e, s, c in LIGHTS]},
        'portraits': report}, indent=2) + '\n')
    print(f'DIGITAL AGE: {len(report)} portraits rendered to {OUT}.')
