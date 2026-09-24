extends Node

@export var hand_move_speed := 0.85
@export var hand_rotation_speed := 85.0
@export var mouse_move_sensitivity := 0.0018
@export var mouse_rotation_sensitivity := 0.22

var player: CharacterBody3D
var camera: Camera3D
var hand: Node3D
var tool_grip: Node3D
var blade_damage: Area3D
var active := false
var swinging := false
var blade_speed := 0.0
var _last_tip := Vector3.ZERO
var _overlay: CanvasLayer
var _status: Label
var _instructions: Label
var _original_tools: Array[Node3D] = []
var _original_parents: Dictionary = {}
var _original_transforms: Dictionary = {}

func _ready() -> void:
	if OS.get_name() == "Web":
		queue_free()
		return
	player = get_parent() as CharacterBody3D
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	call_deferred("_initialize")

func _initialize() -> void:
	camera = player.get_node_or_null("CamPivot/Camera3D") as Camera3D
	if camera == null:
		push_error("Desktop VR Simulator: desktop camera not found")
		return
	hand = Node3D.new()
	hand.name = "SimulatedRightController"
	camera.add_child(hand)
	hand.position = Vector3(0.42, -0.32, -0.72)
	hand.rotation_degrees = Vector3(-12.0, 180.0, 0.0)
	hand.visible = false
	_build_overlay()
	_overlay.visible = false

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 90
	add_child(_overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(510, 0)
	_overlay.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_status = Label.new()
	_status.text = "DESKTOP VR SIMULATOR: OFF  —  press V or click ENABLE"
	_status.add_theme_font_size_override("font_size", 18)
	box.add_child(_status)
	var toggle := Button.new()
	toggle.text = "ENABLE / DISABLE DESKTOP VR  (V)"
	toggle.custom_minimum_size.y = 42
	toggle.pressed.connect(func(): set_active(not active))
	box.add_child(toggle)
	_instructions = Label.new()
	_instructions.text = "WASD: move  |  Mouse: move hand  |  Alt+mouse: rotate hand\nWheel: hand depth  |  Space: test swing  |  1: equip axe  |  V: exit"
	_instructions.visible = false
	box.add_child(_instructions)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_V or event.physical_keycode == KEY_V):
		set_active(not active)
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_test_swing()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER:
			player.call("_try_interact")
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if event.alt_pressed:
			hand.rotation_degrees.x -= event.relative.y * mouse_rotation_sensitivity
			hand.rotation_degrees.y -= event.relative.x * mouse_rotation_sensitivity
		else:
			# In V mode the mouse steers the simulated hand, not the camera.
			hand.position += Vector3(event.relative.x * mouse_move_sensitivity, -event.relative.y * mouse_move_sensitivity, 0.0)
			_clamp_hand()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			hand.position.z -= 0.06
			_clamp_hand()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			hand.position.z += 0.06
			_clamp_hand()
			get_viewport().set_input_as_handled()

func set_active(value: bool) -> void:
	if hand == null or active == value:
		return
	active = value
	_overlay.visible = active
	hand.visible = active
	_instructions.visible = active
	if active:
		# V is the axe-contact simulator: ensure the axe, not the currently held hammer,
		# is equipped before testing the blade against tree colliders.
		player.call("_select_slot", 0)
		_mount_tools()
		_setup_blade_damage()
		_status.text = "DESKTOP VR SIMULATOR: ON  |  blade detector: %s" % ("READY" if is_instance_valid(blade_damage) else "MISSING")
	else:
		if swinging:
			var tween := get_tree().get_processed_tweens()
			for item in tween:
				if item and item.is_valid(): item.kill()
		swinging = false
		_restore_tools()
		if blade_damage: blade_damage.set("enabled", false)
		_status.text = "DESKTOP VR SIMULATOR: OFF  —  press V or click ENABLE"

func _physics_process(delta: float) -> void:
	if not active or hand == null:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_J): move.x -= 1.0
	if Input.is_key_pressed(KEY_L): move.x += 1.0
	if Input.is_key_pressed(KEY_I): move.y += 1.0
	if Input.is_key_pressed(KEY_K): move.y -= 1.0
	if Input.is_key_pressed(KEY_U): move.z -= 1.0
	if Input.is_key_pressed(KEY_O): move.z += 1.0
	if not swinging and move != Vector3.ZERO:
		hand.position += move.normalized() * hand_move_speed * delta
		_clamp_hand()
	var rotate := Vector3.ZERO
	if Input.is_key_pressed(KEY_UP): rotate.x -= 1.0
	if Input.is_key_pressed(KEY_DOWN): rotate.x += 1.0
	if Input.is_key_pressed(KEY_LEFT): rotate.y += 1.0
	if Input.is_key_pressed(KEY_RIGHT): rotate.y -= 1.0
	if Input.is_key_pressed(KEY_Z): rotate.z += 1.0
	if Input.is_key_pressed(KEY_X): rotate.z -= 1.0
	if not swinging:
		hand.rotation_degrees += rotate * hand_rotation_speed * delta
	_update_blade_readout(delta)

