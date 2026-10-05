extends CanvasLayer
## In-game HUD: compass, vitals, clock & weather, purse, interaction prompt,
## notifications, discovery banners, subtitles and full-screen overlays.

var root: Control
var tracker: Label               # active task objectives (top left)
var _track_t := 0.0
const QUESTS := preload("res://scripts/core/quests.gd")
var compass: Control
var vitals: Control
var info: Label
var purse: Label
var gear: Label
var prompt: Label
var prompt_box: HBoxContainer
var prompt_key: Label
var _key_box: PanelContainer
var crosshair: Control
var target_bar: Control
var damage_dir: Control
var _hit_t := 0.0
var combat_label: Label
var notes: VBoxContainer
var banner: VBoxContainer
var banner_title: Label
var banner_sub: Label
var subtitle: Label
var fps: Label
var overlay_dmg: ColorRect
var overlay_water: ColorRect
var fade: ColorRect
var death_label: Label
var _loc := ""
var _loc_t := 0.0
var _sub_t := 0.0
var _dmg := 0.0
var _hidden := false
var _wander := 0.0               # distance walked since anything was last found (for the "lost?" hint)
var _wander_from := Vector3.INF
var _lost_hint := false
var _click_label: Label         # browsers: the mouse can only be captured from a click
var _had_lock := false
var menus: Node


