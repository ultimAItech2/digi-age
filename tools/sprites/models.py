"""Every game kind as a Blender model (tools/sprites).

Buildings stand on an n x n cell footprint centred on the origin; units face +X
and fit inside one cell; deposits fill one cell. The camera looks from -X -Y,
so the faces toward -X (bright) and -Y carry the doors and detail.

`build(kind)` returns {'group': 'buildings' | 'units' | 'props', 'cells': n,
'pose': fn(anim, t)}; `pose` moves a unit's parts for animation `anim` at
phase t in [0, 1). Objects tagged 'scaffold', 'rubble', 'base' and 'flash' are
shown or hidden per frame by render.py.
"""
import math
import random

import bpy
from mathutils import Matrix, Vector

import kit
from kit import ROOT, ball, beam, box, cyl, empty, pipe, ring, rubble, scaffold, shell, slab, strut, wedge

TAU = math.tau


def _fan(name, loc, radius, parent=None):
    cyl(name + 'Housing', radius, 0.1, loc, 'hull_dark', verts=24, parent=parent)
    cyl(name + 'Grille', radius * 0.82, 0.11, loc, 'black', verts=24, parent=parent)
    cyl(name + 'Hub', radius * 0.22, 0.13, loc, 'chrome', verts=12, parent=parent)


def _antenna(name, loc, height, parent=None, light='glow_red'):
    x, y, z = loc
    pipe(name, (x, y, z), (x, y, z + height), 0.018, 'chrome', parent)
    ball(name + 'Light', 0.04, (x, y, z + height), light, parent=parent)


def _dish(name, loc, radius, parent=None):
    x, y, z = loc
    pipe(name + 'Mast', (x, y, z), (x, y, z + radius * 0.9), 0.03, 'hull_dark', parent)
    d = cyl(name, radius, radius * 0.35, (x, y, z + radius * 1.1), 'hull_light', top=radius * 0.15, rot=(math.radians(125), 0, math.radians(-40)), parent=parent)
    return d


def _window_strip(name, size, loc, mat='glow_cyan', parent=None):
    box(name, size, loc, mat, parent=parent)


# ---- buildings ------------------------------------------------------------------

def core():
    slab(5, inset=0.25)
    box('Plinth', (4.1, 4.1, 0.34), (0, 0, 0.33), 'hull_dark')
    cyl('Tier1', 1.95, 0.5, (0, 0, 0.75), 'hull', verts=8, rot=(0, 0, TAU / 16))
    cyl('Tier1Band', 1.97, 0.12, (0, 0, 0.72), 'team', verts=8, rot=(0, 0, TAU / 16))
    cyl('Tier2', 1.45, 0.5, (0, 0, 1.25), 'hull_light', verts=8, rot=(0, 0, TAU / 16))
    cyl('Tier2Glow', 1.47, 0.06, (0, 0, 1.38), 'glow_cyan', verts=8, rot=(0, 0, TAU / 16))
    cyl('Collar', 0.95, 0.35, (0, 0, 1.65), 'hull_dark', verts=8, rot=(0, 0, TAU / 16))
    # The spire: a column of light held by four leaning pylons.
    cyl('Column', 0.3, 3.6, (0, 0, 3.5), 'glow_cyan', verts=24)
    for i in range(4):
        a = TAU / 8 + i * TAU / 4
        base = (0.82 * math.cos(a), 0.82 * math.sin(a), 1.7)
        tip = (0.3 * math.cos(a), 0.3 * math.sin(a), 5.2)
        beam('Pylon', base, tip, 0.2, 'hull_light')
        beam('PylonRib', (base[0] * 1.12, base[1] * 1.12, 1.7), (tip[0] * 1.5, tip[1] * 1.5, 4.2), 0.08, 'hull_dark')
        # Buttresses out to the plinth corners, each with a faction plate.
        corner = (1.75 * math.cos(a), 1.75 * math.sin(a))
        beam('Buttress', (corner[0], corner[1], 0.45), (0.9 * math.cos(a), 0.9 * math.sin(a), 2.5), 0.24, 'hull')
        box('ButtressFoot', (0.62, 0.62, 0.5), (corner[0], corner[1], 0.7), 'hull_dark', rot=(0, 0, a))
        box('ButtressPlate', (0.66, 0.5, 0.12), (corner[0], corner[1], 0.99), 'team', rot=(0, 0, a))
        ball('ButtressLamp', 0.07, (corner[0], corner[1], 1.1), 'glow_cyan')
    halo1 = ring('Halo1', 0.72, 0.045, (0, 0, 3.0), 'chrome')
    halo2 = ring('Halo2', 0.6, 0.04, (0, 0, 4.0), 'chrome')
    halo3 = ring('Halo3', 0.95, 0.03, (0, 0, 3.5), 'glow_cyan', rot=(math.radians(18), math.radians(10), 0))
    pulse = ring('Pulse', 0.5, 0.05, (0, 0, 2.0), 'glow_white')
    cyl('Crown', 0.36, 0.3, (0, 0, 5.3), 'hull_dark', verts=8)
    cyl('Tip', 0.2, 0.9, (0, 0, 5.9), 'glow_cyan', top=0.0, verts=8)
    # Gate on the -Y face with a ramp, and a service block on the -X face.
    box('GateFrame', (1.3, 0.3, 0.8), (0, -1.95, 0.9), 'hull_dark')
    box('GateGlow', (0.9, 0.06, 0.55), (0, -2.11, 0.83), 'glow_cyan')
    wedge('Ramp', (0.5, 1.2, 0.34), (0, -2.25, 0.33), 'concrete_dark', rot=(0, 0, -TAU / 4))
    box('Service', (0.4, 1.5, 0.6), (-2.0, 0.2, 0.8), 'paint_dark')
    for i in range(3):
        _window_strip('ServiceLight', (0.03, 0.3, 0.1), (-2.21, -0.25 + i * 0.45, 0.9), 'glow_amber')
    _dish('Dish', (-1.5, -1.6, 0.5), 0.34)
    _antenna('Mast', (1.6, -1.5, 0.5), 1.3)
    scaffold(5, 3.4)
    rubble(5)

    def animate(t):
        # A ring of light climbs the column while the halos drift and the tilted one precesses.
        pulse.location.z = 1.9 + 3.2 * t
        pulse.scale = (1.0 - 0.45 * t,) * 3
        halo1.location.z = 3.0 + 0.12 * math.sin(t * TAU)
        halo2.location.z = 4.0 - 0.12 * math.sin(t * TAU)
        halo3.rotation_euler = (math.radians(18), math.radians(10), t * TAU)
    return {'group': 'buildings', 'cells': 5, 'animate': animate}


def generator():
    slab(3)
    cyl('Base', 0.95, 0.22, (0, 0, 0.27), 'hull_dark', verts=12)
    cyl('Vessel', 0.72, 1.05, (0, 0, 0.9), 'hull_light')
    cyl('Band', 0.735, 0.2, (0, 0, 0.62), 'team')
    ring('Coil1', 0.74, 0.05, (0, 0, 1.0), 'copper')
    ring('Coil2', 0.74, 0.05, (0, 0, 1.18), 'copper')
    cyl('Shoulder', 0.72, 0.22, (0, 0, 1.53), 'hull_dark', top=0.46)
    cyl('Throat', 0.44, 0.12, (0, 0, 1.68), 'hull')
    plasma = cyl('Plasma', 0.36, 0.1, (0, 0, 1.74), 'glow_cyan')
    rotor = empty('Rotor', (0, 0, 1.86))
    for i in range(3):
        box('RotorBlade', (0.74, 0.07, 0.02), (0, 0, 0), 'hull_dark', rot=(0.2, 0, i * TAU / 6), parent=rotor)
    cyl('RotorHub', 0.07, 0.07, (0, 0, 0), 'chrome', verts=12, parent=rotor)
    ring('ThroatRing', 0.4, 0.045, (0, 0, 1.77), 'chrome')
    for i in range(4):
        a = TAU / 8 + i * TAU / 4
        x, y = 0.98 * math.cos(a), 0.98 * math.sin(a)
        for j in range(5):
            box('Fin', (0.46, 0.035, 0.75), (x * (0.86 + j * 0.055), y * (0.86 + j * 0.055), 0.62), 'hull', rot=(0, 0, a + TAU / 4))
        pipe('Feed', (0.7 * math.cos(a), 0.7 * math.sin(a), 1.35), (x, y, 1.02), 0.045, 'copper')
    cyl('Tank', 0.24, 0.85, (-1.0, 0.25, 0.6), 'paint')
    cyl('TankCap', 0.25, 0.08, (-1.0, 0.25, 1.04), 'hull_dark')
    cyl('TankBand', 0.25, 0.1, (-1.0, 0.25, 0.55), 'hazard')
    pipe('TankPipe', (-1.0, 0.25, 0.95), (-0.6, 0.15, 0.95), 0.04, 'chrome')
    box('Cabin', (0.55, 0.5, 0.44), (0.1, -1.0, 0.39), 'paint_dark')
    box('CabinRoof', (0.6, 0.55, 0.05), (0.1, -1.0, 0.63), 'hull_dark')
    box('CabinWindow', (0.3, 0.03, 0.14), (0.1, -1.26, 0.45), 'glow_amber')
    box('CabinPlate', (0.03, 0.34, 0.2), (-0.185, -1.0, 0.4), 'team')
    _antenna('Mast', (0.3, -0.85, 0.65), 0.6, light='glow_amber')
    scaffold(3, 1.6)
    rubble(3)

    def animate(t):
        rotor.rotation_euler.z = t * TAU / 3.0          # three blades: a third of a turn is one loop
        plasma.scale = (1.0 + 0.08 * math.sin(t * TAU), 1.0 + 0.08 * math.sin(t * TAU), 1.0 + 1.5 * (0.5 + 0.5 * math.sin(t * TAU)))
    return {'group': 'buildings', 'cells': 3, 'animate': animate}


