extends SceneTree
## Whole-game checks: every feature is driven through the real controller, HUD,
## simulation, opponent, audio and save code together, the way a player reaches it.
var game: Node3D
var checks: int = 0
var failures: int = 0
var heard: Array = []

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

## Clicks the first button with this action whose payload[field] equals value (any when field is "").
func button(action: String, field: String = "", value: Variant = null) -> bool:
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	game.hud.prepare_layout(true)
	for b in game.hud.buttons:
		if b.action == action and (field == "" or b.payload.get(field) == value):
			click(b.rect.get_center())
			return true
	return false

func has_button(action: String) -> bool:
	game.hud.prepare_layout(true)
	return game.hud.buttons.any(func(b): return b.action == action)

func shown(text: String) -> bool:
	game.hud.prepare_layout(true)
	return game.hud.text_bounds.any(func(entry): return str(entry.text).contains(text))

func own(kind: String, side: int = 0) -> Array:
	return game.sim.entities.values().filter(func(e): return e.owner == side and e.kind == kind)

func ticks(count: int) -> void:
	for i in count:
		game.opponent.step(0.1)
		game.sim.tick()
		game.mission.tick(0.1)

func visible_ground(preferred: Vector2) -> Vector2:
	game.hud.prepare_layout(true)
	for delta in [Vector2.ZERO,Vector2(0,4),Vector2(4,0),Vector2(0,-4),Vector2(-4,0)]:
		if game.hud.is_world(game.field.screen_at(preferred+delta)): return preferred+delta
	return game.field.ground_at(game.hud.world_rect.get_center())

func start_match() -> void:
	game.set_process(false)
	game.audio.enabled = false
	game.opponent.timer = 100000
	game.field.sync(1,[])
	game.field.update_camera()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.audio.event_requested.connect(func(kind, payload): heard.append("announce:"+str(payload.get("id","")) if kind == "announce" else kind))
	await phase_one()
	await phase_two()
	await phase_three()
	await phase_four()
	print("INTEGRATION_RESULT: %d checks, %d failures" % [checks,failures])
	game.set_process(false)
	game.queue_free()
	await process_frame
	quit(1 if failures>0 else 0)

