extends Node3D

const GENERATED_BODY_NAME := "GeneratedCabinCollision"
const DOOR_NODE_NAME := "Cabin_Door_3"
const DOOR_SCRIPT := preload("res://scripts/cabin_door.gd")

func _ready() -> void:
	_configure_visual_shadow_casting()
	build_collision()

func _configure_visual_shadow_casting() -> void:
	var model := get_node_or_null("CabinModel")
	if model == null:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		# Cabin visuals use layer 2 so the global sun cannot light interior-facing surfaces.
		# Local cabin lights and the flashlight explicitly include this layer.
		mesh_instance.layers = 2
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if _is_window_glass(mesh_instance):
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func build_collision() -> void:
	var old_body := get_node_or_null(GENERATED_BODY_NAME)
	if old_body:
		old_body.free()

	var model := get_node_or_null("CabinModel")
	if model == null:
		push_error("CabinModel not found; cabin collision was not generated.")
		return

	var body := StaticBody3D.new()
	body.name = GENERATED_BODY_NAME
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)

	var door_root := model.find_child(DOOR_NODE_NAME, true, false) as Node3D
	var door_body: AnimatableBody3D
	if door_root:
		door_body = AnimatableBody3D.new()
		door_body.name = "InteractiveDoor"
		door_body.set_script(DOOR_SCRIPT)
		door_body.collision_layer = 1
		door_body.collision_mask = 1
		door_body.transform = door_root.transform
		door_root.get_parent().add_child(door_body)
		door_body.setup_from_imported_door(door_root)
	else:
		push_error("Imported cabin door node was not found.")

	var house_inverse := global_transform.affine_inverse()
	var shape_count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or _is_window_glass(mesh_instance):
			continue
		var shape := mesh_instance.mesh.create_trimesh_shape()
		if shape == null:
			continue
		if shape is ConcavePolygonShape3D:
			shape.backface_collision = true

		var collision := CollisionShape3D.new()
		collision.name = "Collision_%s" % mesh_instance.name
		collision.shape = shape
		var owning_door := _find_door_body(mesh_instance)
		if owning_door:
			collision.transform = owning_door.global_transform.affine_inverse() * mesh_instance.global_transform
			owning_door.add_child(collision)
		else:
			collision.transform = house_inverse * mesh_instance.global_transform
			body.add_child(collision)
		shape_count += 1

	if shape_count == 0:
		push_error("No collision shapes were generated for the cabin.")

func _find_door_body(node: Node) -> AnimatableBody3D:
	var current := node
	while current != null and current != self:
		if current is AnimatableBody3D and current.name == "InteractiveDoor":
			return current as AnimatableBody3D
		current = current.get_parent()
	return null

func _is_window_glass(node: Node) -> bool:
	var current: Node = node
	while current != null and current != self:
		if "window_glass" in current.name.to_lower():
			return true
		current = current.get_parent()
	return false
