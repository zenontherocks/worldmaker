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
## Laid out as a symmetrical cross: the central panel (New World, Save
## World, Load World, then Resume last) in the middle, a Skins card above
## it, an Objects & Tools card below it (two separate rows -- shapes, then
## Empty Hands/Delete/Rotate/Edit), a Colors card to its left, and a Quick
## Loads card to its right (same width as the Colors card, filling in
## the space that used to be an empty reserved spacer). Every card shares
## one StyleBoxFlat (_card_style) and every section heading shares one
## label style (_make_section_label()) so the
## whole thing reads as one uniform layout instead of loose floating rows
## -- all built from code (no image/font assets), so this stays free in
## download size. None of it can live on the always-on BuildHUD: the mouse
## is pointer-locked (invisible, driving camera look) during live
## gameplay and only becomes a visible, clickable cursor once _open() below
## switches to MOUSE_MODE_VISIBLE, so anything clickable has to be part of
## this paused overlay.
##
## The Skins card's first circle ("+jpg/png") triggers the same import
## flow the center panel's file actions use -- there's deliberately no
## separate "Load Skin" button anymore, and no dedicated "clear to
## unskinned" circle either (picking a Color already overrides any texture
## skin, which covers the practical case).
##
## A solid color is not a separate concept from a texture skin -- it fills
## the exact same active_skin_key slot on BuildModeController (as its own
## "#rrggbb" hex string, see SkinManager.is_color_key()), so picking one
## deselects the other automatically: both the Skins row and Colors column
## just re-read the same shared active_skin_key to decide what's selected.
##
## Two flows for the file buttons, chosen per button, exactly as before:
## - Web: WebFilePicker opens a plain, unfiltered browser file picker for
##   imports; world export triggers a browser download. Godot's own
##   FileDialog can't help here -- see WebFilePicker's docstring for why.
## - Desktop (including the editor): real, working native FileDialogs,
##   since desktop Godot has unrestricted filesystem access.
##
## Quick Loads (SaveLoadManager.record_recent_save()/list_recent_saves())
## is a third way to get a world back besides Load World's file dialog:
## every successful Save World click also drops a timestamped copy under
## user://recent_saves, and this card lists the newest few with a
## one-click load, capped and pruned by SaveLoadManager.MAX_RECENT_SAVES.
## That directory is ordinary Godot save data, not a file the player
## picked, so it works identically on both platforms and (crucially for
## Web, where saving is otherwise just a one-way browser download)
## survives a page reload via Godot's own IndexedDB-backed persistence
## for user:// on HTML5 -- no custom JS bridge needed for this one, unlike
## WebFilePicker.
##
## This entire node (and its FileDialog children) runs with
## PROCESS_MODE_ALWAYS so it keeps working while the tree is paused --
## that's the whole point of a pause menu.

var _paused: bool = false
var _content: PanelContainer
var _build_controller: BuildModeController = null

## _close() requests Pointer Lock; it doesn't guarantee it -- the browser
## grants or denies that asynchronously, entirely outside Godot's control,
## and (deliberately, as an anti-abuse measure) tends to reject a request
## made in the first moment right after the tab/window regains focus. Without
## this grace window, _process() below would immediately reinterpret that
## rejection as "the browser kicked us out, re-pause" and snap the menu back
## open before the request had any real chance to land -- which is what
## made a Resume click look like it silently did nothing right after
## switching back to the tab. Doesn't (can't) make the browser grant it any
## faster; just stops the poll from preempting a request that might still
## be about to succeed.
const _RECAPTURE_GRACE_MS := 300
var _last_close_time_ms: int = -_RECAPTURE_GRACE_MS

