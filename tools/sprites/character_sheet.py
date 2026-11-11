"""Character sheet: every troop, building and resource deposit with its stats and
its stages over time, cut from the packed atlases.

    python3 tools/sprites/character_sheet.py        -> docs/images/character-sheet.png
"""
import ast
import re
import textwrap
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ATLAS = ROOT / 'assets' / 'sprites' / 'rendered'
FONTS = ROOT / 'assets' / 'fonts'
OUT = ROOT / 'docs' / 'images' / 'character-sheet.png'

BG = (14, 19, 26)
PANEL = (22, 30, 40)
LINE = (48, 62, 78)
TEXT = (226, 234, 240)
MUTED = (140, 156, 170)
ACCENT = (87, 235, 213)
GOLD = (233, 190, 106)
TEAM = np.array([0x57, 0xeb, 0xd5], dtype=np.float32) / 255.0
AGES = ['Awakening Age', 'Network Age', 'Singularity Age']
WIDTH = 3200
MARGIN = 60
INFO_W = 560
FACING = 1          # atlas row shown for units: walking toward the lower right of the screen


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size)


TITLE = font('Cinzel.ttf', 64)
HEAD = font('Cinzel.ttf', 40)
NAME = font('Rajdhani-SemiBold.ttf', 40)
BODY = font('Rajdhani-SemiBold.ttf', 25)
SMALL = font('Rajdhani-SemiBold.ttf', 22)
MONO = font('JetBrainsMono.ttf', 20)


def atlas_data():
    """KINDS from the generated GDScript (its dictionary literal is also valid Python)."""
    source = (ROOT / 'scripts' / 'sprite_atlas_data.gd').read_text()
    body = source[source.index('const KINDS = ') + len('const KINDS = '):]
    return ast.literal_eval(body.replace('false', 'False').replace('true', 'True'))


def catalog():
    """Units and buildings from data/catalog.tres."""
    source = (ROOT / 'data' / 'catalog.tres').read_text()
    result = {}
    for section in ('units', 'buildings'):
        start = source.index('\n%s = {' % section)
        block = source[start:source.index('\n}', start)]
        for line in block.splitlines():
            match = re.match(r'"(\w+)": (\{.*\}),?$', line.strip())
            if match:
                entry = re.sub(r'Vector3\(([^)]*)\)', r'(\1)', match.group(2))
                entry = re.sub(r'\btrue\b', 'True', re.sub(r'\bfalse\b', 'False', entry))
                result[match.group(1)] = dict(ast.literal_eval(entry), section=section)
    return result


def frame(kind, entry, cache, column, row):
    """One atlas cell with the masked parts painted in the faction colour, as the game draws it."""
    if kind not in cache:
        colour = np.asarray(Image.open(ATLAS / ('%s.png' % kind)).convert('RGBA'), dtype=np.float32) / 255.0
        mask_path = ATLAS / ('%s_mask.png' % kind)
        if mask_path.exists():
            mask = np.asarray(Image.open(mask_path).convert('L'), dtype=np.float32)[..., None] / 255.0
            # The same recolour as assets/shaders/sprite_card.gdshader, in linear light.
            linear = np.where(colour[..., :3] <= 0.04045, colour[..., :3] / 12.92, ((colour[..., :3] + 0.055) / 1.055) ** 2.4)
            team = np.where(TEAM <= 0.04045, TEAM / 12.92, ((TEAM + 0.055) / 1.055) ** 2.4)
            luma = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
            hue = team * 0.85 + team.dot(luma) * 0.15
            painted = np.clip(hue * (linear * luma).sum(-1, keepdims=True) * 2.1, 0.0, 1.0)
            linear = linear * (1.0 - mask) + painted * mask
            colour[..., :3] = np.where(linear <= 0.0031308, linear * 12.92, 1.055 * linear ** (1 / 2.4) - 0.055)
        cache[kind] = Image.fromarray((colour * 255.0 + 0.5).astype(np.uint8), 'RGBA')
    w, h = entry['frame']
    return cache[kind].crop((column * w, row * h, column * w + w, row * h + h))


