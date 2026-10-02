extends Control
## All in-game menus: pause, inventory & character, world map, dialogue, trading,
## horse market and settings.

const QUESTS := preload("res://scripts/core/quests.gd")
const ITEMS3D := preload("res://scripts/core/item_models.gd")
const PICKUP := preload("res://scripts/world/pickup.gd")
const CATS := [["all", "All"], ["gear", "Arms & Armour"], ["food", "Food & Drink"], ["material", "Materials"], ["valuable", "Valuables"], ["tool", "Tools"], ["quest", "Quest"]]
var panel: PanelContainer
var mode := ""
var npc: NPC = null
var _dlg_text: RichTextLabel
var _dlg_opts: VBoxContainer
var _inv_sel := ""
var _inv_hover := ""
var _inv_cat := "all"
var _inv_grid: GridContainer
var _inv_detail: VBoxContainer
var _inv_left: VBoxContainer
var _inv_purse: Label
var _inv_buttons := {}
var _map_tex: TextureRect
var _map_zoom := 1.0
var _map_off := Vector2.ZERO
var _drag := false
var _press_at := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.get_theme()


func _unhandled_input(event: InputEvent) -> void:
	if Game.player_ref == null or Game.world_ref == null or not Game.world_ref.ready_to_play:
		if mode != "" and event.is_action_pressed("pause"):
			close()
		return
	if event.is_action_pressed("pause"):
		if mode == "":
			open_pause()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif mode == "inventory" and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_E, KEY_ENTER, KEY_Q, KEY_DELETE]:
		if event.keycode in [KEY_Q, KEY_DELETE]:
			_inv_drop(false)
		else:
			_inv_use()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and mode in ["", "inventory"]:
		if mode == "inventory": close()
		else: open_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and mode in ["", "map"]:
		if mode == "map": close()
		else: open_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal") and mode in ["", "journal"]:
		if mode == "journal": close()
		else: open_journal()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quicksave") and mode == "":
		Game.save_game()
	elif event.is_action_pressed("quickload") and mode == "":
		Game.world_ref.call("load_save")
	elif mode == "map" and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_map_zoom = minf(_map_zoom * 1.2, 6.0)
			_layout_map()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_map_zoom = maxf(_map_zoom / 1.2, 1.0)
			_layout_map()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
			if event.pressed:
				_press_at = event.position
			elif event.position.distance_to(_press_at) < 6.0 and _map_tex and Rect2(Vector2.ZERO, _map_tex.size).has_point(_map_tex.get_local_mouse_position()):
				# a click (not a drag): put the waypoint there
				var lp := _map_tex.get_local_mouse_position() / _map_tex.size.x
				Game.waypoint = Vector2(lp.x * WorldData.SIZE - WorldData.HALF, lp.y * WorldData.SIZE - WorldData.HALF)
				Audio.ui("click")
				_layout_map()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			Game.waypoint = Vector2.INF
			_layout_map()
	elif mode == "map" and event is InputEventMouseMotion and _drag:
		_map_off += event.relative
		_layout_map()


# ------------------------------------------------------------------ framework
func _open(new_mode: String, size: Vector2) -> VBoxContainer:
	close(false)
	mode = new_mode
	Game.in_menu = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.name = "Dim"
	add_child(dim)
	size = size.min(get_viewport_rect().size * 0.97)
	panel = PanelContainer.new()
	panel.custom_minimum_size = size
	UITheme.place(panel, Control.PRESET_CENTER, -size * 0.5, size)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	Audio.ui("open")
	return v


func close(resume := true) -> void:
	if npc and is_instance_valid(npc):
		npc.end_talk()
	npc = null
	for c in get_children():
		c.queue_free()
	panel = null
	mode = ""
	if resume:
		Game.in_menu = false
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if Game.world_ref else Input.MOUSE_MODE_VISIBLE
		Audio.ui("close")


func _title(v: Container, text: String, sub := "") -> void:
	var t := UITheme.label(text, 38, UITheme.GOLD, "header")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if sub != "":
		var s := UITheme.label(sub, 19, Color(0.8, 0.72, 0.58), "fell")
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	var sep := HSeparator.new()
	v.add_child(sep)


# ------------------------------------------------------------------ pause
func open_pause() -> void:
	var v := _open("pause", Vector2(700, 760))
	_title(v, "Knightfall", "Day %d, %s  -  %s" % [Game.day() + 1, Game.weekday_name(), Game.clock_text()])
	for b in [["Resume", func(): close()], ["Inventory", func(): open_inventory()], ["Journal", func(): open_journal()], ["Map of Aldmere", func(): open_map()], ["Settings", func(): open_settings()],
			["Save Game", func(): Game.save_game(); close()], ["Load Game", func(): close(); Game.world_ref.call("load_save")],
			["Quit to Title", func(): close(); get_tree().paused = false; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; get_tree().change_scene_to_file("res://scenes/main_menu.tscn")],
			["Quit Game", func(): get_tree().quit()]]:
		var btn := UITheme.button(b[0], b[1], 380)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(btn)
	var help := UITheme.label("WASD move · Shift sprint · Space jump · Ctrl crouch · E interact · LMB cut (hold: heavy blow) · RMB shield (just in time: parry)\nAlt or double-tap A/D/S dodge · R draw/sheathe · T torch · G gold coin · H call horse · Z wait · Tab inventory · J journal · M map\nRiding: W canter · Shift gallop · Ctrl walk · S rein in · 1 eat · 2 drink · 3 bandage · 4 campfire · F1 HUD · F5/F9 save/load", 16, Color(0.78, 0.7, 0.56))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)


