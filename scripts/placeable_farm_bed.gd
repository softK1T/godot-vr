extends Node3D
class_name PlaceableFarmBed

var growth_stage := 0
var growing := false
var watered := false
var growth_seconds := 95.0
var _growth_left := 0.0
var _plants: Node3D
var _dismantle_hits := 0
var _dismantling := false

func _ready() -> void:
	_plants = get_node_or_null("Plants")

func _process(delta: float) -> void:
	if not growing:
		return
	_growth_left -= delta * (1.55 if watered else 1.0)
	var new_stage := clampi(1 + int((1.0 - _growth_left / growth_seconds) * 2.0), 1, 3)
	if new_stage != growth_stage:
		growth_stage = new_stage
		_update_plants()
	if _growth_left <= 0.0:
		growing = false
		growth_stage = 3
		_update_plants()
		SurvivalState.notification.emit("Your placed farm bed is ready to harvest.", Color(0.7, 1.0, 0.45))

func get_interaction_text() -> String:
	if _dismantling:
		return ""
	if growth_stage == 0:
		return "Plant seeds in farm bed" if SurvivalState.has_item("seeds") else "Farm bed needs seeds"
	if growth_stage == 3 and not growing:
		return "Harvest vegetables"
	return "Water crops" if not watered else "Crops growing..."

func interact(_player: Node) -> void:
	if growth_stage == 0:
		if SurvivalState.remove_item("seeds"):
			growth_stage = 1
			growing = true
			watered = false
			_growth_left = growth_seconds
			_update_plants()
			SurvivalState.notification.emit("Seeds planted in the new farm bed.", Color(0.62, 1.0, 0.45))
		else:
			SurvivalState.notification.emit("You need seeds.", Color(1.0, 0.55, 0.3))
	elif growth_stage == 3 and not growing:
		SurvivalState.add_item("vegetables", 5, "vegetables")
		SurvivalState.add_item("seeds", 2, "seeds")
		growth_stage = 0
		watered = false
		_update_plants()
	elif not watered:
		watered = true
		SurvivalState.notification.emit("The crops have been watered.", Color(0.48, 0.82, 1.0))

func _update_plants() -> void:
	if not _plants:
		return
	_plants.visible = growth_stage > 0
	if _plants.has_node("Grown"):
		_plants.scale = Vector3.ONE
		(_plants.get_node("Seeded") as Node3D).visible = growth_stage == 1
		(_plants.get_node("Sprouts") as Node3D).visible = growth_stage == 2
		(_plants.get_node("Grown") as Node3D).visible = growth_stage == 3
		return
	var scale_value: float = float([0.02, 0.32, 0.68, 1.0][growth_stage])
	_plants.scale = Vector3.ONE * scale_value

func dismantle(player: Node) -> void:
	if _dismantling:
		return
	if not (player and player.has_method("has_equipped_tool") and player.has_equipped_tool("axe") and SurvivalState.has_item("axe") and SurvivalState.get_tool_durability("axe") > 0):
		SurvivalState.notification.emit("Equip the axe to dismantle this farm bed.", Color(1.0, 0.58, 0.3))
		return
	_dismantle_hits += 1
	SurvivalState.damage_tool("axe")
	var tween := create_tween();tween.tween_property(self,"rotation:z",.018,.05);tween.tween_property(self,"rotation:z",-.012,.07);tween.tween_property(self,"rotation:z",0.0,.07)
	if _dismantle_hits < 3:
		SurvivalState.notification.emit("Dismantling farm bed  %d/3" % _dismantle_hits, Color(0.92, 0.74, 0.45))
		return
	_dismantling = true
	for body in find_children("*", "CollisionObject3D", true, false):
		(body as CollisionObject3D).collision_layer = 0
	if growth_stage > 0:
		SurvivalState.add_item("seeds", 1, "seeds")
	SurvivalState.add_item("farm_bed", 1, "farm bed")
	SurvivalState.notification.emit("Farm bed returned to inventory.", Color(0.7, 1.0, 0.48))
	var remove_tween := create_tween();remove_tween.tween_property(self,"scale",scale*Vector3(.8,.05,.8),.22);remove_tween.tween_callback(queue_free)

func hammer_dismantle(_player: Node) -> void:
	if _dismantling:return
	_dismantling = true
	if growth_stage > 0: SurvivalState.add_item("seeds", 1, "seeds")
	SurvivalState.add_item("wood", 5, "wood")
	SurvivalState.add_item("stone", 1, "stone")
	var tween := create_tween(); tween.tween_property(self,"scale",scale*Vector3(.8,.05,.8),.18); tween.tween_callback(queue_free)
