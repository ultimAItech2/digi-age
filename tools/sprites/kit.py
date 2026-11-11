"""Materials and primitives for the rendered sprite models (tools/sprites).

Everything is built in Blender units where one unit is one map cell. Blender
is Z up; the game's cell axes map to +X (cell x) and -Y (cell y).

Materials are Principled shaders over Poly Haven CC0 texture sets
(assets/third_party/polyhaven/raw, fetched by tools/fetch_cc0_assets.py),
box-projected in object space, with rounded edges and layers of use added in
the shader: chipped paint, streaks, dust, ground dirt and corner grime. The `team` surface also
writes a `team` AOV: the mask the game uses to recolour it per faction.
"""
import math
import random
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
TEXTURES = ROOT / 'assets' / 'third_party' / 'polyhaven' / 'raw'
_materials = {}
_images = {}


def srgb(value, alpha=1.0):
    """'#rrggbb' as the linear RGBA Blender's colour sockets expect."""
    value = value.lstrip('#')
    out = []
    for i in (0, 2, 4):
        c = int(value[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, alpha)


def _image(folder, kind, colour):
    for res in ('2k', '1k'):
        path = TEXTURES / folder / f'{folder}_{kind}_{res}.jpg'
        if path.exists():
            key = str(path)
            if key not in _images:
                img = bpy.data.images.load(key)
                img.colorspace_settings.name = 'sRGB' if colour else 'Non-Color'
                _images[key] = img
            return _images[key]
    return None


DUST = (0.30, 0.24, 0.16)       # what settles on things: the terrain's own colour, lighter
GRIME = (0.30, 0.25, 0.20)      # what gathers in corners
STREAK = (0.34, 0.28, 0.22)     # what runs down walls
BARE = (0.36, 0.35, 0.34)       # steel under chipped paint
RUST = (0.22, 0.10, 0.045)
splash_on = True                # ground dirt on the lowest parts; off for units, whose feet leave the ground


def surface(name, tex=None, tint='#ffffff', scale=1.0, rough=0.5, metal=0.0,
            emit=None, strength=0.0, team=False, dirt=0.55, wear=0.5, alpha=1.0,
            gray=0.0, gain=1.0, chips=0.0, streaks=0.6, dust=0.25, splash=0.5, coat=0.0):
    """A cached material. `tex` is a Poly Haven folder name or None for a flat colour.

    The scan gives colour, roughness and relief; on top of it come the layers
    that make a surface look used: paint chipped to steel and rust along edges
    (`chips`), a brighter worn edge on bare metal (`wear`), streaks down
    vertical faces, dust on upward ones, dirt near the ground (`splash`) and
    grime in corners (`dirt`). `gray` removes the scan's own hue so `tint`
    decides the colour; `gain` brightens a dark scan.
    """
    key = name if splash_on else name + '/nosplash'
    if key in _materials:
        return _materials[key]
    mat = bpy.data.materials.new(key)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes['Principled BSDF']

    def put(socket, value):
        if isinstance(value, bpy.types.NodeSocket):
            links.new(value, socket)
        elif isinstance(value, (tuple, list)):
            socket.default_value = (*value, 1.0) if len(value) == 3 else value
        else:
            socket.default_value = value

    def mix(a, b, factor, blend='MIX'):
        node = nodes.new('ShaderNodeMix')
        node.data_type = 'RGBA'
        node.blend_type = blend
        put(node.inputs[0], factor)
        put(node.inputs[6], a)
        put(node.inputs[7], b)
        return node.outputs[2]

    def blend(a, b, factor):
        node = nodes.new('ShaderNodeMix')
        node.data_type = 'FLOAT'
        put(node.inputs[0], factor)
        put(node.inputs[2], a)
        put(node.inputs[3], b)
        return node.outputs[0]

    def calc(operation, a, b=0.0, clamp=False):
        node = nodes.new('ShaderNodeMath')
        node.operation = operation
        node.use_clamp = clamp
        put(node.inputs[0], a)
        put(node.inputs[1], b)
        return node.outputs[0]

    def remap(value, from_min, from_max, to_min=0.0, to_max=1.0):
        node = nodes.new('ShaderNodeMapRange')
        put(node.inputs['Value'], value)
        node.inputs['From Min'].default_value = from_min
        node.inputs['From Max'].default_value = from_max
        node.inputs['To Min'].default_value = to_min
        node.inputs['To Max'].default_value = to_max
        return node.outputs['Result']

    coords = nodes.new('ShaderNodeTexCoord')

    def noise(size, detail=4.0, stretch=(1.0, 1.0, 1.0)):
        node = nodes.new('ShaderNodeTexNoise')
        node.inputs['Scale'].default_value = size
        node.inputs['Detail'].default_value = detail
        node.inputs['Roughness'].default_value = 0.6
        if stretch == (1.0, 1.0, 1.0):
            links.new(coords.outputs['Object'], node.inputs['Vector'])
        else:
            mapping = nodes.new('ShaderNodeMapping')
            mapping.inputs['Scale'].default_value = stretch
            links.new(coords.outputs['Object'], mapping.inputs['Vector'])
            links.new(mapping.outputs['Vector'], node.inputs['Vector'])
        return node.outputs['Fac']

    plain = emit is not None or alpha < 1.0
    base = srgb(tint)[:3]
    rough_value = rough
    metal_value = metal
    normal_socket = None
    diffuse = _image(tex, 'diffuse', True) if tex else None
    if diffuse:
        mapping = nodes.new('ShaderNodeMapping')
        mapping.inputs['Scale'].default_value = (scale, scale, scale)
        links.new(coords.outputs['Object'], mapping.inputs['Vector'])

        def sample(image):
            node = nodes.new('ShaderNodeTexImage')
            node.image = image
            node.projection = 'BOX'
            node.projection_blend = 0.25
            links.new(mapping.outputs['Vector'], node.inputs['Vector'])
            return node.outputs['Color']

        colour = sample(diffuse)
        if gray > 0.0:
            hue = nodes.new('ShaderNodeHueSaturation')
            hue.inputs['Saturation'].default_value = 1.0 - gray
            links.new(colour, hue.inputs['Color'])
            colour = hue.outputs['Color']
        tinted = tuple(c * gain for c in srgb(tint)[:3])
        base = mix(colour, tinted, 1.0, 'MULTIPLY')
        arm = _image(tex, 'arm', False)
        if arm:
            split = nodes.new('ShaderNodeSeparateColor')
            links.new(sample(arm), split.inputs['Color'])
            rough_value = calc('MULTIPLY', split.outputs['Green'], rough / 0.5, clamp=True)
        nor = _image(tex, 'nor_gl', False)
        if nor:
            normal_map = nodes.new('ShaderNodeNormalMap')
            normal_map.inputs['Strength'].default_value = 0.9
            links.new(sample(nor), normal_map.inputs['Color'])
            normal_socket = normal_map.outputs['Normal']
    elif not plain:
        # Flat colours get a fine grain so large faces are never a dead, even tone.
        grain = noise(9.0, 8.0)
        base = mix(base, remap(grain, 0.3, 0.7, 0.8, 1.1), 1.0, 'MULTIPLY')
        rough_value = remap(grain, 0.0, 1.0, max(0.04, rough - 0.12), min(1.0, rough + 0.14))
    # Rounded edges at render time, so hard boxes catch a highlight like real parts.
    bevel = nodes.new('ShaderNodeBevel')
    bevel.samples = 4
    bevel.inputs['Radius'].default_value = 0.018
    if normal_socket:
        links.new(normal_socket, bevel.inputs['Normal'])
    links.new(bevel.outputs['Normal'], bsdf.inputs['Normal'])
    covered = None      # how much of the paint is gone or buried, for the faction mask
    if not plain:
        geometry = nodes.new('ShaderNodeNewGeometry')
        facing = nodes.new('ShaderNodeSeparateXYZ')
        links.new(geometry.outputs['True Normal'], facing.inputs['Vector'])
        # Nothing weathers evenly: tone and roughness wander slowly over every surface.
        base = mix(base, remap(noise(1.3, 2.0), 0.3, 0.7, 0.72, 1.06), 1.0, 'MULTIPLY')
        rough_value = calc('ADD', rough_value, remap(noise(2.3, 3.0), 0.25, 0.75, -0.11, 0.11), clamp=True)
        # Edges: where the rounded normal leaves the true one.
        edge = None
        if chips > 0.0 or wear > 0.0:
            wide = nodes.new('ShaderNodeBevel')
            wide.samples = 4
            wide.inputs['Radius'].default_value = 0.03
            dot = nodes.new('ShaderNodeVectorMath')
            dot.operation = 'DOT_PRODUCT'
            links.new(wide.outputs['Normal'], dot.inputs[0])
            links.new(geometry.outputs['Normal'], dot.inputs[1])
            edge = remap(dot.outputs['Value'], 1.0, 0.93)
        if chips > 0.0:
            # Paint chips off along edges and in patches, down to steel that then rusts.
            threshold = 1.3 - 0.55 * chips
            chip = calc('MULTIPLY', calc('SUBTRACT', calc('ADD', calc('MULTIPLY', edge, 1.5), noise(6.5, 6.0)), threshold), 8.0, clamp=True)
            rusted = remap(noise(4.0, 5.0), 0.45, 0.62)
            base = mix(base, mix(BARE, RUST, rusted), chip)
            rough_value = blend(rough_value, blend(0.38, 0.82, rusted), chip)
            metal_value = blend(metal_value, blend(1.0, 0.1, rusted), chip)
            covered = chip
        elif wear > 0.0:
            base = mix(base, (0.55, 0.57, 0.6), calc('MULTIPLY', edge, wear))
        if streaks > 0.0:
            # Rain carries dirt down vertical faces.
            upright = remap(calc('ABSOLUTE', facing.outputs['Z']), 0.15, 0.6, 1.0, 0.0)
            run = calc('MULTIPLY', calc('MULTIPLY', remap(noise(1.0, 3.0, (9.0, 9.0, 0.7)), 0.45, 0.72), upright), streaks)
            base = mix(base, STREAK, run, 'MULTIPLY')
            rough_value = calc('ADD', rough_value, calc('MULTIPLY', run, 0.3), clamp=True)
        settle = []
        if dust > 0.0:
            # Dust settles on whatever faces the sky.
            up = calc('POWER', remap(facing.outputs['Z'], 0.0, 1.0), 3.0)
            settle.append(calc('MULTIPLY', calc('MULTIPLY', up, remap(noise(5.0, 5.0), 0.3, 0.7, 0.3, 1.0)), dust))
        if splash > 0.0 and splash_on:
            # Rain throws the ground up the lowest part of everything.
            place = nodes.new('ShaderNodeSeparateXYZ')
            links.new(geometry.outputs['Position'], place.inputs['Vector'])
            low = remap(place.outputs['Z'], 0.04, 0.38, 1.0, 0.0)
            settle.append(calc('MULTIPLY', calc('MULTIPLY', low, remap(noise(8.0, 5.0), 0.3, 0.7, 0.25, 1.0)), splash))
        for amount in settle:
            base = mix(base, DUST, amount)
            rough_value = blend(rough_value, 0.92, amount)
            metal_value = blend(metal_value, 0.0, amount)
            covered = amount if covered is None else calc('MAXIMUM', covered, amount)
        if dirt > 0.0:
            # Grime gathers in corners.
            ao = nodes.new('ShaderNodeAmbientOcclusion')
            ao.samples = 6
            ao.inputs['Distance'].default_value = 0.45
            base = mix(base, mix(GRIME, (1.0, 1.0, 1.0), ao.outputs['AO']), dirt, 'MULTIPLY')
    put(bsdf.inputs['Base Color'], base)
    put(bsdf.inputs['Roughness'], rough_value)
    put(bsdf.inputs['Metallic'], metal_value)
    if coat > 0.0:
        bsdf.inputs['Coat Weight'].default_value = coat
        bsdf.inputs['Coat Roughness'].default_value = 0.05
    if emit:
        bsdf.inputs['Emission Color'].default_value = srgb(emit)
        bsdf.inputs['Emission Strength'].default_value = strength
    if alpha < 1.0:
        bsdf.inputs['Alpha'].default_value = alpha
    if team:
        # The mask is the paint that is still there: chips and dirt keep their own colour in the game.
        aov = nodes.new('ShaderNodeOutputAOV')
        aov.aov_name = 'team'
        put(aov.inputs['Value'], 1.0 if covered is None else calc('SUBTRACT', 1.0, covered, clamp=True))
    _materials[key] = mat
    return mat


def M(name):
    """The shared palette of surfaces every model draws from."""
    table = {
        'hull': dict(tex='metal_plate_02', gray=0.85, tint='#b4bcc4', gain=4.2, scale=1.1, rough=0.45, metal=0.55, chips=0.25),
        'hull_dark': dict(tex='rusty_metal_sheet', gray=0.75, tint='#6a737c', gain=1.0, scale=1.3, rough=0.5, metal=0.6, chips=0.2),
        'hull_light': dict(tex='rusty_metal_02', gray=0.55, tint='#e3e7ea', gain=1.25, scale=0.9, rough=0.42, metal=0.1, chips=0.45),
        'plate': dict(tex='metal_plate', gray=0.6, tint='#c9d0d6', gain=2.2, scale=3.2, rough=0.5, metal=0.7),
        'paint': dict(tex='painted_metal_shutter', tint='#c9ced2', scale=0.7, rough=0.55, chips=0.5),
        'paint_dark': dict(tex='painted_metal_shutter', tint='#59626b', scale=0.7, rough=0.6, chips=0.5),
        'paint_olive': dict(tex='painted_metal_shutter', tint='#8d9079', scale=0.7, rough=0.6, chips=0.6),
        'corrugated': dict(tex='corrugated_iron', tint='#d3d9de', scale=0.6, rough=0.5, metal=0.5, streaks=0.8),
        'rust': dict(tex='rusty_metal_04', tint='#d8c8b8', gain=1.6, scale=0.8, rough=0.75, metal=0.6, wear=0.15),
        'concrete': dict(tex='concrete_wall_006', tint='#aeaca6', scale=0.45, rough=0.8, wear=0.0, streaks=0.7, dust=0.3),
        'concrete_dark': dict(tex='cracked_concrete_wall', tint='#8e8c86', scale=0.35, rough=0.85, wear=0.0, streaks=0.7, dust=0.3),
        'rubber': dict(tex='rubberized_track', gray=1.0, tint='#4a4c50', gain=0.9, scale=1.5, rough=0.85, wear=0.0, dust=0.6),
        'asphalt': dict(tex='asphalt_02', tint='#8a8a88', scale=0.4, rough=0.9, wear=0.0),
        'gravel': dict(tex='gravel_ground_01', tint='#b9a98c', scale=0.5, rough=0.95, wear=0.0, streaks=0.0, dust=0.0, splash=0.0, dirt=0.35),
        'team': dict(tex='painted_metal_shutter', gray=1.0, tint='#c6c9cc', scale=0.7, rough=0.5, team=True, chips=0.55, dirt=0.4, streaks=0.35, dust=0.25),
        'armor': dict(tint='#7c8478', rough=0.5, metal=0.15, chips=0.4, dust=0.12, streaks=0.4),
        'armor_dark': dict(tint='#40464b', rough=0.5, metal=0.3, chips=0.35, dust=0.12, streaks=0.3),
        'armor_light': dict(tint='#b4babd', rough=0.45, metal=0.1, chips=0.4, dust=0.12, streaks=0.4),
        'team_coat': dict(tint='#c6c9cc', rough=0.45, team=True, chips=0.35, dirt=0.4, streaks=0.3, dust=0.1),
        'black': dict(tex='rusty_metal_sheet', gray=1.0, tint='#3a3d42', gain=0.75, scale=1.6, rough=0.45, metal=0.7, wear=0.35),
        'chrome': dict(tint='#d8dde2', rough=0.16, metal=1.0, wear=0.0, dirt=0.3, streaks=0.15, dust=0.15),
        'copper': dict(tex='metal_plate_02', gray=1.0, tint='#d99a62', gain=4.5, scale=1.4, rough=0.38, metal=1.0, wear=0.2),
        'gold': dict(tex='metal_plate_02', gray=1.0, tint='#e8bc55', gain=4.5, scale=1.4, rough=0.32, metal=1.0, wear=0.2),
        'hazard': dict(tex='rusty_painted_metal', gray=1.0, tint='#f0b020', gain=2.6, scale=1.2, rough=0.55, chips=0.7),
        'glass': dict(tint='#0a1722', rough=0.1, metal=0.0, coat=0.5, wear=0.0, dirt=0.25, streaks=0.2, dust=0.3, splash=0.0),
        'glow_cyan': dict(tint='#7fe9ff', emit='#10c4ff', strength=2.0, wear=0.0, dirt=0.0),
        'glow_violet': dict(tint='#d3b4ff', emit='#8a4dff', strength=2.6, wear=0.0, dirt=0.0),
        'glow_amber': dict(tint='#ffd08a', emit='#ff9214', strength=2.4, wear=0.0, dirt=0.0),
        'glow_red': dict(tint='#ff9a8a', emit='#ff3018', strength=2.8, wear=0.0, dirt=0.0),
        'glow_white': dict(tint='#ffffff', emit='#eaf6ff', strength=2.0, wear=0.0, dirt=0.0),
        'lamp_dim': dict(tint='#d9b877', emit='#ffa040', strength=1.0, wear=0.0, dirt=0.0),
        'scrap': dict(tex='rusty_metal_04', tint='#e8cfa4', gain=2.6, scale=1.2, rough=0.65, metal=0.8, wear=0.5),
        'wood': dict(tex='wood_planks_grey', tint='#c8ad88', gain=2.4, scale=1.4, rough=0.85, wear=0.0, dust=0.5),
    }
    return surface(name, **table[name])


# ---- primitives ---------------------------------------------------------------

def _finish(obj, name, mat, parent, tags):
    obj.name = name
    if mat is not None:
        obj.data.materials.append(M(mat) if isinstance(mat, str) else mat)
    if parent is not None:
        obj.parent = parent
    for tag in tags:
        obj[tag] = True
    return obj


def empty(name, loc=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = loc
    if parent is not None:
        obj.parent = parent
    return obj


panel_size = 0.5        # how large one sheet of cladding is; models.build() sets it per family


def _plain(mat):
    """Surfaces that are light or loose material, not sheet: no joints or seams."""
    return not isinstance(mat, str) or mat.startswith(('glow', 'lamp')) or mat in ('gravel', 'scrap', 'wood', 'rubber')


def _panelise(obj, size):
    """Cut a box into sheets with a raised joint between them, so a wall is built of parts, not one slab."""
    step = panel_size
    if sorted(size)[1] < step * 0.8:
        return
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for axis in range(3):
        count = int(round(size[axis] / step))
        for i in range(1, count):
            co, no = Vector(), Vector()
            co[axis] = -size[axis] * 0.5 + size[axis] * i / count
            no[axis] = 1.0
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no)
    joint = min(step * 0.028, min(size) * 0.2)
    faces = [f for f in bm.faces if f.calc_area() > (step * 0.4) ** 2]
    if faces:
        bmesh.ops.inset_individual(bm, faces=faces, thickness=joint, depth=-joint * 0.8, use_even_offset=True)
    bm.to_mesh(obj.data)
    bm.free()


def box(name, size, loc, mat, rot=(0, 0, 0), parent=None, tags=(), panel=None):
    """A box `size` (x, y, z) centred on `loc`. Large ones are clad in panels unless `panel` is False."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if panel is None:
        panel = not _plain(mat) and not tags
    if panel:
        _panelise(obj, size)
    return _finish(obj, name, mat, parent, tags)


def shell(name, size, loc, mat, taper=(1.0, 1.0), shift=(0.0, 0.0), round=0.02, rot=(0, 0, 0), parent=None, tags=(), panel=None):
    """A pressed or cast part: a box whose top is `taper` times its base (and moved by `shift`),
    with every edge rounded to `round`. What armour, cabs and housings are made of."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for v in obj.data.vertices:
        if v.co.z > 0:
            v.co.x = v.co.x * taper[0] + shift[0]
            v.co.y = v.co.y * taper[1] + shift[1]
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    width = min(round, min(size) * 0.45)
    if width > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=width, segments=3, profile=0.5, affect='EDGES', clamp_overlap=True)
    bm.to_mesh(obj.data)
    bm.free()
    if panel is None:
        panel = not _plain(mat) and not tags
    if panel:
        _panelise(obj, size)
    bpy.ops.object.shade_auto_smooth(angle=math.radians(35))
    return _finish(obj, name, mat, parent, tags)


