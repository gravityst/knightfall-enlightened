class_name NPC
extends CharacterBody3D
## A spawned townsperson: follows the routine chosen by the NPC manager, walks the
## settlement path network (opening doors), works / sits / sleeps at spots, talks,
## fights or flees, and dies.

var data: NPCManager.NPCData
var manager: NPCManager
var model: CharacterModel
var path := PackedVector3Array()
var path_i := 0
var speed := 1.35
var arrive_anim := "Idle"
var arrive_yaw := 0.0
var arrive_pos := Vector3.ZERO
var activity := ""
var _think := 0.0
var _yaw := 0.0
var _attack_cd := 0.0
var _greet_cd := 0.0
var target: Node3D = null
var fleeing := false
var pursuing := false          # the watch closing in to arrest the player
var _confront_cd := 0.0
var _route := PackedVector3Array()   # detour through doorways while chasing
var _route_i := 0
var _route_t := 0.0
var dead := false
var talking := false
var mount: Node3D = null
var _dead_t := 0.0
var _stuck_t := 0.0
var _shadow_t := 0.0
var _anim_lod := 0.0
var _anim_far := false
# melee
var _stagger := 0.0             # reeling from a blow or a parry: no attacks
var _swing := 0                 # id of the blow being wound up (a stagger cancels it)
var _swinging := 0.0
var blocking := 0.0             # shield raised
var _recover := 0.0             # stepping back after a blow
var _knock := Vector3.ZERO


func setup(d: NPCManager.NPCData, m: NPCManager) -> void:
	data = d
	manager = m
	name = "NPC_%d" % d.id
	collision_layer = 4
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.76
	cs.shape = cap
	cs.position.y = 0.88
	add_child(cs)
	model = CharacterModel.new()
	add_child(model)
	var look := d.look.duplicate()
	look["torch"] = d.role == "guard" and Game.is_night()   # knights keep their left arm for the shield
	model.build(look)
	model.finalize(d.gender == "f")
	global_position = d.pos
	_yaw = d.yaw
	model.rotation.y = _yaw
	_think = randf() * 0.5


func _process(delta: float) -> void:
	if _anim_far and model and model.anim:
		_anim_lod += delta
		if _anim_lod >= 0.125:
			model.anim.advance(_anim_lod)
			_anim_lod = 0.0


func _physics_process(delta: float) -> void:
	if dead:
		_dead_t += delta
		if _dead_t > 180.0:
			manager.despawn(data)
		return
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_greet_cd = maxf(_greet_cd - delta, 0.0)
	_think -= delta
	if _think <= 0.0:
		_think = 0.6 + randf() * 0.3
		_decide()
	if mount:
		return
	var fighting := target != null and is_instance_valid(target) and (data.hostile or data.role in ["knight", "guard"])
	if model.armed != fighting:
		model.armed = fighting     # draw the sword for a fight, sheathe it after
		model.current = ""
	if fighting:
		_combat(delta)
		return
	if pursuing:
		_pursue(delta)
		return
	_follow_path(delta)
	_lod(delta)


func _lod(delta: float) -> void:
	_shadow_t -= delta
	if _shadow_t > 0.0:
		return
	_shadow_t = 1.0
	var p: Node3D = Game.player_ref
	if p == null:
		return
	var d := p.global_position.distance_to(global_position)
	if Assets.compat:
		# the browser: no character shadows, and distant townsfolk animate ten times a second
		model.set_shadows(false)
		_anim_far = d > 12.0
		model.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if _anim_far else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		return
	model.set_shadows(d < 45.0)
	model.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE


