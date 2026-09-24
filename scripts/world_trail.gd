@tool
extends Node3D
class_name WorldTrail

@export_category("Shape")
@export_range(0.8, 3.0, 0.05) var path_width: float = 1.7
@export_range(3, 12, 1) var samples_per_segment: int = 7
@export var rebuild: bool = false:
	set(value):
		rebuild = false
		if value:
			build()

@export_category("Detail")
@export_range(0, 160, 1) var edge_stone_count: int = 36
@export_range(0, 80, 1) var dirt_patch_count: int = 34
@export var seed_value: int = 20260920

var _rng := RandomNumberGenerator.new()

# Main approach: player spawn -> cabin stairs. Branch: approach -> garden gate.
var main_route := PackedVector3Array([
	Vector3(-0.15, 0.0, 14.8),
	Vector3(-0.55, 0.0, 11.8),
	Vector3(0.15, 0.0, 8.6),
	Vector3(0.75, 0.0, 6.1),
	Vector3(1.55, 0.0, 4.15),
	Vector3(2.75, 0.0, 2.1),
	Vector3(3.78, 0.0, 0.05),
])

var garden_route := PackedVector3Array([
	Vector3(0.15, 0.0, 8.6),
	Vector3(-1.7, 0.0, 7.35),
	Vector3(-3.9, 0.0, 5.75),
	Vector3(-5.8, 0.0, 3.85),
	Vector3(-6.85, 0.0, 1.75),
	Vector3(-6.45, 0.0, -0.72),
])

func _ready() -> void:
	if get_child_count() == 0:
		build()
	_wear_start()

func build() -> void:
	for child in get_children():
		child.free()
	_rng.seed = seed_value

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.285, 0.29, 0.25, 1.0)
	stone.roughness = 0.98

	var main_curve := _sample_curve(main_route, samples_per_segment)
	var garden_curve := _sample_curve(garden_route, samples_per_segment)
	_add_edge_stones([main_curve, garden_curve], stone)

func _sample_curve(control: PackedVector3Array, resolution: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	for segment in range(control.size() - 1):
		var p0 := control[maxi(segment - 1, 0)]
		var p1 := control[segment]
		var p2 := control[segment + 1]
		var p3 := control[mini(segment + 2, control.size() - 1)]
		for step in range(resolution):
			var t := float(step) / float(resolution)
			result.append(_catmull_rom(p0, p1, p2, p3, t))
	result.append(control[-1])
	return result

func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

func _add_ribbon(name: String, curve: PackedVector3Array, width: float, material: Material, height: float, edge_jitter: float) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var travelled := 0.0
	for index in range(curve.size()):
		if index > 0:
			travelled += curve[index - 1].distance_to(curve[index])
		var previous := curve[maxi(0, index - 1)]
		var following := curve[mini(curve.size() - 1, index + 1)]
		var tangent := (following - previous).normalized()
		var side := Vector3(-tangent.z, 0.0, tangent.x)
		var jitter := sin(float(index) * 2.17 + float(seed_value % 17)) * edge_jitter
		var half_width := width * 0.5 + jitter
		vertices.append(curve[index] - side * half_width + Vector3.UP * height)
		vertices.append(curve[index] + side * half_width + Vector3.UP * height)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, travelled))
		uvs.append(Vector2(1.0, travelled))
		if index < curve.size() - 1:
			var base := index * 2
			indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 70.0
	add_child(instance)

func _add_edge_stones(curves: Array[PackedVector3Array], material: Material) -> void:
	if edge_stone_count <= 0:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.13
	mesh.bottom_radius = 0.17
	mesh.height = 0.075
	mesh.radial_segments = 7
	mesh.rings = 1
	mesh.material = material

	# Build a filtered candidate list so edging never appears on the porch,
	# directly beside the cabin, or at either route endpoint.
	var candidates: Array[Vector3] = []
	var candidate_sides: Array[Vector3] = []
	for route_index in range(curves.size()):
		var curve := curves[route_index]
		for curve_index in range(3, curve.size() - 4):
			var point := curve[curve_index]
			if _is_inside_house_buffer(point):
				continue
			# Keep the final third of the garden branch visually clean near the
			# fence and cabin, but preserve edging along the outer approach.
			if route_index == 1 and curve_index > int(curve.size() * 0.68):
				continue
			var tangent := (curve[curve_index + 1] - curve[curve_index - 1]).normalized()
			candidates.append(point)
			candidate_sides.append(Vector3(-tangent.z, 0.0, tangent.x))
	if candidates.is_empty():
		return

	var actual_count := mini(edge_stone_count, candidates.size())
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = actual_count
	for index in range(actual_count):
		# Distribute stones along both routes instead of clustering randomly.
		var candidate_index := int(floor(float(index) * float(candidates.size()) / float(actual_count)))
		candidate_index = clampi(candidate_index + _rng.randi_range(-1, 1), 0, candidates.size() - 1)
		var side := candidate_sides[candidate_index]
		var direction := -1.0 if index % 2 == 0 else 1.0
		var distance := path_width * _rng.randf_range(0.56, 0.69)
		var position := candidates[candidate_index] + side * direction * distance
		position += side * _rng.randf_range(-0.035, 0.035)
		position.y = 0.03
		var yaw := atan2(side.x, side.z) + _rng.randf_range(-0.18, 0.18)
		var basis := Basis(Vector3.UP, yaw)
		basis = basis.scaled(Vector3(_rng.randf_range(0.62, 0.9), _rng.randf_range(0.42, 0.66), _rng.randf_range(0.72, 1.0)))
		multimesh.set_instance_transform(index, Transform3D(basis, position))
	var instance := MultiMeshInstance3D.new()
	instance.name = "EdgeStones"
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.visibility_range_end = 52.0
	add_child(instance)

