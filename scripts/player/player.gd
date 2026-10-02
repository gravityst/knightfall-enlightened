class_name Player
extends CharacterBody3D
## First-person player: walking, sprinting, crouching, swimming, riding, survival needs,
## interaction, melee combat, torch and campfires.

signal interaction_changed(text: String)
signal died

const WALK := 4.3
const SPRINT := 7.6
const CROUCH := 2.1
const SWIM := 2.8
const JUMP := 4.6
const GRAVITY := 9.81
const EYE := 1.64
const REACH := 3.2
const FP_OFFSET := Vector3(-0.08, -0.1, 0.16)   # nudges the first-person arms into frame (model space)

var head: Node3D
var cam: Camera3D
var view: Node3D
var _fp: CharacterModel          # first-person arms (the player's own) holding the real items
var _fp_key := ""
var _fp_tree: AnimationTree
var _fp_guard := 0.0             # right arm: 0 hanging (sheathed) .. 1 sword on guard
var _fp_block := 0.0             # left arm: 0 shield/torch held up .. 1 shield pushed out
var _coin_model: Node3D
var torch_light: OmniLight3D
var torch_on := false
var crouching := false
var swimming := false
var head_under := false
var breath := 30.0
var mounted: Node3D = null
var _yaw := 0.0
var _pitch := 0.0
var _bob := 0.0
var _step_acc := 0.0
var _attack_t := 0.0
var _attack_cd := 0.0
var _blocking := false
var _hurt_flash := 0.0
var _shake := 0.0                # camera shake from blows (decays)
var _focus: Node = null
var _focus_text := ""
var _fall_speed := 0.0
var _stat_t := 0.0
var _hp_regen_block := 0.0
var _env_warmth := 60.0
var indoors := false
var _campfires: Array[Node3D] = []
var dead := false
var last_bed := Vector3.INF
var controls_locked := false
var weapon_drawn := false
var _col: CollisionShape3D
# melee: hold the attack button for a heavy blow; raise the shield just as a blow lands to parry it
var _charging := false
var _charge_t := 0.0
var _queued := 0                 # a swing pressed during the last one's recovery (1 light, 2 heavy)
var _power := false              # the swing being resolved is a heavy one
var _combo := 0
var _parry_t := 0.0
var _guard_break := 0.0
var _iframes := 0.0              # dodging: blows miss
var _dodge_cd := 0.0
var _slide_t := 0.0              # lunges, dodges and knock-backs carry momentum for a moment
var _swing_roll := 0.0
var _land_dip := 0.0
var _taps := {}


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 16
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	var col := CollisionShape3D.new()
	_col = col
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	cam = Camera3D.new()
	cam.fov = float(Game.settings.fov)
	cam.near = 0.05
	cam.far = 30000.0
	head.add_child(cam)
	cam.current = true
	view = Node3D.new()
	cam.add_child(view)
	_build_view_model()
	torch_light = OmniLight3D.new()
	torch_light.light_color = Color(1.0, 0.62, 0.3)
	torch_light.light_energy = 2.2
	torch_light.omni_range = 14.0
	torch_light.shadow_enabled = not Assets.compat
	torch_light.visible = false
	torch_light.position = Vector3(-0.35, -0.1, -0.5)
	cam.add_child(torch_light)
	Game.player_ref = self
	Game.settings_changed.connect(func(): cam.fov = float(Game.settings.fov))
	Game.inventory_changed.connect(_refresh_view_model)


func _build_view_model() -> void:
	_coin_model = Assets.instance_sized("res://assets/props/Coin_Pile.gltf", 0.16, "xz")
	view.add_child(_coin_model)
	_coin_model.position = Vector3(0.18, -0.25, -0.42)
	for mi in _coin_model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_refresh_view_model()


## First-person arms: the player's own arms from the character kit, animated by the shared
## library, with the equipped sword in the right fist and the shield on the left forearm.
func _build_fp_arms() -> void:
	var sword_m := CharacterModel.SWORD
	var shield_m := CharacterModel.SHIELD if Game.equipped.shield == "kite_shield" else "res://assets/props/Shield_Wooden.gltf"
	var key := sword_m + shield_m
	if _fp and _fp_key == key:
		return
	if _fp:
		_fp.queue_free()
	_fp_key = key
	_fp = CharacterModel.new()
	_fp.build({"gender": "m", "outfit": "Ranger", "hue": 0.04, "sat": 0.75, "val": 0.7, "steel": 0.25, "pauldron": false, "hood": false,
		"sword": true, "sword_model": sword_m, "shield": true, "shield_model": shield_m, "torch": true})
	if _fp.sheath_node:
		_fp.sheath_node.queue_free()
		_fp.sheath_node = null
	if _fp.torch_light:
		_fp.torch_light.visible = false     # the player's own torch light does the lighting
	for m in _fp.meshes:
		m.visible = String(m.name).contains("Arms")
	for gi in _fp.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(_fp)
	_fp_tree = _arm_tree(_fp)
	# put the model's eyes at the camera, facing down the view (-Z)
	var hb := _fp.skeleton.find_bone("Head")
	var eye := _fp.skeleton.get_bone_global_rest(hb).origin + Vector3(0, 0.08, 0.1)
	_fp.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * Transform3D(Basis(), -eye + FP_OFFSET)


