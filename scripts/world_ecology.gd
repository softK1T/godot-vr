extends Node
class_name WorldEcology
## Decorative shoreline ecology and forest biomes, generated once at start.
## Reeds and sedge along river and lake, lily pads on the calm side of the lake,
## shore rocks and driftwood, moss in wet patches, flower meadows, sparse flowers
## in the cabin clearing, ferns in tree shade, pebbles on rocky slopes, rare fallen
## trunks and old stumps. Small objects use MultiMesh split into chunks, so the
## visibility range culls them. Decor has no collision, except simple shapes on
## fallen trunks and stumps.
const SEED := 91873
const CHUNK := 32.0

var _rng := RandomNumberGenerator.new()
var _ground: LowPolyGround
var _house := Vector2.ZERO
var _trees: Array[Vector2] = []
var _blocked: Array[Vector3] = []
var _batches := {}
var _defs := {}
var _colliders: StaticBody3D

func _ready() -> void:
	call_deferred("_generate")

func _generate() -> void:
	_ground = get_node_or_null("../Ground") as LowPolyGround
	if _ground == null:
		return
	_rng.seed = SEED
	var house := get_node_or_null("../House") as Node3D
	if house:
		_house = Vector2(house.global_position.x, house.global_position.z)
	for r in get_tree().get_nodes_in_group("harvestable_resources"):
		if r is Node3D and str(r.get("resource_kind")) == "tree":
			var tp: Vector3 = (r as Node3D).global_position
			_trees.append(Vector2(tp.x, tp.z))
	_colliders = StaticBody3D.new()
	_colliders.name = "EcologyColliders"
	add_child(_colliders)
	_define_meshes()
	_fallen_trunks()
	_old_stumps()
	_shoreline()
	_lily_pads()
	_wet_patches()
	_meadows()
	_clearing_flowers()
	_ferns()
	_rocky_slopes()
	_build_multimeshes()

# ---------------------------------------------------------------- meshes
func _mat(double_sided: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.metallic_specular = 0.2
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _def(cat: String, mesh: Mesh, range_end: float, shadow: bool) -> void:
	_defs[cat] = {"mesh": mesh, "range": range_end, "shadow": shadow}
	_batches[cat] = {}

func _define_meshes() -> void:
	_def("reed", _blades(7, 1.5, 0.05, Color(0.44, 0.50, 0.30), Color(0.52, 0.44, 0.28)), 60.0, false)
	_def("sedge", _blades(9, 0.55, 0.07, Color(0.34, 0.42, 0.25), Color(0.48, 0.50, 0.32)), 45.0, false)
	_def("lily", _pad(), 70.0, false)
	_def("lily_flower", _disc_mesh(0.09, 6, Color(0.90, 0.86, 0.82), 0.02), 50.0, false)
	_def("shore_rock", _rock(Color(0.47, 0.47, 0.45)), 90.0, true)
	_def("driftwood", _log(Color(0.55, 0.50, 0.43), Color(0.62, 0.57, 0.48)), 80.0, true)
	_def("moss", _patch(Color(0.30, 0.37, 0.22)), 50.0, false)
	_def("flower_white", _flower(Color(0.88, 0.86, 0.80)), 45.0, false)
	_def("flower_yellow", _flower(Color(0.84, 0.74, 0.38)), 45.0, false)
	_def("flower_lilac", _flower(Color(0.60, 0.53, 0.70)), 45.0, false)
	_def("fern", _fern(), 55.0, false)
	_def("pebble", _rock(Color(0.52, 0.51, 0.48)), 70.0, false)
	_def("trunk", _log(Color(0.36, 0.28, 0.20), Color(0.58, 0.47, 0.32)), 120.0, true)
	_def("stump", _stump(), 100.0, true)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, n: Vector3) -> void:
	st.set_normal(n)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.add_vertex(c)

