extends Node
@onready var sun:DirectionalLight3D=$"../Sun"
@onready var env_node:WorldEnvironment=$"../WorldEnvironment"
@onready var player:CharacterBody3D=$"../Player"
@onready var stove:Node=get_node_or_null("../House/WoodStove")
var _base_sun_rotation:=Vector3.ZERO
func _ready()->void:_base_sun_rotation=sun.rotation
func _process(_delta:float)->void:
	var daylight:=SurvivalState.get_daylight();var night:=1.0-daylight
	var hour:=SurvivalState.time_of_day
	sun.rotation.x=lerpf(-.25,-2.85,clampf((hour-5.0)/17.0,0,1))
	sun.light_energy=lerpf(.08,1.35,pow(daylight,.65));sun.light_color=Color(.52,.64,.9).lerp(Color(1,.84,.62),daylight)
	if env_node.environment:
		env_node.environment.background_energy_multiplier=lerpf(.16,1.0,daylight)
		env_node.environment.ambient_light_energy=lerpf(.18,.72,daylight)
		env_node.environment.volumetric_fog_density=lerpf(.055,.026,daylight)
	var inside:=_inside_cabin();var heat: float = float(stove.heat_strength()) if stove and stove.has_method("heat_strength") else 0.0
	SurvivalState.set_environment(inside,heat if inside else 0.0)
func _inside_cabin()->bool:
	var p:=player.global_position;var house:=get_node_or_null("../House") as Node3D
	if not house:return false
	var local:=house.to_local(p);return absf(local.x)<5.0 and absf(local.z)<4.7 and p.y<4.2
