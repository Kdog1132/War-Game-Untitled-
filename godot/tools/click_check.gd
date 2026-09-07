extends SceneTree
## Headless select/move + camera pick check.
## godot --headless --path . -s res://tools/click_check.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ms: Node = root.get_node_or_null("MapService")
	var armies: Node = root.get_node_or_null("ArmyService")
	if ms == null or not bool(ms.call("load_theater", "stub_med")):
		push_error("failed to load stub_med")
		print("CLICK_CHECK_FAIL")
		quit(1)
		return
	if int(ms.get("overlay_features").size()) < 4:
		push_error("expected painted overlays")
		print("CLICK_CHECK_FAIL")
		quit(1)
		return
	if not bool(ms.get("use_geo_world")):
		push_error("use_geo_world should be on when overlays load")
		print("CLICK_CHECK_FAIL")
		quit(1)
		return

	for cid in ["c_0_0", "c_1_0", "c_2_0", "c_3_0", "c_4_0", "c_5_0", "c_1_1", "c_4_1"]:
		var world: Vector2 = ms.call("cell_world_pos", cid)
		var hit := str(ms.call("cell_id_at_world", world))
		if hit != cid:
			push_error("cell_id_at_world(%s world) -> %s" % [cid, hit])
			print("CLICK_CHECK_FAIL")
			quit(1)
			return

	var bounds: Rect2 = ms.call("map_bounds")
	var cam := bounds.get_center()
	var vp := Vector2(1280, 720)
	var z := minf(vp.x / maxf(bounds.size.x, 1.0), vp.y / maxf(bounds.size.y, 1.0)) * 0.88
	z = clampf(z, 0.12, 2.2)
	var gib: Vector2 = ms.call("cell_world_pos", "c_0_0")
	var screen := (gib - cam) * z + vp * 0.5
	var recovered: Vector2 = ms.call("screen_to_world", screen, cam, Vector2(z, z), vp)
	if recovered.distance_to(gib) > 0.5:
		push_error("screen_to_world missed after center_on_cells")
		print("CLICK_CHECK_FAIL")
		quit(1)
		return
	var cam2 := cam + Vector2(160, -70)
	var z2 := z * 1.4
	var screen2 := (gib - cam2) * z2 + vp * 0.5
	var recovered2: Vector2 = ms.call("screen_to_world", screen2, cam2, Vector2(z2, z2), vp)
	if recovered2.distance_to(gib) > 0.5:
		push_error("screen_to_world missed after pan/zoom")
		print("CLICK_CHECK_FAIL")
		quit(1)
		return
	if str(ms.call("cell_id_at_world", recovered2)) != "c_0_0":
		push_error("picked wrong cell after pan/zoom")
		print("CLICK_CHECK_FAIL")
		quit(1)
		return

	if armies == null:
		push_error("ArmyService missing")
		print("CLICK_CHECK_FAIL")
		quit(1)
		return
	armies.call("reset_for_theater")
	if str(armies.call("try_click", "c_0_0")) != "selected":
		push_error("LMB on army cell should select")
		print("CLICK_CHECK_FAIL")
		quit(1)
		return
	var moved := str(armies.call("try_click", "c_1_0"))
	if moved != "moved":
		push_error("LMB destination should move, got %s" % moved)
		print("CLICK_CHECK_FAIL")
		quit(1)
		return
	if str(armies.call("player_cell")) != "c_1_0":
		push_error("army did not arrive on Andalusia")
		print("CLICK_CHECK_FAIL")
		quit(1)
		return

	print("CLICK_CHECK_OK overlays=%d picked=c_0_0 moved=c_1_0 zoom=%.3f" % [
		int(ms.get("overlay_features").size()),
		z,
	])
	quit(0)