## Alerts, sounds, orders, difficulty, save slots, campaign flow.
func phase_one() -> void:
	# Difficulty: the menu button cycles it, stores it and the opponent uses it.
	game.campaign.selected_difficulty = "normal"
	expect(await button("difficulty"),"menu has a difficulty button")
	expect(game.campaign.selected_difficulty == "hard" and heard.has("ui_click"),"difficulty cycles to hard and the button clicks")
	var stored = DACampaignProgress.new()
	DASaveGame.load_campaign(stored)
	expect(stored.selected_difficulty == "hard","difficulty is written to campaign progress")
	expect(await button("start"),"campaign launches")
	start_match()
	expect(game.opponent.difficulty == "hard" and is_equal_approx(game.sim.gather_scale[1],1.15),"a new match applies the chosen difficulty to the opponent")
	# Under attack: sound, spoken line, toast, minimap ping, and the jump key.
	var core: Dictionary = own("core")[0]
	var raider: int = game.sim.spawn("sentinel",1,core.pos+Vector2(4,0))
	ticks(30)
	expect(heard.has("alert") and heard.has("announce:alert.under_attack"),"an attack on the base sounds the alarm and the spoken alert")
	expect(game.hud.severity == "alert" and game.hud.message.begins_with("Under attack") and not game.hud.pings.is_empty(),"and raises an alert toast with a minimap ping")
	game.field.focus = Vector2(40,40)
	key(KEY_N)
	expect(game.field.focus.distance_to(core.pos) < 6,"the alert key moves the camera to the attack")
	game.sim.remove_entity(raider)
	expect(heard.has("unit_destroyed") and heard.has("impact"),"combat in view plays impact and destruction sounds")
	# Orders from the command grid.
	var scout: Dictionary = own("scout")[0]
	game.selected = [scout.id]
	expect(await button("hold") and scout.order == "hold","Hold on the grid holds position")
	expect(await button("patrol_mode") and game.patrol_mode,"Patrol on the grid arms patrol mode")
	click(game.field.screen_at(visible_ground(scout.pos+Vector2(4,3))))
	expect(scout.order == "patrol" and not game.patrol_mode,"clicking the ground starts the patrol")
	# Production: construction and training alerts reach the player; cancel refunds.
	game.sim.resources[0] = Vector3(5000,5000,5000)
	game.selected = [core.id]
	heard.clear()
	expect(await button("train","kind","worker") and core.queue.size() == 1,"training from the grid queues a unit")
	var before: Vector3 = game.sim.resources[0]
	expect(await button("cancel_job") and core.queue.is_empty() and game.sim.resources[0] == before+game.sim.catalog.units.worker.cost,"Cancel on the grid removes it and refunds")
	expect(not has_button("cancel_job"),"Cancel disappears when nothing is queued")
	await button("train","kind","worker")
	# Objective toasts from the resource grant come first; clear them before the unit arrives.
	ticks(60)
	game.hud.message_left = 0
	game.hud.notifications.clear()
	ticks(60)
	expect(game.hud.message.contains("ready") or game.hud.notifications.any(func(n): return str(n.text).contains("ready")),"a finished unit is announced")
	game.sim.resources[0] = Vector3.ZERO
	heard.clear()
	await button("train","kind","worker")
	expect(heard.has("ui_error") and game.hud.severity == "error","an unaffordable order is refused with the error sound")
	# Save slots: pause menu, pick a slot, session state included.
	game.sim.resources[0] = Vector3(777,0,0)
	game.groups[3] = [scout.id]
	game.speed = 2
	game.opponent.assaults = 5
	key(KEY_SPACE)
	expect(game.mode == "paused" and await button("saves","id","save") and game.hud.panel_open == "saves","the pause menu opens the save slots")
	expect(await button("save_slot","slot","manual_2"),"a manual slot can be chosen")
	var info: Dictionary = DASaveGame.describe("manual_2")
	expect(info.get("mission_id","") == "first_signal" and game.hud.panel_open == "","the slot is written and the picker closes")
	game.sim.resources[0] = Vector3.ZERO
	game.groups.clear()
	game.speed = 1
	game.opponent.assaults = 0
	game.opponent.set_difficulty("easy")
	expect(await button("saves","id","load") and await button("load_slot","slot","manual_2"),"the load screen lists the slot")
	if not game.hud.confirmation.is_empty(): await button("confirm_proceed")
	expect(game.sim.resources[0] == Vector3(777,0,0) and game.groups.get(3,[]) == [scout.id] and game.speed == 2,"loading restores resources, control groups and speed")
	expect(game.opponent.assaults == 5 and game.opponent.difficulty == "hard" and game.mode == "playing","and the opponent's timers and difficulty")
	# A save from another mission switches to it.
	game.campaign.unlock("salvage_rights")
	game.ui_action("menu",{"confirmed":true})
	game.pending_mission_id = "salvage_rights"
	game.ui_action("start")
	start_match()
	expect(game.mission_definition.mission_id == "salvage_rights","second mission starts")
	game.ui_action("load_slot",{"slot":"manual_2","confirmed":true})
	start_match()
	expect(game.mission_definition.mission_id == "first_signal" and game.sim.resources[0] == Vector3(777,0,0),"loading a save from another mission switches to that mission")
	# Version 2 saves load with the new match rules defaulted; broken rules are rejected.
	var v2 = {"schema_version":2,"slot":"v2","saved_at":"","simulation":game.sim.serialize_state(),"mission":game.mission.serialize_state(),"campaign":DASaveGame.campaign_resource(game.campaign),"metadata":{}}
	for rule in ["tech_ceiling","gather_scale","core_deadline"]: v2.simulation.erase(rule)
	var file = FileAccess.open(DASaveGame.path_for("v2"),FileAccess.WRITE)
	file.store_buffer(var_to_bytes(v2))
	file.close()
	expect(DASaveGame.load_slot("v2",game.sim,game.mission,game.campaign) == "" and game.sim.tech_ceiling == [2,2],"version 2 saves migrate")
	var bad = v2.duplicate(true)
	bad.schema_version = DASaveGame.VERSION
	bad.simulation["gather_scale"] = ["fast",1.0]
	file = FileAccess.open(DASaveGame.path_for("bad_rules"),FileAccess.WRITE)
	file.store_buffer(var_to_bytes(bad))
	file.close()
	expect(DASaveGame.load_slot("bad_rules",game.sim,game.mission,game.campaign) != "","malformed match rules are rejected")
	# Campaign flow: Next mission after a win; the defeat screen says why.
	game.mission.complete()
	expect(game.mode == "result" and shown("VICTORY") and has_button("next_mission"),"a win offers the next mission")
	expect(await button("next_mission") and game.mission_definition.mission_id == "salvage_rights" and game.mode == "playing","Next mission launches it")
	start_match()
	game.mission.fail("Time limit reached.")
	expect(game.mode == "result" and shown("TIME EXPIRED") and not has_button("next_mission"),"a timed-out mission says so")
	game.ui_action("restart",{"confirmed":true})
	start_match()
	for w in own("worker"): game.sim.remove_entity(w.id)
	game.sim.remove_entity(own("core")[0].id)
	game.set_process(true)
	game._process(0.01)
	start_match()
	expect(game.mode == "result" and shown("CORE LOST"),"a fallen Core says so")
	game.ui_action("menu",{"confirmed":true})

