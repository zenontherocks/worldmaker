extends Node3D
class_name BuildModeController
## Owns build state (active tool, live dimensions, rotation, active skin)
## and orchestrates raycasting + placement. The whole game is build mode --
## there's no separate "enter/exit" toggle -- so this is always running
## (modulo the pause menu, which stops it for free via SceneTree.paused
## like everything else with the default PROCESS_MODE_PAUSABLE). Lives
## under the player's Camera3D so its raycast always matches the look
## direction. Talks to the rest of the game only through signals and the
## ShapeFactory/GameManager/SkinManager services, plus a handful of public
## methods (select_slot/select_skin) the pause menu calls directly via the
## reference Main.gd hands it -- it never reaches into the UI itself.
##
## [E] cycles through eight tools: the five placeable shapes, then Delete,
## Rotate, and Edit. The pause menu's Tools row offers the same eight
## directly, via select_slot(). Delete, Rotate, and Edit all target
## whatever placed object the crosshair is over (found via the same
## raycast used for placement) and highlight it by temporarily swapping
## its mesh's material; Delete removes it on click, Rotate spins it in
## place with the same R/Shift+R (and T/Shift+T) keys that adjust a
## pending placement's rotation, and Edit locks onto it on click so
## Q/wheel can resize it live instead of adjusting a pending placement.

enum ToolMode { PLACE, DELETE, ROTATE, EDIT }

signal shape_changed(shape_id: int, dimensions: Dictionary)
signal dimensions_changed(dimensions: Dictionary)
signal active_field_changed(field_key: String)
signal tool_mode_changed(mode: int, slot_number: int, slot_count: int)
signal edit_target_changed(shape_id: int, dimensions: Dictionary)
signal edit_target_cleared
signal snap_toggled(enabled: bool)

@export var place_range: float = 8.0
@export var rotation_step_degrees: float = 15.0
## Placements snap their horizontal (X/Z) position to a world-space grid of
## this size, so shapes line up with each other -- vertical (Y) position is
## deliberately left alone, since it's already determined by whatever
## surface the raycast hit. Only applies to the plain default placement
## case; wall-mount and Plane-edge-tile snapping (see
## _process_place_target()) compute their own precise alignment instead.
## All three are gated together behind snap_enabled ([G] toggles it).
@export var grid_size: float = 1.0
## Placements also snap their yaw to the nearest multiple of this, so
## grid-snapped shapes actually face a consistent direction instead of
## whatever continuous angle the player happened to be looking from --
## grid-aligned position without grid-aligned rotation still left objects
## facing arbitrary, mismatched directions.
@export var rotation_snap_degrees: float = 90.0
## A pending Plane defaults to standing vertical when the player is looking
## within this many degrees of level (wall height), and lying flat when
## looking further up or down than that (floor/ceiling height) -- see
## _auto_plane_tilt(). R/Shift+R (_tilt_offset) still nudges further on
## top of whichever this picks.
@export var level_look_threshold_degrees: float = 45.0

## [G]. Gates grid-snap, wall-mount auto-orientation, and Plane-edge
## tiling together as one assist -- the underlying flush surface_offset()
## (no clipping/floating) always applies regardless, since that's a
## correctness fix rather than a snapping assist.
var snap_enabled: bool = true

@onready var ray_cast: RayCast3D = get_parent().get_node("RayCast3D")
@onready var ghost: GhostPreview = $GhostPreview

var tool_mode: int = ToolMode.PLACE
var current_shape_id: int = ShapeDefinitions.ShapeType.BOX
var current_dimensions: Dictionary = {}

## What new placements look like: "" for the default (unskinned) material,
## an imported texture's filename, or (per SkinManager.is_color_key()) a
## solid color's own "#rrggbb" hex string acting as its own key. Settable
## directly by the pause menu's Skins row via select_skin() or its Colors
## column via select_color(), not just by importing a new image.
var active_skin_key: String = ""

