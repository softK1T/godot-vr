extends Node

# Cabin flashlight, debug time override and smooth, independent weather cycle.
@onready var player: CharacterBody3D = $"../Player"
@onready var sun: DirectionalLight3D = $"../Sun"
@onready var world: WorldEnvironment = $"../WorldEnvironment"
@onready var flashlight: SpotLight3D = $"../Player/CamPivot/Camera3D/Flashlight"

const WEATHER_NAMES := ["Clear", "Cloudy", "Rain"]
const CLEAR_TOP := Color(0.24, 0.45, 0.71)
const CLEAR_HORIZON := Color(0.72, 0.72, 0.65)
const CLEAR_GROUND := Color(0.40, 0.40, 0.35)
const NIGHT_TOP := Color(0.014, 0.025, 0.07)
const NIGHT_HORIZON := Color(0.055, 0.075, 0.12)
const NIGHT_GROUND := Color(0.045, 0.055, 0.065)

var debug_night := false
var flashlight_on := false
var weather := 0
var _cloud_cover := 0.0
var _rain_strength := 0.0
var _ground_wetness := 0.0
var _weather_timer := 95.0
var _rng := RandomNumberGenerator.new()
var _rain: GPUParticles3D

func _ready() -> void:
	flashlight.visible = flashlight_on
	_rng.randomize()
	_create_rain()

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_weather_timer -= delta
	if _weather_timer <= 0.0:
		var options := [1] if weather == 0 else ([0, 2] if weather == 1 else [0, 1])
		set_weather(options[_rng.randi_range(0, options.size() - 1)])
		_weather_timer = _rng.randf_range(90.0, 160.0)
	var desired_clouds := 0.0 if weather == 0 else (0.55 if weather == 1 else 1.0)
	_cloud_cover = move_toward(_cloud_cover, desired_clouds, delta / 9.0)
	_rain_strength = move_toward(_rain_strength, 1.0 if weather == 2 else 0.0, delta / (20.0 if weather == 2 else 14.0))
	_update_sky()
	# Puddles fill in rain and slowly evaporate after the sky clears.
	_ground_wetness = move_toward(_ground_wetness, 1.0 if weather == 2 else 0.0, delta / (22.0 if weather == 2 else 110.0))
	var terrain := get_node_or_null("../Ground") as LowPolyGround
	if terrain != null:
		terrain.set_wetness(_ground_wetness)
	if _rain != null:
		_rain.global_position = player.global_position + Vector3(0.0, 8.0, 0.0)
		_rain.amount_ratio = _rain_strength
		_rain.emitting = _rain_strength > 0.01 and not _inside_cabin()

func _inside_cabin() -> bool:
	var house := get_node_or_null("../House") as Node3D
	if house == null:
		return false
	var local := house.to_local(player.global_position)
	return absf(local.x) < 4.0 and absf(local.z) < 3.1 and local.y < 4.5

func _update_sky() -> void:
	var env := world.environment
	var sky_material := env.sky.sky_material as ProceduralSkyMaterial
	var cover := _cloud_cover
	var top := CLEAR_TOP.lerp(Color(0.16, 0.20, 0.25), cover)
	var horizon := CLEAR_HORIZON.lerp(Color(0.35, 0.39, 0.44), cover)
	var ground := CLEAR_GROUND.lerp(Color(0.24, 0.27, 0.30), cover)
	if debug_night:
		top = top.lerp(NIGHT_TOP, 0.92)
		horizon = horizon.lerp(NIGHT_HORIZON, 0.88)
		ground = ground.lerp(NIGHT_GROUND, 0.9)
	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = ground
	sun.light_energy = (0.9 - cover * 0.53) * (0.0 if debug_night else 1.0)
	env.ambient_light_energy = (0.35 - cover * 0.10) * (0.25 if debug_night else 1.0)

func set_weather(next_weather: int) -> void:
	weather = posmod(next_weather, WEATHER_NAMES.size())
	_weather_timer = _rng.randf_range(90.0, 160.0)
	SurvivalState.notification.emit("WEATHER  /  %s" % WEATHER_NAMES[weather].to_upper(), Color(0.72, 0.82, 0.95))

func cycle_weather() -> void:
	set_weather(weather + 1)

func toggle_flashlight() -> bool:
	flashlight_on = not flashlight_on
	flashlight.visible = flashlight_on
	return flashlight_on

func set_debug_night(enabled: bool) -> void:
	debug_night = enabled
	_update_sky()

func _create_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "LocalRain"
	_rain.amount = 780
	_rain.lifetime = 0.9
	_rain.explosiveness = 0.0
	_rain.visibility_aabb = AABB(Vector3(-14, -20, -14), Vector3(28, 24, 28))
	var particles := ParticleProcessMaterial.new()
	particles.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(11.0, 0.25, 11.0)
	particles.direction = Vector3(0.08, -1.0, 0.02)
	particles.spread = 3.0
	particles.initial_velocity_min = 11.0
	particles.initial_velocity_max = 16.0
	particles.gravity = Vector3(0.0, -8.0, 0.0)
	_rain.process_material = particles
	var streak := QuadMesh.new()
	streak.size = Vector2(0.017, 0.36)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.67, 0.79, 0.91, 0.43)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = false
	streak.material = material
	_rain.draw_pass_1 = streak
	_rain.emitting = false
	get_parent().add_child.call_deferred(_rain)
