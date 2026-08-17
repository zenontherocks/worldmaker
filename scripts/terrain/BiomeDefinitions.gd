extends RefCounted
class_name BiomeDefinitions
## Single source of truth for terrain biome colors, mirroring how
## ShapeDefinitions is the source of truth for placeable-shape dimensions.
## No texture assets exist in this project besides player-imported skins,
## so biomes are plain colors blended per-vertex rather than splatted
## textures -- TerrainChunk paints every terrain vertex with color_for().

const DESERT := Color(0.82, 0.7, 0.45)
const GRASSLAND := Color(0.35, 0.55, 0.35)  # matches the old flat Ground's albedo
const HIGHLANDS := Color(0.45, 0.42, 0.3)
const ROCK := Color(0.5, 0.5, 0.5)

## Biome noise sample is expected roughly in [-1, 1]. Blend width around
## each threshold keeps biome borders a smooth gradient instead of a hard
## edge -- there's no cheaper way to fake soft borders without a texture
## splat map, which this project deliberately has none of.
const BIOME_THRESHOLD_LOW := -0.15
const BIOME_THRESHOLD_HIGH := 0.15
const BIOME_BLEND_WIDTH := 0.1

## Elevation-driven overlay: any biome's peaks trend toward bare rock,
## independent of which biome they're in. Amplitude is 8.0 (see
## TerrainNoise.HEIGHT_AMPLITUDE), so most hilltops show at least a
## partial rock cap.
const ROCK_START_HEIGHT := 4.0
const ROCK_FULL_HEIGHT := 7.0


static func color_for(biome_noise: float, height: float) -> Color:
	var base := _base_biome_color(biome_noise)
	var rock_t := smoothstep(ROCK_START_HEIGHT, ROCK_FULL_HEIGHT, height)
	return base.lerp(ROCK, rock_t)


static func _base_biome_color(biome_noise: float) -> Color:
	var low_t := smoothstep(
		BIOME_THRESHOLD_LOW - BIOME_BLEND_WIDTH, BIOME_THRESHOLD_LOW + BIOME_BLEND_WIDTH, biome_noise
	)
	var high_t := smoothstep(
		BIOME_THRESHOLD_HIGH - BIOME_BLEND_WIDTH, BIOME_THRESHOLD_HIGH + BIOME_BLEND_WIDTH, biome_noise
	)
	return DESERT.lerp(GRASSLAND, low_t).lerp(HIGHLANDS, high_t)
