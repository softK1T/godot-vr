extends Node
## Saves vitals, inventory, time, player position and world changes
## (felled trees, stumps, mined rocks, saplings, grown trees, stove fuel,
## farm beds with growth stage, fences and gates).
## Autosave every 90 s and on quit. F5 = save now, hold Shift+F8 for 2 s = new game.
## Procedural objects are identified by their generation index (save_id meta).
## Files are written to a temp file and renamed; the previous save is kept as .bak.
const SAVE_PATH := "user://savegame.json"
const TMP_PATH := "user://savegame.json.tmp"
const BAK_PATH := "user://savegame.json.bak"
const VERSION := 2
const AUTOSAVE_SECONDS := 90.0
const NEW_GAME_HOLD := 2.0
var _original := {}
var _gen_count := 0
var _ready_done := false
var _loaded := false
var _autosave := 0.0
var _new_game_hold := 0.0
var _new_game_hint_step := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not SurvivalState.has_meta("defaults"):
		SurvivalState.set_meta("defaults", _state_snapshot())
	get_tree().create_timer(0.8).timeout.connect(_on_world_ready)

func _on_world_ready() -> void:
	var i := 0
	for r in get_tree().get_nodes_in_group("harvestable_resources"):
		if not (r is Node3D):
			continue
		r.set_meta("save_id", "g%d" % i)
		_original[_id(r)] = true
		i += 1
	_gen_count = i
	_ready_done = true
	load_game()

# Legacy position key, kept as a fallback for old saves.
func _key(n: Node3D) -> String:
	return "%d_%d" % [roundi(n.global_position.x * 4.0), roundi(n.global_position.z * 4.0)]

func _id(n: Node) -> String:
	if n.has_meta("save_id"):
		return str(n.get_meta("save_id"))
	return ""

func _process(delta: float) -> void:
	_update_new_game_hold(delta)
	if not _ready_done:
		return
	_autosave += delta
	if _autosave >= AUTOSAVE_SECONDS:
		_autosave = 0.0
		save_game(true)

