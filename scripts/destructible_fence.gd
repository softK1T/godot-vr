extends StaticBody3D
class_name DestructibleFence

@export var hits_required := 3
@export var wood_return := 1
@export var fence_label := "fence"
var _hits := 0
var _breaking := false

func get_interaction_text() -> String:
 if _breaking:return ""
 return "LMB  Dismantle %s  %d/%d  [Axe]"%[fence_label,_hits,hits_required]

func interact(player:Node)->void:
 if _breaking:return
 if not _has_axe(player):
  SurvivalState.notification.emit("Equip the axe to dismantle this %s."%fence_label,Color(1,.58,.3));return
 _hits+=1;SurvivalState.damage_tool("axe");_hit_animation()
 if _hits<hits_required:
  SurvivalState.notification.emit("The %s is coming apart."%fence_label,Color(.92,.74,.45));return
 _breaking=true;collision_layer=0;collision_mask=0
 SurvivalState.add_item("wood",wood_return,"wood")
 SurvivalState.notification.emit("Dismantled %s."%fence_label,Color(.7,1,.48))
 var tween:=create_tween();tween.set_parallel(true);tween.tween_property(self,"scale",scale*Vector3(.75,.08,.75),.24);tween.tween_property(self,"position:y",position.y-.18,.24);tween.chain().tween_callback(queue_free)

func _has_axe(player:Node)->bool:
 return player!=null and player.has_method("has_equipped_tool") and player.has_equipped_tool("axe") and SurvivalState.has_item("axe") and SurvivalState.get_tool_durability("axe")>0

func _hit_animation()->void:
 var base:=rotation.z;var tween:=create_tween();tween.tween_property(self,"rotation:z",base+.018,.05);tween.tween_property(self,"rotation:z",base-.012,.07);tween.tween_property(self,"rotation:z",base,.07)

func hammer_dismantle(_player: Node) -> void:
 if _breaking:return
 _breaking=true;collision_layer=0;collision_mask=0
 SurvivalState.add_item("wood",wood_return,"wood")
 var tween:=create_tween();tween.set_parallel(true);tween.tween_property(self,"scale",scale*Vector3(.75,.08,.75),.18);tween.tween_property(self,"position:y",position.y-.18,.18);tween.chain().tween_callback(queue_free)
