extends Node3D
## Builds every village, town, castle (intact & ruined), landmark and bridge described in
## world.json, manages their lights and portcullises, and provides NPC path-finding.

const V := "res://assets/village/"
const P := "res://assets/props/"
const FORT := "res://assets/castle/modular_fort_01/modular_fort_01.gltf"
const GATE := "res://assets/castle/large_iron_gate/large_iron_gate.gltf"
const H := 29.12

var infos: Array = []                 # runtime info per settlement (same order as WorldData.settlements)
var poi_infos: Array = []
var lights: Array[OmniLight3D] = []
var street_lights: Array[OmniLight3D] = []
var flicker: Array[OmniLight3D] = []
var portcullises: Array = []
var bridges: Array = []               # [{a, b, ya, yb}]
var _light_t := 0.0
var _fort_ruin_remap := {}


func setup(progress: Callable) -> void:
	var n := WorldData.settlements.size()
	var shown := Time.get_ticks_msec()
	for i in n:
		var s: Dictionary = WorldData.settlements[i]
		infos.append(_build_settlement(s))
		progress.call(float(i + 1) / float(n) * 0.8, "Raising " + String(s.name))
		if Time.get_ticks_msec() - shown > 90:   # refresh the loading screen ~10x a second
			await get_tree().process_frame
			shown = Time.get_ticks_msec()
	for q in WorldData.pois:
		poi_infos.append(_build_poi(q))
	progress.call(0.9, "Building bridges")
	await get_tree().process_frame
	for b in WorldData.info.get("bridges", []):
		_build_bridge(b)
	Game.day_passed.connect(_on_new_day)
	Game.reputation_changed.connect(func(_v): _update_portcullis(true))
	progress.call(1.0, "Settlements raised")


# ------------------------------------------------------------------ settlements
func _new_info(s: Dictionary) -> Dictionary:
	return {"name": s.name, "type": s.type, "center": Vector3(s.x, s.y, s.z), "radius": float(s.radius), "climate": WorldData.climate_at(s.x, s.z),
		"buildings": [], "nav_p": [], "nav_l": [], "hubs": [], "stalls": [], "fields": [], "exits": [], "wells": [], "gate_in": -1, "gate_out": -1,
		"walk_loop": [], "horse_spots": [], "obbs": [], "yaw": float(s.get("yaw", 0.0)), "portcullis": null}


func _build_settlement(s: Dictionary) -> Dictionary:
	var info := _new_info(s)
	var node := Node3D.new()
	node.name = String(s.name).replace(" ", "_")
	add_child(node)
	info["node"] = node
	var kind := String(s.type)
	var ruined := kind in ["ruin", "ruin_keep"]
	var style: String = info.climate
	var ext := Builder.Instancer.new()
	ext.remap = Builder.style_remap("ruin" if ruined else style).duplicate()
	ext.style_key = "ruin" if ruined else style
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(s.name))
	var cy := float(s.y)
	# interiors are GPU-instanced per 64 m district: far cheaper to build than merged meshes
	var inns := {}
	# --- buildings
	for b in s.get("buildings", []):
		var by := _footprint_height(b)
		if kind in ["castle", "ruin"]:
			by = maxf(by, cy)
		var ck := Vector2i(floori(float(b.x) / 64.0), floori(float(b.z) / 64.0))
		if not inns.has(ck):
			var ii := Builder.Instancer.new()
			ii.remap = ext.remap
			ii.style_key = ext.style_key
			inns[ck] = ii
		var r := Builder.build_building(b, style, by + 0.1, ext, s.name, rng, inns[ck])
		node.add_child(r.root)
		for l in r.lights:
			lights.append(l)
			if l.has_meta("flicker"):
				flicker.append(l)
		for f in r.fires:
			Game.world_ref.call("register_fire", f)
		if r.door and not ruined:
			_lantern(ext, node, r, style)
		_merge_nav(info, r)
		info.buildings.append({"type": b.type, "result": r, "spots": r.spots, "door_out": r.get_meta("door_out_g"), "door": r.door,
			"center": r.center, "floors": int(b.floors), "xform": r.xform, "w": int(b.w), "d": int(b.d)})
		info.obbs.append([r.xform, float(b.w) * 0.5 + 0.4, float(b.d) * 0.5 + 0.4, r.xform.affine_inverse()])
		if r.spots.has("horses"):
			info.horse_spots.append_array(r.spots.horses)
	# --- castle walls
	if kind in ["castle", "ruin"]:
		_build_castle(info, ext, kind == "ruin", rng)
	elif kind == "ruin_keep":
		_build_isle_ruin(info, ext, rng)
	# --- outdoor navigation, then props that hook into it
	_build_outdoor_nav(info, s)
	for p in s.get("props", []):
		_build_prop(info, ext, p, style, rng)
	if style == "desert" and not ruined:
		_palms(info, rng)
	ext.build(node, 3200.0)
	for ck in inns:
		(inns[ck] as Builder.Instancer).build(node, 60.0 if Assets.compat else 115.0, true)
	return info


func _palms(info: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = info.center
	var meshes := []
	for k in 3:
		meshes.append(Assets.merged_mesh("res://assets/plants/palm_%d.glb" % (k + 1)))
	for k in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(14.0, float(info.radius) * 1.1)
		var p := Vector3(c.x + sin(a) * r, 0, c.z + cos(a) * r)
		if _blocked(info, p, p + Vector3(0.1, 0, 0.1)):
			continue
		p.y = WorldData.height_at(p.x, p.z) - 0.1
		var m: Mesh = meshes[k % 3]
		var sc := 9.0 / maxf(m.get_aabb().size.y, 0.0001) * rng.randf_range(0.8, 1.25)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), p)
		mi.visibility_range_end = 900.0
		(info.node as Node3D).add_child(mi)