class Compass extends Control:
	var hud
	var _labels := []
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var p: Player = Game.player_ref
		if p == null:
			return
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.04, 0.03, 0.55))
		draw_line(Vector2(0, h), Vector2(w, h), Color(0.75, 0.6, 0.3, 0.6), 1.5)
		var yaw := -p._yaw
		var fov := deg_to_rad(150.0)
		var f := UITheme.font("header")
		for i in 72:
			var a := i * TAU / 72.0
			var d := wrapf(a - yaw, -PI, PI)
			if absf(d) > fov * 0.5:
				continue
			var x := w * 0.5 + d / fov * w
			var major := i % 9 == 0
			var col := Color(0.9, 0.82, 0.62, 1.0 - absf(d) / (fov * 0.5) * 0.8)
			draw_line(Vector2(x, h - (12 if major else 6)), Vector2(x, h - 2), col, 1.5)
			if major:
				var labels := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
				var lbl: String = labels[i / 9]
				var fs := 20 if lbl.length() == 1 else 15
				var tw := f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(f, Vector2(x - tw * 0.5, h - 16), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.86, 0.5, col.a) if lbl == "N" else col)
		# markers: every town, village and castle (the way back is never lost), places you have found,
		# a "?" for anything unfound close by, your tasks and your waypoint
		var pp := p.global_position
		_labels = []
		for s in WorldData.settlements:
			if s.type in ["town", "village", "castle"] or Game.discovered.has(s.name):
				_marker(Vector3(s.x, 0, s.z), pp, yaw, fov, w, h, s.name, s.type, f, 1e9)
		for q in WorldData.pois:
			if Game.discovered.has(q.name):
				_marker(Vector3(q.x, 0, q.z), pp, yaw, fov, w, h, q.name, "poi", f, 2500.0)
		var wd = Game.world_ref.wilds if Game.world_ref else null
		if wd:
			for s in wd.sites:
				if s.found:
					_marker(Vector3(s.x, 0, s.z), pp, yaw, fov, w, h, s.name, "wild", f, 1200.0)
				else:
					_marker(Vector3(s.x, 0, s.z), pp, yaw, fov, w, h, "?", "unknown", f, 260.0)
		for q in hud.QUESTS.active():
			var m: Vector2 = hud.QUESTS.marker(q)
			_marker(Vector3(m.x, 0, m.y), pp, yaw, fov, w, h, String(q.title), "quest", f, 1e9)
		if Game.waypoint != Vector2.INF:
			_marker(Vector3(Game.waypoint.x, 0, Game.waypoint.y), pp, yaw, fov, w, h, "Waypoint", "waypoint", f, 1e9)
		# name the marker nearest the middle; the waypoint gets its own line beneath
		_labels.sort_custom(func(a, b): return a[0] < b[0])
		var row := 0
		for l in _labels:
			if row > 0 and float(l[0]) < 9.0:
				continue
			var tw := f.get_string_size(String(l[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var lx := clampf(float(l[1]) - tw * 0.5, 0.0, w - tw)
			draw_string(f, Vector2(lx + 1, h + 19 + row * 18), String(l[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.7))
			draw_string(f, Vector2(lx, h + 18 + row * 18), String(l[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, l[3])
			row += 1
	func _marker(at: Vector3, pp: Vector3, yaw: float, fov: float, w: float, h: float, nm: String, kind: String, f: Font, max_d: float) -> void:
		var dv := at - pp
		var dist := Vector2(dv.x, dv.z).length()
		if dist > max_d or dist < (12.0 if kind in ["waypoint", "quest", "unknown"] else 60.0):
			return
		# world north = -Z; compass angle 0 = north, increasing clockwise (east = +X)
		var a := atan2(dv.x, -dv.z)
		var d := wrapf(a - yaw, -PI, PI)
		if absf(d) > fov * 0.5:
			return
		var x := w * 0.5 + d / fov * w
		var col: Color = {"town": Color(1, 0.8, 0.4), "village": Color(0.95, 0.9, 0.7), "castle": Color(0.85, 0.6, 1.0), "ruin": Color(0.6, 0.6, 0.6), "ruin_keep": Color(0.6, 0.6, 0.6),
			"poi": Color(0.6, 0.9, 0.6), "wild": Color(0.72, 0.86, 0.62), "unknown": Color(1, 1, 1, 0.75), "quest": Color(1.0, 0.76, 0.22), "waypoint": Color(0.45, 0.9, 1.0)}.get(kind, Color.WHITE)
		if kind in ["quest", "waypoint"]:
			var r := 6.5
			draw_colored_polygon(PackedVector2Array([Vector2(x, 9 - r), Vector2(x + r, 9), Vector2(x, 9 + r), Vector2(x - r, 9)]), col)
		elif kind == "unknown":
			draw_string(f, Vector2(x - 5, 16), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
			return
		else:
			draw_circle(Vector2(x, 9), 5.0 if kind in ["town", "castle"] else 3.5, col)
		if absf(d) < 0.2 or kind == "waypoint":
			_labels.append([absf(d) if kind != "waypoint" else 9.0, x, "%s  %s" % [nm, ("%d m" % int(dist)) if dist < 1000.0 else ("%.1f km" % (dist / 1000.0))], col])
	func _ready() -> void:
		set_process(true)


class Vitals extends Control:
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var s := Game.stats
		var wv := float(s.warmth)
		var rows := [["Health", float(s.health) / Game.max_health, Color(0.72, 0.12, 0.1)], ["Stamina", float(s.stamina) / 100.0, Color(0.36, 0.62, 0.25)],
			["Hunger", float(s.hunger) / 100.0, Color(0.82, 0.55, 0.2)], ["Thirst", float(s.thirst) / 100.0, Color(0.25, 0.5, 0.82)],
			["Warmth", wv / 100.0, Color(0.35, 0.65, 1.0) if wv < 30.0 else (Color(1.0, 0.45, 0.15) if wv > 80.0 else Color(0.95, 0.75, 0.4))]]
		var p: Player = Game.player_ref
		if p and p.mounted:
			rows.append(["Horse", float(p.mounted.get("stamina")) / 100.0, Color(0.78, 0.6, 0.36)])
		if p and p.head_under:
			rows.append(["Breath", p.breath / 30.0, Color(0.7, 0.85, 1.0)])
		var f := UITheme.font("fell")
		var y := size.y - rows.size() * 27.0      # bottom-aligned: extra rows grow upwards
		for r in rows:
			var v := clampf(float(r[1]), 0.0, 1.0)
			var col: Color = r[2]
			var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008) if v < 0.22 else 1.0
			draw_string(f, Vector2(1, y + 19), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0, 0, 0, 0.6))
			draw_string(f, Vector2(0, y + 18), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.95, 0.88, 0.72, 0.95))
			draw_rect(Rect2(98, y + 5, 250, 15), Color(0.04, 0.03, 0.02, 0.78))
			draw_rect(Rect2(100, y + 7, 246 * v, 11), Color(col.r, col.g, col.b, pulse))
			draw_rect(Rect2(100, y + 7, 246 * v, 3), Color(1, 1, 1, 0.12 * pulse))
			draw_rect(Rect2(98, y + 5, 250, 15), Color(0.66, 0.53, 0.3, 0.75), false, 1.5)
			y += 27.0


## Name and health of the foe you are fighting (top centre, under the compass).
class TargetBar extends Control:
	var target: Node3D
	var t := 0.0
	func _process(delta: float) -> void:
		t = maxf(t - delta, 0.0)
		if target and is_instance_valid(target) and target.has_method("is_dead") and not target.call("is_dead"):
			var p: Node3D = Game.player_ref
			var chasing: bool = (target is NPC and (target as NPC).target == p) or (target is Animal and (target as Animal).threat == p)
			if p and p.global_position.distance_to(target.global_position) < 18.0 and chasing:
				t = maxf(t, 0.6)       # stays up while it is still coming for you
		queue_redraw()
	func _draw() -> void:
		if t <= 0.0 or target == null or not is_instance_valid(target):
			return
		var a := clampf(t / 0.6, 0.0, 1.0)
		var nm := ""
		var hp := 0.0
		var mx := 1.0
		if target is NPC:
			var d = (target as NPC).data
			nm = "%s, %s" % [d.name, NPCManager.role_title(d)] if d.role != "bandit" else String(d.name) + ", Bandit"
			hp = float(d.health)
			mx = float(d.max_health)
		elif target is Animal:
			var an := target as Animal
			nm = an.species.capitalize()
			hp = an.hp
			mx = float(an.sp.hp)
		var f := UITheme.font("header")
		var w := size.x
		var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		draw_string(f, Vector2((w - tw) * 0.5 + 1, 21), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0, 0, 0, 0.7 * a))
		draw_string(f, Vector2((w - tw) * 0.5, 20), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.98, 0.9, 0.72, a))
		var v := clampf(hp / maxf(mx, 1.0), 0.0, 1.0)
		draw_rect(Rect2(0, 30, w, 12), Color(0.03, 0.02, 0.02, 0.8 * a))
		draw_rect(Rect2(2, 32, (w - 4) * v, 8), Color(0.72, 0.1, 0.08, a))
		draw_rect(Rect2(0, 30, w, 12), Color(0.66, 0.53, 0.3, 0.8 * a), false, 1.5)


## Red arcs around the crosshair pointing at whatever just hurt you.
class DamageDir extends Control:
	var hits := []
	func add(from: Vector3) -> void:
		hits.append([from, 1.0])
	func _process(delta: float) -> void:
		for h in hits:
			h[1] -= delta * 0.8
		hits = hits.filter(func(h): return h[1] > 0.0)
		queue_redraw()
	func _draw() -> void:
		var p: Player = Game.player_ref
		if p == null:
			return
		var c := size * 0.5
		for h in hits:
			var to: Vector3 = h[0] - p.global_position
			var rel := wrapf(atan2(to.x, -to.z) + p._yaw, -PI, PI) - PI * 0.5
			var col := Color(0.85, 0.07, 0.04, clampf(h[1], 0.0, 1.0) * 0.9)
			draw_arc(c, 170.0, rel - 0.32, rel + 0.32, 24, col, 9.0, true)
			draw_arc(c, 182.0, rel - 0.18, rel + 0.18, 16, Color(col.r, col.g, col.b, col.a * 0.5), 4.0, true)


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	# overlays
	overlay_water = _full_rect(Color(0.05, 0.25, 0.3, 0.0))
	overlay_dmg = _full_rect(Color(0, 0, 0, 0))
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = "shader_type canvas_item; uniform float amount = 0.0; uniform float cold = 0.0; void fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.25, 0.75, length(d)); COLOR = mix(vec4(0.6, 0.0, 0.0, v * amount), vec4(0.75, 0.88, 1.0, v * 0.8), cold * (1.0 - amount)); COLOR.a = max(v * amount, v * cold * 0.7); }"
	overlay_dmg.material = sm
	# compass
	compass = Compass.new()
	compass.hud = self
	compass.custom_minimum_size = Vector2(760, 34)
	UITheme.place(compass, Control.PRESET_CENTER_TOP, Vector2(-380, 14), Vector2(760, 34))
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(compass)
	# info (top right)
	info = UITheme.label("", 21, UITheme.PARCHMENT, "fell")
	info.add_theme_constant_override("outline_size", 6)
	info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.place(info, Control.PRESET_TOP_RIGHT, Vector2(-490, 14), Vector2(466, 110))
	root.add_child(info)
	# vitals (bottom left)
	vitals = Vitals.new()
	UITheme.place(vitals, Control.PRESET_BOTTOM_LEFT, Vector2(28, -214), Vector2(360, 190))
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vitals)
	# purse & gear (bottom right)
	purse = UITheme.label("", 23, UITheme.GOLD, "header")
	purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	purse.add_theme_constant_override("outline_size", 6)
	purse.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	UITheme.place(purse, Control.PRESET_BOTTOM_RIGHT, Vector2(-444, -124), Vector2(420, 34))
	root.add_child(purse)
	gear = UITheme.label("", 19, Color(0.9, 0.83, 0.66), "body")
	gear.add_theme_constant_override("outline_size", 6)
	gear.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gear.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	UITheme.place(gear, Control.PRESET_BOTTOM_RIGHT, Vector2(-624, -86), Vector2(600, 70))
	gear.grow_vertical = Control.GROW_DIRECTION_BEGIN   # extra lines (wanted notices) grow upwards
	root.add_child(gear)
	# crosshair & prompt
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)
	damage_dir = DamageDir.new()
	damage_dir.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_dir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_dir)
	target_bar = TargetBar.new()
	UITheme.place(target_bar, Control.PRESET_CENTER_TOP, Vector2(-200, 74), Vector2(400, 46))
	target_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(target_bar)
	combat_label = UITheme.label("", 30, Color(1, 0.9, 0.6), "header")
	combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combat_label.add_theme_constant_override("outline_size", 9)
	combat_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	UITheme.place(combat_label, Control.PRESET_CENTER, Vector2(-300, -150), Vector2(600, 44))
	combat_label.pivot_offset = Vector2(300, 22)
	combat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(combat_label)
	# interaction prompt: a key-cap and the action, large enough to read at a glance
	prompt_box = HBoxContainer.new()
	prompt_box.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_box.add_theme_constant_override("separation", 14)
	prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.place(prompt_box, Control.PRESET_CENTER, Vector2(-700, 62), Vector2(1400, 52))
	root.add_child(prompt_box)
	_key_box = PanelContainer.new()
	var ks := StyleBoxFlat.new()
	ks.bg_color = Color(0.1, 0.075, 0.05, 0.88)
	ks.border_color = UITheme.GOLD
	ks.set_border_width_all(2)
	ks.set_corner_radius_all(7)
	ks.content_margin_left = 13
	ks.content_margin_right = 13
	ks.content_margin_top = 3
	ks.content_margin_bottom = 5
	ks.shadow_color = Color(0, 0, 0, 0.5)
	ks.shadow_size = 5
	_key_box.add_theme_stylebox_override("panel", ks)
	_key_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prompt_key = UITheme.label("E", 25, Color(1.0, 0.9, 0.6), "header")
	_key_box.add_child(prompt_key)
	_key_box.visible = false
	prompt_box.add_child(_key_box)
	prompt = UITheme.label("", 30, Color(1.0, 0.95, 0.82), "body")
	prompt.add_theme_constant_override("outline_size", 9)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.72))
	prompt_box.add_child(prompt)
	# notifications
	notes = VBoxContainer.new()
	UITheme.place(notes, Control.PRESET_CENTER_LEFT, Vector2(28, -70), Vector2(660, 320))
	notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notes)
	# banner
	banner = VBoxContainer.new()
	UITheme.place(banner, Control.PRESET_CENTER_TOP, Vector2(-500, 120), Vector2(1000, 120))
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	root.add_child(banner)
	banner_title = UITheme.label("", 64, Color(0.97, 0.88, 0.64), "title")
	banner_title.add_theme_constant_override("outline_size", 10)
	banner_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_title)
	banner_sub = UITheme.label("", 24, UITheme.GOLD, "header")
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_sub)
	# subtitles
	subtitle = UITheme.label("", 28, Color(1, 0.97, 0.9), "body")
	subtitle.add_theme_constant_override("outline_size", 9)
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.place(subtitle, Control.PRESET_CENTER_BOTTOM, Vector2(-600, -250), Vector2(1200, 96))
	root.add_child(subtitle)
	tracker = UITheme.label("", 21, Color(0.96, 0.88, 0.66), "body")
	tracker.add_theme_constant_override("outline_size", 6)
	tracker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	UITheme.place(tracker, Control.PRESET_TOP_LEFT, Vector2(28, 60), Vector2(660, 130))
	tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tracker)
	fps = UITheme.label("", 16, Color(0.7, 1, 0.7))
	fps.position = Vector2(10, 6)
	root.add_child(fps)
	# fade & death
	fade = _full_rect(Color(0, 0, 0, 0))
	death_label = UITheme.label("", 72, Color(0.75, 0.12, 0.1), "title")
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.place(death_label, Control.PRESET_CENTER, Vector2(-500, -60), Vector2(1000, 120))
	root.add_child(death_label)
	if OS.has_feature("web") and not Game.mobile:
		_click_label = UITheme.label("Click to play", 36, Color(1.0, 0.88, 0.6), "header")
		_click_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_click_label.add_theme_constant_override("outline_size", 10)
		_click_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		UITheme.place(_click_label, Control.PRESET_CENTER, Vector2(-400, -110), Vector2(800, 50))
		_click_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_click_label.visible = false
		root.add_child(_click_label)
	if Game.mobile:
		_mobile_layout()
	Game.notify.connect(_on_notify)
	if Game.player_ref:
		(Game.player_ref as Player).interaction_changed.connect(set_prompt)
	if ResourceLoader.exists("res://scripts/ui/menus.gd"):
		menus = load("res://scripts/ui/menus.gd").new()
		add_child(menus)


