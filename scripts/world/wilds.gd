extends Node3D
## The wilds between the settlements: about ninety small places to stumble on (hunters' camps,
## wrecked wagons, standing stones, wolf dens, fallen walls, old graves and wayside shrines),
## each with something to find, plus signposts where the roads leave settlements. They are placed
## deterministically (the same island every game) and only built while the player is near.

const P := "res://assets/props/"
const V := "res://assets/village/"
const N := "res://assets/nature/"
const IM := preload("res://scripts/core/item_models.gd")
const COUNT := 90
const LABEL := {"camp": "Camp", "wagon": "Wrecked wagon", "stones": "Standing stones", "den": "Beast's den", "ruin": "Ruin",
	"graves": "Old graves", "shrine": "Wayside shrine"}
## Which kinds turn up in each biome (by WorldData.Biome), with weights.
const BY_BIOME := {
	3: {"camp": 3.0, "den": 2.2, "stones": 1.4, "graves": 1.0, "ruin": 1.0, "shrine": 1.5},
	2: {"camp": 1.5, "stones": 2.0, "graves": 1.5, "ruin": 1.6, "shrine": 1.5, "den": 0.6},
	4: {"camp": 2.0, "den": 2.5, "stones": 1.0, "ruin": 1.0, "graves": 1.0},
	6: {"den": 2.0, "stones": 1.0, "ruin": 1.0},
	5: {"den": 2.0, "ruin": 2.0, "shrine": 1.5, "stones": 1.0, "camp": 1.0},
	7: {"ruin": 2.5, "graves": 1.5, "camp": 1.0, "shrine": 1.0},
	1: {"camp": 1.0, "graves": 1.0, "ruin": 1.0},
}
const PRE := ["Raven", "Briar", "Grey", "Elder", "Fern", "Hart", "Wren", "Ash", "Oak", "Thorn", "Mist", "Stag", "Wolf", "Moss", "Holly",
	"Alder", "Bracken", "Hazel", "Rowan", "Sedge", "Crow", "Bramble", "Cold", "Still", "Hollow", "Black", "White", "Red", "Old", "Long"]
const SUF := ["hollow", "dell", "ford", "mere", "wood", "glen", "combe", "ridge", "fen", "howe", "brook", "holt", "ley", "stead", "moor", "cliff"]
const LOOT := {
	"camp": [["cooked_meat", 0.6, 1, 3], ["deer_hide", 0.5, 1, 2], ["wolf_pelt", 0.3, 1, 1], ["torch", 0.5, 1, 2], ["bandage", 0.4, 1, 2], ["firewood", 0.5, 2, 5]],
	"wagon": [["wine", 0.5, 1, 2], ["cheese", 0.5, 1, 2], ["bread", 0.6, 1, 3], ["iron_sword", 0.15, 1, 1], ["wool_cloak", 0.2, 1, 1], ["silver_ring", 0.25, 1, 1]],
	"den": [["ancient_coin", 0.5, 1, 3], ["silver_ring", 0.35, 1, 1], ["iron_sword", 0.2, 1, 1], ["leather_armor", 0.12, 1, 1], ["healing_draught", 0.3, 1, 1]],
	"ruin": [["ancient_coin", 0.7, 1, 4], ["ruby", 0.2, 1, 1], ["emerald", 0.15, 1, 1], ["steel_longsword", 0.12, 1, 1], ["gold_necklace", 0.2, 1, 1], ["healing_draught", 0.4, 1, 2]],
	"graves": [["ancient_coin", 0.8, 1, 4], ["gold_necklace", 0.15, 1, 1], ["silver_ring", 0.3, 1, 1], ["ruby", 0.08, 1, 1], ["emerald", 0.08, 1, 1]],
	"shrine": [["healing_draught", 0.6, 1, 1], ["bandage", 0.6, 1, 2]],
}
const SILVER := {"camp": [4, 30], "wagon": [20, 80], "den": [10, 60], "ruin": [30, 150], "graves": [10, 50], "shrine": [0, 15]}

