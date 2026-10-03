extends Node3D
## Spawns and despawns wildlife around the player by biome and time of day: herds,
## packs, solitary beasts, water birds, flocks, migrating geese, fish and livestock.

const SPECIES := {
	"deer": {"path": "Deer.glb", "len": 1.75, "hp": 45, "speed": 9.5, "walk": 1.3, "flee": 30.0, "loot": {"raw_meat": 2, "deer_hide": 1}, "group": [3, 6], "kind": "prey"},
	"stag": {"path": "Stag.glb", "len": 2.1, "hp": 65, "speed": 10.0, "walk": 1.3, "flee": 32.0, "loot": {"raw_meat": 3, "deer_hide": 1}, "group": [1, 3], "kind": "prey"},
	"fox": {"path": "Fox.glb", "len": 1.05, "hp": 22, "speed": 8.5, "walk": 1.2, "flee": 24.0, "loot": {"fox_pelt": 1}, "group": [1, 1], "kind": "prey"},
	"wolf": {"path": "Wolf.glb", "len": 1.6, "hp": 55, "speed": 9.2, "walk": 1.5, "aggro": 19.0, "dmg": 9.0, "loot": {"wolf_pelt": 1, "raw_meat": 1}, "group": [3, 5], "kind": "predator"},
	"bear": {"path": "bear_black.glb", "len": 2.2, "hp": 170, "speed": 8.0, "walk": 1.1, "aggro": 12.0, "dmg": 24.0, "loot": {"bear_pelt": 1, "raw_meat": 4}, "group": [1, 1], "kind": "predator"},
	"moose": {"path": "elk.glb", "len": 3.0, "hp": 130, "speed": 8.0, "walk": 1.1, "flee": 16.0, "charge": 7.0, "dmg": 18.0, "loot": {"raw_meat": 4, "moose_antlers": 1}, "group": [1, 2], "kind": "prey", "moose": true},
	"wild_horse": {"path": "Horse.glb", "len": 2.35, "hp": 90, "speed": 13.0, "walk": 1.4, "flee": 38.0, "loot": {"raw_meat": 4, "deer_hide": 2}, "group": [3, 7], "kind": "prey"},
	"hawk": {"path": "gull_flying.glb", "len": 1.25, "hp": 5, "speed": 8.0, "walk": 1.0, "loot": {"feathers": 2}, "group": [1, 2], "kind": "bird"},
	"alpaca": {"path": "Alpaca.glb", "len": 1.7, "hp": 50, "speed": 7.0, "walk": 1.1, "flee": 20.0, "loot": {"raw_meat": 2}, "group": [3, 6], "kind": "prey"},
	"duck": {"path": "duck_mallard.glb", "len": 0.5, "hp": 8, "speed": 9.0, "walk": 0.5, "loot": {"raw_meat": 1, "feathers": 1}, "group": [3, 7], "kind": "water"},
	"goose": {"path": "goose.glb", "len": 0.85, "hp": 12, "speed": 9.0, "walk": 0.5, "loot": {"raw_meat": 1, "feathers": 2}, "group": [3, 6], "kind": "water"},
	"crow": {"path": "crow.glb", "len": 0.5, "hp": 5, "speed": 8.0, "walk": 1.0, "loot": {"feathers": 1}, "group": [5, 9], "kind": "bird"},
	"gull": {"path": "gull_flying.glb", "len": 0.9, "hp": 5, "speed": 8.0, "walk": 1.0, "loot": {"feathers": 1}, "group": [4, 7], "kind": "bird"},
	"goose_flight": {"path": "gull_flying.glb", "len": 1.1, "hp": 5, "speed": 12.0, "walk": 1.0, "loot": {"feathers": 1}, "group": [9, 13], "kind": "bird"},
	"fish": {"path": "Fish.glb", "len": 0.45, "hp": 4, "speed": 3.0, "walk": 0.8, "loot": {"raw_fish": 1}, "group": [4, 8], "kind": "fish"},
	"cow": {"path": "Cow.glb", "len": 2.3, "hp": 80, "speed": 4.0, "walk": 0.8, "flee": 6.0, "loot": {"raw_meat": 4}, "group": [1, 1], "kind": "farm"},
	"bull": {"path": "Bull.glb", "len": 2.5, "hp": 100, "speed": 5.0, "walk": 0.8, "flee": 5.0, "loot": {"raw_meat": 5}, "group": [1, 1], "kind": "farm"},
	"sheep": {"path": "Sheep.glb", "len": 1.25, "hp": 30, "speed": 5.0, "walk": 0.7, "flee": 6.0, "loot": {"raw_meat": 2}, "group": [1, 1], "kind": "farm"},
	"pig": {"path": "Pig.glb", "len": 1.2, "hp": 30, "speed": 4.5, "walk": 0.7, "flee": 5.0, "loot": {"raw_meat": 3}, "group": [1, 1], "kind": "farm"},
	"hen": {"path": "hen.glb", "len": 0.42, "hp": 5, "speed": 3.0, "walk": 0.5, "flee": 3.0, "loot": {"raw_meat": 1, "feathers": 1}, "group": [1, 1], "kind": "farm"},
	"donkey": {"path": "Donkey.glb", "len": 1.8, "hp": 60, "speed": 5.0, "walk": 0.8, "flee": 5.0, "loot": {"raw_meat": 3}, "group": [1, 1], "kind": "farm"},
	"dog": {"path": "Husky.glb", "len": 1.1, "hp": 35, "speed": 6.0, "walk": 1.3, "flee": 3.0, "loot": {}, "group": [1, 1], "kind": "farm"},
}
const BIOME_TABLE := {
	3: {"deer": 3.0, "stag": 1.5, "fox": 1.2, "wolf": 1.0, "bear": 0.7},                    # forest
	2: {"deer": 2.4, "stag": 1.0, "fox": 1.4, "wolf": 0.6, "wild_horse": 1.6},              # plains
	4: {"moose": 2.0, "wolf": 1.8, "fox": 0.8, "bear": 0.5, "stag": 0.6},                   # tundra
	5: {"stag": 1.2, "bear": 1.0, "wolf": 1.0, "moose": 0.6, "deer": 0.6},                  # mountains
	6: {"wolf": 0.8, "moose": 0.3},                                                         # snow
	7: {"alpaca": 2.0, "fox": 1.0, "wild_horse": 0.5},                                      # desert
	1: {"fox": 0.6, "deer": 0.4},                                                           # beach
}
var LAND_GROUPS := 10 if Assets.compat else 16      # herds, packs and solitary beasts kept around the player
var WATER_GROUPS := 4 if Assets.compat else 6
var FLOCKS := 3 if Assets.compat else 4

