@tool
extends StaticBody3D
class_name LowPolyGround

@export var rebuild := false:
	set(value):
		rebuild = false
		if value: build()
@export_range(60.0, 240.0, 2.0) var ground_size := 180.0
@export_range(0.65, 3.0, 0.05) var polygon_size := 1.1
@export_range(0.0, 2.5, 0.01) var relief_depth := 1.45
@export var seed_value := 7351
@onready var mesh_instance: MeshInstance3D = $Mesh
var _weather_material: ShaderMaterial

func set_wetness(amount: float) -> void:
	if _weather_material != null:
		_weather_material.set_shader_parameter("wetness", clampf(amount, 0.0, 1.0))


func _ready() -> void:
	build()
	_weather_material = ShaderMaterial.new()
	_weather_material.shader = preload("res://shaders/weather_ground.gdshader")
	mesh_instance.material_override = _weather_material
	set_wetness(0.0)
func build() -> void:
	if not is_instance_valid(mesh_instance): mesh_instance = get_node_or_null("Mesh") as MeshInstance3D
	if not mesh_instance:
		return
	var terrain_mesh := _create_ground_mesh()
	mesh_instance.mesh = terrain_mesh
	# Player, harvesting and building now follow the same faceted terrain that is visible.
	var collision := get_node_or_null("Collision") as CollisionShape3D
	if collision:
		collision.shape = terrain_mesh.create_trimesh_shape()

func sample_height(world_xz: Vector2) -> float:
	return _height_at(world_xz)

func surface_height(world_xz: Vector2) -> float:
	# Query the actual triangulated collision, not only the height formula. This
	# matters because the visible ground is made from large flat polygon faces.
	if not is_inside_tree():
		return sample_height(world_xz)
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(world_xz.x, 60.0, world_xz.y),
		Vector3(world_xz.x, -30.0, world_xz.y),
		collision_layer
	)
	query.collide_with_areas = false
	var excluded: Array[RID] = []
	for attempt in 8:
		query.exclude = excluded
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		if hit.get("collider") == self:
			return (hit.position as Vector3).y
		var other := hit.get("collider") as CollisionObject3D
		if other == null:
			break
		excluded.append(other.get_rid())
	return sample_height(world_xz)

func surface_position(world_xz: Vector2, offset := 0.0) -> Vector3:
	return Vector3(world_xz.x, surface_height(world_xz) + offset, world_xz.y)

func sample_normal(world_xz: Vector2) -> Vector3:
	var step := polygon_size * 0.35
	var left := _height_at(world_xz - Vector2(step, 0.0))
	var right := _height_at(world_xz + Vector2(step, 0.0))
	var back := _height_at(world_xz - Vector2(0.0, step))
	var front := _height_at(world_xz + Vector2(0.0, step))
	return Vector3(left - right, step * 2.0, back - front).normalized()