func _update_new_game_hold(delta: float) -> void:
	if Input.is_key_pressed(KEY_F8) and Input.is_key_pressed(KEY_SHIFT):
		_new_game_hold += delta
		var step := int(_new_game_hold)
		if step != _new_game_hint_step and _new_game_hold < NEW_GAME_HOLD:
			_new_game_hint_step = step
			SurvivalState.notification.emit("Keep holding Shift+F8 to start a new game (%d s)" % ceili(NEW_GAME_HOLD - _new_game_hold), Color(1, 0.85, 0.55))
		if _new_game_hold >= NEW_GAME_HOLD:
			_new_game_hold = 0.0
			_new_game_hint_step = -1
			new_game()
	else:
		_new_game_hold = 0.0
		_new_game_hint_step = -1

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _ready_done:
		save_game(true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			save_game(false)

func _state_snapshot() -> Dictionary:
	var st := SurvivalState
	return {"inventory": st.inventory.duplicate(true), "tools": st.tool_durability.duplicate(true), "health": st.health, "hunger": st.hunger, "warmth": st.warmth, "stamina": st.stamina, "day": st.day, "time": st.time_of_day}

func _apply_state(s: Dictionary) -> void:
	var st := SurvivalState
	var inv := {}
	for k in s.get("inventory", {}):
		inv[str(k)] = int(s["inventory"][k])
	st.inventory = inv
	var tools := {}
	for k in s.get("tools", {}):
		tools[str(k)] = int(s["tools"][k])
	if not tools.is_empty():
		st.tool_durability = tools
	st.health = float(s.get("health", st.health))
	st.hunger = float(s.get("hunger", st.hunger))
	st.warmth = float(s.get("warmth", st.warmth))
	st.stamina = float(s.get("stamina", st.stamina))
	st.day = int(s.get("day", st.day))
	st.time_of_day = float(s.get("time", st.time_of_day))
	st.inventory_changed.emit(st.inventory.duplicate())
	st.call("_emit_vitals")
	st.time_changed.emit(st.day, int(st.time_of_day), int(fmod(st.time_of_day, 1.0) * 60.0))

func _stoves() -> Array:
	var out := []
	for n in get_tree().root.find_children("*", "", true, false):
		if n is WoodStove:
			out.append(n)
	return out

func save_game(silent: bool) -> void:
	var data := {"version": VERSION, "gen_count": _gen_count, "state": _state_snapshot()}
	var pl := get_node_or_null("../Player") as Node3D
	if pl:
		data["player"] = [pl.global_position.x, pl.global_position.y, pl.global_position.z, pl.rotation.y]
	var current := {}
	var stumps := []
	var saplings := []
	var grown := []
	var pos_of := {}
	for r in get_tree().get_nodes_in_group("harvestable_resources"):
		if not (r is Node3D) or r.is_queued_for_deletion():
			continue
		var k := _id(r)
		if k != "":
			pos_of[k] = _key(r)
		# A rock or bush that is crumbling right now counts as removed.
		if r.collision_layer == 0 and not bool(r.get("_is_stump")) and r.get("resource_kind") in ["stone", "bush"]:
			continue
		if k != "" and _original.has(k):
			current[k] = true
			if bool(r.get("_is_stump")):
				stumps.append(k)
		elif r.get("resource_kind") == "sapling":
			saplings.append([r.global_position.x, r.global_position.z, float(r.get("_regrow_at_hour"))])
		elif r.get("resource_kind") == "tree":
			grown.append([r.global_position.x, r.global_position.z])
	var removed := []
	for k in _original:
		if not current.has(k):
			removed.append(k)
	data["world"] = {"removed": removed, "stumps": stumps, "saplings": saplings, "grown": grown}
	var stoves := []
	for s in _stoves():
		stoves.append(float(s.fuel_time))
	data["stoves"] = stoves
	data["buildings"] = _save_buildings()
	if not _write_atomic(JSON.stringify(data)):
		SurvivalState.notification.emit("Save failed.", Color(1, 0.4, 0.3))
		return
	if not silent:
		SurvivalState.notification.emit("Game saved.", Color(0.7, 1, 0.7))

func _write_atomic(text: String) -> bool:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	var check = JSON.parse_string(FileAccess.get_file_as_string(TMP_PATH))
	if typeof(check) != TYPE_DICTIONARY:
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(SAVE_PATH.get_file()):
		if dir.file_exists(BAK_PATH.get_file()):
			dir.remove(BAK_PATH.get_file())
		dir.copy(SAVE_PATH.get_file(), BAK_PATH.get_file())
	var err := dir.rename(TMP_PATH.get_file(), SAVE_PATH.get_file())
	if err != OK:
		dir.remove(SAVE_PATH.get_file())
		err = dir.rename(TMP_PATH.get_file(), SAVE_PATH.get_file())
	return err == OK

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data

func _ground_y(x: float, z: float) -> float:
	var ground := get_node_or_null("../Ground")
	if ground and ground.has_method("surface_height"):
		return float(ground.call("surface_height", Vector2(x, z)))
	if ground and ground.has_method("sample_height"):
		return float(ground.call("sample_height", Vector2(x, z)))
	return 0.0

func load_game() -> void:
	if _loaded or not FileAccess.file_exists(SAVE_PATH):
		return
	var data := _read_json(SAVE_PATH)
	if data.is_empty():
		data = _read_json(BAK_PATH)
		if data.is_empty():
			SurvivalState.notification.emit("Save file is damaged and no backup was found.", Color(1, 0.4, 0.3))
			return
		SurvivalState.notification.emit("Save file was damaged - loaded backup.", Color(1, 0.8, 0.4))
	_loaded = true
	_apply_state(data.get("state", {}))
	var pl := get_node_or_null("../Player") as Node3D
	var pp: Array = data.get("player", [])
	if pl and pp.size() == 4:
		pl.global_position = Vector3(pp[0], pp[1] + 0.05, pp[2])
		pl.rotation.y = pp[3]
		if pl is CharacterBody3D:
			(pl as CharacterBody3D).velocity = Vector3.ZERO
	var world: Dictionary = data.get("world", {})
	# Version 2 saves use generation IDs; older saves or a changed world use position keys.
	var use_ids := int(data.get("version", 1)) >= 2 and int(data.get("gen_count", -1)) == _gen_count
	var by_key := {}
	for r in get_tree().get_nodes_in_group("harvestable_resources"):
		if r is Node3D and _original.has(_id(r)):
			by_key[_id(r) if use_ids else _key(r)] = r
	if int(data.get("version", 1)) >= 2 and not use_ids:
		SurvivalState.notification.emit("World layout changed - old world changes were skipped.", Color(1, 0.8, 0.4))
		world = {"saplings": world.get("saplings", []), "grown": world.get("grown", [])}
	for k in world.get("removed", []):
		if by_key.has(k) and is_instance_valid(by_key[k]):
			by_key[k].queue_free()
			by_key.erase(k)
	for k in world.get("stumps", []):
		if by_key.has(k) and by_key[k].has_method("restore_stump"):
			by_key[k].call("restore_stump")
	var field := get_node_or_null("../SurvivalResources")
	if field:
		for s in world.get("saplings", []):
			if field.has_method("plant_sapling"):
				field.call("plant_sapling", Vector3(s[0], _ground_y(s[0], s[1]), s[1]))
				var last := field.get_child(field.get_child_count() - 1)
				if last:
					last.set("_regrow_at_hour", float(s[2]))
		for g in world.get("grown", []):
			if field.has_method("restore_tree_at"):
				field.call("restore_tree_at", Vector3(g[0], 0.0, g[1]))
	var stoves := _stoves()
	var saved_stoves: Array = data.get("stoves", [])
	for i in range(mini(stoves.size(), saved_stoves.size())):
		stoves[i].fuel_time = float(saved_stoves[i])
		if stoves[i].has_method("_update_visual"):
			stoves[i].call("_update_visual")
	_load_buildings(data.get("buildings", {}))
	SurvivalState.notification.emit("Save loaded - day %d." % SurvivalState.day, Color(0.7, 0.9, 1))

# --- Player-built objects: farm beds, fences, gates (unique save_uid meta) ---
func _world_root() -> Node:
	return get_parent()

func _t2a(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]

func _a2t(a) -> Transform3D:
	if not (a is Array) or a.size() != 12:
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))

