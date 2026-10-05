class_name Dialogue
## Conversation content: greetings shaped by personality, role, time and the player's
## reputation; rumours about the realm; and role-specific services.

const QUESTS := preload("res://scripts/core/quests.gd")

const GREET := {
	"friendly": ["Well met, traveller!", "Good day to you, friend!", "Ah, a new face! Welcome."],
	"crabby": ["What do you want?", "Make it quick.", "Bah. Another one."],
	"suspicious": ["I've got my eye on you, stranger.", "Who sent you?", "Keep your hands where I can see them."],
	"cautious": ["Er... hello. Keep your distance, if you please.", "Mind yourself. These are uncertain times.", "Who goes there?"],
	"helpful": ["Need directions? Ask away.", "Lost? I know these parts well.", "How can I help you?"],
	"hostile": ["Get lost before I call the knights.", "We don't want your kind here.", "Move along."],
	"cheerful": ["What a fine day it is!", "Hello, hello! Lovely to see you!", "Ha! Good morrow!"],
	"grumpy": ["Hmph.", "My back aches and the ale's gone sour. What is it?", "Not you again... oh, you're new. Still."],
	"shy": ["Oh! I... hello.", "S-sorry, didn't see you there.", "Um. Good day."],
	"boastful": ["You're speaking to the finest in all of Aldmere!", "Heard of me? Of course you have.", "Ha! Come to admire, have you?"],
	"pious": ["May the Light watch over you.", "Blessings upon you, traveller.", "Peace be with you."],
	"greedy": ["Got coin? Then we can talk.", "Everything has a price, friend.", "Looking to spend some silver?"],
	"honourable": ["Well met. I am sworn to keep the peace here.", "Good day, traveller. Walk in honour.", "Hail, stranger. Is all well?"],
	"snobbish": ["Must you stand so close? You smell of the road.", "I have little time for commoners.", "Speak, if you must. Briefly."],
	"stern": ["State your business.", "Keep moving.", "Hmm."],
	"meek": ["Y-yes, my lord?", "Forgive me, I have duties...", "Oh, thank you, kind stranger."],
	"cook": ["Bon Appetite!"],
}
const NIGHT := ["It's late to be wandering about.", "Shouldn't you be abed?", "Dark out. Watch for wolves."]
const LOW_REP := ["I've heard about you. Stay away from me.", "Thief. Murderer. Begone!", "The knights will hear of this if you cause trouble."]
const HIGH_REP := ["You're the one everyone speaks of! An honour.", "Your deeds are known even here, friend.", "The hero of Aldmere, at my door!"]


static func bark(d) -> String:
	if d.role == "cook":
		return "Bon Appetite!"
	if d.role == "prisoner":
		return ["Water... please, a little water.", "I didn't do it! I swear by the Light!", "How long has it been? I can't tell day from night down here.",
			"You there! Put in a word for me with the King!", "Don't trust the jailer. He sells our bread."][randi() % 5]
	if d.role == "jailer":
		return ["Keep away from the bars.", "Visiting? Don't get comfortable.", "They all say they're innocent."][randi() % 3]
	if d.role == "heir":
		return ["Father says I may ride out with the knights next spring!", "Have you seen the falcons? Ours is the fastest in Aldmere.",
			"Mind the dais - only family may sit up there.", "Is it true there are wolves bigger than horses in the north?"][randi() % 4]
	if d.role == "guard":
		return ["Move along.", "Keep your blade sheathed.", "Nothing to see here."][randi() % 3] if randf() < 0.3 else ""
	if d.role == "servant":
		return ""
	if Game.reputation <= -30:
		return LOW_REP[randi() % LOW_REP.size()]
	if Game.reputation >= 45 and randf() < 0.5:
		return HIGH_REP[randi() % HIGH_REP.size()]
	if Game.is_night() and randf() < 0.4:
		return NIGHT[randi() % NIGHT.size()]
	var lines: Array = GREET.get(d.personality, GREET.friendly)
	return lines[randi() % lines.size()]