func _is_inside_house_buffer(point: Vector3) -> bool:
	# Cabin center is around (0, -4); the entrance/stairs extend toward +Z.
	# Stones are omitted from the wall perimeter and immediate porch approach.
	var cabin_walls := point.x > -4.9 and point.x < 5.4 and point.z > -7.8 and point.z < -0.6
	var porch_approach := point.x > 2.0 and point.x < 5.35 and point.z >= -0.6 and point.z < 1.8
	return cabin_walls or porch_approach

func _add_dirt_patches(curves: Array[PackedVector3Array], material: Material) -> void:
	if dirt_patch_count <= 0:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.24
	mesh.bottom_radius = 0.27
	mesh.height = 0.009
	mesh.radial_segments = 8
	mesh.rings = 1
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = dirt_patch_count
	for index in range(dirt_patch_count):
		var curve := curves[index % curves.size()]
		var curve_index := _rng.randi_range(1, curve.size() - 2)
		var tangent := (curve[curve_index + 1] - curve[curve_index - 1]).normalized()
		var side := Vector3(-tangent.z, 0.0, tangent.x)
		var position := curve[curve_index] + side * _rng.randf_range(-path_width * 0.3, path_width * 0.3) + Vector3.UP * 0.03
		var basis := Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3(_rng.randf_range(0.45, 1.15), 1.0, _rng.randf_range(0.28, 0.7)))
		multimesh.set_instance_transform(index, Transform3D(basis, position))
	var instance := MultiMeshInstance3D.new()
	instance.name = "WornPatches"
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 52.0
	add_child(instance)

# --- Persistent footpath wear (runtime only, never in the editor) ---
# Walking marks cells on a coarse grid; worn cells get flat dirt patches in one
# MultiMesh and grass tufts there are thinned. The ground mesh is never rebuilt.
const WEAR_CELL := 0.9
const WEAR_SAVE_PATH := "user://trails.json"
const WEAR_MAX_PATCHES := 3000
const WEAR_PER_STEP := 0.035
var _wear: Dictionary = {}
var _wear_slot: Dictionary = {}
var _wear_level: Dictionary = {}
var _wear_mm: MultiMesh
var _wear_ground: Node
var _wear_last := Vector2.INF
var _wear_timer := 0.0
var _wear_save_timer := 0.0
var _wear_dirty := false
var _wear_ready := false
var _grass_mm: MultiMesh
var _grass_cells: Dictionary = {}
var _grass_hidden: Dictionary = {}
var _grass_scan := 0.0


func _wear_start() -> void:
	if Engine.is_editor_hint():
		return
	await get_tree().process_frame
	_wear_ground = get_node_or_null("../Ground")
	if _wear_ground == null and get_tree().current_scene:
		for n in get_tree().current_scene.find_children("*", "StaticBody3D", true, false):
			if n.has_method("surface_height"):
				_wear_ground = n
				break
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.62
	mesh.bottom_radius = 0.66
	mesh.height = 0.012
	mesh.radial_segments = 7
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.material = mat
	_wear_mm = MultiMesh.new()
	_wear_mm.transform_format = MultiMesh.TRANSFORM_3D
	_wear_mm.use_colors = true
	_wear_mm.mesh = mesh
	_wear_mm.instance_count = WEAR_MAX_PATCHES
	_wear_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PlayerTrailWear"
	mmi.multimesh = _wear_mm
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 60.0
	add_child(mmi)
	_wear_load()
	_wear_ready = true


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _wear_ready:
		return
	_wear_timer += delta
	_wear_save_timer += delta
	_grass_scan -= delta
	if _grass_mm == null and _grass_scan <= 0.0:
		_grass_scan = 2.0
		_wear_find_grass()
	if _wear_save_timer > 30.0:
		_wear_save_timer = 0.0
		if _wear_dirty:
			_wear_save()
	if _wear_timer < 0.25:
		return
	_wear_timer = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := Vector2(cam.global_position.x, cam.global_position.z)
	if _wear_last == Vector2.INF:
		_wear_last = p
		return
	var moved := p.distance_to(_wear_last)
	_wear_last = p
	if moved < 0.15 or moved > 3.0:
		return
	if _is_inside_house_buffer(Vector3(p.x, 0.0, p.y)):
		return
	if _wear_ground and _wear_ground.has_method("is_water") and bool(_wear_ground.call("is_water", p)):
		return
	if cam.global_position.y - _wear_height(p) > 2.6:
		return
	var c := Vector2i(floori(p.x / WEAR_CELL), floori(p.y / WEAR_CELL))
	_wear_add(c, WEAR_PER_STEP)
	for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_wear_add(c + n, WEAR_PER_STEP * 0.2)


