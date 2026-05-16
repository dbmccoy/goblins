extends Node3D

@export var base_movement_speed: float = 4.0
@export var movement_speed_jitter: float = 0.4
@export var animation_speed_jitter: float = 0.6
@export var movement_speed_change_interval: float = 0.35
@export var animation_speed_change_interval: float = 0.18
@export var target: Node3D

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var sprite: AnimatedSprite3D = $Sprite3D
@onready var item_flipper: Node3D = $item_flipper
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var shadow: MeshInstance3D = $shadow

var movement_speed: float
var movement_delta: float
var _movement_speed_timer: float = 0.0
var _animation_speed_timer: float = 0.0
var _facing_right: bool = false
var _smart_target_active: bool = false
var _smart_target: Vector3 = Vector3.ZERO
var _attacking: bool = false
var _held: bool = false

func _ready() -> void:
	add_to_group(&"goblins")
	navigation_agent.velocity_computed.connect(_on_velocity_computed)
	movement_speed = base_movement_speed
	_randomize_animation_speed()
	_randomize_movement_speed()
	_apply_facing()
	_apply_attacking()

func _process(delta: float) -> void:
	if _held:
		return
	if _smart_target_active:
		set_movement_target(_smart_target)
	elif target:
		set_movement_target(target.position)
	_animation_speed_timer -= delta
	if _animation_speed_timer <= 0.0:
		_randomize_animation_speed()

func set_movement_target(movement_target: Vector3) -> void:
	navigation_agent.set_target_position(movement_target)

func set_smart_target(pos: Vector3) -> void:
	_smart_target_active = true
	_smart_target = pos

func clear_smart_target() -> void:
	if not _smart_target_active:
		return
	_smart_target_active = false
	set_movement_target(global_position)

func set_held(value: bool) -> void:
	if _held == value:
		return
	_held = value
	shadow.visible = _held
	if _held:
		_set_animation(&"wiggle")
	else:
		set_movement_target(global_position)

func set_attacking(value: bool) -> void:
	if _attacking == value:
		return
	_attacking = value
	_apply_attacking()

func face_position(pos: Vector3) -> void:
	var dx: float = pos.x - global_position.x
	if absf(dx) > 0.001:
		_facing_right = dx > 0.0
		_apply_facing()

func _physics_process(delta: float) -> void:
	if _held:
		return
	_movement_speed_timer -= delta
	if _movement_speed_timer <= 0.0:
		_randomize_movement_speed()

	if navigation_agent.is_navigation_finished():
		_set_animation(&"idle")
		return

	movement_delta = movement_speed * delta
	var next_path_position: Vector3 = navigation_agent.get_next_path_position()
	var current_agent_position: Vector3 = global_position
	var direction: Vector3 = next_path_position - current_agent_position
	_update_facing_from_direction(direction)
	var new_velocity: Vector3 = direction.normalized() * movement_delta
	if navigation_agent.avoidance_enabled:
		navigation_agent.set_velocity(new_velocity)
	else:
		_on_velocity_computed(new_velocity)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	global_position = global_position.move_toward(global_position + safe_velocity, movement_delta)

func _update_facing_from_direction(direction: Vector3) -> void:
	if absf(direction.x) > 0.001:
		_facing_right = direction.x > 0.0
	_apply_facing()
	_set_animation(&"run_right" if _facing_right else &"run_left")

func _apply_facing() -> void:
	item_flipper.scale = Vector3(-1.0 if _facing_right else 1.0, 1.0, 1.0)

func _apply_attacking() -> void:
	if animation_player == null:
		return
	if _attacking:
		animation_player.play(&"whack")
	else:
		animation_player.play(&"RESET")

func _set_animation(anim: StringName) -> void:
	if sprite.animation != anim:
		sprite.animation = anim

func _randomize_animation_speed() -> void:
	sprite.speed_scale = randf_range(1.0 - animation_speed_jitter, 1.0 + animation_speed_jitter)
	_animation_speed_timer = animation_speed_change_interval * randf_range(0.5, 1.5)

func _randomize_movement_speed() -> void:
	movement_speed = base_movement_speed * randf_range(1.0 - movement_speed_jitter, 1.0 + movement_speed_jitter)
	_movement_speed_timer = movement_speed_change_interval * randf_range(0.5, 1.5)