def strut(name, a, b, width, depth, mat, taper=0.8, round=0.012, parent=None, tags=()):
    """A limb from a to b: `width` along the swing plane, `depth` across it, narrowing toward b."""
    a, b = Vector(a), Vector(b)
    delta = b - a
    obj = shell(name, (width, depth, delta.length), (a + b) * 0.5, None, taper=(taper, taper), round=round, panel=False)
    z = delta.normalized()
    y = Vector((0.0, 1.0, 0.0))
    y = (y - z * y.dot(z)).normalized()
    x = y.cross(z)
    obj.rotation_euler = Matrix((x, y, z)).transposed().to_euler()
    return _finish(obj, name, mat, parent, tags)


def cyl(name, radius, height, loc, mat, rot=(0, 0, 0), verts=40, top=None, parent=None, tags=()):
    """A cylinder (or a cone frustum when `top` is the upper radius) centred on `loc`."""
    if top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=height, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=top, depth=height, location=loc, rotation=rot)
    obj = bpy.context.object
    if verts >= 12:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    obj = _finish(obj, name, mat, parent, tags)
    # Tall upright drums are rolled from courses of plate: a weld seam between each.
    courses = int(height / (panel_size * 0.75))
    if top is None and courses >= 2 and radius >= panel_size * 0.5 and rot[0] == 0 and rot[1] == 0 and not _plain(mat) and not tags and mat != 'glass':
        for i in range(1, courses):
            z = loc[2] - height * 0.5 + height * i / courses
            bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius * 1.006, depth=panel_size * 0.03, location=(loc[0], loc[1], z), rotation=rot)
            _finish(bpy.context.object, name + 'Seam', 'black', parent, tags)
    return obj