var _slots: Array = []
var _slot_index: int = 0
var _active_field_index: int = 0

## Offset applied on top of the player's current facing direction, so
## placements default to facing the same way the player is looking instead
## of a fixed world direction; R/Shift+R still let a placement be nudged
## further without physically turning to face it.
var _rotation_offset: float = 0.0

## Same idea, but around a horizontal axis instead -- only meaningful for
## Plane, whose default orientation lies flat. A Plane's facing is already
## effectively "set by moving around" (nothing about spinning a flat square
## around its own vertical axis looks any different), so for Plane
## specifically R/Shift+R tips it toward standing up vertical instead.
var _tilt_offset: float = 0.0

var _has_valid_target: bool = false
## Cached every physics frame by _process_place_target() (whichever of its
## three cases applied, with _rotation_offset/_tilt_offset already folded
## in), then just read back by _place_current() -- so the ghost and the
## final placement can never drift apart, no matter which case computed
## them.
var _target_position: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _target_tilt: float = 0.0

var _highlighted_object: PlaceableObject = null
var _highlighted_original_material: Material = null
var _delete_highlight_material: StandardMaterial3D
var _rotate_highlight_material: StandardMaterial3D
var _edit_highlight_material: StandardMaterial3D

## True once Edit has locked onto _highlighted_object (a click while
## browsing); while true, raycasting/re-highlighting stops so the edit
## target stays fixed regardless of where the crosshair wanders.
var _edit_locked: bool = false


func _ready() -> void:
	ray_cast.enabled = true
	ray_cast.target_position = Vector3(0, 0, -place_range)
	SkinManager.skin_loaded.connect(_on_skin_loaded)

	for shape_id in ShapeDefinitions.ORDER:
		_slots.append({"mode": ToolMode.PLACE, "shape_id": shape_id})
	_slots.append({"mode": ToolMode.DELETE})
	_slots.append({"mode": ToolMode.ROTATE})
	_slots.append({"mode": ToolMode.EDIT})

	_delete_highlight_material = _make_highlight_material(Color(1.0, 0.25, 0.2, 0.6))
	_rotate_highlight_material = _make_highlight_material(Color(0.25, 0.7, 1.0, 0.6))
	_edit_highlight_material = _make_highlight_material(Color(1.0, 0.85, 0.2, 0.6))

	# Deferred so its signal emissions land after Main.gd's _ready() (which
	# runs after all its children's, including this one) has actually
	# connected them to BuildHUD -- otherwise this initial state emits into
	# a HUD that isn't listening yet and shows blank until the player's
	# first interaction.
	call_deferred("select_slot", 0)
	call_deferred("emit_signal", "snap_toggled", snap_enabled)


func _make_highlight_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func _physics_process(_delta: float) -> void:
	ray_cast.force_raycast_update()

	if tool_mode == ToolMode.PLACE:
		_process_place_target()
	elif tool_mode != ToolMode.EDIT or not _edit_locked:
		_process_targeted_object()


## Three cases, checked in priority order, each caching _target_position/
## _target_yaw/_target_tilt for _place_current() to read back verbatim:
## 1. Snap enabled, placing a Plane, aiming at an already-placed Plane ->
##    edge-tile flush and coplanar against it (for flooring/walls).
## 2. Snap enabled, placing a Plane, aiming at a wall-like surface ->
##    auto-stand it up flush against that wall, facing outward.
## 3. Otherwise -> the plain default: flush surface_offset() along
##    whichever face was hit, grid-snapped (X/Z) facing-based placement.
func _process_place_target() -> void:
	_has_valid_target = ray_cast.is_colliding()
	if not _has_valid_target:
		ghost.set_valid(false)
		return

	var point: Vector3 = ray_cast.get_collision_point()
	var normal: Vector3 = ray_cast.get_collision_normal()
	var collider := ray_cast.get_collider()
	var is_plane := current_shape_id == ShapeDefinitions.ShapeType.PLANE

	if snap_enabled and is_plane and collider is PlaceableObject and collider.shape_id == ShapeDefinitions.ShapeType.PLANE:
		_compute_plane_edge_snap(collider, point)
	elif snap_enabled and is_plane and absf(normal.y) < 0.5:
		_compute_wall_mount(point, normal)
	else:
		_compute_default_placement(point, normal)

	ghost.set_transform_data(_target_position, _target_yaw, _target_tilt)
	ghost.set_valid(true)


