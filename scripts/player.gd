extends CharacterBody3D

@export var speed := 4.0
@export var sprint := 7.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0025
@export var max_step_height := 0.45

@onready var pivot: Node3D = $CamPivot
@onready var camera: Camera3D = $CamPivot/Camera3D
@onready var interaction_ray: RayCast3D = $CamPivot/Camera3D/InteractionRay
@onready var interaction_prompt: Label = $HUD/InteractionPrompt
@onready var inventory_label: Label = $HUD/SurvivalPanel/Margin/VBox/Inventory
@onready var clock_label: Label = $HUD/TopBar/Clock
@onready var objective_label: Label = $HUD/ObjectivePanel/Margin/VBox/Objective
@onready var notification_label: Label = $HUD/Notification
@onready var health_bar: ProgressBar = $HUD/SurvivalPanel/Margin/VBox/Health
@onready var hunger_bar: ProgressBar = $HUD/SurvivalPanel/Margin/VBox/Hunger
@onready var warmth_bar: ProgressBar = $HUD/SurvivalPanel/Margin/VBox/Warmth
@onready var stamina_bar: ProgressBar = $HUD/SurvivalPanel/Margin/VBox/Stamina

const SLOT_ITEMS := ["axe", "pickaxe", "hammer", "berries", "mushroom", "vegetables", "cooked_food", "seeds", "wood", "stone", "sticks", "sapling"]
const SLOT_NAMES := ["AXE", "PICKAXE", "HAMMER", "BERRIES", "MUSHROOM", "VEGETABLES", "WARM MEAL", "SEEDS", "WOOD", "STONE", "STICKS", "SAPLING"]
const SLOT_ICONS := ["A", "P", "H", "●", "♠", "◆", "▣", "✦", "W", "S", "I", "♣"]
const BUILD_PIECES := ["farm_bed", "gate", "wicket", "fence", "base_fence"]
const GATE_ITEMS := ["gate", "wicket"]
const BUILD_NAMES := {"farm_bed":"FARM BED", "gate":"WOODEN GATE", "wicket":"WICKET GATE", "fence":"LOW FENCE", "base_fence":"RUSTIC FENCE"}
const BUILD_COSTS := {"farm_bed":{"wood":6,"stone":2}, "gate":{"wood":8,"stone":2}, "wicket":{"wood":5,"stone":2}, "fence":{"wood":1}, "base_fence":{"wood":2}}
const EDIBLE := ["berries", "mushroom", "vegetables", "cooked_food"]

var selected_slot := 0
var inventory_open := false
var _notice_tween: Tween
var _tool_swing_pivot: Node3D
var _tool_anchor: Node3D
var _axe_grip_pivot: Node3D
var _axe_anchor: Node3D
var _tool_anim_tween: Tween
var _axe_model: Node3D
var _axe_impact_target: Node
var _axe_last_tip := Vector3.ZERO
var _axe_hit_this_swing := false
var _pickaxe_model: Node3D
var _hammer_model: Node3D
var _axe_strike_point: Node3D
var _axe_eye: Node3D
var _pickaxe_strike_point: Node3D
var _build_overlay: ColorRect
var _build_buttons: Dictionary = {}
var _build_menu_open := false
var _building_mode := false
var _remove_mode := false
var _selected_build_piece := "farm_bed"
var _build_rotation_offset := 0.0
var _craft_buttons: Dictionary = {}
var _hotbar: HBoxContainer
var _hotbar_buttons: Array[Button] = []
var _inventory_overlay: ColorRect
var _inventory_buttons: Dictionary = {}
var _use_cooldown := false
var _placement_locked := false
var _farm_bed_preview: Node3D
var _fence_preview: Node3D
var _fence_dragging := false
var _fence_start := Vector3.ZERO
var _fence_end := Vector3.ZERO
const FENCE_WOOD_PER_METER := 1
const BASE_FENCE_WOOD_PER_METER := 2
const FENCE_MAX_LENGTH := 24.0
var _preview_valid := false
var _preview_position := Vector3.ZERO
var _preview_rotation := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_contrast_theme()
	_relayout_game_hud()
	_build_hotbar()
	_build_inventory_window()
	_build_build_menu()
	_build_axe_model()
	SurvivalState.inventory_changed.connect(_inventory_changed)
	SurvivalState.vitals_changed.connect(_vitals_changed)
	SurvivalState.time_changed.connect(_time_changed)
	SurvivalState.notification.connect(_notify)
	_inventory_changed(SurvivalState.inventory)
	_vitals_changed(SurvivalState.health, SurvivalState.hunger, SurvivalState.warmth, SurvivalState.stamina)
	_time_changed(SurvivalState.day, int(SurvivalState.time_of_day), int(fmod(SurvivalState.time_of_day, 1.0) * 60.0))
	_select_slot(0)

func _input(event: InputEvent) -> void:
	# GUI consumes mouse events before _unhandled_input: close the overlay here.
	if _build_menu_open and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_toggle_build_menu(false)
		get_viewport().set_input_as_handled()
		return
	# Hammer fence placement is procedural: hold LMB at the first point, drag, release at the end.
	if inventory_open or _build_menu_open or not has_equipped_tool("hammer") or not _building_mode or _selected_build_piece not in ["fence", "base_fence"]:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_fence_drag()
		else:
			_finish_fence_drag()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if inventory_open:
			_toggle_inventory(false)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_C and not inventory_open and not _build_menu_open and not _building_mode:
			var stove_target := _get_interactable()
			if stove_target is WoodStove:
				stove_target.cook()
				get_viewport().set_input_as_handled()
				return
		if event.physical_keycode == KEY_L and not inventory_open and not _build_menu_open:
			var atmosphere := get_node_or_null("../Atmosphere")
			if atmosphere:
				var lit: bool = atmosphere.toggle_flashlight()
				_notify("FLASHLIGHT  /  ON" if lit else "FLASHLIGHT  /  OFF", Color(0.98, 0.87, 0.63))
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_F9:
			var atmosphere := get_node_or_null("../Atmosphere")
			if atmosphere:
				atmosphere.cycle_weather()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_F8:
			var atmosphere := get_node_or_null("../Atmosphere")
			if atmosphere:
				var night: bool = not atmosphere.debug_night
				SurvivalState.time_of_day = 22.0 if night else 12.0
				SurvivalState.time_changed.emit(SurvivalState.day, int(SurvivalState.time_of_day), 0)
				atmosphere.set_debug_night(night)
				_notify("DEBUG  /  NIGHT" if night else "DEBUG  /  DAY", Color(0.76, 0.86, 1.0))
			get_viewport().set_input_as_handled()
			return
		if has_equipped_tool("hammer") and event.physical_keycode == KEY_R and not _build_menu_open:
			_build_rotation_offset = fposmod(_build_rotation_offset + PI / 8.0, TAU)
			_notify("Rotated 22.5 degrees.", Color(0.72, 0.9, 1.0))
			return
		if has_equipped_tool("hammer") and event.physical_keycode == KEY_Q:
			_close_build_menu(); _building_mode = false; _remove_mode = false; _update_placement_preview_state()
			_notify("Building mode closed.", Color(0.82, 0.84, 0.75))
			return
		if event.physical_keycode == KEY_TAB:
			_toggle_inventory(not inventory_open)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
			_select_slot(int(event.physical_keycode - KEY_1))
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_0:
			_select_slot(9)
			get_viewport().set_input_as_handled()
			return
	if inventory_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		pivot.rotation.x = clampf(pivot.rotation.x, -1.4, 1.4)
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and has_equipped_tool("hammer"):
			_toggle_build_menu(not _build_menu_open)
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE and has_equipped_tool("hammer"):
			_hammer_remove_target()
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_slot(posmod(selected_slot - 1, SLOT_ITEMS.size()))
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_slot(posmod(selected_slot + 1, SLOT_ITEMS.size()))
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_use_selected_item()
	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("eat_food"):
		SurvivalState.eat_best_food()

func _process(_delta: float) -> void:
	_update_farm_bed_preview()
	if has_equipped_tool("hammer") and not inventory_open and not _build_menu_open:
		if _building_mode:
			interaction_prompt.visible = true
			return
		var hammer_target := _get_interactable()
		if hammer_target is WoodStove:
			interaction_prompt.text = hammer_target.get_interaction_text()
			interaction_prompt.visible = true
			return
		if hammer_target and hammer_target.has_method("hammer_dismantle"):
			interaction_prompt.text = "MMB  Remove structure  •  RMB build menu"
		else:
			interaction_prompt.text = "RMB  Open build menu"
		interaction_prompt.visible = true
		return
	var target := _get_interactable()
	interaction_prompt.visible = target != null and not inventory_open
	if target and target.has_method("get_interaction_text"):
		var text := str(target.get_interaction_text())
		if target is HarvestableResource:
			if target.resource_kind == "tree" and not has_equipped_tool("axe"):
				text = "1  Equip axe to chop"
			elif target.resource_kind == "stone" and not has_equipped_tool("pickaxe"):
				text = "2  Equip pickaxe to mine"
		interaction_prompt.text = text
		interaction_prompt.visible = not text.is_empty() and not inventory_open

func has_equipped_tool(tool_name: String) -> bool:
	return SLOT_ITEMS[selected_slot] == tool_name

