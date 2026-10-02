extends Node
## Performance probe (run with: -- --perf). Measures frame time in typical scenes.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()

func _run() -> void:
	var w: Node3D = get_parent()
	var pl: Player = w.player
	pl.set_physics_process(false)
	var scenes := []
	var kb: Dictionary = WorldData.settlement_by_name("Kingsbridge")
	var rv: Dictionary = WorldData.settlement_by_name("Castle Ravenmoor")
	scenes.append(["town square", Vector3(kb.x + 10, 0, kb.z + 14), 40.0])
	scenes.append(["forest", Vector3(-1800, 0, 500), 20.0])
	scenes.append(["plains vista", Vector3(200, 0, 900), 200.0])
	scenes.append(["castle", Vector3(rv.x + 20, 0, rv.z + 20), 200.0])
	scenes.append(["lake shore", Vector3(1900, 0, -220), 75.0])
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	Game.minutes = 1440.0 + 11 * 60.0
	Game.paused_time = true
	if "--forest-only" in OS.get_cmdline_user_args():
		scenes = [scenes[1], scenes[0]]
	for s in scenes:
		var p: Vector3 = s[1]
		p.y = WorldData.height_at(p.x, p.z)
		pl.global_position = p
		pl.set_look(deg_to_rad(s[2]), -0.05)
		for i in 90:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		var frames := 0
		while Time.get_ticks_usec() - t0 < 3000000:
			await get_tree().process_frame
			frames += 1
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / frames
		var vrid := get_viewport().get_viewport_rid()
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vrid)
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vrid) + RenderingServer.get_frame_setup_time_cpu()
		var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		print("     gpu=%.1fms render_cpu=%.1fms process=%.1fms physics=%.1fms" % [gpu, cpu, proc, phys])
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prim := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var obj := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		print("PERF %-14s %.2f ms (%.0f fps)  draws=%d  prims=%.1fM  objects=%d  npcs=%d  res=%s scale=%.2f" % [s[0], ms, 1000.0 / ms, dc, prim / 1e6, obj, w.npcs.active.size(), get_viewport().get_visible_rect().size, get_viewport().scaling_3d_scale])
		if "--paused" in OS.get_cmdline_user_args():
			# same view with all game logic paused: the difference is script/physics time
			get_tree().paused = true
			for i in 30:
				await get_tree().process_frame
			t0 = Time.get_ticks_usec()
			frames = 0
			while Time.get_ticks_usec() - t0 < 2000000:
				await get_tree().process_frame
				frames += 1
			print("PERF %-14s paused: %.2f ms" % [s[0], float(Time.get_ticks_usec() - t0) / 1000.0 / frames])
			get_tree().paused = false
	get_tree().quit()