# ------------------------------------------------------------------ decisions
func _decide() -> void:
	if talking or dead:
		return
	if fleeing:
		if Game.player_ref and Game.player_ref.global_position.distance_to(global_position) > 30.0:
			fleeing = false
		return
	# hostiles & defenders look for targets
	if data.hostile or data.role in ["knight", "guard"]:
		target = manager.find_target(self)
		if target:
			return
	if data.role in ["knight", "guard"]:
		var was := pursuing
		pursuing = manager.should_arrest(self)
		if pursuing:
			return
		if was:
			data.arresting = false
			activity = ""          # back to the patrol / routine
	var act: Dictionary = manager.activity_for(data)
	var key := "%s|%s" % [act.type, act.get("key", "")]
	if key != activity:
		activity = key
		_go(act)
	# greet the player now and then
	var pl: Node3D = Game.player_ref
	if pl and _greet_cd <= 0.0 and path_i >= path.size() and not data.hostile:
		var d := pl.global_position.distance_to(global_position)
		if d < 4.5 and randf() < 0.35:
			_greet_cd = 40.0 + randf() * 40.0
			var line := Dialogue.bark(data)
			if line != "" and Game.world_ref and Game.world_ref.hud:
				Game.world_ref.hud.call("show_subtitle", data.name, line, 3.5)
				Audio.voice(data.gender, global_position)


func _go(act: Dictionary) -> void:
	arrive_anim = act.get("anim", "Idle")
	arrive_yaw = float(act.get("yaw", _yaw))
	arrive_pos = act.get("pos", global_position)
	speed = float(act.get("speed", 1.35))
	path = manager.path_to(data, global_position, act)
	path_i = 0
	_stuck_t = 0.0


func _follow_path(delta: float) -> void:
	if path_i >= path.size():
		# arrived: settle into the activity
		if arrive_anim == "Sleep":
			model.freeze_end("Death01")
			global_position = arrive_pos
			model.rotation.y = arrive_yaw + PI * 0.5
			model.position = Vector3(0, 0.05, 0)
		else:
			model.position = Vector3.ZERO
			if arrive_anim in ["Sitting_Idle", "Sitting_Talking"]:
				global_position = global_position.lerp(arrive_pos, 1.0 - exp(-delta * 6.0))
			_yaw = lerp_angle(_yaw, arrive_yaw, 1.0 - exp(-delta * 5.0))
			model.rotation.y = _yaw
			model.play(arrive_anim)
		return
	var tgt := path[path_i]
	var pos := global_position
	var to := Vector3(tgt.x - pos.x, 0, tgt.z - pos.z)
	var dist := to.length()
	var step := speed * delta
	if dist <= step + 0.05:
		global_position = Vector3(tgt.x, tgt.y, tgt.z)
		path_i += 1
		manager.notify_door(self, tgt)
		return
	var dir := to / dist
	var np := pos + dir * step
	var seg_from := path[path_i - 1] if path_i > 0 else pos
	var total := Vector2(tgt.x - seg_from.x, tgt.z - seg_from.z).length()
	var t := 1.0 - (dist - step) / maxf(total, 0.001)
	var ly := lerpf(seg_from.y, tgt.y, clampf(t, 0.0, 1.0))
	np.y = maxf(ly, WorldData.height_at(np.x, np.z))
	var bh: float = manager.bridge_height(np)
	if bh > np.y - 1.5 and bh < np.y + 3.0:
		np.y = maxf(np.y, bh)
	global_position = np
	_yaw = lerp_angle(_yaw, atan2(dir.x, dir.z), 1.0 - exp(-delta * 8.0))
	model.rotation.y = _yaw
	model.position = Vector3.ZERO
	var walk := "Walk_Formal" if data.role in ["duke", "official"] else "Walk"
	if speed > 2.6:
		model.play("Jog_Fwd", 0.2, speed / 3.1)
	else:
		model.play(walk, 0.2, speed / 1.35)


