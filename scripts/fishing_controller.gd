extends Node3D
## Fishing: hold G (or B/Y on a VR controller) to preview a cast on water,
## release to cast, press again when a fish bites.

const FISH_KEY := KEY_G
const KEY_LABEL := "G"
const XR_BUTTON := "by_button"
enum State { IDLE, AIMING, WAITING, BITE }

var _ground: LowPolyGround
var _state := State.IDLE
var _timer := 0.0
var _was_held := false
var _xr_held := false
var _target := Vector3.INF
var _bobber: MeshInstance3D
var _marker: MeshInstance3D
var _line: MeshInstance3D
var _line_mesh := ImmediateMesh.new()
var _line_mat := StandardMaterial3D.new()
var _sfx: AudioStreamPlayer
var _water_sfx: AudioStreamPlayer3D
var _sounds := {}
var _hint_cd := {}
var _rng := RandomNumberGenerator.new()
var _xr_scan := 0.0
var _connected: Array = []
var _rod_hand: Node3D


func _ready() -> void:
	_rng.randomize()
	_build_visuals()
	_sounds = {
		"cast": synth(700.0, 180.0, 0.35, 0.85, 0.3),
		"splash": synth(320.0, 90.0, 0.45, 0.9, 0.4),
		"bite": synth(540.0, 260.0, 0.14, 0.1, 0.45),
		"catch": synth(420.0, 840.0, 0.32, 0.15, 0.3),
		"miss": synth(300.0, 160.0, 0.3, 0.2, 0.25),
	}
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = bus
	add_child(_sfx)
	_water_sfx = AudioStreamPlayer3D.new()
	_water_sfx.bus = bus
	_water_sfx.unit_size = 6.0
	_water_sfx.top_level = true
	add_child(_water_sfx)
	await get_tree().process_frame
	_ground = _find_ground(get_tree().current_scene if get_tree().current_scene else get_parent())


static func synth(freq_from: float, freq_to: float, length: float, noise: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var smooth := 0.0
	for i in count:
		var t := float(i) / float(count)
		phase += TAU * lerpf(freq_from, freq_to, t) / float(rate)
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), 0.35)
		var env := sin(PI * minf(t * 4.0, 1.0) * 0.5) * pow(1.0 - t, 1.6)
		var s := (sin(phase) * (1.0 - noise) + smooth * noise * 1.6) * env * volume
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


func _find_ground(node: Node) -> LowPolyGround:
	if node == null:
		return null
	if node is LowPolyGround:
		return node
	for child in node.get_children():
		var found := _find_ground(child)
		if found:
			return found
	return null


