extends Node
## Atlas-sim tick order: income → builds → movement → combat → annex → lanes → win.

var enabled: bool = false
var winner: String = ""


func _ready() -> void:
	pass


func _process(dt: float) -> void:
	if enabled:
		step(dt)


func step(dt: float) -> void:
	if MapService == null or not MapService.loaded:
		return
	if EconomyService != null:
		EconomyService.tick(dt)
	if BuildingService != null:
		BuildingService.tick(dt)
	if ArmyService != null:
		ArmyService.process_hops(dt)
	# combat: not in this slice
	if AnnexService != null:
		AnnexService.tick(dt)
	if ShippingService != null:
		ShippingService.tick(dt)
	_check_win()


func _check_win() -> void:
	if OwnershipService == null or Balance == null:
		return
	var c := OwnershipService.counts()
	var land := int(c["player"]) + int(c["enemy"]) + int(c["none"])
	if land <= 0:
		return
	var need := Balance.win_land_control()
	if float(c["player"]) / float(land) >= need:
		winner = "player"
	elif float(c["enemy"]) / float(land) >= need:
		winner = "enemy"
