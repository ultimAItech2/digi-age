class_name DAOpponent
extends RefCounted
## Rule-based opponent: no resource grants and no knowledge of hidden entities.
const PROFILES := {
	"balanced": {"step_interval": 2.0, "worker_target": 17, "attack_start": 240.0, "attack_cooldown": 85.0, "min_army": 12, "scout_interval": 45.0, "age_army": 6, "fabricator_extra": 0},
	"industrial": {"step_interval": 1.8, "worker_target": 20, "attack_start": 200.0, "attack_cooldown": 70.0, "min_army": 10, "scout_interval": 50.0, "age_army": 5, "fabricator_extra": 1},
	"network": {"step_interval": 2.0, "worker_target": 14, "attack_start": 280.0, "attack_cooldown": 75.0, "min_army": 10, "scout_interval": 30.0, "age_army": 7, "fabricator_extra": 0}
}
var sim: DASimulation
var side: int
var timer: float = 0.0
var assaults: int = 0
var last_attack: float = -100.0
var last_scout: float = -100.0
var train_index: int = 0
var profile: Dictionary = {}

func _init(world: DASimulation, owner_id: int = 1) -> void:
	sim = world
	side = owner_id
	apply_profile("balanced")

func apply_profile(name: String) -> void:
	profile = PROFILES.get(name, PROFILES["balanced"]).duplicate()

func apply_overrides(overrides: Dictionary) -> void:
	for key in overrides:
		profile[key] = overrides[key]

func current_profile() -> Dictionary:
	var merged = profile.duplicate()
	merged.merge(sim.ai_overrides, true)
	return merged

func refresh_from_faction() -> void:
	if side >= 0 and side < sim.active_factions.size() and sim.active_factions[side]:
		apply_profile(sim.active_factions[side].ai_profile)

