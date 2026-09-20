extends Node3D
## Connects the imported cabin to this project's interaction and lighting systems.

@export var add_interior_light := true
@export var add_porch_light := true

func _ready() -> void:
	_configure_visuals()
	_setup_door()
	_setup_stove()
	_setup_lights()

func _configure_visuals() -> void:
	var model := get_node_or_null("CabinModel")
	if model == null:
		push_error("CabinModel not found in house scene.")
		return
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		mesh_instance.layers = 2
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if "window_glass" in mesh_instance.name.to_lower():
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _setup_door() -> void:
	var door := find_child("Door_Main", true, false) as Node3D
	if door == null:
		push_error("Door_Main was not found in the imported cabin.")
		return
	var door_body := door.get_parent() as AnimatableBody3D
	if door_body == null or door_body.name != "Physics_COL_Door":
		push_error("Door collision was not generated. Reimport the GLB with cabin_import.gd.")
		return
	door_body.open_angle_degrees = -105.0

func _setup_stove() -> void:
	var stove := find_child("Stove_Body", true, false) as Node3D
	if stove == null:
		push_error("Stove_Body was not found in the imported cabin.")
		return
	var stove_body := stove.get_node_or_null("Physics_COL_Stove_Body") as StaticBody3D
	if stove_body == null or not stove_body.has_method("interact"):
		push_error("Interactive stove collision was not generated.")
		return
	var embers := find_child("Stove_Embers", true, false) as MeshInstance3D
	if embers != null:
		embers.visible = false
		embers.reparent(stove_body, true)
		embers.name = "Flame"
	var fire_light := stove_body.get_node_or_null("FireLight") as OmniLight3D
	if fire_light == null:
		fire_light = OmniLight3D.new()
		fire_light.name = "FireLight"
		fire_light.light_color = Color(1.0, 0.37, 0.1)
		fire_light.light_energy = 0.0
		fire_light.light_cull_mask = 2
		fire_light.light_volumetric_fog_energy = 0.2
		fire_light.omni_range = 4.5
		fire_light.shadow_enabled = true
		stove_body.add_child(fire_light)
	var fire_socket := find_child("SOCKET_StoveFire", true, false) as Node3D
	if fire_socket != null:
		fire_light.global_position = fire_socket.global_position
	stove_body.configure_visuals(fire_light, embers)

func _setup_lights() -> void:
	if add_interior_light:
		_add_socket_light(
			"SOCKET_InteriorLight",
			"InteriorWarmth",
			Color(1.0, 0.72, 0.46),
			4.5,
			8.0,
			Vector3(0.0, -0.35, 0.0)
		)
	if add_porch_light:
		_add_socket_light(
			"SOCKET_PorchLight",
			"PorchLight",
			Color(1.0, 0.73, 0.45),
			3.5,
			6.0,
			Vector3(0.0, -0.15, -0.25)
		)

func _add_socket_light(
	socket_name: String,
	light_name: String,
	color: Color,
	energy: float,
	radius: float,
	local_offset: Vector3
) -> void:
	var socket := find_child(socket_name, true, false) as Node3D
	if socket == null or socket.get_node_or_null(light_name) != null:
		return
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = local_offset
	light.light_color = color
	light.light_energy = energy
	light.light_cull_mask = 0xFFFFFFFF
	light.light_volumetric_fog_energy = 0.35
	light.omni_range = radius
	light.omni_attenuation = 1.15
	# The authored sockets sit inside the lamp meshes. Shadow maps therefore
	# treat the fixtures themselves as occluders and suppress all illumination.
	light.shadow_enabled = false
	socket.add_child(light)
