extends Control
class_name BuildHUD
## Always-on-screen build status readout (bottom of screen): current shape,
## live dimension values with the scroll-adjustable field marked, and a
## control reminder. Built procedurally because the set of dimension
## fields differs per shape and is driven entirely by ShapeDefinitions.
## Purely a signal listener -- BuildModeController never references it
## directly, Main.gd wires the connection.

var _label: Label

var _shape_name: String = ""
var _shape_number: int = 1
var _shape_count: int = ShapeDefinitions.ORDER.size()
var _dimensions: Dictionary = {}
var _active_field: String = ""
var _build_active: bool = false


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


func on_build_mode_changed(is_active: bool) -> void:
	_build_active = is_active
	_refresh()


func on_shape_changed(shape_id: int, dimensions: Dictionary) -> void:
	_shape_name = ShapeDefinitions.shape_name(shape_id)
	_shape_number = ShapeDefinitions.ORDER.find(shape_id) + 1
	_dimensions = dimensions
	_refresh()


func on_dimensions_changed(dimensions: Dictionary) -> void:
	_dimensions = dimensions
	_refresh()


func on_active_field_changed(field_key: String) -> void:
	_active_field = field_key
	_refresh()


func _refresh() -> void:
	if not _build_active:
		_label.text = "Press [B] to enter Build Mode"
		return

	var parts := PackedStringArray()
	for key in _dimensions.keys():
		var marker := ">" if key == _active_field else ""
		parts.append("%s%s=%.2f" % [marker, key, _dimensions[key]])

	_label.text = (
		"BUILD MODE  |  Shape: %s (%d/%d)  |  %s\n"
		% [_shape_name, _shape_number, _shape_count, ", ".join(parts)]
		+ "[E] shape  [Q] field  [wheel] adjust  [R]/[Shift+R] rotate  [Click] place  [B] exit"
	)
