extends Node
## Headless smoke test of the survival loop. Run:
## godot --headless --path . res://tests/smoke_test.tscn
## WARNING: writes user://savegame.json - back up your save first.

var _fails := 0


func _check(test_name: String, ok: bool, detail := "") -> void:
	if not ok:
		_fails += 1
	print("TEST %s: %s %s" % [test_name, "PASS" if ok else "FAIL", detail])


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 60:
		await get_tree().process_frame
	var st := SurvivalState
	for res in ["wood", "stone", "sticks"]:
		st.add_item(res, 60, "")
	var recipes: Dictionary = st.get_script().get_script_constant_map()["RECIPES"]
	for item in recipes.keys():
		var before := int(st.inventory.get(item, 0))
		var can := st.can_craft(item)
		var ok := st.craft(item)
		var after := int(st.inventory.get(item, 0))
		_check("craft_" + str(item), can and ok and after > before, "%d -> %d" % [before, after])
	for food in ["cooked_fish", "raw_fish", "cooked_food", "berries", "vegetables"]:
		st.hunger = 30.0
		st.add_item(food, 1, "")
		var n := int(st.inventory.get(food, 0))
		var ate := st.eat_item(food)
		_check("eat_" + food, ate and st.hunger > 30.0 and int(st.inventory.get(food, 0)) == n - 1, "hunger 30 -> %.1f" % st.hunger)
	st.hunger = 30.0
	st.add_item("cooked_fish", 1, "")
	_check("eat_best_food", st.eat_best_food() and st.hunger > 30.0, "hunger 30 -> %.1f" % st.hunger)
	st.add_item("fishing_rod", 1, "")
	var d0 := st.get_tool_durability("fishing_rod")
	st.damage_tool("fishing_rod")
	_check("rod_durability", st.get_tool_durability("fishing_rod") == d0 - 1, "%d -> %d" % [d0, st.get_tool_durability("fishing_rod")])
	var harvest := get_tree().get_nodes_in_group("harvestable_resources").size()
	_check("harvestables_present", harvest > 50, str(harvest))
	var stoves := 0
	var ground: LowPolyGround = null
	var saver: Node = null
	var landmarks := -1
	for node in main.find_children("*", "", true, false):
		if node is WoodStove:
			stoves += 1
		if node is LowPolyGround and ground == null:
			ground = node
		if saver == null and node.has_method("save_game") and node.has_method("load_game"):
			saver = node
		var sc := node.get_script() as Script
		if sc and sc.resource_path.ends_with("world_landmarks.gd"):
			landmarks = node.get_child_count()
	_check("stove_present", stoves > 0, str(stoves))
	_check("landmarks_built", landmarks > 0, str(landmarks))
	var water := 0
	if ground:
		for x in range(-80, 81, 4):
			for z in range(-80, 81, 4):
				if ground.is_water(Vector2(x, z)):
					water += 1
	_check("water_for_fishing_and_bridges", water > 10, "%d water samples" % water)
	_check("save_system_present", saver != null)
	if saver:
		st.inventory["sapling"] = 7
		st.hunger = 55.5
		saver.save_game(true)
		saver.save_game(true)
		st.inventory["sapling"] = 0
		st.hunger = 10.0
		saver.set("_loaded", false)
		saver.load_game()
		_check("save_roundtrip", int(st.inventory.get("sapling", 0)) == 7 and absf(st.hunger - 55.5) < 0.6, "sapling %d hunger %.1f" % [int(st.inventory.get("sapling", 0)), st.hunger])
		var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
		if f == null:
			_check("corrupt_save_uses_backup", false, "user:// is not writable here")
			print("SMOKE RESULT: %d failures" % _fails)
			get_tree().quit()
			return
		f.store_string("{broken json")
		f.close()
		st.inventory["sapling"] = 0
		st.hunger = 10.0
		saver.set("_loaded", false)
		saver.load_game()
		_check("corrupt_save_uses_backup", int(st.inventory.get("sapling", 0)) == 7 and absf(st.hunger - 55.5) < 0.6, "sapling %d hunger %.1f" % [int(st.inventory.get("sapling", 0)), st.hunger])
	print("SMOKE RESULT: %d failures" % _fails)
	get_tree().quit()
