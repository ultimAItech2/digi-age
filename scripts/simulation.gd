class_name DASimulation
extends RefCounted
## Authoritative, renderer-independent fixed-tick simulation.
signal shot(from: Vector2, to: Vector2, owner: int, kind: String)
signal destroyed(position: Vector2, kind: String)
signal notice(message: String)
## Something a side should be told about: kind, where, which side, and a detail such as the unit kind.
signal alert(kind: String, pos: Vector2, side: int, detail: String)
## A shell landing or an area effect going off: where, which weapon or ability, how wide.
signal impact(pos: Vector2, kind: String, radius: float)
const ALERT_SPACING: float = 8.0
const ALERT_RADIUS: float = 12.0
const CORE_GRACE: float = 120.0
const RETASK_RADIUS: float = 14.0
## How far from its post an aggressive unit will chase.
const LEASH: float = 12.0
## Unit kinds with a cloak or an aura, read once from the catalog.
var cloak_kinds: Dictionary = {}
var aura_kinds: Dictionary = {}
const SIZE: int = 72
var bases: Array[Vector2] = [Vector2(12, 36), Vector2(59, 36)]
var catalog: DACatalog = preload("res://data/catalog.tres")
var entities: Dictionary = {}
var resources: Array[Vector3] = []
## Transient income tracking: resources credited during the current window, and the last per-minute rate.
var income: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var income_rate: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var income_window: float = 0.0
var ages: Array[int] = [0, 0]
## Research tree levels per side: {upgrade id: level 0-5}.
var tech: Array[Dictionary] = [{}, {}]
var visible: Array = []
var explored: Array = []
## Enemy buildings each side has seen at least once: they stay known in the fog.
var remembered: Array = [{}, {}]
var obstacles: Dictionary = {}
var navigation: AStarGrid2D
var next_id: int = 1
var elapsed: float = 0.0
var winner: int = -1
var ticks: int = 0
var stats: Array[Dictionary] = [{"kills": 0, "gathered": 0.0}, {"kills": 0, "gathered": 0.0}]
var destroyed_counts: Array[Dictionary] = [{}, {}]
var active_mission_id: String = "skirmish"
var active_map_id: String = "silent_grid"
var active_faction_ids: Array[String] = ["origin", "foundry"]
var active_map: DAMapDefinition
var active_factions: Array[DAFactionDefinition] = []
var ai_overrides: Dictionary = {}
## Transient: owned entities by 8-cell block, rebuilt every tick for target searches.
const BLOCK: float = 8.0
var blocks: Array = [{}, {}]
var blocks_tick: int = -1
var circle_cache: Dictionary = {}
## Shells in flight: {from, to, target, owner, kind, building, braced, left}.
var projectiles: Array = []
## Timed reveals from Sensor sweeps: {side, pos, radius, until}.
var reveals: Array = []
## Map terrain by cell, from the active map.
var roads: Dictionary = {}
var rough: Dictionary = {}
var high: Dictionary = {}
## Transient: units with an aura, per side, rebuilt with the blocks.
var auras: Array = [[], []]
## Presentation only: side colours that replace the factions' (the colour-blind option). Not saved.
var color_override: Array[Color] = []
## Highest age each side may reach in this match (mission technology ceiling).
var tech_ceiling: Array[int] = [2, 2]
## Per-side gather multiplier (the opponent's difficulty setting).
var gather_scale: Array[float] = [1.0, 1.0]
## When a side without a Core loses the match unless it rebuilds one; -1 when it has a Core.
var core_deadline: Array[float] = [-1.0, -1.0]
## Transient: recent under-attack alerts per side, and the last population-cap alert.
var attack_alerts: Array = [[], []]
var cap_alert: Array[float] = [-100.0, -100.0]

func _init() -> void:
	for kind in catalog.units:
		if catalog.units[kind].has("cloak"): cloak_kinds[kind] = float(catalog.units[kind].cloak)
		if catalog.units[kind].has("aura"): aura_kinds[kind] = true
	for side in 2:
		resources.append(catalog.starting_resources)
		visible.append({})
		explored.append({})
	var map = load("res://data/maps/silent_grid.tres") as DAMapDefinition
	if map:
		build_from_map(map)
	else:
		rebuild_navigation()
		_legacy_default_layout()
		update_visibility()

func rebuild_navigation() -> void:
	navigation = AStarGrid2D.new()
	navigation.region = Rect2i(0, 0, SIZE, SIZE)
	navigation.cell_size = Vector2.ONE
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for cell in obstacles:
		navigation.set_point_solid(cell)
	for cell in rough:
		if navigation.is_in_boundsv(cell):
			navigation.set_point_weight_scale(cell, float(catalog.terrain.get("rough_weight", 1.6)))

## Roads, rough ground and high ground from the active map.
func load_terrain() -> void:
	roads.clear()
	rough.clear()
	high.clear()
	if active_map == null:
		return
	for band in active_map.road_bands:
		var low: int = int(band.get("min", 0))
		var top: int = int(band.get("max", -1))
		for i in SIZE:
			for j in range(low, top + 1):
				roads[Vector2i(i, j) if str(band.get("axis", "y")) == "y" else Vector2i(j, i)] = true
	for cell in active_map.rough_cells:
		rough[cell] = true
		if navigation and navigation.is_in_boundsv(cell):
			navigation.set_point_weight_scale(cell, float(catalog.terrain.get("rough_weight", 1.6)))
	for cell in active_map.high_cells:
		high[cell] = true

func on_high_ground(e: Dictionary) -> bool:
	return not e.building and high.has(Vector2i(e.pos))

## Speed multiplier of the ground under a unit; hovering units ignore rough ground.
func ground_speed(e: Dictionary) -> float:
	var cell = Vector2i(e.pos)
	if rough.has(cell) and not catalog.units[e.kind].get("hover", false):
		return float(catalog.terrain.get("rough_speed", 0.65))
	if roads.has(cell):
		return float(catalog.terrain.get("road_speed", 1.25))
	return 1.0

func clear_world() -> void:
	entities.clear()
	obstacles.clear()
	projectiles.clear()
	reveals.clear()
	roads.clear()
	rough.clear()
	high.clear()
	next_id = 1
	reset_income()
	visible = [{}, {}]
	explored = [{}, {}]
	remembered = [{}, {}]
	rebuild_navigation()

func reset_income() -> void:
	income = [Vector3.ZERO, Vector3.ZERO]
	income_rate = [Vector3.ZERO, Vector3.ZERO]
	income_window = 0.0

func credit(side: int, delta: Vector3) -> void:
	resources[side] += delta
	income[side] += delta

func income_per_minute(side: int) -> Vector3:
	return income_rate[side]

func faction_modifier(side: int, key: String, default: float = 1.0) -> float:
	if side < 0 or side >= active_factions.size() or active_factions[side] == null:
		return default
	return float(active_factions[side].modifiers.get(key, default))

