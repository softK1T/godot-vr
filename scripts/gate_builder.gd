extends Node
class_name GateBuilder
const GATE_MODEL := preload("res://assets/cozy_homestead/gate.glb")
const WICKET_MODEL := preload("res://assets/cozy_homestead/gate_single.glb")

static func _mesh_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box

static func _box_body(body_name: String, box: AABB, offset: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(box.size.x, .08), maxf(box.size.y, .08), maxf(box.size.z, .08))
	shape.shape = bs
	shape.position = box.get_center() + offset
	body.add_child(shape)
	return body

# Wraps a leaf in a pivot placed on its hinge axis so it swings like a real gate.
static func _make_leaf(root: Node3D, leaf: Node3D, pivot_name: String, hinge_on_min_x: bool, offset: Vector3) -> Node3D:
	var box := _mesh_aabb(leaf)
	var hinge_x: float = box.position.x if hinge_on_min_x else box.end.x
	var hinge := Vector3(hinge_x, 0.0, box.get_center().z)
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = hinge + offset
	root.add_child(pivot)
	leaf.get_parent().remove_child(leaf)
	leaf.position = -hinge
	pivot.add_child(leaf)
	pivot.add_child(_box_body("LeafCollision", box, -hinge))
	return pivot

static func create_for(item: String) -> Node3D:
	return create_wicket() if item == "wicket" else create_gate()

static func create_gate() -> Node3D:
	return _build(GATE_MODEL, "PlacedGate")

# Wicket = the same gate with one leaf (left hinge) and a narrower opening.
static func create_wicket() -> Node3D:
	return _build(WICKET_MODEL, "PlacedWicket")

static func _build(scene: PackedScene, root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	var model := scene.instantiate() as Node3D
	model.name = "GateModel"
	root.add_child(model)
	var post_left := model.find_child("Gate_Post_Left", true, false) as Node3D
	var post_right := model.find_child("Gate_Post_Right", true, false) as Node3D
	var left_center: Vector3 = _mesh_aabb(post_left).get_center() if post_left else Vector3.ZERO
	var right_center: Vector3 = _mesh_aabb(post_right).get_center() if post_right else left_center + Vector3(3.0, 0.0, 0.0)
	# Origin = centre of the left post, so snapping and placement work with real post positions.
	var offset := Vector3(-left_center.x, 0.0, -left_center.z)
	model.position = offset
	var latch := model.find_child("InteractiveGate", true, false) as Node3D
	if latch:
		latch.name = "GateLatch"
	var left := model.find_child("Gate_Leaf_Left", true, false) as Node3D
	var right := model.find_child("Gate_Leaf_Right", true, false) as Node3D
	var left_pivot: Node3D = _make_leaf(root, left, "InteractiveGate", true, offset) if left else null
	var right_pivot: Node3D = _make_leaf(root, right, "InteractiveGateRight", false, offset) if right else null
	if latch and left_pivot:
		var target: Node3D = right_pivot if right_pivot and _mesh_aabb(latch).get_center().x > (left_center.x + right_center.x) * 0.5 else left_pivot
		latch.get_parent().remove_child(latch)
		latch.position = offset - target.position
		target.add_child(latch)
	for post in [post_left, post_right]:
		if post:
			root.add_child(_box_body(String(post.name) + "_Collision", _mesh_aabb(post), offset))
	if left_pivot == null:
		var fallback := Node3D.new()
		fallback.name = "InteractiveGate"
		root.add_child(fallback)
	var right_local := Vector3(right_center.x - left_center.x, 0.0, right_center.z - left_center.z)
	# Snap points: both posts. Fences and other gates attach here.
	root.set_meta("post_positions", [Vector3.ZERO, right_local])
	root.set_meta("gate_span", Vector2(right_local.x, right_local.z).length())
	root.add_to_group("gate_snap")
	root.set_script(load("res://scripts/placeable_gate.gd"))
	return root

static func create_preview(item: String = "gate") -> Node3D:
	var gate := create_for(item)
	gate.name = "GatePlacementPreview"
	gate.remove_from_group("gate_snap")
	gate.set_script(null)
	for body in gate.find_children("*", "CollisionObject3D", true, false):
		(body as CollisionObject3D).collision_layer = 0
		(body as CollisionObject3D).collision_mask = 0
	for shape in gate.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = true
	set_preview_valid(gate, true)
	return gate

static func set_preview_valid(preview: Node3D, valid: bool) -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(.16, 1, .3, .55) if valid else Color(1, .1, .05, .6)
	material.no_depth_test = true
	for node in preview.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = material
