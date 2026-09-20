extends Node3D

@export var seed_value: int = 7421

var _rng := RandomNumberGenerator.new()
var _wood_material: StandardMaterial3D
var _bark_material: StandardMaterial3D
var _stone_material: StandardMaterial3D

func _ready() -> void:
	_rng.seed = seed_value
	_build_path_stones()
	_build_woodpile()
	_build_chopping_area()
	_build_fallen_logs()
	_build_mist_banks()

func _build_path_stones() -> void:
	_stone_material = _make_material(Color(0.25, 0.27, 0.23), 0.96)
	var root := Node3D.new()
	root.name = "PathStones"
	add_child(root)
	for index in range(17):
		var stone := MeshInstance3D.new()
		stone.name = "PathStone_%02d" % index
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.52
		mesh.bottom_radius = 0.58
		mesh.height = 0.055
		mesh.radial_segments = 9
		mesh.material = _stone_material
		stone.mesh = mesh
		var progress := float(index) / 16.0
		stone.position = Vector3(
			_rng.randf_range(-0.42, 0.42),
			0.026 + _rng.randf_range(0.0, 0.012),
			lerpf(13.0, 0.8, progress) + _rng.randf_range(-0.16, 0.16)
		)
		stone.rotation.y = _rng.randf_range(-0.55, 0.55)
		stone.scale = Vector3(
			_rng.randf_range(0.72, 1.25),
			1.0,
			_rng.randf_range(0.65, 1.12)
		)
		stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(stone)

func _build_woodpile() -> void:
	_wood_material = _make_material(Color(0.29, 0.16, 0.085), 0.92)
	_bark_material = _make_material(Color(0.16, 0.095, 0.05), 1.0)
	var root := Node3D.new()
	root.name = "Woodpile"
	root.position = Vector3(-5.5, 0.0, -0.3)
	add_child(root)

	for row in range(3):
		var row_count := 6 - row
		for column in range(row_count):
			var log := _make_log(1.15 + _rng.randf_range(-0.12, 0.12), 0.115)
			log.name = "Firewood_%d_%d" % [row, column]
			log.position = Vector3(
				0.0,
				0.13 + row * 0.205,
				(column - (row_count - 1) * 0.5) * 0.22
			)
			log.rotation.x = _rng.randf_range(-0.05, 0.05)
			log.rotation.z = PI * 0.5 + _rng.randf_range(-0.04, 0.04)
			root.add_child(log)

	for side in [-1.0, 1.0]:
		var support := _make_beam(Vector3(0.1, 1.0, 0.1), _bark_material)
		support.name = "WoodpileSupport"
		support.position = Vector3(side * 0.64, 0.5, 0.0)
		root.add_child(support)

func _build_chopping_area() -> void:
	var root := Node3D.new()
	root.name = "ChoppingArea"
	root.position = Vector3(-5.8, 0.0, 1.15)
	add_child(root)

	var stump := MeshInstance3D.new()
	stump.name = "ChoppingStump"
	var stump_mesh := CylinderMesh.new()
	stump_mesh.top_radius = 0.43
	stump_mesh.bottom_radius = 0.48
	stump_mesh.height = 0.58
	stump_mesh.radial_segments = 12
	stump_mesh.material = _bark_material
	stump.mesh = stump_mesh
	stump.position.y = 0.29
	root.add_child(stump)

	for index in range(5):
		var split_log := _make_log(_rng.randf_range(0.48, 0.72), 0.09)
		split_log.name = "SplitLog_%02d" % index
		var angle := _rng.randf_range(0.0, TAU)
		split_log.position = Vector3(cos(angle), 0.09, sin(angle)) * _rng.randf_range(0.55, 1.05)
		split_log.rotation = Vector3(
			_rng.randf_range(-0.35, 0.35),
			_rng.randf_range(0.0, TAU),
			PI * 0.5 + _rng.randf_range(-0.25, 0.25)
		)
		root.add_child(split_log)

func _build_fallen_logs() -> void:
	var root := Node3D.new()
	root.name = "FallenLogs"
	add_child(root)
	var placements := [
		[Vector3(-14.0, 0.28, 7.5), 0.35, 3.7, 0.24],
		[Vector3(15.5, 0.22, 3.5), -0.62, 3.0, 0.20],
		[Vector3(-11.0, 0.19, -15.0), 1.05, 2.7, 0.18]
	]
	for index in range(placements.size()):
		var data: Array = placements[index]
		var log := _make_log(data[2], data[3])
		log.name = "FallenLog_%02d" % index
		log.position = data[0]
		log.rotation = Vector3(PI * 0.5 + _rng.randf_range(-0.06, 0.06), data[1], 0.0)
		root.add_child(log)
		for branch_index in range(2):
			var branch := _make_log(_rng.randf_range(0.7, 1.15), data[3] * 0.42)
			branch.name = "Branch_%d_%d" % [index, branch_index]
			branch.position = data[0] + Vector3(
				_rng.randf_range(-0.7, 0.7),
				data[3] * 1.2,
				_rng.randf_range(-0.7, 0.7)
			)
			branch.rotation = Vector3(
				PI * 0.5,
				data[1] + _rng.randf_range(0.7, 1.5),
				_rng.randf_range(-0.35, 0.35)
			)
			root.add_child(branch)

func _build_mist_banks() -> void:
	var root := Node3D.new()
	root.name = "MistBanks"
	add_child(root)
	var placements := [
		[Vector3(-20.0, 1.1, 5.0), Vector3(17.0, 2.4, 11.0), 0.012],
		[Vector3(19.0, 0.9, -5.0), Vector3(15.0, 2.0, 13.0), 0.010],
		[Vector3(-7.0, 0.8, -24.0), Vector3(22.0, 1.8, 10.0), 0.008]
	]
	for index in range(placements.size()):
		var data: Array = placements[index]
		var volume := FogVolume.new()
		volume.name = "MistBank_%02d" % index
		volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		volume.position = data[0]
		volume.size = data[1]
		var fog_material := FogMaterial.new()
		fog_material.density = data[2]
		fog_material.albedo = Color(0.42, 0.50, 0.46)
		fog_material.emission = Color(0.001, 0.002, 0.0015)
		fog_material.height_falloff = 2.8
		fog_material.edge_fade = 0.35
		volume.material = fog_material
		root.add_child(volume)

func _make_log(length: float, radius: float) -> MeshInstance3D:
	var log := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * _rng.randf_range(0.86, 0.96)
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 9
	mesh.material = _wood_material if _wood_material else _make_material(Color(0.29, 0.16, 0.085), 0.92)
	log.mesh = mesh
	log.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return log

func _make_beam(size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	beam.mesh = mesh
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return beam

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
