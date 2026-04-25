extends StaticBody3D

const BulletScene := preload("res://scenes/Cannonball.tscn")

var team := 0  # which team OWNS this tower (attacks enemies)
var health := 900.0
const MAX_HEALTH := 900.0
var attack_range := 30.0
var attack_damage := 50.0
var attack_cooldown := 1.0
var _attack_timer := 0.0
var _dead := false
var _team_mat: StandardMaterial3D = null

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var area: Area3D = $Area3D

const TOWER_MODEL_PATH := "res://assets/kenney_pirate-kit/Models/GLB format/tower-complete-small.glb"

func setup(p_team: int) -> void:
	team = p_team
	add_to_group("towers")
	# Load and instance the model in code
	_load_team_model()
	# Resize collision sphere
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = attack_range
	$Area3D/CollisionShape3D.shape = shape

func _load_team_model() -> void:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(TOWER_MODEL_PATH, state)
	if err != OK:
		push_error("TowerAI: GLTF failed error=" + str(err))
		return
	var root: Node3D = gltf.generate_scene(state)
	if not root:
		push_error("TowerAI: generate_scene failed")
		return
	add_child(root)
	_add_hit_overlay()

func _add_hit_overlay() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var overlay_mat := StandardMaterial3D.new()
			overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			overlay_mat.albedo_color = Color(1, 0.2, 0.2, 0.0)
			overlay_mat.emission_enabled = true
			overlay_mat.emission = Color(1, 0.2, 0.2, 1)
			overlay_mat.emission_energy_multiplier = 3.0
			child.set("material_override", overlay_mat)

func _process(delta: float) -> void:
	if _dead:
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		var target := _find_target()
		if target:
			_shoot(target)
			_attack_timer = attack_cooldown

func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist := attack_range + 1.0
	for body in area.get_overlapping_bodies():
		if not body.has_method("take_damage"):
			continue
		# Get team: minions use .team, player uses .player_team
		var body_team := -1
		if body.has_method("get"):
			var pt = body.get("player_team")
			if pt != null:
				body_team = pt as int
			else:
				var t = body.get("team")
				if t != null:
					body_team = t as int
		if body_team == team:
			continue
		var d := global_position.distance_to(body.global_position)
		if d < best_dist and _has_line_of_sight(body):
			best_dist = d
			best = body
	return best

func _has_line_of_sight(target: Node3D) -> bool:
	var from: Vector3 = global_position + Vector3(0.0, 2.0, 0.0)
	var to: Vector3 = target.global_position + Vector3(0.0, 0.8, 0.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var excluded: Array[RID] = [get_rid(), target.get_rid()]
	for _attempt in range(4):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = excluded
		query.collision_mask = 0b11
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			return true
		var body: Object = result.collider
		if body != null and body.has_meta("tree_trunk_height"):
			# Short trees (below barrel) and any tree — ignore, they're foliage, not walls
			excluded.append(body.get_rid())
			continue
		return false
	return true

func _shoot(target: Node3D) -> void:
	var spawn_pos: Vector3 = global_position + Vector3(0.0, 2.0, 0.0)
	var aim_pos: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)

	var ball: Node3D = BulletScene.instantiate()
	ball.damage = attack_damage
	ball.source = "cannonball"
	ball.shooter_team = team
	ball.target_pos = aim_pos
	# Position must be set before add_child so _ready() computes arc from correct origin
	ball.position = spawn_pos
	get_tree().root.get_child(0).add_child(ball)

func take_damage(amount: float, _source: String, _killer_team: int = -1) -> void:
	if not multiplayer.is_server():
		return
	if _dead:
		return
	health -= amount
	_hit_flash()
	if health <= 0:
		_die()

var _hit_flash_tween: Tween

func _hit_flash() -> void:
	if mesh == null:
		return
	
	if _hit_flash_tween and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	
	var mat: StandardMaterial3D = mesh.get("material_override")
	if mat != null and mat is StandardMaterial3D:
		mat.albedo_color = Color(1, 0.2, 0.2, 0.8)
		
		_hit_flash_tween = create_tween()
		_hit_flash_tween.tween_property(mat, "albedo_color", Color(1, 0.2, 0.2, 0.0), 0.3)

func _die() -> void:
	_dead = true
	if multiplayer.has_multiplayer_peer():
		LobbyManager.despawn_tower.rpc(name)
	else:
		var node_type: String = LobbyManager._type_from_node_name(name)
		LobbyManager.tower_despawned.emit(node_type, team)
		queue_free()