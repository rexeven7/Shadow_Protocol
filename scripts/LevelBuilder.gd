extends RefCounted
## Turns a level Dictionary (parsed from JSON, hand-authored or AI-generated)
## into actual 3D nodes under a parent. This is the modular "building blocks"
## layer: levels are pure data, this assembles them. sanitize() makes it robust
## to imperfect / AI-produced data so a slightly-off level still loads.

const WALL_HEIGHT := 2.2
const WALL_THICK := 0.4
const LIGHT_Y := 3.2


# ===========================================================================
# Validation / defaults — keeps the builder crash-proof on messy input
# ===========================================================================
static func sanitize(raw) -> Dictionary:
	var d := {}
	if typeof(raw) != TYPE_DICTIONARY:
		raw = {}
	d["schema_version"] = int(raw.get("schema_version", 1))
	d["name"] = str(raw.get("name", "Generated Site"))
	d["meta"] = raw.get("meta", {})

	var b = raw.get("bounds", [40, 28])
	var bw := 40.0
	var bh := 28.0
	if typeof(b) == TYPE_ARRAY and b.size() >= 2:
		bw = clampf(float(b[0]), 22.0, 64.0)
		bh = clampf(float(b[1]), 18.0, 44.0)
	d["bounds"] = [bw, bh]

	d["player_start"] = _pt(raw.get("player_start", [4, 4]), bw, bh, Vector2(4, 4))
	d["terminal"] = _pt(raw.get("terminal", [bw * 0.5, bh * 0.5]), bw, bh, Vector2(bw * 0.5, bh * 0.5))
	d["extraction"] = _pt(raw.get("extraction", [bw - 4, bh - 4]), bw, bh, Vector2(bw - 4, bh - 4))

	# walls: [x1,z1,x2,z2]
	var walls := []
	for w in _arr(raw.get("walls", [])):
		if typeof(w) == TYPE_ARRAY and w.size() >= 4:
			walls.append([
				clampf(float(w[0]), 0.0, bw), clampf(float(w[1]), 0.0, bh),
				clampf(float(w[2]), 0.0, bw), clampf(float(w[3]), 0.0, bh)])
	d["walls"] = walls

	var cover := []
	for c in _arr(raw.get("cover", [])):
		if typeof(c) == TYPE_ARRAY and c.size() >= 2:
			cover.append([clampf(float(c[0]), 0.5, bw - 0.5), clampf(float(c[1]), 0.5, bh - 0.5)])
	d["cover"] = cover

	var lights := []
	for l in _arr(raw.get("lights", [])):
		if typeof(l) != TYPE_DICTIONARY:
			continue
		var p = l.get("pos", [bw * 0.5, bh * 0.5])
		if typeof(p) != TYPE_ARRAY or p.size() < 2:
			continue
		var col = l.get("color", [1.0, 0.9, 0.7])
		var cr := 1.0
		var cg := 0.9
		var cb := 0.7
		if typeof(col) == TYPE_ARRAY and col.size() >= 3:
			cr = clampf(float(col[0]), 0.0, 1.0)
			cg = clampf(float(col[1]), 0.0, 1.0)
			cb = clampf(float(col[2]), 0.0, 1.0)
		lights.append({
			"pos": [clampf(float(p[0]), 0.0, bw), clampf(float(p[1]), 0.0, bh)],
			"range": clampf(float(l.get("range", 6.5)), 3.0, 14.0),
			"energy": clampf(float(l.get("energy", 2.0)), 0.4, 4.0),
			"color": [cr, cg, cb],
		})
	d["lights"] = lights

	var guards := []
	for g in _arr(raw.get("guards", [])):
		if typeof(g) != TYPE_DICTIONARY:
			continue
		var route := []
		for rp in _arr(g.get("route", [])):
			if typeof(rp) == TYPE_ARRAY and rp.size() >= 2:
				route.append([clampf(float(rp[0]), 0.5, bw - 0.5), clampf(float(rp[1]), 0.5, bh - 0.5)])
		var start = _pt(g.get("start", route[0] if route.size() > 0 else [bw * 0.5, bh * 0.5]), bw, bh, Vector2(bw * 0.5, bh * 0.5))
		if route.is_empty():
			route = [[start.x, start.y]]
		guards.append({
			"start": [start.x, start.y],
			"route": route,
			"view_distance": clampf(float(g.get("view_distance", 9.5)), 5.0, 13.0),
			"speed": clampf(float(g.get("speed", 2.4)), 1.2, 3.6),
		})
	d["guards"] = guards

	var cfg = raw.get("config", {})
	if typeof(cfg) != TYPE_DICTIONARY:
		cfg = {}
	d["config"] = {
		"emp_charges": clampi(int(cfg.get("emp_charges", 3)), 0, 9),
		"hack_time": clampf(float(cfg.get("hack_time", 2.6)), 0.8, 8.0),
	}
	return d