def depot():
    rng = random.Random(11)
    slab(3)
    box('Hall', (1.5, 1.9, 0.75), (0.35, 0.15, 0.53), 'corrugated')
    box('RoofL', (0.86, 2.0, 0.06), (0.0, 0.15, 1.02), 'paint_dark', rot=(0, math.radians(-16), 0))
    box('RoofR', (0.86, 2.0, 0.06), (0.72, 0.15, 1.02), 'paint_dark', rot=(0, math.radians(16), 0))
    box('Ridge', (0.1, 2.02, 0.07), (0.36, 0.15, 1.15), 'hull_dark')
    box('Gable', (1.5, 0.05, 0.2), (0.35, -0.8, 0.98), 'corrugated')
    box('DoorFrame', (0.06, 0.95, 0.62), (-0.42, 0.0, 0.47), 'hazard')
    box('DoorDark', (0.05, 0.8, 0.52), (-0.44, 0.0, 0.43), 'black')
    box('DoorShutter', (0.04, 0.8, 0.2), (-0.45, 0.0, 0.6), 'hull')
    box('TeamSign', (0.04, 0.5, 0.22), (-0.42, -0.6 - 0.2, 0.82), 'team')
    box('Dock', (0.7, 1.7, 0.16), (-0.85, 0.1, 0.24), 'concrete_dark')
    for i in range(3):
        box('Bollard', (0.06, 0.06, 0.2), (-1.17, -0.6 + i * 0.7, 0.42), 'hazard')
    # Stacked containers, one in the faction colour.
    box('ContainerA', (0.9, 0.42, 0.4), (0.3, -1.0, 0.36), 'team')
    box('ContainerB', (0.9, 0.42, 0.4), (0.38, -1.02, 0.77), 'paint_olive', rot=(0, 0, 0.08))
    box('ContainerC', (0.42, 0.8, 0.4), (-0.85, -0.85, 0.52), 'rust', rot=(0, 0, -0.1))
    # A loader crane over the dock.
    beam('CraneMast', (-0.95, 0.95, 0.3), (-0.95, 0.95, 1.45), 0.09, 'hazard')
    jib = empty('JibPivot', (-0.95, 0.95, 1.42))
    beam('CraneJib', (0, 0.15, 0), (0, -1.25, 0), 0.07, 'hazard', parent=jib)
    hoist = empty('Hoist', (0, -1.1, 0), jib)
    pipe('CraneCable', (0, 0, -0.02), (0, 0, -0.57), 0.012, 'black', parent=hoist)
    box('CraneHook', (0.16, 0.16, 0.1), (0, 0, -0.62), 'hull_dark', parent=hoist)
    box('CraneLoad', (0.22, 0.22, 0.16), (0, 0, -0.75), 'scrap', parent=hoist)
    for i in range(9):
        s = rng.uniform(0.08, 0.2)
        box('Scrap', (s * 1.5, s, s * 0.7), (-0.9 + rng.uniform(-0.2, 0.2), 0.35 + rng.uniform(-0.25, 0.25), 0.36 + rng.random() * 0.12), rng.choice(['scrap', 'rust', 'hull']), rot=(rng.random(), rng.random(), rng.random() * 3))
    _fan('Vent', (0.7, 0.6, 1.1), 0.16)
    box('Lamp', (0.05, 0.3, 0.05), (-0.43, 0.0, 0.84), 'glow_white')
    scaffold(3, 1.3)
    rubble(3)

    def animate(t):
        jib.rotation_euler.z = 0.35 * math.sin(t * TAU)
        hoist.location.z = -0.12 * (0.5 - 0.5 * math.cos(t * TAU))
    return {'group': 'buildings', 'cells': 3, 'animate': animate}


def data_center():
    slab(3)
    lines = []
    for i, x in enumerate((-0.72, 0.0, 0.72)):
        h = 1.25 + (0.25 if i == 1 else 0.0)
        box('Hall', (0.56, 2.0, h), (x, 0.1, 0.16 + h * 0.5), 'glass' if i != 1 else 'hull_dark')
        box('HallCap', (0.62, 2.06, 0.06), (x, 0.1, 0.19 + h), 'hull')
        for j in range(6):
            lines.append((i + j, box('DataLine', (0.5, 0.025, 0.035), (x, -0.91, 0.36 + j * (h - 0.3) / 5.5), 'glow_violet')))
        for j in range(7):
            box('SideLine', (0.02, 0.05, h - 0.3) if i == 0 else (0.0, 0.0, 0.0), (x - 0.285, -0.75 + j * 0.28, 0.2 + h * 0.5), 'glow_violet') if i == 0 else None
        for j in range(3):
            box('Cooler', (0.4, 0.4, 0.14), (x, -0.5 + j * 0.62, 0.29 + h), 'paint')
            _fan('CoolerFan', (x, -0.5 + j * 0.62, 0.36 + h), 0.14)
    box('Trunk', (2.0, 0.16, 0.12), (0, -0.98, 0.26), 'hull_dark')
    box('TrunkPlate', (0.7, 0.03, 0.16), (0, -1.07, 0.28), 'team')
    box('Kiosk', (0.34, 0.3, 0.5), (-1.02, -0.98, 0.41), 'paint_dark')
    box('KioskScreen', (0.03, 0.2, 0.16), (-1.2, -0.98, 0.5), 'glow_violet')
    box('TeamBanner', (0.03, 0.9, 0.3), (-1.01, 0.2, 1.1), 'team')
    _dish('Dish', (0.0, 0.7, 1.72), 0.3)
    _antenna('Mast', (0.72, -0.8, 1.45), 0.7, light='glow_violet')
    scaffold(3, 1.7)
    rubble(3)

    def animate(t):
        # The light lines chase up the racks: every third one is dark, and the gap climbs.
        step = int(t * 6) % 3
        for order, line in lines:
            if (order + step) % 3 == 0:
                line.hide_render = True
    return {'group': 'buildings', 'cells': 3, 'animate': animate}


def fabricator():
    slab(5, inset=0.25)
    box('Hall', (3.4, 3.0, 1.35), (0.3, 0.35, 0.83), 'paint')
    roof = cyl('Roof', 1.5, 3.4, (0.3, 0.35, 1.5), 'corrugated', rot=(0, TAU / 4, 0), verts=48)
    roof.scale = (1, 1, 0.42)
    for i in range(5):
        r = ring('RoofRib', 1.52, 0.04, (-1.3 + i * 0.8, 0.35, 1.5), 'hull_dark', rot=(0, TAU / 4, 0))
        r.scale = (1, 1, 0.43)
    box('EndWall', (0.08, 3.0, 0.5), (-1.42, 0.35, 1.6), 'paint')
    # The assembly door on the -X face, half raised, with the furnace light inside.
    box('DoorFrame', (0.1, 2.0, 1.2), (-1.44, 0.35, 0.78), 'hazard')
    box('DoorDark', (0.08, 1.76, 1.02), (-1.47, 0.35, 0.7), 'black')
    furnace = box('DoorGlow', (0.04, 1.5, 0.3), (-1.46, 0.35, 0.36), 'glow_amber')
    box('Shutter', (0.07, 1.76, 0.42), (-1.5, 0.35, 1.0), 'hull')
    for i in range(4):
        box('ShutterRib', (0.09, 1.78, 0.03), (-1.51, 0.35, 0.84 + i * 0.1), 'hull_dark')
    box('Apron', (1.0, 2.4, 0.08), (-1.95, 0.35, 0.2), 'asphalt')
    for i in range(2):
        box('TeamPanel', (0.06, 0.34, 0.9), (-1.43, 0.35 + (-1.25 if i == 0 else 1.25), 0.9), 'team')
    # Annex with the control room on the -Y side.
    box('Annex', (2.2, 0.8, 0.9), (0.2, -1.5, 0.61), 'paint_dark')
    box('AnnexRoof', (2.3, 0.9, 0.06), (0.2, -1.5, 1.09), 'hull_dark')
    for i in range(5):
        box('AnnexWindow', (0.26, 0.03, 0.2), (-0.6 + i * 0.4, -1.91, 0.8), 'glow_amber')
    box('AnnexDoor', (0.3, 0.04, 0.5), (0.95, -1.91, 0.45), 'hull')
    box('AnnexStripe', (2.2, 0.03, 0.1), (0.2, -1.91, 0.42), 'team')
    for i in range(3):
        _fan('RoofFan', (-0.6 + i * 0.8, -1.5, 1.16), 0.2)
    # Stacks.
    for i, (x, y, h) in enumerate(((1.55, -1.45, 2.6), (1.55, -0.85, 2.2))):
        cyl('Stack', 0.2, h, (x, y, 0.16 + h * 0.5), 'rust', top=0.15)
        ring('StackRing', 0.19, 0.03, (x, y, h * 0.7), 'hull_dark')
        cyl('StackLip', 0.19, 0.08, (x, y, 0.16 + h), 'black')
        cyl('StackBand', 0.2, 0.14, (x, y, h * 0.5), 'hazard')
    # Gantry over the apron.
    for y in (-0.75, 1.45):
        beam('GantryLeg', (-2.25, y, 0.16), (-2.25, y, 1.75), 0.1, 'hazard')
    beam('GantryBeam', (-2.25, -0.85, 1.75), (-2.25, 1.55, 1.75), 0.12, 'hazard')
    trolley = empty('Trolley', (-2.25, 0.5, 0.0))
    box('GantryTrolley', (0.22, 0.3, 0.16), (0, 0, 1.62), 'hull_dark', parent=trolley)
    pipe('GantryCable', (0, 0, 1.55), (0, 0, 0.95), 0.014, 'black', parent=trolley)
    box('GantryLoad', (0.5, 0.36, 0.26), (0, 0, 0.82), 'hull', parent=trolley)
    pipe('Duct', (1.1, 1.9, 0.5), (-1.0, 1.9, 0.5), 0.12, 'chrome')
    _antenna('Mast', (1.3, 1.5, 1.3), 1.0)
    scaffold(5, 2.2)
    rubble(5)

    def animate(t):
        trolley.location.y = 0.35 + 0.75 * math.sin(t * TAU)
        furnace.scale = (1.0, 1.0, 1.0 + 0.9 * (0.5 + 0.5 * math.sin(t * TAU * 2)))
    return {'group': 'buildings', 'cells': 5, 'animate': animate}


def tower():
    slab(3, inset=0.45)
    cyl('Base', 0.9, 0.45, (0, 0, 0.38), 'concrete', verts=8, rot=(0, 0, TAU / 16))
    cyl('BaseBand', 0.92, 0.1, (0, 0, 0.5), 'hazard', verts=8, rot=(0, 0, TAU / 16))
    cyl('Column', 0.46, 1.5, (0, 0, 1.3), 'hull', top=0.38, verts=8, rot=(0, 0, TAU / 16))
    cyl('ColumnBand', 0.44, 0.22, (0, 0, 1.25), 'team', verts=8, rot=(0, 0, TAU / 16))
    for i in range(4):
        a = TAU / 8 + i * TAU / 4
        beam('Strut', (0.8 * math.cos(a), 0.8 * math.sin(a), 0.6), (0.36 * math.cos(a), 0.36 * math.sin(a), 1.7), 0.07, 'hull_dark')
    cyl('Deck', 0.78, 0.12, (0, 0, 2.1), 'hull_dark', verts=8, rot=(0, 0, TAU / 16))
    ring('Rail', 0.76, 0.02, (0, 0, 2.34), 'chrome')
    # The gun head, trained toward the camera's left.
    head = empty('Head', (0, 0, 2.2))
    head.rotation_euler = (0, 0, math.radians(200))
    box('Turret', (0.75, 0.6, 0.38), (0.0, 0, 0.3), 'hull_light', parent=head)
    wedge('TurretNose', (0.34, 0.6, 0.38), (0.54, 0, 0.3), 'hull_light', parent=head)
    box('TurretPlate', (0.5, 0.62, 0.1), (-0.05, 0, 0.42), 'team', parent=head)
    for y in (-0.16, 0.16):
        pipe('Barrel', (0.45, y, 0.3), (1.25, y, 0.36), 0.05, 'black', parent=head)
        cyl('Muzzle', 0.065, 0.14, (1.25, y, 0.36), 'hull_dark', rot=(0, TAU / 4 - 0.07, 0), verts=12, parent=head)
    ball('Sensor', 0.1, (-0.2, 0, 0.58), 'glow_red', parent=head)
    box('Ammo', (0.3, 0.3, 0.22), (-0.5, 0, 0.26), 'paint_olive', parent=head)
    _antenna('Mast', (-0.5, 0.45, 2.16), 0.7)
    for i in range(6):
        box('Rung', (0.05, 0.22, 0.03), (-0.47, 0, 0.7 + i * 0.22), 'chrome')
    scaffold(3, 2.2)
    rubble(3)

    def animate(t):
        head.rotation_euler.z = math.radians(200) + 0.5 * math.sin(t * TAU)     # the gun head scans
    return {'group': 'buildings', 'cells': 3, 'animate': animate}