## Browsers grant Pointer Lock reliably from a click but are much stingier
## about granting it from a keyboard activation (Esc) -- a restriction the
## grace window above can't work around, since it only buys a pending
## request more time, and a keyboard-triggered request is the wrong *kind*
## of gesture to begin with, not just a late one. So an Esc-triggered
## _close() doesn't ask for capture itself at all; it sets this flag and
## waits for the player's next real click to reach PlayerCamera's own
## click-recapture fallback (see that script's _unhandled_input), which is
## a genuine click gesture and reliably succeeds. While this is true,
## _process() below stays quiet instead of reinterpreting "not captured
## yet" as "browser kicked us out, reopen."
var _awaiting_click_recapture: bool = false

## Shared by every card (Skins/Objects & Tools/Colors/the central panel)
## so they read as one uniform layout -- built once in _ready(), not per
## card, since a StyleBoxFlat is just rendering parameters and Godot
## allows the same Resource to back multiple theme overrides safely.
var _card_style: StyleBoxFlat

var _objects_row: HFlowContainer  ## the five shapes
var _tools_row: HFlowContainer  ## Delete/Rotate/Edit only
var _tool_buttons: Array = []  ## [{"circle": CircleButton, "slot_index": int}]

var _skins_row: HFlowContainer

var _colors_row: HFlowContainer
var _hex_input: LineEdit
var _color_wheel: ColorWheel

var _quick_loads_list: VBoxContainer

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
	_refresh_colors_row()
	_refresh_quick_loads()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	visible = false

	_card_style = _make_card_style()

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

	# CenterContainer only centers a single child, so the whole cross
	# layout lives inside this HBoxContainer: Colors card (left), the
	# Skins/panel/Objects&Tools column (center), an empty spacer (right,
	# same width as the Colors card) reserved for something later.
	var outer_hbox := HBoxContainer.new()
	outer_hbox.add_theme_constant_override("separation", 16)
	centering.add_child(outer_hbox)

	outer_hbox.add_child(_make_colors_column())

	# Skins card, the central panel, and the Objects & Tools card stack as
	# one column -- this also solves the flow rows' wrapping: a
	# FlowContainer only wraps into multiple lines when its parent
	# actually assigns it a width to wrap within, and VBoxContainer
	# (unlike CenterContainer) stretches children to its own width by
	# default -- so each row ends up exactly as wide as the panel and
	# wraps into "a row or two" as more circles get added, instead of
	# every circle stacking into its own single-item line.
	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 16)
	outer_hbox.add_child(outer_vbox)

	var skins_section := VBoxContainer.new()
	skins_section.add_theme_constant_override("separation", 8)
	skins_section.add_child(_make_section_label("Skins"))
	_skins_row = _make_circle_row()
	skins_section.add_child(_skins_row)
	outer_vbox.add_child(_make_section_card(skins_section))

	_content = PanelContainer.new()
	_content.custom_minimum_size = Vector2(380, 0)
	_content.add_theme_stylebox_override("panel", _card_style)
	outer_vbox.add_child(_content)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_content.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var new_world_button := Button.new()
	new_world_button.text = "New World"
	new_world_button.focus_mode = Control.FOCUS_NONE
	new_world_button.pressed.connect(_on_new_world_pressed)
	vbox.add_child(new_world_button)

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

	var resume_button := Button.new()
	resume_button.text = "Resume"
	resume_button.focus_mode = Control.FOCUS_NONE
	resume_button.pressed.connect(_close)
	vbox.add_child(resume_button)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	var hint := Label.new()
	hint.text = "Esc resumes"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(hint)

	var objects_tools_section := VBoxContainer.new()
	objects_tools_section.add_theme_constant_override("separation", 8)
	objects_tools_section.add_child(_make_section_label("Objects & Tools"))
	_objects_row = _make_circle_row()
	objects_tools_section.add_child(_objects_row)
	_tools_row = _make_circle_row()
	objects_tools_section.add_child(_tools_row)
	outer_vbox.add_child(_make_section_card(objects_tools_section))
	_build_objects_and_tools()

	outer_hbox.add_child(_make_quick_loads_column())

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
	SkinManager.color_used.connect(_on_color_used)

	if OS.has_feature("web"):
		WebFilePicker.file_picked.connect(_on_web_file_picked)
		WebFilePicker.file_pick_failed.connect(_on_web_file_pick_failed)

	# Start paused rather than "live": browsers require a real user gesture
	# before Pointer Lock actually engages, so the mouse isn't genuinely
	# captured on load regardless -- opening here matches that reality, and
	# the Resume click doubles as the gesture that lets capture succeed.
	_open()


