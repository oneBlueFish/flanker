extends Camera3D

const PAN_SPEED := 40.0
const ZOOM_SPEED := 5.0
const MIN_FOV := 30.0
const MAX_FOV := 100.0

const TOWER_MODEL_PATH := "res://assets/tower-defense-kit/Models/GLB format/tower-square-build-a.glb"
const SLOPE_THRESHOLD := 0.85
const TOWER_RANGE := 30.0
const RANGE_CIRCLE_SEGMENTS := 64
const PLAYER_VISION_RADIUS := 35.0
const MINION_VISION_RADIUS := 25.0

var build_system: Node = null

var _ghost: Node3D = null
var _ghost_mat_valid: StandardMaterial3D = null
var _ghost_mat_invalid: StandardMaterial3D = null
var _ghost_valid: bool = false
var _ghost_world_pos: Vector3 = Vector3.ZERO
var _player_team: int = 0

var _fog_overlay: MeshInstance3D = null

var _range_mesh_inst: MeshInstance3D = null
var _range_imesh: ImmediateMesh = null
var _range_mat_valid: StandardMaterial3D = null
var _range_mat_invalid: StandardMaterial3D = null

func _ready() -> void:
	build_system = get_node_or_null("/root/Main/BuildSystem")
	rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_build_ghost_materials()
	_create_fog_overlay()

func setup(team: int) -> void:
	_player_team = team
	var base_z: float = 84.0 if team == 0 else -93.0
	global_position = Vector3(0.0, 80.0, base_z)

func _create_fog_overlay() -> void:
	var fog_script := load("res://scripts/FogOverlay.gd")
	_fog_overlay = MeshInstance3D.new()
	_fog_overlay.set_script(fog_script)
	_fog_overlay.name = "FogOverlay"
	# Add to world so it sits in scene space, not camera space
	call_deferred("_add_fog_to_world")

# ── Ghost materials ──────────────────────────────────────────────────────────

func _add_fog_to_world() -> void:
	var world: Node = get_node_or_null("/root/Main/World")
	if world and _fog_overlay:
		world.add_child(_fog_overlay)

func _build_ghost_materials() -> void:
	_ghost_mat_valid = StandardMaterial3D.new()
	_ghost_mat_valid.wireframe = true
	_ghost_mat_valid.albedo_color = Color(0.0, 1.0, 0.4, 1.0)

	_ghost_mat_invalid = StandardMaterial3D.new()
	_ghost_mat_invalid.wireframe = true
	_ghost_mat_invalid.albedo_color = Color(1.0, 0.2, 0.2, 1.0)

	_range_mat_valid = StandardMaterial3D.new()
	_range_mat_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_mat_valid.no_depth_test = true
	_range_mat_valid.albedo_color = Color(0.0, 1.0, 0.4, 1.0)

	_range_mat_invalid = StandardMaterial3D.new()
	_range_mat_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_mat_invalid.no_depth_test = true
	_range_mat_invalid.albedo_color = Color(1.0, 0.2, 0.2, 1.0)

func _create_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		return
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(TOWER_MODEL_PATH, state)
	if err != OK:
		return
	var root: Node3D = gltf.generate_scene(state)
	if root == null:
		return
	_ghost = Node3D.new()
	_ghost.add_child(root)

	# Range circle
	_range_imesh = ImmediateMesh.new()
	_range_mesh_inst = MeshInstance3D.new()
	_range_mesh_inst.mesh = _range_imesh
	_range_mesh_inst.material_override = _range_mat_invalid
	_ghost.add_child(_range_mesh_inst)

	get_tree().root.get_child(0).add_child(_ghost)
	_apply_ghost_material(_ghost_mat_invalid)

func _destroy_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_range_mesh_inst = null
	_range_imesh = null

func _apply_ghost_material(mat: StandardMaterial3D) -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	_set_material_recursive(_ghost, mat)
	# Restore range circle mat separately — don't let recursive override it
	if _range_mesh_inst != null and is_instance_valid(_range_mesh_inst):
		_range_mesh_inst.material_override = _range_mat_valid if mat == _ghost_mat_valid else _range_mat_invalid

