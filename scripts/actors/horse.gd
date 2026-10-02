extends CharacterBody3D
## Rideable horse. For sale at stables (idle in its stall), or owned: grazes, comes when
## whistled for, and carries the player. Riding has weight: the horse gathers speed through a
## walk, trot and canter to the gallop and takes time to pull up; it turns wider the faster it
## goes, slows on climbs and refuses cliffs, leans into turns and pitches with the ground, tires
## at the gallop, and stops short (rearing) if it runs into something. The rider rocks with
## the stride and hears every hoof-fall in time with the legs.

const WALK := 1.7
const TROT := 3.6
const CANTER := 7.2

var spec: Dictionary
var owned := false
var model: Node3D
var ap: AnimationPlayer
var rider: Node3D = null
var speed := 0.0
var max_speed := 14.0
var stamina := 100.0
var _yaw := 0.0
var _turn := 0.0             # eased turn rate (rad/s)
var _lean := 0.0             # roll into turns
var _pitch := 0.0            # nose up or down with the slope
var _come := Vector3.INF
var _anim := ""
var _idle_t := 0.0
var _vy := 0.0
var _jump_t := 0.0
var _air_vy := 0.0
var _land := 0.0             # landing jolt felt by the rider
var _halt := 0.0             # pulled up short (crash or refusal)
var _beat := -1
var _snort_t := 10.0
var _tired := false


func setup(s: Dictionary, is_owned: bool) -> void:
	spec = s
	owned = is_owned
	max_speed = float(s.get("speed", 14.0))
	collision_layer = 16
	collision_mask = 1
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.6
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.75, 1.3, 2.1)
	cs.shape = box
	cs.position = Vector3(0, 1.0, 0)
	add_child(cs)
	model = Assets.instance_sized("res://assets/animals/%s.glb" % ("Horse_White" if s.get("white", false) else "Horse"), 2.35, "xz")
	add_child(model)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		ap = aps[0]
	_play("Idle")


func _play(n: String, scale := 1.0, blend := 0.25) -> void:
	if ap == null:
		return
	ap.speed_scale = scale
	if _anim != n:
		_anim = n
		if ap.has_animation(n):
			ap.play(n, blend)


func speed_label() -> String:
	if max_speed > 17.0: return "swift"
	if max_speed > 14.0: return "quick"
	if max_speed > 12.5: return "steady"
	return "plodding"


func get_interaction(_p) -> String:
	if not owned:
		return "A %s %s horse - %d gold. Speak to the stablemaster." % [speed_label(), "white" if spec.get("white", false) else "bay", int(spec.get("price", 40))]
	if rider:
		return ""
	return "[E] Ride your horse"


func interact(p) -> void:
	if owned and rider == null:
		set_rider(p)
		p.call("mount", self)


func set_rider(p: Node3D) -> void:
	rider = p
	speed = 0.0
	_come = Vector3.INF


## Where the rider sits: on the saddle, tipped with the horse's pitch and lean.
func seat_transform() -> Transform3D:
	var tilt := Basis(Vector3.UP, _yaw) * Basis.from_euler(Vector3(_pitch, 0, _lean))
	return Transform3D(tilt, global_position) * Transform3D(Basis(), Vector3(0, 2.28, -0.12))


func come_to(p: Vector3) -> void:
	if rider == null:
		_come = p
		Audio.play_at("neigh", global_position, -2.0)


