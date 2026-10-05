class_name Builder
## Assembles modular-kit buildings (walls, floors, stairs, roofs, doors, windows) with
## furnished interiors. Static geometry is merged per material; collision uses boxes.

const V := "res://assets/village/"
const P := "res://assets/props/"
const FLOOR_H := 3.0


## Collects kit pieces and turns them into one multimesh per piece type (fast to build,
## instanced on the GPU). Used for building exteriors, castles and bridges.
class Instancer:
	var remap := {}
	var style_key := ""
	var items := {}          # mesh id -> [Mesh, Array of Transform3D] (plain Array: appended by reference)
	var count := 0
	static var styled := {}
	func _styled(mesh: Mesh) -> Mesh:
		var key := "%d|%s" % [mesh.get_instance_id(), style_key]
		if styled.has(key):
			return styled[key]
		var out := mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat and remap.has(mat.resource_name):
				if out == mesh:
					out = mesh.duplicate()
				out.surface_set_material(s, remap[mat.resource_name])
		styled[key] = out
		return out
	func add_part(part: Array, xf: Transform3D) -> void:
		if part.is_empty():
			return
		var mesh := _styled(part[0])
		var key := mesh.get_instance_id()
		if not items.has(key):
			items[key] = [mesh, []]
		(items[key][1] as Array).append(xf * part[1])
		count += 1
	func add(path: String, xf: Transform3D) -> void:
		for p in Assets.parts(path):
			add_part(p, xf)
	func build(parent: Node3D, vis_end: float, fade := false) -> void:
		for key in items:
			var xs: Array = items[key][1]
			var buf := PackedFloat32Array()
			buf.resize(xs.size() * 12)
			var o := 0
			for t in xs:
				var b: Basis = t.basis
				buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = t.origin.x
				buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = t.origin.y
				buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = t.origin.z
				o += 12
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = items[key][0]
			mm.instance_count = xs.size()
			mm.buffer = buf
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			# small pieces drop out sooner than walls and roofs (each kind is a draw call)
			var size := mm.mesh.get_aabb().get_longest_axis_size()
			var cap: float = (120.0 if size < 1.2 else (260.0 if size < 4.0 else 900.0)) if Assets.compat \
				else (220.0 if size < 1.2 else (600.0 if size < 4.0 else INF))
			mi.visibility_range_end = minf(vis_end, cap)
			if fade:
				mi.visibility_range_end_margin = 10.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			parent.add_child(mi)


## Merges many kit pieces into one ArrayMesh with a surface per material.
class Merger:
	var buckets := {}       # Material -> SurfaceTool
	var order: Array = []
	var remap := {}         # material resource name -> replacement Material
	var count := 0
	static var canon := {}  # every kit file imports its own copy of each material: share them by name
	func _resolve(mat: Material) -> Material:
		if mat == null:
			return null
		var key := mat.resource_name
		if key == "":
			return mat
		if remap.has(key):
			return remap[key]
		if not canon.has(key):
			canon[key] = mat
		return canon[key]
	func add_part(part: Array, xf: Transform3D) -> void:
		if part.is_empty():
			return
		var mesh: Mesh = part[0]
		var pxf: Transform3D = xf * part[1]
		for s in mesh.get_surface_count():
			var mat: Material = _resolve(mesh.surface_get_material(s))
			if not buckets.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				buckets[mat] = st
				order.append(mat)
			var u := Assets.unskinned(mesh, s)
			(buckets[mat] as SurfaceTool).append_from(u[0], u[1], pxf)
	func add(path: String, xf: Transform3D) -> void:
		for p in Assets.parts(path):
			var mesh: Mesh = p[0]
			var pxf: Transform3D = xf * p[1]
			for s in mesh.get_surface_count():
				var mat: Material = _resolve(mesh.surface_get_material(s))
				if not buckets.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					buckets[mat] = st
					order.append(mat)
				var u := Assets.unskinned(mesh, s)
				(buckets[mat] as SurfaceTool).append_from(u[0], u[1], pxf)
		count += 1
	func commit() -> ArrayMesh:
		var out := ArrayMesh.new()
		for mat in order:
			var st: SurfaceTool = buckets[mat]
			out = st.commit(out)
			out.surface_set_material(out.get_surface_count() - 1, mat)
		return out