# ------------------------------------------------------------------ inventory
## Equipment and condition on the left, the pack as a grid of item icons in the middle (by
## category), and the chosen item's details and actions on the right.
func open_inventory() -> void:
	var v := _open("inventory", Vector2(1520, 880))
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UITheme.label("Inventory", 40, UITheme.GOLD, "header"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_inv_purse = UITheme.label("", 26, UITheme.GOLD, "header")
	_inv_purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_inv_purse)
	v.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_inv_left = VBoxContainer.new()
	_inv_left.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_inv_left.custom_minimum_size = Vector2(350, 0)
	_inv_left.add_theme_constant_override("separation", 8)
	body.add_child(_inv_left)
	body.add_child(VSeparator.new())
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	body.add_child(mid)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	mid.add_child(tabs)
	var group := ButtonGroup.new()
	for c in CATS:
		var tb := Button.new()
		tb.text = c[1]
		tb.toggle_mode = true
		tb.button_group = group
		tb.button_pressed = c[0] == _inv_cat
		tb.add_theme_font_size_override("font_size", 17)
		tb.add_theme_color_override("font_pressed_color", UITheme.GOLD)
		tb.pressed.connect(func():
			_inv_cat = c[0]
			Audio.ui("page")
			_refresh_inv())
		tabs.add_child(tb)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(sc)
	_inv_grid = GridContainer.new()
	_inv_grid.columns = 6
	_inv_grid.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_inv_grid.add_theme_constant_override("h_separation", 10)
	_inv_grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(_inv_grid)
	body.add_child(VSeparator.new())
	_inv_detail = VBoxContainer.new()
	_inv_detail.custom_minimum_size = Vector2(400, 0)
	_inv_detail.add_theme_constant_override("separation", 8)
	body.add_child(_inv_detail)
	var hint := UITheme.label("Click to select  ·  double-click or E to use / equip  ·  right-click for quick use  ·  Q to drop  ·  Tab to close", 18, Color(0.78, 0.7, 0.56))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	if not Game.inventory.has(_inv_sel):
		_inv_sel = ""
	_refresh_inv()


func _cat_of(id: String) -> String:
	match String(Items.get_item(id).type):
		"weapon", "shield", "cloak", "armor": return "gear"
		"food", "drink": return "food"
		"material": return "material"
		"valuable": return "valuable"
		"tool": return "tool"
		"quest": return "quest"
	return "all"


func _refresh_inv() -> void:
	if _inv_grid == null:
		return
	_inv_purse.text = Game.purse_text()
	for c in _inv_grid.get_children():
		c.queue_free()
	_inv_buttons = {}
	var order := ["weapon", "shield", "armor", "cloak", "food", "drink", "tool", "material", "valuable", "quest"]
	var ids: Array = Game.inventory.keys().filter(func(i): return _inv_cat == "all" or _cat_of(i) == _inv_cat)
	ids.sort_custom(func(a, b):
		var ta := order.find(String(Items.get_item(a).type))
		var tb := order.find(String(Items.get_item(b).type))
		return ta < tb if ta != tb else int(Items.get_item(a).value) > int(Items.get_item(b).value))
	if _inv_sel == "" or not Game.inventory.has(_inv_sel) or not ids.has(_inv_sel):
		_inv_sel = ids[0] if not ids.is_empty() else ""
	for id in ids:
		var b := _slot(id, int(Game.inventory[id]), 104)
		_inv_grid.add_child(b)
		_inv_buttons[id] = b
	if ids.is_empty():
		var l := UITheme.label("Nothing here.", 21, Color(0.7, 0.64, 0.52))
		_inv_grid.add_child(l)
	_inv_restyle()
	_inv_show(_inv_sel)
	_inv_equipment()


