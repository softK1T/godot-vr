extends AnimatableBody3D

@export var open_angle_degrees: float = 105.0
@export var open_speed: float = 4.0

var _closed_rotation_y: float
var _target_rotation_y: float
var _is_open := false

func setup_from_imported_door(imported_door: Node3D) -> void:
	_closed_rotation_y = rotation.y
	_target_rotation_y = _closed_rotation_y
	imported_door.reparent(self, false)
	imported_door.transform = Transform3D.IDENTITY

func _physics_process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _target_rotation_y, minf(1.0, open_speed * delta))
	if absf(angle_difference(rotation.y, _target_rotation_y)) < 0.002:
		rotation.y = _target_rotation_y

func interact(_interactor: Node = null) -> void:
	_is_open = not _is_open
	_target_rotation_y = _closed_rotation_y + deg_to_rad(open_angle_degrees if _is_open else 0.0)

func get_interaction_text() -> String:
	return "E - Close door" if _is_open else "E - Open door"

func is_open() -> bool:
	return _is_open
