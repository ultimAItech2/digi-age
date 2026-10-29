"""Run with Blender: blender -b --factory-startup --python tools/create_industrial_assets.py.
Original Digital Age hard-surface kit plus overgrown-city scenery (tree, bush,
rubble) and ruined high-rises (highrise_a/b/c). Coordinates use Godot-style X/Y-up/Z
at the authoring boundary; conversion below writes Blender's Z-up scene.
"""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models'
OUT.mkdir(parents=True, exist_ok=True)
(ROOT / 'art').mkdir(exist_ok=True)
KINDS = ('core', 'worker', 'sentinel', 'generator', 'fabricator', 'scout',
         'disruptor', 'walker', 'depot', 'data_center', 'tower', 'metal',
         'road', 'cable', 'substation', 'archive', 'ruin', 'barrier',
         'tree', 'bush', 'rubble', 'highrise_a', 'highrise_b', 'highrise_c')
LOW = False
REPORT = []
PALETTE = {'armor': '#263c52', 'edge': '#698298', 'dark': '#080f1d',
           'team': '#00f0ff', 'amber': '#ffaa00', 'violet': '#b026ff',
           'concrete': '#344351', 'white': '#bad0d9',
           # Overgrown-city scenery: vegetation and weathered masonry.
           'bark': '#4a3626', 'leaf': '#3f6b2e', 'leaf_light': '#6f9a3c',
           'moss': '#55703a', 'rubble': '#7c7568', 'rubble_dark': '#4e4a44',
           # Ruined high-rises: weathered facade panels and a darker service core.
           'facade': '#6e7270', 'facade_dark': '#454a4f'}
NON_METAL = ('concrete', 'team', 'bark', 'leaf', 'leaf_light', 'moss',
             'rubble', 'rubble_dark', 'facade', 'facade_dark')

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def mat(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    h = PALETTE[name].lstrip('#')
    # Palette entries are sRGB hex; Blender and glTF store linear base colours,
    # so convert here or every export comes out one gamma lift too pale.
    rgb = tuple(srgb_to_linear(int(h[i:i+2], 16) / 255) for i in (0, 2, 4))
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*rgb, 1)
    bs.inputs['Metallic'].default_value = .55 if name not in NON_METAL else .1
    bs.inputs['Roughness'].default_value = .55 if name not in NON_METAL else .9
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

