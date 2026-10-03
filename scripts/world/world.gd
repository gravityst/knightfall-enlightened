extends Node3D
## Root of the playable world. Loads the island, builds every subsystem and runs the
## per-frame orchestration (streaming, atmosphere, sleeping, death, saving).

const PICKUP := preload("res://scripts/world/pickup.gd")
var atmosphere: Atmosphere
var terrain: Terrain
var vegetation: Node3D
var settlements: Node3D
var npcs: Node3D
var wildlife: Node3D
var wilds: Node3D
var player: Player
var hud: CanvasLayer
var _waiting := false
var loading: CanvasLayer
var fires: Array[Node3D] = []
var ready_to_play := false
var _shots: Array = []
var _shot_frames := 0
var _water_mat: ShaderMaterial
var _player_horse: Node3D


func _ready() -> void:
	Game.world_ref = self
	loading = preload("res://scripts/ui/loading_screen.gd").new()
	add_child(loading)
	_load()


var _t_last := 0
func _progress(v: float, text: String) -> void:
	var now := Time.get_ticks_msec()
	if OS.get_cmdline_user_args().has("--timing"):
		print("LOAD %5d ms  (+%d)  %s" % [now, now - _t_last, text])
	_t_last = now
	loading.call("set_progress", v, text)


func _exit_tree() -> void:
	Assets.save_manifest()


func _load() -> void:
	# the loading screen is all that is drawn while loading: don't wait for vsync between steps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	WorldData.prefetch()
	Assets.prefetch()
	await get_tree().process_frame
	await WorldData.load_all(_progress)
	_progress(0.3, "Raising the sky")
	await get_tree().process_frame
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.setup()
	_progress(0.34, "Shaping the land")
	await get_tree().process_frame
	terrain = Terrain.new()
	add_child(terrain)
	terrain.setup()
	_setup_water()
	_progress(0.4, "Planting the forests")
	await get_tree().process_frame
	preload("res://scripts/world/wilds.gd").plan()     # the wild places, so the forests leave room for them
	if ResourceLoader.exists("res://scripts/world/vegetation.gd"):
		vegetation = load("res://scripts/world/vegetation.gd").new()
		add_child(vegetation)
		await vegetation.call("setup", func(v, t): _progress(0.4 + v * 0.2, t))
	_progress(0.6, "Raising villages, towns and castles")
	await get_tree().process_frame
	if ResourceLoader.exists("res://scripts/world/settlements.gd"):
		settlements = load("res://scripts/world/settlements.gd").new()
		add_child(settlements)
		await settlements.call("setup", func(v, t): _progress(0.6 + v * 0.25, t))
		if vegetation and vegetation.grass:
			vegetation.grass.call("set_mask", settlements.call("build_grass_mask"))
	if vegetation:
		vegetation.call("finish")
	_progress(0.86, "Waking the townsfolk")
	await get_tree().process_frame
	if ResourceLoader.exists("res://scripts/actors/npc_manager.gd"):
		npcs = load("res://scripts/actors/npc_manager.gd").new()
		add_child(npcs)
		await npcs.call("setup")
	_progress(0.92, "Releasing the wildlife")
	await get_tree().process_frame
	if ResourceLoader.exists("res://scripts/actors/wildlife.gd"):
		wildlife = load("res://scripts/actors/wildlife.gd").new()
		add_child(wildlife)
		wildlife.call("setup")
	wilds = preload("res://scripts/world/wilds.gd").new()
	add_child(wilds)
	wilds.call("setup")
	_progress(0.94, "Tuning the lutes")
	await get_tree().process_frame
	Audio.generate_all()
	atmosphere.lightning_struck.connect(func(d): Audio.lightning(d))
	_progress(0.97, "Entering Aldmere")
	player = Player.new()
	add_child(player)
	player.died.connect(_on_player_died)
	var sp: Dictionary = WorldData.info.spawn
	var start := Vector3(float(sp.x), 0, float(sp.z))
	start.y = WorldData.height_at(start.x, start.z) + 0.2
	player.global_position = start
	var town: Dictionary = WorldData.settlement_by_name("Kingsbridge")
	if not town.is_empty():
		player.set_look(atan2(-(float(town.x) - start.x), -(float(town.z) - start.z)), -0.05)
	if not Game.loading_save.is_empty():
		_apply_save(Game.loading_save)
		Game.loading_save = {}
	else:
		atmosphere.set_weather("clear", true)
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	if Game.perf_overlay or Game.tour:
		add_child(preload("res://scripts/ui/perf_overlay.gd").new())
	terrain.update_view(player.cam.global_position, true)
	terrain.update_collision(player.global_position)
	if vegetation:
		vegetation.call("update_stream", player.global_position, true)
	_parse_shots()
	if "--smoke" in OS.get_cmdline_user_args():
		add_child(load("res://tools/smoke.gd").new())
	if "--probe5" in OS.get_cmdline_user_args():
		add_child(load("res://tools/probe5.gd").new())
	if "--perf" in OS.get_cmdline_user_args():
		add_child(load("res://tools/perf.gd").new())
	if Assets.compat and not Game.debug_flag("nowarm"):
		_progress(0.985, "Lighting the lamps")
		await _warm_shaders()
	for i in 8:
		await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if Game.settings.vsync else DisplayServer.VSYNC_DISABLED)
	loading.call("finish")
	ready_to_play = true
	Assets.save_manifest()
	Assets.settle_prefetch()
	if "--timing" in OS.get_cmdline_user_args():
		_progress(1.0, "Ready")
		var worst := 0.0
		var t0 := Time.get_ticks_usec()
		for i in 180:
			var f0 := Time.get_ticks_usec()
			await get_tree().process_frame
			worst = maxf(worst, (Time.get_ticks_usec() - f0) / 1000.0)
		print("LOAD first 180 frames: %.0f ms total, worst frame %.0f ms" % [(Time.get_ticks_usec() - t0) / 1000.0, worst])
		if "--reenter" in OS.get_cmdline_user_args() and not Game.has_meta("reentered"):
			Game.set_meta("reentered", true)   # test hook: quit to the title screen and load again
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
			return
		get_tree().quit()
	if _shots.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.start_ambience()


