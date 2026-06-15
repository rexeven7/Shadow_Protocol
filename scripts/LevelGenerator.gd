extends Node

const LevelBuilderScript = preload("res://scripts/LevelBuilder.gd")
## In-game AI level generator. Opens a panel, takes a text description, asks
## Claude (via the Anthropic Messages API) for a level matching our JSON schema,
## validates it, and hands it to the World to build live.
##
## The API key is stored locally (user://settings.cfg) and never shipped with
## the project. The generating prompt + model are saved into the level's meta
## so levels can be shared and their prompts remixed.

signal level_ready(data: Dictionary)

const API_URL := "https://api.anthropic.com/v1/messages"
const SETTINGS_PATH := "user://settings.cfg"
const GEN_DIR := "user://generated"
const DEFAULT_MODEL := "claude-sonnet-4-6"

const SYSTEM_PROMPT := """You are a level designer for an isometric stealth game, Shadow Protocol. Given a short description, output ONE JSON object describing a playable level. Output ONLY the JSON - no commentary, no markdown, no code fences.

Coordinates are on a flat plane: x in 0..bounds[0], z in 0..bounds[1]. An outer wall is added automatically around the bounds, so only list INTERIOR walls.

Schema:
{
  "name": string,
  "bounds": [width, depth],            // 24..60 by 20..40, e.g. [40,28]
  "player_start": [x,z],               // a shadowed corner
  "terminal": [x,z],                   // hack objective, place deep / guarded
  "extraction": [x,z],                 // exit, far from start
  "walls": [[x1,z1,x2,z2], ...],       // interior segments; LEAVE GAPS for doorways
  "cover": [[x,z], ...],               // pillars/crates for shadow & cover
  "lights": [{"pos":[x,z],"range":6.5,"energy":2.0,"color":[r,g,b]}],  // r,g,b 0..1; energy 1.5..2.8; range 5..9
  "guards": [{"start":[x,z],"route":[[x,z],...],"view_distance":9.5,"speed":2.4}],  // 2..6 guards; route loops 2..5 pts; route[0] should be the NEXT patrol point (not the spawn tile) so guards face their patrol direction on spawn
  "config": {"emp_charges":3, "hack_time":2.6}
}

Rules: keep all coordinates ~1 unit inside the bounds. The player MUST be able to reach the terminal then the extraction - always leave doorway gaps and never seal off an objective. Put lights near the terminal to create tension, and leave some dark corridors as stealth routes. Place guard patrols to threaten the paths between start, terminal and extraction. Make it tense but fair."""

var world

var http: HTTPRequest
var layer: CanvasLayer
var open_btn: Button
var dim: ColorRect
var panel: Panel
var desc_edit: TextEdit
var key_edit: LineEdit
var model_edit: LineEdit
var status: Label
var gen_btn: Button
var copy_btn: Button

var _last_json := ""
var _pending_prompt := ""
var _pending_model := ""


func _ready() -> void:
	_build_ui()
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_response)
	_load_key()


