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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# get_viewport().size_changed (not this Control's own `resized`) so a
	# redraw is guaranteed on an actual window resize regardless of
	# whether this Control's own size/position end up resolving the way
	# a plain Control-in-Control tree would -- its parent is a CanvasLayer,
	# not a Control, which made a previous size*0.5-based centering attempt
	# unreliable. queue_redraw() here too, as a safety net in case the
	# very first automatic draw happens before layout has settled.
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	# get_viewport_rect() returns the viewport's visible rect already
	# translated into this node's own local drawing coordinates -- unlike
	# size * 0.5, it doesn't assume this Control's own position is (0,0),
	# so it stays correct regardless of how this Control (parented
	# directly under a CanvasLayer rather than another Control) resolves
	# its own size/position.
	var rect := get_viewport_rect()
	var center := rect.position + rect.size * 0.5
	draw_circle(center, SHADOW_RADIUS, Color(0, 0, 0, 0.6))
	draw_circle(center, RADIUS, Color(1, 1, 1, 0.9))