func tech_level(side: int, id: String) -> int:
	if side < 0 or side >= tech.size():
		return 0
	return int(tech[side].get(id, 0))

## Sum of level × per-level amount over every upgrade that carries this effect key.
func tech_modifier(side: int, key: String) -> float:
	if side < 0 or side >= tech.size() or tech[side].is_empty():
		return 0.0
	var total = 0.0
	for id in tech[side]:
		var effects: Dictionary = catalog.tech.get(id, {}).get("effects", {})
		total += int(tech[side][id]) * float(effects.get(key, 0.0))
	return total

func researching(side: int, id: String) -> bool:
	for e in entities.values():
		if e.owner == side and e.building and e.research == id:
			return true
	return false

## Why the next level of an upgrade cannot start now, or "" when it can.
func tech_error(side: int, id: String) -> String:
	if not catalog.tech.has(id):
		return "Unknown research."
	var level = tech_level(side, id)
	if level >= DACatalog.TECH_MAX_LEVEL:
		return "Fully researched."
	var required = DACatalog.tech_age_for_level(level + 1)
	if ages[side] < required:
		return "Requires the " + catalog.ages[required].capitalize() + " age."
	if researching(side, id):
		return "Already being researched."
	if not can_pay(side, catalog.tech_cost(id, level + 1)):
		return "Insufficient resources."
	return ""

func cargo_capacity(side: int) -> float:
	return 24.0 + tech_modifier(side, "cargo")

func attack_range(e: Dictionary) -> float:
	var base: float = catalog.definition(e.kind).get("range", 0.0)
	if e.building:
		return base + tech_modifier(e.owner, "tower_range")
	base *= 1.0 + tech_modifier(e.owner, "unit_range")
	if e.get("braced", false):
		base += float(catalog.abilities.get(e.kind, {}).get("range", 0.0))
	if on_high_ground(e):
		base += float(catalog.terrain.get("high_range", 1.0))
	return base

func vision_radius(e: Dictionary) -> float:
	var base: float = catalog.definition(e.kind).get("vision", 0.0) * faction_modifier(e.owner, "vision_radius", 1.0)
	if e.building:
		return base
	base *= 1.0 + tech_modifier(e.owner, "unit_vision")
	if on_high_ground(e):
		base += float(catalog.terrain.get("high_vision", 2.0))
	return base

## Reinforcement research raises every standing building's maximum integrity.
func rescale_building_health(side: int) -> void:
	var bonus = 1.0 + tech_modifier(side, "building_health")
	for e in entities.values():
		if e.owner == side and e.building:
			var new_max: float = catalog.buildings[e.kind].hp * bonus
			e.hp = minf(new_max, e.hp + (new_max - e.max_hp))
			e.max_hp = new_max

func faction_color(side: int) -> Color:
	if not color_override.is_empty() and side >= 0 and side < color_override.size():
		return color_override[side]
	if side < 0 or side >= active_factions.size() or active_factions[side] == null:
		return Color("57ebd5") if side == 0 else Color("ff795c")
	var color: Color = active_factions[side].primary_color
	# Two sides of the same faction: the second takes the opposite hue so they can be told apart.
	if side == 1 and active_factions[0] != null and active_factions[0].faction_id == active_factions[1].faction_id:
		color = Color.from_hsv(fposmod(color.h + 0.5, 1.0), color.s, color.v)
	return color

## `symmetric` gives both sides the same opening (a Core, four Workers, a Scout)
## in place of the map's authored units and structures; `swap` trades the starts.
func build_from_map(map: DAMapDefinition, symmetric: bool = false, swap: bool = false) -> void:
	clear_world()
	active_map = map
	load_terrain()
	if map:
		active_map_id = map.map_id
		if map.starts.size() >= 2:
			bases = [map.starts[0], map.starts[1]]
			if swap:
				bases = [map.starts[1], map.starts[0]]
		for cell in map.obstacle_cells:
			obstacles[cell] = true
			if navigation.is_in_boundsv(cell):
				navigation.set_point_solid(cell)
		for node in map.resource_nodes:
			spawn_resource(str(node.get("kind", "metal")), node.get("pos", Vector2.ZERO), float(node.get("amount", 5000.0)))
		if symmetric:
			for side in 2:
				spawn("core", side, bases[side])
				for i in 4:
					spawn("worker", side, Vector2(nearest_open(bases[side] + Vector2(-2 + i * 1.3, 5))))
				spawn("scout", side, Vector2(nearest_open(bases[side] + Vector2(0, 7))))
		elif map.starting_units.is_empty():
			_legacy_default_units()
		else:
			for unit in map.starting_units:
				var side = int(unit.get("side", 0))
				var origin = bases[side] if side >= 0 and side < bases.size() else Vector2.ZERO
				spawn(str(unit.get("kind", "worker")), side, origin + unit.get("offset", Vector2.ZERO), bool(unit.get("complete", true)))
		for item in ([] if symmetric else map.prebuilt):
			spawn(str(item.get("kind", "tower")), int(item.get("side", 1)), item.get("pos", Vector2.ZERO), bool(item.get("complete", true)))
	else:
		_legacy_default_layout()
	update_visibility()

func _legacy_default_units() -> void:
	for side in 2:
		var b = bases[side]
		spawn("core", side, b)
		spawn("generator", side, b + Vector2(0, -7))
		for i in 5:
			spawn("worker", side, b + Vector2(-3 + i, 5))
		spawn("scout", side, b + Vector2(0, 8))

func _legacy_default_layout() -> void:
	for x in range(29, 43):
		for y in [17, 18, 19, 51, 52, 53]:
			obstacles[Vector2i(x, y)] = true
			navigation.set_point_solid(Vector2i(x, y))
	_legacy_default_units()
	for side in 2:
		var b = bases[side]
		var sign_x = 1 if side == 0 else -1
		for offset in [Vector2(-5, -11), Vector2(8, 10), Vector2(8, -14)]:
			spawn_resource("metal", b + Vector2(offset.x * sign_x, offset.y), 6500.0)
		spawn_resource("data", b + Vector2(13 * sign_x, -4), 4000.0)
	for p in [Vector2(36, 8), Vector2(36, 35), Vector2(36, 63)]:
		spawn_resource("data", p, 7000.0)
	for p in [Vector2(24, 28), Vector2(47, 28), Vector2(24, 44), Vector2(47, 44)]:
		spawn_resource("metal", p, 5000.0)

func spawn_resource(kind: String, p: Vector2, amount: float) -> int:
	var id = next_id
	next_id += 1
	entities[id] = {"id": id, "kind": kind, "owner": -1, "pos": p, "amount": amount, "hp": 1.0, "max_hp": 1.0, "building": false, "complete": true}
	return id