func _flat(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build_visuals() -> void:
	_bobber = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.12
	sphere.radial_segments = 6
	sphere.rings = 3
	_bobber.mesh = sphere
	_bobber.material_override = _flat(Color(0.72, 0.3, 0.2))
	_bobber.top_level = true
	_bobber.visible = false
	add_child(_bobber)
	_marker = MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 0.35
	ring.bottom_radius = 0.35
	ring.height = 0.02
	ring.radial_segments = 10
	ring.rings = 1
	_marker.mesh = ring
	_marker.material_override = _flat(Color(0.62, 0.7, 0.58), true)
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = Color(0.85, 0.82, 0.74)
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


func _scan_xr(delta: float) -> void:
	_xr_scan -= delta
	if _xr_scan > 0.0:
		return
	_xr_scan = 1.0
	for c in get_tree().root.find_children("*", "XRController3D", true, false):
		if c in _connected:
			continue
		_connected.append(c)
		c.button_pressed.connect(_on_xr_pressed.bind(c))
		c.button_released.connect(_on_xr_released)


func _on_xr_pressed(button_name: String, controller: Node3D) -> void:
	if button_name == XR_BUTTON:
		_xr_held = true
		_rod_hand = controller


func _on_xr_released(button_name: String) -> void:
	if button_name == XR_BUTTON:
		_xr_held = false


func _hint(key: String, text: String) -> void:
	if float(_hint_cd.get(key, 0.0)) > 0.0:
		return
	_hint_cd[key] = 6.0
	SurvivalState.notification.emit(text, Color(0.86, 0.88, 0.8))


func _process(delta: float) -> void:
	_scan_xr(delta)
	for k in _hint_cd.keys():
		_hint_cd[k] = maxf(0.0, float(_hint_cd[k]) - delta)
	if _ground == null or get_tree().paused:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var held := _xr_held or Input.is_physical_key_pressed(FISH_KEY)
	var pressed := held and not _was_held
	var released := _was_held and not held
	_was_held = held
	match _state:
		State.IDLE:
			if pressed:
				if not SurvivalState.has_item("fishing_rod"):
					_hint("rod", "You need a fishing rod. Craft one: Wood 2, Sticks 3.")
				else:
					_state = State.AIMING
					_hint("aim", "Aim at open water and release %s to cast." % KEY_LABEL)
		State.AIMING:
			_target = _find_target(cam)
			_marker.visible = _target != Vector3.INF
			if _marker.visible:
				_marker.global_position = _target + Vector3(0.0, 0.02, 0.0)
			if released:
				_marker.visible = false
				if _target == Vector3.INF:
					_hint("nowater", "Aim at open water to cast.")
					_state = State.IDLE
				else:
					_cast()
		State.WAITING:
			_timer -= delta
			_float_bobber(0.0)
			if pressed:
				_reel_in("You reel in the empty line.")
			elif _too_far(cam):
				_reel_in("The line went slack.")
			elif _timer <= 0.0:
				_state = State.BITE
				_timer = 1.3
				_play3d("bite")
				SurvivalState.notification.emit("A fish bites! Press %s now!" % KEY_LABEL, Color(0.95, 0.85, 0.55))
		State.BITE:
			_timer -= delta
			_float_bobber(1.0)
			if pressed:
				_catch()
			elif _timer <= 0.0 or _too_far(cam):
				_play("miss")
				_reel_in("The fish got away.")
	_draw_line(cam)


func _find_target(cam: Camera3D) -> Vector3:
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var t := 1.5
	while t < 14.0:
		var p := origin + dir * t
		var xz := Vector2(p.x, p.z)
		if _ground.is_water(xz):
			if p.y <= _ground.water_level_at(xz) + 0.1:
				return Vector3(p.x, _ground.water_level_at(xz), p.z)
		elif p.y < _ground.surface_height(xz):
			break
		t += 0.35
	var flat := Vector2(dir.x, dir.z)
	if flat.length() < 0.1:
		return Vector3.INF
	flat = flat.normalized()
	var d := 8.0
	while d >= 2.5:
		var q := Vector2(origin.x, origin.z) + flat * d
		if _ground.is_water(q) and _ground.is_water(q + flat * 0.8):
			return Vector3(q.x, _ground.water_level_at(q), q.y)
		d -= 0.5
	return Vector3.INF


func _cast() -> void:
	_state = State.WAITING
	_bobber.global_position = _target
	_bobber.visible = true
	_timer = _rng.randf_range(4.0, 10.0) * (0.75 if SurvivalState.rain_wetness > 0.3 else 1.0)
	_play("cast")
	_play3d("splash")
	_hint("wait", "Wait for a bite, then press %s. Press it early to reel in." % KEY_LABEL)


func _float_bobber(bite: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var y := _target.y + sin(t * 2.2) * 0.015 - bite * (0.05 + absf(sin(t * 14.0)) * 0.05)
	_bobber.global_position = Vector3(_target.x, y, _target.z)


func _catch() -> void:
	SurvivalState.add_item("raw_fish", 1, "raw fish")
	SurvivalState.damage_tool("fishing_rod")
	_play("catch")
	SurvivalState.notification.emit("Nice catch! Fry it on a lit stove.", Color(0.72, 1.0, 0.58))
	_reset()


func _reel_in(text: String) -> void:
	SurvivalState.notification.emit(text, Color(0.85, 0.85, 0.75))
	_reset()


func _reset() -> void:
	_state = State.IDLE
	_bobber.visible = false
	_marker.visible = false
	_target = Vector3.INF


func _too_far(cam: Camera3D) -> bool:
	return Vector2(cam.global_position.x, cam.global_position.z).distance_to(Vector2(_target.x, _target.z)) > 16.0


func _play(sound: String) -> void:
	_sfx.stream = _sounds[sound]
	_sfx.play()


func _play3d(sound: String) -> void:
	_water_sfx.global_position = _bobber.global_position
	_water_sfx.stream = _sounds[sound]
	_water_sfx.play()


func _draw_line(cam: Camera3D) -> void:
	_line_mesh.clear_surfaces()
	if not _bobber.visible:
		return
	var tip := cam.global_transform * Vector3(0.28, -0.22, -0.7)
	if is_instance_valid(_rod_hand) and _rod_hand.is_inside_tree():
		tip = _rod_hand.global_transform * Vector3(0.0, 0.0, -0.3)
	var end := _bobber.global_position
	var mid := tip.lerp(end, 0.55) + Vector3(0.0, -0.3, 0.0)
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	_line_mesh.add_vertex(tip)
	_line_mesh.add_vertex(mid)
	_line_mesh.add_vertex(mid)
	_line_mesh.add_vertex(end)
	_line_mesh.surface_end()
