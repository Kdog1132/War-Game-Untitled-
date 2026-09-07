extends Node
## M3: Forge annex rates. Flip at 100. Tint lerp lives on WorldMap.

signal changed
signal flipped(cell_id: String, owner: String)

## cell_id -> {progress: float 0-100, faction: String}
var meters: Dictionary = {}


func _ready() -> void:
	if MapService != null and not MapService.theater_loaded.is_connected(_on_theater_loaded):
		MapService.theater_loaded.connect(_on_theater_loaded)


func _on_theater_loaded(_theater_id: String) -> void:
	reset()


func reset() -> void:
	meters.clear()
	changed.emit()


func meter(cell_id: String) -> float:
	var rec: Dictionary = meters.get(cell_id, {})
	return float(rec.get("progress", 0.0))


func claiming_faction(cell_id: String) -> String:
	var rec: Dictionary = meters.get(cell_id, {})
	return str(rec.get("faction", ""))


func tint_factor(cell_id: String) -> float:
	return clampf(meter(cell_id) / 100.0, 0.0, 1.0)


func tick(dt: float) -> void:
	if MapService == null or not MapService.loaded or dt <= 0.0:
		return
	var dirty := false
	var flips: Array = []
	for cid in MapService.cells.keys():
		var cell_id := str(cid)
		if _is_water(cell_id):
			continue
		if _tick_cell(cell_id, dt, flips):
			dirty = true
	for pair in flips:
		var cell_id := str(pair[0])
		var owner := str(pair[1])
		_set_owner(cell_id, owner)
		meters.erase(cell_id)
		flipped.emit(cell_id, owner)
		dirty = true
	if dirty:
		changed.emit()


func _tick_cell(cell_id: String, dt: float, flips: Array) -> bool:
	var owner := _owner_of(cell_id)
	var occ := _occupiers(cell_id)
	var rec: Dictionary = meters.get(cell_id, {"progress": 0.0, "faction": ""})
	var progress := float(rec.get("progress", 0.0))
	var faction := str(rec.get("faction", ""))

	var claimer := _claimer(occ, owner)
	if claimer != "":
		if faction != "" and faction != claimer:
			progress = 0.0
		faction = claimer
		if _paused(occ, claimer):
			meters[cell_id] = {"progress": progress, "faction": faction}
			return progress > 0.0
		var strength := float(occ.get(claimer, 0.0))
		var rate := annex_rate_pct(owner, strength)
		progress = minf(100.0, progress + rate * dt)
		if progress >= _flip_at() - 0.0001:
			flips.append([cell_id, claimer])
			meters[cell_id] = {"progress": 100.0, "faction": faction}
			return true
		meters[cell_id] = {"progress": progress, "faction": faction}
		return true

	if progress <= 0.0:
		if meters.has(cell_id):
			meters.erase(cell_id)
			return true
		return false

	var decay := _vacate_decay()
	progress = maxf(0.0, progress - decay * dt)
	if progress <= 0.0001:
		meters.erase(cell_id)
	else:
		meters[cell_id] = {"progress": progress, "faction": faction}
	return true


## Seconds to flip, or -1 if not annexing. INF if paused / no rate.
func eta_sec(cell_id: String) -> float:
	var progress := meter(cell_id)
	var owner := _owner_of(cell_id)
	var occ := _occupiers(cell_id)
	var claimer := claiming_faction(cell_id)
	if claimer == "":
		claimer = _claimer(occ, owner)
	if claimer == "":
		return -1.0
	if _paused(occ, claimer):
		return INF
	var strength := float(occ.get(claimer, 0.0))
	var rate := annex_rate_pct(owner, strength)
	if rate <= 0.001:
		return INF
	return maxf(0.0, (_flip_at() - progress) / rate)


func annex_rate_pct(owner: String, strength: float) -> float:
	var cfg: Dictionary = Balance.annex_cfg() if Balance != null else {}
	if owner == "none":
		var base := float(cfg.get("unclaimed_base_pct", 12))
		var scale := float(cfg.get("unclaimed_str_scale", 0.02))
		var cap := float(cfg.get("unclaimed_str_cap", 8))
		return base + minf(cap, scale * strength)
	if owner == "enemy" or owner == "player":
		var base_e := float(cfg.get("enemy_empty_base_pct", 5))
		var scale_e := float(cfg.get("enemy_empty_str_scale", 0.015))
		var cap_e := float(cfg.get("enemy_empty_str_cap", 5))
		return base_e + minf(cap_e, scale_e * strength)
	return 0.0


func _vacate_decay() -> float:
	var cfg: Dictionary = Balance.annex_cfg() if Balance != null else {}
	return float(cfg.get("vacate_decay_pct", 25))


func _flip_at() -> float:
	var cfg: Dictionary = Balance.annex_cfg() if Balance != null else {}
	return float(cfg.get("flip_at", 100))


func _claimer(occ: Dictionary, owner: String) -> String:
	for faction in occ.keys():
		if str(faction) != owner and float(occ[faction]) > 0.0:
			return str(faction)
	return ""


func _paused(occ: Dictionary, claimer: String) -> bool:
	for faction in occ.keys():
		if str(faction) != claimer and float(occ[faction]) > 0.0:
			return true
	return false


func _occupiers(cell_id: String) -> Dictionary:
	var out := {}
	if ArmyService == null:
		return out
	for aid in ArmyService.armies.keys():
		var rec: Dictionary = ArmyService.armies[aid]
		if bool(rec.get("at_sea", false)):
			continue
		if str(rec.get("cell_id", "")) != cell_id:
			continue
		var faction := str(rec.get("faction", "player"))
		var strength := float(rec.get("strength", 100.0))
		out[faction] = float(out.get(faction, 0.0)) + strength
	return out


func _is_water(cell_id: String) -> bool:
	if MapService == null:
		return false
	var cell: Dictionary = MapService.get_cell(cell_id)
	return str(cell.get("terrain_tag", "")) == "water"


func _owner_of(cell_id: String) -> String:
	if OwnershipService != null:
		return OwnershipService.get_cell_owner(cell_id)
	if MapService != null:
		return MapService.get_cell_owner(cell_id)
	return "none"


func _set_owner(cell_id: String, owner: String) -> void:
	if OwnershipService != null:
		OwnershipService.set_cell_owner(cell_id, owner)
	elif MapService != null:
		MapService.set_cell_owner(cell_id, owner)
