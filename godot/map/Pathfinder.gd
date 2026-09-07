class_name Pathfinder
extends RefCounted
## A* over MapService adjacency.
## Step cost = enter_time_sec(terrain) * mobility_mult(infra). Water / null is skipped.
## Resolves autoloads from the scene tree so this script compiles under --script too.

const NO_PATH := {"ok": false, "cells": [], "cost": INF}


static func _map() -> Node:
	return Engine.get_main_loop().root.get_node("MapService")


static func _balance() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("Balance")


static func enter_cost(cell_id: String) -> Variant:
	var ms := _map()
	var cell: Dictionary = ms.call("get_cell", cell_id)
	if cell.is_empty():
		return null
	var tag := str(cell.get("terrain_tag", ""))
	if tag == "water":
		return null
	var et: Variant = ms.call("enter_time_for", tag)
	if et == null:
		return null
	var bal := _balance()
	var mob := _mobility_kind(cell)
	var mult := 1.0
	if bal != null and bool(bal.get("loaded")):
		mult = float(bal.call("mobility_mult", mob))
	return float(et) * mult


static func _mobility_kind(cell: Dictionary) -> String:
	var infra := str(cell.get("infra", cell.get("mobility", "none")))
	if infra.is_empty():
		return "none"
	return infra


static func is_passable(cell_id: String) -> bool:
	var cost: Variant = enter_cost(cell_id)
	return cost != null and float(cost) >= 0.0


static func find_path(start_id: String, goal_id: String) -> Dictionary:
	var ms := _map()
	if start_id.is_empty() or goal_id.is_empty():
		return NO_PATH.duplicate()
	if start_id == goal_id:
		return {"ok": true, "cells": [start_id], "cost": 0.0}
	var cells: Dictionary = ms.get("cells")
	if not cells.has(start_id) or not cells.has(goal_id):
		return NO_PATH.duplicate()
	if not is_passable(goal_id):
		return NO_PATH.duplicate()

	var h_scale := _heuristic_scale()
	var open: Array = [start_id]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_id: 0.0}
	var f_score: Dictionary = {
		start_id: float(ms.call("hex_distance", start_id, goal_id)) * h_scale
	}
	var closed: Dictionary = {}

	while not open.is_empty():
		var current := _pop_lowest(open, f_score)
		if current == goal_id:
			return {"ok": true, "cells": _reconstruct(came_from, current), "cost": float(g_score[current])}
		closed[current] = true
		for raw_n in ms.call("neighbors", current):
			var nxt := str(raw_n)
			if closed.has(nxt):
				continue
			if not is_passable(nxt):
				continue
			var step: Variant = enter_cost(nxt)
			var tentative := float(g_score[current]) + float(step)
			if tentative < float(g_score.get(nxt, INF)):
				came_from[nxt] = current
				g_score[nxt] = tentative
				f_score[nxt] = tentative + float(ms.call("hex_distance", nxt, goal_id)) * h_scale
				if not open.has(nxt):
					open.append(nxt)
	return NO_PATH.duplicate()


static func _heuristic_scale() -> float:
	var bal := _balance()
	var et: Dictionary = {}
	if bal != null and bool(bal.get("loaded")):
		var data: Dictionary = bal.get("data")
		et = data.get("enter_time_sec", {})
	var best := 2.0
	var have := false
	for key in et.keys():
		var val: Variant = et[key]
		if val == null:
			continue
		var n := float(val)
		if n < 0.0:
			continue
		if not have or n < best:
			best = n
			have = true
	return best if have else 2.0


static func _pop_lowest(open: Array, f_score: Dictionary) -> String:
	var best_i := 0
	var best_f := float(f_score.get(open[0], INF))
	for i in range(1, open.size()):
		var f := float(f_score.get(open[i], INF))
		if f < best_f:
			best_f = f
			best_i = i
	return str(open.pop_at(best_i))


static func _reconstruct(came_from: Dictionary, current: String) -> Array:
	var path: Array = [current]
	while came_from.has(current):
		current = str(came_from[current])
		path.push_front(current)
	return path
