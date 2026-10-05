extends Control
## Title screen: a knight resting by his campfire in a moonlit forest clearing, his horse grazing
## behind (the game's own models, lit and fogged like the world, under a slowly drifting camera),
## with the title and menu over it.

const CREDITS := """[center][b]KNIGHTFALL ENLIGHTENED[/b]

Built with the Godot Engine 4.7 (MIT licence)

[b]Art[/b]
Buildings, props, nature, characters, outfits, hairstyles, animations,
animals, palms & crown - [i]Quaternius[/i] (CC0)
Terrain materials, castle fort kit, iron gate, kite shield, estoc,
fire pit - [i]Poly Haven[/i] (CC0)
Black bear, elk, moose antlers, mallard, goose, crow, hen, hawk, gull -
[i]Poly by Google[/i] via poly.pizza (CC-BY 3.0)

[b]Sound[/b]
Footsteps, hooves, blades, armour, shields, doors, coins, glass, cloth, books and interface sounds - [i]Kenney[/i] (CC0)
Voices, animal calls, birdsong, weather and ambience - modelled in code for Knightfall

[b]Fonts[/b] (SIL Open Font Licence)
UnifrakturCook, Cinzel, EB Garamond, IM Fell English SC

[b]World, code, shaders, ambience & music[/b]
Procedurally generated for Knightfall - the island of Aldmere, its rivers,
roads, settlements and people are baked by tools/worldgen.[/center]"""

const TIPS := [
	"Hold the attack button to draw back for a heavy blow - it smashes a shield guard aside.",
	"Raise your shield just as a blow lands to parry it: the attacker reels, open to a riposte.",
	"Double-tap A, D or S (or press Alt) to side-step or back-step out of harm's way.",
	"Click the map to set a waypoint; the compass leads you to it.",
	"A \"?\" on the compass means something unfound lies close by.",
	"Signposts stand where the roads leave every village and town.",
	"Servants only answer to coin: press G to hold one out.",
	"Knights pay for culling wolves and clearing bandit camps - ask them for work.",
	"A galloping horse tires. Ease to a canter and it gets its wind back.",
	"Cook raw meat at a fire before you eat it. Stand by the flames and use it.",
	"The north freezes the unprepared: a fur cloak and a fire keep you alive.",
	"Press Z to wait an hour when no enemies are near.",
]
const SKY := """shader_type sky;
uniform vec3 moon_dir = vec3(-0.42, 0.36, -0.83);
float h(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
void sky() {
	vec3 d = EYEDIR;
	float up = d.y;
	vec3 top = vec3(0.004, 0.009, 0.03);
	vec3 hor = vec3(0.03, 0.045, 0.08);
	vec3 col = mix(hor, top, pow(clamp(up, 0.0, 1.0), 0.45));
	if (up < 0.0) { col = mix(hor, vec3(0.008, 0.01, 0.014), clamp(-up * 4.0, 0.0, 1.0)); }
	vec3 sd = d * 230.0;
	vec3 cell = floor(sd);
	float r = h(cell);
	float star = step(0.986, r) * smoothstep(0.14, 0.0, length(fract(sd) - 0.5)) * clamp(up * 3.0, 0.0, 1.0);
	col += vec3(0.85, 0.9, 1.0) * star * (0.5 + 0.9 * fract(r * 37.0)) * (0.75 + 0.25 * sin(TIME * (1.0 + r * 3.0) + r * 40.0));
	vec3 m = normalize(moon_dir);
	float md = dot(d, m);
	col += vec3(0.95, 0.96, 1.0) * smoothstep(0.99950, 0.99972, md) * 4.0;
	col += vec3(0.22, 0.3, 0.5) * pow(max(md, 0.0), 80.0) * 0.8 + vec3(0.05, 0.07, 0.12) * pow(max(md, 0.0), 6.0);
	COLOR = col;
}"""
const GROUND := """shader_type spatial;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float r = length(wp.xz);
	float n = texture(noise, wp.xz * 0.045).r;
	float n2 = texture(noise, wp.xz * 0.41).r;
	vec3 dirt = vec3(0.15, 0.11, 0.075) * (0.65 + 0.7 * n2);
	vec3 grass = vec3(0.075, 0.105, 0.045) * (0.6 + 0.8 * n) * (0.85 + 0.3 * n2);
	float g = smoothstep(2.0, 5.5, r + (n - 0.5) * 3.5);
	ALBEDO = mix(dirt, grass, g);
	ROUGHNESS = 0.95;
	NORMAL_MAP = normalize(vec3((n2 - 0.5) * 0.6, (texture(noise, wp.xz * 0.41 + 0.3).r - 0.5) * 0.6, 1.0)) * 0.5 + 0.5;
}"""

