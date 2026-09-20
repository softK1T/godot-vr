@tool
extends Node3D
@export var rabbit_count:=7
@export var bird_count:=10
@export var seed_value:=9122
func _ready()->void:call_deferred("build")
func _mat(c:Color)->StandardMaterial3D:
 var m:=StandardMaterial3D.new();m.albedo_color=c;m.roughness=1;return m
func build()->void:
 var rng:=RandomNumberGenerator.new();rng.seed=seed_value
 for old in get_children():old.queue_free()
 for i in rabbit_count:
  var root:=Node3D.new();root.name="Rabbit%02d"%i;var a:=rng.randf_range(0,TAU);var r:=rng.randf_range(9,28);var xz:=Vector2(cos(a)*r,sin(a)*r);root.position=_surface_position(xz,.02);root.set_script(load("res://scripts/wildlife_critter.gd"));root.set("grounded",true);root.set("surface_offset",.02);add_child(root)
  var body:=MeshInstance3D.new();var mesh:=SphereMesh.new();mesh.radius=.22;mesh.height=.42;mesh.radial_segments=6;mesh.rings=3;mesh.material=_mat(Color(.42,.33,.22));body.mesh=mesh;body.position.y=.23;root.add_child(body)
  for side in [-1,1]:
   var ear:=MeshInstance3D.new();var em:=CapsuleMesh.new();em.radius=.035;em.height=.3;em.radial_segments=5;em.rings=2;em.material=_mat(Color(.38,.28,.2));ear.mesh=em;ear.position=Vector3(side*.08,.5,0);ear.rotation.z=side*.16;root.add_child(ear)
 for i in bird_count:
  var root:=Node3D.new();root.name="ForestBird%02d"%i;var a:=rng.randf_range(0,TAU);var r:=rng.randf_range(8,32);root.position=Vector3(cos(a)*r,rng.randf_range(.1,.35),sin(a)*r);root.set_script(load("res://scripts/wildlife_critter.gd"));add_child(root)
  var body:=MeshInstance3D.new();var mesh:=SphereMesh.new();mesh.radius=.12;mesh.height=.25;mesh.radial_segments=6;mesh.rings=3;mesh.material=_mat([Color(.18,.26,.12),Color(.32,.12,.06),Color(.1,.2,.3)][i%3]);body.mesh=mesh;body.position.y=.15;root.add_child(body)

func _surface_position(xz: Vector2, offset := 0.0) -> Vector3:
 var ground:=get_node_or_null("../Ground")
 if ground and ground.has_method("surface_position"):
  return ground.call("surface_position",xz,offset) as Vector3
 return Vector3(xz.x,offset,xz.y)