def lab():
    slab(3)
    tubes = []
    cyl('Drum', 0.82, 0.55, (0.2, 0.2, 0.44), 'paint')
    cyl('DrumBand', 0.835, 0.14, (0.2, 0.2, 0.36), 'team')
    ball('Dome', 0.8, (0.2, 0.2, 0.7), 'hull_light', scale=(1, 1, 0.72))
    ring('DomeRing', 0.81, 0.035, (0.2, 0.2, 0.72), 'chrome')
    for i in range(6):
        a = i * TAU / 6
        b = ring('DomeRib', 0.8, 0.022, (0.2, 0.2, 0.7), 'hull_dark', rot=(TAU / 4, 0, a))
        b.scale = (1, 1, 0.72)
    cyl('Oculus', 0.2, 0.1, (0.2, 0.2, 1.28), 'hull_dark')
    cyl('OculusGlow', 0.15, 0.1, (0.2, 0.2, 1.31), 'glow_violet')
    # Sample columns on the -X side.
    for i, y in enumerate((-0.25, 0.3, 0.85)):
        cyl('TubeBase', 0.16, 0.14, (-0.95, y, 0.23), 'hull_dark')
        tubes.append((i, 0.7 + i * 0.14, cyl('Tube', 0.13, 0.7 + i * 0.14, (-0.95, y, 0.65 + i * 0.07), 'glow_violet' if i != 1 else 'glow_cyan')))
        cyl('TubeGlass', 0.135, 0.7 + i * 0.14, (-0.95, y, 0.65 + i * 0.07), 'glass', verts=8)
        cyl('TubeCap', 0.16, 0.08, (-0.95, y, 1.04 + i * 0.14), 'chrome')
        pipe('TubeFeed', (-0.95, y, 0.3), (-0.5, y * 0.6 + 0.1, 0.3), 0.035, 'copper')
    # Annex on the -Y side with the entrance.
    box('Annex', (1.1, 0.6, 0.6), (0.25, -0.95, 0.46), 'paint_dark')
    box('AnnexRoof', (1.18, 0.68, 0.05), (0.25, -0.95, 0.78), 'hull_dark')
    box('AnnexDoor', (0.3, 0.03, 0.42), (0.0, -1.26, 0.38), 'glow_cyan')
    box('AnnexWindow', (0.4, 0.03, 0.14), (0.5, -1.26, 0.56), 'glow_amber')
    box('AnnexPlate', (0.03, 0.4, 0.3), (-0.31, -0.95, 0.5), 'team')
    _dish('Dish', (0.95, -0.85, 0.8), 0.24)
    for i in range(3):
        _antenna('Array', (0.95, 0.7 + i * 0.16, 0.2), 1.1 + i * 0.25, light='glow_violet')
    scaffold(3, 1.4)
    rubble(3)

    def animate(t):
        # The sample columns fill and drain out of step with each other, behind their glass ribs.
        for i, height, tube in tubes:
            level = 0.55 + 0.45 * (0.5 + 0.5 * math.sin((t + i / 3.0) * TAU))
            tube.scale = (1.0, 1.0, level)
            tube.location.z = 0.3 + i * 0.0 + height * level * 0.5
    return {'group': 'buildings', 'cells': 3, 'animate': animate}


# ---- deposits ---------------------------------------------------------------------

def metal():
    """A salvage pile. Pieces carry `rank` in [0, 1): depletion hides the high ranks first."""
    rng = random.Random(5)
    for i in range(46):
        rank = i / 46.0
        r = 0.44 * math.sqrt(rng.random()) * (0.55 + 0.45 * rank)
        a = rng.uniform(0, TAU)
        heap = (1.0 - r / 0.46) * 0.42 * (1.0 - rank * 0.5)
        s = rng.uniform(0.09, 0.22)
        kind = rng.random()
        loc = (r * math.cos(a), r * math.sin(a), 0.05 + heap * rng.uniform(0.5, 1.0))
        rot = (rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8), rng.uniform(0, 3.1))
        mat = rng.choice(['scrap', 'scrap', 'rust', 'hull', 'gold', 'hull_dark', 'copper'])
        if kind < 0.5:
            obj = box('Scrap', (s * 1.7, s, s * 0.5), loc, mat, rot=rot)
        elif kind < 0.75:
            obj = cyl('ScrapDrum', s * 0.55, s * 1.3, loc, mat, rot=rot, verts=14)
        elif kind < 0.9:
            obj = ring('ScrapGear', s * 0.7, s * 0.2, loc, mat, rot=rot)
        else:
            obj = beam('ScrapBeam', loc, (loc[0] + rng.uniform(-0.3, 0.3), loc[1] + rng.uniform(-0.3, 0.3), loc[2] + rng.uniform(0.15, 0.4)), 0.045, 'rust')
        obj['rank'] = rank
    return {'group': 'props', 'cells': 1}


def data():
    """A buried archive: server monoliths in a broken plinth. `rank` hides them as it is harvested."""
    rng = random.Random(9)
    box('Plinth', (0.86, 0.86, 0.1), (0, 0, 0.05), 'concrete_dark', rot=(0, 0, 0.2))
    for i, (x, y, h, lean) in enumerate(((-0.05, 0.08, 0.85, 0.06), (0.22, -0.12, 0.62, -0.1), (-0.26, -0.18, 0.48, 0.12), (0.14, 0.26, 0.36, -0.05))):
        rank = i / 4.0
        rot = (lean, lean * 0.7, 0.3 + i * 0.5)
        parts = [box('Monolith', (0.2, 0.26, h), (x, y, 0.1 + h * 0.5), 'glass', rot=rot)]
        parts.append(box('MonolithCap', (0.22, 0.28, 0.03), (x - lean * 0.2, y + lean * 0.2, 0.11 + h), 'hull_dark', rot=rot))
        for j in range(int(h / 0.09)):
            parts.append(box('Line', (0.205, 0.2, 0.014), (x, y, 0.16 + j * 0.09), 'glow_violet', rot=rot))
        for p in parts:
            p['rank'] = rank
    for i in range(7):
        a = rng.uniform(0, TAU)
        r = rng.uniform(0.3, 0.45)
        box('Shard', (0.12, 0.08, 0.05), (r * math.cos(a), r * math.sin(a), 0.1), 'concrete', rot=(rng.random(), rng.random(), rng.random()))
    pipe('Cable', (-0.4, 0.3, 0.06), (0.0, 0.1, 0.12), 0.018, 'black')
    return {'group': 'props', 'cells': 1}


# ---- units ------------------------------------------------------------------------
# Built from rounded, tapered shells (kit.shell), limbs (kit.strut), drums and
# spheres, never from bare boxes: cast armour, pressed housings, turned joints.

def _flash(parent, loc, size=0.1):
    star = ball('Flash', size, loc, 'glow_amber', scale=(2.2, 0.8, 0.8), parent=parent, tags=('flash',))
    ball('FlashCore', size * 0.9, loc, 'glow_white', scale=(1.0, 1.3, 1.3), parent=parent, tags=('flash',))
    return star


def _axle(name, radius, width, loc, mat, parent=None, verts=20):
    """A drum lying across the unit (its axis along Y): wheels, hubs, hinge pins."""
    return cyl(name, radius, width, loc, mat, rot=(TAU / 4, 0, 0), verts=verts, parent=parent)


def _along(name, radius, length, loc, mat, parent=None, top=None, pitch=0.0, verts=20):
    """A drum lying along the unit (its axis along X), nose up by `pitch`."""
    return cyl(name, radius, length, loc, mat, rot=(0, TAU / 4 - pitch, 0), verts=verts, top=top, parent=parent)


def _tyre(loc, radius, width, parent):
    ring('Tyre', radius - width * 0.5, width * 0.5, loc, 'rubber', rot=(TAU / 4, 0, 0), parent=parent)
    _axle('Rim', radius * 0.62, width * 0.8, loc, 'armor_light', parent)
    _axle('RimDish', radius * 0.45, width * 0.86, loc, 'armor_dark', parent)
    _axle('Hub', radius * 0.2, width * 0.95, loc, 'chrome', parent, verts=12)
    for i in range(5):
        a = i * TAU / 5
        for side in (-1, 1):
            ball('Lug', radius * 0.06, (loc[0] + radius * 0.33 * math.cos(a), loc[1] + side * width * 0.44, loc[2] + radius * 0.33 * math.sin(a)), 'chrome', parent=parent)


