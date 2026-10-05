class_name NPCManager
extends Node3D
## Populates Aldmere: residents for every village, town and castle (with castle ranks),
## daily routines, market-day traders, road travellers & mounted patrols, bandits, horses
## for sale. Streams NPC bodies in and out around the player.

var SPAWN_R := (36.0 if Game.mobile else 45.0) if Assets.compat else 100.0       # the browser keeps fewer townsfolk awake
var DESPAWN_R := (50.0 if Game.mobile else 60.0) if Assets.compat else 130.0
var MAX_ACTIVE := (9 if Game.mobile else 14) if Assets.compat else 70
var _spawn_cd := 0.0

const PERSONALITIES := ["friendly", "crabby", "suspicious", "cautious", "helpful", "hostile", "cheerful", "grumpy", "shy", "boastful", "pious", "greedy"]
const RANKS := {"duke": 1, "consort": 1, "heir": 2, "official": 2, "knight": 3, "falconer": 4, "guard": 5, "jailer": 5, "cook": 6, "servant": 7, "prisoner": 9}
const ROYAL_SEAT := "Castle Ravenmoor"     # the King of Aldmere holds court here; the other castles have dukes
const NAMES := {
	"temperate": {"m": ["Aldric", "Edmund", "Gareth", "Rowan", "Tobias", "Matthias", "Cedric", "Hugh", "Osric", "Alaric", "Bertram", "Conrad", "Dunstan", "Edgar", "Godfrey", "Harold", "Leofric", "Merrick", "Oswin", "Percival", "Roland", "Wilfred", "Geoffrey", "Baldwin", "Walter", "Simon"],
		"f": ["Elena", "Maud", "Agnes", "Beatrice", "Rosalind", "Isolde", "Edith", "Gwendolyn", "Matilda", "Eleanor", "Alys", "Cecily", "Juliana", "Margery", "Sibyl", "Joan", "Helewise", "Avelina", "Clarice", "Emma"]},
	"cold": {"m": ["Bjorn", "Ulf", "Ragnar", "Erik", "Leif", "Halvard", "Sigurd", "Torvald", "Gunnar", "Arne", "Eirik", "Stig", "Knut", "Vidar"],
		"f": ["Sigrid", "Astrid", "Ingrid", "Freya", "Solveig", "Gudrun", "Ragnhild", "Thyra", "Helga", "Ylva", "Runa", "Signe"]},
	"desert": {"m": ["Tariq", "Yusuf", "Samir", "Karim", "Rashid", "Hamza", "Faisal", "Idris", "Malik", "Nasir", "Omar", "Zayd", "Harun", "Jamal"],
		"f": ["Nadia", "Leila", "Amira", "Zahra", "Layla", "Samira", "Yasmin", "Farah", "Rania", "Salma", "Huda", "Noor"]},
}
const SURNAMES := ["Ashdown", "Brightwater", "Thorne", "Fletcher", "Cooper", "Mason", "Ward", "Hollins", "Greaves", "Oakes", "Marsh", "Fairweather", "Holt", "Crane", "Blackwood", "Merriweather"]
const DESERT_SUR := ["al-Qadir", "ibn Rashid", "al-Sahra", "ibn Malik", "al-Wadi", "bint Harun", "al-Nur"]
## Complexions, fair to dark (average skin albedo, linear): see the outfit shader's skin tone.
const SKIN_TONES := [Color(0.72, 0.5, 0.4), Color(0.62, 0.42, 0.32), Color(0.52, 0.34, 0.24), Color(0.44, 0.3, 0.19),
	Color(0.34, 0.21, 0.13), Color(0.24, 0.14, 0.085), Color(0.15, 0.09, 0.055)]
const HAIR_COLORS := [Color(0.08, 0.06, 0.05), Color(0.22, 0.14, 0.08), Color(0.35, 0.22, 0.12), Color(0.6, 0.45, 0.22), Color(0.55, 0.25, 0.1), Color(0.5, 0.5, 0.5)]


class NPCData:
	var id := 0
	var name := ""
	var gender := "m"
	var role := "villager"
	var rank := 0
	var personality := "friendly"
	var info: Dictionary
	var sname := ""
	var climate := "temperate"
	var look := {}
	var bed: Dictionary = {}
	var work: Dictionary = {}
	var seat: Dictionary = {}
	var pos := Vector3.ZERO
	var yaw := 0.0
	var node: Node3D = null
	var alive := true
	var hostile := false
	var health := 100.0
	var max_health := 100.0
	var met := false
	var looted := false
	var disposition := 0.0
	var traveler: Dictionary = {}
	var mounted := false
	var market_only := false
	var stock: Dictionary = {}
	var horses: Array = []
	var trained := false
	var camp := Vector3.ZERO
	var escort_of: NPCData = null
	var gift_count := 0
	var arresting := false        # a guard/knight confronting the wanted player
	var warned_ms := -100000      # when the player last struck them (a first stray blow is forgiven)
	var offer := {}               # a job they've described but the player hasn't taken yet


var all: Array[NPCData] = []
var active: Array[NPCData] = []
var for_sale: Array = []           # horses at stables
var player_horses: Array = []      # spawned horse nodes owned by player
var _tick := 0.0
var _spawn_queue: Array[NPCData] = []   # nearest first; one character is built per frame
var _pursuers := {}                      # settlement -> NPCData of the watch sent after the player
const QUESTS := preload("res://scripts/core/quests.gd")
var _rng := RandomNumberGenerator.new()
var settlements: Node
var dialogue_ui: Node


func setup() -> void:
	_rng.seed = 7331
	settlements = Game.world_ref.settlements
	for info in settlements.infos:
		_populate(info)
	for info in settlements.poi_infos:
		_populate_poi(info)
	_make_travellers()
	_spawn_stable_horses()
	_restore_player_horses()
	for d in all:
		if Game.dead_npcs.has(str(d.id)):
			d.alive = false
		_place_virtual(d)
	await get_tree().process_frame


