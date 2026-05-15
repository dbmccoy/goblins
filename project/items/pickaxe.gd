extends SmartObject

@export var attack_range: float = 1.6
@export var detection_range: float = 32.0
@export var swing_cooldown: float = 0.9
@export var swing_damage: int = 1

var _swing_timer: float = 0.0
var _map: Node = null

func _process(delta: float) -> void:
	super(delta)
	if _swing_timer > 0.0:
		_swing_timer -= delta

func _tick() -> void:
	var holder := get_holder()
	if holder == null:
		return
	if not (holder.has_method(&"set_smart_target") and holder.has_method(&"set_attacking")):
		return
	if _map == null:
		_map = get_tree().get_first_node_in_group(&"map")
		if _map == null:
			return

	var origin: Vector3 = holder.global_position

	var ore_cell = _map.find_nearest_ore_cell(origin, detection_range)
	if ore_cell != null:
		_engage_cell(holder, ore_cell)
		return

	var wall_cell = _map.find_nearest_plain_wall_cell(origin, detection_range)
	if wall_cell != null:
		_engage_cell(holder, wall_cell)
		return

	var victim := _find_passing_goblin(holder, attack_range)
	if victim != null:
		holder.clear_smart_target()
		holder.face_position(victim.global_position)
		holder.set_attacking(true)
		_try_swing()
		return

	holder.clear_smart_target()
	holder.set_attacking(false)

func _engage_cell(holder: Node3D, cell: Vector3i) -> void:
	var target_pos: Vector3 = _map.cell_to_world(cell)
	var dist := holder.global_position.distance_to(target_pos)
	if dist <= attack_range:
		holder.clear_smart_target()
		holder.face_position(target_pos)
		holder.set_attacking(true)
		if _try_swing():
			_map.damage_wall(cell, swing_damage)
	else:
		holder.set_smart_target(target_pos)
		holder.set_attacking(false)

func _try_swing() -> bool:
	if _swing_timer > 0.0:
		return false
	_swing_timer = swing_cooldown
	return true

func _find_passing_goblin(holder: Node3D, radius: float) -> Node3D:
	var best: Node3D = null
	var best_d: float = radius
	for n in get_tree().get_nodes_in_group(&"goblins"):
		if n == holder:
			continue
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d := holder.global_position.distance_to(n3.global_position)
		if d < best_d:
			best_d = d
			best = n3
	return best
