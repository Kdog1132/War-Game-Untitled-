extends Node
## M5: Forge lane control (Open / Contested / Blocked) + Harbor→Harbor ferry.

signal changed
signal ferry_started(ferry: Dictionary)
signal ferry_arrived(ferry: Dictionary)

var ferries: Dictionary = {} ## ferry_id -> Dictionary
var _ferry_seq: int = 0


func _ready() -> void:
	if MapService != null and not MapService.theater_loaded.is_connected(_on_theater_loaded):
		MapService.theater_loaded.connect(_on_theater_loaded)
	if OwnershipService != null and not OwnershipService.changed.is_connected(_on_owners_changed):
		OwnershipService.changed.connect(_on_owners_changed)


func _on_theater_loaded(_theater_id: String) -> void:
	reset()


func _on_owners_changed() -> void:
	refresh_lane_control()


func reset() -> void:
	ferries.clear()
	_ferry_seq = 0
	refresh_lane_control()
	changed.emit()


func tick(dt: float) -> void:
	refresh_lane_control()
	if ferries.is_empty() or dt <= 0.0:
		return
	var arrived: Array = []
	for fid in ferries.keys():
		var rec: Dictionary = ferries[fid]
		var lane := _lane_by_id(str(rec.get("lane_id", "")))
		var state := str(lane.get("state", rec.get("state", "Open")))
		if state == "Blocked" or Balance.sea_transit_sec(state) == null:
			continue
		rec["remaining"] = float(rec.get("remaining", 0.0)) - dt
		rec["state"] = state
		ferries[fid] = rec
		if float(rec["remaining"]) <= 0.0001:
			arrived.append(str(fid))
	for fid in arrived:
		var rec: Dictionary = ferries[fid]
		ferries.erase(fid)
		_land_ferry(rec)
		ferry_arrived.emit(rec)
	if not arrived.is_empty():
		changed.emit()


func refresh_lane_control() -> void:
	if MapService == null:
		return
	var dirty := false
	for i in range(MapService.lanes.size()):
		var lane: Dictionary = MapService.lanes[i]
		var next_state := classify_lane(lane)
		if str(lane.get("state", "")) != next_state:
			lane["state"] = next_state
			MapService.lanes[i] = lane
			dirty = true
		elif not lane.has("state"):
			lane["state"] = next_state
			MapService.lanes[i] = lane
			dirty = true
	if dirty:
		changed.emit()


func classify_lane(lane: Dictionary) -> String:
	var a_id := MapService.harbor_cell_id(str(lane.get("a", "")))
	var b_id := MapService.harbor_cell_id(str(lane.get("b", "")))
	var a_own := _owner_of(a_id)
	var b_own := _owner_of(b_id)
	var cfg: Dictionary = Balance.lane_control() if Balance != null else {}
	if bool(cfg.get("block_if_port_closed", true)) and (_port_closed_for_node(str(lane.get("a", ""))) or _port_closed_for_node(str(lane.get("b", "")))):
		return "Blocked"
	var enemy_ends := 0
	if a_own == "enemy":
		enemy_ends += 1
	if b_own == "enemy":
		enemy_ends += 1
	if bool(cfg.get("block_if_both_ends_enemy", true)) and enemy_ends >= 2:
		return "Blocked"
	if bool(cfg.get("contest_if_one_end_enemy", true)) and enemy_ends == 1:
		return "Contested"
	return "Open"


func lane_state(lane_id: String) -> String:
	var lane := _lane_by_id(lane_id)
	return str(lane.get("state", "Open"))


func lane_hud() -> String:
	if MapService == null:
		return ""
	var bits: PackedStringArray = []
	for lane in MapService.lanes:
		bits.append("%s %s" % [str(lane.get("lane_id", "?")), str(lane.get("state", "Open"))])
	return "   ".join(bits)


