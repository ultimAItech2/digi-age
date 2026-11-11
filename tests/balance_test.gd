extends SceneTree
## Faction balance: every pairing of the three factions plays a symmetric skirmish
## on three maps, once from each start, with the opponent on both sides.
## Reports each faction's share of decided matches. Run by hand; it takes a while:
##   tools/godot.sh --headless --script tests/balance_test.gd
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var factions: Array = DASettingsService.SKIRMISH_FACTIONS
	var maps = ["silent_grid", "salvage_basin", "lattice_web"]
	var wins: Dictionary = {}
	var played: Dictionary = {}
	var first_side_wins = 0
	var decided = 0
	for a in factions:
		for b in factions:
			for map_id in maps:
				var d = DAMissionDefinition.new()
				d.mission_id = "skirmish"
				d.map_id = map_id
				d.player_faction_id = a
				d.enemy_faction_id = b
				d.symmetric_start = true
				var sim = DASimulation.new()
				sim.reset_from_mission(d)
				var bots = [DAOpponent.new(sim, 0), DAOpponent.new(sim, 1)]
				for bot in bots: bot.refresh_from_faction()
				for i in 26000:
					# Alternate which side decides first, so neither always moves ahead of the other.
					bots[i % 2].step(0.1)
					bots[1 - i % 2].step(0.1)
					sim.tick()
					if sim.winner >= 0: break
				if a != b:
					for faction in [a, b]: played[faction] = int(played.get(faction, 0)) + 1
				if sim.winner >= 0:
					decided += 1
					if sim.winner == 0: first_side_wins += 1
					if a != b:
						var winner: String = a if sim.winner == 0 else b
						wins[winner] = int(wins.get(winner, 0)) + 1
				print("BALANCE %s vs %s on %s: winner=%s time=%.0f kills=%s" % [a, b, map_id, [a, b][sim.winner] if sim.winner >= 0 else "none", sim.elapsed, [sim.stats[0].kills, sim.stats[1].kills]])
	var worst = 0.0
	for faction in factions:
		var share = float(wins.get(faction, 0)) / maxf(1.0, float(played.get(faction, 0)))
		worst = maxf(worst, share)
		print("BALANCE_FACTION %s: won %d of %d (%.0f%%)" % [faction, wins.get(faction, 0), played.get(faction, 0), share * 100.0])
	print("BALANCE_SUMMARY decided=%d first_side_wins=%d worst_share=%.2f pass=%s" % [decided, first_side_wins, worst, worst <= 0.7])
	quit(0 if worst <= 0.7 else 1)
