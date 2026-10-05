extends RefCounted
## A castle's royal keep, raised in stone blocks rather than the village kit: a tall central great
## hall between two lower wings, corner turrets and twin front towers under slate cones and flags,
## a grand stair up to the raised hall door and battlements all round. Inside: the great hall
## (pillars, feast tables, a carpet up to the dais and the four thrones of the ruling family); in
## the wings the royal bedchamber, the solar and the library, the heirs' chambers and the
## armoury-treasury; under the hall the dungeon - barred cells, the jailer's table and torches.
## It returns a Builder.Result like any other building, so the court finds its posts.

const P := "res://assets/props/"
const FORT := "res://assets/castle/modular_fort_01/modular_fort_01.gltf"
const W := 28.0          # outside width (x)
const D := 24.0          # outside depth (z); the door faces +z, towards the castle gate
const T := 1.4           # outer wall thickness
const L1 := 4.6          # the main floor: the hall stands above the dungeon
const HALL_H := 9.5      # the great hall's height
const WING_H := 5.0      # the chambers' height
const PART := 7.5        # the walls between the hall and the wings stand at x = -PART and +PART
const HALL_TOP := 15.8   # the hall block's walls
const WING_TOP := 10.8   # the wings' walls
const TURRET_R := 3.0
const TURRET_H := 21.5
const FRONT_R := 2.4
const FRONT_H := 24.0
const DOOR_W := 3.2
const DOOR_H := 5.0
const STAIR_RUN := 8.4   # the grand stair runs this far out from the door
const DUN_Y := 0.15      # the dungeon floor
const HOLE_X0 := -7.1    # the stairwell down to the dungeon (one floor tile wide, along the left wall)
const HOLE_X1 := -5.325
const HOLE_Z0 := -7.05
const HOLE_Z1 := 0.05
const CELL_X := 3.4      # the cells' bars
const BARS_LAYER := 128  # solid to the player, but talk and looting reach through
## The chambers in each wing, front to back: [kind, from z, to z]; left wing then right wing.
const ROOMS := [
	[["bedchamber", 2.0, 10.6], ["solar", -4.6, 1.6], ["library", -10.6, -5.0]],
	[["prince", 4.0, 10.6], ["princess", -2.6, 3.6], ["armoury", -10.6, -3.0]],
]

static var _mats := {}


## Kit: blocks, cylinders, cones and balls gathered as GPU instances of unit shapes, one
## multimesh per shape and material (the stone is mapped by world position, so a stretched
## unit block keeps the stones' true size). Cheap to build and a handful of draw calls.
class Kit:
	static var _units := {}
	var groups := {}       # [shape key, material] -> [Mesh, Material, Array of Transform3D]

	static func _unit(key: String) -> Mesh:
		if _units.has(key):
			return _units[key]
		var m: Mesh
		if key == "box":
			m = BoxMesh.new()
		elif key == "ball":
			var sp := SphereMesh.new()
			sp.radius = 1.0
			sp.height = 2.0
			sp.radial_segments = 12
			sp.rings = 6
			m = sp
		else:      # "cyl:<top radius>:<bottom radius>:<height>:<segments>" (made to size: a
			# stretched tapered cylinder would skew its normals and smear the stone)
			var parts := key.split(":")
			var c := CylinderMesh.new()
			c.top_radius = float(parts[1])
			c.bottom_radius = float(parts[2])
			c.height = float(parts[3])
			c.radial_segments = int(parts[4])
			c.rings = 1
			c.cap_top = c.top_radius > 0.001
			m = c
		_units[key] = m
		return m

	func _add(key: String, xf: Transform3D, mat: Material) -> void:
		var gk := "%s|%d" % [key, mat.get_instance_id()]
		if not groups.has(gk):
			groups[gk] = [_unit(key), mat, []]
		(groups[gk][2] as Array).append(xf)

	func box(c: Vector3, size: Vector3, mat: Material, yaw := 0.0) -> void:
		_add("box", Transform3D(Basis(Vector3.UP, yaw).scaled(size), c), mat)

	func cyl(c: Vector3, r_top: float, r_bot: float, h: float, mat: Material, seg := 20) -> void:
		_add("cyl:%.3f:%.3f:%.3f:%d" % [r_top, r_bot, h, seg], Transform3D(Basis(), c), mat)

	func ball(c: Vector3, r: float, mat: Material) -> void:
		_add("ball", Transform3D(Basis().scaled(Vector3.ONE * r), c), mat)

	## The gathered shapes as multimesh nodes under one parent.
	func build(vis_end: float, shadows: bool) -> Node3D:
		var root := Node3D.new()
		for gk in groups:
			var g: Array = groups[gk]
			var xs: Array = g[2]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = g[0]
			mm.instance_count = xs.size()
			for i in xs.size():
				mm.set_instance_transform(i, xs[i])
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = g[1]
			mi.visibility_range_end = vis_end
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		return root


# ------------------------------------------------------------------ materials
static func _stone_src() -> BaseMaterial3D:
	var part := Assets.part_named(FORT, "wall_thick_straight_01")
	if part.is_empty():
		return null
	var m := (part[0] as Mesh).surface_get_material(0)
	return m as BaseMaterial3D


static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	if key in ["window", "glass"]:
		# window panes that follow the day ("glass": the hall's tall windows seen from inside,
		# daylight through leaded glass that goes dark at night; "window": the same from outside,
		# dark by day and lit by the fires and candles within at night)
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/window.gdshader")
		if key == "glass":
			sm.set_shader_parameter("base_color", Color(0.32, 0.36, 0.4))
			sm.set_shader_parameter("glow_color", Color(0.72, 0.8, 0.9))
			sm.set_shader_parameter("night_glow", 0.0)
			sm.set_shader_parameter("day_glow", 0.22)
		_mats[key] = sm
		return sm
	var m: BaseMaterial3D
	match key:
		"stone", "stone_dark", "floor_a", "floor_b", "stone_in":
			var src := _stone_src()
			m = src.duplicate() if src else StandardMaterial3D.new()
			# mapped by world position, so a block of any size keeps the stones' true scale
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_triplanar_sharpness = 8.0
			m.uv1_scale = Vector3.ONE * 0.24
			match key:
				"stone_dark":
					m.albedo_color = Color(0.66, 0.64, 0.6)
				"stone_in":
					m.albedo_color = Color(0.9, 0.86, 0.8)
				"floor_a":
					m.albedo_color = Color(0.92, 0.88, 0.8)
					m.uv1_scale = Vector3.ONE * 0.5
				"floor_b":
					m.albedo_color = Color(0.44, 0.42, 0.4)
					m.uv1_scale = Vector3.ONE * 0.5
		"slate":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.19, 0.23, 0.3)
			m.roughness = 0.55
			var nt = load("res://assets/village/T_RoundTiles_Normal.png")
			if nt:
				m.normal_enabled = true
				m.normal_texture = nt
				m.normal_scale = 0.8
				m.uv1_triplanar = true
				m.uv1_world_triplanar = true
				m.uv1_scale = Vector3.ONE * 0.6
		"wood":
			m = StandardMaterial3D.new()
			var wt = load("res://assets/village/T_WoodTrim_BaseColor.png")
			if wt:
				m.albedo_texture = wt
				m.uv1_triplanar = true
				m.uv1_world_triplanar = true
				m.uv1_scale = Vector3.ONE * 0.5
			m.albedo_color = Color(0.62, 0.48, 0.36)
			m.roughness = 0.8
		"gold":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.85, 0.64, 0.24)
			m.metallic = 0.92
			m.roughness = 0.3
		"velvet":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.4, 0.025, 0.05)
			m.roughness = 0.88
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.6
		"carpet":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.46, 0.04, 0.06)
			m.roughness = 0.96
		"iron":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.11, 0.105, 0.1)
			m.metallic = 0.85
			m.roughness = 0.5
		"slit":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.025, 0.022, 0.02)
			m.roughness = 1.0
		"straw":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.6, 0.48, 0.22)
			m.roughness = 1.0
		"rug":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.1, 0.14, 0.34)
			m.roughness = 0.96
	_mats[key] = m
	return m