func _setup_water() -> void:
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/water.gdshader")
	if Assets.compat:
		_water_mat.set_shader_parameter("ssr_steps", 10)     # the browser: a cheaper reflection march
	_water_mat.set_shader_parameter("watermap", WorldData.water_tex)
	_water_mat.set_shader_parameter("heightmap", WorldData.height_tex)
	_water_mat.set_shader_parameter("flowmap", WorldData.flow_tex)
	_water_mat.set_shader_parameter("normal_a", _noise_normal(0.035, 3, 7))
	_water_mat.set_shader_parameter("normal_b", _noise_normal(0.012, 4, 11))
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn.frequency = 0.03
	fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var ft := NoiseTexture2D.new()
	ft.width = 512
	ft.height = 512
	ft.seamless = true
	ft.noise = fn
	ft.generate_mipmaps = true
	_water_mat.set_shader_parameter("foam_noise", ft)
	_water_mat.render_priority = -1
	terrain.setup_water(_water_mat)
	# far ocean ring beyond the terrain quadtree
	var ring_mat: ShaderMaterial = _water_mat.duplicate()
	ring_mat.set_shader_parameter("ring", true)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := 4096.0
	var outer := 60000.0
	var rects := [Rect2(-outer, -outer, outer * 2, outer - inner), Rect2(-outer, inner, outer * 2, outer - inner),
		Rect2(-outer, -inner, outer - inner, inner * 2), Rect2(inner, -inner, outer - inner, inner * 2)]
	for r in rects:
		var nx := 24
		var nz := 24
		for j in nz:
			for i in nx:
				var x0: float = r.position.x + r.size.x * i / nx
				var x1: float = r.position.x + r.size.x * (i + 1) / nx
				var z0: float = r.position.y + r.size.y * j / nz
				var z1: float = r.position.y + r.size.y * (j + 1) / nz
				for v in [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x0, 0, z1), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]:
					st.add_vertex(v)
	var ring := MeshInstance3D.new()
	ring.mesh = st.commit()
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.custom_aabb = AABB(Vector3(-outer, -10, -outer), Vector3(outer * 2, 20, outer * 2))
	add_child(ring)


