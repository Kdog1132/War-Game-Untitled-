extends SceneTree
## Headless M4 supply earn/spend.
## godot --headless --path . -s res://tools/prove_economy.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tick: Node = root.get_node_or_null("SimTick")
	if tick != null:
		tick.set("enabled", false)
	var ms: Node = root.get_node_or_null("MapService")
	var eco: Node = root.get_node_or_null("EconomyService")
	var bld: Node = root.get_node_or_null("BuildingService")
	var ship: Node = root.get_node_or_null("ShippingService")
	if ms == null or eco == null or bld == null:
		push_error("missing autoloads")
		print("ECONOMY_FAIL")
		quit(1)
		return
	if not bool(ms.call("load_theater", "stub_med")):
		push_error("failed to load stub_med")
		print("ECONOMY_FAIL")
		quit(1)
		return
	if ship != null:
		ship.call("refresh_lane_control")
	eco.call("reset")
	var br: Dictionary = eco.call("apply_income")
	var earned := float(br.get("total", 0.0))
	print("SUPPLY_EARN amount=%.0f land=%s factory=%s trade=%.0f" % [
		earned,
		str(br.get("land", 0)),
		str(br.get("factory", 0)),
		float(br.get("trade", 0.0)),
	])
	if earned <= 0.0:
		push_error("expected positive supply income")
		print("ECONOMY_FAIL")
		quit(1)
		return
	eco.call("grant", 40.0, "prove")
	var before := float(eco.get("supply"))
	if not bool(bld.call("start_build", "Road", "c_0_0", "player")):
		push_error("Road spend/build failed")
		print("ECONOMY_FAIL")
		quit(1)
		return
	var after := float(eco.get("supply"))
	var spent := before - after
	print("SUPPLY_SPEND amount=%.0f kind=Road" % spent)
	if spent < 39.9:
		push_error("expected Road spend 40, got %s" % spent)
		print("ECONOMY_FAIL")
		quit(1)
		return
	print("ECONOMY_OK")
	quit(0)
