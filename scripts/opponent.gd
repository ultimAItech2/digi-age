class_name DAOpponent
extends RefCounted
## Rule-based opponent: no resource grants and no knowledge of hidden entities.
## It acts on what its side has seen (sim.known / sim.seen), the map's public
## layout (start positions, deposits it has explored) and the same commands a player has.
const PROFILES := {
	"balanced": {"step_interval": 2.0, "worker_target": 17, "attack_start": 240.0, "attack_cooldown": 85.0, "min_army": 12, "scout_interval": 45.0, "age_army": 6, "fabricator_extra": 0, "research_order": ["weapons", "mining", "armor", "power", "fabrication", "sensors", "harvesting", "mobility", "reinforcement", "logistics", "construction", "fortification"]},
	"industrial": {"step_interval": 1.8, "worker_target": 20, "attack_start": 200.0, "attack_cooldown": 70.0, "min_army": 10, "scout_interval": 50.0, "age_army": 5, "fabricator_extra": 1, "research_order": ["mining", "harvesting", "logistics", "power", "fabrication", "weapons", "armor", "construction", "reinforcement", "mobility", "sensors", "fortification"]},
	"network": {"step_interval": 2.0, "worker_target": 14, "attack_start": 280.0, "attack_cooldown": 75.0, "min_army": 10, "scout_interval": 30.0, "age_army": 7, "fabricator_extra": 0, "research_order": ["sensors", "harvesting", "weapons", "mobility", "armor", "power", "fortification", "mining", "fabrication", "reinforcement", "logistics", "construction"]}
}
## Difficulty scales the profile's timings; Hard also gathers faster. No free resources.
const DIFFICULTIES := ["easy", "normal", "hard"]
const DIFFICULTY := {
	"easy": {"step_interval": 1.5, "attack_start": 1.6, "attack_cooldown": 1.5, "min_army": 1.3, "worker_target": 0.75, "gather": 1.0},
	"normal": {"gather": 1.0},
	"hard": {"step_interval": 0.7, "attack_start": 0.7, "attack_cooldown": 0.75, "min_army": 0.9, "worker_target": 1.2, "gather": 1.15}
}
## A deposit counts as served when a drop-off stands this close to it.
const DROP_OFF_REACH := 9.0
const MAX_DEPOTS := 4
var difficulty: String = "normal"
var sim: DASimulation
var side: int
var timer: float = 0.0
var assaults: int = 0
var last_attack: float = -100.0
var last_scout: float = -100.0
var train_index: int = 0
var retreats: int = 0
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
	var scale: Dictionary = DIFFICULTY.get(difficulty, {})
	for key in scale:
		if key != "gather" and merged.has(key):
			merged[key] = float(merged[key]) * float(scale[key])
	return merged

func set_difficulty(level: String) -> void:
	difficulty = level if DIFFICULTY.has(level) else "normal"
	sim.gather_scale[side] = float(DIFFICULTY[difficulty].get("gather", 1.0))

func serialize_state() -> Dictionary:
	return {"difficulty": difficulty, "timer": timer, "assaults": assaults, "last_attack": last_attack, "last_scout": last_scout, "train_index": train_index}

