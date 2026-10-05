class_name Atmosphere
extends Node3D
## Day / night cycle, sky, sun & moon, regional weather, precipitation, lightning,
## wind and the graphics-quality settings of the WorldEnvironment.

signal weather_changed(name: String)
signal lightning_struck(distance: float)

const WEATHER := {
	"clear":     {"cov": 0.18, "dark": 0.0, "haze": 0.0, "fog": 0.00008, "vfog": 0.0014, "wind": 0.18, "precip": 0.0, "sun": 1.0},
	"cloudy":    {"cov": 0.55, "dark": 0.1, "haze": 0.15, "fog": 0.00013, "vfog": 0.0028, "wind": 0.35, "precip": 0.0, "sun": 0.8},
	"overcast":  {"cov": 0.92, "dark": 0.35, "haze": 0.55, "fog": 0.00028, "vfog": 0.008, "wind": 0.45, "precip": 0.0, "sun": 0.45},
	"rain":      {"cov": 0.97, "dark": 0.55, "haze": 0.7, "fog": 0.00045, "vfog": 0.012, "wind": 0.55, "precip": 0.75, "sun": 0.32},
	"storm":     {"cov": 1.0, "dark": 0.85, "haze": 0.85, "fog": 0.0006, "vfog": 0.016, "wind": 0.95, "precip": 1.0, "sun": 0.18},
	"fog":       {"cov": 0.6, "dark": 0.15, "haze": 0.6, "fog": 0.0022, "vfog": 0.05, "wind": 0.08, "precip": 0.0, "sun": 0.55},
	"snow":      {"cov": 0.95, "dark": 0.3, "haze": 0.7, "fog": 0.0007, "vfog": 0.015, "wind": 0.35, "precip": 0.7, "sun": 0.45},
	"blizzard":  {"cov": 1.0, "dark": 0.45, "haze": 0.9, "fog": 0.0028, "vfog": 0.05, "wind": 1.0, "precip": 1.0, "sun": 0.3},
	"sandstorm": {"cov": 0.5, "dark": 0.2, "haze": 0.85, "fog": 0.0032, "vfog": 0.04, "wind": 1.0, "precip": 0.0, "sun": 0.5},
}

var env: Environment
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var cam_attr: CameraAttributesPractical
var weather := "clear"
var params := {}
var _target := {}
var _weather_timer := 240.0
var _cloud_offset := Vector2.ZERO
var _wind_angle := 0.6
var wetness := 0.0
var snow := 0.0
var underwater := false
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _dust: GPUParticles3D
var _collider: GPUParticlesCollisionHeightField3D
var _flash := 0.0
var _next_flash := 6.0
var precip_kind := "rain"
var climate := "temperate"
var sun_shadows := true          # (the perf test switches them off)


func setup() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cn.fractal_octaves = 5
	cn.frequency = 0.004
	var ct := NoiseTexture2D.new()
	ct.width = 1024
	ct.height = 1024
	ct.seamless = true
	ct.noise = cn
	ct.generate_mipmaps = true
	sky_mat.set_shader_parameter("cloud_noise", ct)
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	if Assets.compat:
		# the browser: ambient light from a colour that follows the time of day instead of the sky's
		# light probe, which the moving sun and clouds made it rebuild (and re-mipmap) every frame
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.62, 0.7, 0.8)
	env.fog_density = 0.00015
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.25
	env.fog_height = 60.0
	env.fog_height_density = 0.0
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.6
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.7
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_energy = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	world_env = WorldEnvironment.new()
	world_env.environment = env
	cam_attr = CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = true
	cam_attr.auto_exposure_scale = 0.32
	cam_attr.auto_exposure_speed = 0.9
	cam_attr.auto_exposure_min_sensitivity = 90.0
	cam_attr.auto_exposure_max_sensitivity = 420.0
	world_env.camera_attributes = cam_attr
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 90.0
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_angular_distance = 0.5
	moon.shadow_blur = 2.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)

	params = WEATHER.clear.duplicate()
	_target = params.duplicate()
	_build_precipitation()
	apply_graphics()
	Game.settings_changed.connect(apply_graphics)


