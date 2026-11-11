"""The one stage every sprite is rendered on (tools/sprites).

An orthographic camera at the game's fixed view (30 degrees above the ground,
45 degrees to the grid), a sun travelling the way the game's DirectionalLight
does, the game's own sky photograph for fill and reflections (turned so its
sun agrees with the lamp) and an unseen ground plane in the terrain's colour
for bounce. Film is transparent; the cast shadow is drawn in the game, not baked.

`render()` writes the colour frame and the `team` mask for one pose.
"""
import math
import os
import time
from pathlib import Path

import bpy
from mathutils import Vector

PPU = 96                      # pixels per map cell at the sprite's native size
ELEVATION = math.radians(30.0)
# DABattlefield: camera offset (sin yaw cos e, sin e, cos yaw cos e) at yaw -45, in Blender axes (x, -z, y).
TO_CAMERA = Vector((-math.cos(ELEVATION) * math.sqrt(0.5), -math.cos(ELEVATION) * math.sqrt(0.5), math.sin(ELEVATION)))
FORWARD = -TO_CAMERA
RIGHT = Vector((1.0, -1.0, 0.0)).normalized()
UP = RIGHT.cross(FORWARD).normalized()
# DABattlefield.SUN_ROTATION = (-48, -76, 0): the direction the light travels, in Blender axes.
SUN_PITCH = math.radians(48.0)
SUN_YAW = math.radians(-76.0)
SUN_TRAVEL = Vector((-math.cos(SUN_PITCH) * math.sin(SUN_YAW), math.cos(SUN_PITCH) * math.cos(SUN_YAW), -math.sin(SUN_PITCH)))

HDRI = Path(__file__).resolve().parents[2] / 'assets' / 'third_party' / 'processed' / 'hdri' / 'kloofendal_48d_partly_cloudy_puresky_2k.hdr'
SUN_ENERGY = 4.5              # the lamp: the crisp key
SKY_STRENGTH = 0.9           # the photograph: fill, reflections and its own softer sun
EXPOSURE = 0.35                # stops; set so a grey card matches the game's grade (see the README)
GROUND = (0.162, 0.111, 0.048)   # mean of processed/terrain_albedo.jpg, linear

camera = None
mask_node = None


