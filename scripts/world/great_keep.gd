extends RefCounted
## A castle's great keep, raised in stone blocks rather than the village kit: a tall square tower
## with corner turrets under slate cones and flags, a crenellated roof and arrow slits; inside, a
## high great hall - stone pillars, a carpet up to a stepped dais, a gilded throne, braziers and
## banners, feast tables - with the lord's bedchamber and the stewards' room behind. It returns a
## Builder.Result like any other building, so the townsfolk find their posts (the throne, its
## guards, the officials, the beds) as before.

const P := "res://assets/props/"
const FORT := "res://assets/castle/modular_fort_01/modular_fort_01.gltf"
const W := 16.0          # outside width (x)
const D := 24.0          # outside depth (z); the door faces +z, towards the castle gate
const T := 1.4           # wall thickness
const STEP := 0.6        # the hall floor stands this far above the courtyard
const HALL_H := 8.0      # the great hall's height
const BODY_H := 17.0     # the walls' height
const TURRET_R := 2.6
const TURRET_H := 22.0
const DOOR_W := 3.6
const DOOR_H := 5.2
const HALL_BACK := -6.2  # the hall's back wall (the dais stands against it); chambers lie behind

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
		"glass":
			# the hall's tall windows from inside: daylight through leaded glass
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.32, 0.36, 0.4)
			m.emission_enabled = true
			m.emission = Color(0.72, 0.8, 0.9)
			m.emission_energy_multiplier = 0.22
			m.roughness = 0.4
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
## king holds court here (a second throne for the queen, the royal colours on the flags).
static func build(b: Dictionary, base_y: float, ext, settlement: String, rng: RandomNumberGenerator, inn, royal: bool) -> Builder.Result:
	var r := Builder.Result.new()
	r.data = b
	r.ext = ext
	r.inn = inn
	r.xform = Transform3D(Basis(Vector3.UP, float(b.yaw)), Vector3(float(b.x), base_y, float(b.z)))
	r.center = r.xform.origin
	r.root = Node3D.new()
	r.root.name = "great_keep_%d" % int(b.x)
	r.root.transform = r.xform
	r.body = StaticBody3D.new()
	r.body.collision_layer = 1
	r.body.collision_mask = 0
	r.root.add_child(r.body)
	var out := Kit.new()
	var inner := Kit.new()
	_shell(r, out, inner)
	_turrets(r, out, royal)
	_hall(r, inner, settlement, royal)
	_entrance(r, out)
	# the stone, inside and out (shadows from the outside only)
	r.root.add_child(out.build(1800.0 if Assets.compat else 3200.0, true))
	r.root.add_child(inner.build(90.0 if Assets.compat else 160.0, false))
	return r


static func _col(r: Builder.Result, c: Vector3, size: Vector3, yaw := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), c)
	r.body.add_child(cs)


