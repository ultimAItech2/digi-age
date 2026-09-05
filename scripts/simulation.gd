class_name DASimulation
extends RefCounted
## Authoritative, renderer-independent fixed-tick simulation.
signal shot(from: Vector2, to: Vector2, owner: int, kind: String)
signal destroyed(position: Vector2, kind: String)
signal notice(message: String)
const SIZE: int = 72
var bases: Array[Vector2] = [Vector2(12, 36), Vector2(59, 36)]
var catalog: DACatalog = preload("res://data/catalog.tres")
var entities: Dictionary = {}
var resources: Array[Vector3] = []
var ages: Array[int] = [0, 0]
var upgrades: Array[int] = [0, 0]
var visible: Array = []
var explored: Array = []
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

func _init() -> void:
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

func clear_world() -> void:
	entities.clear()
	obstacles.clear()
	next_id = 1
	visible = [{}, {}]
	explored = [{}, {}]
	rebuild_navigation()

func faction_modifier(side: int, key: String, default: float = 1.0) -> float:
	if side < 0 or side >= active_factions.size() or active_factions[side] == null:
		return default
	return float(active_factions[side].modifiers.get(key, default))

func faction_color(side: int) -> Color:
	if side < 0 or side >= active_factions.size() or active_factions[side] == null:
		return Color("57ebd5") if side == 0 else Color("ff795c")
	return active_factions[side].primary_color

func build_from_map(map: DAMapDefinition) -> void:
	clear_world()
	active_map = map
	if map:
		active_map_id = map.map_id
		if map.starts.size() >= 2:
			bases = [map.starts[0], map.starts[1]]
		for cell in map.obstacle_cells:
			obstacles[cell] = true
			if navigation.is_in_boundsv(cell):
				navigation.set_point_solid(cell)
		for node in map.resource_nodes:
			spawn_resource(str(node.get("kind", "metal")), node.get("pos", Vector2.ZERO), float(node.get("amount", 5000.0)))
		if map.starting_units.is_empty():
			_legacy_default_units()
		else:
			for unit in map.starting_units:
				var side = int(unit.get("side", 0))
				var origin = bases[side] if side >= 0 and side < bases.size() else Vector2.ZERO
				spawn(str(unit.get("kind", "worker")), side, origin + unit.get("offset", Vector2.ZERO), bool(unit.get("complete", true)))
		for item in map.prebuilt:
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
	if not building:
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
	return e.owner == side or (explored[side].has(Vector2i(e.pos)) if e.owner == -1 else seen(side, e.pos))

func placement_error(side: int, kind: String, pos: Vector2) -> String:
	if not catalog.buildings.has(kind) or kind == "core":
		return "Select a constructible building."
	var d = catalog.buildings[kind]
	if ages[side] < d.age:
		return "Requires the Network age."
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
		return ""
	if action == "train":
		var kind: String = payload.get("kind", "")
		if not catalog.units.has(kind) or not first.building or not first.complete:
			return "Select a completed production building."
		if (kind == "worker" and first.kind != "core") or (kind != "worker" and first.kind != "fabricator"):
			return "This building cannot produce that unit."
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
		if first.kind != "core" or not first.complete or first.research != "":
			return "Select an idle, completed Core."
		var kind: String = payload.get("kind", "age")
		if kind != "age" and kind != "weapons":
			return "Unknown research."
		var level = ages[side] if kind == "age" else upgrades[side]
		if level >= 2 or (kind == "weapons" and level >= ages[side]):
			return "Research is unavailable in this age."
		var cost = catalog.age_costs[level] if kind == "age" else catalog.upgrade_costs[level]
		if not pay(side, cost):
			return "Insufficient resources."
		first.research = kind
		first.research_left = (catalog.age_times[level] if kind == "age" else 30.0) * faction_modifier(side, "research_speed", 1.0)
		return ""
	if action == "rally":
		for e in owned:
			if e.building:
				e.rally = clamp_point(payload.get("pos", e.pos))
		return ""
	var index = 0
	for e in owned:
		if e.building:
			continue
		if action == "hold":
			set_order(e, "hold", e.pos)
		elif action == "stop":
			set_order(e, "idle", e.pos)
		elif action in ["move", "attack_move"]:
			var offset = Vector2((index % 5) - 2, floori(index / 5.0)) * 1.1 if owned.size() > 1 else Vector2.ZERO
			set_order(e, action, clamp_point(payload.get("pos", e.pos) + offset))
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

