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
@export var clearing_tree_count: int = 16
@export var clearing_bush_count: int = 10
@export var clearing_rock_count: int = 45
@export var clearing_grass_count: int = 180

@export_range(0.0, 1.0, 0.05) var foliage_muting: float = 0.76
@export_range(0.25, 1.0, 0.05) var canopy_brightness: float = 0.76
const FOLIAGE_SHADER := preload("res://shaders/forest_foliage.gdshader")
var _foliage_materials: Dictionary = {}

var _rng := RandomNumberGenerator.new()
# Shared exclusion map for every tree, bush, and rock, including clearing passes.
# Vector3 stores world X/Z in x/z and the reserved radius in y.
var _occupied: Array[Vector3] = []

func _set_regenerate(v: bool) -> void:
	regenerate = false
	if v:
		build()

func _ready() -> void:
	if not Engine.is_editor_hint() and get_child_count() == 0:
		call_deferred("build")

func build() -> void:
	for child in get_children():
		child.free()
	_rng.seed = seed_value
	_occupied.clear()
	_foliage_materials.clear()
	# Seed the former yard first so it cannot be starved by the wider forest passes.
	_scatter_left_of_house()
	_scatter_clearing(tree_scenes, clearing_tree_count, 4.2, clearing_radius + 2.0, Vector2(0.72, 1.15), "Trees", "tree")
	_scatter_clearing(rock_scenes, clearing_rock_count, 2.0, clearing_radius - 0.5, Vector2(0.38, 0.85), "Rocks", "rock")
	_scatter_clearing(bush_scenes, clearing_bush_count, 2.2, clearing_radius - 0.8, Vector2(0.55, 1.0), "Bushes", "bush")
	# Then fill the whole map. Every pass uses the same occupied-position map.
	_scatter(tree_scenes, tree_count, 0.0, radius, Vector2(0.9, 1.65), "tree")
	_scatter(bush_scenes, bush_count, 0.0, radius * 0.92, Vector2(0.75, 1.45), "bush")
	_scatter(rock_scenes, rock_count, 0.0, radius * 0.86, Vector2(0.7, 1.8), "rock")
	_scatter(grass_scenes, grass_count, clearing_radius - 4.0, radius * 0.72, Vector2(0.65, 1.35), "none")
	_scatter_clearing(grass_scenes, clearing_grass_count, 3.8, clearing_radius + 2.0, Vector2(0.35, 0.95), "Grass", "none")


# One metre from cabin walls plus the object footprint, across every pass.
func _near_cabin(pos: Vector3, kind: String, scales: Vector2) -> bool:
	var margin := 1.0
	if kind == "tree": margin += 1.25 * scales.y
	elif kind == "rock": margin += 0.9 * scales.y
	return pos.x > -4.15 - margin and pos.x < 4.15 + margin \
		and pos.z > -7.44 - margin and pos.z < -0.56 + margin

func _scatter_left_of_house() -> void:
	# The old garden reservation leaves an obvious visual hole west of the cabin.
	# Fill its outer/west side deliberately before random world scatter begins.
	var root := Node3D.new()
	root.name = "DenseWestSide"
	add_child(root)
	root.owner = owner
	var specifications := [
		[tree_scenes, 24, "tree", Vector2(0.72, 1.18)],
		[bush_scenes, 38, "bush", Vector2(0.62, 1.15)],
		[rock_scenes, 30, "rock", Vector2(0.48, 1.12)],
	]
	for specification in specifications:
		var library: Array = specification[0]
		var wanted: int = specification[1]
		var kind: String = specification[2]
		var scale_range: Vector2 = specification[3]
		if library.is_empty():
			continue
		var placed := 0
		var attempts := 0
		while placed < wanted and attempts < wanted * 55:
			attempts += 1
			var pos := Vector3(_rng.randf_range(-23.0, -5.6), 0.0, _rng.randf_range(-11.5, 7.5))
			var _terrain := get_node_or_null("../Ground")
			if _terrain and _terrain.has_method("can_place") and not _terrain.call("can_place", Vector2(pos.x, pos.z), "grass" if kind == "none" else kind): continue
			# Preserve the physical garden itself, but not the broad region around it.
			if pos.x > -12.0 and pos.x < -4.0 and pos.z > -8.0 and pos.z < 0.0:
				continue
			if pos.x > -5.8 and pos.z > -8.4 and pos.z < 0.8:
				continue
			if kind in ["tree", "rock"] and _near_cabin(pos, kind, scale_range):
				continue
			var spacing := _spacing_radius(kind, scale_range) * 0.74
			if not _has_spacing(pos, spacing):
				continue
			var scene: PackedScene = library[_rng.randi_range(0, library.size() - 1)]
			if scene == null:
				continue
			var visual := scene.instantiate() as Node3D
			if visual == null:
				continue
			if kind == "tree" or kind == "bush":
				_tone_foliage(visual)
			var item := _create_harvestable(visual, kind)
			item.position = pos
			item.rotation.y = _rng.randf() * TAU
			var scale_factor := _rng.randf_range(scale_range.x, scale_range.y)
			item.scale = Vector3(scale_factor, scale_factor * _rng.randf_range(0.88, 1.14), scale_factor)
			_configure_visibility(visual, kind == "tree", 48.0)
			root.add_child(item)
			_plant_on_surface(item, pos, kind, scale_factor)
			item.owner = owner
			_set_owner_recursive(item)
			_add_harvest_collision(item, visual, kind, scale_factor)
			_reserve_position(pos, spacing)
			placed += 1