func _noise_normal(freq: float, oct: int, seed: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.fractal_octaves = oct
	n.seed = seed
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 6.0
	t.noise = n
	t.generate_mipmaps = true
	return t


func _process(delta: float) -> void:
	if not ready_to_play or player == null:
		return
	var cam := player.cam
	RenderingServer.global_shader_parameter_set("cam_pos", cam.global_position)
	RenderingServer.global_shader_parameter_set("player_pos", player.global_position)
	atmosphere.update_atmosphere(delta, cam)
	terrain.update_view(cam.global_position)
	terrain.update_collision(player.global_position)
	var cp := cam.global_position
	var under := cp.y < WorldData.water_level_at(cp.x, cp.z) - 0.02 and WorldData.water_depth_at(cp.x, cp.z) > 0.2
	atmosphere.underwater = under
	if _shots.size() > 0:
		_run_shots()


# ------------------------------------------------------------------ fires, sleep, death
var water_sources: Array[Vector3] = []


func register_water_source(p: Vector3) -> void:
	water_sources.append(p)


func water_source_near(p: Vector3, r: float) -> bool:
	for w in water_sources:
		if w.distance_squared_to(p) < r * r:
			return true
	return false


func register_fire(n: Node3D) -> void:
	fires.append(n)


func fire_near(p: Vector3, r: float) -> bool:
	for f in fires:
		if is_instance_valid(f) and f.global_position.distance_squared_to(p) < r * r:
			return true
	return false


func spawn_campfire(p: Vector3) -> void:
	var fire: Node3D = preload("res://scripts/world/campfire.gd").new()
	add_child(fire)
	fire.global_position = p
	register_fire(fire)


## Why the player can't rest or wait right now ("" when it is safe to).
func rest_blocked() -> String:
	if player.mounted:
		return "You can't rest in the saddle."
	if player.swimming:
		return "You can't rest while swimming."
	if wildlife.call("predator_near", player.global_position, 30.0):
		return "You can't rest with predators prowling nearby."
	for d in npcs.active:
		if d.node and d.alive and (d.hostile or (d.role in ["knight", "guard"] and Game.is_wanted_in(d.sname))) \
				and d.node.global_position.distance_to(player.global_position) < 30.0:
			return "You can't rest with enemies nearby."
	return ""


## Z: let an hour pass (wait out the night, a closed gate or the next market day).
func wait_hour() -> void:
	if _waiting:
		return
	var why := rest_blocked()
	if why != "":
		Game.notify.emit(why, "warn")
		return
	_waiting = true
	if hud:
		hud.call("fade_wait")
	await get_tree().create_timer(0.3).timeout
	Game.advance_minutes(60.0)
	Game.stats.stamina = minf(float(Game.stats.stamina) + 40.0, 100.0)
	Game.stats.hunger = maxf(float(Game.stats.hunger) - 2.0, 0.0)
	Game.stats.thirst = maxf(float(Game.stats.thirst) - 2.5, 0.0)
	Game.stats_changed.emit()
	Game.notify.emit("You wait an hour. It is now %s." % Game.clock_text(), "info")
	_waiting = false


## F2: save a HUD-free screenshot to ~/Pictures/Knightfall.
func take_screenshot() -> void:
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).path_join("Knightfall")
	DirAccess.make_dir_recursive_absolute(dir)
	var was_visible: bool = hud.visible
	hud.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	hud.visible = was_visible
	var path := dir.path_join("Knightfall %s.png" % Time.get_datetime_string_from_system().replace(":", ".").replace("T", " "))
	if img.save_png(path) == OK:
		Audio.ui("click")
		Game.notify.emit("Screenshot saved to Pictures/Knightfall.", "info")
	else:
		Game.notify.emit("Could not save the screenshot.", "warn")


