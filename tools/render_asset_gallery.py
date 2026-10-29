"""Render the original machine kit using Blender's CPU Cycles renderer."""
import sys
from pathlib import Path
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import create_industrial_assets as kit

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
kit.LOW = False

def lettering(text, position, size, material='white'):
    bpy.ops.object.text_add(location=position)
    obj = bpy.context.object
    obj.name = text
    obj.data.body = text
    obj.data.align_x = 'CENTER'
    obj.data.size = size
    obj.data.extrude = .001
    obj.data.materials.append(kit.mat(material))

order = ['core', 'fabricator', 'generator', 'depot', 'data_center', 'tower',
         'worker', 'scout', 'sentinel', 'disruptor', 'walker', 'archive',
         'road', 'cable', 'substation', 'metal', 'ruin', 'barrier']
for index, kind in enumerate(order):
    x = (index % 6 - 2.5) * 7.0
    y = (1 - index // 6) * 9.2
    before = set(bpy.context.scene.objects)
    kit.asset(kind)
    scale = 1.65 if kind in ('worker','scout','sentinel','disruptor','barrier') else 1
    for obj in set(bpy.context.scene.objects) - before:
        obj.location *= scale
        obj.scale *= scale
        obj.location += Vector((x,y,.1))
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x,y,-.12))
    plate = bpy.context.object
    plate.name = kind + ' display plinth'
    plate.dimensions = (6.4,7.5,.24)
    plate.data.materials.append(kit.mat('dark'))
    lettering(kind.replace('_',' ').upper(), (x,y-3.35,.02), .36)

lettering('DIGITAL AGE', (0,16.3,0), 1.35)
lettering('MACHINE CIVILIZATIONS  /  ORIGINAL 3D ASSET KIT', (0,15.1,0), .4,'team')
lettering('18 ASSET TYPES   /   EDITABLE BLENDER SOURCES   /   GLTF EXPORTS', (0,-15.1,0), .36)

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.resolution_x = 1800
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 100
scene.world.color = (.16,.16,.16)
scene.view_settings.view_transform = 'AgX'
for name, location, energy, size, color in [
    ('Key', (0,-10,28), 16000, 25, (.78,.89,1)),
    ('Fill', (-20,8,18), 11000, 20, (.3,.65,1)),
    ('Rim', (20,15,22), 19000, 18, (1,.65,.3)),
]:
    bpy.ops.object.light_add(type='AREA', location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = 'DISK'
    light.data.size = size
    light.data.color = color
    light.rotation_euler = (Vector((0,0,0))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(0,-32,52))
camera = bpy.context.object
camera.rotation_euler = (Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 46
scene.camera = camera
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = str(kit.ROOT / 'art' / 'asset_gallery.png')
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(kit.ROOT / 'art' / 'asset_gallery.blend'))
bpy.ops.render.render(write_still=True)
