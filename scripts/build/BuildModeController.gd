extends Node3D
class_name BuildModeController
## Owns build state (active tool, live dimensions, rotation, active skin)
## and orchestrates raycasting + placement. The whole game is build mode --
## there's no separate "enter/exit" toggle -- so this is always running
## (modulo the pause menu, which stops it for free via SceneTree.paused
## like everything else with the default PROCESS_MODE_PAUSABLE). Lives
## under the player's Camera3D so its raycast always matches the look
## direction. Talks to the rest of the game only through signals and the
## ShapeFactory/GameManager/SkinManager services, plus a handful of public
## methods (select_slot/select_skin) the pause menu calls directly via the
## reference Main.gd hands it -- it never reaches into the UI itself.
##
## [E] cycles through seven tools: the five placeable shapes, then Delete,
## then Rotate. The pause menu's Tools row offers the same seven directly,
## via select_slot(). Delete and Rotate both target whatever placed object
## the crosshair is over (found via the same raycast used for placement)
## and highlight it by temporarily swapping its mesh's material; Delete
## removes it on click, Rotate spins it in place with the same R/Shift+R
## (and T/Shift+T) keys that adjust a pending placement's rotation.

enum ToolMode { PLACE, DELETE, ROTATE }

signal shape_changed(shape_id: int, dimensions: Dictionary)
signal dimensions_changed(dimensions: Dictionary)
signal active_field_changed(field_key: String)
signal tool_mode_changed(mode: int, slot_number: int, slot_count: int)

@export var place_range: float = 8.0
@export var rotation_step_degrees: float = 15.0
## Placements snap their horizontal (X/Z) position to a world-space grid of
## this size, so shapes line up with each other -- vertical (Y) position is
## deliberately left alone, since it's already determined by whatever
## surface the raycast hit.
@export var grid_size: float = 1.0

@onready var ray_cast: RayCast3D = get_parent().get_node("RayCast3D")
@onready var ghost: GhostPreview = $GhostPreview

var tool_mode: int = ToolMode.PLACE
var current_shape_id: int = ShapeDefinitions.ShapeType.BOX
var current_dimensions: Dictionary = {}

## Which cached SkinManager texture new placements use; "" means the
## default (unskinned) material. Settable directly by the pause menu's
## Skins row via select_skin(), not just by importing a new image.
var active_skin_key: String = ""

var _slots: Array = []
var _slot_index: int = 0
var _active_field_index: int = 0

## Offset applied on top of the player's current facing direction, so
## placements default to facing the same way the player is looking instead
## of a fixed world direction; R/Shift+R still let a placement be nudged
## further without physically turning to face it.
var _rotation_offset: float = 0.0

var _has_valid_target: bool = false
var _target_position: Vector3 = Vector3.ZERO

var _highlighted_object: PlaceableObject = null
var _highlighted_original_material: Material = null
var _delete_highlight_material: StandardMaterial3D
var _rotate_highlight_material: StandardMaterial3D


func _ready() -> void:
	ray_cast.enabled = true
	ray_cast.target_position = Vector3(0, 0, -place_range)
	SkinManager.skin_loaded.connect(_on_skin_loaded)

	for shape_id in ShapeDefinitions.ORDER:
		_slots.append({"mode": ToolMode.PLACE, "shape_id": shape_id})
	_slots.append({"mode": ToolMode.DELETE})
	_slots.append({"mode": ToolMode.ROTATE})

	_delete_highlight_material = _make_highlight_material(Color(1.0, 0.25, 0.2, 0.6))
	_rotate_highlight_material = _make_highlight_material(Color(0.25, 0.7, 1.0, 0.6))

	# Deferred so its signal emissions land after Main.gd's _ready() (which
	# runs after all its children's, including this one) has actually
	# connected them to BuildHUD -- otherwise this initial state emits into
	# a HUD that isn't listening yet and shows blank until the player's
	# first interaction.
	call_deferred("select_slot", 0)


func _make_highlight_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func _physics_process(_delta: float) -> void:
	ray_cast.force_raycast_update()

	if tool_mode == ToolMode.PLACE:
		_process_place_target()
	else:
		_process_targeted_object()


func _process_place_target() -> void:
	_has_valid_target = ray_cast.is_colliding()
	if _has_valid_target:
		var point: Vector3 = ray_cast.get_collision_point()
		var normal: Vector3 = ray_cast.get_collision_normal()
		var offset := ShapeFactory.vertical_offset(current_shape_id, current_dimensions)
		_target_position = point + normal * offset
		_target_position.x = snappedf(_target_position.x, grid_size)
		_target_position.z = snappedf(_target_position.z, grid_size)
		ghost.set_transform_data(_target_position, _current_facing_y() + _rotation_offset)
		ghost.set_valid(true)
	else:
		ghost.set_valid(false)


func _process_targeted_object() -> void:
	var candidate: PlaceableObject = null
	if ray_cast.is_colliding():
		var collider := ray_cast.get_collider()
		if collider is PlaceableObject:
			candidate = collider
	_set_highlighted(candidate)


func _set_highlighted(candidate: PlaceableObject) -> void:
	if candidate == _highlighted_object:
		return
	_clear_highlight()
	if candidate != null and candidate.mesh_instance != null:
		_highlighted_object = candidate
		_highlighted_original_material = candidate.mesh_instance.material_override
		candidate.mesh_instance.material_override = (
			_delete_highlight_material if tool_mode == ToolMode.DELETE else _rotate_highlight_material
		)


func _clear_highlight() -> void:
	if _highlighted_object != null and is_instance_valid(_highlighted_object) and _highlighted_object.mesh_instance != null:
		_highlighted_object.mesh_instance.material_override = _highlighted_original_material
	_highlighted_object = null
	_highlighted_original_material = null