static var _plan: Array = []
var sites: Array = []     # the plan plus runtime state: node, found
var signs: Array = []
var _t := 0.0
var _mats := {}


## Where everything goes (computed once, before the vegetation clears ground for it).
static func plan() -> Array:
	if not _plan.is_empty():
		return _plan
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	var out := []
	var used := {}
	# a handful of wagons wrecked beside the roads
	var roads: Array = WorldData.info.get("roads", [])
	for i in 14:
		if roads.is_empty():
			break
		var r: Dictionary = roads[rng.randi() % roads.size()]
		var pts: Array = r.pts
		if pts.size() < 40:
			continue
		var k := rng.randi_range(15, pts.size() - 15)
		var a: Array = pts[k]
		var b: Array = pts[mini(k + 3, pts.size() - 1)]
		var dir := Vector2(float(b[0]) - float(a[0]), float(b[2]) - float(a[2])).normalized()
		var side := Vector2(-dir.y, dir.x) * (7.0 if rng.randf() < 0.5 else -7.0)
		var x := float(a[0]) + side.x
		var z := float(a[2]) + side.y
		if _blocked(x, z, out, 420.0):
			continue
		out.append(_site("wagon", x, z, atan2(dir.x, dir.y), rng, used))
	var tries := 0
	while out.size() < COUNT and tries < 9000:
		tries += 1
		var x := rng.randf_range(-WorldData.HALF + 160.0, WorldData.HALF - 160.0)
		var z := rng.randf_range(-WorldData.HALF + 160.0, WorldData.HALF - 160.0)
		if not WorldData.is_inside_map(x, z) or WorldData.water_depth_at(x, z) > -0.8 or WorldData.normal_at(x, z).y < 0.9:
			continue
		if _blocked(x, z, out, 360.0):
			continue
		var table: Dictionary = BY_BIOME.get(WorldData.biome_at(x, z), {})
		if table.is_empty():
			continue
		var total := 0.0
		for k in table:
			total += float(table[k])
		var pick := rng.randf() * total
		var kind := ""
		for k in table:
			pick -= float(table[k])
			if pick <= 0.0:
				kind = k
				break
		if kind != "":
			out.append(_site(kind, x, z, rng.randf() * TAU, rng, used))
	_plan = out
	return _plan


static func _site(kind: String, x: float, z: float, yaw: float, rng: RandomNumberGenerator, used: Dictionary) -> Dictionary:
	var nm := ""
	for i in 20:
		nm = PRE[rng.randi() % PRE.size()] + SUF[rng.randi() % SUF.size()]
		if not used.has(nm):
			break
	used[nm] = true
	var title: String = {"camp": "%s Camp", "wagon": "Wreck at %s", "stones": "%s Stones", "den": "%s Den", "ruin": "%s Ruin", "graves": "%s Barrows", "shrine": "%s Shrine"}[kind] % nm
	return {"kind": kind, "name": title, "x": x, "z": z, "yaw": yaw, "seed": rng.randi(), "r": 9.0 if kind in ["ruin", "stones", "camp"] else 7.0}


static func _blocked(x: float, z: float, others: Array, gap: float) -> bool:
	for s in WorldData.settlements:
		if Vector2(float(s.x) - x, float(s.z) - z).length() < float(s.radius) + 200.0:
			return true
	for q in WorldData.pois:
		if Vector2(float(q.x) - x, float(q.z) - z).length() < 220.0:
			return true
	for o in others:
		if Vector2(float(o.x) - x, float(o.z) - z).length() < gap:
			return true
	return false