## Everything produced for one building.
class Result:
	var ext
	var inn             # Merger or Instancer
	var body: StaticBody3D
	var root: Node3D
	var xform: Transform3D
	var spots := {"beds": [], "work": [], "sit": [], "chests": []}
	var nav := []           # [{p: Vector3, links: [idx]}] in world space
	var door_out := -1
	var door_in := -1
	var door: Node3D
	var lights: Array = []
	var fires: Array = []
	var center := Vector3.ZERO
	var data: Dictionary
	func add_nav(p: Vector3) -> int:
		nav.append({"p": p, "links": []})
		return nav.size() - 1
	func link(a: int, b: int) -> void:
		if a < 0 or b < 0 or a == b:
			return
		if not nav[a].links.has(b):
			nav[a].links.append(b)
		if not nav[b].links.has(a):
			nav[b].links.append(a)


static var _mat_cache := {}


## Style remaps materials for the biome: desert adobe, snowy roofs, weathered ruins.
static func style_remap(style: String) -> Dictionary:
	if _mat_cache.has(style):
		return _mat_cache[style]
	if style.ends_with("+castle"):
		# a castle's outbuildings: the climate's look, under slate rather than red clay tiles
		var castle: Dictionary = style_remap(style.trim_suffix("+castle")).duplicate()
		for p in Assets.parts(V + "Roof_RoundTiles_6x8.gltf"):
			for s in (p[0] as Mesh).get_surface_count():
				var src: Material = (p[0] as Mesh).surface_get_material(s)
				if src and "RoundTiles" in src.resource_name:
					var m: BaseMaterial3D = (castle.get(src.resource_name, src) as BaseMaterial3D).duplicate()
					m.albedo_texture = null
					m.albedo_color = Color(0.21, 0.25, 0.31)
					m.roughness = 0.58
					castle[src.resource_name] = m
		_mat_cache[style] = castle
		return castle
	var remap := {}
	var probe := ["Wall_Plaster_Straight.gltf", "Roof_RoundTiles_6x8.gltf", "Wall_UnevenBrick_Straight.gltf", "Floor_WoodDark.gltf"]
	var mats := {}
	for f in probe:
		for p in Assets.parts(V + f):
			for s in (p[0] as Mesh).get_surface_count():
				var m: Material = (p[0] as Mesh).surface_get_material(s)
				if m:
					mats[m.resource_name] = m
	match style:
		"desert":
			for n in mats:
				var m: BaseMaterial3D = mats[n].duplicate()
				if "Plaster" in n:
					m.albedo_color = Color(1.2, 1.05, 0.84)
				elif "Wood" in n:
					m.albedo_color = Color(0.64, 0.5, 0.38)
				elif "Brick" in n or "Rock" in n:
					m.albedo_color = Color(1.05, 0.82, 0.6)
				remap[n] = m
		"cold":
			var snow := ShaderMaterial.new()
			snow.shader = load("res://shaders/snow_overlay.gdshader")
			for n in mats:
				var m: BaseMaterial3D = mats[n].duplicate()
				if "RoundTiles" in n:
					m.albedo_color = Color(0.72, 0.72, 0.78)
					m.next_pass = snow
				elif "Plaster" in n:
					m.albedo_color = Color(0.9, 0.9, 0.92)
				remap[n] = m
		"ruin":
			for n in mats:
				var m: BaseMaterial3D = mats[n].duplicate()
				m.albedo_color = Color(0.62, 0.62, 0.6)
				remap[n] = m
	_mat_cache[style] = remap
	return remap


