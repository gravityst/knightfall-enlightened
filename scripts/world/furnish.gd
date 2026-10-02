class_name Furnish
## Interior layouts per building type. Places kit furniture, interactive beds / chests,
## hearths & lights, and registers NPC spots (beds, work places, seats, horse stalls).

const P := "res://assets/props/"
const V := "res://assets/village/"

const LOOT := {
	"house": [["bread", 0.6, 1, 2], ["apple", 0.5, 1, 4], ["cheese", 0.3, 1, 1], ["silver_ring", 0.05, 1, 1], ["wool_cloak", 0.06, 1, 1], ["candle", 0.0, 0, 0]],
	"tavern": [["ale", 0.7, 1, 4], ["wine", 0.4, 1, 2], ["bread", 0.5, 1, 3], ["cheese", 0.3, 1, 2]],
	"blacksmith": [["iron_sword", 0.25, 1, 1], ["wooden_shield", 0.3, 1, 1], ["leather_armor", 0.12, 1, 1]],
	"shop": [["apple", 0.5, 2, 6], ["bandage", 0.4, 1, 3], ["torch", 0.5, 1, 3], ["wine", 0.2, 1, 1]],
	"warehouse": [["firewood", 0.6, 3, 8], ["bread", 0.4, 2, 4], ["torch", 0.4, 1, 4], ["wool_cloak", 0.1, 1, 1]],
	"keep": [["gold_necklace", 0.6, 1, 1], ["ruby", 0.4, 1, 1], ["emerald", 0.3, 1, 1], ["silk_cloak", 0.1, 1, 1], ["wine", 0.6, 1, 3]],
	"barracks": [["chainmail", 0.1, 1, 1], ["leather_armor", 0.25, 1, 1], ["bandage", 0.6, 1, 3], ["iron_sword", 0.2, 1, 1]],
	"kitchen": [["bread", 0.8, 2, 5], ["cheese", 0.6, 1, 3], ["stew", 0.5, 1, 2], ["apple", 0.6, 2, 6], ["carrot", 0.6, 2, 6]],
	"chapel": [["bandage", 0.6, 1, 3], ["healing_draught", 0.3, 1, 1], ["ancient_coin", 0.2, 1, 2]],
	"ruin": [["ancient_coin", 0.7, 1, 4], ["ruby", 0.2, 1, 1], ["emerald", 0.15, 1, 1], ["steel_longsword", 0.15, 1, 1], ["gold_necklace", 0.2, 1, 1], ["healing_draught", 0.4, 1, 2]],
	"bandit": [["silver_ring", 0.4, 1, 2], ["iron_sword", 0.3, 1, 1], ["wine", 0.5, 1, 2], ["cooked_meat", 0.5, 1, 3], ["ancient_coin", 0.3, 1, 3]],
}
const SILVER := {"house": [3, 24], "tavern": [10, 45], "blacksmith": [12, 60], "shop": [10, 50], "warehouse": [0, 20], "keep": [120, 360],
	"barracks": [8, 40], "kitchen": [0, 10], "chapel": [5, 30], "ruin": [30, 180], "bandit": [40, 140]}