func _slot_box(state: String, equipped: bool, selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	sb.bg_color = Color(0.09, 0.07, 0.05, 0.9)
	sb.border_color = Color(0.42, 0.33, 0.2, 0.75)
	sb.set_border_width_all(1)
	if equipped:
		sb.bg_color = Color(0.16, 0.12, 0.06, 0.95)
		sb.border_color = Color(0.8, 0.64, 0.32, 0.9)
		sb.set_border_width_all(2)
	if state == "hover" or state == "focus":
		sb.bg_color = sb.bg_color.lightened(0.12)
		sb.border_color = UITheme.GOLD
		sb.set_border_width_all(2)
	if selected or state == "pressed":
		sb.bg_color = Color(0.3, 0.21, 0.1, 0.98)
		sb.border_color = Color(1.0, 0.86, 0.52)
		sb.set_border_width_all(3)
		sb.shadow_color = Color(1.0, 0.75, 0.3, 0.25)
		sb.shadow_size = 6
	return sb


## One item: its icon in a frame, a count badge and a mark if it's equipped.
func _slot(id: String, count: int, px: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.icon = ITEMS3D.icon(id)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if b.icon == null:
		b.text = Items.display_name(id).substr(0, 10)
		b.add_theme_font_size_override("font_size", 14)
	b.tooltip_text = Items.display_name(id)
	b.focus_mode = Control.FOCUS_ALL
	if count > 1:
		var badge := UITheme.label(str(count), 19, Color(1, 0.95, 0.85), "header")
		badge.add_theme_constant_override("outline_size", 6)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		UITheme.place(badge, Control.PRESET_BOTTOM_RIGHT, Vector2(-60, -30), Vector2(54, 26))
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(badge)
	if Game.equipped.values().has(id) or (id == "torch" and Game.player_ref and Game.player_ref.torch_on):
		var mark := UITheme.label("E", 15, Color(0.1, 0.07, 0.03), "header")
		var dot := PanelContainer.new()
		var ds := StyleBoxFlat.new()
		ds.bg_color = UITheme.GOLD
		ds.set_corner_radius_all(10)
		ds.content_margin_left = 6
		ds.content_margin_right = 6
		dot.add_theme_stylebox_override("panel", ds)
		dot.add_child(mark)
		dot.position = Vector2(5, 5)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot)
	b.pressed.connect(func():
		_inv_sel = id
		Audio.ui("click")
		_inv_restyle()
		_inv_show(id))
	b.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			if (ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT) or ev.button_index == MOUSE_BUTTON_RIGHT:
				_inv_sel = id
				_inv_use())
	b.mouse_entered.connect(func():
		_inv_hover = id
		_inv_show(id))
	b.mouse_exited.connect(func():
		if _inv_hover == id:
			_inv_hover = ""
			_inv_show(_inv_sel))
	return b


func _inv_restyle() -> void:
	for id in _inv_buttons:
		var b: Button = _inv_buttons[id]
		var eq: bool = Game.equipped.values().has(id)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, _slot_box(st, eq, id == _inv_sel))


## The chosen (or hovered) item: big icon, what it does, what it's worth, and what you can do.
func _inv_show(id: String) -> void:
	if _inv_detail == null:
		return
	for c in _inv_detail.get_children():
		c.queue_free()
	if id == "" or not Game.inventory.has(id):
		var l := UITheme.label("Select an item to see it here.", 21, Color(0.72, 0.65, 0.52))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inv_detail.add_child(l)
		return
	var it := Items.get_item(id)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _slot_box("normal", false, false))
	frame.custom_minimum_size = Vector2(400, 230)
	var tr := TextureRect.new()
	tr.texture = ITEMS3D.icon(id)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(0, 210)
	frame.add_child(tr)
	_inv_detail.add_child(frame)
	var nm := UITheme.label(String(it.name), 30, UITheme.GOLD, "header")
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inv_detail.add_child(nm)
	var kind := {"weapon": "Weapon", "shield": "Shield", "cloak": "Cloak", "armor": "Armour", "food": "Food", "drink": "Drink", "material": "Material",
		"valuable": "Valuable", "tool": "Tool", "quest": "Task item"}.get(String(it.type), "Item")
	if it.has("health") and String(it.type) == "food":
		kind = "Medicine"
	var sub := "%s  ·  %d carried" % [kind, int(Game.inventory[id])]
	if Game.equipped.values().has(id):
		sub += "  ·  equipped"
	_inv_detail.add_child(UITheme.label(sub, 19, Color(0.82, 0.74, 0.6), "fell"))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.add_theme_font_size_override("normal_font_size", 21)
	rt.add_theme_font_size_override("italics_font_size", 20)
	rt.text = _inv_stats(id, it) + "[i][color=#d8cbb0]%s[/color][/i]" % String(it.desc)
	if int(it.get("value", 0)) > 0:
		rt.text += "\n\n[color=#e0c070]Worth about %s[/color]" % Items.price_text(int(it.value))
	_inv_detail.add_child(rt)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inv_detail.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_inv_detail.add_child(row)
	var act := _inv_action_name(id, it)
	if act != "":
		var b := UITheme.button(act, _inv_use, 160)
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(170, 52)
		row.add_child(b)
	if String(it.type) != "quest":
		var d := UITheme.button("Drop", _inv_drop.bind(false), 100)
		d.custom_minimum_size = Vector2(110, 52)
		row.add_child(d)
		if int(Game.inventory[id]) > 1:
			var da := UITheme.button("Drop all", _inv_drop.bind(true), 120)
			da.custom_minimum_size = Vector2(120, 52)
			row.add_child(da)


