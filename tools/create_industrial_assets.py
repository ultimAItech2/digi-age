"""Run with Blender 4.5: blender -b --python tools/create_industrial_assets.py.
Original Digital Age hard-surface kit. Coordinates use Godot-style X/Y-up/Z
at the authoring boundary; conversion below writes Blender's Z-up scene.
"""
import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models'
OUT.mkdir(parents=True, exist_ok=True)
PALETTE = {'armor': '#263c52', 'edge': '#698298', 'dark': '#080f1d',
           'team': '#00f0ff', 'amber': '#ffaa00', 'violet': '#b026ff',
           'concrete': '#344351', 'white': '#bad0d9'}

def mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    h = PALETTE[name].lstrip('#')
    rgb = tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*rgb, 1)
    bs.inputs['Metallic'].default_value = .55 if name not in ('concrete', 'team') else .1
    bs.inputs['Roughness'].default_value = .55
    if name in ('team', 'amber', 'violet'):
        bs.inputs['Emission Color'].default_value = (*rgb, 1)
        bs.inputs['Emission Strength'].default_value = 1
    return m

def box(name, p, s, material='armor', bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(p[0], -p[2], p[1]))
    o = bpy.context.object
    o.name = name
    o.dimensions = (s[0], s[2], s[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat(material))
    if bevel and not LOW:
        m = o.modifiers.new('Machined edges', 'BEVEL')
        m.width, m.segments = bevel, 1
        bpy.ops.object.modifier_apply(modifier=m.name)
        o.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    return o

def cyl(name, p, radius, height, material='edge', vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=6 if LOW else vertices, radius=radius,
                                      depth=height, location=(p[0], -p[2], p[1]))
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat(material))
    return o

def building_base(radius):
    box('Foundation', (0,.12,0), (radius*2,.24,radius*2), 'concrete')
    box('Undercarriage', (0,.32,0), (radius*1.8,.25,radius*1.8), 'dark')
    for x in [-1,1]:
        box('Power conduit', (x*radius*.87,.28,0), (.07,.045,radius*1.65), 'team', 0)
        for z in [-1,1]:
            box('Corner lock', (x*radius*.85,.42,z*radius*.85), (.3,.35,.3), 'edge')

def vents(x, y, z, count=5):
    if LOW: return
    for i in range(count):
        box('Cooling fin', (x+(i-(count-1)/2)*.18,y,z), (.085,.11,.7), 'dark', 0)