func spawn(kind: String, side: int, p: Vector2, complete: bool = true) -> int:
	var d = catalog.definition(kind)
	var id = next_id
	next_id += 1
	var building = catalog.buildings.has(kind)
	var hp: float = d.hp
	if building:
		hp *= 1.0 + tech_modifier(side, "building_health")
	else:
		hp *= faction_modifier(side, "unit_health", 1.0)
	var build_left: float = 0.0 if complete else d.time * faction_modifier(side, "build_speed", 1.0)
	entities[id] = {"id": id, "kind": kind, "owner": side, "pos": p, "hp": hp if complete else hp * 0.15, "max_hp": hp, "building": building, "complete": complete, "build_left": build_left, "order": "idle", "target": -1, "destination": p, "path": [], "path_goal": Vector2(-999, -999), "path_retry": 0.0, "cargo": 0.0, "cargo_kind": "metal", "source": -1, "cooldown": 0.0, "queue": [], "research": "", "research_left": 0.0, "rally": p + Vector2(0, 4)}
	if building:
		set_footprint(p, d.radius, true)
	return id

func set_footprint(p: Vector2, radius: int, solid: bool) -> void:
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var cell = Vector2i(p) + Vector2i(x, y)
			if navigation.is_in_boundsv(cell):
				navigation.set_point_solid(cell, solid or obstacles.has(cell))
	# Routes must be recomputed when the occupancy grid changes.
	for e in entities.values():
		if e.owner >= 0 and not e.building:
			e.path_goal = Vector2(-999, -999)

func population(side: int, include_queued: bool = false) -> int:
	var count = 0
	for e in entities.values():
		if e.owner == side:
			if not e.building:
				count += 1
			elif include_queued:
				count += e.queue.size()
	return count

func capacity(side: int) -> int:
	var total = 0
	for e in entities.values():
		if e.owner == side and e.building and e.complete:
			total += catalog.buildings[e.kind].capacity
	return mini(total, catalog.population_limit)

func can_pay(side: int, cost: Vector3) -> bool:
	var r = resources[side]
	return r.x >= cost.x and r.y >= cost.y and r.z >= cost.z

func pay(side: int, cost: Vector3) -> bool:
	if not can_pay(side, cost):
		return false
	resources[side] -= cost
	return true

func seen(side: int, p: Vector2) -> bool:
	return visible[side].has(Vector2i(p))

func known(side: int, e: Dictionary) -> bool:
	if e.owner == side:
		return true
	if e.owner == -1:
		return explored[side].has(Vector2i(e.pos))
	if e.building:
		return seen(side, e.pos) or remembered[side].has(e.id)
	return seen(side, e.pos) and not cloaked(e)

## A cloaked unit nobody has spotted: invisible to the other side and not a target.
func cloaked(e: Dictionary) -> bool:
	return cloak_kinds.has(e.kind) and not e.get("spotted", false) and e.get("reveal_until", 0.0) <= elapsed

## True when `side` currently sees this entity and may act on it.
func spotted_by(side: int, e: Dictionary) -> bool:
	return seen(side, e.pos) and not cloaked(e)

## Whether a side's faction fields this unit or building.
func allowed(side: int, kind: String) -> bool:
	var faction: DAFactionDefinition = active_factions[side] if side >= 0 and side < active_factions.size() else null
	if catalog.units.has(kind):
		if faction == null:
			return not catalog.units[kind].has("faction")
		return faction.roster.has(kind)
	return kind == "core" or faction == null or faction.buildings.has(kind)

func placement_error(side: int, kind: String, pos: Vector2) -> String:
	if not catalog.buildings.has(kind):
		return "Select a constructible building."
	if kind == "core" and has_core(side, false):
		return "Your civilization already has a Core."
	if not allowed(side, kind):
		return "Your faction does not build this."
	var d = catalog.buildings[kind]
	if ages[side] < d.age:
		return "Requires the " + catalog.ages[d.age].capitalize() + " age."
	var p = Vector2i(pos.round())
	var r: int = d.radius
	for x in range(-r - 1, r + 2):
		for y in range(-r - 1, r + 2):
			var c = p + Vector2i(x, y)
			if not navigation.is_in_boundsv(c):
				return "Outside the buildable map."
			if not explored[side].has(c):
				return "Explore this area first."
			if navigation.is_point_solid(c):
				return "Leave space between buildings and terrain."
	for e in entities.values():
		if e.owner == -1 and e.pos.distance_to(Vector2(p)) < r + 2.5:
			return "Resource deposits need clear access."
		if e.owner >= 0 and not e.building and absf(e.pos.x-p.x) <= r+0.4 and absf(e.pos.y-p.y) <= r+0.4:
			return "A unit is occupying the site."
	if not can_pay(side, d.cost):
		return "Insufficient resources."
	return ""

func has_core(side: int, complete_only: bool = true) -> bool:
	for e in entities.values():
		if e.owner == side and e.kind == "core" and (e.complete or not complete_only):
			return true
	return false

func worker_count(side: int) -> int:
	var count = 0
	for e in entities.values():
		if e.owner == side and e.kind == "worker":
			count += 1
	return count

## At most one under-attack alert per ALERT_SPACING seconds within ALERT_RADIUS cells.
func alert_attack(side: int, pos: Vector2) -> void:
	if side < 0:
		return
	var recent: Array = attack_alerts[side].filter(func(a): return elapsed - a.time < ALERT_SPACING)
	attack_alerts[side] = recent
	for a in recent:
		if a.pos.distance_to(pos) < ALERT_RADIUS:
			return
	recent.append({"time": elapsed, "pos": pos})
	alert.emit("under_attack", pos, side, "")

