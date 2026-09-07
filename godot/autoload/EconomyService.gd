extends Node
## M4: Supply income 1/land + 8/factory + lane trade. Spend on buildings.

signal changed
signal earned(amount: float, breakdown: Dictionary)
signal spent(amount: float, reason: String)

var supply: float = 0.0
var last_income: Dictionary = {}
var _acc: float = 0.0


func _ready() -> void:
	if MapService != null and not MapService.theater_loaded.is_connected(_on_theater_loaded):
		MapService.theater_loaded.connect(_on_theater_loaded)


func _on_theater_loaded(_theater_id: String) -> void:
	reset()


func reset() -> void:
	supply = 0.0
	last_income = {}
	_acc = 0.0
	changed.emit()


func grant(amount: float, reason: String = "grant") -> void:
	supply += amount
	changed.emit()
	if reason != "":
		pass


func can_afford(amount: float) -> bool:
	return supply + 0.0001 >= amount


func spend(amount: float, reason: String = "") -> bool:
	if amount < 0.0 or not can_afford(amount):
		return false
	supply -= amount
	spent.emit(amount, reason)
	changed.emit()
	return true


func tick(dt: float) -> void:
	var step := Balance.tick_sec() if Balance != null else 1.0
	_acc += dt
	while _acc >= step:
		_acc -= step
		apply_income()


func apply_income() -> Dictionary:
	var br := preview_income("player")
	var amount := float(br.get("total", 0.0))
	supply += amount
	last_income = br
	earned.emit(amount, br)
	changed.emit()
	return br


func preview_income(faction: String = "player") -> Dictionary:
	var land := _count_land(faction)
	var factories := 0
	if BuildingService != null:
		factories = BuildingService.count_complete("Factory", faction)
	var trade := _trade_income(faction)
	var per_land := Balance.supply_per_land() if Balance != null else 1.0
	var per_factory := Balance.supply_per_factory() if Balance != null else 8.0
	var land_pay := float(land) * per_land
	var factory_pay := float(factories) * per_factory
	return {
		"land": land,
		"factory": factories,
		"trade": trade,
		"land_pay": land_pay,
		"factory_pay": factory_pay,
		"total": land_pay + factory_pay + trade,
	}


func _count_land(faction: String) -> int:
	if MapService == null:
		return 0
	var n := 0
	for cid in MapService.cells.keys():
		var cell: Dictionary = MapService.get_cell(str(cid))
		if str(cell.get("terrain_tag", "")) == "water":
			continue
		if _owner_of(str(cid)) == faction:
			n += 1
	return n


func _trade_income(faction: String) -> float:
	if MapService == null or Balance == null:
		return 0.0
	var total := 0.0
	for lane in MapService.lanes:
		if typeof(lane) != TYPE_DICTIONARY:
			continue
		var a_id := MapService.harbor_cell_id(str(lane.get("a", "")))
		var b_id := MapService.harbor_cell_id(str(lane.get("b", "")))
		if a_id.is_empty() and b_id.is_empty():
			continue
		var a_own := _owner_of(a_id)
		var b_own := _owner_of(b_id)
		if a_own != faction and b_own != faction:
			continue
		var state := str(lane.get("state", "Open"))
		total += Balance.supply_trade(state)
	return total


func _owner_of(cell_id: String) -> String:
	if cell_id.is_empty():
		return "none"
	if OwnershipService != null:
		return OwnershipService.get_cell_owner(cell_id)
	if MapService != null:
		return MapService.get_cell_owner(cell_id)
	return "none"
