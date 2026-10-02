extends RefCounted
## What every item looks like as a thing in the world: the inventory icons are rendered from
## these (tools/bake_icons.gd) and dropped items fall into the world as physical objects built
## from them. Most use the kit's own models (tinted where one model stands for several items);
## a few small goods the kits lack are modelled here from simple shapes in the same low-poly style.
##   model  - glTF path        tint  - albedo multiplier      metal / rough - material overrides
##   build  - procedural shape (see _build)
##   size   - longest side in the world, metres                rot   - icon pose (degrees)

const P := "res://assets/props/"
const ICON_COLS := 8
const ICON_PX := 192
const ATLAS := "res://assets/ui/item_icons.png"

const SPECS := {
	"bread": {"build": "bread", "size": 0.32, "rot": [18, -30, 0]},
	"apple": {"build": "apple", "size": 0.09, "rot": [15, 0, 0]},
	"cheese": {"build": "cheese", "size": 0.3, "rot": [28, -25, 0]},
	"carrot": {"model": P + "Carrot.gltf", "tint": [1.0, 0.42, 0.1], "size": 0.2, "rot": [10, 30, -40]},
	"dates": {"build": "dates", "size": 0.22, "rot": [35, 0, 0]},
	"raw_meat": {"build": "haunch", "tint": [0.66, 0.14, 0.12], "size": 0.32, "rot": [25, -35, 0]},
	"cooked_meat": {"build": "haunch", "tint": [0.47, 0.24, 0.09], "size": 0.32, "rot": [25, -35, 0]},
	"raw_fish": {"model": "res://assets/animals/Fish.glb", "size": 0.38, "rot": [10, 70, 0]},
	"cooked_fish": {"model": "res://assets/animals/Fish.glb", "tint": [0.72, 0.45, 0.22], "rough": 0.6, "size": 0.38, "rot": [10, 70, 0]},
	"stew": {"model": P + "Pot_1.gltf", "size": 0.3, "rot": [22, 20, 0]},
	"honey_cake": {"build": "cake", "size": 0.24, "rot": [32, 0, 0]},
	"waterskin": {"model": P + "Bag.gltf", "tint": [0.62, 0.42, 0.26], "size": 0.4, "rot": [8, 25, 0]},
	"ale": {"model": P + "Mug.gltf", "size": 0.16, "rot": [12, 35, 0]},
	"wine": {"model": P + "Bottle_1.gltf", "tint": [0.55, 0.16, 0.2], "size": 0.32, "rot": [8, 20, -10]},
	"spiced_wine": {"model": P + "SmallBottle.gltf", "tint": [0.95, 0.55, 0.2], "size": 0.22, "rot": [8, 20, -10]},
	"milk": {"model": P + "Vase_2.gltf", "tint": [1.0, 0.97, 0.9], "size": 0.3, "rot": [10, 20, 0]},
	"wolf_pelt": {"build": "pelt", "tint": [0.55, 0.53, 0.5], "size": 0.8, "rot": [25, -30, 0]},
	"bear_pelt": {"build": "pelt", "tint": [0.25, 0.17, 0.11], "size": 1.1, "rot": [25, -30, 0]},
	"deer_hide": {"build": "pelt", "tint": [0.66, 0.45, 0.27], "size": 0.8, "rot": [25, -30, 0]},
	"fox_pelt": {"build": "pelt", "tint": [0.82, 0.38, 0.12], "size": 0.65, "rot": [25, -30, 0]},
	"moose_antlers": {"model": "res://assets/animals/moose_antlers.glb", "tint": [0.6, 0.52, 0.4], "size": 1.0, "rot": [25, 0, 0]},
	"feathers": {"build": "feathers", "size": 0.3, "rot": [60, 0, 0]},
	"sealed_parcel": {"build": "parcel", "size": 0.3, "rot": [30, -30, 0]},
	"firewood": {"build": "firewood", "size": 0.6, "rot": [20, -35, 0]},
	"rusty_sword": {"model": P + "Sword_Bronze.gltf", "tint": [0.62, 0.42, 0.3], "metal": 0.35, "rough": 0.8, "size": 0.95, "rot": [0, 0, -45]},
	"iron_sword": {"model": P + "Sword_Bronze.gltf", "tint": [0.62, 0.63, 0.66], "metal": 0.75, "rough": 0.45, "size": 1.0, "rot": [0, 0, -45]},
	"steel_longsword": {"model": P + "Sword_Bronze.gltf", "tint": [0.86, 0.88, 0.92], "metal": 0.95, "rough": 0.22, "size": 1.15, "rot": [0, 0, -45]},
	"knight_sword": {"model": "res://assets/items/antique_estoc/antique_estoc.gltf", "size": 1.15, "rot": [0, 0, -45]},
	"elven_blade": {"model": "res://assets/items/antique_estoc/antique_estoc.gltf", "tint": [1.5, 1.7, 2.1], "metal": 1.0, "rough": 0.1, "size": 1.1, "rot": [0, 0, -45]},
	"wooden_shield": {"model": P + "Shield_Wooden.gltf", "size": 0.7, "rot": [0, 15, 0]},
	"kite_shield": {"model": "res://assets/items/kite_shield/kite_shield.gltf", "size": 0.95, "rot": [0, 15, 0]},
	"wool_cloak": {"model": "res://assets/characters/Male_Ranger_Head_Hood.gltf", "outfit": [0.33, 0.45, 0.85, 0.0], "size": 0.5, "rot": [5, 30, 0]},
	"fur_cloak": {"model": "res://assets/characters/Male_Ranger_Head_Hood.gltf", "outfit": [0.8, 0.55, 0.7, 0.0], "size": 0.5, "rot": [5, 30, 0]},
	"desert_robes": {"model": "res://assets/characters/Male_Peasant_Body.gltf", "outfit": [0.0, 0.2, 1.35, 0.0], "size": 0.75, "rot": [0, 20, 0]},
	"silk_cloak": {"model": "res://assets/characters/Male_Ranger_Head_Hood.gltf", "outfit": [0.7, 1.6, 0.8, 0.0], "size": 0.5, "rot": [5, 30, 0]},
	"leather_armor": {"model": "res://assets/characters/Male_Ranger_Body.gltf", "outfit": [0.0, 0.28, 0.6, 0.0], "size": 0.75, "rot": [0, 20, 0]},
	"chainmail": {"model": "res://assets/characters/Male_Ranger_Body.gltf", "outfit": [0.0, 0.3, 0.6, 0.62], "size": 0.75, "rot": [0, 20, 0]},
	"plate_armor": {"model": "res://assets/characters/Male_Ranger_Body.gltf", "extra": ["res://assets/characters/Male_Ranger_Acc_Pauldron.gltf"], "outfit": [0.0, 0.2, 1.08, 1.0], "size": 0.8, "rot": [0, 20, 0]},
	"torch": {"build": "torch", "size": 0.55, "rot": [0, 0, -35]},
	"bedroll": {"build": "bedroll", "size": 0.75, "rot": [25, -30, 0]},
	"campfire_kit": {"model": "res://assets/items/stone_fire_pit/stone_fire_pit.gltf", "size": 0.6, "rot": [30, 0, 0]},
	"bandage": {"build": "bandage", "size": 0.14, "rot": [30, -30, 0]},
	"healing_draught": {"model": P + "Potion_2.gltf", "tint": [0.62, 1.0, 0.5], "size": 0.2, "rot": [8, 20, 0]},
	"silver_ring": {"build": "ring", "size": 0.03, "rot": [55, 0, 0]},
	"gold_necklace": {"build": "necklace", "size": 0.2, "rot": [65, 0, 0]},
	"ruby": {"build": "gem", "tint": [0.85, 0.05, 0.1], "size": 0.035, "rot": [25, 20, 0]},
	"emerald": {"build": "gem", "tint": [0.05, 0.7, 0.3], "size": 0.035, "rot": [25, 20, 0]},
	"ancient_coin": {"model": P + "Coin.gltf", "tint": [0.85, 0.55, 0.3], "size": 0.04, "rot": [-12, 25, 0]},
	"falcon_charm": {"model": "res://assets/animals/hawk.glb", "tint": [1.0, 0.78, 0.35], "metal": 1.0, "rough": 0.3, "size": 0.09, "rot": [5, 35, 0]},
}

