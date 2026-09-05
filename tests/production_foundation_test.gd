extends SceneTree

var failures: int = 0
var checks: int = 0

func expect(condition: bool, title: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + title)
	else:
		failures += 1
		push_error("FAIL: " + title)

func run() -> void:
	var catalog: DAMissionCatalog = load("res://data/missions/catalog.tres")
	var definitions = catalog.all_definitions()
	expect(definitions.size() == 8, "campaign contains eight authored missions")
	expect(catalog.get_definition("first_signal") != null and catalog.get_definition("inheritance") != null, "campaign lookup resolves opening and finale")
	var factions = [load("res://data/factions/origin.tres"), load("res://data/factions/foundry.tres"), load("res://data/factions/lattice.tres")]
	expect(factions.all(func(f): return f is DAFactionDefinition), "origin and rival faction resources load")
	expect(factions[1].faction_id != factions[2].faction_id and factions[1].ai_profile != factions[2].ai_profile, "rival factions have distinct identity")

	var sim = DASimulation.new()
	var mission = DAMissionController.new()
	var definition: DAMissionDefinition = catalog.get_definition("first_signal")
	sim.reset_from_mission(definition)
	mission.setup(sim, definition)
	var completed_ids: Array[String] = []
	mission.objective_completed.connect(func(id): completed_ids.append(id))
	mission.tick(0.1)
	expect(completed_ids.has("restore_power"), "mission objective progression detects authored generator")
	sim.resources[0].z = 120.0
	mission.tick(0.1)
	expect(completed_ids.has("recover_archive"), "gather objective reads deterministic data state")
	mission.tick(120.0)
	expect(mission.mission_won and not mission.active, "required objectives complete the mission")

	var campaign = DACampaignProgress.new()
	campaign.mark_complete("first_signal")
	campaign.unlock("salvage_rights")
	var save_error = DASaveGame.save_slot("production_foundation", sim, mission, campaign, {"test": true})
	expect(save_error == "", "versioned save commits atomically")
	var before = sim.resources[0]
	sim.resources[0] = Vector3.ZERO
	var load_error = DASaveGame.load_slot("production_foundation", sim, mission, campaign)
	expect(load_error == "" and sim.resources[0] == before, "save/load round trip restores simulation")
	expect(campaign.completed_missions.has("first_signal") and campaign.unlocked_missions.has("salvage_rights"), "save/load restores campaign unlocks")
	var corrupt = FileAccess.open(DASaveGame.path_for("production_corrupt"), FileAccess.WRITE)
	corrupt.store_buffer(var_to_bytes({"schema_version": 999}))
	corrupt.close()
	expect(DASaveGame.load_slot("production_corrupt", sim, mission, campaign) != "", "unsupported save versions are rejected")

	var settings = DASettingsService.new()
	settings.values.profile = "low"
	settings.values.subtitles = true
	settings.set_binding("save", KEY_F6)
	expect(settings.save_settings() == "", "settings persist independently")
	var settings_loaded = DASettingsService.new()
	settings_loaded.load_settings()
	expect(settings_loaded.values.profile == "low" and settings_loaded.values.subtitles and settings_loaded.binding("save", KEY_F5) == KEY_F6, "settings round trip preserves accessibility preferences and bindings")

	var platform = DAPlatformService.new()
	platform.initialize()
	platform.unlock("test_achievement")
	expect(platform.achievements.get("test_achievement", false), "Steam adapter records achievements offline")
	var audio = DAAudio.new()
	var events: Array[String] = []
	audio.event_requested.connect(func(kind, _payload): events.append(kind))
	audio.play("order_issued")
	audio.speak("briefing_01", "")
	expect(events == ["order_issued", "dialogue_started"] and audio.events_seen.size() == 2, "semantic audio events work without assets")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	audio.free()
	quit(1 if failures > 0 else 0)

func _initialize() -> void:
	call_deferred("run")