func command(side: int, action: String, ids: Array, payload: Dictionary = {}) -> String:
	if winner >= 0:
		return "The match has ended."
	if side < 0 or side > 1:
		return "Invalid civilization."
	var owned: Array = []
	for id in ids:
		if entities.has(id) and entities[id].owner == side:
			owned.append(entities[id])
	if owned.is_empty():
		return "Select one of your units or buildings."
	if action == "hold" and owned.all(func(e): return e.building):
		return "Select mobile units to hold position."
	var first: Dictionary = owned[0]
	if action == "build":
		var kind: String = payload.get("kind", "")
		var p: Vector2 = payload.get("pos", Vector2.ZERO).round()
		var error = placement_error(side, kind, p)
		if error != "":
			return error
		var workers = owned.filter(func(e): return e.kind == "worker")
		if workers.is_empty():
			return "Select a Worker to construct buildings."
		var reachable = false
		for worker in workers:
			if reachable_point(worker.pos, p).distance_to(p) <= catalog.buildings[kind].radius + 2:
				reachable = true
		if not reachable:
			return "Workers cannot reach this site."
		pay(side, catalog.buildings[kind].cost)
		var id = spawn(kind, side, p, false)
		for worker in workers:
			set_order(worker, "build", p, id)
		alert.emit("construction_started", p, side, kind)
		return ""
	if action == "train":
		var kind: String = payload.get("kind", "")
		if not catalog.units.has(kind) or not first.building or not first.complete:
			return "Select a completed production building."
		if (kind == "worker" and first.kind != "core") or (kind != "worker" and first.kind != "fabricator"):
			return "This building cannot produce that unit."
		if not allowed(side, kind):
			return "Your faction does not field this unit."
		var d = catalog.units[kind]
		if ages[side] < d.age:
			return "Advance to the required age first."
		if first.queue.size() >= 5:
			return "Production queue is full."
		if population(side, true) >= capacity(side):
			return "Compute limit reached. Build a Data Center."
		if not pay(side, d.cost):
			return "Insufficient resources."
		first.queue.append({"kind": kind, "left": d.time})
		return ""
	if action == "research":
		if not first.building or not first.complete:
			return "Select a completed Core or Research Lab."
		if first.research != "":
			return "Research is already underway here."
		var kind: String = payload.get("kind", "age")
		if first.kind == "core":
			if kind != "age":
				return "Ages are researched at the Core; technologies at a Research Lab."
			var level = ages[side]
			if level >= 2:
				return "The Singularity is the final age."
			if level >= tech_ceiling[side]:
				return "This operation is limited to the " + catalog.ages[level].capitalize() + " age."
			if not pay(side, catalog.age_costs[level]):
				return "Insufficient resources."
			first.research = kind
			first.research_left = catalog.age_times[level] * faction_modifier(side, "research_speed", 1.0)
			alert.emit("research_started", first.pos, side, kind)
			return ""
		if first.kind != "lab":
			return "This building cannot research."
		var error = tech_error(side, kind)
		if error != "":
			return error
		var next = tech_level(side, kind) + 1
		pay(side, catalog.tech_cost(kind, next))
		first.research = kind
		first.research_left = catalog.tech_time(kind, next) * faction_modifier(side, "research_speed", 1.0)
		alert.emit("research_started", first.pos, side, kind)
		return ""
	if action == "cancel":
		if not first.building:
			return "Select a building to cancel its work."
		if not first.queue.is_empty():
			var slot: int = int(payload.get("index", first.queue.size() - 1))
			if slot < 0 or slot >= first.queue.size():
				return "Nothing is queued in that slot."
			resources[side] += catalog.units[first.queue[slot].kind].cost
			first.queue.remove_at(slot)
			return ""
		if first.research != "":
			refund_research(first)
			first.research = ""
			first.research_left = 0.0
			return ""
		return "Nothing to cancel."
	if action == "rally":
		for e in owned:
			if e.building:
				e.rally = clamp_point(payload.get("pos", e.pos))
		return ""
	if action == "stance":
		var stance: String = str(payload.get("stance", "defensive"))
		if stance not in ["defensive", "aggressive"]:
			return "Unknown stance."
		for e in owned:
			if not e.building and e.kind != "worker":
				e["stance"] = stance
		return ""
	if action == "ability":
		var reason = "No selected unit has an ability."
		var used = 0
		for e in owned:
			var spec: Dictionary = catalog.abilities.get(e.kind, {})
			if e.building or spec.is_empty():
				continue
			if float(e.get("ability_ready", 0.0)) > elapsed:
				reason = "Ability is recharging."
				continue
			var error = use_ability(e, spec, payload)
			if error != "":
				reason = error
				continue
			e["ability_ready"] = elapsed + float(spec.get("cooldown", 30.0))
			used += 1
			# One aimed ability per order; the rest of the group keeps theirs.
			if spec.get("targeted", false):
				break
		return "" if used > 0 else reason
	if action in ["move", "attack_move", "patrol"]:
		var movers = owned.filter(func(e): return not e.building)
		if not movers.is_empty() and reachable_point(movers[0].pos, clamp_point(payload.get("pos", movers[0].pos))).x < 0:
			return "No route to that location."
	var index = 0
	for e in owned:
		if e.building:
			continue
		if action == "hold":
			set_order(e, "hold", e.pos)
		elif action == "stop":
			set_order(e, "idle", e.pos)
		elif action in ["move", "attack_move", "patrol"]:
			var offset = Vector2((index % 5) - 2, floori(index / 5.0)) * 1.1 if owned.size() > 1 else Vector2.ZERO
			set_order(e, action, clamp_point(payload.get("pos", e.pos) + offset))
			if action == "patrol":
				e["patrol_from"] = e.pos
		elif action in ["gather", "attack", "build", "repair"]:
			var target: int = payload.get("target", -1)
			if not entities.has(target) or not known(side, entities[target]):
				return "Target is outside your vision."
			var t = entities[target]
			if action == "gather" and (e.kind != "worker" or t.owner != -1 or t.amount <= 0):
				continue
			if action == "attack" and (t.owner < 0 or t.owner == side):
				continue
			if action == "repair" and (e.kind != "worker" or t.owner != side or not t.building):
				continue
			set_order(e, action, t.pos, target)
			if action == "gather":
				e.source = target
		index += 1
	return ""

func use_ability(e: Dictionary, spec: Dictionary, payload: Dictionary) -> String:
	var id: String = str(spec.get("id", ""))
	var pos: Vector2 = clamp_point(payload.get("pos", e.pos))
	if spec.get("targeted", false) and e.pos.distance_to(pos) > float(spec.get("reach", 0.0)):
		return "Out of range. Move closer."
	if stunned(e):
		return "This unit is disabled."
	match id:
		"sweep":
			reveals.append({"side": e.owner, "pos": pos, "radius": float(spec.radius), "until": elapsed + float(spec.duration)})
			update_visibility()
		"overdrive":
			e["overdrive_until"] = elapsed + float(spec.duration)
		"emp":
			for target in entities.values():
				if target.owner == 1 - e.owner and not target.building and target.pos.distance_to(pos) <= float(spec.radius):
					target["stunned_until"] = elapsed + float(spec.duration)
					alert_attack(target.owner, target.pos)
			impact.emit(pos, "emp", float(spec.radius))
		"brace":
			e["braced"] = not e.get("braced", false)
			if e.braced:
				set_order(e, "idle", e.pos)
		_:
			return "Unknown ability."
	alert.emit("ability", pos, e.owner, id)
	return ""

func stunned(e: Dictionary) -> bool:
	return float(e.get("stunned_until", 0.0)) > elapsed

func clamp_point(p: Vector2) -> Vector2:
	return p.clamp(Vector2.ONE, Vector2(SIZE - 2, SIZE - 2))

func set_order(e: Dictionary, order: String, p: Vector2, target: int = -1) -> void:
	e.order = order
	e.destination = Vector2(nearest_open(p)) if order in ["move", "attack_move", "patrol"] else p
	e.target = target
	e.path = []
	e.path_goal = Vector2(-999, -999)
	e.path_retry = 0.0

