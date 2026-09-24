extends StaticBody3D
class_name HarvestableResource

@export_enum("tree", "stone", "bush", "berry", "mushroom", "sapling") var resource_kind := "tree"
@export var amount := 3
@export var respawn_seconds := 210.0
@export_range(1, 10, 1) var regrow_days := 3
@export var hits_required := 3
@export var planted := false
var _hits := 0
var _available := true
var _is_stump := false
var _regrow_at_hour := -1.0
var _base_scale := Vector3.ONE
var _base_position := Vector3.ZERO
var _base_collision_layer := 1
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("harvestable_resources")
	_base_scale = scale; _base_position = position; _base_collision_layer = collision_layer
	_rng.seed = int(global_position.x * 92821.0 + global_position.z * 68917.0) + 177
	if resource_kind == "sapling":
		_regrow_at_hour = float(SurvivalState.day - 1 + regrow_days) * 24.0 + SurvivalState.time_of_day
	call_deferred("_capture_planted_position")

func _capture_planted_position() -> void: _base_position = position

func _process(_delta: float) -> void:
	if _regrow_at_hour < 0.0: return
	var now := float(SurvivalState.day - 1) * 24.0 + SurvivalState.time_of_day
	if now >= _regrow_at_hour:
		_regrow_at_hour = -1.0
		_mature_sapling()

func get_interaction_text() -> String:
	if not _available: return ""
	if _is_stump: return "Uproot stump  %d/%d  [Axe]" % [_hits, hits_required]
	match resource_kind:
		"tree": return "Chop tree  %d/%d  [Axe]" % [_hits, hits_required]
		"stone": return "Mine rock  %d/%d  [Pickaxe]" % [_hits, hits_required]
		"bush": return "Cut bush  %d/%d  [Axe]" % [_hits, hits_required]
		"berry": return "E  Pick berries   [Axe: uproot]"
		"sapling": return "Young tree - growing"
		_: return "E  Gather mushrooms"

func interact(player: Node) -> void:
	if not _available or resource_kind == "sapling": return
	if resource_kind in ["tree", "stone", "bush"]:
		var tool_name := "pickaxe" if resource_kind == "stone" else "axe"
		if not _has_tool(player, tool_name):
			SurvivalState.notification.emit("Equip the %s." % tool_name, Color(1, .58, .3)); return
		_hits += 1; _hit_animation(); SurvivalState.damage_tool(tool_name)
		_sfx("pick" if resource_kind == "stone" else "chop")
		_burst(_chip_color(), 6, global_position + Vector3(0, 0.5 if resource_kind != "tree" else 1.1, 0), 0.05)
		if _hits < hits_required: return
		if _is_stump:
			SurvivalState.add_item("wood", _rng.randi_range(1, 2), "wood"); _crumble(Color(.32, .21, .12)); return
		match resource_kind:
			"tree":
				SurvivalState.add_item("wood", amount + _rng.randi_range(2, 5), "wood")
				SurvivalState.add_item("sticks", _rng.randi_range(1, 3), "sticks")
				if _rng.randf() < .55: SurvivalState.add_item("sapling", 1, "sapling")
				_fell_tree(player)
			"stone":
				SurvivalState.add_item("stone", amount + _rng.randi_range(1, 3), "stone"); _crumble(Color(.36, .35, .32))
			_:
				SurvivalState.add_item("sticks", amount + _rng.randi_range(1, 3), "sticks"); _crumble(Color(.16, .30, .10))
	else:
		var item := "berries" if resource_kind == "berry" else "mushroom"
		SurvivalState.add_item(item, amount + _rng.randi_range(0, 2), item)
		_pick()

func axe_harvest(player: Node) -> bool:
	if resource_kind != "berry" or not _available or not _has_tool(player, "axe"): return false
	SurvivalState.damage_tool("axe"); SurvivalState.add_item("sticks", _rng.randi_range(2, 4), "sticks")
	if _rng.randf() < .35: SurvivalState.add_item("sapling", 1, "sapling")
	_crumble(Color(.16, .30, .10)); return true

func _has_tool(player: Node, tool_name: String) -> bool:
	return player != null and player.has_method("has_equipped_tool") and player.has_equipped_tool(tool_name) and SurvivalState.has_item(tool_name) and SurvivalState.get_tool_durability(tool_name) > 0
func _chip_color() -> Color:
	if resource_kind == "stone": return Color(.4, .39, .36)
	if resource_kind == "tree" or _is_stump: return Color(.55, .40, .22)
	return Color(.18, .32, .11)
func _hit_animation() -> void:
	var t := create_tween(); t.tween_property(self, "rotation:z", .035, .06); t.tween_property(self, "rotation:z", -.02, .08); t.tween_property(self, "rotation:z", 0.0, .08)

func _burst(color: Color, count: int, at: Vector3, size := 0.08) -> void:
	var root := get_tree().current_scene
	if root == null: return
	var p := CPUParticles3D.new(); p.one_shot = true; p.amount = count; p.lifetime = 1.1; p.explosiveness = .92
	p.direction = Vector3.UP; p.spread = 70.0; p.initial_velocity_min = 1.4; p.initial_velocity_max = 3.4; p.gravity = Vector3(0, -8, 0)
	p.scale_amount_min = .6; p.scale_amount_max = 1.3
	var bm := BoxMesh.new(); bm.size = Vector3.ONE * size; var mat := StandardMaterial3D.new(); mat.albedo_color = color; bm.material = mat; p.mesh = bm
	root.add_child(p); p.global_position = at; p.emitting = true
	get_tree().create_timer(1.8).timeout.connect(p.queue_free)