func restore_state(state: Dictionary) -> void:
	set_difficulty(str(state.get("difficulty", difficulty)))
	timer = float(state.get("timer", 0.0))
	assaults = int(state.get("assaults", 0))
	last_attack = float(state.get("last_attack", -100.0))
	last_scout = float(state.get("last_scout", -100.0))
	train_index = int(state.get("train_index", 0))

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
		# The Core fell: raise a new one where it stood before the window closes.
		if not workers.is_empty():
			build("core", workers)
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
	if not hq.complete:
		# Every hand to the new Core; nothing else can be trained or researched until it stands.
		for w in workers:
			if w.order not in ["build", "repair"]:
				sim.command(side, "repair", [w.id], {"target": hq.id})
		return
	for i in workers.size():
		var w = workers[i]
		if w.order in ["idle", "move"]:
			var resource = "data" if i % 4 == 3 else "metal"
			var candidates = deposits(resource)
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
	if count(buildings, "depot") < MAX_DEPOTS and depot_site(buildings).x >= 0 and (count(buildings, "depot") < 1 or reserves(buildings) < 1500.0):
		desired.append("depot")
	if age >= 1 and count(buildings, "tower") < 2:
		desired.append("tower")
	if (age >= 1 or workers.size() >= 8) and count(buildings, "lab") < 1:
		desired.append("lab")
	if age >= 2 and count(buildings, "lab") < 2:
		desired.append("lab")
	if count(buildings, "fabricator") < 2 + age + int(rules.get("fabricator_extra", 0)):
		desired.append("fabricator")
	if pending.is_empty() and not workers.is_empty() and not desired.is_empty():
		build(desired[0], workers, buildings)
	var save_for_age = age < mini(2, sim.tech_ceiling[side]) and sim.elapsed > 140 + age * 220 and army.size() >= int(rules.get("age_army", 6))
	if save_for_age and hq.research == "":
		sim.command(side, "research", [hq.id], {"kind": "age"})
	if not save_for_age or hq.research != "":
		var scouts: int = army.filter(func(e): return e.kind == "scout").size()
		for b in buildings:
			if b.kind == "fabricator" and b.complete and b.queue.size() < 2:
				# Eyes first: without a Scout nothing new is ever seen.
				var kind = "scout" if scouts == 0 and not b.queue.any(func(item): return item.kind == "scout") else next_unit(age)
				if sim.command(side, "train", [b.id], {"kind": kind}) == "":
					if kind == "scout": scouts += 1
					else: train_index += 1
	if not save_for_age and sim.resources[side].x > 500:
		var order: Array = rules.get("research_order", [])
		for b in buildings:
			if b.kind == "lab" and b.complete and b.research == "":
				for id in order:
					if sim.tech_error(side, str(id)) == "":
						sim.command(side, "research", [b.id], {"kind": str(id)})
						break
	use_abilities(army)
	var threats = sim.entities.values().filter(func(e): return e.owner == 1-side and sim.spotted_by(side, e) and e.pos.distance_to(hq.pos) < 19)
	if not threats.is_empty():
		for e in army:
			if e.pos.distance_to(hq.pos) < 30:
				sim.command(side, "attack_move", [e.id], {"pos": threats[0].pos})
		return
	if retreat(army, hq.pos):
		return
	# With the metal mined out and nothing left to spend, waiting for a larger army means waiting forever:
	# whatever is left goes in.
	var starved: bool = sim.resources[side].x < 200 and deposits("metal").is_empty()
	var needed: int = 1 if starved else int(rules.get("min_army", 12))
	if sim.elapsed > float(rules.get("attack_start", 240.0)) and sim.elapsed - last_attack > float(rules.get("attack_cooldown", 85.0)) and army.filter(func(e): return e.kind != "scout").size() >= needed:
		last_attack = sim.elapsed
		assaults += 1
		var target = attack_target(hq.pos)
		var expedition = army.filter(func(e): return e.pos.distance_to(hq.pos) < 27 and e.kind != "scout")
		# Late in a match, or with the population nearly full, everything goes: units left
		# in the field from earlier attacks rejoin, so the force arrives together.
		if sim.elapsed >= 1020 or sim.population(side) >= sim.capacity(side) - 6:
			expedition = army.filter(func(e): return e.kind != "scout")
		if sim.elapsed < 1020:
			expedition = expedition.filter(func(e): return e.kind != "walker")
			expedition = expedition.slice(0, mini(4 + age * 2, maxi(0, expedition.size() - 8)))
		if not expedition.is_empty():
			# Look before marching: a sweep over the target shows what is waiting there.
			var eyes = army.filter(func(e): return e.kind == "scout")
			if not eyes.is_empty():
				sim.command(side, "ability", [eyes[0].id], {"pos": target})
			sim.command(side, "attack_move", expedition.map(func(e): return e.id), {"pos": target})
	elif sim.elapsed - last_scout > float(rules.get("scout_interval", 45.0)):
		var scouts = army.filter(func(e): return e.kind == "scout")
		if not scouts.is_empty():
			last_scout = sim.elapsed
			sim.command(side, "move", [scouts[0].id], {"pos": scout_target(scouts[0].pos)})

