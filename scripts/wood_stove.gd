extends StaticBody3D
class_name WoodStove
@export var burn_seconds_per_wood:=95.0
var fuel_time:=0.0
var _light:OmniLight3D
var _flame:MeshInstance3D
func _ready()->void:
	_light=get_node_or_null("FireLight") as OmniLight3D;_flame=get_node_or_null("Flame") as MeshInstance3D;_update_visual()
func _process(delta:float)->void:
	if fuel_time>0:fuel_time=maxf(0.0,fuel_time-delta);_update_visual()
func is_burning()->bool:return fuel_time>0
func heat_strength()->float:return clampf(fuel_time/25.0,0,1)
func get_interaction_text()->String:
	if is_burning():return "E  Cook food / add wood  (%d min fuel)"%int(ceil(fuel_time/60.0))
	return "E  Light stove  (1 wood)"
func interact(_player:Node)->void:
	if is_burning() and SurvivalState.has_item("vegetables",2):
		SurvivalState.remove_item("vegetables",2);SurvivalState.add_item("cooked_food",1,"warm meal");fuel_time=maxf(0.0,fuel_time-12.0);SurvivalState.notification.emit("Vegetable stew simmers on the stove.",Color(1,.72,.35))
	elif SurvivalState.remove_item("wood",1):
		fuel_time+=burn_seconds_per_wood;SurvivalState.notification.emit("The stove crackles. The cabin begins to warm.",Color(1,.58,.25))
	else:SurvivalState.notification.emit("You need wood for the stove, or 2 vegetables to cook.",Color(1,.5,.35))
	_update_visual()
func _update_visual()->void:
	var active:=is_burning()
	if _light:_light.light_energy=3.2*heat_strength() if active else 0.0
	if _flame:_flame.visible=active;_flame.scale.y=.75+sin(Time.get_ticks_msec()*.008)*.18
