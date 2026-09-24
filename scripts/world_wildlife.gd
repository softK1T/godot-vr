extends Node
class_name WorldWildlife
## Ambient low-poly wildlife: bird flocks that sit and take off when the player
## comes close, fish schools that stay inside the lake, and a few deer on distant
## meadows that graze, wander and run away. No hunting or combat.
## Each group only runs while the camera is near it; far groups are hidden and idle.
const SEED := 5521
const BIRD_RANGE := 50.0
const FISH_RANGE := 45.0
const DEER_RANGE := 75.0
const BIRD_SCARE := 7.0
const FISH_SCARE := 4.5
const DEER_SCARE := 16.0
const BOUNDS := 82.0

class Bird:
	var node: Node3D
	var wing_l: Node3D
	var wing_r: Node3D
	var flying := false
	var vel := Vector3.ZERO
	var timer := 0.0
	var air_time := 0.0
	var target := Vector3.ZERO
	var phase := 0.0

class Flock:
	var root: Node3D
	var birds: Array[Bird] = []
	var center := Vector2.ZERO

class School:
	var root: Node3D
	var fish: Array[Node3D] = []
	var offsets: Array[Vector3] = []
	var center := Vector3.ZERO
	var target := Vector3.ZERO
	var speed := 0.8

class Deer:
	var node: Node3D
	var neck: Node3D
	var legs: Array[Node3D] = []
	var home := Vector2.ZERO
	var target := Vector2.ZERO
	var state := 0
	var timer := 0.0
	var yaw := 0.0
	var speed := 0.0
	var gait := 0.0
	var flee_dir := Vector2.ZERO

var _rng := RandomNumberGenerator.new()
var _ground: LowPolyGround
var _house := Vector2.ZERO
var _flocks: Array[Flock] = []
var _schools: Array[School] = []
var _deer: Array[Deer] = []
var _bird_body: ArrayMesh
var _bird_wing: ArrayMesh
var _fish_mesh: ArrayMesh
var _time := 0.0
var _ready_done := false

func _ready() -> void:
	call_deferred("_spawn")

# ---------------------------------------------------------------- meshes
func _mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, n: Vector3) -> void:
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)

