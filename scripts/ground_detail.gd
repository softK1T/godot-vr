@tool
extends Node3D
class_name GroundDetail

@export var rebuild := false:
	set(value):
		rebuild = false
		if value: build()
@export_category("Ground")
@export_range(0, 300, 1) var moss_count := 0
@export_range(0, 220, 1) var pebble_count := 0
@export_range(0, 300, 1) var leaf_count := 0
@export_range(0, 180, 1) var twig_count := 0
@export_category("Vegetation")
@export_range(0, 900, 1) var grass_count := 0
@export_range(0, 160, 1) var bush_count := 0
@export var seed_value := 421906
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if get_child_count() == 0: call_deferred("build")

func build() -> void:
	for child in get_children(): child.free()
	_rng.seed = seed_value
	_add_moss(); _add_pebbles(); _add_leaves(); _add_twigs(); _add_grass(); _add_bushes()

func _mat(vertex_color: bool, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = vertex_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _add_moss() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55; mesh.bottom_radius = 0.62; mesh.height = 0.005; mesh.radial_segments = 10
	mesh.material = _mat(false, Color(0.075, 0.115, 0.03))
	_add_multimesh("MossPatches", mesh, _ground_transforms(moss_count, 5.0, 29.0, 1.2, 0.012, Vector2(0.22, 1.0), Vector2(0.18, 0.74)), false, 42.0)

func _add_pebbles() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.07; mesh.height = 0.09; mesh.radial_segments = 7; mesh.rings = 3
	mesh.material = _mat(false, Color(0.155, 0.16, 0.125))
	_add_multimesh("GroundPebbles", mesh, _ground_transforms(pebble_count, 6.0, 27.0, 1.55, 0.023, Vector2(0.45, 1.2), Vector2(0.28, 0.58)), true, 36.0)

func _add_leaves() -> void:
	_add_multimesh("FallenLeaves", _leaf_mesh(), _ground_transforms(leaf_count, 5.0, 31.0, 1.0, 0.018, Vector2(0.7, 1.35), Vector2(0.8, 1.15)), false, 30.0)

func _add_twigs() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.025, 0.42); mesh.material = _mat(false, Color(0.105, 0.055, 0.026))
	_add_multimesh("Twigs", mesh, _ground_transforms(twig_count, 6.0, 30.0, 1.1, 0.022, Vector2(0.55, 1.4), Vector2(0.7, 1.15)), true, 31.0)

func _add_grass() -> void:
	var output: Array[Transform3D] = []
	var attempts := 0
	while output.size() < grass_count and attempts < grass_count * 35:
		attempts += 1
		var p := _random_position(4.4, 31.0)
		if _is_protected(p, 0.72): continue
		var density := _noise_hash(floor(p * 0.32))
		if density < 0.36 or _rng.randf() > lerpf(0.25, 0.98, density): continue
		var s := _rng.randf_range(0.72, 1.35)
		var basis := Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3(s * _rng.randf_range(0.82, 1.15), s, s * _rng.randf_range(0.82, 1.15)))
		output.append(Transform3D(basis, Vector3(p.x, 0.008, p.y)))
	_add_multimesh("NaturalGrass", _grass_mesh(), output, true, 38.0)

func _add_bushes() -> void:
	var output: Array[Transform3D] = []
	var attempts := 0
	while output.size() < bush_count and attempts < bush_count * 45:
		attempts += 1
		var p := _random_position(7.0, 34.0)
		if _is_protected(p, 1.9) or _noise_hash(floor((p + Vector2(9,-4)) * 0.2)) < 0.5: continue
		var s := _rng.randf_range(0.72, 1.28)
		var basis := Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3(s * _rng.randf_range(0.82, 1.18), s, s * _rng.randf_range(0.82, 1.18)))
		output.append(Transform3D(basis, Vector3(p.x, 0.01, p.y)))
	_add_multimesh("NaturalBushes", _bush_mesh(), output, true, 48.0)

func _grass_mesh() -> ArrayMesh:
	var v := PackedVector3Array(); var n := PackedVector3Array(); var c := PackedColorArray(); var idx := PackedInt32Array()
	var palette := [Color(0.035,0.105,0.025), Color(0.07,0.17,0.035), Color(0.13,0.23,0.045), Color(0.18,0.28,0.055)]
	var data := [Vector4(-.22,-.12,.52,-.18),Vector4(.18,-.16,.68,.12),Vector4(-.05,.13,.82,.04),Vector4(.27,.08,.46,.22),Vector4(-.31,.16,.38,-.08),Vector4(.02,-.28,.58,.19),Vector4(.33,-.04,.34,-.20),Vector4(-.17,.28,.48,.14),Vector4(.12,.25,.62,-.12)]
	for i in range(data.size()):
		var d: Vector4 = data[i]; var base := Vector3(d.x,0,d.y); var direction := Vector3(cos(i*2.399),0,sin(i*2.399)); var side := Vector3(-direction.z,0,direction.x); var width := .055 + (i%3)*.012; var tip := base + Vector3(d.w,d.z,d.w*.35); var start := v.size()
		v.append(base-side*width); v.append(base+side*width); v.append(tip)
		n.append(Vector3.UP); n.append(Vector3.UP); n.append(Vector3.UP)
		c.append(palette[i%4]*.72); c.append(palette[i%4]*.8); c.append(palette[i%4])
		idx.append_array(PackedInt32Array([start,start+1,start+2,start+2,start+1,start]))
	return _array_mesh(v,n,c,idx,_mat(true,Color.WHITE))

