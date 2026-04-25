extends MeshInstance3D

const MAP_SIZE := 200.0
const FOG_Y   := 25.0  # above all terrain (peaks reach 22)
const MAX_SOURCES := 64

var _mat: ShaderMaterial = null

func _ready() -> void:
	_build_mesh()
	visible = false

func _build_mesh() -> void:
	var half := MAP_SIZE / 2.0

	# Two triangles covering the full map, UV2 = world XZ so shader can compute distances
	var verts := PackedVector3Array()
	var uv2   := PackedVector2Array()
	var indices := PackedInt32Array()

	# Quad corners: TL, TR, BL, BR
	var corners := [
		Vector3(-half, FOG_Y, -half),
		Vector3( half, FOG_Y, -half),
		Vector3(-half, FOG_Y,  half),
		Vector3( half, FOG_Y,  half),
	]
	for c in corners:
		verts.append(c)
		uv2.append(Vector2(c.x, c.z))

	# Two triangles (CCW from above)
	indices.append_array([0, 1, 2, 1, 3, 2])

	var arr := Array()
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = indices

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh = am

	var shader := load("res://assets/FogOfWar.gdshader") as Shader
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	material_override = _mat

	# Pre-fill sources array with zeroed vec4s
	var empty: Array[Vector4] = []
	empty.resize(MAX_SOURCES)
	for i in range(MAX_SOURCES):
		empty[i] = Vector4(0, 0, 0, 0)
	_mat.set_shader_parameter("sources", empty)
	_mat.set_shader_parameter("source_count", 0)

func update_sources(player_pos: Vector3, player_radius: float,
		minion_positions: Array, minion_radius: float,
		tower_positions: Array, tower_radius: float) -> void:
	if _mat == null:
		return

	var sources: Array[Vector4] = []
	sources.resize(MAX_SOURCES)
	for i in range(MAX_SOURCES):
		sources[i] = Vector4(0, 0, 0, 0)

	var count := 0

	# Player
	if count < MAX_SOURCES:
		sources[count] = Vector4(player_pos.x, player_pos.z, player_radius, 0.0)
		count += 1

	# Minions
	for pos in minion_positions:
		if count >= MAX_SOURCES:
			break
		sources[count] = Vector4(pos.x, pos.z, minion_radius, 0.0)
		count += 1

	# Towers
	for pos in tower_positions:
		if count >= MAX_SOURCES:
			break
		sources[count] = Vector4(pos.x, pos.z, tower_radius, 0.0)
		count += 1

	_mat.set_shader_parameter("sources", sources)
	_mat.set_shader_parameter("source_count", count)
