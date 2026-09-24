extends Node3D
class_name WaterWorld
# Builds water surfaces that follow the river centre line carved by LowPolyGround.
const RIVER_VISUAL_HALF_WIDTH := 3.2
func _ready() -> void: call_deferred("build")
func _mat(flow: float) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = preload("res://shaders/water.gdshader"); m.set_shader_parameter("flow_speed", flow); return m
func build() -> void:
	for c in get_children(): c.queue_free()
	var ground := get_node_or_null("../Ground")
	if ground == null or not ground.has_method("river_path"): return
	_build_river(ground); _build_lake(ground)
func _water_area(area_name: String) -> Area3D:
	var area := Area3D.new(); area.name = area_name; area.set_script(load("res://scripts/water_body.gd")); add_child(area); return area
func _build_river(ground: Node) -> void:
	var pts: PackedVector2Array = ground.call("river_path")
	var lake_c: Vector2 = ground.call("lake_center"); var lake_r: float = ground.call("lake_radius")
	var lefts: Array[Vector3] = []; var rights: Array[Vector3] = []; var us: Array[float] = []
	var along := 0.0; var n := pts.size()
	for i in n:
		var p := pts[i]
		if i > 0: along += p.distance_to(pts[i - 1])
		var tan := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized(); var side := Vector2(-tan.y, tan.x)
		var info: Vector2 = ground.call("river_info", p); var y: float = ground.call("river_level", info.y)
		lefts.append(Vector3(p.x + side.x * RIVER_VISUAL_HALF_WIDTH, y, p.y + side.y * RIVER_VISUAL_HALF_WIDTH))
		rights.append(Vector3(p.x - side.x * RIVER_VISUAL_HALF_WIDTH, y, p.y - side.y * RIVER_VISUAL_HALF_WIDTH))
		us.append(along / 4.0)
		if p.distance_to(lake_c) < lake_r - 2.0: break
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(lefts.size() - 1):
		var quad := [[lefts[i], Vector2(us[i], 0)], [rights[i], Vector2(us[i], 1)], [lefts[i + 1], Vector2(us[i + 1], 0)], [rights[i], Vector2(us[i], 1)], [rights[i + 1], Vector2(us[i + 1], 1)], [lefts[i + 1], Vector2(us[i + 1], 0)]]
		for v in quad: st.set_normal(Vector3.UP); st.set_uv(v[1]); st.add_vertex(v[0])
	st.generate_tangents()
	var mi := MeshInstance3D.new(); mi.name = "RiverSurface"; mi.mesh = st.commit(); mi.material_override = _mat(0.35); mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(mi)
	var area := _water_area("River")
	for i in range(0, lefts.size() - 1, 2):
		var j := mini(i + 2, lefts.size() - 1)
		var a := (lefts[i] + rights[i]) * 0.5; var b := (lefts[j] + rights[j]) * 0.5; var d := b - a
		var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(d.length() + 0.6, 1.8, RIVER_VISUAL_HALF_WIDTH * 1.5); cs.shape = box
		cs.position = (a + b) * 0.5 - Vector3(0, 0.8, 0); cs.rotation.y = atan2(-d.z, d.x); area.add_child(cs)
func _build_lake(ground: Node) -> void:
	var c: Vector2 = ground.call("lake_center"); var r: float = ground.call("lake_radius") + 0.6; var y: float = ground.call("lake_level")
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); var seg := 56
	for i in seg:
		var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
		for v in [Vector3.ZERO, Vector3(cos(a0) * r, 0, sin(a0) * r), Vector3(cos(a1) * r, 0, sin(a1) * r)]:
			st.set_normal(Vector3.UP); st.set_uv(Vector2(v.x, v.z) / 6.0); st.add_vertex(Vector3(c.x, y, c.y) + v)
	st.generate_tangents()
	var mi := MeshInstance3D.new(); mi.name = "LakeSurface"; mi.mesh = st.commit(); mi.material_override = _mat(0.0); mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(mi)
	var area := _water_area("Lake"); var cs := CollisionShape3D.new(); var cyl := CylinderShape3D.new(); cyl.radius = r - 1.2; cyl.height = 3.6; cs.shape = cyl; cs.position = Vector3(c.x, y - 1.6, c.y); area.add_child(cs)