func _make_flame() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.5
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	curve.curve = c
	pm.scale_curve = curve
	var grad := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	g.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	grad.gradient = g
	pm.color_ramp = grad
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.4, 1.0, 0.6)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _refresh_view_model() -> void:
	var sword: bool = weapon_drawn and Game.equipped.weapon != "" and not holding_coin()
	_coin_model.visible = holding_coin()
	if not (sword or torch_on):
		if _fp:
			_fp.visible = false
			_fp_tree.active = false      # no animation work while the arms are hidden
		return
	_build_fp_arms()
	_fp.visible = true
	_fp_tree.active = true
	_fp.armed = sword
	_fp.draw_weapon(sword)
	if _fp.shield_node:
		_fp.shield_node.visible = sword and Game.equipped.shield != "" and not torch_on
	if _fp.torch_node:
		_fp.torch_node.visible = torch_on
	_fp_pose(true)


## Each arm has its own pose: the right comes up on guard when the sword is drawn (and thrusts on
## attack), the left holds the shield or torch up and pushes the shield out to block.
func _arm_tree(m: CharacterModel) -> AnimationTree:
	var bt := AnimationNodeBlendTree.new()
	var anims := {"down": "Idle", "guard": "Pistol_Aim_Neutral", "hold": "Idle_Torch", "brace": "Spell_Simple_Idle", "lunge": "Sword_Attack"}
	for k in anims:
		var a := AnimationNodeAnimation.new()
		a.animation = anims[k]
		bt.add_node(k, a)
	var right := AnimationNodeBlend2.new()
	var left := AnimationNodeBlend2.new()
	var arms := AnimationNodeBlend2.new()
	var thrust := AnimationNodeOneShot.new()
	var pace := AnimationNodeTimeScale.new()
	arms.filter_enabled = true
	thrust.filter_enabled = true
	thrust.fadein_time = 0.04
	thrust.fadeout_time = 0.16
	for i in m.skeleton.get_bone_count():
		var b := m.skeleton.get_bone_name(i)
		var arm := b.begins_with("clavicle") or b.begins_with("upperarm") or b.begins_with("lowerarm") or b.begins_with("hand") \
			or b.begins_with("thumb") or b.begins_with("index") or b.begins_with("middle") or b.begins_with("ring") or b.begins_with("pinky")
		if arm and b.ends_with("_l"):
			arms.set_filter_path(NodePath("Armature/Skeleton3D:" + b), true)
		elif arm and b.ends_with("_r"):
			thrust.set_filter_path(NodePath("Armature/Skeleton3D:" + b), true)
	bt.add_node("right", right)
	bt.add_node("left", left)
	bt.add_node("arms", arms)
	bt.add_node("pace", pace)
	bt.add_node("thrust", thrust)
	bt.connect_node("right", 0, "down")
	bt.connect_node("right", 1, "guard")
	bt.connect_node("left", 0, "hold")
	bt.connect_node("left", 1, "brace")
	bt.connect_node("arms", 0, "right")
	bt.connect_node("arms", 1, "left")
	bt.connect_node("pace", 0, "lunge")
	bt.connect_node("thrust", 0, "arms")
	bt.connect_node("thrust", 1, "pace")
	bt.connect_node("output", 0, "thrust")
	var tree := AnimationTree.new()
	tree.add_animation_library("", CharacterModel.library())
	m.root_scene.add_child(tree)
	tree.root_node = NodePath("..")
	tree.tree_root = bt
	m.anim.active = false
	tree.active = true
	tree.set("parameters/arms/blend_amount", 1.0)
	tree.set("parameters/pace/scale", 2.2)   # the downward cut crosses the view as the hit lands
	return tree


func _fp_pose(force := false) -> void:
	if _fp == null or not _fp.visible or _fp_tree == null:
		return
	var d := 1.0 if force else minf(get_process_delta_time() * 9.0, 1.0)
	_fp_guard = lerpf(_fp_guard, 1.0 if _fp.armed else 0.0, d)
	_fp_block = lerpf(_fp_block, 1.0 if _blocking else 0.0, d)
	_fp_tree.set("parameters/right/blend_amount", _fp_guard)
	_fp_tree.set("parameters/left/blend_amount", _fp_block)


