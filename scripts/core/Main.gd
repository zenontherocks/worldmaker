extends Node3D
## Composition root: the only script allowed to reach into both the player
## rig and the UI to wire them together. Everything it connects could also
## be discovered independently by its target (e.g. via autoloads), but
## BuildModeController <-> BuildHUD signals are the one link that isn't
## naturally global, so it's made explicit here rather than hidden inside
## either node.

@onready var _world: Node3D = $World
@onready var _player: PlayerController = $Player
@onready var _ui: UIRoot = $UI


func _ready() -> void:
	GameManager.register_world(_world)

	var build_controller := _player.get_node("Camera3D/BuildController") as BuildModeController
	build_controller.build_mode_changed.connect(_ui.build_hud.on_build_mode_changed)
	build_controller.shape_changed.connect(_ui.build_hud.on_shape_changed)
	build_controller.dimensions_changed.connect(_ui.build_hud.on_dimensions_changed)
	build_controller.active_field_changed.connect(_ui.build_hud.on_active_field_changed)
