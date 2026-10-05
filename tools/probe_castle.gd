extends Node
## Walks the player (real physics) from the road outside a castle, through the gate and the
## courtyard, up the keep's steps, into the hall and up to the dais; prints where it gets stuck.
##   godot --path . scenes/world.tscn -- --probe-castle[=Castle Name]
var pts: Array = []
var names: Array = []
var i := 0
var t := 0.0
var stuck_t := 0.0
var last := Vector3.ZERO
var castle := "Castle Ravenmoor"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-castle="):
			castle = a.substr(15)


func _physics_process(delta: float) -> void:
	var w = Game.world_ref
	if w == null or not w.ready_to_play:
		return
	var pl: Player = Game.player_ref
	if pts.is_empty():
		var s: Dictionary = WorldData.settlement_by_name(castle)
		var base := Transform3D(Basis(Vector3.UP, float(s.yaw)), Vector3(float(s.x), 0, float(s.z)))
		for e in [["road", 60.0], ["before the gate", 36.0], ["in the gateway", 29.5], ["courtyard", 18.0], ["keep steps", 8.0],
				["keep door", 3.2], ["hall entrance", 0.5], ["hall centre", -6.0], ["before the dais", -11.0]]:
			pts.append(base * Vector3(0, 0, float(e[1])))
			names.append(e[0])
		var p0: Vector3 = pts[0]
		p0.y = WorldData.height_at(p0.x, p0.z) + 0.6
		pl.global_position = p0
		pl.velocity = Vector3.ZERO
		print("PROBE %s: start at %s" % [castle, p0])
		return
	if i >= pts.size():
		print("PROBE DONE: walked from the road to the dais")
		get_tree().quit()
		return
	var tgt: Vector3 = pts[i]
	var d := Vector2(tgt.x - pl.global_position.x, tgt.z - pl.global_position.z)
	pl.set_look(atan2(-d.x, -d.y), 0.0)
	Input.action_press("move_forward")
	if d.length() < 1.3:
		print("PROBE reached %s at %s" % [names[i], pl.global_position])
		i += 1
		stuck_t = 0.0
	t += delta
	stuck_t = stuck_t + delta if pl.global_position.distance_to(last) < 0.03 else 0.0
	last = pl.global_position
	if stuck_t > 2.5:
		print("PROBE STUCK on the way to %s: at %s, %.1f m short (target %s)" % [names[i], pl.global_position, d.length(), tgt])
		var hit := ""
		for k in pl.get_slide_collision_count():
			var c := pl.get_slide_collision(k)
			hit += " %s(%s)" % [c.get_collider(), c.get_position()]
		print("PROBE blocked by:", hit)
		get_tree().quit()
	if t > 120.0:
		print("PROBE timeout")
		get_tree().quit()
