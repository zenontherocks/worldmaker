extends PanelContainer
class_name SettingsPanelUI
## Collapsible corner panel for import/export: a PNG/JPG skin and world
## builds as JSON. Talks directly to the SkinManager and SaveLoadManager
## autoloads (both global services, so routing UI actions through Main.gd
## would just add an extra hop) and never touches BuildModeController or
## the player.
##
## Two flows, chosen per click:
## - Web: WebFilePicker opens a plain one-off browser file picker for
##   imports; world export triggers a browser download. Godot's own
##   FileDialog can't help here -- see WebFilePicker's docstring for why.
## - Desktop (including the editor): real, working native FileDialogs,
##   since desktop Godot has unrestricted filesystem access.
##
## A folder-based flow (grant access to one directory once, read/write it
## silently afterward) was tried via LocalDataFolder.gd/web/local-data-
## bridge.js's wm_fs_* functions, using the File System Access API on
## Chromium browsers. It's left in the codebase but disconnected from this
## UI: in practice it added a confusing extra step (grant folder -> then
## pick from an in-game list) without ever being confirmed to work
## end-to-end, so the plain one-off picker below is what's actually wired
## up. Worth revisiting later with a real Godot install to test against,
## rather than blind.

var _collapsed: bool = false
var _content: VBoxContainer
var _collapse_button: Button
var _pending_web_pick: String = ""

## Visible feedback for the whole import/export flow. push_warning() alone
## isn't enough here -- it's a debug-only channel that never shows up
## anywhere in a deployed Web build, so any failure would otherwise be
## completely silent to an actual player.
var _status_label: Label

var _skin_dialog: FileDialog
var _export_dialog: FileDialog
var _import_dialog: FileDialog


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -280
	offset_right = -12
	offset_top = 12
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(268, 0)

	var outer := VBoxContainer.new()
	add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)

	var title := Label.new()
	title.text = "Build Settings"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_collapse_button = Button.new()
	_collapse_button.text = "-"
	_collapse_button.custom_minimum_size = Vector2(28, 28)
	_collapse_button.focus_mode = Control.FOCUS_NONE
	_collapse_button.pressed.connect(_on_collapse_pressed)
	header.add_child(_collapse_button)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	outer.add_child(_content)

	var import_skin_button := Button.new()
	import_skin_button.text = "Import Skin (PNG/JPG)"
	import_skin_button.focus_mode = Control.FOCUS_NONE
	import_skin_button.pressed.connect(_on_import_skin_pressed)
	_content.add_child(import_skin_button)

	var export_button := Button.new()
	export_button.text = "Export World (JSON)"
	export_button.focus_mode = Control.FOCUS_NONE
	export_button.pressed.connect(_on_export_pressed)
	_content.add_child(export_button)

	var import_world_button := Button.new()
	import_world_button.text = "Import World (JSON)"
	import_world_button.focus_mode = Control.FOCUS_NONE
	import_world_button.pressed.connect(_on_import_world_pressed)
	_content.add_child(import_world_button)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status_label)

	var hint := Label.new()
	hint.text = "F1 toggles this panel  |  Esc releases the mouse"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_content.add_child(hint)

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


func _make_file_dialog(mode: FileDialog.FileMode, filters: PackedStringArray) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = filters
	dialog.use_native_dialog = true
	dialog.size = Vector2i(640, 420)
	dialog.canceled.connect(_recapture_mouse)
	add_child(dialog)
	return dialog


func _recapture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_status(text: String, is_error: bool = false) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color", Color(1.0, 0.55, 0.55) if is_error else Color(0.6, 1.0, 0.65)
	)


func _on_collapse_pressed() -> void:
	_collapsed = not _collapsed
	_content.visible = not _collapsed
	_collapse_button.text = "+" if _collapsed else "-"


func _on_import_skin_pressed() -> void:
	if OS.has_feature("web"):
		_pending_web_pick = "skin"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		WebFilePicker.pick_file(".png,.jpg,.jpeg")
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_skin_dialog.popup_centered()


func _on_skin_file_selected(path: String) -> void:
	SkinManager.load_skin_from_path(path)
	_recapture_mouse()


func _on_skin_load_succeeded(_texture: Texture2D, skin_key: String) -> void:
	_set_status("Skin '%s' applied -- place a shape to use it" % skin_key)


func _on_skin_load_failed(reason: String) -> void:
	push_warning("Skin load failed: %s" % reason)
	_set_status("Skin load failed: %s" % reason, true)


func _on_export_pressed() -> void:
	if OS.has_feature("web"):
		SaveLoadManager.save_to_browser_download("world.json")
		_set_status("World download started")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_export_dialog.popup_centered()


func _on_export_file_selected(path: String) -> void:
	if SaveLoadManager.save_to_path(path):
		_set_status("World saved to %s" % path.get_file())
	else:
		_set_status("Could not save world to %s" % path.get_file(), true)
	_recapture_mouse()


func _on_import_world_pressed() -> void:
	if OS.has_feature("web"):
		_pending_web_pick = "world"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		WebFilePicker.pick_file(".json")
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_import_dialog.popup_centered()


func _on_import_file_selected(path: String) -> void:
	if SaveLoadManager.load_from_path(path):
		_set_status("World loaded from %s" % path.get_file())
	else:
		_set_status("Could not load world from %s" % path.get_file(), true)
	_recapture_mouse()


func _on_web_file_picked(filename: String, payload: String) -> void:
	var pick := _pending_web_pick
	_pending_web_pick = ""
	if pick == "skin":
		SkinManager.load_skin_from_bytes(Marshalls.base64_to_raw(payload), filename)
	elif pick == "world":
		if SaveLoadManager.load_from_json_text(payload):
			_set_status("World loaded from %s" % filename)
		else:
			_set_status("Could not parse %s as a world file" % filename, true)
	_recapture_mouse()


func _on_web_file_pick_failed(reason: String) -> void:
	_pending_web_pick = ""
	if reason != "canceled":
		push_warning("File pick failed: %s" % reason)
		_set_status("File pick failed: %s" % reason, true)
	_recapture_mouse()
