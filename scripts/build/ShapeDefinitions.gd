extends RefCounted
class_name ShapeDefinitions
## Single source of truth for what primitive shapes exist and which
## dimensions each one exposes. ShapeFactory (mesh/collision generation),
## BuildModeController (cycling/adjusting) and the UI (labels, sliders) all
## read from this table instead of hard-coding per-shape logic, so adding a
## 6th primitive later only means adding one entry here plus one branch in
## ShapeFactory.

enum ShapeType { BOX, PLANE, CYLINDER, CONE, SPHERE }

## Display/cycle order.
const ORDER := [
	ShapeType.BOX,
	ShapeType.PLANE,
	ShapeType.CYLINDER,
	ShapeType.CONE,
	ShapeType.SPHERE,
]

const DEFS := {
	ShapeType.BOX: {
		"key": "box",
		"name": "Box",
		"dimensions": [
			{"key": "width", "label": "Width (X)", "default": 1.0, "min": 0.1, "max": 12.0, "step": 0.1},
			{"key": "height", "label": "Height (Y)", "default": 1.0, "min": 0.1, "max": 12.0, "step": 0.1},
			{"key": "depth", "label": "Depth (Z)", "default": 1.0, "min": 0.1, "max": 12.0, "step": 0.1},
		],
	},
	ShapeType.PLANE: {
		"key": "plane",
		"name": "Plane",
		"dimensions": [
			{"key": "width", "label": "Width (X)", "default": 2.0, "min": 0.1, "max": 24.0, "step": 0.1},
			{"key": "length", "label": "Length (Z)", "default": 2.0, "min": 0.1, "max": 24.0, "step": 0.1},
		],
	},
	ShapeType.CYLINDER: {
		"key": "cylinder",
		"name": "Cylinder",
		"dimensions": [
			{"key": "radius", "label": "Radius", "default": 0.5, "min": 0.1, "max": 6.0, "step": 0.05},
			{"key": "height", "label": "Height", "default": 1.0, "min": 0.1, "max": 12.0, "step": 0.1},
		],
	},
	ShapeType.CONE: {
		"key": "cone",
		"name": "Cone",
		"dimensions": [
			{"key": "radius", "label": "Radius", "default": 0.5, "min": 0.1, "max": 6.0, "step": 0.05},
			{"key": "height", "label": "Height", "default": 1.0, "min": 0.1, "max": 12.0, "step": 0.1},
		],
	},
	ShapeType.SPHERE: {
		"key": "sphere",
		"name": "Sphere",
		"dimensions": [
			{"key": "diameter", "label": "Diameter", "default": 1.0, "min": 0.1, "max": 12.0, "step": 0.05},
		],
	},
}


static func shape_name(shape_id: int) -> String:
	return DEFS[shape_id]["name"]


static func shape_key(shape_id: int) -> String:
	return DEFS[shape_id]["key"]


static func shape_id_from_key(key: String) -> int:
	for shape_id in DEFS.keys():
		if DEFS[shape_id]["key"] == key:
			return shape_id
	return ShapeType.BOX


static func dimension_fields(shape_id: int) -> Array:
	return DEFS[shape_id]["dimensions"]


static func default_dimensions(shape_id: int) -> Dictionary:
	var dims := {}
	for field in dimension_fields(shape_id):
		dims[field["key"]] = field["default"]
	return dims


static func clamp_dimension(shape_id: int, field_key: String, value: float) -> float:
	for field in dimension_fields(shape_id):
		if field["key"] == field_key:
			return clampf(value, field["min"], field["max"])
	return value