def worker():
    root = empty('Root')
    body = empty('Body', (0, 0, 0.2), root)
    shell('Chassis', (0.58, 0.28, 0.1), (0, 0, 0), 'armor_dark', taper=(0.94, 0.9), round=0.02, parent=body)
    shell('Cab', (0.25, 0.26, 0.11), (0.09, 0, 0.1), 'armor', taper=(0.74, 0.82), shift=(0.02, 0), round=0.03, parent=body)
    shell('Windscreen', (0.05, 0.2, 0.06), (0.2, 0, 0.11), 'glass', taper=(0.6, 0.85), shift=(-0.02, 0), round=0.012, parent=body)
    shell('Head', (0.1, 0.17, 0.06), (0.265, 0, 0.06), 'armor_dark', taper=(0.7, 0.9), round=0.02, parent=body)
    shell('Eye', (0.02, 0.11, 0.028), (0.312, 0, 0.062), 'glow_cyan', round=0.008, parent=body)
    shell('Bin', (0.22, 0.3, 0.15), (-0.18, 0, 0.125), 'team_coat', taper=(1.12, 1.08), round=0.015, parent=body)
    shell('BinLoad', (0.19, 0.27, 0.05), (-0.18, 0, 0.19), 'scrap', round=0.012, parent=body)
    for i in range(3):
        shell('BinRib', (0.015, 0.325, 0.13), (-0.26 + i * 0.08, 0, 0.125), 'armor_dark', taper=(1.0, 1.08), round=0.004, parent=body, panel=False)
    pipe('BeaconStalk', (-0.02, 0.1, 0.15), (-0.02, 0.1, 0.2), 0.008, 'black', body)
    ball('Beacon', 0.026, (-0.02, 0.1, 0.205), 'glow_amber', parent=body)
    for x in (-0.19, 0.19):
        for y in (-0.19, 0.19):
            _tyre((x, y, 0.105), 0.105, 0.085, root)
            shell('Fender', (0.23, 0.095, 0.022), (x, y, 0.035), 'armor', taper=(0.7, 1.0), round=0.01, parent=body, panel=False)
    _axle('AxleFront', 0.02, 0.36, (0.19, 0, 0.105), 'black', root, verts=10)
    _axle('AxleRear', 0.02, 0.36, (-0.19, 0, 0.105), 'black', root, verts=10)
    cyl('ArmTurret', 0.055, 0.04, (0.1, -0.08, 0.155), 'hazard', verts=20, parent=body)
    shoulder = empty('Shoulder', (0.1, -0.08, 0.17), body)
    _axle('ShoulderPin', 0.032, 0.07, (0, 0, 0), 'black', shoulder, verts=14)
    strut('Arm', (0, 0, 0), (0.2, 0, 0.16), 0.045, 0.04, 'hazard', taper=0.8, parent=shoulder)
    pipe('ArmRam', (0.03, 0.028, -0.01), (0.14, 0.028, 0.1), 0.012, 'chrome', shoulder)
    elbow = empty('Elbow', (0.2, 0, 0.16), shoulder)
    _axle('ElbowPin', 0.028, 0.065, (0, 0, 0), 'black', elbow, verts=14)
    strut('Forearm', (0, 0, 0), (0.2, 0, -0.08), 0.038, 0.034, 'hazard', taper=0.75, parent=elbow)
    for y in (-0.028, 0.028):
        shell('Claw', (0.08, 0.02, 0.045), (0.225, y, -0.095), 'armor_dark', taper=(0.5, 1.0), shift=(0.015, 0), round=0.008, parent=elbow, panel=False)
    spark = _flash(elbow, (0.27, 0, -0.1), 0.035)
    shell('Bumper', (0.045, 0.3, 0.045), (0.3, 0, -0.025), 'hazard', round=0.015, parent=body, panel=False)
    for y in (-0.1, 0.1):
        ball('Lamp', 0.02, (0.318, y, 0.02), 'glow_white', parent=body)
    pipe('Exhaust', (-0.26, -0.115, 0.05), (-0.26, -0.115, 0.27), 0.016, 'chrome', body)
    cyl('ExhaustCap', 0.022, 0.02, (-0.26, -0.115, 0.27), 'black', verts=12, parent=body)
    shell('Toolbox', (0.1, 0.06, 0.05), (0.0, 0.125, 0.075), 'hazard', round=0.01, parent=body, panel=False)

    def pose(anim, t):
        wave = math.sin(t * TAU)
        d = t if anim == 'death' else 0.0
        body.location.z = 0.2 + (0.012 * wave if anim == 'move' else 0.0) - 0.07 * d
        body.rotation_euler = (0.55 * d, (0.03 * math.cos(t * TAU) if anim == 'move' else 0.0) - 0.2 * d, 0.3 * d)
        shoulder.rotation_euler.y = 0.9 * d
        elbow.rotation_euler.y = 0.7 * d
        if anim == 'attack':
            shoulder.rotation_euler.y = 0.55 * (0.5 - 0.5 * math.cos(t * TAU))
            elbow.rotation_euler.y = 0.5 * (0.5 - 0.5 * math.cos(t * TAU))
        return (anim == 'attack' and 0.35 < t < 0.65) or (anim == 'death' and t < 0.34)
    return {'group': 'units', 'cells': 1, 'pose': pose, 'root': root}


def scout():
    root = empty('Root')
    body = empty('Body', (0, 0, 0.3), root)
    ball('Fuselage', 0.1, (0.0, 0, 0), 'armor_light', scale=(3.0, 0.9, 0.62), parent=body)
    _along('Nose', 0.052, 0.2, (0.33, 0, -0.004), 'armor_light', body, top=0.012)
    ball('Canopy', 0.06, (0.11, 0, 0.035), 'glass', scale=(1.7, 0.85, 0.62), parent=body)
    shell('Stripe', (0.22, 0.14, 0.03), (-0.09, 0, 0.045), 'team_coat', taper=(0.85, 0.7), round=0.012, parent=body, panel=False)
    for y in (-0.2, 0.2):
        shell('Pylon', (0.08, 0.14, 0.026), (0.0, y * 0.5, 0.0), 'armor', taper=(0.7, 1.0), round=0.01, parent=body, panel=False)
        ring('Duct', 0.105, 0.03, (0.0, y, 0.0), 'armor_dark', parent=body)
        ring('DuctLip', 0.105, 0.012, (0.0, y, 0.028), 'team_coat', parent=body)
        cyl('FanDisc', 0.095, 0.01, (0.0, y, 0.0), 'black', verts=24, parent=body)
        cyl('FanGlow', 0.07, 0.01, (0.0, y, -0.03), 'glow_cyan', verts=20, parent=body)
        ball('FanHub', 0.028, (0.0, y, 0.008), 'chrome', scale=(1, 1, 0.7), parent=body)
        for i in range(3):
            a = i * TAU / 3 + 0.4
            pipe('FanStay', (0.0, y, 0.01), (0.1 * math.cos(a), y + 0.1 * math.sin(a), 0.01), 0.006, 'armor_dark', body)
        shell('Winglet', (0.14, 0.07, 0.014), (-0.03, y * 1.72, 0.0), 'team_coat', taper=(0.6, 1.0), shift=(-0.02, 0), round=0.006, parent=body, panel=False)
    pipe('Boom', (-0.22, 0, 0.0), (-0.42, 0, 0.02), 0.022, 'armor_dark', body)
    for side in (-1, 1):
        shell('TailFin', (0.1, 0.012, 0.13), (-0.39, side * 0.04, 0.075), 'team_coat', taper=(0.55, 1.0), shift=(-0.03, 0), round=0.005, rot=(-side * 0.55, 0, 0), parent=body, panel=False)
    _along('Thruster', 0.034, 0.05, (-0.43, 0, 0.02), 'armor_dark', body, verts=14)
    _along('ThrusterGlow', 0.026, 0.052, (-0.435, 0, 0.02), 'glow_cyan', body, verts=14)
    _along('GunPod', 0.024, 0.16, (0.24, 0, -0.05), 'armor_dark', body, verts=14)
    pipe('Gun', (0.3, 0, -0.05), (0.52, 0, -0.05), 0.012, 'black', body)
    ball('Sensor', 0.026, (0.2, 0, -0.075), 'glow_red', parent=body)
    for y in (-0.05, 0.05):
        shell('Intake', (0.07, 0.03, 0.035), (0.16, y * 1.6, 0.0), 'black', taper=(0.7, 0.8), round=0.01, parent=body, panel=False)
    _flash(body, (0.56, 0, -0.05), 0.03)

    def pose(anim, t):
        wave = math.sin(t * TAU)
        d = t if anim == 'death' else 0.0
        body.location = (0, 0, 0.3 + 0.02 * wave * (1.0 - d) - 0.19 * d * d)
        body.rotation_euler = ((0.1 * wave if anim == 'move' else 0.0) + 1.3 * d, (-0.12 if anim == 'move' else 0.0) + 0.5 * d, 0.8 * d)
        if anim == 'attack':
            body.location.x = -0.03 * math.sin(t * math.pi)
        return (anim == 'attack' and t < 0.3) or (anim == 'death' and t < 0.34)
    return {'group': 'units', 'cells': 1, 'pose': pose, 'root': root}


def _leg(parent, y):
    hip = empty('Hip', (0, y, 0), parent)
    _axle('HipJoint', 0.06, 0.1, (0, 0, 0), 'black', hip)
    strut('Thigh', (0, 0, 0), (0.07, 0, -0.2), 0.1, 0.085, 'armor', taper=0.78, round=0.02, parent=hip)
    shell('ThighPlate', (0.04, 0.1, 0.15), (0.085, 0, -0.1), 'armor_light', taper=(0.8, 0.85), round=0.014, rot=(0, -0.33, 0), parent=hip, panel=False)
    knee = empty('Knee', (0.07, 0, -0.2), hip)
    _axle('KneeJoint', 0.05, 0.11, (0, 0, 0), 'chrome', knee)
    shell('KneeGuard', (0.04, 0.105, 0.1), (0.055, 0, 0.0), 'team_coat', taper=(0.8, 0.8), round=0.016, parent=knee, panel=False)
    strut('Shin', (0, 0, 0), (-0.06, 0, -0.2), 0.075, 0.07, 'armor_dark', taper=0.72, round=0.016, parent=knee)
    pipe('ShinRam', (-0.035, 0, -0.01), (-0.085, 0, -0.16), 0.011, 'chrome', knee)
    ball('Ankle', 0.036, (-0.06, 0, -0.2), 'black', parent=knee)
    shell('Foot', (0.2, 0.13, 0.05), (-0.02, 0, -0.22), 'armor_dark', taper=(0.78, 0.82), round=0.016, parent=knee, panel=False)
    shell('Toe', (0.075, 0.12, 0.036), (0.095, 0, -0.227), 'black', taper=(0.6, 0.85), shift=(-0.012, 0), round=0.012, parent=knee, panel=False)
    return hip, knee


