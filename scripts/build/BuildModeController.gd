extends Node3D
class_name BuildModeController
## Owns build-mode state (active shape, live dimensions, rotation, active
## skin) and orchestrates raycasting + placement. Lives under the player's
## Camera3D so its raycast always matches the look direction. Talks to the
## rest of the game only through signals and the ShapeFactory/GameManager/
## SkinManager services -- it never reaches into the UI directly.

signal build_mode_changed(active: bool)
signal shape_changed(shape_id: int, dimensions: Dictionary)
signal dimensions_changed(dimensions: Dictionary)
signal active_field_changed(field_key: String)

@export var place_range: float = 8.0
@export var rotation_step_degrees: float = 15.0

@onready var ray_cast: RayCast3D = get_parent().get_node("RayCast3D")
@onready var ghost: GhostPreview = $GhostPreview

var active: bool = false

var _shape_index: int = 0
var current_shape_id: int = ShapeDefinitions.ShapeType.BOX
var current_dimensions: Dictionary = {}
var _active_field_index: int = 0
var _rotation_y: float = 0.0

var _has_valid_target: bool = false
var _target_position: Vector3 = Vector3.ZERO
var _active_skin_key: String = ""


func _ready() -> void:
	ray_cast.enabled = true
	ray_cast.target_position = Vector3(0, 0, -place_range)
	SkinManager.skin_loaded.connect(_on_skin_loaded)
	_select_shape(0)


func _physics_process(_delta: float) -> void:
	if not active:
		return

	ray_cast.force_raycast_update()
	_has_valid_target = ray_cast.is_colliding()
	if _has_valid_target:
		var point: Vector3 = ray_cast.get_collision_point()
		var normal: Vector3 = ray_cast.get_collision_normal()
		var offset := ShapeFactory.vertical_offset(current_shape_id, current_dimensions)
		_target_position = point + normal * offset
		ghost.set_transform_data(_target_position, _rotation_y)
		ghost.set_valid(true)
	else:
		ghost.set_valid(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode_toggle"):
		_set_active(not active)
		return

	if not active:
		return

	if event.is_action_pressed("build_cycle_shape"):
		_select_shape((_shape_index + 1) % ShapeDefinitions.ORDER.size())
	elif event.is_action_pressed("build_cycle_dimension"):
		_cycle_active_field()
	elif event.is_action_pressed("build_dimension_increase"):
		_adjust_active_field(1.0)
	elif event.is_action_pressed("build_dimension_decrease"):
		_adjust_active_field(-1.0)
	elif event.is_action_pressed("build_rotate_cw"):
		_rotate(rotation_step_degrees)
	elif event.is_action_pressed("build_rotate_ccw"):
		_rotate(-rotation_step_degrees)
	elif event.is_action_pressed("build_place"):
		_place_current()


func _set_active(value: bool) -> void:
	active = value
	if active:
		ghost.show_ghost()
	else:
		ghost.hide_ghost()
	build_mode_changed.emit(active)


func _select_shape(index: int) -> void:
	_shape_index = index
	current_shape_id = ShapeDefinitions.ORDER[_shape_index]
	current_dimensions = ShapeDefinitions.default_dimensions(current_shape_id)
	_active_field_index = 0
	ghost.update_shape(current_shape_id, current_dimensions)
	shape_changed.emit(current_shape_id, current_dimensions)
	active_field_changed.emit(_active_dimension_key())


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


func _rotate(delta_degrees: float) -> void:
	_rotation_y = wrapf(_rotation_y + deg_to_rad(delta_degrees), 0.0, TAU)


func _active_dimension_key() -> String:
	var fields := ShapeDefinitions.dimension_fields(current_shape_id)
	return fields[_active_field_index]["key"]


func _place_current() -> void:
	if not _has_valid_target:
		return

	var material := ghost.build_material_for_placement()
	var instance := ShapeFactory.create_instance(current_shape_id, current_dimensions, material)
	instance.position = _target_position
	instance.rotation.y = _rotation_y
	instance.skin_key = _active_skin_key
	instance.object_id = GameManager.get_next_id()

	if GameManager.world_root:
		GameManager.world_root.add_child(instance)


func _on_skin_loaded(texture: Texture2D, skin_key: String) -> void:
	ghost.set_skin(texture)
	_active_skin_key = skin_key
