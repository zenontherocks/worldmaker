extends CanvasLayer
class_name PauseMenuUI
## Esc-triggered pause menu: dims the screen, stops gameplay via
## SceneTree.paused, and holds the only three things worth interrupting play
## for -- importing a skin image, exporting the world to a file, and
## importing a world file back in. Talks directly to the SkinManager and
## SaveLoadManager autoloads (both global services, so routing through
## Main.gd would just add an extra hop) and never touches
## BuildModeController or the player directly; pausing the tree is what
## actually stops them (both have the default PROCESS_MODE_PAUSABLE).
##
## Two flows, chosen per button, exactly as before:
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

## Visible feedback for the whole import/export flow -- push_warning() alone
## isn't enough here, it's a debug-only channel that never shows up anywhere
## in a deployed Web build, so any failure would otherwise be completely
## silent to an actual player.
var _status_label: Label

var _pending_web_pick: String = ""

var _skin_dialog: FileDialog
var _export_dialog: FileDialog
var _import_dialog: FileDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	visible = false

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_content = PanelContainer.new()
	_content.set_anchors_preset(Control.PRESET_CENTER)
	_content.custom_minimum_size = Vector2(300, 0)
	backdrop.add_child(_content)

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


func _open() -> void:
	_paused = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status_label.text = ""


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