static var _atlas: Texture2D
static var _icons := {}


## The inventory icon for an item (cut from the baked atlas), or null.
static func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var i := SPECS.keys().find(id)
	if i < 0:
		return null
	if _atlas == null:
		if not ResourceLoader.exists(ATLAS):
			return null
		_atlas = load(ATLAS)
	var at := AtlasTexture.new()
	at.atlas = _atlas
	at.region = Rect2((i % ICON_COLS) * ICON_PX, (i / ICON_COLS) * ICON_PX, ICON_PX, ICON_PX)
	_icons[id] = at
	return at


## The item as a 3D object, `size` metres along its longest side (or scaled to `fit` if given).
static func build(id: String, fit := -1.0) -> Node3D:
	var sp: Dictionary = SPECS.get(id, {"build": "parcel", "size": 0.3})
	var size: float = fit if fit > 0.0 else float(sp.get("size", 0.3))
	var root := Node3D.new()
	var body: Node3D
	if sp.has("model") and String(sp.model).begins_with("res://assets/characters/"):
		# outfit pieces share the character skeleton's space: keep them together, unscaled
		body = Node3D.new()
		for path in [String(sp.model)] + Array(sp.get("extra", [])):
			body.add_child((load(path) as PackedScene).instantiate())
		if sp.has("outfit"):
			_outfit(body, sp.outfit)
	elif sp.has("model"):
		body = Assets.instance_sized(String(sp.model), 1.0, "max")
		if sp.has("outfit"):
			_outfit(body, sp.outfit)
		elif sp.has("tint") or sp.has("metal") or sp.has("rough"):
			_retint(body, sp)
	else:
		body = _build(String(sp.build), sp)
	root.add_child(body)
	# normalise to the requested size, centred on the origin
	var bb := _bounds(root)
	var s := size / maxf(maxf(bb.size.x, maxf(bb.size.y, bb.size.z)), 0.0001)
	body.scale *= s
	body.position = body.position * s - bb.get_center() * s
	return root


