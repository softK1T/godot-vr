extends Area3D
## One chop for each new physical contact between the axe blade and a tree collider.

var player: CharacterBody3D
var strike_point: Node3D
var axe_eye: Node3D
var enabled := false
var emulated_velocity := Vector3.ZERO
var _previous_tip := Vector3.ZERO
var _previous_eye := Vector3.ZERO
var _touching_resources: Dictionary = {}
var _blade_probe := SphereShape3D.new()

func configure(owner_player: CharacterBody3D, tip: Node3D, eye: Node3D) -> void:
	player = owner_player
	strike_point = tip
	axe_eye = eye
	_previous_tip = tip.global_position
	_previous_eye = eye.global_position
	_touching_resources.clear()
	_blade_probe.radius = 0.13
	collision_mask = 3
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if not enabled or not is_instance_valid(player) or not player.has_equipped_tool("axe"):
		return
	var target := body
	while target and not target is HarvestableResource:
		target = target.get_parent() as Node3D
	if target is HarvestableResource and target.resource_kind == "tree":
		var id := target.get_instance_id()
		if not _touching_resources.has(id):
			_touching_resources[id] = true
			target.interact(player)
			print("VR AXE CONTACT: ", target.name)

func _on_body_exited(body: Node3D) -> void:
	var target := body
	while target and not target is HarvestableResource:
		target = target.get_parent() as Node3D
	if target is HarvestableResource:
		_touching_resources.erase(target.get_instance_id())

func reset_contacts() -> void:
	_touching_resources.clear()
	if is_instance_valid(strike_point) and is_instance_valid(axe_eye):
		_previous_tip = strike_point.global_position
		_previous_eye = axe_eye.global_position

func _physics_process(_delta: float) -> void:
	if not enabled or not is_instance_valid(player) or not is_instance_valid(strike_point) or not is_instance_valid(axe_eye):
		return
	var tip := strike_point.global_position
	var eye := axe_eye.global_position
	# Physics hitbox represents the full steel edge, not just a tip point.
	var midpoint := eye.lerp(tip, 0.65)
	global_position = midpoint
	if not player.has_equipped_tool("axe"):
		_touching_resources.clear()
		_previous_tip = tip
		_previous_eye = eye
		return
	# Probe the real physics colliders along the visible blade, including intermediate
	# poses so a quick hand movement cannot skip straight through a thin trunk.
	var current := _contacts_on_blade(eye, tip)
	var encountered := current.duplicate()
	var distance_moved := maxf(_previous_eye.distance_to(eye), _previous_tip.distance_to(tip))
	var steps := clampi(ceili(distance_moved / 0.08), 1, 20)
	for step in range(1, steps):
		var t := float(step) / float(steps)
		for id in _contacts_on_blade(_previous_eye.lerp(eye, t), _previous_tip.lerp(tip, t)):
			encountered[id] = true
	for id in encountered:
		if not _touching_resources.has(id):
			var resource := instance_from_id(id) as HarvestableResource
			if is_instance_valid(resource) and resource.collision_layer != 0:
				resource.interact(player)
				print("VR AXE HIT: ", resource.name, " (", resource.resource_kind, ")")
	# Only retain contacts still physically overlapping: withdraw then touch again.
	_touching_resources = current
	_previous_tip = tip
	_previous_eye = eye

func _contacts_on_blade(eye: Vector3, tip: Vector3) -> Dictionary:
	var contacts := {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _blade_probe
	query.collision_mask = 3
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [player.get_rid()]
	var steps := maxi(2, ceili(eye.distance_to(tip) / 0.065))
	for index in range(steps + 1):
		var point := eye.lerp(tip, float(index) / float(steps))
		query.transform = Transform3D(Basis.IDENTITY, point)
		for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
			var node := hit.get("collider") as Node
			while node and not node is HarvestableResource:
				node = node.get_parent()
			if node is HarvestableResource:
				var resource := node as HarvestableResource
				if resource.resource_kind in ["tree", "bush"] and resource.collision_layer != 0:
					contacts[resource.get_instance_id()] = true
	# Tree models have scaled and offset CollisionShape3D nodes. Check each actual
	# collision shape as well: older imports/layers can defeat intersect_shape().
	for node in get_tree().get_nodes_in_group("harvestable_resources"):
		if not node is HarvestableResource:
			continue
		var resource := node as HarvestableResource
		if resource.resource_kind not in ["tree", "bush"] or resource.collision_layer == 0:
			continue
		if resource.global_position.distance_to(tip) > 8.0:
			continue
		for child in resource.get_children():
			if not child is CollisionShape3D:
				continue
			var collider := child as CollisionShape3D
			if collider.disabled or collider.shape == null:
				continue
			var local_eye := collider.to_local(eye)
			var local_tip := collider.to_local(tip)
			var local_scale := collider.global_transform.basis.get_scale().abs()
			var tolerance := 0.09 / maxf(minf(local_scale.x, local_scale.z), 0.01)
			var radius := 0.0
			var half_height := 0.0
			if collider.shape is CylinderShape3D:
				var cylinder := collider.shape as CylinderShape3D
				radius = cylinder.radius
				half_height = cylinder.height * 0.5
			elif collider.shape is CapsuleShape3D:
				var capsule := collider.shape as CapsuleShape3D
				radius = capsule.radius
				half_height = capsule.height * 0.5
			elif collider.shape is SphereShape3D:
				radius = (collider.shape as SphereShape3D).radius
				half_height = radius
			else:
				continue
			var trunk_start := Vector3(0, -half_height, 0)
			var trunk_end := Vector3(0, half_height, 0)
			var nearest := Geometry3D.get_closest_points_between_segments(local_eye, local_tip, trunk_start, trunk_end)
			if nearest.size() == 2 and nearest[0].distance_to(nearest[1]) <= radius + tolerance:
				contacts[resource.get_instance_id()] = true
				break
	return contacts