## A wrapping row of CircleButtons, centered on each line it wraps to --
## used for the Skins row, the Objects row, the Tools row, and the Colors
## card's own row of swatches.
func _make_circle_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


## One shared translucent-rounded-rect style for every card in this menu
## (Skins/Objects & Tools/Colors/the central panel) so they read as one
## uniform layout -- pure code, no image asset, so this costs nothing in
## download size.
func _make_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.06)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	return style


## Consistent section heading style (Skins/Objects & Tools/Colors) --
## bumped size and a brighter tone than the muted hint text below the
## central panel, so headings read as headers rather than fine print.
func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	return label


func _make_section_card(content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_style)
	panel.add_child(content)
	return panel


## The left-side card: a heading, the ring+triangle ColorWheel, a hex text
## input, and a wrapping row of solid-color swatches for colors already
## used. Narrower than the panel (custom_minimum_size below) so it reads
## as its own column rather than a second full-width row -- still wide
## enough for a few swatches per line before wrapping, same "give the row
## a real width" fix the Skins/Objects/Tools rows rely on (this
## VBoxContainer stretches _colors_row to its own width, same as
## outer_vbox does for those).
func _make_colors_column() -> PanelContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(200, 0)
	column.add_theme_constant_override("separation", 8)

	column.add_child(_make_section_label("Colors"))

	_color_wheel = ColorWheel.new()
	_color_wheel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_color_wheel.color_changed.connect(_on_color_wheel_changed)
	_color_wheel.color_committed.connect(_on_color_wheel_committed)
	column.add_child(_color_wheel)

	_hex_input = LineEdit.new()
	_hex_input.placeholder_text = "#hexcode"
	_hex_input.text_submitted.connect(_on_hex_color_submitted)
	column.add_child(_hex_input)

	_colors_row = _make_circle_row()
	column.add_child(_colors_row)

	return _make_section_card(column)


## The right-side card, filling in the space previously left empty. A
## plain vertical list of ordinary Buttons rather than the circle rows
## everything else uses -- each entry needs to show a real timestamp
## label, which the fixed-diameter CircleButton has no room for (unlike
## the single short word/thumbnail every other circle shows).
func _make_quick_loads_column() -> PanelContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(200, 0)
	column.add_theme_constant_override("separation", 8)

	column.add_child(_make_section_label("Quick Loads"))

	_quick_loads_list = VBoxContainer.new()
	_quick_loads_list.add_theme_constant_override("separation", 4)
	column.add_child(_quick_loads_list)

	return _make_section_card(column)


## Built once (the set never changes); _refresh_tools_row() then just
## toggles which circle is selected to show the current tool. Slot order
## mirrors BuildModeController's own _slots construction -- the five
## shapes in ShapeDefinitions.ORDER (into _objects_row), then Empty Hands,
## Delete, Rotate, Edit (into _tools_row) -- split into two rows so shapes
## and tools read as visually distinct, even though they still share one
## slot-index space and one _tool_buttons list under the hood.
func _build_objects_and_tools() -> void:
	var index := 0
	for shape_id in ShapeDefinitions.ORDER:
		_add_tool_circle(_objects_row, ShapeDefinitions.shape_name(shape_id), index)
		index += 1
	_add_tool_circle(_tools_row, "Empty\nHands", index)
	index += 1
	_add_tool_circle(_tools_row, "Delete", index)
	index += 1
	_add_tool_circle(_tools_row, "Rotate", index)
	index += 1
	_add_tool_circle(_tools_row, "Edit", index)


