extends Node

signal inventory_changed(inventory: Dictionary)
signal vitals_changed(health: float, hunger: float, warmth: float, stamina: float)
signal time_changed(day: int, hour: int, minute: int)
signal notification(text: String, color: Color)
const DAY_LENGTH_SECONDS := 1200.0
var inventory: Dictionary = {
	"axe": 1, "pickaxe": 1, "hammer": 1, "farm_bed": 0, "gate": 0,
	"wood": 8, "stone": 0, "sticks": 0, "berries": 1, "mushroom": 0,
	"vegetables": 0, "cooked_food": 0, "seeds": 4, "sapling": 0
}
var tool_durability: Dictionary = {"axe": 60, "pickaxe": 70, "hammer": 100}
const TOOL_MAX_DURABILITY := {"axe": 60, "pickaxe": 70, "hammer": 100}
const RECIPES := {
	"hammer": {"ingredients": {"wood": 3, "sticks": 2}, "amount": 1, "label": "Building hammer"},
	"axe": {"ingredients": {"wood": 5, "stone": 3}, "amount": 1, "label": "Stone axe"},
	"pickaxe": {"ingredients": {"wood": 4, "stone": 6}, "amount": 1, "label": "Stone pickaxe"},
	"farm_bed": {"ingredients": {"wood": 6, "stone": 2}, "amount": 1, "label": "Farm bed"},
	"gate": {"ingredients": {"wood": 8, "stone": 2}, "amount": 1, "label": "Wooden gate"}
}
var health:=100.0; var hunger:=82.0; var warmth:=78.0; var stamina:=100.0
var day:=1; var time_of_day:=7.5; var _accum:=0.0; var _indoors:=false; var _heat:=0.0; var _wet:=false; var _cooldowns:={}
func _ready()->void: process_mode=Node.PROCESS_MODE_ALWAYS; inventory_changed.emit(inventory.duplicate()); _emit_vitals()
func _process(delta:float)->void:
	if get_tree().paused:return
	time_of_day+=delta*24.0/DAY_LENGTH_SECONDS
	if time_of_day>=24.0:time_of_day-=24.0;day+=1
	_accum+=delta
	if _accum>=1.0:_accum=0.0;_tick_survival();time_changed.emit(day,int(time_of_day),int(fmod(time_of_day,1.0)*60.0))
	for key in _cooldowns.keys():_cooldowns[key]=maxf(0.0,float(_cooldowns[key])-delta)
func _tick_survival()->void:
	hunger=maxf(0.0,hunger-.045)
	var night:=time_of_day<6.0 or time_of_day>20.5
	var target:=88.0 if _heat>.35 else (68.0 if _indoors else (12.0 if night else 48.0))
	if _wet: target -= 22.0
	target -= rain_wetness * 16.0 + season_cold
	warmth=move_toward(warmth,target,.22+_heat*.45)
	if hunger<=0 or warmth<=8:health=maxf(0.0,health-.35)
	elif hunger>65 and warmth>55:health=minf(100.0,health+.06)
	if hunger<22:_notify_once("hungry","You are hungry. Find food or harvest the garden.",Color(1,.62,.32))
	if warmth<24:_notify_once("cold","You are getting cold. Return home and light the stove.",Color(.48,.78,1))
	_emit_vitals()
func update_movement(delta:float,sprinting:bool)->void:
	if sprinting and stamina>0 and hunger>0:stamina=maxf(0.0,stamina-delta*18.0)
	else:stamina=minf(100.0,stamina+delta*(13.0 if hunger>20 else 6.0))
	_emit_vitals()
func set_environment(indoors:bool,heat_strength:float)->void:_indoors=indoors;_heat=clampf(heat_strength,0,1)
var _wet_count := 0
var rain_wetness := 0.0
var season_cold := 0.0
func set_wet(value:bool)->void:
	_wet_count = maxi(0, _wet_count + (1 if value else -1))
	var was := _wet
	_wet = _wet_count > 0
	if _wet and not was: notification.emit("You are soaked and losing warmth.",Color(.45,.75,1))
func add_item(item:String,amount:int,label:="")->void:
	inventory[item]=int(inventory.get(item,0))+amount;inventory_changed.emit(inventory.duplicate())
	var shown:=label if not label.is_empty() else item.replace("_"," ").capitalize();notification.emit("+%d %s"%[amount,shown],Color(.72,1,.58))