func _set_material_recursive(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_set_material_recursive(child, mat)

func _draw_range_circle(_center: Vector3) -> void:
	if _range_imesh == null or not is_instance_valid(_range_imesh):
		return
	_range_imesh.clear_surfaces()
	_range_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(RANGE_CIRCLE_SEGMENTS):
		var a0: float = (float(i)       / float(RANGE_CIRCLE_SEGMENTS)) * TAU
		var a1: float = (float(i + 1)   / float(RANGE_CIRCLE_SEGMENTS)) * TAU
		var p0 := Vector3(cos(a0) * TOWER_RANGE, 0.3, sin(a0) * TOWER_RANGE)
		var p1 := Vector3(cos(a1) * TOWER_RANGE, 0.3, sin(a1) * TOWER_RANGE)
		_range_imesh.surface_add_vertex(p0)
		_range_imesh.surface_add_vertex(p1)
	_range_imesh.surface_end()

# ── Process ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not current:
		_destroy_ghost()
		_restore_fog()
		return

	_create_ghost()

	# Zoom
	if Input.is_action_just_pressed("rts_zoom_in"):
		fov = max(MIN_FOV, fov - ZOOM_SPEED)
	elif Input.is_action_just_pressed("rts_zoom_out"):
		fov = min(MAX_FOV, fov + ZOOM_SPEED)

	# WASD pan
	var dir := Vector2.ZERO
	if Input.is_action_pressed("rts_pan_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("rts_pan_down"):
		dir.y += 1.0
	if Input.is_action_pressed("rts_pan_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("rts_pan_right"):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		global_position.x += dir.x * PAN_SPEED * delta
		global_position.z += dir.y * PAN_SPEED * delta

	# Ghost placement preview
	_update_ghost()
	# Fog of war
	_update_fog()

func _update_ghost() -> void:
	if _ghost == null or not is_instance_valid(_ghost) or build_system == null:
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = project_ray_origin(mouse_pos)
	var dir: Vector3 = project_ray_normal(mouse_pos)
	var to: Vector3 = from + dir * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)

	if result.is_empty():
		_ghost.visible = false
		return

	_ghost.visible = true
	var snapped := Vector3(
		snappedf(result.position.x, 2.0),
		result.position.y,
		snappedf(result.position.z, 2.0)
	)
	_ghost.global_position = snapped
	_ghost_world_pos = snapped

	# Slope check
	var normal: Vector3 = result.normal
	var on_flat_enough: bool = normal.dot(Vector3.UP) >= SLOPE_THRESHOLD

	var valid: bool = on_flat_enough and build_system.can_place(snapped, _player_team)
	if valid != _ghost_valid:
		_ghost_valid = valid
		_apply_ghost_material(_ghost_mat_valid if valid else _ghost_mat_invalid)

	_draw_range_circle(snapped)

# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_place_tower(event.position)

func _try_place_tower(_screen_pos: Vector2) -> void:
	if build_system == null or not _ghost_valid:
		return
	if multiplayer.has_multiplayer_peer():
		# Multiplayer: route through server for validation
		if multiplayer.is_server():
			if build_system.place_tower(_ghost_world_pos, _player_team):
				LobbyManager.spawn_tower_visuals.rpc(_ghost_world_pos, _player_team)
				LobbyManager.sync_team_points.rpc(TeamData.get_points(0), TeamData.get_points(1))
		else:
			LobbyManager.request_place_tower.rpc_id(1, _ghost_world_pos, _player_team)
	else:
		build_system.place_tower(_ghost_world_pos, _player_team)

# ── Fog of war ───────────────────────────────────────────────────────────────

func _restore_fog() -> void:
	if _fog_overlay and is_instance_valid(_fog_overlay):
		_fog_overlay.visible = false
	for node in get_tree().get_nodes_in_group("towers"):
		if is_instance_valid(node):
			node.visible = true
	for node in get_tree().get_nodes_in_group("minions"):
		if is_instance_valid(node):
			node.visible = true

func _update_fog() -> void:
	# Collect vision sources on the player's team
	var sources: Array[Vector3] = []

	var main: Node = get_node_or_null("/root/Main")
	var player_pos := Vector3(0.0, 0.0, 84.0 if _player_team == 0 else -84.0)
	if main and main.get("fps_player") != null and is_instance_valid(main.fps_player):
		player_pos = main.fps_player.global_position
		sources.append(player_pos)

	var minion_positions: Array = []
	for minion in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(minion):
			continue
		var t: int = minion.get("team") if minion.get("team") != null else -1
		if t == _player_team:
			sources.append(minion.global_position)
			minion_positions.append(minion.global_position)

	var tower_positions: Array = []
	for tower in get_tree().get_nodes_in_group("towers"):
		if not is_instance_valid(tower):
			continue
		var t: int = tower.get("team") if tower.get("team") != null else -1
		if t == _player_team:
			sources.append(tower.global_position)
			tower_positions.append(tower.global_position)

	# Update overlay mesh
	if _fog_overlay and is_instance_valid(_fog_overlay):
		_fog_overlay.visible = true
		_fog_overlay.call("update_sources", player_pos, PLAYER_VISION_RADIUS,
				minion_positions, MINION_VISION_RADIUS,
				tower_positions, TOWER_RANGE)

	# Apply visibility to enemy nodes
	_apply_fog_to_group("towers")
	_apply_fog_to_group("minions")

func _apply_fog_to_group(group: String) -> void:
	for node in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(node):
			continue
		var node_team: int = node.get("team") if node.get("team") != null else -1
		if node_team == _player_team:
			node.visible = true
			continue
		node.visible = _is_visible_to_sources(node.global_position)

func _is_visible_to_sources(world_pos: Vector3) -> bool:
	var main: Node = get_node_or_null("/root/Main")
	var player_pos: Vector3 = Vector3.INF
	if main and main.get("fps_player") != null and is_instance_valid(main.fps_player):
		player_pos = main.fps_player.global_position

	# Player vision
	if world_pos.distance_to(player_pos) <= PLAYER_VISION_RADIUS:
		return true

	# Friendly minion vision
	for minion in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(minion):
			continue
		if minion.get("team") != _player_team:
			continue
		if world_pos.distance_to(minion.global_position) <= MINION_VISION_RADIUS:
			return true

	# Friendly tower vision
	for tower in get_tree().get_nodes_in_group("towers"):
		if not is_instance_valid(tower):
			continue
		if tower.get("team") != _player_team:
			continue
		if world_pos.distance_to(tower.global_position) <= TOWER_RANGE:
			return true

	return false