static func _col_cyl(r: Builder.Result, c: Vector3, radius: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = radius
	cy.height = h
	cs.shape = cy
	cs.position = c
	r.body.add_child(cs)


## Outer walls (with the great door), the plinth, roof, parapet, string courses and windows; the
## inner wall that closes the hall off from the chambers.
static func _shell(r: Builder.Result, out: Kit, inner: Kit) -> void:
	var stone := mat("stone")
	var dark := mat("stone_dark")
	var hw := W * 0.5
	var hd := D * 0.5
	# plinth: hides the slope of the courtyard under the keep
	out.box(Vector3(0, STEP - 1.6, 0), Vector3(W + 0.8, 3.2, D + 0.8), dark)
	# outer walls (the faces inside the hall are the same blocks)
	var wall_c := BODY_H * 0.5
	out.box(Vector3(0, wall_c, -hd + T * 0.5), Vector3(W, BODY_H, T), stone)
	out.box(Vector3(-hw + T * 0.5, wall_c, 0), Vector3(T, BODY_H, D - 2.0 * T), stone)
	out.box(Vector3(hw - T * 0.5, wall_c, 0), Vector3(T, BODY_H, D - 2.0 * T), stone)
	var side_w := hw - DOOR_W * 0.5
	for s in [-1.0, 1.0]:
		out.box(Vector3(s * (DOOR_W * 0.5 + side_w * 0.5), wall_c, hd - T * 0.5), Vector3(side_w, BODY_H, T), stone)
	var lintel_y := STEP + DOOR_H
	out.box(Vector3(0, (lintel_y + BODY_H) * 0.5, hd - T * 0.5), Vector3(DOOR_W, BODY_H - lintel_y, T), stone)
	_col(r, Vector3(0, wall_c, -hd + T * 0.5), Vector3(W, BODY_H, T))
	_col(r, Vector3(-hw + T * 0.5, wall_c, 0), Vector3(T, BODY_H, D))
	_col(r, Vector3(hw - T * 0.5, wall_c, 0), Vector3(T, BODY_H, D))
	for s in [-1.0, 1.0]:
		_col(r, Vector3(s * (DOOR_W * 0.5 + side_w * 0.5), wall_c, hd - T * 0.5), Vector3(side_w, BODY_H, T))
	_col(r, Vector3(0, (lintel_y + BODY_H) * 0.5, hd - T * 0.5), Vector3(DOOR_W, BODY_H - lintel_y, T))
	# the floor everyone walks on, and the hall's ceiling of beams
	_col(r, Vector3(0, STEP - 0.4, 0), Vector3(W, 0.8, D))
	var iw := W - 2.0 * T
	var id := D - 2.0 * T
	inner.box(Vector3(0, STEP + HALL_H + 0.3, 0), Vector3(iw, 0.6, id), mat("wood"))
	var z := -hd + T + 1.0
	while z < hd - T - 0.5:
		inner.box(Vector3(0, STEP + HALL_H - 0.25, z), Vector3(iw, 0.5, 0.42), mat("wood"))
		z += 2.6
	# roof, the projecting course under the parapet, and the battlements
	out.box(Vector3(0, BODY_H + 0.15, 0), Vector3(W + 0.1, 0.3, D + 0.1), dark)
	out.box(Vector3(0, BODY_H - 0.45, 0), Vector3(W + 0.5, 0.5, D + 0.5), dark)
	out.box(Vector3(0, STEP + HALL_H + 1.2, 0), Vector3(W + 0.3, 0.35, D + 0.3), dark)
	for side in 4:
		var along := W if side < 2 else D
		var n := int(along / 1.9)
		for i in n:
			var t := -along * 0.5 + (i + 0.5) * along / n
			var p: Vector3
			var size := Vector3(1.05, 1.25, 0.7)
			match side:
				0: p = Vector3(t, 0, hd + 0.05)
				1: p = Vector3(t, 0, -hd - 0.05)
				2: p = Vector3(-hw - 0.05, 0, t)
				3: p = Vector3(hw + 0.05, 0, t)
			if side >= 2:
				size = Vector3(0.7, 1.25, 1.05)
			p.y = BODY_H + 0.3 + 0.625
			out.box(p, size, stone)
	# windows: tall leaded windows high in the hall's long walls; arrow slits above
	for s in [-1.0, 1.0]:
		var wz := -3.5
		while wz < hd - T - 1.5:
			var wy := STEP + 5.0
			out.box(Vector3(s * (hw + 0.03), wy, wz), Vector3(0.12, 3.0, 1.1), dark)
			out.box(Vector3(s * (hw + 0.07), wy, wz), Vector3(0.1, 2.6, 0.7), mat("slit"))
			inner.box(Vector3(s * (hw - T - 0.03), wy, wz), Vector3(0.08, 2.6, 0.75), mat("glass"))
			wz += 4.2
	for side in 4:
		var along := W if side < 2 else D
		for i in (3 if side < 2 else 4):
			var t := -along * 0.5 + (i + 0.5) * along / (3 if side < 2 else 4)
			for row in 2:
				var y := 11.5 + row * 3.2
				var size := Vector3(0.38, 1.5, 0.1)
				var p: Vector3
				match side:
					0: p = Vector3(t, y, hd + 0.04)
					1: p = Vector3(t, y, -hd - 0.04)
					2: p = Vector3(-hw - 0.04, y, t)
					3: p = Vector3(hw + 0.04, y, t)
				if side >= 2:
					size = Vector3(0.1, 1.5, 0.38)
				if side == 0 and absf(t) < 3.0:
					continue      # (the banner hangs over the door)
				out.box(p, size, mat("slit"))
	# the inner wall between hall and chambers, with a door at each end, and the wall between
	# the two chambers
	var wall_z := HALL_BACK - 0.4
	var doors := [-4.6, 4.6]
	var segs := [[-iw * 0.5, doors[0] - 0.75], [doors[0] + 0.75, doors[1] - 0.75], [doors[1] + 0.75, iw * 0.5]]
	for sg in segs:
		var x0: float = sg[0]
		var x1: float = sg[1]
		inner.box(Vector3((x0 + x1) * 0.5, STEP + HALL_H * 0.5, wall_z), Vector3(x1 - x0, HALL_H, 0.8), mat("stone_in"))
		_col(r, Vector3((x0 + x1) * 0.5, STEP + HALL_H * 0.5, wall_z), Vector3(x1 - x0, HALL_H, 0.8))
	for dx in doors:
		inner.box(Vector3(dx, STEP + 2.8 + (HALL_H - 2.8) * 0.5, wall_z), Vector3(1.5, HALL_H - 2.8, 0.8), mat("stone_in"))
		_col(r, Vector3(dx, STEP + 2.8 + (HALL_H - 2.8) * 0.5, wall_z), Vector3(1.5, HALL_H - 2.8, 0.8))
	var ch_d := (wall_z - 0.4) - (-hd + T)
	inner.box(Vector3(0, STEP + HALL_H * 0.5, -hd + T + ch_d * 0.5), Vector3(0.6, HALL_H, ch_d), mat("stone_in"))
	_col(r, Vector3(0, STEP + HALL_H * 0.5, -hd + T + ch_d * 0.5), Vector3(0.6, HALL_H, ch_d))
	# floors: the hall in a chequer of pale and dark stone, the chambers in timber
	var tile := iw / 8.0
	var tz := HALL_BACK
	var row := 0
	while tz < hd - T - 0.01:
		var tl := minf(tile, hd - T - tz)
		for i in 8:
			var m := mat("floor_a") if (i + row) % 2 == 0 else mat("floor_b")
			inner.box(Vector3(-iw * 0.5 + (i + 0.5) * tile, STEP - 0.05, tz + tl * 0.5), Vector3(tile, 0.1, tl), m)
		tz += tile
		row += 1
	inner.box(Vector3(0, STEP - 0.05, (-hd + T + wall_z - 0.4) * 0.5), Vector3(iw, 0.1, ch_d), mat("wood"))


## Corner turrets: round towers that rise above the roof, ringed with battlements and capped
## with slate cones, each flying a flag.
static func _turrets(r: Builder.Result, out: Kit, royal: bool) -> void:
	var stone := mat("stone")
	var dark := mat("stone_dark")
	var colours := [Color(0.62, 0.05, 0.07), Color(0.86, 0.66, 0.2)] if royal else [Color(0.12, 0.2, 0.5), Color(0.62, 0.05, 0.07)]
	var k := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * W * 0.5, 0, sz * D * 0.5)
			var h := TURRET_H + 2.5
			out.cyl(c + Vector3(0, TURRET_H - h * 0.5, 0), TURRET_R, TURRET_R + 0.25, h, stone, 24)
			_col_cyl(r, c + Vector3(0, TURRET_H * 0.5, 0), TURRET_R, TURRET_H)
			out.cyl(c + Vector3(0, TURRET_H - 0.55, 0), TURRET_R + 0.4, TURRET_R + 0.2, 0.6, dark, 24)
			out.cyl(c + Vector3(0, STEP + HALL_H + 1.2, 0), TURRET_R + 0.12, TURRET_R + 0.12, 0.35, dark, 24)
			for i in 10:
				var a := TAU * i / 10.0
				var mp := c + Vector3(sin(a) * (TURRET_R + 0.15), TURRET_H + 0.55, cos(a) * (TURRET_R + 0.15))
				out.box(mp, Vector3(0.75, 1.1, 0.55), stone, a)
			# the cone, a gilded knop and the flag
			var cone_h := 7.5
			out.cyl(c + Vector3(0, TURRET_H + 0.9 + cone_h * 0.5, 0), 0.0, TURRET_R + 0.55, cone_h, mat("slate"), 24)
			var top := c + Vector3(0, TURRET_H + 0.9 + cone_h, 0)
			out.ball(top + Vector3(0, 0.12, 0), 0.22, mat("gold"))
			out.cyl(top + Vector3(0, 1.3, 0), 0.05, 0.06, 2.6, mat("iron"), 6)
			_flag(r, top + Vector3(0, 2.3, 0), colours[k % 2])
			# arrow slits round the turret
			for i in 4:
				var a := TAU * (i + 0.5) / 4.0 + (0.0 if sz > 0 else PI * 0.25)
				var sp := c + Vector3(sin(a) * (TURRET_R + 0.04), 13.0 + (i % 2) * 3.5, cos(a) * (TURRET_R + 0.04))
				out.box(sp, Vector3(0.36, 1.4, 0.12), mat("slit"), a)
			k += 1


