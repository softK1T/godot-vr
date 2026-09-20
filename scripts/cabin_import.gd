@tool
extends EditorScenePostImport
## Builds optimized cabin collision and interaction bodies from collision_manifest.json.

const DOOR_SCRIPT := preload("res://scripts/cabin_door.gd")
const STOVE_SCRIPT := preload("res://scripts/wood_stove.gd")

const ATTACHED_GROUPS := {
	"COL_Bed": "Bed",
	"COL_Storage_Chest": "Storage_Chest",
	"COL_Cupboard": "Cupboard",
	"COL_Stove_Body": "Stove_Body",
	"COL_Food_Prep_Counter": "Food_Prep_Counter",
	"COL_Table": "Table",
	"COL_Chair_01": "Chair_01",
	"COL_Chair_02": "Chair_02",
}

func _post_import(scene: Node) -> Object:
	var manifest_path := get_source_file().get_base_dir().path_join("collision_manifest.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		push_error("Cabin collision manifest is missing or invalid: " + manifest_path)
		return scene
	var groups_variant: Variant = (parsed as Dictionary).get("groups", {})
	if not groups_variant is Dictionary:
		push_error("Cabin collision manifest has no groups: " + manifest_path)
		return scene

	var cabin := scene.find_child("Cabin_Structure", true, false) as Node3D
	if cabin == null:
		push_error("Cabin_Structure was not found in the imported GLB.")
		return scene

	_hide_collision_markers(scene)
	for group_variant: Variant in (groups_variant as Dictionary):
		var group := String(group_variant)
		var descriptions_variant: Variant = (groups_variant as Dictionary)[group]
		if not descriptions_variant is Array:
			continue
		var body := _create_body(scene, cabin, group)
		if body == null:
			continue
		_add_shapes(scene, cabin, body, descriptions_variant as Array)

	_configure_windows(scene)
	return scene

func _create_body(scene: Node, cabin: Node3D, group: String) -> PhysicsBody3D:
	if group == "COL_Door":
		var door := scene.find_child("Door_Main", true, false) as Node3D
		if door == null:
			push_error("Door_Main was not found for COL_Door.")
			return null
		var parent := door.get_parent()
		var body := AnimatableBody3D.new()
		body.name = "Physics_COL_Door"
		body.transform = door.transform
		body.collision_layer = 1
		body.collision_mask = 1
		body.set_script(DOOR_SCRIPT)
		parent.add_child(body)
		body.owner = scene
		door.owner = null
		door.reparent(body, false)
		door.transform = Transform3D.IDENTITY
		_set_owner_recursive(door, scene)
		return body

	var parent: Node3D = cabin
	if ATTACHED_GROUPS.has(group):
		parent = scene.find_child(String(ATTACHED_GROUPS[group]), true, false) as Node3D
		if parent == null:
			push_error("Cabin collision target not found for " + group)
			return null
	var old := parent.get_node_or_null("Physics_" + group)
	if old != null:
		old.free()
	var body := StaticBody3D.new()
	body.name = "Physics_" + group
	body.collision_layer = 1
	body.collision_mask = 1
	if group == "COL_Stove_Body":
		body.set_script(STOVE_SCRIPT)
	parent.add_child(body)
	body.owner = scene
	return body

func _add_shapes(scene: Node, cabin: Node3D, body: PhysicsBody3D, descriptions: Array) -> void:
	var body_in_cabin := _relative_transform(body, cabin)
	var to_body := body_in_cabin.affine_inverse()
	for index in descriptions.size():
		var value: Variant = descriptions[index]
		if not value is Dictionary:
			continue
		var description := value as Dictionary
		var collider := CollisionShape3D.new()
		collider.name = "Shape_%02d" % index
		match String(description.get("type", "")):
			"box":
				var box := BoxShape3D.new()
				box.size = _vec(description.get("size", []))
				collider.shape = box
				var authored := Transform3D(
					Basis(Vector3.UP, float(description.get("rotation_y", 0.0))),
					_vec(description.get("center", []))
				)
				collider.transform = to_body * authored
			"convex":
				var convex := ConvexPolygonShape3D.new()
				var points := PackedVector3Array()
				for point: Variant in description.get("points", []):
					if point is Array:
						points.append(to_body * _vec(point as Array))
				convex.points = points
				collider.shape = convex
			_:
				push_warning("Unsupported cabin collision type in " + body.name)
				collider.free()
				continue
		body.add_child(collider)
		collider.owner = scene

func _hide_collision_markers(scene: Node) -> void:
	for node in scene.find_children("COL_*", "Node3D", true, false):
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).visible = false
	var proxies := scene.find_child("Collision_Proxies", true, false) as Node3D
	if proxies != null:
		proxies.visible = false

func _configure_windows(scene: Node) -> void:
	for index in range(1, 5):
		var window := scene.find_child("Window_Glass_%02d" % index, true, false) as MeshInstance3D
		if window == null:
			continue
		window.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := window.get_active_material(0) as StandardMaterial3D
		if material != null:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.metallic = 0.0
			material.roughness = 0.16

func _vec(values: Array) -> Vector3:
	if values.size() < 3:
		return Vector3.ZERO
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != ancestor and current != null:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

func _set_owner_recursive(node: Node, scene: Node) -> void:
	node.owner = scene
	for child in node.get_children():
		_set_owner_recursive(child, scene)
