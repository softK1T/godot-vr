extends StaticBody3D
## Reachable switch by the cabin entrance; independent of the stove fire.

var lights: Array[OmniLight3D] = []
var is_on := true
var lever: MeshInstance3D
var indicator: MeshInstance3D
var lantern: MeshInstance3D
var lantern_surface := -1
var lantern_on_material: Material
var lantern_off_material: Material

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.32, 0.40, 0.18)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	_add_box("WoodenPlate", Vector3(0.30, 0.38, 0.09), Vector3(0, 0, -0.03), Color(0.24, 0.14, 0.085))
	_add_box("IronFrame", Vector3(0.22, 0.24, 0.055), Vector3(0, 0, 0.025), Color(0.15, 0.18, 0.17))
	lever = _add_box("Toggle", Vector3(0.065, 0.17, 0.06), Vector3(0, 0.035, 0.09), Color(0.78, 0.64, 0.37))
	indicator = _add_box("Indicator", Vector3(0.055, 0.035, 0.012), Vector3(0, -0.12, 0.065), Color(1.0, 0.76, 0.38))
	_update_visuals()

func _add_box(label: String, size: Vector3, offset: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = offset
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	node.material_override = material
	add_child(node)
	return node

func configure(interior: OmniLight3D, porch: OmniLight3D) -> void:
	lights.clear()
	if interior: lights.append(interior)
	if porch: lights.append(porch)
	_update_visuals()

func configure_lantern(mesh: MeshInstance3D) -> void:
	lantern = mesh
	if lantern == null or lantern.mesh == null:
		return
	for index in range(lantern.mesh.get_surface_count()):
		var original := lantern.get_active_material(index)
		if original is BaseMaterial3D and original.resource_name.contains("Emissive"):
			lantern_surface = index
			lantern_on_material = original.duplicate()
			var lit := lantern_on_material as BaseMaterial3D
			lit.emission_energy_multiplier = 0.6
			lantern_off_material = original.duplicate()
			var dark := lantern_off_material as BaseMaterial3D
			dark.emission_enabled = false
			dark.albedo_color = Color(0.12, 0.10, 0.075)
			break
	_update_visuals()

func interact(_interactor: Node = null) -> void:
	is_on = not is_on
	_update_visuals()

func get_interaction_text() -> String:
	return "E  Turn cabin lights off" if is_on else "E  Turn cabin lights on"

func _update_visuals() -> void:
	for lamp in lights:
		if is_instance_valid(lamp): lamp.visible = is_on
	if is_instance_valid(lantern) and lantern_surface >= 0:
		lantern.set_surface_override_material(lantern_surface, lantern_on_material if is_on else lantern_off_material)
	if lever: lever.rotation.x = -0.48 if is_on else 0.48
	if indicator:
		(indicator.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.76, 0.38) if is_on else Color(0.22, 0.27, 0.25)
