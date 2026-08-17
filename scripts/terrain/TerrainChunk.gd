extends RefCounted
class_name TerrainChunk
## Turns (chunk_coord, TerrainNoise) into a wired StaticBody3D -- mirrors
## ShapeFactory.create_instance()'s "params in, scene subtree out" idiom.
## TerrainStreamer is the only caller; it owns chunk lifecycle, this only
## knows how to build one.

const CHUNK_SIZE := 32.0
const CHUNK_RESOLUTION := 16  # quads per side -- 17x17 vertices
const CELL_SIZE := CHUNK_SIZE / CHUNK_RESOLUTION
const VERTS_PER_SIDE := CHUNK_RESOLUTION + 1

## Shared across every chunk (built once, lazily) -- terrain is colored
## entirely via per-vertex color, so one material instance is all any
## chunk ever needs.
static var _material: StandardMaterial3D = null

## Same lazy-static caching as _material above.
static var _water_material: StandardMaterial3D = null


static func build(chunk_coord: Vector2i, noise: TerrainNoise) -> StaticBody3D:
	var origin_x := chunk_coord.x * CHUNK_SIZE
	var origin_z := chunk_coord.y * CHUNK_SIZE

	# Collision heights are filled from the exact same values handed to
	# the mesh below (not recomputed from a second call to height_at())
	# so the visual surface and the walkable surface cannot diverge.
	var heights := PackedFloat32Array()
	heights.resize(VERTS_PER_SIDE * VERTS_PER_SIDE)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# A separate unindexed mesh for water, built alongside the terrain
	# indices below rather than as one flat full-chunk quad -- a single
	# quad per "wet" chunk would render as a hard-edged square regardless
	# of the lake/river's actual shape. Reusing the same heights[] this
	# loop already fills means every water quad's corners match the
	# terrain's carved contour exactly, at no extra noise-sampling cost.
	var water_st := SurfaceTool.new()
	water_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_water := false

	for j in range(VERTS_PER_SIDE):
		for i in range(VERTS_PER_SIDE):
			var local_x := i * CELL_SIZE
			var local_z := j * CELL_SIZE
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			var h := noise.height_at(world_x, world_z)
			heights[j * VERTS_PER_SIDE + i] = h
			st.set_normal(noise.normal_at(world_x, world_z))
			st.set_color(noise.color_at(world_x, world_z, h))
			st.add_vertex(Vector3(local_x, h, local_z))

	for j in range(CHUNK_RESOLUTION):
		for i in range(CHUNK_RESOLUTION):
			var top_left := j * VERTS_PER_SIDE + i
			var top_right := top_left + 1
			var bottom_left := (j + 1) * VERTS_PER_SIDE + i
			var bottom_right := bottom_left + 1
			st.add_index(top_left)
			st.add_index(bottom_left)
			st.add_index(top_right)
			st.add_index(top_right)
			st.add_index(bottom_left)
			st.add_index(bottom_right)

			# All four corners submerged, not just one -- ridged-noise river
			# carving (see TerrainNoise._river_carve_at()) can flatten out
			# near-zero over a patch rather than crossing cleanly, so an
			# "any corner" threshold could include far more quads per
			# chunk than intended in those spots. Requiring all four costs
			# a slightly less generous shoreline (a strip of shallow-but-
			# technically-dry ground at the water's edge) in exchange for
			# a hard cap on worst-case water-mesh size per chunk.
			if (
				heights[top_left] < TerrainNoise.WATER_LEVEL
				and heights[top_right] < TerrainNoise.WATER_LEVEL
				and heights[bottom_left] < TerrainNoise.WATER_LEVEL
				and heights[bottom_right] < TerrainNoise.WATER_LEVEL
			):
				has_water = true
				var wx0 := i * CELL_SIZE
				var wx1 := (i + 1) * CELL_SIZE
				var wz0 := j * CELL_SIZE
				var wz1 := (j + 1) * CELL_SIZE
				water_st.set_normal(Vector3.UP)
				water_st.add_vertex(Vector3(wx0, TerrainNoise.WATER_LEVEL, wz0))
				water_st.add_vertex(Vector3(wx0, TerrainNoise.WATER_LEVEL, wz1))
				water_st.add_vertex(Vector3(wx1, TerrainNoise.WATER_LEVEL, wz0))
				water_st.add_vertex(Vector3(wx1, TerrainNoise.WATER_LEVEL, wz0))
				water_st.add_vertex(Vector3(wx0, TerrainNoise.WATER_LEVEL, wz1))
				water_st.add_vertex(Vector3(wx1, TerrainNoise.WATER_LEVEL, wz1))

	var mesh := st.commit()

	var body := StaticBody3D.new()
	body.position = Vector3(origin_x, 0.0, origin_z)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _get_material()
	# Mirrors ShapeFactory.gd's Plane handling: whichever way this mesh's
	# triangle winding actually ends up (verified by hand, but there's no
	# Godot binary here to confirm against), a single-layer heightfield
	# should never have an invisible top or a visible underside either
	# way. Shadow casting has its own independent culling pass, so it
	# needs the same double-sided treatment separately from cull_mode.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	body.add_child(mesh_instance)

	var shape := HeightMapShape3D.new()
	shape.map_width = VERTS_PER_SIDE
	shape.map_depth = VERTS_PER_SIDE
	shape.map_data = heights

	var collider := CollisionShape3D.new()
	collider.name = "Collider"
	collider.shape = shape
	# HeightMapShape3D's grid is 1 local unit apart, centered on its own
	# origin -- scale to CELL_SIZE to match the mesh's vertex spacing,
	# and re-center so the shape covers local [0, CHUNK_SIZE] like the
	# mesh does, instead of being centered on the body's origin.
	collider.transform = Transform3D(
		Basis().scaled(Vector3(CELL_SIZE, 1.0, CELL_SIZE)), Vector3(CHUNK_SIZE / 2.0, 0.0, CHUNK_SIZE / 2.0)
	)
	body.add_child(collider)

	if has_water:
		var water_instance := MeshInstance3D.new()
		water_instance.name = "Water"
		water_instance.mesh = water_st.commit()
		water_instance.material_override = _get_water_material()
		# A flat translucent plane casting a shadow onto itself/nearby
		# terrain looks wrong and isn't worth the extra pass -- unlike
		# the terrain mesh above, water isn't meant to cast one at all.
		water_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(water_instance)

	for veg in VegetationFactory.scatter(chunk_coord, noise, CHUNK_SIZE):
		body.add_child(veg)

	return body


static func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 1.0
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material


static func _get_water_material() -> StandardMaterial3D:
	if _water_material == null:
		_water_material = StandardMaterial3D.new()
		_water_material.albedo_color = Color(0.15, 0.35, 0.55, 0.55)
		_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Needed, not optional: with no swim mechanic, the player can walk
		# into water and the camera ends up under the plane -- without
		# this, the exact backface-culling bug just fixed for terrain
		# would reappear here, on a flat plane instead of a heightfield.
		_water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _water_material
