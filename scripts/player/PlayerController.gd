extends CharacterBody3D
class_name PlayerController
## Movement, gravity and collision only. Mouse look is deliberately handled
## by PlayerCamera.gd instead of here, so swapping in a different camera
## rig (e.g. a third-person orbit camera later) never touches movement
## code, and vice versa.

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 4.5
const ACCELERATION: float = 10.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

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

	move_and_slide()
