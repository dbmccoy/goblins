class_name SmartObject
extends Node

@export var tick_interval: float = 0.4

var _tick_timer: float = 0.0

func _ready() -> void:
	_tick_timer = randf() * tick_interval

func _process(delta: float) -> void:
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval * randf_range(0.85, 1.15)
		_tick()

func get_item() -> Node3D:
	return get_parent() as Node3D

func get_holder() -> Node3D:
	var item := get_item()
	if item == null:
		return null
	var slot := item.get_parent() as Node3D
	if slot == null or String(slot.name) != "held_item":
		return null
	var flipper := slot.get_parent() as Node3D
	if flipper == null:
		return null
	return flipper.get_parent() as Node3D

func _tick() -> void:
	pass