def sphere(name, p, radius, material='leaf', squash=1.0):
    """Faceted canopy blob; low variants use the coarsest icosphere."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1 if LOW else 2, radius=radius,
                                          location=(p[0], -p[2], p[1]))
    o = bpy.context.object
    o.name = name
    o.scale = (1, 1, squash)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat(material))
    return o

def windows(x, y0, y1, z, width, material='amber', axis='z', step=1.1, dead=()):
    """Lit window strips climbing a facade; `axis` is the face normal.
    Rows listed in `dead` are unlit. Low variants keep every other row."""
    y, i = y0, 0
    while y < y1:
        if not (LOW and i % 2):
            m = 'dark' if i in dead else material
            size = (width, .14, .05) if axis == 'z' else (.05, .14, width)
            box('Window strip', (x, y, z), size, m, 0)
        y += step
        i += 1

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
    if kind == 'scout':
        box('Recon keel', (0,.48,0), (.62,.32,1.25))
        for x in [-1,1]:
            box('Hover nacelle', (x*.56,.32,0), (.3,.35,1.05), 'dark')
            box('Lift rail', (x*.56,.16,0), (.18,.06,.75), 'team', 0)
            box('Nacelle armor', (x*.56,.54,-.1), (.33,.13,.62), 'edge')
        cyl('Sensor gimbal', (0,.78,-.15), .26,.3)
        box('Optical array', (0,.85,.12), (.36,.12,.08), 'team', 0)
        box('Antenna mast', (.23,1.1,-.43), (.035,.75,.035), 'edge', 0)
        cyl('Mast beacon', (.23,1.48,-.43), .06,.08,'team',8)
    elif kind == 'disruptor':
        box('Electronic warfare chassis', (0,.43,0), (1,.4,1.25))
        for x in [-1,1]:
            box('Tracked outrigger', (x*.63,.24,0), (.32,.4,1.45), 'dark')
            box('Capacitor bank', (x*.4,.8,-.35), (.28,.5,.65), 'edge')
            for z in [-.55,0,.55]:
                box('Track shoe', (x*.63,.12,z), (.37,.12,.2),'edge',0)
        cyl('Emitter swivel',(0,1.0,.1),.23,.8,'dark')
        dish = cyl('Faceted emitter dish',(0,1.52,.1),.65,.17,'edge',16)
        dish.rotation_euler.x = math.radians(35)
        emitter = cyl('Induction face',(0,1.6,.15),.49,.08,'team',16)
        emitter.rotation_euler.x = math.radians(35)
        box('Pulse feed',(0,1.82,.3),(.12,.4,.12),'violet')
    elif kind == 'walker':
        # Authored at final siege scale; no runtime scale multiplier needed.
        for x in [-1,1]:
            for z in [-1,1]:
                box('Siege foot',(x*.86,.16,z*.76),(.65,.32,.86),'dark')
                box('Lower piston',(x*.86,.64,z*.66),(.23,.85,.25),'edge')
                leg = box('Upper leg armor',(x*.71,1.04,z*.57),(.4,.72,.45))
                leg.rotation_euler.y = x*math.radians(18)
                cyl('Hip bearing',(x*.65,1.35,z*.5),.25,.22,'amber')
        box('Siege hull',(0,1.43,0),(1.65,.63,1.95))
        box('Turret',(0,2.03,-.15),(1.1,.65,1.3),'dark')
        box('Railgun',(0,2.12,1.12),(.32,.3,2.2),'edge')
        for x in [-1,1]:
            box('Accelerator rail',(x*.22,2.14,1.1),(.09,.12,2.05),'team',0)
        box('Muzzle collar',(0,2.12,2.13),(.55,.44,.25),'dark')
        box('Muzzle aperture',(0,2.12,2.265),(.24,.17,.025),'team',0)
        vents(0,2.39,-.4,5)
    elif kind == 'depot':
        building_base(1.3)
        box('Loading deck',(0,.48,0),(2.15,.18,2.1),'edge')
        for x in [-1,1]:
            box('Dock post',(x*1.05,1.0,-.8),(.22,1.25,.22))
        box('Cargo hoist',(0,1.68,-.8),(2.3,.22,.35),'amber')
        for x in [-.58,.1,.7]:
            box('Salvage crate',(x,.88,-.1),(.52,.65,.85),'armor')
            box('Crate band',(x,.9,.34),(.4,.12,.025),'amber',0)
        box('Loading ramp',(0,.3,1.05),(1.7,.15,.7),'dark')
    elif kind == 'data_center':
        building_base(1.3)
        for x in [-.72,0,.72]:
            box('Server rack',(x,1.42,0),(.6,2.0,1.65),'armor')
            box('Server fascia',(x,1.42,.84),(.48,1.75,.035),'dark',0)
            for y in [.7,1.1,1.5,1.9,2.2]:
                box('Compute indicator',(x,y,.87),(.37,.055,.025),'team',0)
            vents(x,2.45,0,2)
        box('Network bus',(0,2.53,-.55),(2.15,.12,.18),'edge')
    elif kind == 'tower':
        building_base(1.25)
        cyl('Tower pedestal',(0,.75,0),.85,.8,'dark',8)
        cyl('Armored column',(0,1.7,0),.58,1.5,'armor',8)
        for x in [-1,1]:
            box('Column signal',(x*.58,1.7,0),(.05,1.2,.15),'team',0)
        cyl('Turret bearing',(0,2.55,0),.7,.23,'edge')
        box('Gun housing',(0,2.94,0),(1.6,.6,1.2),'armor')
        for x in [-.38,.38]:
            box('Twin cannon',(x,2.98,1.0),(.2,.2,1.3),'edge')
            box('Barrel channel',(x,3.1,.98),(.055,.035,1.15),'team',0)
        box('Targeting sensor',(0,3.35,.15),(.4,.2,.4),'dark')
        box('Targeting lens',(0,3.35,.36),(.25,.1,.025),'team',0)
    elif kind == 'metal':
        box('Salvage footing',(0,.06,0),(2.3,.12,2.0),'concrete')
        for i in range(7):
            a = i*2.4
            o = box('Discarded machine plating',(math.sin(a)*.65,.3+(i%3)*.22,math.cos(a)*.6),
                    (.8,.24,.65),'edge' if i%2 else 'armor')
            o.rotation_euler = (.13*i,.17*i,a)
        box('Recoverable alloy',(0,1.02,0),(.75,.15,.5),'amber')
    elif kind == 'core':
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
    elif kind == 'tree':
        # Broadleaf street tree reclaiming the ruins; ~3 m tall at scale 1.
        cyl('Trunk', (0,.8,0), .16, 1.6, 'bark', 7)
        limb = cyl('Limb', (.22,1.55,.1), .07, .7, 'bark', 5)
        limb.rotation_euler = (math.radians(20), math.radians(-35), 0)
        sphere('Canopy', (0,2.1,0), .95, 'leaf', .82)
        sphere('Canopy crown', (.15,2.6,-.1), .72, 'leaf_light', .8)
        sphere('Canopy side', (-.55,1.9,.35), .55, 'leaf', .85)
        if not LOW:
            sphere('Canopy side', (.5,1.85,-.45), .5, 'leaf_light', .85)
    elif kind == 'bush':
        # Low shrub clump; groundcover between the ruins.
        sphere('Shrub', (0,.42,0), .5, 'leaf', .75)
        sphere('Shrub', (.38,.32,.22), .36, 'leaf_light', .8)
        sphere('Shrub', (-.33,.3,-.25), .32, 'moss', .8)
        if not LOW:
            sphere('Shrub', (.05,.55,-.3), .28, 'leaf_light', .85)
    elif kind == 'rubble':
        # Collapsed masonry heap; concrete blocks with rebar and moss.
        box('Debris bed', (0,.08,0), (1.6,.16,1.4), 'rubble_dark', .03)
        for i, (x, y, z, s, m) in enumerate([
                (-.35,.35,-.2,.6,'rubble'), (.3,.32,.25,.55,'rubble'),
                (.1,.62,-.15,.42,'concrete'), (-.1,.3,.45,.4,'rubble_dark'),
                (.5,.25,-.45,.35,'rubble')]):
            if LOW and i > 2: break
            o = box('Concrete block', (x,y,z), (s,s*.7,s*.85), m, .03)
            o.rotation_euler = (.15*i, .55*i, .1*i)
        box('Moss patch', (-.2,.17,.3), (.7,.04,.5), 'moss', 0)
        if not LOW:
            for i, (x, z) in enumerate([(.25,-.1), (-.4,.1)]):
                bar = box('Rebar', (x,.75,z), (.03,.7,.03), 'dark', 0)
                bar.rotation_euler = (.5+.2*i, 0, -.35+.6*i)

    elif kind == 'highrise_a':
        # Slab tower, ~12 m; the top floors are sheared off on one side.
        box('Plinth', (0,.15,0), (3.0,.3,2.4), 'rubble_dark', .03)
        box('Shell', (0,4.6,0), (2.4,8.8,1.8), 'facade', .05)
        box('Upper shell', (-.35,10.2,0), (1.7,2.4,1.8), 'facade', .05)
        box('Top stub', (-.75,12.0,-.3), (.6,1.4,.9), 'facade_dark', 0)
        box('Exposed column', (.95,10.1,.6), (.16,2.2,.16), 'edge', 0)
        box('Exposed column', (.95,9.8,-.6), (.16,1.6,.16), 'edge', 0)
        slab = box('Collapsed floor', (1.75,.95,.2), (1.6,.12,1.5), 'facade_dark', 0)
        slab.rotation_euler = (math.radians(14), math.radians(-28), 0)
        windows(0, 1.2, 8.6, .93, 1.9, 'amber', 'z', dead=(2,5))
        windows(0, 1.2, 8.6, -.93, 1.9, 'amber', 'z', dead=(1,4,6))
        windows(-.35, 9.3, 11.2, .93, 1.3, 'amber', 'z')
    elif kind == 'highrise_b':
        # Narrow tower, ~14 m; the facade has fallen away around the service core.
        box('Plinth', (0,.15,0), (2.2,.3,2.2), 'rubble_dark', .03)
        box('Core', (0,6.6,0), (1.0,13.2,1.0), 'dark', 0)
        box('Shell', (0,5.0,0), (1.7,10.0,1.7), 'facade', .05)
        box('Upper shell', (.2,11.4,-.2), (1.3,2.8,1.3), 'facade', .05)
        box('Crown', (-.2,13.4,.1), (.7,1.2,.6), 'facade_dark', 0)
        for (x, z, h) in [(-.8,-.8,11.2), (.8,-.8,13.0), (-.8,.8,9.6), (.8,.8,14.0)]:
            box('Corner column', (x,h*.5,z), (.18,h,.18), 'edge', 0)
        slab = box('Hanging slab', (1.15,8.4,0), (1.0,.1,1.4), 'facade_dark', 0)
        slab.rotation_euler = (0, math.radians(35), 0)
        windows(0, 1.1, 9.6, .88, 1.3, 'violet', 'z', dead=(0,3,6))
        windows(.88, 1.1, 9.6, 0, 1.3, 'violet', 'x', dead=(2,5))
        windows(.2, 10.4, 12.6, -.88, .9, 'violet', 'z')
    elif kind == 'highrise_c':
        # Wide block, ~7 m, with a collapsed corner wing and rubble spill.
        box('Plinth', (0,.15,0), (3.8,.3,2.8), 'rubble_dark', .03)
        box('Main block', (-.5,3.5,0), (2.4,6.8,2.2), 'facade', .05)
        box('Wing', (1.35,2.3,-.35), (1.3,4.4,1.5), 'facade', .05)
        box('Roof plant', (-.9,7.2,.3), (.8,.8,.7), 'facade_dark', 0)
        box('Roof stub', (.2,7.0,-.6), (.5,.4,.5), 'facade_dark', 0)
        for i, (x, y, z, s) in enumerate([(1.5,.55,.75,.7), (2.0,.4,.2,.55), (1.1,.45,1.0,.5)]):
            if LOW and i > 0: break
            o = box('Collapse debris', (x,y,z), (s,s*.6,s*.8), 'rubble', .03)
            o.rotation_euler = (.2*i, .7*i, .15*i)
        beam = box('Fallen beam', (1.6,1.1,.5), (.14,2.6,.14), 'edge', 0)
        beam.rotation_euler = (math.radians(70), 0, math.radians(20))
        windows(-.5, 1.0, 6.6, 1.13, 2.0, 'amber', 'z', dead=(1,4))
        windows(-.5, 1.0, 6.6, -1.13, 2.0, 'amber', 'z', dead=(2,))
        windows(-1.73, 1.0, 6.6, 0, 1.6, 'amber', 'x', dead=(0,3))
        windows(1.35, 1.0, 4.2, -1.13, 1.0, 'amber', 'z')

def export(kind):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    asset(kind)
    # All parts remain separately editable in the .blend source.
    bpy.context.scene['provenance'] = 'Original Digital Age mesh kit; tools/create_industrial_assets.py'
    bpy.context.scene['units'] = '1 Blender unit = 1 metre; Z up, -Y forward'
    suffix = '_low' if LOW else ''
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.preferences.filepaths.save_version = 0
    triangles = 0
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            mesh.calc_loop_triangles()
            triangles += len(mesh.loop_triangles)
            evaluated.to_mesh_clear()
    REPORT.append({'asset':kind+suffix, 'triangles':triangles})
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'art' / (kind+suffix+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(kind+suffix+'.glb')), export_format='GLB',
                              export_apply=True, export_animations=False)

if __name__ == '__main__':
    for LOW in (False, True):
        for name in KINDS:
            export(name)
    (ROOT / 'art' / 'manifest.json').write_text(json.dumps({
        'blender': bpy.app.version_string, 'assets': REPORT,
        'coordinates': 'GLB: Y up, +Z forward; metres',
        'generator': 'tools/create_industrial_assets.py'}, indent=2)+'\n')
    print(f'DIGITAL AGE: {len(REPORT)} Blender sources and glTF exports created.')
