extends CanvasLayer
## Loading screen with the Knightfall title art, a progress bar and travel tips.

const TIPS := [
	"Knights guard every village (two) and town (seven). Earn their respect - or their blades.",
	"Cooks will only ever tell you one thing.",
	"Servants ignore strangers - unless you hold out a gold coin (G).",
	"Buy a horse at any stable for 30 to 60 gold. Faster horses cost more.",
	"Towns hold market days twice a week, when rare wares appear in the square.",
	"The Frostlands will freeze the unprepared. Wear furs and keep near a fire.",
	"The Qadir Desert parches the throat. Carry a waterskin and wear robes.",
	"Castle guards lower the portcullis on those with an evil reputation.",
	"Wolves hunt in packs after dark. Bears do not like to be surprised.",
	"Drink from any river or lake - but never from the sea.",
	"Sleep in a bed to pass the night and recover your strength.",
	"Ruined castles are abandoned... mostly. Their chests may still hold treasure.",
]

var _bar: ProgressBar
var _text: Label
var _tip: Label
var _root: Control
var _tip_t := 0.0


func _init() -> void:
	layer = 100
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.01)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/knightfall-bg.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.modulate = Color(0.55, 0.5, 0.48)
	_root.add_child(art)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = "shader_type canvas_item; void fragment(){ vec2 d = UV - 0.5; COLOR = vec4(0.0, 0.0, 0.0, clamp(dot(d,d) * 2.2 + 0.15, 0.0, 0.92)); }"
	shade.material = sm
	_root.add_child(shade)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(900, 0)
	UITheme.place(box, Control.PRESET_CENTER, Vector2(-450, -220), Vector2(900, 440))
	_root.add_child(box)
	var t := UITheme.label("Knightfall", 120, Color(0.95, 0.84, 0.58), "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("shadow_offset_y", 6)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	box.add_child(t)
	var sub := UITheme.label("E N L I G H T E N E D", 34, UITheme.GOLD, "header")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 60)
	box.add_child(spacer)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(620, 10)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_bar)
	_text = UITheme.label("Preparing the realm...", 22, UITheme.PARCHMENT, "fell")
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_text)
	_tip = UITheme.label(TIPS[randi() % TIPS.size()], 20, Color(0.75, 0.68, 0.55))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(900, 60)
	box.add_child(_tip)


func _process(delta: float) -> void:
	_tip_t += delta
	if _tip_t > 6.0:
		_tip_t = 0.0
		_tip.text = TIPS[randi() % TIPS.size()]


func set_progress(v: float, text: String) -> void:
	var tw := create_tween()
	tw.tween_property(_bar, "value", v, 0.25)
	_text.text = text + "..."


func finish() -> void:
	set_progress(1.0, "Ready")
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 1.2).set_delay(0.2)
	tw.tween_callback(queue_free)
