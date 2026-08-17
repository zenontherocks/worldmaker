extends RefCounted
class_name VegetationDefinitions
## Data table for the trees and flowers VegetationFactory scatters --
## mirrors ShapeDefinitions.gd's role for placeable shapes. Kept separate
## from BiomeDefinitions.gd (ground color/threshold data) the same way
## ShapeDefinitions and ShapeFactory stay separate concerns: one holds
## data, the other turns it into nodes.

enum TreeArchetype { CACTUS, ROUND, PINE }

## Every dimension below is a Vector2(min, max) sampled per-instance by
## VegetationFactory, so size varies per tree, not just per biome. Each
## archetype's color lists are small and fixed (not per-instance jitter)
## so VegetationFactory can cache one material per distinct Color instead
## of allocating a fresh one per tree.

const CACTUS_TRUNK_RADIUS := Vector2(0.15, 0.3)
const CACTUS_TRUNK_HEIGHT := Vector2(1.8, 3.4)
const CACTUS_COLORS := [Color(0.35, 0.5, 0.3), Color(0.3, 0.45, 0.28), Color(0.4, 0.55, 0.35)]

const ROUND_TRUNK_RADIUS := Vector2(0.2, 0.32)
const ROUND_TRUNK_HEIGHT := Vector2(1.4, 2.2)
const ROUND_TRUNK_COLORS := [Color(0.4, 0.26, 0.14), Color(0.35, 0.22, 0.12), Color(0.45, 0.3, 0.16)]
const ROUND_CANOPY_DIAMETER := Vector2(1.8, 3.2)
const ROUND_CANOPY_COLORS := [Color(0.3, 0.55, 0.25), Color(0.35, 0.6, 0.3), Color(0.25, 0.5, 0.22)]

const PINE_TRUNK_RADIUS := Vector2(0.18, 0.28)
const PINE_TRUNK_HEIGHT := Vector2(2.0, 3.2)
const PINE_TRUNK_COLORS := [Color(0.32, 0.2, 0.12), Color(0.28, 0.18, 0.1), Color(0.36, 0.24, 0.14)]
const PINE_CANOPY_RADIUS := Vector2(1.0, 1.8)
const PINE_CANOPY_HEIGHT := Vector2(2.4, 4.4)
const PINE_CANOPY_COLORS := [Color(0.15, 0.35, 0.18), Color(0.12, 0.3, 0.15), Color(0.18, 0.4, 0.2)]

const FLOWER_STEM_RADIUS := 0.03
const FLOWER_STEM_HEIGHT := Vector2(0.22, 0.4)
const FLOWER_STEM_COLOR := Color(0.25, 0.55, 0.2)
const FLOWER_BLOOM_DIAMETER := Vector2(0.12, 0.22)
const FLOWER_BLOOM_COLORS := [
	Color(0.85, 0.15, 0.15),
	Color(0.95, 0.8, 0.1),
	Color(0.9, 0.5, 0.1),
	Color(0.85, 0.2, 0.55),
	Color(0.55, 0.25, 0.85),
]


## -1 means no archetype for that biome -- VegetationFactory skips the
## candidate outright (bare rock gets no vegetation at all).
static func archetype_for_biome(biome: BiomeDefinitions.Biome) -> int:
	match biome:
		BiomeDefinitions.Biome.DESERT:
			return TreeArchetype.CACTUS
		BiomeDefinitions.Biome.GRASSLAND:
			return TreeArchetype.ROUND
		BiomeDefinitions.Biome.HIGHLANDS:
			return TreeArchetype.PINE
	return -1