static func greeting(d) -> String:
	if d.arresting:
		var fine := Items.price_text(fine_amount(d.sname))
		if d.role == "knight":
			return "Hold, in the name of %s! Your crimes here must be answered. Pay %s, or yield and spend a day in the cells." % [d.sname, fine]
		return "Halt! You've broken the law in %s. That's %s, or the cells. Your choice - choose wisely." % [d.sname, fine]
	if d.role == "servant":
		return "Oh! A gold coin... for me, my lord? You are too kind."
	if Game.is_wanted_in(d.sname) and d.role in ["knight", "official"]:
		return "You stand accused of crimes in %s. Pay your fine, or answer to the sword." % d.sname
	if Game.reputation <= -40 and d.personality not in ["greedy", "hostile"]:
		return LOW_REP[randi() % LOW_REP.size()]
	var g := bark(d)
	if d.met and randf() < 0.5:
		g = ["Back again?", "Ah, it's you.", "Hello again."][randi() % 3] + " " + g
	if d.role == "duke":
		if d.sname == NPCManager.ROYAL_SEAT:
			return "You stand before %s, King of Aldmere. %s" % [d.name, "Kneel, and speak your business." if d.personality == "stern" else "Rise, traveller - my hall is open to all who keep the peace."]
		return "You stand before %s. %s" % [d.name, "Speak, and be swift." if d.personality == "stern" else "Welcome to my hall, traveller."]
	if d.role == "consort":
		var lord := "the King" if d.sname == NPCManager.ROYAL_SEAT else "the Duke"
		return "%s inclines her head. %s" % [d.name, "\"Mind your manners at court.\"" if d.personality == "stern" else "\"Be welcome here. %s is generous to those who serve the realm.\"" % lord.capitalize()]
	if d.role in ["prisoner", "jailer", "heir"]:
		return bark(d)
	return g


static func topics(d) -> Array:
	var t := []
	if d.arresting:
		return [["fine", "Pay the fine (%s)" % Items.price_text(fine_amount(d.sname))],
			["jail", "I'll come quietly. (Serve %s in the cells)" % ("a day" if jail_days(d.sname) == 1 else "%d days" % jail_days(d.sname))],
			["resist", "You'll have to take me by force!"]]
	if d.role == "servant":
		return [["gift", "Give a gold coin"], ["bye", "Farewell"]]
	t.append(["who", "Who are you?"])
	t.append(["news", "What news?"])
	t.append(["directions", "Where can I find..."])
	# work: hand over a parcel, hand in a finished job, or ask for one
	var dq: Dictionary = QUESTS.delivery_for(d)
	if not dq.is_empty():
		t.append(["quest_deliver", "I have a parcel for you, from %s of %s." % [dq.giver, dq.town]])
	var rq: Dictionary = QUESTS.ready_for(d)
	if not rq.is_empty():
		t.append(["quest_turnin", "I've brought the %s you wanted." % Items.display_name(String(rq.item)).to_lower() if rq.kind == "fetch" else "It's done: %s." % rq.title])
	if not d.offer.is_empty():
		t.append(["quest_accept", "I'll do it."])
		t.append(["quest_decline", "Not now."])
	elif QUESTS.can_offer(d):
		t.append(["quest_ask", {"knight": "Is there work for a sword?", "merchant": "Need anything carried?"}.get(d.role, "Is there anything you need?")])
	if not d.stock.is_empty() and not (Game.reputation <= -40 and d.personality != "greedy"):
		t.append(["trade", "Let's trade"])
	match d.role:
		"tavern_owner":
			t.append(["room", "I'd like a room for the night (8 silver)"])
		"stablemaster":
			t.append(["horse", "I want to buy a horse"])
		"explorer":
			t.append(["guide", "Can you guide me somewhere? (6 silver)"])
			t.append(["treasure", "Know of any treasure? (15 silver)"])
		"knight":
			if not d.trained:
				t.append(["train", "Will you train me in swordplay? (2 gold)"])
		"duke":
			t.append(["audience", "I seek an audience, my lord."])
		"priest":
			t.append(["bless", "Bless me, Father. (5 silver - restores health)"])
	if Game.is_wanted_in(d.sname) and d.role in ["knight", "official", "duke"]:
		var fine := fine_amount(d.sname)
		t.insert(0, ["fine", "Pay my fine (%s)" % Items.price_text(fine)])
	t.append(["bye", "Farewell"])
	return t


static func fine_amount(sname: String) -> int:
	return int(float(Game.settlement_standing.get(sname, 10.0)) * 4.0) + 20


static func jail_days(sname: String) -> int:
	return 1 + int(float(Game.settlement_standing.get(sname, 0.0)) / 60.0)