## Grass mask (1 = grass may grow) with building footprints and castle grounds cut out.
func build_grass_mask() -> ImageTexture:
	var N := 4096
	var cell := WorldData.SIZE / N
	var img := Image.create(N, N, false, Image.FORMAT_R8)
	img.fill(Color(1, 1, 1))
	for info in infos + poi_infos:
		for o in info.obbs:
			var xf: Transform3D = o[0]
			# padded by more than half a texel diagonal so no floor texel is left unmasked
			var hx: float = o[1] + 1.1
			var hz: float = o[2] + 1.1
			var rr := Vector2(hx, hz).length()
			var c := xf.origin
			var inv := xf.affine_inverse()
			for j in range(int((c.z - rr + WorldData.HALF) / cell), int((c.z + rr + WorldData.HALF) / cell) + 1):
				for i in range(int((c.x - rr + WorldData.HALF) / cell), int((c.x + rr + WorldData.HALF) / cell) + 1):
					if i < 0 or j < 0 or i >= N or j >= N:
						continue
					var wp := Vector3(-WorldData.HALF + (i + 0.5) * cell, c.y, -WorldData.HALF + (j + 0.5) * cell)
					var lp := inv * wp
					if absf(lp.x) < hx and absf(lp.z) < hz:
						img.set_pixel(i, j, Color(0, 0, 0))
	# the wild places are trodden bare in the middle
	for w in preload("res://scripts/world/wilds.gd").plan():
		var r: float = float(w.r) * 0.75
		var c := Vector2(float(w.x), float(w.z))
		for j in range(int((c.y - r + WorldData.HALF) / cell), int((c.y + r + WorldData.HALF) / cell) + 1):
			for i in range(int((c.x - r + WorldData.HALF) / cell), int((c.x + r + WorldData.HALF) / cell) + 1):
				if i >= 0 and j >= 0 and i < N and j < N and Vector2(-WorldData.HALF + (i + 0.5) * cell, -WorldData.HALF + (j + 0.5) * cell).distance_to(c) < r:
					img.set_pixel(i, j, Color(0, 0, 0))
	return ImageTexture.create_from_image(img)


func _footprint_height(b: Dictionary) -> float:
	var xf := Transform3D(Basis(Vector3.UP, float(b.yaw)), Vector3(float(b.x), 0, float(b.z)))
	var hw := float(b.w) * 0.5
	var hd := float(b.d) * 0.5
	var m := -1e9
	for p in [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(-hw, 0, hd), Vector3(hw, 0, hd), Vector3.ZERO, Vector3(0, 0, hd), Vector3(0, 0, -hd)]:
		var w: Vector3 = xf * p
		m = maxf(m, WorldData.height_at(w.x, w.z))
	return m


func _merge_nav(info: Dictionary, r: Builder.Result) -> void:
	var base: int = info.nav_p.size()
	for n in r.nav:
		info.nav_p.append(n.p)
		var links := []
		for l in n.links:
			links.append(int(l) + base)
		info.nav_l.append(links)
	for key in ["beds", "work", "sit"]:
		for sp in r.spots[key]:
			sp["nav"] = int(sp.nav) + base
	r.set_meta("door_out_g", r.door_out + base)
	r.set_meta("door_in_g", r.door_in + base)


func _add_nav(info: Dictionary, p: Vector3) -> int:
	info.nav_p.append(p)
	info.nav_l.append([])
	return info.nav_p.size() - 1


func _link(info: Dictionary, a: int, b: int) -> void:
	if a < 0 or b < 0 or a == b:
		return
	if not info.nav_l[a].has(b):
		info.nav_l[a].append(b)
	if not info.nav_l[b].has(a):
		info.nav_l[b].append(a)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, WorldData.height_at(x, z) + 0.05, z)


func _blocked(info: Dictionary, a: Vector3, b: Vector3, ignore: int = -1) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / 1.0) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / steps)
		for k in info.obbs.size():
			if k == ignore:
				continue
			var o: Array = info.obbs[k]
			var lp: Vector3 = (o[3] as Transform3D) * p
			if absf(lp.x) < float(o[1]) and absf(lp.z) < float(o[2]):
				return true
	return false


func _build_outdoor_nav(info: Dictionary, s: Dictionary) -> void:
	var c: Vector3 = info.center
	var kind := String(s.type)
	var hubs := []
	var center_i := _add_nav(info, _ground(c.x, c.z + 4.0))
	hubs.append(center_i)
	var ring_r := 13.0 if kind == "town" else (10.0 if kind == "village" else 8.0)
	var ring := []
	for k in 10:
		var a := k * TAU / 10.0
		var i := _add_nav(info, _ground(c.x + sin(a) * ring_r, c.z + cos(a) * ring_r))
		ring.append(i)
		hubs.append(i)
	for k in 10:
		_link(info, ring[k], ring[(k + 1) % 10])
		_link(info, ring[k], center_i)
	if kind == "town":
		var yaw: float = info.yaw
		for axis in [Vector3(sin(yaw), 0, cos(yaw)), Vector3(cos(yaw), 0, -sin(yaw))]:
			var prev := -1
			for t in range(-int(info.radius * 0.95), int(info.radius * 0.95) + 1, 9):
				if absf(t) < ring_r:
					if prev >= 0:
						_link(info, prev, _closest(info, ring, c + axis * t))
					prev = -1
					continue
				var p: Vector3 = c + axis * float(t)
				var i := _add_nav(info, _ground(p.x, p.z))
				hubs.append(i)
				if prev >= 0:
					_link(info, prev, i)
				elif absf(t) < ring_r + 10:
					_link(info, i, _closest(info, ring, p))
				prev = i
	if kind in ["castle", "ruin"]:
		var yaw: float = info.yaw
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var gi := _add_nav(info, _ground(c.x + fwd.x * (H - 6.0), c.z + fwd.z * (H - 6.0)))
		var go := _add_nav(info, _ground(c.x + fwd.x * (H + 9.0), c.z + fwd.z * (H + 9.0)))
		_link(info, gi, go)
		_link(info, gi, _closest(info, ring, info.nav_p[gi]))
		info.gate_in = gi
		info.gate_out = go
		hubs.append(gi)
	info.hubs = hubs
	# connect building doors
	for bi in info.buildings.size():
		var b: Dictionary = info.buildings[bi]
		var dout: int = b.door_out
		var p: Vector3 = info.nav_p[dout]
		var best := -1
		# nearest hub with a clear line of sight (sorted, so the first clear one wins)
		var order := hubs.duplicate()
		order.sort_custom(func(x, y): return (info.nav_p[x] as Vector3).distance_squared_to(p) < (info.nav_p[y] as Vector3).distance_squared_to(p))
		for h in order:
			if not _blocked(info, p, info.nav_p[h], bi):
				best = h
				break
		if best < 0:
			var xf: Transform3D = b.xform
			var out := p + xf.basis.z * 4.0
			var mid := _add_nav(info, _ground(out.x, out.z))
			_link(info, dout, mid)
			best = _closest(info, hubs, out)
		_link(info, dout, best)
	# road exits
	for rd in WorldData.roads:
		if rd.a != info.name and rd.b != info.name:
			continue
		var pts: Array = rd.pts
		var from_start: bool = rd.a == info.name
		var exit_p := Vector3.ZERO
		var idx := 0
		var n := pts.size()
		for k in n:
			var q: Array = pts[k if from_start else n - 1 - k]
			if Vector2(q[0] - c.x, q[2] - c.z).length() > float(info.radius) * 1.05:
				exit_p = Vector3(q[0], q[1], q[2])
				idx = k if from_start else n - 1 - k
				break
		if exit_p == Vector3.ZERO:
			continue
		var e := _add_nav(info, _ground(exit_p.x, exit_p.z))
		_link(info, e, _closest(info, hubs, exit_p))
		info.exits.append({"nav": e, "road": rd, "index": idx, "to": rd.b if from_start else rd.a})


