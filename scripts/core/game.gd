extends Node
## Global game state: calendar & time of day, the player's survival stats, purse,
## inventory and reputation, settings, and save / load.

signal notify(text: String, kind: String)
signal hour_passed(hour: int)
signal day_passed(day: int)
signal stats_changed
signal inventory_changed
signal reputation_changed(value: float)
signal settings_changed

const SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"
const WEEKDAYS := ["Moonday", "Tyrsday", "Wodensday", "Thorsday", "Freyday", "Saturnsday", "Sunday"]
const MARKET_DAYS := {"Kingsbridge": [2, 5], "Frosthold": [1, 4], "Sandmere": [3, 6]}

# ---------------------------------------------------------------- time
var minutes := 8.0 * 60.0          # minutes since the start of day 0
var paused_time := false
var _last_hour := 8
var _last_day := 0

# ---------------------------------------------------------------- player
var stats := {"health": 100.0, "stamina": 100.0, "hunger": 85.0, "thirst": 85.0, "warmth": 70.0}
var max_health := 100.0
var silver := 25 * Items.SILVER_PER_GOLD + 8   # 25 gold, 8 silver
var inventory := {"bread": 2, "apple": 3, "waterskin": 1, "torch": 2, "campfire_kit": 1, "bandage": 2, "rusty_sword": 1, "wooden_shield": 1, "wool_cloak": 1}
var waterskin_charges := 5
var equipped := {"weapon": "rusty_sword", "shield": "wooden_shield", "cloak": "wool_cloak", "armor": ""}
var reputation := 10.0
var settlement_standing := {}       # settlement name -> bounty (crime weight; fades every day)
var resisting := {}                 # settlement name -> true while the player fights its watch
var quests: Array = []
var world_drops: Array = []
var waypoint := Vector2.INF       # set on the map (click) or by a guide; shown on the compass
## Performance overlay (page?perf, or --perf-overlay): heavy jobs leave a mark on the frame they
## run in, so a hitch can be traced to what caused it. ?tour (--tour) walks a set route.
var perf_overlay := false
var tour := false
var frame_marks: PackedStringArray = []
var _query := ""      # items lying in the world: {id, count, x, y, z, node}              # see scripts/core/quests.gd
var quest_seq := 0
const WANTED_AT := 15.0
var discovered := {}                # location name -> true
var looted := {}                    # container id -> true
var dead_npcs := {}                 # npc id -> true
var owned_horses: Array = []        # [{id, speed, color, x, z}]
var kills := {}
var player_ref: Node3D
var world_ref: Node3D
var in_menu := false
var holding_coin := false
var loading_save: Dictionary = {}

