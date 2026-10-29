class_name DASaveGame
extends RefCounted
## Versioned, atomic local persistence. Steam Auto-Cloud can sync this directory.
const VERSION: int = 1
const SAVE_DIR: String = "user://saves"
const SLOT_COUNT: int = 3

static func path_for(slot: String) -> String:
	return SAVE_DIR + "/" + slot + ".save"

static func save_slot(slot: String, sim: DASimulation, mission: DAMissionController, campaign: DACampaignProgress, metadata: Dictionary = {}) -> String:
	if slot.is_empty() or sim == null or mission == null:
		return "Cannot save an incomplete game state."
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var state = {"schema_version": VERSION, "slot": slot, "saved_at": Time.get_datetime_string_from_system(true), "simulation": sim.serialize_state(), "mission": mission.serialize_state(), "campaign": campaign_resource(campaign), "metadata": metadata.duplicate(true)}
	var temp = path_for(slot) + ".tmp"
	var file = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return "Unable to open the save location."
	file.store_buffer(var_to_bytes(state))
	file.flush()
	file.close()
	if FileAccess.file_exists(path_for(slot)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(slot) + ".bak"))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path_for(slot)), ProjectSettings.globalize_path(path_for(slot) + ".bak"))
	var error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path_for(slot)))
	return "" if error == OK else "Unable to commit the save safely."

static func load_slot(slot: String, sim: DASimulation, mission: DAMissionController, campaign: DACampaignProgress) -> String:
	var path = path_for(slot)
	if not FileAccess.file_exists(path):
		return "No save exists in this slot."
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Unable to read the save."
	var state = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	if not state is Dictionary or int(state.get("schema_version", -1)) != VERSION:
		return "This save is from an unsupported version."
	if not state.has_all(["simulation", "mission", "campaign"]):
		return "This save is incomplete."
	if not state.simulation is Dictionary or not state.mission is Dictionary or not state.campaign is Dictionary:
		return "This save is malformed."
	if state.mission.get("mission_id", "") != (mission.definition.mission_id if mission.definition else ""):
		return "Save belongs to a different mission. Select that mission before loading."
	if state.simulation.get("map_id", "") != mission.definition.map_id:
		return "Save map does not match this mission."
	var error = validate_state(state, sim.catalog)
	if error != "": return error
	# Validate on disposable instances before mutating the live session.
	var candidate_sim = DASimulation.new()
	var candidate_mission = DAMissionController.new()
	candidate_mission.setup(candidate_sim, mission.definition)
	error = candidate_sim.restore_state(state.simulation)
	if error != "":
		return error
	error = candidate_mission.restore_state(state.mission)
	if error != "":
		return error
	sim.restore_state(state.simulation)
	mission.restore_state(state.mission)
	apply_campaign(campaign, state.campaign)
	return ""

