@tool
extends Node3D
class_name VolumetricGrassField

@export var rebuild := false:
 set(value):
  rebuild = false
  if value:build()
@export_range(0,5000,1) var tuft_count:=2800
@export var radius:=58.0
@export var seed_value:=930271
var _rng:=RandomNumberGenerator.new()

var _main_route:=PackedVector3Array([Vector3(-.15,0,14.8),Vector3(-.55,0,11.8),Vector3(.15,0,8.6),Vector3(.75,0,6.1),Vector3(1.55,0,4.15),Vector3(2.75,0,2.1),Vector3(3.78,0,.05)])
var _garden_route:=PackedVector3Array([Vector3(.15,0,8.6),Vector3(-1.7,0,7.35),Vector3(-3.9,0,5.75),Vector3(-5.8,0,3.85),Vector3(-6.85,0,1.75),Vector3(-6.45,0,-.72)])

func _ready()->void:
 if get_child_count()==0:call_deferred("build")

func build()->void:
 for child in get_children():child.free()
 if tuft_count<=0:return
 _rng.seed=seed_value
 var mesh:=_create_tuft_mesh()
 var transforms:Array[Transform3D]=[]
 var colors:Array[Color]=[]
 var attempts:=0
 while transforms.size()<tuft_count and attempts<tuft_count*35:
  attempts+=1
  var angle:=_rng.randf()*TAU
  var distance:=sqrt(_rng.randf_range(3.8*3.8,radius*radius))
  var p:=Vector3(cos(angle)*distance,.025,sin(angle)*distance)
  if _protected(p):continue
  p.y = _terrain_height(p) + 0.025
  var patch:=.5+.5*sin(p.x*.31+sin(p.z*.17)*2.1)*sin(p.z*.27-cos(p.x*.13))
  if _rng.randf()>lerpf(.42,1.0,patch):continue
  var scale_value:=_rng.randf_range(.68,1.32)
  var basis:=Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3(scale_value*_rng.randf_range(.8,1.18),scale_value*_rng.randf_range(.82,1.28),scale_value*_rng.randf_range(.8,1.18)))
  transforms.append(Transform3D(basis,p))
  var shade:=_rng.randf_range(.82,1.18)
  colors.append(Color(.45*shade,.72*shade,.22*shade,1.0))
 var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=mesh;mm.instance_count=transforms.size()
 for i in transforms.size():mm.set_instance_transform(i,transforms[i]);mm.set_instance_color(i,colors[i])
 var field:=MultiMeshInstance3D.new();field.name="VolumetricLowPolyGrass";field.multimesh=mm;field.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON;field.visibility_range_end=52.0;field.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
 add_child(field)

func _terrain_height(p: Vector3) -> float:
 var ground := get_node_or_null("../Ground")
 if ground and ground.has_method("sample_height"):
  return float(ground.call("surface_height", Vector2(p.x, p.z)))
 return 0.0

func _protected(p:Vector3)->bool:
 if p.x>-4.95 and p.x<5.35 and p.z>-8.05 and p.z<.45:return true
 if p.x>-12.2 and p.x<-3.8 and p.z>-8.3 and p.z<.3:return true
 if Vector2(p.x,p.z).distance_to(Vector2(0.0,13.0))<.85:return true
 return false

func _distance_to_route(p:Vector3,route:PackedVector3Array)->float:
 var best:=INF
 var point:=Vector2(p.x,p.z)
 for i in route.size()-1:
  var a:=Vector2(route[i].x,route[i].z);var b:=Vector2(route[i+1].x,route[i+1].z)
  var ab:=b-a;var t:=clampf((point-a).dot(ab)/maxf(ab.length_squared(),.0001),0,1)
  best=minf(best,point.distance_to(a+ab*t))
 return best

func _create_tuft_mesh()->ArrayMesh:
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var palette:=[Color(.18,.34,.075),Color(.24,.43,.095),Color(.31,.52,.12),Color(.38,.58,.14)]
 var blades:=[Vector4(-.18,-.08,.48,.03),Vector4(.13,.03,.64,-.06),Vector4(-.04,.16,.78,.04),Vector4(.24,-.13,.42,-.05),Vector4(-.25,.13,.55,.07),Vector4(.06,-.22,.68,.02),Vector4(.26,.17,.51,-.04)]
 for i in blades.size():
  var d:Vector4=blades[i];var c:Color=palette[i%palette.size()]
  var center:=Vector3(d.x,0,d.y);var width:=.045+float(i%3)*.012;var depth:=width*.58
  var tilt:=Vector3(d.w,0,-d.w*.55);var tip:=center+Vector3(tilt.x,d.z,tilt.z)
  var a:=center+Vector3(-width,0,-depth);var b:=center+Vector3(width,0,-depth);var cc:=center+Vector3(width,0,depth);var e:=center+Vector3(-width,0,depth)
  _face(st,a,b,tip,c*.78);_face(st,b,cc,tip,c*.92);_face(st,cc,e,tip,c);_face(st,e,a,tip,c*.86);_face(st,a,e,cc,c*.65);_face(st,a,cc,b,c*.65)
 st.generate_normals();var mesh:=st.commit();var mat:=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.roughness=.96;mat.cull_mode=BaseMaterial3D.CULL_DISABLED;mesh.surface_set_material(0,mat);return mesh

func _face(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,color:Color)->void:
 st.set_color(color);st.add_vertex(a);st.set_color(color);st.add_vertex(b);st.set_color(color);st.add_vertex(c)