def asset(kind):
    if kind == 'core':
        building_base(2.35)
        cyl('Octagonal pedestal',(0,.6,0),1.9,.65)
        box('Archive monolith',(0,1.65,0),(1.75,2.5,1.75),'dark',.1)
        for x in [-1,1]:
            for z in [-1,1]:
                box('Armored buttress',(x*1.4,1.55,z*1.4),(.5,2.4,.5),'armor',.1)
                box('Signal strip',(x*1.4,1.65,z*1.68),(.11,1.9,.06),'team',0)
        cyl('Crown',(0,3.0,0),1.05,.35,'edge',8)
        cyl('Signal crystal',(0,3.55,0),.48,.85,'violet',6)
        for y in [1.0,1.7,2.4]:
            box('Archive index',(0,y,.9),(1.3,.085,.05),'team',0)
        box('Antenna',(0,4.25,0),(.045,.6,.045),'edge',0)
    elif kind == 'generator':
        building_base(1.4)
        cyl('Flux vessel',(0,1.0,0),.72,1.4,'dark')
        cyl('Flux chamber',(0,1.2,0),.5,1.6,'team')
        cyl('Reactor cap',(0,2.05,0),.85,.25)
        for x in [-1,1]:
            box('Cooling pack',(x*.95,1,0),(.5,1.25,1.4))
            vents(x*.95,1.68,0,3)
        for z in [-1,1]:
            box('Copper bus',(0,.5,z*.9),(1.8,.12,.1),'amber',0)
    elif kind == 'fabricator':
        building_base(2.3)
        for x in [-1,1]:
            box('Factory side pod',(x*1.65,1.2,0),(.75,1.65,3.5))
            vents(x*1.65,2.07,0,3)
            box('Gantry pillar',(x*1.5,1.9,1.45),(.32,2.5,.32),'edge')
            box('Door guidance',(x*1.22,1,1.7),(.06,1.2,.08),'team',0)
        box('Gantry bridge',(0,3.2,1.45),(3.45,.35,.55),'edge')
        box('Manipulator carriage',(0,2.85,1.45),(.65,.45,.5),'amber')
        box('Rear workshop',(0,1.05,-1.2),(2.5,1.4,.8),'dark')
        box('Conveyor',(0,.5,.35),(2.3,.15,2.6),'dark')
        if not LOW:
            for z in range(7):
                box('Conveyor rib',(0,.61,-.8+z*.35),(2.1,.06,.1),'edge',0)
    elif kind == 'worker':
        box('Crawler chassis',(0,.43,0),(.9,.4,1.1))
        for x in [-1,1]:
            box('Track housing',(x*.55,.25,0),(.3,.38,1.3),'dark')
            if not LOW:
                for z in [-.45,0,.45]:
                    box('Track tread',(x*.55,.13,z),(.36,.13,.19),'edge',0)
            box('Salvage fork',(x*.3,.45,.9),(.12,.12,.9),'amber')
        cyl('Tool turret',(0,.8,-.12),.34,.36)
        box('Optics',(0,.86,.24),(.38,.09,.09),'team',0)
        box('Cargo rack',(0,.7,-.48),(.65,.15,.26),'dark')
    elif kind == 'sentinel':
        for x in [-1,1]:
            box('Foot',(x*.34,.12,.1),(.36,.24,.6),'dark')
            box('Leg actuator',(x*.34,.5,0),(.23,.65,.24),'edge')
        box('Pelvis',(0,.78,0),(.75,.22,.4),'dark')
        box('Torso',(0,1.12,0),(.8,.62,.55))
        box('Helmet',(0,1.6,0),(.52,.32,.42),'dark')
        box('Visor',(0,1.64,.22),(.4,.06,.04),'team',0)
        box('Shoulder shield',(-.57,1.18,0),(.32,.5,.55),'edge')
        box('Weapon cradle',(.56,1.15,.17),(.3,.3,.65),'dark')
        box('Accelerator barrel',(.56,1.15,.72),(.13,.13,.6),'edge')
        box('Weapon tracer',(.56,1.24,.55),(.065,.045,.65),'team',0)
    elif kind == 'road':
        box('Road slab',(0,-.025,0),(4,.05,4),'dark',0)
        for x in [-1,1]:
            box('Curb',(x*1.9,.04,0),(.13,.08,4),'concrete',0)
            box('Guidance strip',(x*1.73,.005,0),(.04,.025,2.4),'team',0)
        box('Lane dash',(0,.01,0),(.08,.025,1.5),'amber',0)
    elif kind == 'cable':
        box('Cable tray',(0,.04,0),(.6,.08,4),'dark',0)
        for x in [-.2,0,.2]:
            box('Cable',(x,.1,0),(.08,.08,4),'team' if x == 0 else 'edge',0)
    elif kind == 'substation':
        building_base(1.3)
        for x in [-.65,.65]:
            box('Transformer',(x,.85,0),(.8,1.2,1.3))
            for z in [-.4,.4]:
                cyl('Insulator',(x,1.65,z),.12,.5,'amber',8)
    elif kind == 'archive':
        building_base(1.35)
        box('Archive shell',(0,1.45,0),(1.4,2.5,1.3),'dark',.1)
        for y in [.6,1.15,1.7,2.25]:
            box('Repository slot',(0,y,.69),(1.1,.09,.07),'violet',0)
        cyl('Archive beacon',(0,2.95,0),.4,.45,'violet',6)
    elif kind == 'ruin':
        box('Ruined floor',(0,.1,0),(3,.2,3),'concrete')
        box('Broken wall',(-1.25,1.4,0),(.25,2.8,3),'concrete')
        box('Broken wall',(0,.7,-1.3),(2.4,1.4,.25),'concrete')
        for z in [-1,1]:
            box('Exposed beam',(-1.1,2.5,z),(.13,1.4,.13),'edge',0)
        box('Fallen equipment',(.5,.5,.4),(1.2,.8,1.1),'armor')
    elif kind == 'barrier':
        box('Obstruction',(0,.65,0),(1.0,1.3,1.0),'concrete',.12)
        box('Hazard marking',(0,.7,.51),(.7,.12,.02),'amber',0)

def export(kind):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    asset(kind)
    # All parts remain separately editable in the .blend source.
    bpy.context.scene['provenance'] = 'Original Digital Age mesh kit; tools/create_industrial_assets.py'
    bpy.context.scene['units'] = '1 Blender unit = 1 metre; Z up, -Y forward'
    suffix = '_low' if LOW else ''
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'art' / (kind+suffix+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(kind+suffix+'.glb')), export_format='GLB',
                              export_apply=True, export_animations=False)

for LOW in (False, True):
    for name in ('core','worker','sentinel','generator','fabricator','road','cable','substation','archive','ruin','barrier'):
        export(name)
print('DIGITAL AGE: 22 original Blender sources and glTF exports created.')
