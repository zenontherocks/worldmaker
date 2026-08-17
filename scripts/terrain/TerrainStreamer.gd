extends Node3D
class_name TerrainStreamer
## Keeps a ring of terrain chunks loaded around the player and frees ones
## left behind, so the world has walkable ground everywhere instead of the
## old fixed-size Ground plane's hard edge. Main.gd hands this the player
## reference via set_player() -- this node's own _ready() runs before
## Main.gd's (Godot calls a node's _ready() only after its children's),
## so the initial eager chunk block below is built around world origin
## (the player's known spawn point, see Main.tscn's Player transform)
## rather than player position, which wouldn't be set yet.

const VIEW_DISTANCE_CHUNKS := 4
const UNLOAD_HYSTERESIS_CHUNKS := 2
const CHUNKS_GENERATED_PER_FRAME := 1

## Built synchronously in _ready(), before returning -- physics can tick
## before this node's first budgeted _process() call runs, so without an
## eager block the player would fall through empty space for a frame or
## more right after the scene loads. 3x3 chunks is sub-millisecond work.
const EAGER_RADIUS_CHUNKS := 1

var _noise := TerrainNoise.new()
var _loaded_chunks: Dictionary = {}  # Vector2i chunk coord -> StaticBody3D
var _pending_queue: Array[Vector2i] = []
var _player: Node3D = null
var _current_chunk_coord := Vector2i.ZERO


func set_player(player: Node3D) -> void:
	_player = player


func _ready() -> void:
	_build_square(Vector2i.ZERO, EAGER_RADIUS_CHUNKS)
	_refresh(Vector2i.ZERO)


func _process(_delta: float) -> void:
	if _player == null:
		return

	var coord := _chunk_coord_for(_player.global_position)
	if coord != _current_chunk_coord:
		_current_chunk_coord = coord
		_refresh(coord)

	for _i in range(CHUNKS_GENERATED_PER_FRAME):
		if _pending_queue.is_empty():
			break
		var next: Vector2i = _pending_queue.pop_front()
		if not _loaded_chunks.has(next):
			_spawn_chunk(next)


func _chunk_coord_for(world_position: Vector3) -> Vector2i:
	# floori(), not int() -- int() truncates toward zero, which would
	# double up or skip chunk coord -1 on the west/south side of the
	# origin instead of the intended floor-division behavior.
	return Vector2i(floori(world_position.x / TerrainChunk.CHUNK_SIZE), floori(world_position.z / TerrainChunk.CHUNK_SIZE))


func _build_square(center: Vector2i, radius: int) -> void:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var coord := Vector2i(center.x + dx, center.y + dz)
			if not _loaded_chunks.has(coord):
				_spawn_chunk(coord)


func _spawn_chunk(coord: Vector2i) -> void:
	var chunk := TerrainChunk.build(coord, _noise)
	add_child(chunk)
	_loaded_chunks[coord] = chunk


## Recomputes what should be loaded around `center`: frees chunks past the
## unload radius (with hysteresis margin so a player standing right at the
## view-distance boundary doesn't thrash load/unload every frame), then
## rebuilds the pending queue from scratch as "desired minus already
## loaded", nearest-first -- any previously queued coord that's no longer
## desired is naturally dropped since it just won't appear in `desired`.
func _refresh(center: Vector2i) -> void:
	var unload_radius := VIEW_DISTANCE_CHUNKS + UNLOAD_HYSTERESIS_CHUNKS
	for coord in _loaded_chunks.keys():
		var d: Vector2i = coord - center
		if maxi(absi(d.x), absi(d.y)) > unload_radius:
			_loaded_chunks[coord].queue_free()
			_loaded_chunks.erase(coord)

	var desired: Array[Vector2i] = []
	for dz in range(-VIEW_DISTANCE_CHUNKS, VIEW_DISTANCE_CHUNKS + 1):
		for dx in range(-VIEW_DISTANCE_CHUNKS, VIEW_DISTANCE_CHUNKS + 1):
			var coord := Vector2i(center.x + dx, center.y + dz)
			if not _loaded_chunks.has(coord):
				desired.append(coord)

	# Manual dx*dx+dz*dz rather than Vector2i's own length_squared() --
	# can't confirm that method's exact availability without a Godot
	# binary to check against, so this avoids leaning on it. Precomputed
	# into a dictionary rather than recomputed per comparison.
	var dist_sq: Dictionary = {}
	for coord in desired:
		var dx := coord.x - center.x
		var dz := coord.y - center.y
		dist_sq[coord] = dx * dx + dz * dz
	desired.sort_custom(func(a, b): return dist_sq[a] < dist_sq[b])
	_pending_queue = desired
