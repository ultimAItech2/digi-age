extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	var runs = int(args[0]) if args.size()>0 else 3
	var failures = 0
	for run_index in runs:
		var sim = DASimulation.new()
		var bots = [DAOpponent.new(sim,0),DAOpponent.new(sim,1)]
		# Vary the opening decision phase without changing either side's resources.
		bots[run_index%2].timer = run_index*0.7
		var max_ages = [0,0]
		var start = Time.get_ticks_msec()
		for i in 21000:
			for bot in bots:
				bot.step(0.1)
			sim.tick()
			for side in 2:
				max_ages[side] = maxi(max_ages[side],sim.ages[side])
			if i%3000==0:
				print("SOAK %d time=%.0f pop=%s ages=%s resources=%s assaults=%s" % [run_index,sim.elapsed,[sim.population(0),sim.population(1)],sim.ages,sim.resources,[bots[0].assaults,bots[1].assaults]])
			if sim.winner>=0:
				break
		var passed = sim.winner>=0 and bots[0].assaults>0 and bots[1].assaults>0 and sim.stats[0].gathered>2000 and sim.stats[1].gathered>2000
		if not passed:
			failures+=1
		print("SOAK_RESULT run=%d pass=%s winner=%d time=%.1f ages=%s gathered=%s kills=%s wall_ms=%d" % [run_index,passed,sim.winner,sim.elapsed,max_ages,[sim.stats[0].gathered,sim.stats[1].gathered],[sim.stats[0].kills,sim.stats[1].kills],Time.get_ticks_msec()-start])
	print("SOAK_SUMMARY runs=%d failures=%d" % [runs,failures])
	quit(1 if failures>0 else 0)