func _compute_default_placement(point: Vector3, normal: Vector3) -> void:
	var offset := ShapeFactory.surface_offset(current_shape_id, current_dimensions, normal)
	_target_position = point + normal * offset
	_target_yaw = _current_facing_y() + _rotation_offset
	if snap_enabled:
		_target_position.x = snappedf(_target_position.x, grid_size)
		_target_position.z = snappedf(_target_position.z, grid_size)
		_target_yaw = snappedf(_target_yaw, deg_to_rad(rotation_snap_degrees))
	_target_tilt = _current_tilt()


## Auto-orients a pending Plane flush against a wall-like surface (hit
## normal more horizontal than vertical) instead of defaulting to lying
## flat -- R/Shift+R and T/Shift+T still nudge further on top of this.
## Only ever reached when snap_enabled is already true, so the yaw is
## always rounded here, same as the default case above.
func _compute_wall_mount(point: Vector3, normal: Vector3) -> void:
	var offset := ShapeFactory.surface_offset(current_shape_id, current_dimensions, normal)
	_target_position = point + normal * offset
	_target_yaw = snappedf(atan2(normal.x, normal.z) + _rotation_offset, deg_to_rad(rotation_snap_degrees))
	_target_tilt = PI * 0.5 + _tilt_offset


## Snaps a pending Plane against whichever edge of an already-placed target
## Plane the raycast landed nearest, so Planes can either tile edge-to-edge
## (flush and coplanar with the target) or stand up as a hinge rising from
## that edge -- e.g. a wall rising from the edge of a floor tile. Which of
## the two happens defaults to the same look-direction auto-detection as a
## targetless placement (_auto_plane_tilt()): aiming roughly level picks
## standing, aiming down/up picks coplanar, matching the target's own
## orientation -- R/Shift+R still nudges the choice either way on top of
## that. Works entirely in the target's own local frame, so it honors
## however that target is currently oriented (flat, wall-mounted, anything
## the Rotate tool left it at) without needing to special-case any of that.
func _compute_plane_edge_snap(target: PlaceableObject, hit_point: Vector3) -> void:
	var half_width: float = current_dimensions.get("width", 2.0) * 0.5
	var half_length: float = current_dimensions.get("length", 2.0) * 0.5
	var target_half_width: float = target.dimensions.get("width", 2.0) * 0.5
	var target_half_length: float = target.dimensions.get("length", 2.0) * 0.5

	# "Standing" is evaluated relative to the target, not in absolute world
	# terms -- comparing the desired tilt against the target's own rotation
	# (not just against a fixed 0) is what makes this work correctly
	# whether the target itself is a flat floor tile or an already-vertical
	# wall panel. Coplanar (desired tilt matches the target's) always means
	# "same orientation as the target": for a floor target that's flat
	# tiling; for a wall target that's tiling more wall panels sideways to
	# build a longer wall, which needs to keep working for actual buildings
	# to be buildable. Snapping the result to exactly coplanar or exactly a
	# right angle (rather than using the desired tilt's precise value)
	# keeps every tiled edge genuinely flush, not just close.
	var desired_tilt := _auto_plane_tilt() + _tilt_offset
	var relative_tilt := wrapf(desired_tilt - target.rotation.x, -PI, PI)
	var standing := absf(relative_tilt) > PI * 0.25
	var hinge_sign := -1.0 if relative_tilt < 0.0 else 1.0

	var local_hit: Vector3 = target.to_local(hit_point)
	var x_ratio := absf(local_hit.x) / target_half_width if target_half_width > 0.0 else 0.0
	var z_ratio := absf(local_hit.z) / target_half_length if target_half_length > 0.0 else 0.0

	var local_offset := Vector3.ZERO
	if x_ratio >= z_ratio:
		local_offset.x = signf(local_hit.x) * (target_half_width + (0.0 if standing else half_width))
	else:
		local_offset.z = signf(local_hit.z) * (target_half_length + (0.0 if standing else half_length))
	if standing:
		# Tilting ~90 degrees around local X turns the new Plane's own
		# "length" dimension into its vertical extent (same fact the
		# wall-mount case relies on) -- lifting the center by half of
		# that sits its bottom edge exactly on the target's surface at
		# the hinge line, instead of floating above or clipping into it.
		local_offset.y = half_length

	_target_position = target.to_global(local_offset)
	# A plane's local width axis, after any yaw+tilt, always ends up at
	# exactly (cos(yaw), 0, -sin(yaw)) in world space -- tilt never moves it,
	# only yaw does. So a hinge standing up from the target's X-edge needs
	# its width axis rotated 90 degrees relative to the target's yaw to run
	# along that edge instead of pointing straight across it; the Z-edge
	# case is already aligned and needs no correction. Skipped when coplanar
	# since a flat tile's own X vs Z edge doesn't change which way it faces.
	var yaw_correction := (PI * 0.5) if (standing and x_ratio >= z_ratio) else 0.0
	_target_yaw = target.rotation.y + yaw_correction + _rotation_offset
	_target_tilt = target.rotation.x + (hinge_sign * PI * 0.5 if standing else 0.0)