func _closest(info: Dictionary, idxs: Array, p: Vector3) -> int:
	var best := -1
	var bd := 1e18
	for i in idxs:
		var d := (info.nav_p[i] as Vector3).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _lantern(ext, node: Node3D, r: Builder.Result, style: String) -> void:
	var hd := float(r.data.d) * 0.5
	var lp := Vector3(1.05, 2.15, hd + 0.05)
	ext.add(P + "Lantern_Wall.gltf", r.xform * Transform3D(Basis(Vector3.UP, PI), lp))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.68, 0.35)
	l.light_energy = 1.6
	l.omni_range = 8.0
	l.shadow_enabled = false
	l.position = r.xform * (lp + Vector3(0, -0.3, 0.45))
	l.visible = false
	node.add_child(l)
	street_lights.append(l)


# ------------------------------------------------------------------ props
func _build_prop(info: Dictionary, ext, p: Dictionary, style: String, rng: RandomNumberGenerator) -> void:
	var x := float(p.x)
	var z := float(p.z)
	var y := WorldData.height_at(x, z)
	var yaw := float(p.get("yaw", 0.0))
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))
	var node: Node3D = info.node
	match String(p.type):
		"well":
			ext.add("res://assets/items/stone_fire_pit/stone_fire_pit.gltf", xf * Transform3D(Basis().scaled(Vector3(1.7, 2.6, 1.7)), Vector3(0, 0.25, 0)))
			ext.add(V + "Prop_Support.gltf", xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-1.05, 0, 0)))
			ext.add(V + "Prop_Support.gltf", xf * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(1.05, 0, 0)))
			ext.add(V + "Roof_Wooden_2x1.gltf", xf * Transform3D(Basis(), Vector3(0, 1.75, -0.75)))
			ext.add(P + "Bucket_Wooden_1.gltf", xf * Transform3D(Basis(), Vector3(0.4, 0.55, 0.9)))
			_static_box(node, xf, Vector3(0, 0.6, 0), Vector3(2.2, 1.2, 2.2))
			var wn := _add_nav(info, xf * Vector3(0, 0.05, 1.8))
			info.wells.append(wn)
			if info.hubs.size() > 0:
				_link(info, wn, _closest(info, info.hubs, info.nav_p[wn]))
			Game.world_ref.call("register_water_source", xf.origin)
		"stall":
			ext.add(P + "Stall_Empty.gltf", xf)
			var goods := ["FarmCrate_Apple.gltf", "FarmCrate_Carrot.gltf", "Vase_2.gltf", "Bottle_1.gltf", "Book_Stack_2.gltf", "Pouch_Large.gltf", "Potion_1.gltf", "Barrel_Apples.gltf"]
			for k in 3:
				ext.add(P + goods[rng.randi() % goods.size()], xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(-0.55 + k * 0.55, 0.92, 0.0)))
			_static_box(node, xf, Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 0.9))
			var spot := xf * Vector3(0, 0.05, -1.0)
			var front := xf * Vector3(0, 0.05, 1.3)
			var n := _add_nav(info, spot)
			var f := _add_nav(info, front)
			_link(info, n, f)
			if info.hubs.size() > 0:
				_link(info, f, _closest(info, info.hubs, front))
			info.stalls.append({"p": spot, "yaw": yaw, "nav": n, "front": f})
		"field":
			_build_field(info, ext, p, rng)
		"dummy":
			ext.add(P + "Dummy.gltf", xf)
			_static_box(node, xf, Vector3(0, 0.9, 0), Vector3(0.6, 1.8, 0.5))
		"weaponstand":
			ext.add(P + "WeaponStand.gltf", xf)
			_static_box(node, xf, Vector3(0, 0.55, 0), Vector3(1.3, 1.1, 0.9))
		"cart":
			ext.add(V + "Prop_Wagon.gltf", xf)
			_static_box(node, xf, Vector3(0, 0.75, -1.1), Vector3(1.9, 1.5, 3.8))
		"banner":
			ext.add(V + "Prop_Support.gltf", xf * Transform3D(Basis().scaled(Vector3(1, 2.2, 1)), Vector3.ZERO))
			ext.add(P + "Banner_1.gltf", xf * Transform3D(Basis(), Vector3(0, 3.6, 0.15)))
		"statue":
			# the town's founding knight, carved in stone, on a boulder plinth
			var rock := "res://assets/nature/Rock_Medium_2.gltf"
			var rb := Assets.aabb(rock)
			var rs := Vector3(2.2 / maxf(rb.size.x, 0.01), 1.0 / maxf(rb.size.y, 0.01), 2.2 / maxf(rb.size.z, 0.01))
			var rc := rb.get_center() * rs
			ext.add(rock, xf * Transform3D(Basis().scaled(rs), Vector3(-rc.x, -rb.position.y * rs.y - 0.15, -rc.z)))
			var knight := CharacterModel.new()
			knight.transform = xf * Transform3D(Basis().scaled(Vector3.ONE * 1.4), Vector3(0, 0.78, 0))
			node.add_child(knight)
			knight.build({"gender": "m", "outfit": "Ranger", "steel": 0.88, "sword": true, "shield": true, "pauldron": true, "hood": true, "drawn": true})
			for gi in knight.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).material_override = _statue_stone()
			knight.freeze_end.call_deferred("Sword_Idle")
			_static_box(node, xf, Vector3(0, 1.9, 0), Vector3(2.0, 3.8, 2.0))