func holding_coin() -> bool:
	return Game.holding_coin and Game.gold() > 0


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if controls_locked or Game.in_menu or dead:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		for a in ["move_left", "move_right", "move_back"]:
			if event.is_action(a):      # double-tap a direction to dodge that way
				var now := Time.get_ticks_msec()
				if now - int(_taps.get(a, -1000)) < 260:
					_dodge({"move_left": Vector2(-1, 0), "move_right": Vector2(1, 0), "move_back": Vector2(0, 1)}[a])
					_taps[a] = -1000
				else:
					_taps[a] = now
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := float(Game.settings.mouse_sensitivity)
		_yaw -= event.relative.x * s
		_pitch -= event.relative.y * s * (-1.0 if Game.settings.invert_y else 1.0)
		_pitch = clampf(_pitch, -1.5, 1.5)
	elif event.is_action_pressed("interact"):
		_do_interact()
	elif event.is_action_pressed("attack") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_press_attack()
	elif event.is_action_released("attack"):
		_release_attack()
	elif event.is_action_pressed("block"):
		_parry_t = 0.24
	elif event.is_action_pressed("dodge"):
		_dodge(Input.get_vector("move_left", "move_right", "move_forward", "move_back"))
	elif event.is_action_pressed("torch"):
		toggle_torch()
	elif event.is_action_pressed("draw_weapon"):
		weapon_drawn = not weapon_drawn
		Audio.play_at("unsheathe" if weapon_drawn else "sheathe", global_position)
		_refresh_view_model()
	elif event.is_action_pressed("hold_coin"):
		if Game.gold() <= 0:
			Game.notify.emit("You have no gold coins to hold out.", "warn")
		else:
			Game.holding_coin = not Game.holding_coin
			Game.notify.emit("You hold out a gold coin." if Game.holding_coin else "You pocket the coin.", "info")
			_refresh_view_model()
	elif event.is_action_pressed("call_horse"):
		if Game.world_ref:
			Game.world_ref.call("call_horse")
	elif event.is_action_pressed("wait"):
		if Game.world_ref:
			Game.world_ref.call("wait_hour")
	elif event.is_action_pressed("photo_mode"):
		if Game.world_ref:
			Game.world_ref.call("take_screenshot")
	else:
		for k in 4:
			if event.is_action_pressed("hot_%d" % (k + 1)):
				quick_use(k)


## Number keys: 1 eats the best-fitting ready food, 2 drinks, 3 treats wounds, 4 makes camp.
func quick_use(slot: int) -> void:
	var stat: String = ["hunger", "thirst", "health", "health"][slot]
	var missing: float = (Game.max_health if stat == "health" else 100.0) - float(Game.stats[stat])
	var best := ""
	var best_v := -INF
	for id in Game.inventory.keys():
		var it := Items.get_item(id)
		var v := -INF
		match slot:
			0:
				if it.type == "food" and not it.has("cookable") and not it.has("health"):
					v = -absf(float(it.get("hunger", 0)) - missing)
			1:
				if id == "waterskin":
					v = 1000.0 if Game.waterskin_charges > 0 else -INF
				elif it.type == "drink":
					v = -absf(float(it.get("thirst", 0)) - missing)
			2:
				if it.has("health"):
					v = -absf(float(it.health) - missing)
			3:
				if id == "campfire_kit":
					v = 0.0
		if v > best_v:
			best_v = v
			best = id
	if best == "":
		Game.notify.emit(["You have nothing ready to eat.", "You have nothing to drink.", "You have nothing to treat your wounds with.", "You have no campfire kit."][slot], "warn")
		return
	var msg := Game.use_item(best)
	if msg != "":
		Game.notify.emit(msg, "info")


func toggle_torch() -> void:
	if not torch_on and not Game.has_item("torch"):
		Game.notify.emit("You have no torch.", "warn")
		return
	torch_on = not torch_on
	torch_light.visible = torch_on
	_refresh_view_model()


# ------------------------------------------------------------------ physics
func _physics_process(delta: float) -> void:
	if dead:
		return
	head.rotation.x = _pitch
	rotation.y = _yaw
	if mounted:
		_ride(delta)
	else:
		_move(delta)
	_update_camera_fx(delta)
	_update_focus()
	_combat(delta)
	_needs(delta)


