extends Node
@onready var player: CharacterBody3D = $"../Player"
@onready var stove: Node = get_node_or_null("../House/WoodStove")

# Only handles shelter and heat. Atmosphere is the sole owner of sun and sky.
func _process(_delta: float) -> void:
	var inside := _inside_cabin()
	var heat: float = float(stove.heat_strength()) if stove and stove.has_method("heat_strength") else 0.0
	SurvivalState.set_environment(inside, heat if inside else 0.0)
func _inside_cabin()->bool:
	var p:=player.global_position;var house:=get_node_or_null("../House") as Node3D
	if not house:return false
	var local:=house.to_local(p);return absf(local.x)<5.0 and absf(local.z)<4.7 and p.y<4.2