func setup() -> void:
	for s in plan():
		var d: Dictionary = s.duplicate()
		d["node"] = null
		d["found"] = Game.discovered.has(String(s.name))
		sites.append(d)
	_place_signs()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.4
	var pl: Node3D = Game.player_ref
	if pl == null:
		return
	var p := pl.global_position
	var built := false
	for s in sites:
		var d := Vector2(float(s.x) - p.x, float(s.z) - p.z).length()
		if s.node == null and d < 280.0 and not built:
			s.node = _build_site(s)
			built = true          # one a tick: no hitches
		elif s.node != null and d > 360.0:
			(s.node as Node).queue_free()
			s.node = null
		if not s.found and d < 34.0:
			_discover(s)
	for g in signs:
		var d := Vector2(float(g.x) - p.x, float(g.z) - p.z).length()
		if g.node == null and d < 220.0 and not built:
			g.node = _build_sign(g)
			built = true
		elif g.node != null and d > 300.0:
			(g.node as Node).queue_free()
			g.node = null


func _discover(s: Dictionary) -> void:
	s.found = true
	if Game.discover(String(s.name)):
		Game.change_reputation(0.5)
		if Game.world_ref and Game.world_ref.hud:
			Game.world_ref.hud.call("show_banner", String(s.name), "Discovered: " + String(LABEL[s.kind]))


## The nearest site you haven't found yet within `r` (for the compass's "?" hints), or {}.
func unfound_near(p: Vector3, r: float) -> Array:
	var out := []
	for s in sites:
		if not s.found and Vector2(float(s.x) - p.x, float(s.z) - p.z).length() < r:
			out.append(s)
	return out


# ------------------------------------------------------------------ building
func _ground(x: float, z: float) -> float:
	return WorldData.height_at(x, z)


func _put(root: Node3D, path: String, lp: Vector2, yaw: float, size: float, axis := "y", sink := 0.0, tilt := Vector3.ZERO) -> Node3D:
	var n := Assets.instance_sized(path, size, axis)
	root.add_child(n)
	var w := root.global_transform * Vector3(lp.x, 0, lp.y)
	n.global_position = Vector3(w.x, _ground(w.x, w.z) - sink, w.z)
	n.rotation = Vector3(tilt.x, yaw, tilt.z)
	return n


func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var k := c.to_html()
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[k] = m
	return _mats[k]


func _box(body: StaticBody3D, root: Node3D, lp: Vector2, size: Vector3, yaw := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	body.add_child(cs)
	var w := root.global_transform * Vector3(lp.x, 0, lp.y)
	cs.global_transform = Transform3D(Basis(Vector3.UP, root.rotation.y + yaw), Vector3(w.x, _ground(w.x, w.z) + size.y * 0.5, w.z))


func _chest(root: Node3D, s: Dictionary, lp: Vector2, yaw: float, model := "Chest_Wood.gltf", size := 0.75) -> void:
	_put(root, P + model, lp, yaw, size)
	var c := Interactables.Chest.new()
	c.collision_layer = 1 | 32
	c.collision_mask = 0
	c.chest_id = "wild_" + String(s.name)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s.seed)
	for e in LOOT.get(s.kind, []):
		if rng.randf() < float(e[1]):
			c.loot[e[0]] = rng.randi_range(int(e[2]), int(e[3]))
	var sv: Array = SILVER.get(s.kind, [0, 10])
	c.silver = rng.randi_range(int(sv[0]), int(sv[1]))
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.0, 0.7, 0.7) * (size / 0.75)
	cs.shape = bx
	cs.position = Vector3(0, 0.35, 0)
	c.add_child(cs)
	root.add_child(c)
	var w := root.global_transform * Vector3(lp.x, 0, lp.y)
	c.global_position = Vector3(w.x, _ground(w.x, w.z), w.z)
	c.rotation.y = root.rotation.y + yaw


