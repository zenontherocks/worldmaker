extends Control
class_name BuildHUD
## Always-on-screen build status readout (bottom of screen): current tool
## (a shape to place, Empty Hands, or the Delete/Rotate/Edit tool), live
## dimension values with the scroll-adjustable field marked, and a control
## reminder.
## The whole game is build mode (no separate enter/exit toggle), so this
## always shows live status once the first tool_mode_changed signal
## arrives. Built procedurally because the set of dimension fields differs
## per shape and is driven entirely by ShapeDefinitions. Purely a signal
## listener -- BuildModeController never references it directly, Main.gd
## wires the connection.

var _label: Label

var _tool_mode: int = BuildModeController.ToolMode.PLACE
var _slot_number: int = 1
var _slot_count: int = 1
var _shape_name: String = ""
var _dimensions: Dictionary = {}
var _active_field: String = ""

## Edit tool: whether it's currently locked onto a target (vs. still
## browsing for one) and that target's shape name. Dimensions/active field
## while locked are the same _dimensions/_active_field above -- Build
## ModeController reuses dimensions_changed/active_field_changed for both
## a pending placement and a locked edit target.
var _editing: bool = false
var _edit_shape_name: String = ""

## [G]: grid-snap, wall auto-orient, and Plane-edge tiling all together --
## only shown on the Place line, since the other tools don't place anything.
var _snap_enabled: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -70
	offset_bottom = -12
	offset_left = 16
	offset_right = -16

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

	_refresh()


func on_shape_changed(shape_id: int, dimensions: Dictionary) -> void:
	_shape_name = ShapeDefinitions.shape_name(shape_id)
	_dimensions = dimensions
	_refresh()


func on_dimensions_changed(dimensions: Dictionary) -> void:
	_dimensions = dimensions
	_refresh()


func on_active_field_changed(field_key: String) -> void:
	_active_field = field_key
	_refresh()


func on_tool_mode_changed(mode: int, slot_number: int, slot_count: int) -> void:
	_tool_mode = mode
	_slot_number = slot_number
	_slot_count = slot_count
	_editing = false
	_refresh()


func on_edit_target_changed(shape_id: int, dimensions: Dictionary) -> void:
	_editing = true
	_edit_shape_name = ShapeDefinitions.shape_name(shape_id)
	_dimensions = dimensions
	_refresh()


func on_edit_target_cleared() -> void:
	_editing = false
	_refresh()


func on_snap_toggled(enabled: bool) -> void:
	_snap_enabled = enabled
	_refresh()


func _refresh() -> void:
	match _tool_mode:
		BuildModeController.ToolMode.EMPTY:
			_label.text = (
				"Tool: Empty Hands (%d/%d)\n" % [_slot_number, _slot_count]
				+ "[E] change tool  [Esc] menu"
			)
		BuildModeController.ToolMode.DELETE:
			_label.text = (
				"Tool: Delete (%d/%d)\n" % [_slot_number, _slot_count]
				+ "[Click] delete targeted block  [E] change tool  [Esc] menu"
			)
		BuildModeController.ToolMode.ROTATE:
			_label.text = (
				"Tool: Rotate (%d/%d)\n" % [_slot_number, _slot_count]
				+ "[R]/[Shift+R] rotate horizontally  [T]/[Shift+T] tilt vertically  [E] change tool  [Esc] menu"
			)
		BuildModeController.ToolMode.EDIT:
			if _editing:
				var parts := PackedStringArray()
				for key in _dimensions.keys():
					var marker := ">" if key == _active_field else ""
					parts.append("%s%s=%.2f" % [marker, key, _dimensions[key]])
				_label.text = (
					"Editing: %s  |  %s\n" % [_edit_shape_name, ", ".join(parts)]
					+ "[Q] field  [wheel] adjust  [Click] done  [Esc] menu"
				)
			else:
				_label.text = (
					"Tool: Edit (%d/%d)\n" % [_slot_number, _slot_count]
					+ "[Click] select targeted block  [E] change tool  [Esc] menu"
				)
		_:
			var parts := PackedStringArray()
			for key in _dimensions.keys():
				var marker := ">" if key == _active_field else ""
				parts.append("%s%s=%.2f" % [marker, key, _dimensions[key]])

			_label.text = (
				"Shape: %s (%d/%d)  |  %s\n"
				% [_shape_name, _slot_number, _slot_count, ", ".join(parts)]
				+ "[E] tool  [Q] field  [wheel] adjust  [R]/[Shift+R] rotate  [Click] place  "
				+ "[G] snap: %s  [Esc] menu" % ("ON" if _snap_enabled else "OFF")
			)