func nearest_open(p: Vector2) -> Vector2i:
	var c = Vector2i(clamp_point(p).round())
	for r in 9:
		var best = Vector2i(-1, -1)
		var distance = INF
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				if r > 0 and abs(x) != r and abs(y) != r:
					continue
				var q = c + Vector2i(x, y)
				if navigation.is_in_boundsv(q) and not navigation.is_point_solid(q):
					var d = Vector2(q).distance_squared_to(p)
					if d < distance:
						distance = d
						best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

func reachable_point(from: Vector2, to: Vector2) -> Vector2:
	var a = nearest_open(from)
	var b = nearest_open(to)
	if a.x < 0 or b.x < 0:
		return Vector2(-999, -999)
	var path = navigation.get_id_path(a, b)
	return Vector2(path[-1]) if not path.is_empty() else Vector2(-999, -999)

func walk(e: Dictionary, destination: Vector2, dt: float, stop_distance: float = 0.5) -> bool:
	if e.pos.distance_to(destination) <= stop_distance:
		return true
	if e.get("braced", false):
		return false
	e.path_retry -= dt
	if e.path_goal.distance_to(destination) > 1.0 or (e.path.is_empty() and e.path_retry <= 0.0):
		var a = nearest_open(e.pos)
		var b = nearest_open(destination)
		e.path = []
		if a.x >= 0 and b.x >= 0:
			for c in navigation.get_id_path(a, b):
				e.path.append(Vector2(c))
			if e.path.size() > 1:
				e.path.pop_front()
		e.path_goal = destination
		e.path_retry = 1.0
	if e.path.is_empty():
		return false
	var next: Vector2 = e.path[0]
	if navigation.is_point_solid(Vector2i(next)):
		e.path_goal = Vector2(-999, -999)
		return false
	var speed: float = catalog.units[e.kind].speed * (1.0 + tech_modifier(e.owner, "worker_speed" if e.kind == "worker" else "unit_speed")) * ground_speed(e)
	e.pos = e.pos.move_toward(next, speed * dt)
	if e.pos.distance_to(next) < 0.1:
		e.path.pop_front()
	return e.pos.distance_to(destination) <= stop_distance

func nearest_depot(side: int, p: Vector2) -> int:
	var best = -1
	var distance = INF
	for e in entities.values():
		if e.owner == side and e.complete and e.kind in ["core", "depot"]:
			var d = e.pos.distance_squared_to(p)
			if d < distance:
				distance = d
				best = e.id
	return best

func rebuild_blocks() -> void:
	blocks = [{}, {}]
	auras = [[], []]
	blocks_tick = ticks
	for e in entities.values():
		if e.owner < 0:
			continue
		if aura_kinds.has(e.kind):
			auras[e.owner].append(e)
		var key = Vector2i((e.pos / BLOCK).floor())
		var side_blocks: Dictionary = blocks[e.owner]
		if side_blocks.has(key):
			side_blocks[key].append(e)
		else:
			side_blocks[key] = [e]

## Nearest visible enemy within `radius`; of two at the same distance, the older one.
## Searches only the blocks the circle touches (with a cell of slack for this tick's movement).
func closest_enemy(e: Dictionary, radius: float) -> int:
	if blocks_tick != ticks:
		rebuild_blocks()
	var best = -1
	var distance = radius * radius
	var low = Vector2i(((e.pos - Vector2.ONE * (radius + 1.0)) / BLOCK).floor())
	var high = Vector2i(((e.pos + Vector2.ONE * (radius + 1.0)) / BLOCK).floor())
	var mine: Dictionary = visible[e.owner]
	var hostile: Dictionary = blocks[1 - e.owner]
	if hostile.is_empty():
		return -1
	for bx in range(low.x, high.x + 1):
		for by in range(low.y, high.y + 1):
			for target in hostile.get(Vector2i(bx, by), []):
				if target.hp <= 0 or not entities.has(target.id) or (cloak_kinds.has(target.kind) and cloaked(target)):
					continue
				var d = target.pos.distance_squared_to(e.pos)
				if d > distance or (d == distance and (best < 0 or target.id > best)):
					continue
				if not mine.has(Vector2i(target.pos)):
					continue
				if d < distance or best < 0 or target.id < best:
					distance = d
					best = target.id
	return best

## The enemy a unit is engaging. It keeps its target while that stays in view and in
## reach, and looks for a new or nearer one every fourth tick (staggered by id), so a
## standing army does not search the map every tick.
func acquire(e: Dictionary, radius: float) -> int:
	var aim: int = e.get("aim", -1)
	var fresh: bool = (ticks + e.id) % 4 == 0
	if aim >= 0 and not fresh:
		if entities.has(aim):
			var target: Dictionary = entities[aim]
			if target.pos.distance_squared_to(e.pos) <= radius * radius and seen(e.owner, target.pos):
				return aim
		fresh = true
	if not fresh:
		return -1
	aim = closest_enemy(e, radius)
	e["aim"] = aim
	return aim

## Cell offsets inside a circle of this radius, computed once.
func circle(radius: int) -> Array:
	if not circle_cache.has(radius):
		var cells: Array = []
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if dx * dx + dy * dy <= radius * radius:
					cells.append(Vector2i(dx, dy))
		circle_cache[radius] = cells
	return circle_cache[radius]

func damage_amount(attacker: Dictionary, target: Dictionary) -> float:
	var d = catalog.definition(attacker.kind)
	var damage: float = d.get("damage", 0.0) * (1.0 + tech_modifier(attacker.owner, "tower_damage" if attacker.building else "unit_damage"))
	damage *= catalog.damage_bonus(attacker.kind, target.kind, target.building)
	if target.building and attacker.get("braced", false):
		damage *= float(catalog.abilities.get(attacker.kind, {}).get("siege", 1.0))
	if target.owner >= 0 and not target.building:
		damage *= 1.0 - tech_modifier(target.owner, "armor")
		damage *= 1.0 - warded(target)
	return damage

## Damage reduction from a friendly aura carrier in reach (auras do not stack, and a carrier does not shield itself).
func warded(target: Dictionary) -> float:
	if blocks_tick != ticks:
		rebuild_blocks()
	for carrier in auras[target.owner]:
		if carrier.id == target.id or not entities.has(carrier.id) or stunned(carrier):
			continue
		var aura: Dictionary = catalog.units[carrier.kind].aura
		if carrier.pos.distance_to(target.pos) <= float(aura.get("radius", 4.0)):
			return float(aura.get("reduction", 0.25))
	return 0.0

## Applies one hit from `attacker` (an entity, or a shell's record of who fired it).
func strike(attacker: Dictionary, target_id: int, scale: float = 1.0) -> void:
	if not entities.has(target_id):
		return
	var target: Dictionary = entities[target_id]
	target.hp -= damage_amount(attacker, target) * scale
	alert_attack(target.owner, target.pos)
	if target.hp <= 0:
		stats[attacker.owner].kills += 1
		destroyed_counts[attacker.owner][target.kind] = int(destroyed_counts[attacker.owner].get(target.kind, 0)) + 1
		remove_entity(target_id)

