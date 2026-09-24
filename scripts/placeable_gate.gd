extends Node3D
class_name PlaceableGate

@export var open_angle_degrees:=88.0
var _leaf:Node3D
var _leaf2:Node3D
var _closed_rotation2:=0.0
var _closed_rotation:=0.0
var _target_rotation:=0.0
var _is_open:=false
var _hits:=0
var _breaking:=false

func _ready()->void:
 _leaf=get_node("InteractiveGate");_closed_rotation=_leaf.rotation.y;_target_rotation=_closed_rotation
 _leaf2=get_node_or_null("InteractiveGateRight")
 if _leaf2:_closed_rotation2=_leaf2.rotation.y

func _physics_process(delta:float)->void:
 if _leaf:_leaf.rotation.y=lerp_angle(_leaf.rotation.y,_target_rotation,minf(1.0,4.0*delta))
 if _leaf2:_leaf2.rotation.y=lerp_angle(_leaf2.rotation.y,_closed_rotation2-(_target_rotation-_closed_rotation),minf(1.0,4.0*delta))

func get_interaction_text()->String:
 if _breaking:return ""
 return "E  Close gate  •  Axe LMB dismantle" if _is_open else "E  Open gate  •  Axe LMB dismantle"

func interact(interactor:Node=null)->void:
 if _breaking:return
 _is_open=not _is_open
 if _is_open:
  var sign:=1.0
  if interactor is Node3D:sign=1.0 if _leaf.to_local(interactor.global_position).z>=0 else -1.0
  _target_rotation=_closed_rotation+deg_to_rad(open_angle_degrees*sign)
 else:_target_rotation=_closed_rotation

func dismantle(player:Node)->void:
 if _breaking:return
 if not (player and player.has_method("has_equipped_tool") and player.has_equipped_tool("axe") and SurvivalState.has_item("axe") and SurvivalState.get_tool_durability("axe")>0):return
 _hits+=1;SurvivalState.damage_tool("axe")
 if _hits<4:SurvivalState.notification.emit("Dismantling gate  %d/4"%_hits,Color(.92,.74,.45));return
 _breaking=true
 for body in find_children("*","CollisionObject3D",true,false):(body as CollisionObject3D).collision_layer=0
 SurvivalState.add_item("gate",1,"gate")
 var tween:=create_tween();tween.tween_property(self,"scale",scale*Vector3(.8,.05,.8),.24);tween.tween_callback(queue_free)

func hammer_dismantle(_player:Node)->void:
 if _breaking:return
 _breaking=true
 for body in find_children("*","CollisionObject3D",true,false):(body as CollisionObject3D).collision_layer=0
 SurvivalState.add_item("wood",7,"wood");SurvivalState.add_item("stone",1,"stone")
 var tween:=create_tween();tween.tween_property(self,"scale",scale*Vector3(.8,.05,.8),.18);tween.tween_callback(queue_free)
