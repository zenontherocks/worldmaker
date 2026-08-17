extends Node3D
## Composition root: the only script allowed to reach into both the player
## rig and the UI to wire them together. Everything it connects could also
## be discovered independently by its target (e.g. via autoloads), but
## BuildModeController isn't itself global (it lives under the player's
## camera) and both BuildHUD and PauseMenuUI need it, so wiring that up
## here keeps it visible in one small file instead of scattered @onready
## reach-ins.

@onready var _world: Node3D = $World
@onready var _player: PlayerController = $Player
@onready var _ui: UIRoot = $UI
@onready var _terrain: TerrainStreamer = $Terrain


func _ready() -> void:
	GameManager.register_world(_world)
	_terrain.set_player(_player)

	var build_controller := _player.get_node("Camera3D/BuildController") as BuildModeController
	build_controller.shape_changed.connect(_ui.build_hud.on_shape_changed)
	build_controller.dimensions_changed.connect(_ui.build_hud.on_dimensions_changed)
	build_controller.active_field_changed.connect(_ui.build_hud.on_active_field_changed)
	build_controller.tool_mode_changed.connect(_ui.build_hud.on_tool_mode_changed)
	build_controller.edit_target_changed.connect(_ui.build_hud.on_edit_target_changed)
	build_controller.edit_target_cleared.connect(_ui.build_hud.on_edit_target_cleared)
	build_controller.snap_toggled.connect(_ui.build_hud.on_snap_toggled)

	_ui.pause_menu.set_build_controller(build_controller)