# ---------------------------------------------------------------- settings
var settings := {
	"preset": "high", "render_scale": 1.0, "fsr": true, "fullscreen": false, "vsync": true, "max_fps": 0,
	"shadows": 2, "sdfgi": false, "ssr": true, "ssao": true, "ssil": false, "volumetric_fog": true, "glow": true,
	"view_distance": 1.0, "grass_density": 1.0, "fov": 75.0, "mouse_sensitivity": 0.0022, "invert_y": false,
	"day_length_min": 40.0, "master_volume": 0.85, "music_volume": 0.55, "sfx_volume": 0.9, "show_fps": false, "head_bob": true, "ui_scale": 1.0,
}
const PRESETS := {
	"low": {"shadows": 0, "sdfgi": false, "ssr": false, "ssao": false, "ssil": false, "volumetric_fog": false, "glow": true, "view_distance": 0.6, "grass_density": 0.35, "render_scale": 0.75},
	"medium": {"shadows": 1, "sdfgi": false, "ssr": false, "ssao": true, "ssil": false, "volumetric_fog": true, "glow": true, "view_distance": 0.8, "grass_density": 0.65, "render_scale": 0.85},
	"high": {"shadows": 2, "sdfgi": false, "ssr": true, "ssao": true, "ssil": false, "volumetric_fog": true, "glow": true, "view_distance": 1.0, "grass_density": 1.0, "render_scale": 1.0},
	"ultra": {"shadows": 3, "sdfgi": true, "ssr": true, "ssao": true, "ssil": true, "volumetric_fog": true, "glow": true, "view_distance": 1.3, "grass_density": 1.3, "render_scale": 1.0},
	"cinematic": {"shadows": 3, "sdfgi": true, "ssr": true, "ssao": true, "ssil": true, "volumetric_fog": true, "glow": true, "view_distance": 1.6, "grass_density": 1.6, "render_scale": 1.5},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var q := str(JavaScriptBridge.eval("location.search")) if OS.has_feature("web") else ""
	_query = q
	perf_overlay = q.contains("perf") or "--perf-overlay" in OS.get_cmdline_user_args()
	tour = q.contains("tour") or "--tour" in OS.get_cmdline_user_args()
	_register_inputs()
	load_settings()


func _process(delta: float) -> void:
	if paused_time or get_tree().paused or in_menu:
		return
	advance_minutes(delta * minutes_per_second())


func minutes_per_second() -> float:
	return 1440.0 / (float(settings.day_length_min) * 60.0)


func advance_minutes(m: float) -> void:
	minutes += m
	var h := hour()
	if h != _last_hour:
		_last_hour = h
		hour_passed.emit(h)
	var d := day()
	if d != _last_day:
		_last_day = d
		_decay_bounties()
		day_passed.emit(d)


func day() -> int:
	return int(minutes / 1440.0)


func time_of_day() -> float:   # 0..24
	return fmod(minutes, 1440.0) / 60.0


func hour() -> int:
	return int(time_of_day())


func weekday() -> int:
	return day() % 7


func weekday_name() -> String:
	return WEEKDAYS[weekday()]


func clock_text() -> String:
	var t := time_of_day()
	return "%02d:%02d" % [int(t), int(fmod(t * 60.0, 60.0))]


func is_night() -> bool:
	var t := time_of_day()
	return t < 5.5 or t > 20.5


func is_market_day(town: String) -> bool:
	return MARKET_DAYS.has(town) and weekday() in MARKET_DAYS[town]


# ---------------------------------------------------------------- purse & inventory
func gold() -> int:
	return silver / Items.SILVER_PER_GOLD


func purse_text() -> String:
	return "%d gold  %d silver" % [gold(), silver % Items.SILVER_PER_GOLD]


func can_afford(cost_silver: int) -> bool:
	return silver >= cost_silver


func pay(cost_silver: int) -> bool:
	if silver < cost_silver:
		return false
	silver -= cost_silver
	inventory_changed.emit()
	return true


func earn(amount_silver: int) -> void:
	silver += amount_silver
	inventory_changed.emit()


func add_item(id: String, count := 1, announce := true) -> void:
	inventory[id] = int(inventory.get(id, 0)) + count
	if announce:
		notify.emit("+%d %s" % [count, Items.display_name(id)], "item")
	inventory_changed.emit()


func remove_item(id: String, count := 1) -> bool:
	var have := int(inventory.get(id, 0))
	if have < count:
		return false
	if have == count:
		inventory.erase(id)
		for slot in equipped:
			if equipped[slot] == id:
				equipped[slot] = ""
	else:
		inventory[id] = have - count
	inventory_changed.emit()
	return true


func has_item(id: String, count := 1) -> bool:
	return int(inventory.get(id, 0)) >= count


func equip(id: String) -> void:
	var it := Items.get_item(id)
	var slot := String(it.type)
	if slot in ["weapon", "shield", "cloak", "armor"]:
		equipped[slot] = "" if equipped[slot] == id else id
		inventory_changed.emit()
		stats_changed.emit()


func use_item(id: String) -> String:
	var it := Items.get_item(id)
	match String(it.type):
		"food", "drink":
			if id == "waterskin":
				if waterskin_charges <= 0:
					return "Your waterskin is empty. Refill it at fresh water."
				waterskin_charges -= 1
				change_stat("thirst", float(it.thirst))
				if player_ref:
					Audio.play_at("drink", player_ref.global_position, -2.0)
				return "You drink from the waterskin (%d sips left)." % waterskin_charges
			if it.has("cookable") and not _near_fire():
				return "%s should be cooked over a fire first." % it.name
			remove_item(id)
			for k in ["hunger", "thirst", "health", "stamina", "warmth"]:
				if it.has(k):
					change_stat(k, float(it[k]))
			if player_ref:
				Audio.play_at("drink" if String(it.type) == "drink" else ("item_pick" if it.has("health") else "eat"), player_ref.global_position, -2.0)
			return "You consume the %s." % String(it.name).to_lower()
		"weapon", "shield", "cloak", "armor":
			equip(id)
			return ("Equipped " if equipped.values().has(id) else "Unequipped ") + String(it.name)
		"tool":
			if id == "campfire_kit" and player_ref:
				remove_item(id)
				player_ref.call("place_campfire")
				return "You build a crackling campfire."
			if id == "bedroll" and player_ref:
				return player_ref.call("sleep_outdoors")
			if id == "torch":
				if player_ref:
					player_ref.call("toggle_torch")
				return ""
	return "You can't use that."


func cook_all() -> int:
	var n := 0
	for id in inventory.keys():
		var it := Items.get_item(id)
		if it.has("cookable"):
			var c := int(inventory[id])
			inventory.erase(id)
			add_item(it.cookable, c, false)
			n += c
	if n > 0:
		inventory_changed.emit()
	return n


func _near_fire() -> bool:
	return player_ref != null and bool(player_ref.call("is_near_fire"))


func insulation() -> float:
	var c := String(equipped.cloak)
	return float(Items.get_item(c).get("insulation", 0)) if c != "" else 0.0


func armor_value() -> float:
	var a := String(equipped.armor)
	return float(Items.get_item(a).get("armor", 0.0)) if a != "" else 0.0


func weapon_damage() -> float:
	var w := String(equipped.weapon)
	return float(Items.get_item(w).get("damage", 6)) if w != "" else 6.0


func shield_block() -> float:
	var s := String(equipped.shield)
	return float(Items.get_item(s).get("block", 0.0)) if s != "" else 0.0


# ---------------------------------------------------------------- stats & reputation
func change_stat(k: String, amount: float) -> void:
	var mx := max_health if k == "health" else 100.0
	stats[k] = clampf(float(stats[k]) + amount, 0.0, mx)
	stats_changed.emit()


func change_reputation(amount: float, reason := "") -> void:
	var before := reputation
	reputation = clampf(reputation + amount, -100.0, 100.0)
	if reason != "" and absf(amount) >= 1.0:
		notify.emit("%s  (reputation %s%d)" % [reason, "+" if amount > 0 else "", int(round(amount))], "rep")
	if int(before) != int(reputation):
		reputation_changed.emit(reputation)


func reputation_title() -> String:
	if reputation >= 60: return "Hero of Aldmere"
	if reputation >= 30: return "Honoured"
	if reputation >= 10: return "Respected"
	if reputation > -10: return "Stranger"
	if reputation > -30: return "Distrusted"
	if reputation > -60: return "Outlaw"
	return "Villain"


func commit_crime(settlement: String, severity: float, what: String) -> void:
	settlement_standing[settlement] = float(settlement_standing.get(settlement, 0.0)) + severity
	change_reputation(-severity * 0.5, what)


## Wanted: the settlement's watch comes to arrest you. They only draw steel if you resist.
func is_wanted_in(settlement: String) -> bool:
	return float(settlement_standing.get(settlement, 0.0)) >= WANTED_AT


func is_resisting(settlement: String) -> bool:
	return is_wanted_in(settlement) and bool(resisting.get(settlement, false))


func clear_bounty(settlement: String) -> void:
	settlement_standing.erase(settlement)
	resisting.erase(settlement)


func wanted_settlements() -> Array:
	var out := []
	for s in settlement_standing:
		if is_wanted_in(s):
			out.append(s)
	return out


## Bounties fade: the watch forgets a scuffle after a few days.
func _decay_bounties() -> void:
	for s in settlement_standing.keys():
		settlement_standing[s] = float(settlement_standing[s]) - 10.0
		if float(settlement_standing[s]) <= 0.0:
			settlement_standing.erase(s)
	for s in resisting.keys():
		if not is_wanted_in(s):
			resisting.erase(s)


## A test switch, from the page address (?name) or the command line (--name).
func debug_flag(name: String) -> bool:
	return _query.contains(name) if OS.has_feature("web") else ("--" + name) in OS.get_cmdline_user_args()


func mark(tag: String) -> void:
	if perf_overlay:
		frame_marks.append(tag)


func discover(location: String) -> bool:
	if discovered.has(location):
		return false
	discovered[location] = true
	return true


# ---------------------------------------------------------------- settings
func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cf.get_value("settings", k, settings[k])
	elif OS.has_feature("web"):
		# the browser build: WebGL 2 can't afford the desktop's shadows, grass or draw distance
		settings.merge(PRESETS.low, true)
		settings.preset = "low"
		settings.render_scale = 1.0
		settings.view_distance = 0.55
		settings.grass_density = 0.3
	elif DisplayServer.screen_get_size().x * DisplayServer.screen_get_scale() > 2600.0:
		settings.render_scale = 0.5    # 4K panel: FSR 2 reconstructs 4K from a 1080p internal image
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):
			for kv in arg.substr(6).split(","):
				var p := kv.split(":")
				if p.size() == 2 and settings.has(p[0]):
					settings[p[0]] = str_to_var(p[1])
	apply_display_settings()


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)
	apply_display_settings()
	settings_changed.emit()


