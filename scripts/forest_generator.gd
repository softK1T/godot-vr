@tool
extends Node3D
class_name ForestGenerator

@export_category("Layout")
@export var regenerate: bool = false : set = _set_regenerate
@export var radius: float = 72.0
@export var clearing_radius: float = 12.0
@export var seed_value: int = 1337
@export var tree_count: int = 190
@export var bush_count: int = 85
@export var rock_count: int = 90
@export var grass_count: int = 950

@export_category("Asset library")
@export var tree_scenes: Array[PackedScene] = []
@export var bush_scenes: Array[PackedScene] = []
@export var rock_scenes: Array[PackedScene] = []
@export var grass_scenes: Array[PackedScene] = []

@export_category("Clearing detail")
@export var clearing_bush_count: int = 10
@export var clearing_rock_count: int = 45
@export var clearing_grass_count: int = 180

var _rng := RandomNumberGenerator.new()

func _set_regenerate(v: bool) -> void:
	regenerate = false
	if v:
		build()

func _ready() -> void:
	if not Engine.is_editor_hint() and get_child_count() == 0:
		build()

func build() -> void:
	for child in get_children():
		child.free()
	_rng.seed = seed_value
	_scatter(tree_scenes, tree_count, clearing_radius, radius, Vector2(0.9, 1.65), "tree")
	_scatter(bush_scenes, bush_count, clearing_radius - 1.0, radius * 0.92, Vector2(0.75, 1.45), "none")
	_scatter(rock_scenes, rock_count, clearing_radius - 2.0, radius * 0.86, Vector2(0.7, 1.8), "rock")
	_scatter(grass_scenes, grass_count, clearing_radius - 4.0, radius * 0.72, Vector2(0.65, 1.35), "none")
	_scatter_clearing(bush_scenes, clearing_bush_count, 5.8, clearing_radius - 0.8, Vector2(0.55, 1.0), "Bushes", false)
	_scatter_clearing(rock_scenes, clearing_rock_count, 4.8, clearing_radius - 0.5, Vector2(0.38, 0.85), "Rocks", true)
	_scatter_clearing(grass_scenes, clearing_grass_count, 3.8, clearing_radius + 2.0, Vector2(0.35, 0.95), "Grass", false)

func _scatter_clearing(library: Array[PackedScene], count: int, inner: float, outer: float, scale_range: Vector2, group_name: String, add_rock_collision: bool = false) -> void:
	if library.is_empty():
		return
	var root := Node3D.new()
	root.name = "Clearing%s" % group_name
	add_child(root)
	root.owner = owner
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 35:
		attempts += 1
		var angle := _rng.randf() * TAU
		var distance := sqrt(_rng.randf_range(inner * inner, outer * outer))
		var pos := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var trail_clearance := 3.2 if add_rock_collision else 1.25
		if _is_near_world_trail(pos, trail_clearance):
			continue
		# Keep the approach, porch, stairs, and immediate cabin footprint clear.
		if absf(pos.x) < 2.2 and pos.z > -1.5 and pos.z < 15.5:
			continue
		if absf(pos.x) < 5.2 and pos.z > -8.2 and pos.z < 2.8:
			continue
		# Keep the fenced garden at world X -11..-5, Z -7..-1 clear.
		if pos.x > -12.0 and pos.x < -4.0 and pos.z > -8.0 and pos.z < 0.0:
			continue
		var scene := library[_rng.randi_range(0, library.size() - 1)]
		if scene == null:
			continue
		var item := scene.instantiate() as Node3D
		if item == null:
			continue
		item.position = pos
		item.rotation.y = _rng.randf() * TAU
		var scale_factor := _rng.randf_range(scale_range.x, scale_range.y)
		item.scale = Vector3(scale_factor, scale_factor * _rng.randf_range(0.86, 1.12), scale_factor)
		_configure_visibility(item, false, outer + 24.0)
		root.add_child(item)
		item.owner = owner
		_set_owner_recursive(item)
		if add_rock_collision:
			_add_rock_collision(item)
		placed += 1