func _mount_tools() -> void:
	_original_tools.clear()
	_original_parents.clear()
	_original_transforms.clear()
	tool_grip = Node3D.new()
	tool_grip.name = "DesktopVRToolGrip"
	hand.add_child(tool_grip)
	for property_name in ["_axe_grip_pivot", "_tool_swing_pivot"]:
		var value = player.get(property_name)
		if value is Node3D and not _original_tools.has(value):
			var tool := value as Node3D
			_original_tools.append(tool)
			_original_parents[tool] = tool.get_parent()
			_original_transforms[tool] = tool.transform
			tool.reparent(tool_grip, false)
			tool.transform = Transform3D.IDENTITY

func _restore_tools() -> void:
	for tool in _original_tools:
		if is_instance_valid(tool) and is_instance_valid(_original_parents.get(tool)):
			tool.reparent(_original_parents[tool], false)
			tool.transform = _original_transforms[tool]
	_original_tools.clear()
	if is_instance_valid(tool_grip): tool_grip.queue_free()
	tool_grip = null

func _setup_blade_damage() -> void:
	if is_instance_valid(blade_damage):
		blade_damage.call("reset_contacts")
		blade_damage.set("enabled", true)
		return
	var tip = player.get("_axe_strike_point")
	var eye = player.get("_axe_eye")
	if not (tip is Node3D) or not (eye is Node3D):
		push_error("Desktop VR Simulator: axe markers are missing")
		return
	blade_damage = Area3D.new()
	blade_damage.name = "DesktopVRBladeDamage"
	blade_damage.collision_layer = 0
	blade_damage.collision_mask = 1
	blade_damage.monitoring = true
	blade_damage.monitorable = false
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.48, 0.34, 0.34)
	collision.shape = box
	blade_damage.add_child(collision)
	(tip as Node3D).add_child(blade_damage)
	blade_damage.set_script(load("res://scripts/xr/vr_blade_damage.gd"))
	blade_damage.call("configure", player, tip, eye)
	blade_damage.set("enabled", true)

func _test_swing() -> void:
	if swinging or tool_grip == null or not player.has_equipped_tool("axe"):
		return
	swinging = true
	var start_pos := hand.position
	var start_rot := hand.rotation_degrees
	var wind_pos := start_pos + Vector3(0.24, 0.18, 0.10)
	var wind_rot := start_rot + Vector3(-18.0, 10.0, -48.0)
	var hit_pos := start_pos + Vector3(-0.18, -0.05, -0.26)
	var hit_rot := start_rot + Vector3(8.0, -8.0, 32.0)
	var follow_pos := start_pos + Vector3(-0.28, -0.12, -0.20)
	var follow_rot := start_rot + Vector3(12.0, -10.0, 45.0)
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(hand, "position", wind_pos, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(hand, "rotation_degrees", wind_rot, 0.20)
	tween.tween_property(hand, "position", hit_pos, 0.14).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(hand, "rotation_degrees", hit_rot, 0.14)
	tween.tween_property(hand, "position", follow_pos, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(hand, "rotation_degrees", follow_rot, 0.08)
	tween.tween_property(hand, "position", start_pos, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(hand, "rotation_degrees", start_rot, 0.26)
	tween.tween_callback(func(): swinging = false)

func _update_blade_readout(delta: float) -> void:
	var tip = player.get("_axe_strike_point")
	if not (tip is Node3D) or delta <= 0.0:
		return
	var current := (tip as Node3D).global_position
	blade_speed = (current - _last_tip).length() / delta if _last_tip != Vector3.ZERO else 0.0
	_last_tip = current
	if blade_damage:
		blade_damage.set("emulated_velocity", Vector3.ZERO)
	_status.text = "VR: %s | %s | blade %.2f m/s | hand (%.2f, %.2f, %.2f)" % ["AXE" if player.has_equipped_tool("axe") else "EQUIP AXE (1)", "READY" if is_instance_valid(blade_damage) else "NO DETECTOR", blade_speed, hand.position.x, hand.position.y, hand.position.z]

func _clamp_hand() -> void:
	hand.position.x = clampf(hand.position.x, -1.15, 1.15)
	hand.position.y = clampf(hand.position.y, -1.15, 0.75)
	hand.position.z = clampf(hand.position.z, -1.65, -0.18)