var groups: Array = []
var animals: Array = []
var _t := 0.0
var _farm_done := {}
var _migrate_t := 60.0


func setup() -> void:
	pass


func _process(delta: float) -> void:
	_update_migration(delta)
	_t -= delta
	if _t > 0.0:
		return
	var pl: Node3D = Game.player_ref
	if pl == null:
		return
	var p := pl.global_position
	# despawn
	for g in groups.duplicate():
		var far := true
		for a in g.members:
			if is_instance_valid(a) and a.global_position.distance_to(p) < (520.0 if g.get("migrate", false) else 360.0):
				far = false
				break
		if far:
			_free_group(g)
	for g in groups:
		g["flee_t"] = maxf(float(g.get("flee_t", 0.0)) - 0.6, 0.0)
		_roam(g)
	# land groups
	var land := 0
	var water := 0
	var flocks := 0
	for g in groups:
		match String(g.kind):
			"prey", "predator": land += 1
			"water", "fish": water += 1
			"bird": flocks += 1
	var cap := LAND_GROUPS + (3 if Game.is_night() else 0)
	for i in 3:              # a few tries per tick so the land fills quickly (and refills as you ride)
		if land >= cap:
			break
		if _try_spawn_land(p, pl):
			land += 1
	if water < WATER_GROUPS:
		_try_spawn_water(p)
	if flocks < FLOCKS:
		_try_spawn_flock(p)
	_farm_animals(p)
	_t = 0.6


func _rand_point(p: Vector3, rmin: float, rmax: float) -> Vector3:
	var a := randf() * TAU
	var r := randf_range(rmin, rmax)
	var q := p + Vector3(sin(a) * r, 0, cos(a) * r)
	q.y = WorldData.height_at(q.x, q.z)
	return q


func _in_settlement(q: Vector3) -> bool:
	for s in WorldData.settlements:
		if Vector2(s.x - q.x, s.z - q.z).length() < float(s.radius) * 1.25:
			return true
	return false


## Herds drift across the land as they graze instead of circling one spot forever.
func _roam(g: Dictionary) -> void:
	if not (String(g.kind) in ["prey", "predator"]) or g.get("migrate", false) or float(g.get("flee_t", 0.0)) > 0.0:
		return
	g["roam_t"] = float(g.get("roam_t", randf_range(10.0, 30.0))) - 0.6
	if float(g.roam_t) > 0.0:
		return
	g.roam_t = randf_range(18.0, 40.0)
	var c: Vector3 = g.center
	for i in 4:
		var a := randf() * TAU
		var n := c + Vector3(sin(a), 0, cos(a)) * randf_range(10.0, 26.0)
		if WorldData.is_inside_map(n.x, n.z) and WorldData.water_depth_at(n.x, n.z) < -0.3 and WorldData.normal_at(n.x, n.z).y > 0.8 and not _in_settlement(n):
			g.center = n
			return