static var _stone: StandardMaterial3D
static func _statue_stone() -> StandardMaterial3D:
	if _stone == null:
		var t := "res://assets/castle/modular_fort_01/textures/modular_fort_01_plaster_"
		_stone = StandardMaterial3D.new()
		_stone.albedo_texture = load(t + "diff_2k.jpg")
		_stone.albedo_color = Color(0.9, 0.88, 0.84)
		_stone.normal_enabled = true
		_stone.normal_texture = load(t + "nor_gl_2k.jpg")
		_stone.roughness = 0.9
		_stone.uv1_triplanar = true
		_stone.uv1_world_triplanar = true
		_stone.uv1_scale = Vector3.ONE * 0.8
	return _stone


func _static_box(node: Node3D, xf: Transform3D, lp: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	b.add_child(cs)
	b.transform = xf * Transform3D(Basis(), lp)
	node.add_child(b)


func _build_field(info: Dictionary, ext, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(p.w)
	var d := float(p.d)
	var yaw := float(p.yaw)
	var c := Vector3(float(p.x), 0, float(p.z))
	var basis := Basis(Vector3.UP, yaw)
	var wheat := rng.randf() < 0.55
	var path := "res://assets/nature/Grass_Common_Tall.gltf" if wheat else "res://assets/nature/Plant_7_Big.gltf"
	var mesh: Mesh = Assets.merged_mesh(path).duplicate()
	for s in mesh.get_surface_count():
		var m = mesh.surface_get_material(s)
		if m is BaseMaterial3D:
			var mm: BaseMaterial3D = m.duplicate()
			mm.albedo_color = Color(1.35, 1.05, 0.45) if wheat else Color(0.85, 1.05, 0.75)
			mesh.surface_set_material(s, mm)
	var spacing := 0.9 if wheat else 1.1
	var xs := []
	var x := -w * 0.5 + 0.6
	while x < w * 0.5 - 0.4:
		var z := -d * 0.5 + 0.6
		while z < d * 0.5 - 0.4:
			var lp := Vector3(x + rng.randf_range(-0.15, 0.15), 0, z + rng.randf_range(-0.2, 0.2))
			var wp := c + basis * lp
			wp.y = WorldData.height_at(wp.x, wp.z) - 0.05
			var sc := rng.randf_range(0.8, 1.1) if wheat else rng.randf_range(1.1, 1.5)
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * (1.1 if wheat else 1.0), sc)), wp))
			z += spacing
		x += spacing * (1.4 if not wheat else 1.0)
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	mmesh.mesh = mesh
	mmesh.instance_count = xs.size()
	for i in xs.size():
		mmesh.set_instance_transform(i, xs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mmesh
	mi.visibility_range_end = 320.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(info.node as Node3D).add_child(mi)
	# fence
	for side in 4:
		var along := w if side < 2 else d
		var n := int(along / 2.05)
		for k in n:
			var t := -along * 0.5 + 1.03 + k * 2.05
			var lp: Vector3
			var fy := 0.0
			match side:
				0: lp = Vector3(t, 0, d * 0.5)
				1: lp = Vector3(t, 0, -d * 0.5)
				2: lp = Vector3(w * 0.5, 0, t); fy = PI * 0.5
				_: lp = Vector3(-w * 0.5, 0, t); fy = PI * 0.5
			if side == 0 and absf(t) < 1.5:
				continue
			var wp := c + basis * lp
			wp.y = WorldData.height_at(wp.x, wp.z)
			ext.add(V + "Prop_WoodenFence_Single.gltf", Transform3D(Basis(Vector3.UP, yaw + fy), wp))
	var gate := c + basis * Vector3(0, 0, d * 0.5 + 1.5)
	var nf := _add_nav(info, _ground(gate.x, gate.z))
	var spots := []
	for k in 4:
		var lp2 := Vector3(rng.randf_range(-w * 0.35, w * 0.35), 0, rng.randf_range(-d * 0.35, d * 0.35))
		var wp2 := c + basis * lp2
		var ni := _add_nav(info, _ground(wp2.x, wp2.z))
		_link(info, ni, nf)
		spots.append(ni)
	info.fields.append({"gate": nf, "spots": spots})
	_link(info, nf, _closest(info, info.hubs, info.nav_p[nf]) if info.hubs.size() > 0 else -1)


# ------------------------------------------------------------------ castles
func _fort(ext, piece: String, xf: Transform3D) -> void:
	ext.add_part(Assets.part_named(FORT, piece), xf)


func _build_castle(info: Dictionary, ext, ruined: bool, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = info.center
	var yaw: float = info.yaw
	var base := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, c.y - 0.15, c.z))
	var node: Node3D = info.node
	if ruined:
		_ruin_remap(ext)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	node.add_child(body)
	body.transform = base
	var corners := [Vector3(-H, 0, -H), Vector3(H, 0, -H), Vector3(H, 0, H), Vector3(-H, 0, H)]
	for side in 4:
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[(side + 1) % 4]
		var dir := (b - a).normalized()
		var syaw := atan2(dir.x, dir.z)
		var basis := Basis(Vector3.UP, syaw)
		var out := basis * Vector3(1, 0, 0)
		var pieces := []
		if side == 2:
			pieces = [["wall_thin_straight_01", 14.82, 2.55], ["wall_thin_straight_04", 7.41, 2.55], ["wall_thin_gate_01", 7.41, 2.55], ["wall_thin_straight_04", 7.41, 2.55], ["wall_thin_straight_01", 14.82, 2.55]]
		else:
			pieces = [["wall_thick_straight_01", 14.56, 4.17], ["wall_thick_straight_02", 14.56, 4.17], ["wall_thick_straight_01", 14.56, 4.17], ["wall_thick_straight_02", 14.56, 4.17]]
		var total := 0.0
		for pc in pieces:
			total += float(pc[1])
		var t := (2.0 * H - total) * 0.5
		for k in pieces.size():
			var pc: Array = pieces[k]
			var lp := a + dir * t
			var len := float(pc[1])
			var thick := float(pc[2])
			var gap: bool = ruined and rng.randf() < 0.3 and pc[0] != "wall_thin_gate_01"
			var squash := 1.0
			if ruined and not gap and rng.randf() < 0.45:
				squash = rng.randf_range(0.35, 0.75)
			if not gap:
				var xf := base * Transform3D(basis.scaled(Vector3(1, squash, 1)), lp)
				_fort(ext, pc[0], xf)
				if pc[0] == "wall_thin_gate_01":
					var gap_w := 4.4
					var side_w := (len - gap_w) * 0.5
					_box(body, lp + out * thick * 0.5 + dir * side_w * 0.5 + Vector3(0, 4.3, 0), Vector3(thick, 8.6, side_w), syaw)
					_box(body, lp + out * thick * 0.5 + dir * (len - side_w * 0.5) + Vector3(0, 4.3, 0), Vector3(thick, 8.6, side_w), syaw)
					_box(body, lp + out * thick * 0.5 + dir * len * 0.5 + Vector3(0, 7.1, 0), Vector3(thick, 3.0, gap_w), syaw)
					if not ruined:
						_portcullis(info, base, lp + out * thick * 0.5 + dir * len * 0.5, syaw)
				else:
					_box(body, lp + out * thick * 0.5 + dir * len * 0.5 + Vector3(0, 4.26 * squash, 0), Vector3(thick, 8.52 * squash, len), syaw)
				if side != 2 and not ruined:
					var wxf := base * Transform3D(basis, lp - out * 3.37)
					_fort(ext, "wall_walkway_straight_01", wxf)
					_box(body, lp - out * 1.68 + dir * len * 0.5 + Vector3(0, 3.85, 0), Vector3(3.37, 7.7, len), syaw)
			else:
				for q in 6:
					var rp := lp + dir * rng.randf_range(0, len) + out * rng.randf_range(-2, 5)
					ext.add("res://assets/nature/Rock_Medium_%d.gltf" % (1 + q % 3), base * Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.2, 0.5, 1.2) * rng.randf_range(0.8, 1.6)), rp))
			t += len
	# towers
	for k in 4:
		if ruined and k % 2 == 1:
			continue
		var cp: Vector3 = corners[k] * ((H + 2.1) / H)
		var sy := rng.randf_range(0.4, 0.75) if ruined else 1.0
		_fort(ext, "tower_round", base * Transform3D(Basis().scaled(Vector3(1, sy, 1)), cp))
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 7.6
		cyl.height = 13.5 * sy
		cs.shape = cyl
		cs.position = cp + Vector3(0, 6.75 * sy, 0)
		body.add_child(cs)
	if not ruined:
		# stairs up to the left wall walk
		var left_a: Vector3 = corners[3]
		var ldir: Vector3 = (corners[0] - left_a).normalized()
		var lbasis := Basis(Vector3.UP, atan2(ldir.x, ldir.z))
		var lout := lbasis * Vector3(1, 0, 0)
		var sp: Vector3 = left_a + ldir * 7.5 - lout * (3.37 + 3.54)
		_fort(ext, "wall_stairs_straight_01", base * Transform3D(lbasis, sp))
		var ang := atan2(7.53, 14.82)
		var cs2 := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(3.4, 0.3, 16.6)
		cs2.shape = bx
		cs2.transform = Transform3D(lbasis * Basis(Vector3.RIGHT, -ang), sp + lout * 1.77 + ldir * 7.41 + Vector3(0, 3.76, 0))
		body.add_child(cs2)
		# guard walk loop on top of the walkways (back, right and left walls)
		var wy := c.y - 0.15 + 7.75
		var loop := []
		for q in [Vector3(-H + 1.7, 0, H - 9.0), Vector3(-H + 1.7, 0, -H + 1.7), Vector3(0, 0, -H + 1.7), Vector3(H - 1.7, 0, -H + 1.7), Vector3(H - 1.7, 0, H - 9.0)]:
			var wp: Vector3 = base * q
			loop.append(Vector3(wp.x, wy, wp.z))
		info.walk_loop = loop
		# gate torches
		for sgn in [-1.0, 1.0]:
			var tp := base * Vector3(sgn * 3.4, 3.2, H + 2.9)
			var tor := Assets.instance_sized(P + "Torch_Metal.gltf", 0.7, "y")
			tor.position = tp
			node.add_child(tor)
			var fl := FireFX.flames(0.12, 0.5)
			fl.position = tp + Vector3(0, 0.62, 0)
			node.add_child(fl)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.6, 0.3)
			l.light_energy = 2.0
			l.omni_range = 10.0
			l.position = tp + Vector3(0, 0.9, 0)
			l.visible = false
			node.add_child(l)
			street_lights.append(l)
		for k in 4:
			var cp: Vector3 = corners[k] * ((H + 2.1) / H)
			ext.add(P + "Banner_1.gltf", base * Transform3D(Basis(Vector3.UP, atan2(cp.x, cp.z)), cp * 1.0 + cp.normalized() * 7.8 + Vector3(0, 11.0, 0)))