## Phones: the touch controls take the bottom corners, so the vitals move to the top left, the
## notes under the compass, the day and purse under the menu buttons, and the gear line goes.
func _mobile_layout() -> void:
	UITheme.place(vitals, Control.PRESET_TOP_LEFT, Vector2(20, 12), Vector2(360, 190))
	UITheme.place(tracker, Control.PRESET_TOP_LEFT, Vector2(24, 196), Vector2(560, 110))
	UITheme.place(info, Control.PRESET_TOP_RIGHT, Vector2(-490, 104), Vector2(466, 110))
	UITheme.place(purse, Control.PRESET_TOP_RIGHT, Vector2(-444, 212), Vector2(420, 34))
	UITheme.place(notes, Control.PRESET_CENTER_TOP, Vector2(-330, 120), Vector2(660, 220))
	UITheme.place(subtitle, Control.PRESET_CENTER_BOTTOM, Vector2(-380, -200), Vector2(760, 110))
	UITheme.place(prompt_box, Control.PRESET_CENTER, Vector2(-500, 56), Vector2(1000, 52))
	UITheme.place(compass, Control.PRESET_CENTER_TOP, Vector2(-300, 14), Vector2(600, 34))
	compass.custom_minimum_size = Vector2(600, 34)
	gear.visible = false