func _process_targeted_object() -> void:
	var candidate: PlaceableObject = null
	if ray_cast.is_colliding():
		var collider := ray_cast.get_collider()
		if collider is PlaceableObject:
			candidate = collider
	_set_highlighted(candidate)


func _set_highlighted(candidate: PlaceableObject) -> void:
	if candidate == _highlighted_object:
		return
	_clear_highlight()
	if candidate != null and candidate.mesh_instance != null:
		_highlighted_object = candidate
		_highlighted_original_material = candidate.mesh_instance.material_override
		candidate.mesh_instance.material_override = _highlight_material_for(tool_mode)


func _highlight_material_for(mode: int) -> StandardMaterial3D:
	match mode:
		ToolMode.DELETE:
			return _delete_highlight_material
		ToolMode.ROTATE:
			return _rotate_highlight_material
		_:
			return _edit_highlight_material


func _clear_highlight() -> void:
	if _highlighted_object != null and is_instance_valid(_highlighted_object) and _highlighted_object.mesh_instance != null:
		_highlighted_object.mesh_instance.material_override = _highlighted_original_material
	_highlighted_object = null
	_highlighted_original_material = null


func _current_facing_y() -> float:
	# BuildModeController lives under the Camera3D, which only ever pitches
	# (yaw is applied to the player body instead -- see PlayerCamera.gd), so
	# the camera's own global Y rotation already equals the body's facing.
	return get_parent().global_rotation.y


func _current_tilt() -> float:
	if current_shape_id != ShapeDefinitions.ShapeType.PLANE:
		return 0.0
	return _auto_plane_tilt() + _tilt_offset