## Shells fly to where the target stood; a target that moved clear is missed.
## Splash hits every enemy in the radius for half damage.
func tick_projectiles(dt: float) -> void:
	if projectiles.is_empty():
		return
	var flying: Array = []
	for shell in projectiles:
		shell.left -= dt
		if shell.left > 0:
			flying.append(shell)
			continue
		var splash: float = float(catalog.definition(shell.kind).get("splash", 0.0))
		var primary: int = shell.target
		if entities.has(primary) and entities[primary].pos.distance_to(shell.to) <= 1.5 + (catalog.buildings[entities[primary].kind].radius if entities[primary].building else 0.0):
			strike(shell, primary)
		else:
			primary = -1
		if splash > 0:
			for other in entities.values():
				if other.owner == 1 - shell.owner and other.id != primary and other.pos.distance_to(shell.to) <= splash + (catalog.buildings[other.kind].radius if other.building else 0.0):
					strike(shell, other.id, 0.5)
		impact.emit(shell.to, shell.kind, splash)
	projectiles = flying

func fight(e: Dictionary, target_id: int, dt: float, chase: bool) -> bool:
	if not entities.has(target_id):
		return false
	var target = entities[target_id]
	if not seen(e.owner, target.pos) or cloaked(target):
		return false
	var d = catalog.definition(e.kind)
	var reach: float = attack_range(e) + (catalog.buildings[target.kind].radius if target.building else 0.0)
	if e.pos.distance_to(target.pos) > reach:
		if chase and not e.building:
			walk(e, target.pos, dt, reach * 0.95)
		return chase
	if e.cooldown <= 0:
		e.cooldown = d.get("cooldown", 1.0)
		if float(e.get("overdrive_until", 0.0)) > elapsed:
			e.cooldown /= float(catalog.abilities.get(e.kind, {}).get("rate", 1.0))
		if cloak_kinds.has(e.kind):
			# Firing gives a cloaked unit away for a moment.
			e["reveal_until"] = elapsed + 2.0
		shot.emit(e.pos, target.pos, e.owner, e.kind)
		var speed: float = float(d.get("projectile", 0.0))
		if speed > 0:
			projectiles.append({"from": e.pos, "to": target.pos, "target": target_id, "owner": e.owner, "kind": e.kind, "building": e.building, "braced": e.get("braced", false), "left": e.pos.distance_to(target.pos) / speed})
		else:
			strike(e, target_id)
	return true

func remove_entity(id: int) -> void:
	if not entities.has(id):
		return
	var e = entities[id]
	if e.building:
		set_footprint(e.pos, catalog.buildings[e.kind].radius, false)
		# Refund queued units and unfinished research when production is destroyed.
		for item in e.queue:
			resources[e.owner] += catalog.units[item.kind].cost
		refund_research(e)
	destroyed.emit(e.pos, e.kind)
	entities.erase(id)
	for memory in remembered:
		memory.erase(id)
	if e.owner >= 0:
		alert.emit("structure_lost" if e.building else "unit_lost", e.pos, e.owner, e.kind)
	if e.building and e.kind == "core" and not has_core(e.owner):
		# A side that can still build gets a window to raise a new Core.
		if worker_count(e.owner) == 0:
			winner = 1 - e.owner
		else:
			core_deadline[e.owner] = elapsed + CORE_GRACE
			alert.emit("core_lost", e.pos, e.owner, "")

func refund_research(e: Dictionary) -> void:
	if e.research == "age":
		resources[e.owner] += catalog.age_costs[ages[e.owner]]
	elif e.research != "":
		resources[e.owner] += catalog.tech_cost(e.research, tech_level(e.owner, e.research) + 1)

## A side without a Core loses when its window runs out or its last Worker falls.
func check_cores() -> void:
	for side in 2:
		if core_deadline[side] < 0:
			continue
		if has_core(side):
			core_deadline[side] = -1.0
		elif elapsed >= core_deadline[side] or (worker_count(side) == 0 and not has_core(side, false)):
			winner = 1 - side
			return

func tick(dt: float = 0.1) -> void:
	if winner >= 0:
		return
	elapsed += dt
	ticks += 1
	if income_window >= 10.0 - dt * 0.5:
		for side in 2:
			income_rate[side] = income[side] * (60.0 / income_window)
			income[side] = Vector3.ZERO
		income_window = 0.0
	income_window += dt
	if ticks % 5 == 0:
		update_visibility()
	tick_projectiles(dt)
	for id in entities.keys():
		if not entities.has(id):
			continue
		var e = entities[id]
		if e.owner < 0:
			continue
		e.cooldown -= dt
		if e.building:
			tick_building(e, dt)
		elif not stunned(e):
			tick_unit(e, dt)
	if ticks % 2 == 0:
		separate_units()
	check_cores()

func tick_building(e: Dictionary, dt: float) -> void:
	if not e.complete:
		return
	if e.kind == "generator":
		credit(e.owner, Vector3(0, catalog.energy_per_second * dt * (1.0 + tech_modifier(e.owner, "generator_output")), 0))
	if e.research != "":
		e.research_left -= dt
		if e.research_left <= 0:
			if e.research == "age":
				ages[e.owner] += 1
				alert.emit("age_advanced", e.pos, e.owner, catalog.ages[ages[e.owner]])
				if e.owner == 0:
					notice.emit("AGE ADVANCED  /  " + catalog.ages[ages[0]])
			else:
				complete_tech(e.owner, e.research)
			e.research = ""
	if not e.queue.is_empty():
		var item: Dictionary = e.queue[0]
		item.left = maxf(0, item.left - dt * (1.0 + tech_modifier(e.owner, "production_rate")))
		if item.left <= 0 and population(e.owner) < capacity(e.owner):
			var p = nearest_open(e.pos + Vector2(0, catalog.buildings[e.kind].radius + 1))
			if p.x >= 0:
				var id = spawn(item.kind, e.owner, Vector2(p))
				set_order(entities[id], "move", e.rally)
				e.queue.pop_front()
				alert.emit("unit_ready", Vector2(p), e.owner, item.kind)
		elif item.left <= 0 and elapsed - cap_alert[e.owner] > 30.0:
			cap_alert[e.owner] = elapsed
			alert.emit("population_cap", e.pos, e.owner, item.kind)
	if e.kind == "tower":
		var target = acquire(e, attack_range(e) + 2.0)
		if target >= 0:
			fight(e, target, dt, false)

