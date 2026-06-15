extends Node
## In-game level select. Scans res://levels and user://generated for JSON
## levels and lets the player load any of them live. Together with the AI
## generator this is the "browse and play levels" half of the core loop.

var world

var layer: CanvasLayer
var open_btn: Button
var dim: ColorRect
var panel: Panel
var list_box: VBoxContainer


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 6
	add_child(layer)

	open_btn = Button.new()
	open_btn.text = "≡ LEVELS"
	open_btn.position = Vector2(1024, 110)
	open_btn.size = Vector2(232, 32)
	open_btn.pressed.connect(_open)
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
	panel.size = Vector2(560, 540)
	panel.position = Vector2((1280 - 560) * 0.5, (720 - 540) * 0.5)
	dim.add_child(panel)

	var title := Label.new()
	title.text = "≡  SELECT LEVEL"
	title.position = Vector2(24, 18)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	panel.add_child(title)

	var hint := Label.new()
	hint.text = "Built-in and AI-generated levels. Click one to play it now."
	hint.position = Vector2(24, 56)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	panel.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 90)
	scroll.size = Vector2(520, 374)
	panel.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.custom_minimum_size = Vector2(500, 0)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.position = Vector2(20, 476)
	close_btn.size = Vector2(520, 46)
	close_btn.pressed.connect(func(): _toggle(false))
	panel.add_child(close_btn)


func _open() -> void:
	_refresh()
	_toggle(true)


func _toggle(open: bool) -> void:
	dim.visible = open
	if world:
		world.set_ui_open(open)


func _refresh() -> void:
	for c in list_box.get_children():
		c.queue_free()
	for path in _scan():
		var b := Button.new()
		b.text = _level_label(path)
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_load.bind(path))
		list_box.add_child(b)


func _scan() -> Array:
	var out := []
	for dir in ["res://levels", "user://generated"]:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		da.list_dir_begin()
		var fn := da.get_next()
		while fn != "":
			if not da.current_is_dir() and fn.to_lower().ends_with(".json"):
				out.append(dir + "/" + fn)
			fn = da.get_next()
		da.list_dir_end()
	out.sort()
	return out


func _level_label(path: String) -> String:
	var nm := path.get_file()
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(d) == TYPE_DICTIONARY:
			var author := ""
			if typeof(d.get("meta", {})) == TYPE_DICTIONARY:
				author = str(d["meta"].get("author", ""))
			var tag := ""
			if path.begins_with("user://"):
				tag = "  [AI]"
			elif author == "AI":
				tag = "  [AI]"
			return "  %s%s        (%s)" % [str(d.get("name", nm)), tag, nm]
	return "  " + nm


func _load(path: String) -> void:
	if world:
		world.load_level_from_file(path)
	_toggle(false)