# ------------------------------------------------------------------ population
func _new(info: Dictionary, role: String, gender := "") -> NPCData:
	var d := NPCData.new()
	d.id = all.size()
	d.info = info
	d.sname = info.name
	d.climate = info.climate
	d.role = role
	d.rank = RANKS.get(role, 0) if info.type == "castle" else 0
	d.gender = gender if gender != "" else ("m" if _rng.randf() < (0.85 if role in ["knight", "guard", "blacksmith"] else 0.55) else "f")
	if role in ["knight", "guard", "duke"]:
		d.gender = "m" if role != "knight" or _rng.randf() < 0.85 else "f"
	if role == "consort":
		d.gender = "f"
	if role == "heir":
		# a son and a daughter
		var n: int = info.get("heirs", 0)
		info["heirs"] = n + 1
		d.gender = "m" if n % 2 == 0 else "f"
	d.personality = PERSONALITIES[_rng.randi() % PERSONALITIES.size()]
	match role:
		"official": d.personality = "snobbish"
		"knight": d.personality = "honourable"
		"cook": d.personality = "cook"
		"guard": d.personality = "stern"
		"servant": d.personality = "meek"
		"duke": d.personality = ["stern", "friendly", "boastful"][_rng.randi() % 3]
		"consort": d.personality = ["gracious", "stern"][_rng.randi() % 2]
		"heir": d.personality = ["cheerful", "boastful", "shy", "friendly"][_rng.randi() % 4]
		"jailer": d.personality = "grumpy"
		"prisoner": d.personality = "prisoner"
	d.name = _make_name(d)
	d.look = _make_look(d)
	d.health = 160.0 if role == "knight" else (120.0 if role in ["guard", "bandit"] else 70.0)
	d.max_health = d.health
	d.disposition = {"friendly": 0.4, "helpful": 0.35, "cheerful": 0.3, "crabby": -0.25, "grumpy": -0.2, "suspicious": -0.3, "hostile": -0.6, "honourable": 0.2, "snobbish": -0.35}.get(d.personality, 0.0)
	all.append(d)
	return d


func _make_name(d: NPCData) -> String:
	var pool: Dictionary = NAMES.get(d.climate, NAMES.temperate)
	var first: String = pool[d.gender][_rng.randi() % pool[d.gender].size()]
	match d.role:
		"knight": return ("Sir " if d.gender == "m" else "Dame ") + first
		"duke": return ("King %s" % first) if d.sname == ROYAL_SEAT else "Duke %s of %s" % [first, String(d.sname).replace("Castle ", "")]
		"consort": return ("Queen %s" % first) if d.sname == ROYAL_SEAT else "Duchess %s of %s" % [first, String(d.sname).replace("Castle ", "")]
		"heir":
			if d.sname == ROYAL_SEAT:
				return ("Prince " if d.gender == "m" else "Princess ") + first
			return ("Lord " if d.gender == "m" else "Lady ") + first + " of " + String(d.sname).replace("Castle ", "")
		"official": return ("Lord " if d.gender == "m" else "Lady ") + first + " " + SURNAMES[_rng.randi() % SURNAMES.size()]
	if d.climate == "desert":
		return first + " " + DESERT_SUR[_rng.randi() % DESERT_SUR.size()]
	if d.climate == "cold":
		var fathers: Array = NAMES.cold.m
		return first + " " + String(fathers[_rng.randi() % fathers.size()]) + ("son" if d.gender == "m" else "dottir")
	return first + " " + SURNAMES[_rng.randi() % SURNAMES.size()]


func _make_look(d: NPCData) -> Dictionary:
	var L := {"gender": d.gender, "outfit": "Peasant", "hue": _rng.randf_range(-0.08, 0.12), "sat": _rng.randf_range(0.6, 1.1), "val": _rng.randf_range(0.75, 1.05)}
	var hairs: Array = CharacterModel.HAIR_M if d.gender == "m" else CharacterModel.HAIR_F
	L.hair = hairs[_rng.randi() % hairs.size()]
	L.beard = d.gender == "m" and _rng.randf() < 0.45
	L.hair_color = HAIR_COLORS[_rng.randi() % HAIR_COLORS.size()]
	# mostly fair to olive in the heartland, now and then darker (traders and travellers)
	L.skin = _complexion(4, 6) if _rng.randf() < 0.12 else _complexion(0, 4)
	match d.climate:
		"cold":
			L.outfit = "Ranger"
			L.hood = _rng.randf() < 0.7
			L.pauldron = true
			L.val = _rng.randf_range(0.55, 0.8)
			L.sat = _rng.randf_range(0.35, 0.7)
			L.hue = _rng.randf_range(-0.06, 0.04)
			L.skin = _complexion(0, 2)
		"desert":
			L.outfit = "Peasant"
			L.hood = _rng.randf() < 0.8
			L.sat = _rng.randf_range(0.05, 0.35)
			L.val = _rng.randf_range(1.15, 1.45)
			L.hue = [0.0, 0.58, 0.08][_rng.randi() % 3]
			L.dust = 0.25
			L.skin = _complexion(2, 6)
			L.hair_color = Color(0.06, 0.05, 0.04)
	match d.role:
		"knight":
			# mail coif (the hood in steel), steel-sheened gambeson and pauldron, sword and kite shield
			L.outfit = "Ranger"; L.steel = 0.88; L.sword = true; L.shield = true; L.hood = true; L.pauldron = true
		"guard":
			L.outfit = "Ranger"; L.steel = 0.6; L.sword = true; L.hood = _rng.randf() < 0.6; L.pauldron = true
		"bandit":
			L.outfit = "Ranger"; L.hood = true; L.val = 0.4; L.sat = 0.4; L.sword = true; L.hue = _rng.randf_range(-0.1, 0.1)
			if _rng.randf() < 0.45:      # some carry a battered wooden shield
				L.shield = true; L.shield_model = "res://assets/props/Shield_Wooden.gltf"
		"duke":
			L.outfit = "Ranger"; L.crown = true; L.hue = [0.72, 0.95, 0.12][_rng.randi() % 3]; L.sat = 1.7; L.val = 0.85; L.hood = false; L.pauldron = true; L.beard = true
			if d.sname == ROYAL_SEAT:
				L.hue = 0.76; L.sat = 1.6; L.val = 0.95; L.steel = 0.2          # the king: royal crimson
		"consort":
			L.outfit = "Ranger"; L.crown = true; L.hue = 0.74; L.sat = 1.6; L.val = 0.95; L.hood = false; L.pauldron = false
			if d.sname != ROYAL_SEAT:
				L.crown_size = 0.16; L.hue = 0.6
		"heir":
			# the young royals: the family's colours, a slender circlet
			L.outfit = "Ranger"; L.crown = true; L.crown_size = 0.15; L.hue = 0.76 if d.sname == ROYAL_SEAT else 0.62; L.sat = 1.5; L.val = 1.0
			L.hood = false; L.pauldron = d.gender == "m"; L.beard = false; L.sword = d.gender == "m"
		"jailer":
			L.outfit = "Ranger"; L.hood = true; L.val = 0.45; L.sat = 0.5; L.steel = 0.3; L.sword = true; L.pauldron = true
		"prisoner":
			L.outfit = "Peasant"; L.hood = false; L.val = 0.45; L.sat = 0.3; L.dust = 0.6
		"official":
			L.outfit = "Ranger"; L.hue = [0.62, 0.92, 0.33, 0.75][_rng.randi() % 4]; L.sat = 1.5; L.val = 0.8; L.hood = false; L.pauldron = false
		"falconer":
			L.outfit = "Ranger"; L.falcon = true; L.hue = 0.05; L.sat = 0.9; L.hood = false
		"cook":
			L.outfit = "Peasant"; L.sat = 0.08; L.val = 1.45; L.hood = false
		"servant":
			L.outfit = "Peasant"; L.sat = 0.35; L.val = 0.7; L.hood = false
		"priest":
			L.outfit = "Peasant"; L.sat = 0.15; L.val = 1.25; L.hood = true
		"merchant", "shopkeeper":
			L.hue = _rng.randf(); L.sat = 1.35
		"explorer":
			L.outfit = "Ranger"; L.hood = true; L.hue = _rng.randf_range(0.0, 0.3)
		"blacksmith":
			L.val = 0.55
		"farmer":
			L.dust = 0.25
	return L


