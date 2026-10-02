class_name UITheme
## Builds the medieval UI theme (parchment, iron and gold) shared by every screen.

const GOLD := Color(0.86, 0.72, 0.42)
const PARCHMENT := Color(0.93, 0.87, 0.74)
const INK := Color(0.16, 0.11, 0.07)
const DARK := Color(0.07, 0.055, 0.04, 0.9)
const RED := Color(0.75, 0.18, 0.14)

static var _theme: Theme
static var _fonts := {}


static func font(name: String) -> Font:
	if not _fonts.has(name):
		var paths := {"body": "res://assets/fonts/EBGaramond.ttf", "header": "res://assets/fonts/Cinzel.ttf",
			"title": "res://assets/fonts/UnifrakturCook-Bold.ttf", "fell": "res://assets/fonts/IMFellEnglishSC.ttf"}
		_fonts[name] = load(paths[name])
	return _fonts[name]


static func panel_box(alpha := 0.9, border := GOLD) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.058, 0.042, alpha)
	sb.border_color = Color(border.r, border.g, border.b, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 22
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("panel", "PanelContainer", panel_box())
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(2)
		sb.set_border_width_all(1)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		match state:
			"normal":
				sb.bg_color = Color(0.16, 0.11, 0.07, 0.92)
				sb.border_color = Color(0.55, 0.42, 0.22, 0.8)
			"hover":
				sb.bg_color = Color(0.32, 0.22, 0.11, 0.95)
				sb.border_color = GOLD
			"pressed":
				sb.bg_color = Color(0.45, 0.31, 0.13, 1.0)
				sb.border_color = GOLD
			"disabled":
				sb.bg_color = Color(0.1, 0.08, 0.06, 0.6)
				sb.border_color = Color(0.3, 0.25, 0.2, 0.5)
			"focus":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = GOLD
				sb.draw_center = false
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", Color(1.0, 0.92, 0.7))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.45, 0.38))
	t.set_font("font", "Button", font("header"))
	t.set_font_size("font_size", "Button", 20)
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.75))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_color("default_color", "RichTextLabel", PARCHMENT)
	t.set_font("normal_font", "RichTextLabel", font("body"))
	t.set_font("bold_font", "RichTextLabel", font("header"))
	t.set_font_size("normal_font_size", "RichTextLabel", 22)
	t.set_font_size("bold_font_size", "RichTextLabel", 20)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.05, 0.04, 0.03, 0.85)
	bar_bg.border_color = Color(0.5, 0.4, 0.22, 0.7)
	bar_bg.set_border_width_all(1)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = GOLD
	t.set_stylebox("fill", "ProgressBar", bar_fg)
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(0.25, 0.18, 0.1)
	sl.content_margin_top = 3
	sl.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", sl)
	var item_sel := StyleBoxFlat.new()
	item_sel.bg_color = Color(0.4, 0.28, 0.12, 0.8)
	t.set_stylebox("selected", "ItemList", item_sel)
	t.set_stylebox("selected_focus", "ItemList", item_sel)
	t.set_stylebox("panel", "ItemList", panel_box(0.6))
	t.set_color("font_color", "ItemList", PARCHMENT)
	t.set_font_size("font_size", "ItemList", 20)
	t.set_stylebox("panel", "TabContainer", panel_box(0.0))
	t.set_font("font", "TabContainer", font("header"))
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", PARCHMENT)
	t.set_color("font_color", "CheckBox", PARCHMENT)
	t.set_color("font_color", "OptionButton", PARCHMENT)
	_theme = t
	return t


## Anchors `c` to `preset` and places it by explicit offsets from that anchor point: `at` is the
## top-left corner relative to the anchor, `size` the rectangle. (Setting `position` after an
## anchor preset is measured from the parent's top-left once the parent has a size, which threw
## the menus off-screen on large displays.)
static func place(c: Control, preset: int, at: Vector2, size: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = at.x
	c.offset_top = at.y
	c.offset_right = at.x + size.x
	c.offset_bottom = at.y + size.y


static func label(text: String, size := 21, color := PARCHMENT, f := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(f))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_w := 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 48)
	b.pressed.connect(cb)
	b.pressed.connect(func(): Audio.ui("click"))
	b.mouse_entered.connect(func(): Audio.ui("hover"))
	return b