func _bush_mesh() -> ArrayMesh:
	var v := PackedVector3Array(); var n := PackedVector3Array(); var c := PackedColorArray(); var idx := PackedInt32Array()
	var centers := [Vector4(0,.48,0,.52),Vector4(-.38,.34,.05,.38),Vector4(.37,.32,.12,.4),Vector4(.08,.3,-.4,.36),Vector4(-.18,.67,-.14,.34),Vector4(.25,.62,-.12,.32)]
	var palette := [Color(.035,.105,.025),Color(.055,.145,.028),Color(.085,.18,.035),Color(.12,.21,.04)]
	for i in range(centers.size()): _octahedron(v,n,c,idx,Vector3(centers[i].x,centers[i].y,centers[i].z),centers[i].w,palette[i%4])
	return _array_mesh(v,n,c,idx,_mat(true,Color.WHITE))

func _octahedron(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,idx: PackedInt32Array,center: Vector3,r: float,color: Color) -> void:
	var p := [center+Vector3(0,r*1.15,0),center+Vector3(0,-r*.8,0),center+Vector3(r,0,0),center+Vector3(0,0,r*.82),center+Vector3(-r,0,0),center+Vector3(0,0,-r*.82)]
	for face in [[0,2,3],[0,3,4],[0,4,5],[0,5,2],[1,3,2],[1,4,3],[1,5,4],[1,2,5]]:
		var normal: Vector3 = (p[face[1]]-p[face[0]]).cross(p[face[2]]-p[face[0]]).normalized(); var start := v.size()
		for j in face: v.append(p[j]); n.append(normal); c.append(color*(.82+normal.y*.18))
		idx.append_array(PackedInt32Array([start,start+1,start+2]))

func _leaf_mesh() -> ArrayMesh:
	return _array_mesh(PackedVector3Array([Vector3(-.07,0,0),Vector3(0,.008,-.14),Vector3(.07,0,0),Vector3(0,.008,.14)]),PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP]),PackedColorArray([Color(.22,.095,.025),Color(.34,.15,.035),Color(.18,.07,.018),Color(.28,.115,.025)]),PackedInt32Array([0,1,2,0,2,3,2,1,0,3,2,0]),_mat(true,Color.WHITE))

func _array_mesh(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,idx: PackedInt32Array,material: Material) -> ArrayMesh:
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=v; arrays[Mesh.ARRAY_NORMAL]=n; arrays[Mesh.ARRAY_COLOR]=c; arrays[Mesh.ARRAY_INDEX]=idx
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); mesh.surface_set_material(0,material); return mesh

func _ground_transforms(count: int,inner: float,outer: float,clearance: float,height: float,xz: Vector2,y_scale: Vector2) -> Array[Transform3D]:
	var output: Array[Transform3D]=[]; var attempts:=0
	while output.size()<count and attempts<count*30:
		attempts+=1; var p:=_random_position(inner,outer)
		if _is_protected(p,clearance): continue
		var basis:=Basis(Vector3.UP,_rng.randf_range(-PI,PI)).scaled(Vector3(_rng.randf_range(xz.x,xz.y),_rng.randf_range(y_scale.x,y_scale.y),_rng.randf_range(xz.x,xz.y)))
		output.append(Transform3D(basis,Vector3(p.x,height,p.y)))
	return output

func _terrain_height(p: Vector2) -> float:
	var ground := get_node_or_null("../Ground")
	if ground and ground.has_method("sample_height"):
		return float(ground.call("surface_height", p))
	return 0.0

func _noise_hash(p: Vector2) -> float: return fposmod(sin(p.dot(Vector2(127.1,311.7)))*43758.5453,1.0)
func _random_position(inner: float,outer: float) -> Vector2:
	var a:=_rng.randf()*TAU; var d:=sqrt(_rng.randf_range(inner*inner,outer*outer)); return Vector2(cos(a),sin(a))*d
func _is_protected(p: Vector2,clearance: float) -> bool:
	if p.x>-5.2 and p.x<5.6 and p.y>-8.0 and p.y<2.0: return true
	if p.x>-12.4 and p.x<-4.0 and p.y>-8.4 and p.y<0.2: return true
	return _distance(p,_main_route())<clearance or _distance(p,_garden_route())<clearance
func _main_route()->PackedVector2Array: return PackedVector2Array([Vector2(-.15,14.8),Vector2(-.55,11.8),Vector2(.15,8.6),Vector2(.75,6.1),Vector2(1.55,4.15),Vector2(2.75,2.1),Vector2(3.78,.05)])
func _garden_route()->PackedVector2Array: return PackedVector2Array([Vector2(.15,8.6),Vector2(-1.7,7.35),Vector2(-3.9,5.75),Vector2(-5.8,3.85),Vector2(-6.85,1.75),Vector2(-6.45,-.72)])
func _distance(point: Vector2,route: PackedVector2Array)->float:
	var best:=INF
	for i in range(route.size()-1):
		var start:=route[i]; var segment:=route[i+1]-start; var ratio:=clampf((point-start).dot(segment)/maxf(segment.length_squared(),.0001),0,1); best=minf(best,point.distance_to(start+segment*ratio))
	return best
func _add_multimesh(name: String,mesh: Mesh,transforms: Array[Transform3D],shadows: bool,visibility: float)->void:
	var mm:=MultiMesh.new(); mm.transform_format=MultiMesh.TRANSFORM_3D; mm.mesh=mesh; mm.instance_count=transforms.size()
	for i in range(transforms.size()): mm.set_instance_transform(i,transforms[i])
	var instance:=MultiMeshInstance3D.new(); instance.name=name; instance.multimesh=mm; instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; instance.visibility_range_end=visibility; add_child(instance)