func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD], [Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT], [Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n * h
		var du := u * h
		var dv := v * h
		var shade := col.darkened(0.18) if n == Vector3.DOWN else (col.lightened(0.04) if n == Vector3.UP else col)
		_tri(st, o - du - dv, o + du - dv, o + du + dv, shade, n)
		_tri(st, o - du - dv, o + du + dv, o - du + dv, shade, n)

func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

func _end(st: SurfaceTool) -> ArrayMesh:
	var m := st.commit()
	m.surface_set_material(0, _mat())
	return m

func _build_meshes() -> void:
	var st := _begin()
	_box(st, Vector3(0.0, 0.07, 0.0), Vector3(0.11, 0.1, 0.2), Color(0.38, 0.33, 0.28))
	_box(st, Vector3(0.0, 0.13, 0.11), Vector3(0.08, 0.08, 0.08), Color(0.30, 0.27, 0.24))
	_box(st, Vector3(0.0, 0.13, 0.17), Vector3(0.02, 0.02, 0.04), Color(0.55, 0.46, 0.26))
	_box(st, Vector3(0.0, 0.08, -0.13), Vector3(0.08, 0.02, 0.1), Color(0.32, 0.28, 0.24))
	_bird_body = _end(st)
	st = _begin()
	var wc := Color(0.34, 0.30, 0.26)
	_tri(st, Vector3(0.0, 0.0, -0.07), Vector3(0.0, 0.0, 0.06), Vector3(0.1, 0.0, 0.04), wc, Vector3.UP)
	_tri(st, Vector3(0.0, 0.0, -0.07), Vector3(0.1, 0.0, 0.04), Vector3(0.2, 0.0, -0.03), wc, Vector3.UP)
	_bird_wing = _end(st)
	st = _begin()
	_box(st, Vector3.ZERO, Vector3(0.05, 0.09, 0.26), Color(0.44, 0.47, 0.45))
	_box(st, Vector3(0.0, 0.03, 0.0), Vector3(0.052, 0.03, 0.22), Color(0.30, 0.34, 0.32))
	_box(st, Vector3(0.0, 0.0, -0.16), Vector3(0.01, 0.08, 0.07), Color(0.38, 0.41, 0.40))
	_fish_mesh = _end(st)

func _mesh_node(parent: Node, mesh: Mesh, shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# ---------------------------------------------------------------- helpers
func _cam() -> Vector3:
	var c := get_viewport().get_camera_3d()
	if c == null:
		return Vector3(INF, INF, INF)
	return c.global_position

func _flat_dist(a: Vector3, b: Vector2) -> float:
	return Vector2(a.x, a.z).distance_to(b)

func _water_near(p: Vector2, d: float) -> bool:
	for i in 8:
		var dir := Vector2.from_angle(TAU * float(i) / 8.0)
		if _ground.is_water(p + dir * d) or _ground.is_water(p + dir * d * 0.5):
			return true
	return false

func _in_bounds(p: Vector2) -> bool:
	return absf(p.x) < BOUNDS and absf(p.y) < BOUNDS

func _land_ok(p: Vector2, radius: float, min_normal: float) -> bool:
	if not _in_bounds(p) or _ground.is_water(p):
		return false
	return _ground.placement_ok(p, radius, 0.5, min_normal, 6)

func _spot(inner: float, outer: float, radius: float, min_normal: float, around: Vector2) -> Vector2:
	for i in 40:
		var r := sqrt(_rng.randf_range(inner * inner, outer * outer))
		var p := around + Vector2.from_angle(_rng.randf() * TAU) * r
		if _house.distance_to(p) < 9.0 or _water_near(p, 3.0):
			continue
		if _land_ok(p, radius, min_normal):
			return p
	return Vector2(INF, INF)

func _gpos(p: Vector2) -> Vector3:
	return Vector3(p.x, _ground.surface_height(p), p.y)

func _fish_ok(p: Vector2) -> bool:
	return _ground.is_water(p) and _ground.surface_height(p) < _ground.water_level_at(p) - 0.6

# ---------------------------------------------------------------- spawn
func _spawn() -> void:
	_ground = get_node_or_null("../Ground") as LowPolyGround
	if _ground == null:
		return
	_rng.seed = SEED
	var house := get_node_or_null("../House") as Node3D
	if house:
		_house = Vector2(house.global_position.x, house.global_position.z)
	_build_meshes()
	for i in 5:
		var c := _spot(12.0, 60.0, 1.5, 0.85, _house)
		if c.x != INF:
			_spawn_flock(c)
	for i in 3:
		_spawn_school()
	var count := _rng.randi_range(2, 4)
	for i in 30:
		if _deer.size() >= count:
			break
		var c := _spot(45.0, 80.0, 3.0, 0.88, _house)
		if c.x == INF:
			continue
		var far_enough := true
		for d in _deer:
			if d.home.distance_to(c) < 18.0:
				far_enough = false
		if far_enough:
			_spawn_deer(c)
	_ready_done = true

func _spawn_flock(c: Vector2) -> void:
	var f := Flock.new()
	f.center = c
	f.root = Node3D.new()
	f.root.name = "BirdFlock"
	add_child(f.root)
	for i in _rng.randi_range(4, 8):
		var p := c + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.2, 1.5)
		if not _land_ok(p, 0.1, 0.7):
			p = c
		var b := Bird.new()
		b.node = Node3D.new()
		f.root.add_child(b.node)
		_mesh_node(b.node, _bird_body, false)
		b.wing_l = Node3D.new()
		b.wing_l.position = Vector3(0.05, 0.09, 0.0)
		b.node.add_child(b.wing_l)
		_mesh_node(b.wing_l, _bird_wing, false)
		b.wing_r = Node3D.new()
		b.wing_r.position = Vector3(-0.05, 0.09, 0.0)
		b.node.add_child(b.wing_r)
		_mesh_node(b.wing_r, _bird_wing, false).scale = Vector3(-1.0, 1.0, 1.0)
		b.node.global_position = _gpos(p)
		b.node.rotation.y = _rng.randf() * TAU
		b.node.scale = Vector3.ONE * _rng.randf_range(0.9, 1.15)
		b.timer = _rng.randf_range(0.5, 3.0)
		_fold(b)
		f.birds.append(b)
	_flocks.append(f)

func _spawn_school() -> void:
	var lc := _ground.lake_center()
	var lr := _ground.lake_radius()
	var c := Vector2(INF, INF)
	for i in 40:
		var p := lc + Vector2.from_angle(_rng.randf() * TAU) * lr * sqrt(_rng.randf()) * 0.75
		if _fish_ok(p):
			c = p
			break
	if c.x == INF:
		return
	var s := School.new()
	s.root = Node3D.new()
	s.root.name = "FishSchool"
	add_child(s.root)
	s.center = Vector3(c.x, _ground.water_level_at(c) - 0.4, c.y)
	s.target = s.center
	for i in _rng.randi_range(6, 9):
		var fish := _mesh_node(s.root, _fish_mesh, false)
		fish.scale = Vector3.ONE * _rng.randf_range(0.8, 1.3)
		var off := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.12, 0.12), _rng.randf_range(-1.0, 1.0))
		fish.global_position = s.center + off
		s.fish.append(fish)
		s.offsets.append(off)
	_schools.append(s)