func _create_ground_mesh() -> ArrayMesh:
	var vertices:=PackedVector3Array(); var normals:=PackedVector3Array(); var colors:=PackedColorArray(); var indices:=PackedInt32Array()
	var cells:=int(ceil(ground_size/polygon_size)); var half:=cells*polygon_size*.5
	var points:=PackedVector3Array(); points.resize((cells+1)*(cells+1))
	# Shared vertices are strongly jittered in X/Z. This removes the visible
	# square grid while keeping neighbouring triangles welded without cracks.
	for z in range(cells+1):
		for x in range(cells+1):
			var edge:=x==0 or z==0 or x==cells or z==cells
			var jitter_x:=0.0 if edge else (_hash(Vector2(x*7+13,z*11-5))-.5)*polygon_size*.78
			var jitter_z:=0.0 if edge else (_hash(Vector2(x*17-8,z*5+29))-.5)*polygon_size*.78
			# Offset alternating rows so long straight lines no longer continue.
			var stagger:=0.0 if edge else (polygon_size*.22 if z%2==1 else -polygon_size*.22)
			var px:=-half+x*polygon_size+jitter_x+stagger
			var pz:=-half+z*polygon_size+jitter_z
			points[z*(cells+1)+x]=Vector3(px,_height_at(Vector2(px,pz)),pz)
	for z in range(cells):
		for x in range(cells):
			var p00:=points[z*(cells+1)+x]; var p10:=points[z*(cells+1)+x+1]
			var p01:=points[(z+1)*(cells+1)+x]; var p11:=points[(z+1)*(cells+1)+x+1]
			var pattern:=_hash(Vector2(x*23+3,z*19-7))
			# Some cells receive an off-centre fifth vertex. Combined with random
			# diagonals this creates triangles of many sizes and silhouettes.
			if pattern>.70:
				var center:=(p00+p10+p01+p11)*.25
				center.x+=(_hash(Vector2(x*31,z*37))-.5)*polygon_size*.28
				center.z+=(_hash(Vector2(x*41,z*43))-.5)*polygon_size*.28
				center.y=_height_at(Vector2(center.x,center.z))
				_add_face(vertices,normals,colors,indices,p00,center,p10,x,z,0)
				_add_face(vertices,normals,colors,indices,p10,center,p11,x,z,1)
				_add_face(vertices,normals,colors,indices,p11,center,p01,x,z,2)
				_add_face(vertices,normals,colors,indices,p01,center,p00,x,z,3)
			elif pattern>.35:
				_add_face(vertices,normals,colors,indices,p00,p11,p10,x,z,0); _add_face(vertices,normals,colors,indices,p00,p01,p11,x,z,1)
			else:
				_add_face(vertices,normals,colors,indices,p00,p01,p10,x,z,0); _add_face(vertices,normals,colors,indices,p10,p01,p11,x,z,1)
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); return mesh

func _add_face(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,idx: PackedInt32Array,a: Vector3,b: Vector3,d: Vector3,x: int,z: int,t: int)->void:
	var normal:=(b-a).cross(d-a).normalized()
	# Godot treats the opposite winding as the visible front face. Keep the
	# vertices clockwise when viewed from above, but preserve upward normals.
	if normal.y>0: var swap:=b; b=d; d=swap
	normal=(b-a).cross(d-a).normalized()
	if normal.y<0: normal=-normal
	var center:=(a+b+d)/3.0; var color:=_face_color(Vector2(center.x,center.z),x,z,t,normal.y); var start:=v.size()
	v.append(a);v.append(b);v.append(d);n.append(normal);n.append(normal);n.append(normal);c.append(color);c.append(color);c.append(color);idx.append(start);idx.append(start+1);idx.append(start+2)

const LAKE_CENTER := Vector2(44.0, 40.0)
const LAKE_RADIUS := 13.0
const LAKE_LEVEL := -2.25
const RIVER_SOURCE_LEVEL := 2.4
const RIVER_HALF_WIDTH := 2.6
const RIVER_CONTROL := [Vector2(-98, 34), Vector2(-78, 46), Vector2(-58, 39), Vector2(-40, 52), Vector2(-21, 60), Vector2(-2, 57), Vector2(16, 64), Vector2(31, 55), Vector2(42, 43)]
var _river_pts := PackedVector2Array()
var _river_acc := PackedFloat32Array()
var _river_min := Vector2.ZERO
var _river_max := Vector2.ZERO

func lake_center() -> Vector2: return LAKE_CENTER
func lake_radius() -> float: return LAKE_RADIUS
func lake_level() -> float: return LAKE_LEVEL
func river_path() -> PackedVector2Array:
	if _river_pts.is_empty(): _build_river()
	return _river_pts
