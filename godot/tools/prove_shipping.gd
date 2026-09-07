extends SceneTree
## Headless M5 Forge LC + Harbor→Harbor ferry.
## godot --headless --path . -s res://tools/prove_shipping.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tick: Node = root.get_node_or_null("SimTick")
	if tick != null:
		tick.set("enabled", false)
	var ms: Node = root.get_node_or_null("MapService")
	var ship: Node = root.get_node_or_null("ShippingService")
	var armies: Node = root.get_node_or_null("ArmyService")
	if ms == null or ship == null or armies == null:
		push_error("missing autoloads")
		print("SHIPPING_FAIL")
		quit(1)
		return
	if not bool(ms.call("load_theater", "stub_med")):
		push_error("failed to load stub_med")
		print("SHIPPING_FAIL")
		quit(1)
		return
	armies.call("reset_for_theater")
	ship.call("refresh_lane_control")
	if str(ship.call("lane_state", "l_1")) != "Contested":
		push_error("Forge LC expected l_1 Contested (player + enemy harbors), got %s" % str(ship.call("lane_state", "l_1")))
		print("SHIPPING_FAIL")
		quit(1)
		return
	if str(armies.call("player_cell")) != "c_0_0":
		push_error("army should start on Gibraltar c_0_0")
		print("SHIPPING_FAIL")
		quit(1)
		return
	var rec: Dictionary = ship.call("start_ferry", "a_player_1", "h_suez")
	if rec.is_empty():
		push_error("FERRY_START failed")
		print("SHIPPING_FAIL")
		quit(1)
		return
	print("FERRY_START from=%s to=%s lane=%s state=%s eta=%s" % [
		str(rec.get("from", "")),
		str(rec.get("to", "")),
		str(rec.get("lane_id", "")),
		str(rec.get("state", "")),
		str(rec.get("eta", "")),
	])
	var eta := float(rec.get("eta", 12.0))
	ship.call("tick", eta + 0.01)
	var dest := str(armies.call("player_cell"))
	if dest != "c_5_0":
		push_error("expected FERRY_ARRIVE on c_5_0, at %s" % dest)
		print("SHIPPING_FAIL")
		quit(1)
		return
	print("FERRY_ARRIVE cell=c_5_0")
	print("SHIPPING_OK")
	quit(0)