func _spawn_deer(c: Vector2) -> void:
	var d := Deer.new()
	d.home = c
	d.target = c
	d.node = Node3D.new()
	d.node.name = "Deer"
	add_child(d.node)
	var fur := Color(0.50, 0.37, 0.25)
	var light := Color(0.70, 0.61, 0.47)
	var dark := Color(0.40, 0.30, 0.21)
	var st := _begin()
	_box(st, Vector3(0.0, 1.0, 0.0), Vector3(0.42, 0.46, 1.05), fur)
	_box(st, Vector3(0.0, 0.76, 0.0), Vector3(0.36, 0.1, 0.8), light)
	_box(st, Vector3(0.0, 1.12, -0.54), Vector3(0.1, 0.14, 0.06), light)
	_mesh_node(d.node, _end(st), true)
	d.neck = Node3D.new()
	d.neck.position = Vector3(0.0, 1.12, 0.42)
	d.node.add_child(d.neck)
	st = _begin()
	_box(st, Vector3(0.0, 0.24, 0.08), Vector3(0.18, 0.52, 0.2), fur)
	_box(st, Vector3(0.0, 0.5, 0.22), Vector3(0.2, 0.2, 0.36), fur)
	_box(st, Vector3(0.0, 0.47, 0.42), Vector3(0.1, 0.08, 0.08), Color(0.22, 0.19, 0.17))
	_box(st, Vector3(0.08, 0.64, 0.12), Vector3(0.06, 0.14, 0.04), dark)
	_box(st, Vector3(-0.08, 0.64, 0.12), Vector3(0.06, 0.14, 0.04), dark)
	_mesh_node(d.neck, _end(st), true)
	st = _begin()
	_box(st, Vector3(0.0, -0.41, 0.0), Vector3(0.09, 0.82, 0.09), dark)
	var leg_mesh := _end(st)
	for hip in [Vector3(0.14, 0.82, 0.4), Vector3(-0.14, 0.82, 0.4), Vector3(0.14, 0.82, -0.4), Vector3(-0.14, 0.82, -0.4)]:
		var leg := Node3D.new()
		leg.position = hip
		d.node.add_child(leg)
		_mesh_node(leg, leg_mesh, true)
		d.legs.append(leg)
	d.node.global_position = _gpos(c)
	d.yaw = _rng.randf() * TAU
	d.node.rotation.y = d.yaw
	d.node.scale = Vector3.ONE * _rng.randf_range(0.9, 1.1)
	d.timer = _rng.randf_range(3.0, 8.0)
	_deer.append(d)

# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	if not _ready_done:
		return
	_time += delta
	var cam := _cam()
	if cam.x == INF:
		return
	for f in _flocks:
		_update_flock(f, cam, delta)
	for s in _schools:
		_update_school(s, cam, delta)
	for d in _deer:
		_update_deer(d, cam, delta)

func _fold(b: Bird) -> void:
	b.wing_l.rotation.z = 0.0
	b.wing_r.rotation.z = 0.0
	b.wing_l.scale = Vector3(0.35, 1.0, 1.0)
	b.wing_r.scale = Vector3(0.35, 1.0, 1.0)

