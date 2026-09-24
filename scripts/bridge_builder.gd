extends Node3D
## Wooden bridges: hold the build key to preview a 2 m section over water,
## release to build it (4 wood, requires a hammer). Sections snap to bridge ends.

const BUILD_KEY := KEY_B
const KEY_LABEL := "B"
const SECTION_LENGTH := 2.0
const SECTION_WIDTH := 1.6
const WOOD_COST := 4
const SAVE_PATH := "user://bridges.json"

var _ground: LowPolyGround
var _sections: Array[Dictionary] = []
var _was_held := false
var _preview: Node3D
var _preview_ok := false
var _preview_valid_shown := -1
var _plan_data := {}
var _hint_cd := {}
var _wood := _mat(Color(0.5, 0.36, 0.23))
var _wood_dark := _mat(Color(0.37, 0.27, 0.18))
var _ok_mat := _preview_mat(Color(0.6, 0.72, 0.55))
var _bad_mat := _preview_mat(Color(0.76, 0.46, 0.38))
var _sfx: AudioStreamPlayer3D
const XR_BUTTON := "grip_click"
var _xr_held := false
var _xr_scan := 0.0
var _connected: Array = []


func _ready() -> void:
	_sfx = AudioStreamPlayer3D.new()
	_sfx.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_sfx.top_level = true
	_sfx.stream = load("res://scripts/fishing_controller.gd").synth(210.0, 110.0, 0.28, 0.6, 0.45)
	add_child(_sfx)
	await get_tree().process_frame
	_ground = _find_ground(get_tree().current_scene if get_tree().current_scene else get_parent())
	if _ground:
		_load()


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


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


func _preview_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _hint(key: String, text: String) -> void:
	if float(_hint_cd.get(key, 0.0)) > 0.0:
		return
	_hint_cd[key] = 5.0
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
	var held := _xr_held or Input.is_physical_key_pressed(BUILD_KEY)
	if held:
		if not SurvivalState.has_item("hammer"):
			_hint("hammer", "You need a hammer to build a bridge.")
		else:
			if not _was_held:
				_hint("how", "Aim over water, release %s to build a section (4 wood)." % KEY_LABEL)
			_update_preview(cam)
	elif _was_held:
		if _preview != null:
			if _preview_ok:
				_build(_plan_data)
			else:
				SurvivalState.notification.emit(str(_plan_data.get("reason", "You cannot build here.")), Color(1.0, 0.55, 0.4))
		_clear_preview()
	_was_held = held


func _plan(cam: Camera3D) -> Dictionary:
	var fwd := -cam.global_transform.basis.z
	var flat := Vector2(fwd.x, fwd.z)
	if flat.length() < 0.05:
		flat = Vector2(0.0, -1.0)
	flat = flat.normalized()
	var start := Vector2(cam.global_position.x, cam.global_position.z) + flat * 1.2
	var top := -INF
	var snapped := false
	var best := 1.6
	for s in _sections:
		var c := Vector2(float(s["x"]), float(s["z"]))
		var d := Vector2(cos(float(s["yaw"])), sin(float(s["yaw"])))
		for side in [1.0, -1.0]:
			var dir: Vector2 = d * side
			var end: Vector2 = c + dir * SECTION_LENGTH * 0.5
			var dist := end.distance_to(start)
			if dist < best and dir.dot(flat) > 0.3:
				best = dist
				start = end
				flat = dir
				top = float(s["y"])
				snapped = true
	var center := start + flat * SECTION_LENGTH * 0.5
	var finish := start + flat * SECTION_LENGTH
	var yaw := atan2(flat.y, flat.x)
	var data := {"ok": false, "x": center.x, "z": center.y, "yaw": yaw, "y": 0.0, "reason": ""}
	if not _ground.is_water(center):
		data["y"] = _ground.surface_height(center) + 0.05
		data["reason"] = "Bridges can only be built over water."
		return data
	var water := _ground.water_level_at(center)
	if not snapped:
		top = water + 0.45
		if not _ground.is_water(start):
			top = maxf(top, _ground.surface_height(start) + 0.03)
	data["y"] = top
	for s in _sections:
		if Vector2(float(s["x"]), float(s["z"])).distance_to(center) < 1.2:
			data["reason"] = "A bridge section is already here."
			return data
	if not _ground.is_water(finish) and _ground.surface_height(finish) > top + 0.35:
		data["reason"] = "The far bank is too high here."
		return data
	if top > water + 1.6:
		data["reason"] = "Too high above the water."
		return data
	data["ok"] = true
	return data