func _ruin_remap(ext) -> void:
	if not ext.style_key.ends_with("+fortruin"):
		ext.style_key += "+fortruin"
	if _fort_ruin_remap.is_empty():
		for pn in ["wall_thick_straight_01", "tower_round", "wall_walkway_straight_01"]:
			var part := Assets.part_named(FORT, pn)
			if part.is_empty():
				continue
			var mesh: Mesh = part[0]
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s)
				if m is BaseMaterial3D and not _fort_ruin_remap.has(m.resource_name):
					var d: BaseMaterial3D = m.duplicate()
					d.albedo_color = Color(0.7, 0.72, 0.66)
					_fort_ruin_remap[m.resource_name] = d
	for k in _fort_ruin_remap:
		ext.remap[k] = _fort_ruin_remap[k]


func _portcullis(info: Dictionary, base: Transform3D, lp: Vector3, syaw: float) -> void:
	var pc := Interactables.Portcullis.new()
	pc.settlement = info.name
	pc.transform = base * Transform3D(Basis(Vector3.UP, syaw + PI * 0.5), lp)
	var gate := Node3D.new()
	for part in Assets.parts(GATE):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = Transform3D(Basis().scaled(Vector3(1.48, 1.62, 1.0)), Vector3.ZERO) * part[1]
		gate.add_child(mi)
	pc.add_child(gate)
	pc.gate = gate
	var body := AnimatableBody3D.new()
	body.collision_layer = 1 | 32
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4.4, 4.8, 0.3)
	cs.shape = bx
	cs.position = Vector3(0, 2.4, 0)
	body.add_child(cs)
	pc.add_child(body)
	pc.body = body
	pc.height = 4.6
	(info.node as Node3D).add_child(pc)
	info.portcullis = pc
	portcullises.append(pc)
	_update_portcullis(false)