func _notification(what: int) -> void:
	if Engine.is_editor_hint():
		return
	if (what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE) and _wear_dirty:
		_wear_save()


func _wear_height(p: Vector2) -> float:
	if _wear_ground and _wear_ground.has_method("surface_height"):
		return float(_wear_ground.call("surface_height", p))
	return 0.0


func _wear_add(c: Vector2i, amount: float) -> void:
	var w := minf(1.0, float(_wear.get(c, 0.0)) + amount)
	_wear[c] = w
	_wear_dirty = true
	_wear_apply(c)


func _wear_apply(c: Vector2i) -> void:
	var w := float(_wear.get(c, 0.0))
	var level := int(w * 4.0)
	if level == int(_wear_level.get(c, -1)):
		return
	_wear_level[c] = level
	if level >= 1 and _wear_mm != null:
		var slot := -1
		if _wear_slot.has(c):
			slot = int(_wear_slot[c])
		elif _wear_mm.visible_instance_count < WEAR_MAX_PATCHES:
			slot = _wear_mm.visible_instance_count
			_wear_slot[c] = slot
			_wear_mm.visible_instance_count = slot + 1
		if slot >= 0:
			var center := (Vector2(c) + Vector2(0.5, 0.5)) * WEAR_CELL
			center += Vector2(sin(float(c.x) * 12.9898 + float(c.y) * 78.233), cos(float(c.x) * 39.35 + float(c.y) * 11.13)) * 0.18
			var normal := Vector3.UP
			if _wear_ground and _wear_ground.has_method("sample_normal"):
				normal = (_wear_ground.call("sample_normal", center) as Vector3).normalized()
			var s := lerpf(0.55, 1.05, w)
			var basis := Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, float(c.x * 7 + c.y * 13)).scaled(Vector3(s, 1.0, s * 0.8))
			_wear_mm.set_instance_transform(slot, Transform3D(basis, Vector3(center.x, _wear_height(center) + 0.012, center.y)))
			_wear_mm.set_instance_color(slot, Color(0.37, 0.36, 0.25).lerp(Color(0.35, 0.28, 0.19), w))
	_wear_thin_grass(c, w)


func _wear_find_grass() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var found: MultiMeshInstance3D = null
	for n in root.find_children("VolumetricLowPolyGrass", "MultiMeshInstance3D", true, false):
		found = n as MultiMeshInstance3D
		break
	if found == null or found.multimesh == null:
		return
	_grass_mm = found.multimesh
	var gxf := found.global_transform
	for i in _grass_mm.instance_count:
		var origin := gxf * _grass_mm.get_instance_transform(i).origin
		var c := Vector2i(floori(origin.x / WEAR_CELL), floori(origin.z / WEAR_CELL))
		if not _grass_cells.has(c):
			_grass_cells[c] = []
		(_grass_cells[c] as Array).append(i)
	for c in _wear.keys():
		_wear_thin_grass(c, float(_wear[c]))


func _wear_thin_grass(c: Vector2i, w: float) -> void:
	if _grass_mm == null or not _grass_cells.has(c):
		return
	var keep := 1.0 if w < 0.35 else (0.5 if w < 0.7 else 0.0)
	var list: Array = _grass_cells[c]
	for k in list.size():
		var i: int = list[k]
		if float(k % 4) / 4.0 >= keep and not _grass_hidden.has(i):
			_grass_hidden[i] = true
			var t := _grass_mm.get_instance_transform(i)
			t.origin.y -= 200.0
			_grass_mm.set_instance_transform(i, t)


func _wear_save() -> void:
	var cells := []
	for c in _wear.keys():
		cells.append([c.x, c.y, snappedf(float(_wear[c]), 0.01)])
	var tmp := WEAR_SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"version": 1, "cells": cells}))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(WEAR_SAVE_PATH))
	_wear_dirty = false


func _wear_load() -> void:
	if not FileAccess.file_exists(WEAR_SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(WEAR_SAVE_PATH))
	if not data is Dictionary:
		return
	for e in (data as Dictionary).get("cells", []):
		if e is Array and e.size() >= 3:
			var c := Vector2i(int(e[0]), int(e[1]))
			_wear[c] = clampf(float(e[2]), 0.0, 1.0)
			_wear_apply(c)
	_wear_dirty = false