def sentinel():
    root = empty('Root')
    pelvis = empty('Pelvis', (0, 0, 0.45), root)
    shell('Hips', (0.17, 0.24, 0.1), (0, 0, 0), 'armor_dark', taper=(0.86, 0.9), round=0.025, parent=pelvis, panel=False)
    cyl('Belt', 0.1, 0.025, (0, 0, 0.055), 'hazard', verts=24, parent=pelvis).scale = (0.85, 1.25, 1.0)
    legs = [_leg(pelvis, -0.13), _leg(pelvis, 0.13)]
    torso = empty('Torso', (0, 0, 0.08), pelvis)
    cyl('Waist', 0.075, 0.07, (0, 0, 0.01), 'black', verts=20, parent=torso)
    shell('Chest', (0.25, 0.32, 0.23), (0.0, 0, 0.15), 'armor_light', taper=(1.06, 1.1), round=0.04, parent=torso)
    shell('ChestPlate', (0.07, 0.25, 0.17), (0.145, 0, 0.14), 'armor', taper=(0.6, 0.85), shift=(-0.012, 0), round=0.025, parent=torso, panel=False)
    for z in (0.09, 0.125, 0.16):
        shell('Vent', (0.02, 0.15, 0.014), (0.182, 0, z), 'black', round=0.004, parent=torso, panel=False)
    shell('Pack', (0.13, 0.25, 0.2), (-0.18, 0, 0.17), 'armor_dark', taper=(0.85, 0.9), round=0.03, parent=torso, panel=False)
    shell('PackLight', (0.02, 0.13, 0.035), (-0.25, 0, 0.2), 'glow_amber', round=0.008, parent=torso)
    for y in (-0.07, 0.07):
        pipe('PackStack', (-0.2, y, 0.25), (-0.22, y, 0.33), 0.016, 'black', torso)
    cyl('Neck', 0.04, 0.04, (0.03, 0, 0.275), 'black', verts=14, parent=torso)
    shell('Head', (0.14, 0.14, 0.085), (0.04, 0, 0.325), 'armor_dark', taper=(0.74, 0.8), shift=(-0.01, 0), round=0.026, parent=torso, panel=False)
    shell('Visor', (0.022, 0.11, 0.026), (0.108, 0, 0.32), 'glow_cyan', round=0.008, parent=torso)
    arms = []
    for y in (-0.235, 0.235):
        arm = empty('Arm', (0, y, 0.2), torso)
        ball('Pauldron', 0.1, (0, 0, 0.035), 'team_coat', scale=(1.05, 0.82, 0.85), parent=arm)
        _axle('ShoulderPin', 0.04, 0.12, (0, -y * 0.25, 0.02), 'black', arm, verts=14)
        shell('Gun', (0.3, 0.09, 0.1), (0.12, 0, -0.085), 'armor_dark', taper=(0.9, 0.8), round=0.022, parent=arm, panel=False)
        _axle('AmmoDrum', 0.05, 0.085, (0.02, 0, -0.15), 'armor', arm, verts=18)
        _along('Shroud', 0.034, 0.1, (0.29, 0, -0.085), 'armor', arm, verts=14)
        pipe('Barrel', (0.3, 0, -0.085), (0.43, 0, -0.085), 0.02, 'black', arm)
        _along('Muzzle', 0.027, 0.03, (0.43, 0, -0.085), 'black', arm, verts=12)
        _flash(arm, (0.48, 0, -0.085), 0.035)
        arms.append(arm)
    _antenna('Whip', (-0.15, 0.1, 0.26), 0.25, parent=torso)

    def pose(anim, t):
        swing = math.sin(t * TAU) if anim == 'move' else 0.0
        d = t if anim == 'death' else 0.0
        for i, (hip, knee) in enumerate(legs):
            s = swing if i == 0 else -swing
            hip.rotation_euler.y = -0.55 * s - 1.1 * d
            knee.rotation_euler.y = 0.45 * max(0.0, -s) + 0.1 + 1.9 * d
        pelvis.location.z = 0.45 + (0.018 * abs(math.cos(t * TAU)) if anim == 'move' else 0.0) - 0.26 * d
        torso.rotation_euler = (0.25 * d, (0.05 if anim == 'move' else 0.0) + 1.25 * d, 0.06 * swing)
        kick = math.sin(t * math.pi) if anim == 'attack' else 0.0
        for arm in arms:
            arm.location.x = -0.05 * kick
            arm.rotation_euler.y = -0.06 * kick + 0.8 * d
        return (anim == 'attack' and t < 0.3) or (anim == 'death' and t < 0.34)
    return {'group': 'units', 'cells': 1, 'pose': pose, 'root': root}


def disruptor():
    root = empty('Root')
    hull = empty('Hull', (0, 0, 0.2), root)
    shell('Tub', (0.9, 0.42, 0.16), (0, 0, 0.02), 'armor', taper=(0.8, 0.84), shift=(-0.03, 0), round=0.03, parent=hull)
    shell('Glacis', (0.22, 0.38, 0.1), (0.47, 0, -0.01), 'armor', taper=(0.3, 0.9), shift=(-0.07, 0), round=0.025, parent=hull, panel=False)
    shell('EngineDeck', (0.3, 0.33, 0.05), (-0.25, 0, 0.115), 'armor_dark', taper=(0.9, 0.9), round=0.015, parent=hull, panel=False)
    for i in range(5):
        shell('Grille', (0.022, 0.26, 0.012), (-0.35 + i * 0.045, 0, 0.143), 'black', round=0.004, parent=hull, panel=False)
    for y in (-0.27, 0.27):
        shell('Track', (1.0, 0.13, 0.17), (0.02, y, -0.08), 'rubber', round=0.075, parent=hull)
        for i in range(15):
            shell('TrackPad', (0.035, 0.136, 0.014), (-0.4 + i * 0.06, y, 0.006), 'black', round=0.004, parent=hull, panel=False)
        for i in range(5):
            _axle('RoadWheel', 0.058, 0.14, (-0.34 + i * 0.18, y, -0.1), 'armor_dark', hull, verts=18)
            _axle('RoadHub', 0.024, 0.15, (-0.34 + i * 0.18, y, -0.1), 'chrome', hull, verts=10)
        _axle('Sprocket', 0.062, 0.145, (0.46, y, -0.055), 'armor_light', hull, verts=12)
        _axle('Idler', 0.062, 0.145, (-0.43, y, -0.055), 'armor_light', hull, verts=12)
        side = 1.0 if y > 0 else -1.0
        shell('Skirt', (0.74, 0.02, 0.085), (0.0, y + side * 0.068, -0.005), 'team_coat', taper=(0.96, 1.0), round=0.008, parent=hull, panel=True)
        shell('Fender', (1.0, 0.15, 0.016), (0.02, y, 0.03), 'armor', round=0.007, parent=hull, panel=False)
        shell('Stowage', (0.17, 0.065, 0.065), (-0.2, y * 0.8, 0.135), 'armor_dark', round=0.014, parent=hull, panel=False)
    turret = empty('Turret', (-0.02, 0, 0.14), hull)
    cyl('TurretRing', 0.2, 0.04, (0, 0, 0.0), 'armor_dark', verts=28, parent=turret)
    shell('TurretBody', (0.42, 0.32, 0.14), (0.02, 0, 0.085), 'armor_light', taper=(0.72, 0.72), shift=(-0.02, 0), round=0.035, parent=turret, panel=False)
    shell('TurretPlate', (0.22, 0.2, 0.02), (-0.03, 0, 0.158), 'team_coat', taper=(0.9, 0.9), round=0.008, parent=turret, panel=False)
    _axle('Mantlet', 0.062, 0.2, (0.2, 0, 0.08), 'armor_dark', turret, verts=18)
    cyl('Cupola', 0.05, 0.035, (-0.1, 0.075, 0.165), 'armor_dark', verts=18, parent=turret)
    cyl('Hatch', 0.04, 0.012, (-0.1, 0.075, 0.186), 'armor', verts=18, parent=turret)
    gun = empty('Gun', (0.3, 0, 0.08), turret)
    _along('Jacket', 0.045, 0.16, (0.04, 0, 0.002), 'armor', gun, pitch=0.036, verts=16)
    pipe('Barrel', (0, 0, 0), (0.56, 0, 0.02), 0.03, 'armor_dark', gun)
    for i in range(3):
        ring('Emitter', 0.05, 0.014, (0.2 + i * 0.13, 0, 0.007 + i * 0.004), 'glow_violet', rot=(0, TAU / 4, 0), parent=gun)
    _along('Muzzle', 0.045, 0.08, (0.57, 0, 0.02), 'black', gun, pitch=0.036, verts=14)
    _flash(gun, (0.66, 0, 0.02), 0.05)
    _antenna('Whip', (-0.16, -0.1, 0.15), 0.3, parent=turret)
    for y in (-0.12, 0.12):
        ring('TowEye', 0.02, 0.007, (0.56, y, -0.05), 'black', rot=(0, TAU / 4, 0), parent=hull)
        ball('HeadLamp', 0.018, (0.5, y * 1.3, 0.035), 'glow_white', parent=hull)
    pipe('Exhaust', (-0.44, 0.12, 0.08), (-0.52, 0.12, 0.2), 0.02, 'rust', hull)

    def pose(anim, t):
        d = t if anim == 'death' else 0.0
        hull.location.z = 0.2 + (0.008 * math.sin(t * TAU * 2) if anim == 'move' else 0.0) - 0.03 * d
        kick = math.sin(t * math.pi) if anim == 'attack' else 0.0
        hull.rotation_euler = (0.12 * d, (0.015 * math.sin(t * TAU) if anim == 'move' else 0.0) + 0.03 * kick, 0.0)
        gun.location.x = 0.3 - 0.1 * kick
        gun.rotation_euler.y = 0.35 * d
        # The turret is blown off its ring and lands askew.
        turret.location = (-0.02 - 0.12 * d, 0.1 * d, 0.14 + 0.3 * math.sin(d * math.pi) + 0.02 * d)
        turret.rotation_euler = (0.5 * d, -0.3 * d, 1.4 * d)
        return (anim == 'attack' and t < 0.3) or (anim == 'death' and t < 0.5)
    return {'group': 'units', 'cells': 1, 'pose': pose, 'root': root, 'large': True}