func _complexion(lo: int, hi: int) -> Color:
	var c: Color = SKIN_TONES[_rng.randi_range(lo, hi)]
	var k := _rng.randf_range(0.92, 1.08)
	return Color(c.r * k, c.g * k, c.b * k)


func _buildings(info: Dictionary, types: Array) -> Array:
	var out := []
	for b in info.buildings:
		if b.type in types:
			out.append(b)
	return out


func _spot(info: Dictionary, building_types: Array, tag: String, used: Dictionary) -> Dictionary:
	for b in _buildings(info, building_types):
		for s in b.spots.work:
			if s.tag == tag and not used.has(s):
				used[s] = true
				return s
	return {}


func _bed(info: Dictionary, types: Array, used: Dictionary, inn_ok := false) -> Dictionary:
	for b in _buildings(info, types):
		for s in b.spots.beds:
			if not used.has(s) and (inn_ok or not s.inn):
				used[s] = true
				return s
	return {}


func _populate(info: Dictionary) -> void:
	var kind: String = info.type
	if kind in ["ruin", "ruin_keep"]:
		return
	var used := {}
	var beds := {}
	var plan := []
	match kind:
		"village":
			plan = ["knight", "knight", "blacksmith", "tavern_owner", "cook", "stablemaster", "merchant", "farmer", "farmer", "farmer", "villager", "villager", "villager", "villager", "priest"]
			if _rng.randf() < 0.6: plan.append("explorer")
		"town":
			plan = ["knight", "knight", "knight", "knight", "knight", "knight", "knight", "blacksmith", "tavern_owner", "tavern_owner", "cook", "cook", "stablemaster", "stablemaster",
				"shopkeeper", "shopkeeper", "shopkeeper", "merchant", "merchant", "merchant", "merchant", "official", "official", "priest", "porter", "farmer", "farmer", "farmer",
				"villager", "villager", "villager", "villager", "villager", "villager", "villager", "villager", "explorer", "explorer"]
		"castle":
			plan = ["duke", "official", "official", "official", "knight", "knight", "knight", "knight", "knight", "falconer", "guard", "guard", "guard", "guard", "guard", "guard",
				"cook", "cook", "servant", "servant", "servant", "servant", "stablemaster"]
			# the ruling family, and the dungeon's keeper and its prisoners
			plan.insert(1, "consort")
			plan.insert(2, "heir")
			plan.insert(3, "heir")
			plan.append_array(["jailer", "prisoner", "prisoner", "prisoner", "prisoner"])
			if info.name == ROYAL_SEAT:
				plan.append_array(["knight", "knight", "guard", "guard"])      # the royal household
	for role in plan:
		var d := _new(info, role)
		_assign(d, info, used, beds)
	if kind == "town":
		# visiting traders who only come on market days
		for k in 6:
			var d := _new(info, "merchant")
			d.market_only = true
			_assign(d, info, used, beds)


