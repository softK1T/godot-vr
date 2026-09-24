extends Node
class_name FarmBedBuilder
const BED_EMPTY := preload("res://assets/cozy_homestead/farm_bed_empty.glb")
const BED_SEEDED := preload("res://assets/cozy_homestead/farm_bed_seeded.glb")
const BED_SPROUTS := preload("res://assets/cozy_homestead/farm_bed_sprouts.glb")
const BED_GROWN := preload("res://assets/cozy_homestead/farm_bed_grown.glb")

# Copies the children of `holder_name` (optionally filtered by name) out of a bed model.
static func _extract(scene: PackedScene, holder_name: String, stage_name: String, filter: String = "") -> Node3D:
	var src := scene.instantiate() as Node3D
	var out := Node3D.new()
	out.name = stage_name
	out.visible = false
	var holder := src.find_child(holder_name, true, false)
	if holder:
		for c in holder.get_children():
			if filter == "" or String(c.name).contains(filter):
				out.add_child(c.duplicate())
	src.free()
	return out

static func create_bed() -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "PlacedFarmBed"
	root.set_script(load("res://scripts/placeable_farm_bed.gd"))
	var model := BED_EMPTY.instantiate() as Node3D
	model.name = "BedModel"
	var unused := model.find_child("Plants", true, false)
	if unused:
		unused.get_parent().remove_child(unused)
		unused.free()
	root.add_child(model)
	var plants := Node3D.new()
	plants.name = "Plants"
	plants.visible = false
	root.add_child(plants)
	plants.add_child(_extract(BED_SEEDED, "Soil", "Seeded", "Furrow"))
	plants.add_child(_extract(BED_SPROUTS, "Plants", "Sprouts"))
	plants.add_child(_extract(BED_GROWN, "Plants", "Grown"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.42, .44, 1.82)
	shape.shape = box
	shape.position.y = .22
	root.add_child(shape)
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
