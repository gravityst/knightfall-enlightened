extends CanvasLayer
## On-screen controls for phones and tablets (Game.mobile): a movement stick that appears under
## the left thumb, a drag anywhere else to look around, and buttons for the rest. Every control
## acts through the same input actions as the keyboard and mouse, so the game itself is unchanged;
## several fingers work at once (run with one thumb while striking with the other).

const STICK_R := 92.0              # how far the knob travels, in interface pixels
const SPRINT_AT := 0.94            # the stick pushed this far runs (gallops on horseback)
const FILL := Color(0.05, 0.035, 0.02, 0.42)
const RING := Color(0.93, 0.77, 0.42, 0.7)

var _size := Vector2.ZERO
var _stick_id := -1                # the finger on the stick
var _stick_base := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look := {}                    # finger index -> last position
var _buttons: Array = []           # {node, centre, r, label}
var _pad: Control                  # draws the stick
var _crouch := false
var _use_btn: Dictionary = {}
var _tex_cache := {}


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS     # (to hide itself while a menu pauses the game)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		Input.emulate_touch_from_mouse = true     # trying --mobile on the desktop: the mouse is a finger
	_pad = Control.new()
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	for b in _buttons:
		b.node.queue_free()
	_buttons.clear()
	_size = get_viewport().get_visible_rect().size
	var w := _size.x
	var h := _size.y
	# the right thumb: strike, block, jump, use, dodge
	_button("Strike", "attack", Vector2(w - 128, h - 132), 80.0)
	_button("Block", "block", Vector2(w - 300, h - 96), 58.0)
	_button("Jump", "jump", Vector2(w - 112, h - 322), 56.0)
	_use_btn = _button("Use", "interact", Vector2(w - 268, h - 262), 58.0)
	_button("Dodge", "dodge", Vector2(w - 440, h - 74), 46.0)
	_button("Sword", "draw_weapon", Vector2(w - 424, h - 196), 42.0)
	_button("Torch", "torch", Vector2(w - 392, h - 312), 42.0)
	_button("Crouch", "", Vector2(w - 250, h - 410), 40.0).node.pressed.connect(_toggle_crouch)
	# the menus, along the top right
	var x := w - 62.0
	for pair in [["Menu", "pause"], ["Bag", "inventory"], ["Map", "map"], ["Tasks", "journal"]]:
		_button(pair[0], pair[1], Vector2(x, 58), 40.0)
		x -= 100.0
	# eat, drink, treat wounds, call the horse: down the left edge, clear of the stick
	var y := h * 0.4
	for pair in [["Eat", "hot_1"], ["Drink", "hot_2"], ["Heal", "hot_3"], ["Horse", "call_horse"]]:
		_button(pair[0], pair[1], Vector2(54, y), 38.0)
		y += 84.0
	_pad.queue_redraw()


func _button(text: String, action: String, at: Vector2, r: float) -> Dictionary:
	var b := TouchScreenButton.new()
	b.texture_normal = _disc(false)
	b.texture_pressed = _disc(true)
	var shape := CircleShape2D.new()
	shape.radius = 128.0
	b.shape = shape
	b.shape_centered = true
	b.passby_press = action in ["jump", "dodge"]
	b.action = action
	b.scale = Vector2.ONE * (r / 128.0)
	b.position = at - Vector2(r, r)
	add_child(b)
	var l := UITheme.label(text, int(clampf(r * 0.42, 17.0, 30.0) / (r / 128.0)), Color(1.0, 0.94, 0.8), "header")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.size = Vector2(256, 256)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	var d := {"node": b, "centre": at, "r": r, "label": l}
	_buttons.append(d)
	return d


## A soft-edged disc with a gold rim, drawn once for all the buttons.
func _disc(pressed: bool) -> ImageTexture:
	if _tex_cache.has(pressed):
		return _tex_cache[pressed]
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var fill := Color(0.93, 0.77, 0.42, 0.45) if pressed else FILL
	for j in n:
		for i in n:
			var d := Vector2(i + 0.5 - n * 0.5, j + 0.5 - n * 0.5).length()
			var edge := clampf(126.0 - d, 0.0, 1.0)
			var rim := clampf(1.0 - absf(d - 120.0) / 4.5, 0.0, 1.0)
			var c := fill.lerp(RING, rim)
			c.a = maxf(fill.a, RING.a * rim) * edge
			img.set_pixel(i, j, c)
	var t := ImageTexture.create_from_image(img)
	_tex_cache[pressed] = t
	return t


