@tool
extends Node3D
class_name SurvivalResourceField
@export var rebuild:=false:
	set(value):rebuild=false;if value:build()
@export var tree_count:=26
@export var berry_count:=12
@export var mushroom_count:=16
@export var stone_count:=18
@export var seed_value:=24819
var _rng:=RandomNumberGenerator.new()
func _ready()->void:call_deferred("build")
func build()->void:
	for child in get_children():child.queue_free()
	_rng.seed=seed_value
	for i in tree_count:_spawn_tree(_find_position(12.0,42.0),i)
	for i in berry_count:_spawn_bush(_find_position(7.5,28.0),i)
	for i in mushroom_count:_spawn_mushroom(_find_position(6.0,25.0),i)
	for i in stone_count:_spawn_stone(_find_position(8.0,38.0),i)
func _find_position(min_radius:float,max_radius:float)->Vector3:
	for attempt in 80:
		var angle:=_rng.randf_range(0,TAU);var radius:=sqrt(_rng.randf_range(min_radius*min_radius,max_radius*max_radius));var p:=Vector3(cos(angle)*radius,0,sin(angle)*radius)
		if p.distance_to(Vector3(0,0,-2))>10 and p.distance_to(Vector3(-8,0,-4))>8:return _surface_position(p)
	return _surface_position(Vector3(max_radius,0,0))
func _surface_position(p: Vector3, offset := 0.012) -> Vector3:
	var ground := get_node_or_null("../Ground")
	if ground and ground.has_method("surface_position"):
		return ground.call("surface_position", Vector2(p.x, p.z), offset) as Vector3
	p.y = offset
	return p
func _mat(color:Color,rough:=1.0)->StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=rough;return m
func _spawn_tree(pos:Vector3,index:int)->void:
	var body:=StaticBody3D.new();body.name="HarvestTree%02d"%index;body.position=pos;body.rotation.y=_rng.randf_range(0,TAU);body.set_script(load("res://scripts/harvestable_resource.gd"));body.set("resource_kind","tree");body.set("amount",4);body.set("hits_required",3);body.set("respawn_seconds",240.0);add_child(body)
	var trunk:=MeshInstance3D.new();var trunk_mesh:=CylinderMesh.new();trunk_mesh.top_radius=.2;trunk_mesh.bottom_radius=.34;trunk_mesh.height=3.2;trunk_mesh.radial_segments=7;trunk_mesh.material=_mat(Color(.19,.105,.045));trunk.mesh=trunk_mesh;trunk.position.y=1.6;body.add_child(trunk)
	for layer in 3:
		var crown:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=.08;mesh.bottom_radius=1.25-layer*.18;mesh.height=1.75;mesh.radial_segments=7;mesh.material=_mat(Color(.055+layer*.018,.14+layer*.025,.038));crown.mesh=mesh;crown.position=Vector3(_rng.randf_range(-.18,.18),3.15+layer*.72,_rng.randf_range(-.18,.18));crown.rotation.y=_rng.randf_range(0,TAU);body.add_child(crown)
	var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.38;capsule.height=3.4;shape.shape=capsule;shape.position.y=1.7;body.add_child(shape)
func _spawn_bush(pos:Vector3,index:int)->void:
	var body:=StaticBody3D.new();body.name="BerryBush%02d"%index;body.position=pos;body.set_script(load("res://scripts/harvestable_resource.gd"));body.set("resource_kind","berry");body.set("amount",2);body.set("respawn_seconds",150.0);add_child(body)
	for j in 5:
		var leaf:=MeshInstance3D.new();var mesh:=SphereMesh.new();mesh.radius=.52;mesh.height=.85;mesh.radial_segments=6;mesh.rings=3;mesh.material=_mat(Color(.08+.02*j,.22+.014*j,.055));leaf.mesh=mesh;leaf.position=Vector3(_rng.randf_range(-.48,.48),.42+_rng.randf_range(0,.3),_rng.randf_range(-.48,.48));body.add_child(leaf)
	for j in 7:
		var berry:=MeshInstance3D.new();var bm:=SphereMesh.new();bm.radius=.055;bm.height=.11;bm.radial_segments=5;bm.rings=2;bm.material=_mat(Color(.58,.035,.08));berry.mesh=bm;berry.position=Vector3(_rng.randf_range(-.52,.52),_rng.randf_range(.45,.92),_rng.randf_range(-.52,.52));body.add_child(berry)
	var shape:=CollisionShape3D.new();var sphere:=SphereShape3D.new();sphere.radius=.8;shape.shape=sphere;shape.position.y=.5;body.add_child(shape)
func _spawn_mushroom(pos:Vector3,index:int)->void:
	var body:=StaticBody3D.new();body.name="Mushroom%02d"%index;body.position=pos;body.set_script(load("res://scripts/harvestable_resource.gd"));body.set("resource_kind","mushroom");body.set("amount",1);body.set("respawn_seconds",100.0);add_child(body)
	for j in _rng.randi_range(2,4):
		var root:=Node3D.new();root.position=Vector3(_rng.randf_range(-.25,.25),0,_rng.randf_range(-.25,.25));root.scale=Vector3.ONE*_rng.randf_range(.7,1.15);body.add_child(root)
		var stem:=MeshInstance3D.new();var sm:=CylinderMesh.new();sm.top_radius=.035;sm.bottom_radius=.055;sm.height=.3;sm.radial_segments=6;sm.material=_mat(Color(.7,.58,.38));stem.mesh=sm;stem.position.y=.15;root.add_child(stem)
		var cap:=MeshInstance3D.new();var cm:=SphereMesh.new();cm.radius=.15;cm.height=.15;cm.radial_segments=6;cm.rings=2;cm.material=_mat(Color(.62,.16,.055));cap.mesh=cm;cap.position.y=.32;root.add_child(cap)
	var shape:=CollisionShape3D.new();var sphere:=SphereShape3D.new();sphere.radius=.55;shape.shape=sphere;shape.position.y=.25;body.add_child(shape)

func _spawn_stone(pos: Vector3, index: int) -> void:
	var body := StaticBody3D.new()
	body.name = "StoneDeposit%02d" % index
	body.position = pos
	body.rotation.y = _rng.randf_range(0.0, TAU)
	body.scale = Vector3.ONE * _rng.randf_range(0.8, 1.25)
	body.set_script(load("res://scripts/harvestable_resource.gd"))
	body.set("resource_kind", "stone")
	body.set("amount", 3)
	body.set("hits_required", 4)
	body.set("respawn_seconds", 210.0)
	add_child(body)
	var stone_colors := [Color(0.27, 0.29, 0.27), Color(0.34, 0.33, 0.29), Color(0.22, 0.25, 0.25)]
	for j in _rng.randi_range(3, 5):
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = _rng.randf_range(0.35, 0.62)
		mesh.height = _rng.randf_range(0.55, 0.9)
		mesh.radial_segments = _rng.randi_range(5, 7)
		mesh.rings = 3
		mesh.material = _mat(stone_colors[j % stone_colors.size()], 0.88)
		rock.mesh = mesh
		rock.position = Vector3(_rng.randf_range(-0.42, 0.42), mesh.height * 0.36, _rng.randf_range(-0.38, 0.38))
		rock.rotation = Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(0.0, TAU), _rng.randf_range(-0.2, 0.2))
		rock.scale = Vector3(_rng.randf_range(0.8, 1.2), _rng.randf_range(0.75, 1.15), _rng.randf_range(0.8, 1.25))
		body.add_child(rock)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.82
	shape.shape = sphere
	shape.position.y = 0.42
	body.add_child(shape)