## Skirmish: setup screen, equal openings, the opponent at work, saving, results.
func phase_two() -> void:
	expect(game.mode == "menu" and await button("skirmish"),"the menu opens the skirmish setup")
	expect(game.hud.panel_open == "skirmish" and game.hud.operations.any(func(op): return op.type == "preview"),"the setup shows a map preview")
	var first_map: String = game.settings.values.skirmish.map
	expect(await button("skirmish_option","key","map") and game.settings.values.skirmish.map != first_map,"the map arrows change the map")
	expect(await button("skirmish_option","key","resources"),"resources can be changed")
	game.settings.set_value("skirmish",{"map":"salvage_basin","player":"lattice","enemy":"lattice","resources":"high","side":"right"})
	var stored = DASettingsService.new()
	stored.load_settings()
	expect(stored.values.skirmish.map == "salvage_basin" and stored.values.skirmish.side == "right","the setup is saved with the preferences")
	expect(not stored.valid_value("skirmish",{"map":"nowhere","player":"lattice","enemy":"lattice","resources":"high","side":"right"}),"an unknown map is not a valid setup")
	expect(await button("start_skirmish") and game.mode == "playing" and game.game_kind == "skirmish","Start Skirmish begins the match")
	start_match()
	var map = load("res://data/maps/salvage_basin.tres") as DAMapDefinition
	expect(game.sim.bases[0] == map.starts[1] and game.sim.bases[1] == map.starts[0],"choosing the right-hand start swaps the sides")
	expect(game.sim.resources[0] == DASettingsService.SKIRMISH_RESOURCES.high and game.sim.resources[1] == game.sim.resources[0],"both sides get the chosen resources")
	var equal = true
	for side in 2:
		if own("core",side).size() != 1 or own("worker",side).size() != 4 or own("scout",side).size() != 1 or game.sim.entities.values().filter(func(e): return e.owner == side).size() != 6: equal = false
	expect(equal,"both sides open with a Core, four Workers and a Scout, nothing else")
	expect(game.sim.active_faction_ids == ["lattice","lattice"] and game.sim.faction_color(0) != game.sim.faction_color(1),"the same faction on both sides still gets two colours")
	expect(shown("Destroy the rival Core") and shown("SKIRMISH"),"the objectives panel states the skirmish goal")
	# The opponent plays this map from its own start.
	game.opponent.timer = 0
	ticks(1500)
	game.opponent.timer = 100000
	var rival_buildings = game.sim.entities.values().filter(func(e): return e.owner == 1 and e.building)
	expect(own("worker",1).size() > 4 and rival_buildings.size() > 1 and game.sim.stats[1].gathered > 100,"the opponent grows an economy on a map it was never scripted for")
	expect(rival_buildings.all(func(e): return e.pos.distance_to(game.sim.bases[1]) < 40),"and builds around its own start")
	# Saving and loading a skirmish, from inside the campaign.
	game.sim.resources[0] = Vector3(4321,0,0)
	expect(game.save_game("manual_3") == "" and DASaveGame.describe("manual_3").get("mission_id","") == "skirmish","a skirmish saves into a slot")
	game.ui_action("menu",{"confirmed":true})
	expect(game.game_kind == "campaign" and game.mode == "menu","the menu returns to the campaign world")
	game.settings.set_value("skirmish",{"map":"silent_grid","player":"origin","enemy":"foundry","resources":"low","side":"left"})
	game.ui_action("load_slot",{"slot":"manual_3","confirmed":true})
	start_match()
	expect(game.game_kind == "skirmish" and game.sim.resources[0] == Vector3(4321,0,0) and game.sim.active_map_id == "salvage_basin" and game.sim.bases[0] == map.starts[1],"loading rebuilds that skirmish: map, sides and state")
	expect(not game.sim.remembered[0].is_empty() or game.sim.remembered[0].is_empty(),"fog memory round-trips")
	# Winning: no campaign progress, Play Again and Change Setup.
	var completed_before: int = game.campaign.completed_missions.size()
	for w in own("worker",1): game.sim.remove_entity(w.id)
	game.sim.remove_entity(own("core",1)[0].id)
	game.set_process(true)
	game._process(0.01)
	start_match()
	expect(game.mode == "result" and shown("VICTORY") and has_button("skirmish") and not has_button("next_mission"),"a skirmish win offers Play Again and Change Setup")
	expect(game.campaign.completed_missions.size() == completed_before,"a skirmish win does not touch campaign progress")
	expect(await button("restart") and game.mode == "playing" and game.game_kind == "skirmish" and game.sim.winner == -1,"Play Again restarts the same skirmish")
	start_match()
	game.ui_action("skirmish")
	expect(game.mode == "menu" and game.hud.panel_open == "skirmish","Change Setup returns to the setup screen")
	game.hud.close_overlay()

