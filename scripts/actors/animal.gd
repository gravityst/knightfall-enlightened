class_name Animal
extends Node3D
## One animal: grazing / wandering / fleeing herbivores, hunting predators, swimming and
## flying birds, schooling fish and village livestock.

const QUESTS := preload("res://scripts/core/quests.gd")

var sp: Dictionary
var kind := "prey"
var species := ""
var group: Dictionary
var manager: Node
var model: Node3D
var ap: AnimationPlayer
var statics: Array[MeshInstance3D] = []
var body: AnimatableBody3D
var hp := 40.0
var state := "idle"
var target := Vector3.ZERO
var speed := 0.0
var yaw := 0.0
var t_state := 0.0
var dead := false
var looted := false
var threat: Node3D = null
var _attack_cd := 0.0
var _anim := ""
var _phase := 0.0
var _height := 0.0
var _sound_t := 0.0
var home := Vector3.ZERO
var _scan_t := 0.0
var _lod_acc := 0.0
var _stagger := 0.0
var _knock := Vector3.ZERO


func setup(spec: Dictionary, sp_name: String, g: Dictionary, m: Node) -> void:
	sp = spec
	species = sp_name
	kind = spec.kind
	group = g
	manager = m
	hp = float(spec.hp)
	_phase = randf() * TAU
	model = Assets.instance_sized("res://assets/animals/" + String(spec.path), float(spec.len) * randf_range(0.9, 1.12), "xz")
	add_child(model)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		ap = aps[0]
	else:
		_apply_static_shader()
	if spec.get("moose", false):
		var ant := Assets.instance_sized("res://assets/animals/moose_antlers.glb", 1.55, "xz")
		var bb := _model_bounds()
		ant.position = Vector3(0, bb.position.y + bb.size.y * 0.7, bb.end.z - bb.size.z * 0.2)
		model.add_child(ant)
		_tint(ant, Color(0.55, 0.47, 0.36))
	if kind in ["prey", "predator", "farm"]:
		body = AnimatableBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var L: float = float(spec.len)
		box.size = Vector3(L * 0.38, L * 0.55, L * 0.95)
		cs.shape = box
		cs.position = Vector3(0, L * 0.3, 0)
		body.add_child(cs)
		add_child(body)
	elif kind in ["fish", "water"]:
		body = AnimatableBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 0
		var cs2 := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = maxf(float(spec.len) * 0.45, 0.25)
		cs2.shape = sph
		body.add_child(cs2)
		add_child(body)
	_play("Idle")
	yaw = randf() * TAU
	home = global_position


func _model_bounds() -> AABB:
	var bb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != model and n != null:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var a := xf * (mi as MeshInstance3D).mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	return bb


func _tint(n: Node, c: Color) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.7
		(mi as MeshInstance3D).material_override = m


func _apply_static_shader() -> void:
	var shader: Shader = Assets.instanced_shader("res://shaders/animal.gdshader")
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var bb := m.mesh.get_aabb()
		var src := m.mesh.surface_get_material(0)
		var sm := ShaderMaterial.new()
		sm.shader = shader
		if src is BaseMaterial3D:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			sm.set_shader_parameter("tint", src.albedo_color * (Color(0.45, 0.36, 0.3) if sp.get("moose", false) else Color.WHITE))
		sm.set_shader_parameter("mode", {"water": 2, "bird": 1}.get(kind, 0))
		sm.set_shader_parameter("y0", bb.position.y)
		sm.set_shader_parameter("height", bb.size.y)
		sm.set_shader_parameter("z0", bb.position.z)
		sm.set_shader_parameter("length", bb.size.z)
		sm.set_shader_parameter("wing_x", bb.size.x * 0.12)
		if sp.get("moose", false):
			sm.set_shader_parameter("cut_y", bb.position.y + bb.size.y * 0.735)
			sm.set_shader_parameter("cut_z", bb.position.z + bb.size.z * 0.55)
		m.material_override = sm
		Assets.set_iparam(m, "phase_off", _phase)
		statics.append(m)


func _play(n: String, scale := 1.0) -> void:
	if ap:
		ap.speed_scale = scale
		if _anim != n:
			_anim = n
			if ap.has_animation(n):
				ap.play(n, 0.2)
			elif n == "Attack" and ap.has_animation("Attack_Headbutt"):
				ap.play("Attack_Headbutt", 0.15)
			elif n == "Gallop" and ap.has_animation("Run"):
				ap.play("Run", 0.2)
			elif n == "Eating" and ap.has_animation("Idle_Eating"):
				ap.play("Idle_Eating", 0.2)
	else:
		var g := 0.0
		var graze := 0.0
		var rate := 6.0
		match n:
			"Walk": g = 1.0; rate = 6.0 * scale
			"Gallop": g = 1.6; rate = 13.0
			"Eating": graze = 1.0
			"Attack": g = 0.8; rate = 16.0
		for m in statics:
			Assets.set_iparam(m, "gait", g)
			Assets.set_iparam(m, "gait_rate", rate)
			Assets.set_iparam(m, "graze", graze)
		_anim = n