func complete_tech(side: int, id: String) -> void:
	var level = mini(DACatalog.TECH_MAX_LEVEL, tech_level(side, id) + 1)
	tech[side][id] = level
	if catalog.tech.get(id, {}).get("effects", {}).has("building_health"):
		rescale_building_health(side)
	alert.emit("research_complete", Vector2.ZERO, side, id)
	if side == 0:
		notice.emit("RESEARCH COMPLETE  /  " + str(catalog.tech[id].name).to_upper() + " " + str(level))

func tick_unit(e: Dictionary, dt: float) -> void:
	if e.order in ["gather", "deposit"]:
		tick_worker(e, dt)
		return
	if e.order in ["build", "repair"]:
		if not entities.has(e.target):
			set_order(e, "idle", e.pos)
			return
		var t = entities[e.target]
		var radius: float = catalog.buildings[t.kind].radius + 1.2
		if walk(e, t.pos, dt, radius):
			if not t.complete:
				var rate = 1.0 + tech_modifier(e.owner, "construction_rate")
				t.build_left -= dt * rate
				t.hp = minf(t.max_hp, t.hp + t.max_hp * 0.85 / catalog.buildings[t.kind].time * dt * rate)
				if t.build_left <= 0:
					t.complete = true
					t.hp = t.max_hp
					alert.emit("construction_complete", t.pos, t.owner, t.kind)
			elif t.hp < t.max_hp:
				if pay(e.owner, Vector3(1.5 * dt, 0, 0)):
					t.hp = minf(t.max_hp, t.hp + 20.0 * dt)
			else:
				set_order(e, "idle", e.pos)
		return
	if e.order == "attack":
		if not fight(e, e.target, dt, true):
			set_order(e, "attack_move", e.destination)
		return
	if e.order in ["idle", "hold", "attack_move", "patrol"] and e.kind != "worker":
		# An aggressive unit at rest chases what it sees, within a leash of its post, then walks back.
		var hunting: bool = e.order == "idle" and e.get("stance", "defensive") == "aggressive"
		var target = acquire(e, vision_radius(e))
		if target >= 0 and hunting and entities[target].pos.distance_to(e.destination) > LEASH:
			target = -1
		if target >= 0 and fight(e, target, dt, hunting or e.order in ["attack_move", "patrol"]):
			return
		if hunting and e.pos.distance_to(e.destination) > 1.0:
			walk(e, e.destination, dt, 0.65)
			return
	if e.order in ["move", "attack_move"]:
		if walk(e, e.destination, dt, 0.65):
			set_order(e, "idle", e.pos)
	elif e.order == "patrol":
		if walk(e, e.destination, dt, 0.65):
			# Turn around: the leg just walked becomes the way back.
			var back: Vector2 = e.get("patrol_from", e.pos)
			var here: Vector2 = e.destination
			set_order(e, "patrol", back)
			e["patrol_from"] = here

func tick_worker(e: Dictionary, dt: float) -> void:
	if e.cargo >= cargo_capacity(e.owner) or e.order == "deposit":
		e.order = "deposit"
		var depot_id = nearest_depot(e.owner, e.pos)
		if depot_id < 0:
			return
		var depot = entities[depot_id]
		if walk(e, depot.pos, dt, catalog.buildings[depot.kind].radius + 1.1):
			var amount: float = e.cargo
			if e.cargo_kind == "metal":
				credit(e.owner, Vector3(amount, 0, 0))
			else:
				credit(e.owner, Vector3(0, 0, amount))
			stats[e.owner].gathered += amount
			e.cargo = 0.0
			e.order = "gather"
			e.path_goal = Vector2(-999, -999)
		return
	if not entities.has(e.source) or entities[e.source].amount <= 0:
		# The deposit ran out: move on to the nearest known one of the same kind.
		var next_source = next_deposit(e)
		if next_source >= 0:
			e.source = next_source
			e.path_goal = Vector2(-999, -999)
		if e.cargo > 0:
			e.order = "deposit"
		elif next_source < 0:
			set_order(e, "idle", e.pos)
		return
	var source = entities[e.source]
	if e.cargo > 0 and e.cargo_kind != source.kind:
		e.order = "deposit"
		return
	if walk(e, source.pos, dt, 1.7):
		var rate: float = catalog.gather_per_second * gather_scale[e.owner] * (1.0 + tech_modifier(e.owner, "gather_metal" if source.kind == "metal" else "gather_data"))
		var amount = minf(rate * dt, minf(source.amount, cargo_capacity(e.owner) - e.cargo))
		e.cargo_kind = source.kind
		e.cargo += amount
		source.amount -= amount
		if source.amount <= 0 and amount > 0:
			alert.emit("deposit_exhausted", source.pos, e.owner, source.kind)

## Nearest known deposit with something left, of the kind this worker was gathering.
func next_deposit(e: Dictionary) -> int:
	if not entities.has(e.source):
		return -1
	var old: Dictionary = entities[e.source]
	var best = -1
	var distance = RETASK_RADIUS * RETASK_RADIUS
	for other in entities.values():
		if other.owner != -1 or other.kind != old.kind or other.amount <= 0 or not known(e.owner, other):
			continue
		var d = other.pos.distance_squared_to(old.pos)
		if d < distance:
			distance = d
			best = other.id
	return best

func separate_units() -> void:
	var buckets: Dictionary = {}
	for e in entities.values():
		if e.owner < 0 or e.building:
			continue
		var cell = Vector2i(e.pos)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for other in buckets.get(cell + Vector2i(dx, dy), []):
					var delta: Vector2 = e.pos - other.pos
					var distance = delta.length()
					if distance < 0.65 and e.order != "hold":
						var direction = delta / distance if distance > 0.01 else Vector2(0.7, 0.7)
						var next: Vector2 = clamp_point(e.pos + direction * (0.65 - distance) * 0.45)
						if not navigation.is_point_solid(Vector2i(next.round())):
							e.pos = next
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(e)

func update_visibility() -> void:
	visible = [{}, {}]
	# Units standing in the same cell see the same circle: stamp each cell once, at its widest radius.
	var eyes: Array = [{}, {}]
	for e in entities.values():
		if e.owner < 0:
			continue
		var radius: int = int(vision_radius(e))
		if e.building and not e.complete:
			radius = 3
		var p = Vector2i(e.pos)
		if int(eyes[e.owner].get(p, -1)) < radius:
			eyes[e.owner][p] = radius
	for side in 2:
		var lit: Dictionary = visible[side]
		var known_cells: Dictionary = explored[side]
		for p in eyes[side]:
			for offset in circle(eyes[side][p]):
				var c: Vector2i = p + offset
				if c.x >= 0 and c.y >= 0 and c.x < SIZE and c.y < SIZE and not lit.has(c):
					lit[c] = true
					known_cells[c] = true
	# Sensor sweeps light their circle until they run out.
	reveals = reveals.filter(func(r): return r.until > elapsed)
	for r in reveals:
		var centre = Vector2i(r.pos)
		for offset in circle(int(r.radius)):
			var c: Vector2i = centre + offset
			if c.x >= 0 and c.y >= 0 and c.x < SIZE and c.y < SIZE:
				visible[r.side][c] = true
				explored[r.side][c] = true
	# A cloaked unit is spotted by an enemy within its cloak radius (Towers see farther) or inside a sweep.
	if not cloak_kinds.is_empty():
		for e in entities.values():
			if e.owner < 0 or not cloak_kinds.has(e.kind):
				continue
			var reach: float = cloak_kinds[e.kind]
			var found = false
			for other in entities.values():
				if other.owner == 1 - e.owner and (not other.building or other.kind == "tower") and other.complete and other.pos.distance_to(e.pos) <= (reach + 3.0 if other.building else reach):
					found = true
					break
			if not found:
				for r in reveals:
					if r.side == 1 - e.owner and r.pos.distance_to(e.pos) <= r.radius:
						found = true
						break
			e["spotted"] = found
	for e in entities.values():
		if e.owner >= 0 and e.building and visible[1 - e.owner].has(Vector2i(e.pos)):
			remembered[1 - e.owner][e.id] = true