func _build_precipitation() -> void:
	_collider = GPUParticlesCollisionHeightField3D.new()
	_collider.size = Vector3(70, 60, 70)
	_collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_collider.follow_camera_enabled = true
	add_child(_collider)
	_rain = _make_particles(14000, Vector3(34, 14, 34), Vector3(0, -22, 0), 1.6, Vector2(0.018, 0.75), Color(0.72, 0.78, 0.85, 0.32), 0.0)
	_snow = _make_particles(9000, Vector3(30, 14, 30), Vector3(0, -1.6, 0), 9.0, Vector2(0.07, 0.07), Color(1, 1, 1, 0.9), 1.2)
	_dust = _make_particles(6000, Vector3(30, 8, 30), Vector3(10, -0.5, 0), 4.0, Vector2(0.22, 0.22), Color(0.78, 0.62, 0.42, 0.22), 2.0)


func _make_particles(amount: int, box: Vector3, vel: Vector3, life: float, quad: Vector2, col: Color, turb: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(amount * (0.3 if Assets.compat else 1.0))     # the browser: lighter rain and snow
	p.lifetime = life
	p.visibility_aabb = AABB(-box * 1.5, box * 3.0)
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = vel.normalized()
	pm.spread = 4.0
	pm.initial_velocity_min = vel.length() * 0.9
	pm.initial_velocity_max = vel.length() * 1.1
	pm.gravity = Vector3.ZERO
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	if turb > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = turb
		pm.turbulence_noise_scale = 4.0
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.25
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = quad
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if quad.y > quad.x * 3.0 else BaseMaterial3D.BILLBOARD_ENABLED
	m.roughness = 0.3
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.disable_receive_shadows = true
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func apply_graphics() -> void:
	if env == null:
		return
	var s := Game.settings
	env.ssao_enabled = bool(s.ssao)
	env.ssil_enabled = bool(s.ssil)
	env.ssr_enabled = bool(s.ssr)
	env.sdfgi_enabled = bool(s.sdfgi)
	env.volumetric_fog_enabled = bool(s.volumetric_fog)
	env.glow_enabled = bool(s.glow)
	var q := int(s.shadows)
	var dist: float = [70.0, 110.0, 140.0, 240.0][q] * clampf(float(s.view_distance), 0.6, 1.6) * (0.65 if Game.mobile else 1.0)
	sun.directional_shadow_max_distance = dist
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	RenderingServer.directional_shadow_atlas_set_size(1024 if Game.mobile else [2048, 4096, 4096, 8192][q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([1, 1, 2, 3][q] as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality([1, 1, 2, 3][q] as RenderingServer.ShadowQuality)
	env.ssr_max_steps = 48 if q < 3 else 96


# ------------------------------------------------------------------ per frame
func update_atmosphere(delta: float, cam: Camera3D) -> void:
	var t := Game.time_of_day()
	# --- sun path (latitude 46 N, summer declination) ---
	var lat := deg_to_rad(46.0)
	var dec := deg_to_rad(16.0)
	var ha := (t - 13.0) / 24.0 * TAU
	var el := asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha))
	var az := atan2(sin(ha), cos(ha) * sin(lat) - tan(dec) * cos(lat))
	var sun_dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
	_orient(sun, sun_dir)
	var day_phase := float(Game.day()) + t / 24.0
	var moon_phase := fposmod(day_phase / 29.5 + 0.35, 1.0)
	var mha := ha + PI + (moon_phase - 0.5) * TAU * 0.25
	var mel := asin(sin(lat) * sin(-dec * 0.5) + cos(lat) * cos(-dec * 0.5) * cos(mha))
	var maz := atan2(sin(mha), cos(mha) * sin(lat) - tan(-dec * 0.5) * cos(lat))
	var moon_dir := Vector3(sin(maz) * cos(mel), sin(mel), cos(maz) * cos(mel)).normalized()
	_orient(moon, moon_dir)

	# --- weather blending ---
	_weather_timer -= delta * Game.minutes_per_second() / 2.0
	if _weather_timer <= 0.0:
		_pick_weather(cam.global_position)
	var k := 1.0 - exp(-delta * 0.06)
	for key in _target:
		params[key] = lerpf(float(params[key]), float(_target[key]), k)
	var sun_up := smoothstep(-0.06, 0.12, sun_dir.y)
	var golden := 1.0 - smoothstep(0.05, 0.45, sun_dir.y)
	sun.light_color = Color(1.0, 0.93, 0.84).lerp(Color(1.0, 0.56, 0.3), golden * 0.85)
	sun.light_energy = sun_up * lerpf(0.9, 1.75, smoothstep(0.0, 0.6, sun_dir.y)) * float(params.sun) + _flash * 3.0
	sun.shadow_enabled = sun_shadows and sun_dir.y > 0.02
	var moon_up := smoothstep(-0.02, 0.15, moon_dir.y) * (1.0 - sun_up)
	var moon_bright := 0.25 + 0.75 * (1.0 - absf(moon_phase - 0.5) * 2.0)
	moon.light_energy = moon_up * 0.32 * moon_bright * lerpf(1.0, 0.35, float(params.cov))
	moon.visible = moon.light_energy > 0.005
	var dl := clampf(sun_up * float(params.sun) + moon_up * 0.08, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("daylight", dl)
	RenderingServer.global_shader_parameter_set("sun_dir", sun_dir)
	# sky
	_cloud_offset += Vector2(cos(_wind_angle), sin(_wind_angle)) * delta * (0.002 + float(params.wind) * 0.008)
	sky_mat.set_shader_parameter("cloud_coverage", params.cov)
	sky_mat.set_shader_parameter("cloud_darkness", params.dark)
	sky_mat.set_shader_parameter("haze", params.haze)
	sky_mat.set_shader_parameter("cloud_offset", _cloud_offset)
	sky_mat.set_shader_parameter("star_rotation", t / 24.0 * TAU)
	sky_mat.set_shader_parameter("moon_phase", moon_phase)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("exposure", 0.12 + _flash * 0.4)
	# ambient & fog
	var night := 1.0 - sun_up
	env.ambient_light_energy = lerpf(0.22, 1.0, sun_up) + moon_up * 0.12 + _flash * 2.0
	if Assets.compat:
		var sky_tint := Color(0.56, 0.64, 0.78).lerp(Color(0.86, 0.62, 0.46), golden * sun_up * 0.6)
		env.ambient_light_color = sky_tint.lerp(Color(0.1, 0.13, 0.22), night).lerp(Color(0.55, 0.56, 0.58), float(params.cov) * 0.4)
	env.background_energy_multiplier = 1.0
	var fog_day := Color(0.63, 0.71, 0.8).lerp(Color(0.92, 0.66, 0.46), golden * sun_up * 0.7)
	var fog_col := fog_day.lerp(Color(0.035, 0.045, 0.07), night)
	if weather == "sandstorm":
		fog_col = Color(0.7, 0.55, 0.36).lerp(Color(0.12, 0.09, 0.06), night)
	fog_col = fog_col.lerp(Color(0.5, 0.52, 0.55) * (1.0 - night * 0.85), float(params.haze) * 0.6)
	var fogd := float(params.fog) * float(Game.settings.get("fog_scale", 1.0))
	if underwater:
		env.fog_light_color = Color(0.03, 0.16, 0.17) * (0.3 + dl)
		env.fog_density = 0.09
		env.fog_aerial_perspective = 0.0
		env.volumetric_fog_density = 0.0
	else:
		env.fog_light_color = fog_col
		env.fog_density = fogd
		env.fog_aerial_perspective = 0.6 * (1.0 - float(params.haze) * 0.6)
		env.volumetric_fog_density = float(params.vfog) * lerpf(1.0, 1.6, night)
		env.volumetric_fog_albedo = Color(0.85, 0.75, 0.6) if weather == "sandstorm" else Color(0.9, 0.92, 0.96)
	# wind
	_wind_angle += delta * 0.01 * sin(Time.get_ticks_msec() * 0.00003)
	var wdir := Vector2(cos(_wind_angle), sin(_wind_angle))
	RenderingServer.global_shader_parameter_set("wind_dir", wdir)
	var gust := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.0013) * sin(Time.get_ticks_msec() * 0.00071)
	RenderingServer.global_shader_parameter_set("wind_strength", float(params.wind) * gust)
	# precipitation
	var p := cam.global_position
	var temp := WorldData.temperature_at(p.x, p.z)
	precip_kind = "snow" if temp < 0.38 or weather in ["snow", "blizzard"] else "rain"
	var amount := float(params.precip)
	_set_emit(_rain, precip_kind == "rain" and amount > 0.05 and not underwater, amount)
	_set_emit(_snow, precip_kind == "snow" and amount > 0.05 and not underwater, amount)
	_set_emit(_dust, weather == "sandstorm" and float(params.haze) > 0.3, 1.0)
	for e in [_rain, _snow, _dust]:
		e.global_position = p + Vector3(wdir.x, 0, wdir.y) * float(params.wind) * 6.0 + Vector3(0, 10, 0)
	_collider.global_position = p
	if precip_kind == "rain":
		wetness = clampf(wetness + delta * (amount * 0.02 - 0.004), 0.0, 1.0)
	else:
		wetness = clampf(wetness - delta * 0.004, 0.0, 1.0)
		snow = clampf(snow + delta * amount * 0.01, 0.0, 1.0)
	if amount < 0.05 and precip_kind == "rain":
		snow = clampf(snow - delta * 0.002, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	RenderingServer.global_shader_parameter_set("snow_cover", maxf(snow, 0.0))
	# lightning
	_flash = maxf(_flash - delta * 4.0, 0.0)
	if weather == "storm":
		_next_flash -= delta
		if _next_flash <= 0.0:
			_next_flash = randf_range(5.0, 22.0)
			_flash = 1.0
			lightning_struck.emit(randf_range(300.0, 2500.0))


func _set_emit(p: GPUParticles3D, on: bool, amount: float) -> void:
	if p.emitting != on:
		p.emitting = on
	p.amount_ratio = clampf(amount, 0.05, 1.0)


func _orient(light: DirectionalLight3D, toward: Vector3) -> void:
	var up := Vector3.UP if absf(toward.y) < 0.99 else Vector3.FORWARD
	light.global_transform = Transform3D(Basis.looking_at(-toward, up), Vector3.ZERO)


func _pick_weather(p: Vector3) -> void:
	climate = WorldData.climate_at(p.x, p.z)
	var options: Dictionary
	match climate:
		"cold":
			options = {"clear": 3, "cloudy": 3, "overcast": 2, "snow": 3, "blizzard": 1, "fog": 1}
		"desert":
			options = {"clear": 7, "cloudy": 2, "sandstorm": 2, "overcast": 0.5, "rain": 0.3}
		_:
			options = {"clear": 5, "cloudy": 4, "overcast": 2, "rain": 2.5, "storm": 1, "fog": 1.2}
	var total := 0.0
	for k in options: total += float(options[k])
	var r := randf() * total
	var pick := "clear"
	for k in options:
		r -= float(options[k])
		if r <= 0.0:
			pick = k
			break
	set_weather(pick)


func set_weather(name: String, instant := false) -> void:
	weather = name
	_target = WEATHER[name].duplicate()
	_weather_timer = randf_range(120.0, 320.0)
	if instant:
		params = _target.duplicate()
	weather_changed.emit(name)


func get_state() -> Dictionary:
	return {"weather": weather, "wetness": wetness, "snow": snow}


func set_state(d: Dictionary) -> void:
	set_weather(String(d.get("weather", "clear")), true)
	wetness = float(d.get("wetness", 0.0))
	snow = float(d.get("snow", 0.0))
