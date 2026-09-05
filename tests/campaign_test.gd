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
	expect(definitions.size() == 8, "eight missions load")
	var maps: Dictionary = {}
	for definition in definitions:
		expect(definition.events.size() > 0, definition.mission_id + " has authored events")
		expect(definition.dialogue_entries.size() > 0, definition.mission_id + " has dialogue")
		var map = load("res://data/maps/" + definition.map_id + ".tres") as DAMapDefinition
		expect(map != null and map.starting_units.size() > 0, definition.mission_id + " map loads with units")
		maps[definition.map_id] = true
	expect(maps.size() == 8, "each mission uses a distinct map")

	var first: DAMissionDefinition = catalog.get_definition("first_signal")
	var sim = DASimulation.new()
	sim.reset_from_mission(first)
	expect(sim.active_map_id == "silent_grid" and sim.bases[0] == Vector2(12, 36), "first signal rebuilds silent grid")
	expect(sim.active_factions.size() == 2 and sim.active_factions[1].ai_profile == "industrial", "foundry profile attached")
	var mission = DAMissionController.new()
	mission.setup(sim, first)
	var fired: Array[String] = []
	mission.event_emitted.connect(func(id): fired.append(id))
	mission.tick(0.5)
	expect(fired.has("opening"), "opening dialogue event fires")
	expect(mission.completed.get("restore_power", false), "starting generator completes restore power")
	sim.resources[0].z = 120
	mission.tick(0.1)
	expect(mission.completed.get("recover_archive", false), "gather objective completes from data")
	var save_error = DASaveGame.save_slot("campaign_event", sim, mission, DACampaignProgress.new())
	expect(save_error == "", "mid-mission save commits")
	var restored = DAMissionController.new()
	restored.setup(sim, first)
	expect(DASaveGame.load_slot("campaign_event", sim, restored, DACampaignProgress.new()) == "", "mid-mission load")
	expect(restored.fired_events.get("opening", false) and restored.completed.get("recover_archive", false), "fired events and objectives restore")

	mission.tick(120.0)
	expect(mission.mission_won, "first signal required objectives complete the mission")

	var salvage: DAMissionDefinition = catalog.get_definition("salvage_rights")
	sim = DASimulation.new()
	sim.reset_from_mission(salvage)
	expect(sim.active_map_id == "salvage_basin", "salvage rights uses basin map")
	expect(sim.entities.values().filter(func(e): return e.owner == 1 and e.kind == "tower").size() > 0, "foundry outpost is prebuilt")
	var opponent = DAOpponent.new(sim, 1)
	opponent.refresh_from_faction()
	expect(int(opponent.profile.get("worker_target", 0)) == 20, "industrial AI profile applied")

	var blackout: DAMissionDefinition = catalog.get_definition("blackout")
	sim = DASimulation.new()
	sim.reset_from_mission(blackout)
	var gens = sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == "generator").size()
	expect(gens == 0, "blackout starts without player generators")

	var campaign = DACampaignProgress.new()
	campaign.mark_complete("first_signal")
	campaign.unlock("salvage_rights")
	expect(DASaveGame.save_campaign(campaign) == "", "campaign progress file writes")
	var loaded = DACampaignProgress.new()
	expect(DASaveGame.load_campaign(loaded) == "" and loaded.unlocked_missions.has("salvage_rights"), "campaign progress reloads at boot path")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _initialize() -> void:
	call_deferred("run")