def state(kind, entry, cache, name):
    index = entry['states'].index(name)
    return frame(kind, entry, cache, index % entry['cols'], index // entry['cols'])


def scaled(image, factor):
    return image.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.LANCZOS)


def cost_text(cost):
    parts = [('%d metal' % cost[0]) if cost[0] else '', ('%d energy' % cost[1]) if cost[1] else '', ('%d data' % cost[2]) if cost[2] else '']
    return ' · '.join(p for p in parts if p)


def info_lines(item):
    lines = [('Cost', cost_text(item['cost'])), ('Built in' if item['section'] == 'buildings' else 'Trained in', '%d s' % item['time']), ('Integrity', '%d' % item['hp'])]
    if 'damage' in item:
        lines.append(('Attack', '%d damage · range %s · every %s s' % (item['damage'], item['range'], item['cooldown'])))
    if 'speed' in item:
        lines.append(('Speed', '%s cells/s · vision %d' % (item['speed'], item['vision'])))
    else:
        lines.append(('Footprint', '%d × %d cells · vision %d' % (item['radius'] * 2 + 1, item['radius'] * 2 + 1, item['vision'])))
    return lines


class Sheet:
    def __init__(self):
        self.rows = []      # (height, draw function taking (image, draw, y))

    def add(self, height, paint):
        self.rows.append((height, paint))

    def render(self):
        total = MARGIN + sum(h for h, _ in self.rows) + MARGIN
        image = Image.new('RGBA', (WIDTH, total), BG + (255,))
        draw = ImageDraw.Draw(image)
        y = MARGIN
        for height, paint in self.rows:
            paint(image, draw, y)
            y += height
        return image


def heading(sheet, title, note):
    def paint(_image, draw, y):
        draw.text((MARGIN, y + 30), title, font=HEAD, fill=GOLD)
        draw.text((MARGIN + draw.textlength(title, font=HEAD) + 30, y + 46), note, font=BODY, fill=MUTED)
        draw.line((MARGIN, y + 92, WIDTH - MARGIN, y + 92), fill=LINE, width=2)
    sheet.add(120, paint)