func _select_slot(index: int) -> void:
	selected_slot = clampi(index, 0, SLOT_ITEMS.size() - 1)
	if not has_equipped_tool("hammer"):
		_close_build_menu(); _building_mode = false; _remove_mode = false
	for i in _hotbar_buttons.size():
		_style_slot(_hotbar_buttons[i], i == selected_slot)
	_update_tool_visibility()
	_update_placement_preview_state()
	var item: String = SLOT_ITEMS[selected_slot]
	var count_text := ""
	if item in ["axe", "pickaxe", "hammer"]:
		count_text = "  %d/%d" % [SurvivalState.get_tool_durability(item), SurvivalState.get_tool_max_durability(item)]
	else:
		count_text = " ×%d" % int(SurvivalState.inventory.get(item, 0))
	_notify("Selected: %s%s" % [SLOT_NAMES[selected_slot], count_text], Color(1.0, 0.84, 0.42))

func _use_selected_item() -> void:
	if _use_cooldown:
		return
	var item: String = SLOT_ITEMS[selected_slot]
	if item == "hammer":
		if not SurvivalState.has_item("hammer") or SurvivalState.get_tool_durability("hammer") <= 0:
			_notify("Your building hammer is broken. Craft another one.", Color(1.0, 0.4, 0.25))
			return
		if _building_mode:
			_place_hammer_piece()
		else:
			_toggle_build_menu(true)
	elif item in ["axe", "pickaxe"]:
		if not SurvivalState.has_item(item) or SurvivalState.get_tool_durability(item) <= 0:
			_notify("Your %s is broken. Craft another one." % item, Color(1.0, 0.4, 0.25))
			return
		var target := _get_interactable()
		_swing_tool(item, target)
	elif item in ["farm_bed", "gate", "wicket"]:
		_place_building(item)
	elif item in EDIBLE:
		SurvivalState.eat_item(item)
	elif item == "sapling":
		_plant_sapling()
	else:
		_notify("This material is used for crafting.", Color(0.86, 0.86, 0.7))

