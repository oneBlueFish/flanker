extends StaticBody3D
## LauncherTower — manual-fire only, no auto-attack.
## Supports all launcher types defined in LauncherDefs.
## Server-authoritative health / death (mirrors TowerAI pattern).

var team: int = 0
var launcher_type: String = "launcher_missile"
var tower_type: String = "launcher_missile"  # read by despawn_tower for tower_despawned signal

var _health: float = 600.0
var _max_health: float = 600.0
var _dead: bool = false

# Visual nodes created at runtime in setup()
var _mesh_inst: MeshInstance3D = null
var _light: OmniLight3D = null

func setup(p_team: int, p_launcher_type: String = "launcher_missile") -> void:
	team = p_team
	launcher_type = p_launcher_type
	tower_type = p_launcher_type  # used by despawn_tower signal reader

	_health = float(LauncherDefs.get_health(launcher_type))
	_max_health = _health

	add_to_group("towers")
	add_to_group("launchers")

	_build_visuals()

func _build_visuals() -> void:
	# ── Collision body ────────────────────────────────────────────────────────
	var col_shape := CylinderShape3D.new()
	col_shape.radius = 1.2
	col_shape.height = 6.0
	var col := CollisionShape3D.new()
	col.shape = col_shape
	col.position = Vector3(0.0, 3.0, 0.0)
	add_child(col)

	# ── Launch tube mesh (programmatic cylinder) ───────────────────────────────
	var cyl := CylinderMesh.new()
	cyl.top_radius    = 0.55
	cyl.bottom_radius = 0.8
	cyl.height        = 5.5
	cyl.radial_segments = 12

	var mat := StandardMaterial3D.new()
	var team_color: Color = Color(0.18, 0.45, 1.0) if team == 0 else Color(0.9, 0.15, 0.15)
	mat.albedo_color = team_color
	mat.roughness    = 0.6
	mat.metallic     = 0.6
	cyl.material = mat

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = cyl
	_mesh_inst.position = Vector3(0.0, 2.75, 0.0)
	add_child(_mesh_inst)

	# ── Base platform (box) ───────────────────────────────────────────────────
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(2.4, 0.5, 2.4)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.22, 0.22, 0.22)
	base_mat.roughness = 0.8
	base_mesh.material = base_mat
	var base_inst := MeshInstance3D.new()
	base_inst.mesh = base_mesh
	base_inst.position = Vector3(0.0, 0.25, 0.0)
	add_child(base_inst)

	# ── Ambient glow (dim until fired) ───────────────────────────────────────
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.1)
	_light.light_energy = 0.4
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 5.8, 0.0)
	add_child(_light)

	# ── Emissive hit-overlay material on mesh (matches TowerAI pattern) ───────
	var hit_mat := StandardMaterial3D.new()
	hit_mat.albedo_color = Color(1.0, 0.1, 0.1, 0.0)
	hit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hit_mat.emission_enabled = true
	hit_mat.emission = Color(1.0, 0.05, 0.0)
	hit_mat.emission_energy_multiplier = 0.0
	_mesh_inst.set_surface_override_material(0, hit_mat)

# Returns the world-space position from which the missile is launched
# (top of the tube + small offset so the missile clears the barrel).
func get_fire_position() -> Vector3:
	return global_position + Vector3(0.0, 6.2, 0.0)

# ── Damage / death ────────────────────────────────────────────────────────────

func take_damage(amount: float, _source: String, source_team: int, _shooter_peer: int = -1) -> void:
	if _dead:
		return
	if source_team == team:
		return
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		return

	_health -= amount
	_flash_hit()

	if _health <= 0.0:
		_die()

func _flash_hit() -> void:
	if _mesh_inst == null or not is_instance_valid(_mesh_inst):
		return
	var mat := _mesh_inst.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	mat.emission_energy_multiplier = 3.0
	var tween := create_tween()
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.25)

func _die() -> void:
	if _dead:
		return
	_dead = true

	if multiplayer.has_multiplayer_peer():
		LobbyManager.despawn_tower.rpc(name)
	else:
		# Singleplayer — read type/team before freeing, emit signal manually
		var t: int = team
		var lt: String = launcher_type
		queue_free()
		LobbyManager.tower_despawned.emit(lt, t)
