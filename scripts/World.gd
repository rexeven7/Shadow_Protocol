extends Node3D
## Shadow Protocol - runtime orchestrator.
## Persistent systems (camera, lighting env, HUD, audio, vision post-process,
## AI generator) live here. The actual LEVEL is data: loaded from JSON and built
## by LevelBuilder into a swappable "LevelRoot", so levels can be hand-authored,
## AI-generated, and rebuilt live without restarting.

const LevelBuilderScript = preload("res://scripts/LevelBuilder.gd")
const LevelGeneratorScript = preload("res://scripts/LevelGenerator.gd")
const LevelBrowserScript = preload("res://scripts/LevelBrowser.gd")

const AMBIENT_VIS := 0.05
const EMP_RADIUS := 9.0
const EMP_DURATION := 6.0
const EMP_CHARGES := 3
const HACK_TIME := 2.6
const TAKEDOWN_RANGE := 1.8
const VISION_NAMES := ["NORMAL", "NIGHT VISION", "THERMAL"]
const DEFAULT_LEVEL := "res://levels/level_01.json"

# --- state ---
var active := true
var ui_open := false
var player
var guards := []
var level_lights := []
var emp_disabled := []
var vision_mode := 0
var emp_charges := EMP_CHARGES
var hack_progress := 0.0
var hack_time := HACK_TIME
var hacked := false
var terminal_pos := Vector3.ZERO
var extraction_pos := Vector3.ZERO
var current_data := {}
var level_root: Node3D

# --- run stats (seed for leaderboards / "best levels") ---
var stat_time := 0.0
var stat_spotted := 0
var stat_takedowns := 0
var stat_emp := 0

# --- persistent nodes ---
var cam_pivot: Node3D
var camera: Camera3D
var post_rect: ColorRect
var post_mat: ShaderMaterial
var audio
var generator
var browser
var ui_buttons := []

# --- HUD refs ---
var obj_label: Label
var level_name_label: Label
var alert_label: Label
var stance_label: Label
var mode_label: Label
var gadget_label: Label
var prompt_label: Label
var status_label: Label
var sub_status_label: Label
var vis_fill: ColorRect
var det_fill: ColorRect
var hack_root: Control
var hack_fill: ColorRect

const VIS_BAR_W := 220.0
const DET_BAR_W := 260.0
const HACK_BAR_W := 300.0

var _step_timer := 0.0
var _was_suspicious := false
var _hack_beep_timer := 0.0


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_camera()
	_build_post_and_hud()

	audio = Node.new()
	audio.set_script(load("res://scripts/Audio.gd"))
	add_child(audio)
	audio.call("start_loops")

	generator = LevelGeneratorScript.new()
	generator.world = self
	add_child(generator)
	generator.level_ready.connect(_on_level_generated)

	browser = LevelBrowserScript.new()
	browser.world = self
	add_child(browser)

	load_level_from_file(DEFAULT_LEVEL)


# ---------------------------------------------------------------------------
# UI focus — panels register their open buttons; all hide while any panel is open
# ---------------------------------------------------------------------------
func register_ui_button(b: Button) -> void:
	ui_buttons.append(b)


func set_ui_open(v: bool) -> void:
	ui_open = v
	for b in ui_buttons:
		if is_instance_valid(b):
			b.visible = not v


# ---------------------------------------------------------------------------
# Input map (runtime)
# ---------------------------------------------------------------------------
func _setup_input() -> void:
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("run", [KEY_SHIFT])
	_add_action("crouch", [KEY_CTRL, KEY_C])
	_add_action("takedown", [KEY_E])
	_add_action("interact", [KEY_F])
	_add_action("vision", [KEY_V, KEY_TAB])
	_add_action("gadget", [KEY_G])
	_add_action("restart", [KEY_R])


func _add_action(action_name: String, keys: Array) -> void:
	if InputMap.has_action(action_name):
		InputMap.action_erase_events(action_name)
	else:
		InputMap.add_action(action_name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action_name, ev)