# ------------------------------------------------------------------ combat
func _combat(delta: float) -> void:
	var tp := target.global_position
	var to := tp - global_position
	to.y = 0.0
	var d := to.length()
	if d > 40.0 or (target.has_method("is_dead") and target.call("is_dead")):
		target = null
		return
	_swinging = maxf(_swinging - delta, 0.0)
	blocking = maxf(blocking - delta, 0.0)
	model.position = Vector3.ZERO
	if _stagger > 0.0:          # reeling: slide back with the blow
		_stagger -= delta
		_slide(delta)
		return
	_yaw = lerp_angle(_yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 10.0))
	model.rotation.y = _yaw
	if blocking > 0.0:
		model.play("Spell_Simple_Idle", 0.08)     # shield arm thrust out
		return
	if _recover > 0.0:          # give ground after a blow
		_recover -= delta
		if d < 2.6:
			_step(-to / maxf(d, 0.01), 1.2, delta)
			model.play("Walk", 0.2, -1.0)
		return
	if d > 1.8 or manager.line_blocked(data, global_position, tp):
		_chase_step(tp, 3.4 if d > 3.0 else 1.7, delta)
		model.play("Jog_Fwd" if d > 3.0 else "Walk", 0.15, 1.1 if d > 3.0 else 1.0)
	elif _attack_cd <= 0.0 and manager.attackers_on(target) < 2:
		_begin_swing()
	elif _swinging <= 0.0:
		if d < 1.15:
			_step(-to / maxf(d, 0.01), 1.0, delta)
			model.play("Walk", 0.2, -1.0)
		elif model.current != "Sword_Attack" or not model.anim.is_playing():
			model.play("Sword_Idle", 0.2)


## Winds up a cut: the swing whooshes as it comes, then lands after 0.45 s unless the NPC is
## staggered first. Only two foes swing at the player at once; the rest wait their turn.
func _begin_swing() -> void:
	_attack_cd = 1.3 + randf() * 0.8
	_swing += 1
	var id := _swing
	_swinging = 0.8
	model.play_once("Sword_Attack")
	get_tree().create_timer(0.24).timeout.connect(func():
		if id == _swing and not dead:
			Audio.play_at("swing", global_position + Vector3.UP * 1.2, -3.0))
	get_tree().create_timer(0.45).timeout.connect(func():
		if id != _swing or dead or not is_instance_valid(target):
			return
		if global_position.distance_to(target.global_position) < 2.4 and not manager.line_blocked(data, global_position, target.global_position):
			target.call("take_damage", randf_range(8.0, 15.0) * (1.4 if data.role == "knight" else 1.0), self, false)
		_recover = randf_range(0.3, 0.7))


## The player turned this blow aside with a well-timed shield: off balance, open to a riposte.
func parried(by: Node3D) -> void:
	_swing += 1
	_swinging = 0.0
	_stagger = 1.3
	_attack_cd = maxf(_attack_cd, 1.5)
	var away := global_position - by.global_position
	away.y = 0.0
	_knock = away.normalized() * 2.0
	model.play_once("Hit_Head")


## The player is swinging: a shield-bearer facing them may raise it in time.
func consider_block(by: Node3D, power: bool) -> void:
	if dead or _stagger > 0.0 or _swinging > 0.5 or not bool(data.look.get("shield", false)):
		return
	var to := by.global_position - global_position
	to.y = 0.0
	if to.length() > 3.2 or to.normalized().dot(Vector3(sin(_yaw), 0, cos(_yaw))) < 0.5:
		return
	var chance: float = {"knight": 0.5, "guard": 0.35}.get(data.role, 0.25)
	if randf() < chance * (0.6 if power else 1.0):
		blocking = 0.65
		_swing += 1          # a raised shield means no swing this moment
		_swinging = 0.0


func _step(dir: Vector3, spd: float, delta: float) -> void:
	var np := global_position + dir * spd * delta
	if manager.line_blocked(data, global_position, np + dir * 0.4):
		return
	var ground := WorldData.height_at(np.x, np.z)
	var bh: float = manager.bridge_height(np)
	if bh > ground - 1.5:
		ground = maxf(ground, bh)
	var dy := ground - global_position.y
	if dy > 0.5 or dy < -0.6:
		return          # a wall, a drop or the edge of an upper floor
	np.y = ground if dy > -0.15 else global_position.y
	global_position = np


func _slide(delta: float) -> void:
	if _knock.length() < 0.05:
		return
	_step(_knock.normalized(), _knock.length(), delta)
	_knock = _knock.lerp(Vector3.ZERO, 1.0 - exp(-delta * 5.0))