## Picks a spot for a new group: far out in front of the player (so you see them on the
## horizon), or nearer but behind you (so nothing pops into view).
func _spawn_spot(p: Vector3, pl: Node3D) -> Vector3:
	var fwd := -pl.global_transform.basis.z
	var look := atan2(fwd.x, fwd.z)
	var a := randf() * TAU
	var ahead := absf(angle_difference(a, look)) < 1.1
	var r := randf_range(120.0, 250.0) if ahead else randf_range(70.0, 220.0)
	if WorldData.biome_at(p.x, p.z) == WorldData.Biome.FOREST:
		r = randf_range(55.0, 130.0) if ahead else randf_range(40.0, 110.0)   # trees hide anything further
	var q := p + Vector3(sin(a) * r, 0, cos(a) * r)
	q.y = WorldData.height_at(q.x, q.z)
	return q


func _try_spawn_land(p: Vector3, pl: Node3D) -> bool:
	var q := _spawn_spot(p, pl)
	if not WorldData.is_inside_map(q.x, q.z) or WorldData.water_depth_at(q.x, q.z) > -0.3 or _in_settlement(q):
		return false
	if WorldData.normal_at(q.x, q.z).y < 0.76:
		return false
	var b := WorldData.biome_at(q.x, q.z)
	var table: Dictionary = BIOME_TABLE.get(b, {})
	if table.is_empty():
		return false
	var weights := table.duplicate()
	if Game.is_night() and weights.has("wolf"):
		weights.wolf = float(weights.wolf) * 2.5
	var total := 0.0
	for k in weights: total += float(weights[k])
	var r := randf() * total
	var pick := ""
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			pick = k
			break
	if pick == "":
		return false
	_spawn_group(pick, q)
	return true


func _try_spawn_water(p: Vector3) -> void:
	for i in 12:
		var q := _rand_point(p, 30.0, 170.0)
		var depth := WorldData.water_depth_at(q.x, q.z)
		var lvl := WorldData.water_level_at(q.x, q.z)
		if depth > 1.0 and lvl > 0.5:
			if randf() < 0.55:
				q.y = lvl - 1.0
				_spawn_group("fish", q)
			else:
				q.y = lvl
				_spawn_group("duck" if randf() < 0.6 else "goose", q)
			return


func _try_spawn_flock(p: Vector3) -> void:
	var q := _rand_point(p, 60.0, 180.0)
	var b := WorldData.biome_at(q.x, q.z)
	var sp := "gull" if b in [WorldData.Biome.BEACH, WorldData.Biome.OCEAN] else "crow"
	if sp == "crow" and b in [WorldData.Biome.PLAINS, WorldData.Biome.MOUNTAIN, WorldData.Biome.TUNDRA, WorldData.Biome.DESERT] and randf() < 0.45:
		sp = "hawk"        # birds of prey wheel high over open country
	q.y = WorldData.height_at(q.x, q.z) + (randf_range(45.0, 75.0) if sp == "hawk" else randf_range(28.0, 50.0))
	var g := _spawn_group(sp, q)
	g["radius"] = randf_range(35.0, 70.0) if sp == "hawk" else randf_range(18.0, 40.0)


func _spawn_group(sp_name: String, at: Vector3) -> Dictionary:
	var spec: Dictionary = SPECIES[sp_name]
	var n := randi_range(int(spec.group[0]), int(spec.group[1]))
	if Assets.compat:
		n = mini(n, 4)          # the browser: smaller herds
	Game.mark("%d %s spawn" % [n, sp_name])
	var g := {"species": sp_name, "kind": spec.kind, "center": at, "members": [], "flee_t": 0.0}
	for i in n:
		var a: Animal = Animal.new()
		add_child(a)
		var s2 := spec
		if sp_name == "wild_horse" and randf() < 0.3:
			s2 = spec.duplicate()
			s2.path = "Horse_White.glb"
		var off := Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		var pos := at + off
		if spec.kind in ["prey", "predator", "farm"]:
			pos.y = WorldData.height_at(pos.x, pos.z)
		elif spec.kind == "water":
			pos.y = WorldData.water_level_at(pos.x, pos.z)
		a.global_position = pos
		a.setup(s2, sp_name, g, self)
		if sp_name == "hawk":
			_tint_goose(a, Color(0.42, 0.3, 0.2))
		a.home = pos
		g.members.append(a)
		animals.append(a)
	groups.append(g)
	return g


