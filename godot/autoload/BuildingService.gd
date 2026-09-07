extends Node
## M4/M6: Harbor 200/20, Factory 150/15, Road 40/5 (mobility 0.6), Bunker stub.

signal changed

const STRUCTURES := ["Harbor", "Factory", "Bunker"]
const INFRA := ["Road", "Rail"]

var pending: Dictionary = {} ## cell_id -> {kind, ticks_left, owner}
var completed: Dictionary = {} ## cell_id -> Array[{kind, owner}]
var _acc: float = 0.0


func _ready() -> void:
	if MapService != null and not MapService.theater_loaded.is_connected(_on_theater_loaded):
		MapService.theater_loaded.connect(_on_theater_loaded)


func _on_theater_loaded(_theater_id: String) -> void:
	reset()


func reset() -> void:
	pending.clear()
	completed.clear()
	_acc = 0.0
	changed.emit()


func tick(dt: float) -> void:
	if pending.is_empty():
		_acc = 0.0
		return
	var step := Balance.tick_sec() if Balance != null else 1.0
	_acc += dt
	var dirty := false
	while _acc >= step:
		_acc -= step
		if _advance_one_tick():
			dirty = true
	if dirty:
		changed.emit()


func _advance_one_tick() -> bool:
	var dirty := false
	var done: Array = []
	for cid in pending.keys():
		var rec: Dictionary = pending[cid]
		rec["ticks_left"] = int(rec.get("ticks_left", 1)) - 1
		pending[cid] = rec
		if int(rec["ticks_left"]) <= 0:
			done.append(str(cid))
	for cid in done:
		var rec: Dictionary = pending[cid]
		pending.erase(cid)
		_finish(str(cid), rec)
		dirty = true
	return dirty


func _finish(cell_id: String, rec: Dictionary) -> void:
	var kind := str(rec.get("kind", ""))
	var owner := str(rec.get("owner", "player"))
	if not completed.has(cell_id):
		completed[cell_id] = []
	var list: Array = completed[cell_id]
	list.append({"kind": kind, "owner": owner})
	if kind == "Road" or kind == "Rail":
		_set_cell_infra(cell_id, kind)


func _set_cell_infra(cell_id: String, kind: String) -> void:
	if MapService == null or not MapService.cells.has(cell_id):
		return
	var cell: Dictionary = MapService.cells[cell_id]
	cell["infra"] = kind
	MapService.cells[cell_id] = cell


func can_build(kind: String, cell_id: String, faction: String = "player") -> String:
	if cell_id.is_empty() or MapService == null or not MapService.cells.has(cell_id):
		return "no_cell"
	var def: Dictionary = Balance.building_def(kind) if Balance != null else {}
	if def.is_empty():
		return "unknown"
	var cell: Dictionary = MapService.get_cell(cell_id)
	if str(cell.get("terrain_tag", "")) == "water":
		return "water"
	if _owner_of(cell_id) != faction:
		return "not_owned"
	if pending.has(cell_id):
		return "busy"
	if has_complete(cell_id, kind):
		return "exists"
	if STRUCTURES.has(kind) and _has_structure(cell_id):
		return "occupied"
	if kind == "Harbor" and not bool(cell.get("harbor_site", false)) and not bool(cell.get("is_coast", false)):
		return "not_coast"
	if EconomyService != null and not EconomyService.can_afford(Balance.building_cost(kind)):
		return "no_supply"
	return "ok"


func start_build(kind: String, cell_id: String, faction: String = "player") -> bool:
	if can_build(kind, cell_id, faction) != "ok":
		return false
	var cost := Balance.building_cost(kind)
	if EconomyService != null and not EconomyService.spend(cost, kind):
		return false
	pending[cell_id] = {
		"kind": kind,
		"ticks_left": Balance.building_ticks(kind),
		"owner": faction,
	}
	changed.emit()
	return true


func has_complete(cell_id: String, kind: String) -> bool:
	for rec in completed.get(cell_id, []):
		if typeof(rec) == TYPE_DICTIONARY and str(rec.get("kind", "")) == kind:
			return true
	return false


func _has_structure(cell_id: String) -> bool:
	for rec in completed.get(cell_id, []):
		if typeof(rec) == TYPE_DICTIONARY and STRUCTURES.has(str(rec.get("kind", ""))):
			return true
	return false


func count_complete(kind: String, faction: String = "player") -> int:
	var n := 0
	for cid in completed.keys():
		if _owner_of(str(cid)) != faction:
			continue
		for rec in completed[cid]:
			if typeof(rec) == TYPE_DICTIONARY and str(rec.get("kind", "")) == kind:
				n += 1
	return n


func kinds_on(cell_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for rec in completed.get(cell_id, []):
		if typeof(rec) == TYPE_DICTIONARY:
			out.append(str(rec.get("kind", "")))
	if pending.has(cell_id):
		out.append("%s…" % str(pending[cell_id].get("kind", "")))
	return out


func pending_on(cell_id: String) -> Dictionary:
	return pending.get(cell_id, {})


func _owner_of(cell_id: String) -> String:
	if OwnershipService != null:
		return OwnershipService.get_cell_owner(cell_id)
	if MapService != null:
		return MapService.get_cell_owner(cell_id)
	return "none"