func _full_rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r


func _process(delta: float) -> void:
	var p: Player = Game.player_ref
	if p == null:
		return
	var w = Game.world_ref
	var atm: Atmosphere = w.atmosphere if w else null
	var wname := String(atm.weather).capitalize() if atm else ""
	if atm and atm.weather in ["snow", "rain"] and atm.precip_kind != atm.weather and atm.weather != "storm":
		wname = atm.precip_kind.capitalize()
	info.text = "%s\nDay %d, %s  -  %s\n%s" % [_loc if _loc != "" else "Aldmere", Game.day() + 1, Game.weekday_name(), Game.clock_text(), wname]
	purse.text = Game.purse_text()
	var g := []
	if Game.equipped.weapon != "": g.append(Items.display_name(Game.equipped.weapon))
	if Game.equipped.shield != "": g.append(Items.display_name(Game.equipped.shield))
	if Game.equipped.cloak != "": g.append(Items.display_name(Game.equipped.cloak))
	if p.torch_on: g.append("Torch lit")
	if p.holding_coin(): g.append("Holding a gold coin")
	gear.text = "  |  ".join(g) + "\nReputation: %s (%d)" % [Game.reputation_title(), int(Game.reputation)]
	for s in Game.wanted_settlements():
		gear.text += "\n%s in %s  (fine %s)" % ["RESISTING ARREST" if Game.is_resisting(s) else "Wanted", s, Items.price_text(Dialogue.fine_amount(s))]
	_hit_t = maxf(_hit_t - delta, 0.0)
	crosshair.queue_redraw()
	# overlays
	_dmg = maxf(_dmg - delta * 1.5, 0.0)
	var hp := float(Game.stats.health) / Game.max_health
	var cold := clampf((25.0 - float(Game.stats.warmth)) / 25.0, 0.0, 1.0)
	(overlay_dmg.material as ShaderMaterial).set_shader_parameter("amount", maxf(_dmg, (1.0 - hp) * 0.6 if hp < 0.35 else 0.0))
	(overlay_dmg.material as ShaderMaterial).set_shader_parameter("cold", cold)
	overlay_water.color.a = lerpf(overlay_water.color.a, 0.35 if p.head_under else 0.0, 1.0 - exp(-delta * 8.0))
	# location discovery
	_loc_t -= delta
	if _loc_t <= 0.0:
		_loc_t = 1.0
		var n := WorldData.location_name_at(p.global_position)
		if n != _loc:
			_loc = n
			_on_location(n)
		if _wander_from != Vector3.INF:
			_wander += minf(_wander_from.distance_to(p.global_position), 30.0)
		_wander_from = p.global_position
		if _wander > 900.0 and not _lost_hint and not p.mounted:
			_lost_hint = true
			Game.notify.emit("Lost? The compass always marks the towns and villages, and a \"?\" means something is close by. M opens the map: click it to set a waypoint.", "info")
		if Game.waypoint != Vector2.INF and Vector2(p.global_position.x - Game.waypoint.x, p.global_position.z - Game.waypoint.y).length() < 25.0:
			Game.waypoint = Vector2.INF
			Game.notify.emit("You have reached your waypoint.", "info")
	_sub_t -= delta
	if _sub_t <= 0.0:
		subtitle.text = ""
	if _click_label:
		_web_mouse(p)
	fps.visible = bool(Game.settings.show_fps)
	if fps.visible:
		fps.text = "%d FPS" % Engine.get_frames_per_second()
	if Input.is_action_just_pressed("toggle_hud"):
		_hidden = not _hidden
		for c in [compass, info, vitals, purse, gear, prompt_box, crosshair, notes, tracker, target_bar, damage_dir]:
			c.visible = not _hidden
		gear.visible = gear.visible and not Game.mobile
	_track_t -= delta
	if _track_t <= 0.0:
		_track_t = 0.5
		var lines := []
		for q in QUESTS.active().slice(0, 3):
			lines.append("◆ " + QUESTS.objective(q))
		tracker.text = "\n".join(lines)