static func furnish(r: Builder.Result, t: String, W: int, D: int, floors: int, style: String, settlement: String, rng: RandomNumberGenerator, center_i: int) -> void:
	var hw := W * 0.5
	var hd := D * 0.5
	var centers := [center_i]
	for f in range(1, floors):
		var c := r.add_nav(r.xform * Vector3(-hw * 0.3, f * 3.0 + 0.05, -hd * 0.3))
		centers.append(c)
	for f in floors - 1:
		var st: Array = r.get_meta("stair_%d" % f)
		r.link(st[0], centers[f])
		r.link(st[1], centers[f + 1])
	var stairs := floors > 1
	var cold := style == "cold"
	match t:
		"house", "cabin":
			_hearth(r, Vector3(-hw * 0.2, 0, -hd * 0.12), centers[0])
			_put(r, P + "Table_Large.gltf", Vector3(-hw + 1.05, 0, hd * 0.3), PI * 0.5)
			_sit(r, P + "Stool.gltf", Vector3(-hw + 1.95, 0, hd * 0.3 + 0.7), -PI * 0.5, centers[0])
			_sit(r, P + "Stool.gltf", Vector3(-hw + 1.95, 0, hd * 0.3 - 0.7), -PI * 0.5, centers[0])
			_put(r, P + "Mug.gltf", Vector3(-hw + 1.0, 0.81, hd * 0.3 + 0.4), 0.0)
			_put(r, P + "Table_Plate.gltf", Vector3(-hw + 1.1, 0.81, hd * 0.3 - 0.5), 0.0)
			_put(r, P + "Cabinet.gltf", Vector3(-hw * 0.35, 0, -hd + 0.55), 0.0)
			if not stairs:
				_put(r, P + "Barrel.gltf", Vector3(hw - 0.75, 0, hd - 1.0), 0.0)
			_work(r, Vector3(-hw * 0.2, 0, -hd * 0.12 + 1.2), PI, "Interact", "hearth", centers[0])
			var bf: int = floors - 1
			var by := bf * 3.0
			var bc: int = centers[bf]
			var bed_x := hw - 1.3 if not (stairs and bf == 0) else -hw + 1.3
			_bed(r, Vector3(bed_x, by, -hd + 1.55), 0.0, bc, settlement, false)
			if W >= 6:
				_bed(r, Vector3(-bed_x if bf > 0 else 0.0, by, -hd + 1.55), 0.0, bc, settlement, false)
			_chest(r, Vector3(bed_x, by, -hd + 3.25), PI, "house", settlement, bc)
			if bf > 0:
				_put(r, P + "Nightstand_Shelf.gltf", Vector3(-hw + 0.5, by, 0.5), PI * 0.5)
			if cold:
				_firewood(r, Vector3(hw + 0.7, 0, 0), PI * 0.5, rng)
		"tavern":
			_hearth(r, Vector3(-hw + 1.3, 0, -1.0), centers[0])
			_put(r, P + "Table_Large.gltf", Vector3(-0.6, 0, -hd + 2.7), 0.0)
			_put(r, P + "Barrel_Holder.gltf", Vector3(-1.8, 0, -hd + 0.75), 0.0)
			_put(r, P + "Barrel_Holder.gltf", Vector3(0.3, 0, -hd + 0.75), 0.0)
			_put(r, P + "Shelf_Small_Bottles.gltf", Vector3(-1.0, 1.5, -hd + 0.42), 0.0)
			_put(r, P + "Mug.gltf", Vector3(-1.2, 0.81, -hd + 2.6), 0.3)
			_put(r, P + "Mug.gltf", Vector3(0.1, 0.81, -hd + 2.75), 1.2)
			_put(r, P + "Bottle_1.gltf", Vector3(-0.4, 0.81, -hd + 2.5), 0.0)
			_work(r, Vector3(-0.6, 0, -hd + 1.7), 0.0, "Idle_Talking", "barkeep", centers[0])
			for i in 3:
				var tz := -hd + 5.4 + i * 2.6
				if tz > hd - 1.6:
					break
				_put(r, P + "Table_Large.gltf", Vector3(-0.7, 0, tz), 0.0)
				_sit(r, P + "Bench.gltf", Vector3(-0.7, 0, tz - 0.85), 0.0, centers[0])
				_sit(r, P + "Bench.gltf", Vector3(-0.7, 0, tz + 0.85), PI, centers[0])
				_put(r, P + "Mug.gltf", Vector3(-0.2 + i * 0.3, 0.81, tz), float(i))
				_put(r, P + "CandleStick.gltf", Vector3(-1.4, 0.81, tz), 0.0)
			_put(r, P + "Chandelier.gltf", Vector3(-0.5, 2.98, 0.5), 0.0, true, 0.55)
			_light(r, Vector3(-0.5, 2.2, 0.5), 1.4, 9.0, false)
			var by := 3.0
			for i in 3:
				_bed(r, Vector3(-hw + 1.3, by, -hd + 1.6 + i * 3.4), PI * 0.5 * 0.0, centers[1], settlement, true)
			_chest(r, Vector3(-hw + 1.3, by, -hd + 3.2), 0.0, "tavern", settlement, centers[1])
			_put(r, P + "Nightstand_Shelf.gltf", Vector3(-1.0, by, -hd + 0.5), 0.0)
			_light(r, Vector3(-1.0, by + 2.3, 0.0), 0.8, 7.0, false)
		"blacksmith":
			_put(r, P + "Workbench.gltf", Vector3(-hw + 0.85, 0, 0.0), PI * 0.5)
			_put(r, P + "WeaponStand.gltf", Vector3(0.5, 0, -hd + 0.85), 0.0)
			_put(r, P + "Whetstone.gltf", Vector3(-hw + 1.0, 0, -hd + 1.2), 0.0)
			_chest(r, Vector3(hw - 1.0, 0, -hd + 0.75), 0.0, "blacksmith", settlement, centers[0])
			_put(r, P + "Barrel.gltf", Vector3(hw - 0.7, 0, -hd + 2.0), 0.0)
			_work(r, Vector3(-hw + 1.8, 0, 0.0), -PI * 0.5, "Interact", "smith_bench", centers[0])
			# outdoor forge beside the door
			var forge := Vector3(hw + 2.0, 0, hd - 1.8)
			_put(r, P + "Anvil_Log.gltf", forge, 0.4)
			_hearth(r, forge + Vector3(0, 0, -2.0), centers[0], 1.4)
			_put(r, P + "Bucket_Metal.gltf", forge + Vector3(1.0, 0, 0.6), 0.0)
			var o := r.add_nav(r.xform * (forge + Vector3(-1.1, 0.05, 0.3)))
			r.link(o, r.door_out)
			r.spots.work.append({"p": r.xform * (forge + Vector3(-0.9, 0, 0.2)), "yaw": float(r.data.yaw) + PI * 0.5, "anim": "Interact", "tag": "smith", "nav": o})
			_light(r, Vector3(0, 2.4, 0), 0.9, 7.0, false)
		"stable":
			for z in [-hd + 3.2, -hd + 6.4]:
				if z < hd - 1.0:
					for x in [-1.0, 1.0]:
						_put(r, V + "Prop_WoodenFence_Single.gltf", Vector3(x, 0, z), 0.0)
			_put(r, P + "Bag.gltf", Vector3(-hw + 0.6, 0, -hd + 0.6), 0.3)
			_put(r, P + "Crate_Wooden.gltf", Vector3(hw - 0.75, 0, -hd + 0.75), 0.0)
			_put(r, P + "Bucket_Wooden_1.gltf", Vector3(hw - 0.6, 0, -hd + 2.0), 0.0)
			r.spots["horses"] = []
			var z0 := -hd + 1.7
			while z0 < hd - 1.2:
				r.spots.horses.append({"p": r.xform * Vector3(0.2, 0, z0), "yaw": float(r.data.yaw) + PI * 0.5})
				z0 += 3.2
			_work(r, Vector3(0, 0, hd + 1.2), PI, "Idle", "stablemaster", r.door_out)
		"chapel":
			var az := -hd + 1.5
			_put(r, P + "Table_Large.gltf", Vector3(0, 0, az), 0.0)
			_put(r, P + "CandleStick_Triple.gltf", Vector3(-0.8, 0.81, az), 0.0)
			_put(r, P + "CandleStick_Triple.gltf", Vector3(0.8, 0.81, az), 0.0)
			_put(r, P + "CandleStick_Stand.gltf", Vector3(-hw + 0.8, 0, az), 0.0)
			_put(r, P + "CandleStick_Stand.gltf", Vector3(hw - 0.8, 0, az), 0.0)
			_put(r, P + "Banner_1.gltf", Vector3(0, 2.9, -hd + 0.38), 0.0)
			_put(r, P + "BookStand.gltf", Vector3(0, 0, az + 1.6), PI)
			_work(r, Vector3(0, 0, az + 2.4), PI, "Idle_Talking", "priest", centers[0])
			var z := az + 3.6
			while z < hd - 1.5:
				for x in [-1.6, 1.6]:
					if W >= 8:
						x *= 1.3
					_sit(r, P + "Bench.gltf", Vector3(x, 0, z), PI, centers[0])
				z += 1.6
			_light(r, Vector3(0, 2.0, az + 0.5), 1.0, 8.0, false)
			_chest(r, Vector3(hw - 1.0, 0, az), 0.0, "chapel", settlement, centers[0])
		"shop":
			var cz := hd - 2.4
			_put(r, P + "Table_Large.gltf", Vector3(0, 0, cz), 0.0)
			_put(r, P + "FarmCrate_Apple.gltf", Vector3(-0.8, 0.81, cz), 0.2)
			_put(r, P + "Vase_4.gltf", Vector3(0.6, 0.81, cz), 0.0)
			_put(r, P + "Potion_2.gltf", Vector3(0.1, 0.81, cz + 0.2), 0.0)
			_put(r, P + "Book_Stack_1.gltf", Vector3(1.0, 0.81, cz - 0.2), 0.5)
			_put(r, P + "Bookcase_2.gltf", Vector3(-1.0, 0, -hd + 0.55), 0.0)
			_put(r, P + "Shelf_Small_Bottles.gltf", Vector3(-hw + 0.45, 1.4, -0.5), PI * 0.5)
			_put(r, P + "Shelf_Simple.gltf", Vector3(-hw + 0.45, 1.9, -0.5), PI * 0.5)
			_put(r, P + "Crate_Wooden.gltf", Vector3(hw - 0.8, 0, -hd + 0.8), 0.3)
			_put(r, P + "Barrel_Apples.gltf", Vector3(hw - 0.7, 0, -hd + 2.0), 0.0)
			_chest(r, Vector3(1.0, 0, -hd + 0.75), 0.0, "shop", settlement, centers[0])
			_work(r, Vector3(0, 0, cz - 1.0), 0.0, "Idle", "shopkeeper", centers[0])
			if stairs:
				_bed(r, Vector3(-hw + 1.3, 3.0, -hd + 1.6), 0.0, centers[1], settlement, false)
		"townhall":
			for i in 2:
				_put(r, P + "Table_Large.gltf", Vector3(-0.6, 0, -2.0 + i * 2.9), PI * 0.5)
				for s in [-1.0, 1.0]:
					_sit(r, P + "Chair_1.gltf", Vector3(-0.6 + s * 0.95, 0, -2.6 + i * 2.9), PI * 0.5 * -s, centers[0])
					_sit(r, P + "Chair_1.gltf", Vector3(-0.6 + s * 0.95, 0, -1.3 + i * 2.9), PI * 0.5 * -s, centers[0])
			_put(r, P + "Banner_2.gltf", Vector3(-1.6, 2.9, -hd + 0.38), 0.0)
			_put(r, P + "Banner_2.gltf", Vector3(1.0, 2.9, -hd + 0.38), 0.0)
			_put(r, P + "Bookcase_2.gltf", Vector3(-hw + 0.5, 0, -hd + 2.5), PI * 0.5)
			_put(r, P + "Chandelier.gltf", Vector3(-0.6, 2.98, 0), 0.0, true, 0.55)
			_light(r, Vector3(-0.6, 2.2, 0), 1.2, 9.0, false)
			_work(r, Vector3(-0.6, 0, -hd + 1.4), 0.0, "Idle_Talking", "official", centers[0])
			_chest(r, Vector3(-hw + 1.0, 0, hd - 1.0), PI, "shop", settlement, centers[0])
			if stairs:
				_put(r, P + "Table_Large.gltf", Vector3(-hw + 1.2, 3.0, 0), PI * 0.5)
				_put(r, P + "BookStand.gltf", Vector3(-1.0, 3.0, -hd + 1.0), 0.0)
				_bed(r, Vector3(-hw + 1.3, 3.0, -hd + 1.6), 0.0, centers[1], settlement, false)
				_bed(r, Vector3(0.3, 3.0, -hd + 1.6), 0.0, centers[1], settlement, false)
				_work(r, Vector3(-hw + 2.4, 3.0, 0), -PI * 0.5, "Idle_Talking", "official", centers[1])
		"barracks":
			var z := -hd + 1.6
			while z < hd - 2.0:
				_bed(r, Vector3(-hw + 1.3, 0, z), PI * 0.5, centers[0], settlement, false)
				_bed(r, Vector3(hw - 1.3, 0, z), -PI * 0.5, centers[0], settlement, false)
				z += 2.4
			_put(r, P + "WeaponStand.gltf", Vector3(0, 0, -hd + 0.8), 0.0)
			_chest(r, Vector3(0, 0, hd - 2.2), PI, "barracks", settlement, centers[0])
			_light(r, Vector3(0, 2.3, 0), 0.9, 8.0, false)
		"warehouse":
			for i in 7:
				var p := Vector3(rng.randf_range(-hw + 1.0, hw - 1.0), 0, rng.randf_range(-hd + 1.0, hd - 2.5))
				_put(r, P + ["Crate_Wooden.gltf", "Barrel.gltf", "Bag.gltf", "Crate_Metal.gltf"][i % 4], p, rng.randf() * TAU)
			_chest(r, Vector3(hw - 1.0, 0, -hd + 0.75), 0.0, "warehouse", settlement, centers[0])
			_work(r, Vector3(0, 0, hd - 2.0), 0.0, "PickUp_Table", "porter", centers[0])
		"kitchen":
			_hearth(r, Vector3(-hw + 1.4, 0, -hd + 1.6), centers[0])
			_put(r, P + "Cauldron.gltf", Vector3(-hw + 1.4, 0.15, -hd + 1.6), 0.0)
			_put(r, P + "Table_Large.gltf", Vector3(0.6, 0, 0.6), PI * 0.5)
			_put(r, P + "FarmCrate_Carrot.gltf", Vector3(0.6, 0.81, 0.0), 0.0)
			_put(r, P + "FarmCrate_Apple.gltf", Vector3(0.6, 0.81, 1.3), 0.0)
			_put(r, P + "Pot_1_Lid.gltf", Vector3(0.5, 0.81, -0.6), 0.0)
			_put(r, P + "Barrel_Apples.gltf", Vector3(hw - 0.7, 0, -hd + 0.8), 0.0)
			_put(r, P + "Shelf_Simple.gltf", Vector3(hw - 0.4, 1.6, 0.0), -PI * 0.5)
			_put(r, P + "Bucket_Wooden_1.gltf", Vector3(-hw + 0.6, 0, 0.6), 0.0)
			_work(r, Vector3(-hw + 1.4, 0, -hd + 2.9), PI, "Interact", "cook", centers[0])
			_work(r, Vector3(-0.5, 0, 0.6), PI * 0.5, "PickUp_Table", "cook", centers[0])
			_chest(r, Vector3(hw - 1.0, 0, hd - 1.5), PI, "kitchen", settlement, centers[0])
		"mews":
			_put(r, P + "Cage_Small.gltf", Vector3(-hw + 0.7, 0, -hd + 0.8), 0.0)
			_put(r, P + "Cage_Small.gltf", Vector3(hw - 0.7, 0, -hd + 0.8), 0.0)
			_put(r, P + "Peg_Rack.gltf", Vector3(-hw + 0.35, 1.5, 0.5), PI * 0.5)
			_put(r, P + "Bucket_Wooden_1.gltf", Vector3(hw - 0.6, 0, 1.0), 0.0)
			for i in 2:
				var perch := Vector3(-0.6 + i * 1.2, 0, -hd + 2.4)
				_put(r, V + "Prop_Support.gltf", perch + Vector3(0, -0.6, 0), PI * 0.5, false)
				r.spots["perches"] = r.spots.get("perches", []) + [r.xform * (perch + Vector3(0, 1.12, 0))]
			_work(r, Vector3(0, 0, 0.8), 0.0, "Idle", "falconer", centers[0])
		"keep":
			# great hall with the ducal throne
			var tz := -hd + 1.5
			_sit(r, P + "Chair_1.gltf", Vector3(0, 0.0, tz), 0.0, centers[0], 1.45, "throne")
			_put(r, P + "Banner_1.gltf", Vector3(-1.6, 2.95, -hd + 0.4), 0.0)
			_put(r, P + "Banner_1.gltf", Vector3(1.6, 2.95, -hd + 0.4), 0.0)
			_put(r, P + "CandleStick_Stand.gltf", Vector3(-1.4, 0, tz + 0.3), 0.0)
			_put(r, P + "CandleStick_Stand.gltf", Vector3(1.4, 0, tz + 0.3), 0.0)
			for i in 3:
				var z := -hd + 4.2 + i * 2.9
				if z > hd - 2.0:
					break
				_put(r, P + "Table_Large.gltf", Vector3(-0.9, 0, z), PI * 0.5)
				_sit(r, P + "Chair_1.gltf", Vector3(-1.9, 0, z), PI * 0.5, centers[0])
				_sit(r, P + "Chair_1.gltf", Vector3(0.1, 0, z), -PI * 0.5, centers[0])
				_put(r, P + "Chalice.gltf", Vector3(-0.9, 0.81, z - 0.5), 0.0)
				_put(r, P + "Table_Plate.gltf", Vector3(-0.9, 0.81, z + 0.4), 0.0)
			_put(r, P + "Chandelier.gltf", Vector3(-0.9, 2.98, 0), 0.0, true, 0.55)
			_light(r, Vector3(0, 2.0, tz + 1.5), 1.3, 9.0, true)
			_light(r, Vector3(-0.9, 2.1, 2.0), 1.0, 9.0, false)
			_work(r, Vector3(-1.3, 0, tz + 1.4), PI * 0.15, "Idle_Talking", "official", centers[0])
			_work(r, Vector3(1.4, 0, tz + 1.6), -PI * 0.15, "Idle_Talking", "official", centers[0])
			_work(r, Vector3(-1.6, 0, tz + 0.6), 0.0, "Sword_Idle", "throne_guard", centers[0])
			_work(r, Vector3(1.6, 0, tz + 0.6), 0.0, "Sword_Idle", "throne_guard", centers[0])
			# ducal chamber
			if floors > 1:
				_bed(r, Vector3(-hw + 1.6, 3.0, -hd + 1.8), 0.0, centers[1], settlement, false, 1.25)
				_put(r, P + "Nightstand_Shelf.gltf", Vector3(-hw + 3.1, 3.0, -hd + 0.5), 0.0)
				_put(r, P + "Bookcase_2.gltf", Vector3(-hw + 0.5, 3.0, 1.5), PI * 0.5)
				_put(r, P + "Banner_2.gltf", Vector3(0.2, 5.95, -hd + 0.4), 0.0)
				_chest(r, Vector3(-hw + 1.6, 3.0, -hd + 3.6), PI, "keep", settlement, centers[1])
				_light(r, Vector3(-1.0, 5.2, -1.0), 0.8, 7.0, false)
			if floors > 2:
				for i in 3:
					_bed(r, Vector3(-hw + 1.3, 6.0, -hd + 1.6 + i * 2.6), PI * 0.5, centers[2], settlement, false)
				_put(r, P + "Table_Large.gltf", Vector3(0.0, 6.0, 1.5), PI * 0.5)
				_chest(r, Vector3(-hw + 1.0, 6.0, hd - 1.5), PI, "house", settlement, centers[2])
				_light(r, Vector3(-1.0, 8.2, 0.0), 0.7, 7.0, false)


