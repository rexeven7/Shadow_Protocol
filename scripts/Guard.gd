extends CharacterBody3D
## Patrolling guard with a visible vision cone and a light-aware detection
## meter. Sees you faster when you're well-lit and close; barely at all when
## you're in shadow. Fill the meter and the mission fails.
##
## view_distance and patrol_speed are set per-guard by the LevelBuilder, so
## levels (and the AI generator) can tune difficulty.

var world                          # set by LevelBuilder
var player                         # set by LevelBuilder
var waypoints := []                # Array[Vector3]
var view_distance := 9.5           # overridden per level
var patrol_speed := 2.4            # overridden per level

const VIEW_HALF_ANGLE := 32.0      # degrees, half of the cone
const DETECT_GAIN := 1.15
const DETECT_RECOVER := 0.55

enum State { PATROL, SUSPICIOUS, ALERT, DOWN }

var detection := 0.0
var downed := false
var state: int = State.PATROL
var wp_index := 0
var last_seen := Vector3.ZERO
var _view_cos := 0.0
var _foot_timer := 0.0

var body_mat: StandardMaterial3D
var base_albedo := Color(0.45, 0.16, 0.16)
var cone_mi: MeshInstance3D
var cone_mat: StandardMaterial3D
var eye: SpotLight3D
var foot3d: AudioStreamPlayer3D


func _ready() -> void:
	_view_cos = cos(deg_to_rad(VIEW_HALF_ANGLE))
	_build_visuals()
	_build_audio()
	_align_to_patrol()


## Skip waypoints we're already standing on and face the next leg of the route.
## Many levels put start on route[0], which left guards at default rotation (+Z)
## staring at whatever wall happened to be in front of them.
func _align_to_patrol() -> void:
	if waypoints.is_empty():
		return
	var start_i := wp_index
	for _i in range(waypoints.size()):
		var d: Vector3 = waypoints[wp_index] - global_position
		d.y = 0
		if d.length() >= 0.5:
			break
		wp_index = (wp_index + 1) % waypoints.size()
		if wp_index == start_i:
			break
	var to_next: Vector3 = waypoints[wp_index] - global_position
	to_next.y = 0
	if to_next.length() > 0.01:
		rotation.y = atan2(to_next.x, to_next.z)


func _build_visuals() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.7
	body.mesh = cap
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = base_albedo
	body_mat.roughness = 0.7
	body.material_override = body_mat
	add_child(body)

	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.5, 0.42, 0.5)
	head.mesh = hb
	head.position = Vector3(0, 0.78, 0)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.3, 0.1, 0.1)
	head.material_override = hm
	add_child(head)

	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.42, 0.12, 0.08)
	visor.mesh = vb
	visor.position = Vector3(0, 0.78, 0.26)
	var vm := StandardMaterial3D.new()
	vm.emission_enabled = true
	vm.emission = Color(1.0, 0.5, 0.2)
	vm.emission_energy_multiplier = 2.0
	vm.albedo_color = Color(1.0, 0.5, 0.2)
	visor.material_override = vm
	add_child(visor)

	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.4
	cs.height = 1.7
	col.shape = cs
	add_child(col)

	eye = SpotLight3D.new()
	eye.position = Vector3(0, 1.4, 0.2)
	eye.rotation_degrees = Vector3(-6, 180, 0)  # SpotLight shines -Z by default; flip to face +Z (forward)
	eye.spot_range = view_distance
	eye.spot_angle = VIEW_HALF_ANGLE + 4.0
	eye.light_energy = 2.2
	eye.light_color = Color(1.0, 0.95, 0.8)
	eye.shadow_enabled = false
	add_child(eye)

	cone_mi = _build_cone()
	add_child(cone_mi)


func _build_audio() -> void:
	if world == null or world.audio == null:
		return
	var s = world.audio.get_stream("footstep")
	if s == null:
		return
	foot3d = AudioStreamPlayer3D.new()
	foot3d.stream = s
	foot3d.unit_size = 3.0
	foot3d.max_distance = 26.0
	foot3d.volume_db = -7.0
	add_child(foot3d)


func _build_cone() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	cone_mat = StandardMaterial3D.new()
	cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.16)

	var segments := 18
	var start := -deg_to_rad(VIEW_HALF_ANGLE)
	var step := deg_to_rad(VIEW_HALF_ANGLE * 2.0) / float(segments)
	var y := -0.83  # local; guard origin sits at y=0.9 so this lands just above the floor
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, cone_mat)
	for i in range(segments):
		var a0 := start + step * i
		var a1 := start + step * (i + 1)
		var p0 := Vector3(sin(a0), 0, cos(a0)) * view_distance
		var p1 := Vector3(sin(a1), 0, cos(a1)) * view_distance
		im.surface_add_vertex(Vector3(0, y, 0))
		im.surface_add_vertex(Vector3(p0.x, y, p0.z))
		im.surface_add_vertex(Vector3(p1.x, y, p1.z))
	im.surface_end()
	mi.mesh = im
	mi.material_override = cone_mat
	return mi


