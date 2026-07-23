extends Node
## Serializes everything under GameManager.world_root to the world-build
## JSON schema and rebuilds a world from it. Two write paths exist because
## browsers cannot write to an arbitrary OS path: desktop exports write
## straight to disk, HTML5 exports trigger a browser download instead.
##
## JSON schema (version 1):
## {
##   "version": 1,
##   "objects": [
##     {
##       "id": 1,
##       "shape": "box",              # ShapeDefinitions shape key
##       "dimensions": {"width":1.0, "height":1.0, "depth":1.0},
##       "position": [x, y, z],
##       "rotation": [x, y, z],       # radians
##       "skin": "concrete.png"       # SkinManager cache key, "" if none
##     }
##   ]
## }

const SAVE_VERSION: int = 1


func export_world_to_json() -> String:
	var objects := []
	if GameManager.world_root:
		for child in GameManager.world_root.get_children():
			if child is PlaceableObject:
				objects.append(child.to_dict())
	var data := {"version": SAVE_VERSION, "objects": objects}
	return JSON.stringify(data, "\t")


func save_to_path(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveLoadManager: could not open '%s' for writing" % path)
		return false
	file.store_string(export_world_to_json())
	file.close()
	return true


## HTML5 export path: browsers can't be handed a filesystem path to save to,
## so the JSON is pushed to the user as a normal browser file download.
func save_to_browser_download(file_name: String = "world.json") -> void:
	if not OS.has_feature("web"):
		push_warning("save_to_browser_download called outside of a Web export")
		return
	var bytes := export_world_to_json().to_utf8_buffer()
	JavaScriptBridge.download_buffer(bytes, file_name, "application/json")


func load_from_path(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveLoadManager: could not open '%s' for reading" % path)
		return false
	var text := file.get_as_text()
	file.close()
	return load_from_json_text(text)


func load_from_json_text(text: String) -> bool:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("objects"):
		push_warning("SaveLoadManager: malformed world JSON")
		return false

	_clear_world()
	for object_data in parsed["objects"]:
		_spawn_object(object_data)
	return true


func _clear_world() -> void:
	if not GameManager.world_root:
		return
	for child in GameManager.world_root.get_children():
		child.queue_free()
	GameManager.reset_id_counter()
	GameManager.notify_world_cleared()


func _spawn_object(object_data: Dictionary) -> void:
	var shape_id := ShapeDefinitions.shape_id_from_key(object_data.get("shape", "box"))
	var dims: Dictionary = object_data.get("dimensions", {})
	var skin_key: String = object_data.get("skin", "")

	var material: Material = null
	if skin_key != "" and SkinManager.has_skin(skin_key):
		var std_material := StandardMaterial3D.new()
		std_material.albedo_texture = SkinManager.get_cached(skin_key)
		material = std_material

	var instance := ShapeFactory.create_instance(shape_id, dims, material)

	var pos: Array = object_data.get("position", [0.0, 0.0, 0.0])
	var rot: Array = object_data.get("rotation", [0.0, 0.0, 0.0])
	instance.position = Vector3(pos[0], pos[1], pos[2])
	instance.rotation = Vector3(rot[0], rot[1], rot[2])
	instance.skin_key = skin_key
	instance.object_id = GameManager.get_next_id()

	GameManager.world_root.add_child(instance)
