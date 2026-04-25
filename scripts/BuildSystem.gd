extends Node

const TOWER_SCENE := "res://scenes/Tower.tscn"
const TOWER_COST := 25
const LANE_SETBACK := 8.0
const SLOPE_THRESHOLD := 0.85
const MIN_TOWER_SPACING := 20.0

var _tower_scene: PackedScene = null

func _ready() -> void:
	_tower_scene = load(TOWER_SCENE)

func can_place(world_pos: Vector3, team: int) -> bool:
	# Must be on own team's half
	if team == 0 and world_pos.z < 0.0:
		return false
	if team == 1 and world_pos.z > 0.0:
		return false

	# Must not be within lane setback of any lane
	var p := Vector2(world_pos.x, world_pos.z)
	for lane_i in range(3):
		var pts: Array = LaneData.get_lane_points(lane_i)
		if LaneData.dist_to_polyline(p, pts) < LANE_SETBACK:
			return false

	# Slope check — raycast down to get surface normal
	var space: PhysicsDirectSpaceState3D = get_tree().root.get_world_3d().direct_space_state
	if space != null:
		var from := Vector3(world_pos.x, world_pos.y + 10.0, world_pos.z)
		var to   := Vector3(world_pos.x, world_pos.y - 10.0, world_pos.z)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		var result: Dictionary = space.intersect_ray(query)
		if not result.is_empty():
			var normal: Vector3 = result.normal
			if normal.dot(Vector3.UP) < SLOPE_THRESHOLD:
				return false

	# Minimum spacing between towers
	for tower in get_tree().get_nodes_in_group("towers"):
		if world_pos.distance_to(tower.global_position) < MIN_TOWER_SPACING:
			return false

	return true

func place_tower(world_pos: Vector3, team: int) -> bool:
	# Server-side only: validate, deduct points, spawn locally on server
	world_pos.x = snappedf(world_pos.x, 2.0)
	world_pos.z = snappedf(world_pos.z, 2.0)

	if not can_place(world_pos, team):
		print("Cannot place tower at %s — invalid zone" % world_pos)
		return false

	if not TeamData.spend_points(team, TOWER_COST):
		print("Not enough points to place tower. Need %d, have %d" % [TOWER_COST, TeamData.get_points(team)])
		return false

	spawn_tower_local(world_pos, team)
	print("Tower placed at %s for team %d, spent %d points" % [world_pos, team, TOWER_COST])
	return true

func spawn_tower_local(world_pos: Vector3, team: int) -> void:
	# Called on all peers: server via place_tower, clients via RPC
	if _tower_scene == null:
		_tower_scene = load(TOWER_SCENE)
	var tower = _tower_scene.instantiate()
	tower.global_position = world_pos
	var main: Node = get_tree().root.get_node("Main")
	main.add_child(tower)
	tower.setup(team)

	var tree_placer: Node = main.get_node_or_null("World/TreePlacer")
	if tree_placer and tree_placer.has_method("clear_trees_at"):
		tree_placer.clear_trees_at(world_pos, 7.0)

func get_tower_cost() -> int:
	return TOWER_COST
