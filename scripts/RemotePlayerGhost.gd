extends Node3D

var peer_id: int = 0
var target_position: Vector3 = Vector3.ZERO
var target_rotation: Vector3 = Vector3.ZERO
const LERP_SPEED := 15.0

func _process(delta: float) -> void:
	global_position = global_position.lerp(target_position, LERP_SPEED * delta)
	rotation.y = lerp_angle(rotation.y, target_rotation.y, LERP_SPEED * delta)

func update_transform(pos: Vector3, rot: Vector3) -> void:
	target_position = pos
	target_rotation = rot