## Browsers capture the mouse only from a click, and take Esc for themselves (releasing the
## mouse before the game sees the key): ask for a click, and pause when the mouse is let go.
func _web_mouse(p: Player) -> void:
	var playing: bool = Game.world_ref and Game.world_ref.ready_to_play and not Game.in_menu and not p.dead
	var locked := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if playing and locked:
		_had_lock = true
	elif playing and _had_lock:
		_had_lock = false
		menus.open_pause()
	_click_label.visible = playing and not locked


func _unhandled_input(event: InputEvent) -> void:
	if _click_label and _click_label.visible and event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _on_location(n: String) -> void:
	var kind := ""
	for s in WorldData.settlements:
		if s.name == n:
			kind = {"town": "Town", "village": "Village", "castle": "Castle", "ruin": "Ruins", "ruin_keep": "Ruins"}[s.type]
			if Game.is_market_day(n):
				kind += "  -  Market Day"
	if kind == "":
		for q in WorldData.pois:
			if q.name == n:
				kind = "Landmark"
	if kind == "":
		return
	var first := Game.discover(n)
	show_banner(n, ("Discovered: " if first else "") + kind)
	if first:
		Game.change_reputation(0.5)


func show_banner(title: String, sub: String) -> void:
	_wander = 0.0
	Game.mark("banner")
	banner_title.text = title
	banner_sub.text = sub
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.8)
	tw.tween_interval(3.0)
	tw.tween_property(banner, "modulate:a", 0.0, 1.2)