func _box(body: StaticBody3D, lp: Vector3, size: Vector3, yaw: float) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), lp)
	body.add_child(cs)


func _build_isle_ruin(info: Dictionary, ext, rng: RandomNumberGenerator) -> void:
	_ruin_remap(ext)
	var c: Vector3 = info.center
	var body := StaticBody3D.new()
	body.collision_layer = 1
	(info.node as Node3D).add_child(body)
	var y := WorldData.height_at(c.x, c.z) - 0.2
	var tp := Vector3(c.x + 14, WorldData.height_at(c.x + 14, c.z - 10) - 0.3, c.z - 10)
	_fort(ext, "tower_round", Transform3D(Basis().scaled(Vector3(0.75, 0.55, 0.75)), tp))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 5.7
	cyl.height = 7.4
	cs.shape = cyl
	cs.position = tp + Vector3(0, 3.7, 0)
	body.add_child(cs)
	for k in 3:
		var a := k * 1.9 + 0.4
		var p := Vector3(c.x + sin(a) * 17.0, 0, c.z + cos(a) * 17.0)
		p.y = WorldData.height_at(p.x, p.z) - 0.3
		var basis := Basis(Vector3.UP, a + PI * 0.5).scaled(Vector3(1, rng.randf_range(0.4, 0.8), 1))
		_fort(ext, "wall_thin_straight_04", Transform3D(basis, p))


