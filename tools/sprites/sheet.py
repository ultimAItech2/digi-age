"""Contact sheet of one frame per kind, for reviewing the models: python3 tools/sprites/sheet.py [label]."""
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'builds' / 'sprites'
want = sys.argv[1] if len(sys.argv) > 1 else None
tiles = []
for folder in sorted(SRC.iterdir()):
    meta_path = folder / 'meta.json'
    if not meta_path.exists():
        continue
    meta = json.loads(meta_path.read_text())
    pick = None
    for index, label in enumerate(meta['labels']):
        path = folder / ('%03d.png' % index)
        if path.exists() and (want is None or label == want or (want is None)):
            pick = path
            if want is None and label in ('complete', 'full', '0_idle_0', 'v0'):
                break
    if pick:
        tiles.append((meta['kind'], Image.open(pick).convert('RGBA')))
cell_w = max(t[1].width for t in tiles)
cell_h = max(t[1].height for t in tiles)
cols = 4
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new('RGBA', (cols * cell_w, rows * cell_h), (96, 110, 84, 255))
for i, (_kind, image) in enumerate(tiles):
    x = (i % cols) * cell_w + (cell_w - image.width) // 2
    y = (i // cols) * cell_h + (cell_h - image.height)
    sheet.alpha_composite(image, (x, y))
out = ROOT / 'builds' / 'sprites' / 'sheet.png'
sheet.convert('RGB').save(out)
print(out, sheet.size)