def sky_sun_azimuth(image):
    """Angle of the brightest part of an equirectangular sky, as Blender maps it (atan2(y, x) of the direction)."""
    import numpy as np
    w, h = image.size
    pixels = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    lum = pixels.reshape(h, w, 4)[..., :3].sum(axis=2)
    # A small box blur so one hot pixel in a cloud does not win over the sun.
    k = 9
    pad = np.pad(lum, ((k, k), (k, k)), mode='wrap')
    acc = sum(pad[k + dy:k + dy + h, k + dx:k + dx + w] for dy in range(-k, k + 1, 3) for dx in range(-k, k + 1, 3))
    y, x = np.unravel_index(np.argmax(acc), acc.shape)
    a = ((x + 0.5) / w - 0.5) * math.tau
    return math.atan2(math.sin(a), -math.cos(a))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup(samples=64):
    """Build the stage in an empty file. Call once, before any model."""
    global camera, mask_node
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons['cycles'].preferences
    scene.cycles.device = 'CPU'
    for backend in ('OPTIX', 'CUDA'):
        try:
            prefs.compute_device_type = backend
            prefs.get_devices()
            devices = [d for d in prefs.devices if d.type == backend]
            if devices:
                for d in prefs.devices:
                    d.use = d.type == backend
                scene.cycles.device = 'GPU'
                break
        except Exception:
            continue
    scene.cycles.samples = samples
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.02
    scene.cycles.use_denoising = True
    scene.cycles.denoising_input_passes = 'RGB_ALBEDO_NORMAL'
    if scene.cycles.device == 'GPU':
        try:
            scene.cycles.denoiser = 'OPTIX'
        except TypeError:
            pass
    scene.cycles.max_bounces = 8
    scene.cycles.blur_glossy = 0.6
    scene.render.film_transparent = True
    scene.render.use_persistent_data = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.compression = 30
    # A camera-like response: highlights roll off and strong lights lose saturation.
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = EXPOSURE
    scene.render.resolution_percentage = 100
    # Camera.
    data = bpy.data.cameras.new('SpriteCamera')
    data.type = 'ORTHO'
    data.clip_start = 0.1
    data.clip_end = 400.0
    camera = bpy.data.objects.new('SpriteCamera', data)
    scene.collection.objects.link(camera)
    camera.rotation_euler = FORWARD.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = camera
    # Sun.
    sun_data = bpy.data.lights.new('Sun', 'SUN')
    sun_data.energy = SUN_ENERGY
    sun_data.color = (1.0, 0.945, 0.86)
    sun_data.angle = math.radians(1.6)
    sun = bpy.data.objects.new('Sun', sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = SUN_TRAVEL.to_track_quat('-Z', 'Y').to_euler()
    # The sky: the photograph the game lights its world with, turned so its sun stands where the lamp's does.
    world = bpy.data.worlds.new('Sky')
    world.use_nodes = True
    scene.world = world
    nodes, links = world.node_tree.nodes, world.node_tree.links
    background = nodes['Background']
    background.inputs['Strength'].default_value = SKY_STRENGTH
    if HDRI.exists():
        image = bpy.data.images.load(str(HDRI))
        env = nodes.new('ShaderNodeTexEnvironment')
        env.image = image
        coords = nodes.new('ShaderNodeTexCoord')
        mapping = nodes.new('ShaderNodeMapping')
        want = math.atan2(-SUN_TRAVEL.y, -SUN_TRAVEL.x)
        mapping.inputs['Rotation'].default_value = (0.0, 0.0, sky_sun_azimuth(image) - want)
        links.new(coords.outputs['Generated'], mapping.inputs['Vector'])
        links.new(mapping.outputs['Vector'], env.inputs['Vector'])
        links.new(env.outputs['Color'], background.inputs['Color'])
    else:
        sky = nodes.new('ShaderNodeTexSky')
        sky.sky_type = 'NISHITA'
        sky.sun_disc = False
        sky.sun_elevation = SUN_PITCH
        sky.sun_rotation = math.atan2(-SUN_TRAVEL.x, -SUN_TRAVEL.y)
        links.new(sky.outputs['Color'], background.inputs['Color'])
    # Ground: lights the undersides and darkens the base, but is never in the picture.
    bpy.ops.mesh.primitive_plane_add(size=400.0, location=(0, 0, 0))
    ground = bpy.context.object
    ground.name = 'Ground'
    ground['stage'] = True
    mat = bpy.data.materials.new('Ground')
    mat.use_nodes = True
    mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*GROUND, 1.0)
    mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.9
    ground.data.materials.append(mat)
    ground.visible_camera = False
    ground.visible_shadow = False
    # The team mask leaves through a compositor file output.
    aov = bpy.context.view_layer.aovs.add()
    aov.name = 'team'
    aov.type = 'VALUE'
    scene.use_nodes = True
    tree = scene.node_tree
    tree.nodes.clear()
    layers = tree.nodes.new('CompositorNodeRLayers')
    composite = tree.nodes.new('CompositorNodeComposite')
    tree.links.new(layers.outputs['Image'], composite.inputs['Image'])
    mask_node = tree.nodes.new('CompositorNodeOutputFile')
    mask_node.format.file_format = 'PNG'
    mask_node.format.color_mode = 'BW'
    mask_node.file_slots[0].path = 'mask_'
    tree.links.new(layers.outputs['team'], mask_node.inputs[0])
    return scene


def model_objects():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH' and not o.get('stage')]


def clear_model():
    for obj in [o for o in bpy.context.scene.objects if not o.get('stage') and o.type in ('MESH', 'EMPTY')]:
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in [m for m in bpy.data.meshes if m.users == 0]:
        bpy.data.meshes.remove(mesh)


def bounds():
    """(x0, x1, y0, y1) of every render-visible model vertex on the camera plane, in cells from the origin."""
    bpy.context.view_layer.update()
    x0 = y0 = 1e9
    x1 = y1 = -1e9
    for obj in model_objects():
        if obj.hide_render:
            continue
        world = obj.matrix_world
        for corner in obj.bound_box:
            p = world @ Vector(corner)
            x, y = p.dot(RIGHT), p.dot(UP)
            x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
    return x0, x1, y0, y1


def render(colour_path, mask_path, width, height, centre_x, centre_y):
    """Render the window `width` x `height` pixels centred on (centre_x, centre_y) cells of the camera plane."""
    scene = bpy.context.scene
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    camera.data.ortho_scale = max(width, height) / PPU
    camera.location = TO_CAMERA * 120.0 + RIGHT * centre_x + UP * centre_y
    scene.render.filepath = str(colour_path)
    folder = Path(mask_path).parent
    mask_node.base_path = str(folder)
    started = time.time()
    bpy.ops.render.render(write_still=True)
    print('RENDER %s %dx%d %.1fs on %s' % (Path(colour_path).name, width, height, time.time() - started, scene.cycles.device))
    written = folder / ('mask_%04d.png' % scene.frame_current)
    os.replace(written, mask_path)