static func ruin_props(r: Builder.Result, W: int, D: int, rng: RandomNumberGenerator) -> void:
	for i in 5:
		var p := Vector3(rng.randf_range(-W * 0.4, W * 0.4), 0, rng.randf_range(-D * 0.4, D * 0.4))
		_put(r, P + ["Vase_Rubble_Medium.gltf", "Crate_Wooden.gltf", "Barrel.gltf"][i % 3], p, rng.randf() * TAU)
		for k in 3:
			_put(r, V + ["Prop_Brick1.gltf", "Prop_Brick2.gltf", "Prop_Brick3.gltf"][k], p + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), rng.randf() * TAU)
	if rng.randf() < 0.75:
		_chest(r, Vector3(rng.randf_range(-W * 0.3, W * 0.3), 0, -D * 0.5 + 1.0), 0.0, "ruin", "", -1)


# ------------------------------------------------------------------ helpers
static func _put(r: Builder.Result, path: String, lp: Vector3, yaw: float, interior := true, scale := 1.0) -> void:
	var xf := r.xform * Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), lp)
	if interior:
		r.inn.add(path, xf)
	else:
		r.ext.add(path, xf)


static func _nav_near(r: Builder.Result, lp: Vector3, link_to: int) -> int:
	var n := r.add_nav(r.xform * (lp + Vector3(0, 0.05, 0)))
	r.link(n, link_to)
	return n