static func _arr(v) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []


static func _pt(v, bw: float, bh: float, fallback: Vector2) -> Vector2:
	if typeof(v) == TYPE_ARRAY and v.size() >= 2:
		return Vector2(clampf(float(v[0]), 0.5, bw - 0.5), clampf(float(v[1]), 0.5, bh - 0.5))
	return fallback


# ===========================================================================
# Build
# ===========================================================================
func build(world, parent: Node3D, data: Dictionary) -> Dictionary:
	var bounds = data["bounds"]
	var w := float(bounds[0])
	var h := float(bounds[1])

	_floor(parent, w, h)

	# Outer perimeter (auto) so authored data only lists interior walls.
	_wall(parent, 0, 0, w, 0)
	_wall(parent, 0, h, w, h)
	_wall(parent, 0, 0, 0, h)
	_wall(parent, w, 0, w, h)

	for wall in data["walls"]:
		_wall(parent, wall[0], wall[1], wall[2], wall[3])

	for c in data["cover"]:
		_cover(parent, c[0], c[1])

	var level_lights := []
	for l in data["lights"]:
		level_lights.append(_lamp(parent, l))

	var tp = data["terminal"]
	var terminal_pos := Vector3(tp.x, 0, tp.y)
	_terminal(parent, terminal_pos)

	var ep = data["extraction"]
	var extraction_pos := Vector3(ep.x, 0, ep.y)
	_extraction(parent, extraction_pos)

	var sp = data["player_start"]
	_pad(parent, Vector3(sp.x, 0, sp.y))
	var player = _spawn_player(world, parent, Vector3(sp.x, 0.9, sp.y))

	var guards := []
	for g in data["guards"]:
		guards.append(_spawn_guard(world, parent, player, g))

	return {
		"player": player,
		"guards": guards,
		"lights": level_lights,
		"terminal_pos": terminal_pos,
		"extraction_pos": extraction_pos,
		"config": data["config"],
	}