def entry_row(sheet, title, tag, description, stats, groups):
    """One kind: an info panel, then groups of (group label, [(caption, image)])."""
    # Trim every tile to the shared opaque box, then shrink the row if it is still too wide.
    boxes = [image.getbbox() for _, tiles in groups for _, image in tiles if image.getbbox()]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    groups = [(label, [(caption, image.crop(box)) for caption, image in tiles]) for label, tiles in groups]
    count = sum(len(tiles) for _, tiles in groups)
    room = WIDTH - MARGIN - (MARGIN + INFO_W) - 30 - 30 * (len(groups) - 1) - 14 * count
    used = sum(image.width for _, tiles in groups for _, image in tiles)
    if used > room:
        groups = [(label, [(caption, scaled(image, room / used)) for caption, image in tiles]) for label, tiles in groups]
    tile_h = max(image.height for _, tiles in groups for _, image in tiles)
    height = max(tile_h + 110, 330)

    def paint(image, draw, y):
        draw.rounded_rectangle((MARGIN, y, WIDTH - MARGIN, y + height - 24), 10, fill=PANEL, outline=LINE)
        x = MARGIN + 28
        draw.text((x, y + 18), title, font=NAME, fill=TEXT)
        draw.text((x, y + 64), tag, font=SMALL, fill=ACCENT)
        ty = y + 98
        for label, value in stats:
            draw.text((x, ty), label, font=SMALL, fill=MUTED)
            draw.text((x + 120, ty), value, font=SMALL, fill=TEXT)
            ty += 28
        ty += 8
        for line in textwrap.wrap(description, 44):
            draw.text((x, ty), line, font=SMALL, fill=MUTED)
            ty += 26
        gx = MARGIN + INFO_W
        space = WIDTH - MARGIN - gx - 20
        count = sum(len(tiles) for _, tiles in groups)
        used = sum(im.width for _, tiles in groups for _, im in tiles)
        gap = max(14, min(40, (space - used - 30 * (len(groups) - 1)) // max(1, count)))
        for label, tiles in groups:
            start = gx
            for caption, tile in tiles:
                image.alpha_composite(tile, (gx, y + 52 + tile_h - tile.height))
                tw = draw.textlength(caption, font=MONO)
                draw.text((gx + (tile.width - tw) / 2, y + 58 + tile_h), caption, font=MONO, fill=MUTED)
                gx += tile.width + gap
            draw.text((start + 4, y + 16), label.upper(), font=SMALL, fill=GOLD)
            draw.line((start, y + 44, gx - gap, y + 44), fill=LINE, width=2)
            gx += 30
    sheet.add(height, paint)


def main():
    kinds = atlas_data()
    items = catalog()
    cache = {}
    sheet = Sheet()

    def title(_image, draw, y):
        draw.text((MARGIN, y), 'DIGITAL AGE', font=TITLE, fill=TEXT)
        draw.text((MARGIN, y + 84), 'Character sheet: troops, buildings and resource deposits, with every stage they pass through. Shown in the Origin Collective colour.', font=BODY, fill=MUTED)
    sheet.add(140, title)

    heading(sheet, 'Troops', 'left to right: standing, a walk cycle, firing, and the collapse when destroyed')
    for kind in ('worker', 'scout', 'sentinel', 'disruptor', 'walker', 'warden', 'mortar', 'phantom'):
        entry, item = kinds[kind], items[kind]
        factor = 1.25 * 96.0 / entry['ppu']
        anims = entry['anims']

        def cells(anim, picks, entry=entry, kind=kind, factor=factor, anims=anims):
            first = anims[anim][0]
            return [('%d' % (i + 1), scaled(frame(kind, entry, cache, first + i, FACING), factor)) for i in picks]
        groups = [('Idle', cells('idle', [0])), ('Move', cells('move', [0, 2, 4, 6])), ('Attack', cells('attack', [0, 2, 4])), ('Destroyed', cells('death', [0, 1, 2, 3, 4, 5]))]
        entry_row(sheet, item['name'], 'Unit · available from the %s' % AGES[item['age']], item['description'], info_lines(item), groups)

    heading(sheet, 'Buildings', 'left to right: three construction stages, the finished building, two frames of its idle loop, and its wreck')
    for kind in ('core', 'generator', 'depot', 'data_center', 'lab', 'fabricator', 'tower'):
        entry, item = kinds[kind], items[kind]
        factor = 0.62 if entry['cells'] >= 5 else 0.8

        def tile(name, caption, entry=entry, kind=kind, factor=factor):
            return (caption, scaled(state(kind, entry, cache, name), factor))
        groups = [('Under construction', [tile('stage0', 'foundation'), tile('stage1', 'frame'), tile('stage2', 'shell')]),
                  ('Operational', [tile('complete', 'complete'), tile('idle2', 'idle loop'), tile('idle4', 'idle loop')]),
                  ('Destroyed', [tile('wreck', 'wreck')])]
        entry_row(sheet, item['name'], 'Building · available from the %s' % AGES[item['age']], item['description'], info_lines(item), groups)

    heading(sheet, 'Resource deposits', 'they thin out as Workers harvest them')
    deposits = {'metal': ('Salvage heap', 'Metal', 'Scrap left by the old world. Workers carry it to the Core or a Salvage Depot.'),
                'data': ('Data archive', 'Data', 'A buried archive. Workers retrieve data from it for research and advanced units.')}
    for kind, (name, resource, description) in deposits.items():
        entry = kinds[kind]
        tiles = [(caption, scaled(state(kind, entry, cache, name_), 1.6)) for name_, caption in (('full', 'full'), ('half', 'below 60%'), ('low', 'below 25%'))]
        entry_row(sheet, name, 'Deposit · yields %s' % resource, description, [('Gathered by', 'Workers'), ('Dropped at', 'Core or Salvage Depot')], [('Depletion', tiles)])

    image = sheet.render().convert('RGB')
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUT, optimize=True)
    print(OUT, image.size)


if __name__ == '__main__':
    main()