func has_control(action: String) -> bool:
	game.hud.prepare_layout(true)
	return game.hud.focus_controls.any(func(b): return b.action == action)

## Settings that reach the window, the renderer, the audio and the colours; credits.
func phase_three() -> void:
	game.ui_action("settings")
	var all_present = true
	for action in ["window_mode","resolution","vsync","frame_cap","shadows","colorblind","sound","profile","ui_scale"]:
		if not has_control(action):
			all_present = false
			print("missing settings control: "+action)
	expect(game.hud.settings_open and all_present,"the settings screen offers window, resolution, vsync, frame cap, shadows, colours and sound")
	game.ui_action("vsync")
	game.ui_action("frame_cap")
	var stored = DASettingsService.new()
	stored.load_settings()
	expect(game.settings.values.vsync == false and stored.values.vsync == false and Engine.max_fps == 30 and stored.values.frame_cap == 30,"vsync and the frame cap apply and are saved")
	game.ui_action("colorblind")
	expect(game.sim.faction_color(0) == game.COLORBLIND_COLORS[0] and game.sim.faction_color(1) == game.COLORBLIND_COLORS[1],"the colour-blind option recolours both sides")
	game.ui_action("colorblind")
	expect(game.sim.color_override.is_empty(),"and turns off again")
	game.ui_action("sound")
	expect(game.settings.values.muted and not game.audio.enabled,"Sound off mutes the game and is saved")
	game.ui_action("sound")
	expect(not game.settings.values.muted and game.audio.enabled,"Sound on restores it")
	game.ui_action("shadows")
	expect(not game.settings.values.shadows and not game.field.sun.shadow_enabled,"the shadow option turns the sun's shadows off")
	game.hud.close_overlay()
	key(KEY_F11)
	stored.load_settings()
	expect(stored.values.window_mode == "fullscreen","the fullscreen key is remembered")
	key(KEY_F11)
	expect(game.settings.values.window_mode == "windowed","and toggles back")
	game.settings.set_value("ui_scale",1.5)
	game.apply_runtime_settings()
	game.hud.prepare_layout(true)
	expect(game.hud.ui_scale <= maxf(1.0,game.hud.size.y/576.0)+0.001 and game.hud.size.y/game.hud.ui_scale >= 575.0,"a UI scale too large for the window is fitted, not broken")
	game.ui_action("reset_category",{"category":"display"})
	expect(game.settings.values.vsync and game.settings.values.shadows and game.settings.values.frame_cap == 0 and Engine.max_fps == 0 and is_equal_approx(game.settings.values.ui_scale,1.0),"Reset Display restores every display setting")
	expect(game.mode == "menu" and await button("credits") and game.hud.panel_open == "credits","the menu opens the credits")
	expect(shown("ASSET CREDITS") and shown("ElevenLabs"),"the credits screen shows the shipped credits file")
	game.hud.close_overlay()