func _assign(d: NPCData, info: Dictionary, used: Dictionary, beds: Dictionary) -> void:
	match d.role:
		"knight":
			d.bed = _bed(info, ["barracks"], beds)
			if d.bed.is_empty(): d.bed = _bed(info, ["tavern"], beds, true)
			if info.type == "castle":
				d.work = _spot(info, ["keep"], "throne_guard", used)
				if d.work.is_empty():
					d.work = _spot(info, ["keep"], "door_guard", used)
		"guard":
			d.bed = _bed(info, ["barracks"], beds)
		"duke", "consort", "heir":
			d.bed = _bed(info, ["keep"], beds)
			var want: String = {"duke": "throne", "consort": "consort"}.get(d.role, "heir_m" if d.gender == "m" else "heir_f")
			for b in _buildings(info, ["keep"]):
				for s in b.spots.sit:
					if s.tag == want:
						d.seat = s
		"jailer":
			d.bed = _bed(info, ["barracks"], beds)
			for b in _buildings(info, ["keep"]):
				for s in b.spots.sit:
					if s.tag == "jailer":
						d.work = s
		"prisoner":
			d.work = _spot(info, ["keep"], "prisoner", used)
			d.bed = d.work.get("straw", {})
		"official":
			d.work = _spot(info, ["keep", "townhall"], "official", used)
			if d.work.is_empty():
				d.work = _spot(info, ["keep"], "scholar", used)
			d.bed = _bed(info, ["keep", "townhall"], beds)
		"falconer":
			d.work = _spot(info, ["mews"], "falconer", used)
			d.bed = _bed(info, ["barracks"], beds)
		"cook":
			d.work = _spot(info, ["kitchen"], "cook", used)
			if d.work.is_empty(): d.work = _spot(info, ["tavern", "house"], "hearth", used)
			d.bed = _bed(info, ["kitchen", "barracks", "house"], beds)
		"servant":
			d.work = _spot(info, ["kitchen", "keep", "barracks"], "", used)
			d.bed = _bed(info, ["barracks", "kitchen", "house"], beds)
		"blacksmith":
			d.work = _spot(info, ["blacksmith"], "smith", used)
			d.bed = _bed(info, ["house", "blacksmith"], beds)
		"tavern_owner":
			d.work = _spot(info, ["tavern"], "barkeep", used)
			d.bed = _bed(info, ["house", "tavern"], beds, true)
		"stablemaster":
			d.work = _spot(info, ["stable"], "stablemaster", used)
			d.bed = _bed(info, ["house"], beds)
		"shopkeeper":
			d.work = _spot(info, ["shop"], "shopkeeper", used)
			d.bed = _bed(info, ["shop", "house"], beds)
		"merchant":
			for s in info.stalls:
				if not used.has(s):
					used[s] = true
					d.work = {"p": s.p, "yaw": s.yaw, "anim": "Idle_Talking", "tag": "stall", "nav": s.nav}
					break
			d.bed = _bed(info, ["house", "tavern"], beds, true)
		"priest":
			d.work = _spot(info, ["chapel"], "priest", used)
			d.bed = _bed(info, ["house", "chapel"], beds)
		"porter":
			d.work = _spot(info, ["warehouse"], "porter", used)
			d.bed = _bed(info, ["house"], beds)
		"farmer":
			if info.fields.size() > 0:
				var f: Dictionary = info.fields[d.id % info.fields.size()]
				var n: int = f.spots[d.id % f.spots.size()]
				d.work = {"p": info.nav_p[n], "yaw": float(d.id), "anim": "Fixing_Kneeling", "tag": "field", "nav": n}
			d.bed = _bed(info, ["house"], beds)
		_:
			d.bed = _bed(info, ["house", "shop", "townhall"], beds)
			d.work = _spot(info, ["house"], "hearth", used)
	for b in _buildings(info, ["tavern", "keep", "chapel", "townhall"]):
		for s in b.spots.sit:
			if not used.has(s) and s.tag == "" and d.role not in ["guard", "cook", "servant", "duke", "consort", "heir", "jailer", "prisoner"]:
				used[s] = true
				d.seat = s
				break
		if not d.seat.is_empty():
			break
	_stock(d)


func _stock(d: NPCData) -> void:
	var st := {}
	match d.role:
		"blacksmith":
			st = {"rusty_sword": 2, "iron_sword": 2, "wooden_shield": 2, "leather_armor": 1, "torch": 6}
			if d.info.type in ["town", "castle"]:
				st.merge({"steel_longsword": 1, "kite_shield": 1, "chainmail": 1, "knight_sword": 1})
		"tavern_owner":
			st = {"bread": 6, "cheese": 4, "stew": 4, "ale": 10, "wine": 3, "cooked_meat": 4, "waterskin": 2, "apple": 6}
		"shopkeeper", "merchant":
			st = {"bread": 4, "apple": 8, "waterskin": 2, "torch": 6, "bedroll": 1, "campfire_kit": 3, "bandage": 4, "wool_cloak": 1, "cheese": 2}
			match d.climate:
				"cold": st.merge({"fur_cloak": 2, "stew": 2})
				"desert": st.merge({"desert_robes": 2, "dates": 8, "waterskin": 4})
			if d.market_only:
				st.merge({"honey_cake": 3, "spiced_wine": 2, "healing_draught": 2})
				var rare := ["elven_blade", "silk_cloak", "falcon_charm", "plate_armor"]
				st[rare[d.id % rare.size()]] = 1
		"farmer":
			st = {"apple": 10, "carrot": 10, "milk": 4, "bread": 2}
		"priest":
			st = {"bandage": 6, "healing_draught": 3}
		"cook":
			st = {}
	d.stock = st


func _populate_poi(info: Dictionary) -> void:
	match String(info.type):
		"watchtower":
			var d := _new(info, "knight")
			d.camp = info.center
			if info.hubs.size() > 0:
				d.work = {"p": info.nav_p[info.hubs[0]], "yaw": 0.0, "anim": "Sword_Idle", "tag": "sentry", "nav": info.hubs[0]}
		"bandit_camp":
			for k in 4:
				var d := _new(info, "bandit")
				d.hostile = true
				d.camp = info.center
				d.name = ["Grim", "Scar", "Rook", "Mad", "One-Eye", "Black"][k % 6] + " " + ["Tom", "Hugh", "Wat", "Ned", "Col", "Bess"][(k + d.id) % 6]
		"camp", "cabin":
			if info.hubs.size() > 0:
				var d := _new(info, "explorer" if info.type == "cabin" else "villager")
				d.work = {"p": info.nav_p[info.hubs[0]], "yaw": 0.0, "anim": "Idle", "tag": "camp", "nav": info.hubs[0]}
				d.bed = {}


func _make_travellers() -> void:
	var roads: Array = WorldData.roads
	if roads.is_empty():
		return
	var towns := []
	for info in settlements.infos:
		if info.type in ["town", "village", "castle"]:
			towns.append(info)
	for k in 9:
		var rd: Dictionary = roads[(k * 7) % roads.size()]
		var start: Dictionary = settlements.infos[0]
		for info in settlements.infos:
			if info.name == rd.a:
				start = info
		var role := "merchant" if k < 5 else "knight"
		var d := _new(start, role)
		d.mounted = role == "knight" or k % 2 == 0
		d.traveler = {"pts": rd.pts, "t": _rng.randf_range(0.0, float(rd.pts.size() - 1)), "dir": 1 if k % 2 == 0 else -1, "wait": 0.0, "road": rd}
		if role == "merchant":
			d.stock = {"bread": 3, "wine": 2, "torch": 3, "bandage": 2, "silver_ring": 1, "waterskin": 1, "fur_cloak" if k % 2 else "desert_robes": 1}
			if k < 2:
				var e := _new(start, "knight")
				e.mounted = d.mounted
				e.traveler = d.traveler
				e.escort_of = d
		d.look.erase("torch")


func _spawn_stable_horses() -> void:
	for info in settlements.infos:
		var spots: Array = info.horse_spots
		for i in spots.size():
			var sp: Dictionary = spots[i]
			var speed := _rng.randf_range(11.0, 19.0)
			var price := int(round(lerpf(30.0, 60.0, (speed - 11.0) / 8.0)))
			var h := {"id": "%s_%d" % [info.name, i], "speed": speed, "price": price, "white": _rng.randf() < 0.35, "pos": sp.p, "yaw": sp.yaw, "settlement": info.name, "sold": false, "node": null}
			for oh in Game.owned_horses:
				if oh.id == h.id:
					h.sold = true
			for_sale.append(h)


