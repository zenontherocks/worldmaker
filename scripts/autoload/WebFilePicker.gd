extends Node
## Thin bridge to a plain HTML <input type="file"> picker
## (web/local-data-bridge.js's wmPickFile) -- the one file-picking mechanism
## that's actually native and universal across browsers (Firefox and its
## forks, e.g. Zen Browser; Safari; Chromium-based browsers all support it).
## Each call opens an ordinary one-off OS file picker, same as clicking
## "attach a file" on any website; there's no persisted folder or filter --
## deliberately no <input accept> restriction either, so nothing in the OS
## dialog can ever appear greyed out for type reasons. Callers validate the
## picked filename themselves after the fact (see PauseMenuUI).
##
## Godot's own FileDialog can't do this on Web in any browser: DisplayServer
## never reports FEATURE_NATIVE_DIALOG_FILE for the Web platform, so
## use_native_dialog silently does nothing there and it always falls back to
## Godot's own in-engine dialog browsing an empty virtual filesystem instead
## of anything real on the player's disk.
##
## The JS side hands its result back via a plain global object polled from
## _process(), rather than a JavaScriptBridge.create_callback callback --
## every callback-based JS-to-Godot return path tried in this project has
## at some point failed to fire with no error on either side, while
## JavaScriptBridge.eval() has been reliable in both directions throughout.
## Polling trades a few frames of latency for that reliability.
##
## Runs with PROCESS_MODE_ALWAYS: it's only ever used while the pause menu
## (which pauses the tree) is open, so its poll must keep running under
## SceneTree.paused == true or it would simply never see the result.

signal file_picked(filename: String, text_or_base64: String)
signal file_pick_failed(reason: String)

const _POLL_EXPR := "window.wmFileResult ? JSON.stringify(window.wmFileResult) : ''"
const _CLEAR_EXPR := "window.wmFileResult = null"

var _polling: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


## Picked file's payload arrives via file_picked: for a .json file it's the
## file's text, otherwise base64-encoded raw bytes (decode with
## Marshalls.base64_to_raw()). Canceling emits file_pick_failed("canceled").
func pick_file() -> void:
	if _polling:
		return
	JavaScriptBridge.eval("window.wmPickFile()", true)
	_polling = true
	set_process(true)


func _process(_delta: float) -> void:
	var raw = JavaScriptBridge.eval(_POLL_EXPR, true)
	if typeof(raw) != TYPE_STRING or raw == "":
		return

	_polling = false
	set_process(false)
	JavaScriptBridge.eval(_CLEAR_EXPR, true)

	var result = JSON.parse_string(raw)
	if typeof(result) != TYPE_DICTIONARY:
		file_pick_failed.emit("Malformed response from browser")
		return

	if result.get("success", false):
		file_picked.emit(result.get("name", ""), result.get("payload", ""))
	else:
		file_pick_failed.emit(String(result.get("name", "Unknown error")))