func _inv_stats(id: String, it: Dictionary) -> String:
	var lines := []
	match String(it.type):
		"weapon":
			var cur := Game.weapon_damage()
			var dmg := float(it.damage)
			var cmp := "" if Game.equipped.weapon == id else " %s" % _delta(dmg - cur, "%+d")
			lines.append("Damage [b]%d[/b]%s" % [int(dmg), cmp])
			lines.append("Hold the attack button for a heavy blow (about twice the damage).")
		"shield":
			var cur := Game.shield_block()
			var cmp := "" if Game.equipped.shield == id else " %s" % _delta((float(it.block) - cur) * 100.0, "%+d%%")
			lines.append("Takes [b]%d%%[/b] off a blocked blow%s" % [int(float(it.block) * 100.0), cmp])
		"cloak":
			var cur := Game.insulation()
			var cmp := "" if Game.equipped.cloak == id else " %s" % _delta(float(it.insulation) - cur, "%+d")
			lines.append("Warmth [b]+%d[/b]%s" % [int(it.insulation), cmp])
			if it.has("heat"):
				lines.append("The desert dries you out far more slowly.")
			if it.has("charm"):
				lines.append("Nobles look on you more kindly.")
		"armor":
			var cur := Game.armor_value()
			var cmp := "" if Game.equipped.armor == id else " %s" % _delta((float(it.armor) - cur) * 100.0, "%+d%%")
			lines.append("Turns aside [b]%d%%[/b] of every blow%s" % [int(float(it.armor) * 100.0), cmp])
		"food", "drink":
			var parts := []
			for k in ["hunger", "thirst", "health", "stamina", "warmth"]:
				if it.has(k):
					parts.append("%s [b]+%d[/b]" % [k.capitalize(), int(it[k])])
			if not parts.is_empty():
				lines.append("  ·  ".join(parts))
			if id == "waterskin":
				lines.append("[b]%d[/b] of 5 sips left" % Game.waterskin_charges)
			if it.has("cookable"):
				lines.append("[color=#f0a070]Raw - cook it at a fire first (stand by one and use it).[/color]")
		"quest":
			for q in QUESTS.active():
				if q.kind == "deliver":
					lines.append("For %s in %s." % [q.to, q.to_town])
	return "\n".join(lines) + ("\n\n" if not lines.is_empty() else "")


func _delta(v: float, fmt: String) -> String:
	if absf(v) < 0.5:
		return "[color=#a89a80](same as yours)[/color]"
	return "[color=%s](%s)[/color]" % ["#8fd27a" if v > 0.0 else "#e07a6a", fmt % int(round(v))]


func _inv_action_name(id: String, it: Dictionary) -> String:
	match String(it.type):
		"weapon", "shield", "cloak", "armor":
			return "Unequip" if Game.equipped.values().has(id) else "Equip"
		"food":
			return "Use" if it.has("health") else "Eat"
		"drink":
			return "Drink"
		"tool":
			match id:
				"torch": return "Put out" if Game.player_ref and Game.player_ref.torch_on else "Light"
				"bedroll": return "Sleep"
				"campfire_kit": return "Make camp"
	return ""


## Left column: what you wear and wield, how you're faring, and your standing.
func _inv_equipment() -> void:
	for c in _inv_left.get_children():
		c.queue_free()
	_inv_left.add_child(UITheme.label("Equipped", 24, UITheme.GOLD, "header"))
	for e in [["weapon", "Weapon"], ["shield", "Shield"], ["armor", "Armour"], ["cloak", "Cloak"]]:
		var id: String = Game.equipped[e[0]]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_inv_left.add_child(row)
		var b := _slot(id, 1, 76) if id != "" else Button.new()
		if id == "":
			b.custom_minimum_size = Vector2(76, 76)
			b.disabled = true
			for st in ["normal", "disabled"]:
				b.add_theme_stylebox_override(st, _slot_box("normal", false, false))
		else:
			for st in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(st, _slot_box(st, true, id == _inv_sel))
		row.add_child(b)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(col)
		col.add_child(UITheme.label(e[1], 16, Color(0.72, 0.64, 0.5), "fell"))
		col.add_child(UITheme.label(Items.display_name(id) if id != "" else "-", 21, UITheme.PARCHMENT))
		var stat := ""
		match e[0]:
			"weapon": stat = "Damage %d" % int(Game.weapon_damage())
			"shield": stat = "Blocks %d%%" % int(Game.shield_block() * 100.0) if id != "" else ""
			"armor": stat = "Protection %d%%" % int(Game.armor_value() * 100.0) if id != "" else ""
			"cloak": stat = "Warmth +%d" % int(Game.insulation()) if id != "" else ""
		if stat != "":
			col.add_child(UITheme.label(stat, 17, Color(0.85, 0.78, 0.62)))
	_inv_left.add_child(HSeparator.new())
	_inv_left.add_child(UITheme.label("Condition", 24, UITheme.GOLD, "header"))
	var s := Game.stats
	for r in [["Health", float(s.health), Game.max_health, Color(0.72, 0.14, 0.1)], ["Stamina", float(s.stamina), 100.0, Color(0.36, 0.62, 0.25)],
			["Hunger", float(s.hunger), 100.0, Color(0.82, 0.55, 0.2)], ["Thirst", float(s.thirst), 100.0, Color(0.25, 0.5, 0.82)], ["Warmth", float(s.warmth), 100.0, Color(0.95, 0.65, 0.3)]]:
		var h := HBoxContainer.new()
		_inv_left.add_child(h)
		var l := UITheme.label(r[0], 18, UITheme.PARCHMENT, "fell")
		l.custom_minimum_size = Vector2(92, 0)
		h.add_child(l)
		var pb := ProgressBar.new()
		pb.max_value = r[2]
		pb.value = r[1]
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(200, 16)
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = r[3]
		pb.add_theme_stylebox_override("fill", fill)
		h.add_child(pb)
		h.add_child(UITheme.label(" %d" % int(r[1]), 17, Color(0.85, 0.78, 0.62)))
	_inv_left.add_child(HSeparator.new())
	var info := UITheme.label("Reputation: %s (%d)\nWaterskin: %d / 5 sips\nPlaces found %d  ·  Bandits slain %d  ·  Beasts slain %d" % [Game.reputation_title(), int(Game.reputation), Game.waterskin_charges,
		Game.discovered.size(), int(Game.kills.get("bandit", 0)), int(Game.kills.get("beast", 0))], 17, Color(0.85, 0.78, 0.64))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inv_left.add_child(info)


