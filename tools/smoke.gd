extends Node
const QUESTS := preload("res://scripts/core/quests.gd")
## Automated gameplay smoke test (run with: -- --smoke). Exercises dialogue, trade, horses,
## riding, combat, hunting, survival, weather, menus and save/load, then quits.

var w: Node3D
var log_lines := []


func say(s: String) -> void:
	print("SMOKE: ", s)


func _ready() -> void:
	w = get_parent()
	_run()


func wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _run() -> void:
	await wait(10)
	var pl: Player = w.player
	var town: Dictionary = WorldData.settlement_by_name("Kingsbridge")
	pl.global_position = Vector3(town.x + 8, WorldData.height_at(town.x + 8, town.z + 8) + 0.5, town.z + 8)
	Game.minutes = 1440.0 * 2 + 11 * 60.0
	await wait(90)
	var npcs = w.npcs
	npcs.flush_spawns()
	await wait(5)
	say("active npcs: %d / total %d" % [npcs.active.size(), npcs.all.size()])
	# --- dialogue with each role present
	var seen := {}
	for d in npcs.active:
		if d.node == null or seen.has(d.role):
			continue
		seen[d.role] = true
		var n: NPC = d.node
		say("talk %s (%s, %s): %s" % [d.name, d.role, d.personality, n.get_interaction(pl)])
		for t in Dialogue.topics(d):
			if t[0] in ["horse", "trade"]:
				continue
			var r := Dialogue.respond(n, t[0])
			say("   %s -> %s" % [t[0], String(r.get("text", "")).left(70)])
	# --- dialogue UI, trade UI
	for d in npcs.active:
		if d.node and not d.stock.is_empty() and d.role in ["merchant", "shopkeeper", "tavern_owner", "blacksmith"]:
			var menus = w.hud.menus
			menus.open_dialogue(d.node)
			await wait(3)
			menus.open_trade(d.node)
			await wait(3)
			Game.earn(500)
			var id: String = d.stock.keys()[0]
			menus._trade(id, "buy", 3)
			menus._trade(id, "sell", 1)
			say("traded with %s; has %s: %s" % [d.name, id, Game.has_item(id)])
			menus.close()
			break
	# --- horses
	var bought := false
	for h in npcs.for_sale:
		if h.settlement == "Kingsbridge" and not h.sold:
			Game.earn(70 * 12)
			bought = npcs.buy_horse(h)
			break
	say("bought horse: %s, owned=%d" % [bought, npcs.player_horses.size()])
	if npcs.player_horses.size() > 0:
		var horse: Node3D = npcs.player_horses[0]
		horse.global_position = pl.global_position + Vector3(2, 0, 0)
		npcs.call_player_horse()
		await wait(20)
		horse.interact(pl)
		say("mounted: %s" % (pl.mounted != null))
		Input.action_press("move_forward")
		for i in 300:
			if i == 40:
				Input.action_press("sprint")
			if i % 30 == 0:
				say("   ride t=%d speed %.1f halt %.2f grade %.2f wall %s floor %s pos %s" % [i, horse.speed, horse._halt, horse._grade(Vector3(sin(horse._yaw), 0, cos(horse._yaw))), horse.is_on_wall(), horse.is_on_floor(), horse.global_position.snapped(Vector3.ONE * 0.1)])
			await get_tree().physics_frame
		say("horse speed while riding %.1f" % horse.speed)
		Input.action_release("move_forward")
		Input.action_release("sprint")
		say("horse speed after ride %.1f pos %s" % [horse.speed, horse.global_position])
		pl.dismount()
		say("dismount at speed refused: %s" % (pl.mounted != null))
		Input.action_press("move_back")        # rein in
		for i in 240:
			if absf(horse.speed) < 1.0:
				break
			await get_tree().physics_frame
		Input.action_release("move_back")
		say("horse reined in to %.1f, stamina %.0f" % [horse.speed, horse.stamina])
		pl.dismount()
		say("dismounted: %s" % (pl.mounted == null))
		if "--quick-horse" in OS.get_cmdline_user_args():
			get_tree().quit()
			return
	# --- combat & hunting
	var wl = w.wildlife
	var g: Dictionary = wl._spawn_group("wolf", pl.global_position + Vector3(0, 0, -6))
	await wait(10)
	pl.weapon_drawn = true
	Game.equipped.weapon = "rusty_sword"
	for wolf in g.members:
		for k in 12:
			if wolf.dead:
				break
			wolf.take_damage(15.0, pl)
		say("wolf dead: %s" % wolf.dead)
		wolf.interact(pl)
	say("pelts: %d meat: %d" % [int(Game.inventory.get("wolf_pelt", 0)), int(Game.inventory.get("raw_meat", 0))])
	# light and heavy blows, a parry and a dodge
	pl.weapon_drawn = true
	pl._swing(false)
	await wait(40)
	pl._swing(true)
	await wait(50)
	var g2: Dictionary = wl._spawn_group("wolf", pl.global_position - pl.global_transform.basis.z * 2.5)
	var foe: Node3D = g2.members[0]
	foe.global_position = pl.global_position - pl.global_transform.basis.z * 2.0
	var hp0 := float(Game.stats.health)
	pl._blocking = true
	pl._parry_t = 0.2
	pl.take_damage(12.0, foe)
	say("parried: %s" % (absf(float(Game.stats.health) - hp0) < 0.01))
	pl._dodge(Vector2(1, 0))
	say("dodge i-frames: %s" % (pl._iframes > 0.0))
	await wait(30)
	for a in g2.members:
		a.take_damage(500.0, pl, false, 4.0)
	# a body going limp: ragdoll physics, then the pose kept
	var dummy := CharacterModel.new()
	w.add_child(dummy)
	dummy.build({"gender": "m", "outfit": "Ranger", "sword": true, "steel": 0.6})
	dummy.global_position = pl.global_position - pl.global_transform.basis.z * 4.0
	await wait(2)
	var pelvis0 := dummy.skeleton.get_bone_global_pose(dummy.skeleton.find_bone("pelvis")).origin
	say("ragdoll started: %s" % dummy.ragdoll(Vector3(0, 1.0, 3.0)))
	await wait(70)
	var lay := dummy.settle_ragdoll()
	say("ragdoll settled at %s (fell %.2f m)" % [lay.snapped(Vector3.ONE * 0.01), dummy.global_position.y + pelvis0.y - lay.y])
	dummy.queue_free()
	pl.take_damage(5.0, null)
	# --- survival
	say(Game.use_item("bread"))
	say(Game.use_item("waterskin"))
	pl.place_campfire()
	await wait(5)
	say("near fire: %s; cooked: %d" % [pl.is_near_fire(), Game.cook_all()])
	say(Game.use_item("wool_cloak"))
	say(Game.use_item("wool_cloak"))
	Game.add_item("bandage")
	Game.add_item("campfire_kit")
	Game.stats.health = 60.0
	for k in 4:
		pl.quick_use(k)
	say("quick use: health %.0f, fires %d" % [Game.stats.health, w.fires.size()])
	var t0 := Game.minutes
	await w.wait_hour()
	say("waited %.0f min" % (Game.minutes - t0))
	await w.sleep(8.0, true)
	say("after sleep %s day %d" % [Game.clock_text(), Game.day()])
	# --- weather & night
	for wn in ["rain", "storm", "snow", "fog", "sandstorm", "blizzard", "clear"]:
		w.atmosphere.set_weather(wn, true)
		await wait(8)
	Game.minutes = 1440.0 * 3 + 23 * 60.0
	await wait(30)
	say("night ok, lights: %d street, %d interior" % [w.settlements.street_lights.size(), w.settlements.lights.size()])
	# --- menus
	var m = w.hud.menus
	for f in ["open_pause", "open_inventory", "open_map", "open_settings"]:
		m.call(f)
		await wait(4)
	m.close()
	# --- the pack: icons, dropping a thing into the world and picking it up again
	m.open_inventory()
	await wait(3)
	say("inventory slots: %d, icon: %s" % [m._inv_buttons.size(), m._inv_buttons.values()[0].icon != null if not m._inv_buttons.is_empty() else false])
	m._inv_sel = "apple"
	var apples := int(Game.inventory.get("apple", 0))
	m._inv_drop(false)
	m.close()
	await wait(60)
	var dropped: Node = Game.world_drops[-1].node if not Game.world_drops.is_empty() else null
	say("dropped apple lies at %s (apples %d -> %d)" % [(dropped as Node3D).global_position.snapped(Vector3.ONE * 0.1) if dropped else "-", apples, int(Game.inventory.get("apple", 0))])
	if dropped:
		dropped.interact(pl)
		await wait(2)
	say("picked up again: apples %d, drops %d" % [int(Game.inventory.get("apple", 0)), Game.world_drops.size()])
	# --- the wilds: one of each kind of place, and a signpost
	var kinds := {}
	for site in w.wilds.sites:
		if not kinds.has(site.kind):
			kinds[site.kind] = true
			var node: Node3D = w.wilds._build_site(site)
			say("wild %s '%s' built: %d parts" % [site.kind, site.name, node.get_child_count()])
			node.queue_free()
	say("wild places: %d, signposts: %d" % [w.wilds.sites.size(), w.wilds.signs.size()])
	if not w.wilds.signs.is_empty():
		var sg: Node3D = w.wilds._build_sign(w.wilds.signs[0])
		say("signpost: %s" % w.wilds.signs[0].text)
		sg.queue_free()
	# --- walk through a door and climb the stairs of a two-storey building
	say("player dead before walk test: %s hp %.0f" % [pl.dead, Game.stats.health])
	pl.dead = false
	Game.stats.health = 100.0
	for a in w.wildlife.animals.duplicate():
		w.wildlife.remove_animal(a)
	var info: Dictionary = w.settlements.infos[0]
	for b in info.buildings:
		if b.type == "house" and int(b.floors) == 2 and b.door:
			var xf: Transform3D = b.xform
			var hd := float(b.d) * 0.5
			var hw := float(b.w) * 0.5
			var outside: Vector3 = info.nav_p[b.door_out]
			pl.global_position = outside + Vector3(0, 0.3, 0)
			var to_door: Vector3 = (b.door as Node3D).global_transform * Vector3(0.55, 0, 0) - outside
			pl.set_look(atan2(-to_door.x, -to_door.z), 0.0)
			await wait(5)
			b.door.call("interact", pl)
			await wait(40)
			Input.action_press("move_forward")
			for i in 110:
				await get_tree().physics_frame
			Input.action_release("move_forward")
			for ci in pl.get_slide_collision_count():
				var col := pl.get_slide_collision(ci)
				var obj := col.get_collider() as Node
				say("   blocked by %s (%s) at %s normal %s" % [obj.get_path() if obj else "?", obj.get_class() if obj else "", (xf.affine_inverse() * col.get_position()).snapped(Vector3.ONE * 0.01), (xf.basis.inverse() * col.get_normal()).snapped(Vector3.ONE * 0.01)])
				var shp = obj.shape_owner_get_owner(obj.shape_find_owner(col.get_collider_shape_index())) if obj is CollisionObject3D else null
				if shp:
					say("   shape %s xf %s size %s" % [shp.name, (xf.affine_inverse() * shp.global_transform).origin.snapped(Vector3.ONE * 0.01), shp.shape.get("size")])
			say("   door open=%s drop=%.2f" % [b.door.open, xf.origin.y - WorldData.height_at(info.nav_p[b.door_out].x, info.nav_p[b.door_out].z)])
			var lp := xf.affine_inverse() * pl.global_position
			say("door walk: local %s inside=%s" % [lp.snapped(Vector3.ONE * 0.01), absf(lp.x) < hw and absf(lp.z) < hd])
			# stairs along the right wall, rising toward -z
			pl.global_position = xf * Vector3(hw - 1.0, 0.45, hd - 1.0)
			var fwd: Vector3 = xf.basis * Vector3(0, 0, -1)
			pl.set_look(atan2(-fwd.x, -fwd.z), 0.0)
			await wait(10)
			var y0 := pl.global_position.y
			Input.action_press("move_forward")
			for i in 160:
				await get_tree().physics_frame
			Input.action_release("move_forward")
			say("stairs climb: rose %.2f m (expect ~3)" % (pl.global_position.y - y0))
			break
	# --- castle portcullis with bad reputation
	Game.change_reputation(-80.0, "test")
	await wait(5)
	var closed := 0
	for pc in w.settlements.portcullises:
		if pc.closed:
			closed += 1
	say("portcullises closed with bad rep: %d/%d" % [closed, w.settlements.portcullises.size()])
	Game.reputation = 10.0
	# --- castle population check
	var ranks := {}
	for d in npcs.all:
		if d.info.type == "castle":
			ranks[d.role] = int(ranks.get(d.role, 0)) + 1
	say("castle roles: %s" % str(ranks))
	var knights := {}
	for d in npcs.all:
		if d.role == "knight" and d.traveler.is_empty() and d.info.type in ["village", "town"]:
			knights[d.sname] = int(knights.get(d.sname, 0)) + 1
	say("knights per settlement: %s" % str(knights))
	# --- the law: a stray blow is forgiven, assault brings an arrest (never a lynch mob)
	await _law_test(pl, npcs)
	# --- work: bounties, parcels and errands
	await _quest_test(pl, npcs)
	# --- save & load
	say("save: %s" % Game.save_game())
	w.load_save()
	await wait(10)
	say("loaded; pos %s" % pl.global_position)
	say("SMOKE DONE")
	get_tree().quit()


