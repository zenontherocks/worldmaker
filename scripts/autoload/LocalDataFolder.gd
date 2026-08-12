extends Node
## Bridges to web/local-data-bridge.js (injected into the exported page via
## export_presets.cfg's html/head_include) to read and write a single
## folder on the player's own disk through the browser's File System
## Access API: skins are listed/read from it, and the world save file is
## written to and loaded from it too. Nothing is ever uploaded anywhere.
##
## Only Chromium-based browsers (Chrome, Edge, Opera) support this API as
## of this writing -- Firefox and Safari do not. is_supported() reports
## this so callers (SkinManager, SaveLoadManager, SettingsPanelUI) can fall
## back to the ordinary FileDialog/download flow when it's false. Desktop
## exports never use this at all; native FileDialog access to the real
## filesystem already works there without any of this.

signal folder_chosen(folder_name: String)
signal folder_choice_failed(reason: String)
signal image_list_ready(filenames: Array)
signal image_list_failed(reason: String)
signal image_bytes_ready(filename: String, bytes: PackedByteArray)
signal image_read_failed(filename: String, reason: String)
signal world_saved(success: bool, reason: String)
signal world_loaded(success: bool, text: String)

var has_folder: bool = false

var _window: JavaScriptObject = null
var _supported: bool = false


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_window = JavaScriptBridge.get_interface("window")
	_supported = bool(JavaScriptBridge.eval("wm_fs_supported()", true))


func is_supported() -> bool:
	return _supported


func choose_folder() -> void:
	print("[LocalDataFolder] choose_folder: calling into JS")
	var callback := JavaScriptBridge.create_callback(_on_folder_chosen)
	_window.wm_fs_choose_folder(callback)
	print("[LocalDataFolder] choose_folder: JS call returned (async result pending)")


func request_image_list() -> void:
	var callback := JavaScriptBridge.create_callback(_on_image_list)
	_window.wm_fs_list_images(callback)


func request_image_bytes(filename: String) -> void:
	var callback := JavaScriptBridge.create_callback(_on_image_bytes.bind(filename))
	_window.wm_fs_read_image(filename, callback)


func save_world_text(text: String, filename: String = "world.json") -> void:
	var callback := JavaScriptBridge.create_callback(_on_world_saved)
	_window.wm_fs_write_text(filename, text, callback)


func load_world_text(filename: String = "world.json") -> void:
	var callback := JavaScriptBridge.create_callback(_on_world_loaded)
	_window.wm_fs_read_text(filename, callback)


func _on_folder_chosen(args: Array) -> void:
	print("[LocalDataFolder] _on_folder_chosen: callback fired from JS, args = ", args)
	var success: bool = args[0]
	var payload: String = args[1]
	if success:
		has_folder = true
		folder_chosen.emit(payload)
	else:
		folder_choice_failed.emit(payload)


func _on_image_list(args: Array) -> void:
	var success: bool = args[0]
	var payload: String = args[1]
	if not success:
		image_list_failed.emit(payload)
		return
	var parsed = JSON.parse_string(payload)
	image_list_ready.emit(parsed if parsed is Array else [])


func _on_image_bytes(args: Array, filename: String) -> void:
	var success: bool = args[0]
	var payload: String = args[1]
	if success:
		image_bytes_ready.emit(filename, Marshalls.base64_to_raw(payload))
	else:
		image_read_failed.emit(filename, payload)


func _on_world_saved(args: Array) -> void:
	world_saved.emit(args[0], args[1])


func _on_world_loaded(args: Array) -> void:
	world_loaded.emit(args[0], args[1])