static func _flag(r: Builder.Result, at: Vector3, col: Color) -> void:
	var f := flag_node(at, col, 0.0)
	r.root.add_child(f)


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


## The great door's surround, a landing and steps, torches at either side and the lord's banner.
static func _entrance(r: Builder.Result, out: Kit) -> void:
	var dark := mat("stone_dark")
	var hd := D * 0.5
	for s in [-1.0, 1.0]:
		out.box(Vector3(s * (DOOR_W * 0.5 + 0.45), STEP + (DOOR_H + 0.6) * 0.5, hd + 0.25), Vector3(0.9, DOOR_H + 0.6, 0.5), dark)
	out.box(Vector3(0, STEP + DOOR_H + 0.45, hd + 0.25), Vector3(DOOR_W + 1.8, 0.9, 0.5), dark)
	# landing and two steps down to the courtyard (an even ramp underfoot)
	out.box(Vector3(0, STEP - 0.6, hd + 0.9), Vector3(DOOR_W + 3.0, 1.2, 1.8), dark)
	out.box(Vector3(0, STEP - 0.2 - 0.6, hd + 2.1), Vector3(DOOR_W + 3.4, 1.2, 0.7), dark)
	out.box(Vector3(0, STEP - 0.4 - 0.6, hd + 2.8), Vector3(DOOR_W + 3.8, 1.2, 0.7), dark)
	var run := 1.4
	var ang := atan2(STEP, run)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(DOOR_W + 3.0, 0.3, sqrt(run * run + STEP * STEP) + 0.3)
	cs.shape = bx
	cs.transform = Transform3D(Basis(Vector3.RIGHT, ang), Vector3(0, STEP * 0.5 - 0.15, hd + 1.8 + run * 0.5))
	r.body.add_child(cs)
	_col(r, Vector3(0, STEP - 0.15, hd + 0.9), Vector3(DOOR_W + 3.0, 0.3, 1.8))
	# torches flanking the door; the banner above it
	for s in [-1.0, 1.0]:
		var tp := Vector3(s * (DOOR_W * 0.5 + 1.25), STEP + 2.9, hd + 0.35)
		Furnish._put(r, P + "Torch_Metal.gltf", tp, PI, false, 1.4)
		var fl := FireFX.flames(0.14, 0.55)
		fl.position = tp + Vector3(0, 0.85, 0.12)
		r.root.add_child(fl)
		r.fires.append(fl)
	Furnish._put(r, P + "Banner_1_Cloth.gltf", Vector3(0, STEP + DOOR_H + 6.6, hd + 0.08), 0.0, false, 2.4)
	for s in [-1.0, 1.0]:
		Furnish._put(r, P + "Banner_2_Cloth.gltf", Vector3(s * 5.0, STEP + DOOR_H + 5.2, hd + 0.08), 0.0, false, 1.9)


