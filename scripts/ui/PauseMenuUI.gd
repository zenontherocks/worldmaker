extends CanvasLayer
class_name PauseMenuUI
## Esc-triggered pause menu: dims the screen, stops gameplay via
## SceneTree.paused, and holds everything that isn't a raw movement/aiming
## action -- picking a shape or the Delete/Rotate tool, picking which
## imported skin is active, importing a skin image, and exporting/importing
## the world. Talks directly to the SkinManager and SaveLoadManager
## autoloads (both global services, so routing through Main.gd would just
## add an extra hop); Main.gd hands it a BuildModeController reference via
## set_build_controller() since that one isn't global (it lives under the
## player's camera).
##
## The central panel only holds Resume plus the three file actions --
## Tools and Skins are picked via two bands of CircleButtons positioned
## above/below that panel instead, spanning the wider screen. They can't
## live on the always-on BuildHUD: the mouse is pointer-locked (invisible,
## driving camera look) during live gameplay and only becomes a visible,
## clickable cursor once _open() below switches to MOUSE_MODE_VISIBLE, so
## anything clickable has to be part of this paused overlay -- just placed
## outside the panel rather than crammed inside it.
##
## Two flows for the file buttons, chosen per button, exactly as before:
## - Web: WebFilePicker opens a plain, unfiltered browser file picker for
##   imports; world export triggers a browser download. Godot's own
##   FileDialog can't help here -- see WebFilePicker's docstring for why.
## - Desktop (including the editor): real, working native FileDialogs,
##   since desktop Godot has unrestricted filesystem access.
##
## This entire node (and its FileDialog children) runs with
## PROCESS_MODE_ALWAYS so it keeps working while the tree is paused --
## that's the whole point of a pause menu.

var _paused: bool = false
var _content: PanelContainer
var _build_controller: BuildModeController = null

var _tools_row: HFlowContainer
var _tool_buttons: Array = []  ## [{"circle": CircleButton, "slot_index": int}]

var _skins_row: HFlowContainer

## Visible feedback for the whole import/export flow -- push_warning() alone
## isn't enough here, it's a debug-only channel that never shows up anywhere
## in a deployed Web build, so any failure would otherwise be completely
## silent to an actual player.
var _status_label: Label

var _pending_web_pick: String = ""

var _skin_dialog: FileDialog
var _export_dialog: FileDialog
var _import_dialog: FileDialog


## Called once by Main.gd, the only place that knows about both this UI and
## the player's BuildModeController.
func set_build_controller(controller: BuildModeController) -> void:
	_build_controller = controller
	_refresh_tools_row()
	_refresh_skins_row()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	add_child(backdrop)

	# CenterContainer re-centers its child every layout pass, based on
	# whatever that child's actual size turns out to be -- unlike a fixed
	# anchor preset, which locks in an offset computed from _content's size
	# at the moment it's called, before any of the buttons below exist to
	# give it a real size.
	var centering := CenterContainer.new()
	centering.set_anchors_preset(Control.PRESET_FULL_RECT)
	centering.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(centering)

	# Skins row, the panel, and Tools row stack as one centered column --
	# CenterContainer only centers a single child, so that column is this
	# VBoxContainer, with the panel as its middle entry. This also solves
	# the flow rows' wrapping: a FlowContainer only wraps into multiple
	# lines when its parent actually assigns it a width to wrap within, and
	# VBoxContainer (unlike CenterContainer) stretches children to its own
	# width by default -- so each row ends up exactly as wide as the panel
	# and wraps into "a row or two" as more circles get added, instead of
	# every circle stacking into its own single-item line.
	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 16)
	centering.add_child(outer_vbox)

	_skins_row = _make_circle_row()
	outer_vbox.add_child(_skins_row)

	_content = PanelContainer.new()
	_content.custom_minimum_size = Vector2(380, 0)
	outer_vbox.add_child(_content)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_content.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var resume_button := Button.new()
	resume_button.text = "Resume"
	resume_button.focus_mode = Control.FOCUS_NONE
	resume_button.pressed.connect(_close)
	vbox.add_child(resume_button)

	var import_skin_button := Button.new()
	import_skin_button.text = "Load Skin (PNG/JPG)"
	import_skin_button.focus_mode = Control.FOCUS_NONE
	import_skin_button.pressed.connect(_on_import_skin_pressed)
	vbox.add_child(import_skin_button)

	var export_button := Button.new()
	export_button.text = "Save World (JSON)"
	export_button.focus_mode = Control.FOCUS_NONE
	export_button.pressed.connect(_on_export_pressed)
	vbox.add_child(export_button)

	var import_world_button := Button.new()
	import_world_button.text = "Load World (JSON)"
	import_world_button.focus_mode = Control.FOCUS_NONE
	import_world_button.pressed.connect(_on_import_world_pressed)
	vbox.add_child(import_world_button)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	var hint := Label.new()
	hint.text = "Esc resumes"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(hint)

	_tools_row = _make_circle_row()
	outer_vbox.add_child(_tools_row)
	_build_tools_row()

	_skin_dialog = _make_file_dialog(
		FileDialog.FILE_MODE_OPEN_FILE,
		PackedStringArray(["*.png ; PNG Images", "*.jpg, *.jpeg ; JPEG Images"])
	)
	_skin_dialog.file_selected.connect(_on_skin_file_selected)

	_export_dialog = _make_file_dialog(
		FileDialog.FILE_MODE_SAVE_FILE, PackedStringArray(["*.json ; World JSON"])
	)
	_export_dialog.file_selected.connect(_on_export_file_selected)

	_import_dialog = _make_file_dialog(
		FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.json ; World JSON"])
	)
	_import_dialog.file_selected.connect(_on_import_file_selected)

	SkinManager.skin_loaded.connect(_on_skin_load_succeeded)
	SkinManager.skin_load_failed.connect(_on_skin_load_failed)

	if OS.has_feature("web"):
		WebFilePicker.file_picked.connect(_on_web_file_picked)
		WebFilePicker.file_pick_failed.connect(_on_web_file_pick_failed)

	# Start paused rather than "live": browsers require a real user gesture
	# before Pointer Lock actually engages, so the mouse isn't genuinely
	# captured on load regardless -- opening here matches that reality, and
	# the Resume click doubles as the gesture that lets capture succeed.
	_open()