func clamp_point(p: Vector2) -> Vector2:
	return p.clamp(Vector2.ONE, Vector2(SIZE - 2, SIZE - 2))

func set_order(e: Dictionary, order: String, p: Vector2, target: int = -1) -> void:
	e.order = order
	e.destination = Vector2(nearest_open(p)) if order in ["move", "attack_move"] else p
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
	e.pos = e.pos.move_toward(next, catalog.units[e.kind].speed * dt)
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

func closest_enemy(e: Dictionary, radius: float) -> int:
	var best = -1
	var distance = radius * radius
	for target in entities.values():
		if target.owner < 0 or target.owner == e.owner or not seen(e.owner, target.pos):
			continue
		var d = target.pos.distance_squared_to(e.pos)
		if d < distance:
			distance = d
			best = target.id
	return best

func damage_amount(attacker: Dictionary, target: Dictionary) -> float:
	var d = catalog.definition(attacker.kind)
	var damage: float = d.get("damage", 0.0) * (1.0 + upgrades[attacker.owner] * 0.2)
	if attacker.kind == "sentinel" and target.kind == "disruptor":
		damage *= 2.0
	if attacker.kind == "disruptor" and target.kind == "walker":
		damage *= 3.0
	if attacker.kind == "walker" and target.building:
		damage *= 3.0
	return damage

func fight(e: Dictionary, target_id: int, dt: float, chase: bool) -> bool:
	if not entities.has(target_id):
		return false
	var target = entities[target_id]
	if not seen(e.owner, target.pos):
		return false
	var d = catalog.definition(e.kind)
	var reach: float = d.get("range", 0.0) + (catalog.buildings[target.kind].radius if target.building else 0.0)
	if e.pos.distance_to(target.pos) > reach:
		if chase and not e.building:
			walk(e, target.pos, dt, reach * 0.95)
		return chase
	if e.cooldown <= 0:
		e.cooldown = d.get("cooldown", 1.0)
		target.hp -= damage_amount(e, target)
		shot.emit(e.pos, target.pos, e.owner, e.kind)
		if target.hp <= 0:
			stats[e.owner].kills += 1
			destroyed_counts[e.owner][target.kind] = int(destroyed_counts[e.owner].get(target.kind, 0)) + 1
			remove_entity(target_id)
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
		if e.research != "":
			resources[e.owner] += catalog.age_costs[ages[e.owner]] if e.research == "age" else catalog.upgrade_costs[upgrades[e.owner]]
		if e.kind == "core":
			winner = 1 - e.owner
	destroyed.emit(e.pos, e.kind)
	entities.erase(id)

func tick(dt: float = 0.1) -> void:
	if winner >= 0:
		return
	elapsed += dt
	ticks += 1
	if ticks % 5 == 0:
		update_visibility()
	for id in entities.keys():
		if not entities.has(id):
			continue
		var e = entities[id]
		if e.owner < 0:
			continue
		e.cooldown -= dt
		if e.building:
			tick_building(e, dt)
		else:
			tick_unit(e, dt)
	if ticks % 2 == 0:
		separate_units()

func tick_building(e: Dictionary, dt: float) -> void:
	if not e.complete:
		return
	if e.kind == "generator":
		resources[e.owner].y += catalog.energy_per_second * dt
	if e.research != "":
		e.research_left -= dt
		if e.research_left <= 0:
			if e.research == "age":
				ages[e.owner] += 1
				if e.owner == 0:
					notice.emit("AGE ADVANCED  /  " + catalog.ages[ages[0]])
			else:
				upgrades[e.owner] += 1
			e.research = ""
	if not e.queue.is_empty():
		var item: Dictionary = e.queue[0]
		item.left = maxf(0, item.left - dt)
		if item.left <= 0 and population(e.owner) < capacity(e.owner):
			var p = nearest_open(e.pos + Vector2(0, catalog.buildings[e.kind].radius + 1))
			if p.x >= 0:
				var id = spawn(item.kind, e.owner, Vector2(p))
				set_order(entities[id], "move", e.rally)
				e.queue.pop_front()
	if e.kind == "tower":
		var target = closest_enemy(e, 12.0)
		if target >= 0:
			fight(e, target, dt, false)

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
				t.build_left -= dt
				t.hp = minf(t.max_hp, t.hp + t.max_hp * 0.85 / catalog.buildings[t.kind].time * dt)
				if t.build_left <= 0:
					t.complete = true
					t.hp = t.max_hp
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
	if e.order in ["idle", "hold", "attack_move"] and e.kind != "worker":
		var target = closest_enemy(e, catalog.units[e.kind].vision)
		if target >= 0 and fight(e, target, dt, e.order == "attack_move"):
			return
	if e.order in ["move", "attack_move"]:
		if walk(e, e.destination, dt, 0.65):
			set_order(e, "idle", e.pos)