func has_item(item:String,amount:=1)->bool:return int(inventory.get(item,0))>=amount
func remove_item(item:String,amount:=1)->bool:
	if not has_item(item,amount):return false
	inventory[item]=int(inventory[item])-amount;inventory_changed.emit(inventory.duplicate());return true

func get_tool_durability(tool: String) -> int:
	return int(tool_durability.get(tool, 0))

func get_tool_max_durability(tool: String) -> int:
	return int(TOOL_MAX_DURABILITY.get(tool, 0))

func damage_tool(tool: String, amount := 1) -> bool:
	if not has_item(tool):
		return false
	var durability := maxi(0, get_tool_durability(tool) - amount)
	tool_durability[tool] = durability
	if durability <= 0:
		inventory[tool] = 0
		notification.emit("Your %s broke. Craft a new one." % tool.capitalize(), Color(1.0, 0.35, 0.22))
	inventory_changed.emit(inventory.duplicate())
	return durability > 0

func can_craft(item: String) -> bool:
	if not RECIPES.has(item):
		return false
	for ingredient in RECIPES[item].ingredients:
		if not has_item(ingredient, int(RECIPES[item].ingredients[ingredient])):
			return false
	return true

func craft(item: String) -> bool:
	if not RECIPES.has(item):
		return false
	if not can_craft(item):
		notification.emit("Missing materials for %s." % str(RECIPES[item].label), Color(1.0, 0.55, 0.3))
		return false
	for ingredient in RECIPES[item].ingredients:
		inventory[ingredient] = int(inventory.get(ingredient, 0)) - int(RECIPES[item].ingredients[ingredient])
	inventory[item] = int(inventory.get(item, 0)) + int(RECIPES[item].amount)
	if item in TOOL_MAX_DURABILITY:
		tool_durability[item] = int(TOOL_MAX_DURABILITY[item])
	inventory_changed.emit(inventory.duplicate())
	notification.emit("Crafted: %s" % str(RECIPES[item].label), Color(0.65, 1.0, 0.5))
	return true

func recipe_text(item: String) -> String:
	if not RECIPES.has(item):
		return ""
	var parts: Array[String] = []
	for ingredient in RECIPES[item].ingredients:
		parts.append("%s %d/%d" % [ingredient.capitalize(), int(inventory.get(ingredient, 0)), int(RECIPES[item].ingredients[ingredient])])
	return "  •  ".join(parts)

func eat_item(item: String) -> bool:
	var nutrition := {"berries": 13.0, "mushroom": 10.0, "vegetables": 24.0, "cooked_food": 45.0}
	var messages := {
		"berries": "You eat a handful of tart berries.",
		"mushroom": "You eat the wild mushrooms.",
		"vegetables": "You eat fresh vegetables.",
		"cooked_food": "A warm meal restores you."
	}
	if not nutrition.has(item):
		notification.emit("This item is not edible.", Color(1.0, 0.55, 0.42))
		return false
	if hunger >= 98.0:
		notification.emit("You are not hungry.", Color(0.85, 0.85, 0.75))
		return false
	if not remove_item(item):
		notification.emit("You have none left.", Color(1.0, 0.55, 0.42))
		return false
	hunger = minf(100.0, hunger + float(nutrition[item]))
	if item == "cooked_food":
		warmth = minf(100.0, warmth + 12.0)
	notification.emit(str(messages[item]), Color(1.0, 0.78, 0.42))
	_emit_vitals()
	return true

func eat_best_food()->bool:
	for item in ["cooked_food", "vegetables", "berries", "mushroom"]:
		if has_item(item):
			return eat_item(item)
	notification.emit("You have no food.", Color(1.0, 0.55, 0.42))
	return false
func get_daylight()->float:return clampf(sin((time_of_day-6.0)/24.0*TAU)*.5+.5,0,1)
func _emit_vitals()->void:vitals_changed.emit(health,hunger,warmth,stamina)
func _notify_once(key:String,text:String,color:Color)->void:
	if float(_cooldowns.get(key,0))>0:return
	_cooldowns[key]=45.0;notification.emit(text,color)