## A wrapping row of CircleButtons, centered on each line it wraps to --
## used for both the Skins row (above the panel) and Tools row (below it).
func _make_circle_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


## Built once (the set of tools never changes); _refresh_tools_row() then
## just toggles which circle is selected to show the current tool.
## Slot order mirrors BuildModeController's own _slots construction --
## the five shapes in ShapeDefinitions.ORDER, then Delete, Rotate, Edit.
func _build_tools_row() -> void:
	var index := 0
	for shape_id in ShapeDefinitions.ORDER:
		_add_tool_circle(ShapeDefinitions.shape_name(shape_id), index)
		index += 1
	_add_tool_circle("Delete", index)
	index += 1
	_add_tool_circle("Rotate", index)
	index += 1
	_add_tool_circle("Edit", index)


func _add_tool_circle(label: String, slot_index: int) -> void:
	var circle := CircleButton.new()
	circle.label_text = label
	circle.pressed.connect(_on_tool_button_pressed.bind(slot_index))
	_tools_row.add_child(circle)
	_tool_buttons.append({"circle": circle, "slot_index": slot_index})


func _on_tool_button_pressed(slot_index: int) -> void:
	if _build_controller:
		_build_controller.select_slot(slot_index)
	_refresh_tools_row()


func _refresh_tools_row() -> void:
	if _build_controller == null:
		return
	var current_index := _current_slot_index()
	for entry in _tool_buttons:
		entry["circle"].selected = entry["slot_index"] == current_index


func _current_slot_index() -> int:
	match _build_controller.tool_mode:
		BuildModeController.ToolMode.DELETE:
			return ShapeDefinitions.ORDER.size()
		BuildModeController.ToolMode.ROTATE:
			return ShapeDefinitions.ORDER.size() + 1
		BuildModeController.ToolMode.EDIT:
			return ShapeDefinitions.ORDER.size() + 2
		_:
			return ShapeDefinitions.ORDER.find(_build_controller.current_shape_id)


## Rebuilt from scratch each time -- simpler than diffing against
## SkinManager's cache, and this only ever runs on a menu open or a fresh
## import, never per-frame. SkinManager.skin_keys() already reflects every
## skin loaded this session or pulled in from a loaded world file, so this
## covers both "skins I've loaded" and "skins used in this build" for free.
func _refresh_skins_row() -> void:
	for child in _skins_row.get_children():
		child.queue_free()
	if _build_controller == null:
		return

	var none_circle := CircleButton.new()
	none_circle.label_text = "None"
	none_circle.selected = _build_controller.active_skin_key == ""
	none_circle.pressed.connect(_on_skin_button_pressed.bind(""))
	_skins_row.add_child(none_circle)

	for skin_key in SkinManager.skin_keys():
		var circle := CircleButton.new()
		circle.preview_texture = SkinManager.get_cached(skin_key)
		circle.selected = skin_key == _build_controller.active_skin_key
		circle.pressed.connect(_on_skin_button_pressed.bind(skin_key))
		_skins_row.add_child(circle)