func tick_worker(e: Dictionary, dt: float) -> void:
	if e.cargo >= 24.0 or e.order == "deposit":
		e.order = "deposit"
		var depot_id = nearest_depot(e.owner, e.pos)
		if depot_id < 0:
			return
		var depot = entities[depot_id]
		if walk(e, depot.pos, dt, catalog.buildings[depot.kind].radius + 1.1):
			var amount: float = e.cargo
			if e.cargo_kind == "metal":
				resources[e.owner].x += amount
			else:
				resources[e.owner].z += amount
			stats[e.owner].gathered += amount
			e.cargo = 0.0
			e.order = "gather"
			e.path_goal = Vector2(-999, -999)
		return
	if not entities.has(e.source) or entities[e.source].amount <= 0:
		if e.cargo > 0:
			e.order = "deposit"
		else:
			set_order(e, "idle", e.pos)
		return
	var source = entities[e.source]
	if e.cargo > 0 and e.cargo_kind != source.kind:
		e.order = "deposit"
		return
	if walk(e, source.pos, dt, 1.7):
		var amount = minf(catalog.gather_per_second * dt, minf(source.amount, 24.0 - e.cargo))
		e.cargo_kind = source.kind
		e.cargo += amount
		source.amount -= amount

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
	for e in entities.values():
		if e.owner < 0:
			continue
		var radius: int = int(catalog.definition(e.kind).vision * faction_modifier(e.owner, "vision_radius", 1.0))
		if e.building and not e.complete:
			radius = 3
		var p = Vector2i(e.pos)
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if dx * dx + dy * dy > radius * radius:
					continue
				var c = p + Vector2i(dx, dy)
				if navigation.is_in_boundsv(c):
					visible[e.owner][c] = true
					explored[e.owner][c] = true

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
	build_from_map(map)
	for side in 2:
		if definition.starting_resources.size() > side:
			resources[side] = definition.starting_resources[side]
		else:
			resources[side] = catalog.starting_resources
		ages[side] = definition.technology_floor[side] if definition.technology_floor.size() > side else 0
		upgrades[side] = 0
	winner = -1
	elapsed = 0.0
	ticks = 0
	stats = [{"kills": 0, "gathered": 0.0}, {"kills": 0, "gathered": 0.0}]
	destroyed_counts = [{}, {}]

## Variant serialization is deterministic and includes all mutable simulation state.
## SaveGameService stores this payload atomically and validates the outer schema.
func serialize_state() -> Dictionary:
	return {"mission_id": active_mission_id, "map_id": active_map_id, "faction_ids": active_faction_ids.duplicate(), "entities": entities.duplicate(true), "resources": resources.duplicate(), "ages": ages.duplicate(), "upgrades": upgrades.duplicate(), "visible": visible.duplicate(true), "explored": explored.duplicate(true), "next_id": next_id, "elapsed": elapsed, "winner": winner, "ticks": ticks, "stats": stats.duplicate(true), "destroyed_counts": destroyed_counts.duplicate(true), "ai_overrides": ai_overrides.duplicate(true)}

func restore_state(state: Dictionary) -> String:
	if not state.has_all(["entities", "resources", "ages", "upgrades", "visible", "explored"]):
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
	obstacles.clear()
	if active_map:
		for cell in active_map.obstacle_cells:
			obstacles[cell] = true
	entities = state.entities.duplicate(true)
	resources = Array(state.resources)
	ages = Array(state.ages)
	upgrades = Array(state.upgrades)
	visible = Array(state.visible)
	explored = Array(state.explored)
	next_id = int(state.get("next_id", 1))
	elapsed = float(state.get("elapsed", 0.0))
	winner = int(state.get("winner", -1))
	ticks = int(state.get("ticks", 0))
	stats = state.get("stats", [{"kills": 0, "gathered": 0.0}, {"kills": 0, "gathered": 0.0}])
	destroyed_counts = state.get("destroyed_counts", [{}, {}])
	rebuild_navigation()
	for entity in entities.values():
		if entity.owner >= 0 and entity.building:
			set_footprint(entity.pos, catalog.buildings[entity.kind].radius, true)
	return ""
