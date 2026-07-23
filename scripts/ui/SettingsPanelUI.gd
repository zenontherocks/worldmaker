extends PanelContainer
class_name SettingsPanelUI
## Collapsible corner panel for the web-friendly import/export workflow:
## importing a PNG/JPG skin and exporting/importing world builds as JSON.
## Talks directly to the SkinManager and SaveLoadManager autoloads (both
## are global services, so routing UI actions through Main.gd would just
## add an extra hop) and never touches BuildModeController or the player.

var _collapsed: bool = false
var _content: VBoxContainer
var _collapse_button: Button

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
	_collapse_button.pressed.connect(_on_collapse_pressed)
	header.add_child(_collapse_button)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	outer.add_child(_content)

	var import_skin_button := Button.new()
	import_skin_button.text = "Import Skin (PNG/JPG)"
	import_skin_button.pressed.connect(_on_import_skin_pressed)
	_content.add_child(import_skin_button)

	var export_button := Button.new()
	export_button.text = "Export World (JSON)"
	export_button.pressed.connect(_on_export_pressed)
	_content.add_child(export_button)

	var import_world_button := Button.new()
	import_world_button.text = "Import World (JSON)"
	import_world_button.pressed.connect(_on_import_world_pressed)
	_content.add_child(import_world_button)

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

	SkinManager.skin_load_failed.connect(_on_skin_load_failed)


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


func _on_collapse_pressed() -> void:
	_collapsed = not _collapsed
	_content.visible = not _collapsed
	_collapse_button.text = "+" if _collapsed else "-"


func _on_import_skin_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_skin_dialog.popup_centered()


func _on_skin_file_selected(path: String) -> void:
	SkinManager.load_skin_from_path(path)
	_recapture_mouse()


func _on_skin_load_failed(reason: String) -> void:
	push_warning("Skin load failed: %s" % reason)


func _on_export_pressed() -> void:
	if OS.has_feature("web"):
		SaveLoadManager.save_to_browser_download("world.json")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_export_dialog.popup_centered()


func _on_export_file_selected(path: String) -> void:
	SaveLoadManager.save_to_path(path)
	_recapture_mouse()


func _on_import_world_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_import_dialog.popup_centered()


func _on_import_file_selected(path: String) -> void:
	SaveLoadManager.load_from_path(path)
	_recapture_mouse()
