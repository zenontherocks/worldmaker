extends Node
## Loads user-supplied PNG/JPG images from disk at runtime and turns them
## into textures that can be applied to placed primitives. Kept separate
## from BuildModeController so "how do we get a usable texture" never has to
## know anything about shapes, placement, or the world.

signal skin_loaded(texture: Texture2D, skin_key: String)
signal skin_load_failed(reason: String)

## skin_key -> Texture2D, so re-loading a world build can resolve a texture
## reference by name without re-prompting the user for files already seen
## this session.
var _cache: Dictionary = {}


func load_skin_from_path(path: String) -> void:
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		skin_load_failed.emit("Could not load image '%s' (error %d)" % [path, err])
		return

	var texture := ImageTexture.create_from_image(image)
	var skin_key := path.get_file()
	_cache[skin_key] = texture
	skin_loaded.emit(texture, skin_key)


## Same as load_skin_from_path, but for raw bytes already in memory (the Web
## build's WebFilePicker reads files this way instead of via a real path).
func load_skin_from_bytes(bytes: PackedByteArray, filename: String) -> void:
	var image := Image.new()
	var extension := filename.get_extension().to_lower()
	var err: int
	if extension in ["jpg", "jpeg"]:
		err = image.load_jpg_from_buffer(bytes)
	else:
		err = image.load_png_from_buffer(bytes)
	if err != OK:
		skin_load_failed.emit("Could not decode image '%s' (error %d)" % [filename, err])
		return

	var texture := ImageTexture.create_from_image(image)
	_cache[filename] = texture
	skin_loaded.emit(texture, filename)


func get_cached(skin_key: String) -> Texture2D:
	return _cache.get(skin_key, null)


func has_skin(skin_key: String) -> bool:
	return _cache.has(skin_key)