func _set_flap(f: float) -> void:
	for m in statics:
		Assets.set_iparam(m, "flap", f)


func _physics_process(delta: float) -> void:
	if dead:
		return
	# far from the player animals think at a quarter of the rate (they are many)
	var pl: Node3D = Game.player_ref
	if pl and kind != "bird" and state != "attack" and global_position.distance_squared_to(pl.global_position) > 22500.0:
		_lod_acc += delta
		if (Engine.get_physics_frames() + get_instance_id()) % 4 != 0:
			return
		delta = _lod_acc
		_lod_acc = 0.0
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	if _stagger > 0.0:          # reeling from a blow
		_stagger -= delta
		if _knock.length() > 0.05:
			var np := global_position + _knock * delta
			np.y = WorldData.height_at(np.x, np.z)
			global_position = np
			_knock = _knock.lerp(Vector3.ZERO, 1.0 - exp(-delta * 6.0))
		return
	t_state -= delta
	match kind:
		"prey", "predator", "farm":
			_land(delta)
		"water":
			_water(delta)
		"bird":
			_bird(delta)
		"fish":
			_fish(delta)


# ------------------------------------------------------------------ land
func _land(delta: float) -> void:
	var pl: Node3D = Game.player_ref
	var pp := pl.global_position if pl else Vector3(1e9, 0, 0)
	var dp := pp.distance_to(global_position)
	var sneak := 0.5 if pl and pl.get("crouching") else 1.0
	if pl and pl.get("mounted"):
		sneak = 1.3
	var night := Game.is_night()
	# --- perception
	if kind == "prey":
		if dp < float(sp.get("flee", 25.0)) * sneak and state != "flee":
			if sp.has("charge") and dp < float(sp.charge):
				_set_state("attack", 6.0)
				threat = pl
			else:
				_alarm(pp)
		_scan_t -= delta
		if _scan_t <= 0.0 and state != "flee":
			_scan_t = 0.4
			var pred: Node3D = manager.predator_near(global_position, 22.0)
			if pred:
				_alarm(pred.global_position)
		if group.get("flee_t", 0.0) > 0.0 and state != "flee" and state != "attack":
			_set_state("flee", 5.0)
	elif kind == "predator":
		var aggro := float(sp.get("aggro", 15.0)) * (1.5 if night else 1.0) * sneak
		if state not in ["attack", "flee", "eat"] and dp < aggro and not pl.get("dead"):
			threat = pl
			_set_state("attack", 25.0)
			Audio.play_at("growl" if species == "bear" else "howl", global_position)
		elif state in ["idle", "wander"] and species == "wolf" and (night or randf() < 0.002):
			var prey: Node3D = manager.prey_near(global_position, 70.0)
			if prey:
				threat = prey
				_set_state("hunt", 30.0)
		if hp < float(sp.hp) * 0.3 and state == "attack":
			_alarm(pp)
	# --- behaviour
	match state:
		"idle", "eat":
			_play("Eating" if state == "eat" else "Idle")
			if t_state <= 0.0:
				_pick_wander()
		"wander":
			if _move_to(target, float(sp.walk), delta):
				_set_state("eat" if randf() < 0.6 and kind != "predator" else "idle", randf_range(4.0, 12.0))
		"flee":
			var away: Vector3 = global_position - (group.get("flee_from", pp) as Vector3)
			away.y = 0.0
			if away.length() < 0.1:
				away = Vector3(1, 0, 0)
			var tgt := global_position + away.normalized() * 15.0
			if WorldData.water_depth_at(tgt.x, tgt.z) > 0.3:
				tgt = global_position + away.normalized().rotated(Vector3.UP, 1.4) * 15.0
			_move_to(tgt, float(sp.speed), delta)
			if t_state <= 0.0 and dp > float(sp.get("flee", 25.0)) * 1.4:
				_set_state("idle", 3.0)
		"attack", "hunt":
			if threat == null or not is_instance_valid(threat) or (threat.has_method("is_dead") and threat.call("is_dead")) or (threat == pl and pl.get("dead")):
				if state == "hunt" and threat and is_instance_valid(threat):
					_set_state("eat", 25.0)
				else:
					_set_state("idle", 2.0)
				threat = null
				return
			var tp := threat.global_position
			var d := tp.distance_to(global_position)
			if d > 45.0 or t_state <= 0.0:
				_set_state("idle", 3.0)
				threat = null
				return
			if d > float(sp.len) * 0.75 + 0.9:
				_move_to(tp, float(sp.speed) * (0.9 if species == "bear" else 1.0), delta)
			else:
				_face(tp, delta)
				_play("Attack")
				if _attack_cd <= 0.0:
					_attack_cd = 1.3 if species != "bear" else 1.9
					var dmg := float(sp.get("dmg", 8.0))
					if threat.has_method("take_damage"):
						threat.call("take_damage", dmg if threat == pl else 200.0, self, false)
					Audio.play_at("bite" if species == "wolf" else "growl", global_position)
	if kind == "farm":
		_sound_t -= delta
		if _sound_t <= 0.0:
			_sound_t = randf_range(12.0, 40.0)
			if dp < 35.0:
				Audio.play_at(species, global_position, -8.0)