## Standing (PI/2) when the player is looking roughly level -- at "wall
## height", where a vertical Plane is almost always what's wanted -- and
## flat (0) when looking distinctly up or down instead, at floor/ceiling
## height. Camera3D only ever pitches (yaw is on the player body -- see
## PlayerCamera.gd), so its own local rotation.x is the pitch directly.
func _auto_plane_tilt() -> float:
	var pitch: float = get_parent().rotation.x
	var looking_level := absf(pitch) < deg_to_rad(level_look_threshold_degrees)
	return PI * 0.5 if looking_level else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_cycle_shape"):
		select_slot((_slot_index + 1) % _slots.size())
	elif event.is_action_pressed("build_cycle_dimension"):
		if _can_edit_dimensions():
			_cycle_active_field()
	elif event.is_action_pressed("build_dimension_increase"):
		if _can_edit_dimensions():
			_adjust_active_field(1.0)
	elif event.is_action_pressed("build_dimension_decrease"):
		if _can_edit_dimensions():
			_adjust_active_field(-1.0)
	elif event.is_action_pressed("build_rotate_cw"):
		_rotate(rotation_step_degrees)
	elif event.is_action_pressed("build_rotate_ccw"):
		_rotate(-rotation_step_degrees)
	elif event.is_action_pressed("build_tilt_cw"):
		_tilt(rotation_step_degrees)
	elif event.is_action_pressed("build_tilt_ccw"):
		_tilt(-rotation_step_degrees)
	elif event.is_action_pressed("build_place"):
		_confirm()
	elif event.is_action_pressed("build_toggle_snap"):
		snap_enabled = not snap_enabled
		snap_toggled.emit(snap_enabled)


func _can_edit_dimensions() -> bool:
	return tool_mode == ToolMode.PLACE or (tool_mode == ToolMode.EDIT and _edit_locked)


func _update_ghost_visibility() -> void:
	if tool_mode == ToolMode.PLACE:
		ghost.show_ghost()
	else:
		ghost.hide_ghost()


## Public: called both by [E] cycling above and directly by the pause
## menu's Tools row buttons (via the reference Main.gd hands it).
func select_slot(index: int) -> void:
	if _edit_locked:
		_edit_locked = false
		edit_target_cleared.emit()
	_clear_highlight()
	_slot_index = index
	var slot: Dictionary = _slots[_slot_index]
	tool_mode = slot["mode"]

	if tool_mode == ToolMode.PLACE:
		current_shape_id = slot["shape_id"]
		current_dimensions = ShapeDefinitions.default_dimensions(current_shape_id)
		_active_field_index = 0
		ghost.update_shape(current_shape_id, current_dimensions)
		shape_changed.emit(current_shape_id, current_dimensions)
		active_field_changed.emit(_active_dimension_key())

	_update_ghost_visibility()
	tool_mode_changed.emit(tool_mode, _slot_index + 1, _slots.size())


## Public: called by the pause menu's Skins row. "" selects the default
## (unskinned) material.
func select_skin(skin_key: String) -> void:
	active_skin_key = skin_key
	ghost.set_skin(SkinManager.get_cached(skin_key) if skin_key != "" else null)


## Public: called by the pause menu's Colors column, mirroring select_skin()
## above -- a solid color fills the exact same slot a texture skin does
## (SkinManager.build_material() resolves either kind from the same
## active_skin_key), so this just clears any texture preview on the ghost.
## It doesn't try to preview the exact chosen color there too: the ghost's
## albedo_color is already owned by set_valid()'s green/red translucent
## tint, and it doesn't render an untinted preview of a texture skin
## either, so leaving that tint as the only ghost feedback stays
## consistent instead of fighting over the same material property.
func select_color(hex: String) -> void:
	active_skin_key = hex
	ghost.set_skin(null)


func _dimension_fields_in_context() -> Array:
	if tool_mode == ToolMode.EDIT and _edit_locked and _highlighted_object != null:
		return ShapeDefinitions.dimension_fields(_highlighted_object.shape_id)
	return ShapeDefinitions.dimension_fields(current_shape_id)


func _cycle_active_field() -> void:
	var fields := _dimension_fields_in_context()
	_active_field_index = (_active_field_index + 1) % fields.size()
	active_field_changed.emit(_active_dimension_key())