## The great hall: pillars, carpet, dais and throne(s), braziers, banners, feast tables and
## chandeliers; the lord's bedchamber and the stewards' room behind. Townsfolk posts as the old
## keep: "throne" (sit), "throne_guard" and "official" (work), servants, beds and the treasury.
static func _hall(r: Builder.Result, inner: Kit, settlement: String, royal: bool) -> void:
	var hd := D * 0.5
	var iw := W - 2.0 * T
	var front := hd - T
	var y := STEP
	# navigation through the hall
	var p_out := r.add_nav(r.xform * Vector3(0, 0.05, hd + 4.0))
	var p_in := r.add_nav(r.xform * Vector3(0, y + 0.05, front - 1.2))
	r.door_out = p_out
	r.door_in = p_in
	r.link(p_out, p_in)
	var centre := r.add_nav(r.xform * Vector3(0, y + 0.05, 2.5))
	r.link(p_in, centre)
	var before_dais := r.add_nav(r.xform * Vector3(0, y + 0.05, HALL_BACK + 4.0))
	r.link(centre, before_dais)
	# pillars down both sides of the hall
	for sx in [-1.0, 1.0]:
		for pz in [-1.4, 2.8, 7.0]:
			var c := Vector3(sx * 3.4, y, pz)
			inner.box(c + Vector3(0, 0.25, 0), Vector3(1.0, 0.5, 1.0), mat("stone_dark"))
			inner.cyl(c + Vector3(0, HALL_H * 0.5, 0), 0.36, 0.4, HALL_H - 0.8, mat("stone_in"), 16)
			inner.box(c + Vector3(0, HALL_H - 0.3, 0), Vector3(1.0, 0.5, 1.0), mat("stone_dark"))
			_col_cyl(r, c + Vector3(0, HALL_H * 0.5, 0), 0.5, HALL_H)
	# the carpet, edged in gold, from the door to the dais
	var dais_front := HALL_BACK + 2.9
	var cl := front - dais_front
	inner.box(Vector3(0, y + 0.012, dais_front + cl * 0.5), Vector3(2.4, 0.024, cl), mat("carpet"))
	for s in [-1.0, 1.0]:
		inner.box(Vector3(s * 1.16, y + 0.026, dais_front + cl * 0.5), Vector3(0.1, 0.012, cl), mat("gold"))
	# the dais: two broad steps
	inner.box(Vector3(0, y + 0.125, HALL_BACK + 1.45), Vector3(9.0, 0.25, 2.9), mat("stone_dark"))
	inner.box(Vector3(0, y + 0.375, HALL_BACK + 1.05), Vector3(7.4, 0.25, 2.1), mat("stone_dark"))
	inner.box(Vector3(0, y + 0.51, HALL_BACK + 1.05), Vector3(4.4, 0.02, 2.1), mat("carpet"))
	inner.box(Vector3(0, y + 0.26, HALL_BACK + 2.6), Vector3(2.4, 0.02, 0.6), mat("carpet"))
	_col(r, Vector3(0, y + 0.125, HALL_BACK + 1.45), Vector3(9.0, 0.25, 2.9))
	_col(r, Vector3(0, y + 0.375, HALL_BACK + 1.05), Vector3(7.4, 0.25, 2.1))
	var top := y + 0.5
	_throne(inner, Vector3(0, top, HALL_BACK + 0.9), 1.0)
	r.spots.sit.append({"p": r.xform * Vector3(0, top, HALL_BACK + 1.0), "yaw": float(r.data.yaw), "nav": before_dais, "tag": "throne"})
	if royal:
		# the queen's seat at the king's left hand
		_throne(inner, Vector3(2.1, top, HALL_BACK + 1.0), 0.82)
		r.spots.sit.append({"p": r.xform * Vector3(2.1, top, HALL_BACK + 1.1), "yaw": float(r.data.yaw), "nav": before_dais, "tag": "consort"})
	_col(r, Vector3(0, top + 0.6, HALL_BACK + 0.6), Vector3(1.5, 1.2, 1.2))
	# banners behind the throne and along the walls
	Furnish._put(r, P + "Banner_1_Cloth.gltf", Vector3(0, y + HALL_H - 0.4, HALL_BACK - 0.02), 0.0, true, 2.6)
	for s in [-1.0, 1.0]:
		Furnish._put(r, P + "Banner_2_Cloth.gltf", Vector3(s * 3.9, y + HALL_H - 0.9, HALL_BACK - 0.02), 0.0, true, 1.9)
		for bz in [-0.6, 3.6]:
			Furnish._put(r, P + "Banner_1_Cloth.gltf", Vector3(s * (iw * 0.5 - 0.05), y + HALL_H - 1.2, bz + 2.1), -s * PI * 0.5, true, 1.6)
	# braziers either side of the dais, candle stands, chandeliers
	for s in [-1.0, 1.0]:
		var bp := Vector3(s * 3.0, y, HALL_BACK + 3.6)
		inner.cyl(bp + Vector3(0, 0.04, 0), 0.34, 0.38, 0.08, mat("iron"), 12)
		inner.cyl(bp + Vector3(0, 0.5, 0), 0.08, 0.1, 0.9, mat("iron"), 8)
		inner.cyl(bp + Vector3(0, 1.08, 0), 0.5, 0.26, 0.34, mat("iron"), 14)
		var fx := FireFX.flames(0.32, 0.75)
		fx.position = bp + Vector3(0, 1.22, 0)
		r.root.add_child(fx)
		r.fires.append(fx)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.56, 0.24)
		l.light_energy = 1.8
		l.omni_range = 8.0
		l.position = bp + Vector3(0, 1.8, 0)
		l.set_meta("flicker", true)
		r.root.add_child(l)
		r.lights.append(l)
		_col_cyl(r, bp + Vector3(0, 0.6, 0), 0.4, 1.2)
		Furnish._put(r, P + "CandleStick_Stand.gltf", Vector3(s * 1.9, y, HALL_BACK + 2.4), 0.0, true, 1.2)
	for cz in [1.0, 6.5]:
		Furnish._put(r, P + "Chandelier.gltf", Vector3(0, y + HALL_H - 0.5, cz), 0.0, true, 1.5)
	Furnish._light(r, Vector3(0, y + 3.6, HALL_BACK + 3.0), 1.5, 11.0, not Assets.compat)
	Furnish._light(r, Vector3(0, y + 5.8, 4.0), 1.6, 15.0, false)
	# feast tables in the side aisles
	for s in [-1.0, 1.0]:
		var tx: float = s * 5.25
		for tzc in [2.2, 5.3]:
			Furnish._put(r, P + "Table_Large.gltf", Vector3(tx, y, tzc), PI * 0.5)
			Furnish._put(r, P + "Bench.gltf", Vector3(tx - s * 0.95, y, tzc), PI * 0.5)
			Furnish._put(r, P + "Chalice.gltf", Vector3(tx, y + 0.81, tzc - 0.6), 0.0)
			Furnish._put(r, P + "Table_Plate.gltf", Vector3(tx + 0.1, y + 0.81, tzc + 0.3), 0.0)
			Furnish._put(r, P + "Mug.gltf", Vector3(tx - 0.2, y + 0.81, tzc + 0.9), 0.0)
			_col(r, Vector3(tx, y + 0.4, tzc), Vector3(1.1, 0.8, 2.85))
			r.spots.sit.append({"p": r.xform * Vector3(tx - s * 0.95, y, tzc - 0.5), "yaw": float(r.data.yaw) + s * PI * 0.5, "nav": Furnish._nav_near(r, Vector3(tx - s * 1.6, y, tzc - 0.5), centre), "tag": ""})
	# the court: guards at the dais, officials beside it, servants by the tables
	for gx in ([-3.3, 4.0] if royal else [-1.9, 1.9]):
		Furnish._work(r, Vector3(gx, y, HALL_BACK + 3.4), 0.0, "Sword_Idle", "throne_guard", before_dais)
	Furnish._work(r, Vector3(-2.6, y, HALL_BACK + 5.6), PI * 0.2, "Idle_Talking", "official", before_dais)
	Furnish._work(r, Vector3(2.6, y, HALL_BACK + 5.6), -PI * 0.2, "Idle_Talking", "official", before_dais)
	Furnish._work(r, Vector3(4.4, y, 0.6), -PI * 0.5, "Idle", "", centre)
	Furnish._work(r, Vector3(-4.4, y, 0.6), PI * 0.5, "Idle", "", centre)
	# behind the hall: the lord's bedchamber (left) and the stewards' room (right)
	var wall_z := HALL_BACK - 0.4
	var ch_z := (-hd + T + wall_z - 0.4) * 0.5
	for sx in [-1.0, 1.0]:
		var hall_side := Furnish._nav_near(r, Vector3(sx * 4.6, y, HALL_BACK + 1.2), centre)
		var room_side := Furnish._nav_near(r, Vector3(sx * 4.6, y, wall_z - 1.0), hall_side)
		var room := Furnish._nav_near(r, Vector3(sx * 3.2, y, ch_z), room_side)
		if sx < 0:
			Furnish._bed(r, Vector3(-2.6, y, ch_z - 0.2), PI * 0.5, room, settlement, false, 1.3)
			Furnish._put(r, P + "Nightstand_Shelf.gltf", Vector3(-1.0, y, -hd + T + 0.4), 0.0)
			Furnish._put(r, P + "Bookcase_2.gltf", Vector3(-iw * 0.5 + 0.4, y, ch_z), PI * 0.5)
			Furnish._chest(r, Vector3(-5.6, y, -hd + T + 0.6), 0.0, "keep", settlement, room)
			Furnish._put(r, P + "Banner_2.gltf", Vector3(-3.4, y + 3.4, -hd + T + 0.1), 0.0)
		else:
			for i in 2:
				Furnish._bed(r, Vector3(1.6 + i * 2.6, y, ch_z - 0.3), 0.0, room, settlement, false)
			Furnish._put(r, P + "Table_Large.gltf", Vector3(4.6, y, wall_z - 0.9), 0.0, true, 0.7)
			Furnish._chest(r, Vector3(6.0, y, -hd + T + 0.6), 0.0, "house", settlement, room)
		Furnish._light(r, Vector3(sx * 3.2, y + 3.0, ch_z), 0.8, 7.0, false)