func _scatter(library: Array[PackedScene], count: int, inner: float, outer: float, scale_range: Vector2, collision_type: String) -> void:
	if library.is_empty():
		return
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 20:
		attempts += 1
		var angle := _rng.randf() * TAU
		var distance := sqrt(_rng.randf()) * outer
		if distance < inner:
			continue
		var pos := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var trail_clearance := 3.2 if collision_type == "rock" else 1.55
		if _is_near_world_trail(pos, trail_clearance):
			continue
		if absf(pos.x) < 2.6 and pos.z > -7.0 and pos.z < 14.0:
			continue
		# Keep the fenced garden at world X -11..-5, Z -7..-1 clear.
		if pos.x > -12.0 and pos.x < -4.0 and pos.z > -8.0 and pos.z < 0.0:
			continue
		var scene := library[_rng.randi_range(0, library.size() - 1)]
		if scene == null:
			continue
		var item := scene.instantiate() as Node3D
		if item == null:
			continue
		item.position = pos
		item.rotation.y = _rng.randf() * TAU
		var s := _rng.randf_range(scale_range.x, scale_range.y)
		item.scale = Vector3(s, s * _rng.randf_range(0.9, 1.12), s)
		_configure_visibility(item, collision_type == "tree", outer)
		add_child(item)
		item.owner = owner
		_set_owner_recursive(item)
		if collision_type == "tree":
			_add_trunk_collision(item, s)
		elif collision_type == "rock":
			_add_rock_collision(item)
		placed += 1

func _is_near_world_trail(point: Vector3, clearance: float) -> bool:
	var main_route := PackedVector3Array([
		Vector3(-0.15, 0.0, 14.8), Vector3(-0.55, 0.0, 11.8),
		Vector3(0.15, 0.0, 8.6), Vector3(0.75, 0.0, 6.1),
		Vector3(1.55, 0.0, 4.15), Vector3(2.75, 0.0, 2.1),
		Vector3(3.78, 0.0, 0.05),
	])
	var garden_route := PackedVector3Array([
		Vector3(0.15, 0.0, 8.6), Vector3(-1.7, 0.0, 7.35),
		Vector3(-3.9, 0.0, 5.75), Vector3(-5.8, 0.0, 3.85),
		Vector3(-6.85, 0.0, 1.75), Vector3(-6.45, 0.0, -0.72),
	])
	return _distance_to_polyline(point, main_route) < clearance or _distance_to_polyline(point, garden_route) < clearance

func _distance_to_polyline(point: Vector3, route: PackedVector3Array) -> float:
	var best := INF
	var flat_point := Vector2(point.x, point.z)
	for index in range(route.size() - 1):
		var start := Vector2(route[index].x, route[index].z)
		var finish := Vector2(route[index + 1].x, route[index + 1].z)
		var segment := finish - start
		var ratio := clampf((flat_point - start).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, flat_point.distance_to(start + segment * ratio))
	return best

func _configure_visibility(item: Node3D, is_tree: bool, scatter_radius: float) -> void:
	var visibility_end := scatter_radius + 12.0
	if not is_tree:
		visibility_end = minf(scatter_radius, 38.0)
	for node in item.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.visibility_range_end = visibility_end
		geometry.visibility_range_end_margin = 0.0
		geometry.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		geometry.lod_bias = 0.65 if is_tree else 0.5

func _add_trunk_collision(item: Node3D, scale_factor: float) -> void:
	var body := StaticBody3D.new()
	body.name = "TrunkCollision"
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.28 / maxf(scale_factor, 0.01)
	shape.height = 4.2 / maxf(item.scale.y, 0.01)
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	body.add_child(collision)
	item.add_child(body)
	body.owner = owner
	collision.owner = owner

func _add_rock_collision(item: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "RockCollision"
	item.add_child(body)
	body.owner = owner
	var shape_count := 0
	for node in item.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var shape := mesh_instance.mesh.create_convex_shape(true, true)
		if shape == null:
			continue
		var collision := CollisionShape3D.new()
		collision.name = "RockShape_%02d" % shape_count
		collision.shape = shape
		collision.transform = item.global_transform.affine_inverse() * mesh_instance.global_transform
		body.add_child(collision)
		collision.owner = owner
		shape_count += 1
	if shape_count == 0:
		body.queue_free()

func _set_owner_recursive(node: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child)
