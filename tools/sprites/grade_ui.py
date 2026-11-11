"""Grade the rendered HUD plates onto the palette (tools/sprites).

    python3 tools/sprites/grade_ui.py

Scales each plate in builds/ui_plates/ so its mean luminance lands on the
target for that state, tints it toward the HUD's blue-black, and writes
assets/ui/frames/<name>.png. The targets keep every text colour of the HUD at
4.5:1 or better against the plate (tests/ui_production_test.gd checks it).
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'builds' / 'ui_plates'
OUT = ROOT / 'assets' / 'ui' / 'frames'
# Mean sRGB level (0..255) each plate is graded to.
TARGETS = {'panel': 30, 'dock': 31, 'button': 38, 'button_hover': 52, 'button_pressed': 30, 'button_disabled': 22, 'slot': 20}
TINT = (0.86, 0.98, 1.16)      # toward the palette's blue-black


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, target in TARGETS.items():
        image = Image.open(SRC / (name + '.png')).convert('RGB')
        pixels = list(image.getdata())
        mean = sum(0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in pixels) / len(pixels)
        gain = target / max(1.0, mean)
        graded = [tuple(min(255, int(c * gain * t + 0.5)) for c, t in zip(p, TINT)) for p in pixels]
        out = Image.new('RGB', image.size)
        out.putdata(graded)
        out.save(OUT / (name + '.png'), optimize=True)
        print('%s: mean %.0f -> %d' % (name, mean, target))


main()
