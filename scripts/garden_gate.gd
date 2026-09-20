extends AnimatableBody3D

@export var open_angle_degrees: float = 88.0
@export var open_speed: float = 4.0

var _closed_rotation_y: float
var _target_rotation_y: float
var _is_open := false

func _ready() -> void:
	_closed_rotation_y = rotation.y
	_target_rotation_y = _closed_rotation_y

func _physics_process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _target_rotation_y, minf(1.0, open_speed * delta))
	if absf(angle_difference(rotation.y, _target_rotation_y)) < 0.002:
		rotation.y = _target_rotation_y

func interact(interactor: Node = null) -> void:
	_is_open = not _is_open
	if _is_open:
		var opening_sign := 1.0
		if interactor is Node3D:
			opening_sign = 1.0 if to_local(interactor.global_position).z >= 0.0 else -1.0
		_target_rotation_y = _closed_rotation_y + deg_to_rad(open_angle_degrees * opening_sign)
	else:
		_target_rotation_y = _closed_rotation_y

func get_interaction_text() -> String:
	return "E - Close gate" if _is_open else "E - Open gate"
