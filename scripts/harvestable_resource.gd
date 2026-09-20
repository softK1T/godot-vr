extends StaticBody3D
class_name HarvestableResource

@export_enum("tree", "stone", "bush", "berry", "mushroom") var resource_kind := "tree"
@export var amount := 3
@export var respawn_seconds := 210.0
@export var hits_required := 3
var _hits := 0
var _available := true
var _base_scale := Vector3.ONE
var _base_position := Vector3.ZERO
var _base_collision_layer := 1
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_base_scale = scale
	_base_position = position
	_base_collision_layer = collision_layer
	_rng.seed = int(global_position.x * 92821.0 + global_position.z * 68917.0) + 177

func get_interaction_text() -> String:
	if not _available:
		return ""
	match resource_kind:
		"tree": return "Chop tree  %d/%d  [Axe]" % [_hits, hits_required]
		"stone": return "Mine rock  %d/%d  [Pickaxe]" % [_hits, hits_required]
		"bush": return "Cut bush  %d/%d  [Axe]" % [_hits, hits_required]
		"berry": return "E  Pick wild berries"
		_: return "E  Gather mushrooms"

func interact(player: Node) -> void:
	if not _available:
		return
	if resource_kind in ["tree", "stone", "bush"]:
		var required := "pickaxe" if resource_kind == "stone" else "axe"
		if not _player_has_tool(player, required):
			SurvivalState.notification.emit("Equip the %s to gather this resource." % required, Color(1.0, 0.58, 0.3))
			return
		_hits += 1
		_hit_animation()
		SurvivalState.damage_tool(required)
		if _hits < hits_required:
			var hit_text := "Stone chips scatter." if resource_kind == "stone" else ("Branches crack." if resource_kind == "bush" else "The axe bites into the trunk.")
			SurvivalState.notification.emit(hit_text, Color(0.92, 0.74, 0.45))
			return
		match resource_kind:
			"tree":
				SurvivalState.add_item("wood", amount + _rng.randi_range(2, 5), "wood")
			"stone":
				SurvivalState.add_item("stone", amount + _rng.randi_range(1, 3), "stone")
			"bush":
				SurvivalState.add_item("sticks", amount + _rng.randi_range(1, 3), "sticks")
				SurvivalState.add_item("berries", _rng.randi_range(1, 3), "berries")
	else:
		var item := "berries" if resource_kind == "berry" else "mushroom"
		SurvivalState.add_item(item, amount + _rng.randi_range(0, 2), item)
	_deplete()

func _player_has_tool(player: Node, tool: String) -> bool:
	return player != null and player.has_method("has_equipped_tool") and player.has_equipped_tool(tool) and SurvivalState.has_item(tool) and SurvivalState.get_tool_durability(tool) > 0

func _hit_animation() -> void:
	var tween := create_tween()
	tween.tween_property(self, "rotation:z", 0.025, 0.06)
	tween.tween_property(self, "rotation:z", -0.018, 0.08)
	tween.tween_property(self, "rotation:z", 0.0, 0.08)

func _deplete() -> void:
	_available = false
	_hits = 0
	collision_layer = 0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", _base_scale * Vector3(0.12, 0.04, 0.12), 0.38).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "position:y", _base_position.y - 0.2, 0.38)
	await get_tree().create_timer(respawn_seconds).timeout
	_available = true
	collision_layer = _base_collision_layer
	position = _base_position
	var restore := create_tween()
	restore.tween_property(self, "scale", _base_scale, 0.8).set_trans(Tween.TRANS_BACK)