func forward() -> Vector3:
	return global_transform.basis.z


func _physics_process(delta: float) -> void:
	if downed or world == null or player == null:
		velocity = Vector3.ZERO
		return
	if not world.active or world.ui_open:
		velocity = Vector3.ZERO
		return

	_update_detection(delta)
	_update_state()
	_move(delta)
	_update_cone_color()

	if detection >= 1.0:
		world.on_player_spotted()


func _update_detection(delta: float) -> void:
	var to_p: Vector3 = player.global_position - global_position
	var dist := to_p.length()
	var seen := false
	if dist <= view_distance and dist > 0.05:
		var dirp := to_p.normalized()
		if forward().dot(dirp) >= _view_cos:
			var eye_pos := global_position + Vector3(0, 1.4, 0)
			var target: Vector3 = player.global_position + Vector3(0, 1.0, 0)
			if world.has_los(eye_pos, target):
				seen = true

	if seen:
		var prox: float = clamp(1.0 - dist / view_distance, 0.0, 1.0)
		var vis: float = player.get("visibility")
		var rate: float = (0.12 + vis * 1.25) * (0.45 + prox) * DETECT_GAIN
		detection += rate * delta
		last_seen = player.global_position
	else:
		detection -= DETECT_RECOVER * delta

	detection = clamp(detection, 0.0, 1.0)


func _update_state() -> void:
	if detection < 0.12:
		state = State.PATROL
	elif detection < 0.99:
		state = State.SUSPICIOUS
	else:
		state = State.ALERT


func _move(delta: float) -> void:
	if waypoints.is_empty():
		return

	if state == State.SUSPICIOUS or state == State.ALERT:
		velocity = Vector3.ZERO
		var d := last_seen - global_position
		d.y = 0
		if d.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), clamp(8.0 * delta, 0.0, 1.0))
		move_and_slide()
		return

	var target: Vector3 = waypoints[wp_index]
	var to_t := target - global_position
	to_t.y = 0
	if to_t.length() < 0.5:
		wp_index = (wp_index + 1) % waypoints.size()
	else:
		var dir := to_t.normalized()
		velocity.x = dir.x * patrol_speed
		velocity.z = dir.z * patrol_speed
		velocity.y = 0
		move_and_slide()
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clamp(6.0 * delta, 0.0, 1.0))
		_step_audio(delta)


func _step_audio(delta: float) -> void:
	if foot3d == null:
		return
	_foot_timer -= delta
	if _foot_timer <= 0.0:
		_foot_timer = 0.52
		foot3d.pitch_scale = randf_range(0.8, 0.95)
		foot3d.play()


func _update_cone_color() -> void:
	var c: Color
	match state:
		State.PATROL:
			c = Color(0.3, 1.0, 0.4, 0.14)
		State.SUSPICIOUS:
			c = Color(1.0, 0.8, 0.2, 0.20).lerp(Color(1.0, 0.4, 0.1, 0.26), detection)
		_:
			c = Color(1.0, 0.2, 0.15, 0.3)
	cone_mat.albedo_color = c
	if eye:
		eye.light_color = Color(c.r, c.g, c.b) * 0.7 + Color(0.5, 0.5, 0.5)


func set_player_visible(visible_to_player: bool, thermal: bool) -> void:
	visible = thermal or visible_to_player


func set_vision_mode(mode: int) -> void:
	if downed:
		return
	if mode == 2:
		body_mat.emission_enabled = true
		body_mat.emission = Color(1.0, 0.45, 0.1)
		body_mat.emission_energy_multiplier = 4.5
		body_mat.albedo_color = Color(0.5, 0.2, 0.1)
	else:
		body_mat.emission_enabled = false
		body_mat.albedo_color = base_albedo


func take_down() -> void:
	if downed:
		return
	downed = true
	state = State.DOWN
	detection = 0.0
	velocity = Vector3.ZERO
	if cone_mi:
		cone_mi.visible = false
	if eye:
		eye.visible = false
	body_mat.emission_enabled = false
	body_mat.albedo_color = Color(0.2, 0.2, 0.22)
	rotation = Vector3(deg_to_rad(88), rotation.y, 0)
	position.y = 0.4