func _swing_tool(tool: String, target: Node = null) -> void:
	if tool == "axe":
		if not _axe_model or _use_cooldown or _axe_model.is_swinging():
			return
		_use_cooldown = true
		_axe_impact_target = target
		_axe_hit_this_swing = false
		_axe_last_tip = _axe_model.get_blade_tip()
		_axe_model.swing()
		return
	var model: Node3D = _axe_model if tool == "axe" else _pickaxe_model
	var strike_point: Node3D = _axe_strike_point if tool == "axe" else _pickaxe_strike_point
	var swing_pivot: Node3D = _axe_grip_pivot if tool == "axe" else _tool_swing_pivot
	if not model or not strike_point or not swing_pivot or _use_cooldown:
		return
	_use_cooldown = true
	_reset_tool_pose()

	var rest_position := Vector3(0.62, -0.88, -1.10)
	var contact_offset := swing_pivot.to_local(strike_point.global_position)
	var rest_rotation := Quaternion.IDENTITY
	var rest_contact := rest_position + contact_offset
	_tool_anim_tween = create_tween()
	_tool_anim_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)

	if tool == "axe":
		# Solve rotation from the authored axe geometry. The vector from the eye to
		# the cutting tip must point horizontally left at contact; no visual axis is
		# guessed and the permanent model rotation is never overwritten.
		var eye_offset := swing_pivot.to_local(_axe_eye.global_position)
		var blade_axis := (contact_offset - eye_offset).normalized()
		var impact_z := wrapf(PI - atan2(blade_axis.y, blade_axis.x), -PI, PI)

		# Rotate around the HAND, not around the blade tip. Earlier poses solved every
		# tip position independently, so translation hid most of the head rotation.
		# These are true grip-pivot poses: the long grip-to-head lever now creates
		# the visible arc. Only the impact pivot is solved from the exact tip target.
		var impact_contact := Vector3(0.0, 0.0, -1.28)
		var prep_position := rest_position + Vector3(0.03, 0.03, 0.03)
		var windup_position := rest_position + Vector3(0.11, 0.17, 0.13)
		var prep_rotation := Quaternion.from_euler(Vector3(0.0, deg_to_rad(2.0), deg_to_rad(10.0)))
		var windup_rotation := Quaternion.from_euler(Vector3(deg_to_rad(-7.0), deg_to_rad(10.0), deg_to_rad(72.0)))
		var strike_start_rotation := Quaternion.from_euler(Vector3(deg_to_rad(-3.0), deg_to_rad(4.0), deg_to_rad(30.0)))
		# Put the cutting tip to the RIGHT and ABOVE the target before contact.
		# It now enters the centre moving left/down/forward, in the same direction
		# the sharpened eye-to-edge axis points, so the edge leads the impact.
		# Keep the visible strike close to the crosshair: the edge approaches from
		# only slightly right/up, reaches the exact centre, then crosses left/down.
		var strike_start_contact := Vector3(0.18, 0.14, -1.08)
		var strike_start_position := strike_start_contact - strike_start_rotation * contact_offset
		var impact_rotation := Quaternion.from_euler(Vector3(0.0, 0.0, impact_z))
		var impact_position := impact_contact - impact_rotation * contact_offset
		var follow_rotation := Quaternion.from_euler(Vector3(0.0, deg_to_rad(-4.0), deg_to_rad(-30.0)))
		var follow_contact := Vector3(-0.18, -0.12, -1.20)

		_tween_swing_pose(swing_pivot, rest_position, prep_position, rest_rotation, prep_rotation, 0.08, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
		_tween_swing_pose(swing_pivot, prep_position, windup_position, prep_rotation, windup_rotation, 0.20, Tween.TRANS_SINE, Tween.EASE_OUT)
		_tool_anim_tween.tween_interval(0.04)
		_tween_swing_pose(swing_pivot, windup_position, strike_start_position, windup_rotation, strike_start_rotation, 0.075, Tween.TRANS_QUAD, Tween.EASE_IN)
		# Lock the mirrored cutting tip to a direct right-to-left final approach;
		# otherwise pivot interpolation can make the mirrored head loop and hit poll-first.
		_tween_tool_contact(swing_pivot, contact_offset, strike_start_contact, impact_contact, strike_start_rotation, impact_rotation, 0.105, Tween.TRANS_QUART, Tween.EASE_IN)
		_tool_anim_tween.tween_callback(func(): _apply_tool_impact(tool, target))
		# Briefly show the blade on the crosshair, then keep tracking the real edge
		# through the centre instead of letting pivot interpolation pull it right.
		_tool_anim_tween.tween_interval(0.045)
		_tween_tool_contact(swing_pivot, contact_offset, impact_contact, follow_contact, impact_rotation, follow_rotation, 0.12, Tween.TRANS_QUAD, Tween.EASE_OUT)
		var follow_position := follow_contact - follow_rotation * contact_offset
		_tween_swing_pose(swing_pivot, follow_position, rest_position, follow_rotation, rest_rotation, 0.30, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	else:
		# A pick hits point-first: pull the hand back and up, rotate the beak
		# toward the crosshair, then drive the tip forward into the stone.
		# Tracking the actual tip preserves the smaller model's contact position.
		var windup_contact := Vector3(0.46, 0.43, -0.91)
		var approach_contact := Vector3(0.20, 0.18, -1.12)
		var impact_contact := Vector3(0.02, -0.02, -1.42)
		var recoil_contact := Vector3(0.16, 0.09, -1.22)
		var windup_rotation := Quaternion.from_euler(Vector3(deg_to_rad(-35.0), deg_to_rad(-18.0), deg_to_rad(-20.0)))
		var approach_rotation := Quaternion.from_euler(Vector3(deg_to_rad(-23.0), deg_to_rad(-48.0), deg_to_rad(-10.0)))
		var impact_rotation := Quaternion.from_euler(Vector3(deg_to_rad(-12.0), deg_to_rad(-76.0), deg_to_rad(-4.0)))
		var recoil_rotation := Quaternion.from_euler(Vector3(deg_to_rad(-17.0), deg_to_rad(-56.0), deg_to_rad(-8.0)))

		_tween_tool_contact(swing_pivot, contact_offset, rest_contact, windup_contact, rest_rotation, windup_rotation, 0.19, Tween.TRANS_SINE, Tween.EASE_OUT)
		_tool_anim_tween.tween_interval(0.045)
		_tween_tool_contact(swing_pivot, contact_offset, windup_contact, approach_contact, windup_rotation, approach_rotation, 0.13, Tween.TRANS_QUAD, Tween.EASE_IN)
		_tween_tool_contact(swing_pivot, contact_offset, approach_contact, impact_contact, approach_rotation, impact_rotation, 0.095, Tween.TRANS_QUART, Tween.EASE_IN)
		_tool_anim_tween.tween_callback(func(): _apply_tool_impact(tool, target))
		_tool_anim_tween.tween_interval(0.04)
		_tween_tool_contact(swing_pivot, contact_offset, impact_contact, recoil_contact, impact_rotation, recoil_rotation, 0.09, Tween.TRANS_QUAD, Tween.EASE_OUT)
		_tween_tool_contact(swing_pivot, contact_offset, recoil_contact, rest_contact, recoil_rotation, rest_rotation, 0.23, Tween.TRANS_SINE, Tween.EASE_IN_OUT)

	_tool_anim_tween.tween_callback(_finish_tool_animation)

func _tween_swing_pose(swing_pivot: Node3D, from_position: Vector3, to_position: Vector3, from_rotation: Quaternion, to_rotation: Quaternion, duration: float, transition: Tween.TransitionType, easing: Tween.EaseType) -> void:
	var pose_method := Callable(self, "_set_swing_pose").bind(swing_pivot, from_position, to_position, from_rotation, to_rotation)
	_tool_anim_tween.tween_method(pose_method, 0.0, 1.0, duration).set_trans(transition).set_ease(easing)

func _set_swing_pose(weight: float, swing_pivot: Node3D, from_position: Vector3, to_position: Vector3, from_rotation: Quaternion, to_rotation: Quaternion) -> void:
	swing_pivot.position = from_position.lerp(to_position, weight)
	swing_pivot.quaternion = from_rotation.slerp(to_rotation, weight).normalized()

func _tween_tool_contact(swing_pivot: Node3D, contact_offset: Vector3, from_contact: Vector3, to_contact: Vector3, from_rotation: Quaternion, to_rotation: Quaternion, duration: float, transition: Tween.TransitionType, easing: Tween.EaseType) -> void:
	var pose_method := Callable(self, "_set_tool_contact_pose").bind(swing_pivot, contact_offset, from_contact, to_contact, from_rotation, to_rotation)
	_tool_anim_tween.tween_method(pose_method, 0.0, 1.0, duration).set_trans(transition).set_ease(easing)

func _set_tool_contact_pose(weight: float, swing_pivot: Node3D, contact_offset: Vector3, from_contact: Vector3, to_contact: Vector3, from_rotation: Quaternion, to_rotation: Quaternion) -> void:
	var pose_rotation := from_rotation.slerp(to_rotation, weight).normalized()
	var contact_position := from_contact.lerp(to_contact, weight)
	swing_pivot.quaternion = pose_rotation
	swing_pivot.position = contact_position - pose_rotation * contact_offset

func _reset_tool_pose() -> void:
	if _tool_anim_tween and _tool_anim_tween.is_valid():
		_tool_anim_tween.kill()
	if _axe_grip_pivot:
		_axe_grip_pivot.position = Vector3(0.62, -0.88, -1.10)
		_axe_grip_pivot.quaternion = Quaternion.IDENTITY
	if _axe_anchor:
		_axe_anchor.position = Vector3(0.13, 0.35, 0.05)
		_axe_anchor.quaternion = Quaternion.IDENTITY
	_tool_swing_pivot.position = Vector3(0.62, -0.88, -1.10)
	_tool_swing_pivot.quaternion = Quaternion.IDENTITY
	_tool_anchor.position = Vector3(0.13, 0.35, 0.05)
	_tool_anchor.quaternion = Quaternion.IDENTITY

func _on_axe_impact() -> void:
	if _vr_blade_controls_axe():
		return
	if _axe_hit_this_swing:
		return
	# Refresh the target at the actual impact frame, not when the mouse was pressed.
	interaction_ray.force_raycast_update()
	var target := _get_interactable()
	if not is_instance_valid(target):
		target = _axe_impact_target if is_instance_valid(_axe_impact_target) else null
	if is_instance_valid(target) and target is Node3D and camera.global_position.distance_to((target as Node3D).global_position) <= 3.5:
		_axe_hit_this_swing = true
		_apply_tool_impact("axe", target)

func _finish_tool_animation() -> void:
	_axe_impact_target = null
	_reset_tool_pose()
	_use_cooldown = false

func _apply_tool_impact(tool: String, target: Node) -> void:
	if not is_instance_valid(target):
		return
	if tool == "axe" and target.has_method("dismantle"):
		target.dismantle(self)
	elif target is HarvestableResource and ((tool == "axe" and target.resource_kind in ["tree", "bush", "berry"]) or (tool == "pickaxe" and target.resource_kind == "stone")):
		if tool == "axe" and target.has_method("axe_harvest") and target.call("axe_harvest", self): pass
		else: target.interact(self)

func _animate_hammer_strike() -> void:
	if not _hammer_model or not _tool_swing_pivot or _use_cooldown:
		return
	_use_cooldown = true
	_reset_tool_pose()
	var rest_position := Vector3(0.62, -0.88, -1.10)
	_tool_anim_tween = create_tween()
	_tool_anim_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tool_anim_tween.set_parallel(true)
	_tool_anim_tween.tween_property(_tool_swing_pivot, "position", Vector3(0.67, -0.80, -1.02), 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tool_anim_tween.tween_property(_tool_swing_pivot, "rotation", Vector3(-0.08, -0.05, -0.48), 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tool_anim_tween.set_parallel(false)
	_tool_anim_tween.set_parallel(true)
	_tool_anim_tween.tween_property(_tool_swing_pivot, "position", Vector3(0.60, -0.73, -1.18), 0.085).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_tool_anim_tween.tween_property(_tool_swing_pivot, "rotation", Vector3(0.10, 0.03, 0.08), 0.085).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_tool_anim_tween.set_parallel(false)
	_tool_anim_tween.tween_interval(0.035)
	_tool_anim_tween.set_parallel(true)
	_tool_anim_tween.tween_property(_tool_swing_pivot, "position", rest_position, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tool_anim_tween.tween_property(_tool_swing_pivot, "rotation", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tool_anim_tween.set_parallel(false)
	_tool_anim_tween.tween_callback(_finish_tool_animation)

func _place_building(item: String) -> void:
	if _placement_locked:
		return
	_placement_locked = true
	get_tree().create_timer(0.22).timeout.connect(func(): _placement_locked = false)
	if not SurvivalState.has_item(item):
		_notify("Craft this building piece first.", Color(1.0, 0.55, 0.3))
		_update_placement_preview_state()
		return
	if not _preview_valid:
		_notify("Cannot place it here.", Color(1.0, 0.35, 0.25))
		return
	var building: Node3D = GateBuilder.create_for(item) if item in GATE_ITEMS else FarmBedBuilder.create_bed()
	get_parent().add_child(building)
	building.global_position = _preview_position
	building.global_rotation.y = _preview_rotation
	SurvivalState.remove_item(item, 1)
	_notify("Farm bed placed. Add seeds and water it." if item == "farm_bed" else "Gate placed. Press E to open it.", Color(0.62, 1.0, 0.45))
	_update_placement_preview_state()

func _place_farm_bed() -> void:
	_place_building("farm_bed")

func _current_build_piece() -> String:
	if has_equipped_tool("hammer") and _building_mode:
		return _selected_build_piece
	return SLOT_ITEMS[selected_slot]

func _update_placement_preview_state() -> void:
	var item := _current_build_piece()
	var show_building := item in ["farm_bed", "gate", "wicket"] and not inventory_open and not _build_menu_open and (has_equipped_tool("hammer") or SurvivalState.has_item(item))
	if show_building and not is_instance_valid(_farm_bed_preview):
		_farm_bed_preview = GateBuilder.create_preview(item) if item in GATE_ITEMS else FarmBedBuilder.create_preview()
		get_parent().add_child(_farm_bed_preview)
	elif not show_building and is_instance_valid(_farm_bed_preview):
		_farm_bed_preview.queue_free(); _farm_bed_preview = null
	if item not in ["fence", "base_fence"] or inventory_open or _build_menu_open:
		_cancel_fence_drag()
	_preview_valid = false

func _update_farm_bed_preview() -> void:
	var item := _current_build_piece()
	if _fence_dragging:
		_update_fence_drag()
		return
	if has_equipped_tool("hammer") and _building_mode and item in ["fence", "base_fence"] and not _build_menu_open:
		_update_hammer_fence_preview(item)
		return
	if not is_instance_valid(_farm_bed_preview):
		return
	var flat_forward := -camera.global_transform.basis.z;flat_forward.y = 0.0
	if flat_forward.length_squared() < 0.01:flat_forward = -global_transform.basis.z
	if item in GATE_ITEMS:
		# Project the view ray onto the terrain close to the player. The gate
		# pivot follows the crosshair instead of an offset from the player body.
		var view := -camera.global_transform.basis.z.normalized()
		var point := camera.global_position + view * 3.0
		if view.y < -0.02:
			var ground_y := _fence_ground_height(point)
			var distance := clampf((ground_y - camera.global_position.y) / view.y, 2.0, 4.0)
			point = camera.global_position + view * distance
		_preview_rotation = snappedf(rotation.y + _build_rotation_offset, PI / 8.0)
		var gate_axis := Basis(Vector3.UP, _preview_rotation).x
		var gate_center := Vector3(point.x, _fence_ground_height(point), point.z)
		var snap := _gate_snap_to_fence(gate_center, gate_axis, _gate_span() * 0.5)
		if snap.x > -INF:
			gate_center = snap
		# The model starts at its left post: put the OPENING, not that post, under the crosshair.
		_preview_position = gate_center - gate_axis * (_gate_span() * 0.5)
		_preview_position.y = _fence_ground_height(_preview_position)
	else:
		# Beds follow the crosshair, not a fixed point in front of the player's body.
		# This makes close placement reliable when looking down and keeps the final
		# object exactly where the preview was shown.
		var origin := camera.global_position
		var view := -camera.global_transform.basis.z.normalized()
		var target := origin + view * 2.2
		var query := PhysicsRayQueryParameters3D.create(origin, origin + view * 3.6, 1)
		query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			target = hit.position as Vector3
		elif view.y < -0.02:
			var flat_hit := origin + view * clampf((_fence_ground_height(origin) - origin.y) / view.y, 0.9, 3.6)
			target = flat_hit
		else:
			target = global_position + flat_forward.normalized() * 2.2
		_preview_position = Vector3(snappedf(target.x, 0.25), _fence_ground_height(target), snappedf(target.z, 0.25))
	_preview_rotation=snappedf(rotation.y + _build_rotation_offset, PI/8.0);_farm_bed_preview.global_position=_preview_position;_farm_bed_preview.global_rotation.y=_preview_rotation
	_preview_valid=_is_building_position_clear(_preview_position,item)
	if item in GATE_ITEMS:GateBuilder.set_preview_valid(_farm_bed_preview,_preview_valid)
	else:FarmBedBuilder.set_preview_valid(_farm_bed_preview,_preview_valid)
	var cost_text := _build_cost_text(item) if has_equipped_tool("hammer") else "crafted item"
	interaction_prompt.text=("LMB place %s  •  %s  •  R rotate  •  RMB menu  •  MMB remove" % [BUILD_NAMES.get(item,item), cost_text]) if _preview_valid else "Placement blocked  •  R rotate"
	interaction_prompt.visible=not inventory_open

func _start_fence_drag() -> void:
	if inventory_open:return
	if not SurvivalState.has_item("hammer") or SurvivalState.get_tool_durability("hammer") <= 0:
		_notify("Craft a working building hammer first.", Color(1.0, 0.42, 0.24)); return
	var wood_rate := _selected_fence_wood_rate()
	if int(SurvivalState.inventory.get("wood",0)) < wood_rate:
		_notify("You need wood to build a fence.",Color(1,.45,.22));return
	_fence_start = _fence_aim_point()
	_fence_end = _fence_start
	_fence_dragging = true
	var anchor: Node3D = RusticFenceBuilder.create_anchor_preview(_fence_start) if _current_build_piece() == "base_fence" else FenceBuilder.create_anchor_preview(_fence_start)
	_replace_fence_preview(anchor)
	interaction_prompt.text = "Start fixed • keep LMB held and aim at the end point"
	interaction_prompt.visible = true

func _update_fence_drag() -> void:
	_fence_end=_fence_aim_point()
	var delta:=_fence_end-_fence_start;delta.y=0
	if delta.length()>FENCE_MAX_LENGTH:_fence_end=_fence_start+delta.normalized()*FENCE_MAX_LENGTH
	var wood_rate := _selected_fence_wood_rate()
	var affordable:=float(int(SurvivalState.inventory.get("wood",0)))/float(wood_rate)
	delta=_fence_end-_fence_start;delta.y=0
	if delta.length()>affordable:_fence_end=_fence_start+delta.normalized()*affordable
	_fence_end.x=snappedf(_fence_end.x,.25);_fence_end.z=snappedf(_fence_end.z,.25)
	_fence_end.y = _fence_ground_height(_fence_end)
	_fence_end = _snap_to_fence_post(_fence_end)
	var length:=Vector2(_fence_end.x-_fence_start.x,_fence_end.z-_fence_start.z).length()
	_preview_valid=length>=FenceBuilder.MIN_LENGTH and not _fence_obstructed(_fence_start, _fence_end)
	var use_base: bool = _current_build_piece() == "base_fence"
	var next_preview: Node3D
	if length >= FenceBuilder.MIN_LENGTH:
		next_preview = RusticFenceBuilder.create_preview_between(_fence_start,_fence_end,_preview_valid,_fence_ground()) if use_base else FenceBuilder.create_preview_between(_fence_start,_fence_end,_preview_valid,_fence_ground())
	else:
		next_preview = RusticFenceBuilder.create_anchor_preview(_fence_start) if use_base else FenceBuilder.create_anchor_preview(_fence_start)
	_replace_fence_preview(next_preview)
	var cost:=ceili(length)*wood_rate
	interaction_prompt.text = ("Release LMB: %.1f m fence  •  %d wood" % [length,cost]) if _preview_valid else ("Fence intersects an object" if length >= FenceBuilder.MIN_LENGTH else "Drag at least 1 meter")
	interaction_prompt.visible=true

func _finish_fence_drag() -> void:
	if not _fence_dragging:return
	_update_fence_drag()
	var length:=Vector2(_fence_end.x-_fence_start.x,_fence_end.z-_fence_start.z).length();var cost:=ceili(length)*_selected_fence_wood_rate()
	if _preview_valid and not _fence_obstructed(_fence_start, _fence_end) and SurvivalState.remove_item("wood",cost):
		var fence:Node3D = RusticFenceBuilder.create_between(_fence_start,_fence_end,_fence_ground()) if _current_build_piece() == "base_fence" else FenceBuilder.create_between(_fence_start,_fence_end,_fence_ground())
		get_parent().add_child(fence)
		fence.set_meta("fence_ends", [_fence_start, _fence_end, _current_build_piece() == "base_fence"])
		SurvivalState.damage_tool("hammer")
		_notify("Built %.1f m of fence for %d wood."%[length,cost],Color(.62,1,.45))
	_cancel_fence_drag()

func _cancel_fence_drag() -> void:
	_fence_dragging=false
	if is_instance_valid(_fence_preview):
		var old_preview := _fence_preview
		_fence_preview = null
		if old_preview.get_parent():
			old_preview.get_parent().remove_child(old_preview)
		old_preview.queue_free()

func _selected_fence_wood_rate() -> int:
	return BASE_FENCE_WOOD_PER_METER if _current_build_piece() == "base_fence" else FENCE_WOOD_PER_METER

func _fence_obstructed(start: Vector3, finish: Vector3) -> bool:
	# Test the entire stretched fence in short terrain-following sections, not
	# just its endpoints. Ignore the ground and allow joining at an existing post.
	var flat := finish - start
	flat.y = 0.0
	var length := flat.length()
	if length < 0.01:
		return false
	var direction := flat / length
	var sections := maxi(1, ceili(length / 0.45))
	var space := get_world_3d().direct_space_state
	var ground := _fence_ground() as CollisionObject3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	if ground:
		query.exclude.append(ground.get_rid())
	var box := BoxShape3D.new()
	query.shape = box
	var heading := atan2(-direction.z, direction.x)
	for i in range(sections):
		var a := length * float(i) / float(sections)
		var b := length * float(i + 1) / float(sections)
		var middle := (a + b) * 0.5
		var y0 := _fence_ground_height(start + direction * a)
		var y1 := _fence_ground_height(start + direction * b)
		var ym := _fence_ground_height(start + direction * middle)
		var bottom := minf(y0, minf(y1, ym))
		var top := maxf(y0, maxf(y1, ym))
		box.size = Vector3(b - a + 0.06, 1.25 + top - bottom, 0.26)
		query.transform = Transform3D(Basis(Vector3.UP, heading), Vector3(start.x + direction.x * middle, (top + bottom) * 0.5 + 0.625, start.z + direction.z * middle))
		for hit in space.intersect_shape(query, 64):
			var collider := hit.get("collider") as CollisionObject3D
			if collider == null:
				continue
			var structure: Node = collider
			while structure and not _is_snap_structure(structure):
				structure = structure.get_parent()
			if structure is Node3D and (a < 0.25 or length - b < 0.25):
				var endpoint := start if a < 0.25 else finish
				var joins_post := false
				for local_post in structure.get_meta("post_positions", []):
					var world_post := (structure as Node3D).to_global(local_post)
					if Vector2(endpoint.x, endpoint.z).distance_to(Vector2(world_post.x, world_post.z)) < 0.12:
						joins_post = true
						break
				if joins_post:
					continue
			return true
	return false

func _fence_aim_point() -> Vector3:
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * FENCE_MAX_LENGTH, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var result: Vector3
	if not hit.is_empty():
		result = hit.position
	elif direction.y < -0.02:
		result = origin + direction * clampf((.02 - origin.y) / direction.y, 1.0, FENCE_MAX_LENGTH)
	else:
		var flat := direction;flat.y = 0.0
		if flat.length_squared() < .01:flat = -global_transform.basis.z
		result = global_position + flat.normalized() * 5.0
	# Search before grid snapping: existing posts take precedence over the grid.
	var post := _nearest_fence_post(result)
	if post.x > -INF:
		return post
	result.x = snappedf(result.x,.25);result.z = snappedf(result.z,.25);result.y = _fence_ground_height(result)
	return result

func _nearest_fence_post(point: Vector3) -> Vector3:
	var nearest := Vector3(-INF, 0.0, 0.0)
	var best_distance := 0.8
	for fence in _snap_structures():
		if not fence is Node3D or not fence.has_meta("post_positions"):
			continue
		var fence_node := fence as Node3D
		for local_post in fence_node.get_meta("post_positions"):
			var world_post := fence_node.to_global(local_post)
			var distance := Vector2(point.x, point.z).distance_to(Vector2(world_post.x, world_post.z))
			if distance < best_distance:
				best_distance = distance
				nearest = world_post
	return nearest

func _gate_snap_to_fence(center: Vector3, axis: Vector3, half_span: float = 1.5) -> Vector3:
	var nearest := Vector3(-INF, 0.0, 0.0)
	var best_distance := 0.85
	for fence in _snap_structures():
		if not fence is Node3D or not fence.has_meta("post_positions"):
			continue
		var posts: Array = fence.get_meta("post_positions")
		if posts.size() < 2:
			continue
		# Only the two end posts are available: do not cover an existing fence span.
		for index in [0, posts.size() - 1]:
			var post: Vector3 = (fence as Node3D).to_global(posts[index] as Vector3)
			for side: float in [-1.0, 1.0]:
				var candidate: Vector3 = post + axis * (half_span * side)
				var distance: float = Vector2(center.x, center.z).distance_to(Vector2(candidate.x, candidate.z))
				if distance < best_distance:
					best_distance = distance
					nearest = candidate
	return nearest

func _snap_to_fence_post(point: Vector3) -> Vector3:
	var post := _nearest_fence_post(point)
	return post if post.x > -INF else point

func _fence_ground() -> Node:
	return get_parent().get_node_or_null("Ground")

func _fence_ground_height(position: Vector3) -> float:
	var ground := _fence_ground()
	if ground and ground.has_method("surface_height"):
		return float(ground.call("surface_height", Vector2(position.x, position.z))) + 0.02
	return position.y

func _replace_fence_preview(next_preview: Node3D) -> void:
	if is_instance_valid(_fence_preview):
		var old_preview := _fence_preview
		_fence_preview = null
		if old_preview.get_parent():old_preview.get_parent().remove_child(old_preview)
		old_preview.queue_free()
	_fence_preview = next_preview
	get_parent().add_child(_fence_preview)

func _is_building_position_clear(position: Vector3, item: String) -> bool:
	var parameters:=PhysicsShapeQueryParameters3D.new();var box:=BoxShape3D.new();box.size=Vector3(_gate_span(),1.7,.28) if item in GATE_ITEMS else Vector3(2.5,1.0,1.8)
	var basis:=Basis(Vector3.UP,_preview_rotation)
	var center:=position+basis.x*(_gate_span()*0.5) if item in GATE_ITEMS else position
	parameters.shape=box;parameters.transform=Transform3D(basis,center+Vector3.UP*(.87 if item in GATE_ITEMS else .48));parameters.collision_mask=0xFFFFFFFF;parameters.exclude=[get_rid()]
	var ground:=_fence_ground() as CollisionObject3D
	if ground:parameters.exclude.append(ground.get_rid())
	var hits:=get_world_3d().direct_space_state.intersect_shape(parameters,32)
	for hit in hits:
		var collider:=hit.get("collider") as CollisionObject3D
		if collider == null:continue
		if item in GATE_ITEMS:
			var structure:Node=collider
			while structure and not _is_snap_structure(structure):
				structure=structure.get_parent()
			if structure is Node3D and structure.has_meta("post_positions"):
				var existing_posts: Array = structure.get_meta("post_positions")
				if existing_posts.size() >= 2:
					for index in [0, existing_posts.size() - 1]:
						var world_post: Vector3 = (structure as Node3D).to_global(existing_posts[index])
						var other_post: Vector3 = (structure as Node3D).to_global(existing_posts[1 if index == 0 else existing_posts.size() - 2])
						var left_end := position
						var right_end := position + basis.x * _gate_span()
						var attached := left_end if Vector2(world_post.x, world_post.z).distance_to(Vector2(left_end.x, left_end.z)) < 0.12 else right_end
						var free_end := right_end if attached == left_end else left_end
						var near_post := Vector2(world_post.x, world_post.z).distance_to(Vector2(attached.x, attached.z)) < 0.12
						var existing_direction := Vector2(other_post.x - world_post.x, other_post.z - world_post.z).normalized()
						var gate_direction := Vector2(free_end.x - attached.x, free_end.z - attached.z).normalized()
						# Only permit joining OUTSIDE the existing fence; not a gate laid over it.
						if near_post and existing_direction.dot(gate_direction) <= 0.05:
							structure = null
							break
				if structure == null:continue
		return false
	return true

func _try_interact() -> void:
	var target := _get_interactable()
	if target and target.has_method("interact"):
		target.interact(self)
		return
	# Small forage items are easy to miss with a thin ray: pick the nearest one in front.
	var fwd := -camera.global_transform.basis.z; fwd.y = 0.0
	var aim := global_position + fwd.normalized() * 1.2
	var best: Node = null; var best_d := 2.2
	for r in get_tree().get_nodes_in_group("harvestable_resources"):
		if r is HarvestableResource and r.resource_kind in ["mushroom", "berry"] and r.get_interaction_text() != "":
			var d := (r as Node3D).global_position.distance_to(aim)
			if d < best_d: best = r; best_d = d
	if best: best.interact(self)

func _get_interactable() -> Node:
	if not interaction_ray.is_colliding():
		return null
	var target := interaction_ray.get_collider() as Node
	while target:
		if target.has_method("interact") or target.has_method("dismantle"):
			return target
		target = target.get_parent()
	return null

func _vr_blade_controls_axe() -> bool:
	var simulator := get_node_or_null("DesktopVRSimulator")
	if simulator and simulator.get("active"):
		return true
	var webxr_player := get_node_or_null("WebXRPlayer")
	return webxr_player != null and webxr_player.get("xr_active") == true

func _check_axe_blade_contact() -> void:
	if _vr_blade_controls_axe():
		return
	if not _axe_model or not _axe_model.is_swinging():
		return
	var tip: Vector3 = _axe_model.get_blade_tip()
	if _axe_model.is_striking() and not _axe_hit_this_swing:
		var query := PhysicsRayQueryParameters3D.create(_axe_last_tip, tip, interaction_ray.collision_mask, [get_rid()])
		query.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var target := hit["collider"] as Node
			while target and not target.has_method("interact") and not target.has_method("dismantle"):
				target = target.get_parent()
			if is_instance_valid(target) and target is Node3D and camera.global_position.distance_to((target as Node3D).global_position) <= 3.5:
				_axe_hit_this_swing = true
				_apply_tool_impact("axe", target)
	_axe_last_tip = tip

func _physics_process(delta: float) -> void:
	_check_axe_blade_contact()
	if inventory_open or _build_menu_open:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
		if not is_on_floor():
			velocity += get_gravity() * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var sprinting := Input.is_key_pressed(KEY_SHIFT) and SurvivalState.stamina > 1.0 and dir.length_squared() > 0.0
	var current_speed := sprint if sprinting else speed
	SurvivalState.update_movement(delta, sprinting)
	if dir:
		velocity.x = dir.x * current_speed
		velocity.z = dir.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)
	var was_on_floor := is_on_floor()
	var start_transform := global_transform
	var horizontal := Vector3(velocity.x, 0.0, velocity.z) * delta
	move_and_slide()
	# Compare progress along the requested direction. A stair can stop the body
	# without Godot reporting is_on_wall(), especially when the GLB uses a ramp.
	var moved := global_position - start_transform.origin
	var forward_progress := moved.dot(horizontal.normalized()) if horizontal.length_squared() > 0.000001 else 0.0
	var blocked := horizontal.length_squared() > 0.000001 and forward_progress < horizontal.length() * 0.65
	if (was_on_floor or is_on_floor()) and blocked:
		_try_step_up(start_transform, horizontal)

func _try_step_up(start: Transform3D, horizontal: Vector3) -> void:
	var slide_transform := global_transform
	var slide_velocity := velocity
	global_transform = start

	# Lift the full permitted step height, move forward above the obstacle, then
	# sweep down. This works for both authored stair boxes and convex stair ramps.
	var up := Vector3.UP * max_step_height
	if test_move(global_transform, up):
		global_transform = slide_transform
		velocity = slide_velocity
		return
	global_position += up

	var forward_hit := move_and_collide(horizontal)
	if forward_hit != null:
		global_transform = slide_transform
		velocity = slide_velocity
		return

	var down_distance := max_step_height + maxf(floor_snap_length, 0.08) + 0.05
	var down_hit := move_and_collide(Vector3.DOWN * down_distance)
	if down_hit == null or down_hit.get_normal().dot(Vector3.UP) < cos(floor_max_angle):
		global_transform = slide_transform
		velocity = slide_velocity
		return

	var step_height := global_position.y - start.origin.y
	if step_height < -0.01 or step_height > max_step_height + 0.02:
		global_transform = slide_transform
		velocity = slide_velocity
		return
	velocity.y = 0.0

func _build_axe_model() -> void:
	_tool_swing_pivot = Node3D.new()
	_tool_swing_pivot.name = "ToolSwingPivot"
	_tool_swing_pivot.position = Vector3(0.62, -0.88, -1.10)
	camera.add_child(_tool_swing_pivot)
	_tool_anchor = Node3D.new()
	_tool_anchor.name = "HeldTool"
	# Offset back from the grip pivot to the models' original camera-space pose.
	_tool_anchor.position = Vector3(0.13, 0.35, 0.05)
	_tool_swing_pivot.add_child(_tool_anchor)
	_tool_anchor.scale = Vector3.ONE * 0.72

	# The axe has its own true hand/grip pivot. Pickaxe and hammer keep the
	# original shared pivot, so axe rotations cannot distort their animations.
	_axe_grip_pivot = Node3D.new()
	_axe_grip_pivot.name = "AxeGripPivot"
	_axe_grip_pivot.position = Vector3(0.62, -0.88, -1.10)
	camera.add_child(_axe_grip_pivot)
	_axe_anchor = Node3D.new()
	_axe_anchor.name = "AxeHeldTool"
	_axe_anchor.position = Vector3(0.13, 0.35, 0.05)
	_axe_grip_pivot.add_child(_axe_anchor)
	_axe_anchor.scale = Vector3.ONE * 0.72

	var wood := _tool_material(Color(0.31, 0.105, 0.028), 0.0, 0.72)
	var dark_wood := _tool_material(Color(0.12, 0.032, 0.012), 0.0, 0.88)
	var leather := _tool_material(Color(0.105, 0.038, 0.014), 0.0, 0.96)
	var steel := _tool_material(Color(0.23, 0.285, 0.30), 0.82, 0.27)
	var dark_steel := _tool_material(Color(0.075, 0.095, 0.10), 0.76, 0.42)
	var edge_steel := _tool_material(Color(0.62, 0.71, 0.72), 0.92, 0.16)
	var brass := _tool_material(Color(0.48, 0.25, 0.055), 0.72, 0.3)

	# Forest axe: tapered hardwood haft, wrapped grip, reinforced eye, poll and
	# a layered blade with a separately polished cutting edge.
	_axe_model = preload("res://scenes/tools/low_poly_axe.tscn").instantiate()
	_axe_model.name = "LowPolyAxe"
	# New blade points along -X; keep the existing first-person grip pivot.
	_axe_model.rotation = Vector3(-0.12, 0.08, 0.08)
	_axe_anchor.add_child(_axe_model)
	_axe_eye = _axe_model.get_node("SwingPivot/BladeEye")
	_axe_strike_point = _axe_model.get_node("SwingPivot/BladeTip")
	_axe_model.impact.connect(_on_axe_impact)
	_axe_model.swing_finished.connect(_finish_tool_animation)

	# Woodland miner's pick: dark forged iron, one tapered beak and a compact
	# hammer poll on a warm hardwood haft, with leather grip and brass rivets.
	_pickaxe_model = Node3D.new()
	_pickaxe_model.name = "ForestMinerPickaxe"
	_pickaxe_model.rotation = Vector3(-0.12, PI + 0.08, 0.08)
	_tool_anchor.add_child(_pickaxe_model)
	var pick_haft := Node3D.new()
	pick_haft.rotation.z = -0.19
	_pickaxe_model.add_child(pick_haft)
	_add_tool_cylinder(pick_haft, "HardwoodHaft", 0.82, 0.033, 0.048, Vector3(0.0, -0.02, 0.0), Vector3.ZERO, wood, 10)
	_add_tool_sphere(pick_haft, "DarkWoodPommel", 0.052, Vector3(0.0, -0.43, 0.0), dark_wood)
	_add_grip_wrap(pick_haft, leather, -0.32, 5, 0.039, 0.05)
	_add_tool_cylinder(pick_haft, "GripFerrule", 0.025, 0.046, 0.046, Vector3(0.0, -0.12, 0.0), Vector3.ZERO, brass, 10)
	_add_tool_cylinder(pick_haft, "IronSocket", 0.11, 0.051, 0.048, Vector3(0.0, 0.31, 0.0), Vector3.ZERO, dark_steel, 10)
	_add_tool_box(pick_haft, "ForgedEye", Vector3(0.18, 0.14, 0.14), Vector3(0.0, 0.37, 0.0), Vector3.ZERO, dark_steel)
	_add_tool_prism(pick_haft, "ForgedBeak", Vector3(0.48, 0.14, 0.14), Vector3(0.31, 0.38, 0.0), Vector3(0.0, 0.0, -0.08), steel, 0.32)
	_add_tool_cylinder(pick_haft, "HardenedPoint", 0.22, 0.005, 0.065, Vector3(0.62, 0.35, 0.0), Vector3(0.0, 0.0, -PI * 0.5), edge_steel, 8)
	_add_tool_box(pick_haft, "HammerPoll", Vector3(0.20, 0.15, 0.15), Vector3(-0.18, 0.37, 0.0), Vector3.ZERO, steel)
	_add_tool_cylinder(pick_haft, "PollFace", 0.025, 0.083, 0.083, Vector3(-0.29, 0.37, 0.0), Vector3(0.0, 0.0, PI * 0.5), edge_steel, 8)
	_add_tool_cylinder(pick_haft, "BrassRivet", 0.155, 0.015, 0.015, Vector3(0.0, 0.38, 0.0), Vector3(PI * 0.5, 0.0, 0.0), brass, 10)
	_pickaxe_strike_point = Node3D.new()
	_pickaxe_strike_point.name = "PickaxeStrikePoint"
	_pickaxe_strike_point.position = Vector3(0.73, 0.35, 0.0)
	pick_haft.add_child(_pickaxe_strike_point)

	# Carpenter's hammer: shaped handle, wrapped grip, forged cheek, round striking
	# face, brass wedge and a split curved claw instead of a plain metal block.
	_hammer_model = Node3D.new()
	_hammer_model.name = "DetailedHammer"
	_hammer_model.rotation = Vector3(-0.12, PI + 0.08, 0.08)
	_tool_anchor.add_child(_hammer_model)
	var hammer_haft := Node3D.new()
	hammer_haft.rotation.z = -0.25
	_hammer_model.add_child(hammer_haft)
	_add_tool_cylinder(hammer_haft, "Haft", 0.78, 0.035, 0.052, Vector3.ZERO, Vector3.ZERO, wood, 12)
	_add_tool_sphere(hammer_haft, "Pommel", 0.058, Vector3(0.0, -0.38, 0.0), dark_wood)
	_add_grip_wrap(hammer_haft, leather, -0.255, 6, 0.047, 0.052)
	_add_tool_cylinder(hammer_haft, "HeadCollar", 0.10, 0.057, 0.053, Vector3(0.0, 0.29, 0.0), Vector3.ZERO, dark_steel, 12)
	_add_tool_box(hammer_haft, "HammerCheek", Vector3(0.34, 0.18, 0.19), Vector3(0.015, 0.365, 0.0), Vector3.ZERO, steel)
	_add_tool_cylinder(hammer_haft, "FaceNeck", 0.16, 0.073, 0.09, Vector3(0.23, 0.365, 0.0), Vector3(0.0, 0.0, -PI * 0.5), steel, 12)
	_add_tool_cylinder(hammer_haft, "StrikingFace", 0.035, 0.118, 0.118, Vector3(0.325, 0.365, 0.0), Vector3(0.0, 0.0, -PI * 0.5), edge_steel, 16)
	_add_tool_box(hammer_haft, "ClawNeck", Vector3(0.20, 0.11, 0.14), Vector3(-0.20, 0.385, 0.0), Vector3(0.0, 0.0, -0.12), dark_steel)
	_add_tool_box(hammer_haft, "ClawLeft", Vector3(0.29, 0.055, 0.048), Vector3(-0.39, 0.43, -0.054), Vector3(0.0, 0.0, -0.24), steel)
	_add_tool_box(hammer_haft, "ClawRight", Vector3(0.29, 0.055, 0.048), Vector3(-0.39, 0.43, 0.054), Vector3(0.0, 0.0, -0.24), steel)
	_add_tool_cylinder(hammer_haft, "HammerPin", 0.215, 0.018, 0.018, Vector3(0.0, 0.37, 0.0), Vector3(PI * 0.5, 0.0, 0.0), brass, 12)
	_add_tool_box(hammer_haft, "HandleWedge", Vector3(0.075, 0.018, 0.09), Vector3(0.0, 0.462, 0.0), Vector3.ZERO, brass)

	_update_tool_visibility()

func _tool_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material

func _add_tool_cylinder(parent: Node3D, part_name: String, height: float, top_radius: float, bottom_radius: float, position: Vector3, rotation: Vector3, material: StandardMaterial3D, segments: int) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := CylinderMesh.new()
	mesh.height = height
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.radial_segments = segments
	mesh.rings = 2
	mesh.material = material
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(part)
	return part

func _add_tool_box(parent: Node3D, part_name: String, size: Vector3, position: Vector3, rotation: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(part)
	return part

func _add_tool_prism(parent: Node3D, part_name: String, size: Vector3, position: Vector3, rotation: Vector3, material: StandardMaterial3D, slope: float) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.left_to_right = slope
	mesh.material = material
	part.mesh = mesh
	part.position = position
	part.rotation = rotation
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(part)
	return part

func _add_tool_sphere(parent: Node3D, part_name: String, radius: float, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	part.mesh = mesh
	part.position = position
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(part)
	return part

func _add_grip_wrap(parent: Node3D, material: StandardMaterial3D, start_y: float, count: int, radius: float, spacing: float) -> void:
	for index in count:
		var band_y := start_y + float(index) * spacing
		_add_tool_cylinder(parent, "GripBand_%02d" % index, 0.032, radius, radius, Vector3(0.0, band_y, 0.0), Vector3.ZERO, material, 12)

func _update_tool_visibility() -> void:
	if _axe_model:
		_axe_model.visible = has_equipped_tool("axe") and SurvivalState.has_item("axe") and not inventory_open and not _build_menu_open
	if _pickaxe_model:
		_pickaxe_model.visible = has_equipped_tool("pickaxe") and SurvivalState.has_item("pickaxe") and not inventory_open and not _build_menu_open
	if _hammer_model:
		_hammer_model.visible = has_equipped_tool("hammer") and SurvivalState.has_item("hammer") and not inventory_open and not _build_menu_open

func _relayout_game_hud() -> void:
	# Gameplay keeps only vital information; secondary details live in Tab.
	var vitals := $HUD/SurvivalPanel as PanelContainer
	vitals.offset_left = 22.0
	vitals.offset_top = 22.0
	vitals.offset_right = 205.0
	vitals.offset_bottom = 142.0
	var contents := $HUD/SurvivalPanel/Margin/VBox as VBoxContainer
	contents.add_theme_constant_override("separation", 2)
	inventory_label.visible = false
	(contents.get_node("Title") as Label).visible = false
	for pair in [["HealthText", "HEALTH"], ["HungerText", "HUNGER"], ["WarmthText", "WARMTH"], ["StaminaText", "STAMINA"]]:
		var label := contents.get_node(pair[0]) as Label
		label.text = pair[1]
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.70, 0.78, 0.73))
	for bar in [health_bar, hunger_bar, warmth_bar, stamina_bar]:
		bar.custom_minimum_size = Vector2(155, 5)
		bar.show_percentage = false
	var objective := $HUD/ObjectivePanel as PanelContainer
	objective.visible = false
	($HUD/ObjectivePanel/Margin/VBox/Controls as Label).visible = false
	var time := $HUD/TopBar as PanelContainer
	time.offset_left = -72.0
	time.offset_right = 72.0
	time.offset_top = 22.0
	time.offset_bottom = 46.0
	clock_label.add_theme_font_size_override("font_size", 12)
	interaction_prompt.add_theme_font_size_override("font_size", 14)
	interaction_prompt.offset_left = -280.0
	interaction_prompt.offset_right = 280.0
	interaction_prompt.anchor_top = 0.62
	interaction_prompt.anchor_bottom = 0.62
	($HUD/Crosshair as Label).text = "·"
	($HUD/Crosshair as Label).add_theme_font_size_override("font_size", 24)
	$HUD/Notification.add_theme_font_size_override("font_size", 14)

func _build_hotbar() -> void:
	var panel := PanelContainer.new()
	panel.name = "HotbarPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position = Vector2(0.0, -58.0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.045, 0.065, 0.056, 0.55), Color(0.46, 0.54, 0.48, 0.15), 1, 9))
	$HUD.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 4)
	margin.add_child(_hotbar)
	for i in SLOT_ITEMS.size():
		var button := Button.new()
		button.custom_minimum_size = Vector2(46, 42)
		button.focus_mode = Control.FOCUS_NONE
		button.text = "%s\n%s" % [str(i + 1) if i < 9 else ("0" if i == 9 else "·"), SLOT_ICONS[i]]
		button.add_theme_font_size_override("font_size", 11)
		button.pressed.connect(_select_slot.bind(i))
		_hotbar.add_child(button)
		_hotbar_buttons.append(button)
	panel.custom_minimum_size.x = float(SLOT_ITEMS.size() * 46 + maxi(0, SLOT_ITEMS.size() - 1) * 4 + 26)

func _build_inventory_window() -> void:
	_inventory_overlay = ColorRect.new()
	_inventory_overlay.name = "InventoryOverlay"
	_inventory_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inventory_overlay.color = Color(0.018, 0.035, 0.028, 0.72)
	_inventory_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory_overlay.visible = false
	$HUD.add_child(_inventory_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inventory_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 580)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.095, 0.075, 0.98), Color(0.72, 0.77, 0.61, 0.70), 2, 18))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 11)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "INVENTORY & CRAFTING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	vbox.add_child(title)
	var hint := Label.new()
	hint.text = "Select an item to equip, use or place it  •  Tab to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.82, 0.86, 0.76))
	vbox.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)
	for i in SLOT_ITEMS.size():
		var item: String = SLOT_ITEMS[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(158, 64)
		button.add_theme_font_size_override("font_size", 15)
		_style_menu_button(button)
		button.pressed.connect(_inventory_item_pressed.bind(i))
		grid.add_child(button)
		_inventory_buttons[item] = button
	var craft_title := Label.new()
	craft_title.text = "CRAFTING   /   AVAILABLE RECIPES"
	craft_title.add_theme_font_size_override("font_size", 20)
	craft_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	vbox.add_child(craft_title)
	var craft_list := VBoxContainer.new()
	craft_list.add_theme_constant_override("separation", 8)
	vbox.add_child(craft_list)
	for recipe in ["hammer", "axe", "pickaxe"]:
		var craft_button := Button.new()
		craft_button.custom_minimum_size = Vector2(0, 48)
		craft_button.add_theme_font_size_override("font_size", 16)
		_style_menu_button(craft_button, true)
		craft_button.pressed.connect(_craft_item.bind(recipe))
		craft_list.add_child(craft_button)
		_craft_buttons[recipe] = craft_button
	var close := Button.new()
	close.text = "CLOSE  [TAB]"
	close.custom_minimum_size.y = 44
	_style_menu_button(close)
	close.pressed.connect(_toggle_inventory.bind(false))
	vbox.add_child(close)

func _inventory_item_pressed(slot: int) -> void:
	_select_slot(slot)
	if SLOT_ITEMS[slot] in EDIBLE:
		SurvivalState.eat_item(SLOT_ITEMS[slot])
	elif SLOT_ITEMS[slot] in ["axe", "pickaxe", "hammer"]:
		_toggle_inventory(false)

func _craft_item(item: String) -> void:
	if SurvivalState.craft(item):
		var slot := SLOT_ITEMS.find(item)
		if slot >= 0:
			_select_slot(slot)
	_update_crafting_buttons()

func _update_crafting_buttons() -> void:
	for item in _craft_buttons:
		var button := _craft_buttons[item] as Button
		var recipe: Dictionary = SurvivalState.RECIPES[item]
		button.text = "%s    %s
%s" % [str(recipe.label).to_upper(), "CRAFT" if SurvivalState.can_craft(item) else "MISSING MATERIALS", SurvivalState.recipe_text(item)]
		button.disabled = not SurvivalState.can_craft(item)

func _toggle_inventory(open: bool) -> void:
	if open: _close_build_menu()
	inventory_open = open
	_inventory_overlay.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	_update_tool_visibility()
	_update_placement_preview_state()

func _build_contrast_theme() -> void:
	# Quiet forest-glass UI: a clear hierarchy without obscuring the scene.
	var ink := Color(0.055, 0.075, 0.068, 0.90)
	var edge := Color(0.65, 0.72, 0.60, 0.48)
	for panel_path in ["HUD/SurvivalPanel", "HUD/ObjectivePanel", "HUD/TopBar"]:
		var panel := get_node(panel_path) as PanelContainer
		panel.modulate = Color.WHITE
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _panel_style(ink, edge, 1, 14))
	for label_path in ["HUD/SurvivalPanel/Margin/VBox/Title", "HUD/SurvivalPanel/Margin/VBox/HealthText", "HUD/SurvivalPanel/Margin/VBox/HungerText", "HUD/SurvivalPanel/Margin/VBox/WarmthText", "HUD/SurvivalPanel/Margin/VBox/StaminaText", "HUD/SurvivalPanel/Margin/VBox/Inventory", "HUD/ObjectivePanel/Margin/VBox/Objective", "HUD/ObjectivePanel/Margin/VBox/Controls", "HUD/TopBar/Clock"]:
		var label := get_node(label_path) as Label
		label.add_theme_color_override("font_color", Color(0.91, 0.93, 0.85))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.38))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	for label_path in ["HUD/SurvivalPanel/Margin/VBox/Title", "HUD/TopBar/Clock"]:
		(get_node(label_path) as Label).add_theme_color_override("font_color", Color(1.0, 0.80, 0.48))
	(get_node("HUD/ObjectivePanel/Margin/VBox/Controls") as Label).add_theme_color_override("font_color", Color(0.70, 0.77, 0.69))
	interaction_prompt.add_theme_stylebox_override("normal", _panel_style(Color(0.06, 0.09, 0.075, 0.93), Color(0.83, 0.68, 0.40, 0.65), 1, 10))
	interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.86, 0.60))
	for data in [[health_bar, Color(0.84, 0.38, 0.37)], [hunger_bar, Color(0.90, 0.68, 0.34)], [warmth_bar, Color(0.91, 0.48, 0.27)], [stamina_bar, Color(0.48, 0.72, 0.49)]]:
		var bar := data[0] as ProgressBar
		bar.modulate = Color.WHITE
		bar.add_theme_stylebox_override("background", _panel_style(Color(0.12, 0.17, 0.14, 0.94), Color(0.25, 0.32, 0.26, 0.7), 1, 5))
		bar.add_theme_stylebox_override("fill", _panel_style(data[1], data[1].lightened(0.12), 1, 5))