func _terrain_height(pos: Vector3) -> float:
	var ground := get_node_or_null("../Ground")
	if ground and ground.has_method("surface_height"):
		return float(ground.call("surface_height", Vector2(pos.x, pos.z)))
	return 0.0

func _plant_on_surface(item: Node3D, pos: Vector3, kind: String, scale_factor: float) -> void:
	# Sample the actual terrain collision under the centre and around the base.
	# The lowest contact wins, so a trunk on a polygon edge cannot hang in air.
	var radius := (0.28 if kind == "tree" else (0.22 if kind == "bush" else 0.34)) * scale_factor
	var samples := PackedVector2Array([
		Vector2.ZERO, Vector2(radius, 0.0), Vector2(-radius, 0.0),
		Vector2(0.0, radius), Vector2(0.0, -radius),
		Vector2(radius * 0.7, radius * 0.7), Vector2(-radius * 0.7, radius * 0.7),
		Vector2(radius * 0.7, -radius * 0.7), Vector2(-radius * 0.7, -radius * 0.7),
	])
	var lowest := INF
	for offset in samples:
		lowest = minf(lowest, _terrain_height(Vector3(pos.x + offset.x, 0.0, pos.z + offset.y)))
	var center := _terrain_height(Vector3(pos.x, 0.0, pos.z))
	var base_y := lerpf(center, lowest, 0.35 if kind == "rock" else 0.15)
	var burial := (0.12 if kind == "tree" else (0.06 if kind == "bush" else 0.1)) * scale_factor
	item.position = Vector3(pos.x, base_y - burial, pos.z)

func _scatter_clearing(library: Array[PackedScene], count: int, inner: float, outer: float, scale_range: Vector2, group_name: String, kind: String) -> void:
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
		var ground:=get_node_or_null("../Ground")
		if ground and ground.has_method("is_water") and ground.call("is_water",Vector2(pos.x,pos.z)): continue
		if ground and ground.has_method("can_place") and not ground.call("can_place", Vector2(pos.x, pos.z), "grass" if kind == "none" else kind): continue
		if kind == "tree" and ground and ground.has_method("tree_allowed") and not ground.call("tree_allowed", Vector2(pos.x, pos.z)): continue
		# Protect only the cabin mesh itself, not the yard around it.
		if kind in ["tree", "rock"] and _near_cabin(pos, kind, scale_range):
			continue
		if pos.x > -4.95 and pos.x < 5.35 and pos.z > -8.05 and pos.z < 0.45:
			continue
		# Keep the fenced garden at world X -11..-5, Z -7..-1 clear.
		if pos.x > -12.0 and pos.x < -4.0 and pos.z > -8.0 and pos.z < 0.0:
			continue
		var spacing := _spacing_radius(kind, scale_range)
		if not _has_spacing(pos, spacing):
			continue
		var scene := library[_rng.randi_range(0, library.size() - 1)]
		if scene == null:
			continue
		var visual := scene.instantiate() as Node3D
		if visual == null:
			continue
		if kind == "tree" or kind == "bush":
			_tone_foliage(visual)
		var item := _create_harvestable(visual, kind)
		item.position = pos
		item.rotation.y = _rng.randf() * TAU
		var scale_factor := _rng.randf_range(scale_range.x, scale_range.y)
		item.scale = Vector3(scale_factor, scale_factor * _rng.randf_range(0.86, 1.12), scale_factor)
		_configure_visibility(visual, kind == "tree", outer + 24.0)
		root.add_child(item)
		_plant_on_surface(item, pos, kind, scale_factor)
		item.owner = owner
		_set_owner_recursive(item)
		_add_harvest_collision(item, visual, kind, scale_factor)
		_reserve_position(pos, spacing)
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
		var ground:=get_node_or_null("../Ground")
		if ground and ground.has_method("is_water") and ground.call("is_water",Vector2(pos.x,pos.z)): continue
		if ground and ground.has_method("can_place") and not ground.call("can_place", Vector2(pos.x, pos.z), "grass" if collision_type == "none" else collision_type): continue
		if collision_type == "tree" and ground and ground.has_method("tree_allowed") and not ground.call("tree_allowed", Vector2(pos.x, pos.z)): continue
		# Protect only the cabin mesh itself; the former empty yard is available.
		if collision_type in ["tree", "rock"] and _near_cabin(pos, collision_type, scale_range):
			continue
		if pos.x > -4.95 and pos.x < 5.35 and pos.z > -8.05 and pos.z < 0.45:
			continue
		# Keep only a tiny spawn pocket so the player cannot begin inside a trunk or rock.
		if Vector2(pos.x, pos.z).distance_to(Vector2(0.0, 13.0)) < 1.35:
			continue
		# Keep the fenced garden at world X -11..-5, Z -7..-1 clear.
		if pos.x > -12.0 and pos.x < -4.0 and pos.z > -8.0 and pos.z < 0.0:
			continue
		var spacing := _spacing_radius(collision_type, scale_range)
		if not _has_spacing(pos, spacing):
			continue
		var scene := library[_rng.randi_range(0, library.size() - 1)]
		if scene == null:
			continue
		var visual := scene.instantiate() as Node3D
		if visual == null:
			continue
		if collision_type == "tree" or collision_type == "bush":
			_tone_foliage(visual)
		var item := _create_harvestable(visual, collision_type)
		item.position = pos
		item.rotation.y = _rng.randf() * TAU
		var s := _rng.randf_range(scale_range.x, scale_range.y)
		item.scale = Vector3(s, s * _rng.randf_range(0.9, 1.12), s)
		_configure_visibility(visual, collision_type == "tree", outer)
		add_child(item)
		_plant_on_surface(item, pos, collision_type, s)
		item.owner = owner
		_set_owner_recursive(item)
		_add_harvest_collision(item, visual, collision_type, s)
		_reserve_position(pos, spacing)
		placed += 1