var _stage: Node3D
var _cam: Camera3D
var _t := 0.0
var _menus: Control
var _credits: PanelContainer
var _tip: Label
var _tip_i := 0
var _tip_t := 0.0
var _fade: ColorRect
var _first: Button
var _busy := false
var _last_btn: Button
var _gate: Array[Button] = []    # Continue / Begin wait for the island's data in the browser
var _status: Label


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Game.in_menu = false
	Game.world_ref = null
	Game.player_ref = null
	_build_stage()
	_build_ui()
	_menus = load("res://scripts/ui/menus.gd").new()
	add_child(_menus)
	var tw := create_tween()
	tw.tween_interval(0.1)
	tw.tween_property(_fade, "color:a", 0.0, 0.9)
	if Game.debug_flag("timing"):
		print("LOAD %5d ms  title screen" % Time.get_ticks_msec())
	if OS.has_feature("web"):
		_fetch_data()        # (no background warm-up: a single-threaded page would stall on it)
	else:
		# warm up the world while the title screen is up: models and map textures load on worker threads
		WorldData.prefetch()
		Assets.prefetch()
		get_tree().create_timer(0.4).timeout.connect(_title_sound)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autostart="):   # test hook: press Begin after N seconds on the title screen
			await get_tree().create_timer(float(a.substr(12))).timeout
			print("LOAD %5d ms  BEGIN pressed" % Time.get_ticks_msec())
			_go(_new_game_now)
			return
		if a.begins_with("--menushot="):
			await get_tree().create_timer(4.0).timeout
			var img := get_viewport().get_texture().get_image()
			img.resize(1600, int(1600.0 * img.get_height() / img.get_width()))
			img.save_jpg(a.substr(11), 0.88)
			get_tree().quit()


## Music and the crackle of the fire (the synthesised sounds are cached after the first run).
func _title_sound() -> void:
	Audio.start_ambience()
	for n in Audio._amb:
		(Audio._amb[n] as AudioStreamPlayer).volume_db = -80.0
	var sv := linear_to_db(maxf(float(Game.settings.sfx_volume), 0.001))
	if Audio._amb.has("amb_fire"):
		Audio._amb["amb_fire"].volume_db = -4.0 + sv
	if Audio._amb.has("amb_night"):
		Audio._amb["amb_night"].volume_db = -13.0 + sv