func _update_flock(f: Flock, cam: Vector3, delta: float) -> void:
	var any_flying := false
	for b in f.birds:
		if b.flying:
			any_flying = true
	var near := _flat_dist(cam, f.center) < BIRD_RANGE
	f.root.visible = near or any_flying
	if not f.root.visible:
		return
	if not any_flying:
		var scared := false
		for b in f.birds:
			if b.node.global_position.distance_to(cam) < BIRD_SCARE:
				scared = true
		if scared:
			_take_off(f, cam)
			return
	for b in f.birds:
		if b.flying:
			_fly(b, delta)
		else:
			_sit(b, delta)

func _take_off(f: Flock, cam: Vector3) -> void:
	var away := Vector2(f.center.x - cam.x, f.center.y - cam.z).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var landing := _spot(20.0, 38.0, 1.5, 0.85, f.center + away * 12.0)
	if landing.x == INF:
		landing = f.center
	f.center = landing
	for b in f.birds:
		var p := landing + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.2, 1.5)
		if not _land_ok(p, 0.1, 0.7):
			p = landing
		b.target = _gpos(p)
		b.flying = true
		b.air_time = 0.0
		b.phase = _rng.randf() * TAU
		b.vel = Vector3(away.x * 2.5, 3.5 + _rng.randf(), away.y * 2.5) + Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1))
		b.wing_l.scale = Vector3.ONE
		b.wing_r.scale = Vector3.ONE

func _sit(b: Bird, delta: float) -> void:
	b.timer -= delta
	if b.timer > 0.0:
		return
	b.timer = _rng.randf_range(1.0, 4.0)
	var pos := b.node.global_position
	var p := Vector2(pos.x, pos.z) + Vector2.from_angle(_rng.randf() * TAU) * 0.18
	if _land_ok(p, 0.05, 0.7):
		b.node.global_position = _gpos(p)
	b.node.rotation.y += _rng.randf_range(-1.2, 1.2)

func _fly(b: Bird, delta: float) -> void:
	b.air_time += delta
	b.phase += delta * 18.0
	var flap := sin(b.phase) * 0.85
	b.wing_l.rotation.z = flap
	b.wing_r.rotation.z = -flap
	var pos := b.node.global_position
	var to := b.target - pos
	var hdist := Vector2(to.x, to.z).length()
	if b.air_time > 1.2:
		var goal := b.target + Vector3(0.0, 7.0 if hdist > 6.0 else 0.0, 0.0)
		var speed := clampf(hdist, 1.5, 6.0)
		b.vel = b.vel.lerp((goal - pos).normalized() * speed, clampf(delta * 1.5, 0.0, 1.0))
	pos += b.vel * delta
	var floor_y := _ground.surface_height(Vector2(pos.x, pos.z))
	if b.air_time > 1.2 and hdist < 0.4 and pos.y - floor_y < 0.3:
		b.flying = false
		b.node.global_position = b.target
		b.node.rotation = Vector3(0.0, b.node.rotation.y, 0.0)
		b.timer = _rng.randf_range(1.0, 3.0)
		_fold(b)
		return
	pos.y = maxf(pos.y, floor_y + 0.05)
	b.node.global_position = pos
	if Vector2(b.vel.x, b.vel.z).length() > 0.1:
		b.node.rotation.y = lerp_angle(b.node.rotation.y, atan2(b.vel.x, b.vel.z), clampf(delta * 6.0, 0.0, 1.0))

func _new_fish_target(s: School) -> void:
	var lc := _ground.lake_center()
	var lr := _ground.lake_radius()
	for i in 20:
		var p := lc + Vector2.from_angle(_rng.randf() * TAU) * lr * sqrt(_rng.randf()) * 0.8
		if _fish_ok(p):
			s.target = Vector3(p.x, _ground.water_level_at(p) - 0.4, p.y)
			s.speed = _rng.randf_range(0.5, 1.0)
			return

