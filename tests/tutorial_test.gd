extends SceneTree
## The tutorial, played through the game's own controller: every step waits for
## its action, completes on it, and the campaign's progress is left alone.
var game
var failures: int = 0
var checks: int = 0

func expect(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + title)

func step_id() -> String:
	return str(game.mission.current_objective().get("id", ""))

## Let the match run: `calls` frames at four times speed.
func advance(calls: int = 2) -> void:
	for i in calls:
		game._process(0.2)

func advance_until(done: Callable, limit: int = 600) -> bool:
	for i in limit:
		if done.call(): return true
		game._process(0.2)
	return done.call()

func own(kind: String) -> Array:
	return game.sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == kind)

func drawn() -> Array:
	game.hud.prepare_layout(true)
	return game.hud.text_bounds.map(func(entry): return entry.text)

func wheel() -> void:
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.position = game.hud.world_rect.get_center()
	game._input(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	# A new player: no settings, no campaign file, no saves from an earlier suite.
	var stale: Array = [DASettingsService.PATH, DASaveGame.CAMPAIGN_PATH, DASaveGame.CAMPAIGN_PATH + ".bak"]
	for slot in DASaveGame.AUTO_SLOTS + DASaveGame.MANUAL_SLOTS:
		stale.append(DASaveGame.path_for(slot))
		stale.append(DASaveGame.path_for(slot) + ".bak")
	for path in stale:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.hud.set_process(false)
	game.audio.enabled = false
	game.settings.set_value("language", "en")
	game.apply_runtime_settings()
	var hud = game.hud
	var catalog: DAMissionCatalog = game.mission_catalog
	expect(catalog.all_definitions().size() == 8 and catalog.get_definition("tutorial") != null, "the tutorial sits outside the eight campaign missions")
	var definition: DAMissionDefinition = catalog.get_definition("tutorial")
	expect(definition.sequential and definition.passive_opponent and definition.objectives.size() == 7, "the tutorial is a sequence of seven steps against a passive rival")
	expect(definition.objectives.all(func(o): return str(o.get("prompt", "")) != "" and str(o.get("prompt_pad", "")) != ""), "every step explains itself for mouse and for gamepad")

	# The menu points a newcomer at the tutorial.
	hud.prepare_layout(true)
	var entry: Array = hud.buttons.filter(func(b): return b.action == "tutorial")
	var launch: Array = hud.buttons.filter(func(b): return b.action == "start")
	expect(entry.size() == 1 and entry[0].primary and not launch[0].primary, "the menu offers the tutorial first to a new player")
	hud.activate(entry[0])
	expect(game.mode == "playing" and game.game_kind == "tutorial" and step_id() == "look", "the tutorial starts on its first step")
	expect(drawn().has("TUTORIAL · STEP 1 OF 7") and drawn().has("Look around"), "the panel shows the step and its title")
	expect(hud.buttons.any(func(b): return b.action == "tutorial_skip"), "the tutorial can be skipped")

	# 1. Look around: nothing else completes it. (A headless pointer rests on the screen
	# edge, which pans; the pad's cursor is put mid-screen so the view holds still.)
	game.input.device = "pad"
	game.input.cursor = Vector2(640, 300)
	advance()
	game.selected = [own("worker")[0].id]
	advance()
	expect(step_id() == "look", "a later step's action does not complete the current one")
	game.selected.clear()
	advance()
	wheel()
	game.input.device = "pad"
	advance()
	expect(step_id() == "select_worker", "moving the view completes step 1")
	# 2. Select a Worker.
	game.selected = [own("scout")[0].id]
	advance()
	expect(step_id() == "select_worker", "selecting another unit is not selecting a Worker")
	game.selected = [own("worker")[0].id]
	advance()
	expect(step_id() == "gather", "selecting a Worker completes step 2")
	# 3. Gather.
	expect(game.issue("move", {"pos": own("worker")[0].pos + Vector2(1, 0)}) == "", "a move order is accepted")
	advance()
	expect(step_id() == "gather", "a move order is not a gather order")
	var deposit: Dictionary = game.sim.entities.values().filter(func(e): return e.owner == -1 and e.kind == "metal")[0]
	for e in game.sim.entities.values():
		if e.owner == -1 and e.kind == "metal" and e.pos.distance_to(game.sim.bases[0]) < deposit.pos.distance_to(game.sim.bases[0]): deposit = e
	expect(game.issue("gather", {"target": deposit.id}) == "", "a gather order is accepted")
	advance()
	expect(step_id() == "build_fabricator", "a gather order completes step 3")
	# 4. Build a Fabricator: the command is pointed out, and only a finished building counts.
	game.selected = [own("worker")[1].id]
	hud.prepare_layout(true)
	var build: Array = hud.buttons.filter(func(b): return b.id == "build:fabricator:")
	expect(build.size() == 1 and hud.operations.any(func(op): return op.type == "outline" and op.rect.encloses(build[0].rect)), "the Fabricator command is highlighted")
	var site: Vector2 = Vector2(-1, -1)
	for radius in [5, 7, 9, 11]:
		for i in 16:
			var candidate: Vector2 = (game.sim.bases[0] + Vector2.from_angle(i * TAU / 16.0) * radius).round()
			if site.x < 0 and game.sim.placement_error(0, "fabricator", candidate) == "": site = candidate
	expect(site.x >= 0 and game.issue("build", {"kind": "fabricator", "pos": site}) == "", "a Fabricator can be placed")
	advance()
	expect(step_id() == "build_fabricator", "a Fabricator under construction does not complete the step")
	game.speed = 4
	expect(advance_until(func(): return step_id() == "train_sentinel"), "the finished Fabricator completes step 4")
	# 5. Train a Sentinel.
	game.selected = [own("fabricator")[0].id]
	hud.prepare_layout(true)
	expect(hud.operations.any(func(op): return op.type == "outline"), "the Sentinel command is highlighted")
	expect(game.issue("train", {"kind": "sentinel"}) == "", "a Sentinel can be queued")
	game.speed = 4
	expect(advance_until(func(): return step_id() == "save_group"), "the trained Sentinel completes step 5")
	expect(game.sim.entities.values().filter(func(e): return e.owner == 1 and e.pos.distance_to(Vector2(23, 37)) < 4).is_empty(), "the intruder has not appeared yet")
	# 6. Save a control group, with the real key.
	game.selected = [own("sentinel")[0].id]
	var save = InputEventKey.new()
	save.physical_keycode = KEY_1
	save.pressed = true
	save.ctrl_pressed = true
	game._input(save)
	advance()
	expect(game.groups.get(1, []) == [own("sentinel")[0].id] and step_id() == "destroy_intruder", "Ctrl+1 completes step 6")
	# 7. The intruder arrives, is shown, and has to be destroyed.
	var intruders: Array = game.sim.entities.values().filter(func(e): return e.owner == 1 and e.kind == "worker" and e.pos.distance_to(Vector2(23, 37)) < 4)
	expect(intruders.size() == 1 and game.sim.seen(0, intruders[0].pos), "an intruder appears in view for the last step")
	# A save and a load keep the tutorial and its place.
	expect(game.save_game("manual_2") == "" and DASaveGame.describe("manual_2").get("mission_id", "") == "tutorial", "the tutorial can be saved")
	game.ui_action("menu", {"confirmed": true})
	expect(game.load_game("manual_2") == "" and game.game_kind == "tutorial" and step_id() == "destroy_intruder", "loading returns to the same step")
	game.selected = [own("sentinel")[0].id]
	intruders = game.sim.entities.values().filter(func(e): return e.owner == 1 and e.kind == "worker" and e.pos.distance_to(Vector2(23, 37)) < 4)
	expect(game.issue("attack", {"target": intruders[0].id}) == "", "the Sentinel can attack the intruder")
	game.speed = 4
	expect(advance_until(func(): return game.mode == "result"), "destroying the intruder ends the tutorial")
	expect(game.mission.mission_won and game.sim.winner != 1, "the tutorial ends in a win")
	expect(bool(game.settings.values.tutorial_seen), "the tutorial is remembered as played")
	expect(game.campaign.completed_missions.is_empty() and game.campaign.unlocked_missions == ["first_signal"] and game.campaign.current_mission == "", "campaign progress is untouched")
	expect(not FileAccess.file_exists(DASaveGame.CAMPAIGN_PATH) and DASaveGame.AUTO_SLOTS.all(func(slot): return DASaveGame.describe(slot).is_empty()), "no campaign file or checkpoint was written")
	expect(game.next_mission_id() == "first_signal", "the result screen leads on to First Signal")
	expect(hud.buttons.any(func(b): return b.action == "next_mission") or drawn().any(func(line): return line.contains("FIRST SIGNAL")), "and offers it")
	game.ui_action("next_mission")
	expect(game.mode == "playing" and game.game_kind == "campaign" and game.mission_definition.mission_id == "first_signal", "which starts the campaign")

	# Afterwards the menu leads with the campaign; a gamepad gets its own wording; skip returns to the menu.
	game.ui_action("menu", {"confirmed": true})
	hud.prepare_layout(true)
	expect(hud.buttons.filter(func(b): return b.action == "start")[0].primary and not hud.buttons.filter(func(b): return b.action == "tutorial")[0].primary, "once played, the menu leads with the campaign")
	game.settings.set_value("tutorial_seen", false)
	game.ui_action("tutorial")
	game.ui_action("restart", {"confirmed": true})
	expect(game.game_kind == "tutorial" and step_id() == "look", "restarting stays in the tutorial")
	var mouse_text: Array = drawn()
	game.input.device = "pad"
	var pad_text: Array = drawn()
	expect(mouse_text != pad_text and pad_text.any(func(line): return line.contains("right stick")), "a gamepad player reads gamepad instructions")
	game.input.device = "kbm"
	game.ui_action("tutorial_skip")
	expect(game.mode == "menu" and bool(game.settings.values.tutorial_seen), "skipping returns to the menu and is remembered")

	print("TUTORIAL_RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
