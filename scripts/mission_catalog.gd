class_name DAMissionCatalog
extends Resource
@export var missions: Array[String] = []
## Not part of the campaign's order or its unlocks.
@export var tutorial: String = "res://data/missions/tutorial.tres"

func all_definitions() -> Array[DAMissionDefinition]:
	var result: Array[DAMissionDefinition] = []
	for path in missions:
		if ResourceLoader.exists(path):
			result.append(load(path) as DAMissionDefinition)
	return result

func get_definition(mission_id: String) -> DAMissionDefinition:
	if mission_id == "tutorial":
		return load(tutorial) as DAMissionDefinition if ResourceLoader.exists(tutorial) else null
	for definition in all_definitions():
		if definition.mission_id == mission_id:
			return definition
	return null
