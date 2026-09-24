@tool
extends Node3D
## Procedural low-poly axe. Call swing() to play the chop animation.
## The `impact` signal fires at the blade's contact frame for game logic.
class_name LowPolyAxe

signal impact
signal swing_finished

@export var auto_swing_on_left_click := false
@export var swing_time := 0.56
@export var idle_position := Vector3(0, 0, 0)

var _pivot: Node3D
var _anim: AnimationPlayer
var _playing := false

func _ready() -> void:
	_build()

func _unhandled_input(event: InputEvent) -> void:
	if not Engine.is_editor_hint() and auto_swing_on_left_click and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			swing()

func swing() -> void:
	if _playing or Engine.is_editor_hint():
		return
	_playing = true
	_anim.play(&"chop", -1, 0.56 / maxf(swing_time, 0.01))

func is_swinging() -> bool:
	return _playing

func is_striking() -> bool:
	return _playing and _anim.current_animation_position >= 0.22 and _anim.current_animation_position <= 0.40

func get_blade_tip() -> Vector3:
	return _pivot.to_global(Vector3(-0.52, 0.52, 0))

func _emit_impact() -> void:
	impact.emit()

func _on_animation_finished(_name: StringName) -> void:
	_playing = false
	swing_finished.emit()

func _build() -> void:
	if has_node("SwingPivot"):
		return
	_pivot = Node3D.new()
	_pivot.name = "SwingPivot"
	_pivot.position = idle_position
	add_child(_pivot)
	_pivot.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	# Eight-sided tapered ash handle, dark leather grip and brass bands.
	_add_cylinder("Ash handle", 0.047, 0.066, 1.30, Vector3(0, 0, 0), Color("a4784a"), 8)
	_add_cylinder("Leather grip", 0.074, 0.070, 0.37, Vector3(0, -0.46, 0), Color("39352e"), 8)
	_add_cylinder("Grip ring top", 0.075, 0.075, 0.027, Vector3(0, -0.26, 0), Color("c4a370"), 8)
	_add_cylinder("Grip ring bottom", 0.077, 0.077, 0.027, Vector3(0, -0.65, 0), Color("c4a370"), 8)
	_add_cylinder("Pommel", 0.078, 0.057, 0.06, Vector3(0, -0.69, 0), Color("9d7650"), 8)
	_add_cylinder("Iron socket", 0.095, 0.095, 0.26, Vector3(0, 0.49, 0), Color("525f66"), 8)
	# A faceted wedge with a flared cutting edge, extruded across its thickness.
	_add_prism("Forged head", [Vector2(-0.055, 0.39), Vector2(-0.20, 0.47), Vector2(-0.39, 0.40), Vector2(-0.42, 0.65), Vector2(-0.21, 0.59), Vector2(-0.055, 0.61)], 0.084, Color("76878b"))
	_add_prism("Bright blade bevel", [Vector2(-0.39, 0.40), Vector2(-0.44, 0.36), Vector2(-0.49, 0.36), Vector2(-0.51, 0.68), Vector2(-0.44, 0.68), Vector2(-0.42, 0.65)], 0.055, Color("becdd0"))
	_add_prism("Steel glint", [Vector2(-0.49, 0.36), Vector2(-0.51, 0.36), Vector2(-0.54, 0.68), Vector2(-0.51, 0.68)], 0.018, Color("e0e5de"))
	# VR contact points follow the visible steel under both the hand and the swing animation.
	var eye := Node3D.new()
	eye.name = "BladeEye"
	eye.position = Vector3(-0.16, 0.52, 0)
	_pivot.add_child(eye)
	var tip := Node3D.new()
	tip.name = "BladeTip"
	tip.position = Vector3(-0.51, 0.52, 0)
	_pivot.add_child(tip)
	_anim = AnimationPlayer.new()
	_anim.name = "AnimationPlayer"
	_anim.root_node = NodePath("..")
	add_child(_anim)
	_anim.animation_finished.connect(_on_animation_finished)
	_anim.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	var library := AnimationLibrary.new()
	var chop := Animation.new()
	chop.length = 0.56
	chop.loop_mode = Animation.LOOP_NONE
	var track := chop.add_track(Animation.TYPE_VALUE)
	chop.track_set_path(track, NodePath("SwingPivot:rotation"))
	chop.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for sample in [[0.0, -0.13], [0.13, -1.05], [0.22, -1.12], [0.31, 0.70], [0.38, 0.82], [0.56, -0.13]]:
		chop.track_insert_key(track, sample[0], Vector3(0, 0, sample[1]))
	var pos_track := chop.add_track(Animation.TYPE_VALUE)
	chop.track_set_path(pos_track, NodePath("SwingPivot:position"))
	chop.track_set_interpolation_type(pos_track, Animation.INTERPOLATION_CUBIC)
	for sample in [[0.0, Vector3.ZERO], [0.16, Vector3(0.08, 0.08, 0.05)], [0.31, Vector3(-0.09, -0.15, -0.13)], [0.38, Vector3(-0.07, -0.12, -0.12)], [0.56, Vector3.ZERO]]:
		chop.track_insert_key(pos_track, sample[0], sample[1] + idle_position)
	var events := chop.add_track(Animation.TYPE_METHOD)
	chop.track_set_path(events, NodePath("."))
	chop.track_insert_key(events, 0.31, {"method": &"_emit_impact", "args": []})
	library.add_animation(&"chop", chop)
	_anim.add_animation_library(&"", library)

func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.65 if color.b > color.r else 0.0
	m.roughness = 0.45 if m.metallic > 0.0 else 0.9
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m

func _add_cylinder(label: String, top: float, bottom: float, height: float, pos: Vector3, color: Color, sides: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	_pivot.add_child(node)
	node.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null

func _add_prism(label: String, outline: Array[Vector2], half_depth: float, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Convex outlines are triangulated as fans, with flat-shaded side facets.
	for i in range(1, outline.size() - 1):
		_face(st, Vector3(outline[0].x, outline[0].y, half_depth), Vector3(outline[i].x, outline[i].y, half_depth), Vector3(outline[i + 1].x, outline[i + 1].y, half_depth), color)
		_face(st, Vector3(outline[i + 1].x, outline[i + 1].y, -half_depth), Vector3(outline[i].x, outline[i].y, -half_depth), Vector3(outline[0].x, outline[0].y, -half_depth), color.darkened(0.16))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var p := Vector3(a.x, a.y, half_depth)
		var q := Vector3(b.x, b.y, half_depth)
		var r := Vector3(b.x, b.y, -half_depth)
		var s := Vector3(a.x, a.y, -half_depth)
		_face(st, p, s, r, color.darkened(0.13))
		_face(st, p, r, q, color.darkened(0.13))
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = st.commit()
	node.material_override = _material(Color.WHITE)
	_pivot.add_child(node)
	node.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null

func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for v in [a, b, c]:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(v)
