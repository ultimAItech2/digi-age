"""Render every sprite frame of the requested kinds (tools/sprites).

    blender -b -noaudio --factory-startup --python-exit-code 1 \
        --python tools/sprites/render.py -- [--kinds core,worker] [--samples 192] [--still] [--out DIR]

Frames go to builds/sprites/<kind>/ as <index>.png with <index>_mask.png and a
meta.json; tools/sprites/pack.py turns them into the atlases the game loads.
`--still` renders only one frame per kind (the finished building, the first
idle facing) for a quick look; give it `--out` so the frames the atlases are
packed from are left alone.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import kit      # noqa: E402
import models   # noqa: E402
import rig      # noqa: E402

OUT = kit.ROOT / 'builds' / 'sprites'
MARGIN = 4                                   # transparent pixels around every frame
STAGES = (0.14, 0.45, 0.8)                   # share of the height standing at each build stage
ANIMS = (('idle', 1, 1.0), ('move', 8, 10.0), ('attack', 6, 12.0), ('death', 6, 9.0))   # name, frames, frames per second
IDLE_FRAMES = 6                              # a finished building's loop: 'complete' is its first frame
DIRECTIONS = 8
SCALE_UP = 1.5


def args():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    out = {'kinds': list(models.BUILDERS), 'samples': 192, 'still': False, 'out': None}
    i = 0
    while i < len(argv):
        if argv[i] == '--kinds':
            out['kinds'] = argv[i + 1].split(',')
            i += 1
        elif argv[i] == '--samples':
            out['samples'] = int(argv[i + 1])
            i += 1
        elif argv[i] == '--out':
            out['out'] = argv[i + 1]
            i += 1
        elif argv[i] == '--still':
            out['still'] = True
        i += 1
    return out


def z_range(obj):
    zs = [(obj.matrix_world @ Vector(c)).z for c in obj.bound_box]
    return min(zs), max(zs)


def frames_for(kind, info):
    """[(label, apply)] where apply() puts the scene in that frame's state."""
    objs = rig.model_objects()
    bpy.context.view_layer.update()
    if info['group'] == 'buildings':
        lows = {o.name: z_range(o)[0] for o in objs}
        height = max(z_range(o)[1] for o in objs if not o.get('scaffold') and not o.get('rubble'))

        animate = info.get('animate')

        def state(label):
            def apply():
                for o in objs:
                    scaffold, wreck, base = o.get('scaffold'), o.get('rubble'), o.get('base')
                    if label == 'complete' or label.startswith('idle'):
                        o.hide_render = bool(scaffold or wreck)
                    elif label == 'wreck':
                        o.hide_render = not (wreck or base)
                    else:
                        limit = height * STAGES[int(label[-1])]
                        o.hide_render = bool(wreck) or (not scaffold and not base and lows[o.name] > limit)
                if animate:
                    # Stages and the wreck stand still at the loop's first frame.
                    animate(int(label[4:]) / IDLE_FRAMES if label.startswith('idle') else 0.0)
            return apply
        loop = ['idle%d' % i for i in range(1, IDLE_FRAMES)] if animate else []
        return [(label, state(label)) for label in ['stage0', 'stage1', 'stage2', 'complete'] + loop + ['wreck']]
    if info['group'] == 'scenery':
        def only(variant):
            def apply():
                for o in objs:
                    o.hide_render = o.get('variant', 0) != variant
            return apply
        return [('v%d' % v, only(v)) for v in range(info['variants'])]
    if info['group'] == 'props':
        def level(share):
            def apply():
                for o in objs:
                    o.hide_render = o.get('rank', 0.0) >= share
            return apply
        return [('full', level(1.01)), ('half', level(0.6)), ('low', level(0.28))]
    out = []
    root, pose = info['root'], info['pose']

    def unit(direction, anim, t):
        def apply():
            # Facing index d looks along the game direction (cos, sin)(d * 45 deg); cell y is Blender -Y.
            root.rotation_euler.z = -direction * math.tau / DIRECTIONS
            flash = pose(anim, t)
            for o in objs:
                o.hide_render = bool(o.get('flash')) and not flash
        return apply
    for direction in range(DIRECTIONS):
        for anim, count, _fps in ANIMS:
            for f in range(count):
                out.append(('%d_%s_%d' % (direction, anim, f), unit(direction, anim, f / count)))
    return out


def render_kind(kind, still, out=OUT):
    rig.clear_model()
    info = models.build(kind)
    if info['group'] in ('units', 'props'):
        # Units and deposits are drawn larger than life, as the genre does, so they read at a glance.
        for obj in [o for o in bpy.context.scene.objects if o.parent is None and not o.get('stage') and o.type in ('MESH', 'EMPTY')]:
            obj.scale = obj.scale * SCALE_UP
            obj.location = obj.location * SCALE_UP
    frames = frames_for(kind, info)
    # One window for every frame of the kind, so the anchor never moves.
    x0 = y0 = 1e9
    x1 = y1 = -1e9
    for _label, apply in frames:
        apply()
        bx0, bx1, by0, by1 = rig.bounds()
        x0, x1, y0, y1 = min(x0, bx0), max(x1, bx1), min(y0, by0), max(y1, by1)
    if info['group'] == 'buildings':
        # The footprint's near corner sits half a diagonal toward the camera.
        y0 = min(y0, -info['cells'] * math.sqrt(2.0) * 0.5 * math.sin(rig.ELEVATION))
    half = max(abs(x0), abs(x1))
    width = 2 * (math.ceil(half * rig.PPU) + MARGIN)
    below = math.ceil(-y0 * rig.PPU) + MARGIN
    above = math.ceil(y1 * rig.PPU) + MARGIN
    height = below + above
    centre_y = (above - below) * 0.5 / rig.PPU
    folder = out / kind
    folder.mkdir(parents=True, exist_ok=True)
    for stale in folder.glob('*.png'):
        stale.unlink()
    labels = []
    for index, (label, apply) in enumerate(frames):
        labels.append(label)
        if still and label not in ('complete', 'full', '0_idle_0', '1_idle_0', 'v0'):
            continue
        apply()
        rig.render(folder / ('%03d.png' % index), folder / ('%03d_mask.png' % index), width, height, 0.0, centre_y)
    meta = {
        'kind': kind, 'group': info['group'], 'cells': info['cells'], 'large': bool(info.get('large')),
        'ppu': rig.PPU, 'frame': [width, height], 'anchor': below, 'labels': labels,
        'anims': {name: {'frames': count, 'fps': fps} for name, count, fps in ANIMS} if info['group'] == 'units' else {},
        'directions': DIRECTIONS if info['group'] == 'units' else 1,
    }
    (folder / 'meta.json').write_text(json.dumps(meta, indent=1))
    print('SPRITE %s: %d frames of %dx%d, anchor %d' % (kind, len(frames), width, height, below))


def main():
    options = args()
    rig.reset()
    rig.setup(options['samples'])
    for kind in options['kinds']:
        render_kind(kind, options['still'], Path(options['out']) if options['out'] else OUT)


main()
