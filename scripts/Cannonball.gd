extends Node3D

const GRAVITY      := 18.0
const FLIGHT_TIME  := 2.5
const SPLASH_RADIUS := 3.0
const SPLASH_DAMAGE_MULT := 0.5
const MAX_LIFETIME := FLIGHT_TIME + 1.0

var target_pos: Vector3  = Vector3.ZERO
var damage: float        = 50.0
var source: String       = "cannonball"
var shooter_team: int    = -1

var _velocity: Vector3 = Vector3.ZERO
var _age: float        = 0.0
var _light: OmniLight3D = null
var _flicker_timer: float = 0.0
const FLICKER_INTERVAL := 0.05  # update light ~20fps

func _ready() -> void:
	_light = get_node_or_null("OmniLight3D")
	# Tint tracer particle light by team (reuse shared helper material logic)
	# Note: Cannonball uses OmniLight not a mesh tracer, no material needed here.

	# Compute ballistic velocity so we arrive at target_pos in FLIGHT_TIME seconds.
	# x/z components are constant; y must overcome gravity over the arc.
	var start: Vector3 = global_position
	var dt: float = FLIGHT_TIME
	_velocity.x = (target_pos.x - start.x) / dt
	_velocity.z = (target_pos.z - start.z) / dt
	_velocity.y = (target_pos.y - start.y + 0.5 * GRAVITY * dt * dt) / dt

func _process(delta: float) -> void:
	_age += delta
	if _age >= MAX_LIFETIME:
		queue_free()
		return

	var prev_pos: Vector3 = global_position
	_velocity.y -= GRAVITY * delta
	var new_pos: Vector3 = prev_pos + _velocity * delta

	# Raycast for collision
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(prev_pos, new_pos)
	var result: Dictionary = space.intersect_ray(query)

	if not result.is_empty():
		_impact(result.position, result.collider)
		return

	global_position = new_pos

	# Flicker the light at reduced rate
	if _light:
		_flicker_timer += delta
		if _flicker_timer >= FLICKER_INTERVAL:
			_flicker_timer = 0.0
			_light.light_energy = randf_range(1.6, 2.4)

func _impact(pos: Vector3, direct_hit: Object) -> void:
	# Direct hit damage
	if CombatUtils.should_damage(direct_hit, shooter_team):
		direct_hit.take_damage(damage, "cannonball", shooter_team)

	# Splash damage — nearby bodies in a sphere
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = SPLASH_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, pos)
	params.collision_mask = 0xFFFFFFFF
	var overlaps: Array = space.intersect_shape(params, 16)
	for overlap in overlaps:
		var body: Object = overlap.get("collider")
		if body == null or body == direct_hit:
			continue
		if CombatUtils.should_damage(body, shooter_team):
			body.take_damage(damage * SPLASH_DAMAGE_MULT, "cannonball_splash", shooter_team)

	_spawn_impact(pos)
	queue_free()

func _should_damage(hit: Object) -> bool:
	if hit == null or not hit.has_method("take_damage"):
		return false
	var hit_team: int = hit.get("team") if hit.get("team") != null else -999
	if shooter_team != -1 and hit_team == shooter_team:
		return false
	if shooter_team == -1 and hit_team == -1:
		return false
	return true

func _spawn_impact(pos: Vector3) -> void:
	var particles := GPUParticles3D.new()
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3.UP
	pmat.spread = 60.0
	pmat.initial_velocity_min = 4.0
	pmat.initial_velocity_max = 10.0
	pmat.gravity = Vector3(0, -12, 0)
	pmat.scale_min = 0.2
	pmat.scale_max = 0.5

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.25, 0.25)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.albedo_color = Color(1.0, 0.45, 0.05, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat

	particles.process_material = pmat
	particles.draw_pass_1 = mesh
	particles.amount = 40
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 0.95

	get_tree().root.add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	particles.restart()
	particles.call_deferred("free")
