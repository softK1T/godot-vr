extends Node
class_name FenceBuilder

const MIN_LENGTH := 1.0
const POST_SPACING := 1.0
const FENCE_PIECE := preload("res://assets/cozy_homestead/fence_straight_1m.glb")
const FENCE_PIECE_LENGTH := 1.0
const FENCE_VARIANTS := [preload("res://assets/cozy_homestead/fence_straight_1m.glb"), preload("res://assets/cozy_homestead/fence_straight_1m_v2.glb"), preload("res://assets/cozy_homestead/fence_straight_1m_v3.glb"), preload("res://assets/cozy_homestead/fence_straight_1m_v4.glb"), preload("res://assets/cozy_homestead/fence_straight_1m_v5.glb"), preload("res://assets/cozy_homestead/fence_straight_1m_v6.glb")]

static func create_fence(length: float = 3.0, ground: Node = null, start: Vector3 = Vector3.ZERO, direction: Vector3 = Vector3.RIGHT) -> StaticBody3D:
 length = maxf(MIN_LENGTH, length)
 var root := StaticBody3D.new();root.name = "PlacedFence";root.set_script(load("res://scripts/destructible_fence.gd"));root.set("fence_label","low fence");root.set("wood_return",maxi(1,floori(length*.5)))
 var spans := maxi(1, ceili(length / POST_SPACING));var spacing := length / float(spans)
 var heights: Array[float] = []
 for i in spans + 1:
  heights.append(_height(ground,start+direction*(float(i)*spacing),start.y)-start.y)
 for span in spans:
  var rise:float=heights[span+1]-heights[span]
  var piece:=(FENCE_VARIANTS.pick_random() as PackedScene).instantiate() as Node3D
  piece.position=Vector3(float(span)*spacing,heights[span],0)
  piece.rotation.z=atan2(rise,spacing)
  piece.scale.x=Vector2(spacing,rise).length()/FENCE_PIECE_LENGTH
  root.add_child(piece)
  var shape:=CollisionShape3D.new();var box:=BoxShape3D.new()
  box.size=Vector3(Vector2(spacing,rise).length()+.12,1.3,.26)
  shape.shape=box
  shape.position=Vector3((float(span)+.5)*spacing,.65+(heights[span]+heights[span+1])*.5,0)
  shape.rotation.z=atan2(rise,spacing)
  root.add_child(shape)
 return root

static func align_between(fence: Node3D, start: Vector3, finish: Vector3) -> void:
 var flat:=finish-start;flat.y=0
 fence.position=start
 fence.rotation=Vector3(0,atan2(-flat.z,flat.x),0)

static func create_between(start: Vector3, finish: Vector3, ground: Node = null) -> StaticBody3D:
 var flat:=finish-start;flat.y=0
 var length:=flat.length()
 var direction:=flat.normalized() if length>0.001 else Vector3.RIGHT
 start.y=_height(ground,start,start.y)
 var fence:=create_fence(length,ground,start,direction)
 align_between(fence,start,finish)
 var spans:=maxi(1,ceili(maxf(MIN_LENGTH,length)/POST_SPACING))
 var spacing:=maxf(MIN_LENGTH,length)/float(spans)
 var posts: Array[Vector3] = []
 for i in spans+1:
  var x:=float(i)*spacing
  posts.append(Vector3(x,_height(ground,start+direction*x,start.y)-start.y,0.0))
 fence.set_meta("post_positions",posts)
 fence.add_to_group("placed_fences")
 return fence

static func create_preview_between(start: Vector3, finish: Vector3, valid: bool, ground: Node = null) -> Node3D:
 var preview:StaticBody3D=create_between(start,finish,ground);preview.name="FenceDragPreview";preview.remove_from_group("placed_fences");preview.collision_layer=0;preview.collision_mask=0
 for child in preview.get_children():
  if child is CollisionShape3D:child.disabled=true
 set_preview_valid(preview,valid);return preview

static func create_anchor_preview(position: Vector3) -> Node3D:
 var root:=Node3D.new();root.name="FenceDragPreview";root.global_position=position
 var marker:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=.07;mesh.bottom_radius=.13;mesh.height=1.55;mesh.radial_segments=6;marker.mesh=mesh;marker.position.y=.775;root.add_child(marker)
 set_preview_valid(root,true);return root

static func set_preview_valid(preview:Node3D,valid:bool)->void:
 var material:=StandardMaterial3D.new();material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(.12,1,.24,.82) if valid else Color(1,.06,.03,.85);material.emission_enabled=true;material.emission=Color(.08,.9,.16) if valid else Color(1,.03,.01);material.emission_energy_multiplier=1.8;material.no_depth_test=true
 for node in preview.find_children("*","MeshInstance3D",true,false):(node as MeshInstance3D).material_override=material

static func _height(ground:Node,point:Vector3,fallback:float)->float:
 if ground and ground.has_method("surface_height"):
  return float(ground.call("surface_height",Vector2(point.x,point.z)))+0.02
 return fallback