func _inv_use() -> void:
	var id := _inv_sel
	if id == "" or not Game.inventory.has(id):
		return
	var it := Items.get_item(id)
	if _inv_action_name(id, it) == "":
		return
	var msg := Game.use_item(id)
	if msg != "":
		Game.notify.emit(msg, "info")
	Audio.play_at("equip" if String(it.type) in ["weapon", "shield", "armor"] else "item_pick", Game.player_ref.global_position if Game.player_ref else Vector3.ZERO, 0.0)
	if mode == "inventory":
		_refresh_inv()


## Drops one (or all) of the chosen item: it's tossed in front of you and lands in the world.
func _inv_drop(all := false) -> void:
	var id := _inv_sel
	if id == "" or not Game.inventory.has(id):
		return
	if String(Items.get_item(id).type) == "quest":
		Game.notify.emit("That isn't yours to throw away.", "warn")
		return
	var n := int(Game.inventory[id]) if all else 1
	Game.remove_item(id, n)
	var p: Player = Game.player_ref
	if p and Game.world_ref:
		var fwd := -p.cam.global_transform.basis.z
		fwd.y = maxf(fwd.y, -0.2)
		var at := p.cam.global_position + fwd.normalized() * 0.7 - Vector3.UP * 0.35
		PICKUP.drop(Game.world_ref, id, n, at, fwd.normalized() * 2.2 + Vector3.UP * 1.0 + p.velocity)
		Audio.play_at("whoosh", p.global_position, -6.0)
	_refresh_inv()


# ------------------------------------------------------------------ map
func open_map() -> void:
	var v := _open("map", Vector2(1180, 880))
	_title(v, "Map of Aldmere", "Wheel to zoom, drag to pan  ·  click to set a waypoint, right-click to clear it")
	var clip := Control.new()
	clip.custom_minimum_size = Vector2(1140, 760)
	clip.clip_contents = true
	v.add_child(clip)
	_map_tex = TextureRect.new()
	_map_tex.texture = ImageTexture.create_from_image(Image.load_from_file(WorldData.DIR + "map.png"))
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clip.add_child(_map_tex)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_map_overlay.bind(overlay))
	_map_tex.add_child(overlay)
	_map_zoom = 1.0
	_map_off = Vector2.ZERO
	_layout_map()


func _layout_map() -> void:
	if _map_tex == null:
		return
	var s := 760.0 * _map_zoom
	_map_tex.size = Vector2(s, s)
	var base := Vector2((1140.0 - 760.0) * 0.5, 0.0) - Vector2(s - 760.0, s - 760.0) * 0.5
	_map_tex.position = base + _map_off
	if _map_tex.get_child_count() > 0:
		(_map_tex.get_child(0) as Control).queue_redraw()