func _move(delta: float) -> void:
	var p := global_position
	var wl := WorldData.water_level_at(p.x, p.z)
	var ground := WorldData.height_at(p.x, p.z)
	var water_depth := wl - ground
	swimming = water_depth > 1.25 and p.y < wl - 1.0
	head_under = cam.global_position.y < wl - 0.05 and water_depth > 0.3
	var input := Vector2.ZERO
	if not controls_locked and not Game.in_menu:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_h := Basis(Vector3.UP, _yaw)
	var wish := basis_h * Vector3(input.x, 0, input.y)
	var stamina := float(Game.stats.stamina)
	var sprinting := Input.is_action_pressed("sprint") and input.y < -0.1 and stamina > 3.0 and not crouching
	crouching = Input.is_action_pressed("crouch") and not swimming
	if swimming:
		var dir := (cam.global_transform.basis * Vector3(input.x, 0, input.y))
		var spd := SWIM * (1.5 if sprinting else 1.0)
		var target := dir * spd
		if Input.is_action_pressed("jump"):
			target.y = 2.2
		elif Input.is_action_pressed("crouch"):
			target.y = -2.2
		else:
			# buoyancy keeps the head near the surface
			target.y += clampf((wl - 1.35) - p.y, -1.0, 1.0) * 2.0
		velocity = velocity.lerp(target, 1.0 - exp(-delta * 3.0))
		if sprinting:
			Game.change_stat("stamina", -delta * 6.0)
	else:
		var speed := WALK
		if sprinting:
			speed = SPRINT
			Game.change_stat("stamina", -delta * 9.0)
		elif crouching:
			speed = CROUCH
		if water_depth > 0.4:
			speed *= 0.65
		if _blocking:
			speed *= 0.55
		var acc := 10.0 if is_on_floor() else 2.5
		if _slide_t > 0.0:
			acc = 1.3          # carried by a lunge, dodge or knock-back
		var hv := Vector3(velocity.x, 0, velocity.z).lerp(wish * speed, 1.0 - exp(-delta * acc))
		velocity.x = hv.x
		velocity.z = hv.z
		if is_on_floor():
			if _fall_speed < -3.0:
				_land_dip = clampf(-_fall_speed * 0.011, 0.02, 0.16)
			if _fall_speed < -13.0:
				var dmg := (absf(_fall_speed) - 13.0) * 7.0
				take_damage(dmg, null, true)
			_fall_speed = 0.0
			if Input.is_action_just_pressed("jump") and not controls_locked and not Game.in_menu and stamina > 5.0:
				velocity.y = JUMP
				Game.change_stat("stamina", -6.0)
		else:
			velocity.y -= GRAVITY * delta
			_fall_speed = minf(_fall_speed, velocity.y)
		if is_on_floor() and hv.length() > 0.5:
			_step_acc += hv.length() * delta
			if _step_acc > (2.2 if sprinting else 1.6):
				_step_acc = 0.0
				Audio.footstep(global_position, _surface(), sprinting)
	_slide_t = maxf(_slide_t - delta, 0.0)
	var pre_vel := velocity
	move_and_slide()
	_step_up(pre_vel, delta)
	for i in get_slide_collision_count():      # shoulder loose things aside
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb and rb.has_method("wake"):
			rb.call("wake", -c.get_normal() * minf(Vector2(pre_vel.x, pre_vel.z).length(), 6.0) * 0.15)
	# never fall through the world
	var g := WorldData.height_at(global_position.x, global_position.z)
	if global_position.y < g - 2.0 and not indoors:
		global_position.y = g + 0.1
		velocity.y = 0.0
	if not WorldData.is_inside_map(global_position.x, global_position.z):
		global_position.x = clampf(global_position.x, -WorldData.HALF + 12.0, WorldData.HALF - 12.0)
		global_position.z = clampf(global_position.z, -WorldData.HALF + 12.0, WorldData.HALF - 12.0)


## Lets the player climb thresholds, plinths, steps and small rocks (up to 0.5 m).
func _step_up(pre_vel: Vector3, delta: float) -> void:
	if swimming or not is_on_wall() or get_wall_normal().y > 0.2:
		return       # real steps only: steep slopes and rock faces are not stairs
	var h := Vector3(pre_vel.x, 0, pre_vel.z)
	if h.length() < 0.5:
		return
	var motion := h.normalized() * maxf(h.length() * delta, 0.12)
	var start := global_transform
	for step in [0.25, 0.5]:
		var up := Vector3(0, step, 0)
		if test_move(start, up):
			continue
		var raised := start.translated(up)
		if test_move(raised, motion):
			continue
		global_position = raised.origin + motion
		velocity.y = 0.0
		apply_floor_snap()
		return


func _surface() -> String:
	var p := global_position
	if WorldData.water_depth_at(p.x, p.z) > 0.05:
		return "water"
	if indoors:
		return "wood"
	var b := WorldData.biome_at(p.x, p.z)
	match b:
		WorldData.Biome.SNOW, WorldData.Biome.TUNDRA:
			return "snow" if Game.world_ref and float(Game.world_ref.atmosphere.snow) > 0.2 or b == WorldData.Biome.SNOW else "grass"
		WorldData.Biome.DESERT, WorldData.Biome.BEACH:
			return "sand"
		WorldData.Biome.MOUNTAIN:
			return "stone"
	return "grass"


## The horse shied or crashed: the rider is jolted (and hurt at a full gallop).
func horse_jolt(spd: float) -> void:
	_shake = minf(_shake + 0.3 + spd * 0.04, 1.0)
	if spd > 12.5:
		take_damage((spd - 12.5) * 4.0, null, true)


func _ride(delta: float) -> void:
	var seat: Transform3D = mounted.call("seat_transform")
	global_position = seat.origin
	velocity = Vector3.ZERO
	var input := Vector2.ZERO
	if not controls_locked and not Game.in_menu:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	mounted.call("rider_input", input, Input.is_action_pressed("sprint"), Input.is_action_just_pressed("jump"), _yaw, delta)


func mount(horse: Node3D) -> void:
	mounted = horse
	_col.disabled = true
	_yaw = horse.global_rotation.y + PI
	Game.notify.emit("W rides on at a canter, Shift gallops, Ctrl keeps to a walk, S reins in. E to dismount.", "info")