static func _retint(n: Node, sp: Dictionary) -> void:
	var t: Array = sp.get("tint", [1, 1, 1])
	var tint := Color(t[0], t[1], t[2])
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in m.mesh.get_surface_count():
			var src := m.get_active_material(si)
			if src is BaseMaterial3D:
				var c := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				c.albedo_color = c.albedo_color * tint
				if sp.has("metal"):
					c.metallic = float(sp.metal)
				if sp.has("rough"):
					c.roughness = float(sp.rough)
				m.set_surface_override_material(si, c)


## Garments use the characters' own outfit shader: [hue shift, saturation, value, steel].
static func _outfit(n: Node, o: Array) -> void:
	var shader: Shader = Assets.instanced_shader("res://shaders/outfit.gdshader")
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in m.mesh.get_surface_count():
			var src := m.get_active_material(si) as BaseMaterial3D
			if src == null:
				continue
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			if src.normal_enabled and src.normal_texture:
				sm.set_shader_parameter("use_normal", true)
				sm.set_shader_parameter("normal_tex", src.normal_texture)
			if src.roughness_texture:
				sm.set_shader_parameter("use_orm", true)
				sm.set_shader_parameter("orm_tex", src.roughness_texture)
			sm.set_shader_parameter("base_roughness", src.roughness)
			m.set_surface_override_material(si, sm)
		Assets.set_iparam(m, "hue_shift", float(o[0]))
		Assets.set_iparam(m, "sat_mul", float(o[1]))
		Assets.set_iparam(m, "val_mul", float(o[2]))
		Assets.set_iparam(m, "steel", float(o[3]))


static func _bounds(n: Node3D) -> AABB:
	var bb := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var p: Node = m
		while p != null and p != n:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var a := xf * m.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	return bb


