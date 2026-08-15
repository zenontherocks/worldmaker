extends Node
## Serializes everything under GameManager.world_root to the world-build
## JSON schema and rebuilds a world from it. Two write paths exist because
## browsers cannot write to an arbitrary OS path: desktop exports write
## straight to disk, HTML5 exports trigger a browser download instead.
##
## JSON schema (version 2):
## {
##   "version": 2,
##   "skins": {
##     "concrete.png": "<base64-encoded PNG/JPG bytes>"
##   },
##   "objects": [
##     {
##       "id": 1,
##       "shape": "box",              # ShapeDefinitions shape key
##       "dimensions": {"width":1.0, "height":1.0, "depth":1.0},
##       "position": [x, y, z],
##       "rotation": [x, y, z],       # radians
##       "skin": "concrete.png"       # key into "skins" above, "" if none,
##                                     # or a solid color's own "#rrggbb"
##                                     # (see SkinManager.is_color_key())
##     }
##   ]
## }
##
## Skin images are embedded directly in the world file rather than just
## referenced by name -- there's deliberately no server anywhere in this
## project to re-fetch them from (see SkinManager's docstring), so a name-
## only reference would only resolve for as long as SkinManager's
## in-memory, session-only cache happens to still hold that image. A v1
## file (no "skins" key) still loads fine, it just places any skinned
## objects unskinned, exactly like it always did.

const SAVE_VERSION: int = 2


func export_world_to_json() -> String:
	var objects := []
	var skins := {}
	if GameManager.world_root:
		for child in GameManager.world_root.get_children():
			if child is PlaceableObject:
				objects.append(child.to_dict())
				var skin_key: String = child.skin_key
				if skin_key != "" and not skins.has(skin_key) and SkinManager.has_skin(skin_key):
					skins[skin_key] = Marshalls.raw_to_base64(SkinManager.get_bytes(skin_key))
	var data := {"version": SAVE_VERSION, "skins": skins, "objects": objects}
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

	var skins = parsed.get("skins", {})
	if typeof(skins) == TYPE_DICTIONARY:
		for skin_key in skins:
			SkinManager.load_skin_from_bytes(Marshalls.base64_to_raw(skins[skin_key]), skin_key)

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
	if SkinManager.is_color_key(skin_key):
		SkinManager.register_color(skin_key)

	var material := SkinManager.build_material(skin_key)
	var instance := ShapeFactory.create_instance(shape_id, dims, material)

	var pos: Array = object_data.get("position", [0.0, 0.0, 0.0])
	var rot: Array = object_data.get("rotation", [0.0, 0.0, 0.0])
	instance.position = Vector3(pos[0], pos[1], pos[2])
	instance.rotation = Vector3(rot[0], rot[1], rot[2])
	instance.skin_key = skin_key
	instance.object_id = GameManager.get_next_id()

	GameManager.world_root.add_child(instance)