# ------------------------------------------------------------------ the scene
func _build_stage() -> void:
	_stage = Node3D.new()
	add_child(_stage)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skm := ShaderMaterial.new()
	skm.shader = Shader.new()
	skm.shader.code = SKY
	sky.sky_material = skm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.25
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 0.9
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.fog_enabled = true
	e.fog_light_color = Color(0.05, 0.07, 0.11)
	e.fog_density = 0.012
	e.fog_sky_affect = 0.25
	e.volumetric_fog_enabled = bool(Game.settings.get("volumetric_fog", true))
	e.volumetric_fog_density = 0.022
	e.volumetric_fog_albedo = Color(0.55, 0.6, 0.72)
	e.volumetric_fog_length = 48.0
	e.volumetric_fog_ambient_inject = 0.35
	we.environment = e
	_stage.add_child(we)
	# moonlight from behind the trees, the fire in front
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.58, 0.68, 1.0)
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	moon.light_volumetric_fog_energy = 1.6
	_stage.add_child(moon)
	moon.basis = Basis.looking_at(-Vector3(-0.42, 0.36, -0.83).normalized())
	# the clearing
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(220, 220)
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = Shader.new()
	gm.shader.code = GROUND
	var nt := NoiseTexture2D.new()
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	nt.noise = FastNoiseLite.new()
	nt.noise.frequency = 0.03
	gm.set_shader_parameter("noise", nt)
	ground.material_override = gm
	_stage.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	# a ring of pines and broadleaves, thicker behind the fire than behind the camera
	var trees := ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5", "CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "Pine_2", "Pine_4", "DeadTree_2"]
	for i in (36 if Assets.compat else 70):
		var a := rng.randf() * TAU
		var r := rng.randf_range(9.0, 48.0)
		var p := Vector3(sin(a) * r, 0, cos(a) * r)
		if p.z > 4.0 and absf(p.x) < r * 0.55 and r < 22.0:
			continue          # keep the camera's side open
		var nm: String = trees[rng.randi() % trees.size()]
		var t := Assets.instance_sized("res://assets/nature/%s.gltf" % nm, rng.randf_range(10.0, 17.0) if nm.begins_with("Pine") else rng.randf_range(8.0, 12.0))
		t.position = p
		t.rotation.y = rng.randf() * TAU
		_stage.add_child(t)
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(5.0, 16.0)
		var nm: String = ["Bush_Common", "Fern_1", "Plant_1_Big", "Fern_1", "Bush_Common_Flowers", "Rock_Medium_1", "Rock_Medium_2", "Mushroom_Common"][i % 8]
		var b := Assets.instance_sized("res://assets/nature/%s.gltf" % nm, rng.randf_range(0.5, 1.2) if not nm.begins_with("Rock") else rng.randf_range(0.6, 1.4))
		b.position = Vector3(sin(a) * r, 0, cos(a) * r)
		b.rotation.y = rng.randf() * TAU
		_stage.add_child(b)
	_scatter_grass(rng)
	# the camp
	var fire: Node3D = preload("res://scripts/world/campfire.gd").new()
	_stage.add_child(fire)
	var log_seat := Assets.instance_sized("res://assets/props/Anvil_Log.gltf", 0.42)
	log_seat.position = Vector3(-1.95, 0, 0.75)
	_stage.add_child(log_seat)
	var knight := CharacterModel.new()
	_stage.add_child(knight)
	knight.build({"gender": "m", "outfit": "Ranger", "hue": 0.04, "sat": 0.75, "val": 0.75, "steel": 0.7, "hood": true, "pauldron": true, "beard": true,
		"sword": true, "shield": false, "drawn": false})
	knight.position = Vector3(-1.62, 0, 0.62)
	knight.rotation.y = atan2(1.62, -0.62)
	if knight.anim and knight.anim.has_animation("Sitting_Idle"):
		knight.play("Sitting_Idle", 0.0)
	var shield := Assets.instance_sized("res://assets/items/kite_shield/kite_shield.gltf", 1.0)
	shield.position = Vector3(-2.65, 0.0, 0.05)
	shield.rotation = Vector3(-0.28, 0.9, 0.0)
	_stage.add_child(shield)
	var roll := preload("res://scripts/core/item_models.gd").build("bedroll", 1.3)
	roll.position = Vector3(-2.6, 0.15, -1.5)
	roll.rotation.y = 0.4
	_stage.add_child(roll)
	var wood := preload("res://scripts/core/item_models.gd").build("firewood", 0.55)
	wood.position = Vector3(-1.2, 0.13, -1.7)
	wood.rotation.y = 1.2
	_stage.add_child(wood)
	var pot := Assets.instance_sized("res://assets/props/Pot_1.gltf", 0.32)
	pot.position = Vector3(-0.85, 0, -0.75)
	_stage.add_child(pot)
	var bag := Assets.instance_sized("res://assets/props/Bag.gltf", 0.55)
	bag.position = Vector3(-2.4, 0, 1.6)
	bag.rotation.y = 0.7
	_stage.add_child(bag)
	# his horse, grazing at the edge of the light
	var horse := Assets.instance_sized("res://assets/animals/Horse.glb", 2.35, "xz")
	horse.position = Vector3(1.4, 0, -5.2)
	horse.rotation.y = 2.32
	_stage.add_child(horse)
	var aps := horse.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var hap := aps[0] as AnimationPlayer
		if hap.has_animation("Eating"):
			hap.get_animation("Eating").loop_mode = Animation.LOOP_LINEAR
			hap.play("Eating")
	_stage.add_child(FireFX._for_renderer(_fireflies()))     # (CPU particles on WebGL)
	_cam = Camera3D.new()
	_cam.fov = 48.0
	_cam.far = 400.0
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 12.0
	ca.dof_blur_far_transition = 14.0
	ca.dof_blur_amount = 0.05
	_cam.attributes = ca
	_stage.add_child(_cam)
	_cam.current = true
	_place_camera()


func _scatter_grass(rng: RandomNumberGenerator) -> void:
	for nm in ["Grass_Common_Tall", "Grass_Common_Short", "Grass_Wispy_Tall", "Clover_1", "Flower_3_Group"]:
		var src := Assets.scene("res://assets/nature/%s.gltf" % nm).instantiate()
		var mis := src.find_children("*", "MeshInstance3D", true, false)
		if mis.is_empty():
			src.free()
			continue
		var mesh: Mesh = (mis[0] as MeshInstance3D).mesh
		var bb := mesh.get_aabb()
		src.free()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var n := (400 if Assets.compat else 900) if nm.begins_with("Grass") else 160
		mm.instance_count = n
		var s0 := (0.5 if nm.begins_with("Grass") else 0.3) / maxf(bb.size.y, 0.01)
		for i in n:
			var a := rng.randf() * TAU
			var r := rng.randf_range(3.6, 30.0)
			var sc := s0 * rng.randf_range(0.7, 1.4)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(sin(a) * r, -bb.position.y * sc, cos(a) * r)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stage.add_child(mmi)