func _update_school(s: School, cam: Vector3, delta: float) -> void:
	s.root.visible = _flat_dist(cam, Vector2(s.center.x, s.center.z)) < FISH_RANGE
	if not s.root.visible:
		return
	var c2 := Vector2(s.center.x, s.center.z)
	var cam2 := Vector2(cam.x, cam.z)
	if c2.distance_to(cam2) < FISH_SCARE:
		var away := (c2 - cam2).normalized() * 5.0
		if _fish_ok(c2 + away):
			s.target = Vector3(c2.x + away.x, s.center.y, c2.y + away.y)
			s.speed = 2.5
	var to := s.target - s.center
	if to.length() < 0.5:
		_new_fish_target(s)
	else:
		var next := s.center + to.normalized() * s.speed * delta
		if _fish_ok(Vector2(next.x, next.z)):
			s.center = next
		else:
			_new_fish_target(s)
	for i in s.fish.size():
		var fish := s.fish[i]
		var off := s.offsets[i]
		var wobble := Vector3(sin(_time * 0.7 + float(i)), 0.0, cos(_time * 0.6 + float(i) * 1.7)) * 0.35
		var goal := s.center + off + wobble
		var g2 := Vector2(goal.x, goal.z)
		if not _fish_ok(g2):
			goal = s.center
			g2 = Vector2(goal.x, goal.z)
		var top := _ground.water_level_at(g2) - 0.22
		var bottom := _ground.surface_height(g2) + 0.15
		goal.y = clampf(goal.y, minf(bottom, top), top)
		var prev := fish.global_position
		var np := prev.lerp(goal, clampf(delta * 1.8, 0.0, 1.0))
		fish.global_position = np
		var mv := np - prev
		if Vector2(mv.x, mv.z).length() > 0.0005:
			fish.rotation.y = lerp_angle(fish.rotation.y, atan2(mv.x, mv.z), clampf(delta * 5.0, 0.0, 1.0))
		fish.rotation.z = sin(_time * 9.0 + float(i)) * 0.12

func _deer_ok(p: Vector2) -> bool:
	if _house.distance_to(p) < 14.0:
		return false
	return _land_ok(p, 0.5, 0.8)

func _update_deer(d: Deer, cam: Vector3, delta: float) -> void:
	var pos := d.node.global_position
	var p2 := Vector2(pos.x, pos.z)
	var cam_d := _flat_dist(cam, p2)
	d.node.visible = cam_d < DEER_RANGE
	if not d.node.visible:
		return
	if cam_d < DEER_SCARE and d.state != 2:
		d.state = 2
		d.timer = _rng.randf_range(4.0, 6.0)
		d.flee_dir = (p2 - Vector2(cam.x, cam.z)).normalized().rotated(_rng.randf_range(-0.5, 0.5))
	d.timer -= delta
	var dir := Vector2.ZERO
	var want_speed := 0.0
	match d.state:
		0:
			if d.timer <= 0.0:
				var t := d.home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(3.0, 12.0)
				if _deer_ok(t):
					d.target = t
					d.state = 1
				d.timer = _rng.randf_range(4.0, 9.0)
		1:
			var to := d.target - p2
			if to.length() < 0.6 or d.timer <= -20.0:
				d.state = 0
				d.timer = _rng.randf_range(4.0, 9.0)
			else:
				dir = to.normalized()
				want_speed = 1.1
		2:
			dir = d.flee_dir
			want_speed = 6.5
			if d.timer <= 0.0:
				d.state = 0
				d.timer = _rng.randf_range(3.0, 6.0)
				if _deer_ok(p2):
					d.home = p2
	d.speed = lerpf(d.speed, want_speed, clampf(delta * 3.0, 0.0, 1.0))
	if d.speed > 0.05 and dir != Vector2.ZERO:
		var step := dir * d.speed * delta
		var moved := false
		for k in 5:
			var np := p2 + step.rotated(float(k) * 0.6 * (1.0 if k % 2 == 0 else -1.0))
			if _deer_ok(np):
				dir = (np - p2).normalized()
				if d.state == 2:
					d.flee_dir = dir
				p2 = np
				moved = true
				break
		if not moved and d.state == 1:
			d.state = 0
		d.yaw = lerp_angle(d.yaw, atan2(dir.x, dir.y), clampf(delta * 4.0, 0.0, 1.0))
		d.node.global_position = _gpos(p2)
		d.node.rotation.y = d.yaw
	d.gait += delta * d.speed * 3.2
	var swing := clampf(d.speed / 1.1, 0.0, 1.0) * (0.35 if d.speed < 2.0 else 0.6)
	for i in d.legs.size():
		var ph := d.gait + (PI if i == 1 or i == 2 else 0.0)
		d.legs[i].rotation.x = sin(ph) * swing
	var head := 1.3 if d.state == 0 and d.timer < 3.5 else (-0.25 if d.state == 2 else 0.0)
	d.neck.rotation.x = lerpf(d.neck.rotation.x, head, clampf(delta * 2.0, 0.0, 1.0))