func sleep(hours: float, indoor: bool) -> String:
	var why := rest_blocked()
	if why != "":
		Game.notify.emit(why, "warn")
		return why
	if Game.is_night() == false and hours >= 8.0 and Game.time_of_day() > 6.0 and Game.time_of_day() < 17.0:
		hours = 2.0
	var t := Game.time_of_day()
	var until_morning := fposmod(7.0 - t, 24.0)
	var h := until_morning if until_morning > 0.5 and until_morning < 13.0 else hours
	if hud:
		hud.call("fade_sleep")
	await get_tree().create_timer(0.8).timeout
	Game.advance_minutes(h * 60.0)
	Game.stats.stamina = 100.0
	Game.change_stat("health", 35.0 if indoor else 18.0)
	Game.stats.hunger = maxf(float(Game.stats.hunger) - h * 2.0, 0.0)
	Game.stats.thirst = maxf(float(Game.stats.thirst) - h * 2.5, 0.0)
	if indoor:
		Game.stats.warmth = maxf(float(Game.stats.warmth), 70.0)
		player.last_bed = player.global_position
	Game.stats_changed.emit()
	var msg := "You sleep for %d hours and wake rested." % int(round(h))
	Game.notify.emit(msg, "info")
	return msg


func player_hurt(_dmg: float) -> void:
	if hud:
		hud.call("pulse_damage")


func _on_player_died() -> void:
	if hud:
		hud.call("show_death")
	await get_tree().create_timer(4.0).timeout
	var wanted := Game.wanted_settlements()
	var lost := 0
	var msg := "You awaken, bruised. A stranger tended your wounds - and your purse (-%s)."
	if wanted.is_empty():
		lost = Game.silver / 5
	else:
		# the watch considers the matter settled: they take their fines and let you go
		for s in wanted:
			lost += Dialogue.fine_amount(s)
			Game.clear_bounty(s)
		lost = mini(lost, Game.silver)
		msg = "You come to outside the walls. The watch took their fines from your purse (-%s) and consider the matter closed."
	Game.silver -= lost
	if npcs:
		npcs.call("stand_down", "")
	var at := player.last_bed
	if not wanted.is_empty():
		at = _settlement_edge(String(wanted[0]))
	elif at == Vector3.INF:
		var s := WorldData.nearest_settlement(player.global_position)
		at = Vector3(float(s.x), 0, float(s.z))
		at.y = WorldData.height_at(at.x, at.z) + 0.3
	player.respawn(at)
	Game.advance_minutes(6.0 * 60.0)
	Game.notify.emit(msg % Items.price_text(lost), "warn")
	if hud:
		hud.call("hide_death")


## Serving time: a day (more for grave crimes) in the cells clears the bounty; you are
## released at the edge of the settlement.
func serve_jail(sname: String) -> void:
	var days := Dialogue.jail_days(sname)
	if hud:
		hud.call("fade_sleep")
	await get_tree().create_timer(0.8).timeout
	Game.clear_bounty(sname)
	Game.advance_minutes(days * 1440.0)
	Game.stats.hunger = maxf(float(Game.stats.hunger) - 20.0 * days, 15.0)
	Game.stats.thirst = maxf(float(Game.stats.thirst) - 20.0 * days, 15.0)
	Game.stats.stamina = 100.0
	Game.stats_changed.emit()
	player.global_position = _settlement_edge(sname)
	player.velocity = Vector3.ZERO
	terrain.update_view(player.cam.global_position, true)
	terrain.update_collision(player.global_position)
	Game.notify.emit("You served %s in the cells of %s. Your debt is paid." % ["a day" if days == 1 else "%d days" % days, sname], "info")


## A spot just outside a settlement: its castle gate or road exit, else its edge.
func _settlement_edge(sname: String) -> Vector3:
	if settlements:
		for info in settlements.infos:
			if info.name != sname:
				continue
			var p: Vector3 = info.center + Vector3(float(info.radius) * 0.8, 0, 0)
			if int(info.gate_out) >= 0:
				p = info.nav_p[int(info.gate_out)]
			elif not info.exits.is_empty():
				p = info.nav_p[int(info.exits[0].nav)]
			p.y = WorldData.height_at(p.x, p.z) + 0.3
			return p
	return player.global_position