## What to train next: the answer to what has been seen, otherwise the profile's rotation.
func next_unit(age: int) -> String:
	var seen: Dictionary = {}
	for e in sim.entities.values():
		if e.owner == 1 - side and not e.building and e.kind != "worker" and sim.spotted_by(side, e):
			seen[e.kind] = int(seen.get(e.kind, 0)) + 1
	var most = ""
	for kind in seen:
		if most == "" or seen[kind] > seen[most]:
			most = kind
	if most != "" and seen[most] >= 3 and train_index % 2 == 0:
		var answer = counter_to(most)
		if answer != "" and sim.catalog.units[answer].age <= age:
			return answer
	var kind = "sentinel"
	if age >= 1 and train_index % 3 == 1:
		kind = "disruptor"
	if age >= 2 and train_index % 4 == 0:
		kind = "walker"
	# The faction's own unit joins the rotation once its age is reached.
	var special = faction_unit()
	if special != "" and sim.catalog.units[special].age <= age and train_index % 5 == 2:
		kind = special
	return kind

## The unit only this side's faction fields, or "".
func faction_unit() -> String:
	for unit in sim.catalog.units:
		if sim.catalog.units[unit].has("faction") and sim.allowed(side, unit):
			return unit
	return ""

## Each unit's ability, by a simple rule: Sentinels overdrive when engaged, Disruptors
## EMP a cluster, Walkers brace to shell a building and release to move on.
func use_abilities(army: Array) -> void:
	for e in army:
		var spec: Dictionary = sim.catalog.abilities.get(e.kind, {})
		if spec.is_empty() or float(e.get("ability_ready", 0.0)) > sim.elapsed:
			continue
		var aim: int = e.get("aim", -1)
		var target: Dictionary = sim.entities[aim] if aim >= 0 and sim.entities.has(aim) and sim.spotted_by(side, sim.entities[aim]) else {}
		var reach: float = sim.attack_range(e) + (sim.catalog.buildings[target.kind].radius if not target.is_empty() and target.building else 0.0)
		match str(spec.id):
			"overdrive":
				if not target.is_empty() and e.pos.distance_to(target.pos) <= reach + 1.0:
					sim.command(side, "ability", [e.id])
			"emp":
				if not target.is_empty() and not target.building and e.pos.distance_to(target.pos) <= float(spec.reach):
					var caught = 0
					for other in sim.entities.values():
						if other.owner == 1 - side and not other.building and sim.spotted_by(side, other) and other.pos.distance_to(target.pos) <= float(spec.radius):
							caught += 1
					if caught >= 3:
						sim.command(side, "ability", [e.id], {"pos": target.pos})
			"brace":
				var braced: bool = e.get("braced", false)
				var shelling: bool = not target.is_empty() and target.building and e.pos.distance_to(target.pos) <= reach + (0.0 if braced else float(spec.range))
				if shelling != braced:
					sim.command(side, "ability", [e.id])

## The unit with the largest damage bonus against `kind`, from the catalog's counter table.
func counter_to(kind: String) -> String:
	var best = ""
	var bonus = 1.0
	for unit in sim.catalog.units:
		var value: float = sim.catalog.damage_bonus(unit, kind, false)
		if value > bonus:
			bonus = value
			best = unit
	return best

## Deposits this side has explored that still hold something.
func deposits(resource: String) -> Array:
	return sim.entities.values().filter(func(e): return e.owner == -1 and e.kind == resource and e.amount > 0 and sim.known(side, e))

func drop_offs(buildings: Array) -> Array:
	return buildings.filter(func(e): return e.kind in ["core", "depot"])

## Metal still in the ground within reach of a drop-off.
func reserves(buildings: Array) -> float:
	var total = 0.0
	var points = drop_offs(buildings)
	for d in deposits("metal"):
		if points.any(func(b): return b.pos.distance_to(d.pos) < DROP_OFF_REACH + 5.0):
			total += d.amount
	return total

## The nearest known deposit that no drop-off serves, or (-1, -1).
func depot_site(buildings: Array) -> Vector2:
	var points = drop_offs(buildings)
	var best = Vector2(-1, -1)
	var distance = INF
	for d in deposits("metal") + deposits("data"):
		if d.amount < 500 or points.any(func(b): return b.pos.distance_to(d.pos) < DROP_OFF_REACH):
			continue
		var gap = own_base().distance_squared_to(d.pos)
		if gap < distance:
			distance = gap
			best = d.pos
	return best

