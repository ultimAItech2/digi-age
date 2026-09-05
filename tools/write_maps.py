#!/usr/bin/env python3
"""Author the eight 72x72 campaign maps as Godot .tres resources."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / "data" / "maps"


def vec2(x: float, y: float) -> str:
    return f"Vector2({x}, {y})"


def vec2i(x: int, y: int) -> str:
    return f"Vector2i({x}, {y})"


def dict_gd(d: dict) -> str:
    parts = []
    for key, value in d.items():
        parts.append(f'"{key}": {gd(value)}')
    return "{" + ", ".join(parts) + "}"


def gd(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return str(value)
    if isinstance(value, str):
        return f'"{value}"'
    if isinstance(value, tuple) and len(value) == 2:
        if all(isinstance(v, int) for v in value):
            return vec2i(*value)
        return vec2(*value)
    if isinstance(value, dict):
        return dict_gd(value)
    if isinstance(value, list):
        return "[" + ", ".join(gd(v) for v in value) + "]"
    raise TypeError(value)


def default_units(include_generator: bool = True, extra: list | None = None) -> list:
    units = []
    for side in (0, 1):
        units.append({"side": side, "kind": "core", "offset": (0.0, 0.0), "complete": True})
        if include_generator:
            units.append({"side": side, "kind": "generator", "offset": (0.0, -7.0), "complete": True})
        for i in range(5):
            units.append({"side": side, "kind": "worker", "offset": (float(-3 + i), 5.0), "complete": True})
        units.append({"side": side, "kind": "scout", "offset": (0.0, 8.0), "complete": True})
    if extra:
        units.extend(extra)
    return units


def default_ruins() -> list:
    ruins = []
    for x in (3, 68):
        for y in (6, 15, 57, 65):
            ruins.append({"kind": "ruin", "pos": (float(x), float(y))})
    return ruins


def ridge_block(xs: range, ys: list[int]) -> list[tuple[int, int]]:
    return [(x, y) for x in xs for y in ys]


def silent_resources() -> list:
    nodes = []
    bases = [(12.0, 36.0), (59.0, 36.0)]
    for side, b in enumerate(bases):
        sign = 1.0 if side == 0 else -1.0
        for offset in ((-5.0, -11.0), (8.0, 10.0), (8.0, -14.0)):
            nodes.append({"kind": "metal", "pos": (b[0] + offset[0] * sign, b[1] + offset[1]), "amount": 6500.0})
        nodes.append({"kind": "data", "pos": (b[0] + 13.0 * sign, b[1] - 4.0), "amount": 4000.0})
    for p in ((36.0, 8.0), (36.0, 35.0), (36.0, 63.0)):
        nodes.append({"kind": "data", "pos": p, "amount": 7000.0})
    for p in ((24.0, 28.0), (47.0, 28.0), (24.0, 44.0), (47.0, 44.0)):
        nodes.append({"kind": "metal", "pos": p, "amount": 5000.0})
    return nodes


def write_map(spec: dict) -> None:
    fields = []
    order = [
        "map_id",
        "display_name",
        "width",
        "height",
        "camera_min",
        "camera_max",
        "starts",
        "obstacle_cells",
        "resource_nodes",
        "starting_units",
        "prebuilt",
        "scenery",
        "road_bands",
    ]
    defaults = {
        "width": 72,
        "height": 72,
        "camera_min": (1.0, 1.0),
        "camera_max": (70.0, 70.0),
        "starts": [(12.0, 36.0), (59.0, 36.0)],
        "obstacle_cells": [],
        "resource_nodes": [],
        "starting_units": default_units(),
        "prebuilt": [],
        "scenery": default_ruins(),
        "road_bands": [{"axis": "y", "min": 32, "max": 39}, {"axis": "x", "min": 33, "max": 38}],
    }
    data = dict(defaults)
    data.update(spec)
    for key in order:
        fields.append(f"{key} = {gd(data[key])}")
    text = (
        '[gd_resource type="Resource" script_class="DAMapDefinition" load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://scripts/map_definition.gd" id="1"]\n'
        "[resource]\n"
        'script = ExtResource("1")\n'
        + "\n".join(fields)
        + "\n"
    )
    path = MAPS / f"{data['map_id']}.tres"
    path.write_text(text)
    print(f"wrote {path.relative_to(ROOT)}")


def main() -> None:
    MAPS.mkdir(parents=True, exist_ok=True)

    write_map(
        {
            "map_id": "silent_grid",
            "display_name": "The Silent Grid",
            "obstacle_cells": ridge_block(range(29, 43), [17, 18, 19, 51, 52, 53]),
            "resource_nodes": silent_resources(),
        }
    )

    salvage = silent_resources()
    salvage.append({"kind": "metal", "pos": (36.0, 20.0), "amount": 8000.0})
    salvage.append({"kind": "metal", "pos": (36.0, 52.0), "amount": 8000.0})
    write_map(
        {
            "map_id": "salvage_basin",
            "display_name": "Salvage Basin",
            "starts": [(10.0, 28.0), (61.0, 44.0)],
            "obstacle_cells": ridge_block(range(30, 42), [12, 13, 14])
            + ridge_block(range(30, 42), [57, 58, 59])
            + ridge_block(range(18, 24), [34, 35, 36]),
            "resource_nodes": salvage,
            "prebuilt": [
                {"side": 1, "kind": "depot", "pos": (48.0, 36.0), "complete": True},
                {"side": 1, "kind": "tower", "pos": (50.0, 34.0), "complete": True},
                {"side": 1, "kind": "tower", "pos": (50.0, 38.0), "complete": True},
            ],
            "scenery": default_ruins()
            + [{"kind": "ruin", "pos": (36.0, 18.0)}, {"kind": "ruin", "pos": (36.0, 54.0)}],
            "road_bands": [{"axis": "y", "min": 33, "max": 38}, {"axis": "x", "min": 20, "max": 24}],
        }
    )

    write_map(
        {
            "map_id": "relay_road",
            "display_name": "The Relay Road",
            "starts": [(12.0, 18.0), (59.0, 54.0)],
            "obstacle_cells": ridge_block(range(8, 28), [30, 31, 32])
            + ridge_block(range(44, 64), [38, 39, 40])
            + [(36, y) for y in range(4, 16)]
            + [(36, y) for y in range(56, 68)],
            "resource_nodes": silent_resources()
            + [
                {"kind": "data", "pos": (36.0, 22.0), "amount": 5000.0},
                {"kind": "data", "pos": (36.0, 48.0), "amount": 5000.0},
            ],
            "scenery": default_ruins() + [{"kind": "ruin", "pos": (36.0, 12.0)}, {"kind": "ruin", "pos": (36.0, 60.0)}],
            "road_bands": [{"axis": "x", "min": 34, "max": 37}, {"axis": "y", "min": 16, "max": 20}],
        }
    )

    write_map(
        {
            "map_id": "transfer_corridor",
            "display_name": "Transfer Corridor",
            "starts": [(10.0, 36.0), (62.0, 36.0)],
            "obstacle_cells": ridge_block(range(20, 52), [10, 11, 12, 13])
            + ridge_block(range(20, 52), [58, 59, 60, 61])
            + [(36, y) for y in list(range(14, 24)) + list(range(48, 58))],
            "resource_nodes": silent_resources()
            + [{"kind": "data", "pos": (36.0, 36.0), "amount": 9000.0}],
            "prebuilt": [
                {"side": 0, "kind": "depot", "pos": (22.0, 36.0), "complete": True},
            ],
            "road_bands": [{"axis": "y", "min": 34, "max": 38}],
        }
    )

    write_map(
        {
            "map_id": "blackout_grid",
            "display_name": "Blackout Grid",
            "starts": [(14.0, 40.0), (57.0, 32.0)],
            "obstacle_cells": [(x, 24) for x in range(20, 50) if x % 3 != 0]
            + [(x, 48) for x in range(20, 50) if x % 4 != 0]
            + [(28, y) for y in range(18, 28)]
            + [(44, y) for y in range(44, 54)],
            "resource_nodes": silent_resources(),
            "starting_units": default_units(include_generator=False),
            "scenery": default_ruins()
            + [{"kind": "ruin", "pos": (28.0, 36.0)}, {"kind": "ruin", "pos": (44.0, 36.0)}],
            "road_bands": [{"axis": "x", "min": 30, "max": 41}],
        }
    )

    write_map(
        {
            "map_id": "foundry_fortress",
            "display_name": "The Foundry Fortress",
            "starts": [(11.0, 48.0), (60.0, 20.0)],
            "obstacle_cells": ridge_block(range(32, 48), [28, 29, 30, 31])
            + ridge_block(range(24, 30), [16, 17, 18])
            + [(52, y) for y in range(14, 26)],
            "resource_nodes": silent_resources()
            + [{"kind": "metal", "pos": (54.0, 28.0), "amount": 9000.0}],
            "prebuilt": [
                {"side": 1, "kind": "fabricator", "pos": (56.0, 16.0), "complete": True},
                {"side": 1, "kind": "generator", "pos": (63.0, 14.0), "complete": True},
                {"side": 1, "kind": "generator", "pos": (63.0, 26.0), "complete": True},
                {"side": 1, "kind": "data_center", "pos": (54.0, 24.0), "complete": True},
                {"side": 1, "kind": "tower", "pos": (52.0, 18.0), "complete": True},
                {"side": 1, "kind": "tower", "pos": (52.0, 24.0), "complete": True},
                {"side": 1, "kind": "depot", "pos": (58.0, 28.0), "complete": True},
            ],
            "road_bands": [{"axis": "y", "min": 46, "max": 50}, {"axis": "x", "min": 50, "max": 54}],
        }
    )

    write_map(
        {
            "map_id": "lattice_web",
            "display_name": "Lattice Web",
            "starts": [(16.0, 16.0), (55.0, 55.0)],
            "obstacle_cells": [(20 + i, 20 + i) for i in range(12)]
            + [(40 + i, 20 + i) for i in range(10)]
            + [(20 + i, 40 + i) for i in range(10)]
            + [(36, y) for y in range(8, 16)]
            + [(36, y) for y in range(56, 64)],
            "resource_nodes": silent_resources()
            + [
                {"kind": "data", "pos": (20.0, 52.0), "amount": 6000.0},
                {"kind": "data", "pos": (52.0, 20.0), "amount": 6000.0},
            ],
            "prebuilt": [
                {"side": 1, "kind": "tower", "pos": (48.0, 48.0), "complete": True},
                {"side": 1, "kind": "data_center", "pos": (52.0, 50.0), "complete": True},
            ],
            "road_bands": [{"axis": "x", "min": 34, "max": 37}, {"axis": "y", "min": 34, "max": 37}],
        }
    )

    write_map(
        {
            "map_id": "inheritance_core",
            "display_name": "Inheritance Core",
            "starts": [(12.0, 20.0), (59.0, 52.0)],
            "obstacle_cells": ridge_block(range(26, 46), [8, 9])
            + ridge_block(range(26, 46), [62, 63])
            + [(8, y) for y in range(30, 42)]
            + [(63, y) for y in range(30, 42)],
            "resource_nodes": silent_resources()
            + [{"kind": "data", "pos": (36.0, 36.0), "amount": 10000.0}],
            "starting_units": default_units(
                extra=[
                    {"side": 0, "kind": "sentinel", "offset": (2.0, 10.0), "complete": True},
                    {"side": 0, "kind": "sentinel", "offset": (-2.0, 10.0), "complete": True},
                    {"side": 1, "kind": "sentinel", "offset": (2.0, 10.0), "complete": True},
                    {"side": 1, "kind": "sentinel", "offset": (-2.0, 10.0), "complete": True},
                ]
            ),
            "prebuilt": [
                {"side": 1, "kind": "fabricator", "pos": (56.0, 46.0), "complete": True},
                {"side": 1, "kind": "tower", "pos": (54.0, 50.0), "complete": True},
            ],
            "road_bands": [{"axis": "x", "min": 33, "max": 38}, {"axis": "y", "min": 33, "max": 38}],
        }
    )


if __name__ == "__main__":
    main()
