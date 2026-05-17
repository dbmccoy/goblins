extends StaticBody3D

const LAYER_ITEMS_BIT := 1 << 1
const LAYER_CHARACTERS_BIT := 1 << 2

@export var hop_range_min: float = 1.4
@export var hop_range_max: float = 3.0
@export var idle_time_min: float = 0.8
@export var idle_time_max: float = 2.2
@export var hop_duration: float = 0.45
@export var hop_height: float = 0.7
@export var max_hp: int = 3
@export var contact_damage: int = 1
@export var contact_cooldown: float = 0.8
@export var rock_damage_speed: float = 2.5
@export var spawn_invuln: float = 0.8
@export var hitbox_radius: float = 0.55
@export var hurt_sound: AudioStream

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var sprite: AnimatedSprite3D = $Sprite3D

enum State { IDLE, HOP }

var _state: State = State.IDLE
var _state_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _facing_right: bool = false
var _hopping: bool = false
var _hp: int = 3
var _dead: bool = false
var _invuln_timer: float = 0.0
var _contact_cooldowns: Dictionary = {}
var _hit_area: Area3D

func _ready() -> void:
	add_to_group(&"slimes")
	_rng.randomize()
	_hp = max_hp
	_invuln_timer = spawn_invuln
	_apply_facing()
	_setup_hit_area()
	_enter_idle()

func _setup_hit_area() -> void:
	_hit_area = Area3D.new()
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = LAYER_ITEMS_BIT | LAYER_CHARACTERS_BIT
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = hitbox_radius
	shape.shape = sphere
	_hit_area.add_child(shape)
	add_child(_hit_area)
	_hit_area.body_entered.connect(_on_hit_area_body_entered)

func _process(delta: float) -> void:
	if _dead:
		return
	if _invuln_timer > 0.0:
		_invuln_timer -= delta
	_tick_contact_cooldowns(delta)
	_damage_overlapping_goblins()
	if _hopping:
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		match _state:
			State.IDLE:
				_try_hop()
			State.HOP:
				_enter_idle()


func _tick_contact_cooldowns(delta: float) -> void:
	if _contact_cooldowns.is_empty():
		return
	var expired: Array = []
	for goblin in _contact_cooldowns.keys():
		var t: float = _contact_cooldowns[goblin] - delta
		if t <= 0.0 or not is_instance_valid(goblin):
			expired.append(goblin)
		else:
			_contact_cooldowns[goblin] = t
	for goblin in expired:
		_contact_cooldowns.erase(goblin)


func _damage_overlapping_goblins() -> void:
	if _hit_area == null:
		return
	for body in _hit_area.get_overlapping_bodies():
		if not body.is_in_group(&"goblins"):
			continue
		if _contact_cooldowns.has(body):
			continue
		if not body.has_method(&"take_damage"):
			continue
		body.take_damage(contact_damage)
		_contact_cooldowns[body] = contact_cooldown


func _on_hit_area_body_entered(body: Node) -> void:
	if _dead or _invuln_timer > 0.0:
		return
	if body == self:
		return
	if body.is_in_group(&"debris"):
		var rb: RigidBody3D = body as RigidBody3D
		if rb == null:
			return
		if rb.linear_velocity.length() < rock_damage_speed:
			return
		take_damage(1)


func take_damage(amount: int = 1) -> void:
	if _dead or amount <= 0:
		return
	_hp -= amount
	Damage.flash(sprite)
	Damage.play_sound(self, hurt_sound)
	if _hp <= 0:
		_die()


func _die() -> void:
	_dead = true
	queue_free()

func _enter_idle() -> void:
	_state = State.IDLE
	_state_timer = _rng.randf_range(idle_time_min, idle_time_max)
	_play(&"idle")

func _try_hop() -> void:
	var target_variant: Variant = _pick_hop_target()
	if target_variant == null:
		_state_timer = 0.5
		return
	_enter_hop(target_variant as Vector3)

func _pick_hop_target() -> Variant:
	var nav_map: RID = navigation_agent.get_navigation_map()
	if not nav_map.is_valid():
		return null
	for _attempt in 8:
		var angle: float = _rng.randf() * TAU
		var dist: float = _rng.randf_range(hop_range_min, hop_range_max)
		var candidate: Vector3 = global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, candidate)
		var travel: float = Vector3(closest.x - global_position.x, 0.0, closest.z - global_position.z).length()
		if travel >= hop_range_min * 0.5:
			return closest
	return null

func _enter_hop(target: Vector3) -> void:
	_state = State.HOP
	_hopping = true
	_state_timer = hop_duration
	_face_position(target)
	_play(&"jump")

	var from: Vector3 = global_position
	var tween: Tween = create_tween()
	tween.tween_method(func(t: float) -> void:
		global_position = Vector3(
			lerpf(from.x, target.x, t),
			lerpf(from.y, target.y, t) + hop_height * 4.0 * t * (1.0 - t),
			lerpf(from.z, target.z, t)
		)
	, 0.0, 1.0, hop_duration)
	tween.tween_callback(func() -> void:
		global_position = target
		_hopping = false
		_enter_idle()
	)

func _face_position(pos: Vector3) -> void:
	var dx: float = pos.x - global_position.x
	if absf(dx) > 0.001:
		_facing_right = dx > 0.0
		_apply_facing()

func _apply_facing() -> void:
	sprite.flip_h = _facing_right

func _play(anim: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(anim):
		return
	if sprite.animation == anim:
		return
	sprite.play(anim)