func _panel_style(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.24)
	style.shadow_size = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _style_slot(button: Button, selected: bool) -> void:
	var fill := Color(0.14, 0.21, 0.17, 0.91) if selected else Color(0.05, 0.08, 0.07, 0.56)
	var border := Color(0.91, 0.78, 0.51, 0.85) if selected else Color(0.46, 0.54, 0.48, 0.16)
	button.add_theme_stylebox_override("normal", _panel_style(fill, border, 1, 7))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.18, 0.26, 0.20, 0.90), Color(0.78, 0.79, 0.62, 0.68), 1, 7))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.21, 0.27, 0.21, 0.93), border, 1, 7))
	button.add_theme_color_override("font_color", Color(1.0, 0.87, 0.63) if selected else Color(0.78, 0.85, 0.79))

func _style_menu_button(button: Button, accent: bool = false) -> void:
	var edge := Color(0.91, 0.72, 0.43) if accent else Color(0.45, 0.58, 0.45)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.10, 0.16, 0.13, 0.98), edge, 1, 10))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.19, 0.27, 0.19), Color(0.94, 0.79, 0.48), 2, 10))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.27, 0.32, 0.22), edge, 2, 10))
	button.add_theme_stylebox_override("disabled", _panel_style(Color(0.08, 0.11, 0.10), Color(0.25, 0.32, 0.28), 1, 10))
	button.add_theme_color_override("font_color", Color(0.94, 0.94, 0.85))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.63))
	button.add_theme_color_override("font_disabled_color", Color(0.56, 0.62, 0.55))

