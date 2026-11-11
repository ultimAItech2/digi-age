extends SceneTree
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + title)
	else:
		print("PASS: " + title)

func own(sim: DASimulation, kind: String, side: int = 0) -> Array:
	return sim.entities.values().filter(func(e): return e.owner == side and e.kind == kind)

func advance(sim: DASimulation, seconds: float) -> void:
	for i in int(seconds*10):
		sim.tick()

func reveal(sim: DASimulation, side: int = 0) -> void:
	for x in DASimulation.SIZE:
		for y in DASimulation.SIZE:
			sim.explored[side][Vector2i(x,y)] = true
			sim.visible[side][Vector2i(x,y)] = true

func build_site(sim: DASimulation, kind: String) -> Vector2:
	for x in range(5, 28):
		for y in range(22, 52):
			if sim.placement_error(0, kind, Vector2(x,y)) == "":
				return Vector2(x,y)
	return Vector2(-1,-1)

func run() -> void:
	var sim = DASimulation.new()
	var core = own(sim,"core")[0]
	var worker = own(sim,"worker")[0]
	expect(sim.population(0) == 6 and sim.capacity(0) == 15, "starting population and compute")
	expect(sim.resources[0] == sim.resources[1], "symmetric starting economy")
	var before = sim.resources[0]
	expect(sim.command(0,"train",[core.id],{"kind":"walker"}) != "" and sim.resources[0] == before, "invalid production does not spend")
	expect(sim.command(1,"train",[core.id],{"kind":"worker"}) != "", "ownership validation")
	expect(sim.command(0,"train",[core.id],{"kind":"worker"}) == "", "valid production accepted")
	expect(sim.resources[0] == before - sim.catalog.units.worker.cost, "production spends exact cost")
	advance(sim, 10)
	expect(sim.population(0) == 7, "production completes")
	expect(sim.resources[0].y > before.y - 15, "generators accumulate energy")
	sim.tick()
	var generators = own(sim,"generator").filter(func(e): return e.complete).size()
	expect(generators > 0 and absf(sim.income_per_minute(0).y - generators*sim.catalog.energy_per_second*60.0) < 1.0, "income rate reports energy per minute")
	var fabricator_id = sim.spawn("fabricator",0,Vector2(20,45))
	before = sim.resources[0]
	expect(sim.command(0,"train",[fabricator_id],{"kind":"disruptor"}) != "" and sim.resources[0] == before, "age prerequisite enforced without spending")
	var data_center = sim.spawn("data_center",0,Vector2(5,45))
	expect(sim.capacity(0) == 35, "Data Center adds 20 capacity")
	sim.remove_entity(data_center)
	expect(sim.capacity(0) == 15, "capacity decreases when Data Center is destroyed")
	while sim.population(0) < 15:
		sim.spawn("scout",0,Vector2(8,42))
	before = sim.resources[0]
	expect(sim.command(0,"train",[core.id],{"kind":"worker"}) != "" and sim.resources[0] == before, "population cap rejects production without spending")
	sim = DASimulation.new()
	worker = own(sim,"worker")[0]
	var metal = sim.entities.values().filter(func(e): return e.kind == "metal" and sim.known(0,e))[0]
	before = sim.resources[0]
	sim.command(0,"gather",[worker.id],{"target":metal.id})
	advance(sim,45)
	expect(sim.resources[0].x > before.x, "workers gather and deposit metal")
	expect(metal.amount < 6500, "gathering depletes source")
	reveal(sim)
	var data = sim.entities.values().filter(func(e): return e.kind == "data" and sim.known(0,e))[0]
	sim.command(0,"gather",[worker.id],{"target":data.id})
	advance(sim,50)
	expect(sim.resources[0].z > 0, "workers switch resource and deposit data")
	expect(worker.cargo_kind == "data", "resource switch does not transmute cargo")
	sim = DASimulation.new()
	reveal(sim)
	worker = own(sim,"worker")[0]
	var site = build_site(sim,"generator")
	before = sim.resources[0]
	expect(sim.command(0,"build",[worker.id],{"kind":"generator","pos":site}) == "", "valid foundation accepted")
	expect(sim.resources[0].x == before.x-100, "construction spends exact cost")
	var foundation = own(sim,"generator").filter(func(e): return not e.complete)[0]
	expect(sim.navigation.is_point_solid(Vector2i(site)), "foundation occupies navigation grid")
	advance(sim,35)
	expect(foundation.complete, "worker reaches and completes construction")
	before = sim.resources[0]
	expect(sim.command(0,"build",[worker.id],{"kind":"generator","pos":site}) != "" and before == sim.resources[0], "overlapping construction rejected without spending")
	sim.remove_entity(foundation.id)
	expect(not sim.navigation.is_point_solid(Vector2i(site)), "destroyed building releases navigation grid")
	foundation = sim.entities[sim.spawn("generator",0,site,false)]
	sim.command(0,"repair",[worker.id],{"target":foundation.id})
	advance(sim,30)
	expect(foundation.complete,"abandoned foundations can be resumed")
	foundation.hp -= 100
	sim.command(0,"repair",[worker.id],{"target":foundation.id})
	advance(sim,10)
	expect(foundation.hp == foundation.max_hp,"repair restores building integrity")
	sim = DASimulation.new()
	core = own(sim,"core")[0]
	sim.resources[0] = Vector3(3000,3000,3000)
	# Research tree data.
	var catalog: DACatalog = sim.catalog
	expect(catalog.tech.size() == 12, "tree has twelve upgrades")
	var shape_ok = true
	for id in catalog.tech:
		var entry: Dictionary = catalog.tech[id]
		if not catalog.tech_branches.has(entry.get("branch","")) or not entry.has_all(["name","icon","effects","description"]): shape_ok = false
		for key in entry.effects:
			if not DACatalog.TECH_EFFECTS.has(key): shape_ok = false
	expect(shape_ok, "every upgrade has a branch, icon, description and known effects")
	for branch in catalog.tech_branches:
		expect(catalog.tech_ids(branch).size() == 4, branch+" branch has four upgrades")
	expect(DACatalog.tech_age_for_level(1) == 0 and DACatalog.tech_age_for_level(2) == 0 and DACatalog.tech_age_for_level(3) == 1 and DACatalog.tech_age_for_level(4) == 1 and DACatalog.tech_age_for_level(5) == 2, "levels 1-2 Awakening, 3-4 Network, 5 Singularity")
	expect(catalog.tech_cost("mining",1) == Vector3(120,80,30) and catalog.tech_cost("mining",5) == Vector3(700,500,280) and catalog.tech_time("mining",5) == 70.0, "shared cost and time schedule")
	expect(catalog.buildings.lab.age == 0, "Research Lab is available in Awakening")
	# Ages at the Core.
	expect(sim.command(0,"research",[core.id],{"kind":"age"}) == "", "age research starts")
	advance(sim,46)
	expect(sim.ages[0] == 1, "Network age completes")
	expect(sim.command(0,"research",[core.id],{"kind":"mining"}) != "", "Core cannot research technologies")
	# Technologies at Research Labs.
	var lab = sim.entities[sim.spawn("lab",0,Vector2(20,30))]
	expect(sim.command(0,"research",[lab.id],{"kind":"age"}) != "", "Lab cannot research ages")
	expect(sim.command(0,"research",[lab.id],{"kind":"nonsense"}) == "Unknown research.", "unknown research rejected")
	var bank = sim.resources[0]
	expect(sim.command(0,"research",[lab.id],{"kind":"mining"}) == "" and sim.resources[0] == bank-Vector3(120,80,30), "Lab research starts and pays the level 1 cost")
	expect(sim.command(0,"research",[lab.id],{"kind":"power"}) != "", "a busy Lab refuses a second project")
	var lab2 = sim.entities[sim.spawn("lab",0,Vector2(20,33))]
	expect(sim.command(0,"research",[lab2.id],{"kind":"mining"}) == "Already being researched." and sim.resources[0] == bank-Vector3(120,80,30), "parallel Labs cannot duplicate a project")
	expect(sim.command(0,"research",[lab2.id],{"kind":"power"}) == "", "a second Lab researches in parallel")
	advance(sim,26)
	expect(sim.tech_level(0,"mining") == 1 and sim.tech_level(0,"power") == 1 and lab.research == "" and lab2.research == "", "two projects complete in parallel")
	sim.tech[0]["mining"] = 2
	sim.ages[0] = 0
	expect(sim.command(0,"research",[lab.id],{"kind":"mining"}) == "Requires the Network age.", "level 3 needs Network")
	sim.ages[0] = 1
	sim.tech[0]["mining"] = 4
	expect(sim.command(0,"research",[lab.id],{"kind":"mining"}) == "Requires the Singularity age.", "level 5 needs Singularity")
	sim.ages[0] = 2
	bank = sim.resources[0]
	expect(sim.command(0,"research",[lab.id],{"kind":"mining"}) == "" and sim.resources[0] == bank-Vector3(700,500,280), "level 5 starts at Singularity with the level 5 cost")
	sim.remove_entity(lab.id)
	expect(sim.resources[0] == bank, "destroyed Lab refunds its project")
	sim.tech[0]["mining"] = 5
	expect(sim.command(0,"research",[lab2.id],{"kind":"mining"}) == "Fully researched.", "level 5 is the cap")
	sim.resources[0] = Vector3(10,10,10)
	expect(sim.command(0,"research",[lab2.id],{"kind":"armor"}) == "Insufficient resources.", "research needs resources")
	sim.resources[0] = Vector3(3000,3000,3000)
	sim.command(0,"research",[lab2.id],{"kind":"armor"})
	var state = sim.serialize_state()
	var copy = DASimulation.new()
	expect(copy.restore_state(state) == "" and copy.tech[0] == sim.tech[0] and copy.entities[lab2.id].research == "armor" and is_equal_approx(copy.entities[lab2.id].research_left,lab2.research_left), "serialized state keeps tech levels and Lab projects")
	state.erase("tech")
	expect(copy.restore_state(state) != "", "state without tech is rejected")
	# Combat effects: Weapons 2 reproduces the former +20% damage.
	sim = DASimulation.new()
	sim.ages[0] = 2
	sim.resources[0] = Vector3(3000,3000,3000)
	sim.tech[0] = {"weapons": 2}
	var sentinel = sim.entities[sim.spawn("sentinel",0,Vector2(30,35))]
	var disruptor = sim.entities[sim.spawn("disruptor",1,Vector2(32,35))]
	var walker = sim.entities[sim.spawn("walker",1,Vector2(32,37))]
	expect(is_equal_approx(sim.damage_amount(sentinel,disruptor),38.4),"Sentinel counter and weapons upgrade stack")
	var friendly_disruptor = sim.entities[sim.spawn("disruptor",0,Vector2(30,37))]
	expect(is_equal_approx(sim.damage_amount(friendly_disruptor,walker),79.2),"Disruptor counters Siege Walker")
	var friendly_walker = sim.entities[sim.spawn("walker",0,Vector2(30,40))]
	expect(is_equal_approx(sim.damage_amount(friendly_walker,own(sim,"core",1)[0]),162.0),"Siege Walker counters structures")
	sim.tech[1] = {"armor": 2}
	expect(is_equal_approx(sim.damage_amount(sentinel,disruptor),34.56),"Armor 2 removes 10% after counters")
	expect(is_equal_approx(sim.damage_amount(friendly_walker,own(sim,"core",1)[0]),162.0),"buildings ignore unit armor")
	sim.tech[1] = {}
	sim.update_visibility()
	sim.command(0,"attack",[sentinel.id],{"target":disruptor.id})
	advance(sim,10)
	expect(not sim.entities.has(disruptor.id),"combat damages and destroys target")
	# Economy, building and unit effects.
	sim = DASimulation.new()
	reveal(sim)
	sim.ages[0] = 2
	var deposit = sim.entities.values().filter(func(e): return e.owner == -1 and e.kind == "metal")[0]
	var miner = sim.entities[sim.spawn("worker",0,deposit.pos+Vector2(1.2,0))]
	sim.tech[0] = {"mining": 1, "logistics": 1}
	expect(is_equal_approx(sim.cargo_capacity(0),28.0),"Logistics 1 raises cargo to 28")
	sim.command(0,"gather",[miner.id],{"target":deposit.id})
	advance(sim,1)
	expect(is_equal_approx(miner.cargo,3.3),"Mining 1 gathers 3.3 metal per second")
	advance(sim,8)
	expect(is_equal_approx(miner.cargo,28.0) and miner.order == "deposit","worker fills the enlarged cargo hold before returning")
	var plants = own(sim,"generator").size()
	sim.tech[0] = {"power": 1}
	var energy = sim.resources[0].y
	advance(sim,10)
	expect(absf(sim.resources[0].y-energy-plants*33.0) < 0.5,"Power Grid 1 adds 10% generator output")
	sim.tech[0] = {"construction": 1}
	var new_site = sim.entities[sim.spawn("generator",0,Vector2(20,30),false)]
	var builder = sim.entities[sim.spawn("worker",0,Vector2(22,30))]
	sim.command(0,"repair",[builder.id],{"target":new_site.id})
	advance(sim,13)
	expect(new_site.complete,"Rapid Construction 1 finishes a 14s Generator within 13s")
	var standing = own(sim,"generator")[0]
	standing.hp = 400.0
	sim.tech[0] = {}
	sim.complete_tech(0,"reinforcement")
	expect(sim.tech_level(0,"reinforcement") == 1 and is_equal_approx(standing.max_hp,486.0) and is_equal_approx(standing.hp,436.0),"Reinforced Structures 1 rescales standing buildings")
	expect(is_equal_approx(sim.entities[sim.spawn("generator",0,Vector2(20,34))].max_hp,486.0),"new buildings spawn with the reinforcement bonus")
	sim.tech[0] = {"fortification": 1}
	var tower = sim.entities[sim.spawn("tower",0,Vector2(16,30))]
	var raider = sim.entities[sim.spawn("scout",1,Vector2(28.3,30))]
	expect(is_equal_approx(sim.damage_amount(tower,raider),24.2) and is_equal_approx(sim.attack_range(tower),10.6),"Fortification 1 adds tower damage and range")
	expect(sim.closest_enemy(tower,sim.attack_range(tower)+2.0) == raider.id,"tower acquisition follows its upgraded range")
	sim.tech[0] = {"fabrication": 1}
	var workers = own(sim,"worker").size()
	sim.command(0,"train",[own(sim,"core")[0].id],{"kind":"worker"})
	advance(sim,8.3)
	expect(own(sim,"worker").size() == workers+1,"Fabrication Lines 1 trains a 9s Worker within 8.3s")
	sim.tech[0] = {"mobility": 1, "logistics": 1, "sensors": 1}
	var runner = sim.entities[sim.spawn("scout",0,Vector2(10,30))]
	var start = runner.pos
	sim.walk(runner,Vector2(22,30),0.1)
	expect(is_equal_approx(runner.pos.distance_to(start),0.53),"Mobility 1 moves a Scout 5.3 cells per second")
	var hauler = sim.entities[sim.spawn("worker",0,Vector2(10,28))]
	start = hauler.pos
	sim.walk(hauler,Vector2(22,28),0.1)
	expect(is_equal_approx(hauler.pos.distance_to(start),0.315),"Logistics 1 moves a Worker 3.15 cells per second")
	expect(is_equal_approx(sim.vision_radius(runner),16.2) and is_equal_approx(sim.attack_range(sentinel),4.68),"Sensor Arrays 1 extends vision and range")
	sim = DASimulation.new()
	var enemy_core = own(sim,"core",1)[0]
	expect(not sim.known(0,enemy_core),"enemy starts hidden in fog")
	var scout = own(sim,"scout")[0]
	expect(sim.command(0,"attack",[scout.id],{"target":enemy_core.id}) != "","cannot command attack on hidden target")
	scout.pos = Vector2(50,36)
	sim.update_visibility()
	expect(sim.known(0,enemy_core),"scouting reveals enemy")
	scout.pos = Vector2(12,44)
	sim.update_visibility()
	expect(sim.known(0,enemy_core) and not sim.seen(0,enemy_core.pos) and sim.explored[0].has(Vector2i(enemy_core.pos)),"a scouted building stays remembered in the fog")
	var rival_worker = own(sim,"worker",1)[0]
	expect(not sim.known(0,rival_worker),"enemy units hide again once out of sight")
	expect(sim.command(0,"attack",[scout.id],{"target":enemy_core.id}) == "" and sim.command(0,"attack",[scout.id],{"target":rival_worker.id}) != "","a remembered building can be ordered attacked; a hidden unit cannot")
	sim.command(0,"stop",[scout.id])
	sim.command(0,"move",[scout.id],{"pos":Vector2(20,30)})
	sim.command(0,"stop",[scout.id])
	var position: Vector2 = scout.pos
	advance(sim,1)
	expect(scout.pos.distance_to(position)<0.1,"stop cancels movement")
	sim.command(0,"rally",[own(sim,"core")[0].id],{"pos":Vector2(18,44)})
	expect(own(sim,"core")[0].rally == Vector2(18,44),"rally point command")
	# Queued units wait for capacity restored after losing a Data Center.
	sim.resources[0]=Vector3(3000,3000,3000)
	core = own(sim,"core")[0]
	while sim.population(0)<15:
		sim.spawn("scout",0,Vector2(7,43))
	data_center=sim.spawn("data_center",0,Vector2(5,27))
	sim.command(0,"train",[core.id],{"kind":"worker"})
	sim.remove_entity(data_center)
	advance(sim,12)
	expect(sim.population(0)==15 and core.queue.size()==1,"queued unit waits when compute is lost")
	sim.spawn("data_center",0,Vector2(5,27))
	advance(sim,1)
	expect(sim.population(0)==16 and core.queue.is_empty(),"production resumes after capacity restored")
	fabricator_id=sim.spawn("fabricator",0,Vector2(22,42))
	sim.command(0,"train",[fabricator_id],{"kind":"sentinel"})
	before=sim.resources[0]
	sim.remove_entity(fabricator_id)
	expect(sim.resources[0] == before+sim.catalog.units.sentinel.cost,"destroyed production refunds queued unit")
	# A side that loses its Core but keeps Workers gets a window to rebuild.
	sim.remove_entity(enemy_core.id)
	expect(sim.winner == -1 and sim.core_deadline[1] > sim.elapsed,"a fallen Core opens a rebuild window while Workers live")
	for w in own(sim,"worker",1):
		sim.remove_entity(w.id)
	advance(sim,0.2)
	expect(sim.winner == 0,"destroying the rival Core and its Workers wins")
	var elapsed = sim.elapsed
	advance(sim,5)
	expect(sim.elapsed == elapsed,"simulation freezes after victory")
	sim=DASimulation.new()
	sim.remove_entity(own(sim,"core")[0].id)
	advance(sim,DASimulation.CORE_GRACE-1)
	expect(sim.winner==-1,"the rebuild window is still open before it runs out")
	advance(sim,2)
	expect(sim.winner==1,"losing player Core without rebuilding causes defeat")
	sim=DASimulation.new()
	for w in own(sim,"worker"):
		sim.remove_entity(w.id)
	sim.remove_entity(own(sim,"core")[0].id)
	expect(sim.winner==1,"losing the Core with no Workers is immediate defeat")
	# Depleted resources return partial cargo without getting stuck.
	sim=DASimulation.new()
	worker=own(sim,"worker")[0]
	metal=sim.entities.values().filter(func(e): return e.kind=="metal" and sim.known(0,e))[0]
	metal.amount=5.0
	before=sim.resources[0]
	sim.command(0,"gather",[worker.id],{"target":metal.id})
	advance(sim,40)
	expect(is_equal_approx(sim.resources[0].x,before.x+5),"depleted deposit delivers partial cargo")
	expect(worker.order=="idle","worker idles when deposit exhausted")
	# Move orders on occupied cells resolve to reachable adjacent ground.
	scout=own(sim,"scout")[0]
	sim.command(0,"move",[scout.id],{"pos":sim.bases[0]})
	advance(sim,15)
	expect(scout.order=="idle" and not sim.navigation.is_point_solid(Vector2i(scout.pos.round())),"move to occupied building ends on adjacent ground")
	# Impassable terrain rejects unreachable construction and movement safely.
	reveal(sim)
	for y in DASimulation.SIZE:
		sim.navigation.set_point_solid(Vector2i(30,y))
	expect(sim.reachable_point(Vector2(12,36),Vector2(50,36)).x<0,"A* does not cross a sealed obstruction")
	before=sim.resources[0]
	expect(sim.command(0,"build",[worker.id],{"kind":"generator","pos":Vector2(45,10)})!="" and sim.resources[0]==before,"unreachable foundation rejected without spending")
	connected_orders()
	depth()
	print("RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

## Alerts, patrol, hold, cancel, worker re-tasking, Core rebuild, technology ceiling, difficulty.
func connected_orders() -> void:
	var sim = DASimulation.new()
	reveal(sim)
	var alerts: Array = []
	sim.alert.connect(func(kind, pos, side, detail): alerts.append({"kind":kind,"pos":pos,"side":side,"detail":detail}))
	var count = func(kind: String, side: int) -> int: return alerts.filter(func(a): return a.kind == kind and a.side == side).size()
	var core = own(sim,"core")[0]
	var worker = own(sim,"worker")[0]
	var scout = own(sim,"scout")[0]
	# Under attack: one alert per place and time window, not one per shot.
	var raider = sim.entities[sim.spawn("sentinel",1,core.pos+Vector2(4,0))]
	advance(sim,3)
	expect(count.call("under_attack",0) == 1,"under-attack alert fires once per window, got %d" % count.call("under_attack",0))
	advance(sim,DASimulation.ALERT_SPACING+1)
	expect(count.call("under_attack",0) == 2,"under-attack alert repeats after the window")
	sim.remove_entity(raider.id)
	expect(count.call("unit_lost",1) == 1 and count.call("unit_lost",0) == 0,"unit-lost alert goes to the owner only")
	# Construction and production alerts.
	sim.resources[0] = Vector3(5000,5000,5000)
	var site = build_site(sim,"generator")
	expect(sim.command(0,"build",[worker.id],{"kind":"generator","pos":site}) == "" and count.call("construction_started",0) == 1,"starting a building raises construction_started")
	advance(sim,60)
	expect(count.call("construction_complete",0) == 1,"finishing a building raises construction_complete")
	sim.command(0,"train",[core.id],{"kind":"worker"})
	advance(sim,15)
	expect(count.call("unit_ready",0) == 1,"a trained unit raises unit_ready")
	# Cancel refunds the queued unit and research.
	var before: Vector3 = sim.resources[0]
	sim.command(0,"train",[core.id],{"kind":"worker"})
	sim.command(0,"train",[core.id],{"kind":"worker"})
	expect(sim.command(0,"cancel",[core.id],{"index":1}) == "" and core.queue.size() == 1,"cancel removes the chosen queue slot")
	expect(sim.command(0,"cancel",[core.id]) == "" and core.queue.is_empty() and sim.resources[0] == before,"cancelling every queued unit refunds in full")
	sim.command(0,"research",[core.id],{"kind":"age"})
	expect(core.research == "age" and sim.command(0,"cancel",[core.id]) == "" and core.research == "" and sim.resources[0] == before,"cancelling research refunds it")
	expect(sim.command(0,"cancel",[core.id]) != "","cancel with nothing queued is refused")
	# Technology ceiling.
	sim.tech_ceiling[0] = 0
	expect(sim.command(0,"research",[core.id],{"kind":"age"}) != "" and sim.resources[0] == before,"the mission's technology ceiling blocks the next age without spending")
	sim.tech_ceiling[0] = 2
	expect(sim.placement_error(0,"tower",site+Vector2(0,8)).contains("Network"),"placement names the age a building needs")
	# Hold and patrol.
	expect(sim.command(0,"hold",[scout.id]) == "" and scout.order == "hold","hold order is accepted")
	var start: Vector2 = scout.pos
	var far: Vector2 = start+Vector2(8,0)
	expect(sim.command(0,"patrol",[scout.id],{"pos":far}) == "" and scout.order == "patrol","patrol order is accepted")
	var near_far = INF
	var near_start_after = INF
	var turns = 0
	var heading: Vector2 = scout.destination
	for i in 400:
		sim.tick()
		near_far = minf(near_far,scout.pos.distance_to(far))
		if scout.destination != heading:
			heading = scout.destination
			turns += 1
		if turns >= 1: near_start_after = minf(near_start_after,scout.pos.distance_to(start))
	expect(scout.order == "patrol" and near_far < 1.5 and turns >= 2,"a patrolling unit reaches the far end and keeps turning around (%d turns)" % turns)
	expect(near_start_after < 1.5,"and walks back to where it started")
	# No route: refused with a message.
	for y in DASimulation.SIZE:
		sim.navigation.set_point_solid(Vector2i(34,y))
	expect(sim.command(0,"move",[scout.id],{"pos":Vector2(50,36)}) == "No route to that location.","an unreachable destination is refused with a reason")
	for y in DASimulation.SIZE:
		sim.navigation.set_point_solid(Vector2i(34,y),sim.obstacles.has(Vector2i(34,y)))
	# Workers move on to the next deposit when theirs runs out.
	sim = DASimulation.new()
	reveal(sim)
	alerts.clear()
	sim.alert.connect(func(kind, pos, side, detail): alerts.append({"kind":kind,"pos":pos,"side":side,"detail":detail}))
	worker = own(sim,"worker")[0]
	var deposits = sim.entities.values().filter(func(e): return e.kind == "metal")
	deposits.sort_custom(func(a,b): return a.pos.distance_squared_to(worker.pos) < b.pos.distance_squared_to(worker.pos))
	var first: Dictionary = deposits[0]
	var second_id = sim.spawn_resource("metal",first.pos+Vector2(4,0),3000.0)
	first.amount = 5.0
	sim.command(0,"gather",[worker.id],{"target":first.id})
	advance(sim,40)
	expect(worker.source == second_id and worker.order in ["gather","deposit"],"a worker moves to the next deposit when its own runs out")
	expect(count.call("deposit_exhausted",0) == 1,"an emptied deposit raises deposit_exhausted")
	# Core rebuild: allowed only without a Core, and it closes the window.
	expect(sim.placement_error(0,"core",Vector2(20,36)) == "Your civilization already has a Core.","a second Core is refused")
	var lost: Vector2 = own(sim,"core")[0].pos
	sim.remove_entity(own(sim,"core")[0].id)
	expect(count.call("core_lost",0) == 1 and sim.core_deadline[0] > 0,"losing the Core raises core_lost")
	sim.resources[0] = Vector3(5000,5000,5000)
	expect(sim.command(0,"build",[worker.id],{"kind":"core","pos":lost}) == "","Workers may raise a new Core where the old one stood")
	sim.command(0,"repair",own(sim,"worker").map(func(e): return e.id),{"target":own(sim,"core")[0].id})
	advance(sim,90)
	expect(sim.winner == -1 and sim.has_core(0) and sim.core_deadline[0] < 0,"a rebuilt Core closes the window")
	# The opponent rebuilds too.
	var bot = DAOpponent.new(sim,1)
	sim.remove_entity(own(sim,"core",1)[0].id)
	sim.resources[1] = Vector3(5000,5000,5000)
	for i in 1000:
		bot.step(0.1)
		sim.tick()
	expect(sim.has_core(1) and sim.winner == -1,"the opponent rebuilds its Core inside the window")
	# Difficulty scales the profile and the gather rate; state survives a round trip.
	var easy = DAOpponent.new(sim,1)
	easy.set_difficulty("easy")
	var hard = DAOpponent.new(sim,1)
	hard.set_difficulty("hard")
	expect(easy.current_profile().attack_start > hard.current_profile().attack_start and easy.current_profile().min_army > hard.current_profile().min_army,"easy attacks later and needs a larger army than hard")
	expect(is_equal_approx(sim.gather_scale[1],1.15),"hard gathers faster")
	hard.assaults = 3
	hard.last_attack = 123.0
	var copy = DAOpponent.new(sim,1)
	copy.restore_state(hard.serialize_state())
	expect(copy.difficulty == "hard" and copy.assaults == 3 and copy.last_attack == 123.0,"opponent state survives serialisation")
	var state = sim.serialize_state()
	var restored = DASimulation.new()
	expect(restored.restore_state(state) == "" and is_equal_approx(restored.gather_scale[1],1.15) and restored.tech_ceiling == sim.tech_ceiling,"new match rules survive a save round trip")
	# A mined-out opponent attacks with what it has instead of waiting for an army it cannot afford.
	var barren = DASimulation.new()
	reveal(barren,1)
	var last_stand = DAOpponent.new(barren,1)
	barren.spawn("sentinel",1,barren.bases[1]+Vector2(0,6))
	barren.elapsed = 600.0
	last_stand.step(0.1)
	expect(last_stand.assaults == 0,"with metal in the ground the opponent waits for its army")
	for e in barren.entities.values():
		if e.kind == "metal": e.amount = 0.0
	barren.resources[1] = Vector3.ZERO
	last_stand.timer = 0
	last_stand.step(0.1)
	expect(last_stand.assaults == 1,"with nothing left to mine or spend it attacks with what remains")
	# Determinism: the same match played twice ends in the same state, byte for byte.
	var hashes: Array = []
	for attempt in 2:
		var match_sim = DASimulation.new()
		var bots = [DAOpponent.new(match_sim,0),DAOpponent.new(match_sim,1)]
		for i in 4000:
			for b in bots: b.step(0.1)
			match_sim.tick()
		hashes.append(hash(var_to_bytes(match_sim.serialize_state())))
	expect(hashes[0] == hashes[1],"two runs of the same match produce identical state")
	# Target search: the bucketed search agrees with a plain scan of every entity.
	var arena = DASimulation.new()
	reveal(arena)
	reveal(arena,1)
	for i in 40:
		arena.spawn("sentinel",i%2,Vector2(20+(i*7)%23,20+(i*11)%19))
	arena.tick()
	var agree = true
	for e in arena.entities.values():
		if e.owner < 0 or e.building: continue
		var plain = -1
		var nearest = 81.0
		for other in arena.entities.values():
			if other.owner < 0 or other.owner == e.owner or not arena.seen(e.owner,other.pos): continue
			var d = other.pos.distance_squared_to(e.pos)
			if d < nearest:
				nearest = d
				plain = other.id
		if arena.closest_enemy(e,9.0) != plain: agree = false
	expect(agree,"bucketed target search matches a full scan")

func flat(sim: DASimulation) -> void:
	# Plain ground everywhere, so a check measures one thing.
	sim.roads.clear()
	sim.rough.clear()
	sim.high.clear()

func until(sim: DASimulation, condition: Callable, limit: int = 100) -> bool:
	for i in limit:
		if condition.call(): return true
		sim.tick()
	return condition.call()

## Counters from data, shells and splash, abilities, stances, terrain, faction units.
func depth() -> void:
	var sim = DASimulation.new()
	reveal(sim)
	reveal(sim,1)
	flat(sim)
	var c: DACatalog = sim.catalog
	expect(c.damage_bonus("sentinel","disruptor",false) == 2.0 and c.damage_bonus("sentinel","warden",false) == 2.0 and c.damage_bonus("disruptor","walker",false) == 3.0 and c.damage_bonus("walker","core",true) == 3.0 and c.damage_bonus("scout","walker",false) == 1.0,"counters come from the catalog table, by unit kind, armour class or building")
	var saved_counters: Dictionary = c.counters.duplicate(true)
	c.counters["scout"] = {"heavy": 4.0}
	var probe_scout = sim.entities[sim.spawn("scout",0,Vector2(40,60))]
	var probe_walker = sim.entities[sim.spawn("walker",1,Vector2(60,60))]
	expect(is_equal_approx(sim.damage_amount(probe_scout,probe_walker),7.0*4.0),"changing the table changes the damage dealt")
	c.counters = saved_counters
	expect(c.counter_text("sentinel").contains("armoured") and c.counter_text("walker").contains("buildings"),"counter text for tooltips reads from the same table")
	sim.remove_entity(probe_scout.id)
	sim.remove_entity(probe_walker.id)
	# Shells travel, splash enemies for half, and miss a target that moved clear.
	var gun = sim.entities[sim.spawn("disruptor",0,Vector2(20,20))]
	var mark = sim.entities[sim.spawn("sentinel",1,Vector2(25.5,20))]
	var beside = sim.entities[sim.spawn("sentinel",1,Vector2(26.4,20))]
	var far = sim.entities[sim.spawn("sentinel",1,Vector2(29.5,20))]
	var friend = sim.entities[sim.spawn("scout",0,Vector2(25.5,20.8))]
	sim.command(0,"hold",[friend.id])
	for e in [mark,beside,far]: sim.command(1,"hold",[e.id])
	# Only the Disruptor fires in this check.
	for e in [mark,beside,far,friend]: e.cooldown = 100000.0
	var impacts: Array = []
	sim.impact.connect(func(pos, kind, radius): impacts.append({"pos":pos,"kind":kind,"radius":radius}))
	sim.command(0,"attack",[gun.id],{"target":mark.id})
	expect(until(sim,func(): return sim.projectiles.size() == 1) and mark.hp == mark.max_hp,"a Disruptor's shot is a shell in flight, not an instant hit")
	var friend_hp: float = friend.hp
	sim.command(0,"hold",[gun.id])
	until(sim,func(): return sim.projectiles.is_empty(),40)
	expect(is_equal_approx(mark.max_hp-mark.hp,22.0) and is_equal_approx(beside.max_hp-beside.hp,11.0) and far.hp == far.max_hp,"the shell hits its target in full and splashes the neighbour for half")
	expect(friend.hp == friend_hp,"splash does not hurt the shooter's own side")
	expect(impacts.size() == 1 and impacts[0].kind == "disruptor" and is_equal_approx(impacts[0].radius,1.2),"landing raises one impact with the splash radius")
	gun.cooldown = 0
	sim.command(0,"attack",[gun.id],{"target":mark.id})
	until(sim,func(): return sim.projectiles.size() == 1)
	sim.command(0,"hold",[gun.id])
	var before_hp: float = mark.hp
	mark.pos += Vector2(0,6)
	until(sim,func(): return sim.projectiles.is_empty(),40)
	expect(mark.hp == before_hp,"a target that moved clear of the landing point is missed")
	var rifle = sim.entities[sim.spawn("sentinel",0,Vector2(40,20))]
	var dummy = sim.entities[sim.spawn("sentinel",1,Vector2(43,20))]
	sim.command(1,"hold",[dummy.id])
	sim.command(0,"attack",[rifle.id],{"target":dummy.id})
	expect(until(sim,func(): return dummy.hp < dummy.max_hp,20) and sim.projectiles.is_empty(),"a Sentinel still hits instantly")
	# Abilities.
	var fresh = DASimulation.new()
	flat(fresh)
	var scout = own(fresh,"scout")[0]
	var spot = Vector2(scout.pos.x+30,scout.pos.y)
	expect(not fresh.seen(0,spot) and fresh.command(0,"ability",[scout.id],{"pos":spot}) == "" and fresh.seen(0,spot),"a Scout's sweep reveals a distant circle")
	expect(fresh.command(0,"ability",[scout.id],{"pos":spot}) == "Ability is recharging.","an ability cannot be used again until it recharges")
	advance(fresh,9)
	expect(not fresh.seen(0,spot),"the sweep ends after its duration")
	advance(fresh,40)
	expect(fresh.command(0,"ability",[scout.id],{"pos":scout.pos+Vector2(55,0)}).begins_with("Out of range"),"a sweep beyond reach is refused")
	var shots = [0]
	sim.shot.connect(func(from, to, owner, kind): if kind == "sentinel" and owner == 0: shots[0] += 1)
	dummy.hp = 100000.0
	dummy.max_hp = 100000.0
	rifle.cooldown = 0
	advance(sim,6)
	var plain: int = shots[0]
	shots[0] = 0
	expect(sim.command(0,"ability",[rifle.id]) == "","Overdrive is accepted")
	advance(sim,6)
	expect(shots[0] >= plain+2,"Overdrive fires faster: %d shots against %d" % [shots[0],plain])
	var emp = sim.entities[sim.spawn("disruptor",0,Vector2(20,40))]
	var victims: Array = []
	for i in 3: victims.append(sim.entities[sim.spawn("sentinel",1,Vector2(25+i*0.8,40))])
	var bunker = sim.entities[sim.spawn("tower",1,Vector2(25,43))]
	sim.command(0,"hold",[emp.id])
	expect(sim.command(0,"ability",[emp.id],{"pos":Vector2(25.8,40)}) == "" and victims.all(func(v): return sim.stunned(v)) and not sim.stunned(bunker),"an EMP shell stuns units in its circle and leaves buildings alone")
	var stuck: Vector2 = victims[0].pos
	sim.command(1,"move",victims.map(func(v): return v.id),{"pos":Vector2(35,40)})
	advance(sim,2)
	expect(victims[0].pos.distance_to(stuck) < 0.7,"stunned units do not move or fire")
	advance(sim,2.5)
	expect(victims[0].pos.distance_to(stuck) > 1.0,"and recover when the stun ends")
	var walker = sim.entities[sim.spawn("walker",0,Vector2(20,55))]
	var reach: float = sim.attack_range(walker)
	expect(sim.command(0,"ability",[walker.id]) == "" and walker.braced and is_equal_approx(sim.attack_range(walker),reach+3.0),"Brace adds three cells of range")
	var wall = sim.entities[sim.spawn("generator",1,Vector2(40,55))]
	expect(is_equal_approx(sim.damage_amount(walker,wall),45.0*3.0*1.5),"and half again as much damage to buildings")
	var planted: Vector2 = walker.pos
	sim.command(0,"move",[walker.id],{"pos":Vector2(26,55)})
	advance(sim,3)
	expect(walker.pos.distance_to(planted) < 0.5,"a braced Walker cannot move")
	advance(sim,1)
	sim.command(0,"ability",[walker.id])
	sim.command(0,"move",[walker.id],{"pos":Vector2(26,55)})
	advance(sim,3)
	expect(not walker.braced and walker.pos.distance_to(planted) > 2.0,"releasing the brace lets it walk again")
	# Stances.
	var guard = sim.entities[sim.spawn("sentinel",0,Vector2(50,50))]
	var bait = sim.entities[sim.spawn("worker",1,Vector2(57,50))]
	sim.command(0,"stop",[guard.id])
	advance(sim,3)
	expect(guard.pos.distance_to(Vector2(50,50)) < 0.7 and bait.hp == bait.max_hp,"a defensive unit does not leave its post for a target out of range")
	expect(sim.command(0,"stance",[guard.id],{"stance":"aggressive"}) == "" and guard.stance == "aggressive","the stance order is accepted")
	advance(sim,4)
	expect(guard.pos.distance_to(Vector2(50,50)) > 1.5 or bait.hp < bait.max_hp,"an aggressive unit goes after what it sees")
	if sim.entities.has(bait.id): sim.remove_entity(bait.id)
	advance(sim,8)
	expect(guard.pos.distance_to(Vector2(50,50)) < 1.5,"and returns to its post afterwards")
	# Terrain.
	var ground = DASimulation.new()
	var runner = ground.entities[ground.spawn("sentinel",0,Vector2(10,10))]
	flat(ground)
	var pace = func(e: Dictionary, target: Vector2) -> float:
		var from: Vector2 = e.pos
		e.path = []
		e.path_goal = Vector2(-999,-999)
		ground.walk(e,target,0.1)
		var moved: float = e.pos.distance_to(from)
		e.pos = from
		return moved
	var base_pace: float = pace.call(runner,Vector2(16,10))
	ground.roads[Vector2i(10,10)] = true
	expect(is_equal_approx(pace.call(runner,Vector2(16,10)),base_pace*1.25),"a road carries a unit a quarter faster")
	ground.roads.clear()
	ground.rough[Vector2i(10,10)] = true
	expect(is_equal_approx(pace.call(runner,Vector2(16,10)),base_pace*0.65),"rough ground slows it")
	var hover = ground.entities[ground.spawn("scout",0,Vector2(10,10))]
	var hover_pace: float = pace.call(hover,Vector2(16,10))
	ground.rough.clear()
	expect(is_equal_approx(pace.call(hover,Vector2(16,10)),hover_pace),"a hovering unit ignores rough ground")
	var sight: float = ground.vision_radius(runner)
	var range_before: float = ground.attack_range(runner)
	ground.high[Vector2i(10,10)] = true
	expect(is_equal_approx(ground.vision_radius(runner),sight+2.0) and is_equal_approx(ground.attack_range(runner),range_before+1.0),"high ground adds two cells of sight and one of range")
	var maps_ok = true
	for map_id in DASettingsService.SKIRMISH_MAPS:
		var map = load("res://data/maps/%s.tres" % map_id) as DAMapDefinition
		var world = DASimulation.new()
		world.build_from_map(map)
		if map.rough_cells.is_empty() or map.high_cells.is_empty(): maps_ok = false
		for cell in map.rough_cells + map.high_cells:
			if world.obstacles.has(cell) or map.starts.any(func(s): return Vector2(cell).distance_to(s) < 10.0): maps_ok = false
		for cell in map.rough_cells:
			if not is_equal_approx(world.navigation.get_point_weight_scale(cell),1.6): maps_ok = false
		var restored = DASimulation.new()
		restored.restore_state(world.serialize_state())
		if restored.rough.size() != world.rough.size() or restored.high.size() != world.high.size() or restored.roads.size() != world.roads.size(): maps_ok = false
	expect(maps_ok,"every map has rough and high ground clear of the starts and obstacles, weighted for pathfinding, and restored on load")
	# Faction rosters and the three faction units.
	var war = DASimulation.new()
	war.load_factions("origin","foundry")
	reveal(war)
	reveal(war,1)
	flat(war)
	for side in 2:
		war.ages[side] = 1
		war.resources[side] = Vector3(9000,9000,9000)
	var fab0 = war.spawn("fabricator",0,Vector2(22,44))
	var fab1 = war.spawn("fabricator",1,Vector2(50,44))
	expect(war.allowed(0,"warden") and not war.allowed(0,"mortar") and war.allowed(1,"mortar") and not war.allowed(1,"phantom") and war.allowed(0,"lab"),"each faction's roster names its own unit")
	expect(war.command(0,"train",[fab0],{"kind":"mortar"}) == "Your faction does not field this unit." and war.command(0,"train",[fab0],{"kind":"warden"}) == "" and war.command(1,"train",[fab1],{"kind":"mortar"}) == "","the roster is enforced when training")
	expect(not DASimulation.new().allowed(0,"warden") and DASimulation.new().allowed(0,"sentinel"),"without a faction, only the shared units are available")
	var warden = war.entities[war.spawn("warden",0,Vector2(30,20))]
	var ward = war.entities[war.spawn("sentinel",0,Vector2(32,20))]
	var loner = war.entities[war.spawn("sentinel",0,Vector2(45,20))]
	var foe = war.entities[war.spawn("sentinel",1,Vector2(60,20))]
	war.tick()
	expect(is_equal_approx(war.damage_amount(foe,ward),16.0*0.75) and is_equal_approx(war.damage_amount(foe,loner),16.0) and is_equal_approx(war.damage_amount(foe,warden),16.0*2.0),"a Warden cuts damage to units near it by a quarter, but not to itself")
	war.spawn("warden",0,Vector2(31,21))
	war.tick()
	expect(is_equal_approx(war.damage_amount(foe,ward),16.0*0.75),"two Wardens do not stack")
	var mortar = war.entities[war.spawn("mortar",1,Vector2(60,40))]
	expect(is_equal_approx(war.attack_range(mortar),11.0) and float(war.catalog.units.mortar.splash) == 2.0 and float(war.catalog.units.mortar.projectile) > 0,"the Mortar outranges every other unit and splashes wide")
	var ghost_world = DASimulation.new()
	ghost_world.load_factions("lattice","origin")
	reveal(ghost_world)
	reveal(ghost_world,1)
	flat(ghost_world)
	var phantom = ghost_world.entities[ghost_world.spawn("phantom",0,Vector2(30,10))]
	var watcher = ghost_world.entities[ghost_world.spawn("sentinel",1,Vector2(37,10))]
	ghost_world.command(0,"hold",[phantom.id])
	ghost_world.command(1,"hold",[watcher.id])
	ghost_world.update_visibility()
	ghost_world.tick()
	expect(ghost_world.cloaked(phantom) and not ghost_world.known(1,phantom) and ghost_world.closest_enemy(watcher,12.0) != phantom.id and ghost_world.known(0,phantom),"a Phantom seven cells away is unseen and cannot be targeted, though its owner sees it")
	expect(ghost_world.command(1,"attack",[watcher.id],{"target":phantom.id}) != "","and cannot be ordered attacked")
	watcher.pos = Vector2(33,10)
	ghost_world.update_visibility()
	expect(not ghost_world.cloaked(phantom) and ghost_world.known(1,phantom),"an enemy within four cells spots it")
	watcher.pos = Vector2(40,10)
	ghost_world.update_visibility()
	var tower_id = ghost_world.spawn("tower",1,Vector2(36,10))
	ghost_world.update_visibility()
	expect(not ghost_world.cloaked(phantom),"a Tower spots it from farther off")
	ghost_world.remove_entity(tower_id)
	ghost_world.update_visibility()
	expect(ghost_world.cloaked(phantom),"and it fades again once clear")
	var enemy_scout = ghost_world.entities[ghost_world.spawn("scout",1,Vector2(60,10))]
	ghost_world.command(1,"ability",[enemy_scout.id],{"pos":phantom.pos})
	expect(not ghost_world.cloaked(phantom),"a Sensor sweep shows it")
	advance(ghost_world,9)
	watcher.pos = Vector2(34.5,10)
	ghost_world.command(0,"attack",[phantom.id],{"target":watcher.id})
	until(ghost_world,func(): return watcher.hp < watcher.max_hp,30)
	watcher.pos = Vector2(40,10)
	ghost_world.update_visibility()
	expect(watcher.hp < watcher.max_hp and not ghost_world.cloaked(phantom),"firing gives it away for a moment")
	# Shells in flight and sweeps survive a save.
	gun.cooldown = 0
	sim.command(0,"attack",[gun.id],{"target":beside.id})
	until(sim,func(): return sim.projectiles.size() >= 1)
	var copy = DASimulation.new()
	expect(copy.restore_state(sim.serialize_state()) == "" and copy.projectiles.size() == sim.projectiles.size(),"shells in flight are saved and restored")