func _alarm(from: Vector3) -> void:
	group["flee_from"] = from
	group["flee_t"] = 6.0
	_set_state("flee", 6.0)


func _set_state(s: String, t: float) -> void:
	state = s
	t_state = t


func _pick_wander() -> void:
	var c: Vector3 = group.get("center", home)
	var r := 18.0 if kind != "farm" else 9.0
	for i in 6:
		var p := c + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
		if WorldData.water_depth_at(p.x, p.z) < 0.1:
			target = p
			_set_state("wander", 20.0)
			return
	_set_state("idle", 4.0)


func _move_to(p: Vector3, spd: float, delta: float) -> bool:
	var to := p - global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.6:
		return true
	var dir := to / d
	var np := global_position + dir * minf(spd * delta, d)
	if WorldData.water_depth_at(np.x, np.z) > 0.6 and kind != "water":
		_pick_wander()
		return false
	np.y = WorldData.height_at(np.x, np.z)
	global_position = np
	_face(global_position + dir, delta)
	if spd > 3.0:
		_play("Gallop", clampf(spd / 9.0, 0.7, 1.4))
	else:
		_play("Walk", clampf(spd / 1.3, 0.6, 1.5))
	return false


func _face(p: Vector3, delta: float) -> void:
	var to := p - global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return
	yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 7.0))
	rotation.y = yaw
	if kind in ["prey", "predator", "farm"]:
		var n := WorldData.normal_at(global_position.x, global_position.z)
		model.rotation.x = clampf(n.dot(Vector3(sin(yaw), 0, cos(yaw))), -0.35, 0.35)   # nose up the slope


# ------------------------------------------------------------------ water birds
func _water(delta: float) -> void:
	var pl: Node3D = Game.player_ref
	var dp := pl.global_position.distance_to(global_position) if pl else 1e9
	if state == "fly":
		_height += delta * 6.0
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		global_position += dir * 11.0 * delta
		global_position.y = WorldData.water_level_at(global_position.x, global_position.z) + minf(_height, 30.0)
		_set_flap(1.0)
		if t_state <= 0.0:
			manager.remove_animal(self)
		return
	if dp < 14.0:
		state = "fly"
		t_state = 14.0
		var away := global_position - pl.global_position
		yaw = atan2(away.x, away.z) + randf_range(-0.4, 0.4)
		rotation.y = yaw
		Audio.play_at("quack" if species == "duck" else "honk", global_position)
		return
	if t_state <= 0.0:
		var c: Vector3 = group.center
		target = c + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		t_state = randf_range(5.0, 14.0)
		if randf() < 0.1:
			Audio.play_at("quack" if species == "duck" else "honk", global_position, -10.0)
	var to := target - global_position
	to.y = 0.0
	if to.length() > 0.5 and WorldData.water_depth_at(target.x, target.z) > 0.25:
		var np := global_position + to.normalized() * 0.5 * delta
		global_position = np
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 2.0))
		rotation.y = yaw
	global_position.y = WorldData.water_level_at(global_position.x, global_position.z) - 0.05


# ------------------------------------------------------------------ flying flocks
func _bird(delta: float) -> void:
	var c: Vector3 = group.center
	if group.get("migrate", false):
		var dir: Vector3 = group.dir
		var off: Vector3 = group.offsets[group.members.find(self)] if group.members.find(self) >= 0 else Vector3.ZERO
		var basis := Basis(Vector3.UP, atan2(dir.x, dir.z))
		global_position = c + basis * off
		rotation.y = atan2(dir.x, dir.z)
		_set_flap(0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.003 + _phase))
		return
	_phase += delta * (0.35 + 0.1 * sin(float(get_instance_id() % 7)))
	var r: float = group.get("radius", 30.0)
	var p := c + Vector3(cos(_phase) * r, sin(_phase * 0.7) * 3.0, sin(_phase) * r)
	var tangent := Vector3(-sin(_phase), 0, cos(_phase))
	global_position = p
	rotation.y = atan2(tangent.x, tangent.z)
	model.rotation.z = -0.35
	_set_flap(0.75 if sin(_phase * 3.0) > -0.3 else 0.0)