func apply_preset(name: String) -> void:
	settings.preset = name
	for k in PRESETS[name]:
		settings[k] = PRESETS[name][k]
	save_settings()


func apply_display_settings() -> void:
	var win := get_window()
	if win == null:
		return
	if not OS.has_feature("web"):        # a page can only go fullscreen from a click
		win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if settings.fullscreen else (Window.MODE_MAXIMIZED if win.mode == Window.MODE_MAXIMIZED else Window.MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.max_fps)
	var vp := get_viewport()
	var rs := float(settings.render_scale)
	vp.scaling_3d_scale = rs
	if Assets.compat:
		RenderingServer.directional_shadow_atlas_set_size(2048, true)    # as the browser build
	if OS.has_feature("web"):
		# WebGL 2: no temporal upscalers or TAA; plain scaling
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.use_taa = false
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.mesh_lod_threshold = 1.0 / maxf(float(settings.view_distance), 0.3)
		win.content_scale_factor = clampf(float(settings.get("ui_scale", 1.0)), 0.75, 1.3)
		AudioServer.set_bus_volume_db(0, linear_to_db(float(settings.master_volume)))
		return
	if rs < 0.99 and settings.fsr:
		# Apple GPUs upscale in hardware (MetalFX); elsewhere AMD FSR 2
		var metal := OS.get_name() == "macOS" and RenderingServer.get_current_rendering_driver_name() == "metal"
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if metal else Viewport.SCALING_3D_MODE_FSR2
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.use_taa = rs >= 0.99 or not settings.fsr
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.mesh_lod_threshold = 1.0 / maxf(float(settings.view_distance), 0.3)
	# the interface is laid out for 1080p and scales with the window (2x on a 4K screen); this trims it
	win.content_scale_factor = clampf(float(settings.get("ui_scale", 1.0)), 0.75, 1.3)
	AudioServer.set_bus_volume_db(0, linear_to_db(float(settings.master_volume)))


