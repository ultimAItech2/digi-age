"""Render the HUD's 9-slice plates (tools/sprites).

    blender -b -noaudio --factory-startup --python-exit-code 1 --python tools/sprites/ui.py

Each plate is a machined steel tile seen from straight above on the sprite
stage: a field, a raised rim, an inner groove and, on the large ones, corner
bolts. They are written to builds/ui_plates/; tools/sprites/grade_ui.py then
grades them onto the HUD palette and saves assets/ui/frames/<name>.png.
A plate is 96 px square with 12 px margins.
"""
import sys
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import kit      # noqa: E402
import rig      # noqa: E402

OUT = kit.ROOT / 'builds' / 'ui_plates'
SIZE = 96
# name: (field colour, rim colour, rim height, bolts, recessed)
PLATES = {
    'panel': ('#27323c', '#5a6772', 0.05, True, False),
    'dock': ('#2a3640', '#66747f', 0.06, True, False),
    'button': ('#313e49', '#6b7883', 0.05, False, False),
    'button_hover': ('#42525f', '#8794a0', 0.05, False, False),
    'button_pressed': ('#262f38', '#4a5560', 0.02, False, True),
    'button_disabled': ('#20272e', '#353e46', 0.03, False, False),
    'slot': ('#1b2229', '#4e5a65', 0.05, False, True),
}


def plate(name, field, rim, height, bolts, recessed):
    rig.clear_model()
    steel = kit.surface('ui_field_' + name, tex='metal_plate', tint=field, scale=9.0, rough=0.55, metal=0.4, wear=0.2, dirt=0.5, streaks=0.0, dust=0.0, splash=0.0)
    edge = kit.surface('ui_rim_' + name, tint=rim, rough=0.4, metal=0.6, wear=0.6, dirt=0.4, streaks=0.0, dust=0.0, splash=0.0)
    dark = kit.surface('ui_groove', tint='#0c1014', rough=0.6, wear=0.0, dirt=0.0, streaks=0.0, dust=0.0, splash=0.0)
    kit.box('Field', (1.0, 1.0, 0.04), (0, 0, -0.02 if recessed else 0.02), steel)
    w = 0.055
    for x, y, sx, sy in ((0, 0.5 - w / 2, 1.0, w), (0, -0.5 + w / 2, 1.0, w), (0.5 - w / 2, 0, w, 1.0), (-0.5 + w / 2, 0, w, 1.0)):
        kit.box('Rim', (sx, sy, height), (x, y, height * 0.5 + (0.0 if recessed else 0.02)), edge)
    g = 0.5 - w - 0.012
    for x, y, sx, sy in ((0, g, 2 * g, 0.012), (0, -g, 2 * g, 0.012), (g, 0, 0.012, 2 * g), (-g, 0, 0.012, 2 * g)):
        kit.box('Groove', (sx, sy, 0.012), (x, y, 0.045 if not recessed else 0.005), dark)
    if bolts:
        for x in (-0.5 + w / 2, 0.5 - w / 2):
            for y in (-0.5 + w / 2, 0.5 - w / 2):
                kit.cyl('Bolt', 0.02, 0.03, (x, y, height + 0.03), 'chrome', verts=6)
    rig.render(OUT / (name + '.png'), OUT / (name + '_mask.png'), SIZE, SIZE, 0.0, 0.0)
    (OUT / (name + '_mask.png')).unlink()


def main():
    rig.reset()
    rig.setup(96)
    # Straight down, with screen up along +Y; the stage's sun still rakes across from the upper left.
    rig.TO_CAMERA = Vector((0, 0, 1))
    rig.RIGHT = Vector((1, 0, 0))
    rig.UP = Vector((0, 1, 0))
    rig.camera.rotation_euler = (0, 0, 0)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, spec in PLATES.items():
        plate(name, *spec)
        print('PLATE', name)


main()