func _restore_player_horses() -> void:
	for oh in Game.owned_horses:
		var h := _make_horse(oh, true)
		h.global_position = Vector3(float(oh.x), WorldData.height_at(float(oh.x), float(oh.z)), float(oh.z))
		player_horses.append(h)


func _make_horse(spec: Dictionary, owned: bool) -> Node3D:
	var h: Node3D = load("res://scripts/actors/horse.gd").new()
	add_child(h)
	h.call("setup", spec, owned)
	return h


# ------------------------------------------------------------------ routines
static func role_title(d) -> String:
	var t := {"tavern_owner": "Innkeeper", "stablemaster": "Stablemaster", "shopkeeper": "Shopkeeper", "blacksmith": "Blacksmith", "merchant": "Merchant",
		"farmer": "Farmer", "priest": "Priest", "official": "Official", "falconer": "Falconer", "knight": "Knight", "guard": "Guard", "servant": "Servant",
		"cook": "Cook", "porter": "Porter", "explorer": "Explorer", "duke": "Duke", "bandit": "Bandit", "villager": "Villager",
		"jailer": "Jailer", "prisoner": "Prisoner"}
	if d.role == "duke" and d.sname == ROYAL_SEAT:
		return "King"
	if d.role == "consort":
		return "Queen" if d.sname == ROYAL_SEAT else "Duchess"
	if d.role == "heir":
		if d.sname == ROYAL_SEAT:
			return "Prince" if d.gender == "m" else "Princess"
		return "Lord" if d.gender == "m" else "Lady"
	return t.get(d.role, String(d.role).capitalize())


func _act_spot(s: Dictionary, anim := "") -> Dictionary:
	return {"type": "spot", "key": str(s.get("nav", -1)) + anim, "nav": s.get("nav", -1), "pos": s.p, "yaw": s.get("yaw", 0.0), "anim": anim if anim != "" else s.get("anim", "Idle")}


func _act_hub(d: NPCData, salt: int, anim := "Idle_Talking", speed := 1.35) -> Dictionary:
	var hubs: Array = d.info.hubs
	if hubs.is_empty():
		return {"type": "idle", "key": "idle"}
	var n: int = hubs[(salt + d.id * 7) % hubs.size()]
	return {"type": "hub", "key": str(n), "nav": n, "pos": d.info.nav_p[n], "yaw": float(d.id), "anim": anim, "speed": speed}


func activity_for(d: NPCData) -> Dictionary:
	var h := Game.time_of_day()
	var slot := int(Game.minutes / 20.0)
	var off := float(d.id % 5) * 0.25
	var night := h < 6.0 + off or h > 22.0 - off
	if d.hostile:
		var a := float((slot + d.id) % 8) * TAU / 8.0
		var p: Vector3 = d.camp + Vector3(sin(a) * 6.0, 0, cos(a) * 6.0)
		p.y = WorldData.height_at(p.x, p.z)
		return {"type": "camp", "key": str(slot), "nav": -1, "pos": p, "yaw": a, "anim": "Idle"}
	if d.market_only and not (Game.is_market_day(d.sname) and h > 7.5 and h < 18.0):
		return {"type": "absent", "key": "absent"}
	match d.role:
		"guard":
			if d.info.walk_loop.size() > 0 and (d.id % 2 == 0) != night:
				return {"type": "loop", "key": "loop", "loop": d.info.walk_loop, "anim": "Idle_Torch" if night else "Sword_Idle"}
			if night and not d.bed.is_empty():
				return _act_spot(d.bed, "Sleep")
			return {"type": "loop", "key": "loop", "loop": d.info.walk_loop, "anim": "Sword_Idle"} if d.info.walk_loop.size() > 0 else _act_hub(d, slot / 3, "Sword_Idle")
		"knight":
			if not d.work.is_empty() and d.work.tag == "sentry":
				return _act_spot(d.work)
			if night and not d.bed.is_empty() and d.id % 3 != 0:
				return _act_spot(d.bed, "Sleep")
			if h > 19.0 and not d.seat.is_empty() and d.id % 2 == 0:
				return _act_spot(d.seat, "Sitting_Idle")
			if not d.work.is_empty() and h > 8.0 and h < 17.0 and d.id % 2 == 0:
				return _act_spot(d.work)
			return _act_hub(d, slot / 2, "Sword_Idle", 1.3)
		"prisoner":
			if night and not d.bed.is_empty():
				return _act_spot(d.bed, "Sleep")      # on the straw
			return _act_spot(d.work) if not d.work.is_empty() else {"type": "absent", "key": "absent"}
		"jailer":
			if night and not d.bed.is_empty() and d.id % 2 == 0:
				return _act_spot(d.bed, "Sleep")
			if not d.work.is_empty():
				return _act_spot(d.work, "Sitting_Idle")
		"heir":
			if night and not d.bed.is_empty():
				return _act_spot(d.bed, "Sleep")
			if not d.seat.is_empty() and ((h > 9.0 and h < 11.5) or (h > 15.0 and h < 16.5)):
				return _act_spot(d.seat, "Sitting_Talking")
			return _act_hub(d, slot / 2 + d.id, "Idle_Talking" if d.id % 2 else "Idle", 1.2)
		"duke", "consort":
			if night and not d.bed.is_empty():
				return _act_spot(d.bed, "Sleep")
			if not d.seat.is_empty() and ((h > 8.0 and h < 12.0) or (h > 14.0 and h < 19.0)):
				return _act_spot(d.seat, "Sitting_Talking")
			return _act_hub(d, slot / 3, "Idle_Talking", 1.1)
		"tavern_owner":
			if h < 6.5 and not d.bed.is_empty():
				return _act_spot(d.bed, "Sleep")
			if not d.work.is_empty():
				return _act_spot(d.work)
		"cook":
			if night and not d.bed.is_empty():
				return _act_spot(d.bed, "Sleep")
			if not d.work.is_empty():
				return _act_spot(d.work)
		"farmer":
			if night and not d.bed.is_empty():
				return _act_spot(d.bed, "Sleep")
			if h > 19.0 and not d.seat.is_empty():
				return _act_spot(d.seat, "Sitting_Talking")
			if not d.work.is_empty() and not (h > 12.0 and h < 13.0):
				return _act_spot(d.work)
		"servant":
			if night and not d.bed.is_empty():
				return _act_spot(d.bed, "Sleep")
			if slot % 3 == 0 or d.work.is_empty():
				return _act_hub(d, slot, "PickUp_Table", 1.5)
			return _act_spot(d.work)
		"falconer":
			if night and not d.bed.is_empty():
				return _act_spot(d.bed, "Sleep")
			if h > 15.0 and not d.work.is_empty():
				return _act_spot(d.work, "Idle_Torch")
			return _act_hub(d, slot / 2, "Idle_Torch", 1.2)
	# generic day: work hours, leisure in the evening, sleep at night
	if night and not d.bed.is_empty():
		return _act_spot(d.bed, "Sleep")
	if h > 18.5 and not d.seat.is_empty() and d.id % 3 != 2:
		return _act_spot(d.seat, "Sitting_Talking" if d.id % 2 else "Sitting_Idle")
	if not d.work.is_empty() and h > 7.0 + off and h < 18.0 - off and not (h > 12.0 and h < 12.75):
		return _act_spot(d.work)
	return _act_hub(d, slot, "Idle_Talking" if d.id % 2 else "Idle")