func _inventory_changed(inv: Dictionary) -> void:
	inventory_label.text = "WOOD  %d   STONE  %d\nBERRIES %d   MUSHROOMS %d\nVEGETABLES %d   MEALS %d\nSEEDS %d   BEDS %d" % [int(inv.get("wood", 0)), int(inv.get("stone", 0)), int(inv.get("berries", 0)), int(inv.get("mushroom", 0)), int(inv.get("vegetables", 0)), int(inv.get("cooked_food", 0)), int(inv.get("seeds", 0)), int(inv.get("farm_bed", 0))]
	objective_label.text = "HOMESTEAD   /   NEXT STEPS\n%s  Mine stone\n%s  Place a farm bed\n%s  Keep the stove burning" % ["✓" if int(inv.get("stone", 0)) > 0 else "○", "○", "○"]
	for i in SLOT_ITEMS.size():
		var item: String = SLOT_ITEMS[i]
		var count := int(inv.get(item, 0))
		var key_text := str(i + 1) if i < 9 else ("0" if i == 9 else "·")
		var detail := "WOOD" if item in ["fence", "base_fence"] else "×%d" % count
		if item in ["axe", "pickaxe", "hammer"]:
			detail = "%d/%d" % [SurvivalState.get_tool_durability(item), SurvivalState.get_tool_max_durability(item)] if count > 0 else "BROKEN"
		if i < _hotbar_buttons.size():
			_hotbar_buttons[i].text = "%s\n%s" % [key_text, SLOT_ICONS[i]]
			_hotbar_buttons[i].tooltip_text = "%s  /  %s" % [SLOT_NAMES[i], detail]
		if _inventory_buttons.has(item):
			var action := "EQUIP" if item in ["axe", "pickaxe", "hammer"] else ("EAT" if item in EDIBLE else ("BUILD" if item in ["fence", "base_fence"] else ("PLACE" if item in ["farm_bed", "gate", "wicket"] else "MATERIAL")))
			(_inventory_buttons[item] as Button).text = "%s  %s\n%s     [%s]" % [SLOT_ICONS[i], SLOT_NAMES[i], detail, action]
	_update_tool_visibility()
	_update_crafting_buttons()
	_update_build_buttons()

