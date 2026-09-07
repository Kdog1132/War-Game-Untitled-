extends Node
## M1/M5: one local player army. Spawn on stub_med c_0_0. Select, A* path, hop, ferry.
## Uses get_cell_owner / Pathfinder — never Node.get_owner.

const PLAYER_ID := "a_player_1"
const HOME_CELL := "c_0_0"
const DEFAULT_STRENGTH := 100.0

signal changed

const PathfinderScript := preload("res://map/Pathfinder.gd")

var armies: Dictionary = {} ## army_id -> Dictionary
var selected_id: String = ""


func reset_for_theater() -> void:
	armies.clear()
	selected_id = ""
	var home := HOME_CELL
	if MapService.loaded and not MapService.cells.has(home):
		home = _first_player_cell()
	if home.is_empty():
		changed.emit()
		return
	spawn(PLAYER_ID, "player", home, DEFAULT_STRENGTH)
	changed.emit()


func spawn(army_id: String, faction: String, cell_id: String, strength: float = DEFAULT_STRENGTH) -> void:
	armies[army_id] = {
		"army_id": army_id,
		"faction": faction,
		"cell_id": cell_id,
		"selected": army_id == selected_id,
		"path": [],
		"remaining": [],
		"hop_left": 0.0,
		"moving": false,
		"at_sea": false,
		"strength": strength,
	}
	changed.emit()


func player() -> Dictionary:
	return armies.get(PLAYER_ID, {})


func player_cell() -> String:
	return str(player().get("cell_id", ""))


func is_selected() -> bool:
	return selected_id == PLAYER_ID and not player().is_empty()


func select_player() -> void:
	if player().is_empty():
		return
	selected_id = PLAYER_ID
	armies[PLAYER_ID]["selected"] = true
	changed.emit()


func deselect() -> void:
	selected_id = ""
	if armies.has(PLAYER_ID):
		armies[PLAYER_ID]["selected"] = false
	changed.emit()


func army_at(cell_id: String) -> String:
	for aid in armies.keys():
		var rec: Dictionary = armies[aid]
		if bool(rec.get("at_sea", false)):
			continue
		if str(rec.get("cell_id", "")) == cell_id:
			return str(aid)
	return ""


func set_at_sea(army_id: String, at_sea: bool) -> void:
	if not armies.has(army_id):
		return
	armies[army_id]["at_sea"] = at_sea
	if at_sea:
		armies[army_id]["cell_id"] = ""
		armies[army_id]["path"] = []
	changed.emit()


func land_from_sea(army_id: String, cell_id: String) -> void:
	if not armies.has(army_id):
		return
	armies[army_id]["at_sea"] = false
	armies[army_id]["cell_id"] = cell_id
	armies[army_id]["path"] = []
	changed.emit()


func try_click(cell_id: String) -> String:
	if cell_id.is_empty():
		return "empty"
	var rec: Dictionary = player()
	if rec.is_empty():
		return "ignored"
	if bool(rec.get("at_sea", false)):
		return "at_sea"
	if army_at(cell_id) == PLAYER_ID:
		select_player()
		return "selected"
	if not is_selected():
		return "ignored"
	if ShippingService != null:
		var dest_node := ShippingService.harbor_node_for_cell(cell_id)
		if not dest_node.is_empty() and ShippingService.can_ferry(PLAYER_ID, dest_node) == "ok":
			var ferry: Dictionary = ShippingService.start_ferry(PLAYER_ID, dest_node)
			if not ferry.is_empty():
				return "ferried"
	if order_move(cell_id):
		return "moved"
	return "no_path"


func order_move(to_cell: String) -> bool:
	var a: Dictionary = player()
	if a.is_empty() or bool(a.get("at_sea", false)):
		return false
	var from_id := str(a.get("cell_id", ""))
	var result: Dictionary = PathfinderScript.find_path(from_id, to_cell)
	if not bool(result.get("ok", false)):
		return false
	var cells: Array = result.get("cells", [])
	if cells.is_empty():
		return false
	var remaining: Array = cells.duplicate()
	if not remaining.is_empty() and str(remaining[0]) == from_id:
		remaining.pop_front()
	armies[PLAYER_ID]["path"] = cells.duplicate()
	# Discrete hop: snap along the path to the goal in one order.
	while not remaining.is_empty():
		armies[PLAYER_ID]["cell_id"] = str(remaining.pop_front())
	armies[PLAYER_ID]["remaining"] = []
	armies[PLAYER_ID]["moving"] = false
	armies[PLAYER_ID]["hop_left"] = 0.0
	changed.emit()
	return true


func process_hops(_delta: float) -> void:
	pass


func world_pos(army_id: String = PLAYER_ID) -> Vector2:
	var a: Dictionary = armies.get(army_id, {})
	if bool(a.get("at_sea", false)) and ShippingService != null:
		var ferry: Dictionary = ShippingService.ferry_for_army(army_id)
		if not ferry.is_empty() and MapService != null:
			var a_id := MapService.harbor_cell_id(str(ferry.get("from", "")))
			var b_id := MapService.harbor_cell_id(str(ferry.get("to", "")))
			var eta := maxf(float(ferry.get("eta", 1.0)), 0.0001)
			var t := 1.0 - clampf(float(ferry.get("remaining", 0.0)) / eta, 0.0, 1.0)
			return MapService.cell_world_pos(a_id).lerp(MapService.cell_world_pos(b_id), t)
	var cid := str(a.get("cell_id", ""))
	if cid.is_empty():
		return Vector2.ZERO
	return MapService.cell_world_pos(cid)


func last_path() -> Array:
	return player().get("path", [])


func _first_player_cell() -> String:
	for cid in MapService.cells.keys():
		if MapService.get_cell_owner(str(cid)) == "player":
			return str(cid)
	return ""
