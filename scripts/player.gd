extends CharacterBody3D

@export var speed := 4.0
@export var sprint := 7.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0025
@export var max_step_height := 0.6

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

const SLOT_ITEMS := ["axe", "pickaxe", "hammer", "berries", "mushroom", "vegetables", "cooked_food", "seeds", "wood", "stone", "sticks"]
const SLOT_NAMES := ["AXE", "PICKAXE", "HAMMER", "BERRIES", "MUSHROOM", "VEGETABLES", "WARM MEAL", "SEEDS", "WOOD", "STONE", "STICKS"]
const SLOT_ICONS := ["A", "P", "H", "●", "♠", "◆", "▣", "✦", "W", "S", "I"]
const BUILD_PIECES := ["farm_bed", "gate", "fence", "base_fence"]
const BUILD_NAMES := {"farm_bed":"FARM BED", "gate":"WOODEN GATE", "fence":"LOW FENCE", "base_fence":"RUSTIC FENCE"}
const BUILD_COSTS := {"farm_bed":{"wood":6,"stone":2}, "gate":{"wood":8,"stone":2}, "fence":{"wood":1}, "base_fence":{"wood":2}}
const EDIBLE := ["berries", "mushroom", "vegetables", "cooked_food"]

var selected_slot := 0
var inventory_open := false
var _notice_tween: Tween
var _tool_anchor: Node3D
var _axe_model: Node3D
var _pickaxe_model: Node3D
var _hammer_model: Node3D
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
	_notify("3 equips building hammer • RMB opens build menu • R rotates • MMB removes", Color(1.0, 0.86, 0.46))

func _input(event: InputEvent) -> void:
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
		_swing_tool(item)
		var target := _get_interactable()
		if target:
			if item == "axe" and target.has_method("dismantle"):
				target.dismantle(self)
			elif target is HarvestableResource and ((item == "axe" and target.resource_kind in ["tree", "bush"]) or (item == "pickaxe" and target.resource_kind == "stone")):
				target.interact(self)
	elif item in ["farm_bed", "gate"]:
		_place_building(item)
	elif item in EDIBLE:
		SurvivalState.eat_item(item)
	else:
		_notify("This material is used for crafting.", Color(0.86, 0.86, 0.7))

func _swing_tool(tool: String) -> void:
	var model: Node3D = _axe_model if tool == "axe" else _pickaxe_model
	if not model or _use_cooldown:
		return
	_use_cooldown = true
	var rest := Vector3(-0.12, 0.08, 0.08)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(model, "rotation", Vector3(-0.9, -0.32, -0.72), 0.1)
	tween.tween_property(model, "rotation", rest, 0.19).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func(): _use_cooldown = false)

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
	var building: Node3D = GateBuilder.create_gate() if item == "gate" else FarmBedBuilder.create_bed()
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
	var show_building := item in ["farm_bed", "gate"] and not inventory_open and not _build_menu_open and (has_equipped_tool("hammer") or SurvivalState.has_item(item))
	if show_building and not is_instance_valid(_farm_bed_preview):
		_farm_bed_preview = GateBuilder.create_preview() if item == "gate" else FarmBedBuilder.create_preview()
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
	_preview_position = global_position + flat_forward.normalized() * 3.2
	_preview_position.x=snappedf(_preview_position.x,.5);_preview_position.z=snappedf(_preview_position.z,.5);_preview_position.y=.02
	_preview_rotation=snappedf(rotation.y + _build_rotation_offset, PI/8.0);_farm_bed_preview.global_position=_preview_position;_farm_bed_preview.global_rotation.y=_preview_rotation
	_preview_valid=_is_building_position_clear(_preview_position,item)
	if item == "gate":GateBuilder.set_preview_valid(_farm_bed_preview,_preview_valid)
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
	_fence_end.x=snappedf(_fence_end.x,.25);_fence_end.z=snappedf(_fence_end.z,.25);_fence_end.y=.02
	var length:=Vector2(_fence_end.x-_fence_start.x,_fence_end.z-_fence_start.z).length()
	_preview_valid=length>=FenceBuilder.MIN_LENGTH
	var use_base: bool = _current_build_piece() == "base_fence"
	var next_preview: Node3D
	if _preview_valid:
		next_preview = RusticFenceBuilder.create_preview_between(_fence_start,_fence_end,true) if use_base else FenceBuilder.create_preview_between(_fence_start,_fence_end,true)
	else:
		next_preview = RusticFenceBuilder.create_anchor_preview(_fence_start) if use_base else FenceBuilder.create_anchor_preview(_fence_start)
	_replace_fence_preview(next_preview)
	var cost:=ceili(length)*wood_rate
	interaction_prompt.text="Release LMB: %.1f m fence  •  %d wood"%[length,cost] if _preview_valid else "Drag at least 1 meter"
	interaction_prompt.visible=true