## One step of a chase: straight at the goal when the way is clear, otherwise along the
## settlement's paths and through its doorways - never through a wall.
func _chase_step(goal: Vector3, spd: float, delta: float) -> void:
	_route_t -= delta
	if _route_t <= 0.0:
		_route_t = 0.6
		if manager.line_blocked(data, global_position, goal):
			_route = manager.route_to(data, global_position, goal)
			_route_i = 0
		else:
			_route = PackedVector3Array()
	var tgt := goal
	while _route_i < _route.size():
		tgt = _route[_route_i]
		if Vector2(tgt.x - global_position.x, tgt.z - global_position.z).length() > 0.5:
			break
		manager.notify_door(self, tgt)
		_route_i += 1
		tgt = goal
	var to := tgt - global_position
	to.y = 0.0
	var dl := to.length()
	if dl < 0.01:
		return
	var step := minf(spd * delta, dl)
	var np := global_position + to / dl * step
	var ground := WorldData.height_at(np.x, np.z)
	var bh: float = manager.bridge_height(np)
	if bh > ground - 1.5:
		ground = maxf(ground, bh)
	# follow floors and stairs towards the goal's height, never sinking below the ground
	np.y = maxf(ground, lerpf(global_position.y, tgt.y, clampf(step / dl, 0.0, 1.0)))
	global_position = np
	_yaw = lerp_angle(_yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 10.0))
	model.rotation.y = _yaw


## Closes in on a wanted player to arrest them; no blows unless they resist.
func _pursue(delta: float) -> void:
	var pl: Node3D = Game.player_ref
	if pl == null or pl.get("dead"):
		pursuing = false
		return
	var to := pl.global_position - global_position
	to.y = 0.0
	var d := to.length()
	_yaw = lerp_angle(_yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 8.0))
	model.rotation.y = _yaw
	model.position = Vector3.ZERO
	_confront_cd = maxf(_confront_cd - delta, 0.0)
	if d > 2.4 or manager.line_blocked(data, global_position, pl.global_position):
		_chase_step(pl.global_position, 3.4 if d > 8.0 else 1.8, delta)
		model.play("Jog_Fwd" if d > 8.0 else "Walk", 0.2)
	else:
		model.play("Idle", 0.25)
		if _confront_cd <= 0.0:
			_confront_cd = 8.0
			manager.confront(self)


## Returns false if a raised shield turned the blow aside.
func take_damage(amount: float, source: Node, _fall := false, knock := 0.0) -> bool:
	if dead:
		return true
	var from := (source as Node3D).global_position if source is Node3D else global_position - Vector3(sin(_yaw), 0, cos(_yaw))
	var to := from - global_position
	to.y = 0.0
	var front := to.length() > 0.01 and to.normalized().dot(Vector3(sin(_yaw), 0, cos(_yaw))) > 0.35
	if blocking > 0.0 and front:
		if knock < 3.0:
			data.health -= amount * 0.08
			_attack_cd = minf(_attack_cd, 0.35)      # and answers quickly
			if source == Game.player_ref:
				manager.player_attacked(self)
			return false
		blocking = 0.0           # a heavy blow smashes the guard aside
		amount *= 0.5
		knock *= 1.3
	if _stagger > 0.0:
		amount *= 1.35           # caught off balance
	data.health -= amount
	var away := -to.normalized() if to.length() > 0.01 else Vector3.ZERO
	# a blow interrupts a swing that's still winding up (a heavy one always does)
	var interrupt := knock >= 3.0 or _swinging <= 0.0 or (_swinging > 0.35 and randf() < 0.5)
	if data.health > 0.0 and amount > 1.0:
		Audio.play_at("grunt_f" if data.gender == "f" else "grunt_m", global_position + Vector3.UP * 1.5, -2.0, randf_range(0.92, 1.08))
	if interrupt and data.health > 0.0:
		_swing += 1
		_swinging = 0.0
		_stagger = 0.3 + knock * 0.12
		_knock = away * knock
		model.play_once("Hit_Head" if randf() < 0.35 else "Hit_Chest")
	if source == Game.player_ref:
		manager.player_attacked(self)
		if data.hostile or (data.role in ["knight", "guard"] and Game.is_resisting(data.sname)):
			target = source
		elif data.role not in ["knight", "guard"]:
			fleeing = true
			_flee_from(source)
	if data.health <= 0.0:
		_die(source, away * (2.0 + knock))
	return true