# ------------------------------------------------------------------ landmarks
func _build_poi(q: Dictionary) -> Dictionary:
	var info := _new_info(q)
	var node := Node3D.new()
	node.name = String(q.name).replace(" ", "_").replace("'", "")
	add_child(node)
	info["node"] = node
	var ext := Builder.Instancer.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(q.name))
	var c := Vector3(float(q.x), float(q.y), float(q.z))
	var yaw := float(q.get("yaw", 0.0))
	var base := Transform3D(Basis(Vector3.UP, yaw), c)
	var climate := WorldData.climate_at(c.x, c.z)
	match String(q.type):
		"watchtower", "tower_ruin":
			var ruin := String(q.type) == "tower_ruin"
			if ruin:
				_ruin_remap(ext)
			var sy := 0.4 if ruin else 0.62
			_fort(ext, "tower_round", base * Transform3D(Basis().scaled(Vector3(0.55, sy, 0.55)), Vector3(0, -0.3, 0)))
			_static_cyl(node, c + Vector3(0, 13.5 * sy * 0.5, 0), 4.2, 13.5 * sy)
			if not ruin:
				var cf: Node3D = preload("res://scripts/world/campfire.gd").new()
				node.add_child(cf)
				cf.global_position = c + base.basis * Vector3(0, 0, 7.5)
				info.hubs = [_add_nav(info, c + base.basis * Vector3(1.5, 0.05, 9.0))]
			else:
				for k in 8:
					ext.add("res://assets/nature/Rock_Medium_%d.gltf" % (1 + k % 3), base * Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.4, 0.9) * Vector3(1, 0.5, 1)), Vector3(rng.randf_range(-7, 7), -0.2, rng.randf_range(-7, 7))))
				_poi_chest(node, base * Vector3(2.0, 0, 5.5), yaw, "ruin", q.name)
		"stone_circle":
			for k in 9:
				var a := k * TAU / 9.0
				var p := Vector3(sin(a) * 9.0, 0, cos(a) * 9.0)
				var gp := base * p
				gp.y = WorldData.height_at(gp.x, gp.z) - 0.3
				ext.add("res://assets/nature/Rock_Medium_%d.gltf" % (1 + k % 3), Transform3D(Basis(Vector3.UP, a).scaled(Vector3(0.42, 1.9, 0.42)), gp))
				_static_cyl(node, gp + Vector3(0, 2.0, 0), 0.8, 4.0)
			ext.add("res://assets/nature/Rock_Medium_2.gltf", base * Transform3D(Basis().scaled(Vector3(0.8, 0.35, 0.6)), Vector3(0, -0.1, 0)))
			_poi_chest(node, base * Vector3(0, 0.62, 0), yaw, "ruin", q.name)
		"bandit_camp":
			var cf: Node3D = preload("res://scripts/world/campfire.gd").new()
			node.add_child(cf)
			cf.global_position = c
			for k in 4:
				var a := k * TAU / 4.0 + 0.3
				var p := Vector3(sin(a) * 6.5, 0, cos(a) * 6.5)
				var gp := base * p
				gp.y = WorldData.height_at(gp.x, gp.z)
				ext.add(P + ("Stall_Empty.gltf" if k % 2 == 0 else "Stall_Cart_Empty.gltf"), Transform3D(Basis(Vector3.UP, yaw + a + PI), gp))
				ext.add(P + "Bag.gltf", Transform3D(Basis(Vector3.UP, a), gp + base.basis * Vector3(0.8, 0, 0.4)))
			for k in 6:
				var gp := base * Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
				gp.y = WorldData.height_at(gp.x, gp.z)
				ext.add(P + ["Crate_Wooden.gltf", "Barrel.gltf", "Bag.gltf"][k % 3], Transform3D(Basis(Vector3.UP, rng.randf() * TAU), gp))
			_poi_chest(node, base * Vector3(-3.0, 0, -8.0), yaw, "bandit", "")
			info.hubs = [_add_nav(info, c + Vector3(2.5, 0.05, 0))]
		"shrine", "cabin":
			var b := {"type": "chapel" if q.type == "shrine" else "cabin", "x": c.x, "z": c.z, "yaw": yaw, "w": 4, "d": 6, "floors": 1}
			var r := Builder.build_building(b, climate, _footprint_height(b) + 0.1, ext, "", rng)
			node.add_child(r.root)
			if r.inn.count > 0:
				var mi := MeshInstance3D.new()
				mi.mesh = r.inn.commit()
				mi.visibility_range_end = 80.0
				node.add_child(mi)
			for l in r.lights:
				lights.append(l)
				if l.has_meta("flicker"):
					flicker.append(l)
			for f in r.fires:
				Game.world_ref.call("register_fire", f)
			_merge_nav(info, r)
			info.buildings.append({"type": b.type, "result": r, "spots": r.spots, "door_out": r.get_meta("door_out_g"), "door": r.door, "center": r.center, "floors": 1, "xform": r.xform, "w": 4, "d": 6})
			info.hubs = [r.get_meta("door_out_g")]
			if q.type == "cabin":
				var fx := Transform3D(Basis(Vector3.UP, yaw), c + base.basis * Vector3(3.4, 0, 0))
				for row in 3:
					for i in 4:
						ext.add(V + "Roof_Log.gltf", fx * Transform3D(Basis().scaled(Vector3(0.34, 0.3, 0.07)), Vector3(-0.7 + i * 0.42 + row * 0.2, 0.2 + row * 0.34, 0)))
		"mine":
			var mp := base * Vector3(0, 0, -6.0)
			ext.add("res://assets/nature/Rock_Medium_1.gltf", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(3.2, 2.8, 2.4)), mp + Vector3(0, -0.6, 0)))
			_static_cyl(node, mp + Vector3(0, 3, 0), 5.5, 6.0)
			for sgn in [-1.0, 1.0]:
				ext.add(V + "Prop_Support.gltf", base * Transform3D(Basis(Vector3.UP, PI * 0.5 * sgn).scaled(Vector3(1, 1.6, 1)), Vector3(sgn * 1.6, 0, -1.2)))
			ext.add(V + "Roof_Log.gltf", base * Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(0.35, 0.35, 0.36)), Vector3(0, 2.75, -1.2)))
			ext.add(V + "Prop_Wagon.gltf", base * Transform3D(Basis(Vector3.UP, 0.3), Vector3(3.5, 0, 2.0)))
			ext.add(P + "Pickaxe_Bronze.gltf", base * Transform3D(Basis(Vector3.FORWARD, 0.4), Vector3(-2.2, 0.5, 1.0)))
			ext.add(P + "Lantern_Wall.gltf", base * Transform3D(Basis(Vector3.UP, PI), Vector3(1.5, 2.0, -1.0)))
			_poi_chest(node, base * Vector3(-2.5, 0, 0.5), yaw, "ruin", "")
		"camp":
			var cf: Node3D = preload("res://scripts/world/campfire.gd").new()
			node.add_child(cf)
			cf.global_position = c
			for k in 5:
				var gp := base * Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
				gp.y = WorldData.height_at(gp.x, gp.z) + 0.25
				ext.add(V + "Roof_Log.gltf", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.45, 0.45, 0.4)), gp))
			ext.add(P + "Axe_Bronze.gltf", base * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(1.6, 0.4, 1.0)))
			info.hubs = [_add_nav(info, c + Vector3(2.0, 0.05, 1.0))]
		"well":
			_build_prop(info, ext, {"type": "well", "x": c.x, "z": c.z, "yaw": yaw}, climate, rng)
	ext.build(node, 2600.0)
	return info


func _static_cyl(node: Node3D, p: Vector3, r: float, h: float) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	b.add_child(cs)
	b.position = p
	node.add_child(b)


func _poi_chest(node: Node3D, p: Vector3, yaw: float, table: String, nm: String) -> void:
	var holder := Builder.Result.new()
	holder.root = node
	holder.xform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, WorldData.height_at(p.x, p.z), p.z))
	holder.inn = Builder.Merger.new()
	Furnish._chest(holder, Vector3.ZERO, 0.0, table, nm, -1)
	var c: Node = holder.spots.chests[0]
	c.transform = holder.xform
	c.owner_name = ""
	var mi := MeshInstance3D.new()
	mi.mesh = holder.inn.commit()
	node.add_child(mi)