func _build_river() -> void:
	_river_pts = PackedVector2Array(); _river_acc = PackedFloat32Array()
	var c: Array = RIVER_CONTROL
	for i in range(c.size() - 1):
		var p0: Vector2 = c[maxi(i - 1, 0)]; var p1: Vector2 = c[i]; var p2: Vector2 = c[i + 1]; var p3: Vector2 = c[mini(i + 2, c.size() - 1)]
		for s in 6:
			var t := float(s) / 6.0; var t2 := t * t; var t3 := t2 * t
			_river_pts.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	_river_pts.append(c[c.size() - 1])
	var total := 0.0; _river_acc.append(0.0)
	for i in range(1, _river_pts.size()):
		total += _river_pts[i].distance_to(_river_pts[i - 1]); _river_acc.append(total)
	for i in _river_acc.size(): _river_acc[i] /= total
	_river_min = _river_pts[0]; _river_max = _river_pts[0]
	for q in _river_pts:
		_river_min = Vector2(minf(_river_min.x, q.x), minf(_river_min.y, q.y)); _river_max = Vector2(maxf(_river_max.x, q.x), maxf(_river_max.y, q.y))
func river_info(p: Vector2) -> Vector2:
	if _river_pts.is_empty(): _build_river()
	if p.x < _river_min.x - 30.0 or p.x > _river_max.x + 30.0 or p.y < _river_min.y - 30.0 or p.y > _river_max.y + 30.0: return Vector2(INF, 0.0)
	var best := INF; var bt := 0.0
	for i in range(_river_pts.size() - 1):
		var a := _river_pts[i]; var d := _river_pts[i + 1] - a
		var r := clampf((p - a).dot(d) / maxf(d.length_squared(), .0001), 0.0, 1.0)
		var dist := p.distance_to(a + d * r)
		if dist < best: best = dist; bt = lerpf(_river_acc[i], _river_acc[i + 1], r)
	return Vector2(best, bt)
func river_level(t: float) -> float: return lerpf(RIVER_SOURCE_LEVEL, LAKE_LEVEL, clampf(t, 0.0, 1.0))
func water_level_at(p: Vector2) -> float:
	if p.distance_to(LAKE_CENTER) < LAKE_RADIUS + 1.0: return LAKE_LEVEL
	var info := river_info(p)
	if info.x < RIVER_HALF_WIDTH + 0.6: return river_level(info.y)
	return -INF
func is_water(p: Vector2) -> bool:
	var w := water_level_at(p)
	return w > -1000.0 and _height_at(p) < w - 0.03
func shore_factor(p: Vector2) -> float:
	var lake := 1.0 - smoothstep(LAKE_RADIUS, LAKE_RADIUS + 4.5, p.distance_to(LAKE_CENTER))
	var river := 1.0 - smoothstep(RIVER_HALF_WIDTH + 0.8, RIVER_HALF_WIDTH + 4.5, river_info(p).x)
	return maxf(lake, river)
# Placement rules per object type: [footprint radius, max height difference
# inside the footprint, minimum surface normal (1 = flat)]. The footprint is
# the space the visual really occupies, so a tree cannot stand on a small
# level spot while its trunk or crown cuts into the neighbouring hillside.
const PLACEMENT := {
	"tree": [2.4, 0.85, 0.90],
	"rock": [1.4, 0.55, 0.82],
	"bush": [1.1, 0.40, 0.87],
	"mushroom": [0.7, 0.28, 0.87],
	"grass": [0.6, 0.30, 0.83],
}
func can_place(p: Vector2, kind: String) -> bool:
	var rule: Array = PLACEMENT.get(kind, PLACEMENT["grass"])
	return placement_ok(p, float(rule[0]), float(rule[1]), float(rule[2]), 4 if kind == "grass" else 8)
func placement_ok(p: Vector2, radius: float, max_rise: float, min_normal: float, samples := 8) -> bool:
	if sample_normal(p).y < min_normal: return false
	var h0 := _height_at(p)
	for ring in [radius * 0.5, radius]:
		var limit: float = max_rise * (float(ring) / radius)
		for i in samples:
			var a := TAU * (float(i) + (0.5 if ring < radius else 0.0)) / float(samples)
			var q := p + Vector2(cos(a), sin(a)) * float(ring)
			# Rising ground buries the object, falling ground leaves it floating.
			if absf(_height_at(q) - h0) > limit: return false
			if ring == radius and sample_normal(q).y < min_normal - 0.06: return false
	return true

