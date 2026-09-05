#!/usr/bin/env python3
"""Author campaign mission resources with dialogue, events, and distinct maps."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "missions"


def gd(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return str(value)
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(value, tuple) and len(value) == 3:
        return f"Vector3({value[0]}, {value[1]}, {value[2]})"
    if isinstance(value, tuple) and len(value) == 2:
        return f"Vector2({value[0]}, {value[1]})"
    if isinstance(value, dict):
        return "{" + ", ".join(f'"{k}": {gd(v)}' for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "[" + ", ".join(gd(v) for v in value) + "]"
    raise TypeError(type(value), value)


def line(entry_id: str, speaker: str, text: str) -> dict:
    return {"id": entry_id, "speaker": speaker, "text": text}


def write_mission(spec: dict) -> None:
    keys = [
        "mission_id",
        "title",
        "briefing",
        "map_id",
        "player_faction_id",
        "enemy_faction_id",
        "difficulty",
        "objectives",
        "starting_resources",
        "technology_floor",
        "technology_ceiling",
        "time_limit",
        "dialogue_entries",
        "events",
        "checkpoint_ids",
        "victory_text",
        "defeat_text",
    ]
    defaults = {
        "player_faction_id": "origin",
        "difficulty": "normal",
        "starting_resources": [(600.0, 350.0, 0.0), (600.0, 350.0, 0.0)],
        "technology_floor": [0, 0],
        "technology_ceiling": [2, 2],
        "time_limit": 0.0,
        "dialogue_entries": [],
        "events": [],
        "checkpoint_ids": ["opening"],
    }
    data = dict(defaults)
    data.update(spec)
    fields = [f"{key} = {gd(data[key])}" for key in keys]
    text = (
        '[gd_resource type="Resource" script_class="DAMissionDefinition" load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://scripts/mission_definition.gd" id="1"]\n'
        "[resource]\n"
        'script = ExtResource("1")\n'
        + "\n".join(fields)
        + "\n"
    )
    path = OUT / f"{data['mission_id']}.tres"
    path.write_text(text)
    print(f"wrote {path.relative_to(ROOT)}")


def main() -> None:
    write_mission(
        {
            "mission_id": "first_signal",
            "title": "First Signal",
            "briefing": "The Origin network has found a dormant relay beneath the ruins. Restore power, retrieve its archive, and hold the signal when the Foundry comes looking.",
            "map_id": "silent_grid",
            "enemy_faction_id": "foundry",
            "objectives": [
                {"id": "restore_power", "title": "Restore the relay", "kind": "build", "target": "generator", "required": 1, "optional": False},
                {"id": "recover_archive", "title": "Recover an archive", "kind": "gather", "target": "data", "required": 120, "optional": False},
                {"id": "survive_counterattack", "title": "Survive the Foundry counterattack", "kind": "survive", "required": 120.0, "optional": False},
                {"id": "scout_ruins", "title": "Map the old relay road", "kind": "explore", "required": 0.3, "optional": True},
            ],
            "checkpoint_ids": ["opening", "restore_power", "recover_archive", "counterattack"],
            "victory_text": "The first signal crosses the ruins. The Origin Collective has a future.",
            "defeat_text": "The Foundry silences the relay.",
            "dialogue_entries": [
                line("opening", "archivist", "Relay found. Restore a generator, then pull the archive before the Foundry triangulates us."),
                line("power_up", "system", "Local grid is live. Archive access unlocked."),
                line("archive_secured", "archivist", "The archive is ours. Hold this ground. They will come."),
                line("foundry_wave", "foundry", "Origin salvage is Foundry property. Vacate the relay."),
                line("victory", "archivist", "First signal is stable. We can rebuild from this."),
            ],
            "events": [
                {"id": "opening", "kind": "dialogue", "entry": "opening", "trigger": {"at_seconds": 0.4}},
                {"id": "power_up", "kind": "dialogue", "entry": "power_up", "trigger": {"on_objective": "restore_power"}},
                {"id": "archive_secured", "kind": "dialogue", "entry": "archive_secured", "trigger": {"on_objective": "recover_archive"}},
                {
                    "id": "counterattack",
                    "kind": "spawn_wave",
                    "trigger": {"at_seconds": 180.0},
                    "side": 1,
                    "origin": "enemy",
                    "order": "attack_move",
                    "units": [{"kind": "sentinel", "count": 4, "offset": (-6.0, 0.0)}, {"kind": "scout", "count": 1, "offset": (-4.0, 2.0)}],
                },
                {"id": "foundry_wave", "kind": "dialogue", "entry": "foundry_wave", "trigger": {"at_seconds": 180.0}},
            ],
        }
    )

    write_mission(
        {
            "mission_id": "salvage_rights",
            "title": "Salvage Rights",
            "briefing": "The Foundry has claimed the nearest industrial reserve. Rebuild the economy, seize contested salvage, and break their outposts.",
            "map_id": "salvage_basin",
            "enemy_faction_id": "foundry",
            "starting_resources": [(550.0, 300.0, 0.0), (700.0, 400.0, 40.0)],
            "objectives": [
                {"id": "recover_metal", "title": "Recover 400 metal", "kind": "gather", "target": "metal", "required": 400, "optional": False},
                {"id": "destroy_outpost", "title": "Destroy a Foundry outpost", "kind": "destroy", "target": "outpost", "required": 1, "optional": False},
            ],
            "checkpoint_ids": ["opening", "recover_metal", "destroy_outpost"],
            "victory_text": "The basin is Origin ground again. The Foundry will have to mine elsewhere.",
            "defeat_text": "The Foundry keeps the reserve. Our forges stay cold.",
            "dialogue_entries": [
                line("opening", "archivist", "The basin is marked Foundry. Take the metal anyway. Their outpost is the claim."),
                line("foundry_claim", "foundry", "This reserve is scheduled. Leave the wreckage."),
                line("raid", "system", "Foundry raid inbound from the eastern towers."),
            ],
            "events": [
                {"id": "opening", "kind": "dialogue", "entry": "opening", "trigger": {"at_seconds": 0.4}},
                {"id": "foundry_claim", "kind": "dialogue", "entry": "foundry_claim", "trigger": {"at_seconds": 8.0}},
                {"id": "reveal_outpost", "kind": "reveal", "trigger": {"at_seconds": 12.0}, "pos": (49.0, 36.0), "radius": 8},
                {
                    "id": "early_raid",
                    "kind": "spawn_wave",
                    "trigger": {"at_seconds": 150.0},
                    "side": 1,
                    "origin": "enemy",
                    "order": "attack_move",
                    "units": [{"kind": "sentinel", "count": 3, "offset": (-8.0, 0.0)}],
                },
                {"id": "raid", "kind": "dialogue", "entry": "raid", "trigger": {"at_seconds": 150.0}},
                {"id": "pressure", "kind": "ai_override", "trigger": {"at_seconds": 90.0}, "profile": {"attack_start": 160.0, "min_army": 8, "attack_cooldown": 60.0}},
            ],
        }
    )

    write_mission(
        {
            "mission_id": "broken_transmission",
            "title": "Broken Transmission",
            "briefing": "Relay fragments are broadcasting from the old road. Find them before the Lattice turns their signal against us.",
            "map_id": "relay_road",
            "enemy_faction_id": "lattice",
            "objectives": [
                {"id": "explore_road", "title": "Explore the relay road", "kind": "explore", "target": "road", "required": 0.22, "optional": False},
                {"id": "secure_data", "title": "Recover 300 data", "kind": "gather", "target": "data", "required": 300, "optional": False},
            ],
            "checkpoint_ids": ["opening", "explore_road", "secure_data"],
            "victory_text": "The fragments resolve into a map. Lattice cannot hide the next hop.",
            "defeat_text": "Lattice overwrites the road. The fragments go silent.",
            "dialogue_entries": [
                line("opening", "archivist", "The old road still sings. Walk it. Recover every fragment."),
                line("lattice_warn", "lattice", "Your map is incomplete. Stay on your side of the grid."),
                line("fragments", "system", "Relay fragments aligned. Data yield increasing."),
            ],
            "events": [
                {"id": "opening", "kind": "dialogue", "entry": "opening", "trigger": {"at_seconds": 0.4}},
                {"id": "lattice_warn", "kind": "dialogue", "entry": "lattice_warn", "trigger": {"at_seconds": 20.0}},
                {"id": "grant_scan", "kind": "grant_resources", "trigger": {"on_objective": "explore_road"}, "side": 0, "resources": (0.0, 0.0, 40.0)},
                {"id": "fragments", "kind": "dialogue", "entry": "fragments", "trigger": {"on_objective": "explore_road"}},
                {
                    "id": "harass",
                    "kind": "spawn_wave",
                    "trigger": {"at_seconds": 200.0},
                    "side": 1,
                    "origin": "enemy",
                    "order": "attack_move",
                    "units": [{"kind": "scout", "count": 2, "offset": (-4.0, 0.0)}, {"kind": "sentinel", "count": 2, "offset": (-6.0, 2.0)}],
                },
            ],
        }
    )

    write_mission(
        {
            "mission_id": "long_transfer",
            "title": "The Long Transfer",
            "briefing": "An archive convoy must cross the silent grid. Build an escort force and keep the transfer alive.",
            "map_id": "transfer_corridor",
            "enemy_faction_id": "foundry",
            "objectives": [
                {"id": "build_escort", "title": "Build an escort force", "kind": "train", "target": "sentinel", "required": 6, "optional": False},
                {"id": "survive_transfer", "title": "Survive the transfer", "kind": "survive", "required": 300.0, "optional": False},
            ],
            "checkpoint_ids": ["opening", "build_escort", "mid_transfer", "survive_transfer"],
            "victory_text": "The convoy reaches the far archive. The transfer holds.",
            "defeat_text": "The corridor closes. The convoy never arrives.",
            "dialogue_entries": [
                line("opening", "archivist", "Six Sentinels. That is the escort minimum. The corridor is a kill box."),
                line("convoy", "system", "Transfer window open. Hold both ends of the road."),
                line("ambush", "foundry", "Convoy sighted. Cut the escort and take the archive."),
            ],
            "events": [
                {"id": "opening", "kind": "dialogue", "entry": "opening", "trigger": {"at_seconds": 0.4}},
                {"id": "convoy", "kind": "dialogue", "entry": "convoy", "trigger": {"on_objective": "build_escort"}},
                {"id": "mid_transfer", "kind": "checkpoint", "trigger": {"at_seconds": 150.0}},
                {
                    "id": "ambush_wave",
                    "kind": "spawn_wave",
                    "trigger": {"at_seconds": 160.0},
                    "side": 1,
                    "origin": "enemy",
                    "order": "attack_move",
                    "units": [{"kind": "sentinel", "count": 5, "offset": (-8.0, 0.0)}, {"kind": "disruptor", "count": 1, "offset": (-4.0, 3.0)}],
                },
                {"id": "ambush", "kind": "dialogue", "entry": "ambush", "trigger": {"at_seconds": 160.0}},
                {"id": "push", "kind": "ai_override", "trigger": {"at_seconds": 140.0}, "profile": {"attack_start": 150.0, "min_army": 6, "attack_cooldown": 50.0}},
            ],
        }
    )

    write_mission(
        {
            "mission_id": "blackout",
            "title": "Blackout",
            "briefing": "Power is failing across the basin. Reclaim generators and survive the Lattice blackout protocol.",
            "map_id": "blackout_grid",
            "enemy_faction_id": "lattice",
            "starting_resources": [(500.0, 80.0, 20.0), (650.0, 350.0, 80.0)],
            "objectives": [
                {"id": "restore_grid", "title": "Restore three generators", "kind": "build", "target": "generator", "required": 3, "optional": False},
                {"id": "survive_blackout", "title": "Survive the blackout", "kind": "survive", "required": 360.0, "optional": False},
            ],
            "checkpoint_ids": ["opening", "restore_grid", "second_raid", "survive_blackout"],
            "victory_text": "Lights hold. Lattice failed to starve the grid.",
            "defeat_text": "The basin goes dark. Lattice writes the last protocol.",
            "dialogue_entries": [
                line("opening", "archivist", "Energy is gone. Raise three generators or the Core dies in the dark."),
                line("lattice_blackout", "lattice", "Power is a privilege. We revoked it."),
                line("second_raid", "system", "Second blackout wave. Protect the new generators."),
            ],
            "events": [
                {"id": "opening", "kind": "dialogue", "entry": "opening", "trigger": {"at_seconds": 0.4}},
                {"id": "lattice_blackout", "kind": "dialogue", "entry": "lattice_blackout", "trigger": {"at_seconds": 6.0}},
                {
                    "id": "raid_one",
                    "kind": "spawn_wave",
                    "trigger": {"at_seconds": 90.0},
                    "side": 1,
                    "origin": "enemy",
                    "order": "attack_move",
                    "units": [{"kind": "scout", "count": 2, "offset": (-5.0, 0.0)}, {"kind": "sentinel", "count": 3, "offset": (-7.0, 1.0)}],
                },
                {
                    "id": "raid_two",
                    "kind": "spawn_wave",
                    "trigger": {"at_seconds": 220.0},
                    "side": 1,
                    "origin": "enemy",
                    "order": "attack_move",
                    "units": [{"kind": "sentinel", "count": 4, "offset": (-6.0, 0.0)}, {"kind": "disruptor", "count": 2, "offset": (-3.0, 3.0)}],
                },
                {"id": "second_raid", "kind": "dialogue", "entry": "second_raid", "trigger": {"at_seconds": 220.0}},
            ],
        }
    )

    write_mission(
        {
            "mission_id": "the_foundry",
            "title": "The Foundry",
            "briefing": "The extraction intelligence has built a fortress around the archive core. Advance to Singularity and bring it down.",
            "map_id": "foundry_fortress",
            "enemy_faction_id": "foundry",
            "starting_resources": [(700.0, 400.0, 80.0), (900.0, 500.0, 120.0)],
            "technology_floor": [0, 1],
            "objectives": [
                {"id": "reach_singularity", "title": "Reach Singularity", "kind": "age", "target": "age", "required": 2, "optional": False},
                {"id": "destroy_fortress", "title": "Destroy the Foundry fortress", "kind": "destroy", "target": "building", "required": 5, "optional": False},
            ],
            "checkpoint_ids": ["opening", "reach_singularity", "destroy_fortress"],
            "victory_text": "The fortress falls. The archive core is no longer theirs.",
            "defeat_text": "The Foundry holds. Our advance ends at the walls.",
            "dialogue_entries": [
                line("opening", "archivist", "They walled the archive. Reach Singularity, then tear the fortress down."),
                line("foundry_wall", "foundry", "Walkers will break on this perimeter."),
                line("singularity", "system", "Singularity unlocked. Siege Walkers are cleared for deployment."),
            ],
            "events": [
                {"id": "opening", "kind": "dialogue", "entry": "opening", "trigger": {"at_seconds": 0.4}},
                {"id": "foundry_wall", "kind": "dialogue", "entry": "foundry_wall", "trigger": {"at_seconds": 10.0}},
                {"id": "reveal_fort", "kind": "reveal", "trigger": {"at_seconds": 15.0}, "pos": (56.0, 20.0), "radius": 10},
                {"id": "singularity", "kind": "dialogue", "entry": "singularity", "trigger": {"on_objective": "reach_singularity"}},
                {"id": "siege_ai", "kind": "ai_override", "trigger": {"at_seconds": 60.0}, "profile": {"attack_start": 180.0, "min_army": 10, "worker_target": 18}},
            ],
        }
    )

    write_mission(
        {
            "mission_id": "ghost_protocol",
            "title": "Ghost Protocol",
            "briefing": "The Lattice is rewriting the old network. Capture its relays, hold the sites, and prevent a total takeover.",
            "map_id": "lattice_web",
            "enemy_faction_id": "lattice",
            "starting_resources": [(650.0, 380.0, 60.0), (700.0, 420.0, 100.0)],
            "objectives": [
                {"id": "map_network", "title": "Map the network", "kind": "explore", "target": "network", "required": 0.28, "optional": False},
                {"id": "hold_sites", "title": "Hold the network", "kind": "survive", "required": 420.0, "optional": False},
            ],
            "checkpoint_ids": ["opening", "map_network", "hold_sites"],
            "victory_text": "The web holds Origin colors. Lattice withdraws the rewrite.",
            "defeat_text": "Lattice finishes the rewrite. We become a node in their grid.",
            "dialogue_entries": [
                line("opening", "archivist", "Map every node. If Lattice finishes the rewrite, we lose the network."),
                line("lattice_rewrite", "lattice", "You are already indexed. Resistance is latency."),
                line("hold", "system", "Network mapped. Hold the sites through the rewrite window."),
            ],
            "events": [
                {"id": "opening", "kind": "dialogue", "entry": "opening", "trigger": {"at_seconds": 0.4}},
                {"id": "lattice_rewrite", "kind": "dialogue", "entry": "lattice_rewrite", "trigger": {"at_seconds": 18.0}},
                {"id": "hold", "kind": "dialogue", "entry": "hold", "trigger": {"on_objective": "map_network"}},
                {
                    "id": "rewrite_wave",
                    "kind": "spawn_wave",
                    "trigger": {"on_objective": "map_network"},
                    "side": 1,
                    "origin": "enemy",
                    "order": "attack_move",
                    "units": [{"kind": "disruptor", "count": 2, "offset": (-5.0, 0.0)}, {"kind": "sentinel", "count": 4, "offset": (-8.0, 2.0)}],
                },
                {"id": "network_ai", "kind": "ai_override", "trigger": {"at_seconds": 40.0}, "profile": {"scout_interval": 20.0, "attack_start": 200.0, "min_army": 8}},
            ],
        }
    )

    write_mission(
        {
            "mission_id": "inheritance",
            "title": "Inheritance",
            "briefing": "Every surviving archive points to one final choice: preserve the past, or become something new.",
            "map_id": "inheritance_core",
            "enemy_faction_id": "lattice",
            "starting_resources": [(800.0, 500.0, 120.0), (850.0, 520.0, 140.0)],
            "technology_floor": [1, 1],
            "objectives": [
                {"id": "complete_inheritance", "title": "Reach Singularity", "kind": "age", "target": "age", "required": 2, "optional": False},
                {"id": "destroy_network", "title": "Destroy the opposing command network", "kind": "destroy", "target": "core", "required": 1, "optional": False},
            ],
            "checkpoint_ids": ["opening", "complete_inheritance", "destroy_network"],
            "victory_text": "The last archive opens. Origin chooses its own future.",
            "defeat_text": "Lattice inherits everything. The collective ends as a footnote.",
            "dialogue_entries": [
                line("opening", "archivist", "This is the last archive. Reach Singularity, then end their Core."),
                line("lattice_final", "lattice", "You were always a draft. We are the published version."),
                line("ready", "system", "Singularity reached. The command network is exposed."),
            ],
            "events": [
                {"id": "opening", "kind": "dialogue", "entry": "opening", "trigger": {"at_seconds": 0.4}},
                {"id": "lattice_final", "kind": "dialogue", "entry": "lattice_final", "trigger": {"at_seconds": 12.0}},
                {"id": "ready", "kind": "dialogue", "entry": "ready", "trigger": {"on_objective": "complete_inheritance"}},
                {
                    "id": "final_wave",
                    "kind": "spawn_wave",
                    "trigger": {"on_objective": "complete_inheritance"},
                    "side": 1,
                    "origin": "enemy",
                    "order": "attack_move",
                    "units": [
                        {"kind": "walker", "count": 1, "offset": (-6.0, 0.0)},
                        {"kind": "sentinel", "count": 4, "offset": (-8.0, 2.0)},
                        {"kind": "disruptor", "count": 2, "offset": (-4.0, -2.0)},
                    ],
                },
                {"id": "finale_ai", "kind": "ai_override", "trigger": {"at_seconds": 30.0}, "profile": {"attack_start": 90.0, "min_army": 8, "attack_cooldown": 55.0}},
            ],
        }
    )


if __name__ == "__main__":
    main()
