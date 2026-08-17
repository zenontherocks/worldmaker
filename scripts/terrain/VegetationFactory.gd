extends RefCounted
class_name VegetationFactory
## Scatters trees and flowers across one terrain chunk -- mirrors
## ShapeFactory.gd's "params in, wired scene subtree out" role. Called by
## TerrainChunk.build(), which adds every returned node as a child of the
## chunk body, so decorations are freed automatically whenever
## TerrainStreamer frees that chunk -- no separate lifecycle bookkeeping
## anywhere.
##
## Deliberately NOT PlaceableObject: that class exists to make an object
## delete/rotate/edit-able through BuildModeController and serializable
## through SaveLoadManager. Decorations regenerate from the noise seed on
## every chunk load, so making them PlaceableObject would let a player
## "delete" a tree that just comes back on the next reload -- confusing,
## not useful. Plain StaticBody3D/MeshInstance3D, built directly, mirrors
## how TerrainChunk itself (and the old Ground node) already work.

const TreeArchetype = VegetationDefinitions.TreeArchetype
const Biome = BiomeDefinitions.Biome

## Deliberately conservative -- no way to profile actual WASM/browser
## performance from here. If this needs tuning after real in-browser
## testing, lower these first (cheapest); TerrainStreamer.
## VIEW_DISTANCE_CHUNKS is the next lever but squares the effect, since
## it multiplies every chunk's decorations, not just its own count.
const TREE_ATTEMPTS_PER_CHUNK := 5
const FLOWER_ATTEMPTS_PER_CHUNK := 12

## Keeps decorations well clear of the spawn/tan-house build area --
## higher than a bare ">0" check so trees don't start appearing right at
## the nominal 55-unit flatten radius, only well past it.
const FLATTEN_SPAWN_THRESHOLD := 0.9

## One material per distinct Color, not a fresh one per instance --
## mirrors TerrainChunk._get_material()'s lazy-static caching pattern.
static var _material_cache: Dictionary = {}


static func scatter(chunk_coord: Vector2i, noise: TerrainNoise, chunk_size: float) -> Array[Node3D]:
	# Seeded purely from (chunk_coord, the terrain's own seed) -- same
	# reproducibility guarantee TerrainNoise already gives height/color,
	# so a chunk's scenery doesn't reshuffle when it unloads and reloads.
	# Decorations are never persisted (same as terrain itself), so this
	# only needs to be stable within a session, not across engine versions.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(chunk_coord.x, chunk_coord.y, TerrainNoise.NOISE_SEED))

	var nodes: Array[Node3D] = []
	for _i in range(TREE_ATTEMPTS_PER_CHUNK):
		var tree := _try_tree(chunk_coord, chunk_size, noise, rng)
		if tree:
			nodes.append(tree)
	for _i in range(FLOWER_ATTEMPTS_PER_CHUNK):
		var flower := _try_flower(chunk_coord, chunk_size, noise, rng)
		if flower:
			nodes.append(flower)
	return nodes


static func _try_tree(
	chunk_coord: Vector2i, chunk_size: float, noise: TerrainNoise, rng: RandomNumberGenerator
) -> Node3D:
	var candidate := _candidate_position(chunk_coord, chunk_size, noise, rng)
	if candidate.is_empty():
		return null
	var biome := BiomeDefinitions.dominant_biome(
		noise.biome_noise_at(candidate.world_x, candidate.world_z), candidate.height
	)
	var archetype := VegetationDefinitions.archetype_for_biome(biome)
	if archetype == -1:
		return null
	return _build_tree(archetype, candidate.local, rng)


static func _try_flower(
	chunk_coord: Vector2i, chunk_size: float, noise: TerrainNoise, rng: RandomNumberGenerator
) -> Node3D:
	var candidate := _candidate_position(chunk_coord, chunk_size, noise, rng)
	if candidate.is_empty():
		return null
	var biome := BiomeDefinitions.dominant_biome(
		noise.biome_noise_at(candidate.world_x, candidate.world_z), candidate.height
	)
	if biome != Biome.GRASSLAND:
		return null
	return _build_flower(candidate.local, rng)


## Empty Dictionary means "reject this attempt" -- keeps decorations out
## of the spawn/tan-house flatten zone and out of lake/river beds (once
## TerrainChunk's water mesh and TerrainNoise's river carving exist,
## this rejection already covers both automatically).
static func _candidate_position(
	chunk_coord: Vector2i, chunk_size: float, noise: TerrainNoise, rng: RandomNumberGenerator
) -> Dictionary:
	var local_x := rng.randf_range(0.0, chunk_size)
	var local_z := rng.randf_range(0.0, chunk_size)
	var world_x := chunk_coord.x * chunk_size + local_x
	var world_z := chunk_coord.y * chunk_size + local_z

	if noise.flatten_factor(world_x, world_z) < FLATTEN_SPAWN_THRESHOLD:
		return {}
	var height := noise.height_at(world_x, world_z)
	if height < TerrainNoise.WATER_LEVEL:
		return {}

	return {
		"local": Vector3(local_x, height, local_z),
		"world_x": world_x,
		"world_z": world_z,
		"height": height,
	}


