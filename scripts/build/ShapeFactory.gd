extends RefCounted
class_name ShapeFactory
## Turns (shape_id, dimensions dict) pairs into actual Godot geometry. This
## is the only place that knows how ShapeDefinitions' abstract dimension
## keys map onto concrete Mesh/Shape3D resources -- BuildModeController,
## GhostPreview and SaveLoadManager all go through here instead of
## duplicating shape-construction logic.

const ShapeType = ShapeDefinitions.ShapeType


static func build_mesh(shape_id: int, dims: Dictionary) -> Mesh:
	match shape_id:
		ShapeType.BOX:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(
				dims.get("width", 1.0), dims.get("height", 1.0), dims.get("depth", 1.0)
			)
			return mesh
		ShapeType.PLANE:
			var mesh := PlaneMesh.new()
			mesh.size = Vector2(dims.get("width", 2.0), dims.get("length", 2.0))
			return mesh
		ShapeType.CYLINDER:
			var mesh := CylinderMesh.new()
			var radius: float = dims.get("radius", 0.5)
			mesh.top_radius = radius
			mesh.bottom_radius = radius
			mesh.height = dims.get("height", 1.0)
			return mesh
		ShapeType.CONE:
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.0
			mesh.bottom_radius = dims.get("radius", 0.5)
			mesh.height = dims.get("height", 1.0)
			return mesh
		ShapeType.SPHERE:
			var mesh := SphereMesh.new()
			var diameter: float = dims.get("diameter", 1.0)
			mesh.radius = diameter * 0.5
			mesh.height = diameter
			return mesh
	push_warning("ShapeFactory: unknown shape_id %s, defaulting to Box" % shape_id)
	return BoxMesh.new()


static func build_collision_shape(shape_id: int, dims: Dictionary, mesh: Mesh) -> Shape3D:
	match shape_id:
		ShapeType.BOX:
			var shape := BoxShape3D.new()
			shape.size = Vector3(
				dims.get("width", 1.0), dims.get("height", 1.0), dims.get("depth", 1.0)
			)
			return shape
		ShapeType.PLANE:
			# A thin box keeps a Plane walkable without needing an infinite
			# WorldBoundaryShape3D, which wouldn't respect width/length.
			var shape := BoxShape3D.new()
			shape.size = Vector3(dims.get("width", 2.0), 0.05, dims.get("length", 2.0))
			return shape
		ShapeType.CYLINDER:
			var shape := CylinderShape3D.new()
			shape.radius = dims.get("radius", 0.5)
			shape.height = dims.get("height", 1.0)
			return shape
		ShapeType.CONE:
			# Godot has no built-in cone collision primitive; derive a convex
			# hull from the mesh instead. Cones are rarely stacked precisely,
			# so the extra collision cost is acceptable.
			return mesh.create_convex_shape(true, false)
		ShapeType.SPHERE:
			var shape := SphereShape3D.new()
			shape.radius = dims.get("diameter", 1.0) * 0.5
			return shape
	return BoxShape3D.new()


## Distance from a hit surface point (along its normal) to where the
## shape's origin should sit so it rests flush against that surface instead
## of clipping into it or floating above it -- whichever world axis the
## normal is dominant in picks the shape's half-extent along that same
## axis, so this stays correct whether the hit face is a floor, a ceiling,
## or the side of another object (not just "up", despite the old name).
static func surface_offset(shape_id: int, dims: Dictionary, normal: Vector3) -> float:
	var abs_normal := normal.abs()
	match shape_id:
		ShapeType.BOX:
			if abs_normal.x >= abs_normal.y and abs_normal.x >= abs_normal.z:
				return dims.get("width", 1.0) * 0.5
			elif abs_normal.z >= abs_normal.y:
				return dims.get("depth", 1.0) * 0.5
			else:
				return dims.get("height", 1.0) * 0.5
		ShapeType.PLANE:
			return 0.01
		ShapeType.CYLINDER, ShapeType.CONE:
			if abs_normal.y >= abs_normal.x and abs_normal.y >= abs_normal.z:
				return dims.get("height", 1.0) * 0.5
			else:
				return dims.get("radius", 0.5)
		ShapeType.SPHERE:
			return dims.get("diameter", 1.0) * 0.5
	return 0.0


## Builds a fully wired StaticBody3D (mesh + collision + PlaceableObject
## script) ready to be added under GameManager.world_root.
static func create_instance(shape_id: int, dims: Dictionary, material: Material = null) -> PlaceableObject:
	var body := StaticBody3D.new()
	body.set_script(load("res://scripts/build/PlaceableObject.gd"))

	var mesh := build_mesh(shape_id, dims)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	if material:
		mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collider := CollisionShape3D.new()
	collider.name = "Collider"
	collider.shape = build_collision_shape(shape_id, dims, mesh)
	body.add_child(collider)

	var placeable := body as PlaceableObject
	placeable.shape_id = shape_id
	placeable.dimensions = dims.duplicate()
	placeable.mesh_instance = mesh_instance
	placeable.collider = collider
	return placeable
