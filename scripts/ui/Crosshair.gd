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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Full-rect (rather than PRESET_CENTER) so the draw point is just this
	# control's own center -- PRESET_CENTER pins offsets to wherever the
	# control's rect happened to be *before* the anchor change (0,0, since
	# it's freshly instantiated), landing the dot in the top-left corner
	# instead of screen-center. Full-rect always spans the viewport, so
	# size * 0.5 is always the true center, and it stays correct on resize.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, SHADOW_RADIUS, Color(0, 0, 0, 0.6))
	draw_circle(center, RADIUS, Color(1, 1, 1, 0.9))