static func _build_tree(archetype: int, local_pos: Vector3, rng: RandomNumberGenerator) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Tree"
	body.position = local_pos

	var trunk_radius: float
	var trunk_height: float
	match archetype:
		TreeArchetype.CACTUS:
			trunk_radius = rng.randf_range(VegetationDefinitions.CACTUS_TRUNK_RADIUS.x, VegetationDefinitions.CACTUS_TRUNK_RADIUS.y)
			trunk_height = rng.randf_range(VegetationDefinitions.CACTUS_TRUNK_HEIGHT.x, VegetationDefinitions.CACTUS_TRUNK_HEIGHT.y)
			_add_cylinder(body, "Trunk", trunk_radius, trunk_height, _pick_color(VegetationDefinitions.CACTUS_COLORS, rng), 0.0)
		TreeArchetype.ROUND:
			trunk_radius = rng.randf_range(VegetationDefinitions.ROUND_TRUNK_RADIUS.x, VegetationDefinitions.ROUND_TRUNK_RADIUS.y)
			trunk_height = rng.randf_range(VegetationDefinitions.ROUND_TRUNK_HEIGHT.x, VegetationDefinitions.ROUND_TRUNK_HEIGHT.y)
			_add_cylinder(body, "Trunk", trunk_radius, trunk_height, _pick_color(VegetationDefinitions.ROUND_TRUNK_COLORS, rng), 0.0)
			var canopy_diameter := rng.randf_range(VegetationDefinitions.ROUND_CANOPY_DIAMETER.x, VegetationDefinitions.ROUND_CANOPY_DIAMETER.y)
			# Slight overlap (0.3 instead of 0.5) so the canopy sphere's
			# bottom sinks a bit into the trunk top rather than leaving a
			# visible gap between them.
			_add_sphere(body, "Canopy", canopy_diameter, _pick_color(VegetationDefinitions.ROUND_CANOPY_COLORS, rng), trunk_height + canopy_diameter * 0.3)
		TreeArchetype.PINE:
			trunk_radius = rng.randf_range(VegetationDefinitions.PINE_TRUNK_RADIUS.x, VegetationDefinitions.PINE_TRUNK_RADIUS.y)
			trunk_height = rng.randf_range(VegetationDefinitions.PINE_TRUNK_HEIGHT.x, VegetationDefinitions.PINE_TRUNK_HEIGHT.y)
			_add_cylinder(body, "Trunk", trunk_radius, trunk_height, _pick_color(VegetationDefinitions.PINE_TRUNK_COLORS, rng), 0.0)
			var canopy_radius := rng.randf_range(VegetationDefinitions.PINE_CANOPY_RADIUS.x, VegetationDefinitions.PINE_CANOPY_RADIUS.y)
			var canopy_height := rng.randf_range(VegetationDefinitions.PINE_CANOPY_HEIGHT.x, VegetationDefinitions.PINE_CANOPY_HEIGHT.y)
			_add_cone(body, "Canopy", canopy_radius, canopy_height, _pick_color(VegetationDefinitions.PINE_CANOPY_COLORS, rng), trunk_height)

	# Collision covers the trunk only -- canopy overhang gets none, not
	# worth doubling collision shapes per tree for overhang the player
	# capsule rarely reaches.
	var shape := CylinderShape3D.new()
	shape.radius = trunk_radius
	shape.height = trunk_height
	var collider := CollisionShape3D.new()
	collider.name = "Collider"
	collider.shape = shape
	collider.position = Vector3(0, trunk_height * 0.5, 0)
	body.add_child(collider)

	return body


static func _build_flower(local_pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Flower"
	root.position = local_pos
	root.rotation.y = rng.randf_range(0.0, TAU)

	var stem_height := rng.randf_range(VegetationDefinitions.FLOWER_STEM_HEIGHT.x, VegetationDefinitions.FLOWER_STEM_HEIGHT.y)
	_add_cylinder(root, "Stem", VegetationDefinitions.FLOWER_STEM_RADIUS, stem_height, VegetationDefinitions.FLOWER_STEM_COLOR, 0.0)

	var bloom_diameter := rng.randf_range(VegetationDefinitions.FLOWER_BLOOM_DIAMETER.x, VegetationDefinitions.FLOWER_BLOOM_DIAMETER.y)
	var bloom_color := _pick_color(VegetationDefinitions.FLOWER_BLOOM_COLORS, rng)
	_add_sphere(root, "Bloom", bloom_diameter, bloom_color, stem_height + bloom_diameter * 0.3)

	return root


static func _add_cylinder(parent: Node3D, node_name: String, radius: float, height: float, color: Color, base_y: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	_add_mesh_instance(parent, node_name, mesh, color, base_y + height * 0.5)


static func _add_cone(parent: Node3D, node_name: String, base_radius: float, height: float, color: Color, base_y: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = base_radius
	mesh.height = height
	_add_mesh_instance(parent, node_name, mesh, color, base_y + height * 0.5)


static func _add_sphere(parent: Node3D, node_name: String, diameter: float, color: Color, center_y: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = diameter * 0.5
	mesh.height = diameter
	_add_mesh_instance(parent, node_name, mesh, color, center_y)


static func _add_mesh_instance(parent: Node3D, node_name: String, mesh: Mesh, color: Color, y: float) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = _material_for(color)
	instance.position = Vector3(0, y, 0)
	parent.add_child(instance)


static func _material_for(color: Color) -> StandardMaterial3D:
	if not _material_cache.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		_material_cache[color] = material
	return _material_cache[color]


static func _pick_color(colors: Array, rng: RandomNumberGenerator) -> Color:
	return colors[rng.randi_range(0, colors.size() - 1)]
