extends Control
class_name ColorWheel
## Ring + triangle HSV picker: drag around the outer ring to choose hue,
## drag inside the triangle (which rotates to track the current hue) to
## choose saturation/value. Procedurally drawn like every other custom
## control in this project -- no image assets, so this costs nothing in
## download size.
##
## The triangle's three corners are the pure hue color, white, and black.
## draw_polygon() Gouraud-interpolates vertex colors linearly in RGB
## across the triangle, and that linear RGB blend is, algebraically,
## exactly the standard HSV-triangle parameterization: for barycentric
## weights (u, v, w) toward (hue, white, black), value = u + v (the
## fraction not at the black corner) and saturation = u / (u + v) (how
## much of that non-black mix is pure hue vs white). So the same three
## corner colors and the same barycentric math serve both rendering and
## hit-testing -- there's no separate/approximate formula for either, and
## dragging always picks exactly the color that's visually drawn there.

signal color_changed(new_color: Color)  ## live, fired on every drag update
signal color_committed(new_color: Color)  ## fired once, on drag release

const RADIUS: float = 70.0
const RING_WIDTH: float = 14.0
const TRIANGLE_MARGIN: float = 6.0
const RING_SEGMENTS: int = 48
const MARKER_RADIUS: float = 4.0
const MARKER_SHADOW_RADIUS: float = 5.5

var _hue: float = 0.0
var _saturation: float = 1.0
var _value: float = 1.0
var _drag_mode: String = ""  ## "", "hue", "sv"

var color: Color:
	get:
		return Color.from_hsv(_hue, _saturation, _value)


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS, RADIUS) * 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


## Repositions the ring/triangle markers to match an externally-chosen
## color (e.g. a typed hex code or a clicked swatch) without emitting
## color_changed/color_committed -- this is display sync, not a pick.
func set_color(new_color: Color) -> void:
	_hue = new_color.h
	_saturation = new_color.s
	_value = new_color.v
	queue_redraw()


func _center() -> Vector2:
	return size * 0.5


func _triangle_radius() -> float:
	return RADIUS - RING_WIDTH - TRIANGLE_MARGIN


## Pure hue, white, black -- in that order, matching every other function
## in this file that reads/writes triangle barycentric weights (u, v, w).
func _triangle_points() -> PackedVector2Array:
	var c := _center()
	var r := _triangle_radius()
	var a0 := _hue * TAU - PI * 0.5
	return PackedVector2Array(
		[
			c + Vector2(cos(a0), sin(a0)) * r,
			c + Vector2(cos(a0 + TAU / 3.0), sin(a0 + TAU / 3.0)) * r,
			c + Vector2(cos(a0 - TAU / 3.0), sin(a0 - TAU / 3.0)) * r,
		]
	)


func _draw() -> void:
	var c := _center()

	for i in range(RING_SEGMENTS):
		var a_start := (float(i) / RING_SEGMENTS) * TAU - PI * 0.5
		var a_end := (float(i + 1) / RING_SEGMENTS) * TAU - PI * 0.5
		var seg_color := Color.from_hsv(float(i) / RING_SEGMENTS, 1.0, 1.0)
		draw_arc(c, RADIUS - RING_WIDTH * 0.5, a_start, a_end, 3, seg_color, RING_WIDTH, false)

	var points := _triangle_points()
	var hue_color := Color.from_hsv(_hue, 1.0, 1.0)
	draw_polygon(points, PackedColorArray([hue_color, Color.WHITE, Color.BLACK]))

	var hue_angle := _hue * TAU - PI * 0.5
	var hue_marker := c + Vector2(cos(hue_angle), sin(hue_angle)) * (RADIUS - RING_WIDTH * 0.5)
	_draw_marker(hue_marker)

	# Reconstructs the triangle position from _saturation/_value the same
	# way _apply() derives them, just run in reverse.
	var w_hue := _saturation * _value
	var w_white := _value * (1.0 - _saturation)
	var w_black := 1.0 - _value
	var sv_marker := points[0] * w_hue + points[1] * w_white + points[2] * w_black
	_draw_marker(sv_marker)


func _draw_marker(pos: Vector2) -> void:
	draw_circle(pos, MARKER_SHADOW_RADIUS, Color(0, 0, 0, 0.6))
	draw_circle(pos, MARKER_RADIUS, Color.WHITE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_drag_mode = _hit_test(event.position)
			if _drag_mode != "":
				_apply(event.position)
				accept_event()
		elif _drag_mode != "":
			_drag_mode = ""
			color_committed.emit(color)
			accept_event()
	elif event is InputEventMouseMotion and _drag_mode != "":
		_apply(event.position)
		accept_event()


func _hit_test(pos: Vector2) -> String:
	var dist := (pos - _center()).length()
	if dist >= RADIUS - RING_WIDTH and dist <= RADIUS:
		return "hue"
	# A small negative tolerance so a click just outside the triangle's
	# exact edge (easy to miss by a pixel, especially near its pointed
	# corners) still registers as an sv-drag instead of doing nothing.
	var bary := _barycentric(pos, _triangle_points())
	if bary.x >= -0.05 and bary.y >= -0.05 and bary.z >= -0.05:
		return "sv"
	return ""


func _apply(pos: Vector2) -> void:
	if _drag_mode == "hue":
		var offset := pos - _center()
		var angle := atan2(offset.y, offset.x) + PI * 0.5
		_hue = wrapf(angle, 0.0, TAU) / TAU
	elif _drag_mode == "sv":
		var bary := _barycentric(pos, _triangle_points())
		# Clamping each weight to >=0 and renormalizing lands a drag that
		# strayed outside the triangle on its nearest edge/corner instead
		# of doing nothing -- standard, simple way to keep a triangle-pick
		# gesture from "falling off" the widget.
		var u: float = maxf(bary.x, 0.0)
		var v: float = maxf(bary.y, 0.0)
		var w: float = maxf(bary.z, 0.0)
		var total := u + v + w
		if total > 0.0:
			u /= total
			v /= total
		_value = u + v
		_saturation = (u / (u + v)) if (u + v) > 0.0001 else 0.0
	queue_redraw()
	color_changed.emit(color)


func _barycentric(p: Vector2, triangle: PackedVector2Array) -> Vector3:
	var a := triangle[0]
	var b := triangle[1]
	var c := triangle[2]
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denom := d00 * d11 - d01 * d01
	if absf(denom) < 0.0001:
		return Vector3(1, 0, 0)
	var v := (d11 * d20 - d01 * d21) / denom
	var w := (d00 * d21 - d01 * d20) / denom
	var u := 1.0 - v - w
	return Vector3(u, v, w)
