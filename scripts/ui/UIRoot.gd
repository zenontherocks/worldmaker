extends CanvasLayer
class_name UIRoot
## Builds and owns the three independent UI pieces: the build HUD, the
## pause menu, and the crosshair. Main.gd reads build_hud off this node to
## wire BuildModeController signals -- UIRoot itself has no idea
## BuildModeController exists. The pause menu owns its own Esc shortcut
## directly (it needs PROCESS_MODE_ALWAYS to keep working while paused, so
## there's no benefit to routing that through UIRoot instead). The
## crosshair needs no wiring at all -- it's purely decorative.

var pause_menu: PauseMenuUI
var build_hud: BuildHUD


func _ready() -> void:
	pause_menu = PauseMenuUI.new()
	add_child(pause_menu)

	build_hud = BuildHUD.new()
	add_child(build_hud)

	add_child(Crosshair.new())
