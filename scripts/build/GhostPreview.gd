extends Node3D
class_name GhostPreview
## Purely visual: a translucent, non-colliding stand-in for whatever the
## player is about to place. BuildModeController tells it what shape/skin/
## transform/validity to show; it has no raycasting or input logic of its
## own so it stays reusable (e.g. for a future "select tool" preview).

const VALID_COLOR := Color(0.35, 1.0, 0.4, 0.45)
const INVALID_COLOR := Color(1.0, 0.35, 0.35, 0.45)

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = VALID_COLOR
	_mesh_instance.material_override = _material

	hide_ghost()


func update_shape(shape_id: int, dims: Dictionary) -> void:
	_mesh_instance.mesh = ShapeFactory.build_mesh(shape_id, dims)


func set_skin(texture: Texture2D) -> void:
	_material.albedo_texture = texture


## Returns a fresh material carrying whatever skin is currently previewed,
## so the placed object doesn't end up sharing (and being mutated by) the
## ghost's own material.
func build_material_for_placement() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = _material.albedo_texture
	return material


## Sets world-space (not local) position/rotation. This node sits under the
## player's Camera3D, which pitches as the player looks up/down -- a local
## rotation.y here would still inherit that pitch from the parent chain, so
## the ghost would visibly tilt with the camera while the actually-placed
## object (added under the flat, unrotated GameManager.world_root) never
## would. global_rotation sidesteps that: it always resolves to exactly
## this world-space yaw, regardless of the camera's current pitch.
func set_transform_data(world_position: Vector3, y_rotation: float) -> void:
	global_position = world_position
	global_rotation = Vector3(0.0, y_rotation, 0.0)


func set_valid(is_valid: bool) -> void:
	_material.albedo_color = VALID_COLOR if is_valid else INVALID_COLOR


func show_ghost() -> void:
	visible = true


func hide_ghost() -> void:
	visible = false