func dismount() -> void:
	if mounted == null:
		return
	if absf(float(mounted.get("speed"))) > 4.5 and not dead:
		Game.notify.emit("Rein in first - you can't jump off at this speed.", "warn")
		return
	var side: Vector3 = mounted.global_transform.basis.x * 1.4
	var p := mounted.global_position + side
	p.y = maxf(WorldData.height_at(p.x, p.z), mounted.global_position.y) + 0.2
	mounted.call("set_rider", null)
	mounted = null
	global_position = p
	_col.disabled = false


# ------------------------------------------------------------------ camera
func _update_camera_fx(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var eye := EYE - (0.55 if crouching else 0.0)
	if mounted:
		eye = 0.0
	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-delta * 7.0))
	head.position.y = lerpf(head.position.y, eye - _land_dip, 1.0 - exp(-delta * 14.0))
	var ride := {}
	if mounted:
		ride = mounted.call("rider_motion")
	if mounted and Game.settings.head_bob:
		cam.position = cam.position.lerp(ride.bob, 1.0 - exp(-delta * 18.0))
	elif Game.settings.head_bob and is_on_floor() and hspeed > 0.5:
		_bob += delta * hspeed * 1.9
		cam.position = Vector3(sin(_bob * 0.5) * 0.03, absf(sin(_bob)) * 0.045, 0)
	else:
		cam.position = cam.position.lerp(Vector3.ZERO, 1.0 - exp(-delta * 6.0))
	# weapon sway; drawing back for a heavy blow
	var charge := clampf(_charge_t / 0.4, 0.0, 1.0) if _charging else 0.0
	var sway := Vector3(sin(_bob * 0.5) * 0.008, -absf(sin(_bob)) * 0.01, 0) if hspeed > 0.5 and not mounted else Vector3.ZERO
	view.position = view.position.lerp(sway + Vector3(0.02, 0.03, 0.09) * charge, 1.0 - exp(-delta * 8.0))
	var fov := float(Game.settings.fov) - charge * 5.0
	if mounted:
		fov += clampf((float(mounted.get("speed")) - 7.0) / 7.0, 0.0, 1.0) * 5.0   # the rush of a gallop
	cam.fov = lerpf(cam.fov, fov, 1.0 - exp(-delta * 8.0))
	_fp_pose()
	_hurt_flash = maxf(_hurt_flash - delta * 2.0, 0.0)
	# a blow jolts the view (squared so small knocks stay subtle)
	_shake = maxf(_shake - delta * 2.2, 0.0)
	var k := _shake * _shake
	cam.h_offset = randf_range(-1.0, 1.0) * k * 0.05
	cam.v_offset = randf_range(-1.0, 1.0) * k * 0.04
	_swing_roll = lerpf(_swing_roll, 0.0, 1.0 - exp(-delta * 7.0))
	cam.rotation.z = randf_range(-1.0, 1.0) * k * 0.03 + _swing_roll + (float(ride.roll) if mounted else 0.0)
	cam.rotation.x = float(ride.pitch) if mounted else 0.0
	if torch_on:
		torch_light.light_energy = 2.1 + sin(Time.get_ticks_msec() * 0.023) * 0.15 + sin(Time.get_ticks_msec() * 0.051) * 0.1
	RenderingServer.global_shader_parameter_set("player_pos", global_position)
	RenderingServer.global_shader_parameter_set("cam_pos", cam.global_position)


# ------------------------------------------------------------------ interaction
func _update_focus() -> void:
	var space := get_world_3d().direct_space_state
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 8 | 16 | 32)
	q.exclude = [get_rid()]
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	var target: Node = null
	if hit:
		var n: Node = hit.collider
		while n != null and not n.has_method("get_interaction"):
			n = n.get_parent()
		target = n
	var text := ""
	if mounted and target == null:
		text = "[E] Dismount"
	elif target:
		var info = target.call("get_interaction", self)
		text = String(info) if info != null else ""
	# water: drink / refill
	if text == "" and not mounted:
		var look := cam.global_transform.basis.z
		if look.y > 0.35:
			var p := global_position - Vector3(look.x, 0, look.z).normalized() * 1.2
			if WorldData.water_depth_at(p.x, p.z) > 0.05 and absf(WorldData.water_level_at(p.x, p.z) - global_position.y) < 1.4:
				text = "[E] Drink" + (" / refill waterskin" if Game.has_item("waterskin") else "")
				target = self
	_focus = target
	if text != _focus_text:
		_focus_text = text
		interaction_changed.emit(text)


func get_interaction(_p) -> String:
	return "[E] Drink"


func _do_interact() -> void:
	if mounted and (_focus == null or _focus == mounted):
		dismount()
		return
	if _focus == self:
		Game.change_stat("thirst", 35.0)
		var wl := WorldData.water_level_at(global_position.x, global_position.z)
		if wl < 0.5 and WorldData.biome_at(global_position.x, global_position.z) in [WorldData.Biome.OCEAN, WorldData.Biome.BEACH]:
			Game.change_stat("thirst", -30.0)
			Game.notify.emit("Salt water! You spit it out.", "warn")
			return
		if Game.has_item("waterskin"):
			Game.waterskin_charges = 5
		Game.notify.emit("You drink the cool water" + (" and refill your waterskin." if Game.has_item("waterskin") else "."), "info")
		Audio.play_at("drink", global_position)
		return
	if _focus and _focus.has_method("interact"):
		_focus.call("interact", self)


