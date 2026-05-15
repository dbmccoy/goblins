extends Node3D

const LAYER_CELLS := 1 << 0
const LAYER_ITEMS := 1 << 1
const LAYER_CHARACTERS := 1 << 2
const LAYER_BUILDINGS := 1 << 3

@onready var gridmap = get_tree().root.find_child("GridMap", true, false) as GridMap

var dragging: Node3D = null
var drag_layer: int = 0

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag()
		else:
			_end_drag()
	elif event is InputEventMouseMotion:
		_update_hover()

func _update_hover() -> void:
	if dragging != null:
		_update_drag_position()
		return
	var hover = _raycast(LAYER_CELLS | LAYER_ITEMS | LAYER_CHARACTERS | LAYER_BUILDINGS)
	if hover.is_empty():
		return
	if hover.layer == LAYER_CELLS:
		position = hover.cell

func _update_drag_position() -> void:
	var hit = _raycast(LAYER_CELLS, [dragging])
	if hit.is_empty():
		return
	dragging.global_position = hit.position

func _start_drag() -> void:
	var hit = _raycast(LAYER_ITEMS | LAYER_CHARACTERS)
	if hit.is_empty():
		return
	dragging = hit.collider
	drag_layer = hit.layer
	print("Pick up ", _layer_name(drag_layer), ": ", dragging.name)

func _end_drag() -> void:
	if dragging == null:
		return

	var target_mask := 0
	match drag_layer:
		LAYER_ITEMS:
			target_mask = LAYER_CELLS | LAYER_CHARACTERS | LAYER_BUILDINGS
		LAYER_CHARACTERS:
			target_mask = LAYER_BUILDINGS

	var drop = _raycast(target_mask, [dragging])
	if not drop.is_empty():
		_handle_drop(dragging, drag_layer, drop)
	else:
		print("Drop cancelled: no valid target under cursor")

	dragging = null
	drag_layer = 0

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
