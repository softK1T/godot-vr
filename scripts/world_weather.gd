extends Node
class_name WorldWeather
## Single owner of wind, rain soaking, rain ripples on water and seasons.
## Global shader parameters (project.godot [shader_globals]):
## world_wind, world_rain, season_foliage, season_ground, season_desat.
## The season follows the saved day counter, so it is saved with the game.
const SEASON_DAYS := 3
const SEASONS := ["Summer", "Autumn", "Winter"]
const FOLIAGE_TINT := [Color(1.0, 1.0, 1.0), Color(1.10, 0.84, 0.56), Color(0.98, 1.0, 1.04)]
const GROUND_TINT := [Color(1.0, 1.0, 1.0), Color(1.03, 0.95, 0.84), Color(1.04, 1.05, 1.08)]
const DESAT := [0.0, 0.1, 0.5]
const SUN_TINT := [Color(1.0, 0.97, 0.92), Color(1.0, 0.90, 0.78), Color(0.90, 0.94, 1.0)]
const COLD := [0.0, 6.0, 14.0]

var wind := 1.0
var season := -1
var _gust := 0.0
var _gust_target := 0.0
var _gust_timer := 0.0
var _soaked := false
var _age := 0.0
var _rng := RandomNumberGenerator.new()
@onready var _atmo := get_node_or_null("../Atmosphere")
@onready var _sun := get_node_or_null("../Sun") as DirectionalLight3D

func _ready() -> void:
	add_to_group("world_weather")
	_rng.randomize()

func get_wind() -> float:
	return wind

func season_name() -> String:
	return str(SEASONS[maxi(season, 0)])

func _season_pos() -> float:
	return (float(SurvivalState.day - 1) + SurvivalState.time_of_day / 24.0) / float(SEASON_DAYS)

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_age += delta
	var rain := 0.0
	var clouds := 0.0
	var inside := false
	if _atmo:
		var r = _atmo.get("_rain_strength")
		if r != null:
			rain = float(r)
		var c = _atmo.get("_cloud_cover")
		if c != null:
			clouds = float(c)
		if _atmo.has_method("_inside_cabin"):
			inside = bool(_atmo.call("_inside_cabin"))
	_update_wind(delta, rain, clouds)
	_update_wetness(delta, rain, inside)
	_update_season(delta)
	RenderingServer.global_shader_parameter_set("world_rain", rain)

# One wind value for grass and foliage; strong irregular gusts during storms.
func _update_wind(delta: float, rain: float, clouds: float) -> void:
	_gust_timer -= delta
	if _gust_timer <= 0.0:
		var storm := rain > 0.6
		_gust_target = _rng.randf_range(0.0, 1.4 if storm else 0.45)
		_gust_timer = _rng.randf_range(0.8, 2.5) if storm else _rng.randf_range(2.0, 5.0)
	_gust = lerpf(_gust, _gust_target, clampf(delta * 1.2, 0.0, 1.0))
	wind = 0.7 + clouds * 0.35 + rain * 0.45 + _gust
	RenderingServer.global_shader_parameter_set("world_wind", wind)

# Soaking outside in rain; the roof protects, drying inside is faster near a burning stove.
func _update_wetness(delta: float, rain: float, inside: bool) -> void:
	var w := SurvivalState.rain_wetness
	if inside:
		w = move_toward(w, 0.0, delta / (18.0 if SurvivalState._heat > 0.35 else 70.0))
	elif rain > 0.05:
		w = move_toward(w, 1.0, delta * rain / 45.0)
	else:
		w = move_toward(w, 0.0, delta / 150.0)
	SurvivalState.rain_wetness = w
	if w > 0.6 and not _soaked:
		_soaked = true
		SurvivalState.notification.emit("Your clothes are soaked. Dry off inside by the stove.", Color(0.45, 0.75, 1.0))
	elif w < 0.1 and _soaked:
		_soaked = false
		SurvivalState.notification.emit("Your clothes are dry again.", Color(0.75, 0.95, 0.75))

func _update_season(delta: float) -> void:
	var pos := _season_pos()
	var idx := posmod(floori(pos), SEASONS.size())
	var nxt := (idx + 1) % SEASONS.size()
	var blend := smoothstep(0.85, 1.0, pos - floorf(pos))
	if idx != season:
		if season >= 0 and _age > 3.0:
			SurvivalState.notification.emit("%s has come." % str(SEASONS[idx]), Color(0.95, 0.88, 0.7))
		season = idx
	var fa: Color = FOLIAGE_TINT[idx]
	var fb: Color = FOLIAGE_TINT[nxt]
	var ga: Color = GROUND_TINT[idx]
	var gb: Color = GROUND_TINT[nxt]
	var sa: Color = SUN_TINT[idx]
	var sb: Color = SUN_TINT[nxt]
	RenderingServer.global_shader_parameter_set("season_foliage", fa.lerp(fb, blend))
	RenderingServer.global_shader_parameter_set("season_ground", ga.lerp(gb, blend))
	RenderingServer.global_shader_parameter_set("season_desat", lerpf(float(DESAT[idx]), float(DESAT[nxt]), blend))
	SurvivalState.season_cold = lerpf(float(COLD[idx]), float(COLD[nxt]), blend)
	if _sun:
		_sun.light_color = _sun.light_color.lerp(sa.lerp(sb, blend), clampf(delta * 0.5, 0.0, 1.0))
