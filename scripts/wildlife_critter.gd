extends Node3D
var velocity:=Vector3.ZERO
var target:Node3D
var _rng:=RandomNumberGenerator.new()
var _home:=Vector3.ZERO
var _wander:=Vector3.ZERO
var _timer:=0.0
var grounded:=false
var surface_offset:=0.02
func _ready()->void:_home=global_position;_rng.seed=int(global_position.x*331+global_position.z*719);_choose_wander();if grounded:_snap_to_surface()
func _process(delta:float)->void:
	_timer-=delta
	if _timer<=0:_choose_wander()
	var destination:=_wander
	if target and is_instance_valid(target) and global_position.distance_to(target.global_position)<8.0:destination=target.global_position
	var direction:=(destination-global_position);direction.y=0
	if direction.length()>.25:
		direction=direction.normalized();global_position+=direction*delta*.7;rotation.y=lerp_angle(rotation.y,atan2(direction.x,direction.z),delta*4.0)
	if grounded:
		_snap_to_surface()
	else:
		var bob:=sin(Time.get_ticks_msec()*.005+_home.x)*.02;position.y=maxf(.02,position.y+bob*delta)
func _snap_to_surface()->void:
	var ground:=get_node_or_null("../Ground")
	if ground and ground.has_method("surface_height"):
		global_position.y=float(ground.call("surface_height",Vector2(global_position.x,global_position.z)))+surface_offset
func _choose_wander()->void:_timer=_rng.randf_range(3,7);_wander=_home+Vector3(_rng.randf_range(-4,4),0,_rng.randf_range(-4,4))