func _vitals_changed(h: float, food: float, temp: float, energy: float) -> void:
	health_bar.value = h
	hunger_bar.value = food
	warmth_bar.value = temp
	stamina_bar.value = energy
	# Show noncritical vitals only when they need attention or are actively changing.
	(hunger_bar.get_parent().get_node("HungerText") as Label).visible = food < 68.0
	hunger_bar.visible = food < 68.0
	(warmth_bar.get_parent().get_node("WarmthText") as Label).visible = temp < 63.0
	warmth_bar.visible = temp < 63.0
	(stamina_bar.get_parent().get_node("StaminaText") as Label).visible = energy < 96.0
	stamina_bar.visible = energy < 96.0

func _time_changed(d: int, h: int, m: int) -> void:
	clock_label.text = "DAY %d   %02d:%02d" % [d, h, m]

func _notify(text: String, color: Color) -> void:
	notification_label.text = text
	notification_label.modulate = color
	notification_label.visible = true
	if _notice_tween:
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(3.2)
	_notice_tween.tween_property(notification_label, "modulate:a", 0.0, 0.8)
	_notice_tween.tween_callback(func(): notification_label.visible = false; notification_label.modulate.a = 1.0)

func _build_build_menu() -> void:
	_build_overlay = ColorRect.new()
	_build_overlay.name = "BuildMenuOverlay"
	_build_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_overlay.color = Color(0.0, 0.0, 0.0, 0.48)
	_build_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_overlay.visible = false
	$HUD.add_child(_build_overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.position = Vector2(42.0, -260.0)
	panel.size = Vector2(480.0, 520.0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.095, 0.075, 0.98), Color(0.72, 0.77, 0.61, 0.70), 2, 16))
	_build_overlay.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 11)
	margin.add_child(box)
	var title := Label.new()
	title.text = "BUILDING HAMMER"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	box.add_child(title)
	var help := Label.new()
	help.text = "Choose a piece, aim at the ground, then place it.\nNearby structures snap into position."
	help.add_theme_color_override("font_color", Color(0.82, 0.86, 0.76))
	box.add_child(help)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for piece in BUILD_PIECES:
		var button := Button.new()
		button.custom_minimum_size = Vector2(205, 88)
		button.add_theme_font_size_override("font_size", 16)
		_style_menu_button(button)
		button.pressed.connect(_select_build_piece.bind(piece))
		grid.add_child(button)
		_build_buttons[piece] = button
	var controls := Label.new()
	controls.text = "LMB place  •  R rotate  •  MMB remove\nRMB menu  •  Q close building mode"
	controls.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42))
	box.add_child(controls)
	var close := Button.new()
	close.text = "CLOSE  [RMB]"
	close.custom_minimum_size.y = 42
	close.pressed.connect(_toggle_build_menu.bind(false))
	box.add_child(close)
	_update_build_buttons()