func call_horse() -> void:
	if npcs and npcs.has_method("call_player_horse"):
		npcs.call("call_player_horse")
	else:
		Game.notify.emit("You whistle, but no horse answers. Buy one at a stable.", "warn")


# ------------------------------------------------------------------ save
func get_save_state() -> Dictionary:
	var d := {"atmosphere": atmosphere.get_state()}
	if settlements and settlements.has_method("get_state"):
		d["settlements"] = settlements.call("get_state")
	if npcs and npcs.has_method("get_state"):
		d["npcs"] = npcs.call("get_state")
	return d


func _apply_save(d: Dictionary) -> void:
	for old in Game.world_drops:
		if is_instance_valid(old.get("node")):
			(old.node as Node).queue_free()
	Game.apply_save(d)
	PICKUP.restore(self, d.get("drops", []))
	player.set_save_state(d.get("player", {}))
	var w: Dictionary = d.get("world", {})
	atmosphere.set_state(w.get("atmosphere", {}))
	if settlements and settlements.has_method("set_state"):
		settlements.call("set_state", w.get("settlements", {}))
	if npcs and npcs.has_method("set_state"):
		npcs.call("set_state", w.get("npcs", {}))


func load_save() -> void:
	var d := Game.read_save()
	if d.is_empty():
		return
	_apply_save(d)
	terrain.update_view(player.cam.global_position, true)
	terrain.update_collision(player.global_position)
	if vegetation:
		vegetation.call("update_stream", player.global_position, true)
	Game.notify.emit("Game loaded.", "info")


# ------------------------------------------------------------------ screenshot harness
func _parse_shots() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			var d = JSON.parse_string(FileAccess.get_file_as_string(a.substr(8)))
			if d is Array:
				_shots = d
	if not _shots.is_empty():
		atmosphere.cam_attr.auto_exposure_speed = 6.0
		process_mode = Node.PROCESS_MODE_ALWAYS   # menu shots pause the game; the capture must go on
		_begin_shot()


func _begin_shot() -> void:
	var s: Dictionary = _shots[0]
	if hud and String(hud.menus.mode) != "":
		hud.menus.close()
	Game.minutes = float(s.get("day", Game.day())) * 1440.0 + float(s.get("hour", 10.0)) * 60.0
	Game.paused_time = true
	atmosphere.set_weather(String(s.get("weather", "clear")), true)
	if s.has("wetness"):
		atmosphere.wetness = float(s.wetness)
	var p := Vector3(float(s.x), 0, float(s.z))
	var ground := WorldData.height_at(p.x, p.z)
	p.y = float(s.y) if s.has("y") else ground + float(s.get("h", 1.7))
	player.global_position = p - Vector3(0, Player.EYE, 0)
	player.set_physics_process(false)
	player.set_look(deg_to_rad(float(s.get("yaw", 0.0))), deg_to_rad(float(s.get("pitch", 0.0))))
	player.head.rotation.x = player._pitch
	terrain.update_view(player.cam.global_position, true)
	# first-person checks: sword drawn, torch, blocking, or a swing caught mid-cut ("attack_at" frames before the shot)
	player.weapon_drawn = bool(s.get("weapon", false))
	player.torch_on = bool(s.get("torch", false))
	player.torch_light.visible = player.torch_on
	player._blocking = bool(s.get("block", false))
	player._refresh_view_model()
	_shot_frames = int(s.get("frames", 70))
	if s.has("waypoint"):
		Game.waypoint = Vector2(float(s.waypoint[0]), float(s.waypoint[1]))
	if s.has("spawn") and wildlife:
		var fwd := -player.cam.global_transform.basis.z
		fwd.y = 0.0
		var at := p + fwd.normalized() * float(s.spawn[1])
		at.y = WorldData.height_at(at.x, at.z)
		wildlife.call("_spawn_group", String(s.spawn[0]), at)


