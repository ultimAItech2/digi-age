class_name DACatalog
extends Resource
## Balance definitions. Costs are [metal, energy, data]; positions use map cells.
@export var units: Dictionary = {}
@export var buildings: Dictionary = {}
@export var ages: Array[String] = ["AWAKENING", "NETWORK", "SINGULARITY"]
@export var age_costs: Array[Vector3] = [Vector3(400, 250, 120), Vector3(750, 550, 260)]
@export var age_times: Array[float] = [45.0, 65.0]
@export var upgrade_costs: Array[Vector3] = [Vector3(180, 150, 60), Vector3(300, 250, 120)]
@export var starting_resources: Vector3 = Vector3(600, 350, 0)
@export var energy_per_second: float = 3.0
@export var gather_per_second: float = 3.0
@export var population_limit: int = 100
@export var tick_seconds: float = 0.1

func definition(kind: String) -> Dictionary:
	return units.get(kind, buildings.get(kind, {}))
