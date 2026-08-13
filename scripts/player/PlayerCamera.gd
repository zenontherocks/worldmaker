extends Camera3D
class_name PlayerCamera
## Mouse look only: yaw is applied to the parent CharacterBody3D, pitch to
## this camera. Reads/writes the global Input.mouse_mode directly rather
## than keeping its own "am I captured" flag, so the UI (PauseMenuUI) can
## release/recapture the mouse for the pause menu and file dialogs without
## the two ever disagreeing about state.
##
## PauseMenuUI owns Escape and drives mouse_mode itself when opening/
## closing; this script only has to handle re-acquiring capture on click
## when the mouse ends up released some other way (mainly: browsers
## force-exit Pointer Lock on Escape themselves, which can't be prevented,
## so the pause menu opening races that forced release). A click is also
## the real user gesture Pointer Lock re-acquisition expects anyway.

const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_LIMIT: float = deg_to_rad(89.0)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion:
		get_parent().rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		rotation.x = clampf(rotation.x - event.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