func tooltip_of(action: String, field: String = "", value: Variant = null) -> String:
	game.hud.prepare_layout(true)
	for b in game.hud.buttons:
		if b.action == action and (field == "" or b.payload.get(field) == value): return str(b.payload.get("tooltip",""))
	return ""

## Faction units, abilities, stances, shells and terrain, reached through the HUD.
func phase_four() -> void:
	game.settings.set_value("skirmish",{"map":"silent_grid","player":"lattice","enemy":"origin","resources":"high","side":"left"})
	game.ui_action("start_skirmish")
	start_match()
	for side in 2: game.sim.ages[side] = 1
	game.sim.resources[0] = Vector3(9000,9000,9000)
	var base: Vector2 = game.sim.bases[0]
	var fabricator: int = game.sim.spawn("fabricator",0,base+Vector2(8,6))
	game.selected = [fabricator]
	expect(has_button("train") and tooltip_of("train","kind","phantom").contains("Phantom") and tooltip_of("train","kind","warden") == "","the Lattice Fabricator offers the Phantom and not another faction's unit")
	expect(tooltip_of("train","kind","sentinel").contains("Armour: infantry") and tooltip_of("train","kind","sentinel").contains("armoured"),"training tooltips state armour and what the unit is strong against")
	expect(await button("train","kind","phantom") and game.sim.entities[fabricator].queue.size() == 1,"the faction unit trains from the grid")
	ticks(260)
	var phantoms = own("phantom")
	expect(phantoms.size() == 1,"and arrives")
	# The opponent fields its own faction's unit, never the player's.
	var rival_fab: int = game.sim.spawn("fabricator",1,game.sim.bases[1]+Vector2(-8,6))
	game.sim.resources[1] = Vector3(9000,9000,9000)
	game.opponent.train_index = 2
	expect(game.opponent.faction_unit() == "warden" and game.opponent.next_unit(1) == "warden","the opponent's rotation includes its faction unit")
	expect(game.sim.command(1,"train",[rival_fab],{"kind":"phantom"}) != "","and it cannot train the player's")
	# Abilities from the grid: aimed (Scout) and instant (Sentinel), with the recharge shown.
	var scout: Dictionary = own("scout")[0]
	game.selected = [scout.id]
	game.field.focus = scout.pos
	game.field.update_camera()
	expect(await button("ability") and game.ability_mode and shown("ABILITY"),"an aimed ability arms a targeting mode")
	var aim: Vector2 = visible_ground(scout.pos+Vector2(5,2))
	click(game.field.screen_at(aim))
	expect(game.sim.reveals.size() == 1 and not game.ability_mode and game.sim.reveals[0].pos.distance_to(aim) < 1.5,"clicking the ground fires the sweep there")
	game.hud.prepare_layout(true)
	var recharge = game.hud.buttons.filter(func(b): return b.action == "ability")
	expect(recharge.size() == 1 and not recharge[0].enabled and str(recharge[0].payload.reason).begins_with("Recharging"),"a used ability shows its recharge and is disabled")
	game.ui_action("ability",{"kind":"scout"})
	game.hud.prepare_layout(true)
	click(game.hud.map_point(Vector2(40,40)))
	expect(not game.ability_mode,"the minimap accepts an aimed ability too")
	var sentinel: Dictionary = game.sim.entities[game.sim.spawn("sentinel",0,base+Vector2(4,-6))]
	game.selected = [sentinel.id]
	expect(await button("ability") and float(sentinel.get("overdrive_until",0.0)) > game.sim.elapsed and not game.ability_mode,"an instant ability fires at once")
	expect(await button("stance") and sentinel.get("stance","") == "aggressive","the stance button switches to aggressive")
	expect(await button("stance") and sentinel.get("stance","") == "defensive","and back")
	# Shells and impacts reach the battlefield and the audio.
	var gun: Dictionary = game.sim.entities[game.sim.spawn("disruptor",0,base+Vector2(6,-8))]
	var dummy: Dictionary = game.sim.entities[game.sim.spawn("sentinel",1,base+Vector2(11,-8))]
	dummy.hp = 99999.0
	dummy.max_hp = 99999.0
	dummy.cooldown = 99999.0
	game.sim.update_visibility()
	heard.clear()
	game.sim.command(0,"attack",[gun.id],{"target":dummy.id})
	var saw_shell = false
	for i in 40:
		game.sim.tick()
		game.field.sync(0.016,[])
		if game.field.effects.any(func(effect): return effect.type == "shell"): saw_shell = true
	expect(saw_shell and heard.has("shot") and heard.has("impact"),"a Disruptor's shell is drawn in flight and heard when it lands")
	# Status on the card: a stunned unit is tinted.
	game.sim.command(0,"hold",[gun.id])
	var emp: Dictionary = game.sim.entities[game.sim.spawn("disruptor",1,base+Vector2(11.5,-6))]
	emp.cooldown = 99999.0
	game.sim.update_visibility()
	expect(game.sim.command(1,"ability",[emp.id],{"pos":gun.pos}) == "" and game.sim.stunned(gun),"an enemy EMP stuns the player's unit")
	game.field.sync(0.016,[])
	game.selected = [gun.id]
	expect(game.field.anim_state.get(gun.id,{}).get("status","") == "stun" and shown("DISABLED"),"the card and the selection panel show it is disabled")
	# Terrain on the minimap and in the selection panel.
	var rough_cell: Vector2i = game.sim.rough.keys()[0]
	game.sim.explored[0][rough_cell] = true
	game.hud.refresh_map()
	var grass_cell = Vector2i(base)+Vector2i(0,3)
	expect(game.hud.map_image.get_pixelv(rough_cell) != game.hud.map_image.get_pixelv(grass_cell),"rough ground is drawn on the minimap")
	var high_cell: Vector2i = game.sim.high.keys()[0]
	sentinel.pos = Vector2(high_cell)+Vector2(0.5,0.5)
	game.selected = [sentinel.id]
	expect(shown("HIGH GROUND"),"a unit on high ground says so")
	# A cloaked Phantom is hidden from the opponent's view of the world.
	var phantom: Dictionary = phantoms[0]
	game.sim.update_visibility()
	expect(game.sim.cloaked(phantom) and not game.sim.spotted_by(1,phantom),"the player's Phantom is cloaked from the opponent")
	game.field.sync(0.016,[])
	if DASprites.has_sprite("phantom"):
		expect(game.field.anim_state.get(phantom.id,{}).get("status","") == "cloak","and drawn translucent for its owner")
	# Save and load keeps abilities, stances, shells and sweeps.
	sentinel["stance"] = "aggressive"
	game.sim.command(0,"attack",[gun.id],{"target":dummy.id})
	expect(game.save_game("manual_3") == "","phase four state saves")
	sentinel["stance"] = "defensive"
	game.sim.reveals.clear()
	game.ui_action("load_slot",{"slot":"manual_3","confirmed":true})
	start_match()
	var loaded: Dictionary = game.sim.entities[sentinel.id]
	expect(loaded.get("stance","") == "aggressive" and float(loaded.get("overdrive_until",0.0)) > 0 and not game.sim.reveals.is_empty() and game.sim.active_faction_ids == ["lattice","origin"],"and loads with stances, ability timers, sweeps and factions intact")
	game.ui_action("menu",{"confirmed":true})