func _finish_fence_drag() -> void:
	if not _fence_dragging:return
	_update_fence_drag()
	var length:=Vector2(_fence_end.x-_fence_start.x,_fence_end.z-_fence_start.z).length();var cost:=ceili(length)*_selected_fence_wood_rate()
	if _preview_valid and SurvivalState.remove_item("wood",cost):
		var fence:Node3D = RusticFenceBuilder.create_between(_fence_start,_fence_end) if _current_build_piece() == "base_fence" else FenceBuilder.create_between(_fence_start,_fence_end)
		get_parent().add_child(fence)
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
	result.y = .02;result.x = snappedf(result.x,.25);result.z = snappedf(result.z,.25)
	return result

func _replace_fence_preview(next_preview: Node3D) -> void:
	if is_instance_valid(_fence_preview):
		var old_preview := _fence_preview
		_fence_preview = null
		if old_preview.get_parent():old_preview.get_parent().remove_child(old_preview)
		old_preview.queue_free()
	_fence_preview = next_preview
	get_parent().add_child(_fence_preview)

func _is_building_position_clear(position: Vector3, item: String) -> bool:
	var parameters:=PhysicsShapeQueryParameters3D.new();var box:=BoxShape3D.new();box.size=Vector3(3.2,2.0,.55) if item == "gate" else Vector3(2.5,1.0,1.8)
	parameters.shape=box;parameters.transform=Transform3D(Basis(Vector3.UP,_preview_rotation),position+Vector3.UP*.48);parameters.collision_mask=1;parameters.exclude=[get_rid()]
	var hits:=get_world_3d().direct_space_state.intersect_shape(parameters,8)
	# The terrain itself is expected; only elevated/placed objects block beds.
	for hit in hits:
		var collider:Node=hit.get("collider")
		if collider and collider.name!="Ground":return false
	return true

func _try_interact() -> void:
	var target := _get_interactable()
	if target and target.has_method("interact"):
		target.interact(self)

func _get_interactable() -> Node:
	if not interaction_ray.is_colliding():
		return null
	var target := interaction_ray.get_collider() as Node
	while target:
		if target.has_method("interact") or target.has_method("dismantle"):
			return target
		target = target.get_parent()
	return null

func _physics_process(delta: float) -> void:
	if inventory_open or _build_menu_open:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
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
	if was_on_floor and is_on_wall() and horizontal.length_squared() > 0.000001:
		_try_step_up(start_transform, horizontal)

func _try_step_up(start: Transform3D, horizontal: Vector3) -> void:
	var slide := global_transform
	var slide_velocity := velocity
	global_transform = start
	var up := Vector3.UP * max_step_height
	if test_move(global_transform, up):
		global_transform = slide; velocity = slide_velocity; return
	global_position += up
	if move_and_collide(horizontal) != null:
		global_transform = slide; velocity = slide_velocity; return
	var down := move_and_collide(Vector3.DOWN * (max_step_height + 0.08))
	if down == null or down.get_normal().dot(Vector3.UP) < cos(floor_max_angle):
		global_transform = slide; velocity = slide_velocity; return
	velocity.y = 0.0

