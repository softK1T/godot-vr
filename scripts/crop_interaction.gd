extends Area3D
class_name CropInteraction
@export var crop_path:NodePath
func _crop()->Node:
	if not crop_path.is_empty():return get_node_or_null(crop_path)
	return get_parent()
func get_interaction_text()->String:
	var crop:=_crop();return crop.get_interaction_text() if crop and crop.has_method("get_interaction_text") else ""
func interact(player:Node)->void:
	var crop:=_crop();if crop and crop.has_method("interact"):crop.interact(player)