func load_factions(player_id: String, enemy_id: String) -> void:
	active_faction_ids = [player_id, enemy_id]
	active_factions.clear()
	for faction_id in active_faction_ids:
		var faction = load("res://data/factions/" + faction_id + ".tres") as DAFactionDefinition
		if faction:
			active_factions.append(faction)

func reset_from_mission(definition: DAMissionDefinition) -> void:
	if definition == null:
		return
	active_mission_id = definition.mission_id
	active_map_id = definition.map_id
	load_factions(definition.player_faction_id, definition.enemy_faction_id)
	ai_overrides.clear()
	var map = load("res://data/maps/" + definition.map_id + ".tres") as DAMapDefinition
	build_from_map(map, definition.symmetric_start, definition.swap_sides)
	for side in 2:
		if definition.starting_resources.size() > side:
			resources[side] = definition.starting_resources[side]
		else:
			resources[side] = catalog.starting_resources
		ages[side] = definition.technology_floor[side] if definition.technology_floor.size() > side else 0
		tech_ceiling[side] = clampi(definition.technology_ceiling[side], 0, 2) if definition.technology_ceiling.size() > side else 2
		tech[side] = {}
	winner = -1
	elapsed = 0.0
	ticks = 0
	stats = [{"kills": 0, "gathered": 0.0}, {"kills": 0, "gathered": 0.0}]
	destroyed_counts = [{}, {}]
	gather_scale = [1.0, 1.0]
	core_deadline = [-1.0, -1.0]
	attack_alerts = [[], []]
	cap_alert = [-100.0, -100.0]

## Variant serialization is deterministic and includes all mutable simulation state.
## SaveGameService stores this payload atomically and validates the outer schema.
func serialize_state() -> Dictionary:
	return {"mission_id": active_mission_id, "map_id": active_map_id, "faction_ids": active_faction_ids.duplicate(), "entities": entities.duplicate(true), "resources": resources.duplicate(), "ages": ages.duplicate(), "tech": tech.duplicate(true), "visible": visible.duplicate(true), "explored": explored.duplicate(true), "next_id": next_id, "elapsed": elapsed, "winner": winner, "ticks": ticks, "stats": stats.duplicate(true), "destroyed_counts": destroyed_counts.duplicate(true), "ai_overrides": ai_overrides.duplicate(true), "tech_ceiling": tech_ceiling.duplicate(), "gather_scale": gather_scale.duplicate(), "core_deadline": core_deadline.duplicate(), "bases": bases.duplicate(), "remembered": remembered.duplicate(true), "projectiles": projectiles.duplicate(true), "reveals": reveals.duplicate(true)}

func restore_state(state: Dictionary) -> String:
	if not state.has_all(["entities", "resources", "ages", "tech", "visible", "explored"]):
		return "Simulation save is incomplete."
	active_mission_id = str(state.get("mission_id", "skirmish"))
	active_map_id = str(state.get("map_id", "silent_grid"))
	active_faction_ids.clear()
	for faction_id in Array(state.get("faction_ids", ["origin", "foundry"])):
		active_faction_ids.append(str(faction_id))
	active_map = load("res://data/maps/" + active_map_id + ".tres") as DAMapDefinition
	active_factions.clear()
	for faction_id in active_faction_ids:
		var faction = load("res://data/factions/" + str(faction_id) + ".tres") as DAFactionDefinition
		if faction:
			active_factions.append(faction)
	ai_overrides = state.get("ai_overrides", {}).duplicate(true)
	if active_map and active_map.starts.size() >= 2:
		bases = [active_map.starts[0], active_map.starts[1]]
	var saved_bases = state.get("bases", [])
	if saved_bases is Array and saved_bases.size() == 2 and saved_bases[0] is Vector2 and saved_bases[1] is Vector2:
		bases = [saved_bases[0], saved_bases[1]]
	remembered = [{}, {}]
	var saved_memory = state.get("remembered", [])
	if saved_memory is Array and saved_memory.size() == 2:
		for side in 2:
			if saved_memory[side] is Dictionary:
				remembered[side] = saved_memory[side].duplicate()
	obstacles.clear()
	if active_map:
		for cell in active_map.obstacle_cells:
			obstacles[cell] = true
	entities = state.entities.duplicate(true)
	resources = Array(state.resources)
	ages = Array(state.ages)
	tech = [Dictionary(state.tech[0]).duplicate(), Dictionary(state.tech[1]).duplicate()]
	visible = Array(state.visible)
	explored = Array(state.explored)
	next_id = int(state.get("next_id", 1))
	elapsed = float(state.get("elapsed", 0.0))
	winner = int(state.get("winner", -1))
	ticks = int(state.get("ticks", 0))
	stats = state.get("stats", [{"kills": 0, "gathered": 0.0}, {"kills": 0, "gathered": 0.0}])
	destroyed_counts = state.get("destroyed_counts", [{}, {}])
	for side in 2:
		tech_ceiling[side] = clampi(int(Array(state.get("tech_ceiling", [2, 2]))[side]), 0, 2)
		gather_scale[side] = float(Array(state.get("gather_scale", [1.0, 1.0]))[side])
		core_deadline[side] = float(Array(state.get("core_deadline", [-1.0, -1.0]))[side])
	attack_alerts = [[], []]
	cap_alert = [-100.0, -100.0]
	projectiles = state.get("projectiles", []).duplicate(true) if state.get("projectiles", []) is Array else []
	reveals = state.get("reveals", []).duplicate(true) if state.get("reveals", []) is Array else []
	blocks_tick = -1
	load_terrain()
	rebuild_navigation()
	for entity in entities.values():
		if entity.owner >= 0 and entity.building:
			set_footprint(entity.pos, catalog.buildings[entity.kind].radius, true)
	reset_income()
	return ""