static func _work(r: Builder.Result, lp: Vector3, yaw: float, anim: String, tag: String, link_to: int) -> void:
	var n := _nav_near(r, lp, link_to)
	r.spots.work.append({"p": r.xform * lp, "yaw": float(r.data.yaw) + yaw, "anim": anim, "tag": tag, "nav": n})


static func _sit(r: Builder.Result, path: String, lp: Vector3, yaw: float, link_to: int, scale := 1.0, tag := "") -> void:
	_put(r, path, lp, yaw, true, scale)
	var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.7)
	var n := _nav_near(r, lp + fwd, link_to)
	r.spots.sit.append({"p": r.xform * lp, "yaw": float(r.data.yaw) + yaw, "nav": n, "tag": tag})


static func _bed(r: Builder.Result, lp: Vector3, yaw: float, link_to: int, settlement: String, inn: bool, scale := 1.0) -> void:
	_put(r, P + "Bed_Twin1.gltf", lp, yaw, true, scale)
	var b := Interactables.Bed.new()
	b.collision_layer = 1 | 32
	b.collision_mask = 0
	b.inn = inn
	b.settlement = settlement
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.8, 0.62, 2.3) * scale
	cs.shape = bx
	cs.position = Vector3(0, 0.31 * scale, 0)
	b.add_child(cs)
	b.transform = Transform3D(Basis(Vector3.UP, yaw), lp)
	r.root.add_child(b)
	var side := Basis(Vector3.UP, yaw) * Vector3(1.3 * scale, 0, 0)
	var n := _nav_near(r, lp + side, link_to)
	r.spots.beds.append({"p": r.xform * (lp + Vector3(0, 0.62 * scale, 0)), "yaw": float(r.data.yaw) + yaw, "nav": n, "node": b, "inn": inn})