# ===========================================================================
# UI
# ===========================================================================
func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	open_btn = Button.new()
	open_btn.text = "✦ GENERATE LEVEL"
	open_btn.position = Vector2(1024, 74)
	open_btn.size = Vector2(232, 32)
	open_btn.pressed.connect(func(): _toggle(true))
	layer.add_child(open_btn)
	if world:
		world.register_ui_button(open_btn)

	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	layer.add_child(dim)

	panel = Panel.new()
	panel.size = Vector2(780, 540)
	panel.position = Vector2((1280 - 780) * 0.5, (720 - 540) * 0.5)
	dim.add_child(panel)

	_plabel("✦  AI LEVEL GENERATOR", Vector2(28, 18), 26, Color(0.7, 0.95, 1.0))
	_plabel("Describe a level — Claude designs it and the game builds it live. Be specific: layout, rooms, guard count, lighting, mood.",
		Vector2(28, 58), 14, Color(0.8, 0.85, 0.95), 724)

	_plabel("DESCRIPTION", Vector2(28, 96), 13, Color(0.7, 0.8, 0.9))
	desc_edit = TextEdit.new()
	desc_edit.position = Vector2(28, 118)
	desc_edit.size = Vector2(724, 150)
	desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc_edit.placeholder_text = "e.g. A tight server farm: three locked data rooms around a bright central vault, four guards on overlapping patrols, dark maintenance corridors along the edges. Extraction on the roof access in the far corner."
	panel.add_child(desc_edit)

	_plabel("ANTHROPIC API KEY  (stored locally on this machine only)", Vector2(28, 284), 12, Color(0.7, 0.8, 0.9))
	key_edit = LineEdit.new()
	key_edit.position = Vector2(28, 306)
	key_edit.size = Vector2(520, 34)
	key_edit.secret = true
	key_edit.placeholder_text = "sk-ant-..."
	panel.add_child(key_edit)

	_plabel("MODEL", Vector2(564, 284), 12, Color(0.7, 0.8, 0.9))
	model_edit = LineEdit.new()
	model_edit.position = Vector2(564, 306)
	model_edit.size = Vector2(188, 34)
	model_edit.text = DEFAULT_MODEL
	panel.add_child(model_edit)

	status = Label.new()
	status.position = Vector2(28, 350)
	status.size = Vector2(724, 70)
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status)

	gen_btn = Button.new()
	gen_btn.text = "Generate  ▶"
	gen_btn.position = Vector2(28, 446)
	gen_btn.size = Vector2(230, 52)
	gen_btn.pressed.connect(_on_generate)
	panel.add_child(gen_btn)

	copy_btn = Button.new()
	copy_btn.text = "Copy level JSON"
	copy_btn.position = Vector2(274, 446)
	copy_btn.size = Vector2(238, 52)
	copy_btn.disabled = true
	copy_btn.pressed.connect(_on_copy)
	panel.add_child(copy_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.position = Vector2(528, 446)
	close_btn.size = Vector2(224, 52)
	close_btn.pressed.connect(func(): _toggle(false))
	panel.add_child(close_btn)

	_plabel("Tip: the prompt + model are saved into the level so others can play and remix it.",
		Vector2(28, 508), 12, Color(0.6, 0.7, 0.8), 724)


func _plabel(text: String, pos: Vector2, size: int, color: Color, width: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if width > 0:
		l.size.x = width
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(l)
	return l


func _toggle(open: bool) -> void:
	dim.visible = open
	if world:
		world.set_ui_open(open)
	if open:
		desc_edit.grab_focus()


# ===========================================================================
# Generation
# ===========================================================================
func _on_generate() -> void:
	var desc := desc_edit.text.strip_edges()
	var key := key_edit.text.strip_edges()
	var model := model_edit.text.strip_edges()
	if model == "":
		model = DEFAULT_MODEL
	if desc.length() < 8:
		_status("Describe the level first (a sentence or two).", Color(1.0, 0.7, 0.3))
		return
	if key == "":
		_status("Enter your Anthropic API key. It's stored only on this machine.", Color(1.0, 0.7, 0.3))
		return

	_save_key(key)
	_pending_prompt = desc
	_pending_model = model

	var body := {
		"model": model,
		"max_tokens": 4000,
		"system": SYSTEM_PROMPT,
		"messages": [{"role": "user", "content": desc}],
	}
	var headers := PackedStringArray([
		"x-api-key: " + key,
		"anthropic-version: 2023-06-01",
		"content-type: application/json",
	])
	var err := http.request(API_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_status("Could not start the request (error %d)." % err, Color(1.0, 0.4, 0.4))
		return
	gen_btn.disabled = true
	_status("Contacting Claude (%s)…" % model, Color(0.7, 0.9, 1.0))


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	gen_btn.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_status("Network error (result %d). Check your connection." % result, Color(1.0, 0.4, 0.4))
		return

	var text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)

	if code != 200:
		var msg := "API error %d" % code
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
			msg += ": " + str(parsed["error"].get("message", ""))
		_status(msg, Color(1.0, 0.4, 0.4))
		return

	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("content"):
		_status("Unexpected API response.", Color(1.0, 0.4, 0.4))
		return

	# Pull the text out of the message content blocks.
	var raw_text := ""
	for block in parsed["content"]:
		if typeof(block) == TYPE_DICTIONARY and block.get("type", "") == "text":
			raw_text += str(block.get("text", ""))

	var json_str := _extract_json(raw_text)
	var level = JSON.parse_string(json_str)
	if typeof(level) != TYPE_DICTIONARY:
		_status("Claude didn't return valid level JSON. Try rephrasing.\n" + raw_text.substr(0, 160), Color(1.0, 0.5, 0.3))
		return

	var data := LevelBuilderScript.sanitize(level)
	data["meta"] = {
		"author": "AI",
		"prompt": _pending_prompt,
		"model": _pending_model,
		"created": Time.get_datetime_string_from_system(),
	}

	_last_json = JSON.stringify(data, "  ")
	copy_btn.disabled = false
	_save_level_file(data)

	level_ready.emit(data)
	_toggle(false)
	_status("Built '%s'. Have fun." % str(data.get("name", "level")), Color(0.4, 1.0, 0.6))


func _extract_json(text: String) -> String:
	var a := text.find("{")
	var b := text.rfind("}")
	if a >= 0 and b > a:
		return text.substr(a, b - a + 1)
	return text


func _on_copy() -> void:
	if _last_json != "":
		DisplayServer.clipboard_set(_last_json)
		_status("Level JSON copied to clipboard — share it!", Color(0.6, 0.95, 0.8))


# ===========================================================================
# Persistence
# ===========================================================================
func _load_key() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		key_edit.text = str(cfg.get_value("api", "key", ""))
		var m := str(cfg.get_value("api", "model", DEFAULT_MODEL))
		if m != "":
			model_edit.text = m


func _save_key(key: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("api", "key", key)
	cfg.set_value("api", "model", model_edit.text.strip_edges())
	cfg.save(SETTINGS_PATH)


func _save_level_file(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(GEN_DIR)
	var fname := str(data.get("name", "level")).to_lower().replace(" ", "_")
	var path := "%s/%s_%d.json" % [GEN_DIR, fname, int(Time.get_unix_time_from_system())]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


func _status(msg: String, color: Color) -> void:
	status.text = msg
	status.add_theme_color_override("font_color", color)