func _draw_map_overlay(c: Control) -> void:
	var s := _map_tex.size.x
	var f := UITheme.font("header")
	var to_map := func(x: float, z: float) -> Vector2: return Vector2((x + WorldData.HALF) / WorldData.SIZE * s, (z + WorldData.HALF) / WorldData.SIZE * s)
	for r in WorldData.info.get("regions", []):
		var p: Vector2 = to_map.call(float(r.x), float(r.z))
		c.draw_string(UITheme.font("fell"), p - Vector2(60, 0), r.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 15 + int(_map_zoom * 2), Color(0.25, 0.18, 0.1, 0.75))
	for st in WorldData.settlements:
		var p: Vector2 = to_map.call(float(st.x), float(st.z))
		var known: bool = Game.discovered.has(st.name) or st.type in ["town", "castle"]
		var col := {"town": Color(0.75, 0.1, 0.08), "village": Color(0.85, 0.5, 0.1), "castle": Color(0.45, 0.15, 0.6)}.get(st.type, Color(0.3, 0.3, 0.3))
		if st.type in ["town", "castle"]:
			c.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), col)
		else:
			c.draw_circle(p, 4.5, col)
		if known:
			var label: String = st.name + (" (market)" if Game.is_market_day(st.name) else "")
			c.draw_string(f, p + Vector2(8, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13 + int(_map_zoom), Color(0.12, 0.08, 0.04))
	for q in WorldData.pois:
		if Game.discovered.has(q.name):
			var p: Vector2 = to_map.call(float(q.x), float(q.z))
			c.draw_circle(p, 3.5, Color(0.15, 0.4, 0.15))
			c.draw_string(f, p + Vector2(6, 4), q.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11 + int(_map_zoom), Color(0.1, 0.25, 0.1))
	var wd = Game.world_ref.wilds if Game.world_ref else null
	if wd:
		for ws in wd.sites:
			if ws.found:
				var wsp: Vector2 = to_map.call(float(ws.x), float(ws.z))
				c.draw_circle(wsp, 3.0, Color(0.25, 0.35, 0.15))
				if _map_zoom > 1.6:
					c.draw_string(f, wsp + Vector2(6, 4), String(ws.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 10 + int(_map_zoom), Color(0.2, 0.28, 0.12))
	if Game.waypoint != Vector2.INF:
		var wpp: Vector2 = to_map.call(Game.waypoint.x, Game.waypoint.y)
		var wr := 8.0
		c.draw_colored_polygon(PackedVector2Array([wpp + Vector2(0, -wr), wpp + Vector2(wr, 0), wpp + Vector2(0, wr), wpp + Vector2(-wr, 0)]), Color(0.2, 0.7, 0.9))
		c.draw_polyline(PackedVector2Array([wpp + Vector2(0, -wr), wpp + Vector2(wr, 0), wpp + Vector2(0, wr), wpp + Vector2(-wr, 0), wpp + Vector2(0, -wr)]), Color(0.02, 0.15, 0.25), 1.5)
		c.draw_string(f, wpp + Vector2(11, -6), "Waypoint", HORIZONTAL_ALIGNMENT_LEFT, -1, 12 + int(_map_zoom), Color(0.05, 0.25, 0.4))
	for q in QUESTS.active():
		var m: Vector2 = QUESTS.marker(q)
		var qp: Vector2 = to_map.call(m.x, m.y)
		var r := 7.0
		c.draw_colored_polygon(PackedVector2Array([qp + Vector2(0, -r), qp + Vector2(r, 0), qp + Vector2(0, r), qp + Vector2(-r, 0)]), Color(0.95, 0.72, 0.15))
		c.draw_polyline(PackedVector2Array([qp + Vector2(0, -r), qp + Vector2(r, 0), qp + Vector2(0, r), qp + Vector2(-r, 0), qp + Vector2(0, -r)]), Color(0.25, 0.12, 0.02), 1.5)
		c.draw_string(f, qp + Vector2(10, -6), String(q.title), HORIZONTAL_ALIGNMENT_LEFT, -1, 12 + int(_map_zoom), Color(0.35, 0.18, 0.0))
	var pl: Player = Game.player_ref
	var pp: Vector2 = to_map.call(pl.global_position.x, pl.global_position.z)
	var fwd := Vector2(-sin(pl._yaw), -cos(pl._yaw))
	var side := Vector2(fwd.y, -fwd.x)
	c.draw_colored_polygon(PackedVector2Array([pp + fwd * 11.0, pp - fwd * 6.0 + side * 6.0, pp - fwd * 6.0 - side * 6.0]), Color(0.9, 0.1, 0.05))
	c.draw_arc(pp, 14.0, 0, TAU, 24, Color(0.9, 0.1, 0.05, 0.6), 1.5)


# ------------------------------------------------------------------ journal
func open_journal() -> void:
	var v := _open("journal", Vector2(1000, 720))
	Audio.ui("book_open")
	_title(v, "Journal", "Work taken from the people of Aldmere")
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(960, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(930, 0)
	rt.add_theme_font_size_override("normal_font_size", 19)
	rt.add_theme_font_size_override("bold_font_size", 21)
	sc.add_child(rt)
	var txt := ""
	var act := QUESTS.active()
	for q in act:
		var giver := "%s, %s of %s" % [q.giver, String(q.role).replace("_", " "), q.town]
		txt += "[b][color=#e8c56a]%s[/color][/b]\n[i]%s[/i]\n%s\nReward: %s\n\n" % [q.title, giver, QUESTS.objective(q), Items.price_text(int(q.silver))]
	if act.is_empty():
		txt += "[i]No work in hand. Knights pay for culling beasts and clearing bandit camps, merchants need parcels carried between towns, and innkeepers, cooks, shopkeepers and smiths are always short of something.[/i]\n\n"
	var done := Game.quests.filter(func(q): return q.state == "done")
	if not done.is_empty():
		txt += "[b]Completed[/b]\n"
		for i in range(done.size() - 1, maxi(done.size() - 9, -1), -1):
			txt += "[color=#9a8f7a]%s  -  %s of %s[/color]\n" % [done[i].title, done[i].giver, done[i].town]
	rt.text = txt
	var b := UITheme.button("Close", func(): close(), 240)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)


# ------------------------------------------------------------------ dialogue
func open_dialogue(n: NPC) -> void:
	var v := _open("dialogue", Vector2(960, 600))
	npc = n
	var d = n.data
	var sub := NPCManager.role_title(d) + " of " + String(d.sname)
	if d.rank > 0:
		sub += "  ·  Rank %d of 7" % d.rank
	if d.personality not in ["cook", "stern", "meek"]:
		sub += "  ·  " + String(d.personality).capitalize()
	_title(v, d.name, sub)
	_dlg_text = RichTextLabel.new()
	_dlg_text.bbcode_enabled = true
	_dlg_text.add_theme_font_size_override("normal_font_size", 25)
	_dlg_text.add_theme_font_size_override("italics_font_size", 25)
	_dlg_text.custom_minimum_size = Vector2(860, 150)
	_dlg_text.fit_content = true
	v.add_child(_dlg_text)
	_dlg_opts = VBoxContainer.new()
	v.add_child(_dlg_opts)
	_say(Dialogue.greeting(d))
	_options()


func _say(t: String) -> void:
	_dlg_text.text = "[i]\"%s\"[/i]" % t
	Audio.voice(npc.data.gender if npc else "m", Game.player_ref.global_position)


func _options() -> void:
	for c in _dlg_opts.get_children():
		c.queue_free()
	for t in Dialogue.topics(npc.data):
		var b := UITheme.button(t[1], _choose.bind(t[0]), 820)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 21)
		b.custom_minimum_size = Vector2(820, 50)
		_dlg_opts.add_child(b)


func _choose(topic: String) -> void:
	var r := Dialogue.respond(npc, topic)
	if r.has("refund"):
		Game.earn(int(r.refund))
	if r.get("hostile", false):
		var n := npc
		var nm: String = npc.data.name
		close()
		n.target = Game.player_ref
		Game.world_ref.hud.call("show_subtitle", nm, String(r.get("text", "")), 2.5)
		return
	if r.get("close", false):
		var line: String = r.text
		var nm: String = npc.data.name
		close()
		Game.world_ref.hud.call("show_subtitle", nm, line, 3.0)
		return
	match String(r.get("open", "")):
		"trade":
			open_trade(npc)
			return
		"horses":
			open_horses(npc)
			return
	_say(r.text)
	_options()


# ------------------------------------------------------------------ trade
func open_trade(n: NPC) -> void:
	var v := _open("trade", Vector2(1160, 700))
	npc = n
	npc.begin_talk()
	var d = n.data
	_title(v, "Trading with " + String(d.name), "Your purse: " + Game.purse_text())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	for side in ["buy", "sell"]:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(540, 520)
		h.add_child(col)
		col.add_child(UITheme.label("Their wares" if side == "buy" else "Your goods", 22, UITheme.GOLD, "header"))
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(540, 480)
		col.add_child(sc)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(list)
		var source: Dictionary = d.stock if side == "buy" else Game.inventory
		for id in source.keys():
			var it := Items.get_item(id)
			if String(it.get("type", "")) == "quest":
				continue          # parcels and the like are not for sale
			var price := maxi(1, int(round(float(it.value) * Dialogue.price_mult(d, side == "buy"))))
			var b := UITheme.button("%s  x%d   -   %s%s" % [it.name, int(source[id]), Items.price_text(price), "  ★" if it.get("rare", false) else ""], _trade.bind(String(id), side, price), 520)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.icon = ITEMS3D.icon(String(id))
			b.add_theme_constant_override("icon_max_width", 48)
			b.custom_minimum_size = Vector2(520, 58)
			b.tooltip_text = String(it.desc)
			if side == "sell" and Game.equipped.values().has(id) and int(source[id]) <= 1:
				b.disabled = true
			list.add_child(b)
	v.add_child(UITheme.button("Done", func(): close(), 200))


func _trade(id: String, side: String, price: int) -> void:
	var d = npc.data
	if side == "buy":
		if int(d.stock.get(id, 0)) <= 0:
			return
		if not Game.pay(price):
			Game.notify.emit("You can't afford that.", "warn")
			return
		d.stock[id] = int(d.stock[id]) - 1
		if int(d.stock[id]) <= 0:
			d.stock.erase(id)
		Game.add_item(id)
		if id == "falcon_charm":
			Game.change_reputation(5.0, "The falconer's charm")
	else:
		if not Game.remove_item(id):
			return
		Game.earn(price)
		d.stock[id] = int(d.stock.get(id, 0)) + 1
	Audio.ui("coin")
	open_trade(npc)


# ------------------------------------------------------------------ horses
func open_horses(n: NPC) -> void:
	var v := _open("horses", Vector2(760, 520))
	npc = n
	npc.begin_talk()
	_title(v, "Horses of " + String(n.data.sname), "Your purse: " + Game.purse_text())
	var horses: Array = Game.world_ref.npcs.call("horses_at", n.data.sname)
	if horses.is_empty():
		v.add_child(UITheme.label("All my horses are sold, I'm afraid. Come back another time.", 20))
	for h in horses:
		var spd: float = h.speed
		var label := "%s %s - top speed %d - %d gold" % ["Swift" if spd > 17 else ("Quick" if spd > 14 else ("Steady" if spd > 12.5 else "Plodding")), "white mare" if h.white else "bay stallion", int(spd * 3.6), h.price]
		v.add_child(UITheme.button(label, func():
			if Game.world_ref.npcs.call("buy_horse", h):
				close()
			else:
				Game.notify.emit("You need %d gold for that horse." % h.price, "warn"), 700))
	v.add_child(UITheme.button("Not today", func(): close(), 200))


# ------------------------------------------------------------------ settings
func open_settings() -> void:
	var v := _open("settings", Vector2(1180, 840))
	_title(v, "Settings")
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1140, 640)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 8)
	sc.add_child(g)
	var s := Game.settings
	g.add_child(UITheme.label("Quality preset", 20))
	var presets := HBoxContainer.new()
	for p in ["low", "medium", "high", "ultra", "cinematic"]:
		var b := UITheme.button(p.capitalize(), func(): Game.apply_preset(p); open_settings(), 100)
		if s.preset == p:
			b.add_theme_color_override("font_color", UITheme.GOLD)
		presets.add_child(b)
	g.add_child(presets)
	_slider(g, "Render scale (upscaled below 100%, supersampled above - 200% = 8K on a 4K display)", "render_scale", 0.5, 2.0, 0.05)
	_slider(g, "View distance", "view_distance", 0.5, 1.8, 0.1)
	_slider(g, "Grass density", "grass_density", 0.2, 2.0, 0.1)
	_option(g, "Shadow quality", "shadows", ["Low", "Medium", "High", "Ultra"])
	for t in [["sdfgi", "SDFGI global illumination (signed-distance-field ray-marched GI)"], ["ssr", "Screen-space reflections"], ["ssao", "Ambient occlusion (SSAO)"],
			["ssil", "Indirect lighting (SSIL)"], ["volumetric_fog", "Volumetric fog & light shafts"], ["glow", "Bloom / glow"], ["fsr", "Smart upscaling (MetalFX on Mac, FSR 2 elsewhere)"],
			["vsync", "V-Sync"], ["fullscreen", "Fullscreen"], ["show_fps", "Show FPS"], ["head_bob", "Head bob"], ["invert_y", "Invert mouse Y"]]:
		_toggle(g, t[1], t[0])
	_slider(g, "Interface size (text, menus and HUD)", "ui_scale", 0.8, 1.2, 0.05)
	_slider(g, "Field of view", "fov", 55.0, 105.0, 1.0)
	_slider(g, "Mouse sensitivity", "mouse_sensitivity", 0.0006, 0.006, 0.0002)
	_slider(g, "Day length (real minutes)", "day_length_min", 10.0, 120.0, 5.0)
	_slider(g, "Master volume", "master_volume", 0.0, 1.0, 0.05)
	_slider(g, "Music volume", "music_volume", 0.0, 1.0, 0.05)
	_slider(g, "Effects volume", "sfx_volume", 0.0, 1.0, 0.05)
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(UITheme.button("Back", func(): open_pause() if Game.world_ref else close(), 200))
	row.add_child(UITheme.button("Close", func(): close(), 200))


