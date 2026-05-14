extends Node3D

@export var width : int = 100
@export var height : int = 100

@export var floor_mat : Array[BaseMaterial3D]

func _ready() -> void:
	print(width, "_", height)
	_generate_floor()
	
func _generate_floor() -> void:
	for y in range(height):
		for x in range(width):
			_generate_floor_tile(x, y)

func _generate_floor_tile(x : int, y : int) -> void:
	print(x, ":", y)
	var mesh : ArrayMesh = ArrayMesh.new()
	#mesh.position = Vector3(float(x), 0.0, float(y))
	
	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	
	# PackedVector**Arrays for mesh construction.
	var verts = PackedVector3Array()
	var uvs = PackedVector2Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()

	verts = PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(0, 0, 1),
		Vector3(1, 0, 0),
		Vector3(1, 0, 1),
	])
	
	uvs = PackedVector2Array([
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(0, 1),
		Vector2(1, 1),
	])
	
	uvs = PackedVector2Array([
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(0, 1),
		Vector2(1, 1),
	])
	
	indices = PackedInt32Array([
		0, 2, 1, # Draw the first triangle.
		2, 3, 1, # Draw the second triangle.
	])

	# Assign arrays to surface array.
	surface_array[Mesh.ARRAY_VERTEX] = verts
	surface_array[Mesh.ARRAY_TEX_UV] = uvs
	surface_array[Mesh.ARRAY_NORMAL] = normals
	surface_array[Mesh.ARRAY_INDEX] = indices

	# Create mesh surface from mesh array.
	# No blendshapes, lods, or compression used.
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	