func _v3(a) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO

func _uid(n: Node) -> String:
	if not n.has_meta("save_uid"):
		n.set_meta("save_uid", "b%d_%d" % [int(Time.get_unix_time_from_system()), randi()])
	return str(n.get_meta("save_uid"))

func _find_bed(root: Node) -> Node:
	if root is PlaceableFarmBed:
		return root
	for c in root.get_children():
		if c is PlaceableFarmBed:
			return c
	return null

func _find_gate(root: Node) -> Node:
	if root is PlaceableGate:
		return root
	for c in root.get_children():
		if c is PlaceableGate:
			return c
	return null

func _script_vars(n: Object) -> Dictionary:
	var out := {}
	for p in n.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var pname := str(p["name"])
		if pname.begins_with("_dismantl"):
			continue
		if int(p["type"]) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			out[pname] = n.get(pname)
	return out

func _apply_vars(n: Object, d) -> void:
	if not (d is Dictionary):
		return
	for k in d:
		var key := str(k)
		var cur = n.get(key)
		if cur == null:
			continue
		match typeof(cur):
			TYPE_BOOL:
				n.set(key, bool(d[k]))
			TYPE_INT:
				n.set(key, int(d[k]))
			TYPE_FLOAT:
				n.set(key, float(d[k]))
			TYPE_STRING:
				n.set(key, str(d[k]))

func _save_buildings() -> Dictionary:
	var beds := []
	var gates := []
	var fences := []
	var root := _world_root()
	if root == null:
		return {}
	for n in root.get_children():
		if not (n is Node3D) or n.is_queued_for_deletion() or String(n.name).to_lower().contains("preview"):
			continue
		if n.has_meta("fence_ends"):
			var e: Array = n.get_meta("fence_ends")
			var a: Vector3 = e[0]
			var f: Vector3 = e[1]
			fences.append({"id": _uid(n), "a": [a.x, a.y, a.z], "b": [f.x, f.y, f.z], "rustic": bool(e[2])})
			continue
		var bed := _find_bed(n)
		if bed:
			beds.append({"id": _uid(n), "t": _t2a((n as Node3D).global_transform), "vars": _script_vars(bed)})
			continue
		var gate := _find_gate(n)
		if gate:
			gates.append({"id": _uid(n), "t": _t2a((n as Node3D).global_transform), "wicket": String(n.name).to_lower().contains("wicket"), "vars": _script_vars(gate)})
	return {"beds": beds, "gates": gates, "fences": fences}

func _load_buildings(b) -> void:
	var root := _world_root()
	if root == null or not (b is Dictionary):
		return
	var ground := get_node_or_null("../Ground")
	var used := {}
	for e in b.get("fences", []):
		var id := str(e.get("id", ""))
		var a := _v3(e.get("a", []))
		var f := _v3(e.get("b", []))
		if used.has(id) or a.distance_to(f) < 0.05:
			continue
		used[id] = true
		var rustic := bool(e.get("rustic", false))
		var fence: Node3D = RusticFenceBuilder.create_between(a, f, ground) if rustic else FenceBuilder.create_between(a, f, ground)
		root.add_child(fence)
		fence.set_meta("fence_ends", [a, f, rustic])
		fence.set_meta("save_uid", id)
	for e in b.get("beds", []):
		var id := str(e.get("id", ""))
		if used.has(id):
			continue
		used[id] = true
		var bed_root: Node3D = FarmBedBuilder.create_bed()
		root.add_child(bed_root)
		bed_root.global_transform = _a2t(e.get("t", []))
		bed_root.set_meta("save_uid", id)
		var bed := _find_bed(bed_root)
		if bed:
			_apply_vars(bed, e.get("vars", {}))
			if bed.has_method("_update_plants"):
				bed.call("_update_plants")
	for e in b.get("gates", []):
		var id := str(e.get("id", ""))
		if used.has(id):
			continue
		used[id] = true
		var gate_root: Node3D = GateBuilder.create_wicket() if bool(e.get("wicket", false)) else GateBuilder.create_gate()
		root.add_child(gate_root)
		gate_root.global_transform = _a2t(e.get("t", []))
		gate_root.set_meta("save_uid", id)
		var gate := _find_gate(gate_root)
		if gate:
			_apply_vars(gate, e.get("vars", {}))

func new_game() -> void:
	for p in [SAVE_PATH, TMP_PATH, BAK_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_ready_done = false
	if SurvivalState.has_meta("defaults"):
		_apply_state(SurvivalState.get_meta("defaults"))
	get_tree().reload_current_scene()
