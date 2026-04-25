extends Node3D

const FENCE_PATH := "res://assets/kenney_fantasy-town-kit/Models/GLB format/fence.glb"

const LANE_WIDTH := 6.0
const FENCE_OFFSET := 3.3        # half-lane + small gap from dirt ribbon edge
const FENCE_SPACING := 4.0       # world units between fence piece centers (2x scale)
const FENCE_SCALE := 3.0

# Collision box: x=rail thickness, y=height, z=length along lane direction
const FENCE_COL_SIZE := Vector3(0.15, 1.2, 2.0)
const INTERSECTION_CLEAR := LANE_WIDTH / 2.0 + 1.0  # skip fence near other lanes
const FENCE_GAP_CHANCE := 0.2  # probability a fence piece is skipped

const TORCH_CHANCE := 0.15
const TORCH_HEIGHT := 1.5       # local Y offset on fence body (tune as needed)
const TORCH_LIGHT_RANGE := 4.0
const TORCH_LIGHT_ENERGY := 1.5
const TORCH_LIGHT_COLOR := Color(1.0, 0.38, 0.04)
const TORCH_MIN_DIST := FENCE_SPACING * 3.0  # min distance between torches

@onready var _terrain_body: StaticBody3D = null
var _last_torch_pos := Vector3(INF, INF, INF)

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	seed(GameSync.game_seed)
	_terrain_body = _find_terrain()

	var fence_scene: PackedScene = load(FENCE_PATH)
	if fence_scene == null:
		push_error("FencePlacer: failed to load " + FENCE_PATH)
		return

	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		_place_lane_fences(pts, lane_i, fence_scene)

func _place_lane_fences(pts: Array, lane_i: int, fence_scene: PackedScene) -> void:
	# Accumulate distance along the polyline and place pieces at regular intervals
	# for each side (+offset and -offset from lane center)
	for side in [-1, 1]:
		var carry: float = 0.0  # leftover distance from previous segment

		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg: Vector2 = b - a
			var seg_len: float = seg.length()
			if seg_len < 0.001:
				continue

			var seg_dir: Vector2 = seg / seg_len
			# Perpendicular (rotate 90° CCW)
			var perp: Vector2 = Vector2(-seg_dir.y, seg_dir.x)

			# Offset center of the lane edge
			var edge_a: Vector2 = a + perp * (FENCE_OFFSET * float(side))

			# Place fence pieces spaced FENCE_SPACING apart, starting after carry
			var t: float = FENCE_SPACING - carry
			while t <= seg_len:
				var world_xz: Vector2 = edge_a + seg_dir * t
				# Check intersection using the lane centerline point (not the offset position)
				var center_xz: Vector2 = a + seg_dir * t
				if not _is_near_other_lane(center_xz, lane_i) and randf() >= FENCE_GAP_CHANCE:
					var world_pos := Vector3(world_xz.x, 0.0, world_xz.y)
					world_pos.y = _get_terrain_height(world_pos)
					_spawn_fence(world_pos, seg_dir, fence_scene)
				t += FENCE_SPACING

			# Update carry for next segment
			carry = fmod(carry + seg_len, FENCE_SPACING)

func _spawn_fence(pos: Vector3, seg_dir: Vector2, fence_scene: PackedScene) -> void:
	var fence: Node = fence_scene.instantiate()
	fence.position = Vector3(-1.25, 0.0, 0.0)

	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.position = pos

	# Rotate to align with lane direction
	var dir3 := Vector3(seg_dir.x, 0.0, seg_dir.y).normalized()
	var angle: float = Vector3.FORWARD.signed_angle_to(dir3, Vector3.UP)
	body.rotation.y = angle

	# Collision shape
	var col_shape := BoxShape3D.new()
	col_shape.size = FENCE_COL_SIZE
	var col_node := CollisionShape3D.new()
	col_node.shape = col_shape
	col_node.position = Vector3(0.0, FENCE_COL_SIZE.y * 0.5, 0.0)
	body.add_child(col_node)

	fence.scale = Vector3(FENCE_SCALE, FENCE_SCALE, FENCE_SCALE)
	body.add_child(fence)
	if randf() < TORCH_CHANCE and pos.distance_to(_last_torch_pos) >= TORCH_MIN_DIST:
		_add_torch(body)
		_last_torch_pos = pos
	add_child(body)

func _add_torch(body: StaticBody3D) -> void:
	var torch_root := Node3D.new()
	torch_root.position = Vector3(0.15, TORCH_HEIGHT, 1.4)
	body.add_child(torch_root)

	# Stick — thin cylinder
	var stick_mesh := CylinderMesh.new()
	stick_mesh.top_radius = 0.04
	stick_mesh.bottom_radius = 0.06
	stick_mesh.height = 0.6
	var stick_mat := StandardMaterial3D.new()
	stick_mat.albedo_color = Color(0.35, 0.2, 0.08)
	stick_mesh.surface_set_material(0, stick_mat)
	var stick_mi := MeshInstance3D.new()
	stick_mi.mesh = stick_mesh
	stick_mi.position = Vector3(0.0, 0.0, 0.0)
	torch_root.add_child(stick_mi)

	# Flame light
	var light := OmniLight3D.new()
	light.light_color = TORCH_LIGHT_COLOR
	light.light_energy = TORCH_LIGHT_ENERGY
	light.omni_range = TORCH_LIGHT_RANGE
	light.position = Vector3(0.0, 0.4, 0.0)
	torch_root.add_child(light)

	# Fire particles
	var particles := GPUParticles3D.new()
	particles.amount = 16
	particles.lifetime = 0.5
	particles.explosiveness = 0.0
	particles.position = Vector3(0.0, 0.4, 0.0)

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.0, 1.0, 0.0)
	pmat.spread = 18.0
	pmat.initial_velocity_min = 0.8
	pmat.initial_velocity_max = 1.6
	pmat.gravity = Vector3(0.0, -0.3, 0.0)
	pmat.scale_min = 0.3
	pmat.scale_max = 0.5

	# Color ramp: orange → yellow → transparent smoke
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.55, 0.05, 1.0))
	grad.add_point(0.5, Color(1.0, 0.9, 0.1, 0.6))
	grad.add_point(1.0, Color(0.15, 0.15, 0.15, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pmat.color_ramp = grad_tex

	particles.process_material = pmat

	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.06
	flame_mesh.height = 0.12
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.5, 0.05)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.4, 0.0)
	flame_mat.emission_energy_multiplier = 2.0
	flame_mesh.surface_set_material(0, flame_mat)
	particles.draw_pass_1 = flame_mesh

	torch_root.add_child(particles)

func _is_near_other_lane(pos: Vector2, skip_lane: int) -> bool:
	for lane_i in range(3):
		if lane_i == skip_lane:
			continue
		var pts: Array = LaneData.get_lane_points(lane_i)
		if LaneData.dist_to_polyline(pos, pts) < INTERSECTION_CLEAR:
			return true
	return false

func _get_terrain_height(pos: Vector3) -> float:
	if _terrain_body == null:
		return 0.0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return 0.0
	var from := Vector3(pos.x, 50.0, pos.z)
	var to   := Vector3(pos.x, -10.0, pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		return 0.0
	return result.position.y

func _find_terrain() -> StaticBody3D:
	if has_node("/root/Main/World/Terrain"):
		return $/root/Main/World/Terrain
	return null
