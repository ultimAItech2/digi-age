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
	var error = sim.restore_state(state.simulation)
	if error != "":
		return error
	error = mission.restore_state(state.mission)
	if error != "":
		return error
	apply_campaign(campaign, state.campaign)
	return ""

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