def ball(name, radius, loc, mat, scale=(1, 1, 1), parent=None, tags=()):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=20, radius=radius, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    return _finish(obj, name, mat, parent, tags)


def ring(name, radius, tube, loc, mat, rot=(0, 0, 0), parent=None, tags=()):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=tube, major_segments=56, minor_segments=14, location=loc, rotation=rot)
    obj = bpy.context.object
    bpy.ops.object.shade_smooth()
    return _finish(obj, name, mat, parent, tags)


def wedge(name, size, loc, mat, rot=(0, 0, 0), parent=None, tags=()):
    """A box whose top slopes down to nothing along +X: ramps, prows, armour slopes."""
    obj = box(name, size, loc, None, rot, None, (), panel=False)
    for v in obj.data.vertices:
        if v.co.z > 0 and v.co.x > 0:
            v.co.z = -size[2] * 0.5
    obj.data.update()
    return _finish(obj, name, mat, parent, tags)


def beam(name, a, b, thickness, mat, parent=None, tags=()):
    """A square bar from point a to point b."""
    a, b = Vector(a), Vector(b)
    delta = b - a
    obj = box(name, (thickness, thickness, delta.length), (a + b) * 0.5, None, panel=False)
    obj.rotation_euler = delta.to_track_quat('Z', 'Y').to_euler()
    return _finish(obj, name, mat, parent, tags)


