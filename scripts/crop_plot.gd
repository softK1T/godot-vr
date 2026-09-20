extends Node3D
class_name CropPlot
@export var crop_name:="Root vegetables"
@export var growth_seconds:=90.0
@export var harvest_amount:=4
var stage:=0;var growth:=0.0;var watered:=false;var _plants:Node3D
func _ready()->void:
	_plants=Node3D.new();_plants.name="LivingCrop";add_child(_plants);_refresh_visual()
func _process(delta:float)->void:
	if stage==1:
		growth+=delta*(1.6 if watered else 1.0)
		if growth>=growth_seconds:stage=2;_refresh_visual();SurvivalState.notification.emit(crop_name+" are ready to harvest.",Color(.75,1,.48))
func get_interaction_text()->String:
	if stage==0:return "E  Plant seeds  (1 seed)"
	if stage==1:return "E  Water crops  (%d%%)"%int(growth/growth_seconds*100.0)
	return "E  Harvest "+crop_name
func interact(_player:Node)->void:
	if stage==0:
		if not SurvivalState.remove_item("seeds"):SurvivalState.notification.emit("You need seeds. Harvest mature crops to recover some.",Color(1,.55,.4));return
		stage=1;growth=0;watered=false;_refresh_visual();SurvivalState.notification.emit("Seeds planted. They will grow faster when watered.",Color(.68,1,.52))
	elif stage==1:
		watered=true;growth=minf(growth+growth_seconds*.18,growth_seconds);_refresh_visual();SurvivalState.notification.emit("The dark soil drinks the water.",Color(.48,.78,1))
	else:
		SurvivalState.add_item("vegetables",harvest_amount,crop_name);SurvivalState.add_item("seeds",2,"seeds");stage=0;growth=0;watered=false;_refresh_visual()
func _refresh_visual()->void:
	if not _plants:return
	for child in _plants.get_children():child.queue_free()
	if stage==0:return
	var rows:=3;var cols:=4
	for z in rows:
		for x in cols:
			var root:=Node3D.new();root.position=Vector3(-.7+x*.46,.05,-.4+z*.4);_plants.add_child(root)
			var stem:=MeshInstance3D.new();var sm:=CylinderMesh.new();sm.top_radius=.018;sm.bottom_radius=.025;sm.height=.18 if stage==1 else .38;sm.radial_segments=5;var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.13,.35,.065);mat.roughness=1;sm.material=mat;stem.mesh=sm;stem.position.y=sm.height*.5;root.add_child(stem)
			var leaves:=2 if stage==1 else 4
			for j in leaves:
				var leaf:=MeshInstance3D.new();var lm:=SphereMesh.new();lm.radius=.09 if stage==1 else .14;lm.height=.07;lm.radial_segments=5;lm.rings=2;var lmat:=StandardMaterial3D.new();lmat.albedo_color=Color(.12+.025*j,.4+.035*j,.07);lmat.roughness=1;lm.material=lmat;leaf.mesh=lm;leaf.position=Vector3(cos(j*TAU/leaves)*.09,sm.height*.75,sin(j*TAU/leaves)*.09);root.add_child(leaf)
			if stage==2:
				var bulb:=MeshInstance3D.new();var bm:=SphereMesh.new();bm.radius=.085;bm.height=.18;bm.radial_segments=6;bm.rings=3;var bmat:=StandardMaterial3D.new();bmat.albedo_color=Color(.72,.24,.045);bmat.roughness=1;bm.material=bmat;bulb.mesh=bm;bulb.position.y=.1;root.add_child(bulb)
	if watered:
		var wet:=StandardMaterial3D.new();wet.albedo_color=Color(.08,.04,.018,.45);wet.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;wet.roughness=.7
		var patch:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(2.0,1.35);plane.material=wet;patch.mesh=plane;patch.position.y=.012;_plants.add_child(patch)
