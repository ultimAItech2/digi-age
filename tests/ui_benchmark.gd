extends SceneTree
## Diagnostic comparison with 200 units; excludes simulation and asset setup.
func _initialize():
	call_deferred("run")
func run():
	root.content_scale_size = Vector2i(1600,900)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.ui_action("start")
	game.set_process(false)
	game.audio.enabled = false
	for side in 2:
		for i in 94:
			game.sim.spawn("sentinel",side,Vector2(8+(i%10)*1.3+side*35,22+floori(i/10.0)*1.3))
	game.field.sync(0,[])
	var samples: Array[float] = []
	for i in 120:
		game.hud.queue_redraw()
		await process_frame
		if i > 20: samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
	var total = 0.0
	for sample in samples: total += sample
	print("UI_CPU_MEAN_MS=",total/samples.size())
	game.queue_free()
	await process_frame
	quit()
