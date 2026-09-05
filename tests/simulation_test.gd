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
	expect(sim.command(0,"research",[core.id],{"kind":"age"}) == "", "age research starts")
	advance(sim,46)
	expect(sim.ages[0] == 1, "Network age completes")
	sim.command(0,"research",[core.id],{"kind":"weapons"})
	advance(sim,31)
	expect(sim.upgrades[0] == 1, "weapon research completes")
	sim.command(0,"research",[core.id],{"kind":"age"})
	advance(sim,66)
	expect(sim.ages[0] == 2,"Singularity age completes")
	var sentinel = sim.entities[sim.spawn("sentinel",0,Vector2(30,35))]
	var disruptor = sim.entities[sim.spawn("disruptor",1,Vector2(32,35))]
	var walker = sim.entities[sim.spawn("walker",1,Vector2(32,37))]
	expect(is_equal_approx(sim.damage_amount(sentinel,disruptor),38.4),"Sentinel counter and weapons upgrade stack")
	var friendly_disruptor = sim.entities[sim.spawn("disruptor",0,Vector2(30,37))]
	expect(is_equal_approx(sim.damage_amount(friendly_disruptor,walker),79.2),"Disruptor counters Siege Walker")
	var friendly_walker = sim.entities[sim.spawn("walker",0,Vector2(30,40))]
	expect(is_equal_approx(sim.damage_amount(friendly_walker,own(sim,"core",1)[0]),162.0),"Siege Walker counters structures")
	sim.update_visibility()
	sim.command(0,"attack",[sentinel.id],{"target":disruptor.id})
	advance(sim,10)
	expect(not sim.entities.has(disruptor.id),"combat damages and destroys target")
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
	expect(not sim.known(0,enemy_core) and sim.explored[0].has(Vector2i(enemy_core.pos)),"enemy hides again while terrain remains explored")
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
	sim.remove_entity(enemy_core.id)
	expect(sim.winner == 0,"destroying rival Core wins")
	var elapsed = sim.elapsed
	advance(sim,5)
	expect(sim.elapsed == elapsed,"simulation freezes after victory")
	sim=DASimulation.new()
	sim.remove_entity(own(sim,"core")[0].id)
	expect(sim.winner==1,"losing player Core causes defeat")
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
	print("RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
