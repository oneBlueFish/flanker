extends StaticBody3D
## Barrier — passive fortification wall panel, no attack. Cheap, high HP, blocks movement.

const WALL_MODEL_PATH := "res://assets/kenney_fantasy-town-kit/Models/GLB format/wall.glb"

var team := 0
var health := 1200.0
const MAX_HEALTH := 1200.0
var _dead := false

func setup(p_team: int) -> void:
	team = p_team
	add_to_group("towers")
	_load_model()
	_setup_collision()

func _load_model() -> void:
	var packed: PackedScene = load(WALL_MODEL_PATH)
	if packed == null:
		return
	var root: Node3D = packed.instantiate()
	# Scale up: wall.glb is ~1 unit wide × 2 tall × 0.3 deep in Kenney scale
	# Scale to roughly 2 wide × 3 tall × 0.5 deep — solid cover panel
	root.scale = Vector3(2.0, 3.0, 2.0)
	add_child(root)

func _setup_collision() -> void:
	# Match the scaled wall dimensions: 2 wide, 3 tall, 0.5 deep
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 0.5)
	col.shape = box
	col.position = Vector3(0.0, 1.5, 0.0)
	add_child(col)

func take_damage(amount: float, _source: String, _killer_team: int = -1) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0:
		_die()

func _die() -> void:
	_dead = true
	queue_free()
