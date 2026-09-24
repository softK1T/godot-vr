extends Node

@export var move_speed := 3.2
@export var snap_turn_degrees := 30.0
@export var deadzone := 0.18
@export var right_hand_tool_position := Vector3(0.0, -0.03, -0.10)
@export var right_hand_tool_rotation_degrees := Vector3(-12.0, 180.0, 0.0)

@onready var player: CharacterBody3D = get_parent()
@onready var desktop_pivot: Node3D = player.get_node("CamPivot")
@onready var desktop_camera: Camera3D = player.get_node("CamPivot/Camera3D")
@onready var desktop_ray: RayCast3D = player.get_node("CamPivot/Camera3D/InteractionRay")
@onready var origin: XROrigin3D = player.get_node("XROrigin3D")
@onready var head: XRCamera3D = origin.get_node("Head")
@onready var left_hand: XRController3D = origin.get_node("LeftHand")
@onready var right_hand: XRController3D = origin.get_node("RightHand")
@onready var hand_ray: RayCast3D = right_hand.get_node("InteractionRay")
@onready var hud_anchor: Node3D = head.get_node("HUDAnchor")

var webxr: WebXRInterface
var xr_active := false
var _turn_ready := true
var _enter_layer: CanvasLayer
var _status: Label
var _enter_button: Button
var _tool_grip: Node3D
var _blade_last := Vector3.ZERO
var _blade_velocity := Vector3.ZERO
var _blade_damage: Area3D
var _emulator_active := false
var _emulator_tween: Tween

func _ready() -> void:
	origin.visible = false
	# OS.get_name() is "Web" only in an actual browser export. JavaScriptBridge
	# exists as an engine singleton in native builds too, so it cannot distinguish
	# macOS from Web.
	if OS.get_name() != "Web":
		_install_desktop_simulator.call_deferred()
		return
	_build_enter_ui()
	webxr = XRServer.find_interface("WebXR") as WebXRInterface
	if webxr == null:
		_set_status("WebXR is unavailable in this browser.")
		_enter_button.disabled = true
		return
	webxr.session_supported.connect(_on_session_supported)
	webxr.session_started.connect(_on_session_started)
	webxr.session_ended.connect(_on_session_ended)
	webxr.session_failed.connect(_on_session_failed)
	webxr.reference_space_reset.connect(_on_reference_space_reset)
	webxr.is_session_supported("immersive-vr")
	right_hand.button_pressed.connect(_on_right_button_pressed)
	left_hand.button_pressed.connect(_on_left_button_pressed)

func _install_desktop_simulator() -> void:
	if player.get_node_or_null("DesktopVRSimulator"):
		return
	var simulator := Node.new()
	simulator.name = "DesktopVRSimulator"
	simulator.set_script(load("res://scripts/xr/desktop_vr_simulator.gd"))
	player.add_child(simulator)

func _build_enter_ui() -> void:
	_enter_layer = CanvasLayer.new()
	_enter_layer.layer = 100
	add_child(_enter_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-230, -85)
	panel.size = Vector2(460, 170)
	_enter_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "FOREST HOUSE WEBXR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	_status = Label.new()
	_status.text = "Checking immersive VR support…"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_enter_button = Button.new()
	_enter_button.text = "ENTER VR"
	_enter_button.disabled = true
	_enter_button.custom_minimum_size.y = 52
	_enter_button.pressed.connect(_enter_webxr)
	box.add_child(_enter_button)

func _set_status(text: String) -> void:
	if _status:
		_status.text = text

func _on_session_supported(mode: String, supported: bool) -> void:
	if mode != "immersive-vr": return
	_enter_button.disabled = not supported
	_set_status("Put on the headset, then press ENTER VR." if supported else "This browser/device does not support immersive WebXR.")

func _enter_webxr() -> void:
	# Browser security requires initialize() to run directly from this button gesture.
	webxr.session_mode = "immersive-vr"
	webxr.requested_reference_space_types = "local"
	webxr.required_features = ""
	webxr.optional_features = ""
	if not webxr.initialize():
		# initialize() emits session_failed synchronously with the actual reason
		# (for example, missing WebGL multiview support). Do not overwrite it.
		return

func _on_session_started() -> void:
	xr_active = true
	get_viewport().use_xr = true
	origin.visible = true
	desktop_camera.current = false
	head.current = true
	_enter_layer.visible = false
	player.set("pivot", origin)
	player.set("camera", head)
	player.set("interaction_ray", hand_ray)
	player.get_node("HUD").visible = false
	_mount_tools_to_hand()
	_setup_blade_damage()
	_recenter_body()

func _on_session_ended() -> void:
	xr_active = false
	get_viewport().use_xr = false
	origin.visible = false
	desktop_camera.current = true
	_enter_layer.visible = true
	player.set("pivot", desktop_pivot)
	player.set("camera", desktop_camera)
	player.set("interaction_ray", desktop_ray)
	player.get_node("HUD").visible = true
	_restore_tools_to_camera()
	_set_status("VR session ended. Press ENTER VR to start again.")

func _on_session_failed(message: String) -> void:
	_enter_layer.visible = true
	_set_status("WebXR failed: " + message)

func _on_reference_space_reset() -> void:
	_recenter_body()

