class_name DAMissionController
extends RefCounted
## Owns authored objective state and translates simulation events into campaign events.
signal objective_updated(id: String, progress: float, target: float)
signal objective_completed(id: String)
signal mission_completed()
signal mission_failed(reason: String)
signal dialogue_requested(entry_id: String)
signal checkpoint_created(slot_id: String)
signal event_emitted(event_id: String)

var definition: DAMissionDefinition
var sim: DASimulation
var objective_state: Dictionary = {}
var completed: Dictionary = {}
var elapsed: float = 0.0
var active: bool = true
var mission_won: bool = false
var checkpoint: String = "opening"
var fired_events: Dictionary = {}

func setup(world: DASimulation, mission: DAMissionDefinition) -> void:
	sim = world
	definition = mission
	objective_state.clear()
	completed.clear()
	fired_events.clear()
	active = true
	mission_won = false
	elapsed = 0.0
	checkpoint = "opening"
	for objective in definition.objectives:
		objective_state[objective.id] = 0.0
		completed[objective.id] = false

func tick(dt: float) -> void:
	if not active or sim == null:
		return
	elapsed += dt
	if definition.time_limit > 0 and elapsed >= definition.time_limit:
		fail("Time limit reached.")
		return
	evaluate_events()
	for objective in definition.objectives:
		if completed.get(objective.id, false):
			continue
		var progress = progress_for(objective)
		objective_state[objective.id] = progress
		objective_updated.emit(objective.id, progress, float(objective.get("required", 1.0)))
		if progress >= float(objective.get("required", 1.0)):
			complete_objective(objective.id)
	if not active:
		return
	if sim.winner == 0:
		complete()
	elif sim.winner == 1:
		fail(definition.defeat_text)

func evaluate_events() -> void:
	if definition == null:
		return
	for event in definition.events:
		var event_id = str(event.get("id", ""))
		if event_id == "" or fired_events.get(event_id, false):
			continue
		if trigger_ready(event.get("trigger", {})):
			fire_event(event)

func trigger_ready(trigger: Dictionary) -> bool:
	if trigger.has("at_seconds") and elapsed >= float(trigger.at_seconds):
		return true
	if trigger.has("on_objective") and completed.get(str(trigger.on_objective), false):
		return true
	if trigger.has("on_checkpoint") and checkpoint == str(trigger.on_checkpoint):
		return true
	return false

func fire_event(event: Dictionary) -> void:
	var event_id = str(event.get("id", ""))
	fired_events[event_id] = true
	var kind = str(event.get("kind", ""))
	match kind:
		"dialogue":
			dialogue_requested.emit(str(event.get("entry", event_id)))
		"checkpoint":
			checkpoint = event_id
			checkpoint_created.emit(event_id)
		"grant_resources":
			var side = int(event.get("side", 0))
			var grant: Vector3 = event.get("resources", Vector3.ZERO)
			if side >= 0 and side < sim.resources.size():
				sim.resources[side] += grant
		"reveal":
			reveal_area(int(event.get("side", 0)), event.get("pos", Vector2(36, 36)), int(event.get("radius", 10)))
		"spawn_wave":
			spawn_wave(event)
		"ai_override":
			sim.ai_overrides.merge(event.get("profile", {}), true)
		"remove_kind":
			remove_kind(int(event.get("side", 0)), str(event.get("target", "")))
	event_emitted.emit(event_id)

func spawn_wave(event: Dictionary) -> void:
	var side = int(event.get("side", 1))
	var origin = wave_origin(event, side)
	for spec in event.get("units", []):
		var kind = str(spec.get("kind", "sentinel"))
		var count = int(spec.get("count", 1))
		var offset: Vector2 = spec.get("offset", Vector2.ZERO)
		for i in count:
			var spread = Vector2((i % 4) - 1.5, floori(i / 4.0)) * 1.4
			var id = sim.spawn(kind, side, origin + offset + spread)
			if event.get("order", "") == "attack_move" and sim.bases.size() > 1 - side:
				sim.set_order(sim.entities[id], "attack_move", sim.bases[1 - side])

func wave_origin(event: Dictionary, side: int) -> Vector2:
	if event.has("pos"):
		return event.pos
	var source = str(event.get("origin", "enemy"))
	if source == "player" and sim.bases.size() > 0:
		return sim.bases[0]
	if sim.bases.size() > side:
		return sim.bases[side]
	return Vector2(59, 36)

func reveal_area(side: int, pos: Vector2, radius: int) -> void:
	var p = Vector2i(pos)
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var c = p + Vector2i(dx, dy)
			if sim.navigation.is_in_boundsv(c):
				sim.visible[side][c] = true
				sim.explored[side][c] = true

func remove_kind(side: int, kind: String) -> void:
	for e in sim.entities.values():
		if e.owner == side and e.kind == kind:
			sim.remove_entity(e.id)

func progress_for(objective: Dictionary) -> float:
	var kind: String = objective.get("kind", "")
	var target: String = objective.get("target", "")
	match kind:
		"build":
			return sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == target and e.complete).size()
		"gather":
			return sim.resources[0].z if target == "data" else sim.resources[0].x
		"train":
			return sim.entities.values().filter(func(e): return e.owner == 0 and e.kind == target).size()
		"survive":
			return elapsed
		"age":
			return float(sim.ages[0])
		"explore":
			return float(sim.explored[0].size()) / float(DASimulation.SIZE * DASimulation.SIZE)
		"destroy":
			if target == "building":
				var structures = 0
				for building_kind in sim.catalog.buildings.keys():
					structures += int(sim.destroyed_counts[0].get(building_kind, 0))
				return structures
			if target == "outpost":
				return int(sim.destroyed_counts[0].get("tower", 0)) + int(sim.destroyed_counts[0].get("depot", 0))
			return int(sim.destroyed_counts[0].get(target, 0))
	return 0.0

func complete_objective(id: String) -> void:
	completed[id] = true
	checkpoint = id
	objective_completed.emit(id)
	checkpoint_created.emit(id)
	evaluate_events()
	var required_done = true
	for item in definition.objectives:
		if not item.get("optional", false) and not completed.get(item.id, false):
			required_done = false
	if required_done:
		complete()

func complete() -> void:
	if not active:
		return
	active = false
	mission_won = true
	mission_completed.emit()

func fail(reason: String) -> void:
	if not active:
		return
	active = false
	mission_won = false
	mission_failed.emit(reason)

func serialize_state() -> Dictionary:
	return {"mission_id": definition.mission_id if definition else "", "objective_state": objective_state.duplicate(true), "completed": completed.duplicate(true), "elapsed": elapsed, "active": active, "mission_won": mission_won, "checkpoint": checkpoint, "fired_events": fired_events.duplicate(true)}

func restore_state(state: Dictionary) -> String:
	if definition == null or state.get("mission_id", "") != definition.mission_id:
		return "Save belongs to a different mission."
	if not state.has("objective_state") or not state.has("completed"):
		return "Mission save is incomplete."
	objective_state = state.objective_state.duplicate(true)
	completed = state.completed.duplicate(true)
	elapsed = float(state.get("elapsed", 0.0))
	active = bool(state.get("active", true))
	mission_won = bool(state.get("mission_won", false))
	checkpoint = str(state.get("checkpoint", "opening"))
	fired_events = state.get("fired_events", {}).duplicate(true)
	return ""