func _mat(col: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func _emissive(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _floor(parent: Node3D, w: float, h: float) -> void:
	var size := Vector3(w + 8.0, 0.4, h + 8.0)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(w * 0.5, -size.y * 0.5, h * 0.5)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _mat(Color(0.07, 0.09, 0.12), 0.95)
	body.add_child(mesh)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	parent.add_child(body)


func _wall(parent: Node3D, x1: float, z1: float, x2: float, z2: float) -> void:
	var a := Vector2(x1, z1)
	var b := Vector2(x2, z2)
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var mid := (a + b) * 0.5
	var size := Vector3(WALL_THICK, WALL_HEIGHT, length)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(mid.x, WALL_HEIGHT * 0.5, mid.y)
	body.rotation.y = atan2(b.x - a.x, b.y - a.y)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _mat(Color(0.15, 0.17, 0.22))
	body.add_child(mesh)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	parent.add_child(body)


func _cover(parent: Node3D, x: float, z: float) -> void:
	var sz := Vector3(1.4, 2.0, 1.4)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(x, 1.0, z)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mesh.mesh = bm
	mesh.material_override = _mat(Color(0.22, 0.2, 0.16), 0.8)
	body.add_child(mesh)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = sz
	cs.shape = box
	body.add_child(cs)
	parent.add_child(body)


func _lamp(parent: Node3D, l: Dictionary) -> Dictionary:
	var p = l["pos"]
	var pos := Vector3(p[0], LIGHT_Y, p[1])
	var col := Color(l["color"][0], l["color"][1], l["color"][2])
	var rng := float(l["range"])
	var energy := float(l["energy"])

	var light := OmniLight3D.new()
	light.position = pos
	light.omni_range = rng
	light.light_energy = energy
	light.light_color = col
	light.shadow_enabled = true
	light.omni_attenuation = 1.4
	parent.add_child(light)

	var fix := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	fix.mesh = sm
	fix.material_override = _emissive(col, 3.0)
	fix.position = pos
	parent.add_child(fix)

	return { "node": light, "pos": pos, "radius": rng, "energy": energy, "enabled": true }


func _terminal(parent: Node3D, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.2, 0.5)
	mesh.mesh = bm
	mesh.position = pos + Vector3(0, 0.6, 0)
	var m := _emissive(Color(0.2, 0.9, 1.0), 1.2)
	m.albedo_color = Color(0.1, 0.12, 0.15)
	mesh.material_override = m
	parent.add_child(mesh)


func _extraction(parent: Node3D, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.4
	tm.outer_radius = 1.8
	mesh.mesh = tm
	mesh.position = pos + Vector3(0, 0.06, 0)
	mesh.material_override = _emissive(Color(0.3, 1.0, 0.5), 2.0)
	parent.add_child(mesh)


func _pad(parent: Node3D, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.4
	cyl.bottom_radius = 1.4
	cyl.height = 0.08
	mesh.mesh = cyl
	mesh.position = pos + Vector3(0, 0.05, 0)
	mesh.material_override = _emissive(Color(0.2, 0.5, 0.9), 0.8)
	parent.add_child(mesh)


func _spawn_player(world, parent: Node3D, pos: Vector3):
	var p := CharacterBody3D.new()
	p.set_script(load("res://scripts/Player.gd"))
	p.collision_layer = 2
	p.collision_mask = 1
	p.position = pos

	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.38
	cap.height = 1.6
	body.mesh = cap
	body.material_override = _mat(Color(0.10, 0.13, 0.17), 0.7)
	p.add_child(body)

	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.5, 0.4, 0.5)
	head.mesh = hb
	head.position = Vector3(0, 0.7, 0)
	head.material_override = _mat(Color(0.08, 0.1, 0.13))
	p.add_child(head)

	for x in [-0.13, 0.0, 0.13]:
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.055
		sm.height = 0.11
		dot.mesh = sm
		dot.position = Vector3(x, 0.72, 0.26)
		dot.material_override = _emissive(Color(0.25, 1.0, 0.45), 4.0)
		p.add_child(dot)

	var beacon := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.12
	bsm.height = 0.24
	beacon.mesh = bsm
	beacon.position = Vector3(0, 1.5, 0)
	beacon.material_override = _emissive(Color(0.3, 0.8, 1.0), 3.0)
	p.add_child(beacon)

	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.38
	cs.height = 1.6
	col.shape = cs
	p.add_child(col)

	# 3D audio listener rides with the operative so guard footsteps pan/attenuate
	var listener := AudioListener3D.new()
	listener.position = Vector3(0, 1.0, 0)
	p.add_child(listener)
	listener.make_current()

	p.set("world", world)
	parent.add_child(p)
	return p


func _spawn_guard(world, parent: Node3D, player, g: Dictionary):
	var node := CharacterBody3D.new()
	node.set_script(load("res://scripts/Guard.gd"))
	node.collision_layer = 4
	node.collision_mask = 1
	var st = g["start"]
	node.position = Vector3(st[0], 0.9, st[1])
	var wps := []
	for rp in g["route"]:
		wps.append(Vector3(rp[0], 0, rp[1]))
	node.set("world", world)
	node.set("player", player)
	node.set("waypoints", wps)
	node.set("view_distance", float(g["view_distance"]))
	node.set("patrol_speed", float(g["speed"]))
	parent.add_child(node)
	return node