## Shot helper: stands the camera a few metres in front of the nearest active NPC with the
## requested role (and gender), for close-up checks of clothing and gear.
func _frame_npc(sh: Dictionary) -> void:
	npcs.call("flush_spawns")
	var best: NPC = null
	var bd := INF
	for d in npcs.active:
		if d.node == null or (String(sh.near_npc) != "any" and d.role != String(sh.near_npc)) or (sh.has("gender") and d.gender != String(sh.gender)):
			continue
		if (sh.has("mounted") and d.mounted != bool(sh.mounted)) or (sh.has("hostile") and d.hostile != bool(sh.hostile)):
			continue
		var dd: float = (d.node as Node3D).global_position.distance_to(player.global_position)
		if dd < bd:
			bd = dd
			best = d.node
	if best == null and bool(sh.get("search_all", false)):
		# go to the first matching NPC anywhere on the island (e.g. a mounted traveller on a road)
		for d in npcs.all:
			if not d.alive or (String(sh.near_npc) != "any" and d.role != String(sh.near_npc)):
				continue
			if (sh.has("mounted") and d.mounted != bool(sh.mounted)) or (sh.has("hostile") and d.hostile != bool(sh.hostile)):
				continue
			player.global_position = d.pos + Vector3(4, 0, 4)
			if d.node == null:
				npcs.call("_spawn", d)
			best = d.node
			break
	if best == null:
		print("SHOT no npc for ", sh.near_npc)
		return
	if sh.has("anim"):
		best.set_physics_process(false)
		best.model.armed = bool(sh.get("armed", false))
		best.model.current = ""
		best.model.play(String(sh.anim), 0.0)
	var fwd: Vector3 = best.model.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized().rotated(Vector3.UP, deg_to_rad(float(sh.get("around", 20.0))))
	var cam_at: Vector3 = best.global_position + fwd * float(sh.get("dist", 2.6)) + Vector3(0, 1.45, 0)
	player.global_position = cam_at - Vector3(0, Player.EYE, 0)
	var to: Vector3 = best.global_position + Vector3(0, 1.0, 0) - cam_at
	player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	player.head.rotation.x = player._pitch


