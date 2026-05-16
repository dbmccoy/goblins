extends Node3D

const CLEARING_RADIUS := 4
const CARDINAL_OFFSETS: Array = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
# GridMap orthogonal-index values for the four 90-degree rotations around Y.
const Y_ROTATIONS: Array = [0, 22, 10, 16]

const LAYER_CELLS_BIT := 1 << 0
const LAYER_ITEMS_BIT := 1 << 1

@export var generation_seed: int = 0
@export var ore_initial_density: float = 0.42
@export var ore_ca_iterations: int = 4
@export var ore_birth_threshold: int = 3
@export var ore_survive_threshold: int = 4
@export var rock_chips_per_hit: int = 1
@export var rocks_per_break: int = 3
@export var ore_nuggets_per_break: int = 3
@export var debug_ore_visibility: bool = true

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var grid_map: GridMap = $NavigationRegion3D/GridMap

var _rng := RandomNumberGenerator.new()
var _floor_id: int = -1
var _wall_damage_ids: Array[int] = []
var _wall_health: Dictionary = {}
var _ore_nodes: Dictionary = {}
var _ore_visible: Dictionary = {}


func _ready() -> void:
	add_to_group(&"map")
	if generation_seed != 0:
		_rng.seed = generation_seed
	else:
		_rng.randomize()
	_resolve_meshlib_items()
	_generate()
	_rebake_nav()


func cell_to_world(cell: Vector3i) -> Vector3:
	return grid_map.to_global(grid_map.map_to_local(cell))


func find_nearest_ore_cell(origin: Vector3, max_range: float) -> Variant:
	var best: Variant = null
	var best_d: float = max_range
	for cell in _ore_nodes.keys():
		var d := origin.distance_to(cell_to_world(cell))
		if d < best_d:
			best_d = d
			best = cell
	return best


func find_nearest_plain_wall_cell(origin: Vector3, max_range: float) -> Variant:
	var best: Variant = null
	var best_d: float = max_range
	for cell in _wall_health.keys():
		if _ore_nodes.has(cell):
			continue
		var d := origin.distance_to(cell_to_world(cell))
		if d < best_d:
			best_d = d
			best = cell
	return best


func find_approach_cell(wall_cell: Vector3i, origin: Vector3) -> Variant:
	var best: Variant = null
	var best_d: float = INF
	for off in CARDINAL_OFFSETS:
		var floor_cell: Vector3i = wall_cell + off
		if grid_map.get_cell_item(floor_cell) != _floor_id:
			continue
		var d := origin.distance_to(cell_to_world(floor_cell))
		if d < best_d:
			best_d = d
			best = floor_cell
	return best


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
	_ore_visible.clear()

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

	if alive.is_empty() and not wall_cells.is_empty():
		alive[wall_cells[_rng.randi() % wall_cells.size()]] = true

	for c in alive.keys():
		_spawn_ore_at(c)


func _spawn_ore_at(cell: Vector3i) -> void:
	var parent := Node3D.new()
	parent.position = grid_map.map_to_local(cell)
	grid_map.add_child(parent)
	_ore_nodes[cell] = parent
	_populate_ore_nuggets(cell)


func _populate_ore_nuggets(cell: Vector3i) -> void:
	var parent: Node3D = _ore_nodes[cell]
	for child in parent.get_children():
		child.queue_free()

	var exposed_faces: Array = []
	for off in CARDINAL_OFFSETS:
		if grid_map.get_cell_item(cell + off) == _floor_id:
			exposed_faces.append(off)

	var was_visible: bool = _ore_visible.get(cell, false)
	var is_visible := not exposed_faces.is_empty()
	_ore_visible[cell] = is_visible
	if debug_ore_visibility and is_visible and not was_visible:
		print("[map] gold wall exposed at %s (faces: %s)" % [cell, exposed_faces])

	if exposed_faces.is_empty():
		return

	var nugget_count := _rng.randi_range(4, 5)
	for i in nugget_count:
		var face: Vector3i = exposed_faces[i % exposed_faces.size()]
		_add_nugget(parent, face)


func _add_nugget(parent: Node3D, face: Vector3i) -> void:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	var r := _rng.randf_range(0.15, 0.3)
	mesh.radius = r
	mesh.height = r * 2.0
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.75, 0.2)
	mat.metallic = 0.8
	mat.roughness = 0.3
	node.material_override = mat

	var face_v := Vector3(face.x, 0.0, face.z)
	var perp := Vector3(-face_v.z, 0.0, face_v.x)
	node.position = (
		face_v * _rng.randf_range(0.38, 0.48)
		+ perp * _rng.randf_range(-0.32, 0.32)
		+ Vector3.UP * _rng.randf_range(0.15, 0.75)
	)
	parent.add_child(node)


