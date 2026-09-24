extends Node
## Sole owner of Environment fog. The project uses gl_compatibility, so only
## depth/height fog is used here; volumetric fog stays disabled.
## Light haze by day, denser at dawn, stronger in rain, almost none indoors.
const BASE_DENSITY := 0.0026
const INDOOR_DENSITY := 0.0004

var _density := BASE_DENSITY
var _height_density := 0.0
var _indoor := 0.0

@onready var _we := get_node_or_null("../WorldEnvironment") as WorldEnvironment
@onready var _atmo := get_node_or_null("../Atmosphere")

func _ready() -> void:
	if _we == null or _we.environment == null:
		return
	var env := _we.environment
	env.volumetric_fog_enabled = false
	env.fog_enabled = true
	env.fog_density = _density
	env.fog_sky_affect = 0.45

func _process(delta: float) -> void:
	if _we == null or _we.environment == null:
		return
	var env := _we.environment
	var h := SurvivalState.time_of_day
	var day := SurvivalState.get_daylight()
	var morning := exp(-pow((h - 6.6) / 1.5, 2.0))
	var evening := exp(-pow((h - 19.8) / 1.4, 2.0)) * 0.5
	var rain := 0.0
	var inside := false
	if _atmo:
		var r = _atmo.get("_rain_strength")
		if r != null:
			rain = float(r)
		if _atmo.has_method("_inside_cabin"):
			inside = bool(_atmo.call("_inside_cabin"))
	_indoor = move_toward(_indoor, 1.0 if inside else 0.0, delta * 1.5)
	var target := BASE_DENSITY + morning * 0.009 + evening * 0.0035 + rain * 0.008
	target = lerpf(target, INDOOR_DENSITY, _indoor)
	var k := clampf(delta * 0.6, 0.0, 1.0)
	_density = lerpf(_density, target, k)
	_height_density = lerpf(_height_density, (morning * 0.35 + rain * 0.12) * (1.0 - _indoor), k)
	var col := Color(0.06, 0.08, 0.12).lerp(Color(0.64, 0.70, 0.74), day)
	col = col.lerp(Color(0.88, 0.74, 0.62), clampf(morning + evening, 0.0, 1.0) * 0.5 * day)
	col = col.lerp(Color(0.52, 0.56, 0.60), rain * 0.5 * day)
	env.fog_enabled = true
	env.fog_density = _density
	env.fog_light_color = col
	env.fog_light_energy = lerpf(0.35, 0.95, day)
	env.fog_sun_scatter = (0.10 + morning * 0.18) * (1.0 - rain * 0.6)
	env.fog_height = -0.3 + morning * 1.2
	env.fog_height_density = _height_density