func tree_allowed(p: Vector2) -> bool:
	# Keep a wide open strip along the river and lake shore. A few lone trees
	# may still appear farther than 4 m from the water so banks do not look bald.
	var d := minf(river_info(p).x - RIVER_HALF_WIDTH, p.distance_to(LAKE_CENTER) - LAKE_RADIUS)
	if d > 12.0: return true
	if d < 4.0: return false
	return _hash(floor(p / 3.0) + Vector2(71.0, 29.0)) < 0.04 + 0.14 * smoothstep(4.0, 12.0, d)
func terrain_zone(p: Vector2) -> String:
	if is_water(p): return "water"
	var h := _height_at(p); var n := sample_normal(p).y
	if h > 3.2 or n < .82: return "rock"
	if h < -.9: return "lowland"
	return "meadow"

func _height_at(p: Vector2)->float:
	var broad := (_value_noise(p, 44.0, 11.0) - .5) * 7.0
	var rolling := (_value_noise(p + Vector2(31.7, -18.4), 17.0, 37.0) - .5) * 3.0
	var detail := (_value_noise(p + Vector2(-9.3, 22.8), 5.0, 73.0) - .5) * .7
	var ridge := pow(_value_noise(p + Vector2(47, 13), 30.0, 109.0), 3.0) * 6.0
	var edge := smoothstep(60.0, 90.0, p.length()) * 10.0
	var h := broad + rolling + detail + ridge + edge - 1.2
	# River: first a wide valley, then a bed tied to the water level so the
	# water ribbon always sits between two banks and never floats or breaks.
	var info := river_info(p)
	if info.x < 30.0:
		var w := river_level(info.y)
		h = lerpf(h, minf(h, w + 1.2), 1.0 - smoothstep(7.0, 24.0, info.x))
		var bed := w + .35 - 1.5 * (1.0 - smoothstep(0.0, 3.2, info.x))
		h = lerpf(h, bed, 1.0 - smoothstep(3.4, 9.0, info.x))
	var ld := p.distance_to(LAKE_CENTER)
	if ld < LAKE_RADIUS + 26.0:
		h = lerpf(h, minf(h, LAKE_LEVEL + 1.4), 1.0 - smoothstep(LAKE_RADIUS + 4.0, LAKE_RADIUS + 22.0, ld))
		var lbed := LAKE_LEVEL + .4 - 3.4 * (1.0 - smoothstep(0.0, LAKE_RADIUS - 1.5, ld))
		h = lerpf(h, lbed, 1.0 - smoothstep(LAKE_RADIUS, LAKE_RADIUS + 7.0, ld))
	return lerpf(h, 0.0, _protected_flatten(p))

func _value_noise(p: Vector2, scale: float, salt: float)->float:
	var q: Vector2 = p / scale
	var cell := Vector2(floorf(q.x), floorf(q.y))
	var f: Vector2 = q - cell
	f = Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	var salt_offset := Vector2(salt * 1.731, salt * -2.417)
	var a := _hash(cell + salt_offset)
	var b := _hash(cell + Vector2(1.0, 0.0) + salt_offset)
	var c := _hash(cell + Vector2(0.0, 1.0) + salt_offset)
	var d := _hash(cell + Vector2(1.0, 1.0) + salt_offset)
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)