func _add_tool_circle(row: HFlowContainer, label: String, slot_index: int) -> void:
	var circle := CircleButton.new()
	circle.label_text = label
	circle.pressed.connect(_on_tool_button_pressed.bind(slot_index))
	row.add_child(circle)
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
		BuildModeController.ToolMode.EMPTY:
			return ShapeDefinitions.ORDER.size()
		BuildModeController.ToolMode.DELETE:
			return ShapeDefinitions.ORDER.size() + 1
		BuildModeController.ToolMode.ROTATE:
			return ShapeDefinitions.ORDER.size() + 2
		BuildModeController.ToolMode.EDIT:
			return ShapeDefinitions.ORDER.size() + 3
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

	# An action, not a persisted selection -- never shown selected, unlike
	# every other circle in this row.
	var import_circle := CircleButton.new()
	import_circle.label_text = "+jpg/png"
	import_circle.pressed.connect(_on_import_skin_pressed)
	_skins_row.add_child(import_circle)

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
	# A texture skin and a color share one active_skin_key slot (see the
	# class docstring), so picking a texture here must un-highlight
	# whichever color circle was previously selected.
	_refresh_colors_row()


## Same rebuild-from-scratch approach as _refresh_skins_row(), and for the
## same reason: this only runs on open/select, never per-frame.
## SkinManager.used_colors() already reflects every color entered this
## session or pulled in from a loaded world file. Also syncs the
## ColorWheel's marker positions to the currently active color, if it is
## one, so reopening the menu shows where you left off.
func _refresh_colors_row() -> void:
	for child in _colors_row.get_children():
		child.queue_free()
	if _build_controller == null:
		return

	var active_key: String = _build_controller.active_skin_key
	if SkinManager.is_color_key(active_key):
		_color_wheel.set_color(Color.html(active_key))

	for hex in SkinManager.used_colors():
		var circle := CircleButton.new()
		circle.swatch_color = Color.html(hex)
		circle.selected = hex == active_key
		circle.pressed.connect(_on_color_circle_pressed.bind(hex))
		_colors_row.add_child(circle)


func _on_color_circle_pressed(hex: String) -> void:
	if _build_controller:
		_build_controller.select_color(hex)
	_color_wheel.set_color(Color.html(hex))
	_refresh_colors_row()
	_refresh_skins_row()


func _on_color_used(_hex: String) -> void:
	_refresh_colors_row()


## Rebuilt from scratch on every open plus every save/quick-load -- same
## tear-down-and-rebuild approach as the Skins/Colors rows, and just as
## cheap here since it's capped at SaveLoadManager.MAX_RECENT_SAVES
## entries and only runs on those infrequent events, never per-frame.
func _refresh_quick_loads() -> void:
	for child in _quick_loads_list.get_children():
		child.queue_free()

	var entries := SaveLoadManager.list_recent_saves()
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No saves yet"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_quick_loads_list.add_child(empty_label)
		return

	for entry in entries:
		var button := Button.new()
		button.text = _format_recent_save_label(entry["timestamp"])
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_quick_load_pressed.bind(entry))
		_quick_loads_list.add_child(button)


func _on_quick_load_pressed(entry: Dictionary) -> void:
	var label := _format_recent_save_label(entry["timestamp"])
	if SaveLoadManager.load_from_path(entry["path"]):
		_set_status("Loaded quick save from %s" % label)
	else:
		_set_status("Could not load quick save from %s" % label, true)
	_refresh_quick_loads()
	_refresh_skins_row()
	_refresh_colors_row()


const _MONTH_NAMES := [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]