## A gilded throne with a high, crested back and red velvet (facing +z, seat 0.62 m up).
static func _throne(k: Kit, at: Vector3, s: float) -> void:
	var gold := mat("gold")
	var velvet := mat("velvet")
	k.box(at + Vector3(0, 0.24, 0) * s, Vector3(1.36, 0.48, 1.05) * s, gold)
	k.box(at + Vector3(0, 0.55, 0.04) * s, Vector3(1.16, 0.14, 0.95) * s, velvet)
	k.box(at + Vector3(0, 1.45, -0.45) * s, Vector3(1.4, 2.5, 0.16) * s, gold)
	k.box(at + Vector3(0, 1.45, -0.36) * s, Vector3(1.04, 1.9, 0.06) * s, velvet)
	k.box(at + Vector3(0, 2.86, -0.45) * s, Vector3(0.62, 0.62, 0.16) * s, gold, 0.0)
	k.ball(at + Vector3(0, 3.28, -0.45) * s, 0.15 * s, gold)
	for sx in [-1.0, 1.0]:
		k.box(at + Vector3(sx * 0.62, 0.86, 0.02) * s, Vector3(0.16, 0.12, 1.0) * s, gold)
		k.box(at + Vector3(sx * 0.62, 0.7, 0.42) * s, Vector3(0.12, 0.36, 0.12) * s, gold)
		k.ball(at + Vector3(sx * 0.62, 0.96, 0.5) * s, 0.09 * s, gold)
		k.ball(at + Vector3(sx * 0.7, 2.72, -0.45) * s, 0.12 * s, gold)
