extends SceneTree
## Headless M3 annex flip.
## godot --headless --path . -s res://tools/prove_annex.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tick: Node = root.get_node_or_null("SimTick")
	if tick != null:
		tick.set("enabled", false)
	var ms: Node = root.get_node_or_null("MapService")
	var own: Node = root.get_node_or_null("OwnershipService")
	var annex: Node = root.get_node_or_null("AnnexService")
	var armies: Node = root.get_node_or_null("ArmyService")
	if ms == null or own == null or annex == null or armies == null:
		push_error("missing autoloads")
		print("ANNEX_FAIL")
		quit(1)
		return
	if not bool(ms.call("load_theater", "stub_med")):
		push_error("failed to load stub_med")
		print("ANNEX_FAIL")
		quit(1)
		return
	armies.call("reset_for_theater")
	if str(own.call("get_cell_owner", "c_2_0")) != "none":
		push_error("c_2_0 should start unclaimed")
		print("ANNEX_FAIL")
		quit(1)
		return
	if not bool(armies.call("order_move", "c_2_0")):
		push_error("could not hop to c_2_0")
		print("ANNEX_FAIL")
		quit(1)
		return
	var counts_before: Dictionary = own.call("counts")
	var t := 0.0
	var flipped := false
	while t < 20.0:
		annex.call("tick", 0.25)
		t += 0.25
		if str(own.call("get_cell_owner", "c_2_0")) == "player":
			flipped = true
			break
	if not flipped:
		push_error("annex did not flip c_2_0 in 20s")
		print("ANNEX_FAIL")
		quit(1)
		return
	var counts_after: Dictionary = own.call("counts")
	print("ANNEX_FLIP cell=c_2_0 owner=player t=%.2f P=%s N=%s E=%s" % [
		t,
		str(counts_after.get("P", counts_after.get("player", "?"))),
		str(counts_after.get("N", counts_after.get("none", "?"))),
		str(counts_after.get("E", counts_after.get("enemy", "?"))),
	])
	if int(counts_after.get("P", 0)) <= int(counts_before.get("P", 0)):
		push_error("player count should rise after flip")
		print("ANNEX_FAIL")
		quit(1)
		return
	print("ANNEX_OK")
	quit(0)