# ------------------------------------------------------------------ building
## b: {type, x, z, yaw, w, d, floors, ruined?}; style: temperate/cold/desert; base_y ground height.
## `inn` collects the interior: a shared per-district Instancer in settlements, else a Merger.
static func build_building(b: Dictionary, style: String, base_y: float, ext, settlement: String, rng: RandomNumberGenerator, inn = null) -> Result:
	var r := Result.new()
	r.data = b
	r.ext = ext
	if inn == null:
		inn = Merger.new()
		inn.remap = ext.remap
	r.inn = inn
	var W: int = int(b.w)
	var D: int = int(b.d)
	var floors: int = int(b.floors)
	var btype: String = b.type
	var ruined: bool = b.get("ruined", false)
	if btype == "stable" or btype == "mews":
		floors = 1
	r.xform = Transform3D(Basis(Vector3.UP, float(b.yaw)), Vector3(float(b.x), base_y, float(b.z)))
	r.center = r.xform.origin
	r.root = Node3D.new()
	r.root.name = "%s_%s" % [btype, str(int(b.x))]
	r.root.transform = r.xform
	r.body = StaticBody3D.new()
	r.body.collision_layer = 1
	r.body.collision_mask = 0
	r.root.add_child(r.body)
	var stone := style == "cold" or btype in ["keep", "chapel", "barracks", "townhall"] or (style == "temperate" and rng.randf() < 0.25)
	# desert houses are smooth adobe with arched openings; elsewhere plaster, timber framing or stone
	var desert := style == "desert"
	var timber := not stone and not desert and rng.randf() < 0.4
	var wall_plain := V + ("Wall_UnevenBrick_Straight.gltf" if stone else ("Wall_Plaster_WoodGrid.gltf" if timber else "Wall_Plaster_Straight.gltf"))
	var wall_window := V + ("Wall_UnevenBrick_Window_Wide_" if stone else "Wall_Plaster_Window_Wide_") + ("Round.gltf" if desert else "Flat.gltf")
	var wall_window_thin := V + ("Wall_UnevenBrick_Window_Thin_Round.gltf" if stone else "Wall_Plaster_Window_Thin_Round.gltf")
	var wall_door := V + ("Wall_UnevenBrick_Door_Round.gltf" if (stone and (desert or btype in ["chapel", "keep"])) else ("Wall_UnevenBrick_Door_Flat.gltf" if stone else ("Wall_Plaster_Door_Round.gltf" if desert else "Wall_Plaster_Door_Flat.gltf")))
	var door_round := wall_door.ends_with("Round.gltf")
	var flat_roof := style == "desert"
	var open_front := btype == "stable"
	# ---- foundation skirt & floors
	var hw := W * 0.5
	var hd := D * 0.5
	for f in floors:
		var y0 := f * FLOOR_H
		_floor(r, f, W, D, y0, floors, btype)
	# plinth: stone skirt that hides sloped ground below the ground floor
	for side in 4:
		var n := (W if side < 2 else D) / 2
		for i in n:
			var lp := _edge_pos(side, i, W, D)
			_piece(r, V + "Wall_UnevenBrick_Straight.gltf", Vector3(lp.x, -3.05, lp.z), _side_yaw(side), true)
	# ---- walls
	var door_i := ((W / 2) - 1) / 2 if (W / 2) % 2 == 0 else (W / 2) / 2
	if W == 4:
		door_i = 1
	for f in floors:
		var y0 := f * FLOOR_H
		for side in 4:
			var n := (W if side < 2 else D) / 2
			for i in n:
				if ruined and (rng.randf() < 0.28 or (f > 0 and rng.randf() < 0.5)):
					continue
				var lp := _edge_pos(side, i, W, D)
				var pos := Vector3(lp.x, y0, lp.z)
				var yaw := _side_yaw(side)
				if side == 0 and f == 0 and open_front:
					if i == 0 or i == n - 1:
						_piece(r, V + "Prop_Support.gltf", pos + Vector3(0, 0, -0.1), yaw, true)
					continue
				var path := wall_plain
				var is_door := side == 0 and f == 0 and i == door_i
				if is_door:
					path = wall_door
				elif side >= 2 and i % 2 == 1:
					path = wall_window
				elif side < 2 and f > 0 and i != door_i:
					path = wall_window_thin if side == 1 else wall_window
				elif side == 0 and i != door_i and n > 2 and (i % 2 == 0):
					path = wall_window
				if btype in ["warehouse", "barracks"] and path == wall_window and f == 0 and i % 4 != 1:
					path = wall_plain
				_piece(r, path, pos, yaw, true)
				var is_win := path == wall_window or path == wall_window_thin
				if is_win and not ruined:
					var win := V + ((("Window_Wide_Round1.gltf" if desert else "Window_Wide_Flat1.gltf")) if path == wall_window else "Window_Thin_Round1.gltf")
					_piece(r, win, pos, yaw, true)
				# collision
				if is_door:
					_box(r, pos + _rot(Vector3(-0.86, 1.56, -0.1), yaw), Vector3(0.28, 3.12, 0.32), yaw)
					_box(r, pos + _rot(Vector3(0.86, 1.56, -0.1), yaw), Vector3(0.28, 3.12, 0.32), yaw)
					_box(r, pos + _rot(Vector3(0, 2.75, -0.1), yaw), Vector3(2.0, 0.74, 0.32), yaw)
				else:
					_box(r, pos + _rot(Vector3(0, 1.56, -0.1), yaw), Vector3(2.0, 3.12, 0.32), yaw)
			# corners
		for c in 4:
			var cx := hw if (c & 1) else -hw
			var cz := hd if (c & 2) else -hd
			if not (ruined and rng.randf() < 0.3):
				_piece(r, V + ("Corner_Exterior_Brick.gltf" if stone else "Corner_Exterior_Wood.gltf"), Vector3(cx, y0, cz), 0.0, true)
	# ---- door
	if not ruined and not open_front:
		var dpos := _edge_pos(0, door_i, W, D)
		var door := Interactables.Door.new()
		var door_path := V + ("Door_1_Round.gltf" if door_round else "Door_1_Flat.gltf")
		door.setup(Assets.parts(door_path), 1.1)
		door.position = Vector3(dpos.x - 0.55, 0.0, dpos.z - 0.08)
		door.swing = 1.0   # swing inward so the open leaf never blocks the threshold
		r.root.add_child(door)
		r.door = door
		_piece(r, V + ("DoorFrame_Round_WoodDark.gltf" if door_round else "DoorFrame_Flat_WoodDark.gltf"), Vector3(dpos.x, 0, dpos.z), 0.0, true)
	# ---- roof
	var top := floors * FLOOR_H
	if not ruined:
		if flat_roof:
			for zi in D / 2:
				for xi in W / 2:
					var c := Vector3(-hw + 1 + xi * 2, top + 0.12, -hd + 1 + zi * 2)
					_piece(r, V + "Floor_Brick.gltf", c, 0.0, true)
					r.ext.add(V + "Floor_Brick.gltf", r.xform * Transform3D(Basis(Vector3.RIGHT, PI), c + Vector3(0, -0.02, 0)))
			for side in 4:
				var n := (W if side < 2 else D) / 2
				for i in n:
					var lp := _edge_pos(side, i, W, D)
					_piece(r, V + "Prop_ExteriorBorder_Straight1.gltf", Vector3(lp.x, top + 0.13, lp.z), _side_yaw(side) + PI, true)
			_box(r, Vector3(0, top + 0.05, 0), Vector3(W, 0.2, D), 0.0)
		else:
			var roof := V + "Roof_RoundTiles_%dx%d.gltf" % [W, D]
			if not ResourceLoader.exists(roof):
				roof = V + "Roof_RoundTiles_6x8.gltf"
			_piece(r, roof, Vector3(0, top, 0), 0.0, true)
			var gable := V + "Roof_Front_Brick%d.gltf" % W
			_piece(r, gable, Vector3(0, top, hd), 0.0, true)
			_piece(r, gable, Vector3(0, top, -hd), PI, true)
			_box(r, Vector3(0, top + 0.1, 0), Vector3(W, 0.2, D), 0.0)
			if btype in ["house", "tavern", "kitchen", "blacksmith", "townhall", "keep"] and not (style == "desert"):
				_piece(r, V + "Prop_Chimney.gltf", Vector3(hw - 1.2, top + 0.4, -hd + 1.6), 0.0, true)
	# ---- door threshold: stone steps & an entry ramp when the floor sits above the ground
	if not open_front:
		var dp := _edge_pos(0, door_i, W, D)
		var outside := r.xform * Vector3(dp.x, 0, dp.z + 1.6)
		var drop := r.xform.origin.y - WorldData.height_at(outside.x, outside.z)
		if drop > 0.12:
			var steps := clampi(int(ceil(drop / 0.35)), 1, 4)
			for k in steps:
				var sy := -drop + (k + 1) * drop / steps - 0.5
				_piece(r, V + "Prop_ExteriorBorder_Straight1.gltf", Vector3(dp.x, sy, dp.z + 0.75 + (steps - 1 - k) * 0.55), PI, true)
			var ramp_len := 1.2 + steps * 0.55
			var ang := atan2(drop + 0.05, ramp_len)
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(1.9, 0.25, sqrt(ramp_len * ramp_len + drop * drop) + 0.2)
			cs.shape = bx
			cs.transform = Transform3D(Basis(Vector3.RIGHT, ang), Vector3(dp.x, -drop * 0.5 - 0.1, dp.z + ramp_len * 0.5))
			r.body.add_child(cs)
	# ---- navigation & interior
	var dpos2 := _edge_pos(0, door_i, W, D)
	var p_out := r.xform * Vector3(dpos2.x, 0.05, dpos2.z + 1.8)
	var p_in := r.xform * Vector3(dpos2.x, 0.05, dpos2.z - 1.3)
	r.door_out = r.add_nav(p_out)
	r.door_in = r.add_nav(p_in)
	r.link(r.door_out, r.door_in)
	var center_i := r.add_nav(r.xform * Vector3(0, 0.05, 0))
	r.link(r.door_in, center_i)
	if not ruined:
		Furnish.furnish(r, btype, W, D, floors, style, settlement, rng, center_i)
	else:
		Furnish.ruin_props(r, W, D, rng)
	return r