func _build_axe_model() -> void:
	_tool_anchor = Node3D.new()
	_tool_anchor.name = "HeldTool"
	_tool_anchor.position = Vector3(0.55, -0.48, -1.05)
	camera.add_child(_tool_anchor)
	_axe_model = Node3D.new()
	_axe_model.rotation = Vector3(-0.12, 0.08, 0.08)
	_tool_anchor.add_child(_axe_model)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.13, 0.045)
	wood.roughness = 0.9
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.37, 0.38)
	steel.metallic = 0.65
	steel.roughness = 0.34
	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.035
	handle_mesh.bottom_radius = 0.047
	handle_mesh.height = 0.82
	handle_mesh.radial_segments = 7
	handle_mesh.material = wood
	handle.mesh = handle_mesh
	handle.rotation.z = -0.28
	_axe_model.add_child(handle)
	var head := MeshInstance3D.new()
	var head_mesh := PrismMesh.new()
	head_mesh.size = Vector3(0.16, 0.3, 0.42)
	head_mesh.left_to_right = 0.36
	head_mesh.material = steel
	head.mesh = head_mesh
	head.position = Vector3(-0.105, 0.38, 0.0)
	head.rotation = Vector3(0.0, 1.5708, -0.28)
	_axe_model.add_child(head)
	_pickaxe_model = Node3D.new()
	_pickaxe_model.rotation = Vector3(-0.12, 0.08, 0.08)
	_tool_anchor.add_child(_pickaxe_model)
	var pick_handle := MeshInstance3D.new()
	var pick_handle_mesh := CylinderMesh.new()
	pick_handle_mesh.top_radius = 0.032
	pick_handle_mesh.bottom_radius = 0.045
	pick_handle_mesh.height = 0.86
	pick_handle_mesh.radial_segments = 7
	pick_handle_mesh.material = wood
	pick_handle.mesh = pick_handle_mesh
	pick_handle.rotation.z = -0.26
	_pickaxe_model.add_child(pick_handle)
	var pick_head := MeshInstance3D.new()
	var pick_head_mesh := PrismMesh.new()
	pick_head_mesh.size = Vector3(0.13, 0.54, 0.13)
	pick_head_mesh.left_to_right = 0.72
	pick_head_mesh.material = steel
	pick_head.mesh = pick_head_mesh
	pick_head.position = Vector3(-0.11, 0.39, 0.0)
	pick_head.rotation = Vector3(0.0, 0.0, -1.83)
	_pickaxe_model.add_child(pick_head)
	_hammer_model = Node3D.new()
	_hammer_model.rotation = Vector3(-0.12, 0.08, 0.08)
	_tool_anchor.add_child(_hammer_model)
	var hammer_handle := MeshInstance3D.new()
	var hammer_handle_mesh := CylinderMesh.new()
	hammer_handle_mesh.top_radius = 0.038; hammer_handle_mesh.bottom_radius = 0.05; hammer_handle_mesh.height = 0.76; hammer_handle_mesh.radial_segments = 7; hammer_handle_mesh.material = wood
	hammer_handle.mesh = hammer_handle_mesh; hammer_handle.rotation.z = -0.25; _hammer_model.add_child(hammer_handle)
	var hammer_head := MeshInstance3D.new()
	var hammer_head_mesh := BoxMesh.new()
	hammer_head_mesh.size = Vector3(0.42, 0.16, 0.18); hammer_head_mesh.material = steel
	hammer_head.mesh = hammer_head_mesh; hammer_head.position = Vector3(-0.1, 0.34, 0.0); hammer_head.rotation.z = -0.25; _hammer_model.add_child(hammer_head)
	_update_tool_visibility()

func _update_tool_visibility() -> void:
	if _axe_model:
		_axe_model.visible = has_equipped_tool("axe") and SurvivalState.has_item("axe") and not inventory_open and not _build_menu_open
	if _pickaxe_model:
		_pickaxe_model.visible = has_equipped_tool("pickaxe") and SurvivalState.has_item("pickaxe") and not inventory_open and not _build_menu_open
	if _hammer_model:
		_hammer_model.visible = has_equipped_tool("hammer") and SurvivalState.has_item("hammer") and not inventory_open and not _build_menu_open

func _build_hotbar() -> void:
	var panel := PanelContainer.new()
	panel.name = "HotbarPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(-510.0, -104.0)
	panel.size = Vector2(1020.0, 78.0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.032, 0.025, 0.97), Color(0.72, 0.58, 0.24), 3, 12))
	$HUD.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 7)
	margin.add_child(_hotbar)
	for i in SLOT_ITEMS.size():
		var button := Button.new()
		button.custom_minimum_size = Vector2(82, 58)
		button.focus_mode = Control.FOCUS_NONE
		button.text = "%d  %s\n%s" % [i + 1, SLOT_ICONS[i], SLOT_NAMES[i]]
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_select_slot.bind(i))
		_hotbar.add_child(button)
		_hotbar_buttons.append(button)