func _fireflies() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 70
	p.lifetime = 7.0
	p.preprocess = 7.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 1.4, 16)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	var g := Gradient.new()
	g.set_color(0, Color(0.8, 1.0, 0.4, 0.0))
	g.add_point(0.2, Color(0.85, 1.0, 0.45, 1.0))
	g.add_point(0.5, Color(0.6, 0.85, 0.3, 0.2))
	g.add_point(0.75, Color(0.85, 1.0, 0.45, 1.0))
	g.set_color(g.get_point_count() - 1, Color(0.8, 1.0, 0.4, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(2.5, 3.0, 1.2)
	var ft := GradientTexture2D.new()
	var fg := Gradient.new()
	fg.set_color(0, Color(1, 1, 1, 1))
	fg.set_color(1, Color(1, 1, 1, 0))
	ft.gradient = fg
	ft.fill = GradientTexture2D.FILL_RADIAL
	ft.fill_from = Vector2(0.5, 0.5)
	ft.fill_to = Vector2(0.5, 0.0)
	m.albedo_texture = ft
	q.material = m
	p.draw_pass_1 = q
	p.position = Vector3(0, 1.4, -2.0)
	p.visibility_aabb = AABB(Vector3(-20, -3, -20), Vector3(40, 8, 40))
	return p


func _place_camera() -> void:
	var a := 0.62 + sin(_t * 0.045) * 0.3
	var r := 5.3 + sin(_t * 0.07) * 0.4
	var pos := Vector3(sin(a) * r, 1.3 + sin(_t * 0.09) * 0.1, cos(a) * r)
	_cam.look_at_from_position(pos, Vector3(-0.8, 0.78, 0.1))


func _process(delta: float) -> void:
	_t += delta
	if _cam:
		_place_camera()
	_tip_t -= delta
	if _tip_t <= 0.0 and _tip:
		_tip_t = 7.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		var tw := create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.5)
		tw.tween_callback(func(): _tip.text = TIPS[_tip_i])
		tw.tween_property(_tip, "modulate:a", 1.0, 0.6)


# ------------------------------------------------------------------ the menu
func _build_ui() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = """shader_type canvas_item;
void fragment() {
	float side = 1.0 - smoothstep(0.02, 0.62, UV.x);
	float v = smoothstep(0.75, 1.0, UV.y) * 0.5 + smoothstep(0.25, 0.0, UV.y) * 0.25;
	COLOR = vec4(0.012, 0.01, 0.008, clamp(side * 0.86 + v, 0.0, 0.92));
}"""
	shade.material = sm
	add_child(shade)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	UITheme.place(col, Control.PRESET_CENTER_LEFT, Vector2(120, -380), Vector2(640, 780))
	add_child(col)
	var title := UITheme.label("Knightfall", 150, Color(0.95, 0.8, 0.5), "title")
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.06, 0.035, 0.015, 0.9))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 6)
	col.add_child(title)
	var sub := UITheme.label("ENLIGHTENED", 32, Color(0.92, 0.86, 0.72), "header")
	var fv := FontVariation.new()
	fv.base_font = UITheme.font("header")
	fv.spacing_glyph = 14
	sub.add_theme_font_override("font", fv)
	sub.add_theme_constant_override("outline_size", 6)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	col.add_child(sub)
	var orn := Control.new()
	orn.custom_minimum_size = Vector2(560, 34)
	orn.draw.connect(func():
		var y := 17.0
		orn.draw_line(Vector2(0, y), Vector2(240, y), Color(0.86, 0.72, 0.42, 0.8), 1.5, true)
		orn.draw_line(Vector2(280, y), Vector2(520, y), Color(0.86, 0.72, 0.42, 0.8), 1.5, true)
		orn.draw_colored_polygon(PackedVector2Array([Vector2(260, y - 8), Vector2(268, y), Vector2(260, y + 8), Vector2(252, y)]), Color(0.86, 0.72, 0.42)))
	col.add_child(orn)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	col.add_child(spacer)
	if Game.has_save():
		col.add_child(_menu_item("Continue", _save_summary(), func(): _go(_continue_now)))
		_gate.append(_last_btn)
	col.add_child(_menu_item("Begin a New Journey", "", func(): _go(_new_game_now)))
	_gate.append(_last_btn)
	col.add_child(_menu_item("Settings", "", _settings))
	col.add_child(_menu_item("Credits", "", _show_credits))
	col.add_child(_menu_item("Quit", "", func(): get_tree().quit()))
	_tip = UITheme.label(TIPS[0], 20, Color(0.88, 0.82, 0.68), "body")
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tip.add_theme_constant_override("outline_size", 6)
	_tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	UITheme.place(_tip, Control.PRESET_BOTTOM_RIGHT, Vector2(-760, -84), Vector2(720, 60))
	add_child(_tip)
	_tip_t = 7.0
	var ver := UITheme.label("v1.1  ·  Godot 4.7  ·  F1 hides the HUD in game", 16, Color(0.62, 0.57, 0.47))
	UITheme.place(ver, Control.PRESET_BOTTOM_LEFT, Vector2(124, -50), Vector2(520, 26))
	add_child(ver)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	if _first:
		_first.call_deferred("grab_focus")