def pipe(name, a, b, radius, mat, parent=None, tags=()):
    a, b = Vector(a), Vector(b)
    delta = b - a
    obj = cyl(name, radius, delta.length, (a + b) * 0.5, None, verts=16)
    obj.rotation_euler = delta.to_track_quat('Z', 'Y').to_euler()
    return _finish(obj, name, mat, parent, tags)


def apron_material(half):
    """Trodden gravel that thins out to nothing toward the edge of the footprint, so a building
    sits in the ground and is not cut out against it."""
    key = 'apron/%.2f' % half
    if key in _materials:
        return _materials[key]
    mat = surface(key, tex='gravel_ground_01', tint='#a8987c', scale=0.55, rough=0.95, wear=0.0, streaks=0.0, dust=0.0, splash=0.0, dirt=0.5)
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    coords = nodes.new('ShaderNodeTexCoord')
    split = nodes.new('ShaderNodeSeparateXYZ')
    links.new(coords.outputs['Object'], split.inputs['Vector'])

    def calc(operation, a, b=0.0):
        node = nodes.new('ShaderNodeMath')
        node.operation = operation
        for socket, value in ((node.inputs[0], a), (node.inputs[1], b)):
            if isinstance(value, bpy.types.NodeSocket):
                links.new(value, socket)
            else:
                socket.default_value = value
        return node.outputs[0]

    reach = calc('MAXIMUM', calc('ABSOLUTE', split.outputs['X']), calc('ABSOLUTE', split.outputs['Y']))
    noise = nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 2.6
    noise.inputs['Detail'].default_value = 5.0
    links.new(coords.outputs['Object'], noise.inputs['Vector'])
    ragged = calc('ADD', calc('DIVIDE', reach, half), calc('MULTIPLY', calc('SUBTRACT', noise.outputs['Fac'], 0.5), 0.3))
    fade = nodes.new('ShaderNodeMapRange')
    fade.interpolation_type = 'SMOOTHSTEP'
    fade.inputs['From Min'].default_value = 0.86
    fade.inputs['From Max'].default_value = 1.0
    fade.inputs['To Min'].default_value = 1.0
    fade.inputs['To Max'].default_value = 0.0
    links.new(ragged, fade.inputs['Value'])
    links.new(fade.outputs['Result'], nodes['Principled BSDF'].inputs['Alpha'])
    return mat