static func _mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	parent.add_child(m)
	return m


static func _sphere(r: float, segs := 24) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = maxi(segs / 2, 4)
	return s


static func _cyl(r: float, h: float, segs := 20, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if top < 0.0 else top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	return c


static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 24
	t.ring_segments = 10
	return t


static func _build(kind: String, sp: Dictionary) -> Node3D:
	var n := Node3D.new()
	var t: Array = sp.get("tint", [1, 1, 1])
	var tint := Color(t[0], t[1], t[2])
	match kind:
		"bread":
			var cap := CapsuleMesh.new()
			cap.radius = 0.5
			cap.height = 2.0
			_mi(n, cap, _mat(Color(0.74, 0.46, 0.2), 0.85), Vector3.ZERO, Vector3(0, 0, 90), Vector3(0.62, 1.0, 0.72))
			for i in 3:
				var b := BoxMesh.new()
				b.size = Vector3(0.08, 0.06, 0.62)
				_mi(n, b, _mat(Color(0.96, 0.84, 0.58), 0.9), Vector3(-0.42 + i * 0.42, 0.3, 0), Vector3(0, 30, 0))
		"apple":
			_mi(n, _sphere(0.5), _mat(Color(0.74, 0.08, 0.06), 0.35), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.88, 1))
			_mi(n, _cyl(0.035, 0.28), _mat(Color(0.3, 0.2, 0.1), 0.8), Vector3(0.02, 0.5, 0), Vector3(0, 0, -12))
			_mi(n, _sphere(0.5, 12), _mat(Color(0.3, 0.55, 0.15), 0.6), Vector3(0.16, 0.56, 0), Vector3(0, 0, -25), Vector3(0.36, 0.05, 0.18))
		"cheese":
			_mi(n, _cyl(0.6, 0.38, 28), _mat(Color(0.93, 0.68, 0.22), 0.55))
			var w := PrismMesh.new()
			w.size = Vector3(0.5, 0.62, 0.32)
			_mi(n, w, _mat(Color(1.0, 0.86, 0.45), 0.6), Vector3(0.62, -0.03, 0.55), Vector3(90, 0, 30))
		"dates":
			_mi(n, _cyl(0.55, 0.06, 28), _mat(Color(0.82, 0.78, 0.7), 0.4), Vector3(0, -0.12, 0))
			var spots := [Vector3(-0.2, 0, -0.12), Vector3(0.18, 0, -0.16), Vector3(-0.05, 0, 0.18), Vector3(0.27, 0, 0.14), Vector3(0.02, 0.13, -0.02)]
			var yaws := [20.0, -35.0, 80.0, 10.0, -60.0]
			for i in spots.size():
				_mi(n, _sphere(0.1, 14), _mat(Color(0.36, 0.16, 0.06).darkened(0.12 * (i % 2)), 0.28), spots[i], Vector3(0, yaws[i], 0), Vector3(1, 0.85, 1.9))
		"haunch":
			_mi(n, _sphere(0.45), _mat(tint, 0.5), Vector3.ZERO, Vector3.ZERO, Vector3(1.45, 0.9, 1.0))
			_mi(n, _cyl(0.075, 0.7), _mat(Color(0.93, 0.89, 0.8), 0.6), Vector3(0.85, 0, 0), Vector3(0, 0, 90))
			for z in [-0.07, 0.07]:
				_mi(n, _sphere(0.1, 12), _mat(Color(0.93, 0.89, 0.8), 0.6), Vector3(1.2, 0, z))
		"cake":
			_mi(n, _cyl(0.72, 0.05, 32), _mat(Color(0.84, 0.8, 0.72), 0.4), Vector3(0, -0.2, 0))
			_mi(n, _cyl(0.5, 0.3, 32, 0.47), _mat(Color(0.66, 0.38, 0.14), 0.8))
			_mi(n, _cyl(0.485, 0.05, 32), _mat(Color(0.95, 0.66, 0.12), 0.08), Vector3(0, 0.16, 0))
			for i in 9:
				var a := i * TAU / 9.0 + 0.2
				_mi(n, _sphere(0.05, 10), _mat(Color(0.95, 0.66, 0.12), 0.08), Vector3(cos(a) * 0.485, 0.1 - (i % 3) * 0.05, sin(a) * 0.485), Vector3.ZERO, Vector3(0.9, 1.8, 0.9))
			_mi(n, _sphere(0.09, 12), _mat(Color(0.9, 0.2, 0.15), 0.3), Vector3(0, 0.24, 0))
		"pelt":
			_mi(n, _cyl(0.32, 1.1), _mat(tint, 1.0), Vector3.ZERO, Vector3(0, 0, 90))
			for x in [-0.32, 0.32]:
				_mi(n, _torus(0.31, 0.37), _mat(Color(0.3, 0.2, 0.12), 0.8), Vector3(x, 0, 0), Vector3(0, 0, 90))
			_mi(n, _cyl(0.25, 0.02), _mat(tint.lerp(Color(0.85, 0.72, 0.55), 0.6), 0.9), Vector3(0.56, 0, 0), Vector3(0, 0, 90))
		"feathers":
			for i in 3:
				var f := Node3D.new()
				f.rotation_degrees = Vector3(0, -25 + i * 25, 0)
				n.add_child(f)
				var col: Color = [Color(0.85, 0.83, 0.78), Color(0.32, 0.29, 0.27), Color(0.62, 0.5, 0.36)][i]
				_mi(f, _sphere(0.5, 16), _mat(col, 0.8), Vector3(0, 0, -0.5), Vector3.ZERO, Vector3(0.2, 0.02, 1.0))
				_mi(f, _cyl(0.014, 1.15), _mat(Color(0.95, 0.92, 0.85), 0.6), Vector3(0, 0.01, -0.45), Vector3(90, 0, 0))
		"parcel":
			var b := BoxMesh.new()
			b.size = Vector3(1.0, 0.45, 0.75)
			_mi(n, b, _mat(Color(0.7, 0.56, 0.38), 0.95))
			for r in [0.0, 90.0]:
				var s := BoxMesh.new()
				s.size = Vector3(1.04, 0.47, 0.06) if r == 0.0 else Vector3(0.06, 0.47, 0.79)
				_mi(n, s, _mat(Color(0.42, 0.3, 0.18), 0.9))
			_mi(n, _cyl(0.12, 0.05, 18), _mat(Color(0.65, 0.06, 0.05), 0.35), Vector3(0, 0.25, 0))
		"firewood":
			var spots := [Vector3(-0.17, 0, 0), Vector3(0.17, 0, 0), Vector3(0, 0.29, 0), Vector3(0, -0.02, 0.0)]
			for i in 3:
				_mi(n, _cyl(0.16, 1.0, 9), _mat(Color(0.36, 0.24, 0.15), 0.95), spots[i], Vector3(90, 0, 0))
				for e in [-0.5, 0.5]:
					_mi(n, _cyl(0.145, 0.01, 9), _mat(Color(0.86, 0.7, 0.48), 0.9), spots[i] + Vector3(0, 0, e), Vector3(90, 0, 0))
		"bedroll":
			_mi(n, _cyl(0.3, 1.0), _mat(Color(0.32, 0.4, 0.27), 0.95), Vector3.ZERO, Vector3(0, 0, 90))
			for x in [-0.3, 0.3]:
				_mi(n, _torus(0.29, 0.34), _mat(Color(0.35, 0.22, 0.12), 0.7), Vector3(x, 0, 0), Vector3(0, 0, 90))
			_mi(n, _cyl(0.24, 0.02), _mat(Color(0.75, 0.62, 0.45), 0.9), Vector3(0.51, 0, 0), Vector3(0, 0, 90))
		"bandage":
			var linen := _mat(Color(0.9, 0.85, 0.74), 0.95)
			_mi(n, _cyl(0.3, 0.26, 28), linen, Vector3.ZERO, Vector3(90, 0, 0))
			for z in [-0.06, 0.06]:
				_mi(n, _torus(0.27, 0.305), _mat(Color(0.8, 0.75, 0.64), 0.95), Vector3(0, 0, z), Vector3(90, 0, 0))
			var tail := BoxMesh.new()
			tail.size = Vector3(0.62, 0.015, 0.24)
			_mi(n, tail, linen, Vector3(0.26, -0.3, 0), Vector3(0, 0, -12))
			_mi(n, _sphere(0.05, 10), _mat(Color(0.6, 0.1, 0.08), 0.6), Vector3(0.42, -0.29, 0.03), Vector3.ZERO, Vector3(1.4, 0.15, 1.0))
		"torch":
			_mi(n, _cyl(0.05, 1.0, 10, 0.06), _mat(Color(0.42, 0.28, 0.16), 0.9), Vector3(0, -0.15, 0))
			_mi(n, _cyl(0.1, 0.26, 12, 0.11), _mat(Color(0.32, 0.24, 0.17), 1.0), Vector3(0, 0.42, 0))
			for y in [0.33, 0.43, 0.52]:
				_mi(n, _torus(0.095, 0.12), _mat(Color(0.5, 0.4, 0.28), 1.0), Vector3(0, y, 0))
			_mi(n, _cyl(0.085, 0.04, 12), _mat(Color(0.08, 0.06, 0.05), 1.0), Vector3(0, 0.56, 0))
		"ring":
			_mi(n, _torus(0.34, 0.44), _mat(Color(0.86, 0.87, 0.9), 0.18, 1.0), Vector3.ZERO, Vector3(90, 0, 0))
			_mi(n, _gem_mesh(), _mat(Color(0.3, 0.45, 0.95), 0.05, 0.3), Vector3(0, 0.48, 0), Vector3.ZERO, Vector3.ONE * 0.16)
		"necklace":
			for i in 17:
				var a := lerpf(0.15, PI - 0.15, i / 16.0)
				_mi(n, _torus(0.035, 0.06), _mat(Color(1.0, 0.76, 0.3), 0.22, 1.0), Vector3(cos(a) * 0.6, 0, sin(a) * 0.6), Vector3(0, -rad_to_deg(a) + (90 if i % 2 == 0 else 0), 90 if i % 2 == 0 else 0))
			_mi(n, _gem_mesh(), _mat(Color(0.8, 0.06, 0.12), 0.05, 0.3), Vector3(0, -0.02, 0.7), Vector3(90, 0, 0), Vector3.ONE * 0.2)
			_mi(n, _torus(0.07, 0.1), _mat(Color(1.0, 0.76, 0.3), 0.22, 1.0), Vector3(0, 0, 0.6), Vector3(0, 90, 0))
		"gem":
			var g := _mat(tint, 0.04, 0.2)
			g.clearcoat_enabled = true
			g.emission_enabled = true
			g.emission = tint * 0.25
			_mi(n, _gem_mesh(), g)
	return n


## A brilliant-cut gem: an eight-sided crown over a pointed pavilion.
static func _gem_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := 8
	var table := 0.55
	var girdle := 1.0
	for i in k:
		var a0 := i * TAU / k
		var a1 := (i + 1) * TAU / k
		var t0 := Vector3(cos(a0) * table, 0.45, sin(a0) * table)
		var t1 := Vector3(cos(a1) * table, 0.45, sin(a1) * table)
		var g0 := Vector3(cos(a0) * girdle, 0.1, sin(a0) * girdle)
		var g1 := Vector3(cos(a1) * girdle, 0.1, sin(a1) * girdle)
		var tip := Vector3(0, -0.9, 0)
		var top := Vector3(0, 0.45, 0)
		for tri in [[top, t1, t0], [t0, t1, g1], [t0, g1, g0], [g0, g1, tip]]:
			# Godot's front faces wind clockwise seen from outside; normals point outward
			var cr: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0])
			var c: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
			var out := cr.dot(c) > 0.0
			var verts: Array = [tri[0], tri[2], tri[1]] if out else tri
			var nrm := cr.normalized() * (1.0 if out else -1.0)
			for v in verts:
				st.set_normal(nrm)
				st.add_vertex(v)
	return st.commit()