func _farm_animals(p: Vector3) -> void:
	for s in WorldData.settlements:
		if not (s.type in ["village", "town", "castle"]):
			continue
		var c := Vector3(s.x, 0, s.z)
		var near := Vector2(c.x - p.x, c.z - p.z).length() < 260.0
		if near and not _farm_done.has(s.name):
			var gl := []
			var climate := WorldData.climate_at(c.x, c.z)
			var kinds: Array = ["cow", "sheep", "sheep", "pig", "hen", "hen", "hen", "dog", "donkey", "bull"]
			if climate == "desert":
				kinds = ["alpaca_farm", "alpaca_farm", "hen", "hen", "donkey", "dog"]
			elif climate == "cold":
				kinds = ["sheep", "sheep", "cow", "hen", "dog", "dog"]
			if s.type == "castle":
				kinds = ["hen", "hen", "dog", "pig"]
			var spots := []
			for f in s.get("props", []):
				if f.type == "field":
					spots.append(Vector3(f.x, 0, f.z))
			if spots.is_empty():
				spots.append(c)
			for i in kinds.size():
				var kname: String = kinds[i]
				var spec: Dictionary = SPECIES.alpaca.duplicate() if kname == "alpaca_farm" else SPECIES[kname]
				if kname == "alpaca_farm":
					spec.kind = "farm"
					kname = "alpaca"
				var base: Vector3 = spots[i % spots.size()] + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
				if kname in ["hen", "dog"]:
					base = c + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
				base.y = WorldData.height_at(base.x, base.z)
				var g := {"species": kname, "kind": "farm", "center": base, "members": [], "flee_t": 0.0, "farm": s.name}
				var a: Animal = Animal.new()
				add_child(a)
				a.global_position = base
				a.setup(spec, kname, g, self)
				a.home = base
				g.members.append(a)
				animals.append(a)
				gl.append(g)
				groups.append(g)
			_farm_done[s.name] = gl
		elif not near and _farm_done.has(s.name) and Vector2(c.x - p.x, c.z - p.z).length() > 340.0:
			for g in _farm_done[s.name]:
				_free_group(g)
			_farm_done.erase(s.name)


func _free_group(g: Dictionary) -> void:
	for a in g.members:
		if is_instance_valid(a):
			animals.erase(a)
			a.queue_free()
	groups.erase(g)


func remove_animal(a: Node) -> void:
	animals.erase(a)
	for g in groups:
		if g.members.has(a):
			g.members.erase(a)
	if is_instance_valid(a):
		a.queue_free()


func animal_died(_a: Node) -> void:
	pass


# ------------------------------------------------------------------ migration (geese in V formation)
func _update_migration(delta: float) -> void:
	_migrate_t -= delta
	var pl: Node3D = Game.player_ref
	if pl == null:
		return
	for g in groups:
		if g.get("migrate", false):
			g.center = (g.center as Vector3) + (g.dir as Vector3) * 13.0 * delta
	if _migrate_t > 0.0:
		return
	_migrate_t = randf_range(120.0, 260.0)
	var dir := Vector3(randf_range(-0.3, 0.3), 0, 1.0 if randf() < 0.5 else -1.0).normalized()
	var start := pl.global_position - dir * 420.0 + Vector3(dir.z, 0, -dir.x) * randf_range(-150, 150)
	start.y = maxf(WorldData.height_at(start.x, start.z), 0.0) + 90.0
	var spec: Dictionary = SPECIES.goose_flight.duplicate()
	var g := {"species": "goose_flight", "kind": "bird", "center": start, "members": [], "migrate": true, "dir": dir, "offsets": []}
	var n := randi_range(9, 13)
	for i in n:
		var row := (i + 1) / 2
		var side := -1.0 if i % 2 == 0 else 1.0
		g.offsets.append(Vector3(side * row * 2.6, randf_range(-0.3, 0.3), -row * 3.0))
		var a: Animal = Animal.new()
		add_child(a)
		a.global_position = start
		a.setup(spec, "goose", g, self)
		_tint_goose(a)
		g.members.append(a)
		animals.append(a)
	groups.append(g)
	Audio.play_at("honk", pl.global_position + Vector3(0, 60, 0), -4.0)


func _tint_goose(a: Animal, tint := Color(0.45, 0.4, 0.35)) -> void:
	for m in a.statics:
		var sm := m.material_override as ShaderMaterial
		if sm:
			var c := sm.duplicate() as ShaderMaterial
			c.set_shader_parameter("tint", tint)
			m.material_override = c


# ------------------------------------------------------------------ queries
func predator_near(p: Vector3, r: float) -> Node3D:
	for a in animals:
		if is_instance_valid(a) and not a.dead and a.kind == "predator" and a.global_position.distance_squared_to(p) < r * r:
			return a
	return null


func prey_near(p: Vector3, r: float) -> Node3D:
	var best: Node3D = null
	var bd := r * r
	for a in animals:
		if is_instance_valid(a) and not a.dead and a.kind == "prey" and a.species in ["deer", "stag", "alpaca", "fox"]:
			var d: float = a.global_position.distance_squared_to(p)
			if d < bd:
				bd = d
				best = a
	return best