func _recenter_body() -> void:
	# Keep tracked head horizontally inside the CharacterBody capsule.
	var head_offset := origin.transform * head.transform
	origin.position.x -= head_offset.origin.x
	origin.position.z -= head_offset.origin.z

func _setup_blade_damage() -> void:
	if _blade_damage: return
	var tip = player.get("_axe_strike_point"); var eye = player.get("_axe_eye")
	if not (tip is Node3D) or not (eye is Node3D): return
	_blade_damage = Area3D.new(); _blade_damage.name = "VRBladeDamage"
	_blade_damage.collision_layer = 0; _blade_damage.collision_mask = 1
	_blade_damage.monitoring = true; _blade_damage.monitorable = false
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(0.48, 0.34, 0.34); shape.shape = box; _blade_damage.add_child(shape)
	(tip as Node3D).add_child(_blade_damage)
	_blade_damage.set_script(load("res://scripts/xr/vr_blade_damage.gd"))
	_blade_damage.call("configure", player, tip, eye); _blade_damage.set("enabled", true)

func _mount_tools_to_hand() -> void:
	if not _tool_grip:
		_tool_grip = Node3D.new()
		_tool_grip.name = "XRToolGrip"
		right_hand.add_child(_tool_grip)
	_tool_grip.position = right_hand_tool_position
	_tool_grip.rotation_degrees = right_hand_tool_rotation_degrees
	for property_name in ["_axe_grip_pivot", "_tool_swing_pivot"]:
		var tool_root = player.get(property_name)
		if tool_root is Node3D:
			(tool_root as Node3D).reparent(_tool_grip, false)
			(tool_root as Node3D).position = Vector3.ZERO
			(tool_root as Node3D).rotation = Vector3.ZERO

func _restore_tools_to_camera() -> void:
	for property_name in ["_axe_grip_pivot", "_tool_swing_pivot"]:
		var tool_root = player.get(property_name)
		if tool_root is Node3D:
			(tool_root as Node3D).reparent(desktop_camera, false)
			(tool_root as Node3D).position = Vector3(0.62, -0.88, -1.10)
			(tool_root as Node3D).rotation = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if not xr_active: return
	_update_locomotion(delta)
	_update_physical_tool(delta)

func _update_locomotion(_delta: float) -> void:
	var stick := left_hand.get_vector2("primary")
	if stick.length() < deadzone: stick = Vector2.ZERO
	var forward := -head.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := head.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var desired := (right * stick.x + forward * -stick.y) * move_speed
	player.velocity.x = desired.x
	player.velocity.z = desired.z
	if not player.is_on_floor(): player.velocity.y -= 9.8 * get_physics_process_delta_time()
	player.move_and_slide()
	var turn := right_hand.get_vector2("primary").x
	if absf(turn) < 0.35: _turn_ready = true
	elif _turn_ready:
		_turn_ready = false
		player.rotate_y(deg_to_rad(-snap_turn_degrees * signf(turn)))

func _update_physical_tool(delta: float) -> void:
	var tip = player.get("_axe_strike_point")
	if not (tip is Node3D) or delta <= 0.0: return
	var now := (tip as Node3D).global_position
	_blade_velocity = (now - _blade_last) / delta if _blade_last != Vector3.ZERO else Vector3.ZERO
	_blade_last = now

func _on_right_button_pressed(name: String) -> void:
	if not xr_active: return
	match name:
		"trigger_click": player.call("_try_interact")
		"ax_button": player.call("_select_slot", posmod(int(player.get("selected_slot")) + 1, 11))
		"by_button": _emulate_axe_swing() if player.has_equipped_tool("axe") else player.call("_use_selected_item")

func _on_left_button_pressed(name: String) -> void:
	if not xr_active: return
	if name == "menu_button": player.call("_toggle_inventory", not bool(player.get("inventory_open")))

func _emulate_axe_swing() -> void:
	# Optional no-hand-motion assist: it moves the tracked tool; only BladeArea contact can damage.
	if not xr_active or _emulator_active or not _tool_grip or not player.has_equipped_tool("axe"): return
	_emulator_active = true
	var rest_pos := right_hand_tool_position; var rest_rot := right_hand_tool_rotation_degrees
	var wind_pos := rest_pos + Vector3(0.26, 0.30, 0.16); var wind_rot := rest_rot + Vector3(-18.0, -12.0, 72.0)
	var hit_pos := rest_pos + Vector3(-0.20, -0.05, -0.42); var hit_rot := rest_rot + Vector3(4.0, 5.0, -28.0)
	_emulator_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_emulator_tween.tween_property(_tool_grip,"position",wind_pos,0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_emulator_tween.parallel().tween_property(_tool_grip,"rotation_degrees",wind_rot,0.20)
	_emulator_tween.tween_property(_tool_grip,"position",hit_pos,0.13).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_emulator_tween.parallel().tween_property(_tool_grip,"rotation_degrees",hit_rot,0.13)
	_emulator_tween.tween_property(_tool_grip,"position",rest_pos,0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_emulator_tween.parallel().tween_property(_tool_grip,"rotation_degrees",rest_rot,0.24)
	_emulator_tween.tween_callback(func(): _emulator_active = false)