# ------------------------------------------------------------------ combat
## Left button: a quick cut on release, or hold it to draw back for a heavy blow (more damage,
## breaks a shield guard, knocks foes back). Blows can be thrown from horseback too.
func _press_attack() -> void:
	if swimming or holding_coin() or Game.equipped.weapon == "":
		return
	if not weapon_drawn:
		weapon_drawn = true
		_refresh_view_model()
		Audio.play_at("unsheathe", global_position)
		_attack_cd = 0.35
		return
	_charging = true
	_charge_t = 0.0


func _release_attack() -> void:
	if not _charging:
		return
	_charging = false
	_swing(_charge_t >= 0.4)


func _swing(power: bool) -> void:
	if _attack_cd > 0.0:
		_queued = 2 if power else 1      # buffered: it lands as soon as the last blow recovers
		return
	var cost := 24.0 if power else 11.0
	if float(Game.stats.stamina) < cost * 0.6:
		Game.notify.emit("Too exhausted to swing.", "warn")
		return
	_power = power
	_combo = 1 - _combo
	_attack_t = 0.6 if power else 0.45
	_attack_cd = 0.9 if power else 0.52
	Game.change_stat("stamina", -cost)
	Audio.play_at("swing", global_position, 2.0 if power else 0.0, 0.82 if power else 1.0)
	if _fp and _fp.visible and _fp_tree:
		# a slash: the downward cut sweeps across the view as the hit is resolved
		_fp_tree.set("parameters/pace/scale", 1.8 if power else 2.2)
		_fp_tree.set("parameters/thrust/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_swing_roll = (0.055 if power else 0.03) * (1.0 if _combo == 0 else -1.0)
	if not mounted and is_on_floor():
		var sprint_lunge: bool = Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > 5.5
		_kick(-global_transform.basis.z * (4.5 if sprint_lunge else (3.0 if power else 1.3)), 0.14)
	if Game.world_ref:
		Game.world_ref.npcs.call("incoming_blow", self, power)
	get_tree().create_timer(0.22 if power else 0.16).timeout.connect(_resolve_hit)


func _resolve_hit() -> void:
	if dead:
		return
	var power := _power
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 1.7 if mounted else (1.5 if power else 1.35)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), cam.global_position - cam.global_transform.basis.z * (1.9 if mounted else 1.45))
	q.collision_mask = 4 | 8 | 16 | 32
	var ex: Array[RID] = [get_rid()]
	if mounted:
		ex.append((mounted as CollisionObject3D).get_rid())
	q.exclude = ex
	var hits := space.intersect_shape(q, 10)
	var done := {}
	var landed := false
	for h in hits:
		var n: Node = h.collider
		if n is RigidBody3D:            # loose things go flying
			var kick := (-cam.global_transform.basis.z + Vector3.UP * 0.4) * (4.0 if power else 2.0)
			if n.has_method("wake"):
				n.call("wake", kick)
			else:
				(n as RigidBody3D).apply_central_impulse(kick)
			continue
		while n != null and not n.has_method("take_damage"):
			n = n.get_parent()
		if n == null or done.has(n) or n == self or n == mounted or (n.has_method("is_dead") and n.call("is_dead")):
			continue
		done[n] = true
		var mult := 1.9 if power else 1.0
		var note := ""
		if mounted:
			mult *= 1.0 + clampf(float(mounted.get("speed")) / 14.0, 0.0, 1.0) * 0.8
		elif crouching and _unaware(n):
			mult *= 2.5
			note = "Sneak attack!"
		var dmg := Game.weapon_damage() * mult * randf_range(0.88, 1.12)
		var knock := (4.0 if power else 1.4) + (2.0 if mounted else 0.0)
		var at: Vector3 = (n as Node3D).global_position + Vector3(0, 1.15 if n is NPC else 0.6, 0)
		var away := (at - cam.global_position).normalized()
		var res = n.call("take_damage", dmg, self, false, knock)
		if res is bool and not res:
			# turned aside by a raised shield
			Audio.play_at("block", at)
			FireFX.burst(get_tree().current_scene, at - away * 0.4, "sparks", -away + Vector3.UP * 0.6)
			_shake = minf(_shake + 0.3, 1.0)
			Game.change_stat("stamina", -6.0)
			_combat_text("Blocked", Color(0.85, 0.82, 0.74))
			continue
		landed = true
		# steel rings on the watch's mail; everything else bleeds
		var armoured: bool = n is NPC and (n as NPC).data.role in ["knight", "guard"]
		Audio.play_at("hit_metal" if armoured else ("hit_heavy" if power else "hit_flesh"), at)
		FireFX.burst(get_tree().current_scene, at - away * 0.25, "sparks" if armoured else "blood", -away + Vector3.UP * 0.6)
		if note != "":
			_combat_text(note, Color(1.0, 0.75, 0.4))
		if Game.world_ref:
			Game.world_ref.hud.call("show_target", n)
	if landed:
		if Game.world_ref:
			Game.world_ref.hud.call("hit_marker")
		_hitstop(0.09 if power else 0.05)
		_shake = minf(_shake + (0.22 if power else 0.1), 1.0)