func _current_facing_y() -> float:
	# BuildModeController lives under the Camera3D, which only ever pitches
	# (yaw is applied to the player body instead -- see PlayerCamera.gd), so
	# the camera's own global Y rotation already equals the body's facing.
	return get_parent().global_rotation.y


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_cycle_shape"):
		select_slot((_slot_index + 1) % _slots.size())
	elif event.is_action_pressed("build_cycle_dimension"):
		if tool_mode == ToolMode.PLACE:
			_cycle_active_field()
	elif event.is_action_pressed("build_dimension_increase"):
		if tool_mode == ToolMode.PLACE:
			_adjust_active_field(1.0)
	elif event.is_action_pressed("build_dimension_decrease"):
		if tool_mode == ToolMode.PLACE:
			_adjust_active_field(-1.0)
	elif event.is_action_pressed("build_rotate_cw"):
		_rotate(rotation_step_degrees)
	elif event.is_action_pressed("build_rotate_ccw"):
		_rotate(-rotation_step_degrees)
	elif event.is_action_pressed("build_tilt_cw"):
		_tilt(rotation_step_degrees)
	elif event.is_action_pressed("build_tilt_ccw"):
		_tilt(-rotation_step_degrees)
	elif event.is_action_pressed("build_place"):
		_confirm()


func _update_ghost_visibility() -> void:
	if tool_mode == ToolMode.PLACE:
		ghost.show_ghost()
	else:
		ghost.hide_ghost()


## Public: called both by [E] cycling above and directly by the pause
## menu's Tools row buttons (via the reference Main.gd hands it).
func select_slot(index: int) -> void:
	_clear_highlight()
	_slot_index = index
	var slot: Dictionary = _slots[_slot_index]
	tool_mode = slot["mode"]

	if tool_mode == ToolMode.PLACE:
		current_shape_id = slot["shape_id"]
		current_dimensions = ShapeDefinitions.default_dimensions(current_shape_id)
		_active_field_index = 0
		ghost.update_shape(current_shape_id, current_dimensions)
		shape_changed.emit(current_shape_id, current_dimensions)
		active_field_changed.emit(_active_dimension_key())

	_update_ghost_visibility()
	tool_mode_changed.emit(tool_mode, _slot_index + 1, _slots.size())


## Public: called by the pause menu's Skins row. "" selects the default
## (unskinned) material.
func select_skin(skin_key: String) -> void:
	active_skin_key = skin_key
	ghost.set_skin(SkinManager.get_cached(skin_key) if skin_key != "" else null)


func _cycle_active_field() -> void:
	var fields := ShapeDefinitions.dimension_fields(current_shape_id)
	_active_field_index = (_active_field_index + 1) % fields.size()
	active_field_changed.emit(_active_dimension_key())


func _adjust_active_field(direction: float) -> void:
	var fields := ShapeDefinitions.dimension_fields(current_shape_id)
	var field: Dictionary = fields[_active_field_index]
	var new_value: float = current_dimensions[field["key"]] + field["step"] * direction
	current_dimensions[field["key"]] = ShapeDefinitions.clamp_dimension(
		current_shape_id, field["key"], new_value
	)
	ghost.update_shape(current_shape_id, current_dimensions)
	dimensions_changed.emit(current_dimensions)


## R/Shift+R: spins the horizontal facing -- a pending placement's offset in
## Place mode, or the targeted object's own Y rotation directly in Rotate
## mode.
func _rotate(delta_degrees: float) -> void:
	match tool_mode:
		ToolMode.PLACE:
			_rotation_offset = wrapf(_rotation_offset + deg_to_rad(delta_degrees), 0.0, TAU)
		ToolMode.ROTATE:
			if _highlighted_object != null and is_instance_valid(_highlighted_object):
				_highlighted_object.rotation.y = wrapf(
					_highlighted_object.rotation.y + deg_to_rad(delta_degrees), 0.0, TAU
				)


## T/Shift+T: tips the targeted object around a horizontal axis instead
## (e.g. standing a cylinder up vs. laying it on its side). Rotate-tool
## only -- there's no equivalent for a pending placement.
func _tilt(delta_degrees: float) -> void:
	if tool_mode == ToolMode.ROTATE and _highlighted_object != null and is_instance_valid(_highlighted_object):
		_highlighted_object.rotation.x = wrapf(
			_highlighted_object.rotation.x + deg_to_rad(delta_degrees), 0.0, TAU
		)


func _active_dimension_key() -> String:
	var fields := ShapeDefinitions.dimension_fields(current_shape_id)
	return fields[_active_field_index]["key"]


func _confirm() -> void:
	match tool_mode:
		ToolMode.PLACE:
			_place_current()
		ToolMode.DELETE:
			_delete_targeted()


func _place_current() -> void:
	if not _has_valid_target:
		return

	var material := ghost.build_material_for_placement()
	var instance := ShapeFactory.create_instance(current_shape_id, current_dimensions, material)
	instance.position = _target_position
	instance.rotation.y = _current_facing_y() + _rotation_offset
	instance.skin_key = active_skin_key
	instance.object_id = GameManager.get_next_id()

	if GameManager.world_root:
		GameManager.world_root.add_child(instance)


func _delete_targeted() -> void:
	if _highlighted_object == null or not is_instance_valid(_highlighted_object):
		return
	var target := _highlighted_object
	_highlighted_object = null
	_highlighted_original_material = null
	target.queue_free()


func _on_skin_loaded(texture: Texture2D, skin_key: String) -> void:
	ghost.set_skin(texture)
	active_skin_key = skin_key
