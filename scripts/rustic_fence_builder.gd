extends Node
class_name RusticFenceBuilder

const MIN_LENGTH := 1.0
const FULL_SCENE := preload("res://assets/models/low_poly_fence/scenes/fence_straight_3m.tscn")
const HALF_SCENE := preload("res://assets/models/low_poly_fence/scenes/fence_straight_1_5m.tscn")

static func create_fence(length: float) -> Node3D:
 length=maxf(MIN_LENGTH,length)
 var root:=StaticBody3D.new();root.name="PlacedRusticFence";root.set_script(load("res://scripts/destructible_fence.gd"));root.set("fence_label","base fence");root.set("hits_required",4);root.set("wood_return",maxi(2,floori(length)) )
 var cursor:=0.0
 while length-cursor>.01:
  var remaining:=length-cursor
  var nominal:=3.0 if remaining>1.5 else 1.5
  var actual:=minf(nominal,remaining)
  var scene:PackedScene=FULL_SCENE if nominal==3.0 else HALF_SCENE
  var piece:=scene.instantiate() as Node3D
  piece.position.x=cursor;piece.scale.x=actual/nominal;root.add_child(piece)
  cursor+=actual
 return root

static func align_between(fence:Node3D,start:Vector3,finish:Vector3)->void:
 var flat:=finish-start;flat.y=0
 fence.position=start;fence.rotation=Vector3(0,atan2(-flat.z,flat.x),0)

static func create_between(start:Vector3,finish:Vector3)->Node3D:
 var flat:=finish-start;flat.y=0
 var fence:=create_fence(flat.length());align_between(fence,start,finish);return fence

static func create_preview_between(start:Vector3,finish:Vector3,valid:bool)->Node3D:
 var preview:=create_between(start,finish);preview.name="FenceDragPreview"
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