# ---------------------------------------------------------------------------
# Persistent environment / camera
# ---------------------------------------------------------------------------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.22, 0.34)
	env.ambient_light_energy = 0.18
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.12)
	env.fog_density = 0.012
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.55, 0.65, 0.95)
	sun.light_energy = 0.22
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-62, 38, 0)
	add_child(sun)


func _build_camera() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.rotation_degrees = Vector3(-40, 45, 0)
	add_child(cam_pivot)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19.0
	camera.near = 0.1
	camera.far = 300.0
	camera.position = Vector3(0, 0, 60)
	camera.current = true
	cam_pivot.add_child(camera)


# ---------------------------------------------------------------------------
# Level loading / live rebuild
# ---------------------------------------------------------------------------
func load_level_from_file(path: String) -> void:
	var data := {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	load_level_from_data(data)


func _on_level_generated(data: Dictionary) -> void:
	load_level_from_data(data)


func load_level_from_data(data: Dictionary) -> void:
	current_data = LevelBuilderScript.sanitize(data)

	if level_root and is_instance_valid(level_root):
		level_root.free()

	level_root = Node3D.new()
	level_root.name = "LevelRoot"
	add_child(level_root)

	var builder := LevelBuilderScript.new()
	var res := builder.build(self, level_root, current_data)
	player = res["player"]
	guards = res["guards"]
	level_lights = res["lights"]
	terminal_pos = res["terminal_pos"]
	extraction_pos = res["extraction_pos"]
	var cfg = res["config"]
	emp_charges = int(cfg.get("emp_charges", EMP_CHARGES))
	hack_time = float(cfg.get("hack_time", HACK_TIME))

	# reset gameplay state
	active = true
	hacked = false
	hack_progress = 0.0
	_was_suspicious = false
	_hack_beep_timer = 0.0
	emp_disabled.clear()
	vision_mode = 0
	_apply_vision_mode()

	# reset stats
	stat_time = 0.0
	stat_spotted = 0
	stat_takedowns = 0
	stat_emp = 0

	cam_pivot.global_position = player.global_position

	obj_label.text = "OBJECTIVE: Reach and hack the data terminal"
	status_label.text = ""
	sub_status_label.text = ""
	level_name_label.text = str(current_data.get("name", ""))
	hack_root.visible = false


# ---------------------------------------------------------------------------
# HUD (persistent)
# ---------------------------------------------------------------------------
func _build_post_and_hud() -> void:
	var post_layer := CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	post_rect = ColorRect.new()
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/vision.gdshader")
	post_rect.material = post_mat
	post_rect.visible = false
	post_layer.add_child(post_rect)

	var hud := CanvasLayer.new()
	hud.layer = 1
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	obj_label = _label(root, "OBJECTIVE: Reach and hack the data terminal", Vector2(24, 20), 20, Color(0.85, 0.95, 1.0))
	alert_label = _label(root, "UNDETECTED", Vector2(24, 48), 16, Color(0.4, 1.0, 0.5))
	level_name_label = _label(root, "", Vector2(24, 74), 13, Color(0.55, 0.65, 0.8))

	_label(root, "DETECTION", Vector2(640 - DET_BAR_W * 0.5, 20), 13, Color(0.8, 0.8, 0.85))
	det_fill = _bar(root, Vector2(640 - DET_BAR_W * 0.5, 40), Vector2(DET_BAR_W, 14), Color(1.0, 0.85, 0.2))

	mode_label = _label(root, "VISION: NORMAL", Vector2(1024, 20), 16, Color(0.7, 0.95, 1.0))
	mode_label.size.x = 232
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gadget_label = _label(root, "EMP x3  [G]", Vector2(1024, 46), 16, Color(0.6, 0.9, 1.0))
	gadget_label.size.x = 232
	gadget_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_label(root, "VISIBILITY", Vector2(24, 660), 13, Color(0.8, 0.8, 0.85))
	vis_fill = _bar(root, Vector2(24, 680), Vector2(VIS_BAR_W, 16), Color(0.3, 0.9, 0.5))
	stance_label = _label(root, "STANDING", Vector2(24, 632), 14, Color(0.75, 0.85, 0.95))

	hack_root = Control.new()
	hack_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hack_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hack_root.visible = false
	root.add_child(hack_root)
	_label(hack_root, "HACKING...", Vector2(640 - HACK_BAR_W * 0.5, 380), 16, Color(0.3, 0.95, 1.0))
	hack_fill = _bar(hack_root, Vector2(640 - HACK_BAR_W * 0.5, 404), Vector2(HACK_BAR_W, 18), Color(0.3, 0.95, 1.0))

	prompt_label = _label(root, "", Vector2(640 - 250, 600), 18, Color(1.0, 0.95, 0.6))
	prompt_label.size.x = 500
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var controls := _label(root,
		"WASD move   SHIFT run   CTRL crouch\nV goggles   G EMP   E takedown   F hack   R restart",
		Vector2(1280 - 430, 648), 13, Color(0.6, 0.65, 0.75))
	controls.size.x = 410
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	status_label = _label(root, "", Vector2(0, 300), 56, Color(1, 1, 1))
	status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_status_label = _label(root, "", Vector2(0, 380), 22, Color(0.9, 0.9, 0.9))
	sub_status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_status_label.position.y = 70


func _label(parent: Control, text: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, pos: Vector2, size: Vector2, fill_color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.position = pos
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = pos + Vector2(2, 2)
	fill.size = Vector2(size.x - 4, size.y - 4)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_meta("full_w", size.x - 4)
	parent.add_child(fill)
	return fill


func _set_bar(fill: ColorRect, value: float) -> void:
	var fw: float = fill.get_meta("full_w")
	fill.size.x = clamp(value, 0.0, 1.0) * fw


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_follow_camera(delta)
	post_mat.set_shader_parameter("time_val", Time.get_ticks_msec() * 0.001)
	_update_emp()
	_update_guard_visibility()

	var maxd := _max_detection()
	if audio:
		audio.call("set_tension", maxd, active and not ui_open)

	if Input.is_action_just_pressed("restart") and not ui_open:
		load_level_from_data(current_data.duplicate(true))
		return

	if active and not ui_open:
		stat_time += delta
		if Input.is_action_just_pressed("vision"):
			vision_mode = (vision_mode + 1) % 3
			_apply_vision_mode()
			if audio:
				audio.call("play", "vision", -6.0)
		if Input.is_action_just_pressed("gadget"):
			_fire_emp()
		_handle_objective(delta)
		_handle_takedown()
		_update_footsteps(delta)

	_update_hud(maxd)


func _follow_camera(delta: float) -> void:
	if player == null:
		return
	var t: float = clamp(delta * 7.0, 0.0, 1.0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(player.global_position, t)


func _update_footsteps(delta: float) -> void:
	if player == null or audio == null:
		return
	if not bool(player.get("moving")):
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		var interval := 0.42
		var vol := -12.0
		if bool(player.get("crouching")):
			interval = 0.6
			vol = -20.0
		elif bool(player.get("running")):
			interval = 0.28
			vol = -7.0
		_step_timer = interval
		audio.call("play", "footstep", vol, randf_range(0.9, 1.15))


func _max_detection() -> float:
	var maxd := 0.0
	for g in guards:
		if g.get("downed"):
			continue
		maxd = max(maxd, float(g.get("detection")))
	return maxd


# ---------------------------------------------------------------------------
# Objective
# ---------------------------------------------------------------------------
func _handle_objective(delta: float) -> void:
	if player == null:
		return
	var ppos: Vector3 = player.global_position

	if not hacked:
		var near_term := Vector2(ppos.x, ppos.z).distance_to(Vector2(terminal_pos.x, terminal_pos.z)) < 2.2
		if near_term and Input.is_action_pressed("interact"):
			hack_progress += delta / hack_time
			hack_root.visible = true
			_hack_beep_timer -= delta
			if _hack_beep_timer <= 0.0 and audio:
				_hack_beep_timer = 0.34
				audio.call("play", "hack_beep", -9.0, randf_range(0.97, 1.06))
			if hack_progress >= 1.0:
				hacked = true
				hack_progress = 1.0
				hack_root.visible = false
				obj_label.text = "OBJECTIVE: Reach the EXTRACTION zone"
				if audio:
					audio.call("play", "hack_done", -3.0)
		else:
			hack_progress = max(0.0, hack_progress - delta * 0.5)
			hack_root.visible = hack_progress > 0.01
	else:
		var near_ext := Vector2(ppos.x, ppos.z).distance_to(Vector2(extraction_pos.x, extraction_pos.z)) < 2.4
		if near_ext:
			_win()


func _current_prompt() -> String:
	if player == null:
		return ""
	var ppos: Vector3 = player.global_position
	if _takedown_target() != null:
		return "[E]  Silent Takedown"
	if not hacked:
		if Vector2(ppos.x, ppos.z).distance_to(Vector2(terminal_pos.x, terminal_pos.z)) < 2.2:
			return "[F]  Hold to hack terminal"
	else:
		if Vector2(ppos.x, ppos.z).distance_to(Vector2(extraction_pos.x, extraction_pos.z)) < 4.0:
			return ">>> EXTRACTION ZONE <<<"
	return ""


# ---------------------------------------------------------------------------
# Takedowns
# ---------------------------------------------------------------------------
func _takedown_target():
	if player == null:
		return null
	var best = null
	var best_d := TAKEDOWN_RANGE
	for g in guards:
		if g.get("downed"):
			continue
		var d: float = player.global_position.distance_to(g.global_position)
		if d > best_d:
			continue
		var to_player: Vector3 = (player.global_position - g.global_position).normalized()
		var fwd: Vector3 = g.call("forward")
		if fwd.dot(to_player) < -0.1:
			best = g
			best_d = d
	return best


func _handle_takedown() -> void:
	if Input.is_action_just_pressed("takedown"):
		var g = _takedown_target()
		if g != null:
			g.call("take_down")
			stat_takedowns += 1
			if audio:
				audio.call("play", "takedown", -2.0)


# ---------------------------------------------------------------------------
# EMP gadget
# ---------------------------------------------------------------------------
func _fire_emp() -> void:
	if emp_charges <= 0 or player == null:
		return
	var hit := 0
	var until := Time.get_ticks_msec() + int(EMP_DURATION * 1000.0)
	for L in level_lights:
		if not L["enabled"]:
			continue
		if player.global_position.distance_to(L["pos"]) <= EMP_RADIUS:
			L["enabled"] = false
			L["node"].visible = false
			emp_disabled.append({"light": L, "until": until})
			hit += 1
	if hit > 0:
		emp_charges -= 1
		stat_emp += 1
		if audio:
			audio.call("play", "emp", -3.0)


func _update_emp() -> void:
	if emp_disabled.is_empty():
		return
	var now := Time.get_ticks_msec()
	var still := []
	for e in emp_disabled:
		if now >= e["until"]:
			e["light"]["enabled"] = true
			e["light"]["node"].visible = true
		else:
			still.append(e)
	emp_disabled = still


# ---------------------------------------------------------------------------
# Vision modes
# ---------------------------------------------------------------------------
func _apply_vision_mode() -> void:
	post_mat.set_shader_parameter("mode", vision_mode)
	post_rect.visible = vision_mode != 0
	for g in guards:
		g.call("set_vision_mode", vision_mode)
	if player:
		player.call("set_vision_mode", vision_mode)
	_update_guard_visibility()


func _update_guard_visibility() -> void:
	if player == null:
		return
	var thermal := vision_mode == 2
	var eye: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	for g in guards:
		if not is_instance_valid(g):
			continue
		var seen := thermal
		if not seen:
			var target: Vector3 = g.global_position + Vector3(0, 1.0, 0)
			seen = has_los(eye, target)
		g.call("set_player_visible", seen, thermal)


# ---------------------------------------------------------------------------
# Visibility / line-of-sight
# ---------------------------------------------------------------------------
func compute_visibility(pos: Vector3, crouching: bool, running: bool) -> float:
	var v := AMBIENT_VIS
	for L in level_lights:
		if not L["enabled"]:
			continue
		var lp: Vector3 = L["pos"]
		var d: float = pos.distance_to(lp)
		var rad: float = L["radius"]
		if d >= rad:
			continue
		if is_occluded(pos + Vector3(0, 1.0, 0), lp):
			continue
		var f := 1.0 - d / rad
		v += float(L["energy"]) * 0.42 * f * f
	if crouching:
		v *= 0.6
	if running:
		v += 0.12
	return clamp(v, 0.0, 1.0)


func is_occluded(a: Vector3, b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	return not space.intersect_ray(q).is_empty()


func has_los(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


# ---------------------------------------------------------------------------
# Win / lose
# ---------------------------------------------------------------------------
func on_player_spotted() -> void:
	if not active:
		return
	active = false
	if audio:
		audio.call("play", "alarm", -2.0)
	status_label.text = "MISSION FAILED"
	status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	sub_status_label.text = "You were spotted.   " + _stats_line() + "    [R] retry"
	alert_label.text = "DETECTED"
	alert_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


func _win() -> void:
	if not active:
		return
	active = false
	if audio:
		audio.call("play", "success", -2.0)
	status_label.text = "MISSION COMPLETE"
	status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	sub_status_label.text = "Data secured.   " + _stats_line() + "    [R] play again"


func _stats_line() -> String:
	return "Time %.1fs   Spotted x%d   Takedowns x%d   EMP x%d" % [stat_time, stat_spotted, stat_takedowns, stat_emp]


# ---------------------------------------------------------------------------
# HUD refresh
# ---------------------------------------------------------------------------
func _update_hud(maxd: float) -> void:
	if player == null:
		return

	var vis: float = player.get("visibility")
	_set_bar(vis_fill, vis)
	vis_fill.color = Color(0.3, 0.9, 0.5).lerp(Color(1.0, 0.3, 0.25), vis)

	if bool(player.get("crouching")):
		stance_label.text = "CROUCHED  (quiet, low profile)"
	elif bool(player.get("running")) and bool(player.get("moving")):
		stance_label.text = "RUNNING  (fast, loud, exposed)"
	else:
		stance_label.text = "STANDING"

	_set_bar(det_fill, maxd)
	det_fill.color = Color(0.3, 0.9, 0.5).lerp(Color(1.0, 0.2, 0.2), maxd)

	if active and not ui_open:
		if maxd > 0.3 and not _was_suspicious:
			_was_suspicious = true
			stat_spotted += 1
			if audio:
				audio.call("play", "alert", -4.0)
		elif maxd < 0.12:
			_was_suspicious = false

	if active:
		if maxd >= 0.99:
			pass
		elif maxd > 0.45:
			alert_label.text = "SPOTTED — BREAK LINE OF SIGHT!"
			alert_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.25))
		elif maxd > 0.12:
			alert_label.text = "SUSPICIOUS"
			alert_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		else:
			alert_label.text = "UNDETECTED"
			alert_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))

	mode_label.text = "VISION: " + VISION_NAMES[vision_mode]
	gadget_label.text = "EMP x%d  [G]" % emp_charges

	if hack_root.visible:
		_set_bar(hack_fill, hack_progress)

	prompt_label.text = _current_prompt()
