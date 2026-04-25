extends StaticBody3D
## Machine Gun Tower — rapid raycast fire, low damage, short range.

const TOWER_MODEL_PATH := "res://assets/kenney_pirate-kit/Models/GLB format/tower-complete-small.glb"

var team := 0
var health := 600.0
const MAX_HEALTH := 600.0
var attack_range := 22.0
var attack_damage := 12.0
var attack_cooldown := 0.15
var _attack_timer := 0.0
var _dead := false

@onready var area: Area3D = $Area3D

func setup(p_team: int) -> void:
	team = p_team
	add_to_group("towers")
	_load_model()
	var shape := SphereShape3D.new()
	shape.radius = attack_range
	$Area3D/CollisionShape3D.shape = shape

func _load_model() -> void:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	if gltf.append_from_file(TOWER_MODEL_PATH, state) != OK:
		return
	var root: Node3D = gltf.generate_scene(state)
	if root == null:
		return
	add_child(root)

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
		var body_team := -1
		var pt = body.get("player_team")
		if pt != null:
			body_team = pt as int
		else:
			var t = body.get("team")
			if t != null:
				body_team = t as int
		if body_team == team:
			continue
		var d: float = global_position.distance_to(body.global_position)
		if d < best_dist:
			best_dist = d
			best = body
	return best

func _shoot(target: Node3D) -> void:
	# Raycast bullet: direct instant hit with no travel time
	var from: Vector3 = global_position + Vector3(0.0, 2.0, 0.0)
	var to: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty():
		var hit: Object = result.collider
		var hit_pos: Vector3 = result.position
		var hit_normal: Vector3 = result.normal
		var hit_unit := false
		if hit != null and hit.has_method("take_damage"):
			var hit_team: int = -1
			var pt = hit.get("player_team")
			if pt != null:
				hit_team = pt as int
			else:
				var t = hit.get("team")
				if t != null:
					hit_team = t as int
			if hit_team != team:
				hit.take_damage(attack_damage, "machinegun_tower", team)
				hit_unit = true
		_spawn_hit_impact(hit_pos, hit_normal, hit_unit)
	# Muzzle flash particle
	_spawn_muzzle_flash(from)

func _spawn_hit_impact(pos: Vector3, normal: Vector3, is_unit: bool) -> void:
	var root: Node = get_tree().root

	if is_unit:
		# ── Unit hit: blood/impact puff + bright spark ────────────────────────
		var p1 := GPUParticles3D.new()
		var pm1 := ParticleProcessMaterial.new()
		pm1.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm1.emission_sphere_radius = 0.05
		pm1.direction = normal
		pm1.spread = 60.0
		pm1.initial_velocity_min = 2.0
		pm1.initial_velocity_max = 6.0
		pm1.gravity = Vector3(0.0, -10.0, 0.0)
		pm1.scale_min = 0.1
		pm1.scale_max = 0.22
		var m1 := QuadMesh.new()
		m1.size = Vector2(0.18, 0.18)
		var mat1 := StandardMaterial3D.new()
		mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat1.albedo_color = Color(0.9, 0.15, 0.05, 0.9)
		mat1.emission_enabled = true
		mat1.emission = Color(1.0, 0.1, 0.0)
		mat1.emission_energy_multiplier = 3.0
		mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m1.material = mat1
		p1.process_material = pm1
		p1.draw_pass_1 = m1
		p1.amount = 10
		p1.lifetime = 0.3
		p1.one_shot = true
		p1.explosiveness = 0.9
		root.add_child(p1)
		p1.global_position = pos
		p1.emitting = true
		p1.restart()
		p1.call_deferred("free")

		var p2 := GPUParticles3D.new()
		var pm2 := ParticleProcessMaterial.new()
		pm2.direction = normal
		pm2.spread = 30.0
		pm2.initial_velocity_min = 4.0
		pm2.initial_velocity_max = 10.0
		pm2.gravity = Vector3(0.0, -15.0, 0.0)
		pm2.scale_min = 0.03
		pm2.scale_max = 0.08
		var m2 := QuadMesh.new()
		m2.size = Vector2(0.08, 0.08)
		var mat2 := StandardMaterial3D.new()
		mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat2.albedo_color = Color(1.0, 0.95, 0.7, 1.0)
		mat2.emission_enabled = true
		mat2.emission = Color(1.0, 0.9, 0.4)
		mat2.emission_energy_multiplier = 8.0
		m2.material = mat2
		p2.process_material = pm2
		p2.draw_pass_1 = m2
		p2.amount = 6
		p2.lifetime = 0.15
		p2.one_shot = true
		p2.explosiveness = 1.0
		root.add_child(p2)
		p2.global_position = pos
		p2.emitting = true
		p2.restart()
		p2.call_deferred("free")
	else:
		# ── Terrain/static hit: dust puff + spark ────────────────────────────
		var p1 := GPUParticles3D.new()
		var pm1 := ParticleProcessMaterial.new()
		pm1.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm1.emission_sphere_radius = 0.05
		pm1.direction = normal
		pm1.spread = 55.0
		pm1.initial_velocity_min = 1.5
		pm1.initial_velocity_max = 4.5
		pm1.gravity = Vector3(0.0, -8.0, 0.0)
		pm1.scale_min = 0.08
		pm1.scale_max = 0.22
		var m1 := QuadMesh.new()
		m1.size = Vector2(0.2, 0.2)
		var mat1 := StandardMaterial3D.new()
		mat1.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat1.albedo_color = Color(0.62, 0.5, 0.35, 0.85)
		mat1.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat1.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m1.material = mat1
		p1.process_material = pm1
		p1.draw_pass_1 = m1
		p1.amount = 12
		p1.lifetime = 0.4
		p1.one_shot = true
		p1.explosiveness = 0.85
		root.add_child(p1)
		p1.global_position = pos
		p1.emitting = true
		p1.restart()
		p1.call_deferred("free")

		var p2 := GPUParticles3D.new()
		var pm2 := ParticleProcessMaterial.new()
		pm2.direction = normal
		pm2.spread = 40.0
		pm2.initial_velocity_min = 3.0
		pm2.initial_velocity_max = 8.0
		pm2.gravity = Vector3(0.0, -15.0, 0.0)
		pm2.scale_min = 0.03
		pm2.scale_max = 0.07
		var m2 := QuadMesh.new()
		m2.size = Vector2(0.08, 0.08)
		var mat2 := StandardMaterial3D.new()
		mat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat2.albedo_color = Color(1.0, 0.95, 0.6, 1.0)
		mat2.emission_enabled = true
		mat2.emission = Color(1.0, 0.85, 0.2)
		mat2.emission_energy_multiplier = 7.0
		m2.material = mat2
		p2.process_material = pm2
		p2.draw_pass_1 = m2
		p2.amount = 8
		p2.lifetime = 0.2
		p2.one_shot = true
		p2.explosiveness = 1.0
		root.add_child(p2)
		p2.global_position = pos
		p2.emitting = true
		p2.restart()
		p2.call_deferred("free")

func _spawn_muzzle_flash(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.05
	pm.scale_max = 0.15
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.3, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.0)
	mat.emission_energy_multiplier = 4.0
	mesh.material = mat
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.amount = 8
	p.lifetime = 0.12
	p.one_shot = true
	p.explosiveness = 1.0
	get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.restart()
	p.call_deferred("free")

func take_damage(amount: float, _source: String, _killer_team: int = -1) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0:
		_die()

func _die() -> void:
	_dead = true
	queue_free()