func _on_skin_button_pressed(skin_key: String) -> void:
	if _build_controller:
		_build_controller.select_skin(skin_key)
	_refresh_skins_row()


func _make_file_dialog(mode: FileDialog.FileMode, filters: PackedStringArray) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = filters
	dialog.use_native_dialog = true
	dialog.size = Vector2i(640, 420)
	add_child(dialog)
	return dialog


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause_menu"):
		if _paused:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()


## Buttons and other Controls in _content sit on top of the backdrop and
## consume their own clicks first, so this only ever fires for a click that
## landed on the dimmed area outside the panel -- closing the menu is then
## a genuine click gesture, which is the most reliable way to get the
## browser to actually grant Pointer Lock back (more reliable than Escape,
## which carries its own re-lock cooldown after a browser-forced exit).
func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


## Browsers force-exit Pointer Lock on Escape themselves, at the browser
## level, before/instead of delivering that keypress to the page as a
## normal key event -- which meant a first Escape only released the mouse
## (silently, with nothing here ever seeing it) and a second Escape was
## needed to actually open the menu. Watching mouse_mode directly instead
## of only reacting to the action catches that release however it
## happened, so releasing the mouse and opening the menu become the same
## single keypress from the player's perspective.
func _process(_delta: float) -> void:
	if not _paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_open()


func _open() -> void:
	_paused = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status_label.text = ""
	_refresh_tools_row()
	_refresh_skins_row()


func _close() -> void:
	_paused = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_status(text: String, is_error: bool = false) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color", Color(1.0, 0.55, 0.55) if is_error else Color(0.6, 1.0, 0.65)
	)


func _on_import_skin_pressed() -> void:
	if OS.has_feature("web"):
		_pending_web_pick = "skin"
		WebFilePicker.pick_file()
		return
	_skin_dialog.popup_centered()


func _on_skin_file_selected(path: String) -> void:
	SkinManager.load_skin_from_path(path)


func _on_skin_load_succeeded(_texture: Texture2D, skin_key: String) -> void:
	_set_status("Skin '%s' applied -- place a shape to use it" % skin_key)
	_refresh_skins_row()


func _on_skin_load_failed(reason: String) -> void:
	push_warning("Skin load failed: %s" % reason)
	_set_status("Skin load failed: %s" % reason, true)


func _on_export_pressed() -> void:
	if OS.has_feature("web"):
		SaveLoadManager.save_to_browser_download("world.json")
		_set_status("World download started")
	else:
		_export_dialog.popup_centered()


func _on_export_file_selected(path: String) -> void:
	if SaveLoadManager.save_to_path(path):
		_set_status("World saved to %s" % path.get_file())
	else:
		_set_status("Could not save world to %s" % path.get_file(), true)


func _on_import_world_pressed() -> void:
	if OS.has_feature("web"):
		_pending_web_pick = "world"
		WebFilePicker.pick_file()
		return
	_import_dialog.popup_centered()


func _on_import_file_selected(path: String) -> void:
	if SaveLoadManager.load_from_path(path):
		_set_status("World loaded from %s" % path.get_file())
	else:
		_set_status("Could not load world from %s" % path.get_file(), true)


## The Web picker has no OS-level type filter (nothing can appear greyed
## out that way), so a wrong-type pick is only caught here, by extension,
## after the fact.
func _on_web_file_picked(filename: String, payload: String) -> void:
	var pick := _pending_web_pick
	_pending_web_pick = ""
	var lower := filename.to_lower()

	if pick == "skin":
		if not (lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg")):
			_set_status("'%s' isn't a PNG or JPG image" % filename, true)
			return
		SkinManager.load_skin_from_bytes(Marshalls.base64_to_raw(payload), filename)
	elif pick == "world":
		if not lower.ends_with(".json"):
			_set_status("'%s' isn't a world JSON file" % filename, true)
			return
		if SaveLoadManager.load_from_json_text(payload):
			_set_status("World loaded from %s" % filename)
		else:
			_set_status("Could not parse %s as a world file" % filename, true)


func _on_web_file_pick_failed(reason: String) -> void:
	_pending_web_pick = ""
	if reason != "canceled":
		push_warning("File pick failed: %s" % reason)
		_set_status("File pick failed: %s" % reason, true)