def walker():
    root = empty('Root')
    body = empty('Body', (0, 0, 0.62), root)
    shell('Core', (0.74, 0.46, 0.27), (0, 0, 0), 'armor', taper=(0.8, 0.78), shift=(-0.02, 0), round=0.05, parent=body)
    shell('Prow', (0.28, 0.4, 0.2), (0.44, 0, -0.03), 'armor', taper=(0.3, 0.78), shift=(-0.08, 0), round=0.04, parent=body, panel=False)
    shell('Belly', (0.52, 0.34, 0.08), (0, 0, -0.16), 'armor_dark', taper=(1.1, 1.12), round=0.02, parent=body, panel=False)
    shell('Armour', (0.46, 0.34, 0.05), (-0.05, 0, 0.15), 'team_coat', taper=(0.86, 0.84), round=0.018, parent=body, panel=False)
    _along('Reactor', 0.13, 0.2, (-0.44, 0, 0.03), 'armor_dark', body, verts=24)
    for i in range(4):
        ring('ReactorFin', 0.133, 0.012, (-0.5 + i * 0.045, 0, 0.03), 'black', rot=(0, TAU / 4, 0), parent=body)
    _along('ReactorGlow', 0.085, 0.03, (-0.545, 0, 0.03), 'glow_amber', body, verts=18)
    ball('Cockpit', 0.095, (0.27, 0, 0.115), 'glass', scale=(1.35, 1.0, 0.6), parent=body)
    shell('Visor', (0.02, 0.15, 0.028), (0.4, 0, 0.07), 'glow_cyan', round=0.008, parent=body)
    legs = []
    for i, (x, y) in enumerate(((0.26, -0.24), (0.26, 0.24), (-0.26, -0.24), (-0.26, 0.24))):
        hip = empty('Hip', (x, y, -0.04), body)
        side = -1.0 if y < 0 else 1.0
        ball('HipJoint', 0.09, (0, 0, 0), 'armor_dark', parent=hip)
        _along('HipPin', 0.04, 0.2, (0, 0, 0), 'chrome', hip, verts=14)
        strut('Upper', (0, 0, 0), (0.06, side * 0.2, 0.08), 0.11, 0.095, 'armor_light', taper=0.82, round=0.022, parent=hip)
        knee = empty('Knee', (0.06, side * 0.2, 0.08), hip)
        ball('KneeJoint', 0.078, (0, 0, 0), 'chrome', parent=knee)
        strut('Lower', (0, 0, 0), (0.02, side * 0.08, -0.6), 0.1, 0.09, 'armor_dark', taper=0.6, round=0.022, parent=knee)
        shell('Shin', (0.04, 0.105, 0.3), (0.07, side * 0.06, -0.27), 'team_coat', taper=(0.8, 0.75), round=0.016, rot=(side * 0.13, 0, 0), parent=knee, panel=False)
        pipe('Piston', (-0.03, side * 0.02, -0.06), (-0.02, side * 0.07, -0.42), 0.02, 'chrome', knee)
        pipe('Hose', (-0.045, side * 0.0, 0.02), (-0.05, side * 0.06, -0.3), 0.01, 'black', knee)
        ball('Ankle', 0.05, (0.02, side * 0.08, -0.59), 'black', parent=knee)
        cyl('Foot', 0.125, 0.06, (0.03, side * 0.08, -0.63), 'armor_dark', verts=18, top=0.095, parent=knee)
        for a in (-0.9, 0.0, 0.9, math.pi):
            shell('FootClaw', (0.09, 0.05, 0.04), (0.03 + 0.13 * math.cos(a), side * 0.08 + 0.13 * math.sin(a), -0.642), 'black', taper=(0.5, 0.8), round=0.012, rot=(0, 0, a), parent=knee, panel=False)
        legs.append((hip, knee))
    mount = empty('Mount', (-0.05, 0, 0.2), body)
    shell('Cradle', (0.3, 0.24, 0.12), (0, 0, 0.05), 'armor_dark', taper=(0.85, 0.82), round=0.025, parent=mount, panel=False)
    _axle('Trunnion', 0.05, 0.27, (0.02, 0, 0.12), 'chrome', mount, verts=16)
    gun = empty('Gun', (0.05, 0, 0.14), mount)
    _along('Breech', 0.09, 0.3, (-0.05, 0, -0.01), 'armor_light', gun, pitch=0.0, verts=20)
    _along('BreechCap', 0.075, 0.04, (-0.21, 0, -0.01), 'black', gun, verts=18)
    pipe('Barrel', (0.05, 0, 0), (0.95, 0, 0.1), 0.05, 'armor_dark', gun)
    _along('Sleeve', 0.072, 0.3, (0.3, 0, 0.027), 'armor', gun, pitch=0.105, verts=18)
    pipe('Recoil', (0.02, 0, 0.085), (0.4, 0, 0.125), 0.02, 'chrome', gun)
    _along('Brake', 0.078, 0.12, (0.95, 0, 0.1), 'black', gun, pitch=0.105, verts=16)
    _along('BrakeRing', 0.085, 0.02, (0.9, 0, 0.095), 'armor', gun, pitch=0.105, verts=16)
    _flash(gun, (1.1, 0, 0.115), 0.09)
    _antenna('Whip', (-0.3, 0.16, 0.2), 0.35, parent=body)
    for y in (-0.2, 0.2):
        shell('Chevron', (0.12, 0.012, 0.035), (0.2, y * 1.06, -0.085), 'hazard', round=0.004, parent=body, panel=False)
        ball('Lamp', 0.022, (0.5, y * 0.6, -0.06), 'glow_white', parent=body)
    for y in (-0.1, 0.1):
        pipe('Stack', (-0.36, y, 0.14), (-0.4, y, 0.32), 0.024, 'rust', body)
        cyl('StackCap', 0.03, 0.02, (-0.4, y, 0.32), 'black', verts=12, parent=body)

    def pose(anim, t):
        d = t if anim == 'death' else 0.0
        for i, (hip, knee) in enumerate(legs):
            phase = t + (0.0 if i in (0, 3) else 0.5)
            s = math.sin(phase * TAU) if anim == 'move' else 0.0
            side = -1.0 if i % 2 == 0 else 1.0
            hip.rotation_euler = (-side * 1.0 * d, -0.32 * s, 0.0)
            knee.rotation_euler = (side * 0.15 * d, 0.22 * max(0.0, -math.cos(phase * TAU)) if anim == 'move' else 0.0, 0.0)
        body.location.z = 0.62 + (0.015 * math.sin(t * TAU * 2) if anim == 'move' else 0.0) - 0.3 * d
        kick = math.sin(t * math.pi) if anim == 'attack' else 0.0
        gun.location.x = 0.05 - 0.14 * kick
        gun.rotation_euler.y = 0.3 * d
        body.rotation_euler = (0.3 * d, 0.05 * kick + 0.12 * d, 0.0)
        return (anim == 'attack' and t < 0.3) or (anim == 'death' and t < 0.5)
    return {'group': 'units', 'cells': 1, 'pose': pose, 'root': root, 'large': True}


# ---- scenery ----------------------------------------------------------------------
# One atlas column per variant; every object carries the `variant` it belongs to.

def _track(hull, y, length=1.0):
    """One tracked running gear along the hull at side offset y: belt, pads, road wheels, sprocket, idler, skirt."""
    half = length * 0.5
    shell('Track', (length, 0.13, 0.17), (0.02, y, -0.08), 'rubber', round=0.075, parent=hull)
    pads = int(length / 0.066)
    for i in range(pads):
        shell('TrackPad', (0.035, 0.136, 0.014), (0.02 - half + 0.08 + i * (length - 0.16) / (pads - 1), y, 0.006), 'black', round=0.004, parent=hull, panel=False)
    wheels = max(3, int(length / 0.2))
    for i in range(wheels):
        x = 0.02 - half + 0.16 + i * (length - 0.32) / (wheels - 1)
        _axle('RoadWheel', 0.058, 0.14, (x, y, -0.1), 'armor_dark', hull, verts=18)
        _axle('RoadHub', 0.024, 0.15, (x, y, -0.1), 'chrome', hull, verts=10)
    _axle('Sprocket', 0.062, 0.145, (0.02 + half - 0.06, y, -0.055), 'armor_light', hull, verts=12)
    _axle('Idler', 0.062, 0.145, (0.02 - half + 0.07, y, -0.055), 'armor_light', hull, verts=12)
    side = 1.0 if y > 0 else -1.0
    shell('Skirt', (length * 0.74, 0.02, 0.085), (0.0, y + side * 0.068, -0.005), 'team_coat', taper=(0.96, 1.0), round=0.008, parent=hull, panel=True)
    shell('Fender', (length, 0.15, 0.016), (0.02, y, 0.03), 'armor', round=0.007, parent=hull, panel=False)


def warden():
    """Origin shield carrier: a six-wheeled armoured hull under a projector ring on a mast."""
    root = empty('Root')
    body = empty('Body', (0, 0, 0.25), root)
    shell('Hull', (0.8, 0.4, 0.17), (0, 0, 0.01), 'armor', taper=(0.84, 0.84), shift=(-0.02, 0), round=0.035, parent=body)
    shell('Prow', (0.2, 0.36, 0.12), (0.43, 0, -0.01), 'armor', taper=(0.32, 0.9), shift=(-0.07, 0), round=0.028, parent=body, panel=False)
    shell('Cab', (0.2, 0.3, 0.085), (0.22, 0, 0.125), 'armor_light', taper=(0.68, 0.8), shift=(0.015, 0), round=0.03, parent=body, panel=False)
    shell('Visor', (0.03, 0.23, 0.036), (0.315, 0, 0.128), 'glass', taper=(0.6, 0.9), shift=(-0.01, 0), round=0.01, parent=body, panel=False)
    shell('Deck', (0.4, 0.34, 0.04), (-0.15, 0, 0.11), 'armor_dark', taper=(0.92, 0.92), round=0.012, parent=body, panel=False)
    for y in (-0.2, 0.2):
        side = 1.0 if y > 0 else -1.0
        shell('SidePlate', (0.52, 0.02, 0.1), (-0.03, y + side * 0.012, 0.03), 'team_coat', taper=(0.94, 1.0), round=0.008, parent=body, panel=True)
        shell('Mudguard', (0.86, 0.1, 0.018), (0.0, y + side * 0.04, -0.045), 'armor', round=0.008, parent=body, panel=False)
        for i in range(3):
            cyl('Cell', 0.032, 0.085, (-0.3 + i * 0.075, y * 0.6, 0.165), 'hazard', verts=14, parent=body)
            ball('CellCap', 0.022, (-0.3 + i * 0.075, y * 0.6, 0.21), 'chrome', scale=(1, 1, 0.6), parent=body)
        ball('HeadLamp', 0.02, (0.455, y * 0.6, 0.0), 'glow_white', parent=body)
    for x in (-0.28, 0.0, 0.28):
        for y in (-0.235, 0.235):
            _tyre((x, y, 0.115), 0.115, 0.09, root)
        _axle('Axle', 0.022, 0.44, (x, 0, 0.115), 'black', root, verts=10)
    mast = empty('Mast', (-0.14, 0, 0.13), body)
    cyl('MastBase', 0.115, 0.05, (0, 0, 0.0), 'armor_dark', verts=28, parent=mast)
    cyl('MastCollar', 0.07, 0.04, (0, 0, 0.045), 'armor', verts=20, parent=mast)
    cyl('MastColumn', 0.04, 0.2, (0, 0, 0.16), 'armor_light', verts=16, parent=mast)
    for i in range(3):
        a = i * TAU / 3
        pipe('MastStay', (0.09 * math.cos(a), 0.09 * math.sin(a), 0.02), (0.03 * math.cos(a), 0.03 * math.sin(a), 0.2), 0.008, 'chrome', mast)
    emitter = empty('Emitter', (0, 0, 0.28), mast)
    ring('Halo', 0.2, 0.024, (0, 0, 0), 'team_coat', parent=emitter)
    ring('HaloGlow', 0.2, 0.011, (0, 0, 0.02), 'glow_cyan', parent=emitter)
    ball('Lens', 0.07, (0, 0, 0), 'glow_cyan', scale=(1, 1, 0.55), parent=emitter)
    cyl('LensSeat', 0.08, 0.03, (0, 0, -0.02), 'armor_dark', verts=20, parent=emitter)
    for i in range(4):
        a = i * TAU / 4 + TAU / 8
        pipe('Spoke', (0.06 * math.cos(a), 0.06 * math.sin(a), 0), (0.19 * math.cos(a), 0.19 * math.sin(a), 0), 0.011, 'chrome', emitter)
        ball('Node', 0.026, (0.2 * math.cos(a), 0.2 * math.sin(a), 0), 'armor_dark', parent=emitter)
    gun = empty('Gun', (0.3, 0, 0.19), body)
    ball('GunMount', 0.045, (0, 0, 0), 'armor_dark', scale=(1.2, 1, 0.8), parent=gun)
    pipe('GunBarrel', (0.02, 0, 0.0), (0.24, 0, 0.0), 0.014, 'black', gun)
    _along('GunShroud', 0.024, 0.09, (0.09, 0, 0), 'armor', gun, verts=12)
    _flash(gun, (0.28, 0, 0), 0.032)
    _antenna('Whip', (-0.34, 0.12, 0.13), 0.26, parent=body)
    pipe('Exhaust', (-0.38, -0.13, 0.06), (-0.45, -0.13, 0.19), 0.018, 'rust', body)

    def pose(anim, t):
        wave = math.sin(t * TAU)
        d = t if anim == 'death' else 0.0
        kick = math.sin(t * math.pi) if anim == 'attack' else 0.0
        body.location.z = 0.25 + (0.01 * wave if anim == 'move' else 0.0) - 0.06 * d
        body.rotation_euler = (0.35 * d, (0.02 * math.cos(t * TAU) if anim == 'move' else 0.0) - 0.12 * d, 0.2 * d)
        # The ring turns a quarter per cycle; with four spokes that loops without a seam.
        emitter.rotation_euler = (0.9 * d, 0.4 * d, t * TAU / 4 if anim != 'death' else 0.0)
        emitter.scale = (1.0 + 0.08 * kick,) * 3
        mast.rotation_euler = (0.0, 1.1 * d, 0.0)
        gun.location.x = 0.3 - 0.04 * kick
        return (anim == 'attack' and t < 0.3) or (anim == 'death' and t < 0.34)
    return {'group': 'units', 'cells': 1, 'pose': pose, 'root': root, 'large': True}


