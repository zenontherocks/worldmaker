extends RefCounted
class_name TerrainNoise
## The single source of truth for "what does the terrain look like at this
## world (x, z)". TerrainChunk reads height_at()/normal_at()/color_at() for
## both its visual mesh and its HeightMapShape3D collision -- neither can
## drift from the other since both go through the exact same functions,
## and every function here is a pure function of world coordinates (never
## chunk-local ones), so two chunks sharing an edge compute bit-identical
## values at that edge. That's what actually prevents seams/cracks between
## chunks, not just careful chunk placement.

const NOISE_SEED := 1337
const HEIGHT_NOISE_FREQUENCY := 0.015
const HEIGHT_NOISE_OCTAVES := 4
const HEIGHT_AMPLITUDE := 8.0
const BIOME_NOISE_FREQUENCY := 0.004

## Below this height, TerrainChunk renders a water surface (see its
## water-quad mesh) instead of leaving the carved-out terrain dry.
## VegetationFactory also reads this to keep trees/flowers out of lake
## and river beds.
const WATER_LEVEL := -2.0

## Player spawns at (0, 1, 0) (see Main.tscn's Player transform) and any
## hand-authored world JSON (e.g. a saved house build) assumes flat ground
## at y=0 near the origin -- so terrain is forced flat within this radius
## and blends smoothly into full noise-driven hills by the outer radius.
## The old Ground plane was 60x60 (+-30 half-extent); 55 keeps that whole
## footprint at or near flat with margin.
const FLATTEN_INNER_RADIUS := 25.0
const FLATTEN_OUTER_RADIUS := 55.0

## Sample offset (in world units) used for the central-difference normal
## calculation below -- half a mesh cell (CHUNK_SIZE / CHUNK_RESOLUTION
## in TerrainChunk is 2.0) keeps the gradient estimate local to roughly
## one triangle's scale.
const NORMAL_SAMPLE_EPSILON := 0.5

var _height_noise := FastNoiseLite.new()
var _biome_noise := FastNoiseLite.new()


func _init() -> void:
	_height_noise.seed = NOISE_SEED
	_height_noise.frequency = HEIGHT_NOISE_FREQUENCY
	_height_noise.fractal_octaves = HEIGHT_NOISE_OCTAVES

	# Different seed than the height field so biome regions don't just
	# trace the hills -- deserts and highlands should cut across slopes.
	_biome_noise.seed = NOISE_SEED + 1
	_biome_noise.frequency = BIOME_NOISE_FREQUENCY


func height_at(world_x: float, world_z: float) -> float:
	var raw := _height_noise.get_noise_2d(world_x, world_z) * HEIGHT_AMPLITUDE
	return raw * flatten_factor(world_x, world_z)


func normal_at(world_x: float, world_z: float) -> Vector3:
	var e := NORMAL_SAMPLE_EPSILON
	var h_left := height_at(world_x - e, world_z)
	var h_right := height_at(world_x + e, world_z)
	var h_down := height_at(world_x, world_z - e)
	var h_up := height_at(world_x, world_z + e)
	return Vector3(h_left - h_right, 2.0 * e, h_down - h_up).normalized()


func color_at(world_x: float, world_z: float, height: float) -> Color:
	var biome_color := BiomeDefinitions.color_for(biome_noise_at(world_x, world_z), height)
	var t := flatten_factor(world_x, world_z)
	return BiomeDefinitions.GRASSLAND_COLOR.lerp(biome_color, t)


func biome_noise_at(world_x: float, world_z: float) -> float:
	return _biome_noise.get_noise_2d(world_x, world_z)


## Public (no longer file-private) -- VegetationFactory also reads this
## to keep decorations out of the spawn/tan-house flatten zone.
func flatten_factor(world_x: float, world_z: float) -> float:
	var dist := Vector2(world_x, world_z).length()
	return smoothstep(FLATTEN_INNER_RADIUS, FLATTEN_OUTER_RADIUS, dist)
