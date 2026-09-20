extends Node
class_name GateBuilder
const GATE_SCENE:=preload("res://assets/models/low_poly_fence/scenes/fence_gate_3m.tscn")
static func create_gate()->Node3D:
 var gate:=GATE_SCENE.instantiate() as Node3D;gate.name="PlacedGate"
 var old_leaf:=gate.get_node_or_null("InteractiveGate")
 if old_leaf:old_leaf.set_script(null)
 gate.set_script(load("res://scripts/placeable_gate.gd"));return gate
static func create_preview()->Node3D:
 var gate:=create_gate();gate.name="GatePlacementPreview";gate.set_script(null)
 for body in gate.find_children("*","CollisionObject3D",true,false):(body as CollisionObject3D).collision_layer=0;(body as CollisionObject3D).collision_mask=0
 for shape in gate.find_children("*","CollisionShape3D",true,false):(shape as CollisionShape3D).disabled=true
 set_preview_valid(gate,true);return gate
static func set_preview_valid(preview:Node3D,valid:bool)->void:
 var material:=StandardMaterial3D.new();material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(.16,1,.3,.55) if valid else Color(1,.1,.05,.6);material.no_depth_test=true
 for node in preview.find_children("*","MeshInstance3D",true,false):(node as MeshInstance3D).material_override=material
