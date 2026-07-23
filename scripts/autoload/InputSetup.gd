extends Node
## Registers all gameplay input actions at runtime instead of relying on
## hand-edited entries in project.godot. This keeps the binding table in one
## data-driven place, guarantees the actions always exist (no risk of a
## stale/missing Input Map entry after a merge), and is trivial to re-map
## later from a settings menu since it is just data.
##
## This must be the FIRST autoload listed in project.godot so every other
## script can safely call Input.is_action_pressed(...) from _ready() onward.

const KEY_BINDINGS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"toggle_mouse_capture": [KEY_ESCAPE],
	"toggle_ui_panel": [KEY_F1],
	"build_mode_toggle": [KEY_B],
	"build_cycle_shape": [KEY_TAB],
	"build_cycle_dimension": [KEY_Q],
}

const MOUSE_BINDINGS := {
	"build_place": MOUSE_BUTTON_LEFT,
	"build_dimension_increase": MOUSE_BUTTON_WHEEL_UP,
	"build_dimension_decrease": MOUSE_BUTTON_WHEEL_DOWN,
}


func _ready() -> void:
	for action_name in KEY_BINDINGS.keys():
		_ensure_action(action_name)
		for key in KEY_BINDINGS[action_name]:
			var ev := InputEventKey.new()
			ev.keycode = key
			_add_event_if_missing(action_name, ev)

	_ensure_action("build_rotate_cw")
	var rotate_cw := InputEventKey.new()
	rotate_cw.keycode = KEY_R
	_add_event_if_missing("build_rotate_cw", rotate_cw)

	_ensure_action("build_rotate_ccw")
	var rotate_ccw := InputEventKey.new()
	rotate_ccw.keycode = KEY_R
	rotate_ccw.shift_pressed = true
	_add_event_if_missing("build_rotate_ccw", rotate_ccw)

	for action_name in MOUSE_BINDINGS.keys():
		_ensure_action(action_name)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BINDINGS[action_name]
		_add_event_if_missing(action_name, ev)


func _ensure_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)


func _add_event_if_missing(action_name: String, event: InputEvent) -> void:
	for existing in InputMap.action_get_events(action_name):
		if existing.as_text() == event.as_text():
			return
	InputMap.action_add_event(action_name, event)
