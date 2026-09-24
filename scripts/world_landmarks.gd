extends Node3D
class_name WorldLandmarks
## Hand-placed-looking landmarks generated deterministically on top of LowPolyGround.

@export var seed_value := 4127

var _ground: LowPolyGround
var _rng := RandomNumberGenerator.new()
var _bounds := Rect2()
var _used: Array[Vector2] = []
var _cabin := Vector2.INF
var _stone := _mat(Color(0.5, 0.49, 0.46))
var _stone_dark := _mat(Color(0.41, 0.41, 0.39))
var _bark := _mat(Color(0.33, 0.24, 0.17))
var _root_mat := _mat(Color(0.27, 0.2, 0.14))
var _wood := _mat(Color(0.52, 0.38, 0.25))


func _ready() -> void:
	await get_tree().process_frame
	var scene_root: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
	_ground = _find_ground(scene_root)
	if _ground == null or not is_instance_valid(_ground.mesh_instance) or _ground.mesh_instance.mesh == null:
		push_warning("WorldLandmarks: LowPolyGround not found")
		return
	var aabb: AABB = _ground.mesh_instance.global_transform * _ground.mesh_instance.mesh.get_aabb()
	_bounds = Rect2(Vector2(aabb.position.x, aabb.position.z), Vector2(aabb.size.x, aabb.size.z)).grow(-10.0)
	var cabin := _find_cabin(scene_root)
	if cabin:
		_cabin = Vector2(cabin.global_position.x, cabin.global_position.z)
	_rng.seed = seed_value
	_build_boulder()
	_build_fallen_tree()
	_build_viewpoint()
	_build_quiet_bay()


func _find_ground(node: Node) -> LowPolyGround:
	if node == null:
		return null
	if node is LowPolyGround:
		return node
	for child in node.get_children():
		var found := _find_ground(child)
		if found:
			return found
	return null


func _find_cabin(node: Node) -> Node3D:
	if node is Node3D and node != self and String(node.name).to_lower().contains("cabin"):
		return node
	for child in node.get_children():
		var found := _find_cabin(child)
		if found:
			return found
	return null


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


func _anchor(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	add_child(n)
	return n


func _add_mesh(parent: Node3D, mesh: Mesh, material: Material, xform: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.visibility_range_end = 140.0
	parent.add_child(mi)
	mi.global_transform = xform
	return mi


func _add_collider(parent: Node3D, shape: Shape3D, xform: Transform3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	body.global_transform = xform


func _height(p: Vector2) -> float:
	return _ground.surface_height(p)


func _v3(p: Vector2, offset := 0.0) -> Vector3:
	return Vector3(p.x, _height(p) + offset, p.y)


func _dry_around(p: Vector2, r: float) -> bool:
	if _ground.is_water(p):
		return false
	for i in 8:
		var a := TAU * float(i) / 8.0
		if _ground.is_water(p + Vector2(cos(a), sin(a)) * r):
			return false
	return true


func _free_spot(p: Vector2, min_gap: float) -> bool:
	if not _bounds.has_point(p):
		return false
	if _cabin != Vector2.INF and p.distance_to(_cabin) < 16.0:
		return false
	for u in _used:
		if p.distance_to(u) < min_gap:
			return false
	return true


func _find_spot(min_r: float, max_r: float, clearance: float, max_rise: float) -> Vector2:
	var center := _bounds.get_center()
	for i in 160:
		var a := _rng.randf() * TAU
		var p := center + Vector2(cos(a), sin(a)) * _rng.randf_range(min_r, max_r)
		if not _free_spot(p, 18.0) or not _dry_around(p, clearance + 1.5):
			continue
		if _ground.placement_ok(p, clearance, max_rise, 0.82):
			_used.append(p)
			return p
	return Vector2.INF


func _rock_mesh(size: Vector3, jitter: float) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 9
	sphere.rings = 5
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cache := {}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx.size():
		var v: Vector3 = verts[idx[i]]
		var key := Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))
		if not cache.has(key):
			cache[key] = 1.0 + _rng.randf_range(-jitter, jitter)
		var s: float = cache[key]
		st.add_vertex(Vector3(v.x * size.x, v.y * size.y, v.z * size.z) * s)
	st.generate_normals()
	return st.commit()


func _axis_basis(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _small_rock(parent: Node3D, p: Vector2, size: float, collide: bool) -> void:
	var mesh := _rock_mesh(Vector3(size, size * 0.62, size * 0.85), 0.16)
	var xform := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), _v3(p, -size * 0.12))
	_add_mesh(parent, mesh, _stone_dark if _rng.randf() < 0.5 else _stone, xform)
	if collide:
		_add_collider(parent, mesh.create_convex_shape(), xform)