# ------------------------------------------------------------------ bridges
func _build_bridge(b: Dictionary) -> void:
	var a := Vector3(b.a[0], b.a[1], b.a[2])
	var e := Vector3(b.b[0], b.b[1], b.b[2])
	var flat := Vector3(e.x - a.x, 0, e.z - a.z)
	var length := flat.length()
	var dir := flat / length
	var yaw := atan2(dir.x, dir.z)
	var ext := Builder.Instancer.new()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var n := int(ceil(length / 2.0))
	var deck := []
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(e, t)
		p.y = lerpf(a.y, e.y, t) + sin(t * PI) * minf(1.6, length * 0.06) + 0.35
		deck.append(p)
	for i in n:
		var p0: Vector3 = deck[i]
		var p1: Vector3 = deck[i + 1]
		var mid := (p0 + p1) * 0.5
		var seg_dir := (p1 - p0).normalized()
		var pitch := asin(clampf(seg_dir.y, -1, 1))
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
		for sx in [-1.0, 1.0]:
			ext.add(V + "Floor_WoodDark.gltf", Transform3D(basis, mid + basis * Vector3(sx, 0.0, 0)))
		ext.add(V + "Prop_WoodenFence_Single.gltf", Transform3D(basis * Basis(Vector3.UP, PI * 0.5), mid + basis * Vector3(2.05, 0, 0)))
		ext.add(V + "Prop_WoodenFence_Single.gltf", Transform3D(basis * Basis(Vector3.UP, PI * 0.5), mid + basis * Vector3(-2.05, 0, 0)))
		if i % 2 == 0:
			for sx in [-1.8, 1.8]:
				var pp := mid + basis * Vector3(sx, 0, 0)
				var g := minf(WorldData.height_at(pp.x, pp.z), WorldData.water_level_at(pp.x, pp.z) - 1.5)
				var hgt := maxf(pp.y - g, 0.5)
				ext.add(V + "Corner_Exterior_Wood.gltf", Transform3D(Basis().scaled(Vector3(1.6, hgt / 3.0, 1.6)), Vector3(pp.x, g, pp.z)))
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(4.2, 0.3, p0.distance_to(p1) + 0.05)
		cs.shape = bx
		cs.transform = Transform3D(basis, mid - basis.y * 0.15)
		body.add_child(cs)
	ext.build(self, 1500.0)
	bridges.append({"a": a, "b": e, "deck": deck})


func bridge_height(p: Vector3) -> float:
	for br in bridges:
		var a: Vector3 = br.a
		var e: Vector3 = br.b
		var ab := Vector2(e.x - a.x, e.z - a.z)
		var ap := Vector2(p.x - a.x, p.z - a.z)
		var t := ap.dot(ab) / ab.length_squared()
		if t < 0.0 or t > 1.0:
			continue
		var closest := Vector2(a.x, a.z) + ab * t
		if closest.distance_to(Vector2(p.x, p.z)) < 2.6:
			var deck: Array = br.deck
			var fi := t * (deck.size() - 1)
			var i := clampi(int(fi), 0, deck.size() - 2)
			return lerpf((deck[i] as Vector3).y, (deck[i + 1] as Vector3).y, fi - i)
	return -INF


# ------------------------------------------------------------------ runtime
func _process(delta: float) -> void:
	var pl: Node3D = Game.player_ref
	if pl == null:
		return
	var p := pl.global_position
	var t := Time.get_ticks_msec() * 0.001
	for l in flicker:
		if l.visible:
			l.light_energy = 2.3 + sin(t * 13.0 + l.position.x) * 0.22 + sin(t * 23.7) * 0.15
	_light_t -= delta
	if _light_t > 0.0:
		return
	_light_t = 0.4
	var t_day := Game.time_of_day()
	var dark := t_day < 6.2 or t_day > 19.6
	for l in lights:
		var d := l.global_position.distance_to(p)
		l.visible = d < 60.0
		l.shadow_enabled = d < 18.0 and l.has_meta("flicker") and not Assets.compat   # (the browser: no lamp shadows)
	for l in street_lights:
		l.visible = dark and l.global_position.distance_to(p) < 130.0


func _update_portcullis(announce: bool) -> void:
	for pc in portcullises:
		var bad := Game.reputation <= -25.0 or Game.is_wanted_in(pc.settlement)
		if bad and not pc.closed:
			pc.set_closed(true)
			if announce and pc.global_position.distance_to(Game.player_ref.global_position) < 200.0:
				Game.notify.emit("The guards of %s lower the portcullis against you!" % pc.settlement, "warn")


func _on_new_day(_d: int) -> void:
	for pc in portcullises:
		if pc.closed and Game.reputation > -25.0 and not Game.is_wanted_in(pc.settlement):
			pc.set_closed(false)
			Game.notify.emit("At dawn, the portcullis of %s is raised once more." % pc.settlement, "info")


## A* over a settlement's navigation graph. Returns world positions.
func find_path(info: Dictionary, from_i: int, to_i: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if from_i < 0 or to_i < 0:
		return out
	if from_i == to_i:
		out.append(info.nav_p[to_i])
		return out
	var P_: Array = info.nav_p
	var L: Array = info.nav_l
	var open := {from_i: true}
	var came := {}
	var g := {from_i: 0.0}
	var f := {from_i: (P_[from_i] as Vector3).distance_to(P_[to_i])}
	var guard := 0
	while not open.is_empty() and guard < 4000:
		guard += 1
		var cur := -1
		var best := INF
		for k in open:
			if float(f[k]) < best:
				best = f[k]
				cur = k
		if cur == to_i:
			break
		open.erase(cur)
		for nb in L[cur]:
			var ng: float = float(g[cur]) + (P_[cur] as Vector3).distance_to(P_[nb])
			if ng < float(g.get(nb, INF)):
				came[nb] = cur
				g[nb] = ng
				f[nb] = ng + (P_[nb] as Vector3).distance_to(P_[to_i])
				open[nb] = true
	if not came.has(to_i):
		return out
	var node := to_i
	var rev := [node]
	while came.has(node):
		node = came[node]
		rev.append(node)
	rev.reverse()
	for i in rev:
		out.append(P_[i])
	return out


func nearest_nav(info: Dictionary, p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in info.nav_p.size():
		var d := (info.nav_p[i] as Vector3).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func get_state() -> Dictionary:
	var d := {}
	for pc in portcullises:
		d[pc.settlement] = pc.closed
	return {"portcullis": d}


func set_state(d: Dictionary) -> void:
	var pcs: Dictionary = d.get("portcullis", {})
	for pc in portcullises:
		if pcs.has(pc.settlement):
			pc.closed = bool(pcs[pc.settlement])
