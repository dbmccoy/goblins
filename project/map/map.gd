extends Node3D

const CLEARING_RADIUS := 4
const CARDINAL_OFFSETS: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
# GridMap orthogonal-index values for the four 90-degree rotations around Y.
const Y_ROTATIONS: Array = [0, 22, 10, 16]

@export var generation_seed: int = 0
@export var ore_initial_density: float = 0.42
@export var ore_ca_iterations: int = 4
@export var ore_birth_threshold: int = 6
@export var ore_survive_threshold: int = 4

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var grid_map: GridMap = $NavigationRegion3D/GridMap

var _rng := RandomNumberGenerator.new()
var _floor_id: int = -1
var _wall_damage_ids: Array[int] = []
var _wall_health: Dictionary = {}
var _ore_nodes: Dictionary = {}


func _ready() -> void:
	if generation_seed != 0:
		_rng.seed = generation_seed
	else:
		_rng.randomize()
	_resolve_meshlib_items()
	_generate()
	_rebake_nav()


func _resolve_meshlib_items() -> void:
	var lib := grid_map.mesh_library
	_floor_id = lib.find_item_by_name("floor_1")
	_wall_damage_ids.clear()
	var i := 1
	while true:
		var id := lib.find_item_by_name("wall_%d" % i)
		if id == -1:
			break
		_wall_damage_ids.append(id)
		i += 1
	if _floor_id == -1 or _wall_damage_ids.is_empty():
		push_error("map_meshlib missing required items (floor_1 / wall_N)")


func _generate() -> void:
	grid_map.clear()
	_wall_health.clear()
	for ore in _ore_nodes.values():
		ore.queue_free()
	_ore_nodes.clear()

	var floor_cells: Array[Vector3i] = []
	for x in range(-CLEARING_RADIUS, CLEARING_RADIUS + 1):
		for z in range(-CLEARING_RADIUS, CLEARING_RADIUS + 1):
			var c := Vector3i(x, 0, z)
			_place_floor(c)
			floor_cells.append(c)

	var wall_cells: Array[Vector3i] = []
	for c in floor_cells:
		for off in CARDINAL_OFFSETS:
			var n: Vector3i = c + off
			if grid_map.get_cell_item(n) == GridMap.INVALID_CELL_ITEM:
				_place_wall(n)
				wall_cells.append(n)

	_seed_ores(wall_cells)


func _place_floor(cell: Vector3i) -> void:
	grid_map.set_cell_item(cell, _floor_id, _random_y_orientation())
	_wall_health.erase(cell)


func _place_wall(cell: Vector3i) -> void:
	grid_map.set_cell_item(cell, _wall_damage_ids[0], _random_y_orientation())
	_wall_health[cell] = _wall_damage_ids.size()


func _random_y_orientation() -> int:
	return Y_ROTATIONS[_rng.randi() % Y_ROTATIONS.size()]


func _seed_ores(wall_cells: Array[Vector3i]) -> void:
	var alive: Dictionary = {}
	for c in wall_cells:
		if _rng.randf() < ore_initial_density:
			alive[c] = true

	for _i in ore_ca_iterations:
		var next_alive: Dictionary = {}
		for c in wall_cells:
			var n_count := 0
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if dx == 0 and dz == 0:
						continue
					if alive.has(c + Vector3i(dx, 0, dz)):
						n_count += 1
			if alive.has(c):
				if n_count >= ore_survive_threshold:
					next_alive[c] = true
			else:
				if n_count >= ore_birth_threshold:
					next_alive[c] = true
		alive = next_alive

	for c in alive.keys():
		_spawn_ore_at(c)


func _spawn_ore_at(cell: Vector3i) -> void:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.75, 0.2)
	mat.metallic = 0.7
	mat.roughness = 0.3
	node.material_override = mat
	node.position = grid_map.map_to_local(cell)
	grid_map.add_child(node)
	_ore_nodes[cell] = node


func damage_wall(cell: Vector3i, amount: int = 1) -> void:
	if not _wall_health.has(cell):
		return
	_wall_health[cell] -= amount
	if _wall_health[cell] <= 0:
		_destroy_wall(cell)
	else:
		_refresh_wall_visual(cell)


func _refresh_wall_visual(cell: Vector3i) -> void:
	var stages := _wall_damage_ids.size()
	var hp: int = _wall_health[cell]
	var stage := clampi(stages - hp, 0, stages - 1)
	var orientation := grid_map.get_cell_item_orientation(cell)
	grid_map.set_cell_item(cell, _wall_damage_ids[stage], orientation)


func _destroy_wall(cell: Vector3i) -> void:
	_place_floor(cell)
	if _ore_nodes.has(cell):
		_ore_nodes[cell].queue_free()
		_ore_nodes.erase(cell)
	for off in CARDINAL_OFFSETS:
		var n: Vector3i = cell + off
		if grid_map.get_cell_item(n) == GridMap.INVALID_CELL_ITEM:
			_place_wall(n)
	_rebake_nav.call_deferred()


func _rebake_nav() -> void:
	nav_region.bake_navigation_mesh()