def slab(n, mat='concrete', height=0.16, inset=0.2, parent=None):
    """The ground an n-cell building stands on: worn gravel out to the footprint's edge, and on it a
    low concrete pad a little inside the footprint."""
    side = n - 2 * inset
    half = n * 0.5 + 0.08
    bpy.ops.mesh.primitive_plane_add(size=half * 2.0, location=(0, 0, 0.012))
    _finish(bpy.context.object, 'Apron', apron_material(half), parent, ('base',))
    pad = box('Foundation', (side, side, height), (0, 0, height * 0.5), mat, parent=parent, tags=('base',), panel=True)
    box('FoundationLip', (side + 0.14, side + 0.14, height * 0.45), (0, 0, height * 0.225), 'concrete_dark', parent=parent, tags=('base',))
    return pad


def scaffold(n, height, parent=None, rng=None):
    """Construction dressing shown only in the build stages: poles, decks, a crane."""
    rng = rng or random.Random(n)
    half = n * 0.5 - 0.32
    count = 3 if n <= 3 else 5
    for side in range(4):
        for i in range(count):
            t = -half + 2 * half * i / (count - 1)
            x, y = [(t, -half), (half, t), (t, half), (-half, t)][side]
            pipe('ScaffoldPole', (x, y, 0.1), (x, y, height), 0.03, 'rust', parent, ('scaffold',))
        for level in range(1, int(height / 0.9) + 1):
            z = level * 0.9
            a = [(-half, -half), (half, -half), (half, half), (-half, half)][side]
            b = [(half, -half), (half, half), (-half, half), (-half, -half)][side]
            pipe('ScaffoldRail', (*a, z), (*b, z), 0.022, 'rust', parent, ('scaffold',))
            if rng.random() < 0.7:
                mid = ((a[0] + b[0]) * 0.5 * 0.96, (a[1] + b[1]) * 0.5 * 0.96, z - 0.05)
                size = (abs(b[0] - a[0]) * 0.55 + 0.16, abs(b[1] - a[1]) * 0.55 + 0.16, 0.035)
                box('ScaffoldDeck', size, mid, 'wood', parent=parent, tags=('scaffold',))
    # A site crane on one corner.
    cx, cy = half - 0.1, half - 0.1
    top = height + 1.0
    beam('CraneMast', (cx, cy, 0.1), (cx, cy, top), 0.1, 'hazard', parent, ('scaffold',))
    beam('CraneJib', (cx + 0.5, cy + 0.5, top), (cx - n * 0.62, cy - n * 0.62, top), 0.08, 'hazard', parent, ('scaffold',))
    pipe('CraneCable', (cx - n * 0.45, cy - n * 0.45, top), (cx - n * 0.45, cy - n * 0.45, top - 0.9), 0.012, 'black', parent, ('scaffold',))
    box('CraneLoad', (0.34, 0.34, 0.22), (cx - n * 0.45, cy - n * 0.45, top - 1.0), 'hull', parent=parent, tags=('scaffold',))
    for i in range(3):
        box('SiteCrate', (0.3, 0.3, 0.26), (-half + 0.3 + i * 0.36, -half + 0.25, 0.3), 'paint_olive', rot=(0, 0, rng.uniform(-0.3, 0.3)), parent=parent, tags=('scaffold',))


def rubble(n, parent=None, rng=None):
    """What is left after a building falls: shown only in the wreck frame."""
    rng = rng or random.Random(n * 7)
    half = n * 0.5 - 0.4
    for i in range(int(16 * n)):
        r = half * math.sqrt(rng.random())
        a = rng.uniform(0, math.tau)
        s = rng.uniform(0.12, 0.5) * (1.0 if n <= 3 else 1.35)
        size = (s * rng.uniform(0.6, 1.6), s * rng.uniform(0.5, 1.2), s * rng.uniform(0.25, 0.8))
        heap = max(0.0, 1.0 - r / half) * n * 0.16
        box('Rubble', size, (r * math.cos(a), r * math.sin(a), 0.18 + heap * rng.random() + size[2] * 0.4),
            rng.choice(['concrete_dark', 'rust', 'hull_dark', 'concrete', 'black']),
            rot=(rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0, 3.14)), parent=parent, tags=('rubble',))
    for i in range(n * 2):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.2, half)
        base = Vector((r * math.cos(a), r * math.sin(a), 0.15))
        tip = base + Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), rng.uniform(0.5, 1.4)))
        beam('RubbleBeam', base, tip, 0.07, 'rust', parent, ('rubble',))
