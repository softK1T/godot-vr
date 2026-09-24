extends Node3D

const LIGHT_SWITCH_SCRIPT := preload("res://scripts/cabin_light_switch.gd")
## Connects the imported cabin to this project's interaction and lighting systems.

@export var add_interior_light := true
@export var add_porch_light := true

func _ready() -> void:
	_configure_visuals()
	_setup_door()
	_setup_stove()
	_setup_lights()
	_setup_light_switch()

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
		fire_light.omni_range = 7.0
		fire_light.shadow_enabled = true
		stove_body.add_child(fire_light)
	# The stove's shadowed flame only lights the opening in the metal casing.
	# A weak, shadowless bounced-light source spreads its warmth across the room.
	var room_fill := stove_body.get_node_or_null("StoveRoomBounce") as OmniLight3D
	if room_fill == null:
		room_fill = OmniLight3D.new()
		room_fill.name = "StoveRoomBounce"
		room_fill.light_color = Color(1.0, 0.59, 0.34)
		room_fill.light_energy = 0.0
		room_fill.light_cull_mask = 2
		room_fill.light_volumetric_fog_energy = 0.0
		room_fill.omni_range = 7.5
		room_fill.omni_attenuation = 1.4
		room_fill.shadow_enabled = false
		stove_body.add_child(room_fill)
	# Keep the bounce light low beside the stove. At (0, 2.2, 0) it sat almost
	# exactly on the ceiling lamp socket and painted a hot spot on the ceiling
	# that looked like the lamp was still on whenever the stove was burning.
	var toward_room := to_global(Vector3.ZERO) - stove_body.global_position
	toward_room.y = 0.0
	room_fill.global_position = stove_body.global_position + toward_room.normalized() * minf(1.2, toward_room.length()) + Vector3(0.0, 1.0, 0.0)
	var fire_socket := find_child("SOCKET_StoveFire", true, false) as Node3D
	if fire_socket != null:
		fire_light.global_position = fire_socket.global_position
	stove_body.configure_visuals(fire_light, embers, room_fill)

func _setup_lights() -> void:
	if add_interior_light:
		_add_socket_light(
			"SOCKET_InteriorLight",
			"InteriorWarmth",
			Color(1.0, 0.72, 0.46),
			1.8,
			6.5,
			Vector3(0.0, -0.35, 0.0)
		)
	if add_porch_light:
		_add_socket_light(
			"SOCKET_PorchLight",
			"PorchLight",
			Color(1.0, 0.73, 0.45),
			1.4,
			4.5,
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

func _setup_light_switch() -> void:
	# The front wall is thick: its inner face is near house z=2.9,
	# not z=3.24 (the outer face). Keep the plate completely inside.
	var switch_body := StaticBody3D.new()
	switch_body.set_script(LIGHT_SWITCH_SCRIPT)
	switch_body.name = "CabinLightSwitch"
	switch_body.position = Vector3(1.12, 1.36, 2.84)
	switch_body.rotation.y = PI
	add_child(switch_body)
	var interior_socket := find_child("SOCKET_InteriorLight", true, false) as Node3D
	var porch_socket := find_child("SOCKET_PorchLight", true, false) as Node3D
	var interior := interior_socket.get_node_or_null("InteriorWarmth") as OmniLight3D if interior_socket else null
	var porch := porch_socket.get_node_or_null("PorchLight") as OmniLight3D if porch_socket else null
	switch_body.configure(interior, porch)
	# The imported lantern has a separate emissive surface that stays bright
	# even when its OmniLight3D is hidden. Switch the mesh surface too.
	var lantern := find_child("Lantern", true, false) as MeshInstance3D
	switch_body.configure_lantern(lantern)
