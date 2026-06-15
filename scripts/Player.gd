extends CharacterBody3D
## The operative. Camera-relative isometric movement, three stances
## (crouch / walk / run) that trade speed for noise & exposure, and a
## light-driven visibility value the guards read to decide if they can see you.

var world                          # set by World before add_child

const SPEED_WALK := 3.6
const SPEED_RUN := 6.2
const SPEED_CROUCH := 2.0
const ACCEL := 14.0
const TURN_SPEED := 12.0

var visibility := 0.0              # 0 = pitch dark, 1 = fully lit
var crouching := false
var running := false
var moving := false

var _face_angle := 0.0


func _physics_process(delta: float) -> void:
	if world == null:
		return

	if not world.active or world.ui_open:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# --- gather input -----------------------------------------------------
	var ix := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var iz := Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	var raw := Vector2(ix, iz)
	if raw.length() > 1.0:
		raw = raw.normalized()

	crouching = Input.is_action_pressed("crouch")
	running = Input.is_action_pressed("run") and not crouching

	# --- camera-relative direction (matches the isometric view) -----------
	var cam_basis: Basis = world.cam_pivot.global_transform.basis
	var fwd := -cam_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()

	var dir := right * raw.x + fwd * (-raw.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	moving = dir.length() > 0.05

	var speed := SPEED_WALK
	if crouching:
		speed = SPEED_CROUCH
	elif running:
		speed = SPEED_RUN

	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	velocity.y = 0.0
	move_and_slide()

	# --- face travel direction -------------------------------------------
	if moving:
		_face_angle = lerp_angle(_face_angle, atan2(dir.x, dir.z), clamp(TURN_SPEED * delta, 0.0, 1.0))
		rotation.y = _face_angle

	# --- recompute how exposed we are ------------------------------------
	visibility = world.compute_visibility(global_position, crouching, running and moving)


func set_vision_mode(_mode: int) -> void:
	# Player visuals stay constant across goggle modes; hook kept for symmetry.
	pass
