extends Node
class_name FarmBedBuilder

static func create_bed() -> StaticBody3D:
 var root:=StaticBody3D.new();root.name="PlacedFarmBed";root.set_script(load("res://scripts/placeable_farm_bed.gd"))
 var wood:=StandardMaterial3D.new();wood.albedo_color=Color(.31,.14,.055);wood.roughness=.94
 var soil:=StandardMaterial3D.new();soil.albedo_color=Color(.16,.075,.03);soil.roughness=1
 var leaf:=StandardMaterial3D.new();leaf.albedo_color=Color(.12,.42,.07);leaf.roughness=.9
 for x in [-1.12,1.12]:
  var edge:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(.14,.28,1.65);mesh.material=wood;edge.mesh=mesh;edge.position=Vector3(x,.14,0);root.add_child(edge)
 for z in [-.82,.82]:
  var edge:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(2.38,.28,.14);mesh.material=wood;edge.mesh=mesh;edge.position=Vector3(0,.14,z);root.add_child(edge)
 var dirt:=MeshInstance3D.new();var dm:=BoxMesh.new();dm.size=Vector3(2.12,.18,1.48);dm.material=soil;dirt.mesh=dm;dirt.position.y=.18;root.add_child(dirt)
 var plants:=Node3D.new();plants.name="Plants";plants.visible=false;plants.position.y=.27;root.add_child(plants)
 for row in 2:
  for col in 5:
   var plant:=MeshInstance3D.new();var pm:=CylinderMesh.new();pm.top_radius=0;pm.bottom_radius=.13;pm.height=.44;pm.radial_segments=5;pm.material=leaf;plant.mesh=pm;plant.position=Vector3(-.8+col*.4,.22,-.36+row*.72);plant.rotation.z=(-.14 if (row+col)%2 else .14);plants.add_child(plant)
 var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2.4,.34,1.7);shape.shape=box;shape.position.y=.17;root.add_child(shape)
 return root


static func create_preview() -> Node3D:
 var preview: StaticBody3D = create_bed()
 preview.name = "FarmBedPlacementPreview"
 preview.set_script(null)
 preview.collision_layer = 0
 preview.collision_mask = 0
 for child in preview.get_children():
  if child is CollisionShape3D:
   child.disabled = true
 set_preview_valid(preview, true)
 return preview

static func set_preview_valid(preview: Node3D, valid: bool) -> void:
 var material := StandardMaterial3D.new()
 material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 material.albedo_color = Color(0.22, 1.0, 0.32, 0.46) if valid else Color(1.0, 0.12, 0.08, 0.5)
 material.no_depth_test = true
 for node in preview.find_children("*", "MeshInstance3D", true, false):
  (node as MeshInstance3D).material_override = material