func _adjust_active_field(direction: float) -> void:
	var fields := _dimension_fields_in_context()
	var field: Dictionary = fields[_active_field_index]

	if tool_mode == ToolMode.EDIT and _edit_locked and _highlighted_object != null:
		var target := _highlighted_object
		var new_dims: Dictionary = target.dimensions.duplicate()
		var new_value: float = new_dims[field["key"]] + field["step"] * direction
		new_dims[field["key"]] = ShapeDefinitions.clamp_dimension(target.shape_id, field["key"], new_value)
		target.rebuild_geometry(new_dims)
		dimensions_changed.emit(target.dimensions)
		return

	var new_value: float = current_dimensions[field["key"]] + field["step"] * direction
	current_dimensions[field["key"]] = ShapeDefinitions.clamp_dimension(
		current_shape_id, field["key"], new_value
	)
	ghost.update_shape(current_shape_id, current_dimensions)
	dimensions_changed.emit(current_dimensions)


## R/Shift+R: for a pending placement this spins its horizontal facing --
## except for Plane, whose facing already tracks the player (see
## _tilt_offset above), so it tips vertical instead. In Rotate mode it
## spins the targeted object's own Y rotation directly.
func _rotate(delta_degrees: float) -> void:
	match tool_mode:
		ToolMode.PLACE:
			if current_shape_id == ShapeDefinitions.ShapeType.PLANE:
				_tilt_offset = wrapf(_tilt_offset + deg_to_rad(delta_degrees), 0.0, TAU)
			else:
				_rotation_offset = wrapf(_rotation_offset + deg_to_rad(delta_degrees), 0.0, TAU)
		ToolMode.ROTATE:
			if _highlighted_object != null and is_instance_valid(_highlighted_object):
				_highlighted_object.rotation.y = wrapf(
					_highlighted_object.rotation.y + deg_to_rad(delta_degrees), 0.0, TAU
				)


## T/Shift+T: tips the targeted object around a horizontal axis instead
## (e.g. standing a cylinder up vs. laying it on its side). Rotate-tool
## only -- there's no equivalent for a pending placement.
func _tilt(delta_degrees: float) -> void:
	if tool_mode == ToolMode.ROTATE and _highlighted_object != null and is_instance_valid(_highlighted_object):
		_highlighted_object.rotation.x = wrapf(
			_highlighted_object.rotation.x + deg_to_rad(delta_degrees), 0.0, TAU
		)


func _active_dimension_key() -> String:
	var fields := _dimension_fields_in_context()
	return fields[_active_field_index]["key"]


func _confirm() -> void:
	match tool_mode:
		ToolMode.PLACE:
			_place_current()
		ToolMode.DELETE:
			_delete_targeted()
		ToolMode.EDIT:
			_toggle_edit_lock()


func _place_current() -> void:
	if not _has_valid_target:
		return

	var material := SkinManager.build_material(active_skin_key)
	var instance := ShapeFactory.create_instance(current_shape_id, current_dimensions, material)
	instance.position = _target_position
	instance.rotation.y = _target_yaw
	instance.rotation.x = _target_tilt
	instance.skin_key = active_skin_key
	instance.object_id = GameManager.get_next_id()

	if GameManager.world_root:
		GameManager.world_root.add_child(instance)


func _delete_targeted() -> void:
	if _highlighted_object == null or not is_instance_valid(_highlighted_object):
		return
	var target := _highlighted_object
	_highlighted_object = null
	_highlighted_original_material = null
	target.queue_free()


## First click while browsing (Edit selected, nothing locked yet) locks
## onto whatever's currently highlighted; a second click anywhere unlocks
## again, restoring its original material via _clear_highlight().
func _toggle_edit_lock() -> void:
	if _edit_locked:
		_edit_locked = false
		_clear_highlight()
		edit_target_cleared.emit()
		return

	if _highlighted_object != null and is_instance_valid(_highlighted_object):
		_edit_locked = true
		_active_field_index = 0
		edit_target_changed.emit(_highlighted_object.shape_id, _highlighted_object.dimensions)
		active_field_changed.emit(_active_dimension_key())


func _on_skin_loaded(texture: Texture2D, skin_key: String) -> void:
	ghost.set_skin(texture)
	active_skin_key = skin_key