def mortar():
    """Foundry tracked launcher: a short hull carrying one fat tube laid back at a high angle."""
    root = empty('Root')
    hull = empty('Hull', (0, 0, 0.2), root)
    shell('Tub', (0.86, 0.44, 0.15), (0, 0, 0.015), 'armor', taper=(0.84, 0.86), shift=(-0.02, 0), round=0.03, parent=hull)
    shell('Glacis', (0.2, 0.4, 0.1), (0.45, 0, -0.01), 'armor', taper=(0.3, 0.9), shift=(-0.07, 0), round=0.025, parent=hull, panel=False)
    shell('Cab', (0.18, 0.3, 0.07), (0.26, 0, 0.12), 'armor_light', taper=(0.7, 0.8), round=0.025, parent=hull, panel=False)
    shell('Slit', (0.02, 0.22, 0.02), (0.345, 0, 0.125), 'glass', round=0.006, parent=hull, panel=False)
    for y in (-0.28, 0.28):
        _track(hull, y, 0.96)
    shell('Well', (0.42, 0.36, 0.05), (-0.1, 0, 0.11), 'armor_dark', taper=(0.94, 0.94), round=0.012, parent=hull, panel=False)
    shell('WellPlate', (0.16, 0.3, 0.012), (-0.33, 0, 0.14), 'team_coat', round=0.005, parent=hull, panel=False)
    cradle = empty('Cradle', (-0.04, 0, 0.19), hull)
    _axle('Trunnion', 0.05, 0.34, (0, 0, 0), 'armor_dark', cradle, verts=18)
    for y in (-0.15, 0.15):
        shell('Cheek', (0.2, 0.035, 0.16), (0, y, -0.03), 'armor', taper=(0.6, 1.0), round=0.012, parent=cradle, panel=False)
        ball('CheekBolt', 0.022, (0, y * 1.15, 0), 'chrome', parent=cradle)
    tube = empty('Tube', (0, 0, 0), cradle)
    tube.rotation_euler.y = -0.95
    slide = empty('Slide', (0, 0, 0), tube)
    _along('Breech', 0.095, 0.16, (-0.02, 0, 0), 'armor_dark', slide, verts=22)
    ball('BreechCap', 0.085, (-0.1, 0, 0), 'armor_dark', scale=(0.6, 1, 1), parent=slide)
    _along('Barrel', 0.07, 0.5, (0.3, 0, 0), 'armor', slide, verts=24)
    for x in (0.14, 0.34):
        ring('Band', 0.072, 0.013, (x, 0, 0), 'hazard', rot=(0, TAU / 4, 0), parent=slide)
    _along('MuzzleRing', 0.084, 0.06, (0.57, 0, 0), 'black', slide, verts=22)
    _along('Bore', 0.052, 0.02, (0.6, 0, 0), 'glow_amber', slide, verts=18)
    _flash(slide, (0.68, 0, 0), 0.075)
    for y in (-0.105, 0.105):
        pipe('Recoil', (0.02, y, -0.07), (0.3, y, -0.07), 0.016, 'chrome', tube)
    for i in range(3):
        cyl('Round', 0.034, 0.11, (-0.36, -0.1 + i * 0.1, 0.2), 'hazard', verts=14, parent=hull)
        ball('RoundTip', 0.034, (-0.36, -0.1 + i * 0.1, 0.255), 'armor_light', scale=(1, 1, 1.3), parent=hull)
    shell('Rack', (0.1, 0.34, 0.04), (-0.36, 0, 0.155), 'armor_dark', round=0.01, parent=hull, panel=False)
    for y in (-0.13, 0.13):
        ball('HeadLamp', 0.018, (0.47, y * 0.95, 0.01), 'glow_white', parent=hull)
        pipe('Stack', (-0.44, y, 0.08), (-0.5, y, 0.24), 0.02, 'rust', hull)
    _antenna('Whip', (0.2, -0.12, 0.15), 0.24, parent=hull)

    def pose(anim, t):
        d = t if anim == 'death' else 0.0
        kick = math.sin(t * math.pi) if anim == 'attack' else 0.0
        hull.location.z = 0.2 + (0.008 * math.sin(t * TAU * 2) if anim == 'move' else 0.0) - 0.035 * kick - 0.03 * d
        hull.rotation_euler = (0.14 * d, (0.015 * math.sin(t * TAU) if anim == 'move' else 0.0) - 0.03 * kick, 0.0)
        slide.location.x = -0.14 * kick
        # Destroyed: the tube drops off its trunnion and the cradle slews.
        tube.rotation_euler.y = -0.95 + 1.25 * d
        cradle.location = (-0.04 - 0.05 * d, 0.06 * d, 0.19 - 0.05 * d)
        cradle.rotation_euler = (0.3 * d, 0.0, 0.5 * d)
        return (anim == 'attack' and t < 0.3) or (anim == 'death' and t < 0.5)
    return {'group': 'units', 'cells': 1, 'pose': pose, 'root': root, 'large': True}


def phantom():
    """Lattice hover raider: a low blade of a hull on two lift pods, with twin lances forward."""
    root = empty('Root')
    body = empty('Body', (0, 0, 0.27), root)
    ball('Hullform', 0.1, (0.0, 0, 0), 'armor_dark', scale=(3.3, 1.55, 0.42), parent=body)
    ball('Back', 0.08, (-0.06, 0, 0.022), 'armor', scale=(2.6, 1.05, 0.42), parent=body)
    ball('Canopy', 0.05, (0.12, 0, 0.03), 'glass', scale=(1.9, 0.8, 0.5), parent=body)
    shell('Spine', (0.34, 0.035, 0.022), (-0.1, 0, 0.052), 'team_coat', taper=(0.9, 0.6), round=0.008, parent=body, panel=False)
    for i in range(4):
        ring('Coil', 0.03, 0.007, (-0.2 + i * 0.07, 0, 0.06), 'glow_violet', rot=(0, TAU / 4, 0), parent=body)
    for y in (-1, 1):
        strut('Lance', (0.12, y * 0.085, -0.005), (0.52, y * 0.055, -0.012), 0.05, 0.034, 'armor', taper=0.45, round=0.012, parent=body)
        pipe('LanceTip', (0.5, y * 0.055, -0.012), (0.6, y * 0.052, -0.012), 0.008, 'black', body)
        ball('LanceGlow', 0.014, (0.5, y * 0.055, -0.012), 'glow_violet', parent=body)
        shell('Blade', (0.34, 0.15, 0.014), (-0.14, y * 0.2, 0.0), 'team_coat', taper=(0.4, 1.0), shift=(-0.1, 0), round=0.006, rot=(y * 0.12, 0, y * 0.5), parent=body, panel=False)
        ball('Pod', 0.07, (-0.16, y * 0.15, -0.03), 'armor', scale=(1.9, 0.95, 0.75), parent=body)
        cyl('PodGlow', 0.05, 0.012, (-0.16, y * 0.15, -0.08), 'glow_violet', verts=20, parent=body)
        ring('PodLip', 0.054, 0.009, (-0.16, y * 0.15, -0.076), 'armor_dark', parent=body)
        shell('Fin', (0.13, 0.01, 0.1), (-0.3, y * 0.07, 0.07), 'team_coat', taper=(0.45, 1.0), shift=(-0.045, 0), round=0.004, rot=(-y * 0.4, 0, 0), parent=body, panel=False)
        _flash(body, (0.63, y * 0.052, -0.012), 0.026)
    ball('Eye', 0.022, (0.31, 0, 0.0), 'glow_red', scale=(1.3, 1, 0.7), parent=body)
    _along('Drive', 0.03, 0.06, (-0.34, 0, 0.0), 'armor_dark', body, verts=14)
    _along('DriveGlow', 0.022, 0.062, (-0.345, 0, 0.0), 'glow_violet', body, verts=14)

    def pose(anim, t):
        wave = math.sin(t * TAU)
        d = t if anim == 'death' else 0.0
        body.location = (0, 0, 0.27 + 0.018 * wave * (1.0 - d) - 0.2 * d * d)
        body.rotation_euler = ((0.14 * wave if anim == 'move' else 0.0) + 1.5 * d, (-0.1 if anim == 'move' else 0.0) + 0.4 * d, 1.1 * d)
        if anim == 'attack':
            body.location.x = -0.035 * math.sin(t * math.pi)
        return (anim == 'attack' and t < 0.3) or (anim == 'death' and t < 0.34)
    return {'group': 'units', 'cells': 1, 'pose': pose, 'root': root}


def _tag(before, variant):
    for obj in bpy.context.scene.objects:
        if obj.name not in before and not obj.get('stage'):
            obj['variant'] = variant


def _names():
    return {o.name for o in bpy.context.scene.objects}


def _brighten(objects):
    """Lift the scan's colours: photographed foliage renders dull at sprite size."""
    for obj in objects:
        for slot in obj.material_slots:
            mat = slot.material
            if mat is None or not mat.use_nodes or mat.get('lifted'):
                continue
            mat['lifted'] = True
            bsdf = mat.node_tree.nodes.get('Principled BSDF')
            if bsdf is None or not bsdf.inputs['Base Color'].links:
                continue
            source = bsdf.inputs['Base Color'].links[0].from_socket
            lift = mat.node_tree.nodes.new('ShaderNodeHueSaturation')
            lift.inputs['Saturation'].default_value = 1.25
            lift.inputs['Value'].default_value = 1.45
            mat.node_tree.links.new(source, lift.inputs['Color'])
            mat.node_tree.links.new(lift.outputs['Color'], bsdf.inputs['Base Color'])


