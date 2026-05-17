extends Node3D

const LAYER_CELLS := 1 << 0
const LAYER_ITEMS := 1 << 1
const LAYER_CHARACTERS := 1 << 2
const LAYER_BUILDINGS := 1 << 3

@export var hurt_sound: AudioStream
@export var damage_lockout_duration: float = 1.0

@onready var gridmap = get_tree().root.find_child("GridMap", true, false) as GridMap
@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D

const INTERACTABLE_MASK := LAYER_ITEMS | LAYER_CHARACTERS | LAYER_BUILDINGS
const GRAB_OFFSET := {
	LAYER_CHARACTERS: Vector3(0, 0, 1.5),
}
const DRAG_PLANE_Y := 0.5

var dragging: Node3D = null
var drag_layer: int = 0

var _shake_energy: float = 0.0
var _last_shake_vel_x: float = 0.0
var _drag_world_vel: Vector3 = Vector3.ZERO
var _prev_drag_world_pos: Vector3 = Vector3.ZERO
var _prev_drag_world_time: float = 0.0
var _damage_lockout: float = 0.0

const SHAKE_VEL_THRESHOLD := 150.0  # px/s
const SHAKE_ENERGY_PER_REVERSAL := 1.0
const SHAKE_ENERGY_DECAY := 3.0
const SHAKE_TRIGGER := 2.0
const THROW_VEL_THRESHOLD := 3.0  # world units/s
const ITEM_THROW_UP_BOOST := 1.5

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	sprite.visible = true
	sprite.no_depth_test = true
	sprite.render_priority = 127

func _process(delta: float) -> void:
	var prev_energy := _shake_energy
	_shake_energy = maxf(_shake_energy - SHAKE_ENERGY_DECAY * delta, 0.0)
	if prev_energy > 0.0 and _shake_energy == 0.0:
		if dragging != null and drag_layer == LAYER_CHARACTERS and dragging.has_method("play_anim"):
			dragging.play_anim(&"wiggle")
	if _damage_lockout > 0.0:
		_damage_lockout = maxf(_damage_lockout - delta, 0.0)


func take_damage(_amount: int = 1) -> void:
	Damage.flash(sprite)
	Damage.play_sound(self, hurt_sound)
	_damage_lockout = damage_lockout_duration

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag()
		else:
			_end_drag()
	elif event is InputEventMouseMotion:
		if dragging != null and drag_layer == LAYER_CHARACTERS:
			_check_shake(event.velocity.x)
		_update_hover()

func _update_hover() -> void:
	if dragging != null:
		_update_drag_position()
		return
	var pos = _mouse_on_plane(DRAG_PLANE_Y)
	if pos != null:
		global_position = pos
	var hover = _raycast(LAYER_CELLS | LAYER_ITEMS | LAYER_CHARACTERS | LAYER_BUILDINGS)
	_set_anim("hover" if not hover.is_empty() and hover.layer & INTERACTABLE_MASK else "idle")

func _update_drag_position() -> void:
	var pos = _mouse_on_plane(DRAG_PLANE_Y)
	if pos == null:
		return
	var now: float = Time.get_ticks_msec() * 0.001
	if _prev_drag_world_time > 0.0:
		var dt: float = now - _prev_drag_world_time
		if dt > 0.001:
			_drag_world_vel = (pos - _prev_drag_world_pos) / dt
	_prev_drag_world_pos = pos
	_prev_drag_world_time = now
	global_position = pos
	var clamped = _clamp_to_nav(pos)
	dragging.global_position = clamped + GRAB_OFFSET.get(drag_layer, Vector3.ZERO)

func _clamp_to_nav(pos: Vector3) -> Vector3:
	var map_node := get_tree().get_first_node_in_group(&"map")
	if map_node == null:
		return pos
	return map_node.clamp_to_floor(pos)

func _mouse_on_plane(y: float):
	var camera = get_viewport().get_camera_3d()
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t = (y - origin.y) / dir.y
	if t < 0:
		return null
	return origin + dir * t

func _start_drag() -> void:
	if _damage_lockout > 0.0:
		return
	var hit = _raycast(LAYER_ITEMS | LAYER_CHARACTERS)
	if hit.is_empty():
		return
	var collider: Node = hit.collider as Node
	if collider != null and collider.is_in_group(&"slimes"):
		take_damage(1)
		print("Slime bites cursor!")
		return
	dragging = hit.collider
	drag_layer = hit.layer
	_drag_world_vel = Vector3.ZERO
	_prev_drag_world_time = 0.0
	_set_anim("grab")
	if dragging.has_method("set_held"):
		dragging.set_held(true)
	var rb: RigidBody3D = dragging as RigidBody3D
	if rb != null:
		rb.freeze = true
	print("Pick up ", _layer_name(drag_layer), ": ", dragging.name)

func _end_drag() -> void:
	if dragging == null:
		return

	var thrown: bool = false
	if _drag_world_vel.length() >= THROW_VEL_THRESHOLD:
		if drag_layer == LAYER_CHARACTERS and dragging.has_method(&"throw"):
			dragging.throw(_drag_world_vel)
			thrown = true
		elif drag_layer == LAYER_ITEMS:
			var rb: RigidBody3D = dragging as RigidBody3D
			if rb != null:
				rb.freeze = false
				rb.linear_velocity = _drag_world_vel + Vector3.UP * ITEM_THROW_UP_BOOST
				rb.angular_velocity = Vector3(
					randf_range(-12.0, 12.0),
					randf_range(-12.0, 12.0),
					randf_range(-12.0, 12.0),
				)
				thrown = true

	if not thrown:
		var target_mask := 0
		match drag_layer:
			LAYER_ITEMS:
				target_mask = LAYER_CELLS | LAYER_CHARACTERS | LAYER_BUILDINGS
			LAYER_CHARACTERS:
				target_mask = LAYER_BUILDINGS

		var drop = _raycast(target_mask, [dragging])
		var dropped_on_character: bool = not drop.is_empty() and drop.layer == LAYER_CHARACTERS
		if not drop.is_empty():
			_handle_drop(dragging, drag_layer, drop)
		else:
			print("Drop cancelled: no valid target under cursor")

		if dragging.has_method(&"set_held"):
			dragging.set_held(false)
		var rb_drop: RigidBody3D = dragging as RigidBody3D
		if rb_drop != null and not dropped_on_character:
			rb_drop.freeze = false

	_drag_world_vel = Vector3.ZERO
	dragging = null
	drag_layer = 0
	_update_hover()