## A menu line: large carved-looking text that lights up gold, with an optional detail beneath.
func _menu_item(text: String, detail: String, cb: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -6)
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(560, 62)
	b.add_theme_font_override("font", UITheme.font("header"))
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_color_override("font_color", Color(0.9, 0.85, 0.74))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.52))
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.85, 0.52))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	b.add_theme_constant_override("outline_size", 6)
	var plain := StyleBoxEmpty.new()
	plain.content_margin_left = 22
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(0.9, 0.68, 0.3, 0.1)
	lit.border_color = Color(0.95, 0.76, 0.4)
	lit.border_width_left = 4
	lit.content_margin_left = 22
	lit.shadow_color = Color(1.0, 0.7, 0.3, 0.08)
	lit.shadow_size = 12
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, plain)
	for st in ["hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, lit)
	b.pressed.connect(cb)
	b.pressed.connect(func(): Audio.ui("click"))
	b.mouse_entered.connect(func():
		Audio.ui("hover")
		b.grab_focus())
	box.add_child(b)
	if detail != "":
		var d := UITheme.label(detail, 19, Color(0.78, 0.72, 0.6), "fell")
		d.add_theme_constant_override("outline_size", 5)
		d.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 26)
		m.add_child(d)
		box.add_child(m)
	if _first == null:
		_first = b
	_last_btn = b
	return box


## The browser build: download (or find cached) the island's data packs before play can start.
func _fetch_data() -> void:
	for b in _gate:
		b.disabled = true
	_status = UITheme.label("Fetching the island...", 21, Color(0.95, 0.86, 0.66), "fell")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	UITheme.place(_status, Control.PRESET_CENTER_BOTTOM, Vector2(-500, -130), Vector2(1000, 34))
	add_child(_status)
	var web: Node = preload("res://scripts/core/web_data.gd").new()
	add_child(web)
	web.progress.connect(func(f: float, t: String): _status.text = "%s  -  %d%%" % [t, int(f * 100.0)])
	web.finished.connect(func(ok: bool):
		if ok:
			_status.text = ""
			for b in _gate:
				b.disabled = false
			if _first:
				_first.grab_focus()
			_title_sound()
			if str(JavaScriptBridge.eval("location.search")).contains("autostart"):
				_go(_new_game_now)       # (page?autostart: straight into a new game, for testing)
		else:
			_status.text = "The island's data couldn't be downloaded. Check your connection and reload the page.")
	web.start()


func _save_summary() -> String:
	var d := Game.read_save()
	if d.is_empty():
		return ""
	var mins := float(d.get("minutes", 0.0))
	var day := int(mins / 1440.0) + 1
	var tod := fmod(mins, 1440.0)
	var s := "Day %d, %02d:%02d" % [day, int(tod / 60.0), int(tod) % 60]
	if String(d.get("location", "")) != "":
		s += "  ·  " + String(d.location)
	return s + "  ·  " + Items.price_text(int(d.get("silver", 0)))


func _go(then: Callable) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_callback(then)


func _new_game_now() -> void:
	Game.new_game()
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _continue_now() -> void:
	Game.new_game()
	var d := Game.read_save()
	if not d.is_empty():
		Game.apply_save(d)
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _settings() -> void:
	_menus.call("open_settings")


func _show_credits() -> void:
	if _credits:
		_credits.queue_free()
		_credits = null
		return
	_credits = PanelContainer.new()
	_credits.custom_minimum_size = Vector2(980, 660)
	UITheme.place(_credits, Control.PRESET_CENTER, Vector2(-490, -330), Vector2(980, 660))
	var v := VBoxContainer.new()
	_credits.add_child(v)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = CREDITS
	rt.custom_minimum_size = Vector2(940, 570)
	v.add_child(rt)
	var close := UITheme.button("Close", _show_credits, 200)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)
	add_child(_credits)