func _flee_from(src: Node) -> void:
	if src == null:
		return
	var away: Vector3 = (global_position - (src as Node3D).global_position)
	away.y = 0.0
	away = away.normalized() * 25.0
	path = PackedVector3Array([global_position + away])
	path_i = 0
	speed = 4.2
	arrive_anim = "Idle"


func _die(source: Node, push := Vector3.ZERO) -> void:
	dead = true
	Audio.play_at("death_f" if data.gender == "f" else "death_m", global_position + Vector3.UP * 1.4, 0.0, randf_range(0.95, 1.05))
	collision_layer = 32       # still searchable, no longer in the way
	Game.dead_npcs[str(data.id)] = true
	data.alive = false
	manager.npc_died(self, source)
	# the body goes limp and falls where the blow sends it; the pose is kept once it settles
	if model.ragdoll(push + Vector3.UP * 0.5):
		get_tree().create_timer(4.5).timeout.connect(func():
			if is_instance_valid(model):
				var at := model.settle_ragdoll()
				var cs := get_child(0) as CollisionShape3D
				if cs and at != Vector3.INF:
					var sph := SphereShape3D.new()
					sph.radius = 0.55
					cs.shape = sph
					cs.global_position = at + Vector3.UP * 0.2)
	else:
		model.play_once("Death01", 0.05)
		get_tree().create_timer(float(model.anim.current_animation_length) - 0.05 if model.anim.current_animation_length > 0 else 1.5).timeout.connect(func():
			if is_instance_valid(model):
				model.freeze_end("Death01"))


func is_dead() -> bool:
	return dead


# ------------------------------------------------------------------ interaction
func get_interaction(_p) -> String:
	if dead:
		return "[E] Search the body" if not data.looted else ""
	if data.hostile:
		return ""
	match data.role:
		"guard":
			return "%s (on duty - will not speak)" % data.name if not mount else ""
		"servant":
			if Game.holding_coin and Game.gold() > 0:
				return "[E] Offer a gold coin to %s" % data.name
			return ""
		"cook":
			return "[E] Talk to %s the Cook" % data.name
	return "[E] Talk to %s%s" % [data.name, (" the " + NPCManager.role_title(data)) if data.role != "villager" else ""]


func interact(_p) -> void:
	if dead:
		if not data.looted:
			data.looted = true
			var sv := randi_range(2, 30) * (3 if data.hostile else 1)
			Game.earn(sv)
			Game.notify.emit("You find %s on the body." % Items.price_text(sv), "item")
			if data.role in ["knight", "guard"] or data.hostile:
				Game.add_item("iron_sword" if randf() < 0.4 else "bandage")
		return
	if data.role == "cook":
		face(Game.player_ref)
		model.play_once("Interact")
		Game.world_ref.hud.call("show_subtitle", data.name, "Bon Appetite!", 2.5)
		Audio.voice(data.gender, global_position)
		return
	if data.role == "servant" and not (Game.holding_coin and Game.gold() > 0):
		return
	face(Game.player_ref)
	manager.open_dialogue(self)


func face(n: Node3D) -> void:
	if n == null:
		return
	var to := n.global_position - global_position
	_yaw = atan2(to.x, to.z)
	model.rotation.y = _yaw


func begin_talk() -> void:
	talking = true
	path = PackedVector3Array()
	path_i = 0
	model.position = Vector3.ZERO
	model.play("Idle_Talking", 0.2)


func end_talk() -> void:
	talking = false
	activity = ""