# ------------------------------------------------------------------ fish
func _fish(delta: float) -> void:
	var c: Vector3 = group.center
	if t_state <= 0.0:
		for i in 5:
			var p := c + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
			var depth := WorldData.water_depth_at(p.x, p.z)
			if depth > 0.8:
				target = p
				target.y = WorldData.water_level_at(p.x, p.z) - clampf(depth * 0.5, 0.4, 2.5)
				break
		t_state = randf_range(2.0, 6.0)
	var pl: Node3D = Game.player_ref
	var spd := 0.9
	if pl and pl.global_position.distance_to(global_position) < 4.0:
		target = global_position + (global_position - pl.global_position).normalized() * 5.0
		spd = 4.0
	var to := target - global_position
	if to.length() > 0.2:
		global_position += to.normalized() * spd * delta
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 4.0))
		rotation.y = yaw
	if ap:
		ap.speed_scale = spd


# ------------------------------------------------------------------ damage / loot
func take_damage(amount: float, source: Node, _fall := false, knock := 0.0) -> void:
	if dead:
		return
	hp -= amount
	var from: Vector3 = (source as Node3D).global_position if source is Node3D else global_position
	if ap:
		var away := global_position - from
		var side := away.dot(global_transform.basis.x)
		_play("Idle_HitReact_Right" if side > 0.0 else "Idle_HitReact_Left")
		_anim = ""
	if hp <= 0.0:
		_die(source, knock)
		return
	if knock > 0.0 and kind in ["prey", "predator", "farm"]:
		var dir := global_position - from
		dir.y = 0.0
		_knock = dir.normalized() * knock * clampf(2.0 / float(sp.len), 0.4, 1.6)
		_stagger = 0.35 + knock * 0.08
	if kind == "predator" or (sp.has("charge") and randf() < 0.6):
		threat = source as Node3D
		_set_state("attack", 20.0)
	elif kind in ["prey", "farm"]:
		_alarm((source as Node3D).global_position if source is Node3D else global_position)
	elif kind == "water":
		state = "fly"
		t_state = 12.0


func _die(source: Node, knock := 0.0) -> void:
	dead = true
	if knock > 0.0 and source is Node3D and kind in ["prey", "predator", "farm"]:
		var dir := global_position - (source as Node3D).global_position
		dir.y = 0.0
		var np := global_position + dir.normalized() * minf(knock * 0.25, 1.2)
		np.y = WorldData.height_at(np.x, np.z)
		global_position = np
	if body:
		body.collision_layer = 32
	if kind == "water" or kind == "bird":
		global_position.y = WorldData.height_at(global_position.x, global_position.z) if WorldData.water_depth_at(global_position.x, global_position.z) < 0.2 else WorldData.water_level_at(global_position.x, global_position.z)
	if ap and ap.has_animation("Death"):
		ap.play("Death", 0.1)
		ap.animation_finished.connect(func(_n): ap.pause(), CONNECT_ONE_SHOT)
	else:
		model.rotation.z = PI * 0.5
		model.position.y = float(sp.len) * 0.2
		_play("Idle")
	if source == Game.player_ref:
		QUESTS.on_beast_killed(species)
		if kind == "predator":
			Game.kills["beast"] = int(Game.kills.get("beast", 0)) + 1
			var near = WorldData.nearest_settlement(global_position, 300.0)
			if not near.is_empty():
				Game.change_reputation(1.5, "You protected %s from a %s" % [near.name, species])
		if kind == "farm":
			var near2 = WorldData.nearest_settlement(global_position, 300.0)
			if not near2.is_empty():
				Game.commit_crime(near2.name, 10.0, "You slaughtered a villager's %s!" % species)
	manager.animal_died(self)


func is_dead() -> bool:
	return dead


func get_interaction(_p) -> String:
	if dead and not looted:
		return "[E] %s the %s" % ["Gather" if kind in ["fish", "water", "bird"] else "Skin", species]
	return ""


func interact(_p) -> void:
	if not dead or looted:
		return
	looted = true
	var got := []
	for id in sp.get("loot", {}):
		var n := int(sp.loot[id])
		Game.add_item(id, n, false)
		got.append("%d %s" % [n, Items.display_name(id)])
	Game.notify.emit("You take " + ", ".join(got) + ".", "item")
	Audio.play_at("skin", global_position)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 1.2)
	tw.tween_callback(func(): manager.remove_animal(self))