func step(dt: float) -> void:
	timer -= dt
	if timer > 0 or sim.winner >= 0:
		return
	var rules = current_profile()
	timer = float(rules.get("step_interval", 2.0))
	var own = sim.entities.values().filter(func(e): return e.owner == side)
	var workers = own.filter(func(e): return e.kind == "worker")
	var core = own.filter(func(e): return e.kind == "core")
	if core.is_empty():
		return
	var hq: Dictionary = core[0]
	var army = own.filter(func(e): return not e.building and e.kind != "worker")
	var buildings = own.filter(func(e): return e.building)
	var pending = buildings.filter(func(e): return not e.complete)
	if not pending.is_empty():
		var target = pending[0]
		var assigned = workers.filter(func(e): return e.order in ["build", "repair"] and e.target == target.id)
		if assigned.is_empty() and not workers.is_empty():
			sim.command(side, "repair", [workers[0].id], {"target": target.id})
	for i in workers.size():
		var w = workers[i]
		if w.order in ["idle", "move"]:
			var resource = "data" if i % 4 == 3 else "metal"
			var candidates = sim.entities.values().filter(func(e): return e.owner == -1 and e.kind == resource and e.amount > 0 and sim.known(side, e))
			candidates.sort_custom(func(a, b): return w.pos.distance_squared_to(a.pos) < w.pos.distance_squared_to(b.pos))
			if not candidates.is_empty():
				sim.command(side, "gather", [w.id], {"target": candidates[0].id})
	if workers.size() < int(rules.get("worker_target", 17)) and hq.queue.size() < 1:
		sim.command(side, "train", [hq.id], {"kind": "worker"})
	var desired: Array[String] = []
	var age = sim.ages[side]
	if count(buildings, "fabricator") < 1:
		desired.append("fabricator")
	if sim.population(side, true) >= sim.capacity(side) - 4 and sim.capacity(side) < 100:
		desired.push_front("data_center")
	if count(buildings, "generator") < 2 + age * 2:
		desired.append("generator")
	if count(buildings, "depot") < 1:
		desired.append("depot")
	if age >= 1 and count(buildings, "tower") < 2:
		desired.append("tower")
	if count(buildings, "fabricator") < 2 + age + int(rules.get("fabricator_extra", 0)):
		desired.append("fabricator")
	if pending.is_empty() and not workers.is_empty() and not desired.is_empty():
		build(desired[0], workers)
	var save_for_age = age < 2 and sim.elapsed > 140 + age * 220 and army.size() >= int(rules.get("age_army", 6))
	if save_for_age and hq.research == "":
		sim.command(side, "research", [hq.id], {"kind": "age"})
	if not save_for_age or hq.research != "":
		for b in buildings:
			if b.kind == "fabricator" and b.complete and b.queue.size() < 2:
				var kind = "sentinel"
				if age >= 1 and train_index % 3 == 1:
					kind = "disruptor"
				if age >= 2 and train_index % 4 == 0:
					kind = "walker"
				if sim.command(side, "train", [b.id], {"kind": kind}) == "":
					train_index += 1
	if age > sim.upgrades[side] and sim.resources[side].x > 650 and hq.research == "":
		sim.command(side, "research", [hq.id], {"kind": "weapons"})
	var threats = sim.entities.values().filter(func(e): return e.owner == 1-side and sim.seen(side, e.pos) and e.pos.distance_to(hq.pos) < 19)
	if not threats.is_empty():
		for e in army:
			if e.pos.distance_to(hq.pos) < 30:
				sim.command(side, "attack_move", [e.id], {"pos": threats[0].pos})
	elif sim.elapsed > float(rules.get("attack_start", 240.0)) and sim.elapsed - last_attack > float(rules.get("attack_cooldown", 85.0)) and army.size() >= int(rules.get("min_army", 12)):
		last_attack = sim.elapsed
		assaults += 1
		var target = enemy_base()
		var expedition = army.filter(func(e): return e.pos.distance_to(hq.pos) < 27)
		if sim.elapsed < 1020:
			expedition = expedition.filter(func(e): return e.kind in ["sentinel", "scout", "disruptor"])
			expedition = expedition.slice(0, mini(4 + age * 2, maxi(0, expedition.size() - 8)))
		if not expedition.is_empty():
			sim.command(side, "attack_move", expedition.map(func(e): return e.id), {"pos": target})
	elif sim.elapsed - last_scout > float(rules.get("scout_interval", 45.0)):
		var scouts = army.filter(func(e): return e.kind == "scout")
		if not scouts.is_empty():
			last_scout = sim.elapsed
			var waypoints = [Vector2(36, 35), Vector2(36, 8), enemy_base(), Vector2(36, 63)]
			sim.command(side, "move", [scouts[0].id], {"pos": waypoints[int(sim.elapsed / 45) % 4]})

func enemy_base() -> Vector2:
	return sim.bases[1 - side] if sim.bases.size() > 1 - side else Vector2(59, 36)

func own_base() -> Vector2:
	return sim.bases[side] if sim.bases.size() > side else Vector2(12, 36)

func count(items: Array, kind: String) -> int:
	return items.filter(func(e): return e.kind == kind).size()

func build(kind: String, workers: Array) -> void:
	var center = own_base()
	if kind == "depot":
		center += Vector2(8 if side == 0 else -8, 0)
	if kind == "tower":
		center += Vector2(12 if side == 0 else -12, 0)
	for radius in [6, 10, 14, 18]:
		for i in 16:
			var angle = i * TAU / 16.0
			var p = (center + Vector2(cos(angle), sin(angle)) * radius).round()
			if sim.placement_error(side, kind, p) == "":
				var candidates = workers.filter(func(e): return e.order not in ["build", "repair"])
				candidates.sort_custom(func(a, b): return a.pos.distance_squared_to(p) < b.pos.distance_squared_to(p))
				if not candidates.is_empty():
					sim.command(side, "build", [candidates[0].id], {"kind": kind, "pos": p})
				return