func _unaware(n: Node) -> bool:
	if n is NPC:
		return (n as NPC).target != self and not (n as NPC).pursuing
	if n is Animal:
		return (n as Animal).state in ["idle", "eat", "wander"]
	return false


## A fraction of a second of slowed time when a blow connects, so hits land with weight.
func _hitstop(secs: float) -> void:
	if Engine.time_scale < 0.99:
		return
	Engine.time_scale = 0.08
	get_tree().create_timer(secs, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func _kick(v: Vector3, slide: float) -> void:
	velocity.x += v.x
	velocity.z += v.z
	_slide_t = maxf(_slide_t, slide)


## A quick side- or back-step (double-tap A, D or S, or Alt): blows miss you while you move.
func _dodge(d: Vector2) -> void:
	if mounted or swimming or dead or controls_locked or Game.in_menu or not is_on_floor() or _dodge_cd > 0.0:
		return
	if float(Game.stats.stamina) < 12.0:
		return
	if d.length() < 0.1:
		d = Vector2(0, 1)
	var dir := Basis(Vector3.UP, _yaw) * Vector3(d.x, 0, d.y).normalized()
	_kick(dir * 8.0, 0.26)
	velocity.y = 1.8
	_iframes = 0.34
	_dodge_cd = 0.65
	_land_dip = 0.06
	Game.change_stat("stamina", -14.0)
	Audio.play_at("whoosh", global_position, 0.0)


func _combat_text(t: String, col: Color) -> void:
	if Game.world_ref:
		Game.world_ref.hud.call("combat_text", t, col)


func _combat(delta: float) -> void:
	_attack_t = maxf(_attack_t - delta, 0.0)
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_parry_t = maxf(_parry_t - delta, 0.0)
	_guard_break = maxf(_guard_break - delta, 0.0)
	_iframes = maxf(_iframes - delta, 0.0)
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	if _charging:
		_charge_t += delta
		if not Input.is_action_pressed("attack"):
			_release_attack()        # the release happened while a menu or the mouse was elsewhere
	if _queued > 0 and _attack_cd <= 0.0:
		var p := _queued == 2
		_queued = 0
		_swing(p)
	_blocking = weapon_drawn and Input.is_action_pressed("block") and Game.equipped.shield != "" and not torch_on and not mounted and not Game.in_menu \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _guard_break <= 0.0


func take_damage(amount: float, source: Node, fall := false, _knock := 0.0) -> void:
	if dead:
		return
	var dmg := amount
	var blocked := false
	if not fall:
		if _iframes > 0.0 and source is Node3D:
			return       # stepped clear of the blow
		if _blocking and source is Node3D:
			var to_src := ((source as Node3D).global_position - global_position).normalized()
			if to_src.dot(-global_transform.basis.z) > 0.3:
				var shield_at := cam.global_position - cam.global_transform.basis.z * 0.55 + cam.global_transform.basis.x * -0.2
				if _parry_t > 0.0:
					# raised just in time: the blow is turned aside and the attacker reels
					Audio.play_at("parry", global_position, 3.0)
					Audio.play_at("block", global_position)
					FireFX.burst(get_tree().current_scene, shield_at, "sparks", to_src)
					FireFX.burst(get_tree().current_scene, shield_at + Vector3.UP * 0.1, "sparks", to_src + Vector3.UP)
					_hitstop(0.08)
					Game.change_stat("stamina", -4.0)
					if source.has_method("parried"):
						source.call("parried", self)
					_combat_text("Parried!", Color(1.0, 0.85, 0.45))
					return
				blocked = true
				dmg *= 1.0 - Game.shield_block()
				Game.change_stat("stamina", -amount * 0.6)
				Audio.play_at("block", global_position)
				FireFX.burst(get_tree().current_scene, shield_at, "sparks", to_src)
				if float(Game.stats.stamina) <= 0.5:
					_guard_break = 1.4
					_shake = 0.8
					_combat_text("Guard broken!", Color(1.0, 0.5, 0.4))
		dmg *= 1.0 - Game.armor_value()
		if source is Node3D:
			if source is NPC and not blocked:
				Audio.play_at("hit_flesh", global_position + Vector3.UP * 1.2)
			if Game.world_ref:
				Game.world_ref.hud.call("damage_from", (source as Node3D).global_position)
			var push := global_position - (source as Node3D).global_position
			push.y = 0.0
			if dmg > 6.0 and mounted == null and push.length() > 0.01:
				_kick(push.normalized() * minf(dmg * 0.16, 4.5), 0.16)     # heavy blows shove you back
	Game.change_stat("health", -dmg)
	_hurt_flash = 1.0
	_shake = minf(_shake + 0.25 + dmg * 0.035, 1.0)
	if Game.world_ref:
		Game.world_ref.call("player_hurt", dmg)
	if float(Game.stats.health) <= 0.0:
		_die()


func _die() -> void:
	dead = true
	if mounted:
		dismount()
	died.emit()


func is_dead() -> bool:
	return dead


func respawn(at: Vector3) -> void:
	dead = false
	global_position = at
	velocity = Vector3.ZERO
	Game.stats.health = 60.0
	Game.stats.stamina = 60.0
	Game.stats.hunger = maxf(float(Game.stats.hunger), 40.0)
	Game.stats.thirst = maxf(float(Game.stats.thirst), 40.0)
	Game.stats.warmth = maxf(float(Game.stats.warmth), 50.0)
	Game.stats_changed.emit()


# ------------------------------------------------------------------ survival
func _needs(delta: float) -> void:
	_stat_t += delta
	if _stat_t < 0.25:
		return
	var dt := _stat_t
	_stat_t = 0.0
	var gh := dt * Game.minutes_per_second() / 60.0   # game hours elapsed
	var p := global_position
	var temp := WorldData.temperature_at(p.x, p.z)
	var desert := WorldData.biome_at(p.x, p.z) == WorldData.Biome.DESERT
	var t := Game.time_of_day()
	var night := Game.is_night()
	var atm: Atmosphere = Game.world_ref.atmosphere if Game.world_ref else null
	# environment warmth (0 freezing .. 100 scorching)
	var env := 15.0 + temp * 80.0
	env -= 12.0 if night else 0.0
	if desert and t > 10.0 and t < 17.0:
		env += 12.0
	if atm:
		if atm.weather in ["rain", "storm"]: env -= 8.0
		if atm.weather == "snow": env -= 12.0
		if atm.weather == "blizzard": env -= 24.0
		env -= atm.wetness * 6.0
	if swimming or head_under:
		env -= 18.0
	if indoors:
		env = maxf(env, 52.0)
	if is_near_fire():
		env = maxf(env, 70.0)
	var ins := Game.insulation()
	var target := env + (ins * 0.7 if env < 55.0 else -ins * 0.15)
	_env_warmth = target
	var w := float(Game.stats.warmth)
	Game.stats.warmth = clampf(w + (target - w) * minf(gh * 0.9, 1.0), 0.0, 100.0)
	# hunger / thirst
	var thirst_rate := 5.0
	if desert and not indoors:
		var heat := 1.7
		if Game.equipped.cloak == "desert_robes": heat = 1.25
		thirst_rate *= heat
	if float(Game.stats.warmth) > 85.0:
		thirst_rate *= 1.4
	Game.stats.hunger = maxf(float(Game.stats.hunger) - gh * 3.6, 0.0)
	Game.stats.thirst = maxf(float(Game.stats.thirst) - gh * thirst_rate, 0.0)
	# stamina regen
	var sprinting := Input.is_action_pressed("sprint") and velocity.length() > 5.0
	if not sprinting and _attack_t <= 0.0:
		var regen := 14.0 if float(Game.stats.hunger) > 15.0 else 5.0
		Game.stats.stamina = minf(float(Game.stats.stamina) + dt * regen, 100.0)
	# health
	var hp_loss := 0.0
	if float(Game.stats.hunger) <= 0.0: hp_loss += 6.0
	if float(Game.stats.thirst) <= 0.0: hp_loss += 9.0
	if float(Game.stats.warmth) < 18.0: hp_loss += 10.0
	if head_under:
		breath -= dt
		if breath <= 0.0: hp_loss += 240.0
	else:
		breath = minf(breath + dt * 4.0, 30.0)
	if hp_loss > 0.0:
		Game.change_stat("health", -hp_loss * gh)
		if float(Game.stats.health) <= 0.0:
			_die()
	elif float(Game.stats.hunger) > 30.0 and float(Game.stats.thirst) > 30.0 and float(Game.stats.warmth) > 30.0:
		Game.stats.health = minf(float(Game.stats.health) + gh * 4.0, Game.max_health)
	Game.stats_changed.emit()


func is_near_fire() -> bool:
	if Game.world_ref and Game.world_ref.call("fire_near", global_position, 6.0):
		return true
	return false


func warmth_target() -> float:
	return _env_warmth


func place_campfire() -> void:
	var p := global_position - global_transform.basis.z * 1.8
	p.y = WorldData.height_at(p.x, p.z)
	if Game.world_ref:
		Game.world_ref.call("spawn_campfire", p)


func sleep_outdoors() -> String:
	if Game.world_ref:
		var why := String(Game.world_ref.call("rest_blocked"))
		if why != "":
			return why
		Game.world_ref.call("sleep", 8.0, false)
	return ""


func hurt_flash() -> float:
	return _hurt_flash


func get_save_state() -> Dictionary:
	return {"x": global_position.x, "y": global_position.y, "z": global_position.z, "yaw": _yaw, "pitch": _pitch}


func set_save_state(d: Dictionary) -> void:
	global_position = Vector3(float(d.x), float(d.y), float(d.z))
	_yaw = float(d.get("yaw", 0.0))
	_pitch = float(d.get("pitch", 0.0))


func set_look(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch
	rotation.y = yaw
	head.rotation.x = pitch