func _build_site(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(float(s.x), _ground(float(s.x), float(s.z)), float(s.z))
	root.rotation.y = float(s.yaw)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s.seed)
	match String(s.kind):
		"camp":
			var fire: Node3D = preload("res://scripts/world/campfire.gd").new()
			root.add_child(fire)
			fire.global_position = root.global_position
			for i in 2:
				var roll := IM.build("bedroll", 1.7)
				root.add_child(roll)
				var a := 0.9 + i * 1.5
				var w := root.global_transform * Vector3(cos(a) * 2.6, 0, sin(a) * 2.6)
				roll.global_position = Vector3(w.x, _ground(w.x, w.z) + 0.2, w.z)
				roll.rotation.y = -a
			_lean_to(root, Vector2(-0.6, 5.0))
			_put(root, P + "Barrel.gltf", Vector2(3.2, -1.8), 0.4, 0.9)
			_put(root, P + "Crate_Wooden.gltf", Vector2(2.4, -3.0), 0.2, 0.6)
			_put(root, P + "Pot_1.gltf", Vector2(0.9, 0.9), 0.0, 0.3)
			for i in 2:
				var pelt := IM.build(["deer_hide", "wolf_pelt"][i], 0.9)
				root.add_child(pelt)
				var w := root.global_transform * Vector3(-3.0 + i * 0.4, 0, -1.6 - i * 0.7)
				pelt.global_position = Vector3(w.x, _ground(w.x, w.z) + 0.16, w.z)
				pelt.rotation.y = rng.randf() * TAU
			_chest(root, s, Vector2(-2.4, 2.8), 0.6)
			_box(body, root, Vector2(3.2, -1.8), Vector3(0.7, 0.9, 0.7))
		"wagon":
			_put(root, V + "Prop_Wagon.gltf", Vector2.ZERO, 0.0, 3.6, "xz", 0.25, Vector3(0, 0, 0.22))
			_put(root, P + "Crate_Wooden.gltf", Vector2(2.2, 1.0), 0.6, 0.6, "y", 0.0, Vector3(0.3, 0, 0))
			_put(root, P + "Crate_Wooden.gltf", Vector2(2.8, -0.4), 1.2, 0.55)
			_put(root, P + "Barrel.gltf", Vector2(-2.4, 1.6), 0.0, 0.85, "y", 0.0, Vector3(PI * 0.5, 0, 0))
			_put(root, P + "Bag.gltf", Vector2(1.6, 2.2), 0.4, 0.45)
			_chest(root, s, Vector2(-1.2, -2.0), 2.6)
			_box(body, root, Vector2.ZERO, Vector3(1.6, 1.4, 3.4))
		"stones":
			var n := rng.randi_range(6, 8)
			for i in n:
				var a := i * TAU / n
				var st := _put(root, N + "Rock_Medium_%d.gltf" % (1 + i % 3), Vector2(cos(a), sin(a)) * 6.0, rng.randf() * TAU, 1.0, "y", 0.3)
				st.scale = Vector3(1.0, rng.randf_range(2.4, 3.4), 1.0)
				_box(body, root, Vector2(cos(a), sin(a)) * 6.0, Vector3(0.9, 2.6, 0.9))
			var altar := _put(root, N + "Rock_Medium_2.gltf", Vector2.ZERO, 0.0, 0.7, "y", 0.1)
			altar.scale = Vector3(1.6, 0.8, 1.2)
			var candle := _put(root, P + "CandleStick.gltf", Vector2(0.4, 0.2), 0.0, 0.3)
			candle.position.y += 0.55
			_blessing(root, s, "[E] Lay a hand on the altar stone", Vector2.ZERO)
		"den":
			for i in 5:
				var a := i * TAU / 5.0 + rng.randf() * 0.4
				_put(root, N + "Rock_Medium_%d.gltf" % (1 + i % 3), Vector2(cos(a), sin(a)) * rng.randf_range(4.0, 6.0), rng.randf() * TAU, rng.randf_range(1.4, 2.4), "y", 0.4)
			for i in 6:
				var b := MeshInstance3D.new()
				var c := CylinderMesh.new()
				c.top_radius = 0.025
				c.bottom_radius = 0.03
				c.height = rng.randf_range(0.3, 0.55)
				b.mesh = c
				b.material_override = _mat(Color(0.88, 0.84, 0.74), 0.7)
				root.add_child(b)
				var w := root.global_transform * Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
				b.global_position = Vector3(w.x, _ground(w.x, w.z) + 0.03, w.z)
				b.rotation = Vector3(PI * 0.5, rng.randf() * TAU, 0)
			_chest(root, s, Vector2(1.4, -1.0), 0.8, "Pouch_Large.gltf", 0.45)
			if Game.world_ref and Game.world_ref.wildlife and not Game.looted.has("wild_" + String(s.name)):
				var sp := "bear" if rng.randf() < 0.3 else "wolf"
				Game.world_ref.wildlife.call("_spawn_group", sp, root.global_position + Vector3(3, 0, 3))
		"ruin":
			# a roofless stone house, its walls broken off at different heights
			var segs := [
				["Wall_UnevenBrick_Straight", Vector2(-3, -3), 0.0, 1.0], ["Wall_UnevenBrick_Window_Wide_Round", Vector2(-1, -3), 0.0, 0.92],
				["Wall_UnevenBrick_Straight", Vector2(1, -3), 0.0, 0.55], ["Wall_UnevenBrick_Straight", Vector2(3, -3), 0.0, 0.3],
				["Wall_UnevenBrick_Straight", Vector2(-4, -2), PI * 0.5, 0.85], ["Wall_UnevenBrick_Window_Wide_Round", Vector2(-4, 0), PI * 0.5, 0.7],
				["Wall_UnevenBrick_Straight", Vector2(-4, 2), PI * 0.5, 0.35], ["Wall_UnevenBrick_Door_Round", Vector2(4, -2), PI * 0.5, 0.8],
				["Wall_UnevenBrick_Straight", Vector2(4, 0), PI * 0.5, 0.45], ["Wall_UnevenBrick_Straight", Vector2(-3, 3), 0.0, 0.22],
			]
			for sg in segs:
				var piece := _put(root, V + String(sg[0]) + ".gltf", sg[1], sg[2], 2.0, "xz", 0.15)
				piece.scale.y *= float(sg[3])
				_box(body, root, sg[1], Vector3(2.0, 3.0 * float(sg[3]), 0.5), sg[2])
			for i in 14:
				var rp := Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-3.5, 4.5))
				if i % 3 == 0:
					_put(root, N + "Rock_Medium_%d.gltf" % (1 + i % 3), rp, rng.randf() * TAU, rng.randf_range(0.3, 0.6), "y", 0.1)
				else:
					_put(root, V + "Prop_Brick%d.gltf" % (1 + i % 4), rp, rng.randf() * TAU, 0.28, "xz")
			_put(root, P + "Vase_Rubble_Medium.gltf", Vector2(2.6, 1.8), 0.3, 0.5)
			_put(root, V + "Prop_Vine2.gltf", Vector2(-2.0, -2.75), 0.0, 2.4)
			_put(root, V + "Prop_Vine5.gltf", Vector2(-3.75, 0.5), PI * 0.5, 2.0)
			_chest(root, s, Vector2(-2.4, -1.8), 0.4)
		"graves":
			for i in rng.randi_range(3, 5):
				var gp := Vector2(-3.0 + i * 1.8, rng.randf_range(-0.5, 0.5))
				var mound := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.8
				sm.height = 0.7
				mound.mesh = sm
				mound.material_override = _mat(Color(0.3, 0.25, 0.18), 1.0)
				root.add_child(mound)
				var w := root.global_transform * Vector3(gp.x, 0, gp.y)
				mound.global_position = Vector3(w.x, _ground(w.x, w.z) - 0.1, w.z)
				mound.scale = Vector3(0.75, 1.0, 1.6)
				mound.rotation.y = root.rotation.y
				var stone := _put(root, N + "Rock_Medium_1.gltf", gp + Vector2(0, -1.5), rng.randf_range(-0.2, 0.2), 0.9, "y", 0.15, Vector3(rng.randf_range(-0.15, 0.15), 0, 0))
				stone.scale = Vector3(0.6, 1.0, 0.35)
			_put(root, P + "Lantern_Wall.gltf", Vector2(4.0, -1.2), 0.0, 0.4)
			_chest(root, s, Vector2(0.4, 2.2), 3.1)
		"shrine":
			# a weathered stone saint, hand raised in blessing, on a boulder plinth
			var plinth := _put(root, N + "Rock_Medium_2.gltf", Vector2(0, -1.0), 0.0, 0.8, "y", 0.25)
			plinth.scale = Vector3(1.5, 1.0, 1.3)
			var saint := CharacterModel.new()
			root.add_child(saint)
			saint.build({"gender": "f" if rng.randf() < 0.5 else "m", "outfit": "Peasant", "hood": true})
			var sw := root.global_transform * Vector3(0, 0, -1.0)
			saint.global_position = Vector3(sw.x, _ground(sw.x, sw.z) + 0.45, sw.z)
			saint.rotation.y = root.rotation.y
			saint.scale = Vector3.ONE * 1.15
			var stone: Material = preload("res://scripts/world/settlements.gd")._statue_stone()
			for gi in saint.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).material_override = stone
			saint.freeze_end.call_deferred("Spell_Simple_Idle")
			_box(body, root, Vector2(0, -1.0), Vector3(1.4, 2.6, 1.2))
			_put(root, P + "BookStand.gltf", Vector2(0, 0.6), 0.0, 1.1)
			_put(root, P + "CandleStick_Triple.gltf", Vector2(1.0, 0.3), 0.0, 0.5)
			_put(root, P + "CandleStick_Stand.gltf", Vector2(-1.0, 0.3), 0.0, 1.2)
			_put(root, P + "Banner_2.gltf", Vector2(-1.9, -1.5), 0.0, 2.6)
			_put(root, P + "Chalice.gltf", Vector2(0.6, -0.6), 0.0, 0.22)
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.75, 0.45)
			lamp.light_energy = 1.4
			lamp.omni_range = 6.0
			root.add_child(lamp)
			lamp.global_position = root.global_position + Vector3(0, 1.3, 0)
			_blessing(root, s, "[E] Pray at the shrine", Vector2(0, 0.9))
			_chest(root, s, Vector2(1.8, -1.4), 0.2, "Chest_Wood.gltf", 0.6)
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 300.0
	return root