def _scan(folder, height, variant, spin=0.0, layers=1):
    """A Poly Haven photoscan (assets/third_party/processed), scaled to `height` cells.
    `layers` stands that many copies on the same trunk, turned about it, for a denser crown."""
    path = ROOT / 'assets' / 'third_party' / 'processed' / folder / (folder + '_lod0.gltf')
    if not path.exists():
        return False
    before = _names()
    bpy.ops.import_scene.gltf(filepath=str(path))
    fresh = [o for o in bpy.context.scene.objects if o.name not in before]
    bpy.context.view_layer.update()
    top = max((o.matrix_world @ Vector(c)).z for o in fresh if o.type == 'MESH' for c in o.bound_box)
    holder = empty('Scan')
    for obj in fresh:
        if obj.parent is None:
            obj.parent = holder
    # Stand the scan on its trunk: the centre of its lowest vertices goes to the origin.
    low = []
    for obj in fresh:
        if obj.type == 'MESH':
            for v in obj.data.vertices:
                p = obj.matrix_world @ v.co
                if p.z < top * 0.05:
                    low.append(p)
    foot = sum(low, Vector()) / len(low) if low else Vector()
    scale = height / top
    holder.scale = (scale,) * 3
    holder.rotation_euler.z = spin
    holder.location = -(Matrix.Rotation(spin, 3, 'Z') @ Vector((foot.x, foot.y, 0.0))) * scale
    _brighten(fresh)
    rng = random.Random(hash(folder) % 1000 + variant)
    for layer in range(1, layers):
        turn = spin + layer * TAU / layers + rng.uniform(-0.3, 0.3)
        size = scale * rng.uniform(0.82, 0.98)
        twin = empty('ScanLayer')
        copies = {}
        for obj in fresh:
            copy = obj.copy()
            bpy.context.scene.collection.objects.link(copy)
            copies[obj] = copy
        for obj, copy in copies.items():
            copy.parent = copies.get(obj.parent, twin)
            copy.matrix_parent_inverse = obj.matrix_parent_inverse.copy()
        twin.scale = (size,) * 3
        twin.rotation_euler.z = turn
        twin.location = -(Matrix.Rotation(turn, 3, 'Z') @ Vector((foot.x, foot.y, 0.0))) * size
    _tag(before, variant)
    return True


def _scans(group, entries):
    count = 0
    for folder, height, spin in entries:
        if _scan(folder, height, count, spin, 3 if group == 'tree' else 2):
            count += 1
    return {'group': 'scenery', 'cells': 1, 'variants': count}


def tree():
    return _scans('tree', (('island_tree_01', 3.4, 0.0), ('island_tree_02', 3.6, 1.0), ('jacaranda_tree', 3.4, 0.5), ('jacaranda_tree', 3.0, 2.1), ('island_tree_01', 2.8, 2.6), ('jacaranda_tree', 3.8, 4.0)))


def bush():
    return _scans('bush', (('fern_02', 0.5, 0.0), ('jacaranda_tree', 1.0, 0.0), ('jacaranda_tree', 0.8, 2.0), ('fern_02', 0.62, 1.5), ('island_tree_01', 1.1, 1.0), ('jacaranda_tree', 1.2, 3.3)))


def scenery_rubble():
    for variant in range(3):
        before = _names()
        rng = random.Random(40 + variant)
        for i in range(22):
            r = 0.42 * math.sqrt(rng.random())
            a = rng.uniform(0, TAU)
            s = rng.uniform(0.08, 0.3)
            heap = (1.0 - r / 0.45) * 0.3
            box('Chunk', (s * rng.uniform(0.7, 1.6), s * rng.uniform(0.6, 1.2), s * rng.uniform(0.3, 0.8)),
                (r * math.cos(a), r * math.sin(a), 0.04 + heap * rng.random() + s * 0.2),
                rng.choice(['concrete_dark', 'concrete', 'concrete', 'rust', 'hull_dark']),
                rot=(rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0, 3.1)))
        for i in range(3):
            a = rng.uniform(0, TAU)
            base = Vector((0.25 * math.cos(a), 0.25 * math.sin(a), 0.05))
            beam('Rebar', base, base + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0.3, 0.7))), 0.03, 'rust')
        _tag(before, variant)
    _scan('boulder_01', 0.55, 3)
    return {'group': 'scenery', 'cells': 1, 'variants': 4}


def barrier():
    for variant in range(2):
        before = _names()
        rng = random.Random(60 + variant)
        for i in range(3):
            y = -0.34 + i * 0.34
            turn = rng.uniform(-0.12, 0.12) + (0.0 if variant == 0 else TAU / 4)
            holder = empty('Barrier', (rng.uniform(-0.04, 0.04) if variant == 0 else y, y if variant == 0 else rng.uniform(-0.04, 0.04), 0.0))
            holder.rotation_euler.z = turn
            box('BarrierFoot', (0.3, 0.32, 0.12), (0, 0, 0.06), 'concrete', parent=holder)
            box('BarrierWall', (0.14, 0.32, 0.34), (0, 0, 0.27), 'concrete', parent=holder)
            box('BarrierStripe', (0.145, 0.1, 0.1), (0, 0, 0.32), 'hazard', parent=holder)
        cyl('Drum', 0.1, 0.26, (0.3, 0.3, 0.13), 'rust', verts=16)
        _tag(before, variant)
    return {'group': 'scenery', 'cells': 1, 'variants': 2}


def ruin():
    """The shell of a small building: broken walls around a slab."""
    for variant in range(3):
        before = _names()
        rng = random.Random(80 + variant)
        box('Slab', (0.92, 0.92, 0.08), (0, 0, 0.04), 'concrete_dark')
        for side in range(4):
            if side == (variant + 1) % 4 and rng.random() < 0.8:
                continue
            for i in range(5):
                t = -0.4 + i * 0.2
                h = rng.uniform(0.25, 1.5) * (1.0 if side in (2, 3) else 0.7)
                x, y = [(t, -0.42), (0.42, t), (t, 0.42), (-0.42, t)][side]
                size = (0.2, 0.08, h) if side in (0, 2) else (0.08, 0.2, h)
                box('Wall', size, (x, y, 0.08 + h * 0.5), 'concrete' if rng.random() < 0.7 else 'concrete_dark')
                if h > 0.9 and rng.random() < 0.5:
                    hole = (0.1, 0.09, 0.16) if side in (0, 2) else (0.09, 0.1, 0.16)
                    box('Window', hole, (x, y, 0.7), 'black')
        for i in range(4):
            a = rng.uniform(0, TAU)
            base = Vector((0.3 * math.cos(a), 0.3 * math.sin(a), 0.08))
            beam('Rebar', base, base + Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), rng.uniform(0.4, 1.1))), 0.03, 'rust')
        for i in range(8):
            s = rng.uniform(0.06, 0.18)
            box('Debris', (s * 1.4, s, s * 0.6), (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0.1 + s * 0.3), rng.choice(['concrete', 'concrete_dark', 'rust']), rot=(rng.random(), rng.random(), rng.random() * 3))
        _tag(before, variant)
    return {'group': 'scenery', 'cells': 1, 'variants': 3}


def _highrise(seed, floors, side):
    """A gutted tower: slabs and columns, glass left in some bays, the top floors torn open."""
    rng = random.Random(seed)
    half = side * 0.5
    storey = 0.85
    box('Podium', (side + 0.3, side + 0.3, 0.3), (0, 0, 0.15), 'concrete_dark')
    for f in range(floors):
        z = 0.3 + f * storey
        torn = max(0, f - floors + 3)                      # the last storeys lose more and more
        keep = 1.0 - torn * 0.3
        box('Slab', (side * (1.0 if torn < 2 else 0.7), side * (1.0 if torn < 1 else 0.75), 0.09), (-(0.0 if torn < 2 else side * 0.15), (0.0 if torn < 1 else side * 0.12), z + storey), 'concrete')
        for cx in (-half, 0.0, half):
            for cy in (-half, 0.0, half):
                if rng.random() < keep:
                    h = storey * (1.0 if rng.random() < keep else rng.uniform(0.3, 0.7))
                    box('Column', (0.16, 0.16, h), (cx * 0.94, cy * 0.94, z + h * 0.5), 'concrete_dark')
        for face in range(4):
            for bay in range(2):
                roll = rng.random()
                if roll > keep * 0.72:
                    continue
                t = (-0.5 + bay) * half + half * 0.5 - half * 0.5
                t = -half * 0.5 + bay * half
                x, y = [(t, -half), (half, t), (t, half), (-half, t)][face]
                size = (half * 0.82, 0.05, storey * 0.86) if face in (0, 2) else (0.05, half * 0.82, storey * 0.86)
                lit = rng.random() < 0.04
                box('Pane', size, (x, y, z + storey * 0.5), 'lamp_dim' if lit else ('glass' if roll < keep * 0.5 else 'paint_dark'))
    top = 0.3 + floors * storey
    for i in range(6):
        base = Vector((rng.uniform(-half, half), rng.uniform(-half, half), top))
        beam('Rebar', base, base + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0.3, 0.9))), 0.04, 'rust')
    for i in range(14):
        a = rng.uniform(0, TAU)
        r = rng.uniform(half * 1.05, half * 1.45)
        s = rng.uniform(0.12, 0.34)
        box('Fallen', (s * 1.5, s, s * 0.6), (r * math.cos(a), r * math.sin(a), 0.1 + s * 0.2), rng.choice(['concrete', 'concrete_dark', 'rust']), rot=(rng.random(), rng.random(), rng.random() * 3))
    for obj in bpy.context.scene.objects:
        if not obj.get('stage') and 'variant' not in obj.keys():
            obj['variant'] = 0
    return {'group': 'scenery', 'cells': 3, 'variants': 1}


def highrise_a():
    return _highrise(101, 7, 2.3)


def highrise_b():
    return _highrise(102, 10, 2.0)


def highrise_c():
    return _highrise(103, 5, 2.6)


def flag():
    """The rally point marker: a pole with a pennant in the faction colour."""
    cyl('FlagFoot', 0.09, 0.05, (0, 0, 0.025), 'hull_dark', verts=12)
    pipe('FlagPole', (0, 0, 0.03), (0, 0, 1.0), 0.02, 'chrome')
    ball('FlagTop', 0.035, (0, 0, 1.0), 'gold')
    for i in range(4):
        box('Pennant', (0.11, 0.02, 0.26 - i * 0.045), (0.07 + i * 0.105, -0.02 * math.sin(i * 1.3), 0.82), 'team', rot=(0, 0, 0.25 * math.sin(i * 1.3 + 0.6)))
    for obj in bpy.context.scene.objects:
        if not obj.get('stage'):
            obj['variant'] = 0
    return {'group': 'scenery', 'cells': 1, 'variants': 1}


BUILDERS = {
    'flag': flag,
    'tree': tree, 'bush': bush, 'rubble': scenery_rubble, 'barrier': barrier, 'ruin': ruin,
    'highrise_a': highrise_a, 'highrise_b': highrise_b, 'highrise_c': highrise_c,
    'core': core, 'generator': generator, 'depot': depot, 'data_center': data_center,
    'fabricator': fabricator, 'tower': tower, 'lab': lab,
    'worker': worker, 'scout': scout, 'sentinel': sentinel, 'disruptor': disruptor, 'walker': walker,
    'warden': warden, 'mortar': mortar, 'phantom': phantom,
    'metal': metal, 'data': data,
}


def build(kind):
    # Units lift their feet, so ground dirt tied to height would crawl over them as they walk.
    unit = kind in ('worker', 'scout', 'sentinel', 'disruptor', 'walker', 'warden', 'mortar', 'phantom')
    kit.splash_on = not unit and kind != 'flag'
    kit.panel_size = 0.2 if unit else (0.3 if kind in ('metal', 'data', 'flag', 'barrier', 'rubble', 'ruin') else 0.75)
    return BUILDERS[kind]()
