class_name DACampaignProgress
extends Resource
## Versioned player-facing campaign state. Never put hardware settings here.
const CURRENT_VERSION: int = 1
@export var schema_version: int = CURRENT_VERSION
@export var completed_missions: Array[String] = []
@export var optional_objectives: Dictionary = {}
@export var unlocked_missions: Array[String] = ["first_signal"]
@export var selected_difficulty: String = "normal"
@export var current_mission: String = ""
@export var last_checkpoint: String = ""

func mark_complete(mission_id: String, optional: Array[String] = []) -> void:
	if not completed_missions.has(mission_id):
		completed_missions.append(mission_id)
	for objective_id in optional:
		optional_objectives[mission_id + ":" + objective_id] = true

func unlock(mission_id: String) -> void:
	if not unlocked_missions.has(mission_id):
		unlocked_missions.append(mission_id)
