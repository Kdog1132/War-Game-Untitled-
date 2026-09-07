extends Node
## M0–M6 boot: stub_med, WorldMap, HUD (Supply + lane Open/Contested/Blocked).
## KEY_1 = stub_med. KEY_2 = med_v0.

@onready var world_map: Node2D = $WorldMap
@onready var theater_label: Label = $HUD/TheaterLabel
@onready var help_label: Label = $HUD/HelpLabel
@onready var status_label: Label = $HUD/StatusLabel


func _ready() -> void:
	if world_map.has_signal("status_changed"):
		world_map.status_changed.connect(_on_map_status)
	_connect_refresh(OwnershipService)
	_connect_refresh(EconomyService)
	_connect_refresh(AnnexService)
	_connect_refresh(ShippingService)
	_connect_refresh(BuildingService)
	_connect_refresh(ArmyService)
	SimTick.enabled = true
	_load_theater("stub_med")


func _connect_refresh(node: Node) -> void:
	if node != null and node.has_signal("changed") and not node.changed.is_connected(_on_service_changed):
		node.changed.connect(_on_service_changed)


func _on_service_changed() -> void:
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_load_theater("stub_med")
				get_viewport().set_input_as_handled()
			KEY_2:
				_load_theater("med_v0")
				get_viewport().set_input_as_handled()
			KEY_H:
				_try_build("Harbor")
			KEY_F:
				_try_build("Factory")
			KEY_R:
				_try_build("Road")
			KEY_B:
				_try_build("Bunker")


func _try_build(kind: String) -> void:
	var cell := _build_cell()
	if cell.is_empty():
		return
	if BuildingService.start_build(kind, cell, "player"):
		_refresh_hud()
	get_viewport().set_input_as_handled()


func _build_cell() -> String:
	if world_map != null and world_map.get("_hover_cell") != null:
		var hover := str(world_map.get("_hover_cell"))
		if not hover.is_empty() and OwnershipService.get_cell_owner(hover) == "player":
			return hover
	return ArmyService.player_cell()


func _load_theater(dir_name: String) -> void:
	if not MapService.load_theater(dir_name):
		push_error("Main: failed to load theater '%s'" % dir_name)
		theater_label.text = "Theater: failed to load %s" % dir_name
		return
	MapService.hex_size_px = MapService.suggested_hex_size(dir_name)
	if world_map.has_method("rebuild"):
		world_map.rebuild()
	_refresh_hud()


func _refresh_hud() -> void:
	var name := str(MapService.meta.get("name", MapService.theater_id))
	theater_label.text = "%s  (%s)  %s" % [name, MapService.theater_id, OwnershipService.counts_hud()]
	help_label.text = "1 stub_med  2 med_v0  LMB pick territory  MMB pan  WASD  wheel  H/F/R/B build  %d cells" % MapService.cells.size()
	if status_label:
		status_label.text = _status_text()


func _status_text() -> String:
	var bits: PackedStringArray = []
	var income: Dictionary = EconomyService.preview_income("player")
	bits.append("Supply %.0f  (+%.0f/s  land %d  factory %d  trade %.0f)" % [
		EconomyService.supply,
		float(income.get("total", 0.0)),
		int(income.get("land", 0)),
		int(income.get("factory", 0)),
		float(income.get("trade", 0.0)),
	])
	var cell := ArmyService.player_cell()
	if bool(ArmyService.player().get("at_sea", false)):
		var ferry: Dictionary = ShippingService.ferry_for_army(ArmyService.PLAYER_ID)
		bits.append("Selected army at sea  %s → %s  %.1fs" % [
			str(ferry.get("from", "?")),
			str(ferry.get("to", "?")),
			float(ferry.get("remaining", 0.0)),
		])
	elif cell.is_empty():
		bits.append("No army")
	elif ArmyService.is_selected():
		bits.append("Selected %s  str %.0f  LMB territory to hop / harbor to ferry" % [
			cell,
			float(ArmyService.player().get("strength", 100.0)),
		])
	else:
		bits.append("LMB a territory to pick")
	var annex_cell := ""
	if world_map != null and world_map.has_method("picked_cell"):
		annex_cell = str(world_map.call("picked_cell"))
	if annex_cell.is_empty():
		annex_cell = cell
	if not annex_cell.is_empty():
		var meter := AnnexService.meter(annex_cell)
		var claim := AnnexService.claiming_faction(annex_cell)
		if meter > 0.0:
			var annex := "Annex %s  %.0f/100  %s" % [annex_cell, meter, claim]
			var eta := AnnexService.eta_sec(annex_cell)
			# ETA only when annex is slow (>8s). Fast flips stay meter-only.
			if is_finite(eta) and eta > 8.0:
				annex += "  ETA %.0fs" % eta
			bits.append(annex)
	var lanes := ShippingService.lane_hud()
	if lanes != "":
		bits.append("Lanes  %s" % lanes)
	if SimTick.winner != "":
		bits.append("WIN %s" % SimTick.winner)
	return "    ".join(bits)


func _on_map_status(_text: String) -> void:
	_refresh_hud()
