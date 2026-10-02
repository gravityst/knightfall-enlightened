extends RefCounted
## Work offered by the people of Aldmere, tracked in Game.quests (saved with the game):
##   cull    - knights: thin out the wolves or a bear troubling the countryside
##   clear   - knights: wipe out a bandit camp
##   deliver - merchants: carry a sealed parcel to a trader in another settlement
##   fetch   - innkeepers, cooks, shopkeepers: bring back meat, hides or pelts
## A quest is "active" until its goal is met, then "ready" to hand in to whoever gave it.

const PARCEL := "sealed_parcel"
const MAX_ACTIVE := 5
const FETCH := {
	"tavern_owner": [["raw_meat", 3, "venison for the stewpot"], ["raw_fish", 3, "fresh fish for supper"]],
	"cook": [["raw_meat", 4, "venison for the kitchens"], ["raw_fish", 3, "fish for the table"]],
	"shopkeeper": [["deer_hide", 2, "deer hides to sell on"], ["wolf_pelt", 2, "wolf pelts - furriers pay well"]],
	"blacksmith": [["wolf_pelt", 2, "pelts to line gauntlets"], ["deer_hide", 3, "hides for bellows and grips"]],
}


static func active() -> Array:
	return Game.quests.filter(func(q): return q.state != "done")


static func can_offer(d) -> bool:
	if d.hostile or not (d.role in ["knight", "merchant", "tavern_owner", "cook", "shopkeeper", "blacksmith"]):
		return false
	if active().size() >= MAX_ACTIVE:
		return false
	for q in active():
		if int(q.giver_id) == d.id:
			return false
	return true


## Builds (but does not yet accept) a job suited to this person.
static func make_offer(d, npcs) -> Dictionary:
	var q := {"id": Game.quest_seq + 1, "giver_id": d.id, "giver": d.name, "town": d.sname, "role": d.role, "state": "active", "done": 0, "count": 1}
	match d.role:
		"knight":
			var camp := _open_camp(d, npcs)
			if not camp.is_empty() and randf() < 0.6:
				q.merge({"kind": "clear", "camp": camp.name, "at": [camp.x, camp.z], "silver": 120, "rep": 8.0,
					"title": "Clear %s" % camp.name,
					"pitch": "Bandits hold %s, %s of here. They rob the roads and laugh at the law. Put an end to them and %s will pay you ten gold." % [camp.name, Dialogue.compass(Vector3(camp.x, 0, camp.z) - d.info.center), d.sname]}, true)
			else:
				var bear := randf() < 0.3
				q.merge({"kind": "cull", "species": "bear" if bear else "wolf", "count": 1 if bear else 3, "silver": 60 if bear else 36, "rep": 5.0 if bear else 4.0,
					"title": "Slay a bear" if bear else "Cull the wolves", "at": [d.info.center.x, d.info.center.z],
					"pitch": ("A great bear has been raiding the farms around %s. Bring it down and five gold is yours." if bear else "Wolves have been taking sheep around %s - and they grow bold. Kill three and I'll pay you three gold.") % d.sname}, true)
		"merchant":
			var to = _recipient(d, npcs)
			if to == null:
				return {}
			var dist := Vector2(to.info.center.x - d.info.center.x, to.info.center.z - d.info.center.z).length()
			var pay := 18 + int(dist / 100.0) * 2
			q.merge({"kind": "deliver", "to_id": to.id, "to": to.name, "to_town": to.sname, "silver": pay, "rep": 2.0, "at": [to.info.center.x, to.info.center.z],
				"title": "A parcel for %s" % to.sname,
				"pitch": "This must reach %s, the %s in %s - sealed, mind, no peeking. They'll pay you %s when it's in their hands." % [to.name, NPCManager.role_title(to).to_lower(), to.sname, Items.price_text(pay)]}, true)
		_:
			var opts: Array = FETCH.get(d.role, [])
			if opts.is_empty():
				return {}
			var o: Array = opts[randi() % opts.size()]
			var pay := int(Items.get_item(o[0]).get("value", 3)) * int(o[1]) * 2 + 12
			q.merge({"kind": "fetch", "item": o[0], "count": int(o[1]), "silver": pay, "rep": 2.0, "at": [d.info.center.x, d.info.center.z],
				"title": "%d %s for %s" % [int(o[1]), Items.display_name(o[0]).to_lower(), d.name],
				"pitch": "I need %s: %d %s. Bring them and I'll pay %s." % [o[2], int(o[1]), Items.display_name(o[0]).to_lower(), Items.price_text(pay)]}, true)
	return q


static func accept(q: Dictionary, npcs) -> void:
	Game.quest_seq = int(q.id)
	Game.quests.append(q)
	if q.kind == "deliver":
		Game.add_item(PARCEL, 1, false)
	elif q.kind == "clear" and _camp_cleared(String(q.camp), npcs):
		q.state = "ready"
	Game.notify.emit("New task: %s" % q.title, "info")
	Audio.ui("open")