static func _flag_mat(col: Color) -> ShaderMaterial:
	var key := "flag%s" % col.to_html()
	if _mats.has(key):
		return _mats[key]
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 col : source_color;
global uniform vec2 wind_dir;
global uniform float wind_strength;
void vertex() {
	// the cloth ripples away from the pole (UV.x 0 at the pole)
	float t = TIME * (2.6 + wind_strength * 2.0);
	VERTEX.z += sin(t + VERTEX.x * 3.2) * 0.16 * UV.x * (0.4 + wind_strength);
	VERTEX.y += sin(t * 0.7 + VERTEX.x * 2.1) * 0.05 * UV.x;
}
void fragment() {
	ALBEDO = col.rgb * (0.8 + 0.2 * smoothstep(0.0, 0.1, UV.y) * smoothstep(1.0, 0.9, UV.y));
	ROUGHNESS = 0.9;
}
"""
	sm.shader = sh
	sm.set_shader_parameter("col", col)
	_mats[key] = sm
	return sm


# ------------------------------------------------------------------ the keep
## b: the keep's building entry (x, z, yaw); base_y: the courtyard floor; royal: the realm's
## king holds court here (royal colours on the flags).
static func build(b: Dictionary, base_y: float, ext, settlement: String, rng: RandomNumberGenerator, inn, royal: bool) -> Builder.Result:
	var r := Builder.Result.new()
	r.data = b
	r.ext = ext
	r.inn = inn
	r.xform = Transform3D(Basis(Vector3.UP, float(b.yaw)), Vector3(float(b.x), base_y, float(b.z)))
	r.center = r.xform.origin
	r.root = Node3D.new()
	r.root.name = "royal_keep_%d" % int(b.x)
	r.root.transform = r.xform
	r.body = StaticBody3D.new()
	r.body.collision_layer = 1
	r.body.collision_mask = 0
	r.root.add_child(r.body)
	r.spots["straw"] = []
	var out := Kit.new()
	var inner := Kit.new()
	_shell(r, out)
	_towers(r, out, royal)
	_grand_stair(r, out)
	var nav := _hall(r, inner, royal)
	_chambers(r, inner, settlement, nav)
	_dungeon(r, inner, nav)
	r.root.add_child(out.build(1800.0 if Assets.compat else 3200.0, true))
	r.root.add_child(inner.build(90.0 if Assets.compat else 160.0, false))
	# indoor lights go out with distance (and so cost nothing from across the courtyard)
	for l in r.lights:
		(l as Light3D).distance_fade_enabled = true
		(l as Light3D).distance_fade_begin = 38.0
		(l as Light3D).distance_fade_length = 8.0
	return r


static func _col(r: Builder.Result, c: Vector3, size: Vector3, yaw := 0.0, layer := 1) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), c)
	if layer == 1:
		r.body.add_child(cs)
		return
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.add_child(cs)
	r.root.add_child(body)


static func _col_cyl(r: Builder.Result, c: Vector3, radius: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = radius
	cy.height = h
	cs.shape = cy
	cs.position = c
	r.body.add_child(cs)


## A walkable slope whose surface runs straight from `lo` up to `hi` ((z, y), centred on x),
## carried on a block beneath it that runs on past `lo` (under the floor it starts from), so
## there is no lip at either end.
static func _ramp(r: Builder.Result, x: float, width: float, lo: Vector2, hi: Vector2) -> void:
	var d := hi - lo
	var a := lo - d.normalized() * 0.6
	var phi := atan2(-d.y, d.x)
	var basis := Basis(Vector3.RIGHT, phi)
	var up := basis.y if basis.y.y > 0.0 else -basis.y
	var mid := Vector3(x, (a.y + hi.y) * 0.5, (a.x + hi.x) * 0.5) - up * 0.15
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(width, 0.3, (hi - a).length())
	cs.shape = bx
	cs.transform = Transform3D(basis, mid)
	r.body.add_child(cs)


## A block that is both seen and solid.
static func _solid(r: Builder.Result, k: Kit, c: Vector3, size: Vector3, m: Material) -> void:
	k.box(c, size, m)
	_col(r, c, size)


static func _light(r: Builder.Result, at: Vector3, energy: float, rng: float, col := Color(1.0, 0.72, 0.42), flicker := false) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.position = at
	if flicker:
		l.set_meta("flicker", true)
	r.root.add_child(l)
	r.lights.append(l)


static func _fire(r: Builder.Result, at: Vector3, size: float) -> void:
	var fx := FireFX.flames(0.3 * size, 0.7 * size)
	fx.position = at
	r.root.add_child(fx)
	r.fires.append(fx)


# ------------------------------------------------------------------ outside
## The walls: a tall central block for the hall between two lower wings, all on a raised floor
## (the dungeon is underneath), with battlements, string courses and windows.
static func _shell(r: Builder.Result, out: Kit) -> void:
	var stone := mat("stone")
	var dark := mat("stone_dark")
	var hw := W * 0.5
	var hd := D * 0.5
	var base := -2.0                           # walls run below ground (the courtyard is never quite level)
	# outer side walls (the wings), front and back walls (wings low, hall part tall)
	for sx in [-1.0, 1.0]:
		var h := WING_TOP - base
		_solid(r, out, Vector3(sx * (hw - T * 0.5), base + h * 0.5, 0), Vector3(T, h, D), stone)
		for sz in [-1.0, 1.0]:
			var wx := (PART + hw) * 0.5
			_solid(r, out, Vector3(sx * wx, base + h * 0.5, sz * (hd - T * 0.5)), Vector3(hw - PART, h, T), stone)
	var hh := HALL_TOP - base
	_solid(r, out, Vector3(0, base + hh * 0.5, -hd + T * 0.5), Vector3(PART * 2.0, hh, T), stone)
	# the front of the hall, around the great door
	var side := PART - DOOR_W * 0.5
	for sx in [-1.0, 1.0]:
		_solid(r, out, Vector3(sx * (DOOR_W * 0.5 + side * 0.5), base + hh * 0.5, hd - T * 0.5), Vector3(side, hh, T), stone)
	var lintel := L1 + DOOR_H
	_solid(r, out, Vector3(0, (lintel + HALL_TOP) * 0.5, hd - T * 0.5), Vector3(DOOR_W, HALL_TOP - lintel, T), stone)
	_solid(r, out, Vector3(0, (base + L1) * 0.5, hd - T * 0.5), Vector3(DOOR_W, L1 - base, T), dark)
	# the walls between hall and wings: a door into each chamber; above the wings they are the
	# hall's own walls, with its tall windows
	for sx in [-1.0, 1.0]:
		var x: float = sx * PART
		_solid(r, out, Vector3(x, (base + L1) * 0.5, 0), Vector3(0.8, L1 - base, D - 0.4), stone)
		var top0 := L1 + 3.2
		_solid(r, out, Vector3(x, (top0 + HALL_TOP) * 0.5, 0), Vector3(0.8, HALL_TOP - top0, D - 0.4), stone)
		var doors: Array = _doors(sx)
		var z0 := -hd + 0.2
		for dz in doors:
			var a: float = float(dz) - 0.8
			_solid(r, out, Vector3(x, L1 + 1.6, (z0 + a) * 0.5), Vector3(0.8, 3.2, a - z0), stone)
			z0 = float(dz) + 0.8
		_solid(r, out, Vector3(x, L1 + 1.6, (z0 + hd - 0.2) * 0.5), Vector3(0.8, 3.2, hd - 0.2 - z0), stone)
	# roofs, cornices and battlements
	for sx in [-1.0, 1.0]:
		var wx := (PART + hw) * 0.5
		out.box(Vector3(sx * wx, WING_TOP - 0.2, 0), Vector3(hw - PART + 0.1, 0.4, D + 0.1), dark)
		out.box(Vector3(sx * wx, WING_TOP - 0.75, 0), Vector3(hw - PART + 0.5, 0.45, D + 0.5), dark)
	out.box(Vector3(0, HALL_TOP - 0.2, 0), Vector3(PART * 2.0 + 0.9, 0.4, D + 0.1), dark)
	out.box(Vector3(0, HALL_TOP - 0.75, 0), Vector3(PART * 2.0 + 1.3, 0.45, D + 0.5), dark)
	# a string course round the outside at the main floor (a band, not a slab: it must not cover
	# the floors within), broken for the great door
	out.box(Vector3(0, L1 - 0.1, -hd - 0.05), Vector3(W + 0.4, 0.5, 0.3), dark)
	for sx in [-1.0, 1.0]:
		out.box(Vector3(sx * (hw + 0.05), L1 - 0.1, 0), Vector3(0.3, 0.5, D + 0.4), dark)
		var fx := (DOOR_W * 0.5 + 0.8 + hw + 0.2) * 0.5
		out.box(Vector3(sx * fx, L1 - 0.1, hd + 0.05), Vector3(hw + 0.2 - DOOR_W * 0.5 - 0.8, 0.5, 0.3), dark)
	_merlons(out, Vector2(-hw, -hd), Vector2(-PART, hd), WING_TOP)
	_merlons(out, Vector2(PART, -hd), Vector2(hw, hd), WING_TOP)
	_merlons(out, Vector2(-PART - 0.4, -hd), Vector2(PART + 0.4, hd), HALL_TOP)
	# a plinth round the foot of the walls
	for sx in [-1.0, 1.0]:
		out.box(Vector3(sx * (hw + 0.2), -1.0, 0), Vector3(0.6, 3.2, D + 1.0), dark)
	for sz in [-1.0, 1.0]:
		out.box(Vector3(0, -1.0, sz * (hd + 0.2)), Vector3(W + 1.0, 3.2, 0.6), dark)
	# windows: the hall's tall windows above the wing roofs; one to each chamber; the great window
	for sx in [-1.0, 1.0]:
		for wz in [-7.5, -2.5, 2.5, 7.5]:
			_window(out, Vector3(sx * (PART + 0.42), 12.9, wz), Vector2(1.1, 2.9), Vector3(sx, 0, 0))
		for room in ROOMS[0 if sx < 0 else 1]:
			var zc := (float(room[1]) + float(room[2])) * 0.5
			_window(out, Vector3(sx * (hw + 0.02), L1 + 2.5, zc), Vector2(1.0, 2.4), Vector3(sx, 0, 0))
		_window(out, Vector3(sx * 10.8, L1 + 2.5, hd + 0.02), Vector2(1.0, 2.4), Vector3(0, 0, 1))
	_window(out, Vector3(0, L1 + 7.4, hd + 0.02), Vector2(2.2, 3.6), Vector3(0, 0, 1))
	for wx in [-4.5, 4.5]:
		_window(out, Vector3(wx, L1 + 7.0, hd + 0.02), Vector2(0.9, 2.6), Vector3(0, 0, 1))
	# the door's surround, and the leaves standing open
	for sx in [-1.0, 1.0]:
		out.box(Vector3(sx * (DOOR_W * 0.5 + 0.4), L1 + (DOOR_H + 0.5) * 0.5, hd + 0.2), Vector3(0.8, DOOR_H + 0.5, 0.45), dark)
		out.box(Vector3(sx * (DOOR_W * 0.5 - 0.05), L1 + DOOR_H * 0.5, hd - T - 0.8), Vector3(0.12, DOOR_H - 0.1, 1.55), mat("wood"))
	out.box(Vector3(0, L1 + DOOR_H + 0.45, hd + 0.2), Vector3(DOOR_W + 1.6, 0.9, 0.45), dark)
	Furnish._put(r, P + "Banner_1_Cloth.gltf", Vector3(-2.9, L1 + 9.6, hd + 0.08), 0.0, false, 2.0)
	Furnish._put(r, P + "Banner_1_Cloth.gltf", Vector3(2.9, L1 + 9.6, hd + 0.08), 0.0, false, 2.0)


## The door in the hall/wing wall into each chamber (its centre along z).
static func _doors(sx: float) -> Array:
	var out := []
	for room in ROOMS[0 if sx < 0 else 1]:
		out.append((float(room[1]) + float(room[2])) * 0.5)
	out.sort()
	return out


static func _window(k: Kit, at: Vector3, size: Vector2, n: Vector3) -> void:
	var frame := Vector3(0.12, size.y + 0.5, size.x + 0.5) if n.x != 0.0 else Vector3(size.x + 0.5, size.y + 0.5, 0.12)
	var glass := Vector3(0.12, size.y, size.x) if n.x != 0.0 else Vector3(size.x, size.y, 0.12)
	k.box(at, frame, mat("stone_dark"))
	k.box(at + n * 0.05, glass, mat("window"))
	_leading(k, at, size, n, mat("stone_dark"), 0.13)


## A glazed window seen from inside (`n` faces into the room): the glass and its leading.
static func _glass(k: Kit, at: Vector3, size: Vector2, n: Vector3) -> void:
	k.box(at, Vector3(0.08, size.y, size.x) if n.x != 0.0 else Vector3(size.x, size.y, 0.08), mat("glass"))
	_leading(k, at, size, n, mat("iron"), 0.065)


## Bars across a window pane (centred `off` out from `at` along its normal `n`): a mullion and
## two transoms, six lights in all, so it reads as glazing rather than a flat panel.
static func _leading(k: Kit, at: Vector3, size: Vector2, n: Vector3, m: Material, off: float) -> void:
	var c := at + n * off
	var along := Vector3(0, 0, 1) if n.x != 0.0 else Vector3(1, 0, 0)
	var depth := n.abs() * 0.05
	k.box(c, along * 0.07 + Vector3(0, size.y, 0) + depth, m)
	for f in [-1.0, 1.0]:
		k.box(c + Vector3(0, size.y * f / 6.0, 0), along * size.x + Vector3(0, 0.07, 0) + depth, m)


## Merlons along the edges of the rectangle a..b (x, z) at height y.
static func _merlons(k: Kit, a: Vector2, b: Vector2, y: float) -> void:
	for edge in 4:
		var p0: Vector2
		var p1: Vector2
		match edge:
			0: p0 = Vector2(a.x, a.y); p1 = Vector2(b.x, a.y)
			1: p0 = Vector2(b.x, a.y); p1 = Vector2(b.x, b.y)
			2: p0 = Vector2(b.x, b.y); p1 = Vector2(a.x, b.y)
			3: p0 = Vector2(a.x, b.y); p1 = Vector2(a.x, a.y)
		var n := int(p0.distance_to(p1) / 1.9)
		for i in n:
			var p := p0.lerp(p1, (i + 0.5) / n)
			var along_x := absf(p1.x - p0.x) > absf(p1.y - p0.y)
			k.box(Vector3(p.x, y + 0.62, p.y), Vector3(1.05, 1.25, 0.6) if along_x else Vector3(0.6, 1.25, 1.05), mat("stone"))


## Corner turrets and the twin towers either side of the door: battlemented, under slate cones,
## each flying a flag.
static func _towers(r: Builder.Result, out: Kit, royal: bool) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	var colours := [Color(0.62, 0.05, 0.07), Color(0.86, 0.66, 0.2)] if royal else [Color(0.12, 0.2, 0.5), Color(0.62, 0.05, 0.07)]
	var k := 0
	for t in [[-hw, -hd, TURRET_R, TURRET_H], [hw, -hd, TURRET_R, TURRET_H], [-hw, hd, TURRET_R, TURRET_H], [hw, hd, TURRET_R, TURRET_H],
			[-PART, hd + 0.4, FRONT_R, FRONT_H], [PART, hd + 0.4, FRONT_R, FRONT_H]]:
		var c := Vector3(float(t[0]), 0, float(t[1]))
		_tower(r, out, c, float(t[2]), float(t[3]), colours[k % 2])
		k += 1


## A round tower: from below ground to `top`, a corbelled crown of merlons, a slate cone and a flag.
static func _tower(r: Builder.Result, out: Kit, c: Vector3, rad: float, top: float, flag: Color) -> void:
	var h := top + 2.5
	out.cyl(c + Vector3(0, top - h * 0.5, 0), rad, rad + 0.2, h, mat("stone"), 24)
	_col_cyl(r, c + Vector3(0, top * 0.5, 0), rad, top)
	out.cyl(c + Vector3(0, top - 0.55, 0), rad + 0.4, rad + 0.2, 0.6, mat("stone_dark"), 24)
	out.cyl(c + Vector3(0, L1 - 0.1, 0), rad + 0.12, rad + 0.12, 0.4, mat("stone_dark"), 24)
	var n := int(TAU * rad / 1.6)
	for i in n:
		var a := TAU * i / float(n)
		out.box(c + Vector3(sin(a) * (rad + 0.15), top + 0.55, cos(a) * (rad + 0.15)), Vector3(0.75, 1.1, 0.55), mat("stone"), a)
	var cone_h := rad * 2.7
	out.cyl(c + Vector3(0, top + 0.9 + cone_h * 0.5, 0), 0.0, rad + 0.55, cone_h, mat("slate"), 24)
	var tip := c + Vector3(0, top + 0.9 + cone_h, 0)
	out.ball(tip + Vector3(0, 0.12, 0), 0.22, mat("gold"))
	out.cyl(tip + Vector3(0, 1.3, 0), 0.05, 0.06, 2.6, mat("iron"), 6)
	r.root.add_child(flag_node(tip + Vector3(0, 2.3, 0), flag, 0.0))
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		out.box(c + Vector3(sin(a) * (rad + 0.04), top * 0.55 + (i % 2) * 3.0, cos(a) * (rad + 0.04)), Vector3(0.36, 1.4, 0.12), mat("window") if i % 2 == 0 else mat("slit"), a)


## The grand stair from the hall door down into the courtyard, with stepped parapets and braziers
## at its foot.
static func _grand_stair(r: Builder.Result, out: Kit) -> void:
	var dark := mat("stone_dark")
	var hd := D * 0.5
	var land := 1.2
	var z0 := hd + land                       # the top step
	var z1 := hd + STAIR_RUN                  # the courtyard
	var n := 15
	var tread := (z1 - z0) / n
	var rise := L1 / n
	var wid := 7.0
	out.box(Vector3(0, (L1 - 2.0) * 0.5, hd + land * 0.5), Vector3(wid + 1.0, L1 + 2.0, land), dark)
	for i in n:
		var top := (i + 1) * rise
		var za := z1 - (i + 1) * tread
		out.box(Vector3(0, (top - 1.0) * 0.5, za + tread * 0.5), Vector3(wid, top + 1.0, tread), dark if i % 2 else mat("stone"))
	# parapets stepping down beside it
	for sx in [-1.0, 1.0]:
		for i in range(0, n, 3):
			var top := (i + 3) * rise + 0.9
			var za := z1 - (i + 3) * tread
			out.box(Vector3(sx * (wid * 0.5 + 0.3), (top - 1.0) * 0.5, za + tread * 1.5), Vector3(0.6, top + 1.0, tread * 3.0), mat("stone"))
		out.box(Vector3(sx * (wid * 0.5 + 0.3), (L1 + 0.9 - 1.0) * 0.5, hd + land * 0.5), Vector3(0.6, L1 + 1.9, land), mat("stone"))
		_col(r, Vector3(sx * (wid * 0.5 + 0.3), L1 * 0.5, (hd + z1) * 0.5), Vector3(0.6, L1 + 2.0, z1 - hd))
		# pedestals with braziers at the foot
		var bp := Vector3(sx * (wid * 0.5 + 1.0), 0, z1 + 0.6)
		_solid(r, out, bp + Vector3(0, 0.6, 0), Vector3(1.1, 1.2, 1.1), dark)
		out.cyl(bp + Vector3(0, 1.42, 0), 0.55, 0.3, 0.42, mat("iron"), 14)
		_fire(r, bp + Vector3(0, 1.62, 0), 1.1)
	_col(r, Vector3(0, L1 - 0.15, hd - 0.1 + land * 0.5), Vector3(wid, 0.3, land + 0.2))
	_ramp(r, 0.0, wid, Vector2(z1, 0.0), Vector2(z0, L1))


# ------------------------------------------------------------------ the great hall
## The great hall: chequered floor, pillars, feast tables, a carpet up to the dais and its four
## thrones (the ruler, the consort and their two heirs), braziers, banners and chandeliers.
## Returns the navigation points the chambers and the dungeon hang off.
static func _hall(r: Builder.Result, inner: Kit, royal: bool) -> Dictionary:
	var hd := D * 0.5
	var xi := PART - 0.4
	var zi := hd - T
	var y := L1
	# floor: chequered stone with the stairwell down to the dungeon left open (one tile wide)
	var tile := xi * 2.0 / 8.0
	var row := 0
	var tz := -zi
	while tz < zi - 0.01:
		var tl := minf(tile, zi - tz)
		for i in 8:
			var tx := -xi + i * tile
			if i == 0 and tz >= HOLE_Z0 - 0.01 and tz + tl <= HOLE_Z1 + 0.01:
				continue
			inner.box(Vector3(tx + tile * 0.5, y - 0.05, tz + tl * 0.5), Vector3(tile, 0.1, tl), mat("floor_a") if (i + row) % 2 == 0 else mat("floor_b"))
		tz += tile
		row += 1
	_col(r, Vector3((HOLE_X1 + xi) * 0.5, y - 0.3, 0), Vector3(xi - HOLE_X1, 0.6, zi * 2.0))
	_col(r, Vector3((HOLE_X0 + HOLE_X1) * 0.5, y - 0.3, (HOLE_Z1 + zi) * 0.5), Vector3(HOLE_X1 - HOLE_X0, 0.6, zi - HOLE_Z1))
	_col(r, Vector3((HOLE_X0 + HOLE_X1) * 0.5, y - 0.3, (HOLE_Z0 - zi) * 0.5), Vector3(HOLE_X1 - HOLE_X0, 0.6, HOLE_Z0 + zi))
	# a stone balustrade round the stairwell
	_solid(r, inner, Vector3(HOLE_X1 - 0.12, y + 0.5, (HOLE_Z0 + HOLE_Z1) * 0.5 - 0.1), Vector3(0.25, 1.0, HOLE_Z1 - HOLE_Z0 + 0.2), mat("stone_dark"))
	_solid(r, inner, Vector3((HOLE_X0 + HOLE_X1) * 0.5, y + 0.5, HOLE_Z0 - 0.12), Vector3(HOLE_X1 - HOLE_X0, 1.0, 0.25), mat("stone_dark"))
	# ceiling of timber beams
	inner.box(Vector3(0, y + HALL_H + 0.3, 0), Vector3(xi * 2.0, 0.6, zi * 2.0), mat("wood"))
	var bz := -zi + 1.2
	while bz < zi - 0.5:
		inner.box(Vector3(0, y + HALL_H - 0.25, bz), Vector3(xi * 2.0, 0.5, 0.42), mat("wood"))
		bz += 2.65
	# the hall's tall windows from inside, and the great window over the door
	for sx in [-1.0, 1.0]:
		for wz in [-7.5, -2.5, 2.5, 7.5]:
			_glass(inner, Vector3(sx * (xi - 0.02), 12.9, wz), Vector2(1.1, 2.9), Vector3(-sx, 0, 0))
	_glass(inner, Vector3(0, L1 + 7.4, zi - 0.02), Vector2(2.2, 3.6), Vector3(0, 0, -1))
	for wx in [-4.5, 4.5]:
		_glass(inner, Vector3(wx, L1 + 7.0, zi - 0.02), Vector2(0.9, 2.6), Vector3(0, 0, -1))
	# pillars
	for sx in [-1.0, 1.0]:
		for pz in [-5.6, -1.1, 3.4, 7.9]:
			var c := Vector3(sx * 4.6, y, pz)
			inner.box(c + Vector3(0, 0.25, 0), Vector3(1.0, 0.5, 1.0), mat("stone_dark"))
			inner.cyl(c + Vector3(0, HALL_H * 0.5, 0), 0.4, 0.4, HALL_H - 0.8, mat("stone_in"), 16)
			inner.box(c + Vector3(0, HALL_H - 0.3, 0), Vector3(1.0, 0.5, 1.0), mat("stone_dark"))
			_col_cyl(r, c + Vector3(0, HALL_H * 0.5, 0), 0.5, HALL_H)
	# the carpet, edged in gold, from the door to the dais
	var dais_front := -zi + 3.2
	var cl := zi - dais_front
	inner.box(Vector3(0, y + 0.012, dais_front + cl * 0.5), Vector3(2.4, 0.024, cl), mat("carpet"))
	for sx in [-1.0, 1.0]:
		inner.box(Vector3(sx * 1.16, y + 0.026, dais_front + cl * 0.5), Vector3(0.1, 0.012, cl), mat("gold"))
	# the dais and the thrones of the ruling family
	_solid(r, inner, Vector3(0, y + 0.125, -zi + 1.6), Vector3(10.0, 0.25, 3.2), mat("stone_dark"))
	_solid(r, inner, Vector3(0, y + 0.375, -zi + 1.25), Vector3(9.0, 0.25, 2.5), mat("stone_dark"))
	inner.box(Vector3(0, y + 0.51, -zi + 1.25), Vector3(8.6, 0.02, 2.3), mat("carpet"))
	var top := y + 0.5
	var seats := [["throne", -1.0, 1.0], ["consort", 1.0, 0.9], ["heir_m", -3.1, 0.72], ["heir_f", 3.1, 0.72]]
	var before_dais_p := Vector3(0, y + 0.05, -zi + 4.4)
	var nav := {}
	var p_out := r.add_nav(r.xform * Vector3(0, 0.05, hd + STAIR_RUN + 1.6))
	var p_top := r.add_nav(r.xform * Vector3(0, y + 0.05, hd + 0.6))
	var p_in := r.add_nav(r.xform * Vector3(0, y + 0.05, zi - 1.0))
	r.door_out = p_out
	r.door_in = p_in
	r.link(p_out, p_top)
	r.link(p_top, p_in)
	var centre := r.add_nav(r.xform * Vector3(0, y + 0.05, 2.4))
	r.link(p_in, centre)
	var before_dais := r.add_nav(r.xform * before_dais_p)
	r.link(centre, before_dais)
	nav.centre = centre
	nav.dais = before_dais
	for s in seats:
		var sc: float = s[2]
		_throne(inner, Vector3(float(s[1]), top, -zi + 0.95), sc)
		r.spots.sit.append({"p": r.xform * Vector3(float(s[1]), top, -zi + 1.05), "yaw": float(r.data.yaw), "nav": before_dais, "tag": s[0]})
		_col(r, Vector3(float(s[1]), top + 0.6 * sc, -zi + 0.6), Vector3(1.4, 1.2, 1.1) * sc)
	# banners: the great banner behind the thrones, others between the windows
	Furnish._put(r, P + "Banner_1_Cloth.gltf", Vector3(0, y + HALL_H - 0.4, -zi + 0.03), 0.0, true, 2.8)
	for sx in [-1.0, 1.0]:
		Furnish._put(r, P + "Banner_2_Cloth.gltf", Vector3(sx * 3.6, y + HALL_H - 1.0, -zi + 0.03), 0.0, true, 2.0)
		for bz2 in [-5.0, 0.0, 5.0]:
			Furnish._put(r, P + "Banner_1_Cloth.gltf", Vector3(sx * (xi - 0.04), y + HALL_H - 1.6, bz2), -sx * PI * 0.5, true, 1.7)
	# braziers either side of the dais, candle stands, chandeliers, lights
	for sx in [-1.0, 1.0]:
		var bp := Vector3(sx * 4.2, y, -zi + 3.9)
		inner.cyl(bp + Vector3(0, 0.04, 0), 0.34, 0.38, 0.08, mat("iron"), 12)
		inner.cyl(bp + Vector3(0, 0.5, 0), 0.08, 0.1, 0.9, mat("iron"), 8)
		inner.cyl(bp + Vector3(0, 1.08, 0), 0.5, 0.26, 0.34, mat("iron"), 14)
		_fire(r, bp + Vector3(0, 1.22, 0), 1.0)
		_light(r, bp + Vector3(0, 1.8, 0), 1.8, 8.0, Color(1.0, 0.56, 0.24), true)
		_col_cyl(r, bp + Vector3(0, 0.6, 0), 0.4, 1.2)
		Furnish._put(r, P + "CandleStick_Stand.gltf", Vector3(sx * 2.0, y, -zi + 3.6), 0.0, true, 1.2)
	for cz in [-3.0, 2.2, 7.0]:
		Furnish._put(r, P + "Chandelier.gltf", Vector3(0, y + HALL_H - 0.5, cz), 0.0, true, 1.5)
	_light(r, Vector3(0, y + 3.8, -zi + 3.2), 1.5, 11.0)
	_light(r, Vector3(0, y + 6.0, 2.4), 1.7, 16.0)
	# feast tables down the nave, benches on both sides
	for sx in [-1.0, 1.0]:
		var tx: float = sx * 2.85
		for tzc in [-0.6, 4.6]:
			Furnish._put(r, P + "Table_Large.gltf", Vector3(tx, y, tzc), PI * 0.5)
			Furnish._put(r, P + "Bench.gltf", Vector3(tx + sx * 0.95, y, tzc), PI * 0.5)
			Furnish._put(r, P + "Bench.gltf", Vector3(tx - sx * 0.95, y, tzc), PI * 0.5)
			Furnish._put(r, P + "Chalice.gltf", Vector3(tx, y + 0.81, tzc - 0.7), 0.0)
			Furnish._put(r, P + "Table_Plate.gltf", Vector3(tx + 0.1, y + 0.81, tzc + 0.2), 0.0)
			Furnish._put(r, P + "Mug.gltf", Vector3(tx - 0.2, y + 0.81, tzc + 0.9), 0.0)
			_col(r, Vector3(tx, y + 0.4, tzc), Vector3(1.1, 0.8, 2.85))
			r.spots.sit.append({"p": r.xform * Vector3(tx + sx * 0.95, y, tzc - 0.5), "yaw": float(r.data.yaw) - sx * PI * 0.5,
				"nav": Furnish._nav_near(r, Vector3(tx + sx * 1.6, y, tzc - 0.5), centre), "tag": ""})
	# the court: guards at the dais, officials beside it, servants by the tables
	for gx in [-5.2, 5.2]:
		Furnish._work(r, Vector3(gx, y, -zi + 3.4), 0.0, "Sword_Idle", "throne_guard", before_dais)
	Furnish._work(r, Vector3(-3.0, y, -zi + 5.4), PI * 0.2, "Idle_Talking", "official", before_dais)
	Furnish._work(r, Vector3(3.0, y, -zi + 5.4), -PI * 0.2, "Idle_Talking", "official", before_dais)
	Furnish._work(r, Vector3(5.6, y, 2.0), -PI * 0.5, "Idle", "", centre)
	Furnish._work(r, Vector3(-5.6, y, 6.0), PI * 0.5, "Idle", "", centre)
	# the heralds at the door
	for sx in [-1.0, 1.0]:
		Furnish._work(r, Vector3(sx * 2.2, y, zi - 1.2), PI, "Sword_Idle", "door_guard", p_in)
	return nav


# ------------------------------------------------------------------ the chambers
## The wings: the royal bedchamber, the solar and the library on the left; the heirs' chambers
## and the armoury-treasury on the right. Each opens off the hall.
static func _chambers(r: Builder.Result, inner: Kit, settlement: String, nav: Dictionary) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	var y := L1
	var x0 := PART + 0.4
	var x1 := hw - T
	var ww := x1 - x0
	for sx in [-1.0, 1.0]:
		var wx: float = sx * (x0 + x1) * 0.5
		# floor, ceiling and the walls between the rooms
		_solid(r, inner, Vector3(wx, y - 0.25, 0), Vector3(ww, 0.5, (hd - T) * 2.0), mat("wood"))
		inner.box(Vector3(wx, y + WING_H + 0.2, 0), Vector3(ww, 0.4, (hd - T) * 2.0), mat("wood"))
		var rooms: Array = ROOMS[0 if sx < 0 else 1]
		for i in rooms.size() - 1:
			var za: float = float(rooms[i][1])
			var zb: float = float(rooms[i + 1][2])
			_solid(r, inner, Vector3(wx, y + WING_H * 0.5, (za + zb) * 0.5), Vector3(ww, WING_H, absf(za - zb)), mat("stone_in"))
		for room in rooms:
			var kind: String = room[0]
			var za: float = float(room[1])
			var zb: float = float(room[2])
			var zc := (za + zb) * 0.5
			# glass in the window, a rug, a light; the way in from the hall
			_glass(inner, Vector3(sx * (x1 - 0.02), y + 2.5, zc), Vector2(1.0, 2.4), Vector3(-sx, 0, 0))
			inner.box(Vector3(wx, y + 0.01, zc), Vector3(ww - 1.2, 0.02, (zb - za) - 1.4), mat("rug") if kind in ["princess", "solar"] else mat("carpet"))
			_light(r, Vector3(wx, y + 3.6, zc), 0.9, 7.0)
			var hall_side := Furnish._nav_near(r, Vector3(sx * (PART - 1.1), y, zc), nav.centre)
			var door := Furnish._nav_near(r, Vector3(sx * (PART + 1.0), y, zc), hall_side)
			var mid := Furnish._nav_near(r, Vector3(wx, y, zc), door)
			_furnish_room(r, inner, kind, sx, Vector2(x0, x1), za, zb, mid, settlement)


static func _furnish_room(r: Builder.Result, inner: Kit, kind: String, sx: float, xs: Vector2, za: float, zb: float, mid: int, settlement: String) -> void:
	var y := L1
	var wall := sx * (xs.y - 0.5)           # against the outer wall
	var inside := sx * (xs.x + 0.5)         # against the hall wall
	var zc := (za + zb) * 0.5
	var face_in := -sx * PI * 0.5           # facing the hall
	match kind:
		"bedchamber":
			# the royal bed: two beds under one canopy, its posts and red hangings
			var bz := zc + 0.9
			for k in 2:
				Furnish._bed(r, Vector3(wall - sx * 0.95, y, bz - 0.68 + k * 1.36), face_in, mid, settlement, false, 1.12)
			_canopy(inner, Vector3(wall - sx * 0.95, y, bz), Vector2(2.6, 3.0))
			Furnish._put(r, P + "Nightstand_Shelf.gltf", Vector3(wall - sx * 0.35, y, bz - 1.9), face_in)
			Furnish._put(r, P + "Nightstand_Shelf.gltf", Vector3(wall - sx * 0.35, y, bz + 1.9), face_in)
			Furnish._put(r, P + "Cabinet.gltf", Vector3(inside, y, za + 1.0), -face_in)
			Furnish._chest(r, Vector3(wall - sx * 2.6, y, bz), face_in, "keep", settlement, mid)
			_fireplace(r, inner, Vector3(wall + sx * 0.2, y, za + 1.6), sx)
			Furnish._put(r, P + "CandleStick_Stand.gltf", Vector3(inside, y, zb - 0.8), 0.0)
			Furnish._put(r, P + "Banner_2_Cloth.gltf", Vector3(sx * (xs.x + xs.y) * 0.5, y + 3.9, zb - 0.04), PI, true, 1.2)
		"solar":
			Furnish._put(r, P + "Table_Large.gltf", Vector3(sx * (xs.x + xs.y) * 0.5, y, zc), 0.0, true, 0.6)
			for k in 3:
				var cp := Vector3(sx * (xs.x + xs.y) * 0.5 + [-1.2, 1.2, 0.0][k], y, zc + [0.0, 0.0, 1.2][k])
				Furnish._put(r, P + "Chair_1.gltf", cp, [PI * 0.5, -PI * 0.5, PI][k])
				r.spots.sit.append({"p": r.xform * cp, "yaw": float(r.data.yaw) + [PI * 0.5, -PI * 0.5, PI][k], "nav": mid, "tag": "solar"})
			Furnish._put(r, P + "Bookcase_2.gltf", Vector3(inside, y, za + 0.9), -face_in)
			Furnish._put(r, P + "Vase_2.gltf", Vector3(sx * (xs.x + xs.y) * 0.5, y + 0.5, zc - 0.3), 0.0)
			_fireplace(r, inner, Vector3(wall + sx * 0.2, y, zc), sx)
		"library":
			for k in 3:
				Furnish._put(r, P + "Bookcase_2.gltf", Vector3(wall, y, za + 1.0 + k * 1.6), face_in)
			Furnish._put(r, P + "Bookcase_2.gltf", Vector3(inside, y, za + 1.0), -face_in)
			Furnish._put(r, P + "BookStand.gltf", Vector3(sx * (xs.x + xs.y) * 0.5, y, zb - 1.2), PI)
			Furnish._put(r, P + "Table_Large.gltf", Vector3(sx * (xs.x + xs.y) * 0.5, y, zc), 0.0, true, 0.6)
			Furnish._put(r, P + "Book_Stack_1.gltf", Vector3(sx * (xs.x + xs.y) * 0.5 - 0.3, y + 0.49, zc), 0.4)
			Furnish._put(r, P + "Scroll_1.gltf", Vector3(sx * (xs.x + xs.y) * 0.5 + 0.3, y + 0.49, zc + 0.2), 1.2)
			Furnish._put(r, P + "CandleStick_Triple.gltf", Vector3(sx * (xs.x + xs.y) * 0.5, y + 0.49, zc - 0.4), 0.0)
			Furnish._work(r, Vector3(sx * (xs.x + xs.y) * 0.5, y, zc + 1.0), PI, "Idle", "scholar", mid)
		"prince", "princess":
			Furnish._bed(r, Vector3(wall - sx * 0.6, y, zc + 0.6), face_in, mid, settlement, false, 1.05)
			Furnish._put(r, P + "Nightstand_Shelf.gltf", Vector3(wall - sx * 0.3, y, zc - 1.2), face_in)
			Furnish._chest(r, Vector3(inside, y, zb - 0.9), -face_in, "house", settlement, mid)
			if kind == "prince":
				Furnish._put(r, P + "WeaponStand.gltf", Vector3(inside, y, za + 1.0), -face_in)
				Furnish._put(r, P + "Shield_Wooden.gltf", Vector3(wall + sx * 0.05, y + 2.2, za + 1.4), face_in)
			else:
				Furnish._put(r, P + "Chair_1.gltf", Vector3(inside, y, za + 1.2), -face_in)
				Furnish._put(r, P + "Vase_4.gltf", Vector3(wall - sx * 0.3, y + 0.75, zc - 1.2), 0.0)
				Furnish._put(r, P + "Potion_2.gltf", Vector3(wall - sx * 0.2, y + 0.75, zc - 1.0), 0.0)
			Furnish._put(r, P + "Banner_2_Cloth.gltf", Vector3(sx * (xs.x + xs.y) * 0.5, y + 3.9, zb - 0.04), PI, true, 1.2)
		"armoury":
			for k in 3:
				Furnish._put(r, P + "WeaponStand.gltf", Vector3(wall, y, za + 1.2 + k * 1.7), face_in)
			Furnish._put(r, P + "Shield_Wooden.gltf", Vector3(inside + sx * 0.05, y + 2.0, za + 1.6), -face_in)
			Furnish._put(r, P + "Shield_Wooden.gltf", Vector3(inside + sx * 0.05, y + 2.0, za + 3.0), -face_in)
			Furnish._put(r, P + "Crate_Metal.gltf", Vector3(inside, y, zb - 1.0), 0.3)
			for k in 2:
				Furnish._chest(r, Vector3(sx * (xs.x + xs.y) * 0.5 + (k - 0.5) * 1.4, y, zb - 1.1), PI, "keep", settlement, mid)
			Furnish._put(r, P + "Coin_Pile_2.gltf", Vector3(sx * (xs.x + xs.y) * 0.5, y, zb - 2.3), 0.0)


## Four carved posts, a canopy and red hangings over the royal bed.
static func _canopy(k: Kit, c: Vector3, size: Vector2) -> void:
	var h := 2.7
	for px in [-1.0, 1.0]:
		for pz in [-1.0, 1.0]:
			k.cyl(c + Vector3(px * size.x * 0.5, h * 0.5, pz * size.y * 0.5), 0.07, 0.09, h, mat("wood"), 8)
			k.ball(c + Vector3(px * size.x * 0.5, h + 0.08, pz * size.y * 0.5), 0.11, mat("gold"))
	k.box(c + Vector3(0, h, 0), Vector3(size.x + 0.2, 0.16, size.y + 0.2), mat("velvet"))
	k.box(c + Vector3(0, h - 0.35, size.y * 0.5 + 0.05), Vector3(size.x, 0.55, 0.04), mat("velvet"))
	k.box(c + Vector3(0, h - 0.35, -size.y * 0.5 - 0.05), Vector3(size.x, 0.55, 0.04), mat("velvet"))


## A stone fireplace on the outer wall, with its fire.
static func _fireplace(r: Builder.Result, k: Kit, at: Vector3, sx: float) -> void:
	var c := at - Vector3(sx * 0.35, 0, 0)
	k.box(c + Vector3(0, 0.9, 0), Vector3(0.7, 1.8, 2.0), mat("stone_dark"))
	k.box(c + Vector3(-sx * 0.05, 0.55, 0), Vector3(0.62, 1.0, 1.2), mat("slit"))
	k.box(c + Vector3(-sx * 0.25, 1.85, 0), Vector3(0.5, 0.15, 2.2), mat("stone_dark"))
	_col(r, c + Vector3(0, 0.9, 0), Vector3(0.7, 1.8, 2.0))
	_fire(r, c + Vector3(-sx * 0.25, 0.1, 0), 0.8)
	_light(r, c + Vector3(-sx * 0.9, 0.9, 0), 1.4, 6.0, Color(1.0, 0.56, 0.24), true)


# ------------------------------------------------------------------ the dungeon
## Under the hall: a vaulted dungeon reached by the stair from the hall, with five barred cells,
## the jailer's table, straw, chains and torches.
static func _dungeon(r: Builder.Result, inner: Kit, nav: Dictionary) -> void:
	var hd := D * 0.5
	var xi := PART - 0.4
	var zi := hd - T
	var y := DUN_Y
	var top := L1 - 0.5
	# floor, ceiling (under the hall floor, with the stairwell open) and ribs of the vault
	_solid(r, inner, Vector3(0, y - 0.25, 0), Vector3(xi * 2.0, 0.5, zi * 2.0), mat("floor_b"))
	inner.box(Vector3((HOLE_X1 + xi) * 0.5, top + 0.2, 0), Vector3(xi - HOLE_X1, 0.4, zi * 2.0), mat("stone_in"))
	inner.box(Vector3((HOLE_X0 + HOLE_X1) * 0.5, top + 0.2, (HOLE_Z1 + zi) * 0.5), Vector3(HOLE_X1 - HOLE_X0, 0.4, zi - HOLE_Z1), mat("stone_in"))
	inner.box(Vector3((HOLE_X0 + HOLE_X1) * 0.5, top + 0.2, (HOLE_Z0 - zi) * 0.5), Vector3(HOLE_X1 - HOLE_X0, 0.4, HOLE_Z0 + zi), mat("stone_in"))
	for rz in [-8.0, -3.6, 0.8, 5.2, 9.6]:
		inner.box(Vector3(0, top - 0.25, rz), Vector3(xi * 2.0, 0.5, 0.5), mat("stone_dark"))
	# the stair down from the hall, and the wall along its open side
	var n := 15
	var tread := (HOLE_Z1 - HOLE_Z0) / n
	var rise := (L1 - y) / n
	for i in n:
		var st := y + (i + 1) * rise
		inner.box(Vector3((HOLE_X0 + HOLE_X1) * 0.5, (y + st) * 0.5, HOLE_Z0 + (i + 0.5) * tread), Vector3(HOLE_X1 - HOLE_X0, st - y, tread), mat("stone_dark") if i % 2 else mat("stone"))
	_ramp(r, (HOLE_X0 + HOLE_X1) * 0.5, HOLE_X1 - HOLE_X0, Vector2(HOLE_Z0, y), Vector2(HOLE_Z1, L1))
	_solid(r, inner, Vector3(HOLE_X1 + 0.12, (y + top) * 0.5, (HOLE_Z0 + 2.2 + HOLE_Z1) * 0.5), Vector3(0.25, top - y, HOLE_Z1 - HOLE_Z0 - 2.2), mat("stone_in"))
	# five cells along the far wall, behind iron bars
	var cells := [[-10.6, -6.6], [-6.2, -2.2], [-1.8, 2.2], [2.6, 6.6], [7.0, zi]]
	for wz in [-6.4, -2.0, 2.4, 6.8]:
		_solid(r, inner, Vector3((CELL_X + xi) * 0.5, (y + top) * 0.5, wz), Vector3(xi - CELL_X, top - y, 0.4), mat("stone_in"))
	var spine := []
	for c in cells:
		var za: float = c[0]
		var zb: float = c[1]
		var zc := (za + zb) * 0.5
		var bars := int((zb - za) / 0.24)
		for i in bars:
			inner.cyl(Vector3(CELL_X, y + 1.6, za + (i + 0.5) * (zb - za) / bars), 0.028, 0.028, 3.2, mat("iron"), 6)
		for ry in [y + 0.12, y + 3.1]:
			inner.box(Vector3(CELL_X, ry, zc), Vector3(0.08, 0.08, zb - za), mat("iron"))
		_col(r, Vector3(CELL_X, y + 1.8, zc), Vector3(0.14, 3.6, zb - za), 0.0, BARS_LAYER)
		inner.box(Vector3((CELL_X + xi) * 0.5 + 0.4, y + 0.04, zc), Vector3(2.0, 0.08, 1.8), mat("straw"))
		Furnish._put(r, P + "Bucket_Wooden_1.gltf", Vector3(xi - 0.4, y, za + 0.5), 0.0)
		Furnish._put(r, P + "Chain_Coil.gltf", Vector3(xi - 0.15, y + 1.6, zc + 0.6), PI * 0.5)
		var sp := r.add_nav(r.xform * Vector3(1.4, y + 0.05, zc))
		if not spine.is_empty():
			r.link(sp, spine[-1])
		spine.append(sp)
		var cell := r.add_nav(r.xform * Vector3(5.4, y + 0.05, zc))
		r.link(cell, sp)
		# the prisoner: at the bars by day, asleep on the straw at night
		var straw := {"p": r.xform * Vector3((CELL_X + xi) * 0.5 + 0.4, y + 0.1, zc), "yaw": float(r.data.yaw), "nav": cell}
		r.spots.straw.append(straw)
		r.spots.work.append({"p": r.xform * Vector3(CELL_X + 0.55, y, zc), "yaw": float(r.data.yaw) - PI * 0.5, "anim": "Idle", "tag": "prisoner", "nav": cell, "straw": straw})
	# the way down: hall -> top of the stair -> foot of the stair -> the dungeon
	var above := Furnish._nav_near(r, Vector3((HOLE_X0 + HOLE_X1) * 0.5, L1, HOLE_Z1 + 0.9), nav.centre)
	var s_top := r.add_nav(r.xform * Vector3((HOLE_X0 + HOLE_X1) * 0.5, L1 + 0.05, HOLE_Z1 - 0.2))
	var s_foot := r.add_nav(r.xform * Vector3((HOLE_X0 + HOLE_X1) * 0.5, y + 0.05, HOLE_Z0 + 0.2))
	var below := r.add_nav(r.xform * Vector3(-3.6, y + 0.05, HOLE_Z0 - 0.8))
	r.link(above, s_top)
	r.link(s_top, s_foot)
	r.link(s_foot, below)
	r.link(below, spine[0])
	# the jailer's table at the foot of the stair, and torches
	Furnish._put(r, P + "Table_Large.gltf", Vector3(-2.6, y, -9.0), 0.0, true, 0.55)
	Furnish._put(r, P + "Key_Metal.gltf", Vector3(-2.3, y + 0.45, -9.0), 0.6)
	Furnish._put(r, P + "Mug.gltf", Vector3(-2.9, y + 0.45, -8.9), 0.0)
	Furnish._put(r, P + "Chair_1.gltf", Vector3(-2.6, y, -7.9), PI)
	r.spots.sit.append({"p": r.xform * Vector3(-2.6, y, -7.9), "yaw": float(r.data.yaw) + PI, "nav": below, "tag": "jailer"})
	for tp in [Vector3(0.0, y + 2.4, -zi + 0.25), Vector3(-xi + 0.25, y + 2.4, 5.0), Vector3(0.0, y + 2.4, zi - 0.25)]:
		var yaw := 0.0 if tp.z < -5.0 else (PI if tp.z > 5.0 else PI * 0.5)
		Furnish._put(r, P + "Torch_Metal.gltf", tp, yaw, true, 1.2)
		_fire(r, tp + Vector3(0, 0.75, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.12), 0.5)
	_light(r, Vector3(-1.5, y + 2.8, -6.0), 1.4, 9.0, Color(1.0, 0.6, 0.3), true)
	_light(r, Vector3(-1.5, y + 2.8, 4.5), 1.4, 9.0, Color(1.0, 0.6, 0.3), true)


## A flag flying from a pole's top at `at` (its hoist on the pole), turned to `yaw`.
static func flag_node(at: Vector3, col: Color, yaw: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(1.9, 1.15)
	q.subdivide_width = 8
	q.subdivide_depth = 2
	q.center_offset = Vector3(0.95, -0.575, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _flag_mat(col)
	mi.transform = Transform3D(Basis(Vector3.UP, yaw + 0.6), at)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 900.0
	return mi


## A gilded throne with a high, crested back and red velvet (facing +z). `s` sizes its width and
## back; the seat is always a chair's height, where the sitting pose puts a body.
static func _throne(k: Kit, at: Vector3, s: float) -> void:
	const SEAT := 0.5
	var gold := mat("gold")
	var velvet := mat("velvet")
	k.box(at + Vector3(0, (SEAT - 0.07) * 0.5, 0), Vector3(1.36 * s, SEAT - 0.07, 1.05 * s), gold)
	k.box(at + Vector3(0, SEAT - 0.05, 0.04 * s), Vector3(1.16 * s, 0.1, 0.95 * s), velvet)
	k.box(at + Vector3(0, 1.45, -0.45) * s, Vector3(1.4, 2.5, 0.16) * s, gold)
	k.box(at + Vector3(0, 1.45, -0.36) * s, Vector3(1.04, 1.9, 0.06) * s, velvet)
	k.box(at + Vector3(0, 2.86, -0.45) * s, Vector3(0.62, 0.62, 0.16) * s, gold, 0.0)
	k.ball(at + Vector3(0, 3.28, -0.45) * s, 0.15 * s, gold)
	for sx in [-1.0, 1.0]:
		k.box(at + Vector3(sx * 0.62 * s, SEAT + 0.24, 0.02 * s), Vector3(0.16 * s, 0.12, 1.0 * s), gold)
		k.box(at + Vector3(sx * 0.62 * s, SEAT + 0.04, 0.42 * s), Vector3(0.12 * s, 0.36, 0.12 * s), gold)
		k.ball(at + Vector3(sx * 0.62 * s, SEAT + 0.34, 0.5 * s), 0.09 * s, gold)
		k.ball(at + Vector3(sx * 0.7, 2.72, -0.45) * s, 0.12 * s, gold)
