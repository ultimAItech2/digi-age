extends SceneTree
## A complete accelerated skirmish with the actual scene, HUD and renderer:
## an opponent plays the player's side against the game's own, from the setup
## screen's Start button to the result screen.
var game: Node3D
var player_bot: DAOpponent
var last_checkpoint: int = -1
var observed_ages: Array = [false,false,false]
var elapsed_real: float = 0.0

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.settings.set_value("skirmish",{"map":"silent_grid","player":"origin","enemy":"foundry","resources":"standard","side":"left"})
	game.ui_action("start_skirmish")
	game.set_process(false)
	game.audio.enabled = false
	player_bot = DAOpponent.new(game.sim,0)
	player_bot.refresh_from_faction()
	game.auto_player = player_bot
	game.speed = 32
	game.field.focus = Vector2(22,36)
	game.field.zoom = DABattlefield.ZOOM_MAX
	game.field.update_camera()
	while game.mode == "playing" and game.sim.elapsed < 2600:
		game._process(0.2)
		observed_ages[game.sim.ages[0]] = true
		var checkpoint = int(game.sim.elapsed/300)
		if checkpoint != last_checkpoint:
			last_checkpoint = checkpoint
			game.selected = game.sim.entities.values().filter(func(e):return e.owner==0 and e.kind=="core").map(func(e):return e.id)
			game.hud.toast("AUTOMATED PLAYTHROUGH  /  " + DAInterface.time_text(game.sim.elapsed))
			print("RENDERED_MATCH time=%.0f ages=%s population=%s" % [game.sim.elapsed,game.sim.ages,[game.sim.population(0),game.sim.population(1)]])
		await process_frame
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var result = game.mode=="result" and game.sim.winner >= 0 and observed_ages==[true,true,true] and game.game_kind == "skirmish"
	root.get_texture().get_image().save_png("res://builds/match-result.png")
	print("RENDERED_RESULT passed=%s winner=%d time=%.1f ages_observed=%s" % [result,game.sim.winner,game.sim.elapsed,observed_ages])
	game.queue_free()
	await process_frame
	quit(0 if result else 1)
