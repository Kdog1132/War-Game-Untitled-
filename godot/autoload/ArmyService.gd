extends Node
## M1: one local player army. Spawn on stub_med c_0_0. Select, A* path, hop.
## Uses get_cell_owner / Pathfinder — never Node.get_owner.

const PLAYER_ID := "a_player_1"
const HOME_CELL := "c_0_0"

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
	armies[PLAYER_ID] = {
		"army_id": PLAYER_ID,
		"faction": "player",
		"cell_id": home,
		"selected": false,
		"path": [],
		"remaining": [],
		"hop_left": 0.0,
		"moving": false,
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
		if str(armies[aid].get("cell_id", "")) == cell_id:
			return str(aid)
	return ""


func try_click(cell_id: String) -> String:
	if cell_id.is_empty():
		return "empty"
	if army_at(cell_id) == PLAYER_ID:
		select_player()
		return "selected"
	if not is_selected():
		return "ignored"
	if order_move(cell_id):
		return "moved"
	return "no_path"


func order_move(to_cell: String) -> bool:
	var a: Dictionary = player()
	if a.is_empty():
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