## W canters, Shift gallops (while the horse has wind), Ctrl keeps to a walk, S reins in and
## then backs up. The horse steers toward where the rider looks (unless looking well behind)
## and with A / D, turning on the spot when standing.
func rider_input(input: Vector2, sprint: bool, jump: bool, cam_yaw: float, delta: float) -> void:
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	var target := 0.0
	if _halt > 0.0:
		target = 0.0
	elif input.y < -0.1:
		if sprint and not _tired:
			target = max_speed
		elif Input.is_action_pressed("crouch"):
			target = WALK
		else:
			target = CANTER * clampf(max_speed / 14.0, 0.85, 1.15)
	elif input.y > 0.1:
		target = -1.4 if speed < 0.4 else 0.0
	# the lie of the land: climbs slow the horse, the steepest it will not take
	var grade := _grade(fwd * (1.0 if speed >= -0.1 else -1.0))
	if grade > 0.0:
		target *= clampf(1.0 - grade * 1.5, 0.25, 1.0)
	else:
		target *= 1.0 + minf(-grade, 0.3) * 0.5
	if (grade > 0.85 or grade < -1.1) and speed > 1.0 and _halt <= 0.0:
		_refuse()
		target = 0.0
	var accel := 2.4
	if target > speed:
		accel = 2.6 if speed > CANTER else 3.6        # the gallop takes a few strides to build
	elif input.y > 0.1:
		accel = 6.5                                   # reined in hard
	elif _halt > 0.0:
		accel = 14.0
	speed = move_toward(speed, target, delta * accel)
	# wind: the gallop tires a horse (more so uphill); easy gaits let it recover
	if speed > CANTER + 0.5:
		stamina = maxf(stamina - delta * 8.0 * (1.0 + maxf(grade, 0.0) * 2.0), 0.0)
	else:
		stamina = minf(stamina + delta * (9.0 if speed < TROT else 4.5), 100.0)
	if stamina <= 0.0 and not _tired:
		_tired = true
		Audio.play_at("snort", global_position, 3.0)
		Game.notify.emit("Your horse is blown. Ease off to a canter or walk and it will get its wind back.", "warn")
	elif _tired and stamina > 35.0:
		_tired = false
	# steering
	var k := clampf(absf(speed) / max_speed, 0.0, 1.0)
	var max_turn := lerpf(1.9, 0.75, k)
	var want := 0.0
	var diff := angle_difference(_yaw, cam_yaw + PI)
	if absf(diff) < 1.8 and absf(speed) > 0.4:
		want = clampf(diff * 2.2, -1.0, 1.0) * max_turn
	want = clampf(want - input.x * max_turn, -max_turn, max_turn)
	if absf(speed) < 0.4:
		want = -input.x * 1.3       # pivot on the spot
	_turn = lerpf(_turn, want, 1.0 - exp(-delta * 5.0))
	_yaw += _turn * delta
	if jump and is_on_floor() and _jump_t <= 0.0 and speed > TROT:
		_vy = 4.3 + speed * 0.09
		_jump_t = 0.9
		if ap and ap.has_animation("Gallop_Jump"):
			ap.play("Gallop_Jump", 0.1)
		_anim = "Gallop_Jump"


func _grade(dir: Vector3) -> float:
	var p := global_position
	return (WorldData.height_at(p.x + dir.x * 2.5, p.z + dir.z * 2.5) - WorldData.height_at(p.x, p.z)) / 2.5


func _refuse() -> void:
	_halt = 1.1
	speed = minf(speed, 2.0)
	_play("Idle_HitReact_Left" if randf() < 0.5 else "Idle_HitReact_Right", 1.0, 0.1)
	Audio.play_at("neigh", global_position, 1.0)
	if rider:
		rider.call("horse_jolt", 3.0)


func _crash(spd: float) -> void:
	_halt = 1.4
	speed = 0.0
	_play("Idle_HitReact_Left" if randf() < 0.5 else "Idle_HitReact_Right", 1.0, 0.08)
	Audio.play_at("neigh", global_position, 3.0)
	Audio.play_at("hit_heavy", global_position + Vector3.UP, -4.0)
	if rider:
		rider.call("horse_jolt", spd)


func _physics_process(delta: float) -> void:
	_jump_t = maxf(_jump_t - delta, 0.0)
	_halt = maxf(_halt - delta, 0.0)
	_land = lerpf(_land, 0.0, 1.0 - exp(-delta * 6.0))
	if not owned:
		_idle_t += delta
		if _idle_t > 8.0:
			_idle_t = 0.0
			_play("Eating" if randf() < 0.5 else "Idle")
		return
	if rider == null:
		if _come != Vector3.INF:
			var to := _come - global_position
			to.y = 0.0
			var d := to.length()
			if d < 3.0:
				_come = Vector3.INF
			else:
				var want := atan2(to.x, to.z)
				_yaw = lerp_angle(_yaw, want, 1.0 - exp(-delta * 3.0))
				speed = move_toward(speed, minf(max_speed * 0.8, d * 0.8), delta * 3.0)
		if _come == Vector3.INF:
			speed = move_toward(speed, 0.0, delta * 4.0)
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	var wd := WorldData.water_depth_at(global_position.x, global_position.z)
	# wading: the deeper the water, the slower the going
	var spd := speed * clampf(1.0 - maxf(wd - 0.3, 0.0) * 0.55, 0.3, 1.0)
	velocity.x = fwd.x * spd
	velocity.z = fwd.z * spd
	var was_air := not is_on_floor()
	if is_on_floor() and _vy <= 0.0:
		_vy = -1.0
	else:
		_vy -= 18.0 * delta
		_air_vy = minf(_air_vy, _vy)
	velocity.y = _vy
	if wd > 1.3:
		var wl := WorldData.water_level_at(global_position.x, global_position.z)
		velocity.y = clampf((wl - 1.3 - global_position.y) * 3.0, -2.0, 2.0)
	if rider == null and (Game.player_ref == null or global_position.distance_to(Game.player_ref.global_position) > 120.0):
		# far from the player there is no terrain collision: follow the heightmap
		global_position += velocity * Vector3(1, 0, 1) * delta
		global_position.y = WorldData.height_at(global_position.x, global_position.z)
	else:
		move_and_slide()
		var g := WorldData.height_at(global_position.x, global_position.z)
		if global_position.y < g - 1.0:
			global_position.y = g + 0.1
		if was_air and is_on_floor() and _air_vy < -3.0:
			_land = clampf(-_air_vy * 0.018, 0.04, 0.16)
			Audio.play_at(_hoof_sound(), global_position, 0.0)
			_air_vy = 0.0
		# ran into a wall, a tree or a rock at speed: pull up short
		if rider and is_on_wall() and speed > 6.5:
			var n := get_wall_normal()
			if n.dot(-fwd) > 0.55 and absf(n.y) < 0.5:
				_crash(speed)
	rotation.y = _yaw
	_settle(delta)
	_animate()
	if rider == null and speed > 0.5 and Game.player_ref and global_position.distance_to(Game.player_ref.global_position) < 60.0:
		rider_motion()       # hoof-falls as it comes when called
	if rider:
		_snort_t -= delta
		if _snort_t <= 0.0:
			_snort_t = randf_range(9.0, 22.0) if not _tired else randf_range(2.5, 4.0)
			Audio.play_at("snort", global_position + fwd * 1.2 + Vector3.UP * 1.6, -6.0 if not _tired else 0.0)
	if owned and rider == null and Engine.get_physics_frames() % 120 == 0:
		spec["x"] = global_position.x
		spec["z"] = global_position.z