## Local time, not UTC -- a quick-load timestamp is meant to answer "when
## did I make this" from the player's own perspective, not the server's
## (there being no server at all is rather the point of this project).
func _format_recent_save_label(timestamp: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(timestamp, false)
	var hour12: int = d["hour"] % 12
	if hour12 == 0:
		hour12 = 12
	var am_pm := "AM" if d["hour"] < 12 else "PM"
	return "%s %d, %d:%02d %s" % [_MONTH_NAMES[d["month"] - 1], d["day"], hour12, d["minute"], am_pm]


## Live drag feedback -- updates the active color and the hex field's
## readout on every drag step, but doesn't touch SkinManager's used-colors
## history (that only happens once, on release; see _on_color_wheel_committed())
## so fine-tuning a drag doesn't flood the Colors row with near-duplicate
## swatches.
func _on_color_wheel_changed(new_color: Color) -> void:
	var hex := "#" + new_color.to_html(false)
	_hex_input.text = hex
	if _build_controller:
		_build_controller.select_color(hex)


func _on_color_wheel_committed(new_color: Color) -> void:
	var hex := "#" + new_color.to_html(false)
	SkinManager.register_color(hex)
	_refresh_colors_row()
	_refresh_skins_row()


## Empty/whitespace input is a no-op (e.g. hitting Enter in an empty field)
## rather than an error -- only a genuinely malformed hex string counts as
## a mistake worth surfacing.
func _on_hex_color_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return
	if not Color.html_is_valid(trimmed):
		_set_status("'%s' isn't a valid hex color" % text, true)
		return

	# Normalized form (always "#rrggbb", no alpha) so equivalent inputs --
	# "3fae02", "#3FAE02", "3fae02ff" -- collapse to the same used-colors
	# entry instead of piling up near-duplicate swatches.
	var hex := "#" + Color.html(trimmed).to_html(false)
	SkinManager.register_color(hex)
	if _build_controller:
		_build_controller.select_color(hex)
	_color_wheel.set_color(Color.html(hex))
	_hex_input.text = ""
	_refresh_colors_row()
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
			_close(false)
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
## single keypress from the player's perspective. Gated by
## _RECAPTURE_GRACE_MS (see its declaration) so this doesn't preempt a
## Resume click's own still-pending (or just-rejected) recapture attempt.
func _process(_delta: float) -> void:
	if _awaiting_click_recapture:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_awaiting_click_recapture = false
		return
	if not _paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if Time.get_ticks_msec() - _last_close_time_ms >= _RECAPTURE_GRACE_MS:
			_open()


func _open() -> void:
	_paused = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_awaiting_click_recapture = false
	_status_label.text = ""
	_refresh_tools_row()
	_refresh_skins_row()
	_refresh_colors_row()
	_refresh_quick_loads()


## force_recapture is false only for the Esc path (see
## _awaiting_click_recapture's declaration for why Esc can't just request
## capture directly the way a click can).
func _close(force_recapture: bool = true) -> void:
	_paused = false
	visible = false
	get_tree().paused = false
	if force_recapture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_last_close_time_ms = Time.get_ticks_msec()
	else:
		_awaiting_click_recapture = true


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


## Wipes the current build back to a blank slate -- placed objects,
## imported skins, and used colors all gone, and the active tool/skin/
## rotation state reset -- without the page reload a browser "refresh"
## would need. Order matters: the world's objects reference skin_keys that
## SkinManager.reset() is about to invalidate, so the world has to go
## first; BuildModeController.reset_for_new_world() goes last since it
## also clears active_skin_key, which would otherwise still point at a
## skin/color that just stopped existing.
func _on_new_world_pressed() -> void:
	SaveLoadManager.clear_world()
	SkinManager.reset()
	if _build_controller:
		_build_controller.reset_for_new_world()
	_hex_input.text = ""
	_set_status("New world started")
	_refresh_tools_row()
	_refresh_skins_row()
	_refresh_colors_row()


func _on_export_pressed() -> void:
	if OS.has_feature("web"):
		SaveLoadManager.save_to_browser_download("world.json")
		_set_status("World download started")
		_refresh_quick_loads()
	else:
		_export_dialog.popup_centered()


func _on_export_file_selected(path: String) -> void:
	if SaveLoadManager.save_to_path(path):
		_set_status("World saved to %s" % path.get_file())
		_refresh_quick_loads()
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
