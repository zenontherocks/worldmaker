extends Control
class_name Crosshair
## Tiny screen-center dot so the player can see exactly where the camera is
## pointing -- otherwise the only aim feedback is the Place-mode ghost
## (absent entirely in Delete/Rotate/Edit, which show a highlight instead).
## Drawn procedurally rather than as an image asset, same reasoning as
## GhostPreview's material and BuildModeController's highlight materials.
## Purely decorative -- BuildModeController has no idea this exists.

const RADIUS: float = 2.5
const SHADOW_RADIUS: float = 3.5

var _center: Vector2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(SHADOW_RADIUS, SHADOW_RADIUS) * 2.0
	size = custom_minimum_size
	_center = size * 0.5


func _draw() -> void:
	draw_circle(_center, SHADOW_RADIUS, Color(0, 0, 0, 0.6))
	draw_circle(_center, RADIUS, Color(1, 1, 1, 0.9))
