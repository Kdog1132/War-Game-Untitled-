extends Node2D
## Visible hex theater: terrain fill + ownership tint, shipping lanes, Camera2D.

const TERRAIN_COLORS := {
	"plains": Color("#9ccc65"),
	"urban": Color("#90a4ae"),
	"forest": Color("#2e7d32"),
	"hill": Color("#8d6e63"),
	"desert": Color("#ffd54f"),
	"swamp": Color("#00695c"),
	"mountain": Color("#5d4037"),
	"water": Color("#1565c0"),
}

const OWNER_TINT := {
	"player": Color(0.18, 0.42, 1.0, 0.38),
	"enemy": Color(0.89, 0.23, 0.23, 0.38),
	"none": Color(0.45, 0.45, 0.48, 0.22),
}

const LANE_COLOR := Color(0.35, 0.75, 0.95, 0.85)
const OUTLINE := Color(0.08, 0.09, 0.11, 0.55)
const ARMY := Color("#2E6BFF")

@onready var camera: Camera2D = $Camera2D

var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _army_cell_id: String = ""


func _ready() -> void:
	if camera:
		camera.make_current()
	rebuild()


func rebuild() -> void:
	_army_cell_id = _first_player_cell()
	queue_redraw()
	recenter()


func recenter() -> void:
	if camera == null or not MapService.loaded:
		return
	var bounds := MapService.map_bounds()
	camera.position = bounds.get_center()
	var vp := get_viewport_rect().size
	var z := minf(vp.x / maxf(bounds.size.x, 1.0), vp.y / maxf(bounds.size.y, 1.0)) * 0.88
	z = clampf(z, 0.12, 2.2)
	camera.zoom = Vector2(z, z)


func _process(delta: float) -> void:
	if camera == null:
		return
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if pan != Vector2.ZERO:
		var speed := 520.0 / maxf(camera.zoom.x, 0.05)
		camera.position += pan.normalized() * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(1.12)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(1.0 / 1.12)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_drag_last = mb.position
			if mb.pressed:
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		camera.position -= mm.relative / camera.zoom
		get_viewport().set_input_as_handled()


func _zoom_by(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, 0.08, 4.0)
	camera.zoom = Vector2(z, z)


func _draw() -> void:
	if not MapService.loaded:
		return
	var bounds := MapService.map_bounds().grow(MapService.hex_size_px * 24.0)
	draw_rect(bounds, Color("#1565c0"))
	for cell in MapService.cells.values():
		_draw_hex(cell)
	_draw_lanes()
	if not _army_cell_id.is_empty():
		_draw_army(MapService.cell_world_pos(_army_cell_id))


func _draw_hex(cell: Dictionary) -> void:
	var q := int(cell.get("q", 0))
	var r := int(cell.get("r", 0))
	var center := MapService.axial_to_world(q, r)
	var pts := _hex_corners(center, MapService.hex_size_px * 0.96)
	var tag := str(cell.get("terrain_tag", "plains"))
	var fill: Color = TERRAIN_COLORS.get(tag, TERRAIN_COLORS["plains"])
	draw_colored_polygon(pts, fill)
	var owner := MapService.get_cell_owner(str(cell.get("cell_id", "")))
	var tint: Color = OWNER_TINT.get(owner, OWNER_TINT["none"])
	draw_colored_polygon(pts, tint)
	var outline_pts := pts.duplicate()
	outline_pts.append(pts[0])
	draw_polyline(outline_pts, OUTLINE, 1.2)
	if bool(cell.get("harbor_site", false)):
		draw_circle(center, MapService.hex_size_px * 0.16, Color("#1565c0"))
		draw_arc(center, MapService.hex_size_px * 0.22, 0.0, TAU, 14, Color("#e3f2fd"), 1.5)


func _draw_lanes() -> void:
	for lane in MapService.lanes:
		var a_id := MapService.harbor_cell_id(str(lane.get("a", "")))
		var b_id := MapService.harbor_cell_id(str(lane.get("b", "")))
		if a_id.is_empty() or b_id.is_empty():
			continue
		var a := MapService.cell_world_pos(a_id)
		var b := MapService.cell_world_pos(b_id)
		var col := LANE_COLOR
		match str(lane.get("state", "Open")):
			"Contested":
				col = Color(0.95, 0.75, 0.2, 0.9)
			"Blocked":
				col = Color(0.7, 0.15, 0.15, 0.75)
		draw_line(a, b, col, maxf(1.5, MapService.hex_size_px * 0.12))


func _draw_army(pos: Vector2) -> void:
	var s := MapService.hex_size_px * 0.28
	var pts := PackedVector2Array([
		pos + Vector2(0, -s),
		pos + Vector2(s * 0.7, s * 0.55),
		pos + Vector2(0, s * 0.15),
		pos + Vector2(-s * 0.7, s * 0.55),
	])
	draw_colored_polygon(pts, ARMY)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.05, 0.08, 0.16, 0.8), 1.4)


func _hex_corners(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i))
		pts.append(center + Vector2(cos(angle), sin(angle)) * size)
	return pts


func _first_player_cell() -> String:
	for cid in MapService.cells.keys():
		if MapService.get_cell_owner(str(cid)) == "player":
			return str(cid)
	return ""
