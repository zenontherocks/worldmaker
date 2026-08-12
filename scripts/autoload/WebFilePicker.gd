extends Node
## Thin bridge to a plain HTML <input type="file"> picker
## (web/local-data-bridge.js's wm_pick_file) -- the universal Web fallback
## for browsers without the File System Access API (Firefox and its forks,
## e.g. Zen Browser; Safari). Unlike LocalDataFolder there's no persisted
## folder here: each call opens an ordinary one-off OS file picker, same as
## clicking "attach a file" on any website.
##
## Godot's own FileDialog can't do this on Web in any browser:
## DisplayServer never reports FEATURE_NATIVE_DIALOG_FILE for the Web
## platform, so use_native_dialog silently does nothing there and it
## always falls back to Godot's own in-engine dialog browsing an empty
## virtual filesystem instead of anything real on the player's disk.

signal file_picked(filename: String, text_or_base64: String)
signal file_pick_failed(reason: String)

var _window: JavaScriptObject = null


func _ready() -> void:
	if OS.has_feature("web"):
		_window = JavaScriptBridge.get_interface("window")


## `accept` is a standard <input accept> filter string, e.g.
## ".png,.jpg,.jpeg" or ".json". The picked file's payload arrives via
## file_picked: for a .json file it's the file's text, otherwise
## base64-encoded raw bytes (matches LocalDataFolder's image convention,
## decode with Marshalls.base64_to_raw()).
func pick_file(accept: String) -> void:
	var callback := JavaScriptBridge.create_callback(_on_file_picked)
	_window.wm_pick_file(accept, callback)


func _on_file_picked(args: Array) -> void:
	var success: bool = args[0]
	var filename_or_reason: String = args[1]
	if not success:
		file_pick_failed.emit(filename_or_reason)
		return
	var payload: String = args[2]
	file_picked.emit(filename_or_reason, payload)
