extends Camera3D
class_name PlayerCamera
## Mouse look only: yaw is applied to the parent CharacterBody3D, pitch to
## this camera. Reads/writes the global Input.mouse_mode directly rather
## than keeping its own "am I captured" flag, so the UI (SettingsPanelUI)
## can release/recapture the mouse for file dialogs without the two ever
## disagreeing about state.

const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_LIMIT: float = deg_to_rad(89.0)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse_capture"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		get_parent().rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		rotation.x = clampf(rotation.x - event.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