## A canvas lean-to on two poles.
func _lean_to(root: Node3D, lp: Vector2) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var w := root.global_transform * Vector3(lp.x, 0, lp.y)
	holder.global_position = Vector3(w.x, _ground(w.x, w.z), w.z)
	holder.rotation.y = root.rotation.y
	var tarp := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(3.2, 0.03, 2.6)
	tarp.mesh = b
	tarp.material_override = _mat(Color(0.8, 0.73, 0.58), 0.95)
	tarp.position = Vector3(0, 0.9, 0)
	tarp.rotation.x = 0.67           # high side toward the fire, back edge on the ground
	holder.add_child(tarp)
	for x in [-1.5, 1.5]:
		var pole := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.04
		c.bottom_radius = 0.05
		c.height = 1.85
		pole.mesh = c
		pole.material_override = _mat(Color(0.38, 0.26, 0.16))
		pole.position = Vector3(x, 0.92, -1.02)
		holder.add_child(pole)


class Blessing extends StaticBody3D:
	var key := ""
	var text := ""
	func get_interaction(_p) -> String:
		return text if not Game.looted.has(key + str(Game.day())) else "You have prayed here today."
	func interact(_p) -> void:
		if Game.looted.has(key + str(Game.day())):
			return
		Game.looted[key + str(Game.day())] = true
		Game.change_stat("health", 40.0)
		Game.change_stat("stamina", 100.0)
		Game.change_reputation(0.5)
		Game.notify.emit("A calm settles over you. Your wounds ease and your strength returns.", "rep")
		Audio.ui("open")