func _set_anim(name: String) -> void:
	if sprite and sprite.animation != name:
		sprite.play(name)

func _handle_drop(source: Node3D, source_layer: int, drop: Dictionary) -> void:
	var target = drop.collider
	match [source_layer, drop.layer]:
		[LAYER_ITEMS, LAYER_CHARACTERS]:
			var slot: Node3D = target.find_child("held_item", true, false) as Node3D
			if slot == null:
				push_warning("Character '%s' has no 'held_item' node" % target.name)
				return
			source.reparent(slot)
			source.transform = Transform3D.IDENTITY
			if "collision_layer" in source:
				source.collision_layer = 0
			print("Give item '", source.name, "' to character '", target.name, "'")
		[LAYER_CHARACTERS, LAYER_BUILDINGS]:
			print("Assign character '", source.name, "' to building '", target.name, "'")
		[LAYER_ITEMS, LAYER_CELLS]:
			print("Drop item '", source.name, "' on cell ", drop.cell)
		[LAYER_ITEMS, LAYER_BUILDINGS]:
			print("Deposit item '", source.name, "' into building '", target.name, "'")

func _raycast(mask: int, exclude: Array = []) -> Dictionary:
	var camera = get_viewport().get_camera_3d()
	var mouse_pos = get_viewport().get_mouse_position()
	var space_state = get_world_3d().direct_space_state

	var origin = camera.project_ray_origin(mouse_pos)
	var end = origin + camera.project_ray_normal(mouse_pos) * 1000.0

	var query = PhysicsRayQueryParameters3D.create(origin, end, mask)
	if not exclude.is_empty():
		var rids: Array[RID] = []
		for n in exclude:
			if n is CollisionObject3D:
				rids.append(n.get_rid())
		query.exclude = rids
	var result = space_state.intersect_ray(query)

	if result.is_empty():
		return {}

	var collider = result.collider
	var layer = _primary_layer(collider, mask)
	var info := {
		"collider": collider,
		"layer": layer,
		"position": result.position,
		"normal": result.normal,
	}
	if collider == gridmap:
		var inset = result.position - result.normal * 0.1
		info["cell"] = gridmap.local_to_map(gridmap.to_local(inset))
	return info

func _primary_layer(body, mask: int) -> int:
	if body == null or not "collision_layer" in body:
		return 0
	var bits: int = body.collision_layer & mask
	for layer in [LAYER_CELLS, LAYER_ITEMS, LAYER_CHARACTERS, LAYER_BUILDINGS]:
		if bits & layer:
			return layer
	return 0

func _layer_name(layer: int) -> String:
	match layer:
		LAYER_CELLS: return "cell"
		LAYER_ITEMS: return "item"
		LAYER_CHARACTERS: return "character"
		LAYER_BUILDINGS: return "building"
		_: return "unknown"

func _check_shake(dx: float) -> void:
	if abs(dx) < SHAKE_VEL_THRESHOLD:
		return
	if _last_shake_vel_x != 0.0 and signf(_last_shake_vel_x) != signf(dx):
		_shake_energy += SHAKE_ENERGY_PER_REVERSAL
		if _shake_energy >= SHAKE_TRIGGER:
			_shake_energy = 0.0
			_last_shake_vel_x = 0.0
			if dragging != null and dragging.has_method("play_anim"):
				dragging.play_anim(&"fall")
			_do_shake_drop()
			return
	_last_shake_vel_x = dx

func _do_shake_drop() -> void:
	if dragging == null or drag_layer != LAYER_CHARACTERS:
		return
	var slot := dragging.find_child("held_item", true, false) as Node3D
	if slot == null or slot.get_child_count() == 0:
		return
	var item := slot.get_child(0) as Node3D
	if item == null:
		return
	var launch_from := dragging.global_position
	var scene_root := get_tree().root.get_child(0) as Node3D
	item.reparent(scene_root, true)
	print("Shake drop: ", item.name)
	_fling_item(item, launch_from)

func _fling_item(item: Node3D, from: Vector3) -> void:
	var angle := randf() * TAU
	var dist := randf_range(1.5, 3.0)
	var raw_land := Vector3(from.x + cos(angle) * dist, 0.0, from.z + sin(angle) * dist)
	var land := _clamp_to_nav(raw_land)
	land.y = 0.0
	var arc_height := randf_range(1.2, 2.0)
	var from_y := from.y
	var tween := create_tween()
	tween.tween_method(func(t: float):
		item.global_position = Vector3(
			lerpf(from.x, land.x, t),
			lerpf(from_y, 0.0, t) + arc_height * 4.0 * t * (1.0 - t),
			lerpf(from.z, land.z, t)
		)
	, 0.0, 1.0, 0.6)
	tween.tween_callback(func():
		if "collision_layer" in item:
			item.collision_layer = LAYER_ITEMS
		item.global_position = land
	)
