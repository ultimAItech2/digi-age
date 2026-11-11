class_name DACatalog
extends Resource
## Balance definitions. Costs are [metal, energy, data]; positions use map cells.
@export var units: Dictionary = {}
@export var buildings: Dictionary = {}
@export var ages: Array[String] = ["AWAKENING", "NETWORK", "SINGULARITY"]
@export var age_costs: Array[Vector3] = [Vector3(400, 250, 120), Vector3(750, 550, 260)]
@export var age_times: Array[float] = [45.0, 65.0]
## Research tree: branch order, upgrade definitions keyed by id, and the shared
## per-level cost and duration schedule (an entry may override with "costs"/"times").
@export var tech_branches: Array[String] = ["resources", "buildings", "military"]
@export var tech: Dictionary = {}
@export var tech_costs: Array[Vector3] = [Vector3(120, 80, 30), Vector3(200, 140, 60), Vector3(320, 220, 110), Vector3(480, 340, 180), Vector3(700, 500, 280)]
@export var tech_times: Array[float] = [25.0, 35.0, 45.0, 55.0, 70.0]
@export var starting_resources: Vector3 = Vector3(600, 350, 0)
@export var energy_per_second: float = 3.0
@export var gather_per_second: float = 3.0
@export var population_limit: int = 100
@export var tick_seconds: float = 0.1
## Damage multipliers by attacker kind: against a unit kind, or against "building".
## Keys are a unit kind, an armour class ("light", "infantry", "armored", "heavy") or "building".
@export var counters: Dictionary = {"sentinel": {"armored": 2.0}, "disruptor": {"heavy": 3.0}, "walker": {"building": 3.0}, "mortar": {"building": 1.5}, "phantom": {"light": 1.5}}
## One ability per unit kind. "targeted" abilities are aimed at a point.
@export var abilities: Dictionary = {
	"scout": {"id": "sweep", "name": "Sensor sweep", "icon": "sensors", "cooldown": 45.0, "targeted": true, "reach": 40.0, "radius": 10.0, "duration": 8.0, "description": "Reveals a 10-cell circle within 40 cells for 8 seconds, cloaked units included."},
	"sentinel": {"id": "overdrive", "name": "Overdrive", "icon": "weapons", "cooldown": 30.0, "targeted": false, "duration": 6.0, "rate": 1.5, "description": "Fires 50% faster for 6 seconds."},
	"disruptor": {"id": "emp", "name": "EMP shell", "icon": "energy", "cooldown": 40.0, "targeted": true, "reach": 7.0, "radius": 2.5, "duration": 3.0, "description": "Stuns enemy units in a 2.5-cell circle for 3 seconds. No effect on buildings."},
	"walker": {"id": "brace", "name": "Brace", "icon": "fortify", "cooldown": 3.0, "targeted": false, "range": 3.0, "siege": 1.5, "description": "Locks the legs: cannot move, range +3, +50% damage to buildings. Use again to release."}
}
## Ground effects: speed on roads and rough ground, path cost of rough ground, bonus on high ground.
@export var terrain: Dictionary = {"road_speed": 1.25, "rough_speed": 0.65, "rough_weight": 1.6, "high_vision": 2.0, "high_range": 1.0}
const ARMOR_NAMES = {"light": "light units", "infantry": "infantry", "armored": "armoured units", "heavy": "heavy units", "building": "buildings"}
const TECH_MAX_LEVEL: int = 5
## Every effect key the simulation understands; a tree entry may only use these.
const TECH_EFFECTS = ["gather_metal", "gather_data", "generator_output", "cargo", "worker_speed", "construction_rate", "building_health", "tower_damage", "tower_range", "production_rate", "unit_damage", "armor", "unit_speed", "unit_vision", "unit_range"]

func definition(kind: String) -> Dictionary:
	return units.get(kind, buildings.get(kind, {}))

func damage_bonus(attacker: String, target: String, target_building: bool) -> float:
	var table: Dictionary = counters.get(attacker, {})
	if table.is_empty():
		return 1.0
	if table.has(target):
		return float(table[target])
	if target_building:
		return float(table.get("building", 1.0))
	return float(table.get(str(units.get(target, {}).get("armor", "")), 1.0))

## What a unit is strong against, for tooltips: "×2 vs Disruptor".
func counter_text(attacker: String) -> String:
	var parts: Array = []
	for target in counters.get(attacker, {}):
		var label: String = str(ARMOR_NAMES.get(target, definition(target).get("name", str(target).capitalize())))
		parts.append("×%s vs %s" % [str(counters[attacker][target]).trim_suffix(".0"), label])
	return ", ".join(parts)

## Age required to research a level: 1-2 Awakening, 3-4 Network, 5 Singularity.
static func tech_age_for_level(level: int) -> int:
	return clampi((level - 1) / 2, 0, 2)

func tech_cost(id: String, level: int) -> Vector3:
	var entry: Dictionary = tech.get(id, {})
	var costs: Array = entry.get("costs", tech_costs)
	return costs[clampi(level - 1, 0, costs.size() - 1)]

func tech_time(id: String, level: int) -> float:
	var entry: Dictionary = tech.get(id, {})
	var times: Array = entry.get("times", tech_times)
	return float(times[clampi(level - 1, 0, times.size() - 1)])

func tech_ids(branch: String) -> Array:
	var ids: Array = []
	for id in tech:
		if tech[id].get("branch", "") == branch:
			ids.append(id)
	return ids