## Where to send an attack: the rival Core when it has been seen, else the nearest
## building it remembers, else the rival's start, which every player can read off the map.
func attack_target(from: Vector2) -> Vector2:
	var best = Vector2(-1, -1)
	var distance = INF
	for e in sim.entities.values():
		if e.owner != 1 - side or not e.building or not sim.known(side, e):
			continue
		if e.kind == "core":
			return e.pos
		var gap = from.distance_squared_to(e.pos)
		if gap < distance:
			distance = gap
			best = e.pos
	return best if best.x >= 0 else enemy_base()

## Where a Scout looks next: the rival's start until it has been seen, then the
## nearest deposit not yet explored, then a slow circuit of what is known.
func scout_target(from: Vector2) -> Vector2:
	if not sim.explored[side].has(Vector2i(enemy_base())):
		return enemy_base()
	var best = Vector2(-1, -1)
	var distance = INF
	for e in sim.entities.values():
		if e.owner == -1 and not sim.explored[side].has(Vector2i(e.pos)):
			var gap = from.distance_squared_to(e.pos)
			if gap < distance:
				distance = gap
				best = e.pos
	if best.x >= 0:
		return best
	var centre = Vector2.ONE * DASimulation.SIZE * 0.5
	var circuit = [centre, enemy_base(), centre + (centre - own_base()).orthogonal() * 0.6, centre - (centre - own_base()).orthogonal() * 0.6]
	return sim.clamp_point(circuit[int(sim.elapsed / 45) % circuit.size()])

## An expedition that meets twice its number in view falls back to the base.
func retreat(army: Array, home: Vector2) -> bool:
	# Late in a match the army is committed: falling back only prolongs a war of attrition.
	if sim.elapsed >= 1020:
		return false
	var away = army.filter(func(e): return e.kind != "scout" and e.order in ["attack_move", "attack"] and e.pos.distance_to(home) > 30)
	if away.is_empty():
		return false
	var centre = Vector2.ZERO
	for e in away:
		centre += e.pos
	centre /= away.size()
	var hostile = 0
	for e in sim.entities.values():
		if e.owner == 1 - side and sim.spotted_by(side, e) and e.pos.distance_to(centre) < 12 and (e.kind == "tower" or (not e.building and e.kind not in ["worker", "scout"])):
			hostile += 1
	if hostile < away.size() * 2:
		return false
	retreats += 1
	sim.command(side, "move", away.map(func(e): return e.id), {"pos": home})
	return true

func enemy_base() -> Vector2:
	return sim.bases[1 - side] if sim.bases.size() > 1 - side else Vector2(59, 36)

func own_base() -> Vector2:
	return sim.bases[side] if sim.bases.size() > side else Vector2(12, 36)

func count(items: Array, kind: String) -> int:
	return items.filter(func(e): return e.kind == kind).size()

func build(kind: String, workers: Array, buildings: Array = []) -> void:
	var center = own_base()
	var rings = [6, 10, 14, 18]
	if kind == "core":
		rings = [0, 4, 8, 12]
	elif kind == "depot":
		# Beside the deposit it will serve.
		var site = depot_site(buildings)
		if site.x < 0:
			return
		center = site
		rings = [4, 6, 8]
	elif kind == "tower":
		# On the way the rival will come from.
		center += (attack_target(center) - center).normalized() * 10.0
		rings = [0, 3, 6, 9]
	for radius in rings:
		for i in 16:
			var angle = i * TAU / 16.0
			var p = (center + Vector2(cos(angle), sin(angle)) * radius).round()
			if sim.placement_error(side, kind, p) == "":
				var candidates = workers.filter(func(e): return e.order not in ["build", "repair"])
				candidates.sort_custom(func(a, b): return a.pos.distance_squared_to(p) < b.pos.distance_squared_to(p))
				if not candidates.is_empty():
					sim.command(side, "build", [candidates[0].id], {"kind": kind, "pos": p})
				return