func _blessing(root: Node3D, s: Dictionary, text: String, lp: Vector2) -> void:
	var b := Blessing.new()
	b.collision_layer = 1 | 32
	b.collision_mask = 0
	b.key = "bless_" + String(s.name) + "_"
	b.text = text
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.1, 1.1, 1.1)
	cs.shape = bx
	cs.position.y = 0.55
	b.add_child(cs)
	root.add_child(b)
	var w := root.global_transform * Vector3(lp.x, 0, lp.y)
	b.global_position = Vector3(w.x, _ground(w.x, w.z), w.z)


# ------------------------------------------------------------------ signposts
## Where each road leaves a settlement (or a landmark) a signpost names where it leads.
func _place_signs() -> void:
	for r in WorldData.info.get("roads", []):
		var pts: Array = r.pts
		if pts.size() < 6:
			continue
		var length := 0.0
		for i in range(1, pts.size()):
			length += Vector2(float(pts[i][0]) - float(pts[i - 1][0]), float(pts[i][2]) - float(pts[i - 1][2])).length()
		for end in 2:
			var here := String(r.a if end == 0 else r.b)
			var there := String(r.b if end == 0 else r.a)
			var c := _place_center(here)
			if c.z < 0.0:
				continue
			var walked := 0.0
			var idx := range(pts.size()) if end == 0 else range(pts.size() - 1, -1, -1)
			var prev: Array = pts[idx[0]]
			for i in idx:
				var q: Array = pts[i]
				walked += Vector2(float(q[0]) - float(prev[0]), float(q[2]) - float(prev[2])).length()
				prev = q
				if Vector2(float(q[0]) - c.x, float(q[2]) - c.y).length() > c.z:
					var j: int = clampi(i + (3 if end == 0 else -3), 0, pts.size() - 1)
					var dir := Vector2(float(pts[j][0]) - float(q[0]), float(pts[j][2]) - float(q[2])).normalized()
					var side := Vector2(-dir.y, dir.x) * 3.2
					signs.append({"x": float(q[0]) + side.x, "z": float(q[2]) + side.y, "dir": dir, "text": there, "km": maxf(length - walked, 0.0) / 1000.0, "node": null})
					break


