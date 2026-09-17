extends RefCounted
class_name BiomeDefinitions
## Single source of truth for terrain biome colors, mirroring how
## ShapeDefinitions is the source of truth for placeable-shape dimensions.
## No texture assets exist in this project besides player-imported skins,
## so biomes are plain colors blended per-vertex rather than splatted
## textures -- TerrainChunk paints every terrain vertex with color_for().

## Suffixed _COLOR (not just DESERT etc.) because the Biome enum below
## needs those exact bare names for its own members -- a named GDScript
## enum's members are injected as class-level constants too, not just as
## Biome.DESERT, so unsuffixed names here would collide with it.
const DESERT_COLOR := Color(0.82, 0.7, 0.45)
const GRASSLAND_COLOR := Color(0.35, 0.55, 0.35)  # matches the old flat Ground's albedo
const HIGHLANDS_COLOR := Color(0.45, 0.42, 0.3)
const ROCK_COLOR := Color(0.5, 0.5, 0.5)

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

## Discrete counterpart to color_for()'s continuous blending, used by
## VegetationFactory to pick a single tree archetype for a given point
## rather than blend between several. ROCK_START_HEIGHT (not the later
## ROCK_FULL_HEIGHT) is the cutoff -- that's the first height any rock
## tint appears at all, so it's the conservative "no vegetation" line.
enum Biome { DESERT, GRASSLAND, HIGHLANDS, ROCK }


static func color_for(biome_noise: float, height: float) -> Color:
	var base := _base_biome_color(biome_noise)
	var rock_t := smoothstep(ROCK_START_HEIGHT, ROCK_FULL_HEIGHT, height)
	return base.lerp(ROCK_COLOR, rock_t)


static func dominant_biome(biome_noise: float, height: float) -> Biome:
	if height >= ROCK_START_HEIGHT:
		return Biome.ROCK
	if biome_noise < BIOME_THRESHOLD_LOW:
		return Biome.DESERT
	elif biome_noise > BIOME_THRESHOLD_HIGH:
		return Biome.HIGHLANDS
	return Biome.GRASSLAND


static func _base_biome_color(biome_noise: float) -> Color:
	var low_t := smoothstep(
		BIOME_THRESHOLD_LOW - BIOME_BLEND_WIDTH, BIOME_THRESHOLD_LOW + BIOME_BLEND_WIDTH, biome_noise
	)
	var high_t := smoothstep(
		BIOME_THRESHOLD_HIGH - BIOME_BLEND_WIDTH, BIOME_THRESHOLD_HIGH + BIOME_BLEND_WIDTH, biome_noise
	)
	return DESERT_COLOR.lerp(GRASSLAND_COLOR, low_t).lerp(HIGHLANDS_COLOR, high_t)
