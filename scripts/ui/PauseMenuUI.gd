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
var _tool_buttons: Array = []  ## [{"button": Button, "slot_index": int}]

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

	_content = PanelContainer.new()
	_content.custom_minimum_size = Vector2(380, 0)
	centering.add_child(_content)

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

	vbox.add_child(_make_section_label("Tools"))
	_tools_row = HFlowContainer.new()
	vbox.add_child(_tools_row)
	_build_tools_row()

	vbox.add_child(_make_section_label("Skins"))
	_skins_row = HFlowContainer.new()
	vbox.add_child(_skins_row)

	var import_skin_button := Button.new()
	import_skin_button.text = "Import Skin (PNG/JPG)"
	import_skin_button.focus_mode = Control.FOCUS_NONE
	import_skin_button.pressed.connect(_on_import_skin_pressed)
	vbox.add_child(import_skin_button)

	var export_button := Button.new()
	export_button.text = "Export World (JSON)"
	export_button.focus_mode = Control.FOCUS_NONE
	export_button.pressed.connect(_on_export_pressed)
	vbox.add_child(export_button)

	var import_world_button := Button.new()
	import_world_button.text = "Import World (JSON)"
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


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	return label


## Built once (the set of tools never changes); _refresh_tools_row() then
## just toggles which button is disabled to show the current selection.
## Slot order mirrors BuildModeController's own _slots construction --
## the five shapes in ShapeDefinitions.ORDER, then Delete, Rotate, Edit.
func _build_tools_row() -> void:
	var index := 0
	for shape_id in ShapeDefinitions.ORDER:
		_add_tool_button(ShapeDefinitions.shape_name(shape_id), index)
		index += 1
	_add_tool_button("Delete", index)
	index += 1
	_add_tool_button("Rotate", index)
	index += 1
	_add_tool_button("Edit", index)


func _add_tool_button(label: String, slot_index: int) -> void:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_tool_button_pressed.bind(slot_index))
	_tools_row.add_child(button)
	_tool_buttons.append({"button": button, "slot_index": slot_index})


func _on_tool_button_pressed(slot_index: int) -> void:
	if _build_controller:
		_build_controller.select_slot(slot_index)
	_refresh_tools_row()


func _refresh_tools_row() -> void:
	if _build_controller == null:
		return
	var current_index := _current_slot_index()
	for entry in _tool_buttons:
		entry["button"].disabled = entry["slot_index"] == current_index


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
## import, never per-frame.
func _refresh_skins_row() -> void:
	for child in _skins_row.get_children():
		child.queue_free()
	if _build_controller == null:
		return

	var none_button := Button.new()
	none_button.text = "None"
	none_button.focus_mode = Control.FOCUS_NONE
	none_button.disabled = _build_controller.active_skin_key == ""
	none_button.pressed.connect(_on_skin_button_pressed.bind(""))
	_skins_row.add_child(none_button)

	for skin_key in SkinManager.skin_keys():
		var button := Button.new()
		button.text = skin_key
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = skin_key == _build_controller.active_skin_key
		button.pressed.connect(_on_skin_button_pressed.bind(skin_key))
		_skins_row.add_child(button)


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