func _build_inventory_window() -> void:
	_inventory_overlay = ColorRect.new()
	_inventory_overlay.name = "InventoryOverlay"
	_inventory_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inventory_overlay.color = Color(0.0, 0.0, 0.0, 0.68)
	_inventory_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory_overlay.visible = false
	$HUD.add_child(_inventory_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inventory_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1050, 650)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.045, 0.035, 0.99), Color(0.92, 0.72, 0.28), 4, 16))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "INVENTORY & CRAFTING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	vbox.add_child(title)
	var hint := Label.new()
	hint.text = "Terraria-style crafting: available recipes stay visible. Click items to equip/use."
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
		button.custom_minimum_size = Vector2(184, 72)
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_inventory_item_pressed.bind(i))
		grid.add_child(button)
		_inventory_buttons[item] = button
	var craft_title := Label.new()
	craft_title.text = "CRAFTING  —  click a recipe to craft instantly"
	craft_title.add_theme_font_size_override("font_size", 20)
	craft_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	vbox.add_child(craft_title)
	var craft_list := VBoxContainer.new()
	craft_list.add_theme_constant_override("separation", 8)
	vbox.add_child(craft_list)
	for recipe in ["hammer", "axe", "pickaxe"]:
		var craft_button := Button.new()
		craft_button.custom_minimum_size = Vector2(0, 52)
		craft_button.add_theme_font_size_override("font_size", 16)
		craft_button.pressed.connect(_craft_item.bind(recipe))
		craft_list.add_child(craft_button)
		_craft_buttons[recipe] = craft_button
	var close := Button.new()
	close.text = "CLOSE  [TAB]"
	close.custom_minimum_size.y = 44
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
	var dark := Color(0.025, 0.032, 0.025, 0.97)
	var border := Color(0.75, 0.6, 0.25, 1.0)
	for panel_path in ["HUD/SurvivalPanel", "HUD/ObjectivePanel", "HUD/TopBar"]:
		var panel := get_node(panel_path) as PanelContainer
		panel.modulate = Color.WHITE
		panel.add_theme_stylebox_override("panel", _panel_style(dark, border, 3, 10))
	for label_path in ["HUD/SurvivalPanel/Margin/VBox/Title", "HUD/SurvivalPanel/Margin/VBox/HealthText", "HUD/SurvivalPanel/Margin/VBox/HungerText", "HUD/SurvivalPanel/Margin/VBox/WarmthText", "HUD/SurvivalPanel/Margin/VBox/StaminaText", "HUD/SurvivalPanel/Margin/VBox/Inventory", "HUD/ObjectivePanel/Margin/VBox/Objective", "HUD/ObjectivePanel/Margin/VBox/Controls", "HUD/TopBar/Clock"]:
		var label := get_node(label_path) as Label
		label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.88))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
	interaction_prompt.add_theme_stylebox_override("normal", _panel_style(Color(0.015, 0.018, 0.012, 0.88), Color(1.0, 0.75, 0.2), 2, 8))
	interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.48))
	for data in [[health_bar, Color(0.92, 0.2, 0.16)], [hunger_bar, Color(1.0, 0.58, 0.08)], [warmth_bar, Color(1.0, 0.3, 0.05)], [stamina_bar, Color(0.25, 0.82, 0.35)]]:
		var bar := data[0] as ProgressBar
		bar.modulate = Color.WHITE
		bar.add_theme_stylebox_override("background", _panel_style(Color(0.08, 0.08, 0.065), Color(0.32, 0.3, 0.22), 1, 4))
		bar.add_theme_stylebox_override("fill", _panel_style(data[1], data[1].lightened(0.25), 1, 4))

func _panel_style(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.65)
	style.shadow_size = 7
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _style_slot(button: Button, selected: bool) -> void:
	var fill := Color(0.18, 0.14, 0.065, 1.0) if selected else Color(0.055, 0.065, 0.052, 1.0)
	var border := Color(1.0, 0.72, 0.18, 1.0) if selected else Color(0.28, 0.3, 0.22, 1.0)
	button.add_theme_stylebox_override("normal", _panel_style(fill, border, 3 if selected else 1, 7))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.22, 0.18, 0.08), Color(1.0, 0.8, 0.3), 2, 7))
	button.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55) if selected else Color(0.9, 0.92, 0.84))