func _toggle_build_menu(open: bool) -> void:
	if open and (not has_equipped_tool("hammer") or not SurvivalState.has_item("hammer")):
		return
	_build_menu_open = open
	if open:
		velocity.y = minf(velocity.y, 0.0)
	_build_overlay.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	_update_build_buttons()
	_update_placement_preview_state()
	_update_tool_visibility()

func _close_build_menu() -> void:
	if is_instance_valid(_build_overlay):
		_build_overlay.visible = false
	_build_menu_open = false
	if not inventory_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _select_build_piece(piece: String) -> void:
	_selected_build_piece = piece
	_building_mode = true
	_remove_mode = false
	_close_build_menu()
	_update_placement_preview_state()
	_notify("Selected %s. LMB place • R rotate." % str(BUILD_NAMES[piece]).to_lower(), Color(0.64, 1.0, 0.48))

func _update_build_buttons() -> void:
	for piece in _build_buttons:
		var button := _build_buttons[piece] as Button
		var affordable := _can_pay_build_cost(piece)
		button.text = "%s\n%s\n%s" % [BUILD_NAMES[piece], _build_cost_text(piece), "READY" if affordable else "MISSING MATERIALS"]
		button.disabled = not affordable

func _build_cost_text(piece: String) -> String:
	var parts: Array[String] = []
	for item in BUILD_COSTS[piece]:
		parts.append("%d %s" % [int(BUILD_COSTS[piece][item]), item])
	return " + ".join(parts)