func _xform(s: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -float(s["yaw"])), Vector3(float(s["x"]), float(s["y"]), float(s["z"])))


func _update_preview(cam: Camera3D) -> void:
	_plan_data = _plan(cam)
	_preview_ok = bool(_plan_data["ok"])
	if _preview == null:
		_preview = _make_section(_plan_data, true)
		_preview_valid_shown = -1
	_preview.global_transform = _xform(_plan_data)
	var shown := 1 if _preview_ok else 0
	if shown != _preview_valid_shown:
		_preview_valid_shown = shown
		for mi in _preview.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = _ok_mat if _preview_ok else _bad_mat


func _clear_preview() -> void:
	if _preview != null:
		_preview.queue_free()
	_preview = null
	_preview_ok = false


func _box_mesh(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.visibility_range_end = 120.0
	parent.add_child(mi)


func _box_shape(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	parent.add_child(cs)


func _make_section(s: Dictionary, preview: bool) -> Node3D:
	var root: Node3D = Node3D.new() if preview else StaticBody3D.new()
	root.name = "BridgePreview" if preview else "BridgeSection"
	add_child(root)
	root.global_transform = _xform(s)
	var half := SECTION_LENGTH * 0.5
	for i in 5:
		_box_mesh(root, Vector3(0.37, 0.08, SECTION_WIDTH), Vector3(-half + 0.2 + float(i) * 0.4, -0.04, 0.0), _wood if i % 2 == 0 else _wood_dark)
	for z in [-0.6, 0.6]:
		_box_mesh(root, Vector3(SECTION_LENGTH, 0.14, 0.14), Vector3(0.0, -0.15, z), _wood_dark)
	var depth := float(s["y"]) - (_ground.water_level_at(Vector2(float(s["x"]), float(s["z"]))) - 0.9)
	depth = clampf(depth, 0.4, 3.0)
	for x in [-half + 0.1, half - 0.1]:
		for z in [-0.7, 0.7]:
			_box_mesh(root, Vector3(0.14, depth, 0.14), Vector3(x, -depth * 0.5, z), _wood_dark)
			_box_mesh(root, Vector3(0.09, 0.9, 0.09), Vector3(x, 0.45, z * 1.09), _wood)
	for z in [-0.76, 0.76]:
		_box_mesh(root, Vector3(SECTION_LENGTH, 0.07, 0.07), Vector3(0.0, 0.86, z), _wood)
	if not preview:
		_box_shape(root, Vector3(SECTION_LENGTH, 0.2, SECTION_WIDTH), Vector3(0.0, -0.1, 0.0))
		for z in [-0.8, 0.8]:
			_box_shape(root, Vector3(SECTION_LENGTH, 1.0, 0.1), Vector3(0.0, 0.5, z))
	else:
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


func _build(s: Dictionary) -> void:
	if not SurvivalState.remove_item("wood", WOOD_COST):
		SurvivalState.notification.emit("You need %d wood for a bridge section." % WOOD_COST, Color(1.0, 0.55, 0.4))
		return
	SurvivalState.damage_tool("hammer")
	var entry := {"x": float(s["x"]), "y": float(s["y"]), "z": float(s["z"]), "yaw": float(s["yaw"])}
	_sections.append(entry)
	_make_section(entry, false)
	_sfx.global_position = Vector3(entry["x"], entry["y"], entry["z"])
	_sfx.play()
	SurvivalState.notification.emit("Bridge section built.", Color(0.72, 1.0, 0.58))
	_save()


func _save() -> void:
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_sections))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(SAVE_PATH))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Array:
		return
	for e in parsed:
		if e is Dictionary and e.has("x") and e.has("yaw"):
			var entry := {"x": float(e["x"]), "y": float(e["y"]), "z": float(e["z"]), "yaw": float(e["yaw"])}
			_sections.append(entry)
			_make_section(entry, false)


func _scan_xr(delta: float) -> void:
	_xr_scan -= delta
	if _xr_scan > 0.0:
		return
	_xr_scan = 1.0
	for c in get_tree().root.find_children("*", "XRController3D", true, false):
		if c in _connected:
			continue
		_connected.append(c)
		c.button_pressed.connect(_on_xr_button.bind(true))
		c.button_released.connect(_on_xr_button.bind(false))


func _on_xr_button(button_name: String, down: bool) -> void:
	if button_name == XR_BUTTON:
		_xr_held = down