## The browser compiles each shader the first time it's drawn, which froze the game for seconds on
## reaching a town or at nightfall. So everything is drawn once here, tiny and hidden behind the
## loading screen - each mesh with its own materials and in the same form the game draws it (plain,
## or instanced with or without per-instance colour and data, which WebGL insists match) - under the
## sun, an oil lamp and a lantern beam, casting a shadow, beside a townsperson, every beast and the
## fires and blood the game makes later.
func _warm_shaders() -> void:
	var rig := Node3D.new()
	add_child(rig)
	rig.global_transform = player.cam.global_transform.translated_local(Vector3(0, 0, -1.4))
	var slot := [0]
	var place := func(n: Node3D, size: float) -> void:
		var i: int = slot[0]
		slot[0] = i + 1
		n.position = Vector3(-0.45 + (i % 40) * 0.023, -0.25 + (i / 40) * 0.023, 0.0)
		n.scale = Vector3.ONE * size
		rig.add_child(n)
	var folk := CharacterModel.new()
	place.call(folk, 0.006)
	folk.build({"gender": "f", "outfit": "Peasant", "hood": true, "torch": true})
	for f in [FireFX.flames(0.2, 0.4), FireFX.flames(0.1, 0.2)]:
		place.call(f, 0.05)
	FireFX.burst(rig, rig.global_position, "blood")
	FireFX.burst(rig, rig.global_position, "sparks")
	var later := ["res://assets/animals/Horse.glb", "res://assets/animals/Horse_White.glb", "res://assets/village/Prop_Wagon.gltf",
		"res://assets/village/Wall_UnevenBrick_Straight.gltf", "res://assets/village/Wall_UnevenBrick_Window_Wide_Round.gltf", "res://assets/village/Wall_UnevenBrick_Door_Round.gltf",
		"res://assets/village/Prop_Vine2.gltf", "res://assets/village/Prop_Vine5.gltf", "res://assets/village/Prop_Brick1.gltf"]
	for sp in preload("res://scripts/actors/wildlife.gd").SPECIES.values():
		later.append("res://assets/animals/" + String(sp.path))
	for f in ["Barrel", "Crate_Wooden", "Pot_1", "Bag", "Chest_Wood", "Pouch_Large", "BookStand", "CandleStick", "CandleStick_Triple", "CandleStick_Stand",
			"Banner_2", "Chalice", "Lantern_Wall", "Vase_Rubble_Medium", "Shield_Wooden", "Sword_Bronze", "Torch_Metal"]:
		later.append("res://assets/props/%s.gltf" % f)
	var seen := {}
	for path in later:
		if ResourceLoader.exists(path) and not seen.has(path):
			seen[path] = true
			place.call(Assets.instance_sized(path, 0.02, "max"), 1.0)
	var statue := MeshInstance3D.new()
	statue.mesh = BoxMesh.new()
	statue.material_override = preload("res://scripts/world/settlements.gd")._statue_stone()
	place.call(statue, 0.01)
	# one of every mesh in the world, drawn as the world draws it
	var n := 0
	for gi in find_children("*", "GeometryInstance3D", true, false):
		if gi.get_parent() == rig or rig.is_ancestor_of(gi):
			continue
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh and (gi as MeshInstance3D).skeleton.is_empty():
			var mi := gi as MeshInstance3D
			var key := "m%d|%d" % [mi.mesh.get_instance_id(), mi.material_override.get_instance_id() if mi.material_override else 0]
			if seen.has(key):
				continue
			seen[key] = true
			var c := MeshInstance3D.new()
			c.mesh = mi.mesh
			c.material_override = mi.material_override
			for si in mi.mesh.get_surface_count():
				c.set_surface_override_material(si, mi.get_surface_override_material(si))
			place.call(c, 0.01 / maxf(mi.mesh.get_aabb().get_longest_axis_size(), 0.01))
			n += 1
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh and (gi as MultiMeshInstance3D).multimesh.mesh:
			var src := (gi as MultiMeshInstance3D).multimesh
			var key := "mm%d|%s%s|%d" % [src.mesh.get_instance_id(), src.use_colors, src.use_custom_data, gi.material_override.get_instance_id() if gi.material_override else 0]
			if seen.has(key):
				continue
			seen[key] = true
			place.call(_warm_batch(src.mesh, src.use_colors, src.use_custom_data, gi.material_override), 0.01 / maxf(src.mesh.get_aabb().get_longest_axis_size(), 0.01))
			n += 1
	if vegetation:
		for m in vegetation.get("_meshes"):
			for custom in [false, true]:
				place.call(_warm_batch(m, false, custom, null), 0.01 / maxf((m as Mesh).get_aabb().get_longest_axis_size(), 0.01))
				n += 1
		var imp = vegetation.get("_imp_mesh")
		if imp:
			place.call(_warm_batch(imp, false, true, vegetation.get("_imp_material")), 0.01)
		if vegetation.grass:
			for m in vegetation.grass.get("_meshes"):
				if m is Mesh:
					place.call(_warm_batch(m, false, false, null), 0.01 / maxf((m as Mesh).get_aabb().get_longest_axis_size(), 0.01))
					n += 1
	var omni := OmniLight3D.new()
	omni.omni_range = 4.0
	omni.position = Vector3(0, 0, 0.4)
	rig.add_child(omni)
	var spot := SpotLight3D.new()
	spot.spot_range = 5.0
	spot.spot_angle = 60.0
	spot.position = Vector3(0, 0, 1.0)
	rig.add_child(spot)
	for f in 4:
		await get_tree().process_frame
	rig.queue_free()
	print("Warmed %d meshes" % n)


func _warm_batch(mesh: Mesh, colors: bool, custom: bool, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D())
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


