extends Control
class_name CircleButton
## Reusable round clickable button used by the pause menu's Tools and Skins
## circle bands. Godot has no built-in round Button, and the only existing
## circle-drawing code (Crosshair.gd) is purely decorative -- MOUSE_FILTER_
## IGNORE, no input handling -- so hit-testing is built from scratch here:
## a plain rectangular Button's clickable area would extend into this
## Control's square bounding box outside the drawn circle, so _gui_input()
## does its own distance-from-center check instead of relying on the
## bounding rect. Two content modes, chosen by which property is set:
## label_text draws centered text (tool circles), preview_texture draws a
## skin thumbnail inscribed inside the circle so its corners stay inside
## the circle's curve (good enough without a clipping shader).

signal pressed

const DIAMETER: float = 56.0
const _RADIUS: float = DIAMETER * 0.5
const _FONT_SIZE: int = 11

var label_text: String = "":
	set(value):
		label_text = value
		queue_redraw()

var preview_texture: Texture2D = null:
	set(value):
		preview_texture = value
		queue_redraw()

var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

var _hovered: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(DIAMETER, DIAMETER)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if (event.position - Vector2(_RADIUS, _RADIUS)).length() <= _RADIUS:
			pressed.emit()


func _draw() -> void:
	var center := Vector2(_RADIUS, _RADIUS)
	var fill := Color(1, 1, 1, 0.12)
	if selected:
		fill = Color(0.4, 0.6, 1.0, 0.85)
	elif _hovered:
		fill = Color(1, 1, 1, 0.22)
	draw_circle(center, _RADIUS, fill)
	if selected:
		draw_arc(center, _RADIUS - 1.0, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 2.0)

	if preview_texture:
		# Inscribed square: its corners still land inside the circle's
		# curve, so the thumbnail never pokes out past the round outline.
		var half := _RADIUS * 0.68
		draw_texture_rect(
			preview_texture, Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0), false
		)
	elif label_text != "":
		var font := ThemeDB.fallback_font
		var baseline_y := _RADIUS + _FONT_SIZE * 0.35
		draw_string(
			font,
			Vector2(0, baseline_y),
			label_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			DIAMETER,
			_FONT_SIZE,
			Color.WHITE
		)