func show_subtitle(speaker: String, text: String, secs := 4.0) -> void:
	subtitle.text = ("%s: \"%s\"" % [speaker, text]) if speaker != "" else text
	_sub_t = secs


func _on_notify(text: String, kind: String) -> void:
	var l := UITheme.label(text, 22, {"warn": Color(1, 0.62, 0.45), "item": Color(0.8, 0.95, 0.7), "rep": Color(0.9, 0.8, 1.0)}.get(kind, UITheme.PARCHMENT), "body")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(640, 0)
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	notes.add_child(l)
	if notes.get_child_count() > 6:
		notes.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


func pulse_damage() -> void:
	_dmg = 1.0


## "[E] Talk to Aldric" shows as a key-cap and the action; plain text shows as a quiet note.
func set_prompt(t: String) -> void:
	var key := ""
	if t.length() > 4 and t[0] == "[" and t[2] == "]":
		key = t[1]
		t = t.substr(4)
		if Game.mobile and key == "E":
			key = "Use"            # (the touch button's name)
	_key_box.visible = key != ""
	prompt_key.text = key
	prompt.text = t
	prompt.add_theme_font_size_override("font_size", 30 if key != "" else 23)
	prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82) if key != "" else Color(0.88, 0.83, 0.72))


func _draw_crosshair() -> void:
	crosshair.draw_circle(Vector2.ZERO, 3.0, Color(1, 0.95, 0.85, 0.85))
	crosshair.draw_arc(Vector2.ZERO, 6.0, 0, TAU, 20, Color(0, 0, 0, 0.35), 1.5)
	if _hit_t > 0.0:      # a connecting blow flashes a hit marker
		var a := _hit_t / 0.18
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			crosshair.draw_line(d * 8.0, d * 17.0, Color(1, 0.9, 0.75, a), 2.5, true)


## Short combat call-outs above the crosshair: "Parried!", "Sneak attack!", "Guard broken!".
func combat_text(t: String, col := Color(1, 0.9, 0.6)) -> void:
	combat_label.text = t
	combat_label.add_theme_color_override("font_color", col)
	combat_label.modulate.a = 1.0
	combat_label.scale = Vector2.ONE * 1.25
	var tw := combat_label.create_tween()
	tw.tween_property(combat_label, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(0.6)
	tw.tween_property(combat_label, "modulate:a", 0.0, 0.5)


func hit_marker() -> void:
	_hit_t = 0.18


func show_target(n: Node3D) -> void:
	target_bar.target = n
	target_bar.t = 4.0


func damage_from(at: Vector3) -> void:
	damage_dir.add(at)


func fade_sleep() -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.7)
	tw.tween_interval(1.4)
	tw.tween_property(fade, "color:a", 0.0, 1.2)


func fade_wait() -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.85, 0.3)
	tw.tween_interval(0.15)
	tw.tween_property(fade, "color:a", 0.0, 0.5)


func show_death() -> void:
	death_label.text = "You have fallen"
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.85, 2.0)


func hide_death() -> void:
	death_label.text = ""
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 1.5)