func _signpost(parent: Node3D, p: Vector2, toward: Vector2, text: String) -> void:
	var dir := toward - p
	if dir.length() < 0.01:
		dir = Vector2(0.0, 1.0)
	var facing := Basis.looking_at(-Vector3(dir.x, 0.0, dir.y).normalized())
	var base := _v3(p)
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.4, 0.12)
	_add_mesh(parent, post, _wood, Transform3D(facing, base + Vector3(0.0, 0.6, 0.0)))
	var board := BoxMesh.new()
	board.size = Vector3(1.05, 0.34, 0.06)
	_add_mesh(parent, board, _wood, Transform3D(facing, base + Vector3(0.0, 1.15, 0.0)) * Transform3D(Basis(), Vector3(0.0, 0.0, 0.07)))
	var label := Label3D.new()
	label.text = text
	label.font_size = 44
	label.pixel_size = 0.004
	label.outline_size = 0
	label.modulate = Color(0.24, 0.17, 0.11)
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.visibility_range_end = 20.0
	parent.add_child(label)
	label.global_transform = Transform3D(facing, base + Vector3(0.0, 1.15, 0.0)) * Transform3D(Basis(), Vector3(0.0, 0.0, 0.105))
	_add_collider(parent, _box(Vector3(0.2, 1.4, 0.2)), Transform3D(facing, base + Vector3(0.0, 0.6, 0.0)))


func _box(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


func _bench(parent: Node3D, p: Vector2, look_at_p: Vector2) -> void:
	var dir := look_at_p - p
	var facing := Basis.looking_at(Vector3(dir.x, 0.0, dir.y).normalized()) if dir.length() > 0.01 else Basis()
	var base := _v3(p)
	var seat := BoxMesh.new()
	seat.size = Vector3(1.8, 0.1, 0.45)
	_add_mesh(parent, seat, _wood, Transform3D(facing, base + Vector3(0.0, 0.46, 0.0)))
	var leg := BoxMesh.new()
	leg.size = Vector3(0.14, 0.5, 0.4)
	for side in [-0.7, 0.7]:
		_add_mesh(parent, leg, _bark, Transform3D(facing, base + Vector3(0.0, 0.2, 0.0)) * Transform3D(Basis(), Vector3(side, 0.0, 0.0)))
	_add_collider(parent, _box(Vector3(1.8, 0.52, 0.45)), Transform3D(facing, base + Vector3(0.0, 0.26, 0.0)))


func _build_boulder() -> void:
	var p := _find_spot(24.0, 60.0, 3.0, 1.2)
	if p == Vector2.INF:
		return
	var root := _anchor("OldBoulder")
	var mesh := _rock_mesh(Vector3(4.6, 3.1, 3.9), 0.12)
	var xform := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), _v3(p, 0.55))
	_add_mesh(root, mesh, _stone, xform)
	_add_collider(root, mesh.create_convex_shape(), xform)
	for i in 4:
		var a := _rng.randf() * TAU
		_small_rock(root, p + Vector2(cos(a), sin(a)) * _rng.randf_range(3.0, 4.4), _rng.randf_range(0.45, 0.9), i < 2)


func _build_fallen_tree() -> void:
	var p := _find_spot(26.0, 70.0, 4.0, 0.7)
	if p == Vector2.INF:
		return
	var root := _anchor("FallenTree")
	var yaw := _rng.randf() * TAU
	var dir := Vector2(cos(yaw), sin(yaw))
	var radius := 0.4
	var a2 := p - dir * 3.8
	var b2 := p + dir * 3.8
	var a := _v3(a2, radius * 0.75)
	var b := _v3(b2, radius * 0.55)
	var basis := _axis_basis(b - a)
	var trunk := CylinderMesh.new()
	trunk.bottom_radius = radius
	trunk.top_radius = radius * 0.7
	trunk.height = a.distance_to(b)
	trunk.radial_segments = 7
	trunk.rings = 1
	_add_mesh(root, trunk, _bark, Transform3D(basis, (a + b) * 0.5))
	var plate := CylinderMesh.new()
	plate.top_radius = 1.05
	plate.bottom_radius = 0.85
	plate.height = 0.32
	plate.radial_segments = 7
	plate.rings = 1
	_add_mesh(root, plate, _root_mat, Transform3D(basis, a - basis.y * 0.12))
	var stub := CylinderMesh.new()
	stub.top_radius = 0.05
	stub.bottom_radius = 0.11
	stub.height = 1.1
	stub.radial_segments = 5
	stub.rings = 1
	for t in [0.35, 0.62]:
		var at: Vector3 = a.lerp(b, t)
		var branch_axis := (basis.x * (1.0 if t < 0.5 else -1.0) + basis.y * 0.6 + Vector3.UP * 0.5)
		var bb := _axis_basis(branch_axis)
		_add_mesh(root, stub, _bark, Transform3D(bb, at + bb.y * 0.55))
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = trunk.height
	_add_collider(root, capsule, Transform3D(basis, (a + b) * 0.5))


