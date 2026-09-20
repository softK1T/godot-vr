extends Node

@export var day_cycle_seconds: float = 300.0
@export var enable_day_cycle: bool = false
@export var exterior_fog_density: float = 0.038
@export var interior_fog_density: float = 0.010
@export var exterior_flashlight_scatter: float = 2.2

@onready var sun: DirectionalLight3D = $"../Sun"
@onready var world_environment: WorldEnvironment = $"../WorldEnvironment"
@onready var player: CharacterBody3D = $"../Player"
@onready var flashlight: SpotLight3D = $"../Player/CamPivot/Camera3D/Flashlight"

var _indoor_blend := 0.0

func _ready() -> void:
	# Keep only shadowed direct sunlight. Indirect and volumetric directional
	# lighting can leak through the thin imported cabin ceiling.
	sun.light_indirect_energy = 0.0
	sun.light_volumetric_fog_energy = 0.0

func _process(delta: float) -> void:
	if enable_day_cycle:
		sun.rotation.x += TAU * delta / day_cycle_seconds

	var indoors := _is_player_inside_cabin()
	var target := 1.0 if indoors else 0.0
	_indoor_blend = move_toward(_indoor_blend, target, delta * 3.0)

	# Keep the flashlight itself bright indoors, but remove only its visible fog cone.
	flashlight.light_volumetric_fog_energy = lerpf(exterior_flashlight_scatter, 0.0, _indoor_blend)
	if world_environment.environment:
		world_environment.environment.volumetric_fog_density = lerpf(
			exterior_fog_density,
			interior_fog_density,
			_indoor_blend
		)

func _is_player_inside_cabin() -> bool:
	var p := player.global_position
	return p.x > -2.75 and p.x < 2.75 \
		and p.z > -7.15 and p.z < -0.65 \
		and p.y > 0.45 and p.y < 5.0