## Something the player can hand in to this person right now (a finished job, or the goods).
static func ready_for(d) -> Dictionary:
	for q in active():
		if String(q.town) != d.sname:
			continue
		var giver_ok: bool = int(q.giver_id) == d.id or (String(q.role) == d.role and not _giver_alive(q))
		if not giver_ok:
			continue
		if q.state == "ready" or (q.kind == "fetch" and Game.has_item(String(q.item), int(q.count))):
			return q
	return {}


static func delivery_for(d) -> Dictionary:
	for q in active():
		if q.kind == "deliver" and int(q.to_id) == d.id and Game.has_item(PARCEL):
			return q
	return {}


static func turn_in(q: Dictionary) -> void:
	if q.kind == "fetch":
		Game.remove_item(String(q.item), int(q.count))
	elif q.kind == "deliver":
		Game.remove_item(PARCEL)
	_reward(q)


static func on_beast_killed(species: String) -> void:
	for q in active():
		if q.kind == "cull" and q.state == "active" and String(q.species) == species:
			q.done = int(q.done) + 1
			if int(q.done) >= int(q.count):
				q.state = "ready"
				Game.notify.emit("%s: done - return to %s in %s." % [q.title, q.giver, q.town], "info")
			else:
				Game.notify.emit("%s: %d / %d" % [q.title, int(q.done), int(q.count)], "info")


static func on_bandit_killed(camp: String, npcs) -> void:
	if not _camp_cleared(camp, npcs):
		return
	for q in active():
		if q.kind == "clear" and String(q.camp) == camp and q.state == "active":
			q.state = "ready"
			Game.notify.emit("%s is clear - return to %s in %s." % [camp, q.giver, q.town], "info")


## The short objective line shown on the HUD and in the journal.
static func objective(q: Dictionary) -> String:
	if q.state == "ready":
		return "Return to %s in %s" % [q.giver, q.town] if q.kind != "deliver" else "Give the parcel to %s in %s" % [q.to, q.to_town]
	match String(q.kind):
		"cull": return "%s (%d / %d)" % ["Slay a bear" if q.species == "bear" else "Kill wolves", int(q.done), int(q.count)]
		"clear": return "Kill the bandits at %s" % q.camp
		"deliver": return "Give the parcel to %s in %s" % [q.to, q.to_town]
		"fetch": return "Bring %d %s to %s (%d carried)" % [int(q.count), Items.display_name(String(q.item)).to_lower(), q.giver, int(Game.inventory.get(String(q.item), 0))]
	return ""


## World position for the map marker: where the work is, or where to hand it in.
static func marker(q: Dictionary) -> Vector2:
	if q.state == "ready" and q.kind != "deliver":
		var s := WorldData.settlement_by_name(String(q.town))
		if not s.is_empty():
			return Vector2(float(s.x), float(s.z))
	return Vector2(float(q.at[0]), float(q.at[1]))


# ------------------------------------------------------------------ helpers
static func _reward(q: Dictionary) -> void:
	q.state = "done"
	Game.earn(int(q.silver))
	Game.change_reputation(float(q.rep), "Task done: %s" % q.title)
	Game.notify.emit("Reward: %s" % Items.price_text(int(q.silver)), "rep")
	Audio.ui("coin")


static func _giver_alive(q: Dictionary) -> bool:
	return not Game.dead_npcs.has(str(int(q.giver_id)))


static func _camp_cleared(camp: String, npcs) -> bool:
	for d in npcs.all:
		if d.hostile and d.alive and String(d.info.name) == camp:
			return false
	return true


static func _open_camp(d, npcs) -> Dictionary:
	var best := {}
	var bd := INF
	for p in WorldData.pois:
		if p.type != "bandit_camp" or _camp_cleared(String(p.name), npcs):
			continue
		var taken := false
		for q in active():
			if q.kind == "clear" and String(q.camp) == String(p.name):
				taken = true
		if taken:
			continue
		var dd := Vector2(float(p.x) - d.info.center.x, float(p.z) - d.info.center.z).length()
		if dd < bd:
			bd = dd
			best = p
	return best


static func _recipient(d, npcs):
	var cands := []
	for o in npcs.all:
		if o.alive and o.sname != d.sname and o.role in ["merchant", "shopkeeper", "tavern_owner"] and not o.market_only and o.traveler.is_empty() \
				and String(o.info.type) in ["town", "village"]:
			var dist := Vector2(o.info.center.x - d.info.center.x, o.info.center.z - d.info.center.z).length()
			if dist > 400.0 and dist < 2600.0:
				cands.append(o)
	return cands[randi() % cands.size()] if not cands.is_empty() else null