func _law_test(pl: Player, npcs) -> void:
	var town: Dictionary = WorldData.settlement_by_name("Kingsbridge")
	pl.global_position = Vector3(town.x + 6, WorldData.height_at(town.x + 6, town.z + 6) + 0.5, town.z + 6)
	Game.clear_bounty("Kingsbridge")
	Game.minutes = 1440.0 * 5 + 11 * 60.0
	await wait(60)
	npcs.flush_spawns()
	await wait(5)
	var victim: NPC = null
	for d in npcs.active:
		if d.node and d.alive and d.role in ["villager", "merchant", "farmer", "shopkeeper"] and d.sname == "Kingsbridge":
			victim = d.node
			break
	if victim == null:
		say("law: no civilian found")
		return
	victim.take_damage(1.0, pl)
	say("law: after one stray blow wanted=%s" % Game.is_wanted_in("Kingsbridge"))
	victim.take_damage(1.0, pl)
	await wait(3)
	var crew := _watch_after_player(npcs)
	say("law: after assault wanted=%s pursuers=%d fighting=%d" % [Game.is_wanted_in("Kingsbridge"), crew[0], crew[1]])
	# let the nearest pursuer catch up and confront the player
	var menus = w.hud.menus
	for i in 2400:
		await get_tree().process_frame
		if menus.mode == "dialogue":
			break
	var guard: NPC = menus.npc
	say("law: confronted=%s by %s (%s) options=%s" % [menus.mode == "dialogue", guard.data.name if guard else "-", guard.data.role if guard else "-", str(Dialogue.topics(guard.data).map(func(t): return t[0])) if guard else "-"])
	if guard:
		Game.earn(400)
		menus._choose("fine")
		await wait(10)
		crew = _watch_after_player(npcs)
		say("law: fine paid wanted=%s pursuers=%d fighting=%d" % [Game.is_wanted_in("Kingsbridge"), crew[0], crew[1]])
	# resist, die, and wake up free
	Game.commit_crime("Kingsbridge", 20.0, "test")
	npcs.alert_guards(pl.global_position, "Kingsbridge")
	Game.resisting["Kingsbridge"] = true
	npcs.alert_guards(pl.global_position, "Kingsbridge")
	await wait(5)
	crew = _watch_after_player(npcs)
	say("law: resisting fighting=%d (crew only)" % crew[1])
	pl.take_damage(500.0, null)
	await get_tree().create_timer(5.5).timeout
	await wait(30)
	crew = _watch_after_player(npcs)
	say("law: after death dead=%s wanted=%s fighting=%d pursuers=%d dist_from_centre=%.0f" % [pl.dead, Game.is_wanted_in("Kingsbridge"), crew[1], crew[0], Vector2(pl.global_position.x - town.x, pl.global_position.z - town.z).length()])
	for i in 300:
		await get_tree().process_frame
	say("law: 5 s later still alive=%s hp=%.0f" % [not pl.dead, Game.stats.health])
	# serving time
	Game.commit_crime("Kingsbridge", 20.0, "test")
	var day0 := Game.day()
	await w.serve_jail("Kingsbridge")
	say("law: jail served wanted=%s days passed=%d" % [Game.is_wanted_in("Kingsbridge"), Game.day() - day0])
	# hide in a house: the watch must come in through the door, not through the walls
	var info: Dictionary = w.settlements.infos[0]
	var house: Dictionary = {}
	for b in info.buildings:
		if b.type == "house" and b.door:
			house = b
			break
	var xf: Transform3D = house.xform
	pl.global_position = xf * Vector3(0, 0.4, 0)
	await wait(30)
	Game.commit_crime("Kingsbridge", 20.0, "test")
	npcs.alert_guards(pl.global_position, "Kingsbridge")
	var clipped := 0
	var menus2 = w.hud.menus
	for i in 2400:
		await get_tree().process_frame
		if menus2.mode == "dialogue":
			break
		for d in npcs.active:
			if d.node and (d.node as NPC).pursuing:
				var gp: Vector3 = (d.node as Node3D).global_position
				for o in info.obbs:
					var lp: Vector3 = (o[3] as Transform3D) * gp
					# deep inside a footprint but not at a doorway = walking through a wall
					if absf(lp.x) < float(o[1]) - 1.2 and absf(lp.z) < float(o[2]) - 1.2 and (o[0] as Transform3D).origin.distance_to(xf.origin) > 1.0:
						clipped += 1
	say("law: hiding indoors -> confronted=%s, frames a guard spent inside other buildings=%d" % [menus2.mode == "dialogue", clipped])
	if menus2.mode == "dialogue":
		menus2._choose("jail")
		await get_tree().create_timer(1.2).timeout