func _active() -> bool:
	var p: Player = Game.player_ref
	return p != null and Game.world_ref != null and Game.world_ref.ready_to_play and not Game.in_menu and not p.dead


func _process(_delta: float) -> void:
	var on := _active()
	if visible != on:
		visible = on
		if not on:
			_release_all()
	if not on:
		return
	# the Use button lights up when there is something to use
	var p: Player = Game.player_ref
	var can_use: bool = p.get("_focus") != null
	_use_btn.label.modulate = Color(1, 1, 1, 1.0 if can_use else 0.45)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			if _on_button(pos):
				return
			if _stick_id < 0 and pos.x < _size.x * 0.45 and pos.y > _size.y * 0.42:
				_stick_id = event.index
				_stick_base = pos
				_stick_vec = Vector2.ZERO
				_pad.queue_redraw()
			else:
				_look[event.index] = pos
		else:
			if event.index == _stick_id:
				_stick_id = -1
				_stick_vec = Vector2.ZERO
				_apply_stick()
			_look.erase(event.index)
	elif event is InputEventScreenDrag:
		var pos: Vector2 = event.position
		if event.index == _stick_id:
			var d := pos - _stick_base
			if d.length() > STICK_R * 1.35:          # the base follows a thumb that strays far
				_stick_base = pos - d.normalized() * STICK_R * 1.35
				d = pos - _stick_base
			_stick_vec = (d / STICK_R).limit_length(1.0)
			_apply_stick()
		elif _look.has(event.index):
			var rel: Vector2 = pos - _look[event.index]
			_look[event.index] = pos
			(Game.player_ref as Player).add_look(rel)


func _on_button(pos: Vector2) -> bool:
	for b in _buttons:
		if pos.distance_to(b.centre) <= float(b.r) * 1.08:
			return true
	return false


func _apply_stick() -> void:
	var v := _stick_vec
	for pair in [["move_right", v.x], ["move_left", -v.x], ["move_back", v.y], ["move_forward", -v.y]]:
		if pair[1] > 0.06:
			Input.action_press(pair[0], clampf(pair[1], 0.0, 1.0))
		else:
			Input.action_release(pair[0])
	if v.length() >= SPRINT_AT and v.y < -0.4:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	_pad.queue_redraw()


func _toggle_crouch() -> void:
	_crouch = not _crouch
	if _crouch:
		Input.action_press("crouch")
	else:
		Input.action_release("crouch")


func _release_all() -> void:
	_stick_id = -1
	_stick_vec = Vector2.ZERO
	_look.clear()
	for a in ["move_right", "move_left", "move_back", "move_forward", "sprint"]:
		Input.action_release(a)
	_pad.queue_redraw()


func _draw_pad() -> void:
	var base := _stick_base if _stick_id >= 0 else Vector2(250, _size.y - 175)
	var a := 1.0 if _stick_id >= 0 else 0.45
	_pad.draw_circle(base, STICK_R + 26.0, Color(0, 0, 0, 0.22 * a))
	_pad.draw_arc(base, STICK_R + 26.0, 0.0, TAU, 64, Color(RING.r, RING.g, RING.b, 0.55 * a), 3.0, true)
	var knob := base + _stick_vec * STICK_R
	_pad.draw_circle(knob, 46.0, Color(0.93, 0.77, 0.42, 0.42 * a))
	_pad.draw_arc(knob, 46.0, 0.0, TAU, 48, Color(1, 0.92, 0.7, 0.8 * a), 2.5, true)
	if _stick_vec.length() >= SPRINT_AT and _stick_vec.y < -0.4:
		_pad.draw_arc(base, STICK_R + 34.0, -PI * 0.75, -PI * 0.25, 24, Color(1, 0.85, 0.5, 0.9), 5.0, true)
