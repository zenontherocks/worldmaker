extends CharacterBody3D
class_name PlayerController
## Movement, gravity and collision only. Mouse look is deliberately handled
## by PlayerCamera.gd instead of here, so swapping in a different camera
## rig (e.g. a third-person orbit camera later) never touches movement
## code, and vice versa.

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 4.5
const ACCELERATION: float = 10.0

## Terrain streams in around the player rather than being one fixed
## always-present mesh (see TerrainStreamer), so unlike the old flat
## Ground plane this can't be tested locally end-to-end -- this is cheap
## insurance against any streaming edge case (a load-time race, a future
## bug in the chunk queue) dropping the player into empty space.
const FALL_RESET_Y: float = -50.0
const SPAWN_POSITION: Vector3 = Vector3(0, 1, 0)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _physics_process(delta: float) -> void:
	if global_position.y < FALL_RESET_Y:
		global_position = SPAWN_POSITION
		velocity = Vector3.ZERO

	if not is_on_floor():
		velocity.y -= _gravity * delta

	# jump/movement read raw Input state every frame rather than routed
	# events, so unlike _unhandled_input they're never blocked just because
	# a UI Control (e.g. a settings-panel button, the skin picker list) has
	# focus -- Space would both jump AND re-press a focused button
	# otherwise. Gate on mouse capture, the project's existing signal for
	# "player is actively playing" vs. "player is using a menu."
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		if direction != Vector3.ZERO:
			velocity.x = move_toward(velocity.x, direction.x * SPEED, ACCELERATION * delta * SPEED)
			velocity.z = move_toward(velocity.z, direction.z * SPEED, ACCELERATION * delta * SPEED)
		else:
			velocity.x = move_toward(velocity.x, 0.0, ACCELERATION * delta * SPEED)
			velocity.z = move_toward(velocity.z, 0.0, ACCELERATION * delta * SPEED)
	else:
		velocity.x = move_toward(velocity.x, 0.0, ACCELERATION * delta * SPEED)
		velocity.z = move_toward(velocity.z, 0.0, ACCELERATION * delta * SPEED)

	move_and_slide()