# ---------------------------------------------------------------- input map
func _register_inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C], "interact": [KEY_E], "inventory": [KEY_TAB, KEY_I],
		"map": [KEY_M], "journal": [KEY_J], "pause": [KEY_ESCAPE], "torch": [KEY_T], "hold_coin": [KEY_G], "call_horse": [KEY_H], "quicksave": [KEY_F5, KEY_K] if OS.has_feature("web") else [KEY_F5],
		"quickload": [KEY_F9, KEY_L] if OS.has_feature("web") else [KEY_F9], "toggle_hud": [KEY_F1], "wait": [KEY_Z], "hot_1": [KEY_1], "hot_2": [KEY_2], "hot_3": [KEY_3], "hot_4": [KEY_4],
		"photo_mode": [KEY_F2], "draw_weapon": [KEY_R], "dodge": [KEY_ALT],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for pair in [["attack", MOUSE_BUTTON_LEFT], ["block", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)


# ---------------------------------------------------------------- save / load
func new_game() -> void:
	minutes = 8.0 * 60.0
	_last_hour = 8
	_last_day = 0
	stats = {"health": 100.0, "stamina": 100.0, "hunger": 85.0, "thirst": 85.0, "warmth": 70.0}
	silver = 25 * Items.SILVER_PER_GOLD + 8
	inventory = {"bread": 2, "apple": 3, "waterskin": 1, "torch": 2, "campfire_kit": 1, "bandage": 2, "rusty_sword": 1, "wooden_shield": 1, "wool_cloak": 1}
	waterskin_charges = 5
	equipped = {"weapon": "rusty_sword", "shield": "wooden_shield", "cloak": "wool_cloak", "armor": ""}
	reputation = 10.0
	settlement_standing = {}
	resisting = {}
	quests = []
	quest_seq = 0
	world_drops = []
	waypoint = Vector2.INF
	discovered = {}
	looted = {}
	dead_npcs = {}
	owned_horses = []
	kills = {}
	loading_save = {}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	if player_ref == null:
		return false
	var data := {
		"version": 1, "minutes": minutes, "stats": stats, "silver": silver, "inventory": inventory, "equipped": equipped,
		"waterskin": waterskin_charges, "reputation": reputation, "standing": settlement_standing, "discovered": discovered,
		"looted": looted, "dead_npcs": dead_npcs, "kills": kills, "horses": owned_horses, "player": player_ref.call("get_save_state"),
		"quests": quests, "quest_seq": quest_seq,
		"location": _where(),
		"waypoint": [waypoint.x, waypoint.y] if waypoint != Vector2.INF else [],
		"drops": world_drops.map(func(d): return {"id": d.id, "count": d.count, "x": d.x, "y": d.y, "z": d.z}),
		"world": world_ref.call("get_save_state") if world_ref else {},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	notify.emit("Game saved.", "info")
	return true


func _where() -> String:
	if player_ref == null:
		return ""
	var p: Vector3 = player_ref.global_position
	var n := WorldData.location_name_at(p)
	if n != "":
		return n
	var s := WorldData.nearest_settlement(p, 1e9)
	if s.is_empty():
		return ""
	var d := Vector2(float(s.x) - p.x, float(s.z) - p.z)
	return "%s of %s" % [Dialogue.compass(Vector3(-d.x, 0, -d.y)).capitalize(), s.name] if d.length() > 200.0 else String(s.name)


func read_save() -> Dictionary:
	if not has_save():
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return d if d is Dictionary else {}


func apply_save(d: Dictionary) -> void:
	minutes = float(d.get("minutes", minutes))
	_last_hour = hour()
	_last_day = day()
	stats = d.get("stats", stats)
	silver = int(d.get("silver", silver))
	inventory = {}
	for k in d.get("inventory", {}):
		inventory[k] = int(d.inventory[k])
	equipped = d.get("equipped", equipped)
	waterskin_charges = int(d.get("waterskin", 5))
	reputation = float(d.get("reputation", 10.0))
	settlement_standing = d.get("standing", {})
	resisting = {}
	discovered = d.get("discovered", {})
	looted = d.get("looted", {})
	dead_npcs = d.get("dead_npcs", {})
	kills = d.get("kills", {})
	quests = d.get("quests", [])
	world_drops = []
	var wp: Array = d.get("waypoint", [])
	waypoint = Vector2(float(wp[0]), float(wp[1])) if wp.size() == 2 else Vector2.INF
	quest_seq = int(d.get("quest_seq", quests.size()))
	owned_horses = d.get("horses", [])
	loading_save = d


func _exit_tree() -> void:
	Assets.settle_prefetch(true)   # don't leave background model loads dangling at shutdown
	Assets.free_lods()