func _can_pay_build_cost(piece: String) -> bool:
	for item in BUILD_COSTS[piece]:
		if not SurvivalState.has_item(item, int(BUILD_COSTS[piece][item])):
			return false
	return true

func _pay_build_cost(piece: String) -> bool:
	if not _can_pay_build_cost(piece):
		_notify("Missing materials: %s." % _build_cost_text(piece), Color(1.0, 0.45, 0.25))
		return false
	for item in BUILD_COSTS[piece]:
		SurvivalState.remove_item(item, int(BUILD_COSTS[piece][item]))
	SurvivalState.damage_tool("hammer")
	return true

func _place_hammer_piece() -> void:
	if not _preview_valid:
		_notify("Cannot place this piece here.", Color(1.0, 0.35, 0.25))
		return
	if not _pay_build_cost(_selected_build_piece):
		return
	_animate_hammer_strike()
	if _selected_build_piece in ["farm_bed", "gate", "wicket"]:
		var building: Node3D = GateBuilder.create_for(_selected_build_piece) if _selected_build_piece in GATE_ITEMS else FarmBedBuilder.create_bed()
		get_parent().add_child(building)
		building.global_position = _preview_position
		building.global_rotation.y = _preview_rotation
	else:
		var direction := Vector3(sin(_preview_rotation), 0.0, cos(_preview_rotation))
		var start := _preview_position - direction
		var finish := _preview_position + direction
		var fence: Node3D = RusticFenceBuilder.create_between(start, finish, _fence_ground()) if _selected_build_piece == "base_fence" else FenceBuilder.create_between(start, finish, _fence_ground())
		get_parent().add_child(fence)
		fence.set_meta("fence_ends", [start, finish, _selected_build_piece == "base_fence"])
	_notify("Built %s." % str(BUILD_NAMES[_selected_build_piece]).to_lower(), Color(0.62, 1.0, 0.45))
	_update_placement_preview_state()

func _update_hammer_fence_preview(piece: String) -> void:
	# The preview marks the exact first post that LMB will lock in.
	# Use the same camera ray and post snapping as _start_fence_drag(), not
	# a fixed distance in front of the player's feet.
	_preview_position = _fence_aim_point()
	_preview_valid = _can_pay_build_cost(piece)
	var next_preview: Node3D = RusticFenceBuilder.create_anchor_preview(_preview_position) if piece == "base_fence" else FenceBuilder.create_anchor_preview(_preview_position)
	if piece == "base_fence":
		RusticFenceBuilder.set_preview_valid(next_preview, _preview_valid)
	else:
		FenceBuilder.set_preview_valid(next_preview, _preview_valid)
	_replace_fence_preview(next_preview)
	interaction_prompt.text = "Hold LMB and drag procedural %s  •  %d wood/m  •  RMB menu" % [BUILD_NAMES[piece], _selected_fence_wood_rate()]
	interaction_prompt.visible = true

func _hammer_remove_target() -> void:
	var target := _get_interactable()
	if target and target.has_method("hammer_dismantle"):
		target.hammer_dismantle(self)
		SurvivalState.damage_tool("hammer")
		_notify("Structure dismantled; materials recovered.", Color(0.72, 1.0, 0.5))
	else:
		_notify("Aim at a player-built structure to remove it.", Color(0.9, 0.76, 0.42))

# Real distance between the gate posts of the piece being placed (gate 3 m, wicket narrower).
func _gate_span() -> float:
	if is_instance_valid(_farm_bed_preview) and _farm_bed_preview.has_meta("gate_span"):
		return float(_farm_bed_preview.get_meta("gate_span"))
	return 3.0

# Everything with snap posts: fences plus placed gates and wickets.
func _snap_structures() -> Array:
	var result: Array = get_tree().get_nodes_in_group("placed_fences")
	for gate in get_tree().get_nodes_in_group("gate_snap"):
		if not result.has(gate):
			result.append(gate)
	return result

func _is_snap_structure(node: Node) -> bool:
	return node.is_in_group("placed_fences") or node.is_in_group("gate_snap")

func _plant_sapling() -> void:
	if not SurvivalState.has_item("sapling"): return
	var p:=_fence_aim_point()
	if Vector2(p.x,p.z).length()>82.0:
		_notify("Plant inside the valley.",Color(1,.5,.3));return
	for r in get_tree().get_nodes_in_group("harvestable_resources"):
		if r is Node3D and (r as Node3D).global_position.distance_to(p)<2.5:
			_notify("The sapling needs more space.",Color(1,.62,.3));return
	var field:=get_parent().get_node_or_null("SurvivalResources")
	if field and field.has_method("plant_sapling") and SurvivalState.remove_item("sapling"):
		field.call("plant_sapling",p)
		_notify("Sapling planted. It will grow in three days.",Color(.55,1,.4))