func _slider(g: GridContainer, label: String, key: String, mn: float, mx: float, step: float) -> void:
	var l := UITheme.label(label, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
	g.add_child(l)
	var h := HBoxContainer.new()
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.value = float(Game.settings[key])
	sl.custom_minimum_size = Vector2(320, 28)
	var val := UITheme.label(str(snapped(sl.value, step)), 18)
	sl.value_changed.connect(func(x):
		Game.settings[key] = x
		val.text = str(snapped(x, step))
		Game.settings.preset = "custom"
		Game.save_settings())
	h.add_child(sl)
	h.add_child(val)
	g.add_child(h)


func _toggle(g: GridContainer, label: String, key: String) -> void:
	var l := UITheme.label(label, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
	g.add_child(l)
	var cb := CheckBox.new()
	cb.button_pressed = bool(Game.settings[key])
	cb.toggled.connect(func(on): Game.settings[key] = on; Game.settings.preset = "custom"; Game.save_settings())
	g.add_child(cb)


func _option(g: GridContainer, label: String, key: String, opts: Array) -> void:
	g.add_child(UITheme.label(label, 18))
	var ob := OptionButton.new()
	for o in opts:
		ob.add_item(o)
	ob.selected = int(Game.settings[key])
	ob.item_selected.connect(func(i): Game.settings[key] = i; Game.settings.preset = "custom"; Game.save_settings())
	g.add_child(ob)
