extends PanelContainer
class_name SettingsPanelUI
## Collapsible corner panel for import/export: a PNG/JPG skin and world
## builds as JSON. Talks directly to the SkinManager, SaveLoadManager and
## LocalDataFolder autoloads (all global services, so routing UI actions
## through Main.gd would just add an extra hop) and never touches
## BuildModeController or the player.
##
## Two different flows share these three buttons, chosen per click based on
## LocalDataFolder.is_supported():
## - Supported (Chromium browsers): everything reads/writes one folder on
##   the player's disk, chosen once via LocalDataFolder.choose_folder().
##   Skins are picked from an in-game list of that folder's images; world
##   save/load silently reads/writes "world.json" in the same folder.
## - Unsupported (desktop, or Firefox/Safari): the older FileDialog/
##   browser-download flow, which needs no special browser feature.

var _collapsed: bool = false
var _content: VBoxContainer
var _collapse_button: Button

var _folder_status_label: Label
var _pending_folder_action: String = ""

var _skin_picker: PopupPanel
var _skin_item_list: ItemList

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

	if LocalDataFolder.is_supported():
		var choose_folder_button := Button.new()
		choose_folder_button.text = "Choose Data Folder..."
		choose_folder_button.focus_mode = Control.FOCUS_NONE
		choose_folder_button.pressed.connect(_on_choose_folder_pressed)
		_content.add_child(choose_folder_button)

		_folder_status_label = Label.new()
		_folder_status_label.text = "No data folder chosen yet"
		_folder_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_folder_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		_content.add_child(_folder_status_label)

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

	_skin_picker = PopupPanel.new()
	_skin_picker.popup_hide.connect(_recapture_mouse)
	add_child(_skin_picker)

	var picker_vbox := VBoxContainer.new()
	_skin_picker.add_child(picker_vbox)

	var picker_title := Label.new()
	picker_title.text = "Choose a skin from your data folder"
	picker_vbox.add_child(picker_title)

	_skin_item_list = ItemList.new()
	_skin_item_list.custom_minimum_size = Vector2(260, 240)
	_skin_item_list.item_selected.connect(_on_skin_item_selected)
	picker_vbox.add_child(_skin_item_list)

	SkinManager.skin_load_failed.connect(_on_skin_load_failed)

	if LocalDataFolder.is_supported():
		LocalDataFolder.folder_chosen.connect(_on_folder_chosen)
		LocalDataFolder.folder_choice_failed.connect(_on_folder_choice_failed)
		LocalDataFolder.image_list_ready.connect(_on_image_list_ready)
		LocalDataFolder.image_list_failed.connect(_on_image_list_failed)
		LocalDataFolder.image_bytes_ready.connect(_on_image_bytes_ready)
		LocalDataFolder.image_read_failed.connect(_on_image_read_failed)
		LocalDataFolder.world_saved.connect(_on_world_saved)
		LocalDataFolder.world_loaded.connect(_on_world_loaded)


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


## Runs `action` immediately if a data folder is already chosen, otherwise
## prompts for one first and runs `action` once it's picked. Shared by all
## three buttons' "supported browser" path so the folder-picking prompt
## only has to be wired up once.
func _ensure_folder_then(action: String) -> void:
	if LocalDataFolder.has_folder:
		_run_folder_action(action)
		return
	_pending_folder_action = action
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LocalDataFolder.choose_folder()


func _run_folder_action(action: String) -> void:
	match action:
		"import_skin":
			LocalDataFolder.request_image_list()
		"export_world":
			LocalDataFolder.save_world_text(SaveLoadManager.export_world_to_json())
		"import_world":
			LocalDataFolder.load_world_text()


func _on_choose_folder_pressed() -> void:
	_pending_folder_action = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LocalDataFolder.choose_folder()


func _on_folder_chosen(folder_name: String) -> void:
	_recapture_mouse()
	if _folder_status_label:
		_folder_status_label.text = "Data folder: %s" % folder_name
	if _pending_folder_action != "":
		var action := _pending_folder_action
		_pending_folder_action = ""
		_run_folder_action(action)


func _on_folder_choice_failed(reason: String) -> void:
	_recapture_mouse()
	_pending_folder_action = ""
	push_warning("Could not choose data folder: %s" % reason)


func _on_import_skin_pressed() -> void:
	if LocalDataFolder.is_supported():
		_ensure_folder_then("import_skin")
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_skin_dialog.popup_centered()


func _on_skin_file_selected(path: String) -> void:
	SkinManager.load_skin_from_path(path)
	_recapture_mouse()


func _on_skin_load_failed(reason: String) -> void:
	push_warning("Skin load failed: %s" % reason)


func _on_image_list_ready(filenames: Array) -> void:
	_skin_item_list.clear()
	for filename in filenames:
		_skin_item_list.add_item(filename)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_skin_picker.popup_centered()


func _on_image_list_failed(reason: String) -> void:
	push_warning("Could not list data folder images: %s" % reason)


func _on_skin_item_selected(index: int) -> void:
	var filename := _skin_item_list.get_item_text(index)
	LocalDataFolder.request_image_bytes(filename)
	_skin_picker.hide()


func _on_image_bytes_ready(filename: String, bytes: PackedByteArray) -> void:
	SkinManager.load_skin_from_bytes(bytes, filename)


func _on_image_read_failed(filename: String, reason: String) -> void:
	push_warning("Could not read '%s' from data folder: %s" % [filename, reason])


func _on_export_pressed() -> void:
	if LocalDataFolder.is_supported():
		_ensure_folder_then("export_world")
	elif OS.has_feature("web"):
		SaveLoadManager.save_to_browser_download("world.json")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_export_dialog.popup_centered()


func _on_export_file_selected(path: String) -> void:
	SaveLoadManager.save_to_path(path)
	_recapture_mouse()


func _on_world_saved(success: bool, reason: String) -> void:
	if not success:
		push_warning("Could not save world to data folder: %s" % reason)


func _on_import_world_pressed() -> void:
	if LocalDataFolder.is_supported():
		_ensure_folder_then("import_world")
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_import_dialog.popup_centered()


func _on_import_file_selected(path: String) -> void:
	SaveLoadManager.load_from_path(path)
	_recapture_mouse()


func _on_world_loaded(success: bool, text: String) -> void:
	if success:
		SaveLoadManager.load_from_json_text(text)
	else:
		push_warning("Could not load world from data folder: %s" % text)
