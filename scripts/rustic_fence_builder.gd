extends Node
class_name RusticFenceBuilder

const MIN_LENGTH := 1.0
const FENCE_VARIANTS := [preload("res://assets/cozy_homestead/fence_straight_1m.glb"), preload("res://assets/cozy_homestead/fence_straight_1m_v2.glb"), preload("res://assets/cozy_homestead/fence_straight_1m_v3.glb"), preload("res://assets/cozy_homestead/fence_straight_1m_v4.glb"), preload("res://assets/cozy_homestead/fence_straight_1m_v5.glb"), preload("res://assets/cozy_homestead/fence_straight_1m_v6.glb")]
const FULL_SCENE := preload("res://assets/cozy_homestead/fence_straight_1m.glb")
const HALF_SCENE := preload("res://assets/cozy_homestead/fence_straight_1m.glb")

static func create_fence(length: float, ground: Node = null, start: Vector3 = Vector3.ZERO, direction: Vector3 = Vector3.RIGHT) -> Node3D:
 length=maxf(MIN_LENGTH,length)
 var root:=StaticBody3D.new();root.name="PlacedRusticFence";root.set_script(load("res://scripts/destructible_fence.gd"));root.set("fence_label","base fence");root.set("hits_required",4);root.set("wood_return",maxi(2,floori(length)) )
 var cursor:=0.0
 while length-cursor>.01:
  var remaining:=length-cursor
  var nominal:=1.0
  var actual:=minf(1.0,remaining)
  var scene:PackedScene=FENCE_VARIANTS.pick_random()
  var piece:=scene.instantiate() as Node3D
  var world_start:=start+direction*cursor
  var world_end:=start+direction*(cursor+actual)
  var y0:=_height(ground,world_start,start.y)
  var y1:=_height(ground,world_end,start.y)
  piece.position=Vector3(cursor,y0-start.y,0)
  piece.rotation.z=atan2(y1-y0,actual)
  piece.scale.x=Vector2(actual,y1-y0).length()/nominal
  root.add_child(piece)
  var col:=CollisionShape3D.new();var cbox:=BoxShape3D.new();cbox.size=Vector3(Vector2(actual,y1-y0).length()+.12,1.3,.26);col.shape=cbox
  col.position=Vector3(cursor+actual*.5,.65+(y0+y1)*.5-start.y,0);col.rotation.z=atan2(y1-y0,actual);root.add_child(col)
  cursor+=actual
 return root

static func align_between(fence:Node3D,start:Vector3,finish:Vector3)->void:
 var flat:=finish-start;flat.y=0
 fence.position=start;fence.rotation=Vector3(0,atan2(-flat.z,flat.x),0)

static func create_between(start:Vector3,finish:Vector3,ground:Node=null)->Node3D:
 var flat:=finish-start;flat.y=0
 var length:=flat.length()
 var direction:=flat.normalized() if length>0.001 else Vector3.RIGHT
 start.y=_height(ground,start,start.y)
 var fence:=create_fence(length,ground,start,direction)
 align_between(fence,start,finish)
 var posts: Array[Vector3] = []
 var distance:=0.0
 while distance < length:
  posts.append(Vector3(distance,_height(ground,start+direction*distance,start.y)-start.y,0.0))
  distance+=minf(1.0,length-distance)
 posts.append(Vector3(length,_height(ground,start+direction*length,start.y)-start.y,0.0))
 fence.set_meta("post_positions",posts)
 fence.add_to_group("placed_fences")
 return fence

static func create_preview_between(start:Vector3,finish:Vector3,valid:bool,ground:Node=null)->Node3D:
 var preview:=create_between(start,finish,ground);preview.name="FenceDragPreview";preview.remove_from_group("placed_fences")
 for body in preview.find_children("*","StaticBody3D",true,false):
  (body as StaticBody3D).collision_layer=0;(body as StaticBody3D).collision_mask=0
 for shape in preview.find_children("*","CollisionShape3D",true,false):(shape as CollisionShape3D).disabled=true
 set_preview_valid(preview,valid);return preview

static func create_anchor_preview(position:Vector3)->Node3D:
 var preview:=FULL_SCENE.instantiate() as Node3D;preview.name="FenceDragPreview";preview.position=position;preview.scale.x=.04
 for body in preview.find_children("*","StaticBody3D",true,false):(body as StaticBody3D).collision_layer=0
 for shape in preview.find_children("*","CollisionShape3D",true,false):(shape as CollisionShape3D).disabled=true
 set_preview_valid(preview,true);return preview

static func set_preview_valid(preview:Node3D,valid:bool)->void:
 var material:=StandardMaterial3D.new();material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(.12,1,.24,.82) if valid else Color(1,.06,.03,.85);material.emission_enabled=true;material.emission=Color(.08,.9,.16) if valid else Color(1,.03,.01);material.emission_energy_multiplier=1.8;material.no_depth_test=true
 for node in preview.find_children("*","MeshInstance3D",true,false):(node as MeshInstance3D).material_override=material

static func _height(ground:Node,point:Vector3,fallback:float)->float:
 if ground and ground.has_method("surface_height"):
  return float(ground.call("surface_height",Vector2(point.x,point.z)))+0.02
 return fallback
