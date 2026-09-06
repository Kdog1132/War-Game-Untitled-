class_name Army
extends RefCounted
## One local player army. Click-to-move follows a Pathfinder A* cell list.
## Edge duration = Forge enter_time_sec of the destination hex.

var army_id: String = "a_player_1"
var faction: String = "player"
var cell_id: String = ""
var selected: bool = false
var moving: bool = false
var from_cell: String = ""
var to_cell: String = ""
var travel: float = 0.0
var edge_sec: float = 1.0
var remaining: Array = [] ## cell_ids still to enter
var last_path: Array = []
var last_cost: float = 0.0


func _map() -> Node:
	return Engine.get_main_loop().root.get_node("MapService")


func _balance() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Balance")


func place(on_cell: String) -> void:
	cell_id = on_cell
	from_cell = on_cell
	to_cell = ""
	remaining.clear()
	moving = false
	travel = 0.0
	last_path.clear()
	last_cost = 0.0


func order_path(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	var cells: Array = result.get("cells", [])
	if cells.is_empty():
		return false
	last_path = cells.duplicate()
	last_cost = float(result.get("cost", 0.0))
	remaining = cells.duplicate()
	if not remaining.is_empty() and str(remaining[0]) == cell_id:
		remaining.pop_front()
	_begin_edge()
	return true


func tick(delta: float) -> void:
	if not moving:
		return
	if edge_sec <= 0.001:
		_arrive()
		return
	travel += delta / edge_sec
	if travel >= 1.0:
		_arrive()


func world_pos() -> Vector2:
	var ms := _map()
	if moving and not to_cell.is_empty():
		var a: Vector2 = ms.call("cell_world_pos", from_cell)
		var b: Vector2 = ms.call("cell_world_pos", to_cell)
		return a.lerp(b, clampf(travel, 0.0, 1.0))
	return ms.call("cell_world_pos", cell_id)


func _begin_edge() -> void:
	if remaining.is_empty():
		moving = false
		to_cell = ""
		return
	from_cell = cell_id
	to_cell = str(remaining.pop_front())
	var ms := _map()
	var cell: Dictionary = ms.call("get_cell", to_cell)
	var tag := str(cell.get("terrain_tag", "plains"))
	var et: Variant = ms.call("enter_time_for", tag)
	edge_sec = float(et) if et != null else 1.0
	var bal := _balance()
	if bal != null and bool(bal.get("loaded")):
		edge_sec *= float(bal.call("mobility_mult", "none"))
	travel = 0.0
	moving = true


func _arrive() -> void:
	cell_id = to_cell
	from_cell = to_cell
	travel = 0.0
	_begin_edge()