func _place_center(n: String) -> Vector3:
	var s := WorldData.settlement_by_name(n)
	if not s.is_empty():
		return Vector3(float(s.x), float(s.z), float(s.radius) + 14.0)
	for q in WorldData.pois:
		if q.name == n:
			return Vector3(float(q.x), float(q.z), 26.0)
	return Vector3(0, 0, -1)


func _build_sign(g: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(float(g.x), _ground(float(g.x), float(g.z)), float(g.z))
	var dir: Vector2 = g.dir
	var wood := _mat(Color(0.42, 0.29, 0.18))
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.14, 2.5, 0.14)
	post.mesh = pm
	post.material_override = wood
	post.position.y = 1.2
	root.add_child(post)
	# the arm points down the road toward the place it names
	var arm := Node3D.new()
	arm.position.y = 2.05
	arm.rotation.y = atan2(dir.x, dir.y) - PI * 0.5
	root.add_child(arm)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.55, 0.34, 0.05)
	board.mesh = bm
	board.material_override = _mat(Color(0.72, 0.56, 0.36))
	board.position.x = 0.85
	arm.add_child(board)
	var tip := MeshInstance3D.new()
	var tm := PrismMesh.new()
	tm.size = Vector3(0.34, 0.24, 0.05)
	tip.mesh = tm
	tip.material_override = board.material_override
	tip.position.x = 1.74
	tip.rotation.z = -PI * 0.5
	arm.add_child(tip)
	var txt := "%s  %s" % [g.text, ("%.1f km" % g.km) if g.km >= 1.0 else "%d m" % int(g.km * 1000.0)]
	for face in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = txt
		l.font = UITheme.font("fell")
		l.font_size = 56
		l.pixel_size = 0.0036
		l.modulate = Color(0.12, 0.07, 0.03)
		l.outline_size = 0
		l.double_sided = false
		l.position = Vector3(0.85, 0, 0.032 * face)
		l.rotation.y = 0.0 if face > 0.0 else PI
		arm.add_child(l)
		var w: float = l.font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x * l.pixel_size
		if w > 1.45:
			l.pixel_size *= 1.45 / w
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.2, 2.5, 0.2)
	cs.shape = bx
	cs.position.y = 1.25
	body.add_child(cs)
	root.add_child(body)
	return root