func _inventory_changed(inv: Dictionary) -> void:
	inventory_label.text = "WOOD  %d   STONE  %d\nBERRIES %d   MUSHROOMS %d\nVEGETABLES %d   MEALS %d\nSEEDS %d   BEDS %d" % [int(inv.get("wood", 0)), int(inv.get("stone", 0)), int(inv.get("berries", 0)), int(inv.get("mushroom", 0)), int(inv.get("vegetables", 0)), int(inv.get("cooked_food", 0)), int(inv.get("seeds", 0)), int(inv.get("farm_bed", 0))]
	objective_label.text = "BUILD A HOMESTEAD\n• Mine stone with a pickaxe\n• Craft and place a farm bed\n• Keep the cabin stove burning"
	for i in SLOT_ITEMS.size():
		var item: String = SLOT_ITEMS[i]
		var count := int(inv.get(item, 0))
		var key_text := str(i + 1) if i < 9 else "0"
		var detail := "WOOD" if item in ["fence", "base_fence"] else "×%d" % count
		if item in ["axe", "pickaxe", "hammer"]:
			detail = "%d/%d" % [SurvivalState.get_tool_durability(item), SurvivalState.get_tool_max_durability(item)] if count > 0 else "BROKEN"
		if i < _hotbar_buttons.size():
			_hotbar_buttons[i].text = "%s  %s  %s\n%s" % [key_text, SLOT_ICONS[i], detail, SLOT_NAMES[i]]
		if _inventory_buttons.has(item):
			var action := "EQUIP" if item in ["axe", "pickaxe", "hammer"] else ("EAT" if item in EDIBLE else ("BUILD" if item in ["fence", "base_fence"] else ("PLACE" if item in ["farm_bed", "gate"] else "MATERIAL")))
			(_inventory_buttons[item] as Button).text = "%s  %s\n%s     [%s]" % [SLOT_ICONS[i], SLOT_NAMES[i], detail, action]
	_update_tool_visibility()
	_update_crafting_buttons()
	_update_build_buttons()

func _vitals_changed(h: float, food: float, temp: float, energy: float) -> void:
	health_bar.value = h
	hunger_bar.value = food
	warmth_bar.value = temp
	stamina_bar.value = energy

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
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.028, 0.035, 0.026, 0.99), Color(0.91, 0.69, 0.24), 4, 14))
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
	help.text = "Select a piece, then place its green ghost.\nStructures snap to the grid like Valheim pieces."
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
	if _selected_build_piece in ["farm_bed", "gate"]:
		var building: Node3D = GateBuilder.create_gate() if _selected_build_piece == "gate" else FarmBedBuilder.create_bed()
		get_parent().add_child(building)
		building.global_position = _preview_position
		building.global_rotation.y = _preview_rotation
	else:
		var direction := Vector3(sin(_preview_rotation), 0.0, cos(_preview_rotation))
		var start := _preview_position - direction
		var finish := _preview_position + direction
		var fence: Node3D = RusticFenceBuilder.create_between(start, finish) if _selected_build_piece == "base_fence" else FenceBuilder.create_between(start, finish)
		get_parent().add_child(fence)
	_notify("Built %s." % str(BUILD_NAMES[_selected_build_piece]).to_lower(), Color(0.62, 1.0, 0.45))
	_update_placement_preview_state()

func _update_hammer_fence_preview(piece: String) -> void:
	var flat_forward := -camera.global_transform.basis.z
	flat_forward.y = 0.0
	if flat_forward.length_squared() < 0.01:
		flat_forward = -global_transform.basis.z
	_preview_position = global_position + flat_forward.normalized() * 3.4
	_preview_position.x = snappedf(_preview_position.x, 0.5)
	_preview_position.z = snappedf(_preview_position.z, 0.5)
	_preview_position.y = 0.02
	_preview_rotation = snappedf(rotation.y + _build_rotation_offset, PI / 8.0)
	var direction := Vector3(sin(_preview_rotation), 0.0, cos(_preview_rotation))
	var start := _preview_position - direction
	var finish := _preview_position + direction
	_preview_valid = _can_pay_build_cost(piece)
	var next_preview: Node3D = RusticFenceBuilder.create_preview_between(start, finish, _preview_valid) if piece == "base_fence" else FenceBuilder.create_preview_between(start, finish, _preview_valid)
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