func _build_viewpoint() -> void:
	var best := Vector2.INF
	var best_h := -INF
	var x := _bounds.position.x + 4.0
	while x < _bounds.end.x - 4.0:
		var z := _bounds.position.y + 4.0
		while z < _bounds.end.y - 4.0:
			var p := Vector2(x, z)
			var h := _height(p)
			if h > best_h and _free_spot(p, 14.0) and _dry_around(p, 3.0) and _ground.placement_ok(p, 2.2, 0.5, 0.85):
				best = p
				best_h = h
			z += 5.0
		x += 5.0
	if best == Vector2.INF:
		return
	_used.append(best)
	var root := _anchor("HillLookout")
	var view := _ground.lake_center()
	_bench(root, best, view)
	var side := (view - best).normalized().orthogonal() * 1.9
	var cairn_p := best + side
	var base_y := _height(cairn_p)
	var size := 0.8
	var y := base_y
	for i in 3:
		var mesh := _rock_mesh(Vector3(size, size * 0.55, size * 0.9), 0.12)
		var xform := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(cairn_p.x, y + size * 0.2, cairn_p.y))
		_add_mesh(root, mesh, _stone if i % 2 == 0 else _stone_dark, xform)
		if i == 0:
			_add_collider(root, mesh.create_convex_shape(), xform)
		y += size * 0.48
		size *= 0.72
	_signpost(root, best - side, best - (view - best).normalized() * 4.0, "Old Lookout")


func _river_distance(p: Vector2) -> float:
	var d := INF
	for q in _ground.river_path():
		d = minf(d, p.distance_to(q))
	return d


func _build_quiet_bay() -> void:
	var c := _ground.lake_center()
	var r := _ground.lake_radius()
	var best_score := -INF
	var best_shore := Vector2.INF
	var best_dir := Vector2.ZERO
	for i in 24:
		var a := TAU * float(i) / 24.0
		var dir := Vector2(cos(a), sin(a))
		var dist := r * 0.5
		while dist < r * 2.0 and _ground.is_water(c + dir * dist):
			dist += 0.5
		var shore := c + dir * dist
		var spot := shore + dir * 3.2
		if not _free_spot(spot, 14.0) or not _dry_around(spot, 1.2):
			continue
		if not _ground.placement_ok(spot, 1.6, 0.6, 0.85):
			continue
		var score := _river_distance(shore)
		if score > best_score:
			best_score = score
			best_shore = shore
			best_dir = dir
	if best_shore == Vector2.INF:
		return
	var spot := best_shore + best_dir * 3.2
	_used.append(spot)
	var root := _anchor("QuietBay")
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.26
	log_mesh.bottom_radius = 0.28
	log_mesh.height = 2.2
	log_mesh.radial_segments = 7
	log_mesh.rings = 1
	var along := best_dir.orthogonal()
	var la := _v3(spot - along * 1.1, 0.22)
	var lb := _v3(spot + along * 1.1, 0.22)
	var lbasis := _axis_basis(lb - la)
	_add_mesh(root, log_mesh, _bark, Transform3D(lbasis, (la + lb) * 0.5))
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 2.2
	_add_collider(root, cap, Transform3D(lbasis, (la + lb) * 0.5))
	for k in 4:
		var sp := best_shore + best_dir * _rng.randf_range(0.6, 1.6) + along * _rng.randf_range(-3.0, 3.0)
		if not _ground.is_water(sp):
			_small_rock(root, sp, _rng.randf_range(0.35, 0.7), false)
	_signpost(root, spot + best_dir * 1.6 + along * 1.8, spot + best_dir * 6.0, "Quiet Bay")
