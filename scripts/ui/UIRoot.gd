extends CanvasLayer
class_name UIRoot
## Builds and owns the two independent UI pieces (the collapsible settings
## panel and the build HUD) and handles the one cross-cutting shortcut
## (F1 toggles the whole panel). Main.gd reads settings_panel/build_hud off
## this node to wire BuildModeController signals -- UIRoot itself has no
## idea BuildModeController exists.

var settings_panel: SettingsPanelUI
var build_hud: BuildHUD


func _ready() -> void:
	settings_panel = SettingsPanelUI.new()
	add_child(settings_panel)

	build_hud = BuildHUD.new()
	add_child(build_hud)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ui_panel"):
		settings_panel.visible = not settings_panel.visible
