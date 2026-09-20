@tool
extends Node3D

@export var stone_count: int = 26
@export var path_width: float = 1.55
@export var rebuild: bool = false:
	set(value):
		rebuild = false
		if value:
			build()

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if get_child_count() == 0:
		build()

func build() -> void:
	for child in get_children():
		child.free()

	_rng.seed = 20260920
	var route := PackedVector3Array([
		Vector3(-1.15, 0.0, 1.6),
		Vector3(-2.4, 0.0, 1.25),
		Vector3(-4.1, 0.0, 0.75),
		Vector3(-5.35, 0.0, 0.0),
		Vector3(-6.35, 0.0, -0.75),
	])

	var dirt_material := StandardMaterial3D.new()
	dirt_material.albedo_color = Color(0.115, 0.085, 0.055, 1.0)
	dirt_material.roughness = 1.0

	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color(0.24, 0.255, 0.225, 1.0)
	stone_material.roughness = 0.96

	for index in range(route.size() - 1):
		_add_dirt_segment(route[index], route[index + 1], dirt_material, index)

	var total_length := _route_length(route)
	for index in range(stone_count):
		var distance := total_length * float(index) / float(maxi(1, stone_count - 1))
		var sample := _sample_route(route, distance)
		var side := -1.0 if index % 2 == 0 else 1.0
		var lateral_offset := side * _rng.randf_range(0.18, 0.42)
		var position := sample[0] + sample[1] * lateral_offset
		position.x += _rng.randf_range(-0.08, 0.08)
		position.z += _rng.randf_range(-0.08, 0.08)
		_add_stone(position, stone_material, index)

func _add_dirt_segment(start: Vector3, finish: Vector3, material: Material, index: int) -> void:
	var delta := finish - start
	var mesh := BoxMesh.new()
	mesh.size = Vector3(path_width, 0.025, delta.length() + 0.25)

	var instance := MeshInstance3D.new()
	instance.name = "DirtSegment%02d" % index
	instance.position = (start + finish) * 0.5 + Vector3(0.0, 0.012, 0.0)
	instance.rotation.y = atan2(delta.x, delta.z)
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 48.0
	add_child(instance)

func _add_stone(position: Vector3, material: Material, index: int) -> void:
	var radius := _rng.randf_range(0.23, 0.36)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * _rng.randf_range(0.78, 0.92)
	mesh.bottom_radius = radius
	mesh.height = _rng.randf_range(0.055, 0.095)
	mesh.radial_segments = _rng.randi_range(7, 9)
	mesh.rings = 1

	var instance := MeshInstance3D.new()
	instance.name = "PathStone%02d" % index
	instance.position = position + Vector3(0.0, mesh.height * 0.48, 0.0)
	instance.rotation.y = _rng.randf_range(-PI, PI)
	instance.scale = Vector3(_rng.randf_range(0.9, 1.15), 1.0, _rng.randf_range(0.72, 1.18))
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.visibility_range_end = 48.0
	add_child(instance)

func _route_length(route: PackedVector3Array) -> float:
	var result := 0.0
	for index in range(route.size() - 1):
		result += route[index].distance_to(route[index + 1])
	return result

func _sample_route(route: PackedVector3Array, distance: float) -> Array[Vector3]:
	var remaining := distance
	for index in range(route.size() - 1):
		var start := route[index]
		var finish := route[index + 1]
		var segment_length := start.distance_to(finish)
		if remaining <= segment_length or index == route.size() - 2:
			var ratio := clampf(remaining / maxf(segment_length, 0.001), 0.0, 1.0)
			var tangent := (finish - start).normalized()
			var perpendicular := Vector3(-tangent.z, 0.0, tangent.x)
			return [start.lerp(finish, ratio), perpendicular]
		remaining -= segment_length
	return [route[-1], Vector3.RIGHT]
