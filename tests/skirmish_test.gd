extends SceneTree
## The opponent on every map: two of them play a symmetric skirmish against each
## other. Both must build an economy, find the other, attack, and act only on
## what their side has seen.
func _initialize() -> void:
	call_deferred("run")

func definition(map_id: String, swap: bool) -> DAMissionDefinition:
	var d = DAMissionDefinition.new()
	d.mission_id = "skirmish"
	d.map_id = map_id
	d.player_faction_id = "origin"
	d.enemy_faction_id = "foundry"
	d.symmetric_start = true
	d.swap_sides = swap
	return d

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var limit = int(args[0]) if args.size() > 0 else 24000
	var failures = 0
	var decided = 0
	var abilities: Dictionary = {}
	var maps: Array = DASettingsService.SKIRMISH_MAPS
	for index in maps.size():
		var sim = DASimulation.new()
		sim.reset_from_mission(definition(maps[index], index % 2 == 1))
		var bots = [DAOpponent.new(sim, 0), DAOpponent.new(sim, 1)]
		for bot in bots: bot.refresh_from_faction()
		var symmetric = true
		for side in 2:
			var own = sim.entities.values().filter(func(e): return e.owner == side)
			if own.filter(func(e): return e.kind == "core").size() != 1 or own.filter(func(e): return e.kind == "worker").size() != 4 or own.size() != 6:
				symmetric = false
		var blind_attack = false
		var found = [false, false]
		var used: Dictionary = {}
		var fielded: Dictionary = {}
		# The handler must not hold the simulation it listens to, or neither is ever freed.
		var units: Dictionary = sim.catalog.units
		sim.alert.connect(func(kind, _pos, _side, detail):
			if kind == "ability": used[detail] = int(used.get(detail, 0)) + 1
			if kind == "unit_ready" and units[detail].has("faction"): fielded[detail] = int(fielded.get(detail, 0)) + 1)
		var start = Time.get_ticks_msec()
		for i in limit:
			for bot in bots:
				var before: int = bot.assaults
				var remembered: bool = not sim.remembered[bot.side].is_empty()
				bot.step(0.1)
				# An attack launched before anything was seen may only go to the public start position.
				if bot.assaults > before and not remembered and bot.attack_target(bot.own_base()) != bot.enemy_base():
					blind_attack = true
			sim.tick()
			for side in 2:
				if not sim.remembered[side].is_empty(): found[side] = true
			if sim.winner >= 0:
				break
		if sim.winner >= 0: decided += 1
		var economy = sim.stats[0].gathered > 1500 and sim.stats[1].gathered > 1500
		var fought = bots[0].assaults > 0 and bots[1].assaults > 0 and sim.stats[0].kills + sim.stats[1].kills > 0
		# Both opponents field their faction's unit, and abilities get used.
		var depth = fielded.has("warden") and fielded.has("mortar") and not fielded.has("phantom") and used.has("overdrive") and used.has("sweep")
		for id in used: abilities[id] = int(abilities.get(id, 0)) + used[id]
		var passed = symmetric and economy and fought and found[0] and found[1] and not blind_attack and depth
		if not passed: failures += 1
		print("SKIRMISH_RESULT map=%s pass=%s abilities=%s fielded=%s winner=%d time=%.0f symmetric=%s found=%s assaults=%s retreats=%s gathered=%s kills=%s ages=%s wall_ms=%d" % [maps[index], passed, str(used), str(fielded), sim.winner, sim.elapsed, symmetric, found, [bots[0].assaults, bots[1].assaults], [bots[0].retreats, bots[1].retreats], [int(sim.stats[0].gathered), int(sim.stats[1].gathered)], [sim.stats[0].kills, sim.stats[1].kills], sim.ages, Time.get_ticks_msec() - start])
	# Most maps must reach a decision inside the limit, or the opponent cannot finish a match.
	if decided < maps.size() / 2:
		failures += 1
		print("FAIL: only %d of %d skirmishes reached a winner" % [decided, maps.size()])
	# Across the eight maps every ability must have been used at least once.
	for id in ["sweep", "overdrive", "emp", "brace"]:
		if not abilities.has(id):
			failures += 1
			print("FAIL: the opponent never used " + id)
	print("SKIRMISH_SUMMARY maps=%d decided=%d abilities=%s failures=%d" % [maps.size(), decided, str(abilities), failures])
	quit(1 if failures > 0 else 0)