## Shot helper: stands back from a wild place of the given kind ("sign" = a signpost) and looks at it.
func _frame_place(sh: Dictionary) -> void:
	var at := Vector3.INF
	if String(sh.wild) == "sign":
		var g: Dictionary = wilds.signs[int(sh.get("index", 0))]
		at = Vector3(float(g.x), 0, float(g.z))
	else:
		for st in wilds.sites:
			if st.kind == String(sh.wild):
				at = Vector3(float(st.x), 0, float(st.z))
				break
	if at == Vector3.INF:
		return
	at.y = WorldData.height_at(at.x, at.z)
	var a := deg_to_rad(float(sh.get("around", 30.0)))
	var d := float(sh.get("dist", 13.0))
	var cam_at := at + Vector3(sin(a) * d, 0, cos(a) * d)
	cam_at.y = WorldData.height_at(cam_at.x, cam_at.z) + float(sh.get("h", 2.2))
	player.global_position = cam_at - Vector3(0, Player.EYE, 0)
	var to := at + Vector3(0, 1.0, 0) - cam_at
	player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	player.head.rotation.x = player._pitch
	terrain.update_view(player.cam.global_position, true)
	if vegetation:
		vegetation.call("update_stream", player.global_position, true)
	for st in wilds.sites:
		if st.node == null and Vector2(float(st.x) - at.x, float(st.z) - at.z).length() < 5.0:
			st.node = wilds._build_site(st)
	for g in wilds.signs:
		if g.node == null and Vector2(float(g.x) - at.x, float(g.z) - at.z).length() < 5.0:
			g.node = wilds._build_sign(g)


## Shot helper: takes a job from the nearest knight, merchant and innkeeper.
func _seed_quests() -> void:
	npcs.call("flush_spawns")
	var seen := {}
	for d in npcs.active:
		if d.node and d.role in ["knight", "merchant", "tavern_owner"] and not seen.has(d.role):
			seen[d.role] = true
			Dialogue.respond(d.node, "quest_ask")
			Dialogue.respond(d.node, "quest_accept")


## Shot helper: opens a menu just before the capture (dialogue/trade use the framed NPC).
func _shot_ui(which: String) -> void:
	var m = hud.menus
	match which:
		"pause": m.open_pause()
		"inventory": m.open_inventory()
		"map": m.open_map()
		"settings": m.open_settings()
		"journal": m.open_journal()
		"dialogue", "trade":
			var best: NPC = null
			var bd := INF
			for d in npcs.active:
				if d.node and (which == "dialogue" or not d.stock.is_empty()):
					var dd: float = (d.node as Node3D).global_position.distance_to(player.global_position)
					if dd < bd:
						bd = dd
						best = d.node
			if best:
				if which == "dialogue":
					npcs.open_dialogue(best)
				else:
					m.open_trade(best)


func _run_shots() -> void:
	player.rotation.y = player._yaw
	player.head.rotation.x = player._pitch
	_shot_frames -= 1
	var sh: Dictionary = _shots[0]
	if sh.has("near_npc") and _shot_frames == 40:
		_frame_npc(sh)
	if sh.has("seed_quests") and _shot_frames == 50:
		_seed_quests()
	if sh.has("ui") and _shot_frames == 12:
		_shot_ui(String(sh.ui))
	if _shot_frames == int(sh.get("attack_at", -1)):
		player._attack_cd = 0.0
		player._swing(bool(sh.get("power", false)))
	if sh.has("wild") and _shot_frames == 60:
		_frame_place(sh)
	if sh.has("combat_hud") and _shot_frames == 8 and wildlife:
		for a in wildlife.animals:
			if is_instance_valid(a) and a.kind == "predator":
				a.hp *= 0.55
				hud.show_target(a)
				hud.damage_from(a.global_position)
				break
		hud.combat_text("Parried!", Color(1.0, 0.85, 0.45))
		hud.hit_marker()
	player._update_focus()
	if _shot_frames > 0:
		return
	var s: Dictionary = _shots.pop_front()
	var img := get_viewport().get_texture().get_image()
	var w := int(s.get("width", 1280))
	img.resize(w, int(w * img.get_height() / float(img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.save_jpg(String(s.file), 0.85)
	print("SHOT saved ", s.file, " t=", Time.get_ticks_msec() / 1000.0, " fps=", Engine.get_frames_per_second())
	if _shots.is_empty():
		get_tree().quit()
	else:
		_begin_shot()