## Pitch with the ground underfoot and lean into turns (more at speed).
func _settle(delta: float) -> void:
	var n := WorldData.normal_at(global_position.x, global_position.z)
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	var pitch_t := clampf(n.dot(fwd), -0.3, 0.3) if is_on_floor() else _pitch
	var lean_t := clampf(-_turn * absf(speed) * 0.014, -0.16, 0.16)
	_pitch = lerpf(_pitch, pitch_t, 1.0 - exp(-delta * 6.0))
	_lean = lerpf(_lean, lean_t, 1.0 - exp(-delta * 4.0))
	model.rotation.x = _pitch
	model.rotation.z = _lean


func _animate() -> void:
	if _anim == "Gallop_Jump" and _jump_t > 0.0:
		return
	if _halt > 0.6 and _anim.begins_with("Idle_HitReact"):
		return
	var s := absf(speed)
	if s < 0.25:
		_play("Idle")
	elif s < 4.6:
		_play("Walk", clampf(s / WALK, 0.6, 2.3))        # walk, quickening to a trot
	else:
		_play("Gallop", clampf(s / 12.0, 0.6, 1.45))       # canter, opening out to a full gallop


func _gait_phase() -> float:
	if ap == null or ap.current_animation == "" or ap.current_animation_length <= 0.0:
		return 0.0
	return fposmod(ap.current_animation_position / ap.current_animation_length, 1.0)


func _hoof_sound() -> String:
	var p := global_position
	if WorldData.water_depth_at(p.x, p.z) > 0.05:
		return "step_water"
	if not WorldData.nearest_settlement(p, 90.0).is_empty() or WorldData.biome_at(p.x, p.z) == WorldData.Biome.MOUNTAIN:
		return "hoof_hard"        # cobbles, packed streets and bare rock ring under iron shoes
	return "hoof_soft"


## The rider's motion: bob, sway and pitch in time with the stride (read from the leg animation
## so it always matches what the legs are doing), plus the jolt of a landing.
func rider_motion() -> Dictionary:
	var ph := _gait_phase()
	var s := absf(speed)
	var bob := Vector3.ZERO
	var roll := _lean * 0.6
	var pitch := -_pitch * 0.5
	var beats: Array = []
	if _anim == "Walk" and s > 0.2:
		var trot := clampf((s - 2.4) / 2.0, 0.0, 1.0)
		var amp := lerpf(0.02, 0.05, trot)
		bob = Vector3(sin(ph * TAU) * lerpf(0.022, 0.01, trot), absf(sin(ph * TAU * 2.0)) * amp - amp * 0.5, 0)
		pitch += sin(ph * TAU * 2.0) * 0.006
		beats = [0.0, 0.25, 0.5, 0.75] if trot < 0.5 else [0.0, 0.5]
	elif _anim == "Gallop":
		var amp := lerpf(0.045, 0.08, clampf((s - CANTER) / maxf(max_speed - CANTER, 1.0), 0.0, 1.0))
		bob = Vector3(0, sin(ph * TAU) * amp, sin(ph * TAU + 1.2) * amp * 0.4)
		pitch += sin(ph * TAU + 0.6) * 0.028
		beats = [0.0, 0.08, 0.36, 0.44]
	bob.y -= _land
	# hoof-falls on the beats of the gait
	if not beats.is_empty() and is_on_floor():
		var b := 0
		for i in beats.size():
			if ph >= float(beats[i]):
				b = i
		if b != _beat:
			_beat = b
			Audio.play_at(_hoof_sound(), global_position + Vector3(0, 0.1, 0), -9.0 if s < 3.0 else (-5.0 if s < CANTER else -2.0), randf_range(0.92, 1.08))
	return {"bob": bob, "roll": roll, "pitch": pitch}