func _fell_tree(player: Node) -> void:
	_available = false; collision_layer = 0
	var pivot := Node3D.new(); pivot.name = "FallingTree"; add_child(pivot)
	for c in get_children():
		if c == pivot: continue
		if c is CollisionShape3D: (c as CollisionShape3D).set_deferred("disabled", true)
		elif c is Node3D: (c as Node3D).reparent(pivot)
	var yaw := _rng.randf() * TAU
	if player is Node3D:
		var away := to_local(global_position + (global_position - (player as Node3D).global_position))
		yaw = atan2(away.x, away.z)
	pivot.rotation.y = yaw
	_make_stump()
	_sfx("tree_fall", 3.0)
	var t := create_tween()
	t.tween_property(pivot, "rotation:x", 1.47, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): _burst(Color(.18, .33, .12), 28, pivot.to_global(Vector3(0, 3.2, 0)), 0.1); _burst(Color(.42, .34, .22), 14, pivot.to_global(Vector3(0, 1.5, 0)), 0.07))
	t.tween_property(pivot, "rotation:x", 1.36, .15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(pivot, "rotation:x", 1.47, .18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): collision_layer = _base_collision_layer; _available = true)
	t.tween_interval(1.2)
	t.tween_property(pivot, "scale", Vector3.ONE * 0.001, .6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(pivot.queue_free)

func _make_stump() -> void:
	var inv := Vector3(1.0 / maxf(scale.x, .01), 1.0 / maxf(scale.y, .01), 1.0 / maxf(scale.z, .01))
	var stump := MeshInstance3D.new(); stump.name = "Stump"; var cm := CylinderMesh.new(); cm.top_radius = .26; cm.bottom_radius = .36; cm.height = .55; cm.radial_segments = 7
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(.30, .20, .12); cm.material = mat; stump.mesh = cm; stump.scale = inv; stump.position.y = .2 * inv.y; add_child(stump)
	var top := MeshInstance3D.new(); var tm := CylinderMesh.new(); tm.top_radius = .25; tm.bottom_radius = .25; tm.height = .02; tm.radial_segments = 7
	var tmat := StandardMaterial3D.new(); tmat.albedo_color = Color(.62, .47, .28); tm.material = tmat; top.mesh = tm; top.position.y = .28; stump.add_child(top)
	var cs := CollisionShape3D.new(); var cyl := CylinderShape3D.new(); cyl.radius = .36 * inv.x; cyl.height = .6 * inv.y; cs.shape = cyl; cs.position.y = .2 * inv.y; add_child(cs)
	_is_stump = true; resource_kind = "bush"; hits_required = 2; _hits = 0

func _crumble(color: Color) -> void:
	_available = false; collision_layer = 0
	_burst(color, 18, global_position + Vector3(0, .45, 0))
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "scale", Vector3(scale.x * 1.15, scale.y * .05, scale.z * 1.15), .45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(self, "position:y", position.y - .15, .45)
	t.chain().tween_callback(queue_free)

func _berry_meshes() -> Array:
	var out := []
	for m in find_children("*", "MeshInstance3D", true, false):
		var mesh = (m as MeshInstance3D).mesh
		if mesh is SphereMesh and (mesh as SphereMesh).radius < 0.1: out.append(m)
	return out

func _pick() -> void:
	_sfx("pickup", -3.0)
	_available = false; collision_layer = 0
	if resource_kind == "berry":
		for b in _berry_meshes(): (b as Node3D).visible = false
		_hit_animation()
	else:
		var t := create_tween(); t.tween_property(self, "scale", _base_scale * 1.15, .08); t.tween_property(self, "scale", _base_scale * .02, .22)
		t.tween_callback(func(): visible = false)
	get_tree().create_timer(respawn_seconds).timeout.connect(_regrow)

func _regrow() -> void:
	if not is_inside_tree(): return
	for b in _berry_meshes(): (b as Node3D).visible = true
	visible = true
	if resource_kind == "mushroom": scale = _base_scale * .02; create_tween().tween_property(self, "scale", _base_scale, .8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	collision_layer = _base_collision_layer; _available = true; _hits = 0

func _mature_sapling() -> void:
	var parent := get_parent()
	if parent and parent.has_method("grow_tree_at"): parent.call("grow_tree_at", global_position, self)

func _sfx(sound: String, volume_db := 0.0) -> void:
	var audio := get_tree().get_first_node_in_group("world_audio")
	if audio: audio.call("play_at", sound, global_position + Vector3(0, 0.8, 0), volume_db)

# Used by the save system: show a stump without the falling animation.
func restore_stump() -> void:
	for c in get_children():
		if c is CollisionShape3D: (c as CollisionShape3D).disabled = true
		elif c is Node3D: (c as Node3D).visible = false
	_make_stump()