func _spacing_radius(kind: String, scale_range: Vector2) -> float:
	var average_scale := (scale_range.x + scale_range.y) * 0.5
	match kind:
		"tree": return 1.15 + average_scale * 0.38
		"rock": return 0.72 + average_scale * 0.24
		"bush": return 0.62 + average_scale * 0.22
		_: return 0.35

func _has_spacing(pos: Vector3, radius_value: float) -> bool:
	var flat := Vector2(pos.x, pos.z)
	for occupied in _occupied:
		if flat.distance_to(Vector2(occupied.x, occupied.z)) < radius_value + occupied.y:
			return false
	return true

func _reserve_position(pos: Vector3, radius_value: float) -> void:
	_occupied.append(Vector3(pos.x, radius_value, pos.z))

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

func _tone_foliage(visual: Node3D) -> void:
	# Preserve trunk and bark colors; tint only green texels in the imported atlas.
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var imported := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if imported == null or imported.albedo_texture == null:
				continue
			var texture := imported.albedo_texture
			var texture_id := texture.get_instance_id()
			if not _foliage_materials.has(texture_id):
				var muted := ShaderMaterial.new()
				muted.shader = FOLIAGE_SHADER
				muted.set_shader_parameter("albedo_texture", texture)
				muted.set_shader_parameter("foliage_strength", foliage_muting)
				muted.set_shader_parameter("canopy_brightness", canopy_brightness)
				_foliage_materials[texture_id] = muted
			mesh_instance.set_surface_override_material(surface, _foliage_materials[texture_id])

func _create_harvestable(visual: Node3D, kind: String) -> Node3D:
	if kind not in ["tree", "rock", "bush"]:
		return visual
	var body := HarvestableResource.new()
	body.name = "%sResource" % kind.capitalize()
	body.resource_kind = "stone" if kind == "rock" else kind
	body.amount = 4 if kind == "tree" else (3 if kind == "rock" else 2)
	body.hits_required = 5 if kind == "tree" else (4 if kind == "rock" else 2)
	body.respawn_seconds = 240.0 if kind == "tree" else 190.0
	# Bushes stay ray-interactable on layer 2, but never block the player.
	if kind == "bush":
		body.collision_layer = 2
		body.collision_mask = 0
	body.add_child(visual)
	return body

func _add_harvest_collision(body: Node3D, visual: Node3D, kind: String, scale_factor: float) -> void:
	if body == visual or not body is CollisionObject3D:
		return
	if kind == "tree":
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.3 / maxf(scale_factor, 0.01)
		shape.height = 4.4 / maxf(body.scale.y, 0.01)
		collision.shape = shape
		collision.position.y = shape.height * 0.5
		body.add_child(collision)
	elif kind == "bush":
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.72 / maxf(scale_factor, 0.01)
		collision.shape = shape
		collision.position.y = 0.52 / maxf(body.scale.y, 0.01)
		body.add_child(collision)
	elif kind == "rock":
		var shape_count := 0
		for node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			var shape := mesh_instance.mesh.create_convex_shape(true, true)
			if shape == null:
				continue
			var collision := CollisionShape3D.new()
			collision.name = "RockShape_%02d" % shape_count
			collision.shape = shape
			collision.transform = body.global_transform.affine_inverse() * mesh_instance.global_transform
			body.add_child(collision)
			shape_count += 1

func _set_owner_recursive(node: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child)
