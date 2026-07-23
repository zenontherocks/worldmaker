extends StaticBody3D
class_name PlaceableObject
## Attached (via set_script, from ShapeFactory) to every primitive that gets
## placed into the world. Holds exactly the metadata needed to serialize the
## object to/from the world-build JSON format, and knows how to re-skin
## itself. Deliberately has no idea how build mode, raycasting, or the UI
## work -- it is pure data plus a couple of self-contained operations.

var shape_id: int = ShapeDefinitions.ShapeType.BOX
var dimensions: Dictionary = {}
var skin_key: String = ""
var object_id: int = -1

## Set by ShapeFactory right after instancing so this node never has to
## depend on child node names/order via get_node().
var mesh_instance: MeshInstance3D = null


func apply_skin(texture: Texture2D, key: String) -> void:
	if mesh_instance == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	mesh_instance.material_override = material
	skin_key = key


func to_dict() -> Dictionary:
	return {
		"id": object_id,
		"shape": ShapeDefinitions.shape_key(shape_id),
		"dimensions": dimensions,
		"position": [position.x, position.y, position.z],
		"rotation": [rotation.x, rotation.y, rotation.z],
		"skin": skin_key,
	}