func _watch_after_player(npcs) -> Array:
	var pursuing := 0
	var fighting := 0
	for d in npcs.active:
		if d.node and d.role in ["knight", "guard"]:
			if (d.node as NPC).pursuing:
				pursuing += 1
			if (d.node as NPC).target == Game.player_ref:
				fighting += 1
	return [pursuing, fighting]


func _quest_test(pl: Player, npcs) -> void:
	var town: Dictionary = WorldData.settlement_by_name("Kingsbridge")
	pl.global_position = Vector3(town.x + 6, WorldData.height_at(town.x + 6, town.z + 6) + 0.5, town.z + 6)
	Game.clear_bounty("Kingsbridge")
	Game.reputation = 10.0
	await wait(40)
	npcs.flush_spawns()
	await wait(5)
	var by_role := {}
	for d in npcs.active:
		if d.node and d.alive and d.sname == "Kingsbridge" and not by_role.has(d.role):
			by_role[d.role] = d
	# a knight's bounty
	var k = by_role.get("knight")
	if k:
		var r: Dictionary = Dialogue.respond(k.node, "quest_ask")
		say("quest: knight offers -> %s" % String(r.text).left(90))
		Dialogue.respond(k.node, "quest_accept")
		var q: Dictionary = Game.quests[Game.quests.size() - 1]
		say("quest: accepted %s (%s) objective: %s" % [q.title, q.kind, QUESTS.objective(q)])
		if q.kind == "cull":
			for i in int(q.count):
				QUESTS.on_beast_killed(String(q.species))
		else:
			for d in npcs.all:
				if d.hostile and String(d.info.name) == String(q.camp):
					d.alive = false
			QUESTS.on_bandit_killed(String(q.camp), npcs)
		say("quest: after the deed state=%s topics=%s" % [q.state, str(Dialogue.topics(k).map(func(t): return t[0]))])
		var silver0 := Game.silver
		Dialogue.respond(k.node, "quest_turnin")
		say("quest: handed in state=%s paid=%d silver" % [q.state, Game.silver - silver0])
	# a merchant's parcel
	var m = by_role.get("merchant")
	if m:
		Dialogue.respond(m.node, "quest_ask")
		Dialogue.respond(m.node, "quest_accept")
		var q: Dictionary = Game.quests[Game.quests.size() - 1]
		say("quest: parcel for %s in %s, carrying parcel=%s" % [q.to, q.to_town, Game.has_item(QUESTS.PARCEL)])
		var target = null
		for d in npcs.all:
			if d.id == int(q.to_id):
				target = d
		if target:
			if target.node == null:
				npcs._spawn(target)
			var silver0 := Game.silver
			var r: Dictionary = Dialogue.respond(target.node, "quest_deliver")
			say("quest: delivered -> %s | state=%s paid=%d parcel=%s" % [String(r.text).left(60), q.state, Game.silver - silver0, Game.has_item(QUESTS.PARCEL)])
	# an innkeeper's errand
	var t = by_role.get("tavern_owner")
	if t:
		Dialogue.respond(t.node, "quest_ask")
		Dialogue.respond(t.node, "quest_accept")
		var q: Dictionary = Game.quests[Game.quests.size() - 1]
		Game.add_item(String(q.item), int(q.count), false)
		var can := str(Dialogue.topics(t).map(func(x): return x[0]))
		Dialogue.respond(t.node, "quest_turnin")
		say("quest: errand %s, topics with goods=%s, state=%s" % [q.title, can, q.state])
	w.hud.menus.open_journal()
	await wait(3)
	w.hud.menus.open_map()
	await wait(3)
	w.hud.menus.close()
	Dialogue.respond(by_role.get("knight").node, "quest_ask") if by_role.has("knight") else null
	Dialogue.respond(by_role.get("knight").node, "quest_accept") if by_role.has("knight") else null
	say("quest: journal ok, %d tasks recorded, %d active" % [Game.quests.size(), QUESTS.active().size()])
