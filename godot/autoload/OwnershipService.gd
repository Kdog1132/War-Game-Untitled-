extends Node
## M2: runtime cell owners. Seed from ownership_seed; tint via WorldMap.
## Public API is get_cell_owner / set_cell_owner — never get_owner (Node clash).

signal changed

var owners: Dictionary = {} ## cell_id -> player|enemy|none


func _ready() -> void:
	if MapService != null and not MapService.theater_loaded.is_connected(_on_theater_loaded):
		MapService.theater_loaded.connect(_on_theater_loaded)
	if MapService != null and MapService.loaded:
		reset_from_theater()


func _on_theater_loaded(_theater_id: String) -> void:
	reset_from_theater()


func reset_from_theater() -> void:
	owners.clear()
	if MapService == null or MapService.cells.is_empty():
		changed.emit()
		return
	var seed_owners: Dictionary = MapService.ownership_seed.get("cell_owners", {})
	for cid in MapService.cells.keys():
		var cell: Dictionary = MapService.get_cell(str(cid))
		var owner := _norm_owner(cell.get("default_owner", "none"))
		if seed_owners.has(cid):
			owner = _norm_owner(seed_owners[cid])
		owners[str(cid)] = owner
		MapService.cell_owners[str(cid)] = owner
	changed.emit()


func get_cell_owner(cell_id: String) -> String:
	if owners.has(cell_id):
		return str(owners[cell_id])
	if MapService != null and MapService.cell_owners.has(cell_id):
		return str(MapService.cell_owners[cell_id])
	if MapService != null:
		var cell: Dictionary = MapService.get_cell(cell_id)
		return _norm_owner(cell.get("default_owner", "none"))
	return "none"


func set_cell_owner(cell_id: String, owner: String) -> void:
	if MapService != null and not MapService.cells.has(cell_id):
		return
	var norm := _norm_owner(owner)
	if owners.get(cell_id, "") == norm:
		return
	owners[cell_id] = norm
	if MapService != null:
		MapService.cell_owners[cell_id] = norm
	changed.emit()


func counts() -> Dictionary:
	var out := {"player": 0, "none": 0, "enemy": 0, "P": 0, "N": 0, "E": 0}
	var ids: Array = owners.keys()
	if ids.is_empty() and MapService != null:
		ids = MapService.cells.keys()
	for cid in ids:
		var owner := get_cell_owner(str(cid))
		match owner:
			"player":
				out["player"] += 1
			"enemy":
				out["enemy"] += 1
			_:
				out["none"] += 1
	out["P"] = out["player"]
	out["N"] = out["none"]
	out["E"] = out["enemy"]
	return out


func counts_hud() -> String:
	var c := counts()
	return "P:%d N:%d E:%d" % [int(c["P"]), int(c["N"]), int(c["E"])]


func _norm_owner(value: Variant) -> String:
	var s := str(value).to_lower()
	if s == "player" or s == "enemy":
		return s
	return "none"