static func _floor(r: Result, f: int, W: int, D: int, y0: float, floors: int, btype: String) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	var has_stair_above := f < floors - 1
	var has_hole := f > 0
	var mat_floor := V + ("Floor_WoodDark.gltf" if btype != "keep" or f > 0 else "Floor_Brick.gltf")
	if btype in ["chapel", "barracks"] and f == 0:
		mat_floor = V + "Floor_UnevenBrick.gltf"
	if not has_hole:
		for zi in D / 2:
			for xi in W / 2:
				_piece(r, mat_floor, Vector3(-hw + 1 + xi * 2, y0 + 0.02, -hd + 1 + zi * 2), 0.0, true)
		_box(r, Vector3(0, y0 - 0.1, 0), Vector3(W, 0.24, D), 0.0)
	else:
		# stair hole along the right wall (x = hw-1 column), stair top at z = hd - 0.42 - 4.58
		var top_z := hd - 0.42 - 4.58
		var clear_z := hd - 0.42 - 0.9
		for xi in W / 2:
			var cx := -hw + 1 + xi * 2
			if xi == W / 2 - 1:
				for k in D:
					var cz := -hd + 0.5 + k
					if cz > top_z and cz < clear_z:
						continue
					_piece(r, V + "Floor_WoodDark_Half3.gltf", Vector3(cx, y0 + 0.02, cz), 0.0, true)
					r.ext.add(V + "Floor_WoodDark_Half3.gltf", r.xform * Transform3D(Basis(Vector3.RIGHT, PI), Vector3(cx, y0 - 0.05, cz)))
					_box(r, Vector3(cx, y0 - 0.1, cz), Vector3(2.0, 0.24, 1.0), 0.0)
			else:
				for zi in D / 2:
					var c := Vector3(cx, y0 + 0.02, -hd + 1 + zi * 2)
					_piece(r, V + "Floor_WoodDark.gltf", c, 0.0, true)
					r.ext.add(V + "Floor_WoodDark.gltf", r.xform * Transform3D(Basis(Vector3.RIGHT, PI), c - Vector3(0, 0.07, 0)))
				_box(r, Vector3(cx, y0 - 0.1, 0), Vector3(2.0, 0.24, D), 0.0)
	if has_stair_above:
		var sx := hw - 1.0
		var sz := hd - 0.42
		r.inn.add(V + "Stair_Interior_Solid.gltf", r.xform * Transform3D(Basis(), Vector3(sx, y0, sz)))
		var ang := atan2(3.0, 4.58)
		var mid := Vector3(sx, y0 + 1.5 - 0.12, sz - 2.29)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(1.6, 0.2, sqrt(3.0 * 3.0 + 4.58 * 4.58) + 0.3)
		cs.shape = bx
		cs.transform = Transform3D(Basis(Vector3.RIGHT, ang), mid)
		r.body.add_child(cs)
		var a := r.add_nav(r.xform * Vector3(sx - 1.2, y0 + 0.05, sz - 0.35))
		var foot := r.add_nav(r.xform * Vector3(sx, y0 + 0.1, sz - 0.35))
		var b := r.add_nav(r.xform * Vector3(sx, y0 + 3.05, sz - 4.9))
		r.link(a, foot)
		r.link(foot, b)
		r.set_meta("stair_%d" % f, [a, b])


static func _edge_pos(side: int, i: int, W: int, D: int) -> Vector3:
	var hw := W * 0.5
	var hd := D * 0.5
	match side:
		0: return Vector3(-hw + 1 + i * 2, 0, hd)
		1: return Vector3(hw - 1 - i * 2, 0, -hd)
		2: return Vector3(hw, 0, hd - 1 - i * 2)
		_: return Vector3(-hw, 0, -hd + 1 + i * 2)


static func _side_yaw(side: int) -> float:
	match side:
		0: return 0.0
		1: return PI
		2: return PI * 0.5
		_: return -PI * 0.5


static func _rot(v: Vector3, yaw: float) -> Vector3:
	return Basis(Vector3.UP, yaw) * v


static func _piece(r: Result, path: String, lp: Vector3, yaw: float, exterior: bool, scale := 1.0) -> void:
	var xf := r.xform * Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), lp)
	if exterior:
		r.ext.add(path, xf)
	else:
		r.inn.add(path, xf)


static func _box(r: Result, lp: Vector3, size: Vector3, yaw: float) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), lp)
	r.body.add_child(cs)
