extends Node
class_name FenceBuilder

const MIN_LENGTH := 1.0
const POST_SPACING := 1.0

static func create_fence(length: float = 3.0) -> StaticBody3D:
 length = maxf(MIN_LENGTH, length)
 var root := StaticBody3D.new();root.name = "PlacedFence";root.set_script(load("res://scripts/destructible_fence.gd"));root.set("fence_label","low fence");root.set("wood_return",maxi(1,floori(length*.5)))
 var wood := StandardMaterial3D.new();wood.albedo_color=Color(.29,.13,.045);wood.roughness=.94
 var cut := StandardMaterial3D.new();cut.albedo_color=Color(.46,.26,.11);cut.roughness=.9
 var spans := maxi(1, ceili(length / POST_SPACING));var spacing := length / float(spans)
 for i in spans + 1:
  var x := float(i)*spacing
  var post:=MeshInstance3D.new();var pm:=CylinderMesh.new();pm.top_radius=.105;pm.bottom_radius=.145;pm.height=1.25;pm.radial_segments=6;pm.material=wood;post.mesh=pm;post.position=Vector3(x,.625,0);root.add_child(post)
  var cap:=MeshInstance3D.new();var cm:=CylinderMesh.new();cm.top_radius=0;cm.bottom_radius=.11;cm.height=.24;cm.radial_segments=6;cm.material=cut;cap.mesh=cm;cap.position=Vector3(x,1.37,0);root.add_child(cap)
 for span in spans:
  var center_x := (float(span)+.5)*spacing
  for y in [.42,.88]:
   var rail:=MeshInstance3D.new();var rm:=BoxMesh.new();rm.size=Vector3(spacing+.06,.16,.12);rm.material=wood;rail.mesh=rm;rail.position=Vector3(center_x,y,0);rail.rotation.z=.012 if (span+int(y*10))%2==0 else -.012;root.add_child(rail)
  var slats := maxi(1, floori(spacing/.34))
  for slat_i in slats:
   var t := (float(slat_i)+.5)/float(slats);var x := float(span)*spacing+t*spacing
   var slat:=MeshInstance3D.new();var sm:=BoxMesh.new();sm.size=Vector3(.14,.92,.105);sm.material=wood;slat.mesh=sm;slat.position=Vector3(x,.67,-.07);slat.rotation.z=.018 if (span+slat_i)%2==0 else -.018;root.add_child(slat)
 var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(length+.28,1.45,.32);shape.shape=box;shape.position=Vector3(length*.5,.725,0);root.add_child(shape)
 return root

static func align_between(fence: Node3D, start: Vector3, finish: Vector3) -> void:
 var flat:=finish-start;flat.y=0
 fence.position=start
 fence.rotation=Vector3(0,atan2(-flat.z,flat.x),0)

static func create_between(start: Vector3, finish: Vector3) -> StaticBody3D:
 var flat:=finish-start;flat.y=0
 var fence:=create_fence(flat.length());align_between(fence,start,finish);return fence

static func create_preview_between(start: Vector3, finish: Vector3, valid: bool) -> Node3D:
 var preview:StaticBody3D=create_between(start,finish);preview.name="FenceDragPreview";preview.collision_layer=0;preview.collision_mask=0
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