func path_to(d: NPCData, from: Vector3, act: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	if act.type == "loop":
		var loop: Array = act.loop
		var best := 0
		var bd := INF
		for i in loop.size():
			var dd := (loop[i] as Vector3).distance_squared_to(from)
			if dd < bd:
				bd = dd
				best = i
		for k in 40:
			var i := (best + k) % (loop.size() * 2 - 2) if loop.size() > 1 else 0
			out.append(loop[i] if i < loop.size() else loop[loop.size() * 2 - 2 - i])
		return out
	if act.type in ["idle", "absent"]:
		return out
	var nav: int = int(act.get("nav", -1))
	if nav < 0 or d.info.nav_p.is_empty():
		out.append(act.pos)
		return out
	var from_i: int = settlements.nearest_nav(d.info, from)
	out = settlements.find_path(d.info, from_i, nav)
	if out.is_empty() or (out[0] as Vector3).distance_to(from) > 25.0:
		out = PackedVector3Array()
	out.append(act.pos)
	return out


## A route along the settlement's paths and through its doorways towards `to`, for chases
## that would otherwise cut through walls.
func route_to(d: NPCData, from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if d.info.nav_p.is_empty():
		return out
	out = settlements.find_path(d.info, settlements.nearest_nav(d.info, from), settlements.nearest_nav(d.info, to))
	out.append(to)
	return out


## True when a building stands between two points of this NPC's settlement.
func line_blocked(d: NPCData, a: Vector3, b: Vector3) -> bool:
	return not d.info.obbs.is_empty() and settlements._blocked(d.info, a, b)


func bridge_height(p: Vector3) -> float:
	return settlements.bridge_height(p)


func notify_door(npc: Node3D, p: Vector3) -> void:
	for b in npc.data.info.buildings:
		var door: Node3D = b.door
		if door and door.global_position.distance_squared_to(p) < 9.0:
			door.call("npc_pass")


# ------------------------------------------------------------------ streaming
func _process(delta: float) -> void:
	var pl: Node3D = Game.player_ref
	if pl == null:
		return
	_move_travellers(delta)
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = 0.2 if Assets.compat else 0.0      # one townsperson at a time in the browser
		_spawn_next(pl.global_position)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	_refresh_queue(pl.global_position)


## Who should be standing about near the player (queued, nearest built first); who has gone.
func _refresh_queue(pp: Vector3) -> void:
	_spawn_queue.clear()
	for d in all:
		if not d.alive and d.node == null:
			continue
		if d.node == null:
			if not d.traveler.is_empty():
				pass
			else:
				_place_virtual(d)
			if d.alive and d.pos.distance_squared_to(pp) < SPAWN_R * SPAWN_R:
				if activity_for(d).type != "absent":
					_spawn_queue.append(d)
		elif d.pos.distance_squared_to(pp) > DESPAWN_R * DESPAWN_R or (d.node.global_position.distance_squared_to(pp) > DESPAWN_R * DESPAWN_R):
			despawn(d)
		elif d.market_only and activity_for(d).type == "absent":
			despawn(d)
		else:
			d.pos = d.node.global_position


## Builds at most one queued character per frame (nearest first), so riding into a busy
## town never stalls on a burst of character models.
func _spawn_next(pp: Vector3) -> void:
	if _spawn_queue.is_empty() or active.size() >= MAX_ACTIVE:
		return
	var best := 0
	var bd := INF
	for i in _spawn_queue.size():
		var dd := _spawn_queue[i].pos.distance_squared_to(pp)
		if dd < bd:
			bd = dd
			best = i
	var d: NPCData = _spawn_queue[best]
	_spawn_queue.remove_at(best)
	if d.node == null and d.alive and bd < SPAWN_R * SPAWN_R:
		_spawn(d)


## Everyone near the player, built at once (behind the loading screen).
func spawn_nearby_now() -> void:
	var pl: Node3D = Game.player_ref
	if pl:
		_refresh_queue(pl.global_position)
		flush_spawns()


## Spawns everyone already queued (used by tests and teleports), up to the cap on active people
## (the rest wait in the queue for a free place, or this would never finish in a crowded town).
func flush_spawns() -> void:
	var pl: Node3D = Game.player_ref
	while not _spawn_queue.is_empty() and pl and active.size() < MAX_ACTIVE:
		_spawn_next(pl.global_position)


func _place_virtual(d: NPCData) -> void:
	if not d.traveler.is_empty():
		return
	var act := activity_for(d)
	if act.type == "loop":
		var loop: Array = act.loop
		d.pos = loop[d.id % loop.size()]
	elif act.has("pos"):
		d.pos = act.pos
	elif d.info.hubs.size() > 0:
		d.pos = d.info.nav_p[d.info.hubs[d.id % d.info.hubs.size()]]
	else:
		d.pos = d.info.center


func _spawn(d: NPCData) -> void:
	Game.mark("townsfolk spawn")
	var n := NPC.new()
	add_child(n)
	n.setup(d, self)
	d.node = n
	active.append(d)
	if d.mounted:
		var horse := Assets.instance_sized("res://assets/animals/%s.glb" % ("Horse_White" if d.id % 3 == 0 else "Horse"), 2.35, "xz")
		n.add_child(horse)
		n.mount = horse
		horse.rotation.y = 0.0
		n.model.position = Vector3(0, 1.08, -0.05)
		n.model.play("Driving", 0.0)
		var ap: AnimationPlayer = horse.find_children("*", "AnimationPlayer", true, false)[0]
		ap.play("Walk")
		horse.set_meta("ap", ap)
	if not d.alive:
		n.dead = true
		n.collision_layer = 0
		n.model.freeze_end("Death01")


func despawn(d: NPCData) -> void:
	if d.node and is_instance_valid(d.node):
		d.pos = d.node.global_position
		d.node.queue_free()
	d.node = null
	active.erase(d)


func _move_travellers(delta: float) -> void:
	var gm := delta * Game.minutes_per_second()
	for d in all:
		if d.traveler.is_empty() or not d.alive:
			continue
		var tr: Dictionary = d.traveler
		if d.escort_of != null:
			continue
		if d.node and (d.node as NPC).talking:
			continue
		if tr.wait > 0.0:
			tr.wait -= gm
			continue
		var pts: Array = tr.pts
		var speed := 3.4 if d.mounted else 1.45
		var i := int(tr.t)
		var j := clampi(i + int(tr.dir), 0, pts.size() - 1)
		var a := Vector3(pts[i][0], pts[i][1], pts[i][2])
		var b := Vector3(pts[j][0], pts[j][1], pts[j][2])
		var seg := maxf(a.distance_to(b), 0.5)
		tr.t = clampf(float(tr.t) + float(tr.dir) * speed * delta / seg, 0.0, float(pts.size() - 1))
		if (tr.dir > 0 and tr.t >= pts.size() - 1.001) or (tr.dir < 0 and tr.t <= 0.001):
			tr.wait = _rng.randf_range(30.0, 120.0)
			_next_road(d)
		_traveller_pose(d)
		for e in all:
			if e.escort_of == d:
				e.pos = d.pos - Vector3(sin(d.yaw), 0, cos(d.yaw)) * 5.0
				e.pos.y = WorldData.height_at(e.pos.x, e.pos.z)
				e.yaw = d.yaw
				if e.node:
					_pose_node(e)


func _next_road(d: NPCData) -> void:
	var tr: Dictionary = d.traveler
	var here: String = tr.road.b if tr.dir > 0 else tr.road.a
	var options := []
	for rd in WorldData.roads:
		if (rd.a == here or rd.b == here) and rd != tr.road:
			options.append(rd)
	if options.is_empty():
		tr.dir = -tr.dir
		return
	var rd: Dictionary = options[_rng.randi() % options.size()]
	tr.road = rd
	tr.pts = rd.pts
	tr.dir = 1 if rd.a == here else -1
	tr.t = 0.0 if tr.dir > 0 else float(rd.pts.size() - 1)


func _traveller_pose(d: NPCData) -> void:
	var tr: Dictionary = d.traveler
	var pts: Array = tr.pts
	var i := clampi(int(tr.t), 0, pts.size() - 2)
	var f := float(tr.t) - i
	var a := Vector3(pts[i][0], pts[i][1], pts[i][2])
	var b := Vector3(pts[i + 1][0], pts[i + 1][1], pts[i + 1][2])
	var p := a.lerp(b, f)
	p.y = WorldData.height_at(p.x, p.z)
	var bh := bridge_height(p)
	if bh > p.y - 2.0:
		p.y = maxf(p.y, bh)
	d.pos = p
	var dir := (b - a) * float(tr.dir)
	if dir.length_squared() > 0.001:
		d.yaw = atan2(dir.x, dir.z)
	if d.node:
		_pose_node(d)


func _pose_node(d: NPCData) -> void:
	var n: NPC = d.node
	if n.talking or n.dead or n.target:
		return
	n.global_position = d.pos
	n._yaw = lerp_angle(n._yaw, d.yaw, 0.15)
	if n.mount:
		n.mount.rotation.y = n._yaw
		n.model.rotation.y = n._yaw
		var ap = n.mount.get_meta("ap")
		var waiting: bool = d.traveler.get("wait", 0.0) > 0.0 if d.escort_of == null else d.escort_of.traveler.get("wait", 0.0) > 0.0
		if ap:
			ap.play("Idle" if waiting else "Walk", 0.3)
	else:
		n.model.rotation.y = n._yaw
		var waiting2: bool = d.traveler.get("wait", 0.0) > 0.0
		n.model.play("Idle" if waiting2 else "Walk", 0.2)


# ------------------------------------------------------------------ crime & combat
func find_target(npc: NPC) -> Node3D:
	var pl: Node3D = Game.player_ref
	var d: NPCData = npc.data
	if pl and not pl.get("dead"):
		var dist := pl.global_position.distance_to(npc.global_position)
		if d.hostile and dist < 22.0:
			return pl
		if d.role in ["knight", "guard"] and dist < 30.0 and Game.is_resisting(d.sname):
			return pl
	if d.role in ["knight", "guard"] or d.hostile:
		var w = Game.world_ref.wildlife
		if w and w.has_method("predator_near"):
			var a = w.call("predator_near", npc.global_position, 20.0)
			if a:
				return a
	return null


func player_attacked(npc: NPC) -> void:
	var d := npc.data
	if d.hostile:
		return
	var watch := d.role in ["knight", "guard"]
	if watch and Game.is_wanted_in(d.sname):
		# striking the watch while wanted is resisting arrest
		if not Game.is_resisting(d.sname):
			Game.resisting[d.sname] = true
			Game.notify.emit("You are resisting arrest in %s!" % d.sname, "warn")
			alert_guards(npc.global_position, d.sname)
		return
	var now := Time.get_ticks_msec()
	if now - d.warned_ms > 20000:
		# a single stray blow (a missed swing at a wolf, a crowded market) earns a warning
		d.warned_ms = now
		Game.change_reputation(-2.0, "")
		if Game.world_ref and Game.world_ref.hud:
			Game.world_ref.hud.call("show_subtitle", d.name, ["Watch it!", "Oi! Mind that blade!", "Are you mad? Put that away!", "Strike me again and I'll call the watch!"][randi() % 4], 3.0)
		return
	d.warned_ms = now
	Game.commit_crime(d.sname, 25.0 if d.role in ["knight", "guard", "duke", "official"] else 15.0, "You assaulted %s!" % d.name)
	alert_guards(npc.global_position, d.sname)


func npc_died(npc: NPC, source: Node) -> void:
	Game.mark("death")
	var d := npc.data
	if source == Game.player_ref:
		if d.hostile:
			Game.change_reputation(4.0, "Bandit slain")
			Game.kills["bandit"] = int(Game.kills.get("bandit", 0)) + 1
			QUESTS.on_bandit_killed(String(d.info.name), self)
		else:
			Game.commit_crime(d.sname, 40.0, "Murder! %s is dead." % d.name)
			alert_guards(npc.global_position, d.sname)


## The player is swinging: shield-bearers in front of them may get their guard up in time.
func incoming_blow(p: Node3D, power: bool) -> void:
	for d in active:
		if d.node and d.alive and (d.node as Node3D).global_position.distance_squared_to(p.global_position) < 12.0:
			(d.node as NPC).consider_block(p, power)


## How many are mid-swing at `t` right now (at most two attack the player at once).
func attackers_on(t: Node3D) -> int:
	var n := 0
	for d in active:
		if d.node and d.alive and (d.node as NPC).target == t and (d.node as NPC)._swinging > 0.0:
			n += 1
	return n


func witnesses(p: Vector3, r: float) -> int:
	var n := 0
	for d in active:
		if d.node and d.alive and not d.hostile and d.role != "guard" and (d.node as Node3D).global_position.distance_to(p) < r:
			n += 1
	return n


## Sends the nearest members of the watch (two in a village, three elsewhere) after the player:
## to arrest them, or to fight if they are resisting. Everyone else carries on with their day.
func alert_guards(p: Vector3, sname: String) -> void:
	if not Game.is_wanted_in(sname):
		return
	var near := []
	for d in active:
		if d.node and d.alive and d.role in ["knight", "guard"] and d.sname == sname and (d.node as Node3D).global_position.distance_to(p) < 90.0:
			near.append(d)
	near.sort_custom(func(a, b): return (a.node as Node3D).global_position.distance_squared_to(p) < (b.node as Node3D).global_position.distance_squared_to(p))
	var crew: Array = near.slice(0, _crew_size(sname))
	_pursuers[sname] = crew
	for d in crew:
		var n: NPC = d.node
		if Game.is_resisting(sname):
			n.target = Game.player_ref
		else:
			n.pursuing = true


func _crew_size(sname: String) -> int:
	var s := WorldData.settlement_by_name(sname)
	return 2 if String(s.get("type", "")) == "village" else 3


## True while this guard/knight should be closing in to arrest the player.
func should_arrest(npc: NPC) -> bool:
	var d := npc.data
	var pl: Node3D = Game.player_ref
	if pl == null or pl.get("dead") or not Game.is_wanted_in(d.sname) or Game.is_resisting(d.sname):
		return false
	var dist := pl.global_position.distance_to(npc.global_position)
	var crew: Array = _pursuers.get(d.sname, []).filter(func(c): return c.alive and c.node != null)
	if crew.has(d):
		return dist < 60.0
	if dist < 20.0 and crew.size() < _crew_size(d.sname):
		# a guard who spots a wanted player joins in, up to the crew size
		crew.append(d)
		_pursuers[d.sname] = crew
		return true
	return false


## The guard has caught up with the player: "Halt!" (pay the fine, serve time, or resist).
func confront(npc: NPC) -> void:
	var pl: Node3D = Game.player_ref
	if Game.in_menu or pl == null or pl.get("dead") or pl.get("mounted"):
		return
	npc.data.arresting = true
	open_dialogue(npc)


## Calls the watch off (fine paid, time served, or the player died).
func stand_down(sname: String) -> void:
	_pursuers.erase(sname)
	for d in active:
		if d.node and d.role in ["knight", "guard"] and (sname == "" or d.sname == sname):
			var n: NPC = d.node
			if n.target == Game.player_ref:
				n.target = null
			n.pursuing = false
			d.arresting = false


# ------------------------------------------------------------------ dialogue & horses
func open_dialogue(npc: NPC) -> void:
	npc.begin_talk()
	npc.data.met = true
	Game.world_ref.hud.menus.call("open_dialogue", npc)


func horses_at(sname: String) -> Array:
	var out := []
	for h in for_sale:
		if h.settlement == sname and not h.sold:
			out.append(h)
	return out


func buy_horse(h: Dictionary) -> bool:
	if not Game.pay(int(h.price) * Items.SILVER_PER_GOLD):
		return false
	h.sold = true
	var spec := {"id": h.id, "speed": h.speed, "white": h.white, "x": h.pos.x, "z": h.pos.z}
	Game.owned_horses.append(spec)
	if h.node and is_instance_valid(h.node):
		h.node.queue_free()
	var node := _make_horse(spec, true)
	node.global_position = h.pos
	player_horses.append(node)
	Game.notify.emit("You bought a %s horse! Press H to whistle for it." % ("white" if h.white else "bay"), "item")
	return true


func call_player_horse() -> void:
	if player_horses.is_empty():
		Game.notify.emit("You whistle, but you own no horse. Stables sell them for 30 to 60 gold.", "warn")
		return
	var h: Node3D = player_horses[0]
	h.call("come_to", Game.player_ref.global_position)
	Audio.play_at("whistle", Game.player_ref.global_position)
	Game.notify.emit("You whistle for your horse.", "info")


func _physics_process(_d: float) -> void:
	# keep stable horses for sale around the player
	var pl: Node3D = Game.player_ref
	if pl == null or Engine.get_physics_frames() % 30 != 0:
		return
	for h in for_sale:
		if h.sold:
			continue
		var near: bool = (h.pos as Vector3).distance_to(pl.global_position) < 110.0
		if near and h.node == null:
			h.node = _make_horse({"id": h.id, "speed": h.speed, "white": h.white, "price": h.price}, false)
			h.node.global_position = h.pos
			h.node.rotation.y = h.yaw
		elif not near and h.node != null:
			h.node.queue_free()
			h.node = null


func get_state() -> Dictionary:
	var horses := []
	for h in player_horses:
		if is_instance_valid(h):
			horses.append({"id": h.get("spec").id, "speed": h.get("spec").speed, "white": h.get("spec").white, "x": h.global_position.x, "z": h.global_position.z})
	Game.owned_horses = horses
	return {}


func set_state(_d: Dictionary) -> void:
	pass
