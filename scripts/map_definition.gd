class_name DAMapDefinition
extends Resource
## Data-only map contract. Mission setup consumes this without knowing presentation details.
@export var map_id: String = "silent_grid"
@export var display_name: String = "The Silent Grid"
@export var width: int = 72
@export var height: int = 72
@export var camera_min: Vector2 = Vector2.ONE
@export var camera_max: Vector2 = Vector2(70, 70)
@export var starts: Array[Vector2] = [Vector2(12, 36), Vector2(59, 36)]
@export var obstacle_cells: Array[Vector2i] = []
@export var resource_nodes: Array[Dictionary] = []
@export var starting_units: Array[Dictionary] = []
@export var prebuilt: Array[Dictionary] = []
@export var scenery: Array[Dictionary] = []
@export var road_bands: Array[Dictionary] = []

func resource_nodes_for_mission() -> Array[Dictionary]:
	return resource_nodes.duplicate(true)