static func intro(d) -> String:
	var title := NPCManager.role_title(d).to_lower()
	match d.role:
		"duke":
			if d.sname == NPCManager.ROYAL_SEAT:
				return "I am %s, King of Aldmere. Every duke on this island holds his castle of my crown, and every road is under my peace." % d.name
			return "I am %s, lord of these lands and all who dwell within its walls." % d.name
		"consort":
			if d.sname == NPCManager.ROYAL_SEAT:
				return "I am %s, Queen of Aldmere. I see to the court and the realm's charity - and I hear more than the King's ministers think." % d.name
			return "I am %s. My lord husband rules this castle; I rule everything he forgets." % d.name
		"heir":
			if d.sname == NPCManager.ROYAL_SEAT:
				return "I am %s of Aldmere. One day I'll %s - but for now my tutors won't let me out of their sight." % [d.name, "wear the crown" if d.gender == "m" else "sit on the council"]
			return "I'm %s. Father wants me at my lessons; I'd rather be in the training yard." % d.name
		"jailer": return "%s, keeper of the cells. Thieves, poachers, one fellow who insulted the King's horse. They stay till the King says otherwise." % d.name
		"prisoner": return "%s. They say I stole from the King's stores. I took bread for my children - is that a crime?" % d.name
		"official": return "%s, steward to the %s. I keep the ledgers and, unlike some, my boots clean." % [d.name, "king" if d.sname == NPCManager.ROYAL_SEAT else "duke"]
		"knight": return "%s, knight of %s. My oath is to protect these people - and I keep it." % [d.name, d.sname]
		"falconer": return "I'm %s, the castle falconer. This beauty is Swift - the finest hunter in Aldmere." % d.name
		"cook": return "Bon Appetite!"
		"explorer": return "%s. I've walked every road on this island and a few that aren't on any map." % d.name
		"bandit": return "None of your business."
	var p := {"friendly": "Pleased to meet you!", "crabby": "Not that it's any business of yours.", "boastful": "The best %s you'll find anywhere, mind." % title,
		"shy": "...That's all, really.", "pious": "I give thanks every day for this life.", "greedy": "And I'm always open for business."}.get(d.personality, "")
	return "I'm %s, the %s here in %s. %s" % [d.name, title, d.sname, p]


static func rumor(d) -> String:
	var opts := []
	var c: Vector3 = d.info.center
	# market days
	for town in Game.MARKET_DAYS:
		var days := []
		for i in Game.MARKET_DAYS[town]:
			days.append(Game.WEEKDAYS[i])
		opts.append("Market day in %s falls on %s. Traders bring rare wares from across the sea." % [town, " and ".join(days)])
	# nearby places
	var near := []
	for s in WorldData.settlements:
		var dist := Vector2(s.x - c.x, s.z - c.z).length()
		if dist > 100.0 and dist < 1800.0:
			near.append([dist, s])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for e in near.slice(0, 4):
		var s: Dictionary = e[1]
		var dir := compass(Vector3(s.x, 0, s.z) - c)
		match String(s.type):
			"ruin", "ruin_keep": opts.append("The ruins of %s lie %s of here. Nobody goes there anymore... they say there's still gold inside." % [s.name, dir])
			"castle": opts.append("%s stands %s of here. The duke's knights ride the roads from there." % [s.name, dir])
			"town": opts.append("%s is %s - a proper town, with a market and seven knights to keep the peace." % [s.name, dir])
			_: opts.append("The village of %s is %s, about %d paces away." % [s.name, dir, int(e[0])])
	for q in WorldData.pois:
		if q.type == "bandit_camp" and Vector2(q.x - c.x, q.z - c.z).length() < 2200.0:
			opts.append("Bandits have made camp at %s, %s of here. Travel in company." % [q.name, compass(Vector3(q.x, 0, q.z) - c)])
	match d.climate:
		"cold": opts.append("Winter never quite leaves the Frostlands. Wear furs, or the cold will have you by morning.")
		"desert": opts.append("The Qadir sands drink a man dry by noon. Carry water, and wear loose robes.")
		_: opts.append("Wolves have been bold of late. They hunt in packs after dark.")
	opts.append("They say a bear the size of a cart roams the Thornwood. I'd not go alone.")
	opts.append("Geese are flying south early this year. A hard season coming, mark my words.")
	opts.append("The island's old name was Aldmere - before the kings, before the castles.")
	return opts[randi() % opts.size()]


static func compass(v: Vector3) -> String:
	var a := atan2(v.x, -v.z)
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(round(a / (PI / 4.0))) % 8 if a >= 0 else (int(round(a / (PI / 4.0))) + 8) % 8]