static func validate_state(state: Dictionary, catalog: Resource) -> String:
	var s: Dictionary = state.simulation
	for key in ["elapsed", "ticks", "next_id", "winner"]:
		if not is_number(s.get(key)): return "Simulation save has invalid counters."
	for key in ["ai_overrides"]:
		if not s.get(key, {}) is Dictionary: return "Simulation save is malformed."
	for key in ["stats", "destroyed_counts"]:
		if not s.get(key) is Array or s[key].size()!=2: return "Simulation save is incomplete."
		for entry in s[key]:
			if not entry is Dictionary: return "Simulation save is malformed."
	for entry in s.stats:
		if not is_number(entry.get("kills")) or not is_number(entry.get("gathered")): return "Simulation statistics are invalid."
	if not s.get("faction_ids") is Array: return "Save factions are incomplete."
	for faction in s.faction_ids:
		if not faction is String or not ResourceLoader.exists("res://data/factions/"+faction+".tres"): return "Save faction is unavailable."
	for key in ["resources", "ages", "upgrades", "visible", "explored"]:
		if not s.get(key) is Array or s[key].size() != 2: return "Simulation save is incomplete."
	for i in 2:
		if not s.resources[i] is Vector3 or not s.visible[i] is Dictionary or not s.explored[i] is Dictionary: return "Simulation save is malformed."
		if not s.ages[i] is int or s.ages[i] < 0 or s.ages[i] > 2 or not s.upgrades[i] is int or s.upgrades[i] < 0 or s.upgrades[i] > 2: return "Simulation save has invalid progression."
	if not s.get("entities") is Dictionary: return "Simulation save is incomplete."
	for e in s.entities.values():
		if not e is Dictionary or not e.has_all(["id","kind","owner","pos","hp","max_hp","building","complete"]): return "Save contains an incomplete entity."
		if not e.id is int or not e.owner is int or not e.building is bool or not e.complete is bool or not is_number(e.hp) or not is_number(e.max_hp) or e.max_hp<=0: return "Save contains invalid entity properties."
		if not e.pos is Vector2 or not e.pos.is_finite(): return "Save contains an invalid position."
		if not e.kind is String or (not catalog.units.has(e.kind) and not catalog.buildings.has(e.kind) and e.kind not in ["metal","data"]): return "Save contains an unknown entity."
		if e.owner == -1:
			if e.kind not in ["metal","data"] or not e.pos is Vector2 or not e.get("amount") is float: return "Save contains an invalid resource."
			continue
		if not e.has_all(["build_left","order","target","destination","path","cargo","queue","research","research_left","rally"]): return "Save contains an incomplete entity."
		for key in ["build_left","cargo","research_left","cooldown"]:
			if not is_number(e.get(key)): return "Save contains an invalid entity counter."
		if not e.order is String or not e.research is String or not e.rally is Vector2: return "Save contains invalid orders."
		if not e.pos is Vector2 or not e.destination is Vector2 or not e.path is Array or not e.queue is Array or not e.owner is int or e.owner < -1 or e.owner > 1: return "Save contains an invalid entity."
		if e.building != catalog.buildings.has(e.kind): return "Save contains an invalid building."
		for item in e.queue:
			if not item is Dictionary or not catalog.units.has(item.get("kind", "")) or not item.get("left") is float: return "Save contains an invalid production queue."
	if not state.mission.get("objective_state") is Dictionary or not state.mission.get("completed") is Dictionary: return "Mission save is incomplete."
	if not is_number(state.mission.get("elapsed")) or not state.mission.get("active") is bool or not state.mission.get("mission_won") is bool or not state.mission.get("fired_events", {}) is Dictionary: return "Mission save is malformed."
	for key in ["completed_missions", "unlocked_missions"]:
		if not state.campaign.get(key) is Array: return "Campaign save is incomplete."
		for entry in state.campaign[key]:
			if not entry is String: return "Campaign save is malformed."
	if not state.campaign.get("optional_objectives", {}) is Dictionary: return "Campaign save is malformed."
	var map_id = str(s.get("map_id", "silent_grid"))
	if not ResourceLoader.exists("res://data/maps/"+map_id+".tres"): return "Save map is unavailable."
	return ""

static func is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func campaign_resource(campaign: DACampaignProgress) -> Dictionary:
	return {"schema_version": campaign.schema_version, "completed_missions": campaign.completed_missions.duplicate(), "optional_objectives": campaign.optional_objectives.duplicate(true), "unlocked_missions": campaign.unlocked_missions.duplicate(), "selected_difficulty": campaign.selected_difficulty, "current_mission": campaign.current_mission, "last_checkpoint": campaign.last_checkpoint}

const CAMPAIGN_PATH: String = "user://campaign.save"

static func save_campaign(campaign: DACampaignProgress) -> String:
	if campaign == null:
		return "Cannot save campaign progress."
	var file = FileAccess.open(CAMPAIGN_PATH, FileAccess.WRITE)
	if file == null:
		return "Unable to save campaign progress."
	file.store_buffer(var_to_bytes({"schema_version": VERSION, "campaign": campaign_resource(campaign)}))
	file.flush()
	file.close()
	return ""

static func load_campaign(campaign: DACampaignProgress) -> String:
	if not FileAccess.file_exists(CAMPAIGN_PATH):
		return ""
	var file = FileAccess.open(CAMPAIGN_PATH, FileAccess.READ)
	if file == null:
		return "Unable to read campaign progress."
	var state = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	if not state is Dictionary or int(state.get("schema_version", -1)) != VERSION or not state.has("campaign"):
		return "Campaign progress is unsupported."
	apply_campaign(campaign, state.campaign)
	return ""

static func apply_campaign(campaign: DACampaignProgress, state: Dictionary) -> void:
	campaign.schema_version = int(state.get("schema_version", VERSION))
	campaign.completed_missions = Array(state.get("completed_missions", []))
	campaign.optional_objectives = state.get("optional_objectives", {}).duplicate(true)
	campaign.unlocked_missions = Array(state.get("unlocked_missions", ["first_signal"]))
	campaign.selected_difficulty = str(state.get("selected_difficulty", "normal"))
	campaign.current_mission = str(state.get("current_mission", ""))
	campaign.last_checkpoint = str(state.get("last_checkpoint", ""))
