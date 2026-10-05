extends CanvasLayer
## Performance overlay (page?perf or --perf-overlay): frame rate, frame times and draw calls, and
## every hitch (a frame over 120 ms) with the jobs that ran in it (Game.mark), so a freeze can be
## traced to its cause. With ?tour (--tour) the player is walked along a set route through
## Kingsbridge and into the forest, from noon into the night, and a summary is printed at the end.

const HITCH_MS := 120.0
const ROUTE := [[-318, 330], [-378, 262], [-430, 236], [-470, 200], [-640, 180], [-900, 120], [-1050, -60], [-1078, -150], [-980, -250], [-720, -120], [-470, 120], [-378, 262]]
const SPEED := 9.0

var _label: Label
var _last := 0
var _times: Array[float] = []
var _hitches: Array = []
var _start := 0
var _tour_i := 0
var _tour_pos := Vector3.ZERO
var _tour_done := false
var _seg_ms := 0.0
var _seg_frames := 0
var _summary: Array = []


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.7))
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.position = Vector2(16, 190)
	add_child(_label)
	_last = Time.get_ticks_usec()
	_start = _last
	# (the GPU timing queries can themselves stall some drivers: only with ?perfgpu / --perfgpu)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), Game.debug_flag("perfgpu"))


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := float(now - _last) / 1000.0
	_last = now
	_times.append(ms)
	if _times.size() > 240:
		_times.pop_front()
	if ms > HITCH_MS:
		var tags := (", ".join(Game.frame_marks) + ", end (+%d ms)" % ((now - Game.mark_t) / 1000)) if not Game.frame_marks.is_empty() else "nothing marked"
		# where the time went: drawing (a shader compiling) or the game's own code
		var vr := get_viewport().get_viewport_rid()
		var draw := RenderingServer.viewport_get_measured_render_time_cpu(vr) + RenderingServer.get_frame_setup_time_cpu()
		tags += "  [drawing %d ms, the rest %d ms]" % [int(draw), int(maxf(ms - draw, 0.0))]
		_hitches.push_front("%5.1fs  %4d ms  %s" % [float(now - _start) / 1e6, int(ms), tags])
		if _hitches.size() > 9:
			_hitches.pop_back()
		print("HITCH %d ms at %.1fs: %s" % [int(ms), float(now - _start) / 1e6, tags])
	Game.frame_marks.clear()
	Game.mark_t = Time.get_ticks_usec()
	if Game.tour and Game.world_ref and Game.world_ref.ready_to_play and not _tour_done:
		_walk(delta, ms)
	_show()


func _show() -> void:
	var avg := 0.0
	var worst := 0.0
	for t in _times:
		avg += t
		worst = maxf(worst, t)
	avg /= maxf(_times.size(), 1)
	var w = Game.world_ref
	var npcs: int = w.npcs.active.size() if w and w.npcs else 0
	var beasts: int = w.wildlife.animals.size() if w and w.wildlife else 0
	var lines := ["%d fps   %.1f ms avg   worst %.0f ms (last 4 s)" % [int(1000.0 / maxf(avg, 0.1)), avg, worst],
		"draws %d   objects %d   townsfolk %d   animals %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), npcs, beasts]]
	if Game.tour:
		lines.append("tour: %s" % ("done" if _tour_done else "leg %d of %d" % [_tour_i + 1, ROUTE.size() - 1]))
		lines.append_array(_summary)
	lines.append("hitches (over %d ms):" % int(HITCH_MS))
	lines.append_array(_hitches)
	_label.text = "\n".join(lines)


## Walks the route at a steady pace (no physics), looking where it goes; night falls halfway.
func _walk(delta: float, ms: float) -> void:
	var pl: Player = Game.player_ref
	if _tour_i == 0 and _tour_pos == Vector3.ZERO:
		_tour_pos = Vector3(ROUTE[0][0], 0, ROUTE[0][1])
		pl.set_physics_process(false)
		Game.minutes = float(Game.day()) * 1440.0 + 11.0 * 60.0
	if _tour_i >= ROUTE.size() - 1:
		_tour_done = true
		pl.set_physics_process(true)
		print("TOUR DONE ", " | ".join(_summary))
		return
	var to := Vector3(ROUTE[_tour_i + 1][0], 0, ROUTE[_tour_i + 1][1])
	var d := Vector2(to.x - _tour_pos.x, to.z - _tour_pos.z)
	var step := minf(SPEED * delta, d.length())
	if d.length() > 0.01:
		_tour_pos += Vector3(d.x, 0, d.y).normalized() * step
	_tour_pos.y = WorldData.height_at(_tour_pos.x, _tour_pos.z)
	pl.global_position = _tour_pos
	pl.set_look(atan2(-d.x, -d.y), -0.08)
	_seg_ms += ms
	_seg_frames += 1
	if d.length() < 0.5:
		_summary.append("leg %d: %.0f fps" % [_tour_i + 1, 1000.0 * _seg_frames / maxf(_seg_ms, 1.0)])
		print("TOUR leg %d: %.1f fps avg over %d frames" % [_tour_i + 1, 1000.0 * _seg_frames / maxf(_seg_ms, 1.0), _seg_frames])
		_seg_ms = 0.0
		_seg_frames = 0
		_tour_i += 1
		if _tour_i == ROUTE.size() / 2:
			Game.minutes = float(Game.day()) * 1440.0 + 21.5 * 60.0     # into the night: lamps and fires