static func directions(d) -> String:
	var c: Vector3 = d.info.center
	var lines := []
	for b in d.info.buildings:
		var label: String = {"tavern": "The tavern", "blacksmith": "The smithy", "stable": "The stables", "chapel": "The chapel", "shop": "A shop", "townhall": "The town hall", "keep": "The keep"}.get(b.type, "")
		if label != "" and lines.size() < 4:
			lines.append("%s is %s of the square." % [label, compass((b.center as Vector3) - c)])
	if lines.is_empty():
		return "Follow the road and you'll find what you need."
	return " ".join(lines)


## Returns {text, close, open}. Applies side effects.
static func respond(npc, topic: String) -> Dictionary:
	var d = npc.data
	match topic:
		"who": return {"text": intro(d)}
		"news": return {"text": rumor(d)}
		"directions": return {"text": directions(d)}
		"trade": return {"text": "Have a look.", "open": "trade"}
		"horse": return {"text": "Fine animals, every one. The faster they run, the more they cost.", "open": "horses"}
		"bye": return {"text": ["Safe travels.", "Farewell.", "Go well.", "Hmph. Bye."][randi() % 4], "close": true}
		"room":
			if Game.has_meta("rented_" + d.sname):
				return {"text": "Your room's already paid for. Upstairs."}
			if not Game.pay(8):
				return {"text": "Eight silver, friend. Come back when you have it."}
			Game.set_meta("rented_" + d.sname, true)
			return {"text": "Room's upstairs. Clean sheets, mostly. Sleep well!"}
		"gift":
			if Game.gold() < 1:
				return {"text": "...", "close": true}
			Game.pay(Items.SILVER_PER_GOLD)
			d.gift_count += 1
			Game.change_reputation(2.0, "Generosity to a servant")
			var secrets := []
			for s in WorldData.settlements:
				if s.type in ["ruin", "ruin_keep"] and not Game.discovered.has(s.name):
					secrets.append(s)
			if not secrets.is_empty():
				var s: Dictionary = secrets[randi() % secrets.size()]
				Game.discover(s.name)
				return {"text": "Bless you! I'll tell you a secret: the old lord hid his gold at %s. I've marked it in your mind's map, so to speak." % s.name}
			return {"text": "Thank you, my lord! The duke's cellar key hangs by the kitchen hearth... but you didn't hear that from me."}
		"guide":
			if not Game.pay(6):
				return {"text": "Six silver. I don't work for free."}
			var cand := []
			for s in WorldData.settlements + WorldData.pois:
				if not Game.discovered.has(s.name):
					cand.append(s)
			if cand.is_empty():
				return {"text": "You've seen more of Aldmere than I have! Keep your coin.", "refund": 6}
			cand.sort_custom(func(a, b): return Vector2(a.x - d.info.center.x, a.z - d.info.center.z).length() < Vector2(b.x - d.info.center.x, b.z - d.info.center.z).length())
			var s: Dictionary = cand[0]
			Game.discover(s.name)
			Game.waypoint = Vector2(float(s.x), float(s.z))
			return {"text": "%s lies %s of here. I've marked it on your map - follow your compass." % [s.name, compass(Vector3(s.x, 0, s.z) - d.info.center)]}
		"treasure":
			if not Game.pay(15):
				return {"text": "Fifteen silver for that kind of knowledge."}
			var ruins := []
			for s in WorldData.settlements + WorldData.pois:
				if s.type in ["ruin", "ruin_keep", "tower_ruin", "stone_circle", "mine"]:
					ruins.append(s)
			var s: Dictionary = ruins[randi() % ruins.size()]
			Game.discover(s.name)
			return {"text": "Search %s. There's a chest there that nobody's opened in a hundred years. It's on your map now." % s.name}
		"trouble":
			for q in WorldData.pois:
				if q.type == "bandit_camp" and not Game.discovered.has(q.name):
					Game.discover(q.name)
					return {"text": "Bandits at %s have been robbing merchants. Clear them out and the realm will remember it. I've marked the place on your map." % q.name}
			return {"text": "Wolves near the roads at night, and a bear or two in the deep woods. Otherwise, quiet. Keep it that way."}
		"train":
			if not Game.pay(2 * Items.SILVER_PER_GOLD):
				return {"text": "Two gold for a lesson. Steel isn't cheap, and neither am I."}
			d.trained = true
			Game.max_health += 10.0
			Game.change_stat("health", 10.0)
			return {"text": "Feet apart. Shield high. Strike from the hip... Good! You've the makings of a warrior. (+10 maximum health)"}
		"bless":
			if not Game.pay(5):
				return {"text": "The chapel asks five silver for the candles."}
			Game.change_stat("health", 100.0)
			return {"text": "May the Light mend your wounds and guide your steps."}
		"fine":
			var fine := fine_amount(d.sname)
			if not Game.pay(fine):
				if d.arresting:
					return {"text": "You haven't the coin. The cells, then - or the hard way."}
				return {"text": "You haven't the coin. Come back when you do, and keep your head down until then.", "close": true}
			Game.clear_bounty(d.sname)
			npc.manager.stand_down(d.sname)
			Game.change_reputation(3.0, "Fine paid")
			return {"text": "Your debt to %s is paid. Keep the peace, and we'll have no more trouble." % d.sname, "close": d.arresting}
		"jail":
			var sname: String = d.sname
			npc.manager.stand_down(sname)
			Game.world_ref.call("serve_jail", sname)
			return {"text": "Sensible. Come along, then.", "close": true}
		"quest_ask":
			var q: Dictionary = QUESTS.make_offer(d, npc.manager)
			if q.is_empty():
				return {"text": "Nothing just now. Ask me again another day."}
			d.offer = q
			return {"text": String(q.pitch)}
		"quest_accept":
			if d.offer.is_empty():
				return {"text": "..."}
			QUESTS.accept(d.offer, npc.manager)
			d.offer = {}
			return {"text": ["Good. Don't keep me waiting.", "Thank you - I knew I could count on you.", "Then go, and good fortune go with you."][randi() % 3]}
		"quest_decline":
			d.offer = {}
			return {"text": ["Suit yourself.", "Another time, then.", "Hmph. As you like."][randi() % 3]}
		"quest_turnin":
			var q: Dictionary = QUESTS.ready_for(d)
			if q.is_empty():
				return {"text": "..."}
			QUESTS.turn_in(q)
			match String(q.kind):
				"cull": return {"text": "The farms will sleep easier tonight. Here - %s, as promised." % Items.price_text(int(q.silver))}
				"clear": return {"text": "The roads are safe again because of you. %s - and the thanks of %s." % [Items.price_text(int(q.silver)), q.town]}
			return {"text": "Just what I needed! Here's %s for your trouble." % Items.price_text(int(q.silver))}
		"quest_deliver":
			var q: Dictionary = QUESTS.delivery_for(d)
			if q.is_empty():
				return {"text": "..."}
			QUESTS.turn_in(q)
			return {"text": "From %s? At last! Here - %s, as agreed." % [q.giver, Items.price_text(int(q.silver))]}
		"resist":
			Game.resisting[d.sname] = true
			d.arresting = false
			npc.manager.alert_guards(npc.global_position, d.sname)
			return {"text": "So be it - to arms!", "close": true, "hostile": true}
		"audience":
			if Game.reputation >= 50.0 and not Game.has_meta("knighted"):
				Game.set_meta("knighted", true)
				Game.earn(100 * Items.SILVER_PER_GOLD)
				Game.change_reputation(10.0, "Honoured by the king" if d.sname == NPCManager.ROYAL_SEAT else "Honoured by the duke")
				return {"text": "Your deeds have reached my ears. Kneel... Rise, Knight of Aldmere. Take this purse of a hundred gold, with my thanks."}
			if Game.reputation < 0.0:
				return {"text": "You dare seek audience with that reputation? Guards, watch this one."}
			return {"text": "Serve the realm well - rid our roads of bandits and beasts - and you will find me generous. (Earn reputation 50 to be honoured.)"}
	return {"text": "..."}


## Buy / sell price multipliers by personality & reputation.
static func price_mult(d, buying: bool) -> float:
	var m := 1.3 if buying else 0.45
	match d.personality:
		"greedy": m *= 1.18 if buying else 0.85
		"friendly", "helpful", "cheerful": m *= 0.94 if buying else 1.06
		"crabby", "grumpy", "suspicious": m *= 1.07 if buying else 0.94
	if Game.reputation >= 30.0:
		m *= 0.9 if buying else 1.1
	if Game.equipped.cloak == "silk_cloak":
		m *= 0.95 if buying else 1.05
	return m
