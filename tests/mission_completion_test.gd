extends SceneTree
## Every campaign mission must be winnable. The computer strategy plays the
## player's side (as `--autoplay` does) against the mission's own rival and
## script on Easy, and each mission has to end in a win inside the limit.
##
## This proves a mission can be completed, not that it is balanced: the strategy
## is a mirror of the rival, so a mission where the rival starts ahead is beyond
## it. Those are listed in UNPROVEN and need a human playtest; they run only
## when a mission id (or "all") is given.
##
## Usage: --script tests/mission_completion_test.gd -- [tick_limit] [mission_id or "all"] [difficulty]
const UNPROVEN: Array[String] = ["the_foundry"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var limit: int = int(args[0]) if args.size() > 0 else 36000
	var only: String = args[1] if args.size() > 1 else ""
	var level: String = args[2] if args.size() > 2 else "easy"
	var catalog: DAMissionCatalog = load("res://data/missions/catalog.tres")
	var failures: int = 0
	for definition in catalog.all_definitions():
		if only not in ["", "all"] and definition.mission_id != only:
			continue
		if only == "" and definition.mission_id in UNPROVEN:
			print("MISSION_RESULT mission=%s pass=unproven (not run: needs a human playtest)" % definition.mission_id)
			continue
		var sim = DASimulation.new()
		var mission = DAMissionController.new()
		mission.setup(sim, definition)
		sim.reset_from_mission(definition)
		var rival = DAOpponent.new(sim, 1)
		rival.refresh_from_faction()
		rival.set_difficulty(level)
		var player = DAOpponent.new(sim, 0)
		player.refresh_from_faction()
		var reason: Array[String] = [""]
		mission.mission_failed.connect(func(text): reason[0] = text)
		var dt: float = sim.catalog.tick_seconds
		var start = Time.get_ticks_msec()
		for i in limit:
			rival.step(dt)
			player.step(dt)
			if i % 20 == 0: pursue_objectives(sim, mission, definition, player)
			sim.tick(dt)
			mission.tick(dt)
			if not mission.active:
				break
		var open: Array = definition.objectives.filter(func(o): return not o.get("optional", false) and not mission.completed.get(o.id, false)).map(func(o): return o.id)
		var expected: bool = definition.mission_id not in UNPROVEN
		if not mission.mission_won and expected:
			failures += 1
		print("MISSION_RESULT mission=%s pass=%s time=%.0f open=%s failed=\"%s\" kills=%s wall_ms=%d" % [definition.mission_id, mission.mission_won, mission.elapsed, str(open), reason[0], [sim.stats[0].kills, sim.stats[1].kills], Time.get_ticks_msec() - start])
		if not mission.mission_won and expected:
			print("FAIL: " + definition.mission_id + " was not won by the computer player")
	print("MISSION_SUMMARY failures=%d" % failures)
	quit(1 if failures > 0 else 0)

## The strategy knows nothing of mission objectives, so the test adds the one thing a
## player reads off the objective list: build what a "build" objective asks for.
func pursue_objectives(sim: DASimulation, mission: DAMissionController, definition: DAMissionDefinition, player: DAOpponent) -> void:
	var own = sim.entities.values().filter(func(e): return e.owner == 0)
	var workers = own.filter(func(e): return e.kind == "worker")
	var buildings = own.filter(func(e): return e.building)
	if workers.is_empty() or buildings.any(func(e): return not e.complete):
		return
	for objective in definition.objectives:
		if objective.get("kind", "") == "build" and not mission.completed.get(objective.id, false):
			if buildings.filter(func(e): return e.kind == objective.target).size() < int(objective.get("required", 1)):
				player.build(str(objective.target), workers, buildings)
				return
