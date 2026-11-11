#!/usr/bin/env python3
"""Author rough and high ground for every map in data/maps.

Rough ground is the rubble apron around each cluster of blocked cells. High
ground is a pair of plateaus placed point-symmetrically about the map centre,
so neither start is favoured. Both keep clear of the starts, the deposits and
the roads. The result is written into each map's .tres as rough_cells and
high_cells; re-running replaces them.
"""
import math
import pathlib
import re

SIZE = 72
ROOT = pathlib.Path(__file__).resolve().parent.parent / "data" / "maps"


def vectors(text: str, key: str, cls: str) -> list[tuple[float, float]]:
    match = re.search(rf"^{key} = (.*)$", text, re.M)
    if not match:
        return []
    return [(float(a), float(b)) for a, b in re.findall(rf"{cls}\(([-\d.]+), ([-\d.]+)\)", match.group(1))]


def author(path: pathlib.Path) -> tuple[int, int]:
    text = path.read_text()
    starts = vectors(text, "starts", "Vector2")
    blocked = {(int(x), int(y)) for x, y in vectors(text, "obstacle_cells", "Vector2i")}
    nodes = [(float(a), float(b)) for a, b in re.findall(r'"pos": Vector2\(([-\d.]+), ([-\d.]+)\)', re.search(r"^resource_nodes = (.*)$", text, re.M).group(1))]
    roads = set()
    for axis, low, top in re.findall(r'\{"axis": "(\w)", "min": (\d+), "max": (\d+)\}', text):
        for i in range(SIZE):
            for j in range(int(low), int(top) + 1):
                roads.add((i, j) if axis == "y" else (j, i))

    def clear(cell, start_gap, node_gap):
        x, y = cell
        if not (2 <= x < SIZE - 2 and 2 <= y < SIZE - 2) or cell in blocked or cell in roads:
            return False
        if any(math.dist(cell, s) < start_gap for s in starts):
            return False
        return not any(math.dist(cell, n) < node_gap for n in nodes)

    # Rough: within two cells of a blocked cell, thinned by a fixed pattern so the edge is ragged.
    rough = set()
    for bx, by in blocked:
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                cell = (bx + dx, by + dy)
                if max(abs(dx), abs(dy)) == 2 and (cell[0] * 7 + cell[1] * 13) % 3 == 0:
                    continue
                if clear(cell, 11.0, 3.5):
                    rough.add(cell)

    # High: the open spot nearest to a point a third of the way from the first start
    # to the centre, pushed sideways; then its mirror image through the centre.
    high = set()
    if len(starts) >= 2:
        centre = (SIZE - 1) / 2.0
        sx, sy = starts[0]
        ax, ay = centre - sx, centre - sy
        length = math.hypot(ax, ay) or 1.0
        px, py = -ay / length, ax / length
        want = (sx + ax * 0.55 + px * 13.0, sy + ay * 0.55 + py * 13.0)
        radius = 3
        best = None
        for x in range(6, SIZE - 6):
            for y in range(6, SIZE - 6):
                disc = [(x + dx, y + dy) for dx in range(-radius, radius + 1) for dy in range(-radius, radius + 1) if dx * dx + dy * dy <= radius * radius + 1]
                mirror = [(SIZE - 1 - cx, SIZE - 1 - cy) for cx, cy in disc]
                if all(clear(c, 12.0, 4.0) and c not in rough for c in disc + mirror):
                    gap = math.dist((x, y), want)
                    if best is None or gap < best[0]:
                        best = (gap, disc, mirror)
        if best:
            high.update(best[1])
            high.update(best[2])

    def line(key, cells):
        return f"{key} = Array[Vector2i]([" + ", ".join(f"Vector2i({x}, {y})" for x, y in sorted(cells)) + "])"

    text = re.sub(r"^(rough_cells|high_cells) = .*\n", "", text, flags=re.M).rstrip("\n")
    text += "\n" + line("rough_cells", rough) + "\n" + line("high_cells", high) + "\n"
    path.write_text(text)
    return len(rough), len(high)


if __name__ == "__main__":
    for path in sorted(ROOT.glob("*.tres")):
        rough, high = author(path)
        print(f"{path.stem}: {rough} rough cells, {high} high cells")
