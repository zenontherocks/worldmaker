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

## "Ridged noise" river carving: a point's distance from a meandering
## centerline is approximated by abs(river noise) (zero exactly on the
## centerline, rising on both sides). RIVER_WIDTH_NOISE is a threshold on
## that noise MAGNITUDE, not actual world-space distance -- real river
## width will vary along its length depending on how steep the noise
## field's local gradient is there (narrower where steep, wider where
## shallow). This is a noise trick, not simulated hydrology.
##
## Tuned down from an earlier pass (frequency 0.008, width 0.04, depth
## 9.0) after user reports of falling into steep-walled pits and getting
## stuck -- a low frequency relative to HEIGHT_NOISE_FREQUENCY produces a
## whole crossing NETWORK of channels, not a few sparse rivers, and a
## narrow/deep combination makes each one a near-vertical trap a jump
## can't escape. Lower frequency means far fewer channels; a wider
## falloff spreads the same depth change over more world-space distance
## (gentler, walkable slopes instead of cliffs); a shallower depth means
## a stuck player can jump out directly. Also means carving is now
## usually shallow enough to sit above WATER_LEVEL except at genuinely
## low ground -- rivers show as blue water more consistently, less often
## as the "dry ravine crossing a hilltop" case described below.
const RIVER_NOISE_FREQUENCY := 0.003
const RIVER_WIDTH_NOISE := 0.09
const RIVER_DEPTH := 4.0

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
var _river_noise := FastNoiseLite.new()


func _init() -> void:
	_height_noise.seed = NOISE_SEED
	_height_noise.frequency = HEIGHT_NOISE_FREQUENCY
	_height_noise.fractal_octaves = HEIGHT_NOISE_OCTAVES

	# Different seed than the height field so biome regions don't just
	# trace the hills -- deserts and highlands should cut across slopes.
	_biome_noise.seed = NOISE_SEED + 1
	_biome_noise.frequency = BIOME_NOISE_FREQUENCY

	# Different seed again so river paths don't trace biome boundaries.
	_river_noise.seed = NOISE_SEED + 2
	_river_noise.frequency = RIVER_NOISE_FREQUENCY


func height_at(world_x: float, world_z: float) -> float:
	var raw := _height_noise.get_noise_2d(world_x, world_z) * HEIGHT_AMPLITUDE
	var carve := _river_carve_at(world_x, world_z)
	# Carve happens *inside* the flatten multiply, not after it -- that's
	# what keeps a river from cutting through the flat spawn/tan-house
	# zone even if its centerline would otherwise pass through the
	# origin. flatten_factor() is exactly 0 within FLATTEN_INNER_RADIUS,
	# so the same multiply that already zeroes hill noise there zeroes
	# the carve too. (raw * flatten_factor(...) - carve) would NOT have
	# this property.
	return (raw - carve) * flatten_factor(world_x, world_z)


## Depth to subtract from the raw height at this point for river carving.
## 0 far from a river centerline, rising smoothly to RIVER_DEPTH within
## RIVER_WIDTH_NOISE of it. A river crossing a hilltop can still carve
## deep enough to be a dry ravine rather than filled water (RIVER_DEPTH
## doesn't always reach down to WATER_LEVEL from a hill peak) -- only
## lower-elevation stretches of the same river actually show water via
## TerrainChunk's water mesh. Reads as "rivers pool in valleys," not as
## a bug, but means no continuous unbroken blue ribbon everywhere.
func _river_carve_at(world_x: float, world_z: float) -> float:
	var distance_from_centerline := absf(_river_noise.get_noise_2d(world_x, world_z))
	var carve_t := 1.0 - smoothstep(0.0, RIVER_WIDTH_NOISE, distance_from_centerline)
	return carve_t * RIVER_DEPTH


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
