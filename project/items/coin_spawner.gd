extends Node3D

const LAYER_CELLS_BIT := 1 << 0
const LAYER_ITEMS_BIT := 1 << 1

@export var enabled: bool = true
@export var interval: float = 0.18
@export var interval_jitter: float = 0.4
@export var spawn_spread: float = 0.25
@export var coin_radius: float = 0.16
@export var coin_thickness: float = 0.05
@export var coin_collision_thickness: float = 0.18

var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = interval * _rng.randf_range(1.0 - interval_jitter, 1.0 + interval_jitter)
		_spawn_coin()


func _spawn_coin() -> void:
	var body := RigidBody3D.new()
	body.collision_layer = LAYER_ITEMS_BIT
	body.collision_mask = LAYER_CELLS_BIT | LAYER_ITEMS_BIT
	body.continuous_cd = true
	body.linear_damp = 0.2
	body.angular_damp = 0.15
	body.mass = 0.12
	body.add_to_group(&"debris")
	body.add_to_group(&"coins")

	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.45
	pmat.friction = 0.8
	body.physics_material_override = pmat

	var mesh_node := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = coin_radius
	disc.bottom_radius = coin_radius
	disc.height = coin_thickness
	mesh_node.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.83, 0.22)
	mat.metallic = 0.95
	mat.roughness = 0.18
	mesh_node.material_override = mat
	body.add_child(mesh_node)

	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = coin_radius
	shape.height = coin_collision_thickness
	collider.shape = shape
	body.add_child(collider)

	add_child(body)
	body.global_position = global_position + Vector3(
		_rng.randf_range(-spawn_spread, spawn_spread),
		0.0,
		_rng.randf_range(-spawn_spread, spawn_spread),
	)
	body.rotation = Vector3(
		_rng.randf_range(-PI, PI),
		_rng.randf_range(-PI, PI),
		_rng.randf_range(-PI, PI),
	)
	body.angular_velocity = Vector3(
		_rng.randf_range(-4.0, 4.0),
		_rng.randf_range(-4.0, 4.0),
		_rng.randf_range(-4.0, 4.0),
	)
