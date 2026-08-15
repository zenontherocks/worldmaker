extends Node
## Loads user-supplied PNG/JPG images from disk at runtime and turns them
## into textures that can be applied to placed primitives. Also resolves a
## "skin_key" -- everywhere else in the codebase that stores what a placed
## object looks like (BuildModeController.active_skin_key,
## PlaceableObject.skin_key, the world JSON's per-object "skin" field) --
## into an actual material, whether that key names an imported texture or
## (per is_color_key()) is a solid color's own hex string acting as its own
## key. Kept separate from BuildModeController so "how do we get a usable
## material" never has to know anything about shapes, placement, or the
## world.

signal skin_loaded(texture: Texture2D, skin_key: String)
signal skin_load_failed(reason: String)
signal color_used(hex: String)

## skin_key -> Texture2D, so re-loading a world build can resolve a texture
## reference by name without re-prompting the user for files already seen
## this session.
var _cache: Dictionary = {}

## skin_key -> the original PNG/JPG bytes, kept alongside the decoded
## texture purely so SaveLoadManager can embed them back into a saved world
## JSON (see its docstring for why: skins otherwise wouldn't survive a
## reload, since there's deliberately no server-side image storage to
## re-fetch them from).
var _bytes_cache: Dictionary = {}

## Hex color strings ("#rrggbb") picked via the pause menu's Colors column,
## in first-used order -- unlike an image, a color is small enough to just
## re-derive from its own key, so there's no bytes_cache equivalent needed
## for save/reload.
var _used_colors: Array[String] = []


func load_skin_from_path(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		skin_load_failed.emit("Could not read image '%s'" % path)
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	load_skin_from_bytes(bytes, path.get_file())


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
	_bytes_cache[filename] = bytes
	skin_loaded.emit(texture, filename)


func get_cached(skin_key: String) -> Texture2D:
	return _cache.get(skin_key, null)


func get_bytes(skin_key: String) -> PackedByteArray:
	return _bytes_cache.get(skin_key, PackedByteArray())


func has_skin(skin_key: String) -> bool:
	return _cache.has(skin_key)


## All skin keys imported so far this session, for the pause menu's Skins
## selector -- letting the player switch back to an earlier import instead
## of only ever using whichever one was imported most recently.
func skin_keys() -> Array:
	return _cache.keys()


## True if skin_key names a solid color (its own "#rrggbb" hex string)
## rather than an imported texture's filename -- image filenames never
## start with "#", so this is an unambiguous, allocation-free check that
## lets the rest of the codebase treat active_skin_key/skin_key as one
## opaque string without needing a separate field for "which kind is it."
func is_color_key(skin_key: String) -> bool:
	return skin_key.begins_with("#")


## Records hex (already validated and normalized by the caller) as used,
## if not already known, and notifies listeners -- mirrors skin_loaded's
## role for imported textures, so the pause menu's Colors column can add a
## new circle immediately.
func register_color(hex: String) -> void:
	if hex in _used_colors:
		return
	_used_colors.append(hex)
	color_used.emit(hex)


## All colors used so far this session, for the pause menu's Colors
## selector -- same role as skin_keys() above, for colors instead of
## textures.
func used_colors() -> Array:
	return _used_colors.duplicate()


## The one place a skin_key (color or texture, or "" for none) turns into
## an actual material -- used both for a live placement and for rebuilding
## a placed object on world-load, so those two paths can't drift apart on
## how they resolve the same key.
func build_material(skin_key: String) -> StandardMaterial3D:
	if skin_key == "":
		return null
	if is_color_key(skin_key):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.html(skin_key)
		return material
	if has_skin(skin_key):
		var material := StandardMaterial3D.new()
		material.albedo_texture = get_cached(skin_key)
		return material
	return null
