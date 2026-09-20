extends CharacterBody3D

@export var speed: float = 4.0
@export var sprint: float = 7.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var max_step_height: float = 0.6

@onready var pivot: Node3D = $CamPivot
@onready var interaction_ray: RayCast3D = $CamPivot/Camera3D/InteractionRay
@onready var interaction_prompt: Label = $HUD/InteractionPrompt

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		pivot.rotation.x = clampf(pivot.rotation.x, -1.4, 1.4)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("interact"):
		_try_interact()

func _process(_delta: float) -> void:
	var target := _get_interactable()
	interaction_prompt.visible = target != null
	if target and target.has_method("get_interaction_text"):
		interaction_prompt.text = target.get_interaction_text()

func _try_interact() -> void:
	var target := _get_interactable()
	if target and target.has_method("interact"):
		target.interact(self)

func _get_interactable() -> Node:
	if not interaction_ray.is_colliding():
		return null
	var target := interaction_ray.get_collider() as Node
	while target != null:
		if target.has_method("interact"):
			return target
		target = target.get_parent()
	return null

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var current_speed: float = sprint if Input.is_key_pressed(KEY_SHIFT) else speed
	if dir:
		velocity.x = dir.x * current_speed
		velocity.z = dir.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)

	var was_on_floor := is_on_floor()
	var start_transform := global_transform
	var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	move_and_slide()
	if was_on_floor and is_on_wall() and horizontal_motion.length_squared() > 0.000001:
		_try_step_up(start_transform, horizontal_motion)

func _try_step_up(start_transform: Transform3D, horizontal_motion: Vector3) -> void:
	var slide_transform := global_transform
	var slide_velocity := velocity
	global_transform = start_transform

	var up_motion := Vector3.UP * max_step_height
	if test_move(global_transform, up_motion):
		global_transform = slide_transform
		velocity = slide_velocity
		return
	global_position += up_motion

	var forward_collision := move_and_collide(horizontal_motion)
	if forward_collision != null:
		global_transform = slide_transform
		velocity = slide_velocity
		return

	var down_collision := move_and_collide(Vector3.DOWN * (max_step_height + 0.08))
	if down_collision == null or down_collision.get_normal().dot(Vector3.UP) < cos(floor_max_angle):
		global_transform = slide_transform
		velocity = slide_velocity
		return

	velocity.y = 0.0
