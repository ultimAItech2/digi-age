extends SceneTree
var game: Node3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, title: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + title)
	else:
		failures += 1
		push_error("FAIL: " + title)

func click(p: Vector2, right: bool = false) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	event.position = p
	event.pressed = true
	game._input(event)
	event.pressed = false
	game._input(event)

func key(code: Key, ctrl: bool = false) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	game._input(event)

func visible_ground(preferred: Vector2) -> Vector2:
	game.hud.prepare_layout(true)
	for delta in [Vector2.ZERO,Vector2(0,4),Vector2(4,0),Vector2(0,-4),Vector2(-4,0)]:
		if game.hud.is_world(game.field.screen_at(preferred+delta)): return preferred+delta
	return game.field.ground_at(game.hud.world_rect.get_center())

func button(action: String, kind: String = "") -> bool:
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	for b in game.hud.buttons:
		if b.action == action and (kind == "" or b.payload.get("kind","") == kind):
			click(b.rect.get_center())
			return true
	return false

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	# Drive the actual controller and UI, not a second implementation of their logic.
	expect(game.mode == "menu", "starts on main menu")
	expect(game.hud.portrait("worker") == DASprites.portrait("worker") and game.hud.portrait("walker") != null, "HUD portraits come from the sprites, Blender renders remain for the rest")
	expect(await button("start"), "launch button is clickable")
	expect(game.mode == "playing", "launch starts a fresh match")
	game.set_process(false)
	game.audio.enabled = false
	game.opponent.timer=10000
	game.field.sync(1,[])
	game.field.update_camera()
	var worker = game.sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == "worker")[0]
	click(game.field.screen_at(worker.pos,0.5))
	expect(game.selected.has(worker.id), "click selects a rendered Worker")
	key(KEY_1,true)
	game.selected.clear()
	key(KEY_1)
	expect(game.selected.has(worker.id), "control group save and recall")
	var target = visible_ground(worker.pos+Vector2(2,3))
	click(game.field.screen_at(target),true)
	expect(worker.order == "move", "right-click terrain issues move")
	key(KEY_S)
	expect(worker.order == "idle", "S stops selected unit")
	key(KEY_A)
	click(game.field.screen_at(visible_ground(Vector2(25,40))))
	expect(worker.order == "attack_move" and not game.attack_mode, "A then click issues attack-move")
	key(KEY_S)
	expect(await button("build","generator"), "worker build menu renders and responds")
	expect(game.build_kind == "generator", "build button enters placement mode")
	click(game.field.screen_at(Vector2(15,32)),true)
	expect(game.build_kind == "", "right-click cancels construction preview")
	await button("build","generator")
	var before: Vector3 = game.sim.resources[0]
	click(game.field.screen_at(game.sim.bases[0]))
	expect(game.sim.resources[0].x==before.x and game.build_kind!="", "invalid placement does not spend or leave placement mode")
	var site = Vector2.ZERO
	for x in range(5,25):
		for y in range(23,46):
			var p=Vector2(x,y)
			if game.sim.placement_error(0,"generator",p)=="" and game.hud.is_world(game.field.screen_at(p)):
				site=p
				break
		if site!=Vector2.ZERO:
			break
	click(game.field.screen_at(site))
	expect(game.sim.resources[0].x==before.x-100 and game.build_kind=="", "click creates paid foundation")
	var foundation=game.sim.entities.values().filter(func(e): return e.owner==0 and e.kind=="generator" and not e.complete)[0]
	game.field.sync(0.1, game.selected)
	var foundation_node: Node3D = game.field.models[foundation.id]
	var rise = foundation_node.get_child(0).get_instance_shader_parameter("rise")
	expect(DASprites.is_card(foundation_node) and rise != null and rise < 1.0 and foundation_node.scale == Vector3.ONE, "construction uses the card's rise, not node scale")
	for i in 500:
		game.sim.tick()
	expect(foundation.complete,"UI-ordered construction finishes in simulation")
	game.field.sync(0.1, game.selected)
	expect(foundation_node.get_child(0).get_instance_shader_parameter("rise") == 1.0, "finished building is fully risen")
	key(KEY_HOME)
	await process_frame
	var core=game.sim.entities[game.selected[0]]
	expect(core.kind=="core" and game.field.focus.distance_to(game.sim.bases[0])<1.0,"Home selects and focuses Core")
	expect(await button("train","worker"),"Core production button clickable")
	expect(core.queue.size()==1,"UI production queues Worker")
	var rally_target = visible_ground(Vector2(18,40))
	click(game.field.screen_at(rally_target),true)
	expect(core.rally.distance_to(rally_target)<0.1,"building right-click sets rally point")
	# Sprite cards: facing follows the camera yaw, ghost tint stays per instance, cards survive a load.
	var sentinel_id = game.sim.spawn("sentinel", 0, Vector2(20, 20))
	game.sim.set_order(game.sim.entities[sentinel_id], "move", Vector2(10, 20))
	game.field.yaw = -0.62
	game.field.update_camera()
	game.field.sync(0.1, game.selected)
	var sentinel_node: Node3D = game.field.models[sentinel_id]
	expect(DASprites.is_card(sentinel_node), "sentinel is drawn as a sprite card")
	expect(sentinel_node.get_child(0).get_instance_shader_parameter("flip") == 1.0, "moving to world -x flips at default yaw")
	game.field.yaw = -0.62 + PI
	game.field.update_camera()
	game.field.sync(0.1, game.selected)
	expect(sentinel_node.get_child(0).get_instance_shader_parameter("flip") == 0.0, "same move after a half-turn does not flip")
	game.field.yaw = -0.62
	game.field.update_camera()
	game.field.preview("generator", Vector2(30, 30), true)
	expect(game.field.ghost != null and DASprites.is_card(game.field.ghost) and game.field.ghost.get_child(0).get_instance_shader_parameter("tint") != null, "placement ghost is a tinted card")
	var tint = sentinel_node.get_child(0).get_instance_shader_parameter("tint")
	expect(tint == null or Color(tint) == Color(1, 1, 1, 1), "entity cards keep white tint while a ghost is shown")
	expect(game.field.ghost.get_node_or_null("Fx/Ground") == null, "placement ghost has no owner disc or contact shadow")
	game.field.preview("", Vector2.ZERO, false)
	var archive = game.sim.entities.values().filter(func(e): return e.kind == "data")[0]
	game.field.sync(0.1, game.selected)
	expect(game.field.models[archive.id].get_node_or_null("Ground") != null, "archive model gets the contact shadow quad")
	# Clicking the drawn base of a building card (anchor_offset toward the camera,
	# below the node's ground point on screen) selects it when no unit stands there.
	var lone_id = game.sim.spawn("fabricator", 0, Vector2(60, 12))
	var lone = game.sim.entities[lone_id]
	var saved_focus = game.field.focus
	game.field.focus = lone.pos
	game.field.update_camera()
	game.field.sync(0.1, game.selected)
	var base_point: Vector2 = lone.pos + Vector2(sin(game.field.yaw), cos(game.field.yaw)) * DASprites.anchor_offset("fabricator", 5)
	game.selected.clear()
	click(game.field.screen_at(base_point, 0.3))
	expect(game.selected.has(lone_id), "clicking the card's drawn base selects the building")
	game.field.focus = saved_focus
	game.field.update_camera()
	expect(game.save_game("test_cards") == "" and game.load_game("test_cards") == "", "save and load round trip")
	game.field.sync(0.1, game.selected)
	expect(game.field.models.has(sentinel_id) and DASprites.is_card(game.field.models[sentinel_id]), "cards rebuilt after load")
	core = game.sim.entities[core.id]
	game.selected.assign([core.id])
	game.field.apply_settings({"profile": "low"})
	expect(not game.field.models[sentinel_id].get_node("Fx/Shadow").visible, "low profile hides card shadows along with the sun's")
	game.field.apply_settings({"profile": "normal"})
	expect(game.field.models[sentinel_id].get_node("Fx/Shadow").visible, "normal profile shows card shadows again")
	# Pause, help, speed and restart use real key/menu routes.
	key(KEY_SPACE)
	expect(game.mode=="paused","Space opens pause overlay")
	var elapsed: float=game.sim.elapsed
	game._process(0.15)
	expect(game.sim.elapsed==elapsed,"pause freezes simulation")
	await button("speed")
	expect(game.speed==2,"pause speed setting changes")
	await button("help")
	expect(game.hud.manual,"field manual opens over pause")
	key(KEY_ESCAPE)
	expect(not game.hud.manual and game.mode=="paused","Escape closes help without resuming")
	key(KEY_SPACE)
	expect(game.mode=="playing","Space resumes match")
	key(KEY_F1)
	elapsed=game.sim.elapsed
	game._process(0.2)
	expect(game.sim.elapsed==elapsed,"field manual pauses active simulation")
	key(KEY_F1)
	# Both age paths are accessible through the actual Core action buttons.
	game.sim.resources[0]=Vector3(3000,3000,3000)
	await button("research","age")
	for i in 460:
		game.sim.tick()
	expect(game.sim.ages[0]==1,"UI research reaches Network")
	await button("research","age")
	for i in 660:
		game.sim.tick()
	expect(game.sim.ages[0]==2,"UI research reaches Singularity")
	# Rendered picking includes upper parts of a tall building, not just its floor.
	game.field.sync(1,game.selected)
	click(game.field.screen_at(core.pos,2.5))
	expect(game.selected.has(core.id),"clicking tall Core mesh selects it")
	var enemy=game.sim.entities.values().filter(func(e):return e.kind=="core" and e.owner==1)[0]
	game.sim.remove_entity(enemy.id)
	game._process(0.2)
	expect(game.mode=="result","victory opens results screen")
	expect(await button("restart"),"results replay button clickable")
	expect(game.mode=="playing" and game.sim.ages[0]==0 and game.sim.winner==-1 and game.selected.is_empty(),"restart resets match, progression and selection")
	key(KEY_SPACE)
	await button("menu")
	expect(not game.hud.confirmation.is_empty(),"leaving active mission asks about unsaved progress")
	await button("confirm_proceed")
	expect(game.mode=="menu","pause menu returns to title screen")
	print("UI_RESULT: %d checks, %d failures" % [checks,failures])
	game.set_process(false)
	game.queue_free()
	await process_frame
	quit(1 if failures>0 else 0)