static func _chest(r: Builder.Result, lp: Vector3, yaw: float, table: String, settlement: String, link_to: int) -> void:
	_put(r, P + "Chest_Wood.gltf", lp, yaw)
	var c := Interactables.Chest.new()
	c.collision_layer = 1 | 32
	c.collision_mask = 0
	c.settlement = settlement
	var wp := r.xform * lp
	c.chest_id = "%d_%d_%d" % [int(wp.x * 10), int(wp.y * 10), int(wp.z * 10)]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c.chest_id)
	for e in LOOT.get(table, []):
		if rng.randf() < float(e[1]):
			c.loot[e[0]] = rng.randi_range(int(e[2]), int(e[3]))
	var sv: Array = SILVER.get(table, [0, 10])
	c.silver = rng.randi_range(int(sv[0]), int(sv[1]))
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.25, 0.7, 0.75)
	cs.shape = bx
	cs.position = Vector3(0, 0.35, 0)
	c.add_child(cs)
	c.transform = Transform3D(Basis(Vector3.UP, yaw), lp)
	r.root.add_child(c)
	r.spots.chests.append(c)


static func _hearth(r: Builder.Result, lp: Vector3, link_to: int, size := 1.0) -> void:
	_put(r, "res://assets/items/stone_fire_pit/stone_fire_pit.gltf", lp, 0.0, true, size)
	var fx := FireFX.flames(0.32 * size, 0.8 * size)
	fx.position = lp + Vector3(0, 0.12, 0)
	r.root.add_child(fx)
	r.fires.append(fx)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.56, 0.24)
	l.light_energy = 2.4
	l.omni_range = 8.5
	l.omni_attenuation = 1.4
	l.shadow_enabled = not Assets.compat
	l.position = lp + Vector3(0, 0.9, 0)
	l.set_meta("flicker", true)
	r.root.add_child(l)
	r.lights.append(l)


static func _light(r: Builder.Result, lp: Vector3, energy: float, rng: float, shadow: bool) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.42)
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	l.position = lp
	r.root.add_child(l)
	r.lights.append(l)


static func _firewood(r: Builder.Result, lp: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	# stacked split logs (log pieces scaled from the kit's roof log)
	for row in 4:
		for i in 5 - row % 2:
			var p := lp + Basis(Vector3.UP, yaw) * Vector3(-0.9 + i * 0.42 + (0.21 if row % 2 else 0.0), 0.22 + row * 0.36, 0)
			var xf := r.xform * Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.36, 0.3, 0.075)), p)
			r.ext.add(V + "Roof_Log.gltf", xf)
