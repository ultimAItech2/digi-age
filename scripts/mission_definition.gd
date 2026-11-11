class_name DAMissionDefinition
extends Resource
## Authored mission contract. Runtime state is owned by MissionController.
@export var mission_id: String = "first_signal"
@export var title: String = "First Signal"
@export_multiline var briefing: String = "Restore the first signal and establish a foothold."
@export var map_id: String = "silent_grid"
@export var player_faction_id: String = "origin"
@export var enemy_faction_id: String = "foundry"
@export var difficulty: String = "normal"
@export var objectives: Array[Dictionary] = []
@export var starting_resources: Array[Vector3] = [Vector3(600, 350, 0), Vector3(600, 350, 0)]
@export var technology_floor: Array[int] = [0, 0]
@export var technology_ceiling: Array[int] = [2, 2]
@export var time_limit: float = 0.0
## Skirmish: both sides open with the same force, ignoring the map's authored units and structures.
@export var symmetric_start: bool = false
## Skirmish: the player takes the map's second start.
@export var swap_sides: bool = false
@export var dialogue_entries: Array[Dictionary] = []
@export var events: Array[Dictionary] = []
@export var checkpoint_ids: Array[String] = ["opening", "first_signal", "counterattack"]
@export var victory_text: String = "The Origin signal survives."
@export var defeat_text: String = "The signal is lost."

func objective(id: String) -> Dictionary:
	for item in objectives:
		if item.get("id", "") == id:
			return item
	return {}

func dialogue_entry(entry_id: String) -> Dictionary:
	for item in dialogue_entries:
		if item.get("id", "") == entry_id:
			return item
	return {}