func _face_color(p: Vector2,x: int,z: int,t: int,upward: float)->Color:
	var coarse:=_hash(Vector2(floor(p.x/7.0),floor(p.y/7.0))); var face:=_hash(Vector2(x*2+t,z*3-t))
	var result:=Color(.22,.33,.20).lerp(Color(.29,.41,.25),smoothstep(.18,.72,coarse))
	if face>.72: result=result.lerp(Color(.33,.45,.26),.38)
	elif face<.17: result=result.lerp(Color(.25,.36,.22),.46)
	if upward < 0.86: result = result.lerp(Color(.40, .39, .35), smoothstep(0.86, 0.66, upward) * 0.85)
	var shore := shore_factor(p)
	if shore > 0.0: result = result.lerp(Color(.56, .50, .36), shore * 0.85)
	if is_water(p): result = Color(.33, .31, .24)
	# Strong face-to-face contrast keeps the relief readable without overlays.
	var light := remap(clampf(upward, 0.72, 1.0), 0.72, 1.0, 0.82, 1.08)
	if upward < 0.91:
		result = result.lerp(Color(0.29, 0.25, 0.17), smoothstep(0.91, 0.72, upward) * 0.30)
	return Color(result.r * light, result.g * light, result.b * light, 1)

func _wear_mask(p: Vector2)->float:
	var cabin:=_ellipse(p,Vector2(0,-2),Vector2(8.5,8),.32); var garden:=_ellipse(p,Vector2(-8,-4),Vector2(6.2,5.2),.34)
	return maxf(cabin,garden)*smoothstep(.32,.62,_hash(floor((p+Vector2(13,5))/2.5)))
func _protected_flatten(p: Vector2)->float:
	# The cabin mesh is centered at world (0, -4). Its visual/collision footprint
	# reaches about x = +/-4.5 and z = -9.8..-0.3; keep a generous level apron so
	# terrain triangles cannot poke through the rear wall or porch stairs.
	var house := _rect_mask(p, Vector2(0.0, -5.0), Vector2(6.2, 6.2), 2.4)
	# Porch steps occupy x = -1.04..1.04 and z = 0.98..1.84 at ground level.
	# Keep a full-height landing under and in front of them, then blend it broadly
	# into the path so the first step is reachable instead of hanging over a dip.
	var porch_approach := _rect_mask(p, Vector2(0.0, 3.0), Vector2(2.35, 2.25), 2.8)
	var garden := _rect_mask(p, Vector2(-8.2,-4.1), Vector2(4.7,4.3), 1.4)
	var spawn := _ellipse(p, Vector2(0.0,13.0), Vector2(1.8,1.8), 0.42)
	return maxf(maxf(maxf(house, porch_approach), garden), spawn)
func _ellipse(p:Vector2,center:Vector2,radius:Vector2,soft:float)->float: return 1.0-smoothstep(1.0-soft,1.0,((p-center)/radius).length())
func _rect_mask(p:Vector2,center:Vector2,half_size:Vector2,fade:float)->float:
	var q: Vector2 = abs(p-center)-half_size; return 1.0-smoothstep(0.0,fade,Vector2(maxf(q.x,0),maxf(q.y,0)).length())
func _hash(p:Vector2)->float: return fposmod(sin(p.dot(Vector2(127.1,311.7))+seed_value*.013)*43758.5453,1.0)
func _main_route()->PackedVector2Array: return PackedVector2Array([Vector2(-.15,14.8),Vector2(-.55,11.8),Vector2(.15,8.6),Vector2(.75,6.1),Vector2(1.55,4.15),Vector2(2.75,2.1),Vector2(3.78,.05)])
func _garden_route()->PackedVector2Array: return PackedVector2Array([Vector2(.15,8.6),Vector2(-1.7,7.35),Vector2(-3.9,5.75),Vector2(-5.8,3.85),Vector2(-6.85,1.75),Vector2(-6.45,-.72)])
func _distance(point:Vector2,route:PackedVector2Array)->float:
	var best:=INF
	for i in range(route.size()-1): var start:=route[i];var segment:=route[i+1]-start;var ratio:=clampf((point-start).dot(segment)/maxf(segment.length_squared(),.0001),0,1);best=minf(best,point.distance_to(start+segment*ratio))
	return best