func _commit(st: SurfaceTool, double_sided: bool) -> ArrayMesh:
	var m := st.commit()
	m.surface_set_material(0, _mat(double_sided))
	return m

func _blades(count: int, h: float, w: float, base: Color, tip: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var ang := TAU * float(i) / float(count) + _rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x) * w
		var hh := h * _rng.randf_range(0.7, 1.1)
		var root := dir * _rng.randf_range(0.02, 0.12)
		var top := root + dir * hh * _rng.randf_range(0.12, 0.3) + Vector3(0.0, hh, 0.0)
		_tri(st, root - side, root + side, top, base, base, tip, (Vector3.UP * 0.7 + dir * 0.3).normalized())
	return _commit(st, true)

func _add_disc(st: SurfaceTool, center: Vector3, r: float, sides: int, col: Color, skip_first: bool) -> void:
	for i in range(1 if skip_first else 0, sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var r0 := r * (1.0 if skip_first else _rng.randf_range(0.8, 1.1))
		_tri(st, center, center + Vector3(cos(a1), 0.0, sin(a1)) * r, center + Vector3(cos(a0), 0.0, sin(a0)) * r0, col, col.lightened(0.06), col.lightened(0.06), Vector3.UP)

func _disc_mesh(r: float, sides: int, col: Color, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_disc(st, Vector3(0.0, y, 0.0), r, sides, col, false)
	return _commit(st, true)

func _pad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_disc(st, Vector3.ZERO, 0.32, 9, Color(0.27, 0.41, 0.25), true)
	return _commit(st, true)

func _patch(col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_disc(st, Vector3(0.0, 0.02, 0.0), 0.75, 7, col, false)
	return _commit(st, true)

func _flower(col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color(0.33, 0.43, 0.25)
	var hh := 0.3
	_tri(st, Vector3(-0.012, 0.0, 0.0), Vector3(0.012, 0.0, 0.0), Vector3(0.0, hh, 0.0), stem, stem, stem, Vector3.BACK)
	_tri(st, Vector3(0.0, 0.0, -0.012), Vector3(0.0, 0.0, 0.012), Vector3(0.0, hh, 0.0), stem, stem, stem, Vector3.RIGHT)
	_add_disc(st, Vector3(0.0, hh, 0.0), 0.05, 5, col, false)
	return _commit(st, true)

func _fern() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := Color(0.26, 0.38, 0.21)
	var light := Color(0.36, 0.47, 0.27)
	for i in 7:
		var ang := TAU * float(i) / 7.0 + _rng.randf_range(-0.25, 0.25)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.1
		var ln := _rng.randf_range(0.55, 0.8)
		var mid := dir * ln * 0.45 + Vector3(0.0, ln * 0.4, 0.0)
		var tip := dir * ln + Vector3(0.0, ln * 0.15, 0.0)
		var n := (Vector3.UP * 0.8 + dir * 0.2).normalized()
		_tri(st, Vector3.ZERO, mid + side, tip, dark, light, light, n)
		_tri(st, Vector3.ZERO, tip, mid - side, dark, light, light, n)
	return _commit(st, true)

func _from_primitive(arr: Array, colorize: Callable, jitter: float) -> ArrayMesh:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var offsets := {}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var tri: Array[Vector3] = []
		for j in 3:
			var v := verts[idx[t + j]]
			var key := v.snapped(Vector3.ONE * 0.001)
			if not offsets.has(key):
				offsets[key] = Vector3(_rng.randf_range(-jitter, jitter), _rng.randf_range(-jitter, jitter), _rng.randf_range(-jitter, jitter))
			var off: Vector3 = offsets[key]
			tri.append(v + off)
		var col: Color = colorize.call(verts[idx[t]], verts[idx[t + 1]], verts[idx[t + 2]])
		for v in tri:
			st.set_color(col)
			st.add_vertex(v)
	st.generate_normals()
	return _commit(st, false)

func _rock(col: Color) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.7
	sm.radial_segments = 6
	sm.rings = 3
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y = maxf(verts[i].y, -0.14)
	arr[Mesh.ARRAY_VERTEX] = verts
	var shade := func(_a: Vector3, _b: Vector3, _c: Vector3) -> Color: return col.darkened(_rng.randf_range(0.0, 0.12))
	return _from_primitive(arr, shade, 0.06)

# Unit log: diameter 1, length 1 along local Z.
func _log(side: Color, cap: Color) -> ArrayMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 1.0
	cm.radial_segments = 7
	cm.rings = 1
	var arr := cm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		verts[i] = Vector3(v.x, -v.z, v.y)
	arr[Mesh.ARRAY_VERTEX] = verts
	var shade := func(a: Vector3, b: Vector3, c: Vector3) -> Color:
		if absf(a.z) > 0.49 and absf(b.z) > 0.49 and absf(c.z) > 0.49:
			return cap
		return side.darkened(_rng.randf_range(0.0, 0.1))
	return _from_primitive(arr, shade, 0.03)

func _stump() -> ArrayMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.42
	cm.height = 0.5
	cm.radial_segments = 7
	cm.rings = 1
	var arr := cm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 0.25
	arr[Mesh.ARRAY_VERTEX] = verts
	var bark := Color(0.34, 0.27, 0.20)
	var top := Color(0.52, 0.45, 0.30)
	var shade := func(a: Vector3, b: Vector3, c: Vector3) -> Color:
		if a.y > 0.49 and b.y > 0.49 and c.y > 0.49:
			return top
		return bark.darkened(_rng.randf_range(0.0, 0.1))
	return _from_primitive(arr, shade, 0.03)

# ---------------------------------------------------------------- placement helpers
func _h(p: Vector2) -> float:
	return _ground.surface_height(p)

func _dry_ok(p: Vector2, radius: float, rise: float, min_normal: float) -> bool:
	if _ground.is_water(p):
		return false
	return _ground.placement_ok(p, radius, rise, min_normal, 6)

func _water_near(p: Vector2, d: float) -> bool:
	for i in 8:
		var dir := Vector2.from_angle(TAU * float(i) / 8.0)
		if _ground.is_water(p + dir * d) or _ground.is_water(p + dir * d * 0.5):
			return true
	return false

func _above_water(p: Vector2, margin: float) -> bool:
	return _h(p) > _ground.water_level_at(p) + margin

func _near_tree(p: Vector2, d: float) -> bool:
	for t in _trees:
		if t.distance_squared_to(p) < d * d:
			return true
	return false

func _is_blocked(p: Vector2, r: float) -> bool:
	for b in _blocked:
		if Vector2(b.x, b.y).distance_to(p) < b.z + r:
			return true
	return false

func _cluster(center: Vector2, count: int, spread: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in count:
		out.append(center + Vector2.from_angle(_rng.randf() * TAU) * spread * sqrt(_rng.randf()))
	return out

func _random_point(inner: float, outer: float) -> Vector2:
	var r := sqrt(_rng.randf_range(inner * inner, outer * outer))
	var p := _house + Vector2.from_angle(_rng.randf() * TAU) * r
	return p.clamp(Vector2(-84.0, -84.0), Vector2(84.0, 84.0))

func _upright(s: float) -> Basis:
	return Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))

func _on_normal(p: Vector2, s: Vector3) -> Basis:
	var n := _ground.sample_normal(p).normalized()
	return Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(s)

func _add(cat: String, pos: Vector3, b: Basis, tint := 0.08) -> void:
	var key := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
	var cb: Dictionary = _batches[cat]
	if not cb.has(key):
		cb[key] = []
	var v := _rng.randf_range(1.0 - tint, 1.0 + tint * 0.5)
	cb[key].append([Transform3D(b, pos), Color(v, v * _rng.randf_range(0.97, 1.03), v)])

func _add_box(t: Transform3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = t
	_colliders.add_child(cs)

# Log lying between two points on the ground. Returns false if the terrain does not fit.
func _place_log(cat: String, center: Vector2, dir: Vector2, length: float, radius: float, collide: bool) -> bool:
	var a := center - dir * length * 0.5
	var b := center + dir * length * 0.5
	if not _dry_ok(a, 0.2, 0.4, 0.75) or not _dry_ok(b, 0.2, 0.4, 0.75):
		return false
	if not _above_water(a, 0.05) or not _above_water(b, 0.05):
		return false
	var ha := _h(a)
	var hb := _h(b)
	if absf(ha - hb) > length * 0.12:
		return false
	for i in range(1, 4):
		var t := float(i) / 4.0
		var q := a.lerp(b, t)
		if _ground.is_water(q) or absf(_h(q) - lerpf(ha, hb, t)) > radius * 0.9:
			return false
		if collide and _near_tree(q, 1.4):
			return false
	var a3 := Vector3(a.x, ha, a.y)
	var b3 := Vector3(b.x, hb, b.y)
	var z := (b3 - a3).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	var d := radius * 2.0
	var pos := (a3 + b3) * 0.5 + Vector3(0.0, radius * 0.6, 0.0)
	_add(cat, pos, Basis(x * d, y * d, z * length), 0.06)
	if collide:
		_add_box(Transform3D(Basis(x, y, z), pos), Vector3(d * 0.9, d * 0.9, length))
		_blocked.append(Vector3(center.x, center.y, length * 0.5))
	return true

# ---------------------------------------------------------------- biomes
func _bank_point(pts: PackedVector2Array, near: float, far: float) -> Vector2:
	var lc := _ground.lake_center()
	if _rng.randf() < 0.35 or pts.size() < 2:
		return lc + Vector2.from_angle(_rng.randf() * TAU) * (_ground.lake_radius() + _rng.randf_range(near, far))
	var k := _rng.randi_range(0, pts.size() - 2)
	var seg := pts[k + 1] - pts[k]
	var along := pts[k] + seg * _rng.randf()
	var perp := Vector2(-seg.y, seg.x).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
	return along + perp * (LowPolyGround.RIVER_HALF_WIDTH + _rng.randf_range(near, far))

func _shoreline() -> void:
	var pts := _ground.river_path()
	for i in 80:
		var c := _bank_point(pts, 0.2, 1.6)
		if not _water_near(c, 2.4) or _house.distance_to(c) < 8.0:
			continue
		var reeds := i % 4 != 3
		for p in _cluster(c, _rng.randi_range(6, 13), 1.3):
			if _ground.is_water(p) or not _water_near(p, 1.8) or not _above_water(p, 0.04):
				continue
			if not _ground.placement_ok(p, 0.2, 0.3, 0.75, 4):
				continue
			if reeds:
				_add("reed", Vector3(p.x, _h(p) - 0.05, p.y), _upright(_rng.randf_range(0.75, 1.25)))
			else:
				_add("sedge", Vector3(p.x, _h(p) - 0.03, p.y), _upright(_rng.randf_range(0.8, 1.3)))
		if i % 6 == 0:
			for p in _cluster(c, _rng.randi_range(2, 4), 1.6):
				if not _dry_ok(p, 0.3, 0.4, 0.6) or not _above_water(p, 0.03):
					continue
				var s := _rng.randf_range(0.4, 1.1)
				_add("shore_rock", Vector3(p.x, _h(p) - 0.12 * s, p.y), _on_normal(p, Vector3(s, s * _rng.randf_range(0.6, 0.9), s)))
	var placed := 0
	for i in 60:
		if placed >= 10:
			break
		var c := _bank_point(pts, 0.6, 2.2)
		if not _water_near(c, 2.8) or _house.distance_to(c) < 10.0:
			continue
		if _place_log("driftwood", c, Vector2.from_angle(_rng.randf() * TAU), _rng.randf_range(1.6, 3.0), _rng.randf_range(0.1, 0.17), false):
			placed += 1
	# Sedge further up the bank.
	for i in 50:
		var c := _bank_point(pts, 1.5, 3.5)
		if not _water_near(c, 4.0) or _house.distance_to(c) < 8.0:
			continue
		for p in _cluster(c, _rng.randi_range(5, 10), 1.5):
			if _dry_ok(p, 0.2, 0.3, 0.75) and _above_water(p, 0.08):
				_add("sedge", Vector3(p.x, _h(p) - 0.03, p.y), _upright(_rng.randf_range(0.7, 1.2)))

# Lily pads on the side of the lake opposite to the river inflow.
func _lily_pads() -> void:
	var pts := _ground.river_path()
	var lc := _ground.lake_center()
	var lr := _ground.lake_radius()
	var calm := Vector2.RIGHT
	if pts.size() > 0 and pts[pts.size() - 1].distance_to(lc) > 0.5:
		calm = (lc - pts[pts.size() - 1]).normalized()
	for i in 10:
		var c := lc + Vector2.from_angle(calm.angle() + _rng.randf_range(-0.9, 0.9)) * lr * _rng.randf_range(0.35, 0.8)
		for p in _cluster(c, _rng.randi_range(4, 9), 1.6):
			if not _ground.is_water(p):
				continue
			var wl := _ground.water_level_at(p)
			if _h(p) > wl - 0.25:
				continue
			_add("lily", Vector3(p.x, wl + 0.035, p.y), _upright(_rng.randf_range(0.7, 1.3)), 0.1)
			if _rng.randf() < 0.15:
				_add("lily_flower", Vector3(p.x + 0.08, wl + 0.04, p.y + 0.05), _upright(1.0), 0.04)

# Moss and sedge in damp ground near the water.
func _wet_patches() -> void:
	var pts := _ground.river_path()
	for i in 45:
		var c := _bank_point(pts, 2.0, 5.0)
		if not _water_near(c, 5.5) or _house.distance_to(c) < 8.0:
			continue
		for p in _cluster(c, _rng.randi_range(2, 5), 1.8):
			if _dry_ok(p, 0.6, 0.12, 0.85) and _above_water(p, 0.1):
				var s := _rng.randf_range(0.6, 1.1)
				_add("moss", Vector3(p.x, _h(p) + 0.01, p.y), _on_normal(p, Vector3(s, 1.0, s)), 0.1)
		for p in _cluster(c, _rng.randi_range(3, 6), 1.8):
			if _dry_ok(p, 0.2, 0.3, 0.75) and _above_water(p, 0.08):
				_add("sedge", Vector3(p.x, _h(p) - 0.03, p.y), _upright(_rng.randf_range(0.6, 1.0)))

func _meadows() -> void:
	var cats := ["flower_white", "flower_yellow", "flower_lilac"]
	var made := 0
	for i in 60:
		if made >= 7:
			break
		var c := _random_point(16.0, 62.0)
		if not _dry_ok(c, 3.0, 0.5, 0.9) or _water_near(c, 6.0) or _near_tree(c, 4.0) or _is_blocked(c, 4.0):
			continue
		made += 1
		var main_cat: String = cats[made % 3]
		for p in _cluster(c, _rng.randi_range(30, 50), 4.5):
			if not _dry_ok(p, 0.1, 0.2, 0.8) or _near_tree(p, 0.8):
				continue
			var cat: String = main_cat if _rng.randf() < 0.7 else str(cats[_rng.randi_range(0, 2)])
			_add(cat, Vector3(p.x, _h(p) - 0.02, p.y), _upright(_rng.randf_range(0.7, 1.2)))

# Sparse light flowers in the bright clearing around the cabin.
func _clearing_flowers() -> void:
	for i in 90:
		var p := _random_point(7.5, 12.0)
		if _dry_ok(p, 0.1, 0.2, 0.85) and not _near_tree(p, 0.8):
			_add("flower_white" if _rng.randf() < 0.65 else "flower_yellow", Vector3(p.x, _h(p) - 0.02, p.y), _upright(_rng.randf_range(0.6, 1.0)))

# Ferns in the shade of the deeper forest.
func _ferns() -> void:
	var total := 0
	for t in _trees:
		if total >= 600:
			break
		if _house.distance_to(t) < 22.0 or _rng.randf() > 0.35:
			continue
		for i in _rng.randi_range(2, 5):
			var p := t + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(1.2, 3.0)
			if _dry_ok(p, 0.3, 0.3, 0.75) and not _is_blocked(p, 0.4) and _above_water(p, 0.1):
				_add("fern", Vector3(p.x, _h(p) - 0.03, p.y), _upright(_rng.randf_range(0.7, 1.3)), 0.1)
				total += 1

# Pebble clusters on moderately steep, dry slopes.
func _rocky_slopes() -> void:
	for i in 900:
		var c := _random_point(15.0, 82.0)
		if _ground.is_water(c) or _water_near(c, 3.0):
			continue
		var ny := _ground.sample_normal(c).normalized().y
		if ny < 0.72 or ny > 0.9:
			continue
		for p in _cluster(c, _rng.randi_range(3, 6), 1.2):
			if not _ground.placement_ok(p, 0.15, 0.25, 0.6, 4) or _ground.is_water(p):
				continue
			var s := _rng.randf_range(0.15, 0.4)
			_add("pebble", Vector3(p.x, _h(p) - 0.3 * s, p.y), _on_normal(p, Vector3(s, s * 0.7, s)))

func _fallen_trunks() -> void:
	var placed := 0
	for i in 80:
		if placed >= 6:
			break
		var c := _random_point(25.0, 75.0)
		if _is_blocked(c, 4.0) or _water_near(c, 4.0):
			continue
		if _place_log("trunk", c, Vector2.from_angle(_rng.randf() * TAU), _rng.randf_range(4.0, 6.5), _rng.randf_range(0.22, 0.32), true):
			placed += 1

func _old_stumps() -> void:
	var placed := 0
	for i in 80:
		if placed >= 10:
			break
		var p := _random_point(20.0, 80.0)
		if not _dry_ok(p, 0.5, 0.25, 0.85) or _near_tree(p, 1.5) or _is_blocked(p, 1.0) or _water_near(p, 2.0):
			continue
		var s := _rng.randf_range(0.8, 1.3)
		var pos := Vector3(p.x, _h(p) - 0.05, p.y)
		_add("stump", pos, _upright(s), 0.06)
		var shape := CylinderShape3D.new()
		shape.radius = 0.4 * s
		shape.height = 0.5 * s
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = pos + Vector3(0.0, 0.25 * s, 0.0)
		_colliders.add_child(cs)
		_blocked.append(Vector3(p.x, p.y, 0.6 * s))
		placed += 1

# ---------------------------------------------------------------- build
func _build_multimeshes() -> void:
	for cat in _batches:
		var def: Dictionary = _defs[cat]
		var cb: Dictionary = _batches[cat]
		for key in cb:
			var items: Array = cb[key]
			var center := Vector3((float(key.x) + 0.5) * CHUNK, 0.0, (float(key.y) + 0.5) * CHUNK)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = def["mesh"]
			mm.instance_count = items.size()
			for i in items.size():
				var t: Transform3D = items[i][0]
				t.origin -= center
				mm.set_instance_transform(i, t)
				mm.set_instance_color(i, items[i][1])
			var mi := MultiMeshInstance3D.new()
			mi.name = "%s_%d_%d" % [cat, key.x, key.y]
			mi.multimesh = mm
			mi.position = center
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(def["shadow"]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = float(def["range"])
			mi.visibility_range_end_margin = 6.0
			add_child(mi)
