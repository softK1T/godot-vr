extends Area3D
class_name WaterBody
func _ready()->void: body_entered.connect(_enter);body_exited.connect(_exit)
func _enter(body:Node)->void:
	if body.is_in_group("player") or body.name=="Player": SurvivalState.set_wet(true)
func _exit(body:Node)->void:
	if body.is_in_group("player") or body.name=="Player": SurvivalState.set_wet(false)