func can_ferry(army_id: String, to_node: String) -> String:
	if ArmyService == null or not ArmyService.armies.has(army_id):
		return "no_army"
	var army: Dictionary = ArmyService.armies[army_id]
	if bool(army.get("at_sea", false)):
		return "at_sea"
	var from_cell := str(army.get("cell_id", ""))
	var from_node := harbor_node_for_cell(from_cell)
	if from_node.is_empty():
		return "not_harbor"
	if to_node.is_empty() or to_node == from_node:
		return "bad_dest"
	var lane := _lane_between(from_node, to_node)
	if lane.is_empty():
		return "no_lane"
	var state := str(lane.get("state", "Open"))
	if state == "Blocked" or Balance.sea_transit_sec(state) == null:
		return "blocked"
	return "ok"


func start_ferry(army_id: String, to_node: String) -> Dictionary:
	if can_ferry(army_id, to_node) != "ok":
		return {}
	var army: Dictionary = ArmyService.armies[army_id]
	var from_node := harbor_node_for_cell(str(army.get("cell_id", "")))
	var lane := _lane_between(from_node, to_node)
	var state := str(lane.get("state", "Open"))
	var eta: Variant = Balance.sea_transit_sec(state)
	_ferry_seq += 1
	var fid := "f_%d" % _ferry_seq
	var rec := {
		"ferry_id": fid,
		"army_id": army_id,
		"from": from_node,
		"to": to_node,
		"lane_id": str(lane.get("lane_id", "")),
		"state": state,
		"remaining": float(eta),
		"eta": float(eta),
	}
	ferries[fid] = rec
	ArmyService.set_at_sea(army_id, true)
	ferry_started.emit(rec)
	changed.emit()
	return rec


func ferry_for_army(army_id: String) -> Dictionary:
	for rec in ferries.values():
		if typeof(rec) == TYPE_DICTIONARY and str(rec.get("army_id", "")) == army_id:
			return rec
	return {}


func harbor_node_for_cell(cell_id: String) -> String:
	if cell_id.is_empty() or MapService == null:
		return ""
	var nodes: Array = MapService.shipping_graph.get("nodes", [])
	for node in nodes:
		if typeof(node) == TYPE_DICTIONARY and str(node.get("cell_id", "")) == cell_id:
			return str(node.get("harbor_node_id", ""))
	var cell: Dictionary = MapService.get_cell(cell_id)
	return str(cell.get("harbor_node_id", ""))


func other_harbors(from_node: String) -> Array:
	var out: Array = []
	if MapService == null:
		return out
	for lane in MapService.lanes:
		var a := str(lane.get("a", ""))
		var b := str(lane.get("b", ""))
		if a == from_node and not out.has(b):
			out.append(b)
		elif b == from_node and not out.has(a):
			out.append(a)
	return out


func _land_ferry(rec: Dictionary) -> void:
	var to_cell := MapService.harbor_cell_id(str(rec.get("to", "")))
	if ArmyService != null:
		ArmyService.land_from_sea(str(rec.get("army_id", "")), to_cell)


func _lane_between(a: String, b: String) -> Dictionary:
	if MapService == null:
		return {}
	for lane in MapService.lanes:
		var la := str(lane.get("a", ""))
		var lb := str(lane.get("b", ""))
		if (la == a and lb == b) or (la == b and lb == a):
			return lane
	return {}


func _lane_by_id(lane_id: String) -> Dictionary:
	if MapService == null:
		return {}
	for lane in MapService.lanes:
		if str(lane.get("lane_id", "")) == lane_id:
			return lane
	return {}


func _port_closed_for_node(node_id: String) -> bool:
	if MapService == null:
		return false
	for port in MapService.ports.values():
		if typeof(port) != TYPE_DICTIONARY:
			continue
		if str(port.get("harbor_node_id", "")) != node_id:
			continue
		if bool(port.get("closed", false)):
			return true
		if str(port.get("state", "")).to_lower() == "closed":
			return true
	return false


func _owner_of(cell_id: String) -> String:
	if cell_id.is_empty():
		return "none"
	if OwnershipService != null:
		return OwnershipService.get_cell_owner(cell_id)
	if MapService == null:
		return "none"
	return MapService.get_cell_owner(cell_id)