func damage_wall(cell: Vector3i, amount: int = 1) -> void:
	if not _wall_health.has(cell):
		return
	var fly_dir := _compute_fly_direction(cell)
	var had_ore := _ore_nodes.has(cell)
	_wall_health[cell] -= amount
	if _wall_health[cell] <= 0:
		_eject_break_debris(cell, fly_dir, had_ore)
		_destroy_wall(cell)
	else:
		_eject_hit_debris(cell, fly_dir)
		_refresh_wall_visual(cell)


func _compute_fly_direction(cell: Vector3i) -> Vector3:
	var dir := Vector3.ZERO
	for off in CARDINAL_OFFSETS:
		var n: Vector3i = cell + off
		if grid_map.get_cell_item(n) == _floor_id:
			dir += Vector3(off.x, 0.0, off.z)
	if dir.length_squared() < 0.0001:
		var a := _rng.randf() * TAU
		return Vector3(cos(a), 0.0, sin(a))
	return dir.normalized()


func _eject_hit_debris(cell: Vector3i, dir: Vector3) -> void:
	for _i in rock_chips_per_hit:
		_spawn_pebble(cell, dir, false)


func _eject_break_debris(cell: Vector3i, dir: Vector3, had_ore: bool) -> void:
	for _i in rocks_per_break:
		_spawn_pebble(cell, dir, false)
	if had_ore:
		for _i in ore_nuggets_per_break:
			_spawn_pebble(cell, dir, true)


func _spawn_pebble(cell: Vector3i, dir: Vector3, is_ore: bool) -> void:
	var radius := 0.13 if is_ore else 0.09
	var body := RigidBody3D.new()
	body.collision_layer = LAYER_ITEMS_BIT
	body.collision_mask = LAYER_CELLS_BIT | LAYER_ITEMS_BIT
	body.continuous_cd = true
	body.linear_damp = 0.35
	body.angular_damp = 0.25
	body.mass = 0.4 if is_ore else 0.2
	body.add_to_group(&"debris")

	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.55
	pmat.friction = 0.75
	body.physics_material_override = pmat

	var mesh_node := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	mesh_node.mesh = sphere_mesh
	var mat := StandardMaterial3D.new()
	if is_ore:
		mat.albedo_color = Color(0.95, 0.75, 0.2)
		mat.metallic = 0.85
		mat.roughness = 0.25
	else:
		mat.albedo_color = Color(0.42, 0.4, 0.38)
		mat.roughness = 0.95
	mesh_node.material_override = mat
	body.add_child(mesh_node)

	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	collider.shape = shape
	body.add_child(collider)

	var origin := grid_map.map_to_local(cell) + dir * 0.55
	body.position = origin + Vector3(
		_rng.randf_range(-0.12, 0.12),
		_rng.randf_range(0.05, 0.35),
		_rng.randf_range(-0.12, 0.12),
	)
	grid_map.add_child(body)

	var horiz_speed := _rng.randf_range(3.0, 5.5)
	var up_speed := _rng.randf_range(2.8, 4.5)
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var spread := _rng.randf_range(-0.6, 0.6)
	var launch := (dir + perp * spread).normalized() * horiz_speed + Vector3.UP * up_speed
	body.linear_velocity = launch
	body.angular_velocity = Vector3(
		_rng.randf_range(-14.0, 14.0),
		_rng.randf_range(-14.0, 14.0),
		_rng.randf_range(-14.0, 14.0),
	)


func _refresh_wall_visual(cell: Vector3i) -> void:
	var stages := _wall_damage_ids.size()
	var hp: int = _wall_health[cell]
	var stage := clampi(stages - hp, 0, stages - 1)
	var orientation := grid_map.get_cell_item_orientation(cell)
	grid_map.set_cell_item(cell, _wall_damage_ids[stage], orientation)


func _destroy_wall(cell: Vector3i) -> void:
	_place_floor(cell)
	if _ore_nodes.has(cell):
		if debug_ore_visibility and _ore_visible.get(cell, false):
			print("[map] gold wall mined at %s" % [cell])
		_ore_nodes[cell].queue_free()
		_ore_nodes.erase(cell)
		_ore_visible.erase(cell)
	for off in CARDINAL_OFFSETS:
		var n: Vector3i = cell + off
		if grid_map.get_cell_item(n) == GridMap.INVALID_CELL_ITEM:
			_place_wall(n)
		elif _ore_nodes.has(n):
			_populate_ore_nuggets(n)
	_rebake_nav.call_deferred()


func _rebake_nav() -> void:
	nav_region.bake_navigation_mesh()
