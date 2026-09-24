extends Node
## Runtime optimisation for desktop and WebXR. Runs once after the world is generated:
## batches repeated static decor meshes of the forest into chunked MultiMeshes,
## adds visibility ranges to small/medium geometry and drops shadows on tiny decor.

const CHUNK := 24.0
const MIN_BATCH := 4
const SMALL_SIZE := 1.4
const MEDIUM_SIZE := 12.0


func _ready() -> void:
	for i in 4:
		await get_tree().process_frame
	var root := get_tree().current_scene
	if root == null:
		return
	var batched := 0
	var multimeshes := 0
	var generators: Array[Node] = []
	_find_by_script(root, "forest_generator.gd", generators)
	if generators.is_empty():
		print("WorldOptimizer: no forest_generator node in the scene")
	for gen in generators:
		var total := gen.find_children("*", "MeshInstance3D", true, false)
		var ok := 0
		for m in total:
			if _batchable(m as MeshInstance3D, gen):
				ok += 1
		print("WorldOptimizer: %s has %d mesh instances, %d batchable" % [gen.name, total.size(), ok])
	for gen in generators:
		var r := _batch_subtree(gen)
		batched += r.x
		multimeshes += r.y
	var ranged := _apply_ranges(root)
	print("WorldOptimizer: batched %d meshes into %d multimeshes, visibility ranges on %d" % [batched, multimeshes, ranged])


func _find_by_script(node: Node, file_name: String, out: Array[Node]) -> void:
	var script := node.get_script() as Script
	if script != null and script.resource_path.ends_with(file_name):
		out.append(node)
		return
	for child in node.get_children():
		_find_by_script(child, file_name, out)


func _has_surface_overrides(mi: MeshInstance3D) -> bool:
	for s in mi.get_surface_override_material_count():
		if mi.get_surface_override_material(s) != null:
			return true
	return false


func _batchable(mi: MeshInstance3D, gen: Node) -> bool:
	if mi.mesh == null or mi.transparency > 0.0 or not mi.visible:
		return false
	if mi.get_child_count() > 0 or mi.get_script() != null or mi.skeleton != NodePath(".."):
		if mi.get_child_count() > 0 or mi.get_script() != null:
			return false
	if _user_groups(mi):
		return false
	var n: Node = mi.get_parent()
	while n != null and n != gen:
		if n is CollisionObject3D or n is Skeleton3D or n.get_script() != null or _user_groups(n):
			return false
		for c in n.get_children():
			if c is AnimationPlayer:
				return false
		n = n.get_parent()
	return n == gen


func _user_groups(n: Node) -> bool:
	for g in n.get_groups():
		if not String(g).begins_with("_"):
			return true
	return false


func _batch_subtree(gen: Node) -> Vector2i:
	var groups := {}
	for n in gen.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not _batchable(mi, gen):
			continue
		var mat: Material = mi.material_override
		if mat == null:
			if mi.mesh.get_surface_count() == 1:
				mat = mi.get_surface_override_material(0)
			elif _has_surface_overrides(mi):
				continue
		var p := mi.global_position
		var key := "%d|%d|%d|%d" % [mi.mesh.get_rid().get_id(), mat.get_rid().get_id() if mat else 0, floori(p.x / CHUNK), floori(p.z / CHUNK)]
		if not groups.has(key):
			groups[key] = {"mat": mat, "items": []}
		(groups[key]["items"] as Array).append(mi)
	var batched := 0
	var made := 0
	for key in groups:
		var items: Array = groups[key]["items"]
		if items.size() < MIN_BATCH:
			continue
		var first := items[0] as MeshInstance3D
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = first.mesh
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, (items[i] as MeshInstance3D).global_transform)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "BatchedDecor"
		mmi.multimesh = mm
		mmi.material_override = groups[key]["mat"]
		mmi.cast_shadow = first.cast_shadow
		mmi.visibility_range_end = first.visibility_range_end if first.visibility_range_end > 0.0 else 110.0
		mmi.top_level = true
		gen.add_child(mmi)
		mmi.global_transform = Transform3D.IDENTITY
		for m in items:
			(m as Node).queue_free()
		batched += items.size()
		made += 1
	_cleanup_empty(gen, gen)
	return Vector2i(batched, made)


func _live_children(n: Node) -> int:
	var count := 0
	for c in n.get_children():
		if not c.is_queued_for_deletion():
			count += 1
	return count


func _cleanup_empty(n: Node, gen: Node) -> void:
	for c in n.get_children():
		if not c.is_queued_for_deletion():
			_cleanup_empty(c, gen)
	if n != gen and n.get_class() == "Node3D" and n.get_script() == null and not _user_groups(n) and _live_children(n) == 0:
		n.queue_free()


func _excluded(g: Node) -> bool:
	if g is GPUParticles3D or g is CPUParticles3D:
		return true
	var n: Node = g
	while n != null:
		if n is Camera3D or n is XROrigin3D or n is XRController3D or n is CharacterBody3D or n is CanvasLayer:
			return true
		if String(n.name).to_lower().contains("cabin") or String(n.name).to_lower().contains("water"):
			return true
		n = n.get_parent()
	return false


func _apply_ranges(root: Node) -> int:
	var count := 0
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.is_queued_for_deletion() or g.visibility_range_end > 0.0 or g is MultiMeshInstance3D or _excluded(g):
			continue
		var sc := g.global_transform.basis.get_scale()
		var s := g.get_aabb().size.length() * maxf(absf(sc.x), maxf(absf(sc.y), absf(sc.z)))
		if s <= 0.0 or s > MEDIUM_SIZE:
			continue
		g.visibility_range_end = 70.0 if s < SMALL_SIZE * 2.0 else 130.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if s < SMALL_SIZE:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		count += 1
	return count
