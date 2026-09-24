extends StaticBody3D
class_name WoodStove

@export var burn_seconds_per_wood := 95.0
var fuel_time := 0.0
var _light: OmniLight3D
var _room_fill: OmniLight3D
var _flame: MeshInstance3D

func _ready() -> void:
	_light = get_node_or_null("FireLight") as OmniLight3D
	_flame = get_node_or_null("Flame") as MeshInstance3D
	_update_visual()

func configure_visuals(light: OmniLight3D, flame: MeshInstance3D, room_fill: OmniLight3D = null) -> void:
	_light = light
	_flame = flame
	_room_fill = room_fill
	_update_visual()

func _process(delta: float) -> void:
	if fuel_time > 0.0:
		fuel_time = maxf(0.0, fuel_time - delta)
		_update_visual()

func is_burning() -> bool:
	return fuel_time > 0.0

func heat_strength() -> float:
	return clampf(fuel_time / 25.0, 0.0, 1.0)

func get_interaction_text() -> String:
	var wood_label := "E  Add wood (1)" if is_burning() else "E  Light stove (1 wood)"
	if not SurvivalState.has_item("wood", 1):
		wood_label = "E  Need 1 wood"
	if not is_burning():
		return wood_label
	var food_label := "C  Cook (2 vegetables)" if SurvivalState.has_item("vegetables", 2) else "C  Need 2 vegetables"
	if SurvivalState.has_item("raw_fish", 1):
		food_label = "C  Fry fish (1 raw fish)"
	return "%s    •    %s" % [wood_label, food_label]

func interact(_player: Node) -> void:
	# E always fuels the stove; cooking never consumes wood by accident.
	if SurvivalState.remove_item("wood", 1):
		fuel_time += burn_seconds_per_wood
		SurvivalState.notification.emit("Wood added to the stove.", Color(1.0, 0.58, 0.25))
	else:
		SurvivalState.notification.emit("You need 1 wood to fuel the stove.", Color(1.0, 0.5, 0.35))
	_update_visual()

func cook() -> void:
	if not is_burning():
		SurvivalState.notification.emit("Light the stove before cooking.", Color(1.0, 0.5, 0.35))
	elif SurvivalState.remove_item("raw_fish", 1):
		SurvivalState.add_item("cooked_fish", 1, "fried fish")
		fuel_time = maxf(0.0, fuel_time - 6.0)
		SurvivalState.notification.emit("The fish sizzles in the pan.", Color(1.0, 0.72, 0.35))
		var sizzle := AudioStreamPlayer3D.new()
		sizzle.stream = load("res://scripts/fishing_controller.gd").synth(900.0, 500.0, 1.1, 0.95, 0.3)
		add_child(sizzle)
		sizzle.finished.connect(sizzle.queue_free)
		sizzle.play()
	elif SurvivalState.remove_item("vegetables", 2):
		SurvivalState.add_item("cooked_food", 1, "warm meal")
		fuel_time = maxf(0.0, fuel_time - 12.0)
		SurvivalState.notification.emit("Vegetable stew simmers on the stove.", Color(1.0, 0.72, 0.35))
	else:
		SurvivalState.notification.emit("You need 2 vegetables to cook.", Color(1.0, 0.5, 0.35))
	_update_visual()

func _update_visual() -> void:
	var active := is_burning()
	if _light != null:
		_light.light_energy = 3.2 * heat_strength() if active else 0.0
	if _room_fill != null:
		_room_fill.light_energy = 0.95 * heat_strength() if active else 0.0
	if _flame != null:
		_flame.visible = active
		_flame.scale.y = 0.75 + sin(Time.get_ticks_msec() * 0.008) * 0.18
